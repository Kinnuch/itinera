import '../../../core/geo.dart';
import '../../../core/time_utils.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/plan_item.dart';
import '../advice.dart';

/// 同一天两条安排时间重叠 —— 最硬的冲突，直接判 error。
class TimeOverlapRule implements ReviewRule {
  const TimeOverlapRule();

  @override
  String get code => 'time_overlap';

  @override
  List<Advice> check(ReviewContext ctx) {
    final advices = <Advice>[];
    for (final date in ctx.trip.dates) {
      final timed = ctx
          .itemsOn(date)
          .where((i) => i.startMinutes != null && i.endMinutes != null)
          .toList()
        ..sort((a, b) => a.startMinutes!.compareTo(b.startMinutes!));

      for (var i = 0; i < timed.length - 1; i++) {
        for (var j = i + 1; j < timed.length; j++) {
          final a = timed[i];
          final b = timed[j];
          if (b.startMinutes! >= a.endMinutes!) break; // 已排序，后面的更不会重叠
          final overlap = TimeUtils.overlapMinutes(
            a.startMinutes!,
            a.endMinutes!,
            b.startMinutes!,
            b.endMinutes!,
          );
          if (overlap <= 0) continue;
          advices.add(Advice(
            code: code,
            severity: AdviceSeverity.error,
            title: '时间撞车了',
            detail: '「${a.title}」和「${b.title}」重叠 ${TimeUtils.formatDuration(overlap)}，'
                '同一时段安排不了两件事。',
            date: date,
            itemIds: [a.id, b.id],
            action: AdviceAction.adjustTime,
            actionLabel: '调整时间',
          ));
        }
      }
    }
    return advices;
  }
}

/// 前一项结束到后一项开始的空档，装不下两地之间的通勤 —— 计划表上看着连贯，实际赶不到。
class TravelFeasibilityRule implements ReviewRule {
  const TravelFeasibilityRule();

  /// 留 10 分钟容错，避免把「刚好赶上」也报成冲突。
  static const int _toleranceMinutes = 10;

  @override
  String get code => 'travel_infeasible';

  @override
  List<Advice> check(ReviewContext ctx) {
    final advices = <Advice>[];
    for (final date in ctx.trip.dates) {
      final timed = ctx.itemsOn(date).where((i) => i.startMinutes != null).toList()
        ..sort((a, b) => a.startMinutes!.compareTo(b.startMinutes!));

      for (var i = 0; i < timed.length - 1; i++) {
        final a = timed[i];
        final b = timed[i + 1];

        // 离开 a 时人在 a 的终点，开始 b 时人必须在 b 的起点。
        final from = a.anchorPlace?.latLng;
        final to = b.originPlace?.latLng;
        if (from == null || to == null) continue;

        final meters = GeoUtils.distanceMeters(from, to);
        if (meters < 200) continue;

        final mode = b.isTransport
            ? (b.transportMode ?? TransportMode.inferFromDistance(meters))
            : TransportMode.inferFromDistance(meters);
        final needed = mode.estimateMinutes(meters);
        final available = b.startMinutes! - (a.endMinutes ?? a.startMinutes!);

        if (needed > available + _toleranceMinutes) {
          advices.add(Advice(
            code: code,
            severity: AdviceSeverity.error,
            title: '来不及赶过去',
            detail: '从「${a.title}」到「${b.title}」约 ${_km(meters)}，'
                '${mode.label}需要 ${TimeUtils.formatDuration(needed)}，'
                '但中间只留了 ${TimeUtils.formatDuration(available < 0 ? 0 : available)}。',
            date: date,
            itemIds: [a.id, b.id],
            action: AdviceAction.adjustTime,
            actionLabel: '调整时间',
          ));
        }
      }
    }
    return advices;
  }

  String _km(double meters) =>
      meters < 1000 ? '${meters.round()} 米' : '${(meters / 1000).toStringAsFixed(1)} 公里';
}

/// 白天出现大段空白 —— 不是错误，但值得提醒「这里还能塞点东西」。
class IdleGapRule implements ReviewRule {
  const IdleGapRule();

