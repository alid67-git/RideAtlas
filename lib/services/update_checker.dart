import 'dart:convert';
import 'dart:io';

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

/// Checks GitHub's rolling "android-latest" release against [currentVersion]
/// (typically [kAppBuildLabel]). Returns null if already up to date, or if
/// the check fails for any reason (offline, rate-limited, malformed
/// response) - this is a best-effort background check that should never
/// block or error out the app.
Future<UpdateInfo?> checkForAndroidUpdate(String currentVersion) async {
  try {
    final response = await http
        .get(Uri.parse(_releaseApiUrl))
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final name = json['name'] as String? ?? '';
    final releaseVersion = _versionInName.firstMatch(name)?.group(0)?.trim();
    if (releaseVersion == null || releaseVersion == currentVersion) {
      return null;
    }

    final assets = (json['assets'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final apkAsset = assets.where((a) => a['name'] == 'RideAtlas.apk');
    if (apkAsset.isEmpty) return null;
    final asset = apkAsset.first;
    final downloadUrl = asset['browser_download_url'] as String?;
    if (downloadUrl == null) return null;
    final size = asset['size'];
    final sizeBytes = size is int
        ? size
        : size is num
        ? size.toInt()
        : 0;

    return UpdateInfo(
      version: releaseVersion,
      downloadUrl: downloadUrl,
      sizeBytes: sizeBytes,
    );
  } catch (_) {
    return null;
  }
}

/// Streams [info]'s APK to a temp file (reporting [onProgress]), then hands
/// it to the system installer. Throws on HTTP/write/installer failure so the
/// caller can fall back to a browser download.
Future<void> downloadAndInstallUpdate(
  UpdateInfo info, {
  UpdateDownloadProgress? onProgress,
}) async {
  final client = http.Client();
  try {
    final request = http.Request('GET', Uri.parse(info.downloadUrl));
    final response = await client
        .send(request)
        .timeout(const Duration(minutes: 8));
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}');
    }

    final total = response.contentLength ??
        (info.sizeBytes > 0 ? info.sizeBytes : null);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/RideAtlas-update.apk');
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }

    final sink = file.openWrite();
    var received = 0;
    var lastPct = -1;
    var lastReceivedForUnknown = 0;
    onProgress?.call(0, total);

    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total != null && total > 0) {
          final pct = received * 100 ~/ total;
          if (pct != lastPct || received >= total) {
            lastPct = pct;
            onProgress?.call(received, total);
          }
        } else if (received - lastReceivedForUnknown >= 256 * 1024) {
          lastReceivedForUnknown = received;
          onProgress?.call(received, total);
        }
      }
    } finally {
      await sink.close();
    }

    if (!await file.exists() || await file.length() < 1024) {
      throw const HttpException('İndirilen dosya geçersiz veya boş.');
    }

    onProgress?.call(received, total ?? received);

    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      throw Exception(result.message);
    }
  } finally {
    client.close();
  }
}
