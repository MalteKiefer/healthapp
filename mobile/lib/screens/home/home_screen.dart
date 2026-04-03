import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/profile.dart';
import '../../providers/providers.dart';

// ── Module definition ────────────────────────────────────────────────────────

class _Module {
  const _Module(this.label, this.icon, this.route);
  final String label;
  final IconData icon;
  final String route;
}

const _modules = [
  _Module('Vitals',       Icons.monitor_heart_outlined,  '/vitals'),
  _Module('Labs',         Icons.science_outlined,         '/labs'),
  _Module('Medications',  Icons.medication_outlined,      '/medications'),
  _Module('Allergies',    Icons.warning_amber_outlined,   '/allergies'),
  _Module('Diagnoses',    Icons.local_hospital_outlined,  '/diagnoses'),
  _Module('Vaccinations', Icons.vaccines_outlined,        '/vaccinations'),
  _Module('Appointments', Icons.event_outlined,           '/appointments'),
  _Module('Contacts',     Icons.contacts_outlined,        '/contacts'),
  _Module('Tasks',        Icons.task_alt_outlined,        '/tasks'),
  _Module('Diary',        Icons.book_outlined,            '/diary'),
  _Module('Symptoms',     Icons.sick_outlined,            '/symptoms'),
  _Module('Documents',    Icons.folder_outlined,          '/documents'),
];

// Bottom nav indices map to specific modules
const _bottomNavRoutes = [null, '/vitals', '/labs', '/medications', null];

// ── Screen ───────────────────────────────────────────────────────────────────

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _navIndex = 0;

  @override
  void initState() {
    super.initState();
    // Kick off profile fetch and auto-select the first profile
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfiles());
  }

  Future<void> _loadProfiles() async {
    final profiles = await ref.read(profilesProvider('').future);
    if (!mounted) return;
    if (profiles.isNotEmpty && ref.read(selectedProfileProvider) == null) {
      ref.read(selectedProfileProvider.notifier).state = profiles.first;
    }
  }

  void _navigateToModule(String route) {
    final profile = ref.read(selectedProfileProvider);
    if (profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a profile first.')),
      );
      return;
    }
    context.push('$route/${profile.id}');
  }

  void _onNavTap(int index) {
    if (index == 0 || index == 4) {
      setState(() => _navIndex = index);
      return;
    }
    final route = _bottomNavRoutes[index];
    if (route != null) _navigateToModule(route);
  }

  // ── AppBar actions ──────────────────────────────────────────────────────────

  Widget _buildProfileSelector(List<Profile> profiles) {
    final selected = ref.watch(selectedProfileProvider);
    return PopupMenuButton<Profile>(
      tooltip: 'Select profile',
      icon: CircleAvatar(
        radius: 16,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Text(
          (selected?.displayName ?? '?').substring(0, 1).toUpperCase(),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
      onSelected: (p) =>
          ref.read(selectedProfileProvider.notifier).state = p,
      itemBuilder: (_) => profiles
          .map((p) => PopupMenuItem<Profile>(
                value: p,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor:
                          Theme.of(context).colorScheme.secondaryContainer,
                      child: Text(
                        p.displayName.substring(0, 1).toUpperCase(),
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(p.displayName),
                    if (selected?.id == p.id) ...[
                      const Spacer(),
                      Icon(Icons.check,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary),
                    ],
                  ],
                ),
              ))
          .toList(),
    );
  }

  // ── Module grid ─────────────────────────────────────────────────────────────

  Widget _buildModuleGrid() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.1,
        ),
        itemCount: _modules.length,
        itemBuilder: (_, i) => _ModuleCard(
          module: _modules[i],
          onTap: () => _navigateToModule(_modules[i].route),
        ),
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final profilesAsync = ref.watch(profilesProvider(''));

    return Scaffold(
      appBar: AppBar(
        title: const Text('HealthVault'),
        centerTitle: false,
        actions: [
          profilesAsync.when(
            data: (profiles) => profiles.isNotEmpty
                ? _buildProfileSelector(profiles)
                : const SizedBox.shrink(),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (_, __) => IconButton(
              icon: const Icon(Icons.person_outline),
              tooltip: 'No profiles',
              onPressed: null,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: profilesAsync.when(
        data: (profiles) {
          final selected = ref.watch(selectedProfileProvider);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selected != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Text('Hello, ${selected.displayName}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
              Expanded(child: _buildModuleGrid()),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text('Failed to load profiles', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(e.toString(), textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 24),
              FilledButton.tonal(
                  onPressed: () => ref.invalidate(profilesProvider('')),
                  child: const Text('Retry')),
            ]),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: _onNavTap,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.monitor_heart_outlined),
              selectedIcon: Icon(Icons.monitor_heart),
              label: 'Vitals'),
          NavigationDestination(
              icon: Icon(Icons.science_outlined),
              selectedIcon: Icon(Icons.science),
              label: 'Labs'),
          NavigationDestination(
              icon: Icon(Icons.medication_outlined),
              selectedIcon: Icon(Icons.medication),
              label: 'Meds'),
          NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view),
              label: 'More'),
        ],
      ),
    );
  }
}

// ── Module card widget ───────────────────────────────────────────────────────

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.module, required this.onTap});

  final _Module module;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(module.icon,
                    size: 28, color: cs.onPrimaryContainer),
              ),
              const SizedBox(height: 12),
              Text(
                module.label,
                style: Theme.of(context).textTheme.labelLarge,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
