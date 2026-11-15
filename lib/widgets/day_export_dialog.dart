import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/gen/app_localizations.dart';
import '../services/backup_folder_bridge.dart';
import '../services/daily_analysis.dart';
import '../services/day_export.dart';

/// Asks which part of a multi-day track to export and where to put it.
///
/// Returns null if cancelled. [days] must have length ≥ 2.
Future<DayExportPlan?> showDayExportDialog({
  required BuildContext context,
  required List<DayStats> days,
}) {
  assert(days.length >= 2);
  return showDialog<DayExportPlan>(
    context: context,
    builder: (context) => _DayExportDialog(days: days),
  );
}

class _DayExportDialog extends StatefulWidget {
  const _DayExportDialog({required this.days});

  final List<DayStats> days;

  @override
  State<_DayExportDialog> createState() => _DayExportDialogState();
}

class _DayExportDialogState extends State<_DayExportDialog> {
  DayExportScope _scope = DayExportScope.selectedDays;
  late Set<DateTime> _checked;
  DayExportDestination _destination = BackupFolderBridge.isSupported
      ? DayExportDestination.folder
      : DayExportDestination.share;

  @override
  void initState() {
    super.initState();
    _checked = {for (final d in widget.days) d.date};
  }

  void _toggleDay(DateTime day, bool? value) {
    setState(() {
      if (value == true) {
        _checked.add(day);
      } else if (_checked.length > 1) {
        _checked.remove(day);
      }
    });
  }

  void _submit() {
    final selected = widget.days
        .map((d) => d.date)
        .where(_checked.contains)
        .toList();
    if (_scope == DayExportScope.selectedDays && selected.isEmpty) return;
    Navigator.pop(
      context,
      DayExportPlan(
        scope: _scope,
        destination: _destination,
        selectedDays: selected,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final dateFmt =
        DateFormat.yMMMEd(Localizations.localeOf(context).toString());
    final folderOk = BackupFolderBridge.isSupported;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.dayExportTitle(widget.days.length),
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                l10n.dayExportSubtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              RadioGroup<DayExportScope>(
                groupValue: _scope,
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _scope = v);
                },
                child: Column(
                  children: [
                    RadioListTile<DayExportScope>(
                      value: DayExportScope.fullRoute,
                      title: Text(l10n.dayExportFullRoute),
                      subtitle: Text(l10n.dayExportFullRouteHint),
                      contentPadding: EdgeInsets.zero,
                    ),
                    RadioListTile<DayExportScope>(
                      value: DayExportScope.selectedDays,
                      title: Text(l10n.dayExportSelectedDays),
                      subtitle: Text(l10n.dayExportSelectedDaysHint),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              if (_scope == DayExportScope.selectedDays) ...[
                const Divider(height: 16),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: widget.days.length,
                    itemBuilder: (context, i) {
                      final day = widget.days[i];
                      final km = day.distanceKm.toStringAsFixed(1);
                      return CheckboxListTile(
                        value: _checked.contains(day.date),
                        onChanged: (v) => _toggleDay(day.date, v),
                        contentPadding: EdgeInsets.zero,
                        secondary: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: day.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        title: Text(
                          '${l10n.dayLabel(day.dayNumber)} · ${dateFmt.format(day.date)}',
                        ),
                        subtitle: Text('$km km'),
                      );
                    },
                  ),
                ),
              ],
              const Divider(height: 16),
              Text(
                l10n.dayExportDestinationTitle,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              RadioGroup<DayExportDestination>(
                groupValue: _destination,
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _destination = v);
                },
                child: Column(
                  children: [
                    if (folderOk)
                      RadioListTile<DayExportDestination>(
                        value: DayExportDestination.folder,
                        title: Text(l10n.dayExportDestinationFolder),
                        subtitle: Text(l10n.dayExportDestinationFolderHint),
                        contentPadding: EdgeInsets.zero,
                      ),
                    RadioListTile<DayExportDestination>(
                      value: DayExportDestination.share,
                      title: Text(l10n.dayExportDestinationShare),
                      subtitle: Text(l10n.dayExportDestinationShareHint),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l10n.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _submit,
                    child: Text(l10n.dayExportContinue),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
