import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/i18n/translations.dart';
import '../../providers/providers.dart';

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

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (i) {
          final pid = profile?.id ?? '';
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
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: T.tr('nav.home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.favorite_outline),
            selectedIcon: const Icon(Icons.favorite),
            label: T.tr('nav.vitals'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.science_outlined),
            selectedIcon: const Icon(Icons.science),
            label: T.tr('nav.labs'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.medication_outlined),
            selectedIcon: const Icon(Icons.medication),
            label: T.tr('nav.meds'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.more_horiz),
            selectedIcon: const Icon(Icons.more_horiz),
            label: T.tr('nav.more'),
          ),
        ],
      ),
    );
  }
}
