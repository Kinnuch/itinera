import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../../data/models/enums.dart';
import '../../data/models/location.dart';
import 'map_provider.dart';
import 'tile_sources.dart';

/// 高德 Web 服务 API。境内 POI、公交换乘、路况都比国际服务商准。
/// 高德全程使用 GCJ-02，进出本类时统一与 WGS-84 互转。
class AmapProvider implements MapProvider {
  AmapProvider({required this.webKey, http.Client? client})
      : _client = client ?? http.Client();

  final String? webKey;
  final http.Client _client;

  static const _host = 'restapi.amap.com';

  @override
  String get id => 'amap';

  @override
  String get displayName => '高德地图';

  @override
  bool get isConfigured => webKey != null && webKey!.isNotEmpty;

  @override
  TileSource get tileSource => BaseMaps.amap;

  @override
  Future<List<GeoPlace>> searchPlaces(String keyword, {LatLng? near}) async {
    if (!isConfigured || keyword.trim().isEmpty) return const [];
    final gcjNear = near == null ? null : GeoUtils.wgs84ToGcj02(near);
    final uri = Uri.https(_host, '/v3/place/text', {
      'key': webKey!,
      'keywords': keyword,
      'offset': '20',
      'page': '1',
      'extensions': 'base',
      if (gcjNear != null) 'location': _lngLat(gcjNear),
    });
    final json = await _getJson(uri);
    if (json == null || json['status'] != '1') return const [];
    final pois = (json['pois'] as List?) ?? const [];
    return pois
        .whereType<Map<String, dynamic>>()
        .map(_placeFromPoi)
        .whereType<GeoPlace>()
        .toList();
  }

  @override
  Future<GeoPlace?> reverseGeocode(LatLng point) async {
    if (!isConfigured) return null;
    final gcj = GeoUtils.wgs84ToGcj02(point);
    final uri = Uri.https(_host, '/v3/geocode/regeo', {
      'key': webKey!,
      'location': _lngLat(gcj),
      'extensions': 'base',
    });
    final json = await _getJson(uri);
    if (json == null || json['status'] != '1') return null;
    final regeo = json['regeocode'] as Map<String, dynamic>?;
    final address = _stringOrNull(regeo?['formatted_address']);
    return GeoPlace(
      name: address ?? '地图选点',
      address: address,
      latitude: point.latitude,
      longitude: point.longitude,
      provider: id,
    );
  }

  @override
  Future<RouteLegGeometry?> route(LatLng from, LatLng to, TransportMode mode) async {
    if (!isConfigured) return null;
    final path = _pathFor(mode);
    if (path == null) return null;

    final isTransit = path.contains('transit');
    final params = <String, String>{
      'key': webKey!,
      'origin': _lngLat(GeoUtils.wgs84ToGcj02(from)),
      'destination': _lngLat(GeoUtils.wgs84ToGcj02(to)),
      if (isTransit) 'city': '全国',
      if (isTransit) 'cityd': '全国',
    };
    final json = await _getJson(Uri.https(_host, path, params));
    if (json == null || json['status'] != '1') return null;

    final route = json['route'] as Map<String, dynamic>?;
    final plans = (route?['paths'] ?? route?['transits']) as List?;
    if (plans == null || plans.isEmpty) return null;
    final best = plans.first as Map<String, dynamic>;

    final points = <LatLng>[];
    for (final step in _stepsOf(best)) {
      points.addAll(_parsePolyline(_stringOrNull(step['polyline'])));
    }
    if (points.isEmpty) return null;

    return RouteLegGeometry(
      points: points.map(GeoUtils.gcj02ToWgs84).toList(),
      distanceMeters: double.tryParse('${best['distance']}') ?? 0,
      durationSeconds: int.tryParse('${best['duration']}') ?? 0,
    );
  }

  /// 驾车/步行方案的几何在 steps 里；公交方案埋在 segments 的 walking 和 bus.buslines 下。
  Iterable<Map<String, dynamic>> _stepsOf(Map<String, dynamic> plan) sync* {
    final steps = plan['steps'] as List?;
    if (steps != null) {
      yield* steps.whereType<Map<String, dynamic>>();
      return;
    }
    for (final seg in (plan['segments'] as List? ?? const []).whereType<Map<String, dynamic>>()) {
      final walking = seg['walking'];
      if (walking is Map<String, dynamic>) {
        yield* (walking['steps'] as List? ?? const []).whereType<Map<String, dynamic>>();
      }
      final bus = seg['bus'];
      if (bus is Map<String, dynamic>) {
        yield* (bus['buslines'] as List? ?? const []).whereType<Map<String, dynamic>>();
      }
    }
  }

  String? _pathFor(TransportMode mode) {
    switch (mode) {
      case TransportMode.walk:
        return '/v3/direction/walking';
      case TransportMode.bike:
        return '/v4/direction/bicycling';
      case TransportMode.transit:
        return '/v3/direction/transit/integrated';
      case TransportMode.drive:
      case TransportMode.taxi:
        return '/v3/direction/driving';
      case TransportMode.coach:
      case TransportMode.train:
      case TransportMode.ferry:
      case TransportMode.flight:
        // 城际班次没有逐路段几何，交给直线兜底。
        return null;
    }
  }

  /// 高德的 polyline 是 "lng,lat;lng,lat" 明文串，不是 Google 折线编码。
  List<LatLng> _parsePolyline(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    return raw
        .split(';')
        .map((pair) {
          final parts = pair.split(',');
          if (parts.length != 2) return null;
          final lng = double.tryParse(parts[0]);
          final lat = double.tryParse(parts[1]);
          return (lat == null || lng == null) ? null : LatLng(lat, lng);
        })
        .whereType<LatLng>()
        .toList();
  }

  GeoPlace? _placeFromPoi(Map<String, dynamic> poi) {
    final location = _stringOrNull(poi['location']);
    if (location == null) return null;
    final parts = location.split(',');
    if (parts.length != 2) return null;
    final lng = double.tryParse(parts[0]);
    final lat = double.tryParse(parts[1]);
    if (lat == null || lng == null) return null;
    final wgs = GeoUtils.gcj02ToWgs84(LatLng(lat, lng));
    return GeoPlace(
      name: _stringOrNull(poi['name']) ?? '未命名地点',
      address: _stringOrNull(poi['address']),
      latitude: wgs.latitude,
      longitude: wgs.longitude,
      providerPoiId: _stringOrNull(poi['id']),
      provider: id,
    );
  }

  String _lngLat(LatLng p) =>
      '${p.longitude.toStringAsFixed(6)},${p.latitude.toStringAsFixed(6)}';

  /// 高德对空字段返回空数组 `[]` 而非 null，直接 `as String` 会抛类型错误。
  String? _stringOrNull(Object? value) =>
      (value is String && value.isNotEmpty) ? value : null;

  Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    try {
      final res = await _client.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
