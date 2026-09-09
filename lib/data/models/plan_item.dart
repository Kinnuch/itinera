import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../core/time_utils.dart';
import 'attachment.dart';
import 'enums.dart';
import 'location.dart';

/// 行程里的一条安排。住宿/餐饮/景点/交通/购物共用这一张表，
/// 交通独有的字段（方式、起讫点、班次号）以可空列存在，读写时按 category 解释。
class PlanItem {
  const PlanItem({
    required this.id,
    required this.tripId,
    required this.date,
    required this.category,
    required this.title,
    this.startMinutes,
    this.endMinutes,
    this.place,
    this.fromPlace,
    this.toPlace,
    this.transportMode,
    this.carrierNo,
    this.amountMinor,
    this.currency,
    this.headcount = 1,
    this.booked = false,
    this.bookingRef,
    this.note,
    this.sortOrder = 0,
    this.attachments = const [],
  });

  final String id;
  final String tripId;
  final DateOnly date;
  final ItemCategory category;
  final String title;

  /// 自当日 0 点起的分钟数；null 表示「当天未定时间」，排序时沉到末尾。
  final int? startMinutes;
  final int? endMinutes;

  /// 非交通条目的所在地。
  final GeoPlace? place;

  /// 交通条目的起讫点。
  final GeoPlace? fromPlace;
  final GeoPlace? toPlace;
  final TransportMode? transportMode;

  /// 航班号 / 车次 / 船班。
  final String? carrierNo;

  final int? amountMinor;
  final String? currency;

  /// 人数，用于把「总价」和「人均」都算出来。
  final int headcount;

  final bool booked;
  final String? bookingRef;
  final String? note;
  final int sortOrder;
  final List<Attachment> attachments;

  Money? get amount =>
      (amountMinor != null && currency != null) ? Money(amountMinor!, currency!) : null;

  /// 时间轴上的位置：有开始时间用开始时间，否则用 sortOrder 兜底并排到最后。
  int get timelineKey => startMinutes ?? (24 * 60 + sortOrder);

  int? get durationMinutes =>
      (startMinutes != null && endMinutes != null && endMinutes! >= startMinutes!)
          ? endMinutes! - startMinutes!
          : null;

  bool get isTransport => category == ItemCategory.transport;

  /// 路线图上代表本条目的点：交通取终点（人最终到达的地方），其余取所在地。
  GeoPlace? get anchorPlace => isTransport ? (toPlace ?? fromPlace) : place;

  GeoPlace? get originPlace => isTransport ? (fromPlace ?? toPlace) : place;

  String get timeLabel {
    if (startMinutes == null) return '未定时间';
    final start = TimeUtils.formatMinutes(startMinutes!);
    if (endMinutes == null) return start;
    return '$start – ${TimeUtils.formatMinutes(endMinutes!)}';
  }

  IconData get icon => isTransport ? (transportMode?.icon ?? category.icon) : category.icon;

  PlanItem copyWith({
    String? title,
    DateOnly? date,
    ItemCategory? category,
    int? Function()? startMinutes,
    int? Function()? endMinutes,
    GeoPlace? Function()? place,
    GeoPlace? Function()? fromPlace,
    GeoPlace? Function()? toPlace,
    TransportMode? Function()? transportMode,
    String? Function()? carrierNo,
    int? Function()? amountMinor,
    String? Function()? currency,
    int? headcount,
    bool? booked,
    String? Function()? bookingRef,
    String? Function()? note,
    int? sortOrder,
    List<Attachment>? attachments,
  }) {
    return PlanItem(
      id: id,
      tripId: tripId,
      date: date ?? this.date,
      category: category ?? this.category,
      title: title ?? this.title,
      startMinutes: startMinutes != null ? startMinutes() : this.startMinutes,
      endMinutes: endMinutes != null ? endMinutes() : this.endMinutes,
      place: place != null ? place() : this.place,
      fromPlace: fromPlace != null ? fromPlace() : this.fromPlace,
      toPlace: toPlace != null ? toPlace() : this.toPlace,
      transportMode: transportMode != null ? transportMode() : this.transportMode,
      carrierNo: carrierNo != null ? carrierNo() : this.carrierNo,
      amountMinor: amountMinor != null ? amountMinor() : this.amountMinor,
      currency: currency != null ? currency() : this.currency,
      headcount: headcount ?? this.headcount,
      booked: booked ?? this.booked,
      bookingRef: bookingRef != null ? bookingRef() : this.bookingRef,
      note: note != null ? note() : this.note,
      sortOrder: sortOrder ?? this.sortOrder,
      attachments: attachments ?? this.attachments,
    );
  }

  Map<String, Object?> toRow() => {
        'id': id,
        'trip_id': tripId,
        'date': date.toIso(),
        'category': category.name,
        'title': title,
        'start_minutes': startMinutes,
        'end_minutes': endMinutes,
        ...?place?.toMap('place'),
        ...?fromPlace?.toMap('from'),
        ...?toPlace?.toMap('to'),
        'transport_mode': transportMode?.name,
        'carrier_no': carrierNo,
        'amount_minor': amountMinor,
        'currency': currency,
        'headcount': headcount,
        'booked': booked ? 1 : 0,
        'booking_ref': bookingRef,
        'note': note,
        'sort_order': sortOrder,
      };

  static PlanItem fromRow(Map<String, Object?> row, {List<Attachment> attachments = const []}) {
    return PlanItem(
      id: row['id'] as String,
      tripId: row['trip_id'] as String,
      date: DateOnly.parse(row['date'] as String),
      category: ItemCategory.fromName(row['category'] as String?),
      title: row['title'] as String? ?? '',
      startMinutes: row['start_minutes'] as int?,
      endMinutes: row['end_minutes'] as int?,
      place: GeoPlace.fromMap(row, 'place'),
      fromPlace: GeoPlace.fromMap(row, 'from'),
      toPlace: GeoPlace.fromMap(row, 'to'),
      transportMode:
          row['transport_mode'] == null ? null : TransportMode.fromName(row['transport_mode'] as String),
      carrierNo: row['carrier_no'] as String?,
      amountMinor: row['amount_minor'] as int?,
      currency: row['currency'] as String?,
      headcount: (row['headcount'] as int?) ?? 1,
      booked: (row['booked'] as int? ?? 0) == 1,
      bookingRef: row['booking_ref'] as String?,
      note: row['note'] as String?,
      sortOrder: (row['sort_order'] as int?) ?? 0,
      attachments: attachments,
    );
  }
}
