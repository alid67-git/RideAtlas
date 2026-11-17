import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// A newer Android build found on GitHub than the one currently running.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.sizeBytes,
  });

  final String version;
  final String downloadUrl;

  /// Asset size from the GitHub Releases API - used for percent progress
  /// when the download response itself has no Content-Length (common on
  /// GitHub's CDN with chunked transfer).
  final int sizeBytes;
}

/// Progress while streaming the APK: [received] bytes so far and optional
/// Content-Length [total] (null when the server omits it).
typedef UpdateDownloadProgress = void Function(int received, int? total);

const _releaseApiUrl =
    'https://api.github.com/repos/alid67-git/RideAtlas/releases/tags/android-latest';

/// The CI workflow (build-android.yml) embeds the build's version from
/// build_info.dart into the release name as "... - vX.Y.Z beta".
final _versionInName = RegExp(r'v[\d.]+(?:\s+\w+)?$');

/// Outcome of probing GitHub for a newer Android APK.
enum AndroidUpdateProbeStatus {
  /// Running build matches (or is newer than) android-latest.
  upToDate,

  /// A newer APK is available - see [AndroidUpdateProbeResult.info].
  updateAvailable,

  /// Offline, rate-limited, malformed response, etc.
  failed,
}

/// Result of [probeAndroidUpdate] - distinguishes "already latest" from
/// "couldn't reach GitHub", which the silent [checkForAndroidUpdate] path
/// used to collapse into a single null.
class AndroidUpdateProbeResult {
  const AndroidUpdateProbeResult._(this.status, [this.info]);

  const AndroidUpdateProbeResult.upToDate()
      : this._(AndroidUpdateProbeStatus.upToDate);

  const AndroidUpdateProbeResult.failed()
      : this._(AndroidUpdateProbeStatus.failed);

  const AndroidUpdateProbeResult.available(UpdateInfo info)
      : this._(AndroidUpdateProbeStatus.updateAvailable, info);

  final AndroidUpdateProbeStatus status;
  final UpdateInfo? info;
}

