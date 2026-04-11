import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error_messages.dart';
import '../../models/emergency_access.dart';
import '../../providers/emergency_access_provider.dart';

/// Emergency Access screen.
///
/// Three tabs:
///   1. Card preview     — read-only summary returned by the server.
///   2. Access config    — enable/disable + access type + delay + notify.
///   3. Pending requests — incoming requests with Approve / Deny buttons.
///
/// All strings are English. Errors are run through [apiErrorMessage]
/// before being shown to the user. Colors come from the active
/// [ColorScheme] so the screen automatically follows light/dark themes.
class EmergencyAccessScreen extends ConsumerWidget {
  const EmergencyAccessScreen({super.key, required this.profileId});

  final String profileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Emergency access'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Card preview'),
              Tab(text: 'Access config'),
              Tab(text: 'Pending requests'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _CardPreviewTab(profileId: profileId),
            _AccessConfigTab(profileId: profileId),
            const _PendingRequestsTab(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 1 — Card preview
// ---------------------------------------------------------------------------

class _CardPreviewTab extends ConsumerWidget {
  const _CardPreviewTab({required this.profileId});

  final String profileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardAsync = ref.watch(emergencyCardProvider(profileId));
    final scheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(emergencyCardProvider(profileId));
        await ref.read(emergencyCardProvider(profileId).future).catchError((_) {
          // Swallow — error state is rendered below.
          return EmergencyCard.fromJson(const {});
        });
      },
      child: cardAsync.when(
        loading: () => const _CenteredLoading(),
        error: (err, _) => _ErrorView(
          message: apiErrorMessage(err),
          onRetry: () => ref.invalidate(emergencyCardProvider(profileId)),
        ),
        data: (card) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SectionCard(
              title: 'Emergency card',
              icon: Icons.medical_information_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (card.hasUrl) ...[
                    Text(
                      'Public URL',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      card.url!,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: scheme.primary,
                      ),
                    ),
                    const Divider(height: 24),
                  ],
                  _Field(label: 'Blood type', value: card.bloodType),
                  _ListField(label: 'Allergies', items: card.allergies),
                  _ListField(label: 'Medications', items: card.medications),
                  _ListField(label: 'Diagnoses', items: card.diagnoses),
                  if (card.contacts.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Emergency contacts',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    ...card.contacts.map(
                      (c) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          [
                            if ((c.name ?? '').isNotEmpty) c.name,
                            if ((c.relation ?? '').isNotEmpty) '(${c.relation})',
                            if ((c.phone ?? '').isNotEmpty) c.phone,
                            if ((c.email ?? '').isNotEmpty) c.email,
                          ].whereType<String>().join(' · '),
                        ),
                      ),
                    ),
                  ],
                  if ((card.message ?? '').isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Message',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(card.message!),
                  ],
                  if (card.isEmpty && !card.hasUrl) ...[
                    const SizedBox(height: 8),
                    Text(
                      'No emergency card data is available yet.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 2 — Access config
// ---------------------------------------------------------------------------

class _AccessConfigTab extends ConsumerStatefulWidget {
  const _AccessConfigTab({required this.profileId});

  final String profileId;

  @override
  ConsumerState<_AccessConfigTab> createState() => _AccessConfigTabState();
}

class _AccessConfigTabState extends ConsumerState<_AccessConfigTab> {
  String _accessType = EmergencyAccessType.delayed;
  int _delayHours = 48;
  final Set<String> _notifyContacts = <String>{};
  final TextEditingController _newContactCtrl = TextEditingController();
  bool _initialized = false;

  @override
  void dispose() {
    _newContactCtrl.dispose();
    super.dispose();
  }

  void _hydrate(EmergencyAccessConfig cfg) {
    if (_initialized) return;
    _initialized = true;
    _accessType = EmergencyAccessType.all.contains(cfg.accessType)
        ? cfg.accessType
        : EmergencyAccessType.delayed;
    _delayHours = cfg.delayHours;
    _notifyContacts
      ..clear()
      ..addAll(cfg.notifyContacts);
  }

  Future<void> _save({required bool enable}) async {
    final controller =
        ref.read(emergencyAccessConfigControllerProvider.notifier);
    final cfg = EmergencyAccessConfig(
      profileId: widget.profileId,
      enabled: enable,
      accessType: _accessType,
      delayHours: _delayHours,
      notifyContacts: _notifyContacts.toList(),
    );
    final ok = await controller.save(cfg);
    if (!mounted) return;
    final state = ref.read(emergencyAccessConfigControllerProvider);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Emergency access configuration saved.')),
      );
    } else if (state.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(state.error!))),
      );
    }
  }

  Future<void> _disable() async {
    final controller =
        ref.read(emergencyAccessConfigControllerProvider.notifier);
    final ok = await controller.disable(widget.profileId);
    if (!mounted) return;
    final state = ref.read(emergencyAccessConfigControllerProvider);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Emergency access disabled.')),
      );
    } else if (state.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(state.error!))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final configAsync =
        ref.watch(emergencyAccessConfigProvider(widget.profileId));
    final mutation = ref.watch(emergencyAccessConfigControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    return configAsync.when(
      loading: () => const _CenteredLoading(),
      error: (err, _) => _ErrorView(
        message: apiErrorMessage(err),
        onRetry: () =>
            ref.invalidate(emergencyAccessConfigProvider(widget.profileId)),
      ),
      data: (cfg) {
        _hydrate(cfg);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SectionCard(
              title: 'Status',
              icon: Icons.toggle_on_outlined,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: cfg.enabled
                          ? scheme.primaryContainer
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      cfg.enabled ? 'Enabled' : 'Disabled',
                      style: TextStyle(
                        color: cfg.enabled
                            ? scheme.onPrimaryContainer
                            : scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (cfg.enabled)
                    OutlinedButton(
                      onPressed: mutation.busy ? null : _disable,
                      child: const Text('Disable'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Access type',
              icon: Icons.lock_outline,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: EmergencyAccessType.all
                    .map(
                      (t) => InkWell(
                        onTap: mutation.busy
                            ? null
                            : () => setState(() => _accessType = t),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Icon(
                                _accessType == t
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_unchecked,
                                size: 20,
                                color: scheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(EmergencyAccessType.label(t)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Delay (hours)',
              icon: Icons.schedule_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'How long to wait before granting access after a request '
                    'is made. Ignored for "Immediate" and "Manual approval".',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          min: 0,
                          max: 168,
                          divisions: 168,
                          label: '$_delayHours h',
                          value: _delayHours.toDouble().clamp(0, 168),
                          onChanged: mutation.busy
                              ? null
                              : (v) =>
                                  setState(() => _delayHours = v.round()),
                        ),
                      ),
                      SizedBox(
                        width: 56,
                        child: Text(
                          '$_delayHours h',
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Notify contacts',
              icon: Icons.notifications_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Contacts who will be notified when an emergency request '
                    'is made. Add user IDs or emails.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  if (_notifyContacts.isEmpty)
                    Text(
                      'No contacts added yet.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: _notifyContacts
                          .map(
                            (c) => InputChip(
                              label: Text(c),
                              onDeleted: mutation.busy
                                  ? null
                                  : () =>
                                      setState(() => _notifyContacts.remove(c)),
                            ),
                          )
                          .toList(),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newContactCtrl,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                            hintText: 'user@example.com or user-id',
                          ),
                          onSubmitted: (_) => _addContact(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: mutation.busy ? null : _addContact,
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                        mutation.busy ? null : () => _save(enable: true),
                    icon: const Icon(Icons.save_outlined),
                    label: Text(cfg.enabled
                        ? 'Save changes'
                        : 'Enable & save'),
                  ),
                ),
              ],
            ),
            if (mutation.busy)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        );
      },
    );
  }

  void _addContact() {
    final value = _newContactCtrl.text.trim();
    if (value.isEmpty) return;
    setState(() {
      _notifyContacts.add(value);
      _newContactCtrl.clear();
    });
  }
}

// ---------------------------------------------------------------------------
// Tab 3 — Pending requests
// ---------------------------------------------------------------------------

class _PendingRequestsTab extends ConsumerWidget {
  const _PendingRequestsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(emergencyPendingRequestsProvider);
    final mutation = ref.watch(emergencyRequestsControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    Future<void> handleApprove(String id) async {
      final ok = await ref
          .read(emergencyRequestsControllerProvider.notifier)
          .approve(id);
      if (!context.mounted) return;
      final state = ref.read(emergencyRequestsControllerProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Request approved.'
                : apiErrorMessage(state.error ?? 'Approve failed'),
          ),
        ),
      );
    }

    Future<void> handleDeny(String id) async {
      final ok = await ref
          .read(emergencyRequestsControllerProvider.notifier)
          .deny(id);
      if (!context.mounted) return;
      final state = ref.read(emergencyRequestsControllerProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Request denied.'
                : apiErrorMessage(state.error ?? 'Deny failed'),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(emergencyPendingRequestsProvider);
        await ref
            .read(emergencyPendingRequestsProvider.future)
            .catchError((_) => const <EmergencyRequest>[]);
      },
      child: pendingAsync.when(
        loading: () => const _CenteredLoading(),
        error: (err, _) => _ErrorView(
          message: apiErrorMessage(err),
          onRetry: () => ref.invalidate(emergencyPendingRequestsProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return ListView(
              children: [
                const SizedBox(height: 96),
                Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        size: 48,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No pending emergency requests.',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (context, index) =>
                const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final req = items[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        req.displayRequester,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if ((req.profileName ?? '').isNotEmpty)
                        Text(
                          'For profile: ${req.profileName}',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      if (req.requestedAt != null)
                        Text(
                          'Requested: ${req.requestedAt!.toLocal()}',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      if (req.availableAt != null)
                        Text(
                          'Available: ${req.availableAt!.toLocal()}',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      if ((req.reason ?? '').isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(req.reason!),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            onPressed: mutation.busy
                                ? null
                                : () => handleDeny(req.id),
                            icon: const Icon(Icons.close),
                            label: const Text('Deny'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: mutation.busy
                                ? null
                                : () => handleApprove(req.id),
                            icon: const Icon(Icons.check),
                            label: const Text('Approve'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared sub-widgets
// ---------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: scheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    if ((value ?? '').isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 2),
          Text(value!),
        ],
      ),
    );
  }
}

class _ListField extends StatelessWidget {
  const _ListField({required this.label, required this.items});
  final String label;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 2),
          ...items.map((s) => Text('• $s')),
        ],
      ),
    );
  }
}

class _CenteredLoading extends StatelessWidget {
  const _CenteredLoading();
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: scheme.error, size: 40),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurface),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
