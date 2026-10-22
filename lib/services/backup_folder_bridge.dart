import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android Storage Access Framework bridge: pick a persistable folder
/// (including a Google Drive folder) and write a file into it.
class BackupFolderBridge {
  BackupFolderBridge._();

  static const _channel = MethodChannel('com.rideatlas.app/backup_folder');

  static final bool isSupported =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Opens the system folder picker. Returns a map with `uri` + `name`, or
  /// null if the rider cancelled.
  static Future<({String uri, String name})?> pickFolder() async {
    if (!isSupported) return null;
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>('pickFolder');
    if (raw == null) return null;
    final uri = raw['uri'] as String?;
    final name = raw['name'] as String? ?? 'Drive';
    if (uri == null || uri.isEmpty) return null;
    return (uri: uri, name: name);
  }

  /// Writes [bytes] as [fileName] under the previously picked tree [uri].
  /// Overwrites an existing file with the same name. Returns true on success.
  static Future<bool> writeFile({
    required String uri,
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (!isSupported) return false;
    final ok = await _channel.invokeMethod<bool>('writeFile', {
      'uri': uri,
      'fileName': fileName,
      'bytes': bytes,
    });
    return ok == true;
  }

  /// Best-effort display name for a previously persisted tree URI.
  static Future<String?> folderDisplayName(String uri) async {
    if (!isSupported) return null;
    return _channel.invokeMethod<String>('folderDisplayName', {'uri': uri});
  }
}
