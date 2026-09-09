import 'package:shared_preferences/shared_preferences.dart';

/// 用户级设置：汇总币种、地图密钥、体检阈值。
/// 密钥放在设备本地而不是打包进二进制，方便用户填自己的配额。
class AppSettings {
  const AppSettings({
    this.homeCurrency = 'CNY',
    this.amapWebKey,
    this.mapboxToken,
    this.maxActiveHoursPerDay = 12,
    this.maxAttractionsPerDay = 5,
    this.idleGapThresholdMinutes = 180,
    this.dailyOverBudgetRatio = 1.3,
    this.detourToleranceRatio = 1.4,
  });

  final String homeCurrency;
  final String? amapWebKey;
  final String? mapboxToken;

  /// 单日「净活动时长」上限（含通勤），超过判定为塞太满。
  final int maxActiveHoursPerDay;
  final int maxAttractionsPerDay;

  /// 白天出现超过这么久的空档就提示「可以补点安排」。
  final int idleGapThresholdMinutes;

  /// 单日开销 / 日均预算 超过这个倍数即提醒。
  final double dailyOverBudgetRatio;

  /// 当日实际路径里程 / 最优顺序里程 超过这个倍数即提示重排。
  final double detourToleranceRatio;

  AppSettings copyWith({
    String? homeCurrency,
    String? Function()? amapWebKey,
    String? Function()? mapboxToken,
    int? maxActiveHoursPerDay,
    int? maxAttractionsPerDay,
    int? idleGapThresholdMinutes,
    double? dailyOverBudgetRatio,
    double? detourToleranceRatio,
  }) {
    return AppSettings(
      homeCurrency: homeCurrency ?? this.homeCurrency,
      amapWebKey: amapWebKey != null ? amapWebKey() : this.amapWebKey,
      mapboxToken: mapboxToken != null ? mapboxToken() : this.mapboxToken,
      maxActiveHoursPerDay: maxActiveHoursPerDay ?? this.maxActiveHoursPerDay,
      maxAttractionsPerDay: maxAttractionsPerDay ?? this.maxAttractionsPerDay,
      idleGapThresholdMinutes: idleGapThresholdMinutes ?? this.idleGapThresholdMinutes,
      dailyOverBudgetRatio: dailyOverBudgetRatio ?? this.dailyOverBudgetRatio,
      detourToleranceRatio: detourToleranceRatio ?? this.detourToleranceRatio,
    );
  }
}

class SettingsRepository {
  static const _kHomeCurrency = 'home_currency';
  static const _kAmapKey = 'amap_web_key';
  static const _kMapboxToken = 'mapbox_token';
  static const _kMaxHours = 'max_active_hours';
  static const _kMaxAttractions = 'max_attractions';
  static const _kIdleGap = 'idle_gap_minutes';
  static const _kBudgetRatio = 'daily_budget_ratio';
  static const _kDetourRatio = 'detour_ratio';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    const fallback = AppSettings();
    return AppSettings(
      homeCurrency: prefs.getString(_kHomeCurrency) ?? fallback.homeCurrency,
      amapWebKey: prefs.getString(_kAmapKey),
      mapboxToken: prefs.getString(_kMapboxToken),
      maxActiveHoursPerDay: prefs.getInt(_kMaxHours) ?? fallback.maxActiveHoursPerDay,
      maxAttractionsPerDay: prefs.getInt(_kMaxAttractions) ?? fallback.maxAttractionsPerDay,
      idleGapThresholdMinutes: prefs.getInt(_kIdleGap) ?? fallback.idleGapThresholdMinutes,
      dailyOverBudgetRatio: prefs.getDouble(_kBudgetRatio) ?? fallback.dailyOverBudgetRatio,
      detourToleranceRatio: prefs.getDouble(_kDetourRatio) ?? fallback.detourToleranceRatio,
    );
  }

  Future<void> save(AppSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHomeCurrency, s.homeCurrency);
    await _setOrRemove(prefs, _kAmapKey, s.amapWebKey);
    await _setOrRemove(prefs, _kMapboxToken, s.mapboxToken);
    await prefs.setInt(_kMaxHours, s.maxActiveHoursPerDay);
    await prefs.setInt(_kMaxAttractions, s.maxAttractionsPerDay);
    await prefs.setInt(_kIdleGap, s.idleGapThresholdMinutes);
    await prefs.setDouble(_kBudgetRatio, s.dailyOverBudgetRatio);
    await prefs.setDouble(_kDetourRatio, s.detourToleranceRatio);
  }

  Future<void> _setOrRemove(SharedPreferences prefs, String key, String? value) async {
    if (value == null || value.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }
}
