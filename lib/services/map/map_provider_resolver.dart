import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../../data/models/plan_item.dart';
import '../../data/repositories/settings_repository.dart';
import 'amap_provider.dart';
import 'map_provider.dart';
import 'mapbox_provider.dart';
import 'tile_sources.dart';

/// 按行程的地理位置选服务商：境内走高德，境外走 Mapbox，密钥缺失时逐级降级。
///
/// 判定依据是「行程里已有坐标的条目有多少落在中国大陆范围内」——
/// 用条目而不是用手机定位，因为在家规划出境游时手机还在国内。
class MapProviderResolver {
  MapProviderResolver(this.settings);

  final AppSettings settings;

  /// 底图。与搜索/导航服务商分开解析：高德瓦片无需密钥，
  /// 所以「没配 Key」绝不该把底图也退回国内很慢的 OSM。
  TileSource baseMapForItems(Iterable<PlanItem> items) {
    if (settings.baseMap != BaseMapChoice.auto) {
      return BaseMaps.resolve(settings.baseMap, mapboxToken: settings.mapboxToken);
    }
    return BaseMaps.resolveAuto(
      domestic: _isDomestic(_pointsOf(items)),
      mapboxToken: settings.mapboxToken,
    );
  }

  /// 行程还没有任何坐标时按境内处理：这是最快且无需密钥的选择，
  /// 用户一旦加了境外地点，auto 会自己切过去。
  bool _isDomestic(List<LatLng> points) {
    if (points.isEmpty) return true;
    final inChina = points.where((p) => !GeoUtils.outOfChina(p)).length;
    return inChina * 2 >= points.length;
  }

  List<LatLng> _pointsOf(Iterable<PlanItem> items) => items
      .map((i) => i.anchorPlace?.latLng ?? i.originPlace?.latLng)
      .whereType<LatLng>()
      .toList();

  MapProvider forItems(Iterable<PlanItem> items) => forPoints(_pointsOf(items));

  MapProvider forPoints(List<LatLng> points) {
    if (points.isEmpty) return _preferred();
    // 半数以上在境内即按境内处理
    return _isDomestic(points) ? _amapOrFallback() : _mapboxOrFallback();
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
