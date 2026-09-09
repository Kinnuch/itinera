import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/settings_repository.dart';
import '../../providers/app_providers.dart';
import '../../services/map/tile_sources.dart';
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
              const _Section('汇总币种'),
              DropdownButtonFormField<String>(
                initialValue: MoneyField.commonCurrencies.contains(settings.homeCurrency)
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

              const _Section('底图'),
              Text(
                '底图不需要任何密钥。国内用高德，实测一张瓦片约 60 毫秒；'
                'OpenStreetMap 官方瓦片在国内约 2.5 秒，慢 40 倍，除非在境外否则不建议选。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              RadioGroup<BaseMapChoice>(
                groupValue: settings.baseMap,
                onChanged: (value) {
                  if (value != null) _save(settings.copyWith(baseMap: value));
                },
                child: Column(
                  children: [
                    for (final choice in BaseMapChoice.values)
                      RadioListTile<BaseMapChoice>(
                        value: choice,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(choice.label),
                        subtitle: Text(
                          choice == BaseMapChoice.mapbox &&
                                  (settings.mapboxToken ?? '').isEmpty
                              ? '需要下面的 Access Token，没填则回落到高德'
                              : choice.hint,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              const _Section('搜索与路径规划'),
              Text(
                '这里的密钥只影响「搜地点」「反查地址」「算真实导航路径」三件事，'
                '不影响底图。国内行程用高德，境外用 Mapbox，按行程位置自动选择。'
                '都不填也能用：在地图上长按选点即可，只是路线按直线估算（图上画虚线）。',
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

              const _Section('体检阈值'),
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

  void _save(AppSettings next) => ref.read(settingsProvider.notifier).save(next);
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
