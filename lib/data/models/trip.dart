import '../../core/money.dart';
import '../../core/time_utils.dart';

/// 一次旅行。日期区间是行程的骨架：改动区间会重排「第 N 天」，
/// 但条目按日期存储，落在区间外的条目不会被删除，只标记为「区间外」提示用户处理。
class Trip {
  const Trip({
    required this.id,
    required this.title,
    required this.startDate,
    required this.endDate,
    required this.homeCurrency,
    this.destination,
    this.coverPath,
    this.budgetMinor,
    this.headcount = 1,
    this.note,
    this.updatedAt,
  });

  final String id;
  final String title;
  final DateOnly startDate;
  final DateOnly endDate;

  /// 汇总口径币种：所有开销都会换算到它再相加。
  final String homeCurrency;

  final String? destination;
  final String? coverPath;
  final int? budgetMinor;
  final int headcount;
  final String? note;
  final DateTime? updatedAt;

  int get dayCount => startDate.daysUntil(endDate) + 1;

  List<DateOnly> get dates =>
      List.generate(dayCount, (i) => startDate.addDays(i), growable: false);

  Money? get budget => budgetMinor == null ? null : Money(budgetMinor!, homeCurrency);

  /// 日均预算，用于单日超支提醒。
  Money? get dailyBudget => budget == null || dayCount == 0 ? null : budget! / dayCount;

  bool containsDate(DateOnly d) =>
      d.compareTo(startDate) >= 0 && d.compareTo(endDate) <= 0;

  int dayIndexOf(DateOnly d) => startDate.daysUntil(d) + 1;

  Trip copyWith({
    String? title,
    DateOnly? startDate,
    DateOnly? endDate,
    String? homeCurrency,
    String? Function()? destination,
    String? Function()? coverPath,
    int? Function()? budgetMinor,
    int? headcount,
    String? Function()? note,
    DateTime? updatedAt,
  }) {
    return Trip(
      id: id,
      title: title ?? this.title,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      homeCurrency: homeCurrency ?? this.homeCurrency,
      destination: destination != null ? destination() : this.destination,
      coverPath: coverPath != null ? coverPath() : this.coverPath,
      budgetMinor: budgetMinor != null ? budgetMinor() : this.budgetMinor,
      headcount: headcount ?? this.headcount,
      note: note != null ? note() : this.note,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toRow() => {
        'id': id,
        'title': title,
        'start_date': startDate.toIso(),
        'end_date': endDate.toIso(),
        'home_currency': homeCurrency,
        'destination': destination,
        'cover_path': coverPath,
        'budget_minor': budgetMinor,
        'headcount': headcount,
        'note': note,
        'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
      };

  static Trip fromRow(Map<String, Object?> row) => Trip(
        id: row['id'] as String,
        title: row['title'] as String? ?? '未命名行程',
        startDate: DateOnly.parse(row['start_date'] as String),
        endDate: DateOnly.parse(row['end_date'] as String),
        homeCurrency: row['home_currency'] as String? ?? 'CNY',
        destination: row['destination'] as String?,
        coverPath: row['cover_path'] as String?,
        budgetMinor: row['budget_minor'] as int?,
        headcount: (row['headcount'] as int?) ?? 1,
        note: row['note'] as String?,
        updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? ''),
      );
}

/// 某一天的备注（住哪个城市、当天主题）。与条目分表，改日期区间时不受影响。
class DayNote {
  const DayNote({required this.tripId, required this.date, required this.text});

  final String tripId;
  final DateOnly date;
  final String text;

  Map<String, Object?> toRow() =>
      {'trip_id': tripId, 'date': date.toIso(), 'text': text};

  static DayNote fromRow(Map<String, Object?> row) => DayNote(
        tripId: row['trip_id'] as String,
        date: DateOnly.parse(row['date'] as String),
        text: row['text'] as String? ?? '',
      );
}
