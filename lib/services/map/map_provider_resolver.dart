import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../../data/models/plan_item.dart';
import '../../data/repositories/settings_repository.dart';
import 'amap_provider.dart';
import 'map_provider.dart';
import 'mapbox_provider.dart';

/// 按行程的地理位置选服务商：境内走高德，境外走 Mapbox，密钥缺失时逐级降级。
///
/// 判定依据是「行程里已有坐标的条目有多少落在中国大陆范围内」——
/// 用条目而不是用手机定位，因为在家规划出境游时手机还在国内。
class MapProviderResolver {
  MapProviderResolver(this.settings);

  final AppSettings settings;

  MapProvider forItems(Iterable<PlanItem> items) {
    final points = items
        .map((i) => i.anchorPlace?.latLng ?? i.originPlace?.latLng)
        .whereType<LatLng>()
        .toList();
    return forPoints(points);
  }

  MapProvider forPoints(List<LatLng> points) {
    if (points.isEmpty) return _preferred();
    final inChina = points.where((p) => !GeoUtils.outOfChina(p)).length;
    final domestic = inChina * 2 >= points.length; // 半数以上在境内即按境内处理
    return domestic ? _amapOrFallback() : _mapboxOrFallback();
  }

  MapProvider get amap => AmapProvider(webKey: settings.amapWebKey);

  MapProvider get mapbox => MapboxProvider(token: settings.mapboxToken);

  /// 还没有任何坐标时（刚建的空行程），优先用已配置的那一个。
  MapProvider _preferred() {
    final a = amap;
    if (a.isConfigured) return a;
    final m = mapbox;
    if (m.isConfigured) return m;
    return const OsmProvider();
  }

  MapProvider _amapOrFallback() {
    final a = amap;
    if (a.isConfigured) return a;
    final m = mapbox;
    return m.isConfigured ? m : const OsmProvider();
  }

  MapProvider _mapboxOrFallback() {
    final m = mapbox;
    if (m.isConfigured) return m;
    final a = amap;
    return a.isConfigured ? a : const OsmProvider();
  }
}
