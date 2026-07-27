import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../changelog.dart';
import '../l10n/gen/app_localizations.dart';

/// Full version history, opened by tapping the build badge in the corner
/// of the app (see `_BuildBadge` in main.dart).
class ChangelogDialog extends StatelessWidget {
  const ChangelogDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final dateFmt = DateFormat(
      'd MMMM yyyy',
      Localizations.localeOf(context).languageCode,
    );

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.changelogTitle,
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: l10n.close,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: kChangelog.length,
                  separatorBuilder: (_, _) => const Divider(height: 20),
                  itemBuilder: (context, i) {
                    final entry = kChangelog[i];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              entry.version,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              dateFmt.format(DateTime.parse(entry.date)),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(entry.note, style: theme.textTheme.bodyMedium),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
