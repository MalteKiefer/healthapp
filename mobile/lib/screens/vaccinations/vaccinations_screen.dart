import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_error_messages.dart';
import '../../core/i18n/translations.dart';
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
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final tt = Theme.of(ctx).textTheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  T.tr('vaccinations.delete'),
                  style: tt.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  T.tr('vaccinations.delete_body'),
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.error,
                    foregroundColor: cs.onError,
                  ),
                  child: Text(T.tr('common.delete')),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(T.tr('common.cancel')),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (confirmed != true) return;
    await HapticFeedback.mediumImpact();
    try {
      await ref
          .read(apiClientProvider)
          .delete('/api/v1/profiles/${widget.profileId}/vaccinations/$id');
      ref.invalidate(_vaccinationsProvider(widget.profileId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(apiErrorMessage(e)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _showFormSheet({Vaccination? existing}) async {
    final api = ref.read(apiClientProvider);
    final isEdit = existing != null;
    final vaccineCtrl =
        TextEditingController(text: existing?.vaccine ?? '');
    final adminDateCtrl = TextEditingController(
        text: isEdit && existing.administeredAt != null
            ? (existing.administeredAt!.length >= 10
                ? existing.administeredAt!.substring(0, 10)
                : existing.administeredAt!)
            : '');
    final nextDueCtrl = TextEditingController(
        text: isEdit && existing.nextDueAt != null
            ? (existing.nextDueAt!.length >= 10
                ? existing.nextDueAt!.substring(0, 10)
                : existing.nextDueAt!)
            : '');
    final lotCtrl =
        TextEditingController(text: existing?.batchNumber ?? '');
    final adminByCtrl =
        TextEditingController(text: existing?.administeredBy ?? '');
    final tradeNameCtrl =
        TextEditingController(text: existing?.tradeName ?? '');
    final manufacturerCtrl =
        TextEditingController(text: existing?.manufacturer ?? '');
    final doseNumberCtrl = TextEditingController(
        text: existing?.doseNumber?.toString() ?? '');
    final siteCtrl = TextEditingController(text: existing?.site ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    final formKey = GlobalKey<FormState>();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
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
                Text(
                  isEdit
                      ? T.tr('vaccinations.edit')
                      : T.tr('vaccinations.add'),
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: vaccineCtrl,
                  decoration:
                      InputDecoration(labelText: T.tr('field.vaccine_name_required')),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? T.tr('common.required') : null,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: adminDateCtrl,
                  decoration: InputDecoration(
                    labelText: T.tr('field.administered_date'),
                    hintText: 'YYYY-MM-DD',
                    suffixIcon: const Icon(Icons.calendar_today),
                  ),
                  readOnly: true,
                  onTap: () async {
                    final initDate = adminDateCtrl.text.isNotEmpty
                        ? (DateTime.tryParse(adminDateCtrl.text) ??
                            DateTime.now())
                        : DateTime.now();
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: initDate,
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
                  decoration: InputDecoration(
                    labelText: T.tr('field.next_due_date'),
                    hintText: 'YYYY-MM-DD',
                    suffixIcon: const Icon(Icons.calendar_today),
                  ),
                  readOnly: true,
                  onTap: () async {
                    final initDate = nextDueCtrl.text.isNotEmpty
                        ? (DateTime.tryParse(nextDueCtrl.text) ??
                            DateTime.now())
                        : DateTime.now();
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: initDate,
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
                      InputDecoration(labelText: T.tr('field.lot_number')),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: adminByCtrl,
                  decoration:
                      InputDecoration(labelText: T.tr('field.administered_by')),
                ),
                // -- Advanced --
                ExpansionTile(
                  title: Text(T.tr('common.advanced')),
                  children: [
                    TextField(
                      controller: tradeNameCtrl,
                      decoration: InputDecoration(
                          labelText: T.tr('vaccinations.trade_name')),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: manufacturerCtrl,
                      decoration: InputDecoration(
                          labelText: T.tr('vaccinations.manufacturer')),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: doseNumberCtrl,
                      decoration: InputDecoration(
                          labelText: T.tr('vaccinations.dose_number')),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: siteCtrl,
                      decoration: InputDecoration(
                          labelText: T.tr('vaccinations.site')),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesCtrl,
                      decoration: InputDecoration(
                          labelText: T.tr('common.notes')),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                  ],
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
                      if (tradeNameCtrl.text.trim().isNotEmpty)
                        'trade_name': tradeNameCtrl.text.trim(),
                      if (manufacturerCtrl.text.trim().isNotEmpty)
                        'manufacturer': manufacturerCtrl.text.trim(),
                      if (int.tryParse(doseNumberCtrl.text.trim()) != null)
                        'dose_number':
                            int.tryParse(doseNumberCtrl.text.trim()),
                      if (siteCtrl.text.trim().isNotEmpty)
                        'site': siteCtrl.text.trim(),
                      if (notesCtrl.text.trim().isNotEmpty)
                        'notes': notesCtrl.text.trim(),
                    };
                    try {
                      if (isEdit) {
                        await api.patch<void>(
                          '/api/v1/profiles/${widget.profileId}/vaccinations/${existing.id}',
                          body: body,
                        );
                      } else {
                        await api.post<void>(
                          '/api/v1/profiles/${widget.profileId}/vaccinations',
                          body: body,
                        );
                      }
                      ref.invalidate(
                          _vaccinationsProvider(widget.profileId));
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(apiErrorMessage(e)),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    }
                  },
                  child: Text(T.tr('common.save')),
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
    tradeNameCtrl.dispose();
    manufacturerCtrl.dispose();
    doseNumberCtrl.dispose();
    siteCtrl.dispose();
    notesCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final asyncVal = ref.watch(_vaccinationsProvider(widget.profileId));

    return Scaffold(
      appBar: AppBar(
        title: Text(T.tr('vaccinations.title')),
        automaticallyImplyLeading: false,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showFormSheet(),
        tooltip: T.tr('vaccinations.add'),
        child: const Icon(Icons.add),
      ),
      body: asyncVal.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline, size: 48, color: cs.error),
            const SizedBox(height: 12),
            Text(T.tr('vaccinations.failed'), style: tt.bodyLarge),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () =>
                  ref.invalidate(_vaccinationsProvider(widget.profileId)),
              child: Text(T.tr('common.retry')),
            ),
          ]),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.vaccines_outlined, size: 48, color: cs.outline),
                const SizedBox(height: 12),
                Text(T.tr('vaccinations.no_data'),
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
              onTap: () => _showFormSheet(existing: items[i]),
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
  final VoidCallback onTap;
  const _VaccinationCard({
    required this.vaccination,
    required this.onDelete,
    required this.onTap,
  });

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

    return Semantics(
      button: true,
      label: '${vaccination.vaccine}. ${T.tr('vaccinations.edit')}.',
      hint: T.tr('vaccinations.delete'),
      child: Card(
      clipBehavior: Clip.antiAlias,
      child: Tooltip(
        message: T.tr('vaccinations.edit'),
        child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
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
                        '${T.tr('field.administered_date')}: $adminDate',
                        style: tt.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                    if (nextDue != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${T.tr('field.next_due_date')}: $nextDue',
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
                            '${T.tr('field.lot_number')}: ${vaccination.batchNumber}',
                          if (vaccination.administeredBy != null)
                            '${T.tr('field.administered_by')}: ${vaccination.administeredBy}',
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
                    T.tr('status.overdue'),
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
      ),
      ),
    );
  }
}
