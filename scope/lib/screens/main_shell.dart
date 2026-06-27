import 'package:flutter/material.dart';
import 'package:scope/core/utils/focus_area_mapper.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/screens/focus_screen.dart';
import 'package:scope/screens/home_screen.dart';
import 'package:scope/screens/insights_screen.dart';
import 'package:scope/screens/search_screen.dart';
import 'package:scope/screens/settings_screen.dart';

/// Root shell with bottom navigation across main app sections.
class MainShell extends StatefulWidget {
  final NotificationController controller;

  const MainShell({super.key, required this.controller});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.startPolling();
  }

  @override
  void dispose() {
    widget.controller.stopPolling();
    super.dispose();
  }

  void _goToFocus(FocusFilterType type, [FocusArea? area]) {
    widget.controller.setFilter(type, area);
    setState(() => _currentIndex = 1);
  }

  void _goToHome() => setState(() => _currentIndex = 0);

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(controller: widget.controller, onStartFocus: _goToFocus),
      FocusScreen(controller: widget.controller, onBackHome: _goToHome),
      SearchScreen(controller: widget.controller),
      InsightsScreen(controller: widget.controller),
      SettingsScreen(controller: widget.controller),
    ];

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        return Scaffold(
          body: IndexedStack(
            index: _currentIndex,
            children: pages,
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              if (widget.controller.inFocusSession && index != 1) {
                widget.controller.recordFocusInterruption();
              }
              setState(() => _currentIndex = index);
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.center_focus_weak_outlined),
                selectedIcon: Icon(Icons.center_focus_strong),
                label: 'Focus',
              ),
              NavigationDestination(
                icon: Icon(Icons.search_outlined),
                selectedIcon: Icon(Icons.search),
                label: 'Search',
              ),
              NavigationDestination(
                icon: Icon(Icons.insights_outlined),
                selectedIcon: Icon(Icons.insights),
                label: 'Insights',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        );
      },
    );
  }
}
