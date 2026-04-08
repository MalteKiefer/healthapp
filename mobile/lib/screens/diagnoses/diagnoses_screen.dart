import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/i18n/translations.dart';
import '../../models/common.dart';
import '../../providers/providers.dart';

// -- Provider -----------------------------------------------------------------

final _diagnosesProvider =
    FutureProvider.family<List<Diagnosis>, String>((ref, profileId) async {
  final api = ref.read(apiClientProvider);
  final data = await api
      .get<Map<String, dynamic>>('/api/v1/profiles/$profileId/diagnoses');
  return (data['items'] as List)
      .map((e) => Diagnosis.fromJson(e as Map<String, dynamic>))
      .toList();
});

// -- Screen -------------------------------------------------------------------

class DiagnosesScreen extends ConsumerStatefulWidget {
  final String profileId;
  const DiagnosesScreen({super.key, required this.profileId});

  @override
  ConsumerState<DiagnosesScreen> createState() => _DiagnosesScreenState();
}

class _DiagnosesScreenState extends ConsumerState<DiagnosesScreen> {
  bool _activeOnly = true;

  Future<void> _delete(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(T.tr('diagnoses.delete')),
        content: Text(T.tr('diagnoses.delete_body')),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(T.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(T.tr('common.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(apiClientProvider)
          .delete('/api/v1/profiles/${widget.profileId}/diagnoses/$id');
      ref.invalidate(_diagnosesProvider(widget.profileId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _showFormSheet({Diagnosis? existing}) async {
    final api = ref.read(apiClientProvider);
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final icdCtrl = TextEditingController(text: existing?.icdCode ?? '');
    final dateCtrl = TextEditingController(
        text: isEdit && existing.diagnosedAt != null
            ? (existing.diagnosedAt!.length >= 10
                ? existing.diagnosedAt!.substring(0, 10)
                : existing.diagnosedAt!)
            : '');
    final resolvedCtrl = TextEditingController(
        text: isEdit && existing.resolvedAt != null
            ? (existing.resolvedAt!.length >= 10
                ? existing.resolvedAt!.substring(0, 10)
                : existing.resolvedAt!)
            : '');
    final diagnosedByCtrl =
        TextEditingController(text: existing?.diagnosedBy ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    final formKey = GlobalKey<FormState>();
    String? status = existing?.status;

    const statuses = ['active', 'resolved', 'remission'];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.80,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (ctx, scrollCtrl) {
          bool isSaving = false;
          return StatefulBuilder(
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
                    isEdit ? T.tr('diagnoses.edit') : T.tr('diagnoses.add'),
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
                  TextField(
                    controller: icdCtrl,
                    decoration:
                        InputDecoration(labelText: T.tr('field.icd10_code')),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: statuses.contains(status) ? status : null,
                    decoration: InputDecoration(
                        labelText: T.tr('diagnoses.status')),
                    items: statuses
                        .map((s) => DropdownMenuItem(
                              value: s,
                              child: Text(T.tr('diagnoses.status_$s')),
                            ))
                        .toList(),
                    onChanged: (v) => setSheetState(() => status = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: dateCtrl,
                    decoration: InputDecoration(
                      labelText: T.tr('field.diagnosed_date'),
                      hintText: 'YYYY-MM-DD',
                      suffixIcon: const Icon(Icons.calendar_today),
                    ),
                    readOnly: true,
                    onTap: () async {
                      final initDate = dateCtrl.text.isNotEmpty
                          ? (DateTime.tryParse(dateCtrl.text) ?? DateTime.now())
                          : DateTime.now();
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: initDate,
                        firstDate: DateTime(1900),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        dateCtrl.text = DateFormat('yyyy-MM-dd').format(picked);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    decoration: InputDecoration(
                        labelText: T.tr('common.notes')),
                    maxLines: 2,
                  ),
                  // -- Advanced --
                  ExpansionTile(
                    title: Text(T.tr('common.advanced')),
                    children: [
                      TextField(
                        controller: diagnosedByCtrl,
                        decoration: InputDecoration(
                            labelText: T.tr('diagnoses.diagnosed_by')),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: resolvedCtrl,
                        decoration: InputDecoration(
                          labelText: T.tr('diagnoses.resolved_at'),
                          hintText: 'YYYY-MM-DD',
                          suffixIcon: const Icon(Icons.calendar_today),
                        ),
                        readOnly: true,
                        onTap: () async {
                          final initDate = resolvedCtrl.text.isNotEmpty
                              ? (DateTime.tryParse(resolvedCtrl.text) ??
                                  DateTime.now())
                              : DateTime.now();
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: initDate,
                            firstDate: DateTime(1900),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) {
                            resolvedCtrl.text =
                                DateFormat('yyyy-MM-dd').format(picked);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: isSaving ? null : () async {
                      if (!formKey.currentState!.validate()) return;
                      setSheetState(() => isSaving = true);
                      final body = <String, dynamic>{
                        'name': nameCtrl.text.trim(),
                        if (icdCtrl.text.trim().isNotEmpty)
                          'icd_code': icdCtrl.text.trim(),
                        if (status != null) 'status': status,
                        if (dateCtrl.text.trim().isNotEmpty)
                          'diagnosed_at':
                              '${dateCtrl.text.trim()}T00:00:00.000Z',
                        if (resolvedCtrl.text.trim().isNotEmpty)
                          'resolved_at':
                              '${resolvedCtrl.text.trim()}T00:00:00.000Z',
                        if (diagnosedByCtrl.text.trim().isNotEmpty)
                          'diagnosed_by': diagnosedByCtrl.text.trim(),
                        if (notesCtrl.text.trim().isNotEmpty)
                          'notes': notesCtrl.text.trim(),
                      };
                      try {
                        if (isEdit) {
                          await api.patch<void>(
                            '/api/v1/profiles/${widget.profileId}/diagnoses/${existing.id}',
                            body: body,
                          );
                        } else {
                          await api.post<void>(
                            '/api/v1/profiles/${widget.profileId}/diagnoses',
                            body: body,
                          );
                        }
                        ref.invalidate(
                            _diagnosesProvider(widget.profileId));
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        if (ctx.mounted) {
                          setSheetState(() => isSaving = false);
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text('$e')));
                        }
                      }
                    },
                    child: isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(T.tr('common.save')),
                  ),
                ],
              ),
            ),
          ),
        );
        },
      ),
    );
    nameCtrl.dispose();
    icdCtrl.dispose();
    dateCtrl.dispose();
    resolvedCtrl.dispose();
    diagnosedByCtrl.dispose();
    notesCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final asyncVal = ref.watch(_diagnosesProvider(widget.profileId));

    return Scaffold(
      appBar: AppBar(
        title: Text(T.tr('diagnoses.title')),
        automaticallyImplyLeading: false,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showFormSheet(),
        tooltip: T.tr('diagnoses.add'),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
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
          Expanded(
            child: asyncVal.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.error_outline, size: 48, color: cs.error),
                  const SizedBox(height: 12),
                  Text(T.tr('diagnoses.failed'), style: tt.bodyLarge),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: () => ref
                        .invalidate(_diagnosesProvider(widget.profileId)),
                    child: Text(T.tr('common.retry')),
                  ),
                ]),
              ),
              data: (items) {
                final list = _activeOnly
                    ? items.where((d) => d.resolvedAt == null).toList()
                    : items;
                if (list.isEmpty) {
                  return Center(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.local_hospital_outlined,
                              size: 48, color: cs.outline),
                          const SizedBox(height: 12),
                          Text(
                            _activeOnly
                                ? T.tr('diagnoses.no_active')
                                : T.tr('diagnoses.no_data'),
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
                  itemBuilder: (_, i) => _DiagnosisCard(
                    diagnosis: list[i],
                    onDelete: () => _delete(list[i].id),
                    onTap: () => _showFormSheet(existing: list[i]),
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

// -- Card ---------------------------------------------------------------------

class _DiagnosisCard extends StatelessWidget {
  final Diagnosis diagnosis;
  final VoidCallback onDelete;
  final VoidCallback onTap;
  const _DiagnosisCard({
    required this.diagnosis,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isResolved = diagnosis.resolvedAt != null;

    String? diagDate;
    if (diagnosis.diagnosedAt != null) {
      try {
        final d = DateTime.parse(diagnosis.diagnosedAt!);
        diagDate = DateFormat('MMM d, yyyy').format(d);
      } catch (_) {
        diagDate = diagnosis.diagnosedAt;
      }
    }

    String? resDate;
    if (diagnosis.resolvedAt != null) {
      try {
        final d = DateTime.parse(diagnosis.resolvedAt!);
        resDate = DateFormat('MMM d, yyyy').format(d);
      } catch (_) {
        resDate = diagnosis.resolvedAt;
      }
    }

    return Dismissible(
      key: ValueKey(diagnosis.id),
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
                  child: Icon(Icons.local_hospital,
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
                              diagnosis.name,
                              style: tt.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (diagnosis.icdCode != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: cs.tertiaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                diagnosis.icdCode!,
                                style: tt.labelSmall?.copyWith(
                                    color: cs.onTertiaryContainer,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (diagDate != null) ...[
                            Text(
                              '${T.tr('field.diagnosed_date')}: $diagDate',
                              style: tt.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                          if (isResolved) ...[
                            const SizedBox(width: 8),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${T.tr('status.resolved')}${resDate != null ? ' $resDate' : ''}',
                              style: tt.bodySmall
                                  ?.copyWith(color: Colors.green),
                            ),
                          ],
                        ],
                      ),
                      if (diagnosis.notes != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          diagnosis.notes!,
                          style: tt.bodySmall?.copyWith(color: cs.outline),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
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
