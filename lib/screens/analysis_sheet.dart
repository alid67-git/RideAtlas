import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/gpx_route.dart';
import '../models/track_point.dart';
import '../services/gpx_parser.dart';
import '../services/route_geography.dart';
import '../services/weather_service.dart';

/// Tabbed route analysis: overview, elevation, countries, stops, weather.
class AnalysisSheet extends StatefulWidget {
  const AnalysisSheet({super.key, required this.route, required this.points});

  final GpxRoute route;
  final List<TrackPoint> points;

  @override
  State<AnalysisSheet> createState() => _AnalysisSheetState();
}

class _AnalysisSheetState extends State<AnalysisSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  RouteGeography? _geography;
  List<DayWeather>? _weather;
  String? _geoError;
  String? _weatherError;
  String _status = '';
  double? _progress;
  bool _geoLoading = false;
  bool _weatherLoading = false;
  bool _geoStarted = false;
  bool _weatherStarted = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _tabs.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;
    if (_tabs.index == 2 || _tabs.index == 3) {
      _ensureGeography();
    } else if (_tabs.index == 4) {
      _ensureWeather();
    }
  }

  Future<void> _ensureGeography() async {
    if (_geoStarted || _geography != null) return;
    _geoStarted = true;
    setState(() {
      _geoLoading = true;
      _geoError = null;
      _status = 'Güzergâh analiz ediliyor…';
      _progress = 0;
    });
    try {
      final result = await RouteGeographyAnalyzer().analyze(
        widget.points,
        onProgress: (msg, p) {
          if (!mounted) return;
          setState(() {
            _status = msg;
            _progress = p;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _geography = result;
        _geoLoading = false;
        _status = '';
        _progress = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _geoLoading = false;
        _geoError = 'Güzergâh analizi başarısız: $e';
        _status = '';
        _progress = null;
      });
    }
  }

  Future<void> _ensureWeather() async {
    if (_weatherStarted || _weather != null) return;
    _weatherStarted = true;
    setState(() {
      _weatherLoading = true;
      _weatherError = null;
      _status = 'Hava durumu yükleniyor…';
      _progress = 0;
    });
    try {
      final result = await WeatherService.instance.forTrack(
        widget.points,
        onProgress: (msg, p) {
          if (!mounted) return;
          setState(() {
            _status = msg;
            _progress = p;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _weather = result;
        _weatherLoading = false;
        _status = '';
        _progress = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _weatherLoading = false;
        _weatherError = 'Hava durumu alınamadı: $e';
        _status = '';
        _progress = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final route = widget.route;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 740),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      route.name,
                      style: theme.textTheme.titleLarge,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Kapat',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              Text(
                DateFormat('d MMMM yyyy, HH:mm').format(route.importedAt),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              TabBar(
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: const [
                  Tab(text: 'Özet'),
                  Tab(text: 'Yükseklik'),
                  Tab(text: 'Güzergâh'),
                  Tab(text: 'Molalar'),
                  Tab(text: 'Hava'),
                ],
              ),
              if (_status.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(_status, style: theme.textTheme.bodySmall),
                if (_progress != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: LinearProgressIndicator(value: _progress),
                  ),
              ],
              const SizedBox(height: 8),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _OverviewTab(route: route, points: widget.points),
                    _ElevationTab(route: route, points: widget.points),
                    _CountriesTab(
                      geography: _geography,
                      loading: _geoLoading,
                      error: _geoError,
                      onRetry: () {
                        _geoStarted = false;
                        _geography = null;
                        _ensureGeography();
                      },
                    ),
                    _StopsTab(
                      geography: _geography,
                      loading: _geoLoading,
                      error: _geoError,
                      onRetry: () {
                        _geoStarted = false;
                        _geography = null;
                        _ensureGeography();
                      },
                    ),
                    _WeatherTab(
                      weather: _weather,
                      loading: _weatherLoading,
                      error: _weatherError,
                      hasTimestamps: widget.points.any((p) => p.time != null),
                      onRetry: () {
                        _weatherStarted = false;
                        _weather = null;
                        _ensureWeather();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Tabs ───────────────────────────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.route, required this.points});

  final GpxRoute route;
  final List<TrackPoint> points;

  @override
  Widget build(BuildContext context) {
    final speed = buildSpeedStats(points);
    final times = trackTimeRange(points);
    final timeFmt = DateFormat('d MMM yyyy, HH:mm');

    return ListView(
      padding: const EdgeInsets.only(right: 8, top: 8),
      children: [
        Row(
          children: [
            Expanded(
              child: AnalysisHeroStat(
                label: 'Mesafe',
                value: route.distanceKm.toStringAsFixed(1),
                unit: 'km',
              ),
            ),
            Expanded(
              child: AnalysisHeroStat(
                label: 'Süre',
                value: route.duration == null
                    ? '—'
                    : formatAnalysisDuration(route.duration!),
                unit: '',
              ),
            ),
            Expanded(
              child: AnalysisHeroStat(
                label: 'Maks. hız',
                value: speed.maxKmh?.toStringAsFixed(1) ?? '—',
                unit: 'km/s',
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const AnalysisSectionTitle(icon: Icons.schedule, title: 'Zaman'),
        const SizedBox(height: 10),
        AnalysisStatGrid(
          children: [
            AnalysisStatCard(
              icon: Icons.play_arrow,
              label: 'Başlangıç',
              value: times.start == null ? '—' : timeFmt.format(times.start!),
            ),
            AnalysisStatCard(
              icon: Icons.stop,
              label: 'Bitiş',
              value: times.end == null ? '—' : timeFmt.format(times.end!),
            ),
            AnalysisStatCard(
              icon: Icons.gps_fixed,
              label: 'GPS noktası',
              value: '${route.pointCount}',
            ),
            AnalysisStatCard(
              icon: Icons.trending_up,
              label: 'Tırmanış',
              value: '${route.elevationGainMeters.round()} m',
            ),
          ],
        ),
      ],
    );
  }
}

class _ElevationTab extends StatelessWidget {
  const _ElevationTab({required this.route, required this.points});

  final GpxRoute route;
  final List<TrackPoint> points;

  @override
  Widget build(BuildContext context) {
    final profile = buildElevationProfile(points);
    final netEle = netElevationChange(points);
    final avgElevation = profile.isEmpty
        ? null
        : profile.map((s) => s.elevation).reduce((a, b) => a + b) /
              profile.length;
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.only(right: 8, top: 8),
      children: [
        if (profile.length > 1) ...[
          Container(
            padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: SizedBox(
              height: 180,
              child: AnalysisElevationChart(samples: profile),
            ),
          ),
          const SizedBox(height: 20),
        ],
        const AnalysisSectionTitle(icon: Icons.terrain, title: 'İstatistikler'),
        const SizedBox(height: 10),
        AnalysisStatGrid(
          children: [
            AnalysisStatCard(
              icon: Icons.trending_up,
              label: 'Tırmanış',
              value: '${route.elevationGainMeters.round()} m',
            ),
            AnalysisStatCard(
              icon: Icons.trending_down,
              label: 'İniş',
              value: '${route.elevationLossMeters.round()} m',
            ),
            AnalysisStatCard(
              icon: Icons.arrow_upward,
              label: 'Maksimum irtifa',
              value: route.maxElevation == null
                  ? '—'
                  : '${route.maxElevation!.round()} m',
            ),
            AnalysisStatCard(
              icon: Icons.arrow_downward,
              label: 'Minimum irtifa',
              value: route.minElevation == null
                  ? '—'
                  : '${route.minElevation!.round()} m',
            ),
            AnalysisStatCard(
              icon: Icons.landscape,
              label: 'Ortalama yükseklik',
              value: avgElevation == null ? '—' : '${avgElevation.round()} m',
            ),
            AnalysisStatCard(
              icon: Icons.swap_vert,
              label: 'Net değişim',
              value: netEle == null
                  ? '—'
                  : '${netEle >= 0 ? '+' : ''}${netEle.round()} m',
            ),
          ],
        ),
      ],
    );
  }
}

class _CountriesTab extends StatelessWidget {
  const _CountriesTab({
    required this.geography,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final RouteGeography? geography;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading && geography == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && geography == null) {
      return _ErrorPane(message: error!, onRetry: onRetry);
    }
    final geo = geography;
    if (geo == null) {
      return const Center(child: Text('Güzergâh sekmesine geçince yüklenir.'));
    }
    if (geo.legs.isEmpty) {
      return const _EmptyPane(
        icon: Icons.public_off,
        message:
            'Ülke bilgisi çıkarılamadı. İnternet gerekir; konum servisi yanıt vermemiş olabilir.',
      );
    }

    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(right: 8, top: 8),
      children: [
        Text(
          '${geo.uniqueCountries.length} ülke · geçiş sırası',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in geo.uniqueCountries)
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text(c, style: theme.textTheme.bodySmall),
              ),
          ],
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < geo.legs.length; i++) ...[
          _CountryLegTile(index: i + 1, leg: geo.legs[i]),
          if (i < geo.legs.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _CountryLegTile extends StatelessWidget {
  const _CountryLegTile({required this.index, required this.leg});

  final int index;
  final CountryLeg leg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cities = leg.cities.isEmpty ? null : leg.cities.join(', ');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            child: Text('$index', style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  leg.country,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    '${leg.distanceKm.toStringAsFixed(0)} km',
                    if (leg.duration != null)
                      formatAnalysisDuration(leg.duration!),
                  ].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
                if (cities != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    cities,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StopsTab extends StatelessWidget {
  const _StopsTab({
    required this.geography,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final RouteGeography? geography;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading && geography == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && geography == null) {
      return _ErrorPane(message: error!, onRetry: onRetry);
    }
    final geo = geography;
    if (geo == null) {
      return const Center(child: Text('Molalar sekmesine geçince yüklenir.'));
    }
    if (geo.stops.isEmpty) {
      return const _EmptyPane(
        icon: Icons.hotel_outlined,
        message:
            '20 dk+ mola tespit edilmedi. GPX’te zaman damgası yoksa veya sürekli hareket varsa liste boş kalır.',
      );
    }

    final theme = Theme.of(context);
    final fmt = DateFormat('d MMM HH:mm');
    return ListView(
      padding: const EdgeInsets.only(right: 8, top: 8),
      children: [
        Text(
          '${geo.stops.length} mola (≥ 20 dk)',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 12),
        for (final stop in geo.stops) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.place, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          if (stop.city != null) stop.city!,
                          if (stop.country != null) stop.country!,
                        ].isEmpty
                            ? 'Bilinmeyen konum'
                            : [
                                if (stop.city != null) stop.city!,
                                if (stop.country != null) stop.country!,
                              ].join(', '),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formatAnalysisDuration(stop.duration),
                        style: theme.textTheme.bodySmall,
                      ),
                      if (stop.start != null || stop.end != null)
                        Text(
                          [
                            if (stop.start != null) fmt.format(stop.start!),
                            if (stop.end != null) fmt.format(stop.end!),
                          ].join(' → '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _WeatherTab extends StatelessWidget {
  const _WeatherTab({
    required this.weather,
    required this.loading,
    required this.error,
    required this.hasTimestamps,
    required this.onRetry,
  });

  final List<DayWeather>? weather;
  final bool loading;
  final String? error;
  final bool hasTimestamps;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (!hasTimestamps) {
      return const _EmptyPane(
        icon: Icons.event_busy,
        message: 'Bu rotada GPS zaman damgası yok; günlük hava durumu hesaplanamaz.',
      );
    }
    if (loading && weather == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && weather == null) {
      return _ErrorPane(message: error!, onRetry: onRetry);
    }
    final days = weather;
    if (days == null) {
      return const Center(child: Text('Hava sekmesine geçince yüklenir.'));
    }
    if (days.isEmpty) {
      return _EmptyPane(
        icon: Icons.cloud_off,
        message: 'Hava verisi alınamadı. İnternet bağlantını kontrol et.',
        onRetry: onRetry,
      );
    }

    final theme = Theme.of(context);
    final fmt = DateFormat('EEEE, d MMM yyyy', 'tr');
    return ListView(
      padding: const EdgeInsets.only(right: 8, top: 8),
      children: [
        Text('${days.length} gün', style: theme.textTheme.titleSmall),
        const SizedBox(height: 12),
        for (final day in days) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(day.icon, color: theme.colorScheme.primary, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fmt.format(day.date),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(day.label, style: theme.textTheme.bodySmall),
                      Text(
                        [
                          if (day.tempMinC != null && day.tempMaxC != null)
                            '${day.tempMinC!.round()}° / ${day.tempMaxC!.round()}°C',
                          if (day.precipitationMm != null)
                            'yağış ${day.precipitationMm!.toStringAsFixed(1)} mm',
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

// ─── Shared UI ──────────────────────────────────────────────────────────────

String formatAnalysisDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) return '$h sa $m dk';
  if (m > 0) return '$m dk $s sn';
  return '$s sn';
}

class AnalysisSectionTitle extends StatelessWidget {
  const AnalysisSectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Text(title, style: theme.textTheme.titleMedium),
      ],
    );
  }
}

class AnalysisHeroStat extends StatelessWidget {
  const AnalysisHeroStat({
    required this.label,
    required this.value,
    required this.unit,
  });

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
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(unit, style: theme.textTheme.bodySmall),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class AnalysisStatCard extends StatelessWidget {
  const AnalysisStatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

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
          Icon(icon, color: theme.colorScheme.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AnalysisStatGrid extends StatelessWidget {
  const AnalysisStatGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.5,
      children: children,
    );
  }
}

class AnalysisElevationChart extends StatelessWidget {
  const AnalysisElevationChart({required this.samples});

  final List<ElevationSample> samples;

  @override
  Widget build(BuildContext context) {
    final minY =
        samples.map((s) => s.elevation).reduce((a, b) => a < b ? a : b);
    final maxY =
        samples.map((s) => s.elevation).reduce((a, b) => a > b ? a : b);
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
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (v, meta) {
                return Text('${v.round()}m', style: theme.textTheme.bodySmall);
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (v, meta) {
                return Text(
                  '${v.toStringAsFixed(0)}km',
                  style: theme.textTheme.bodySmall,
                );
              },
            ),
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
            belowBarData: BarAreaData(
              show: true,
              color: theme.colorScheme.primary.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Tekrar dene')),
          ],
        ),
      ),
    );
  }
}

class _EmptyPane extends StatelessWidget {
  const _EmptyPane({
    required this.icon,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: onRetry, child: const Text('Tekrar dene')),
            ],
          ],
        ),
      ),
    );
  }
}
