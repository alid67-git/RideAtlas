import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// A newer Android build found on GitHub than the one currently running.
class UpdateInfo {
  const UpdateInfo({required this.version, required this.downloadUrl});

  final String version;
  final String downloadUrl;
}

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
    final downloadUrl = apkAsset.first['browser_download_url'] as String?;
    if (downloadUrl == null) return null;

    return UpdateInfo(version: releaseVersion, downloadUrl: downloadUrl);
  } catch (_) {
    return null;
  }
}

/// Downloads [info]'s APK to a temp file and hands it to the system
/// installer (via a content:// URI, as required on Android 7+). Throws on
/// any failure - a failed HTTP request, a write error, or the installer
/// rejecting the file (e.g. "install unknown apps" not yet granted for this
/// app) - so the caller can fall back to a plain browser download.
Future<void> downloadAndInstallUpdate(UpdateInfo info) async {
  final response = await http
      .get(Uri.parse(info.downloadUrl))
      .timeout(const Duration(minutes: 2));
  if (response.statusCode != 200) {
    throw HttpException('HTTP ${response.statusCode}');
  }

  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/RideAtlas-update.apk');
  await file.writeAsBytes(response.bodyBytes);

  final result = await OpenFilex.open(file.path);
  if (result.type != ResultType.done) {
    throw Exception(result.message);
  }
}
