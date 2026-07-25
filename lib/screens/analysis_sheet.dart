import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/gpx_route.dart';
import '../models/track_point.dart';
import '../services/gpx_parser.dart';

/// Detailed stats for a route: distance, duration, average speed, elevation
/// gain/loss, min/max/avg elevation and an elevation-vs-distance profile
/// chart.
class AnalysisSheet extends StatelessWidget {
  const AnalysisSheet({super.key, required this.route, required this.points});

  final GpxRoute route;
  final List<TrackPoint> points;

  @override
  Widget build(BuildContext context) {
    final profile = buildElevationProfile(points);
    final avgElevation = profile.isEmpty
        ? null
        : profile.map((s) => s.elevation).reduce((a, b) => a + b) / profile.length;
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(route.name, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                DateFormat('d MMMM yyyy, HH:mm').format(route.importedAt),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _HeroStat(
                      label: 'Mesafe',
                      value: route.distanceKm.toStringAsFixed(1),
                      unit: 'km',
                    ),
                  ),
                  Expanded(
                    child: _HeroStat(
                      label: 'Süre',
                      value: route.duration == null ? '—' : _formatDuration(route.duration!),
                      unit: '',
                    ),
                  ),
                  Expanded(
                    child: _HeroStat(
                      label: 'Ort. hız',
                      value: route.averageSpeedKmh?.toStringAsFixed(0) ?? '—',
                      unit: 'km/s',
                    ),
                  ),
                ],
              ),
              if (profile.length > 1) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    Icon(Icons.show_chart, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Text('Yükseklik profili', style: theme.textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SizedBox(height: 200, child: _ElevationChart(samples: profile)),
                ),
              ],
              const SizedBox(height: 24),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 2.6,
                children: [
                  _StatCard(
                    icon: Icons.trending_up,
                    label: 'Tırmanış',
                    value: '${route.elevationGainMeters.round()} m',
                  ),
                  _StatCard(
                    icon: Icons.trending_down,
                    label: 'İniş',
                    value: '${route.elevationLossMeters.round()} m',
                  ),
                  _StatCard(
                    icon: Icons.height,
                    label: 'Yükseklik (min/maks)',
                    value: route.minElevation == null
                        ? '—'
                        : '${route.minElevation!.round()} / ${route.maxElevation!.round()} m',
                  ),
                  _StatCard(
                    icon: Icons.landscape,
                    label: 'Ortalama yükseklik',
                    value: avgElevation == null ? '—' : '${avgElevation.round()} m',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${route.pointCount} GPS noktası',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '$h sa $m dk';
    return '$m dk';
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value, required this.unit});

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        const SizedBox(height: 2),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Text(
              value,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(unit, style: theme.textTheme.bodyMedium),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, style: theme.textTheme.bodySmall),
                Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ElevationChart extends StatelessWidget {
  const _ElevationChart({required this.samples});

  final List<ElevationSample> samples;

  @override
  Widget build(BuildContext context) {
    final minY = samples.map((s) => s.elevation).reduce((a, b) => a < b ? a : b);
    final maxY = samples.map((s) => s.elevation).reduce((a, b) => a > b ? a : b);
    final maxX = samples.last.distanceKm;
    final theme = Theme.of(context);

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX == 0 ? 1 : maxX,
        minY: minY - 10,
        maxY: maxY + 10,
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 44, getTitlesWidget: (v, meta) {
              return Text('${v.round()}m', style: theme.textTheme.bodySmall);
            }),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 24, getTitlesWidget: (v, meta) {
              return Text('${v.toStringAsFixed(0)}km', style: theme.textTheme.bodySmall);
            }),
          ),
        ),
        lineTouchData: const LineTouchData(enabled: true),
        lineBarsData: [
          LineChartBarData(
            spots: [for (final s in samples) FlSpot(s.distanceKm, s.elevation)],
            isCurved: true,
            barWidth: 2,
            color: theme.colorScheme.primary,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: theme.colorScheme.primary.withValues(alpha: 0.15)),
          ),
        ],
      ),
    );
  }
}
