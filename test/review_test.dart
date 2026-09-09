import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:itinera/data/models/enums.dart';
import 'package:itinera/data/models/plan_item.dart';
import 'package:itinera/data/models/trip.dart';
import 'package:itinera/data/repositories/settings_repository.dart';
import 'package:itinera/domain/budget/budget_summary.dart';
import 'package:itinera/domain/review/itinerary_reviewer.dart';

import 'helpers.dart';

void main() {
  // 规则文案用 DateFormat('...', 'zh_CN')，纯 Dart 测试里必须先加载 locale 数据
  setUpAll(() => initializeDateFormatting('zh_CN'));

  const settings = AppSettings();
  const calculator = BudgetCalculator();
  final reviewer = ItineraryReviewer();

  ReviewReport run(List<PlanItem> items, {Trip? trip}) {
    final t = trip ?? makeTrip();
    final budget = calculator.summarize(trip: t, items: items, rates: const {'CNY': 1});
    return reviewer.review(trip: t, items: items, budget: budget, settings: settings);
  }

  test('时间重叠报冲突', () {
    final trip = makeTrip();
    final report = run(
      [
        makeItem(date: trip.dates[0], startMinutes: hm(9, 0), endMinutes: hm(11, 0)),
        makeItem(date: trip.dates[0], startMinutes: hm(10, 0), endMinutes: hm(12, 0)),
      ],
      trip: trip,
    );

    expect(report.advices.any((a) => a.code == 'time_overlap'), isTrue);
    expect(
      report.advices.firstWhere((a) => a.code == 'time_overlap').severity,
      AdviceSeverity.error,
    );
  });

  test('相邻两点距离太远、间隔太短，判为赶不到', () {
    final trip = makeTrip();
    // 北京天安门 -> 上海外滩，中间只留 30 分钟
    final report = run(
      [
        makeItem(
          date: trip.dates[0],
          startMinutes: hm(9, 0),
          endMinutes: hm(10, 0),
          lat: 39.9087,
          lng: 116.3975,
        ),
        makeItem(
          date: trip.dates[0],
          startMinutes: hm(10, 30),
          endMinutes: hm(12, 0),
          lat: 31.2397,
          lng: 121.4900,
        ),
      ],
      trip: trip,
    );

    expect(report.advices.any((a) => a.code == 'travel_infeasible'), isTrue);
  });

  test('同城两点、间隔充足时不报可达性问题', () {
    final trip = makeTrip();
    // 两点相距约 1.5 公里，中间留了 2 小时
    final report = run(
      [
        makeItem(
          date: trip.dates[0],
          startMinutes: hm(9, 0),
          endMinutes: hm(10, 0),
          lat: 35.0116,
          lng: 135.7681,
        ),
        makeItem(
          date: trip.dates[0],
          startMinutes: hm(12, 0),
          endMinutes: hm(13, 0),
          lat: 35.0250,
          lng: 135.7681,
        ),
      ],
      trip: trip,
    );

    expect(report.advices.any((a) => a.code == 'travel_infeasible'), isFalse);
  });

  test('中间日缺住宿会提醒，最后一天不提醒', () {
    final trip = makeTrip(days: 3);
    final report = run(
      [
        makeItem(date: trip.dates[0], startMinutes: hm(9, 0), endMinutes: hm(10, 0)),
        makeItem(date: trip.dates[1], startMinutes: hm(9, 0), endMinutes: hm(10, 0)),
        makeItem(date: trip.dates[2], startMinutes: hm(9, 0), endMinutes: hm(10, 0)),
      ],
      trip: trip,
    );

    final lodging = report.advices.where((a) => a.code == 'missing_lodging').toList();
    expect(lodging.length, 2);
    expect(lodging.any((a) => a.date == trip.dates[2]), isFalse);
  });

  test('单日景点超上限报过载', () {
    final trip = makeTrip();
    final report = run(
      [
        for (var i = 0; i < 7; i++)
          makeItem(
            date: trip.dates[0],
            category: ItemCategory.attraction,
            startMinutes: hm(8 + i, 0),
            endMinutes: hm(8 + i, 45),
          ),
      ],
      trip: trip,
    );

    expect(report.advices.any((a) => a.code == 'day_overloaded_attractions'), isTrue);
  });

  test('落在行程区间外的条目报错', () {
    final trip = makeTrip(days: 2);
    final report = run(
      [makeItem(date: trip.startDate.addDays(5))],
      trip: trip,
    );

    expect(report.advices.any((a) => a.code == 'item_out_of_range'), isTrue);
  });

  test('健康分随冲突数下降', () {
    final trip = makeTrip();
    final clean = run(const <PlanItem>[], trip: trip);
    final messy = run(
      [
        makeItem(date: trip.dates[0], startMinutes: hm(9, 0), endMinutes: hm(11, 0)),
        makeItem(date: trip.dates[0], startMinutes: hm(10, 0), endMinutes: hm(12, 0)),
      ],
      trip: trip,
    );

    expect(messy.healthScore, lessThan(clean.healthScore));
  });
}
