import 'package:flutter_test/flutter_test.dart';
import 'package:itinera/core/money.dart';
import 'package:itinera/data/models/enums.dart';
import 'package:itinera/domain/budget/budget_summary.dart';

import 'helpers.dart';

void main() {
  const calculator = BudgetCalculator();

  test('按天与按分类汇总', () {
    final trip = makeTrip(days: 2);
    final items = [
      makeItem(date: trip.dates[0], category: ItemCategory.hotel, amountMinor: 60000),
      makeItem(date: trip.dates[0], category: ItemCategory.food, amountMinor: 12000),
      makeItem(date: trip.dates[1], category: ItemCategory.food, amountMinor: 8000),
    ];

    final budget = calculator.summarize(trip: trip, items: items, rates: {'CNY': 1});

    expect(budget.total, const Money(80000, 'CNY'));
    expect(budget.days[0].total, const Money(72000, 'CNY'));
    expect(budget.days[1].total, const Money(8000, 'CNY'));
    expect(budget.amountOf(ItemCategory.food), const Money(20000, 'CNY'));
    expect(budget.dailyAverage, const Money(40000, 'CNY'));
  });

  test('多币种按汇率折算到汇总币种', () {
    final trip = makeTrip(days: 1);
    final items = [
      makeItem(date: trip.dates[0], amountMinor: 10000), // 100 CNY
      makeItem(date: trip.dates[0], amountMinor: 5000, currency: 'JPY'), // 5000 日元(0 位小数)
    ];

    // 1 JPY = 0.05 CNY
    final budget =
        calculator.summarize(trip: trip, items: items, rates: {'CNY': 1, 'JPY': 0.05});

    // 100 + 5000*0.05 = 350 元
    expect(budget.total, const Money(35000, 'CNY'));
    expect(budget.uncountedCount, 0);
  });

  test('缺汇率的条目单独计数，不静默混入合计', () {
    final trip = makeTrip(days: 1);
    final items = [
      makeItem(date: trip.dates[0], amountMinor: 10000),
      makeItem(date: trip.dates[0], amountMinor: 3000, currency: 'THB'),
    ];

    final budget = calculator.summarize(trip: trip, items: items, rates: {'CNY': 1});

    expect(budget.total, const Money(10000, 'CNY'));
    expect(budget.uncountedCount, 1);
    expect(budget.days[0].uncounted.single.currency, 'THB');
  });

  test('预算用量与超支', () {
    final trip = makeTrip(days: 2, budgetMinor: 50000);
    final items = [makeItem(date: trip.dates[0], amountMinor: 60000)];

    final budget = calculator.summarize(trip: trip, items: items, rates: {'CNY': 1});

    expect(budget.isOverBudget, isTrue);
    expect(budget.remaining, const Money(-10000, 'CNY'));
    expect(budget.usageRatio, closeTo(1.2, 0.001));
  });

  test('人均按出行人数拆分', () {
    final trip = makeTrip(days: 1, headcount: 3);
    final items = [makeItem(date: trip.dates[0], amountMinor: 30000)];

    final budget = calculator.summarize(trip: trip, items: items, rates: {'CNY': 1});

    expect(budget.perPerson, const Money(10000, 'CNY'));
  });

  group('Money', () {
    test('按币种小数位解析', () {
      expect(Money.tryParse('128.50', 'CNY'), const Money(12850, 'CNY'));
      // 日元没有小数位
      expect(Money.tryParse('1200', 'JPY'), const Money(1200, 'JPY'));
    });

    test('币种不一致的加法直接抛错，不静默相加', () {
      expect(
        () => const Money(100, 'CNY') + const Money(100, 'JPY'),
        throwsArgumentError,
      );
    });
  });
}
