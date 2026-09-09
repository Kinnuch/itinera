import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// 行程内所有「日期」都用本地日历日（截断到 00:00），避免时区抖动导致跨日错位。
class DateOnly implements Comparable<DateOnly> {
  DateOnly(int year, int month, int day) : value = DateTime(year, month, day);

  DateOnly.from(DateTime dt) : value = DateTime(dt.year, dt.month, dt.day);

  factory DateOnly.parse(String iso) => DateOnly.from(DateTime.parse(iso));

  final DateTime value;

  int get year => value.year;
  int get month => value.month;
  int get day => value.day;

  String toIso() => DateFormat('yyyy-MM-dd').format(value);

  DateOnly addDays(int days) => DateOnly.from(value.add(Duration(days: days)));

  int daysUntil(DateOnly other) => other.value.difference(value).inDays;

  DateTime at(TimeOfDay time) => DateTime(year, month, day, time.hour, time.minute);

  @override
  int compareTo(DateOnly other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) => other is DateOnly && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => toIso();
}

class TimeUtils {
  TimeUtils._();

  /// 分钟数（自当日 0 点起）与 TimeOfDay 互转，便于排序与区间运算。
  static int toMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  static TimeOfDay fromMinutes(int minutes) {
    final m = minutes.clamp(0, 24 * 60 - 1).toInt();
    return TimeOfDay(hour: m ~/ 60, minute: m % 60);
  }

  static String formatMinutes(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  /// 把时长渲染成「2 小时 15 分」这种可读文案。
  static String formatDuration(int minutes) {
    if (minutes < 60) return '$minutes 分钟';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '$h 小时' : '$h 小时 $m 分';
  }

  static String formatDayLabel(DateOnly date) => DateFormat('M月d日 EEE', 'zh_CN').format(date.value);

  /// 两个闭开区间 [aStart, aEnd) 与 [bStart, bEnd) 的重叠分钟数。
  static int overlapMinutes(int aStart, int aEnd, int bStart, int bEnd) {
    final start = aStart > bStart ? aStart : bStart;
    final end = aEnd < bEnd ? aEnd : bEnd;
    return end > start ? end - start : 0;
  }
}
