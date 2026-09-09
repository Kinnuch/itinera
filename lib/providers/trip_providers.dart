import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/time_utils.dart';
import '../data/models/plan_item.dart';
import '../data/models/trip.dart';
import '../domain/budget/budget_summary.dart';
import '../domain/review/itinerary_reviewer.dart';
import '../domain/review/rules/route_rules.dart';
import '../domain/route/route_builder.dart';
import '../services/map/map_provider.dart';
import 'app_providers.dart';

/// 一趟行程的完整可编辑状态。
class TripState {
  const TripState({
    required this.trip,
    required this.items,
    required this.dayNotes,
  });

  final Trip trip;
  final List<PlanItem> items;
  final Map<String, String> dayNotes;

  List<PlanItem> itemsOn(DateOnly date) {
    final list = items.where((i) => i.date == date).toList()
      ..sort((a, b) => a.timelineKey.compareTo(b.timelineKey));
    return list;
  }

  String noteOn(DateOnly date) => dayNotes[date.toIso()] ?? '';

  TripState copyWith({Trip? trip, List<PlanItem>? items, Map<String, String>? dayNotes}) =>
      TripState(
        trip: trip ?? this.trip,
        items: items ?? this.items,
        dayNotes: dayNotes ?? this.dayNotes,
      );
}

/// 行程编辑控制器。所有写操作都先落库再刷新内存状态，
/// 避免「界面显示成功、重启后没了」这类不一致。
class TripController extends FamilyAsyncNotifier<TripState, String> {
  @override
  Future<TripState> build(String tripId) async {
    final tripRepo = ref.read(tripRepositoryProvider);
    final itemRepo = ref.read(itemRepositoryProvider);
    final trip = await tripRepo.findTrip(tripId);
    if (trip == null) throw StateError('行程不存在：$tripId');
    return TripState(
      trip: trip,
      items: await itemRepo.itemsOfTrip(tripId),
      dayNotes: await tripRepo.dayNotes(tripId),
    );
  }

  Future<void> _reload() async {
    final tripId = arg;
    state = await AsyncValue.guard(() => build(tripId));
  }

  Future<void> saveTrip(Trip trip) async {
    await ref.read(tripRepositoryProvider).saveTrip(trip);
    ref.invalidate(tripListProvider);
    await _reload();
  }

  /// 整体平移出发日期，所有安排跟着挪。
  Future<void> shiftDates(int days) async {
    final current = state.valueOrNull;
    if (current == null) return;
    await ref.read(tripRepositoryProvider).shiftTripDates(current.trip, days);
    ref.invalidate(tripListProvider);
    await _reload();
  }

  Future<void> upsertItem(PlanItem item) async {
    await ref.read(itemRepositoryProvider).upsertItem(item);
    await _reload();
  }

  Future<void> deleteItem(String itemId) async {
    await ref.read(itemRepositoryProvider).deleteItem(itemId);
    await ref.read(imageStoreProvider).deleteItemFolder(itemId);
    await _reload();
  }

  Future<void> moveItemToDate(PlanItem item, DateOnly target) async {
    await ref.read(itemRepositoryProvider).moveToDate(item, target);
    await _reload();
  }

  Future<void> reorderDay(DateOnly date, List<PlanItem> ordered) async {
    await ref.read(itemRepositoryProvider).reorder(ordered);
    await _reload();
  }

  /// 采纳「按建议重排」：重排顺序并把原有时间段依次分配下去。
  Future<void> applySuggestedOrder(DateOnly date) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final dayItems = current.itemsOn(date);
    const planner = DayReorderPlanner();
    final reordered = planner.reorder(dayItems);
    final retimed = planner.reassignTimeSlots(reordered, dayItems);

    final repo = ref.read(itemRepositoryProvider);
    for (var i = 0; i < retimed.length; i++) {
      await repo.upsertItem(retimed[i].copyWith(sortOrder: i));
    }
    await _reload();
  }

  Future<void> saveDayNote(DateOnly date, String text) async {
    final current = state.valueOrNull;
    if (current == null) return;
    await ref
        .read(tripRepositoryProvider)
        .saveDayNote(DayNote(tripId: current.trip.id, date: date, text: text));
    await _reload();
  }
}

final tripControllerProvider =
    AsyncNotifierProvider.family<TripController, TripState, String>(TripController.new);

/// 汇率表：只在行程涉及的币种上拉取。
final tripRatesProvider =
    FutureProvider.family<Map<String, double>, String>((ref, tripId) async {
  final state = await ref.watch(tripControllerProvider(tripId).future);
  final currencies = BudgetCalculator.currenciesIn(state.items);
  if (currencies.isEmpty) return {state.trip.homeCurrency.toUpperCase(): 1};
  return ref.read(exchangeRateServiceProvider).ratesTo(state.trip.homeCurrency, currencies);
});

/// 开销汇总。
final tripBudgetProvider =
    FutureProvider.family<TripBudget, String>((ref, tripId) async {
  final state = await ref.watch(tripControllerProvider(tripId).future);
  final rates = await ref.watch(tripRatesProvider(tripId).future);
  return const BudgetCalculator()
      .summarize(trip: state.trip, items: state.items, rates: rates);
});

/// 合理性体检。
final tripReviewProvider =
    FutureProvider.family<ReviewReport, String>((ref, tripId) async {
  final state = await ref.watch(tripControllerProvider(tripId).future);
  final budget = await ref.watch(tripBudgetProvider(tripId).future);
  final settings = await ref.watch(settingsProvider.future);
  return ItineraryReviewer()
      .review(trip: state.trip, items: state.items, budget: budget, settings: settings);
});

/// 当前行程该用哪个地图服务商（境内/境外自动切）。
final tripMapProviderProvider =
    FutureProvider.family<MapProvider, String>((ref, tripId) async {
  final state = await ref.watch(tripControllerProvider(tripId).future);
  final resolver = ref.watch(mapProviderResolverProvider);
  return resolver?.forItems(state.items) ?? const OsmProvider();
});

/// 路线图数据。导航请求有缓存，重复进入不会重复计费。
final tripRouteProvider = FutureProvider.family<TripRoute, String>((ref, tripId) async {
  final state = await ref.watch(tripControllerProvider(tripId).future);
  final provider = await ref.watch(tripMapProviderProvider(tripId).future);
  final builder = RouteBuilder(
    provider: provider,
    routing: ref.read(routingServiceProvider),
  );
  return builder.build(trip: state.trip, items: state.items);
});
