import 'package:flutter/material.dart';

import 'dashboard_screen.dart';
import 'health_log_screen.dart';
import 'map_screen.dart';
import 'settings_screen.dart';

/// App-level bottom navigation shell. Dashboard/Map/Health Log are all
/// reachable regardless of wearable connection status — only the
/// wearable-specific cards within DashboardScreen depend on it.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _screens = [
    DashboardScreen(),
    MapScreen(),
    HealthLogScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.map_outlined), label: 'Map'),
          NavigationDestination(
              icon: Icon(Icons.monitor_weight_outlined), label: 'Health Log'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}
