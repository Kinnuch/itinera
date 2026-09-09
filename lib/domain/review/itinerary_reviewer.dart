import '../../core/time_utils.dart';
import '../../data/models/enums.dart';
import '../../data/models/plan_item.dart';
import '../../data/models/trip.dart';
import '../../data/repositories/settings_repository.dart';
import '../budget/budget_summary.dart';
import 'advice.dart';
import 'rules/budget_rules.dart';
import 'rules/coverage_rules.dart';
import 'rules/route_rules.dart';
import 'rules/schedule_rules.dart';

/// 体检报告：按天分组的建议，外加全局项。
class ReviewReport {
  const ReviewReport({required this.advices});

  final List<Advice> advices;

  bool get isClean => advices.isEmpty;

  int get errorCount => advices.where((a) => a.severity == AdviceSeverity.error).length;
  int get warnCount => advices.where((a) => a.severity == AdviceSeverity.warn).length;
  int get infoCount => advices.where((a) => a.severity == AdviceSeverity.info).length;

  /// 0–100 的健康分：一个 error 扣 12，一个 warn 扣 5，一个 info 扣 1。
  /// 只用来给用户一个直觉，不参与任何决策。
  int get healthScore {
    final penalty = errorCount * 12 + warnCount * 5 + infoCount * 1;
    return (100 - penalty).clamp(0, 100).toInt();
  }

  List<Advice> forDate(DateOnly date) =>
      advices.where((a) => a.date == date).toList();

  List<Advice> get globalAdvices => advices.where((a) => a.date == null).toList();

  /// 每天的最高严重度，用于在日期条上打小红点。
  Map<String, AdviceSeverity> severityByDate() {
    final map = <String, AdviceSeverity>{};
    for (final a in advices) {
      final date = a.date;
      if (date == null) continue;
      final key = date.toIso();
      final existing = map[key];
      if (existing == null || a.severity.index < existing.index) {
        map[key] = a.severity; // enum 顺序即 error < warn < info
      }
    }
    return map;
  }
}

/// 把所有规则跑一遍，产出排好序的报告。纯计算，可直接单测。
class ItineraryReviewer {
  ItineraryReviewer({List<ReviewRule>? rules})
      : _rules = rules ??
            const [
              OutOfRangeItemRule(),
              TimeOverlapRule(),
              TravelFeasibilityRule(),
              MissingLodgingRule(),
              OverloadedDayRule(),
              RouteDetourRule(),
              MissingMealRule(),
              MissingLocationRule(),
              EmptyDayRule(),
              BudgetRule(),
              UnbookedBigTicketRule(),
            ];

  final List<ReviewRule> _rules;

  ReviewReport review({
    required Trip trip,
    required List<PlanItem> items,
    required TripBudget budget,
    required AppSettings settings,
  }) {
    final byDate = <String, List<PlanItem>>{};
    for (final item in items) {
      byDate.putIfAbsent(item.date.toIso(), () => []).add(item);
    }
    for (final list in byDate.values) {
      list.sort((a, b) => a.timelineKey.compareTo(b.timelineKey));
    }

    final ctx = ReviewContext(
      trip: trip,
      settings: settings,
      itemsByDate: byDate,
      budget: budget,
    );

    final all = <Advice>[];
    for (final rule in _rules) {
      // 单条规则出错不该让整个体检页白屏。
      try {
        all.addAll(rule.check(ctx));
      } catch (_) {
        continue;
      }
    }

    all.sort((a, b) {
      final bySeverity = a.severity.index.compareTo(b.severity.index);
      if (bySeverity != 0) return bySeverity;
      if (a.date == null && b.date == null) return 0;
      if (a.date == null) return -1;
      if (b.date == null) return 1;
      return a.date!.compareTo(b.date!);
    });

    return ReviewReport(advices: all);
  }
}
