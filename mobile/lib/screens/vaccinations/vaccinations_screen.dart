import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/common.dart';
import '../../providers/providers.dart';

// -- Provider -----------------------------------------------------------------

final _vaccinationsProvider =
    FutureProvider.family<List<Vaccination>, String>((ref, profileId) async {
  final api = ref.read(apiClientProvider);
  final data = await api
      .get<Map<String, dynamic>>('/api/v1/profiles/$profileId/vaccinations');
  return (data['items'] as List)
      .map((e) => Vaccination.fromJson(e as Map<String, dynamic>))
      .toList();
});

// -- Screen -------------------------------------------------------------------

class VaccinationsScreen extends ConsumerStatefulWidget {
  final String profileId;
  const VaccinationsScreen({super.key, required this.profileId});

  @override
  ConsumerState<VaccinationsScreen> createState() =>
      _VaccinationsScreenState();
}

class _VaccinationsScreenState extends ConsumerState<VaccinationsScreen> {
  Future<void> _delete(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Vaccination'),
        content: const Text('This vaccination will be permanently removed.'),
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
          .delete('/api/v1/profiles/${widget.profileId}/vaccinations/$id');
      ref.invalidate(_vaccinationsProvider(widget.profileId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _showAddSheet() async {
    final vaccineCtrl = TextEditingController();
    final adminDateCtrl = TextEditingController();
    final nextDueCtrl = TextEditingController();
    final lotCtrl = TextEditingController();
    final adminByCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.5,
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
                Text('Add Vaccination',
                    style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 20),
                TextFormField(
                  controller: vaccineCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Vaccine Name *'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: adminDateCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Administered Date',
                    hintText: 'YYYY-MM-DD',
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  readOnly: true,
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(1900),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      adminDateCtrl.text =
                          DateFormat('yyyy-MM-dd').format(picked);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nextDueCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Next Due Date',
                    hintText: 'YYYY-MM-DD',
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  readOnly: true,
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      nextDueCtrl.text =
                          DateFormat('yyyy-MM-dd').format(picked);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: lotCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Lot Number'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: adminByCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Administered By'),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    Navigator.pop(ctx);
                    final body = <String, dynamic>{
                      'vaccine': vaccineCtrl.text.trim(),
                      if (adminDateCtrl.text.trim().isNotEmpty)
                        'administered_at':
                            '${adminDateCtrl.text.trim()}T00:00:00.000Z',
                      if (nextDueCtrl.text.trim().isNotEmpty)
                        'next_due_at':
                            '${nextDueCtrl.text.trim()}T00:00:00.000Z',
                      if (lotCtrl.text.trim().isNotEmpty)
                        'batch_number': lotCtrl.text.trim(),
                      if (adminByCtrl.text.trim().isNotEmpty)
                        'administered_by': adminByCtrl.text.trim(),
                    };
                    try {
                      await ref.read(apiClientProvider).post<void>(
                            '/api/v1/profiles/${widget.profileId}/vaccinations',
                            body: body,
                          );
                      ref.invalidate(
                          _vaccinationsProvider(widget.profileId));
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('$e')));
                      }
                    }
                  },
                  child: const Text('Add Vaccination'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    vaccineCtrl.dispose();
    adminDateCtrl.dispose();
    nextDueCtrl.dispose();
    lotCtrl.dispose();
    adminByCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final asyncVal = ref.watch(_vaccinationsProvider(widget.profileId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vaccinations'),
        automaticallyImplyLeading: false,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSheet,
        tooltip: 'Add vaccination',
        child: const Icon(Icons.add),
      ),
      body: asyncVal.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline, size: 48, color: cs.error),
            const SizedBox(height: 12),
            Text('Failed to load vaccinations', style: tt.bodyLarge),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () =>
                  ref.invalidate(_vaccinationsProvider(widget.profileId)),
              child: const Text('Retry'),
            ),
          ]),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.vaccines_outlined, size: 48, color: cs.outline),
                const SizedBox(height: 12),
                Text('No vaccinations recorded',
                    style:
                        tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _VaccinationCard(
              vaccination: items[i],
              onDelete: () => _delete(items[i].id),
            ),
          );
        },
      ),
    );
  }
}

// -- Card ---------------------------------------------------------------------

class _VaccinationCard extends StatelessWidget {
  final Vaccination vaccination;
  final VoidCallback onDelete;
  const _VaccinationCard(
      {required this.vaccination, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    String? adminDate;
    if (vaccination.administeredAt != null) {
      try {
        final d = DateTime.parse(vaccination.administeredAt!);
        adminDate = DateFormat('MMM d, yyyy').format(d);
      } catch (_) {
        adminDate = vaccination.administeredAt;
      }
    }

    String? nextDue;
    bool isOverdue = false;
    if (vaccination.nextDueAt != null) {
      try {
        final d = DateTime.parse(vaccination.nextDueAt!);
        nextDue = DateFormat('MMM d, yyyy').format(d);
        isOverdue = d.isBefore(DateTime.now());
      } catch (_) {
        nextDue = vaccination.nextDueAt;
      }
    }

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
                child: Icon(Icons.vaccines,
                    size: 20, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vaccination.vaccine,
                      style: tt.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (adminDate != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Administered: $adminDate',
                        style: tt.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                    if (nextDue != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Next due: $nextDue',
                        style: tt.bodySmall?.copyWith(
                          color: isOverdue ? cs.error : cs.onSurfaceVariant,
                          fontWeight:
                              isOverdue ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                    if (vaccination.batchNumber != null ||
                        vaccination.administeredBy != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (vaccination.batchNumber != null)
                            'Lot: ${vaccination.batchNumber}',
                          if (vaccination.administeredBy != null)
                            'By: ${vaccination.administeredBy}',
                        ].join(' \u00b7 '),
                        style: tt.bodySmall?.copyWith(color: cs.outline),
                      ),
                    ],
                  ],
                ),
              ),
              if (isOverdue)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Overdue',
                    style: TextStyle(
                      fontSize: 10,
                      color: cs.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