/// Probes GitHub's rolling "android-latest" release against [currentVersion]
/// (typically [kAppBuildLabel]).
Future<AndroidUpdateProbeResult> probeAndroidUpdate(
  String currentVersion,
) async {
  try {
    final response = await http
        .get(Uri.parse(_releaseApiUrl))
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      return const AndroidUpdateProbeResult.failed();
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final name = json['name'] as String? ?? '';
    final releaseVersion = _versionInName.firstMatch(name)?.group(0)?.trim();
    if (releaseVersion == null) {
      return const AndroidUpdateProbeResult.failed();
    }
    if (releaseVersion == currentVersion) {
      return const AndroidUpdateProbeResult.upToDate();
    }

    final assets = (json['assets'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final apkAsset = assets.where((a) => a['name'] == 'RideAtlas.apk');
    if (apkAsset.isEmpty) {
      return const AndroidUpdateProbeResult.failed();
    }
    final asset = apkAsset.first;
    final downloadUrl = asset['browser_download_url'] as String?;
    if (downloadUrl == null) {
      return const AndroidUpdateProbeResult.failed();
    }
    final size = asset['size'];
    final sizeBytes = size is int
        ? size
        : size is num
        ? size.toInt()
        : 0;

    return AndroidUpdateProbeResult.available(
      UpdateInfo(
        version: releaseVersion,
        downloadUrl: downloadUrl,
        sizeBytes: sizeBytes,
      ),
    );
  } catch (_) {
    return const AndroidUpdateProbeResult.failed();
  }
}

/// Checks GitHub's rolling "android-latest" release against [currentVersion].
/// Returns null if already up to date, or if the check fails for any reason
/// (offline, rate-limited, malformed response) - best-effort background
/// check that should never block or error out the app.
Future<UpdateInfo?> checkForAndroidUpdate(String currentVersion) async {
  final result = await probeAndroidUpdate(currentVersion);
  return result.info;
}

class _DownloadIsolateArgs {
  const _DownloadIsolateArgs({
    required this.url,
    required this.path,
    required this.sendPort,
  });

  final String url;
  final String path;
  final SendPort sendPort;
}

/// Downloads the APK on a background isolate (HTTP + disk write). Messages:
/// `int` = bytes received so far, `'done'` = success, `'error:…'` = failure.
@pragma('vm:entry-point')
void _downloadApkIsolate(_DownloadIsolateArgs args) async {
  HttpClient? client;
  IOSink? sink;
  try {
    client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    final request = await client.getUrl(Uri.parse(args.url));
    request.headers.set(HttpHeaders.userAgentHeader, 'RideAtlas');
    final response = await request.close().timeout(const Duration(minutes: 8));
    if (response.statusCode != 200) {
      args.sendPort.send('error:HTTP ${response.statusCode}');
      return;
    }

    final file = File(args.path);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
    sink = file.openWrite();
    var received = 0;
    var lastReport = 0;
    await for (final chunk in response) {
      sink.add(chunk);
      received += chunk.length;
      // Coarse progress from the worker so the UI isolate isn't flooded.
      if (received - lastReport >= 512 * 1024) {
        lastReport = received;
        args.sendPort.send(received);
      }
    }
    await sink.flush();
    await sink.close();
    sink = null;
    client.close(force: true);
    client = null;

    if (!await file.exists() || await file.length() < 1024) {
      args.sendPort.send('error:Downloaded file is invalid or empty.');
      return;
    }
    args.sendPort.send(received);
    args.sendPort.send('done');
  } catch (e) {
    try {
      await sink?.close();
    } catch (_) {}
    try {
      client?.close(force: true);
    } catch (_) {}
    args.sendPort.send('error:$e');
  }
}

/// Streams [info]'s APK to a temp file on a **background isolate** (so a
/// ~70 MB write never ANRs the UI), reporting [onProgress], then hands the
/// file to the system installer on the main isolate.
Future<void> downloadAndInstallUpdate(
  UpdateInfo info, {
  UpdateDownloadProgress? onProgress,
}) async {
  final totalHint = info.sizeBytes > 0 ? info.sizeBytes : null;
  final dir = await getTemporaryDirectory();
  final path = '${dir.path}/RideAtlas-update.apk';
  onProgress?.call(0, totalHint);

  final port = ReceivePort();
  final errorPort = ReceivePort();
  final done = Completer<void>();
  var lastReceived = 0;

  void fail(Object error) {
    if (!done.isCompleted) done.completeError(error);
  }

  final sub = port.listen((message) {
    if (message is int) {
      lastReceived = message;
      onProgress?.call(message, totalHint ?? message);
      return;
    }
    if (message == 'done') {
      if (!done.isCompleted) done.complete();
      return;
    }
    if (message is String && message.startsWith('error:')) {
      fail(HttpException(message.substring(6)));
    }
  });
  final errSub = errorPort.listen((message) {
    fail(Exception('Download isolate error: $message'));
  });

  try {
    await Isolate.spawn(
      _downloadApkIsolate,
      _DownloadIsolateArgs(
        url: info.downloadUrl,
        path: path,
        sendPort: port.sendPort,
      ),
      onError: errorPort.sendPort,
      errorsAreFatal: true,
    );
    await done.future.timeout(const Duration(minutes: 10));
  } finally {
    await sub.cancel();
    await errSub.cancel();
    port.close();
    errorPort.close();
  }

  onProgress?.call(
    lastReceived > 0 ? lastReceived : (totalHint ?? 0),
    totalHint ?? lastReceived,
  );

  final result = await OpenFilex.open(path);
  if (result.type != ResultType.done) {
    throw Exception(result.message);
  }
  // The installer screen is now open on top of us, but this process keeps
  // running underneath it - once the install finishes, the rider could
  // swipe back into this same stale process instead of the fresh APK.
  // Close it shortly after handing off to the installer.
  if (Platform.isAndroid) {
    unawaited(Future<void>.delayed(const Duration(milliseconds: 600), () {
      SystemNavigator.pop();
    }));
  }
}
