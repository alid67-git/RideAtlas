import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../build_info.dart';
import '../changelog.dart';
import '../l10n/gen/app_localizations.dart';

/// Current version plus full version history. Reachable from
/// Settings > About; used to live behind a floating badge in the corner of
/// every screen, moved here since that badge collided with other on-screen
/// controls.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final dateFmt = DateFormat(
      'd MMMM yyyy',
      Localizations.localeOf(context).languageCode,
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('RideAtlas', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            l10n.appRunningVersion(kAppBuildLabel),
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.aboutDeveloper,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Text(l10n.aboutVersionHistoryTitle, style: theme.textTheme.titleMedium),
          const Divider(height: 24),
          for (final entry in kChangelog) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
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
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}
