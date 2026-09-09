import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/money.dart';

/// 金额输入：数字框 + 币种下拉。
/// 币种默认跟随行程的汇总币种，出境游改一次即可（表单会记住上次选择）。
class MoneyField extends StatelessWidget {
  const MoneyField({
    super.key,
    required this.controller,
    required this.currency,
    required this.onCurrencyChanged,
    this.label = '金额',
    this.helperText,
  });

  final TextEditingController controller;
  final String currency;
  final ValueChanged<String> onCurrencyChanged;
  final String label;
  final String? helperText;

  /// 常用币种放前面；需要更多时在设置里补。
  static const List<String> commonCurrencies = [
    'CNY', 'JPY', 'USD', 'EUR', 'HKD', 'TWD', 'KRW', 'THB', 'SGD', 'GBP', 'AUD', 'MYR',
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              // 只允许数字和一个小数点，避免各平台数字键盘差异带来的脏输入。
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              labelText: label,
              helperText: helperText,
              prefixText: '${_symbol(currency)} ',
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 104,
          child: DropdownButtonFormField<String>(
            initialValue: commonCurrencies.contains(currency) ? currency : commonCurrencies.first,
            decoration: const InputDecoration(labelText: '币种'),
            items: commonCurrencies
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (value) {
              if (value != null) onCurrencyChanged(value);
            },
          ),
        ),
      ],
    );
  }

  String _symbol(String currency) => Money(0, currency).format().replaceAll(RegExp(r'[\d.,\s]'), '');
}
