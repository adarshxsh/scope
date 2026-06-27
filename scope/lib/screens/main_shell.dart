import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/utils/focus_area_mapper.dart';
import 'package:scope/screens/focus_screen.dart';
import 'package:scope/screens/home_screen.dart';
import 'package:scope/screens/insights_screen.dart';
import 'package:scope/screens/search_screen.dart';
import 'package:scope/screens/settings_screen.dart';
import 'package:scope/theme/app_colors.dart';
import 'package:scope/theme/app_spacing.dart';

/// Root shell with bottom navigation.
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
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final pages = [
          HomeScreen(controller: widget.controller, onStartFocus: _goToFocus),
          FocusScreen(controller: widget.controller, onBackHome: _goToHome),
          SearchScreen(controller: widget.controller),
          InsightsScreen(controller: widget.controller),
          SettingsScreen(controller: widget.controller),
        ];

        return Scaffold(
          extendBody: true,
          body: IndexedStack(index: _currentIndex, children: pages),
          bottomNavigationBar: _buildFloatingNavBar(context),
        );
      },
    );
  }

  Widget _buildFloatingNavBar(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 24,
                spreadRadius: 4,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _NavBarItem(
                    icon: Icons.home_outlined,
                    activeIcon: Icons.home_rounded,
                    label: 'Home',
                    isActive: _currentIndex == 0,
                    onTap: () => _onTabTapped(0),
                  ),
                  _NavBarItem(
                    icon: Icons.center_focus_weak_outlined,
                    activeIcon: Icons.center_focus_strong,
                    label: 'Focus',
                    isActive: _currentIndex == 1,
                    onTap: () => _onTabTapped(1),
                  ),
                  _NavBarItem(
                    icon: Icons.search_outlined,
                    activeIcon: Icons.search_rounded,
                    label: 'Search',
                    isActive: _currentIndex == 2,
                    onTap: () => _onTabTapped(2),
                  ),
                  _NavBarItem(
                    icon: Icons.insights_outlined,
                    activeIcon: Icons.insights_rounded,
                    label: 'Insights',
                    isActive: _currentIndex == 3,
                    onTap: () => _onTabTapped(3),
                  ),
                  _NavBarItem(
                    icon: Icons.settings_outlined,
                    activeIcon: Icons.settings_rounded,
                    label: 'Settings',
                    isActive: _currentIndex == 4,
                    onTap: () => _onTabTapped(4),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onTabTapped(int index) {
    if (widget.controller.inFocusSession && index != 1) {
      widget.controller.recordFocusInterruption();
    }
    setState(() => _currentIndex = index);
  }
}

class _NavBarItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: isActive ? AppSpacing.md : AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isActive ? AppColors.medium.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
              child: Icon(
                isActive ? activeIcon : icon,
                key: ValueKey(isActive),
                color: isActive ? AppColors.medium : AppColors.muted(context),
                size: 24,
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: AppSpacing.xs),
              AnimatedOpacity(
                opacity: isActive ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.medium,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
}
