import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/geo.dart';
import '../../core/time_utils.dart';
import '../../domain/route/route_builder.dart';
import '../../providers/trip_providers.dart';
import '../../services/map/map_provider.dart';

/// 功能点 4：最终生成路径路线图。
///
/// 每天一种颜色，站点按当日顺序编号；真实导航几何画实线，
/// 直线估算画虚线，用户一眼能看出哪段是「估的」。
class RouteMapView extends ConsumerStatefulWidget {
  const RouteMapView({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<RouteMapView> createState() => _RouteMapViewState();
}

class _RouteMapViewState extends ConsumerState<RouteMapView> {
  final _mapController = MapController();
  final _captureKey = GlobalKey();

  /// null 表示显示全部日期。
  Set<String>? _visibleDates;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final routeAsync = ref.watch(tripRouteProvider(widget.tripId));
    final provider = ref.watch(tripMapProviderProvider(widget.tripId)).valueOrNull ??
        const OsmProvider();
    final adapter = MapDisplayAdapter(provider.tileSource.datum);

    return routeAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('生成路线失败：$error')),
      data: (route) {
        final visible = route.days
            .where((d) => _visibleDates == null || _visibleDates!.contains(d.date.toIso()))
            .where((d) => d.stops.isNotEmpty)
            .toList();

        if (route.days.every((d) => d.stops.isEmpty)) {
          return const _NoLocationState();
        }

        final allPoints = visible.expand((d) => d.allPoints).toList();
        final box = GeoUtils.boundsOf(adapter.toDisplayAll(allPoints));
        final bounds = box == null ? null : LatLngBounds(box.southWest, box.northEast);

        return Stack(
          children: [
            RepaintBoundary(
              key: _captureKey,
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCameraFit: bounds == null
                      ? null
                      : CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
                  initialCenter: bounds?.center ?? const LatLng(35.0116, 135.7681),
                  initialZoom: 12,
                ),
                children: [
                  TileLayer(
                    urlTemplate: provider.tileSource.urlTemplate,
                    subdomains: provider.tileSource.subdomains,
                    maxZoom: provider.tileSource.maxZoom,
                    userAgentPackageName: 'io.github.kinnuch.itinera',
                  ),
                  PolylineLayer(
                    polylines: [
                      for (final day in visible)
                        for (final leg in day.legs)
                          Polyline(
                            points: adapter.toDisplayAll(leg.geometry.points),
                            color: day.color.withValues(alpha: leg.isEstimated ? 0.45 : 0.85),
                            strokeWidth: leg.isEstimated ? 2.5 : 4,
                            // 估算段用点划线区分（flutter_map 的 pattern）
                            pattern: leg.isEstimated
                                ? StrokePattern.dotted()
                                : const StrokePattern.solid(),
                          ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      for (final day in visible)
                        for (final stop in day.stops)
                          Marker(
                            point: adapter.toDisplay(stop.point),
                            width: 30,
                            height: 30,
                            child: _StopPin(
                              color: day.color,
                              label: '${stop.sequence}',
                            ),
                          ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 8,
              child: _DayFilterBar(
                route: route,
                visibleDates: _visibleDates,
                onToggle: _toggleDate,
                onShowAll: () => setState(() => _visibleDates = null),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: _RouteSummaryCard(
                days: visible,
                attribution: provider.tileSource.attribution,
                onExport: _exportImage,
              ),
            ),
          ],
        );
      },
    );
  }

  void _toggleDate(DateOnly date) {
    setState(() {
      final key = date.toIso();
      final current = _visibleDates;
      if (current == null) {
        // 从「全部」切到单选：点哪天就只看哪天。
        _visibleDates = {key};
        return;
      }
      final next = Set<String>.from(current);
      next.contains(key) ? next.remove(key) : next.add(key);
      _visibleDates = next.isEmpty ? null : next;
    });
  }

  /// 把当前地图视图渲染成 PNG 并调起系统分享，用于发给同行的人。
  Future<void> _exportImage() async {
    try {
      final boundary =
          _captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;

      final dir = await getTemporaryDirectory();
      final file = await _writeBytes(
        '${dir.path}/itinera_route_${DateTime.now().millisecondsSinceEpoch}.png',
        bytes.buffer.asUint8List(),
      );
      await Share.shareXFiles([XFile(file)], text: '我的行程路线图');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出失败：$error')));
      }
    }
  }

  Future<String> _writeBytes(String path, Uint8List bytes) async {
    final file = await File(path).writeAsBytes(bytes);
    return file.path;
  }
}

class _DayFilterBar extends StatelessWidget {
  const _DayFilterBar({
    required this.route,
    required this.visibleDates,
    required this.onToggle,
    required this.onShowAll,
  });

  final TripRoute route;
  final Set<String>? visibleDates;
  final ValueChanged<DateOnly> onToggle;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _Pill(
            label: '全部',
            selected: visibleDates == null,
            color: Theme.of(context).colorScheme.primary,
            onTap: onShowAll,
          ),
          for (final day in route.days)
            if (day.stops.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: _Pill(
                  label: 'D${day.dayIndex}',
                  selected: visibleDates?.contains(day.date.toIso()) ?? false,
                  color: day.color,
                  onTap: () => onToggle(day.date),
                ),
              ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? color : scheme.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : scheme.outlineVariant),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _StopPin extends StatelessWidget {
  const _StopPin({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1))],
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RouteSummaryCard extends StatelessWidget {
  const _RouteSummaryCard({
    required this.days,
    required this.attribution,
    required this.onExport,
  });

  final List<DayRoute> days;
  final String attribution;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final distance = days.fold<double>(0, (sum, d) => sum + d.totalDistanceMeters);
    final minutes = days.fold<int>(0, (sum, d) => sum + d.totalTravelMinutes);
    final stops = days.fold<int>(0, (sum, d) => sum + d.stops.length);
    final hasEstimated = days.any((d) => d.hasEstimatedLegs);

    return Card(
      color: scheme.surface.withValues(alpha: 0.95),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$stops 个站点 · 约 ${(distance / 1000).toStringAsFixed(1)} 公里 · '
                    '在途 ${TimeUtils.formatDuration(minutes)}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.ios_share),
                  tooltip: '导出图片',
                  onPressed: onExport,
                ),
              ],
            ),
            if (hasEstimated)
              Text(
                '虚线为直线估算（该段没有可用的导航数据）',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            Text(attribution, style: TextStyle(fontSize: 10, color: scheme.outline)),
          ],
        ),
      ),
    );
  }
}

class _NoLocationState extends StatelessWidget {
  const _NoLocationState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wrong_location_outlined, size: 48, color: scheme.outline),
            const SizedBox(height: 12),
            Text('还画不出路线', style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            Text(
              '给安排里的酒店、景点、餐厅选上位置后，\n这里会自动按天连成路线图。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: scheme.outline, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
