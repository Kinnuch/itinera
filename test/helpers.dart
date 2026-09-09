import 'package:itinera/core/time_utils.dart';
import 'package:itinera/data/models/enums.dart';
import 'package:itinera/data/models/location.dart';
import 'package:itinera/data/models/plan_item.dart';
import 'package:itinera/data/models/trip.dart';

/// 测试夹具：造一趟固定日期的行程，避免测试依赖「今天」。
Trip makeTrip({
  int days = 3,
  String currency = 'CNY',
  int? budgetMinor,
  int headcount = 1,
}) {
  final start = DateOnly(2026, 4, 10);
  return Trip(
    id: 'trip-1',
    title: '测试行程',
    startDate: start,
    endDate: start.addDays(days - 1),
    homeCurrency: currency,
    budgetMinor: budgetMinor,
    headcount: headcount,
  );
}

int _seq = 0;

PlanItem makeItem({
  required DateOnly date,
  ItemCategory category = ItemCategory.attraction,
  String? title,
  int? startMinutes,
  int? endMinutes,
  double? lat,
  double? lng,
  int? amountMinor,
  String currency = 'CNY',
  TransportMode? mode,
  bool booked = false,
}) {
  final id = 'item-${_seq++}';
  final place = (lat == null || lng == null)
      ? null
      : GeoPlace(name: title ?? id, latitude: lat, longitude: lng);
  return PlanItem(
    id: id,
    tripId: 'trip-1',
    date: date,
    category: category,
    title: title ?? id,
    startMinutes: startMinutes,
    endMinutes: endMinutes,
    place: category == ItemCategory.transport ? null : place,
    fromPlace: category == ItemCategory.transport ? place : null,
    toPlace: category == ItemCategory.transport ? place : null,
    transportMode: mode,
    amountMinor: amountMinor,
    currency: amountMinor == null ? null : currency,
    booked: booked,
  );
}

/// 分钟数辅助：`hm(9, 30)` -> 570。
int hm(int hour, int minute) => hour * 60 + minute;
