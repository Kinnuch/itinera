import 'package:flutter/material.dart';

import '../../core/time_utils.dart';
import '../../data/models/attachment.dart';
import '../../data/models/plan_item.dart';

/// 时间轴上的一条安排。左侧时间轴，右侧卡片：标题、地点、金额、图片缩略。
class ItemTile extends StatelessWidget {
  const ItemTile({
    super.key,
    required this.item,
    this.onTap,
    this.onLongPress,
    this.isFirst = false,
    this.isLast = false,
    this.gapLabel,
  });

  final PlanItem item;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isFirst;
  final bool isLast;

  /// 与上一项之间的通勤估算，形如「步行 12 分钟 · 900 米」。
  final String? gapLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = item.category.color;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 58,
            child: Column(
              children: [
                Text(
                  item.startMinutes == null
                      ? '--:--'
                      : TimeUtils.formatMinutes(item.startMinutes!),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: item.startMinutes == null ? scheme.outline : scheme.onSurface,
                  ),
                ),
                if (item.endMinutes != null)
                  Text(
                    TimeUtils.formatMinutes(item.endMinutes!),
                    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          _TimelineRail(color: color, isFirst: isFirst, isLast: isLast),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 10, bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (gapLabel != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Icon(Icons.more_vert, size: 13, color: scheme.outline),
                          const SizedBox(width: 2),
                          Text(
                            gapLabel!,
                            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: onTap,
                      onLongPress: onLongPress,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(item.icon, size: 16, color: color),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    item.title,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (item.amount != null)
                                  Text(
                                    item.amount!.format(),
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                              ],
                            ),
                            if (_subtitle != null) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(Icons.place_outlined,
                                      size: 13, color: scheme.onSurfaceVariant),
                                  const SizedBox(width: 3),
                                  Expanded(
                                    child: Text(
                                      _subtitle!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (item.attachments.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 56,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: item.attachments.length,
                                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                                  itemBuilder: (context, i) =>
                                      _Thumb(attachment: item.attachments[i]),
                                ),
                              ),
                            ],
                            if (item.booked || item.headcount > 1) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                children: [
                                  if (item.booked)
                                    _MiniChip(
                                      icon: Icons.check_circle_outline,
                                      label: '已预订',
                                      color: scheme.primary,
                                    ),
                                  if (item.headcount > 1)
                                    _MiniChip(
                                      icon: Icons.group_outlined,
                                      label: '${item.headcount} 人',
                                      color: scheme.onSurfaceVariant,
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? get _subtitle {
    if (item.isTransport) {
      final from = item.fromPlace?.name;
      final to = item.toPlace?.name;
      if (from == null && to == null) return item.carrierNo;
      final route = '${from ?? '?'} → ${to ?? '?'}';
      return item.carrierNo == null ? route : '${item.carrierNo} · $route';
    }
    return item.place?.name;
  }
}

class _TimelineRail extends StatelessWidget {
  const _TimelineRail({required this.color, required this.isFirst, required this.isLast});

  final Color color;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final line = Theme.of(context).colorScheme.outlineVariant;
    return SizedBox(
      width: 16,
      child: Column(
        children: [
          Container(width: 2, height: 6, color: isFirst ? Colors.transparent : line),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Expanded(
            child: Container(
              width: 2,
              color: isLast ? Colors.transparent : line,
            ),
          ),
        ],
      ),
    );
  }
}

/// 缩略图。字节直接在内存里，无需异步解析文件。
class _Thumb extends StatelessWidget {
  const _Thumb({required this.attachment});

  final Attachment attachment;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(
        attachment.bytes,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        // 缩略图只需要 56 逻辑像素，让引擎按需解码而不是把整张图铺进显存。
        cacheWidth: 168,
        gaplessPlayback: true,
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }
}
