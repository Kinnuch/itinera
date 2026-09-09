import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../data/models/trip.dart';
import '../../providers/app_providers.dart';
import 'settings_screen.dart';
import 'trip_create_screen.dart';
import 'trip_home_screen.dart';

class TripListScreen extends ConsumerWidget {
  const TripListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(tripListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的行程'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createTrip(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('新建行程'),
      ),
      body: trips.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('读取失败：$error')),
        data: (list) => list.isEmpty
            ? const _EmptyState()
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) => _TripCard(
                  trip: list[index],
                  onOpen: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => TripHomeScreen(tripId: list[index].id),
                    ),
                  ),
                  onDelete: () => _confirmDelete(context, ref, list[index]),
                ),
              ),
      ),
    );
  }

  Future<void> _createTrip(BuildContext context, WidgetRef ref) async {
    final tripId = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const TripCreateScreen()),
    );
    if (tripId != null && context.mounted) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => TripHomeScreen(tripId: tripId)),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Trip trip) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除「${trip.title}」？'),
        content: const Text('这趟行程的所有安排、金额和图片都会一并删除，无法恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(tripListProvider.notifier).remove(trip.id);
    }
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip, required this.onOpen, required this.onDelete});

  final Trip trip;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final range = '${DateFormat('yyyy年M月d日').format(trip.startDate.value)}'
        ' – ${DateFormat('M月d日').format(trip.endDate.value)}';
    final today = DateTime.now();
    final daysAway = trip.startDate.value.difference(DateTime(today.year, today.month, today.day)).inDays;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onOpen,
        onLongPress: onDelete,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      trip.title,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (daysAway > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$daysAway 天后出发',
                        style: TextStyle(fontSize: 11, color: scheme.onPrimaryContainer),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '$range · ${trip.dayCount} 天'
                '${trip.destination == null ? '' : ' · ${trip.destination}'}',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
              if (trip.budgetMinor != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.account_balance_wallet_outlined,
                        size: 14, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      '预算 ${Money(trip.budgetMinor!, trip.homeCurrency).format()}'
                      '${trip.headcount > 1 ? ' · ${trip.headcount} 人' : ''}',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.luggage_outlined, size: 56, color: scheme.outline),
          const SizedBox(height: 12),
          Text('还没有行程', style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(
            '点右下角新建，先选好出发和返回的日期',
            style: TextStyle(fontSize: 13, color: scheme.outline),
          ),
        ],
      ),
    );
  }
}
