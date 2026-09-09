import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../../data/models/enums.dart';
import '../../data/models/location.dart';

/// 瓦片源描述。flutter_map 只认 WGS-84/Web Mercator 的瓦片网格，
/// 但高德瓦片画的是 GCJ-02 的地物，所以要连同 [datum] 一起传出来，
/// 由 [MapDisplayAdapter] 在绘制前把坐标搬到瓦片所在的坐标系。
class TileSource {
  const TileSource({
    required this.urlTemplate,
    required this.attribution,
    required this.datum,
    this.subdomains = const [],
    this.maxZoom = 18,
    this.headers = const {},
  });

  final String urlTemplate;
  final String attribution;
  final GeoDatum datum;
  final List<String> subdomains;
  final double maxZoom;
  final Map<String, String> headers;
}

/// 一段导航结果。
class RouteLegGeometry {
  const RouteLegGeometry({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    this.isEstimated = false,
  });

  /// 直线兜底：没有网络或没配密钥时，用两点直线 + 速度模型估算。
  factory RouteLegGeometry.straightLine(LatLng from, LatLng to, TransportMode mode) {
    final meters = GeoUtils.distanceMeters(from, to);
    return RouteLegGeometry(
      points: [from, to],
      distanceMeters: meters,
      durationSeconds: mode.estimateMinutes(meters) * 60,
      isEstimated: true,
    );
  }

  final List<LatLng> points;
  final double distanceMeters;
  final int durationSeconds;

  /// true 表示这段是直线估算而非真实导航，UI 上用虚线画出来以示区别。
  final bool isEstimated;

  int get durationMinutes => (durationSeconds / 60).round();
}

/// 地图能力接口。新增服务商（腾讯、Google）只要实现这一个类。
abstract class MapProvider {
  String get id;

  String get displayName;

  /// 密钥是否已配置；没配就只能用免费底图 + 直线兜底。
  bool get isConfigured;

  TileSource get tileSource;

  /// 关键词搜地点。[near] 用于把结果按距离排序（城市内搜「咖啡」时很关键）。
  Future<List<GeoPlace>> searchPlaces(String keyword, {LatLng? near});

  /// 点图选点后反查地址。
  Future<GeoPlace?> reverseGeocode(LatLng point);

  /// 算一段路。失败时返回 null，调用方负责降级到直线。
  Future<RouteLegGeometry?> route(LatLng from, LatLng to, TransportMode mode);
}

/// 把内部统一的 WGS-84 坐标，搬到当前瓦片源所用的坐标系再交给 flutter_map 绘制；
/// 反向用于「用户在地图上点了一下」这类交互。
class MapDisplayAdapter {
  const MapDisplayAdapter(this.datum);

  final GeoDatum datum;

  LatLng toDisplay(LatLng stored) =>
      datum == GeoDatum.gcj02 ? GeoUtils.wgs84ToGcj02(stored) : stored;

  LatLng toStored(LatLng displayed) =>
      datum == GeoDatum.gcj02 ? GeoUtils.gcj02ToWgs84(displayed) : displayed;

  List<LatLng> toDisplayAll(Iterable<LatLng> stored) => stored.map(toDisplay).toList();
}

/// 完全没配密钥时的保底：OSM 公共瓦片可看图，但不提供搜索与导航。
/// 生产环境请让用户填自己的密钥，OSM 官方瓦片不允许 App 大流量使用。
class OsmProvider implements MapProvider {
  const OsmProvider();

  static const TileSource osmTileSource = TileSource(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    attribution: '© OpenStreetMap contributors',
    datum: GeoDatum.wgs84,
    maxZoom: 19,
  );

  @override
  String get id => 'osm';

  @override
  String get displayName => 'OpenStreetMap（未配置密钥）';

  @override
  bool get isConfigured => false;

  @override
  TileSource get tileSource => osmTileSource;

  @override
  Future<List<GeoPlace>> searchPlaces(String keyword, {LatLng? near}) async => const [];

  @override
  Future<GeoPlace?> reverseGeocode(LatLng point) async => null;

  @override
  Future<RouteLegGeometry?> route(LatLng from, LatLng to, TransportMode mode) async => null;
}
