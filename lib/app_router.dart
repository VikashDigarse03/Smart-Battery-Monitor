import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../ui/features/dashboard/views/dashboard_view.dart';
import '../ui/features/rooms/views/rooms_list_view.dart';
import '../ui/features/rooms/views/room_detail_view.dart';
import '../ui/features/rooms/views/rack_detail_view.dart';
import '../ui/features/batteries/views/battery_detail_view.dart';
import '../ui/features/batteries/views/add_battery_view.dart';
import '../ui/features/measurement/views/scan_battery_view.dart';
import '../ui/features/measurement/views/measurement_view.dart';
import '../ui/features/devices/views/devices_list_view.dart';
import '../ui/features/settings/views/settings_view.dart';
import '../ui/features/reports/views/reports_view.dart';
import '../ui/shell/app_shell.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

/// Application router using GoRouter for declarative navigation.
final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/dashboard',
  routes: [
    // ─── Shell Route (Bottom Navigation) ──────────────────────
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: '/dashboard',
          name: 'dashboard',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: DashboardView(),
          ),
        ),
        GoRoute(
          path: '/rooms',
          name: 'rooms',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: RoomsListView(),
          ),
          routes: [
            GoRoute(
              path: ':roomId',
              name: 'room-detail',
              builder: (context, state) {
                final roomId =
                    int.parse(state.pathParameters['roomId']!);
                return RoomDetailView(roomId: roomId);
              },
              routes: [
                GoRoute(
                  path: 'rack/:rackId',
                  name: 'rack-detail',
                  builder: (context, state) {
                    final rackId =
                        int.parse(state.pathParameters['rackId']!);
                    return RackDetailView(rackId: rackId);
                  },
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: '/devices',
          name: 'devices',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: DevicesListView(),
          ),
        ),
        GoRoute(
          path: '/settings',
          name: 'settings',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SettingsView(),
          ),
        ),
      ],
    ),

    // ─── Full-screen routes (no bottom nav) ───────────────────
    GoRoute(
      path: '/scan',
      name: 'scan-battery',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ScanBatteryView(),
    ),
    GoRoute(
      path: '/measure/:batteryDbId',
      name: 'measurement',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final batteryDbId =
            int.parse(state.pathParameters['batteryDbId']!);
        return MeasurementView(batteryDbId: batteryDbId);
      },
    ),
    GoRoute(
      path: '/battery/:batteryDbId',
      name: 'battery-detail',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final batteryDbId =
            int.parse(state.pathParameters['batteryDbId']!);
        return BatteryDetailView(batteryDbId: batteryDbId);
      },
    ),
    GoRoute(
      path: '/add-battery',
      name: 'add-battery',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const AddBatteryView(),
    ),
    GoRoute(
      path: '/reports',
      name: 'reports',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ReportsView(),
    ),
  ],
);
