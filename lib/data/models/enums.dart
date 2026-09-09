import 'package:flutter/material.dart';

/// 行程条目的大类。UI 的表单字段、开销分类、路线图配色都由它驱动。
enum ItemCategory {
  hotel('住宿', Icons.hotel_outlined, Color(0xFF7C4DFF)),
  food('餐饮', Icons.restaurant_outlined, Color(0xFFEF6C00)),
  attraction('景点', Icons.photo_camera_outlined, Color(0xFF00897B)),
  transport('交通', Icons.directions_transit_outlined, Color(0xFF1E88E5)),
  shopping('购物', Icons.shopping_bag_outlined, Color(0xFFD81B60)),
  other('其他', Icons.event_note_outlined, Color(0xFF546E7A));

  const ItemCategory(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;

  static ItemCategory fromName(String? name) =>
      ItemCategory.values.firstWhere((e) => e.name == name, orElse: () => ItemCategory.other);
}

/// 交通方式。速度用于「这段路来得及吗」的可达性推算，单位 km/h。
/// [fixedOverheadMinutes] 是与距离无关的固定开销（值机、安检、候车）。
enum TransportMode {
  walk('步行', Icons.directions_walk, 4.5, 0),
  bike('骑行', Icons.directions_bike, 13, 5),
  transit('公共交通', Icons.directions_subway, 22, 12),
  drive('自驾', Icons.directions_car, 35, 5),
  taxi('打车', Icons.local_taxi, 32, 8),
  coach('长途巴士', Icons.directions_bus, 60, 25),
  train('火车/高铁', Icons.train, 160, 40),
  ferry('轮渡', Icons.directions_boat, 35, 30),
  flight('飞机', Icons.flight, 700, 150);

  const TransportMode(this.label, this.icon, this.speedKmh, this.fixedOverheadMinutes);

  final String label;
  final IconData icon;
  final double speedKmh;
  final int fixedOverheadMinutes;

  /// 直线距离折算到实际耗时：乘绕行系数再加固定开销。
  int estimateMinutes(double straightLineMeters) {
    final detourFactor = this == TransportMode.flight ? 1.05 : 1.35;
    final km = straightLineMeters / 1000 * detourFactor;
    return (km / speedKmh * 60).round() + fixedOverheadMinutes;
  }

  static TransportMode fromName(String? name) =>
      TransportMode.values.firstWhere((e) => e.name == name, orElse: () => TransportMode.walk);

  /// 没有显式交通条目时，按距离猜一个默认方式用于可达性判断。
  static TransportMode inferFromDistance(double meters) {
    if (meters < 1200) return TransportMode.walk;
    if (meters < 25000) return TransportMode.transit;
    if (meters < 300000) return TransportMode.train;
    return TransportMode.flight;
  }
}

/// 建议的严重度。error 会挡在页面顶部，warn 折叠在当日，info 只在体检页出现。
enum AdviceSeverity {
  error('冲突', Color(0xFFD32F2F)),
  warn('提醒', Color(0xFFF57C00)),
  info('建议', Color(0xFF0288D1));

  const AdviceSeverity(this.label, this.color);

  final String label;
  final Color color;
}
