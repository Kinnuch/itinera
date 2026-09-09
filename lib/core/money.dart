import 'package:intl/intl.dart';

/// 金额一律用「最小货币单位」的整数存储（人民币=分，日元=円），避免浮点误差。
class Money implements Comparable<Money> {
  const Money(this.minor, this.currency);

  final int minor;
  final String currency;

  static const Map<String, int> _decimals = {
    'JPY': 0, 'KRW': 0, 'VND': 0, 'IDR': 0, 'CLP': 0, 'ISK': 0,
    'KWD': 3, 'BHD': 3, 'OMR': 3, 'JOD': 3, 'TND': 3,
  };

  static int decimalsOf(String currency) => _decimals[currency.toUpperCase()] ?? 2;

  static Money zero(String currency) => Money(0, currency);

  /// 从用户输入的「元」解析，如 "128.50" -> 12850 分。
  static Money? tryParse(String text, String currency) {
    final cleaned = text.replaceAll(RegExp(r'[,\s¥$€£]'), '').trim();
    if (cleaned.isEmpty) return null;
    final value = double.tryParse(cleaned);
    if (value == null) return null;
    final scale = _pow10(decimalsOf(currency));
    return Money((value * scale).round(), currency.toUpperCase());
  }

  static int _pow10(int n) {
    var r = 1;
    for (var i = 0; i < n; i++) {
      r *= 10;
    }
    return r;
  }

  double get amount => minor / _pow10(decimalsOf(currency));

  bool get isZero => minor == 0;

  Money operator +(Money other) {
    _assertSame(other);
    return Money(minor + other.minor, currency);
  }

  Money operator -(Money other) {
    _assertSame(other);
    return Money(minor - other.minor, currency);
  }

  Money operator *(num factor) => Money((minor * factor).round(), currency);

  Money operator /(num divisor) =>
      divisor == 0 ? Money(0, currency) : Money((minor / divisor).round(), currency);

  void _assertSame(Money other) {
    if (other.currency != currency) {
      throw ArgumentError('币种不一致：$currency vs ${other.currency}，请先换算到同一币种');
    }
  }

  /// 按汇率换算到目标币种。[rate] 为「1 单位本币种 = rate 单位目标币种」。
  Money convertTo(String target, double rate) {
    if (target.toUpperCase() == currency) return this;
    final value = amount * rate;
    return Money((value * _pow10(decimalsOf(target))).round(), target.toUpperCase());
  }

  String format({bool withSymbol = true, String? locale}) {
    final fmt = NumberFormat.currency(
      locale: locale ?? 'zh_CN',
      name: withSymbol ? null : '',
      symbol: withSymbol ? _symbolOf(currency) : '',
      decimalDigits: decimalsOf(currency),
    );
    return fmt.format(amount).trim();
  }

  static String _symbolOf(String currency) {
    switch (currency.toUpperCase()) {
      case 'CNY':
        return '¥';
      case 'JPY':
        return 'JP¥';
      case 'USD':
        return r'$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'KRW':
        return '₩';
      case 'HKD':
        return r'HK$';
      case 'TWD':
        return r'NT$';
      case 'THB':
        return '฿';
      case 'SGD':
        return r'S$';
      default:
        return '${currency.toUpperCase()} ';
    }
  }

  @override
  int compareTo(Money other) {
    _assertSame(other);
    return minor.compareTo(other.minor);
  }

  @override
  bool operator ==(Object other) =>
      other is Money && other.minor == minor && other.currency == currency;

  @override
  int get hashCode => Object.hash(minor, currency);

  @override
  String toString() => '$currency $amount';
}
