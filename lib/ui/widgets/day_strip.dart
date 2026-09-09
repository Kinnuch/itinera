import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/time_utils.dart';
import '../../data/models/enums.dart';

/// 顶部横向日期条。每天一格，显示「D1 / 9月10日 / 周三」，
/// 右上角小圆点表示当天体检的最高严重度。
class DayStrip extends StatelessWidget {
  const DayStrip({
    super.key,
    required this.dates,
    required this.selected,
    required this.onSelect,
    this.severityByDate = const {},
    this.itemCountByDate = const {},
  });

  final List<DateOnly> dates;
  final DateOnly selected;
  final ValueChanged<DateOnly> onSelect;
  final Map<String, AdviceSeverity> severityByDate;
  final Map<String, int> itemCountByDate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 82,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: dates.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final date = dates[index];
          final isSelected = date == selected;
          final severity = severityByDate[date.toIso()];
          final count = itemCountByDate[date.toIso()] ?? 0;

          return GestureDetector(
            onTap: () => onSelect(date),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 66,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? scheme.primary : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Stack(
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'D${index + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? scheme.onPrimary.withValues(alpha: 0.85)
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        DateFormat('M/d').format(date.value),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? scheme.onPrimary : scheme.onSurface,
                        ),
                      ),
                      Text(
                        DateFormat('EEE', 'zh_CN').format(date.value),
                        style: TextStyle(
                          fontSize: 11,
                          color: isSelected
                              ? scheme.onPrimary.withValues(alpha: 0.8)
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        count == 0 ? '空' : '$count 项',
                        style: TextStyle(
                          fontSize: 10,
                          color: isSelected
                              ? scheme.onPrimary.withValues(alpha: 0.7)
                              : scheme.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                  if (severity != null)
                    Positioned(
                      right: 8,
                      top: 6,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: severity.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
