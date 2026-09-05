import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:web/web.dart' as web;

/// An empty or `*/*` `accept` makes iOS Safari's `<input type="file">` also
/// match image/video content, so the OS offers "Photo Library"/"Take Photo
/// or Video" alongside "Choose File" - confusing for a track-file picker.
/// A bare extension list alone is also unreliable there for less common
/// extensions, so each one is paired with its MIME type plus a generic
/// `application/octet-stream` fallback for files the browser can't
/// identify - no image/video MIME type is listed, so the photo shortcuts
/// never appear (MediaAtlas-style; ported after this exact bug resurfaced
/// on iOS Safari with a plain `.gpx,.kml,.kmz` accept string).
const _trackAccept =
    '.gpx,.kml,.kmz,application/octet-stream,application/gpx+xml,'
    'application/vnd.google-earth.kml+xml,application/vnd.google-earth.kmz,'
    'application/xml,text/xml';

/// Web: opens a hidden `<input type="file">` instead of going through
/// file_picker's own web implementation, so the `accept` string above can
/// be used verbatim (file_picker only accepts a plain extension list, which
/// is what broke GPX selection on iOS Safari in the first place).
Future<FilePickerResult?> pickTrackFiles({bool allowMultiple = false}) async {
  final done = Completer<FilePickerResult?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..multiple = allowMultiple
    ..accept = _trackAccept;
  input.style
    ..position = 'fixed'
    ..left = '0'
    ..top = '0'
    ..width = '1px'
    ..height = '1px'
    ..opacity = '0'
    ..pointerEvents = 'none'
    ..zIndex = '-1';
  web.document.body?.appendChild(input);

  void finish(FilePickerResult? value) {
    if (!done.isCompleted) done.complete(value);
  }

  void cleanup() {
    try {
      input.remove();
    } catch (_) {}
  }

  Future<Uint8List?> readFile(web.File file) async {
    try {
      final buffer = await file.arrayBuffer().toDart;
      return buffer.toDart.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> readFiles(web.FileList list) async {
    final out = <PlatformFile>[];
    for (var i = 0; i < list.length; i++) {
      final file = list.item(i);
      if (file == null) continue;
      final bytes = await readFile(file);
      if (bytes == null) continue;
      out.add(PlatformFile(name: file.name, size: bytes.length, bytes: bytes));
    }
    finish(out.isEmpty ? null : FilePickerResult(out));
  }

  input.addEventListener(
    'change',
    (web.Event _) {
      final list = input.files;
      if (list == null || list.length == 0) {
        finish(null);
        return;
      }
      unawaited(readFiles(list));
    }.toJS,
  );
  input.addEventListener(
    'cancel',
    (web.Event _) {
      finish(null);
    }.toJS,
  );

  // Safari doesn't reliably fire 'cancel' when the sheet is dismissed
  // without picking a file - fall back to checking on window focus
  // (fired when the native file sheet closes either way).
  var focusArmed = false;
  void onFocus(web.Event _) {
    if (!focusArmed || done.isCompleted) return;
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      if (done.isCompleted) return;
      final list = input.files;
      if (list != null && list.length > 0) {
        unawaited(readFiles(list));
      } else {
        finish(null);
      }
    });
  }

  final jsOnFocus = onFocus.toJS;
  web.window.addEventListener('focus', jsOnFocus);
  Future<void>.delayed(const Duration(milliseconds: 300), () {
    focusArmed = true;
  });

  input.click();

  try {
    return await done.future;
  } finally {
    web.window.removeEventListener('focus', jsOnFocus);
    Future<void>.delayed(const Duration(seconds: 2), cleanup);
  }
}
