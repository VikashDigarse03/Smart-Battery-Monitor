import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';

/// Main app shell with bottom navigation bar.
///
/// Shown on all tab routes (dashboard, rooms, devices, settings).
/// Full-screen routes like scan and measurement bypass this shell.
class AppShell extends StatelessWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/dashboard')) return 0;
    if (location.startsWith('/rooms')) return 1;
    if (location.startsWith('/devices')) return 2;
    if (location.startsWith('/settings')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _currentIndex(context);

    return Scaffold(
      body: child,
      // Floating action button for the primary action: Scan Battery
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'scan_fab',
        onPressed: () => context.pushNamed('scan-battery'),
        icon: const Icon(Icons.qr_code_scanner_rounded),
        label: const Text('Scan'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.black,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          switch (index) {
            case 0:
              context.goNamed('dashboard');
            case 1:
              context.goNamed('rooms');
            case 2:
              context.goNamed('devices');
            case 3:
              context.goNamed('settings');
          }
        },
        backgroundColor: AppTheme.surfaceBg,
        indicatorColor: AppTheme.primary.withValues(alpha: 0.15),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.meeting_room_outlined),
            selectedIcon: Icon(Icons.meeting_room_rounded),
            label: 'Rooms',
          ),
          NavigationDestination(
            icon: Icon(Icons.developer_board_outlined),
            selectedIcon: Icon(Icons.developer_board),
            label: 'Devices',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
