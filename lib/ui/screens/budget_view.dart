import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/time_utils.dart';
import '../../data/models/enums.dart';
import '../../domain/budget/budget_summary.dart';
import '../../providers/trip_providers.dart';

/// 功能点 3 的前半：自动汇总每日开销。
/// 顶部是总览与预算进度，中间是分类占比，下面是逐日柱状图 + 明细。
class BudgetView extends ConsumerWidget {
  const BudgetView({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgetAsync = ref.watch(tripBudgetProvider(tripId));

    return budgetAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('汇总失败：$error')),
      data: (budget) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _TotalCard(budget: budget),
          const SizedBox(height: 16),
          if (budget.byCategory.isNotEmpty) ...[
            Text('分类占比', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            _CategoryBreakdown(budget: budget),
            const SizedBox(height: 20),
          ],
          Text('每日开销', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          _DailyChart(budget: budget),
          const SizedBox(height: 12),
          for (final day in budget.days) _DayRow(day: day, budget: budget),
        ],
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.budget});

  final TripBudget budget;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ratio = budget.usageRatio;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('全程合计', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(
              budget.total.format(),
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '日均 ${budget.dailyAverage.format()}'
              '${budget.headcount > 1 ? ' · 人均 ${budget.perPerson.format()}' : ''}',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            if (budget.budget != null && ratio != null) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: ratio.clamp(0.0, 1.0).toDouble(),
                  minHeight: 8,
                  backgroundColor: scheme.surfaceContainerHighest,
                  color: budget.isOverBudget ? scheme.error : scheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '预算 ${budget.budget!.format()}',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  Text(
                    budget.isOverBudget
                        ? '超出 ${(budget.total - budget.budget!).format()}'
                        : '剩余 ${budget.remaining!.format()}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: budget.isOverBudget ? scheme.error : scheme.primary,
                    ),
                  ),
                ],
              ),
            ],
            if (budget.uncountedCount > 0) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: AdviceSeverity.warn.color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${budget.uncountedCount} 笔外币开销暂无汇率，未计入合计',
                      style: TextStyle(fontSize: 12, color: AdviceSeverity.warn.color),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 分类占比：横向堆叠条 + 图例。比饼图更省纵向空间，小屏上也读得清。
class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({required this.budget});

  final TripBudget budget;

  @override
  Widget build(BuildContext context) {
    final shares = budget.categoryShares();
    if (shares.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 12,
            child: Row(
              children: [
                for (final entry in shares)
                  Expanded(
                    flex: (entry.value * 1000).round().clamp(1, 1000).toInt(),
                    child: ColoredBox(color: entry.key.color),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            for (final entry in shares)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration:
                        BoxDecoration(color: entry.key.color, borderRadius: BorderRadius.circular(3)),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${entry.key.label} ${(entry.value * 100).round()}%',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    budget.amountOf(entry.key).format(),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// 逐日柱状图。柱内按分类分段着色，一眼看出哪天花在哪。
class _DailyChart extends StatelessWidget {
  const _DailyChart({required this.budget});

  final TripBudget budget;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxMinor = budget.days.fold<int>(0, (m, d) => d.total.minor > m ? d.total.minor : m);
    if (maxMinor == 0) {
      return Text('还没有记录任何金额', style: TextStyle(color: scheme.onSurfaceVariant));
    }

    return SizedBox(
      height: 130,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final day in budget.days)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: FractionallySizedBox(
                        alignment: Alignment.bottomCenter,
                        heightFactor: (day.total.minor / maxMinor).clamp(0.02, 1.0).toDouble(),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          child: Column(
                            children: [
                              for (final category in _orderedCategories(day))
                                Expanded(
                                  flex: day.amountOf(category).minor.clamp(1, 1 << 30).toInt(),
                                  child: ColoredBox(color: category.color),
                                ),
                              if (day.total.minor == 0)
                                Expanded(child: ColoredBox(color: scheme.surfaceContainerHighest)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${day.dayIndex}',
                      style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<ItemCategory> _orderedCategories(DayBudget day) => ItemCategory.values
      .where((c) => day.byCategory[c] != null && day.byCategory[c]!.minor > 0)
      .toList();
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.day, required this.budget});

  final DayBudget day;
  final TripBudget budget;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isHeaviest = budget.heaviestDay?.date == day.date && day.total.minor > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text('D${day.dayIndex}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  TimeUtils.formatDayLabel(day.date),
                  style: const TextStyle(fontSize: 13),
                ),
                Text(
                  day.itemCount == 0 ? '无安排' : '${day.itemCount} 项',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (isHeaviest)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(Icons.local_fire_department_outlined,
                  size: 15, color: scheme.error),
            ),
          Text(
            day.total.isZero ? '—' : day.total.format(),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
