import 'dart:async';

import 'package:flutter/material.dart';

/// Non-dismissible “working…” dialog with an updatable status line.
class BusyProgressHandle {
  BusyProgressHandle._(this._context, this._message);

  final BuildContext _context;
  final ValueNotifier<String> _message;
  var _closed = false;

  void update(String message) {
    if (_closed) return;
    _message.value = message;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _message.dispose();
    if (_context.mounted) {
      Navigator.of(_context, rootNavigator: true).pop();
    }
  }
}

/// Shows a blocking progress dialog, then runs [action]. Always closes the
/// dialog afterward (even on throw). [action] may call [setMessage] to update
/// the status line (e.g. “File 2/5…”).
Future<T> runBusyProgress<T>({
  required BuildContext context,
  required String message,
  required Future<T> Function(void Function(String message) setMessage) action,
}) async {
  final handle = await showBusyProgress(context, message: message);
  try {
    return await action(handle.update);
  } finally {
    await handle.close();
  }
}

Future<BusyProgressHandle> showBusyProgress(
  BuildContext context, {
  required String message,
}) async {
  final notifier = ValueNotifier(message);
  final dialogContextCompleter = Completer<BuildContext>();

  // Do not await the dialog future — it completes only when popped.
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogContext) {
        if (!dialogContextCompleter.isCompleted) {
          dialogContextCompleter.complete(dialogContext);
        }
        return PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ValueListenableBuilder<String>(
                    valueListenable: notifier,
                    builder: (context, msg, _) => Text(msg),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  final dialogContext = await dialogContextCompleter.future;
  // Let the first frame paint before heavy work.
  await Future<void>.delayed(Duration.zero);
  return BusyProgressHandle._(dialogContext, notifier);
}
