import 'package:latlong2/latlong.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/geo.dart';
import '../../data/db/database.dart';
import '../../data/models/enums.dart';
import 'map_provider.dart';

/// 在 [MapProvider] 之上加一层缓存与降级：
/// 1. 先查本地缓存（同一段路反复打开地图不该反复计费）；
/// 2. 再问服务商；
/// 3. 都拿不到就返回直线估算，保证路线图永远画得出来。
class RoutingService {
  RoutingService({AppDatabase? db}) : _db = db ?? AppDatabase.instance;

  final AppDatabase _db;

  /// 缓存有效期：路网变化慢，但限时票价/施工会变，两周足够。
  static const Duration _ttl = Duration(days: 14);

  Future<RouteLegGeometry> leg({
    required MapProvider provider,
    required LatLng from,
    required LatLng to,
    required TransportMode mode,
  }) async {
    // 起讫点几乎重合时不必问服务商。
    if (GeoUtils.distanceMeters(from, to) < 30) {
      return RouteLegGeometry(
        points: [from, to],
        distanceMeters: 0,
        durationSeconds: 0,
        isEstimated: true,
      );
    }

    final key = _cacheKey(provider.id, from, to, mode);
    final cached = await _readCache(key);
    if (cached != null) return cached;

    final fetched = await provider.route(from, to, mode);
    if (fetched != null) {
      await _writeCache(key, fetched);
      return fetched;
    }
    return RouteLegGeometry.straightLine(from, to, mode);
  }

  String _cacheKey(String providerId, LatLng from, LatLng to, TransportMode mode) {
    String fmt(LatLng p) =>
        '${p.latitude.toStringAsFixed(4)},${p.longitude.toStringAsFixed(4)}';
    return '$providerId|${mode.name}|${fmt(from)}|${fmt(to)}';
  }

  Future<RouteLegGeometry?> _readCache(String key) async {
    final db = await _db.database;
    final rows = await db.query(
      'route_cache',
      where: 'cache_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final fetchedAt = DateTime.tryParse(row['fetched_at'] as String? ?? '');
    if (fetchedAt == null || DateTime.now().difference(fetchedAt) > _ttl) {
      await db.delete('route_cache', where: 'cache_key = ?', whereArgs: [key]);
      return null;
    }
    return RouteLegGeometry(
      points: GeoUtils.decodePolyline(row['polyline'] as String, precision: 6),
      distanceMeters: (row['distance_m'] as num).toDouble(),
      durationSeconds: row['duration_s'] as int,
    );
  }

  Future<void> _writeCache(String key, RouteLegGeometry leg) async {
    final db = await _db.database;
    await db.insert(
      'route_cache',
      {
        'cache_key': key,
        'polyline': _encodePolyline(leg.points, precision: 6),
        'distance_m': leg.distanceMeters,
        'duration_s': leg.durationSeconds,
        'fetched_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 折线编码（与 GeoUtils.decodePolyline 对应），把上百个点压成一个字符串再入库。
  static String _encodePolyline(List<LatLng> points, {int precision = 6}) {
    var factor = 1;
    for (var i = 0; i < precision; i++) {
      factor *= 10;
    }
    final buffer = StringBuffer();
    var prevLat = 0, prevLng = 0;
    for (final p in points) {
      final lat = (p.latitude * factor).round();
      final lng = (p.longitude * factor).round();
      _encodeValue(lat - prevLat, buffer);
      _encodeValue(lng - prevLng, buffer);
      prevLat = lat;
      prevLng = lng;
    }
    return buffer.toString();
  }

  static void _encodeValue(int value, StringBuffer buffer) {
    var v = value < 0 ? ~(value << 1) : (value << 1);
    while (v >= 0x20) {
      buffer.writeCharCode((0x20 | (v & 0x1f)) + 63);
      v >>= 5;
    }
    buffer.writeCharCode(v + 63);
  }
}
