import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/settings_repository.dart';
import '../../providers/app_providers.dart';
import '../widgets/money_field.dart';

/// 设置页：汇总币种、地图密钥、体检阈值。
///
/// 密钥由用户自己填而不是打包进应用：地图 API 按调用量计费，
/// 让每个用户用自己的配额，也免去把密钥硬编码进二进制的泄露风险。
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _amapController = TextEditingController();
  final _mapboxController = TextEditingController();
  bool _loaded = false;

  @override
  void dispose() {
    _amapController.dispose();
    _mapboxController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('读取设置失败：$error')),
        data: (settings) {
          if (!_loaded) {
            _amapController.text = settings.amapWebKey ?? '';
            _mapboxController.text = settings.mapboxToken ?? '';
            _loaded = true;
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _Section('汇总币种'),
              DropdownButtonFormField<String>(
                value: MoneyField.commonCurrencies.contains(settings.homeCurrency)
                    ? settings.homeCurrency
                    : MoneyField.commonCurrencies.first,
                decoration: const InputDecoration(
                  labelText: '新建行程的默认币种',
                  helperText: '所有开销都会换算到行程各自的汇总币种',
                ),
                items: MoneyField.commonCurrencies
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (value) {
                  if (value != null) _save(settings.copyWith(homeCurrency: value));
                },
              ),
              const SizedBox(height: 24),

              _Section('地图服务'),
              Text(
                '国内行程走高德，境外行程走 Mapbox，应用会按行程位置自动选择。'
                '两个都不填也能用：可以在地图上手动点选位置，但没有搜索和真实导航路径。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amapController,
                decoration: const InputDecoration(
                  labelText: '高德 Web 服务 Key',
                  helperText: 'console.amap.com 申请「Web 服务」类型的 Key',
                ),
                onSubmitted: (value) =>
                    _save(settings.copyWith(amapWebKey: () => value.trim())),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _mapboxController,
                decoration: const InputDecoration(
                  labelText: 'Mapbox Access Token',
                  helperText: 'account.mapbox.com 的默认 public token 即可',
                ),
                onSubmitted: (value) =>
                    _save(settings.copyWith(mapboxToken: () => value.trim())),
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () => _save(settings.copyWith(
                  amapWebKey: () => _amapController.text.trim(),
                  mapboxToken: () => _mapboxController.text.trim(),
                )),
                child: const Text('保存密钥'),
              ),
              const SizedBox(height: 24),

              _Section('体检阈值'),
              _SliderRow(
                label: '单日在外时长上限',
                value: settings.maxActiveHoursPerDay.toDouble(),
                min: 6,
                max: 18,
                divisions: 12,
                format: (v) => '${v.round()} 小时',
                onChanged: (v) =>
                    _save(settings.copyWith(maxActiveHoursPerDay: v.round())),
              ),
              _SliderRow(
                label: '单日景点数上限',
                value: settings.maxAttractionsPerDay.toDouble(),
                min: 2,
                max: 10,
                divisions: 8,
                format: (v) => '${v.round()} 个',
                onChanged: (v) =>
                    _save(settings.copyWith(maxAttractionsPerDay: v.round())),
              ),
              _SliderRow(
                label: '空档提醒起点',
                value: settings.idleGapThresholdMinutes.toDouble(),
                min: 60,
                max: 360,
                divisions: 10,
                format: (v) => '${(v / 60).toStringAsFixed(1)} 小时',
                onChanged: (v) =>
                    _save(settings.copyWith(idleGapThresholdMinutes: v.round())),
              ),
              _SliderRow(
                label: '绕路提醒倍数',
                value: settings.detourToleranceRatio,
                min: 1.1,
                max: 2.5,
                divisions: 14,
                format: (v) => '${v.toStringAsFixed(1)} 倍',
                onChanged: (v) => _save(settings.copyWith(detourToleranceRatio: v)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _save(AppSettings next) => ref.read(settingsProvider.notifier).update(next);
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      );
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 14)),
            const Spacer(),
            Text(
              format(value),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
