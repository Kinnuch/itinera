import 'dart:ui' show Color;

import 'package:latlong2/latlong.dart';

import '../../core/time_utils.dart';
import '../../data/models/enums.dart';
import '../../data/models/plan_item.dart';
import '../../data/models/trip.dart';
import '../../services/map/map_provider.dart';
import '../../services/map/routing_service.dart';

/// 路线图上的一个停靠点。
class RouteStop {
  const RouteStop({
    required this.item,
    required this.point,
    required this.sequence,
  });

  final PlanItem item;
  final LatLng point;

  /// 当天的第几站，画在标记里。
  final int sequence;
}

/// 相邻两站之间的一段路。
class RouteLeg {
  const RouteLeg({
    required this.from,
    required this.to,
    required this.mode,
    required this.geometry,
  });

  final RouteStop from;
  final RouteStop to;
  final TransportMode mode;
  final RouteLegGeometry geometry;

  bool get isEstimated => geometry.isEstimated;
}

/// 某一天的完整路线。
class DayRoute {
  const DayRoute({
    required this.date,
    required this.dayIndex,
    required this.color,
    required this.stops,
    required this.legs,
  });

  final DateOnly date;
  final int dayIndex;
  final Color color;
  final List<RouteStop> stops;
  final List<RouteLeg> legs;

  double get totalDistanceMeters =>
      legs.fold(0.0, (sum, leg) => sum + leg.geometry.distanceMeters);

  int get totalTravelMinutes =>
      legs.fold(0, (sum, leg) => sum + leg.geometry.durationMinutes);

  bool get hasEstimatedLegs => legs.any((l) => l.isEstimated);

  List<LatLng> get allPoints => [
        for (final leg in legs) ...leg.geometry.points,
        for (final stop in stops) stop.point,
      ];
}

/// 整趟行程的路线图数据。
class TripRoute {
  const TripRoute({required this.days});

  final List<DayRoute> days;

  List<LatLng> get allPoints => [for (final d in days) ...d.allPoints];

  double get totalDistanceMeters =>
      days.fold(0.0, (sum, d) => sum + d.totalDistanceMeters);

  int get totalTravelMinutes => days.fold(0, (sum, d) => sum + d.totalTravelMinutes);

  DayRoute? dayOf(DateOnly date) {
    for (final d in days) {
      if (d.date == date) return d;
    }
    return null;
  }
}

/// 把行程条目编译成可绘制的路线。
///
/// 每天一种颜色；每段路优先取真实导航几何，拿不到就退回直线（UI 画虚线区分）。
class RouteBuilder {
  RouteBuilder({required this.provider, RoutingService? routing})
      : _routing = routing ?? RoutingService();

  final MapProvider provider;
  final RoutingService _routing;

  /// 日程配色。超过 10 天后循环使用，同色不相邻。
  static const List<Color> dayPalette = [
    Color(0xFF1E88E5),
    Color(0xFFE53935),
    Color(0xFF43A047),
    Color(0xFF8E24AA),
    Color(0xFFFB8C00),
    Color(0xFF00ACC1),
    Color(0xFFD81B60),
    Color(0xFF3949AB),
    Color(0xFF7CB342),
    Color(0xFF6D4C41),
  ];

  static Color colorForDay(int dayIndex) => dayPalette[(dayIndex - 1) % dayPalette.length];

  Future<TripRoute> build({
    required Trip trip,
    required List<PlanItem> items,
    Set<DateOnly>? onlyDates,
  }) async {
    final byDate = <String, List<PlanItem>>{};
    for (final item in items) {
      byDate.putIfAbsent(item.date.toIso(), () => []).add(item);
    }

    final days = <DayRoute>[];
    for (var i = 0; i < trip.dates.length; i++) {
      final date = trip.dates[i];
      if (onlyDates != null && !onlyDates.contains(date)) continue;

      final dayItems = (byDate[date.toIso()] ?? const <PlanItem>[]).toList()
        ..sort((a, b) => a.timelineKey.compareTo(b.timelineKey));

      final stops = <RouteStop>[];
      for (final item in dayItems) {
        final point = item.anchorPlace?.latLng;
        if (point == null) continue;
        // 连续两项在同一位置（酒店退房 + 早餐在酒店）不重复打点。
        if (stops.isNotEmpty && _sameSpot(stops.last.point, point)) continue;
        stops.add(RouteStop(item: item, point: point, sequence: stops.length + 1));
      }

      final legs = <RouteLeg>[];
      for (var s = 0; s < stops.length - 1; s++) {
        final from = stops[s];
        final to = stops[s + 1];
        final mode = _modeBetween(from.item, to.item);
        final geometry = await _routing.leg(
          provider: provider,
          from: from.point,
          to: to.point,
          mode: mode,
        );
        legs.add(RouteLeg(from: from, to: to, mode: mode, geometry: geometry));
      }

      days.add(DayRoute(
        date: date,
        dayIndex: i + 1,
        color: colorForDay(i + 1),
        stops: stops,
        legs: legs,
      ));
    }

    return TripRoute(days: days);
  }

  /// 用户显式排了交通条目就用它声明的方式，否则按距离推断。
  TransportMode _modeBetween(PlanItem from, PlanItem to) {
    if (to.isTransport && to.transportMode != null) return to.transportMode!;
    if (from.isTransport && from.transportMode != null) return from.transportMode!;
    final a = from.anchorPlace?.latLng;
    final b = to.anchorPlace?.latLng;
    if (a == null || b == null) return TransportMode.transit;
    return TransportMode.inferFromDistance(
      const Distance().as(LengthUnit.Meter, a, b),
    );
  }

  bool _sameSpot(LatLng a, LatLng b) =>
      const Distance().as(LengthUnit.Meter, a, b) < 50;
}
