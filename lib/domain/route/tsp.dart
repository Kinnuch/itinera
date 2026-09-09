import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';

/// 单日游览顺序优化。
///
/// 一天的点通常不超过十来个，用「最近邻构造 + 2-opt 改良」就够，
/// 无需真正的 TSP 求解器；起点（早上出发的酒店）和终点（晚上回的酒店）可以锁定。
class RouteOptimizer {
  const RouteOptimizer();

  /// [points] 按当前顺序给出。返回优化后的下标序列。
  /// [pinFirst]/[pinLast] 为 true 时对应端点位置不动。
  List<int> optimizeOrder(
    List<LatLng> points, {
    bool pinFirst = true,
    bool pinLast = false,
  }) {
    final n = points.length;
    if (n <= 3) return List.generate(n, (i) => i);

    final startFixed = pinFirst ? 1 : 0;
    final endFixed = pinLast ? 1 : 0;
    final movable = List.generate(n - startFixed - endFixed, (i) => i + startFixed);
    if (movable.length <= 2) return List.generate(n, (i) => i);

    // 1) 最近邻构造
    final order = <int>[if (pinFirst) 0];
    final remaining = movable.toSet();
    var current = pinFirst ? 0 : movable.first;
    if (!pinFirst) {
      order.add(current);
      remaining.remove(current);
    }
    while (remaining.isNotEmpty) {
      var best = remaining.first;
      var bestDist = double.infinity;
      for (final candidate in remaining) {
        final d = GeoUtils.distanceMeters(points[current], points[candidate]);
        if (d < bestDist) {
          bestDist = d;
          best = candidate;
        }
      }
      order.add(best);
      remaining.remove(best);
      current = best;
    }
    if (pinLast) order.add(n - 1);

    // 2) 2-opt 改良：反复翻转子段，直到没有改进为止
    return _twoOpt(order, points, lockFirst: pinFirst, lockLast: pinLast);
  }

  List<int> _twoOpt(
    List<int> order,
    List<LatLng> points, {
    required bool lockFirst,
    required bool lockLast,
  }) {
    final result = List<int>.from(order);
    final lo = lockFirst ? 1 : 0;
    final hi = lockLast ? result.length - 2 : result.length - 1;

    var improved = true;
    var guard = 0;
    while (improved && guard++ < 100) {
      improved = false;
      for (var i = lo; i < hi; i++) {
        for (var k = i + 1; k <= hi; k++) {
          final delta = _swapDelta(result, points, i, k);
          if (delta < -1) {
            // 只接受至少 1 米的改进，避免浮点噪声导致无限循环
            _reverseSegment(result, i, k);
            improved = true;
          }
        }
      }
    }
    return result;
  }

  /// 翻转 [i,k] 后总长度的变化量：只需比较两条被断开的边与两条新接上的边。
  double _swapDelta(List<int> order, List<LatLng> points, int i, int k) {
    final prev = i - 1;
    final next = k + 1;
    var removed = 0.0, added = 0.0;
    if (prev >= 0) {
      removed += GeoUtils.distanceMeters(points[order[prev]], points[order[i]]);
      added += GeoUtils.distanceMeters(points[order[prev]], points[order[k]]);
    }
    if (next < order.length) {
      removed += GeoUtils.distanceMeters(points[order[k]], points[order[next]]);
      added += GeoUtils.distanceMeters(points[order[i]], points[order[next]]);
    }
    return added - removed;
  }

  void _reverseSegment(List<int> order, int i, int k) {
    var a = i, b = k;
    while (a < b) {
      final tmp = order[a];
      order[a] = order[b];
      order[b] = tmp;
      a++;
      b--;
    }
  }

  /// 按给定顺序走完全程的直线总里程（米）。
  double pathLength(List<LatLng> points, List<int> order) {
    var sum = 0.0;
    for (var i = 1; i < order.length; i++) {
      sum += GeoUtils.distanceMeters(points[order[i - 1]], points[order[i]]);
    }
    return sum;
  }
}
