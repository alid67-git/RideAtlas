'use strict';

// RideAtlas web service worker - KDO-style versioned cache + update flow.
//
// APP_VERSION is the single number that retires every old cache: bumping it
// changes CACHE, `activate` below deletes all other rideatlas-* caches, and
// the byte-diff makes the browser install this file as a new (waiting) SW,
// which is what triggers the "Yeni sürüm hazır" banner (see app_update.js).
//
// Do not bump this by hand: .github/workflows/deploy-web.yml stamps it from
// lib/build_info.dart's kAppBuildLabel on every deploy, together with
// index.html's RIDEATLAS_WEB_VERSION and its ?v= cache busters, so all
// three always advance in lockstep with the app version.
const APP_VERSION = '1.4.80';
const CACHE = 'rideatlas-v' + APP_VERSION;

// Minimal app shell, precached at install. Everything else (main.dart.js,
// canvaskit, assets, icons) lands in the same cache on first fetch - the
// goal here is a consistent versioned snapshot, not full offline support.
// app_update.js is precached under the exact ?v= URL index.html loads it
// with - cache matches are exact-URL, so an unversioned entry would never
// be hit.
const CORE = [
  'index.html',
  'manifest.json',
  'favicon.png',
  'app_update.js?v=' + APP_VERSION,
];

self.addEventListener('install', (event) => {
  // No skipWaiting() here on purpose: the new SW stays waiting until the
  // rider taps Güncelle on the banner (SKIP_WAITING message below).
  event.waitUntil(
    caches
      .open(CACHE)
      .then((cache) =>
        cache.addAll(CORE.map((url) => new Request(url, { cache: 'reload' }))),
      ),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((names) =>
        Promise.all(
          names
            .filter((name) => name.startsWith('rideatlas-') && name !== CACHE)
            .map((name) => caches.delete(name)),
        ),
      )
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('message', (event) => {
  const data = event.data;
  // {type:'SKIP_WAITING'} is the KDO protocol; the bare 'skipWaiting'
  // string is Flutter's own convention - accept both so nothing breaks if
  // the PWA strategy ever changes.
  if (data === 'skipWaiting' || (data && data.type === 'SKIP_WAITING')) {
    self.skipWaiting();
  }
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  // Leave cross-origin traffic (map tiles, elevation APIs, fonts) to the
  // browser - caching third-party tiles here would balloon storage and
  // violate the tile servers' own cache policies.
  if (url.origin !== self.location.origin) return;

  // HTML: network-first, so a fresh deploy is picked up on the next
  // navigation; cache is only the offline/failure fallback.
  if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request)
        .then((response) => {
          const copy = response.clone();
          caches
            .open(CACHE)
            .then((cache) => cache.put(request, copy))
            .catch(() => {});
          return response;
        })
        .catch(() =>
          caches
            .match(request)
            .then((hit) => hit || caches.match('index.html')),
        ),
    );
    return;
  }

  // Everything else: cache-then-network within this version's cache. On a
  // miss, revalidate with the server ('no-cache' forces an ETag check)
  // instead of trusting the HTTP cache - GitHub Pages serves with
  // max-age=600, which could otherwise seed a brand-new versioned cache
  // with a stale main.dart.js right after an update.
  event.respondWith(
    caches.match(request).then((hit) => {
      if (hit) return hit;
      return fetch(new Request(request, { cache: 'no-cache' })).then(
        (response) => {
          if (response.ok && response.type === 'basic') {
            const copy = response.clone();
            caches
              .open(CACHE)
              .then((cache) => cache.put(request, copy))
              .catch(() => {});
          }
          return response;
        },
      );
    }),
  );
});
