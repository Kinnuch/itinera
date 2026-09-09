import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../providers/app_providers.dart';
import '../widgets/money_field.dart';

/// 新建行程：功能点 1「选择旅行日期」的入口。
/// 用系统的日期区间选择器，Android 走 Material、iOS 走同一套但适配了手势返回。
class TripCreateScreen extends ConsumerStatefulWidget {
  const TripCreateScreen({super.key});

  @override
  ConsumerState<TripCreateScreen> createState() => _TripCreateScreenState();
}

class _TripCreateScreenState extends ConsumerState<TripCreateScreen> {
  final _titleController = TextEditingController();
  final _destinationController = TextEditingController();
  final _budgetController = TextEditingController();

  DateTimeRange? _range;
  String _currency = 'CNY';
  int _headcount = 1;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // 默认给一段「下周出发、玩 4 天」的区间，减少空白表单的启动阻力。
    final start = DateTime.now().add(const Duration(days: 7));
    _range = DateTimeRange(
      start: DateTime(start.year, start.month, start.day),
      end: DateTime(start.year, start.month, start.day).add(const Duration(days: 3)),
    );
    final settings = ref.read(settingsProvider).valueOrNull;
    if (settings != null) _currency = settings.homeCurrency;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _destinationController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final range = _range;

    return Scaffold(
      appBar: AppBar(title: const Text('新建行程')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            controller: _titleController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: '行程名称',
              hintText: '例如：京都赏枫 5 日',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _destinationController,
            decoration: const InputDecoration(
              labelText: '目的地（可选）',
              hintText: '用于地图初始定位',
            ),
          ),
          const SizedBox(height: 20),
          Text('旅行日期', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _pickRange,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.date_range_outlined, color: scheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            range == null
                                ? '选择出发与返回日期'
                                : '${DateFormat('yyyy年M月d日 EEE', 'zh_CN').format(range.start)}'
                                    '  →  ${DateFormat('M月d日 EEE', 'zh_CN').format(range.end)}',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                          if (range != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              '共 ${range.duration.inDays + 1} 天',
                              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: scheme.outline),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('预算与人数（可选）', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          MoneyField(
            controller: _budgetController,
            currency: _currency,
            onCurrencyChanged: (value) => setState(() => _currency = value),
            label: '总预算',
            helperText: '所有开销都会换算成这个币种来汇总',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('出行人数'),
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
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _submit,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: _saving
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('创建行程'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      // 允许往前一年选：补记已经出发过的行程也是常见用法。
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      initialDateRange: _range,
      helpText: '选择旅行日期',
      saveText: '确定',
    );
    if (picked != null) setState(() => _range = picked);
  }

  Future<void> _submit() async {
    final range = _range;
    if (range == null) {
      _toast('请先选择旅行日期');
      return;
    }
    final title = _titleController.text.trim().isEmpty
        ? '${DateFormat('M月d日').format(range.start)} 出发的行程'
        : _titleController.text.trim();

    setState(() => _saving = true);
    try {
      final trip = await ref.read(tripListProvider.notifier).create(
            title: title,
            start: range.start,
            end: range.end,
            homeCurrency: _currency,
            destination: _destinationController.text.trim().isEmpty
                ? null
                : _destinationController.text.trim(),
            budgetMinor: Money.tryParse(_budgetController.text, _currency)?.minor,
            headcount: _headcount,
          );
      if (mounted) Navigator.of(context).pop(trip.id);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
