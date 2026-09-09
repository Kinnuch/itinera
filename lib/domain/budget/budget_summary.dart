import '../../core/money.dart';
import '../../core/time_utils.dart';
import '../../data/models/enums.dart';
import '../../data/models/plan_item.dart';
import '../../data/models/trip.dart';
import '../../services/currency/exchange_rate_service.dart';

/// 单日开销。
class DayBudget {
  const DayBudget({
    required this.date,
    required this.dayIndex,
    required this.byCategory,
    required this.total,
    required this.itemCount,
    required this.uncounted,
  });

  final DateOnly date;
  final int dayIndex;
  final Map<ItemCategory, Money> byCategory;
  final Money total;
  final int itemCount;

  /// 因为缺汇率而没能计入总额的条目，UI 必须单独提示，不能静默吞掉。
  final List<PlanItem> uncounted;

  Money amountOf(ItemCategory c) => byCategory[c] ?? Money.zero(total.currency);
}

/// 整趟行程的开销汇总。
class TripBudget {
  const TripBudget({
    required this.currency,
    required this.days,
    required this.total,
    required this.byCategory,
    required this.budget,
    required this.headcount,
    required this.uncountedCount,
  });

  final String currency;
  final List<DayBudget> days;
  final Money total;
  final Map<ItemCategory, Money> byCategory;
  final Money? budget;
  final int headcount;
  final int uncountedCount;

  Money get dailyAverage => days.isEmpty ? Money.zero(currency) : total / days.length;

  Money get perPerson => headcount <= 1 ? total : total / headcount;

  Money? get remaining => budget == null ? null : budget! - total;

  bool get isOverBudget => budget != null && total.minor > budget!.minor;

  /// 预算使用率，用于进度条；无预算时返回 null。
  double? get usageRatio =>
      (budget == null || budget!.minor == 0) ? null : total.minor / budget!.minor;

  /// 花得最多的那一天，用于「行程亮点/黑洞」提示。
  DayBudget? get heaviestDay {
    if (days.isEmpty) return null;
    return days.reduce((a, b) => a.total.minor >= b.total.minor ? a : b);
  }

  Money amountOf(ItemCategory c) => byCategory[c] ?? Money.zero(currency);

  /// 各分类占比，降序，供饼图/条形图直接消费。
  List<MapEntry<ItemCategory, double>> categoryShares() {
    if (total.minor == 0) return const [];
    final entries = byCategory.entries
        .where((e) => e.value.minor != 0)
        .map((e) => MapEntry(e.key, e.value.minor / total.minor))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }
}

/// 纯函数式汇总器：给定条目和汇率表算出结果，不碰 IO，便于单测。
class BudgetCalculator {
  const BudgetCalculator();

  TripBudget summarize({
    required Trip trip,
    required List<PlanItem> items,
    required Map<String, double> rates,
  }) {
    final currency = trip.homeCurrency;
    final dayBudgets = <DayBudget>[];
    final tripByCategory = <ItemCategory, Money>{};
    var tripTotal = Money.zero(currency);
    var uncountedCount = 0;

    final byDate = <String, List<PlanItem>>{};
    for (final item in items) {
      byDate.putIfAbsent(item.date.toIso(), () => []).add(item);
    }

    for (var i = 0; i < trip.dates.length; i++) {
      final date = trip.dates[i];
      final dayItems = byDate[date.toIso()] ?? const <PlanItem>[];
      final categoryTotals = <ItemCategory, Money>{};
      final uncounted = <PlanItem>[];
      var dayTotal = Money.zero(currency);

      for (final item in dayItems) {
        final amount = item.amount;
        if (amount == null || amount.isZero) continue;
        final converted = ExchangeRateService.convert(amount, currency, rates);
        if (converted == null) {
          uncounted.add(item);
          continue;
        }
        categoryTotals.update(
          item.category,
          (prev) => prev + converted,
          ifAbsent: () => converted,
        );
        dayTotal = dayTotal + converted;
      }

      categoryTotals.forEach((category, money) {
        tripByCategory.update(category, (prev) => prev + money, ifAbsent: () => money);
      });
      tripTotal = tripTotal + dayTotal;
      uncountedCount += uncounted.length;

      dayBudgets.add(DayBudget(
        date: date,
        dayIndex: i + 1,
        byCategory: categoryTotals,
        total: dayTotal,
        itemCount: dayItems.length,
        uncounted: uncounted,
      ));
    }

    return TripBudget(
      currency: currency,
      days: dayBudgets,
      total: tripTotal,
      byCategory: tripByCategory,
      budget: trip.budget,
      headcount: trip.headcount,
      uncountedCount: uncountedCount,
    );
  }

  /// 行程里出现过的所有币种，用来一次性把汇率拉齐。
  static Set<String> currenciesIn(List<PlanItem> items) =>
      items.map((i) => i.currency).whereType<String>().map((c) => c.toUpperCase()).toSet();
}
