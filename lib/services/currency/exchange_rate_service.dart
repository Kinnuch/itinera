import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../../core/money.dart';
import '../../data/db/database.dart';

/// 汇率表：把多币种开销折算到行程的汇总币种。
///
/// 出境游记账离不开它——在日本刷的日元和国内付的定金必须能相加。
/// 汇率入库后长期可用：离线时用上次拉到的值，只在 UI 上标注「汇率更新于 X」。
class ExchangeRateService {
  ExchangeRateService({AppDatabase? db, http.Client? client})
      : _db = db ?? AppDatabase.instance,
        _client = client ?? http.Client();

  final AppDatabase _db;
  final http.Client _client;

  /// 免费、无需密钥的公开汇率源；换成公司自有接口只需改这一处。
  static const _endpoint = 'https://open.er-api.com/v6/latest';

  static const Duration _refreshAfter = Duration(hours: 12);

  /// 返回「1 单位 base = ? 单位 quote」。取不到时返回 null，
  /// 调用方应把该笔开销单独列出而不是按 1:1 蒙混计入总额。
  Future<double?> rate(String base, String quote) async {
    final b = base.toUpperCase();
    final q = quote.toUpperCase();
    if (b == q) return 1;

    final cached = await _readCached(b, q);
    if (cached != null && !cached.stale) return cached.rate;

    final fresh = await _fetchAll(b);
    if (fresh != null) {
      await _persist(b, fresh);
      final value = fresh[q];
      if (value != null) return value;
    }
    return cached?.rate; // 网络失败就用过期值，总比丢数据好
  }

  /// 批量换算：一次拉表，避免 N 笔开销触发 N 次查询。
  Future<Map<String, double>> ratesTo(String target, Set<String> sources) async {
    final result = <String, double>{target.toUpperCase(): 1};
    for (final source in sources.map((s) => s.toUpperCase())) {
      if (result.containsKey(source)) continue;
      final r = await rate(source, target);
      if (r != null) result[source] = r;
    }
    return result;
  }

  /// 用已备好的汇率表折算，缺汇率时返回 null 由调用方标记为「未计入」。
  static Money? convert(Money money, String target, Map<String, double> rates) {
    final t = target.toUpperCase();
    if (money.currency.toUpperCase() == t) return money;
    final r = rates[money.currency.toUpperCase()];
    return r == null ? null : money.convertTo(t, r);
  }

  Future<_CachedRate?> _readCached(String base, String quote) async {
    final db = await _db.database;
    final rows = await db.query(
      'exchange_rates',
      where: 'base = ? AND quote = ?',
      whereArgs: [base, quote],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final fetchedAt = DateTime.tryParse(rows.first['fetched_at'] as String? ?? '');
    return _CachedRate(
      rate: (rows.first['rate'] as num).toDouble(),
      stale: fetchedAt == null || DateTime.now().difference(fetchedAt) > _refreshAfter,
    );
  }

  Future<Map<String, double>?> _fetchAll(String base) async {
    try {
      final res = await _client
          .get(Uri.parse('$_endpoint/$base'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      if (json['result'] != 'success') return null;
      final rates = json['rates'] as Map<String, dynamic>?;
      if (rates == null) return null;
      return rates.map((k, v) => MapEntry(k.toUpperCase(), (v as num).toDouble()));
    } catch (_) {
      return null;
    }
  }

  Future<void> _persist(String base, Map<String, double> rates) async {
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    rates.forEach((quote, value) {
      batch.insert(
        'exchange_rates',
        {'base': base, 'quote': quote, 'rate': value, 'fetched_at': now},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    await batch.commit(noResult: true);
  }
}

class _CachedRate {
  const _CachedRate({required this.rate, required this.stale});

  final double rate;
  final bool stale;
}
