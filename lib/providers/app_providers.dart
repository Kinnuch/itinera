import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/time_utils.dart';
import '../data/repositories/attachment_repository.dart';
import '../data/repositories/item_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/trip_repository.dart';
import '../data/models/trip.dart';
import '../services/currency/exchange_rate_service.dart';
import '../services/map/map_provider.dart';
import '../services/map/map_provider_resolver.dart';
import '../services/map/routing_service.dart';
import '../services/media/image_store.dart';

final tripRepositoryProvider = Provider((ref) => TripRepository());
final itemRepositoryProvider = Provider((ref) => ItemRepository());
final attachmentRepositoryProvider = Provider((ref) => AttachmentRepository());
final settingsRepositoryProvider = Provider((ref) => SettingsRepository());
final imageStoreProvider = Provider((ref) => ImageStore());
final exchangeRateServiceProvider = Provider((ref) => ExchangeRateService());
final routingServiceProvider = Provider((ref) => RoutingService());

/// 全局设置。改动后所有依赖它的派生状态（体检阈值、地图密钥）自动重算。
class SettingsController extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() => ref.read(settingsRepositoryProvider).load();

  Future<void> save(AppSettings next) async {
    state = AsyncData(next);
    await ref.read(settingsRepositoryProvider).save(next);
  }
}

final settingsProvider =
    AsyncNotifierProvider<SettingsController, AppSettings>(SettingsController.new);

/// 行程列表。
class TripListController extends AsyncNotifier<List<Trip>> {
  @override
  Future<List<Trip>> build() => ref.read(tripRepositoryProvider).listTrips();

  Future<Trip> create({
    required String title,
    required DateTime start,
    required DateTime end,
    required String homeCurrency,
    String? destination,
    int? budgetMinor,
    int headcount = 1,
  }) async {
    final repo = ref.read(tripRepositoryProvider);
    final trip = await repo.createTrip(
      title: title,
      startDate: DateOnly.from(start),
      endDate: DateOnly.from(end),
      homeCurrency: homeCurrency,
      destination: destination,
      budgetMinor: budgetMinor,
      headcount: headcount,
    );
    ref.invalidateSelf();
    return trip;
  }

  Future<void> remove(String tripId) async {
    await ref.read(tripRepositoryProvider).deleteTrip(tripId);
    ref.invalidateSelf();
  }
}

final tripListProvider =
    AsyncNotifierProvider<TripListController, List<Trip>>(TripListController.new);

/// 当前生效的地图服务商。密钥变化或行程位置变化时会重新解析。
final mapProviderResolverProvider = Provider<MapProviderResolver?>((ref) {
  final settings = ref.watch(settingsProvider).valueOrNull;
  return settings == null ? null : MapProviderResolver(settings);
});

/// 没有具体行程时（设置页预览底图）用的默认服务商。
final defaultMapProviderProvider = Provider<MapProvider>((ref) {
  final resolver = ref.watch(mapProviderResolverProvider);
  return resolver?.forPoints(const []) ?? const OsmProvider();
});
