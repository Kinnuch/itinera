import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/geo.dart';
import '../../core/time_utils.dart';
import '../../data/models/enums.dart';
import '../../data/models/plan_item.dart';
import '../../domain/review/advice.dart';
import '../../providers/trip_providers.dart';
import '../widgets/advice_tile.dart';
import '../widgets/day_strip.dart';
import '../widgets/item_tile.dart';
import 'item_editor_screen.dart';

/// 「按日安排」主界面：顶部日期条 + 当日时间轴 + 新增按钮。
/// 功能点 2 的落脚处，各类别共用同一个编辑器。
class DayPlanView extends ConsumerStatefulWidget {
  const DayPlanView({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<DayPlanView> createState() => _DayPlanViewState();
}

class _DayPlanViewState extends ConsumerState<DayPlanView> {
  DateOnly? _selected;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tripControllerProvider(widget.tripId)).valueOrNull;
    if (state == null) return const Center(child: CircularProgressIndicator());

    final trip = state.trip;
    // 默认停在「今天」，行程还没开始或已结束就停在第一天。
    final today = DateOnly.from(DateTime.now());
    final selected = _selected ?? (trip.containsDate(today) ? today : trip.startDate);
    final items = state.itemsOn(selected);
    final review = ref.watch(tripReviewProvider(widget.tripId)).valueOrNull;
    final dayAdvices = review?.forDate(selected) ?? const [];

    final counts = <String, int>{};
    for (final item in state.items) {
      counts.update(item.date.toIso(), (v) => v + 1, ifAbsent: () => 1);
    }

    return Scaffold(
      body: Column(
        children: [
          const SizedBox(height: 8),
          DayStrip(
            dates: trip.dates,
            selected: selected,
            onSelect: (date) => setState(() => _selected = date),
            severityByDate: review?.severityByDate() ?? const {},
            itemCountByDate: counts,
          ),
          const SizedBox(height: 8),
          _DaySummaryBar(tripId: widget.tripId, date: selected),
          Expanded(
            child: items.isEmpty && dayAdvices.isEmpty
                ? _EmptyDay(onAdd: () => _openEditor(selected, null))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(8, 8, 16, 96),
                    children: [
                      for (final advice in dayAdvices.take(2))
                        Padding(
                          padding: const EdgeInsets.only(left: 8, bottom: 8),
                          child: AdviceTile(
                            advice: advice,
                            onAction: _actionFor(advice.action, selected),
                          ),
                        ),
                      for (var i = 0; i < items.length; i++)
                        ItemTile(
                          item: items[i],
                          isFirst: i == 0,
                          isLast: i == items.length - 1,
                          gapLabel: i == 0 ? null : _gapLabel(items[i - 1], items[i]),
                          onTap: () => _openEditor(selected, items[i]),
                          onLongPress: () => _itemMenu(items[i]),
                        ),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(selected, null),
        child: const Icon(Icons.add),
      ),
    );
  }

  /// 两项之间的通勤提示：直线距离 + 按推断方式的耗时估算。
  String? _gapLabel(PlanItem previous, PlanItem next) {
    final from = previous.anchorPlace?.latLng;
    final to = next.originPlace?.latLng;
    if (from == null || to == null) return null;
    final meters = GeoUtils.distanceMeters(from, to);
    if (meters < 200) return null;
    final mode = next.isTransport
        ? (next.transportMode ?? TransportMode.inferFromDistance(meters))
        : TransportMode.inferFromDistance(meters);
    final minutes = mode.estimateMinutes(meters);
    final distance =
        meters < 1000 ? '${meters.round()} 米' : '${(meters / 1000).toStringAsFixed(1)} 公里';
    return '${mode.label} 约 ${TimeUtils.formatDuration(minutes)} · $distance';
  }

  VoidCallback? _actionFor(AdviceAction action, DateOnly date) {
    switch (action) {
      case AdviceAction.reorderDay:
        return () async {
          await ref
              .read(tripControllerProvider(widget.tripId).notifier)
              .applySuggestedOrder(date);
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('已按建议重排当天顺序')));
          }
        };
      case AdviceAction.addLodging:
        return () => _openEditor(date, null, preset: ItemCategory.hotel);
      case AdviceAction.addMeal:
        return () => _openEditor(date, null, preset: ItemCategory.food);
      case AdviceAction.none:
      case AdviceAction.adjustTime:
      case AdviceAction.fillLocation:
      case AdviceAction.moveToAnotherDay:
        return null;
    }
  }

  Future<void> _openEditor(DateOnly date, PlanItem? item, {ItemCategory? preset}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ItemEditorScreen(
          tripId: widget.tripId,
          date: date,
          existing: item,
          presetCategory: preset,
        ),
      ),
    );
  }

  Future<void> _itemMenu(PlanItem item) async {
    final state = ref.read(tripControllerProvider(widget.tripId)).valueOrNull;
    if (state == null) return;
    final controller = ref.read(tripControllerProvider(widget.tripId).notifier);

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('挪到其它天'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final target = await showDialog<DateOnly>(
                  context: context,
                  builder: (context) => SimpleDialog(
                    title: const Text('挪到哪一天？'),
                    children: [
                      for (var i = 0; i < state.trip.dates.length; i++)
                        SimpleDialogOption(
                          onPressed: () => Navigator.pop(context, state.trip.dates[i]),
                          child: Text(
                            'D${i + 1} · ${TimeUtils.formatDayLabel(state.trip.dates[i])}',
                          ),
                        ),
                    ],
                  ),
                );
                if (target != null) await controller.moveItemToDate(item, target);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
              title: Text('删除', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () async {
                Navigator.pop(sheetContext);
                await controller.deleteItem(item.id);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 当日一行小结：合计花销 + 条目数，让用户在时间轴上就能看到当天成本。
class _DaySummaryBar extends ConsumerWidget {
  const _DaySummaryBar({required this.tripId, required this.date});

  final String tripId;
  final DateOnly date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budget = ref.watch(tripBudgetProvider(tripId)).valueOrNull;
    final scheme = Theme.of(context).colorScheme;
    if (budget == null) return const SizedBox(height: 4);

    final matches = budget.days.where((d) => d.date == date);
    if (matches.isEmpty) return const SizedBox(height: 4);
    final day = matches.first;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.receipt_long_outlined, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text('当日 ${day.itemCount} 项',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          const Spacer(),
          Text(
            day.total.isZero ? '未记开销' : day.total.format(),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _EmptyDay extends StatelessWidget {
  const _EmptyDay({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_available_outlined, size: 48, color: scheme.outline),
          const SizedBox(height: 10),
          Text('这天还是空的', style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          FilledButton.tonal(onPressed: onAdd, child: const Text('添加第一项安排')),
        ],
      ),
    );
  }
}
