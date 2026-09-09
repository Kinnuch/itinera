import '../../../core/money.dart';
import '../../../core/time_utils.dart';
import '../../../data/models/enums.dart';
import '../advice.dart';

/// 全程超预算 / 单日显著高于日均。
class BudgetRule implements ReviewRule {
  const BudgetRule();

  @override
  String get code => 'over_budget';

  @override
  List<Advice> check(ReviewContext ctx) {
    final advices = <Advice>[];
    final budget = ctx.budget;
    final tripBudget = budget.budget;

    if (tripBudget != null && tripBudget.minor > 0) {
      if (budget.total.minor > tripBudget.minor) {
        final over = budget.total - tripBudget;
        advices.add(Advice(
          code: code,
          severity: AdviceSeverity.warn,
          title: '已超出总预算 ${over.format()}',
          detail: '当前合计 ${budget.total.format()}，预算 ${tripBudget.format()}。',
        ));
      } else if (budget.usageRatio != null && budget.usageRatio! > 0.9) {
        advices.add(Advice(
          code: '${code}_near',
          severity: AdviceSeverity.info,
          title: '预算已用 ${(budget.usageRatio! * 100).round()}%',
          detail: '还剩 ${budget.remaining!.format()}，后面的安排注意留余量。',
        ));
      }

      final daily = ctx.trip.dailyBudget;
      if (daily != null && daily.minor > 0) {
        final threshold = (daily.minor * ctx.settings.dailyOverBudgetRatio).round();
        for (final day in budget.days) {
          if (day.total.minor <= threshold) continue;
          advices.add(Advice(
            code: '${code}_day',
            severity: AdviceSeverity.info,
            title: '第 ${day.dayIndex} 天花销偏高',
            detail: '${TimeUtils.formatDayLabel(day.date)} 合计 ${day.total.format()}，'
                '是日均预算 ${daily.format()} 的 '
                '${(day.total.minor / daily.minor).toStringAsFixed(1)} 倍。',
            date: day.date,
          ));
        }
      }
    }

    // 缺汇率导致部分金额没进总额，必须显式提示，否则用户会以为花得比实际少。
    if (budget.uncountedCount > 0) {
      advices.add(Advice(
        code: 'currency_missing_rate',
        severity: AdviceSeverity.warn,
        title: '${budget.uncountedCount} 笔开销未计入合计',
        detail: '这些条目的币种暂时拿不到汇率（可能是离线），联网后会自动补上。',
      ));
    }

    return advices;
  }
}

/// 大额条目还没订 —— 机票酒店越晚订越贵，出行前该收口。
class UnbookedBigTicketRule implements ReviewRule {
  const UnbookedBigTicketRule();

  @override
  String get code => 'unbooked_big_ticket';

  @override
  List<Advice> check(ReviewContext ctx) {
    final currency = ctx.trip.homeCurrency;
    final dailyBudget = ctx.trip.dailyBudget;
    // 阈值：日均预算的一半；没设预算时退回一个保守的固定值。
    final threshold = dailyBudget != null && dailyBudget.minor > 0
        ? dailyBudget.minor ~/ 2
        : Money(50000, currency).minor;

    final pending = <String>[];
    final ids = <String>[];
    for (final items in ctx.itemsByDate.values) {
      for (final item in items) {
        if (item.booked) continue;
        if (item.category != ItemCategory.hotel && !item.isTransport) continue;
        final amount = item.amount;
        if (amount == null) continue;
        // 只比较同币种的粗略量级，跨币种的交给总额规则。
        if (amount.currency != currency || amount.minor < threshold) continue;
        pending.add(item.title);
        ids.add(item.id);
      }
    }
    if (pending.isEmpty) return const [];

    return [
      Advice(
        code: code,
        severity: AdviceSeverity.info,
        title: '${pending.length} 项大额还未标记已订',
        detail: '${pending.take(3).join('、')}${pending.length > 3 ? ' 等' : ''}'
            '金额不小但还没勾「已预订」，出发前记得确认。',
        itemIds: ids,
      ),
    ];
  }
}
