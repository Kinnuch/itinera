import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/time_utils.dart';
import '../../data/models/enums.dart';
import '../../domain/review/advice.dart';
import '../../domain/review/itinerary_reviewer.dart';
import '../../providers/trip_providers.dart';
import '../widgets/advice_tile.dart';
import 'item_editor_screen.dart';

/// 功能点 3 的后半：安排是否合理。
/// 上面是健康分与三档计数，下面按「全局 → 逐日」列出所有结论。
class ReviewView extends ConsumerWidget {
  const ReviewView({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewAsync = ref.watch(tripReviewProvider(tripId));
    final state = ref.watch(tripControllerProvider(tripId)).valueOrNull;

    return reviewAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('体检失败：$error')),
      data: (report) {
        if (state == null) return const SizedBox.shrink();
        final globals = report.globalAdvices;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _ScoreCard(report: report),
            const SizedBox(height: 16),
            if (report.isClean)
              const _CleanState()
            else ...[
              if (globals.isNotEmpty) ...[
                Text('全程', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                for (final advice in globals)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AdviceTile(advice: advice),
                  ),
                const SizedBox(height: 8),
              ],
              for (var i = 0; i < state.trip.dates.length; i++)
                ..._daySection(context, ref, report, state.trip.dates[i], i + 1),
            ],
          ],
        );
      },
    );
  }

  List<Widget> _daySection(
    BuildContext context,
    WidgetRef ref,
    ReviewReport report,
    DateOnly date,
    int dayIndex,
  ) {
    final advices = report.forDate(date);
    if (advices.isEmpty) return const [];

    return [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Text(
          'D$dayIndex · ${TimeUtils.formatDayLabel(date)}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
      for (final advice in advices)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AdviceTile(
            advice: advice,
            onAction: _actionFor(context, ref, advice, date),
          ),
        ),
    ];
  }

  VoidCallback? _actionFor(
    BuildContext context,
    WidgetRef ref,
    Advice advice,
    DateOnly date,
  ) {
    switch (advice.action) {
      case AdviceAction.reorderDay:
        return () async {
          await ref.read(tripControllerProvider(tripId).notifier).applySuggestedOrder(date);
          if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('已按建议重排当天顺序')));
          }
        };
      case AdviceAction.addLodging:
        return () => _openEditor(context, date, ItemCategory.hotel);
      case AdviceAction.addMeal:
        return () => _openEditor(context, date, ItemCategory.food);
      case AdviceAction.none:
      case AdviceAction.adjustTime:
      case AdviceAction.fillLocation:
      case AdviceAction.moveToAnotherDay:
        return null;
    }
  }

  void _openEditor(BuildContext context, DateOnly date, ItemCategory category) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ItemEditorScreen(
          tripId: tripId,
          date: date,
          presetCategory: category,
        ),
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.report});

  final ReviewReport report;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final score = report.healthScore;
    final tone = score >= 85
        ? scheme.primary
        : score >= 60
            ? AdviceSeverity.warn.color
            : AdviceSeverity.error.color;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: score / 100,
                    strokeWidth: 6,
                    backgroundColor: scheme.surfaceContainerHighest,
                    color: tone,
                  ),
                  Text(
                    '$score',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: tone),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _headline(score),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    children: [
                      _Count(label: '冲突', count: report.errorCount, color: AdviceSeverity.error.color),
                      _Count(label: '提醒', count: report.warnCount, color: AdviceSeverity.warn.color),
                      _Count(label: '建议', count: report.infoCount, color: AdviceSeverity.info.color),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _headline(int score) {
    if (score >= 90) return '安排得挺妥当';
    if (score >= 70) return '大体可行，有几处可以再顺一顺';
    if (score >= 50) return '有几个地方需要调整';
    return '现在这版跑不通，先处理红色冲突';
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.count, required this.color});

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text('$label $count', style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}

class _CleanState extends StatelessWidget {
  const _CleanState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.verified_outlined, size: 48, color: scheme.primary),
          const SizedBox(height: 10),
          Text('没有发现问题', style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(
            '时间、通勤、住宿、餐饮和预算都检查过了',
            style: TextStyle(fontSize: 12, color: scheme.outline),
          ),
        ],
      ),
    );
  }
}
