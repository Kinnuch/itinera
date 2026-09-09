import '../../../core/time_utils.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/plan_item.dart';
import '../advice.dart';

/// 中间某天没有住宿 —— 最后一晚不需要（当天回家），其余每晚都得有着落。
class MissingLodgingRule implements ReviewRule {
  const MissingLodgingRule();

  @override
  String get code => 'missing_lodging';

  @override
  List<Advice> check(ReviewContext ctx) {
    final advices = <Advice>[];
    final dates = ctx.trip.dates;
    if (dates.length < 2) return advices;

    // 最后一天不查：那天晚上人已经在回程路上或到家了。
    for (var i = 0; i < dates.length - 1; i++) {
      final date = dates[i];
      final items = ctx.itemsOn(date);
      if (items.isEmpty) continue; // 完全空白的一天由 EmptyDayRule 管
      final hasLodging = items.any((it) => it.category == ItemCategory.hotel);
      // 跨夜交通（夜班火车/红眼航班）也算解决了住宿。
      final hasOvernightTransport = items.any((it) =>
          it.isTransport &&
          (it.transportMode == TransportMode.train ||
              it.transportMode == TransportMode.flight ||
              it.transportMode == TransportMode.ferry) &&
          (it.endMinutes == null || it.startMinutes == null || it.endMinutes! < it.startMinutes!));

      if (!hasLodging && !hasOvernightTransport) {
        advices.add(Advice(
          code: code,
          severity: AdviceSeverity.warn,
          title: '第 ${i + 1} 天晚上没定住处',
          detail: '${TimeUtils.formatDayLabel(date)} 没有住宿安排，也没有跨夜交通。',
          date: date,
          action: AdviceAction.addLodging,
          actionLabel: '加住宿',
        ));
      }
    }
    return advices;
  }
}

/// 饭点没安排 —— 出门在外漏掉正餐很常见，尤其是排满景点的那天。
class MissingMealRule implements ReviewRule {
  const MissingMealRule();

  /// 午餐 11:00–14:00，晚餐 17:00–21:00。
  static const _windows = [
    (label: '午餐', start: 11 * 60, end: 14 * 60),
    (label: '晚餐', start: 17 * 60, end: 21 * 60),
  ];

  @override
  String get code => 'missing_meal';

  @override
  List<Advice> check(ReviewContext ctx) {
    final advices = <Advice>[];
    for (final date in ctx.trip.dates) {
      final items = ctx.itemsOn(date);
      // 当天几乎没安排就不必唠叨吃饭。
      if (items.length < 2) continue;

      final meals = items.where((i) => i.category == ItemCategory.food).toList();
      final missing = <String>[];
      for (final window in _windows) {
        // 那个时段整段都在赶路（长途交通）就不提示，飞机上会有餐。
        final inTransit = items.any((i) =>
            i.isTransport &&
            i.startMinutes != null &&
            i.endMinutes != null &&
            TimeUtils.overlapMinutes(i.startMinutes!, i.endMinutes!, window.start, window.end) >
                (window.end - window.start) ~/ 2);
        if (inTransit) continue;

        final covered = meals.any((m) {
          final start = m.startMinutes;
          if (start == null) return true; // 有餐但没写时间，按覆盖处理，不误报
          final end = m.endMinutes ?? start + 60;
          return TimeUtils.overlapMinutes(start, end, window.start, window.end) > 0;
        });
        if (!covered) missing.add(window.label);
      }

      if (missing.isNotEmpty) {
        advices.add(Advice(
          code: code,
          severity: AdviceSeverity.info,
          title: '${missing.join('、')}没安排',
          detail: '${TimeUtils.formatDayLabel(date)} 的${missing.join('和')}时段没有餐饮条目，'
              '可以先占个位，金额之后再补。',
          date: date,
          action: AdviceAction.addMeal,
          actionLabel: '加一餐',
        ));
      }
    }
    return advices;
  }
}

/// 条目缺坐标 —— 不影响记账，但路线图上会缺一段，必须提醒。
class MissingLocationRule implements ReviewRule {
  const MissingLocationRule();

  @override
  String get code => 'missing_location';

  @override
  List<Advice> check(ReviewContext ctx) {
    final advices = <Advice>[];
    for (final date in ctx.trip.dates) {
      final missing = ctx
          .itemsOn(date)
          .where((i) => i.category != ItemCategory.other)
          .where((i) => i.anchorPlace?.latLng == null)
          .toList();
      if (missing.isEmpty) continue;

      advices.add(Advice(
        code: code,
        severity: AdviceSeverity.info,
        title: '${missing.length} 项还没定位置',
        detail: '${missing.map((i) => i.title).join('、')} 没有坐标，'
            '路线图会跳过它们，通勤时间也算不准。',
        date: date,
        itemIds: missing.map((i) => i.id).toList(),
        action: AdviceAction.fillLocation,
        actionLabel: '补位置',
      ));
    }
    return advices;
  }
}

/// 行程中间有一整天空白。
class EmptyDayRule implements ReviewRule {
  const EmptyDayRule();

  @override
  String get code => 'empty_day';

  @override
  List<Advice> check(ReviewContext ctx) {
    final advices = <Advice>[];
    for (var i = 0; i < ctx.trip.dates.length; i++) {
      final date = ctx.trip.dates[i];
      if (ctx.itemsOn(date).isNotEmpty) continue;
      advices.add(Advice(
        code: code,
        severity: AdviceSeverity.info,
        title: '第 ${i + 1} 天还是空的',
        detail: '${TimeUtils.formatDayLabel(date)} 一条安排都没有。',
        date: date,
      ));
    }
    return advices;
  }
}

/// 条目掉到了行程日期区间之外（通常是改期之后）。
class OutOfRangeItemRule implements ReviewRule {
  const OutOfRangeItemRule();

  @override
  String get code => 'item_out_of_range';

  @override
  List<Advice> check(ReviewContext ctx) {
    final strays = <PlanItem>[];
    ctx.itemsByDate.forEach((iso, items) {
      if (!ctx.trip.containsDate(DateOnly.parse(iso))) strays.addAll(items);
    });
    if (strays.isEmpty) return const [];

    return [
      Advice(
        code: code,
        severity: AdviceSeverity.error,
        title: '${strays.length} 项落在行程日期之外',
        detail: '${strays.map((i) => '${i.date.toIso()} ${i.title}').take(4).join('、')}'
            '${strays.length > 4 ? ' 等' : ''}不在 '
            '${ctx.trip.startDate.toIso()} ~ ${ctx.trip.endDate.toIso()} 区间内，'
            '需要挪回来或延长行程。',
        itemIds: strays.map((i) => i.id).toList(),
        action: AdviceAction.moveToAnotherDay,
        actionLabel: '处理',
      ),
    ];
  }
}
