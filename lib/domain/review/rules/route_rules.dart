import '../../../data/models/enums.dart';
import '../../../data/models/plan_item.dart';
import '../../route/tsp.dart';
import '../advice.dart';

/// 一天之内来回折返 —— 当前顺序的总里程明显大于优化顺序，提示重排。
///
/// 这条规则只给建议，不自动改动用户的安排：顺序背后可能有营业时间、
/// 预约时段等应用不知道的约束。
class RouteDetourRule implements ReviewRule {
  const RouteDetourRule({this.optimizer = const RouteOptimizer()});

  final RouteOptimizer optimizer;

  @override
  String get code => 'route_detour';

  @override
  List<Advice> check(ReviewContext ctx) {
    final advices = <Advice>[];

    for (final date in ctx.trip.dates) {
      final stops = ctx
          .itemsOn(date)
          // 跨城交通的起讫点会把里程拉爆，比较的是市内游览顺序。
          .where((i) => !_isLongHaul(i))
          .where((i) => i.anchorPlace?.latLng != null)
          .toList();
      if (stops.length < 4) continue;

      final points = stops.map((i) => i.anchorPlace!.latLng!).toList();
      final currentOrder = List.generate(points.length, (i) => i);
      final currentLength = optimizer.pathLength(points, currentOrder);
      if (currentLength < 3000) continue; // 全天不到 3 公里，谈不上折返

      // 起点锁定（早上从哪出发是既定的），终点是否锁定看末项是不是住宿。
      final pinLast = stops.last.category == ItemCategory.hotel;
      final optimized = optimizer.optimizeOrder(points, pinFirst: true, pinLast: pinLast);
      final optimizedLength = optimizer.pathLength(points, optimized);
      if (optimizedLength <= 0) continue;

      final ratio = currentLength / optimizedLength;
      if (ratio < ctx.settings.detourToleranceRatio) continue;

      final saved = currentLength - optimizedLength;
      advices.add(Advice(
        code: code,
        severity: AdviceSeverity.warn,
        title: '这天在绕路',
        detail: '按当前顺序要走约 ${_km(currentLength)}，换个顺序约 ${_km(optimizedLength)}，'
            '能少绕 ${_km(saved)}。建议顺序：'
            '${optimized.map((i) => stops[i].title).join(' → ')}',
        date: date,
        itemIds: stops.map((i) => i.id).toList(),
        action: AdviceAction.reorderDay,
        actionLabel: '按建议重排',
      ));
    }

    return advices;
  }

  bool _isLongHaul(PlanItem item) =>
      item.isTransport &&
      (item.transportMode == TransportMode.flight ||
          item.transportMode == TransportMode.train ||
          item.transportMode == TransportMode.coach ||
          item.transportMode == TransportMode.ferry);

  String _km(double meters) => '${(meters / 1000).toStringAsFixed(1)} 公里';
}

/// 计算某天按建议顺序重排后的条目列表，供 UI 的「一键重排」使用。
/// 只调换 sort_order 与时间段的先后，不改每项的时长。
class DayReorderPlanner {
  const DayReorderPlanner({this.optimizer = const RouteOptimizer()});

  final RouteOptimizer optimizer;

  /// 返回重排后的条目顺序；无可优化空间时返回原列表。
  List<PlanItem> reorder(List<PlanItem> dayItems) {
    final locatable = dayItems.where((i) => i.anchorPlace?.latLng != null).toList();
    if (locatable.length < 4) return dayItems;

    final points = locatable.map((i) => i.anchorPlace!.latLng!).toList();
    final pinLast = locatable.last.category == ItemCategory.hotel;
    final order = optimizer.optimizeOrder(points, pinFirst: true, pinLast: pinLast);
    final reordered = order.map((i) => locatable[i]).toList();

    // 没有坐标的条目保持相对位置，追加在末尾。
    final rest = dayItems.where((i) => i.anchorPlace?.latLng == null).toList();
    return [...reordered, ...rest];
  }

  /// 把原有的时间段按新顺序重新分配（第 1 项拿原来最早的时段，以此类推）。
  List<PlanItem> reassignTimeSlots(List<PlanItem> reordered, List<PlanItem> original) {
    final slots = original
        .where((i) => i.startMinutes != null)
        .map((i) => (start: i.startMinutes!, end: i.endMinutes))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    if (slots.isEmpty) return reordered;

    final result = <PlanItem>[];
    var slotIndex = 0;
    for (final item in reordered) {
      if (item.startMinutes == null || slotIndex >= slots.length) {
        result.add(item);
        continue;
      }
      final slot = slots[slotIndex++];
      result.add(item.copyWith(
        startMinutes: () => slot.start,
        endMinutes: () => slot.end,
      ));
    }
    return result;
  }
}
