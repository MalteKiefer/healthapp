import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/providers.dart';

class AppShell extends ConsumerWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(selectedProfileProvider);
    final location = GoRouterState.of(context).uri.toString();

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
        location.startsWith('/documents')) {
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
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_outline),
            selectedIcon: Icon(Icons.favorite),
            label: 'Vitals',
          ),
          NavigationDestination(
            icon: Icon(Icons.science_outlined),
            selectedIcon: Icon(Icons.science),
            label: 'Labs',
          ),
          NavigationDestination(
            icon: Icon(Icons.medication_outlined),
            selectedIcon: Icon(Icons.medication),
            label: 'Meds',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz),
            selectedIcon: Icon(Icons.more_horiz),
            label: 'More',
          ),
        ],
      ),
    );
  }
}
