import '../../core/geo.dart';
import 'map_provider.dart';

/// 底图选择。
///
/// 底图和「搜索/导航服务商」是两件事，这里刻意分开：
/// 高德的瓦片服务**不需要任何密钥**，而它的 POI 搜索、逆地理、路径规划需要。
/// 早先把两者绑在一起，导致没填 Key 的用户连底图都被退回 OpenStreetMap ——
/// OSM 官方瓦片在国内实测 2.5 秒一张，高德 0.06 秒，差 40 倍。
enum BaseMapChoice {
  auto('自动', '按行程所在地区自动选择'),
  amap('高德地图', '国内快，无需密钥'),
  amapSatellite('高德卫星', '卫星影像 + 路网注记，无需密钥'),
  mapbox('Mapbox', '全球覆盖，需要 Access Token'),
  osm('OpenStreetMap', '全球覆盖，国内访问慢');

  const BaseMapChoice(this.label, this.hint);

  final String label;
  final String hint;

  static BaseMapChoice fromName(String? name) => BaseMapChoice.values
      .firstWhere((e) => e.name == name, orElse: () => BaseMapChoice.auto);
}

/// 各底图的瓦片地址。
class BaseMaps {
  BaseMaps._();

  /// 高德矢量路网。style=7 是标准街道图。
  static const TileSource amap = TileSource(
    urlTemplate: 'https://webst0{s}.is.autonavi.com/appmaptile?style=7&x={x}&y={y}&z={z}',
    subdomains: ['1', '2', '3', '4'],
    attribution: '© 高德地图',
    datum: GeoDatum.gcj02,
    maxZoom: 18,
  );

  /// 高德卫星影像（style=6）+ 路网注记叠加层（style=8）。
  /// 只放影像的话没有任何文字，行程规划时认不出哪条是哪条路。
  static const TileSource amapSatellite = TileSource(
    urlTemplate: 'https://webst0{s}.is.autonavi.com/appmaptile?style=6&x={x}&y={y}&z={z}',
    subdomains: ['1', '2', '3', '4'],
    attribution: '© 高德地图',
    datum: GeoDatum.gcj02,
    maxZoom: 18,
    overlay: TileSource(
      urlTemplate: 'https://webst0{s}.is.autonavi.com/appmaptile?style=8&x={x}&y={y}&z={z}',
      subdomains: ['1', '2', '3', '4'],
      attribution: '© 高德地图',
      datum: GeoDatum.gcj02,
      maxZoom: 18,
    ),
  );

  static const TileSource osm = TileSource(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    attribution: '© OpenStreetMap contributors',
    datum: GeoDatum.wgs84,
    maxZoom: 19,
  );

  static TileSource mapbox(String token) => TileSource(
        urlTemplate:
            'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/512/{z}/{x}/{y}@2x?access_token=$token',
        attribution: '© Mapbox © OpenStreetMap',
        datum: GeoDatum.wgs84,
        maxZoom: 20,
      );

  /// 把用户的选择变成实际瓦片源。选了 Mapbox 却没有 token 时退回高德，
  /// 而不是退回 OSM —— 后者在国内慢到不可用。
  static TileSource resolve(BaseMapChoice choice, {String? mapboxToken}) {
    switch (choice) {
      case BaseMapChoice.amap:
      case BaseMapChoice.auto:
        return amap;
      case BaseMapChoice.amapSatellite:
        return amapSatellite;
      case BaseMapChoice.mapbox:
        final token = mapboxToken;
        return (token == null || token.isEmpty) ? amap : mapbox(token);
      case BaseMapChoice.osm:
        return osm;
    }
  }

  /// [BaseMapChoice.auto] 的判定：境内用高德，境外优先 Mapbox，没 token 才用 OSM。
  static TileSource resolveAuto({required bool domestic, String? mapboxToken}) {
    if (domestic) return amap;
    if (mapboxToken != null && mapboxToken.isNotEmpty) return mapbox(mapboxToken);
    return osm;
  }
}
