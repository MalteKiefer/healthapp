import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/api/api_error_messages.dart';
import '../../core/i18n/translations.dart';
import '../../models/medication.dart';
import '../../providers/providers.dart';
import '../../widgets/error_widget.dart';
import '../../widgets/loading_widget.dart';

// -- Provider -----------------------------------------------------------------

final medicationsProvider =
    FutureProvider.family<List<Medication>, String>((ref, profileId) async {
  final api = ref.read(apiClientProvider);
  final crypto = ref.watch(e2eCryptoServiceProvider);
  final data = await api
      .get<Map<String, dynamic>>('/api/v1/profiles/$profileId/medications');
  final rawItems = (data['items'] as List?) ?? const [];
  final decrypted = await crypto.decryptRows(
    rows: rawItems,
    profileId: profileId,
    entityType: 'medications',
  );
  return decrypted.map(Medication.fromJson).toList();
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

  Future<bool> _confirmDeleteSheet() async {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final result = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                T.tr('meds.delete'),
                style: tt.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                T.tr('meds.delete_body'),
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: cs.error,
                  foregroundColor: cs.onError,
                ),
                icon: const Icon(Icons.delete_outline),
                label: Text(T.tr('common.delete')),
                onPressed: () => Navigator.pop(ctx, true),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(T.tr('common.cancel')),
              ),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }

  Future<void> _delete(String id) async {
    final confirmed = await _confirmDeleteSheet();
    if (!confirmed) return;
    await HapticFeedback.mediumImpact();
    try {
      await ref
          .read(apiClientProvider)
          .delete('/api/v1/profiles/${widget.profileId}/medications/$id');
      ref.invalidate(medicationsProvider(widget.profileId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(apiErrorMessage(e)),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _showFormSheet({Medication? existing}) async {
    final api = ref.read(apiClientProvider);
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final dosageCtrl = TextEditingController(text: existing?.dosage ?? '');
    final unitCtrl = TextEditingController(text: existing?.unit ?? '');
    final freqCtrl = TextEditingController(text: existing?.frequency ?? '');
    final startCtrl = TextEditingController(
        text: isEdit && existing.startedAt != null
            ? (existing.startedAt!.length >= 10
                ? existing.startedAt!.substring(0, 10)
                : existing.startedAt!)
            : '');
    final endCtrl = TextEditingController(
        text: isEdit && existing.endedAt != null
            ? (existing.endedAt!.length >= 10
                ? existing.endedAt!.substring(0, 10)
                : existing.endedAt!)
            : '');
    final prescribedByCtrl =
        TextEditingController(text: existing?.prescribedBy ?? '');
    final reasonCtrl = TextEditingController(text: existing?.reason ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    final formKey = GlobalKey<FormState>();
    String? route = existing?.route;

    const routes = [
      'oral',
      'iv',
      'im',
      'sc',
      'topical',
      'inhaled',
      'rectal',
      'other'
    ];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.80,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (ctx, scrollCtrl) => StatefulBuilder(
          builder: (ctx, setSheetState) => Padding(
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
                    isEdit ? T.tr('meds.edit') : T.tr('meds.add'),
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: nameCtrl,
                    decoration: InputDecoration(labelText: T.tr('field.name_required')),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? T.tr('common.required') : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: dosageCtrl,
                          decoration:
                              InputDecoration(labelText: T.tr('field.dosage')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: unitCtrl,
                          decoration: InputDecoration(
                              labelText: T.tr('meds.unit'),
                              hintText: 'mg, ml...'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: freqCtrl,
                    decoration: InputDecoration(labelText: T.tr('field.frequency')),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: routes.contains(route) ? route : null,
                    decoration: InputDecoration(
                        labelText: T.tr('meds.route')),
                    items: routes
                        .map((r) => DropdownMenuItem(
                              value: r,
                              child: Text(T.tr('meds.route_$r')),
                            ))
                        .toList(),
                    onChanged: (v) => setSheetState(() => route = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: startCtrl,
                    decoration: InputDecoration(
                      labelText: T.tr('field.start_date'),
                      hintText: 'YYYY-MM-DD',
                      suffixIcon: const Icon(Icons.calendar_today),
                    ),
                    readOnly: true,
                    onTap: () async {
                      final initDate = startCtrl.text.isNotEmpty
                          ? (DateTime.tryParse(startCtrl.text) ??
                              DateTime.now())
                          : DateTime.now();
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: initDate,
                        firstDate: DateTime(1900),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        startCtrl.text =
                            DateFormat('yyyy-MM-dd').format(picked);
                      }
                    },
                  ),
                  // -- Advanced --
                  ExpansionTile(
                    title: Text(T.tr('common.advanced')),
                    children: [
                      TextField(
                        controller: endCtrl,
                        decoration: InputDecoration(
                          labelText: T.tr('meds.ended_at'),
                          hintText: 'YYYY-MM-DD',
                          suffixIcon: const Icon(Icons.calendar_today),
                        ),
                        readOnly: true,
                        onTap: () async {
                          final initDate = endCtrl.text.isNotEmpty
                              ? (DateTime.tryParse(endCtrl.text) ??
                                  DateTime.now())
                              : DateTime.now();
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: initDate,
                            firstDate: DateTime(1900),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            endCtrl.text =
                                DateFormat('yyyy-MM-dd').format(picked);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: prescribedByCtrl,
                        decoration: InputDecoration(
                            labelText: T.tr('meds.prescribed_by')),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: reasonCtrl,
                        decoration: InputDecoration(
                            labelText: T.tr('meds.reason')),
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
                        'name': nameCtrl.text.trim(),
                        if (dosageCtrl.text.trim().isNotEmpty)
                          'dosage': dosageCtrl.text.trim(),
                        if (unitCtrl.text.trim().isNotEmpty)
                          'unit': unitCtrl.text.trim(),
                        if (freqCtrl.text.trim().isNotEmpty)
                          'frequency': freqCtrl.text.trim(),
                        if (route != null) 'route': route,
                        if (startCtrl.text.trim().isNotEmpty)
                          'started_at':
                              '${startCtrl.text.trim()}T00:00:00.000Z',
                        if (endCtrl.text.trim().isNotEmpty)
                          'ended_at':
                              '${endCtrl.text.trim()}T00:00:00.000Z',
                        if (prescribedByCtrl.text.trim().isNotEmpty)
                          'prescribed_by': prescribedByCtrl.text.trim(),
                        if (reasonCtrl.text.trim().isNotEmpty)
                          'reason': reasonCtrl.text.trim(),
                        if (notesCtrl.text.trim().isNotEmpty)
                          'notes': notesCtrl.text.trim(),
                      };
                      try {
                        final crypto = ref.read(e2eCryptoServiceProvider);
                        final write = await crypto.encryptForWrite(
                          profileId: widget.profileId,
                          entityType: 'medications',
                          body: body,
                          existingId: isEdit ? existing.id : null,
                        );
                        if (isEdit) {
                          await api.patch<void>(
                            '/api/v1/profiles/${widget.profileId}/medications/${write.id}',
                            body: write.toBody(),
                          );
                        } else {
                          await api.post<void>(
                            '/api/v1/profiles/${widget.profileId}/medications',
                            body: write.toBody(),
                          );
                        }
                        ref.invalidate(
                            medicationsProvider(widget.profileId));
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(apiErrorMessage(e)),
                            behavior: SnackBarBehavior.floating,
                          ));
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
      ),
    );
    nameCtrl.dispose();
    dosageCtrl.dispose();
    unitCtrl.dispose();
    freqCtrl.dispose();
    startCtrl.dispose();
    endCtrl.dispose();
    prescribedByCtrl.dispose();
    reasonCtrl.dispose();
    notesCtrl.dispose();
  }

  void _shareMedications(List<Medication> meds) {
    if (meds.isEmpty) return;
    final active = meds.where((m) => m.isActive).toList();
    final parts = <String>[
      'My Medications (${active.length} active)',
      '',
    ];
    for (final m in active) {
      final details = [
        m.name,
        if (m.dosage != null) m.dosage!,
        if (m.frequency != null) m.frequency!,
      ].join(' - ');
      parts.add(details);
    }
    Share.share(parts.join('\n'));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final async = ref.watch(medicationsProvider(widget.profileId));

    return Scaffold(
      appBar: AppBar(
        title: Text(T.tr('meds.title')),
        automaticallyImplyLeading: false,
        actions: [
          async.whenOrNull(
                data: (items) => Semantics(
                  button: true,
                  label: T.tr('common.share'),
                  child: IconButton(
                    icon: const Icon(Icons.share),
                    tooltip: T.tr('common.share'),
                    onPressed: () => _shareMedications(items),
                  ),
                ),
              ) ??
              const SizedBox.shrink(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showFormSheet(),
        tooltip: T.tr('meds.add'),
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
                  label: Text(T.tr('common.active')),
                  selected: _activeOnly,
                  onSelected: (_) => setState(() => _activeOnly = true),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(T.tr('common.all')),
                  selected: !_activeOnly,
                  onSelected: (_) => setState(() => _activeOnly = false),
                ),
              ],
            ),
          ),
          // List
          Expanded(
            child: async.when(
              loading: () => const LoadingWidget(),
              error: (e, _) => AppErrorWidget(
                message: T.tr('meds.failed'),
                onRetry: () =>
                    ref.invalidate(medicationsProvider(widget.profileId)),
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
                                ? T.tr('meds.no_active')
                                : T.tr('meds.no_data'),
                            style: tt.bodyLarge
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ]),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(medicationsProvider(widget.profileId));
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _MedCard(
                      med: list[i],
                      onDelete: () => _delete(list[i].id),
                      onTap: () => _showFormSheet(existing: list[i]),
                    ),
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
  final VoidCallback onTap;
  const _MedCard({
    required this.med,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Dismissible(
      key: ValueKey(med.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: cs.error,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.delete_outline, color: cs.onError),
      ),
      child: Card(
        clipBehavior: Clip.antiAlias,
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
                          Semantics(
                            label: med.isActive
                                ? T.tr('common.active')
                                : T.tr('common.all'),
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: med.isActive
                                    ? cs.tertiary
                                    : cs.outlineVariant,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (med.dosage != null || med.frequency != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (med.dosage != null)
                              '${med.dosage!}${med.unit != null ? ' ${med.unit}' : ''}',
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
      ),
    );
  }
}
