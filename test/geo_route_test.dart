import 'package:flutter_test/flutter_test.dart';
import 'package:itinera/core/geo.dart';
import 'package:itinera/data/models/enums.dart';
import 'package:itinera/domain/route/tsp.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('坐标系转换', () {
    test('境内 WGS-84 与 GCJ-02 往返误差在 1 米内', () {
      const original = LatLng(39.9087, 116.3975); // 天安门
      final gcj = GeoUtils.wgs84ToGcj02(original);
      final back = GeoUtils.gcj02ToWgs84(gcj);

      // 偏移确实发生了（不是恒等变换）
      expect(GeoUtils.distanceMeters(original, gcj), greaterThan(100));
      // 反解回来足够准
      expect(GeoUtils.distanceMeters(original, back), lessThan(1.0));
    });

    test('境外坐标不做偏移', () {
      const paris = LatLng(48.8584, 2.2945);
      expect(GeoUtils.wgs84ToGcj02(paris), paris);
      expect(GeoUtils.gcj02ToWgs84(paris), paris);
    });

    test('折线编码可解码回原始点', () {
      // Google 官方示例串
      final points = GeoUtils.decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
      expect(points.length, 3);
      expect(points.first.latitude, closeTo(38.5, 0.001));
      expect(points.first.longitude, closeTo(-120.2, 0.001));
    });
  });

  group('路径优化', () {
    const optimizer = RouteOptimizer();

    test('把折返顺序整理成顺路顺序', () {
      // 沿一条直线排布，但访问顺序被打乱成 A -> C -> B -> D
      const a = LatLng(35.000, 135.000);
      const b = LatLng(35.010, 135.000);
      const c = LatLng(35.020, 135.000);
      const d = LatLng(35.030, 135.000);
      final scrambled = [a, c, b, d];

      final before = optimizer.pathLength(scrambled, [0, 1, 2, 3]);
      final order = optimizer.optimizeOrder(scrambled, pinFirst: true);
      final after = optimizer.pathLength(scrambled, order);

      expect(after, lessThan(before));
      expect(order.first, 0); // 起点被锁定
    });

    test('点数太少时原样返回', () {
      const points = [LatLng(35.0, 135.0), LatLng(35.1, 135.1)];
      expect(optimizer.optimizeOrder(points), [0, 1]);
    });
  });

  group('交通耗时估算', () {
    test('步行比公共交通慢，且都含绕行系数', () {
      const meters = 3000.0;
      final walk = TransportMode.walk.estimateMinutes(meters);
      final transit = TransportMode.transit.estimateMinutes(meters);

      expect(walk, greaterThan(transit));
      // 3 公里直线 × 1.35 绕行 ÷ 4.5km/h ≈ 54 分钟
      expect(walk, closeTo(54, 3));
    });

    test('飞机含固定的值机安检开销', () {
      // 极短距离也不会低于固定开销
      expect(TransportMode.flight.estimateMinutes(1000), greaterThanOrEqualTo(150));
    });

    test('按距离推断的方式随距离升级', () {
      expect(TransportMode.inferFromDistance(500), TransportMode.walk);
      expect(TransportMode.inferFromDistance(8000), TransportMode.transit);
      expect(TransportMode.inferFromDistance(100000), TransportMode.train);
      expect(TransportMode.inferFromDistance(2000000), TransportMode.flight);
    });
  });
}
