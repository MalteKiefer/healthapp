import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/i18n/translations.dart';
import '../../providers/providers.dart';

class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

class AppShell extends ConsumerWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(selectedProfileProvider);
    final location = GoRouterState.of(context).uri.toString();
    // Watch language to rebuild nav labels on change
    ref.watch(languageProvider);

    int currentIndex = 0;
    if (location.startsWith('/vitals')) {
      currentIndex = 1;
    } else if (location.startsWith('/labs')) {
      currentIndex = 2;
    } else if (location.startsWith('/medications')) {
      currentIndex = 3;
    } else if (location.startsWith('/more') ||
        location.startsWith('/allergies') ||
        location.startsWith('/diagnoses') ||
        location.startsWith('/vaccinations') ||
        location.startsWith('/appointments') ||
        location.startsWith('/contacts') ||
        location.startsWith('/tasks') ||
        location.startsWith('/diary') ||
        location.startsWith('/symptoms') ||
        location.startsWith('/documents') ||
        location.startsWith('/about') ||
        location.startsWith('/settings')) {
      currentIndex = 4;
    }

    // When no profile is selected, profile-scoped destinations like
    // /vitals/:profileId would resolve to /vitals/ and 404. Fall back to a
    // minimal Home + More nav set until a profile exists and is selected.
    final hasProfile = profile != null;

    final items = hasProfile
        ? <_NavItem>[
            _NavItem(
              icon: Icons.home_outlined,
              selectedIcon: Icons.home,
              label: T.tr('nav.home'),
            ),
            _NavItem(
              icon: Icons.favorite_outline,
              selectedIcon: Icons.favorite,
              label: T.tr('nav.vitals'),
            ),
            _NavItem(
              icon: Icons.science_outlined,
              selectedIcon: Icons.science,
              label: T.tr('nav.labs'),
            ),
            _NavItem(
              icon: Icons.medication_outlined,
              selectedIcon: Icons.medication,
              label: T.tr('nav.meds'),
            ),
            _NavItem(
              icon: Icons.more_horiz,
              selectedIcon: Icons.more_horiz,
              label: T.tr('nav.more'),
            ),
          ]
        : <_NavItem>[
            _NavItem(
              icon: Icons.home_outlined,
              selectedIcon: Icons.home,
              label: T.tr('nav.home'),
            ),
            _NavItem(
              icon: Icons.more_horiz,
              selectedIcon: Icons.more_horiz,
              label: T.tr('nav.more'),
            ),
          ];

    // Collapse current-index into the reduced destination set when no
    // profile is selected (index 0 = Home, 1 = More).
    if (!hasProfile) {
      currentIndex = location.startsWith('/more') ? 1 : 0;
    }

    void onSelected(int i) {
      if (!hasProfile) {
        switch (i) {
          case 0:
            context.go('/home');
          case 1:
            context.go('/more');
        }
        return;
      }
      final pid = profile.id;
      switch (i) {
        case 0:
          context.go('/home');
        case 1:
          context.go('/vitals/$pid');
        case 2:
          context.go('/labs/$pid');
        case 3:
          context.go('/medications/$pid');
        case 4:
          context.go('/more');
      }
    }

    final isWide = MediaQuery.of(context).size.width >= 600;

    if (isWide) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: currentIndex,
                onDestinationSelected: onSelected,
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (final item in items)
                    NavigationRailDestination(
                      icon: Icon(item.icon),
                      selectedIcon: Icon(item.selectedIcon),
                      label: Text(item.label),
                    ),
                ],
              ),
              const VerticalDivider(thickness: 1, width: 1),
              Expanded(child: child),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: onSelected,
        destinations: [
          for (final item in items)
            NavigationDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.selectedIcon),
              label: item.label,
            ),
        ],
      ),
    );
  }
}
