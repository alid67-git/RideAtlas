import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/gen/app_localizations.dart';
import '../repositories/locale_controller.dart';

/// Opens the language picker dialog (Türkçe/English/Deutsch). Used by the
/// language row in the Settings screen.
void showLanguagePicker(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (_) => const _LanguagePickerDialog(),
  );
}

class _LanguagePickerDialog extends StatelessWidget {
  const _LanguagePickerDialog();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = context.watch<LocaleController>();
    final current = controller.locale?.languageCode;

    Widget option(String code, String label) {
      return ListTile(
        title: Text(label),
        trailing: current == code ? const Icon(Icons.check) : null,
        selected: current == code,
        onTap: () {
          controller.setLocale(Locale(code));
          Navigator.pop(context);
        },
      );
    }

    return AlertDialog(
      title: Text(l10n.languagePickerTitle),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          option('tr', l10n.languageTurkish),
          option('en', l10n.languageEnglish),
          option('de', l10n.languageGerman),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}
