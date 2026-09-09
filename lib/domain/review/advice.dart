import '../../core/time_utils.dart';
import '../../data/models/enums.dart';
import '../../data/models/plan_item.dart';
import '../../data/models/trip.dart';
import '../../data/repositories/settings_repository.dart';
import '../budget/budget_summary.dart';

/// 一条体检结论。[code] 稳定不变，用于埋点、忽略清单和测试断言。
class Advice {
  const Advice({
    required this.code,
    required this.severity,
    required this.title,
    required this.detail,
    this.date,
    this.itemIds = const [],
    this.action = AdviceAction.none,
    this.actionLabel,
  });

  final String code;
  final AdviceSeverity severity;
  final String title;
  final String detail;
  final DateOnly? date;

  /// 涉及的条目，UI 点进去可以直接高亮定位。
  final List<String> itemIds;

  final AdviceAction action;
  final String? actionLabel;
}

/// 建议附带的一键操作。UI 决定是否提供按钮，engine 只声明可以怎么修。
enum AdviceAction {
  none,
  reorderDay,
  addLodging,
  addMeal,
  adjustTime,
  fillLocation,
  moveToAnotherDay,
}

/// 规则运行所需的全部输入。一次组装，所有规则共享，避免每条规则重复算。
class ReviewContext {
  ReviewContext({
    required this.trip,
    required this.settings,
    required this.itemsByDate,
    required this.budget,
  });

  final Trip trip;
  final AppSettings settings;

  /// key 为 ISO 日期，value 已按时间轴排序。
  final Map<String, List<PlanItem>> itemsByDate;

  final TripBudget budget;

  List<PlanItem> itemsOn(DateOnly date) => itemsByDate[date.toIso()] ?? const [];

  DayBudget? budgetOn(DateOnly date) {
    for (final d in budget.days) {
      if (d.date == date) return d;
    }
    return null;
  }
}

/// 规则接口。加一条新体检项 = 新写一个类并注册到 [ItineraryReviewer]。
abstract class ReviewRule {
  String get code;

  List<Advice> check(ReviewContext ctx);
}
