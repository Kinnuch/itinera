import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../../data/models/enums.dart';
import '../../data/models/location.dart';
import 'map_provider.dart';
import 'tile_sources.dart';

/// Mapbox。境外行程用它：全球覆盖、原生 WGS-84，不需要坐标偏移。
class MapboxProvider implements MapProvider {
  MapboxProvider({required this.token, http.Client? client})
      : _client = client ?? http.Client();

  final String? token;
  final http.Client _client;

  static const _host = 'api.mapbox.com';

  @override
  String get id => 'mapbox';

  @override
  String get displayName => 'Mapbox';

  @override
  bool get isConfigured => token != null && token!.isNotEmpty;

  @override
  TileSource get tileSource =>
      isConfigured ? BaseMaps.mapbox(token!) : BaseMaps.osm;

  @override
  Future<List<GeoPlace>> searchPlaces(String keyword, {LatLng? near}) async {
    if (!isConfigured || keyword.trim().isEmpty) return const [];
    final uri = Uri.https(_host, '/geocoding/v5/mapbox.places/${Uri.encodeComponent(keyword)}.json', {
      'access_token': token!,
      'limit': '10',
      'language': 'zh-Hans,en',
      if (near != null) 'proximity': '${near.longitude},${near.latitude}',
    });
    final json = await _getJson(uri);
    final features = (json?['features'] as List?) ?? const [];
    return features.whereType<Map<String, dynamic>>().map((f) {
      final center = (f['center'] as List?)?.cast<num>();
      return GeoPlace(
        name: '${f['text'] ?? f['place_name'] ?? ''}',
        address: f['place_name'] as String?,
        latitude: center != null && center.length == 2 ? center[1].toDouble() : null,
        longitude: center != null && center.length == 2 ? center[0].toDouble() : null,
        providerPoiId: f['id'] as String?,
        provider: id,
      );
    }).where((p) => p.name.isNotEmpty).toList();
  }

  @override
  Future<GeoPlace?> reverseGeocode(LatLng point) async {
    if (!isConfigured) return null;
    final uri = Uri.https(
      _host,
      '/geocoding/v5/mapbox.places/${point.longitude},${point.latitude}.json',
      {'access_token': token!, 'limit': '1', 'language': 'zh-Hans,en'},
    );
    final json = await _getJson(uri);
    final features = (json?['features'] as List?) ?? const [];
    if (features.isEmpty) return null;
    final f = features.first as Map<String, dynamic>;
    final label = (f['place_name'] as String?) ?? '地图选点';
    return GeoPlace(
      name: label,
      address: label,
      latitude: point.latitude,
      longitude: point.longitude,
      provider: id,
    );
  }

  @override
  Future<RouteLegGeometry?> route(LatLng from, LatLng to, TransportMode mode) async {
    if (!isConfigured) return null;
    final profile = _profileFor(mode);
    if (profile == null) return null;
    final coords = '${from.longitude},${from.latitude};${to.longitude},${to.latitude}';
    final uri = Uri.https(_host, '/directions/v5/mapbox/$profile/$coords', {
      'access_token': token!,
      'geometries': 'polyline6',
      'overview': 'full',
    });
    final json = await _getJson(uri);
    final routes = (json?['routes'] as List?) ?? const [];
    if (routes.isEmpty) return null;
    final best = routes.first as Map<String, dynamic>;
    final geometry = best['geometry'];
    if (geometry is! String) return null;
    return RouteLegGeometry(
      points: GeoUtils.decodePolyline(geometry, precision: 6),
      distanceMeters: (best['distance'] as num?)?.toDouble() ?? 0,
      durationSeconds: ((best['duration'] as num?) ?? 0).round(),
    );
  }

  /// Mapbox Directions 只有三种 profile；轨道与航空交给直线兜底。
  String? _profileFor(TransportMode mode) {
    switch (mode) {
      case TransportMode.walk:
        return 'walking';
      case TransportMode.bike:
        return 'cycling';
      case TransportMode.drive:
      case TransportMode.taxi:
      case TransportMode.coach:
        return 'driving-traffic';
      case TransportMode.transit:
      case TransportMode.train:
      case TransportMode.ferry:
      case TransportMode.flight:
        return null;
    }
  }

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
