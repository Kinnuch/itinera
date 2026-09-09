import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/enums.dart';
import '../../providers/trip_providers.dart';
import 'budget_view.dart';
import 'day_plan_view.dart';
import 'review_view.dart';
import 'route_map_view.dart';

/// 行程主容器：四个页签对应四项核心功能。
/// 状态（当前选中的日期）提到这里，切页签回来不会丢。
class TripHomeScreen extends ConsumerStatefulWidget {
  const TripHomeScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<TripHomeScreen> createState() => _TripHomeScreenState();
}

class _TripHomeScreenState extends ConsumerState<TripHomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final tripState = ref.watch(tripControllerProvider(widget.tripId));
    final review = ref.watch(tripReviewProvider(widget.tripId)).valueOrNull;
    final errorCount = review?.errorCount ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(tripState.valueOrNull?.trip.title ?? '行程'),
      ),
      body: tripState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('打开失败：$error')),
        data: (_) => IndexedStack(
          index: _tab,
          children: [
            DayPlanView(tripId: widget.tripId),
            BudgetView(tripId: widget.tripId),
            ReviewView(tripId: widget.tripId),
            RouteMapView(tripId: widget.tripId),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.view_agenda_outlined),
            selectedIcon: Icon(Icons.view_agenda),
            label: '行程',
          ),
          const NavigationDestination(
            icon: Icon(Icons.pie_chart_outline),
            selectedIcon: Icon(Icons.pie_chart),
            label: '开销',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: errorCount > 0,
              label: Text('$errorCount'),
              backgroundColor: AdviceSeverity.error.color,
              child: const Icon(Icons.fact_check_outlined),
            ),
            selectedIcon: const Icon(Icons.fact_check),
            label: '体检',
          ),
          const NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: '路线',
          ),
        ],
      ),
    );
  }
}
