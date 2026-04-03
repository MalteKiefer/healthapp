import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/medication.dart';
import '../../providers/providers.dart';

// -- Provider -----------------------------------------------------------------

final medicationsProvider =
    FutureProvider.family<List<Medication>, String>((ref, profileId) async {
  final api = ref.read(apiClientProvider);
  final data = await api
      .get<Map<String, dynamic>>('/api/v1/profiles/$profileId/medications');
  return (data['items'] as List)
      .map((m) => Medication.fromJson(m as Map<String, dynamic>))
      .toList();
});

// -- Screen -------------------------------------------------------------------

class MedicationsScreen extends ConsumerStatefulWidget {
  final String profileId;
  const MedicationsScreen({super.key, required this.profileId});

  @override
  ConsumerState<MedicationsScreen> createState() => _MedicationsScreenState();
}

class _MedicationsScreenState extends ConsumerState<MedicationsScreen> {
  bool _activeOnly = true;

  Future<void> _delete(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Medication'),
        content: const Text('This medication will be permanently removed.'),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(apiClientProvider)
          .delete('/api/v1/profiles/${widget.profileId}/medications/$id');
      ref.invalidate(medicationsProvider(widget.profileId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _showAddSheet() async {
    final nameCtrl = TextEditingController();
    final dosageCtrl = TextEditingController();
    final freqCtrl = TextEditingController();
    final startCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        minChildSize: 0.45,
        maxChildSize: 0.9,
        builder: (ctx, scrollCtrl) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Form(
            key: formKey,
            child: ListView(
              controller: scrollCtrl,
              children: [
                const SizedBox(height: 8),
                Text('Add Medication',
                    style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 20),
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name *'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dosageCtrl,
                  decoration: const InputDecoration(labelText: 'Dosage'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: freqCtrl,
                  decoration: const InputDecoration(labelText: 'Frequency'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: startCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Start date',
                    hintText: 'YYYY-MM-DD',
                  ),
                  keyboardType: TextInputType.datetime,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    Navigator.pop(ctx);
                    final body = <String, dynamic>{
                      'name': nameCtrl.text.trim(),
                      if (dosageCtrl.text.trim().isNotEmpty)
                        'dosage': dosageCtrl.text.trim(),
                      if (freqCtrl.text.trim().isNotEmpty)
                        'frequency': freqCtrl.text.trim(),
                      if (startCtrl.text.trim().isNotEmpty)
                        'started_at':
                            '${startCtrl.text.trim()}T00:00:00.000Z',
                    };
                    try {
                      await ref.read(apiClientProvider).post<void>(
                            '/api/v1/profiles/${widget.profileId}/medications',
                            body: body,
                          );
                      ref.invalidate(
                          medicationsProvider(widget.profileId));
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('$e')));
                      }
                    }
                  },
                  child: const Text('Add Medication'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    nameCtrl.dispose();
    dosageCtrl.dispose();
    freqCtrl.dispose();
    startCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final async = ref.watch(medicationsProvider(widget.profileId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Medications'),
        automaticallyImplyLeading: false,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSheet,
        tooltip: 'Add medication',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // Filter
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Active'),
                  selected: _activeOnly,
                  onSelected: (_) => setState(() => _activeOnly = true),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('All'),
                  selected: !_activeOnly,
                  onSelected: (_) => setState(() => _activeOnly = false),
                ),
              ],
            ),
          ),
          // List
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.error_outline, size: 48, color: cs.error),
                  const SizedBox(height: 12),
                  Text('Failed to load', style: tt.bodyLarge),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: () => ref
                        .invalidate(medicationsProvider(widget.profileId)),
                    child: const Text('Retry'),
                  ),
                ]),
              ),
              data: (items) {
                final list = _activeOnly
                    ? items.where((m) => m.isActive).toList()
                    : items;
                if (list.isEmpty) {
                  return Center(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.medication_outlined,
                              size: 48, color: cs.outline),
                          const SizedBox(height: 12),
                          Text(
                            _activeOnly
                                ? 'No active medications'
                                : 'No medications recorded',
                            style: tt.bodyLarge
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ]),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _MedCard(
                    med: list[i],
                    onDelete: () => _delete(list[i].id),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// -- Medication Card ----------------------------------------------------------

class _MedCard extends StatelessWidget {
  final Medication med;
  final VoidCallback onDelete;
  const _MedCard({required this.med, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onLongPress: onDelete,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.medication,
                    size: 20, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            med.name,
                            style: tt.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        // Active dot
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: med.isActive
                                ? Colors.green
                                : cs.outlineVariant,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                    if (med.dosage != null || med.frequency != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (med.dosage != null) med.dosage!,
                          if (med.frequency != null) med.frequency!,
                        ].join(' \u00b7 '),
                        style: tt.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
