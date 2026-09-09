import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// 坐标系。国内地图服务（高德/腾讯）用 GCJ-02，国际服务（Mapbox/OSM/GPS）用 WGS-84。
/// 全库内部一律以 WGS-84 存储，只在调用国内服务商的边界上转换。
enum GeoDatum { wgs84, gcj02 }

class GeoUtils {
  GeoUtils._();

  static const double _a = 6378245.0; // 克拉索夫斯基椭球长半轴
  static const double _ee = 0.00669342162296594323; // 偏心率平方

  static const Distance _distance = Distance();

  /// 两点大圆距离（米）。
  static double distanceMeters(LatLng a, LatLng b) => _distance.as(LengthUnit.Meter, a, b);

  /// 一串点的累计距离（米）。
  static double pathLengthMeters(List<LatLng> points) {
    var sum = 0.0;
    for (var i = 1; i < points.length; i++) {
      sum += distanceMeters(points[i - 1], points[i]);
    }
    return sum;
  }

  /// 中国大陆范围外的坐标不做偏移（GCJ-02 只在境内生效）。
  static bool outOfChina(LatLng p) {
    if (p.longitude < 72.004 || p.longitude > 137.8347) return true;
    if (p.latitude < 0.8293 || p.latitude > 55.8271) return true;
    return false;
  }

  static LatLng wgs84ToGcj02(LatLng p) {
    if (outOfChina(p)) return p;
    final d = _offset(p);
    return LatLng(p.latitude + d.latitude, p.longitude + d.longitude);
  }

  static LatLng gcj02ToWgs84(LatLng p) {
    if (outOfChina(p)) return p;
    // 偏移函数不可逆，用一次迭代反解（误差 < 1m，足够行程规划使用）。
    final d = _offset(p);
    final rough = LatLng(p.latitude - d.latitude, p.longitude - d.longitude);
    final d2 = _offset(rough);
    return LatLng(p.latitude - d2.latitude, p.longitude - d2.longitude);
  }

  static LatLng _offset(LatLng p) {
    final dLat = _transformLat(p.longitude - 105.0, p.latitude - 35.0);
    final dLon = _transformLon(p.longitude - 105.0, p.latitude - 35.0);
    final radLat = p.latitude / 180.0 * math.pi;
    var magic = math.sin(radLat);
    magic = 1 - _ee * magic * magic;
    final sqrtMagic = math.sqrt(magic);
    return LatLng(
      (dLat * 180.0) / ((_a * (1 - _ee)) / (magic * sqrtMagic) * math.pi),
      (dLon * 180.0) / (_a / sqrtMagic * math.cos(radLat) * math.pi),
    );
  }

  static double _transformLat(double x, double y) {
    var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * math.sqrt(x.abs());
    ret += (20.0 * math.sin(6.0 * x * math.pi) + 20.0 * math.sin(2.0 * x * math.pi)) * 2.0 / 3.0;
    ret += (20.0 * math.sin(y * math.pi) + 40.0 * math.sin(y / 3.0 * math.pi)) * 2.0 / 3.0;
    ret += (160.0 * math.sin(y / 12.0 * math.pi) + 320 * math.sin(y * math.pi / 30.0)) * 2.0 / 3.0;
    return ret;
  }

  static double _transformLon(double x, double y) {
    var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * math.sqrt(x.abs());
    ret += (20.0 * math.sin(6.0 * x * math.pi) + 20.0 * math.sin(2.0 * x * math.pi)) * 2.0 / 3.0;
    ret += (20.0 * math.sin(x * math.pi) + 40.0 * math.sin(x / 3.0 * math.pi)) * 2.0 / 3.0;
    ret += (150.0 * math.sin(x / 12.0 * math.pi) + 300.0 * math.sin(x / 30.0 * math.pi)) * 2.0 / 3.0;
    return ret;
  }

  /// 包住所有点的最小矩形（含边距），用于地图自动缩放。
  /// 故意返回记录而不是 flutter_map 的 LatLngBounds：core 层不依赖 UI 包。
  static ({LatLng southWest, LatLng northEast})? boundsOf(
    Iterable<LatLng> points, {
    double paddingRatio = 0.15,
  }) {
    final list = points.toList();
    if (list.isEmpty) return null;
    var minLat = list.first.latitude, maxLat = list.first.latitude;
    var minLng = list.first.longitude, maxLng = list.first.longitude;
    for (final p in list) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    final padLat = math.max((maxLat - minLat) * paddingRatio, 0.005);
    final padLng = math.max((maxLng - minLng) * paddingRatio, 0.005);
    return (
      southWest: LatLng(minLat - padLat, minLng - padLng),
      northEast: LatLng(maxLat + padLat, maxLng + padLng),
    );
  }

  /// Google/高德 折线编码解码（Directions 返回的 geometry 常用此格式）。
  static List<LatLng> decodePolyline(String encoded, {int precision = 5}) {
    final points = <LatLng>[];
    final factor = math.pow(10, precision).toDouble();
    var index = 0, lat = 0, lng = 0;
    while (index < encoded.length) {
      int shift = 0, result = 0, b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      points.add(LatLng(lat / factor, lng / factor));
    }
    return points;
  }
}
