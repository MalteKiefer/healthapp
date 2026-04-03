import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/medication.dart';
import '../../providers/providers.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final medicationsProvider =
    FutureProvider.family<List<Medication>, String>((ref, profileId) async {
  final api = ref.read(apiClientProvider);
  final data = await api
      .get<Map<String, dynamic>>('/api/v1/profiles/$profileId/medications');
  return (data['items'] as List)
      .map((m) => Medication.fromJson(m as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class MedicationsScreen extends ConsumerStatefulWidget {
  final String profileId;
  const MedicationsScreen({super.key, required this.profileId});

  @override
  ConsumerState<MedicationsScreen> createState() => _MedicationsScreenState();
}

class _MedicationsScreenState extends ConsumerState<MedicationsScreen> {
  bool _activeOnly = true;

  Future<void> _delete(String id) async {
    try {
      await ref.read(apiClientProvider).delete(
          '/api/v1/profiles/${widget.profileId}/medications/$id');
      ref.invalidate(medicationsProvider(widget.profileId));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _showAddDialog() async {
    final nameCtrl = TextEditingController();
    final dosageCtrl = TextEditingController();
    final freqCtrl = TextEditingController();
    final startCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Medication'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name *'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(controller: dosageCtrl, decoration: const InputDecoration(labelText: 'Dosage')),
              const SizedBox(height: 12),
              TextFormField(controller: freqCtrl, decoration: const InputDecoration(labelText: 'Frequency')),
              const SizedBox(height: 12),
              TextFormField(
                controller: startCtrl,
                decoration: const InputDecoration(labelText: 'Start date (YYYY-MM-DD)'),
                keyboardType: TextInputType.datetime,
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () { if (formKey.currentState!.validate()) Navigator.pop(ctx, true); },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    final body = <String, dynamic>{
      'name': nameCtrl.text.trim(),
      if (dosageCtrl.text.trim().isNotEmpty) 'dosage': dosageCtrl.text.trim(),
      if (freqCtrl.text.trim().isNotEmpty) 'frequency': freqCtrl.text.trim(),
      if (startCtrl.text.trim().isNotEmpty)
        'started_at': '${startCtrl.text.trim()}T00:00:00.000Z',
    };
    try {
      await ref.read(apiClientProvider)
          .post<void>('/api/v1/profiles/${widget.profileId}/medications', body: body);
      ref.invalidate(medicationsProvider(widget.profileId));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final async = ref.watch(medicationsProvider(widget.profileId));

    return Scaffold(
      appBar: AppBar(leading: const BackButton(), title: const Text('Medications')),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        tooltip: 'Add medication',
        child: const Icon(Icons.add),
      ),
      body: Column(children: [
        // Filter chips
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: [
            FilterChip(
              label: const Text('Active'),
              selected: _activeOnly,
              onSelected: (_) => setState(() => _activeOnly = true),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: const Text('All'),
              selected: !_activeOnly,
              onSelected: (_) => setState(() => _activeOnly = false),
            ),
          ]),
        ),
        // List
        Expanded(child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Failed to load', style: tt.bodyLarge),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: () => ref.invalidate(medicationsProvider(widget.profileId)),
              child: const Text('Retry'),
            ),
          ])),
          data: (items) {
            final list = _activeOnly ? items.where((m) => m.isActive).toList() : items;
            if (list.isEmpty) {
              return Center(
                child: Text(
                  _activeOnly ? 'No active medications' : 'No medications recorded',
                  style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _MedCard(
                key: ValueKey(list[i].id),
                med: list[i],
                onDelete: () => _delete(list[i].id),
              ),
            );
          },
        )),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Card
// ---------------------------------------------------------------------------

class _MedCard extends StatelessWidget {
  final Medication med;
  final VoidCallback onDelete;
  const _MedCard({super.key, required this.med, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Dismissible(
      key: ValueKey(med.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async { onDelete(); return false; },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.delete_outline, color: cs.onErrorContainer),
      ),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(med.name, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              if (med.dosage != null || med.frequency != null) ...[
                const SizedBox(height: 4),
                Text(
                  [if (med.dosage != null) med.dosage!, if (med.frequency != null) med.frequency!].join(' · '),
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ])),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              _StatusBadge(isActive: med.isActive),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                color: cs.error,
                onPressed: onDelete,
                tooltip: 'Delete',
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status badge
// ---------------------------------------------------------------------------

class _StatusBadge extends StatelessWidget {
  final bool isActive;
  const _StatusBadge({required this.isActive});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final label = isActive ? 'Active' : 'Inactive';

    final bg = isActive
        ? Color.alphaBlend(cs.primary.withOpacity(0.12), cs.surface)
        : cs.surfaceContainerHighest;
    final fg = isActive ? cs.primary : cs.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: tt.labelSmall?.copyWith(color: fg)),
    );
  }
}