  /// 只看 08:00–21:00 之间的空档，夜里空着是正常的。
  static const int _dayStart = 8 * 60;
  static const int _dayEnd = 21 * 60;

  @override
  String get code => 'idle_gap';

  @override
  List<Advice> check(ReviewContext ctx) {
    final advices = <Advice>[];
    final threshold = ctx.settings.idleGapThresholdMinutes;

    for (final date in ctx.trip.dates) {
      final timed = ctx.itemsOn(date).where((i) => i.startMinutes != null).toList()
        ..sort((a, b) => a.startMinutes!.compareTo(b.startMinutes!));
      if (timed.length < 2) continue;

      for (var i = 0; i < timed.length - 1; i++) {
        final a = timed[i];
        final b = timed[i + 1];
        final gapStart = a.endMinutes ?? a.startMinutes!;
        final gapEnd = b.startMinutes!;
        final visible = TimeUtils.overlapMinutes(gapStart, gapEnd, _dayStart, _dayEnd);
        if (visible < threshold) continue;

        advices.add(Advice(
          code: code,
          severity: AdviceSeverity.info,
          title: '白天有 ${TimeUtils.formatDuration(visible)} 空着',
          detail: '${TimeUtils.formatMinutes(gapStart)} 到 ${TimeUtils.formatMinutes(gapEnd)} '
              '没有安排，可以补一个景点或留作机动。',
          date: date,
          itemIds: [a.id, b.id],
        ));
      }
    }
    return advices;
  }
}

/// 一天塞太满 —— 净活动时长（含估算通勤）超上限，或景点数量超上限。
class OverloadedDayRule implements ReviewRule {
  const OverloadedDayRule();

  @override
  String get code => 'day_overloaded';

  @override
  List<Advice> check(ReviewContext ctx) {
    final advices = <Advice>[];
    for (final date in ctx.trip.dates) {
      final items = ctx.itemsOn(date);
      if (items.isEmpty) continue;

      final activeMinutes = _activeMinutes(items);
      final limit = ctx.settings.maxActiveHoursPerDay * 60;
      if (activeMinutes > limit) {
        advices.add(Advice(
          code: code,
          severity: AdviceSeverity.warn,
          title: '这天排得太满',
          detail: '含通勤估算共 ${TimeUtils.formatDuration(activeMinutes)} 在外奔波，'
              '超过设定的 ${ctx.settings.maxActiveHoursPerDay} 小时上限，建议挪一项到别天。',
          date: date,
          itemIds: items.map((i) => i.id).toList(),
          action: AdviceAction.moveToAnotherDay,
          actionLabel: '挪到其它天',
        ));
      }

      final attractions =
          items.where((i) => i.category == ItemCategory.attraction).toList();
      if (attractions.length > ctx.settings.maxAttractionsPerDay) {
        advices.add(Advice(
          code: '${code}_attractions',
          severity: AdviceSeverity.warn,
          title: '一天 ${attractions.length} 个景点偏多',
          detail: '超过设定的每日 ${ctx.settings.maxAttractionsPerDay} 个上限，'
              '赶场会压缩每个点的停留时间。',
          date: date,
          itemIds: attractions.map((i) => i.id).toList(),
          action: AdviceAction.moveToAnotherDay,
          actionLabel: '挪到其它天',
        ));
      }
    }
    return advices;
  }

  /// 首项开始到末项结束的跨度；没有时间的条目不计入。
  int _activeMinutes(List<PlanItem> items) {
    final timed = items.where((i) => i.startMinutes != null).toList();
    if (timed.isEmpty) return 0;
    var earliest = timed.first.startMinutes!;
    var latest = timed.first.endMinutes ?? timed.first.startMinutes!;
    for (final item in timed) {
      final start = item.startMinutes!;
      final end = item.endMinutes ?? start;
      if (start < earliest) earliest = start;
      if (end > latest) latest = end;
    }
    return latest - earliest;
  }
}
