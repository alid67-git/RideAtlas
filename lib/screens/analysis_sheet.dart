import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/gpx_route.dart';
import '../models/track_point.dart';
import '../repositories/stat_icon_settings_controller.dart';
import '../services/daily_analysis.dart';
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
    _tabs = TabController(length: 6, vsync: this);
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
    if (_tabs.index == 2 || _tabs.index == 3 || _tabs.index == 5) {
      _ensureGeography();
    } else if (_tabs.index == 4) {
      _ensureWeather();
    }
  }

  Future<void> _ensureGeography() async {
    if (_geoStarted || _geography != null) return;
    _geoStarted = true;
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _geoLoading = true;
      _geoError = null;
      _status = l10n.statusAnalyzingRoute;
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
        _geoError = l10n.geographyFailed('$e');
        _status = '';
        _progress = null;
      });
    }
  }

  Future<void> _ensureWeather() async {
    if (_weatherStarted || _weather != null) return;
    _weatherStarted = true;
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _weatherLoading = true;
      _weatherError = null;
      _status = l10n.statusLoadingWeather;
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
        _weatherError = l10n.weatherFailed('$e');
        _status = '';
        _progress = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final route = widget.route;
    final localeName = Localizations.localeOf(context).languageCode;

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
                    tooltip: l10n.close,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              Text(
                DateFormat(
                  'd MMMM yyyy, HH:mm',
                  localeName,
                ).format(route.importedAt),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              TabBar(
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: l10n.tabOverview),
                  Tab(text: l10n.tabElevation),
                  Tab(text: l10n.tabRoute),
                  Tab(text: l10n.tabStops),
                  Tab(text: l10n.tabWeather),
                  Tab(text: l10n.tabDaily),
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
                    _DailyTab(
                      points: widget.points,
                      geography: _geography,
                      geoLoading: _geoLoading,
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
    final lastAltitude = lastAltitudeOf(points);
    final l10n = AppLocalizations.of(context)!;
    final speed = buildSpeedStats(points);
    final times = trackTimeRange(points);
    final timeFmt = DateFormat(
      'd MMM yyyy, HH:mm',
      Localizations.localeOf(context).languageCode,
    );
    final total = route.duration;
    // Same dwell-cluster detection the Stops tab and the Daily tab's own
    // riding/rest split already use (RouteGeographyAnalyzer.detectStops),
    // so "Aktif sürüş süresi" here agrees with "Sürüş süresi" on the Daily
    // tab instead of using a different, looser definition of "moving".
    final stops = RouteGeographyAnalyzer().detectStops(points);
    final restDuration = total == null
        ? null
        : stops.fold<Duration>(Duration.zero, (sum, stop) => sum + stop.duration);
    final moving = (total == null || restDuration == null)
        ? null
        : (total - restDuration).isNegative
              ? Duration.zero
              : total - restDuration;
    // Distance ÷ this same "Aktif sürüş süresi" figure, not
    // speed.averageMovingKmh - that one uses a different, narrower
    // definition of "moving" (per-segment, excluding anything under 1 km/h)
    // that doesn't agree with the >=10min-stop definition used everywhere
    // else on this tab, which made the two numbers next to each other look
    // like a bug (a rider caught this by comparing against another app).
    final movingHours = moving == null || moving == Duration.zero
        ? null
        : moving.inMilliseconds / Duration.millisecondsPerHour;
    final distanceKm = totalDistanceKm(points);
    final averageSpeedKmh = movingHours == null
        ? null
        : distanceKm / movingHours;

    return ListView(
      padding: const EdgeInsets.only(right: 8, top: 8),
      children: [
        // Unequal widths instead of 3 plain Expanded columns - "Aktif sürüş
        // süresi" is a much longer label than "Mesafe"/"Ortalama hız", which
        // made every value shrink to match its cramped column and read as
        // uneven at a glance. Giving it more room fixes that without
        // dropping any of the three headline figures.
        Row(
          children: [
            Expanded(
              child: AnalysisHeroStat(
                label: l10n.distance,
                value: distanceKm.toStringAsFixed(1),
                unit: 'km',
              ),
            ),
            Expanded(
              flex: 2,
              child: AnalysisHeroStat(
                label: l10n.netDurationLabel,
                value: moving == null
                    ? '—'
                    : formatAnalysisDuration(l10n, moving),
                unit: '',
              ),
            ),
            Expanded(
              child: AnalysisHeroStat(
                label: l10n.averageSpeedLabel,
                value: averageSpeedKmh?.toStringAsFixed(1) ?? '—',
                unit: 'km/s',
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        AnalysisSectionTitle(icon: Icons.schedule, title: l10n.timeSectionTitle),
        const SizedBox(height: 10),
        AnalysisStatGrid(
          children: [
            AnalysisStatCard(
              icon: Icons.play_arrow,
              label: l10n.start,
              value: times.start == null ? '—' : timeFmt.format(times.start!),
            ),
            AnalysisStatCard(
              icon: Icons.stop,
              label: l10n.end,
              value: times.end == null ? '—' : timeFmt.format(times.end!),
            ),
            AnalysisStatCard(
              icon: Icons.schedule,
              label: l10n.totalDurationLabel,
              value: total == null ? '—' : formatAnalysisDuration(l10n, total),
            ),
            AnalysisStatCard(
              icon: Icons.pause_circle_outline,
              label: l10n.restDurationLabel,
              value: restDuration == null
                  ? '—'
                  : formatAnalysisDuration(l10n, restDuration),
            ),
            AnalysisStatCard(
              icon: Icons.speed,
              label: l10n.averageSpeedLabel,
              value: averageSpeedKmh == null
                  ? '—'
                  : '${averageSpeedKmh.toStringAsFixed(1)} km/s',
            ),
            AnalysisStatCard(
              icon: Icons.bolt,
              label: l10n.maxSpeed,
              value: speed.maxKmh == null
                  ? '—'
                  : '${speed.maxKmh!.toStringAsFixed(1)} km/s',
            ),
            AnalysisStatCard(
              icon: Icons.arrow_upward,
              label: l10n.maxAltitude,
              value: route.maxElevation == null
                  ? '—'
                  : '${route.maxElevation!.round()} m',
            ),
            AnalysisStatCard(
              icon: Icons.arrow_downward,
              label: l10n.minAltitude,
              value: route.minElevation == null
                  ? '—'
                  : '${route.minElevation!.round()} m',
            ),
            AnalysisStatCard(
              icon: Icons.trending_up,
              label: l10n.climb,
              value: '${route.elevationGainMeters.round()} m',
            ),
            AnalysisStatCard(
              icon: Icons.trending_down,
              label: l10n.descent,
              value: '${route.elevationLossMeters.round()} m',
            ),
            AnalysisStatCard(
              icon: Icons.landscape,
              label: l10n.lastAltitudeLabel,
              value: lastAltitude == null
                  ? '—'
                  : '${lastAltitude.round()} m',
            ),
          ],
        ),
        // Kept out of the grid (which would otherwise leave it alone in a
        // half-empty last row, unbalanced) and centered on its own instead.
        if (route.batteryStartPercent != null &&
            route.batteryEndPercent != null) ...[
          const SizedBox(height: 10),
          Center(
            child: SizedBox(
              width: 220,
              child: AnalysisStatCard(
                icon: Icons.battery_std,
                label: l10n.batteryLabel,
                value: l10n.batteryRangeLabel(
                  route.batteryStartPercent!,
                  route.batteryEndPercent!,
                ),
              ),
            ),
          ),
        ],
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
    final l10n = AppLocalizations.of(context)!;
    final profile = buildElevationProfile(points);
    final netEle = netElevationChange(points);
    final avgElevation = profile.isEmpty
        ? null
        : profile.map((s) => s.elevation).reduce((a, b) => a + b) /
              profile.length;
    final lastAltitude = lastAltitudeOf(points);
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
        AnalysisSectionTitle(
          icon: Icons.terrain,
          title: l10n.statisticsTitle,
        ),
        const SizedBox(height: 10),
        AnalysisStatGrid(
          children: [
            AnalysisStatCard(
              icon: Icons.trending_up,
              label: l10n.climb,
              value: '${route.elevationGainMeters.round()} m',
            ),
            AnalysisStatCard(
              icon: Icons.trending_down,
              label: l10n.descent,
              value: '${route.elevationLossMeters.round()} m',
            ),
            AnalysisStatCard(
              icon: Icons.arrow_upward,
              label: l10n.maxAltitude,
              value: route.maxElevation == null
                  ? '—'
                  : '${route.maxElevation!.round()} m',
            ),
            AnalysisStatCard(
              icon: Icons.arrow_downward,
              label: l10n.minAltitude,
              value: route.minElevation == null
                  ? '—'
                  : '${route.minElevation!.round()} m',
            ),
            AnalysisStatCard(
              icon: Icons.landscape,
              label: l10n.avgAltitude,
              value: avgElevation == null ? '—' : '${avgElevation.round()} m',
            ),
            AnalysisStatCard(
              icon: Icons.swap_vert,
              label: l10n.netChange,
              value: netEle == null
                  ? '—'
                  : '${netEle >= 0 ? '+' : ''}${netEle.round()} m',
            ),
          ],
        ),
        const SizedBox(height: 20),
        // The rider's own reading of "how high up am I now" - worth calling
        // out large at the very bottom, separate from the grid above (which
        // is all track-wide extremes/averages, not a single current value).
        AnalysisHeroStat(
          label: l10n.lastAltitudeLabel,
          value: lastAltitude == null ? '—' : lastAltitude.round().toString(),
          unit: 'm',
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
    final l10n = AppLocalizations.of(context)!;
    if (loading && geography == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && geography == null) {
      return _ErrorPane(message: error!, onRetry: onRetry);
    }
    final geo = geography;
    if (geo == null) {
      return Center(child: Text(l10n.loadsOnRouteTab));
    }
    if (geo.legs.isEmpty) {
      return _EmptyPane(
        icon: Icons.public_off,
        message: l10n.countryDataUnavailable,
      );
    }

    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(right: 8, top: 8),
      children: [
        Text(
          l10n.countriesCountLabel(geo.uniqueCountries.length),
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
    final l10n = AppLocalizations.of(context)!;
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
                      formatAnalysisDuration(l10n, leg.duration!),
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
    final l10n = AppLocalizations.of(context)!;
    if (loading && geography == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && geography == null) {
      return _ErrorPane(message: error!, onRetry: onRetry);
    }
    final geo = geography;
    if (geo == null) {
      return Center(child: Text(l10n.loadsOnStopsTab));
    }
    if (geo.stops.isEmpty) {
      return _EmptyPane(
        icon: Icons.hotel_outlined,
        message: l10n.noStopsDetected,
      );
    }

    final theme = Theme.of(context);
    final fmt = DateFormat(
      'd MMM HH:mm',
      Localizations.localeOf(context).languageCode,
    );
    return ListView(
      padding: const EdgeInsets.only(right: 8, top: 8),
      children: [
        Text(
          l10n.stopsCountLabel(geo.stops.length),
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
                            ? l10n.unknownLocation
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
                        formatAnalysisDuration(l10n, stop.duration),
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
    final l10n = AppLocalizations.of(context)!;
    if (!hasTimestamps) {
      return _EmptyPane(
        icon: Icons.event_busy,
        message: l10n.noTimestampsWeather,
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
      return Center(child: Text(l10n.loadsOnWeatherTab));
    }
    if (days.isEmpty) {
      return _EmptyPane(
        icon: Icons.cloud_off,
        message: l10n.weatherDataUnavailable,
        onRetry: onRetry,
      );
    }

    final theme = Theme.of(context);
    final fmt = DateFormat(
      'EEEE, d MMM yyyy',
      Localizations.localeOf(context).languageCode,
    );
    return ListView(
      padding: const EdgeInsets.only(right: 8, top: 8),
      children: [
        Text(l10n.daysCountLabel(days.length), style: theme.textTheme.titleSmall),
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
                      Text(
                        weatherLabelFor(l10n, day.weatherCode),
                        style: theme.textTheme.bodySmall,
                      ),
                      Text(
                        [
                          if (day.tempMinC != null && day.tempMaxC != null)
                            '${day.tempMinC!.round()}° / ${day.tempMaxC!.round()}°C',
                          if (day.precipitationMm != null)
                            l10n.precipitationLabel(
                              day.precipitationMm!.toStringAsFixed(1),
                            ),
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

/// Maps an Open-Meteo weather code to a localized label (mirrors
/// [weatherCodeLabelTr] in weather_service.dart, which stays Turkish-only
/// since it has no BuildContext).
String weatherLabelFor(AppLocalizations l10n, int code) {
  if (code == 0) return l10n.weatherClear;
  if (code == 1) return l10n.weatherMostlyClear;
  if (code == 2) return l10n.weatherPartlyCloudy;
  if (code == 3) return l10n.weatherOvercast;
  if (code == 45 || code == 48) return l10n.weatherFog;
  if (code >= 51 && code <= 57) return l10n.weatherDrizzle;
  if (code >= 61 && code <= 67) return l10n.weatherRain;
  if (code >= 71 && code <= 77) return l10n.weatherSnow;
  if (code >= 80 && code <= 82) return l10n.weatherShowers;
  if (code >= 85 && code <= 86) return l10n.weatherSnowShowers;
  if (code >= 95 && code <= 99) return l10n.weatherThunderstorm;
  return l10n.weatherVariable;
}

class _DailyTab extends StatelessWidget {
  const _DailyTab({
    required this.points,
    required this.geography,
    required this.geoLoading,
  });

  final List<TrackPoint> points;
  final RouteGeography? geography;
  final bool geoLoading;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final days = splitIntoDays(points, geography: geography);
    if (days.isEmpty) {
      return _EmptyPane(
        icon: Icons.calendar_month,
        message: l10n.noTimestampsDaily,
      );
    }

    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(right: 8, top: 8),
      children: [
        Text(l10n.daysCountLabel(days.length), style: theme.textTheme.titleSmall),
        const SizedBox(height: 12),
        for (final day in days) ...[
          _DayCard(
            day: day,
            geoLoading: geoLoading,
            hasGeography: geography != null,
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.day,
    required this.geoLoading,
    required this.hasGeography,
  });

  final DayStats day;
  final bool geoLoading;
  final bool hasGeography;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final fmt = DateFormat(
      'd MMMM yyyy, EEEE',
      Localizations.localeOf(context).languageCode,
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: day.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${l10n.dayLabel(day.dayNumber)} · ${fmt.format(day.date)}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AnalysisStatGrid(
            children: [
              AnalysisStatCard(
                icon: Icons.schedule,
                label: l10n.ridingDuration,
                value: day.ridingDuration == null
                    ? '—'
                    : formatAnalysisDuration(l10n, day.ridingDuration!),
              ),
              AnalysisStatCard(
                icon: Icons.straighten,
                label: l10n.distance,
                value: '${day.distanceKm.toStringAsFixed(0)} km',
              ),
              AnalysisStatCard(
                icon: Icons.hotel,
                label: l10n.rest,
                value: day.restDuration == Duration.zero
                    ? '—'
                    : formatAnalysisDuration(l10n, day.restDuration),
              ),
              AnalysisStatCard(
                icon: Icons.arrow_upward,
                label: l10n.maxAltitude,
                value: day.maxElevation == null
                    ? '—'
                    : '${day.maxElevation!.round()} m',
              ),
              AnalysisStatCard(
                icon: Icons.trending_up,
                label: l10n.climb,
                value: '${day.elevationGainM.round()} m',
              ),
            ],
          ),
          if (day.countries.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in day.countries)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(c, style: theme.textTheme.bodySmall),
                  ),
              ],
            ),
          ] else if (geoLoading) ...[
            const SizedBox(height: 8),
            Text(l10n.countriesCalculating, style: theme.textTheme.bodySmall),
          ] else if (!hasGeography) ...[
            const SizedBox(height: 8),
            Text(
              l10n.countriesNeedRouteTab,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Shared UI ──────────────────────────────────────────────────────────────

/// The last GPS point that has elevation data - "where the ride's altitude
/// reading ended up", as opposed to a route's max/min elevation which are
/// the extremes across the whole track.
double? lastAltitudeOf(List<TrackPoint> points) {
  for (final p in points.reversed) {
    if (p.elevation != null) return p.elevation;
  }
  return null;
}

String formatAnalysisDuration(AppLocalizations l10n, Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) return l10n.durationHoursMinutes(h, m);
  if (m > 0) return l10n.durationMinutesSeconds(m, s);
  return l10n.durationSeconds(s);
}

class AnalysisSectionTitle extends StatelessWidget {
  const AnalysisSectionTitle({
    super.key,
    required this.icon,
    required this.title,
  });

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
    super.key,
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
        Text(
          label,
          style: theme.textTheme.bodySmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        // FittedBox scales the value+unit down to fit this column's width
        // instead of letting a long value (e.g. "11 sa 47 dk") wrap onto a
        // second line mid-word, which is what a plain Wrap did here before.
        Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
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
          ),
        ),
      ],
    );
  }
}

class AnalysisStatCard extends StatelessWidget {
  const AnalysisStatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.accentColor,
    this.large = false,
  });

  final IconData icon;
  final String label;
  final String value;

  /// Optional per-card accent - tints the background and icon instead of
  /// the plain neutral default, so a grid of many cards (e.g.
  /// RecordScreen's info page) can read as distinct stats at a glance
  /// rather than a wall of identical gray tiles.
  final Color? accentColor;

  /// When true, the value reads at the same size/weight as
  /// [RecordScreen]'s duration tiles above it, instead of the compact
  /// titleSmall used by the Analysis sheet's own denser grids - readable at
  /// a glance while riding was the whole point of enlarging it. Off by
  /// default so the Analysis sheet's existing tabs are unaffected.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = accentColor;
    // Icon color/size are a user-wide choice (Settings > icon look) rather
    // than decided per card here - previously every card picked its own
    // icon color (accent or theme primary), which read as arbitrary to
    // riders who wanted a say in it.
    final iconSettings = context.watch<StatIconSettingsController>();
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 8 : 12, vertical: large ? 8 : 8),
      decoration: BoxDecoration(
        color: accent == null
            ? theme.colorScheme.surfaceContainerHighest
            : accent.withValues(alpha: theme.brightness == Brightness.dark ? 0.20 : 0.12),
        borderRadius: BorderRadius.circular(14),
        border: accent == null
            ? null
            : Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: large
          // The record screen's live info page now gives each card a
          // generous, screen-filling slot (see RecordScreen's stat grid) -
          // a fixed small font would just leave that space mostly empty.
          // FittedBox scales the icon+text block (at its natural size) up
          // or down to exactly fill whatever box the card ends up with, so
          // a card that gets taller/wider genuinely reads bigger instead of
          // padding out around unchanged text. No maxLines/ellipsis here -
          // FittedBox lays the text out at its natural width first, so a
          // long value just scales the whole block down a bit instead of
          // clipping mid-word.
          ? Center(
              child: FittedBox(
                fit: BoxFit.contain,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      color: iconSettings.color,
                      size: 22 * iconSettings.sizeScale,
                    ),
                    const SizedBox(width: 10),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          label,
                          style: theme.textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          value,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
          : Row(
              children: [
                Icon(
                  icon,
                  color: iconSettings.color,
                  size: 20 * iconSettings.sizeScale,
                ),
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
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
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
  const AnalysisStatGrid({
    super.key,
    required this.children,
    this.childAspectRatio = 2.5,
  });

  final List<Widget> children;
  final double childAspectRatio;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: childAspectRatio,
      children: children,
    );
  }
}

class AnalysisElevationChart extends StatelessWidget {
  const AnalysisElevationChart({
    super.key,
    required this.samples,
    this.showPeakMarkers = false,
    this.lineColor,
  });

  final List<ElevationSample> samples;

  /// When true, permanently marks the highest and lowest points reached
  /// with a dot and a small floating "N m" label, instead of only showing
  /// on touch - used by [RecordScreen]'s live info page so the extremes
  /// stay visible on the chart itself as the ride goes on, without needing
  /// to tap it. Off by default so the existing Analysis-sheet elevation tab
  /// keeps its plain touch-to-inspect behavior.
  final bool showPeakMarkers;

  /// Overrides the line/dot/fill color, which otherwise defaults to
  /// [ThemeData.colorScheme.primary] - used by [RecordScreen]'s info page so
  /// this chart matches its own blue accent instead of the app's (reddish)
  /// theme primary. The Analysis sheet's own elevation tab leaves this null.
  final Color? lineColor;

  @override
  Widget build(BuildContext context) {
    final minY = samples
        .map((s) => s.elevation)
        .reduce((a, b) => a < b ? a : b);
    final maxY = samples
        .map((s) => s.elevation)
        .reduce((a, b) => a > b ? a : b);
    final maxX = samples.last.distanceKm;
    final theme = Theme.of(context);
    final color = lineColor ?? theme.colorScheme.primary;

    final spots = [
      for (final s in samples) FlSpot(s.distanceKm, s.elevation),
    ];
    var maxIndex = 0;
    var minIndex = 0;
    for (var i = 1; i < spots.length; i++) {
      if (spots[i].y > spots[maxIndex].y) maxIndex = i;
      if (spots[i].y < spots[minIndex].y) minIndex = i;
    }
    final maxSpot = spots[maxIndex];
    final minSpot = spots[minIndex];

    final barData = LineChartBarData(
      spots: spots,
      isCurved: true,
      barWidth: 2,
      color: color,
      dotData: FlDotData(
        show: showPeakMarkers,
        checkToShowDot: (spot, bar) => spot == maxSpot || spot == minSpot,
        getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
          radius: 4,
          color: color,
          strokeWidth: 2,
          strokeColor: theme.colorScheme.surface,
        ),
      ),
      belowBarData: BarAreaData(
        show: true,
        color: color.withValues(alpha: 0.15),
      ),
    );

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
        lineTouchData: LineTouchData(
          enabled: !showPeakMarkers,
          touchTooltipData: LineTouchTooltipData(
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 3,
            ),
            tooltipMargin: 8,
            getTooltipColor: (_) => color.withValues(alpha: 0.92),
            getTooltipItems: (touchedSpots) => touchedSpots
                .map(
                  (s) => LineTooltipItem(
                    '${s.y.round()} m',
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        showingTooltipIndicators: !showPeakMarkers
            ? const []
            : [
                ShowingTooltipIndicators([LineBarSpot(barData, 0, maxSpot)]),
                if (minSpot != maxSpot)
                  ShowingTooltipIndicators([
                    LineBarSpot(barData, 0, minSpot),
                  ]),
              ],
        lineBarsData: [barData],
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
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: Text(l10n.retry)),
          ],
        ),
      ),
    );
  }
}

class _EmptyPane extends StatelessWidget {
  const _EmptyPane({required this.icon, required this.message, this.onRetry});

  final IconData icon;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
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
              FilledButton(onPressed: onRetry, child: Text(l10n.retry)),
            ],
          ],
        ),
      ),
    );
  }
}
