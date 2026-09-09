import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/time_utils.dart';
import '../../data/models/attachment.dart';
import '../../data/models/enums.dart';
import '../../data/models/location.dart';
import '../../data/models/plan_item.dart';
import '../../providers/app_providers.dart';
import '../../providers/trip_providers.dart';
import '../widgets/money_field.dart';
import '../widgets/photo_strip.dart';
import 'place_picker_screen.dart';

/// 单条安排的编辑页。所有类别共用一个表单，
/// 只有交通额外展示「方式 / 起点 / 终点 / 班次」这一组字段。
class ItemEditorScreen extends ConsumerStatefulWidget {
  const ItemEditorScreen({
    super.key,
    required this.tripId,
    required this.date,
    this.existing,
    this.presetCategory,
  });

  final String tripId;
  final DateOnly date;
  final PlanItem? existing;
  final ItemCategory? presetCategory;

  @override
  ConsumerState<ItemEditorScreen> createState() => _ItemEditorScreenState();
}

class _ItemEditorScreenState extends ConsumerState<ItemEditorScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  late final TextEditingController _carrierController;
  late final TextEditingController _bookingRefController;

  late ItemCategory _category;
  TransportMode _mode = TransportMode.transit;
  TimeOfDay? _start;
  TimeOfDay? _end;
  GeoPlace? _place;
  GeoPlace? _from;
  GeoPlace? _to;
  String _currency = 'CNY';
  int _headcount = 1;
  bool _booked = false;
  List<Attachment> _attachments = [];

  /// 新建时先生成 id：图片要在保存之前就能落到该条目的目录下。
  late final String _itemId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _itemId = existing?.id ?? ref.read(itemRepositoryProvider).newId();
    _category = existing?.category ?? widget.presetCategory ?? ItemCategory.attraction;
    _titleController = TextEditingController(text: existing?.title ?? '');
    _noteController = TextEditingController(text: existing?.note ?? '');
    _carrierController = TextEditingController(text: existing?.carrierNo ?? '');
    _bookingRefController = TextEditingController(text: existing?.bookingRef ?? '');
    _amountController = TextEditingController(
      text: existing?.amount == null ? '' : existing!.amount!.amount.toString(),
    );
    _mode = existing?.transportMode ?? TransportMode.transit;
    _start = existing?.startMinutes == null
        ? null
        : TimeUtils.fromMinutes(existing!.startMinutes!);
    _end = existing?.endMinutes == null ? null : TimeUtils.fromMinutes(existing!.endMinutes!);
    _place = existing?.place;
    _from = existing?.fromPlace;
    _to = existing?.toPlace;
    _booked = existing?.booked ?? false;
    _attachments = List.of(existing?.attachments ?? const []);

    final trip = ref.read(tripControllerProvider(widget.tripId)).valueOrNull?.trip;
    _currency = existing?.currency ?? trip?.homeCurrency ?? 'CNY';
    _headcount = existing?.headcount ?? trip?.headcount ?? 1;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    _carrierController.dispose();
    _bookingRefController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTransport = _category == ItemCategory.transport;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? '添加安排' : '编辑安排'),
        actions: [
          if (widget.existing != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除',
              onPressed: _delete,
            ),
          TextButton(onPressed: _saving ? null : _save, child: const Text('保存')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          _CategorySelector(
            selected: _category,
            onChanged: (c) => setState(() => _category = c),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleController,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: '名称',
              hintText: _hintFor(_category),
            ),
          ),
          const SizedBox(height: 16),

          _SectionLabel('时间'),
          Row(
            children: [
              Expanded(
                child: _TimeButton(
                  label: '开始',
                  value: _start,
                  onPick: () => _pickTime(isStart: true),
                  onClear: () => setState(() => _start = null),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TimeButton(
                  label: '结束',
                  value: _end,
                  onPick: () => _pickTime(isStart: false),
                  onClear: () => setState(() => _end = null),
                ),
              ),
            ],
          ),
          if (_start != null && _end != null && _durationMinutes < 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '结束早于开始 —— 跨夜的班次这样填是对的，会算成次日到达。',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 16),

          _SectionLabel(isTransport ? '路线' : '位置'),
          if (isTransport) ...[
            _TransportModePicker(
              selected: _mode,
              onChanged: (m) => setState(() => _mode = m),
            ),
            const SizedBox(height: 10),
            _PlaceRow(
              icon: Icons.trip_origin,
              label: '出发地',
              place: _from,
              onTap: () => _pickPlace((p) => setState(() => _from = p), _from),
            ),
            const SizedBox(height: 8),
            _PlaceRow(
              icon: Icons.place,
              label: '到达地',
              place: _to,
              onTap: () => _pickPlace((p) => setState(() => _to = p), _to),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _carrierController,
              decoration: const InputDecoration(
                labelText: '班次号（可选）',
                hintText: '如 CA1501 / G7501',
              ),
            ),
          ] else
            _PlaceRow(
              icon: Icons.place_outlined,
              label: '地点',
              place: _place,
              onTap: () => _pickPlace((p) => setState(() => _place = p), _place),
            ),
          const SizedBox(height: 20),

          _SectionLabel('花费'),
          MoneyField(
            controller: _amountController,
            currency: _currency,
            onCurrencyChanged: (value) => setState(() => _currency = value),
            helperText: '留空表示暂未确定',
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('人数'),
              const SizedBox(width: 8),
              Text(
                '（总价填全部人的合计）',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _headcount > 1 ? () => setState(() => _headcount--) : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('$_headcount', style: const TextStyle(fontSize: 16)),
              IconButton(
                onPressed: () => setState(() => _headcount++),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _booked,
            onChanged: (v) => setState(() => _booked = v),
            title: const Text('已预订/已支付'),
            subtitle: const Text('未勾选的大额项会在体检页提醒'),
          ),
          if (_booked) ...[
            const SizedBox(height: 4),
            TextField(
              controller: _bookingRefController,
              decoration: const InputDecoration(
                labelText: '订单号 / 确认码（可选）',
              ),
            ),
          ],
          const SizedBox(height: 20),

          _SectionLabel('图片'),
          PhotoStrip(
            attachments: _attachments,
            imageStore: ref.read(imageStoreProvider),
            onAdd: _addImages,
            onRemove: _removeImage,
          ),
          const SizedBox(height: 20),

          _SectionLabel('备注'),
          TextField(
            controller: _noteController,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: '开放时间、预约要求、想吃什么……',
            ),
          ),
        ],
      ),
    );
  }

  int get _durationMinutes {
    if (_start == null || _end == null) return 0;
    return TimeUtils.toMinutes(_end!) - TimeUtils.toMinutes(_start!);
  }

  String _hintFor(ItemCategory category) {
    switch (category) {
      case ItemCategory.hotel:
        return '如：京都四条大和 ROYNET 酒店';
      case ItemCategory.food:
        return '如：一保堂茶寮 午餐';
      case ItemCategory.attraction:
        return '如：伏见稻荷大社';
      case ItemCategory.transport:
        return '如：关西机场 → 京都站 HARUKA';
      case ItemCategory.shopping:
        return '如：锦市场 采买';
      case ItemCategory.other:
        return '如：换汇 / 寄存行李';
    }
  }

  Future<void> _pickTime({required bool isStart}) async {
    final initial = (isStart ? _start : _end) ??
        (isStart ? const TimeOfDay(hour: 9, minute: 0) : const TimeOfDay(hour: 11, minute: 0));
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
        // 首次设开始时间时，顺手给一个合理的结束时间，省一次操作。
        _end ??= TimeUtils.fromMinutes(
          (TimeUtils.toMinutes(picked) + _defaultDurationMinutes()).clamp(0, 24 * 60 - 1).toInt(),
        );
      } else {
        _end = picked;
      }
    });
  }

  int _defaultDurationMinutes() {
    switch (_category) {
      case ItemCategory.food:
        return 60;
      case ItemCategory.attraction:
        return 120;
      case ItemCategory.hotel:
        return 30;
      case ItemCategory.transport:
        return 60;
      case ItemCategory.shopping:
        return 90;
      case ItemCategory.other:
        return 60;
    }
  }

  Future<void> _pickPlace(ValueChanged<GeoPlace> onPicked, GeoPlace? current) async {
    final picked = await Navigator.of(context).push<GeoPlace>(
      MaterialPageRoute(
        builder: (_) => PlacePickerScreen(tripId: widget.tripId, initial: current),
      ),
    );
    if (picked != null) {
      onPicked(picked);
      // 名称还空着时用地点名兜底，减少一次输入。
      if (_titleController.text.trim().isEmpty && _category != ItemCategory.transport) {
        _titleController.text = picked.name;
      }
    }
  }

  Future<void> _addImages(List<String> paths) async {
    final repo = ref.read(attachmentRepositoryProvider);
    for (final path in paths) {
      final added = await repo.addImage(
        itemId: _itemId,
        sourcePath: path,
        sortOrder: _attachments.length,
      );
      if (!mounted) return;
      setState(() => _attachments = [..._attachments, added]);
    }
  }

  Future<void> _removeImage(Attachment attachment) async {
    await ref.read(attachmentRepositoryProvider).remove(attachment);
    if (!mounted) return;
    setState(() => _attachments = _attachments.where((a) => a.id != attachment.id).toList());
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('给这项安排起个名字')));
      return;
    }

    setState(() => _saving = true);
    try {
      final controller = ref.read(tripControllerProvider(widget.tripId).notifier);
      final amount = Money.tryParse(_amountController.text, _currency);
      final sortOrder = widget.existing?.sortOrder ??
          await ref.read(itemRepositoryProvider).nextSortOrder(widget.tripId, widget.date);

      final item = PlanItem(
        id: _itemId,
        tripId: widget.tripId,
        date: widget.date,
        category: _category,
        title: title,
        startMinutes: _start == null ? null : TimeUtils.toMinutes(_start!),
        endMinutes: _end == null ? null : TimeUtils.toMinutes(_end!),
        place: _category == ItemCategory.transport ? null : _place,
        fromPlace: _category == ItemCategory.transport ? _from : null,
        toPlace: _category == ItemCategory.transport ? _to : null,
        transportMode: _category == ItemCategory.transport ? _mode : null,
        carrierNo: _carrierController.text.trim().isEmpty
            ? null
            : _carrierController.text.trim(),
        amountMinor: amount?.minor,
        currency: amount == null ? null : _currency,
        headcount: _headcount,
        booked: _booked,
        bookingRef: _bookingRefController.text.trim().isEmpty
            ? null
            : _bookingRefController.text.trim(),
        note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
        sortOrder: sortOrder,
        attachments: _attachments,
      );

      await controller.upsertItem(item);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这项安排？'),
        content: const Text('关联的图片也会一起删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(tripControllerProvider(widget.tripId).notifier).deleteItem(_itemId);
    if (mounted) Navigator.of(context).pop();
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
}

class _CategorySelector extends StatelessWidget {
  const _CategorySelector({required this.selected, required this.onChanged});

  final ItemCategory selected;
  final ValueChanged<ItemCategory> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: ItemCategory.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = ItemCategory.values[index];
          final isSelected = category == selected;
          return GestureDetector(
            onTap: () => onChanged(category),
            child: Container(
              width: 66,
              decoration: BoxDecoration(
                color: isSelected
                    ? category.color.withValues(alpha: 0.14)
                    : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? category.color : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(category.icon,
                      size: 20,
                      color: isSelected
                          ? category.color
                          : Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(height: 4),
                  Text(
                    category.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected
                          ? category.color
                          : Theme.of(context).colorScheme.onSurfaceVariant,
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

class _TransportModePicker extends StatelessWidget {
  const _TransportModePicker({required this.selected, required this.onChanged});

  final TransportMode selected;
  final ValueChanged<TransportMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final mode in TransportMode.values)
          ChoiceChip(
            avatar: Icon(mode.icon, size: 16),
            label: Text(mode.label),
            selected: mode == selected,
            onSelected: (_) => onChanged(mode),
          ),
      ],
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.label,
    required this.value,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final TimeOfDay? value;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onPick,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.schedule, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                  Text(
                    value == null ? '未设置' : TimeUtils.formatMinutes(TimeUtils.toMinutes(value!)),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            if (value != null)
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close, size: 16, color: scheme.outline),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({
    required this.icon,
    required this.label,
    required this.place,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final GeoPlace? place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                  Text(
                    place?.name ?? '未设置',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: place == null ? scheme.outline : scheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (place?.address != null)
                    Text(
                      place!.address!,
                      style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (place != null && !place!.hasCoordinates)
              Tooltip(
                message: '没有坐标，路线图会跳过',
                child: Icon(Icons.warning_amber_rounded,
                    size: 16, color: AdviceSeverity.warn.color),
              ),
            Icon(Icons.chevron_right, color: scheme.outline),
          ],
        ),
      ),
    );
  }
}
