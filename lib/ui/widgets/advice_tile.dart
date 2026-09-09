import 'package:flutter/material.dart';

import '../../data/models/enums.dart';
import '../../domain/review/advice.dart';

/// 一条体检建议。右侧可选的操作按钮由 [onAction] 决定是否出现。
class AdviceTile extends StatelessWidget {
  const AdviceTile({super.key, required this.advice, this.onAction, this.onTapItems});

  final Advice advice;
  final VoidCallback? onAction;
  final VoidCallback? onTapItems;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = advice.severity.color;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTapItems,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_iconFor(advice.severity), size: 16, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      advice.title,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      advice.detail,
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.4),
                    ),
                    if (onAction != null && advice.actionLabel != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                          ),
                          onPressed: onAction,
                          child: Text(advice.actionLabel!),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(AdviceSeverity severity) {
    switch (severity) {
      case AdviceSeverity.error:
        return Icons.error_outline;
      case AdviceSeverity.warn:
        return Icons.warning_amber_outlined;
      case AdviceSeverity.info:
        return Icons.lightbulb_outline;
    }
  }
}
