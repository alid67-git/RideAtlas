// RideAtlas web update client (KDO-style).
//
// Registers sw.js, watches for a new (waiting) service worker, and shows
// the fixed bottom banner in index.html (#update-banner). Tapping Güncelle
// posts SKIP_WAITING to the waiting SW; the resulting controllerchange
// reloads the page exactly once, landing on the new version. A background
// reg.update() runs every 60s (and on tab re-focus) so long-lived tabs
// learn about deploys without a manual refresh.
(function () {
  'use strict';

  // Stamped by deploy-web.yml from lib/build_info.dart, same as sw.js's
  // APP_VERSION and index.html's ?v= busters.
  var VERSION = window.RIDEATLAS_WEB_VERSION || '0.0.0';
  var VERSION_KEY = 'rideatlas_web_version';
  var RELOADED_KEY = 'rideatlas_version_reloaded';
  var SW_UPDATED_KEY = 'rideatlas_sw_updated';

  var STRINGS = {
    tr: { text: 'Yeni sürüm hazır', button: 'Güncelle', dismiss: 'Kapat' },
    en: { text: 'A new version is ready', button: 'Update', dismiss: 'Dismiss' },
    de: { text: 'Neue Version verfügbar', button: 'Aktualisieren', dismiss: 'Schließen' },
  };

  function strings() {
    var lang = (navigator.language || 'tr').slice(0, 2).toLowerCase();
    return STRINGS[lang] || STRINGS.en;
  }

  // --- Version hard-reload safety -----------------------------------------
  // If the shell HTML we're running from belongs to a different release than
  // the one localStorage last saw, drop the outdated versioned caches and
  // replace the URL once with a cache-busting _r param - belt and braces for
  // the rare case where an old SW/HTTP cache combination keeps serving a
  // stale shell. sessionStorage guards against a reload loop.
  try {
    var stored = localStorage.getItem(VERSION_KEY);
    // A load right after the banner's own SKIP_WAITING/controllerchange
    // reload is already fresh - the SW just activated and wiped old
    // caches, so the hard reload below would only add a pointless second
    // refresh. The flag is set in the controllerchange handler.
    var swJustUpdated = sessionStorage.getItem(SW_UPDATED_KEY);
    if (swJustUpdated) sessionStorage.removeItem(SW_UPDATED_KEY);
    if (
      stored &&
      stored !== VERSION &&
      !swJustUpdated &&
      !sessionStorage.getItem(RELOADED_KEY)
    ) {
      sessionStorage.setItem(RELOADED_KEY, '1');
      localStorage.setItem(VERSION_KEY, VERSION);
      var currentCache = 'rideatlas-v' + VERSION;
      var wipe =
        'caches' in window
          ? caches.keys().then(function (names) {
              return Promise.all(
                names
                  .filter(function (n) {
                    return n.indexOf('rideatlas-') === 0 && n !== currentCache;
                  })
                  .map(function (n) { return caches.delete(n); })
              );
            })
          : Promise.resolve();
      wipe
        .catch(function () {})
        .then(function () {
          var url = new URL(window.location.href);
          url.searchParams.set('_r', String(Date.now()));
          window.location.replace(url.toString());
        });
      return;
    }
    localStorage.setItem(VERSION_KEY, VERSION);
    sessionStorage.removeItem(RELOADED_KEY);
  } catch (_) {
    // Storage blocked (private mode etc.) - the SW flow below still works.
  }

  if (!('serviceWorker' in navigator)) return;
  // Don't interfere with `flutter run` dev servers.
  var host = window.location.hostname;
  if (host === 'localhost' || host === '127.0.0.1') return;

  var banner = document.getElementById('update-banner');
  var bannerText = document.getElementById('update-banner-text');
  var updateButton = document.getElementById('update-btn');
  var dismissButton = document.getElementById('update-dismiss');
  if (!banner || !bannerText || !updateButton || !dismissButton) return;

  var localized = strings();
  bannerText.textContent = localized.text;
  updateButton.textContent = localized.button;
  dismissButton.setAttribute('aria-label', localized.dismiss);
  dismissButton.title = localized.dismiss;

  var waitingWorker = null;
  var reloading = false;
  // True once the rider tapped Güncelle - the only controllerchange that
  // should reload. The very first SW install also fires controllerchange
  // (clients.claim()), and reloading a first-time visitor would just flash
  // the page for nothing.
  var updateRequested = false;
  var hadController = Boolean(navigator.serviceWorker.controller);

  function showBanner(worker) {
    waitingWorker = worker;
    updateButton.disabled = false;
    banner.classList.add('show');
  }

  function hideBanner() {
    banner.classList.remove('show');
  }

  updateButton.addEventListener('click', function () {
    if (!waitingWorker) return;
    updateRequested = true;
    updateButton.disabled = true;
    waitingWorker.postMessage({ type: 'SKIP_WAITING' });
  });

  dismissButton.addEventListener('click', hideBanner);

  navigator.serviceWorker.addEventListener('controllerchange', function () {
    if (!updateRequested && !hadController) {
      // First install taking control - not an update.
      hadController = true;
      return;
    }
    if (reloading) return;
    reloading = true;
    try {
      // Tells the next load it's the post-update one, so the version
      // hard-reload safety doesn't stack a second refresh on top.
      sessionStorage.setItem(SW_UPDATED_KEY, '1');
    } catch (_) {}
    window.location.reload();
  });

  function watch(reg) {
    // A new SW might already be parked waiting (deploy happened while the
    // tab was closed) - only banner it when an old version is actually in
    // control, otherwise this is just the first install.
    if (reg.waiting && navigator.serviceWorker.controller) {
      showBanner(reg.waiting);
    }
    reg.addEventListener('updatefound', function () {
      var installing = reg.installing;
      if (!installing) return;
      installing.addEventListener('statechange', function () {
        if (
          installing.state === 'installed' &&
          navigator.serviceWorker.controller
        ) {
          showBanner(installing);
        }
      });
    });

    function check() {
      reg.update().catch(function () {});
    }
    setInterval(check, 60000);
    document.addEventListener('visibilitychange', function () {
      if (document.visibilityState === 'visible') check();
    });
  }

  navigator.serviceWorker
    .register('sw.js')
    .then(watch)
    .catch(function () {
      // Registration failing (unsupported, storage full) must never take
      // the app down - it just means updates arrive via plain reloads.
    });
})();
