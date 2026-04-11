import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_error_messages.dart';
import '../../core/i18n/translations.dart';
import '../../models/common.dart';
import '../../providers/providers.dart';

// -- Provider -----------------------------------------------------------------

final _allergiesProvider =
    FutureProvider.family<List<Allergy>, String>((ref, profileId) async {
  final api = ref.read(apiClientProvider);
  final data = await api
      .get<Map<String, dynamic>>('/api/v1/profiles/$profileId/allergies');
  return (data['items'] as List)
      .map((e) => Allergy.fromJson(e as Map<String, dynamic>))
      .toList();
});

// -- Screen -------------------------------------------------------------------

class AllergiesScreen extends ConsumerStatefulWidget {
  final String profileId;
  const AllergiesScreen({super.key, required this.profileId});

  @override
  ConsumerState<AllergiesScreen> createState() => _AllergiesScreenState();
}

class _AllergiesScreenState extends ConsumerState<AllergiesScreen> {
  Future<void> _delete(String id) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  T.tr('allergies.delete'),
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  T.tr('allergies.delete_body'),
                  style: Theme.of(ctx).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
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
          .delete('/api/v1/profiles/${widget.profileId}/allergies/$id');
      ref.invalidate(_allergiesProvider(widget.profileId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(apiErrorMessage(e)),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _showFormSheet({Allergy? existing}) async {
    final api = ref.read(apiClientProvider);
    final isEdit = existing != null;
    final allergenCtrl =
        TextEditingController(text: existing?.allergen ?? '');
    final reactionCtrl =
        TextEditingController(text: existing?.reaction ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    final onsetDateCtrl = TextEditingController(
        text: isEdit && existing.onsetDate != null
            ? (existing.onsetDate!.length >= 10
                ? existing.onsetDate!.substring(0, 10)
                : existing.onsetDate!)
            : '');
    final diagnosedByCtrl =
        TextEditingController(text: existing?.diagnosedBy ?? '');
    final formKey = GlobalKey<FormState>();
    String severity = existing?.severity ?? 'mild';
    String? category = existing?.category;
    String? status = existing?.status;

    const categories = ['food', 'drug', 'environmental', 'other'];
    const statuses = ['active', 'inactive', 'resolved'];

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
                    isEdit ? T.tr('allergies.edit') : T.tr('allergies.add'),
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: allergenCtrl,
                    decoration: InputDecoration(labelText: T.tr('field.allergen_required')),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? T.tr('common.required') : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: severity,
                    decoration: InputDecoration(labelText: T.tr('field.severity')),
                    items: [
                      DropdownMenuItem(value: 'mild', child: Text(T.tr('severity.mild'))),
                      DropdownMenuItem(
                          value: 'moderate', child: Text(T.tr('severity.moderate'))),
                      DropdownMenuItem(value: 'severe', child: Text(T.tr('severity.severe'))),
                    ],
                    onChanged: (v) {
                      if (v != null) setSheetState(() => severity = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reactionCtrl,
                    decoration: InputDecoration(labelText: T.tr('field.reaction')),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: categories.contains(category) ? category : null,
                    decoration: InputDecoration(
                        labelText: T.tr('allergies.category')),
                    items: categories
                        .map((c) => DropdownMenuItem(
                              value: c,
                              child: Text(T.tr('allergies.cat_$c')),
                            ))
                        .toList(),
                    onChanged: (v) => setSheetState(() => category = v),
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
                        controller: onsetDateCtrl,
                        decoration: InputDecoration(
                          labelText: T.tr('allergies.onset_date'),
                          hintText: 'YYYY-MM-DD',
                          suffixIcon: const Icon(Icons.calendar_today),
                        ),
                        readOnly: true,
                        onTap: () async {
                          final initDate = onsetDateCtrl.text.isNotEmpty
                              ? (DateTime.tryParse(onsetDateCtrl.text) ??
                                  DateTime.now())
                              : DateTime.now();
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: initDate,
                            firstDate: DateTime(1900),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) {
                            onsetDateCtrl.text =
                                DateFormat('yyyy-MM-dd').format(picked);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: diagnosedByCtrl,
                        decoration: InputDecoration(
                            labelText: T.tr('allergies.diagnosed_by')),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: statuses.contains(status) ? status : null,
                        decoration: InputDecoration(
                            labelText: T.tr('allergies.status')),
                        items: statuses
                            .map((s) => DropdownMenuItem(
                                  value: s,
                                  child:
                                      Text(T.tr('allergies.status_$s')),
                                ))
                            .toList(),
                        onChanged: (v) => setSheetState(() => status = v),
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
                        'allergen': allergenCtrl.text.trim(),
                        'severity': severity,
                        if (reactionCtrl.text.trim().isNotEmpty)
                          'reaction': reactionCtrl.text.trim(),
                        if (category != null) 'category': category,
                        if (onsetDateCtrl.text.trim().isNotEmpty)
                          'onset_date':
                              '${onsetDateCtrl.text.trim()}T00:00:00.000Z',
                        if (diagnosedByCtrl.text.trim().isNotEmpty)
                          'diagnosed_by': diagnosedByCtrl.text.trim(),
                        if (status != null) 'status': status,
                        if (notesCtrl.text.trim().isNotEmpty)
                          'notes': notesCtrl.text.trim(),
                      };
                      try {
                        if (isEdit) {
                          await api.patch<void>(
                            '/api/v1/profiles/${widget.profileId}/allergies/${existing.id}',
                            body: body,
                          );
                        } else {
                          await api.post<void>(
                            '/api/v1/profiles/${widget.profileId}/allergies',
                            body: body,
                          );
                        }
                        ref.invalidate(
                            _allergiesProvider(widget.profileId));
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        if (ctx.mounted) {
                          setSheetState(() => isSaving = false);
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(apiErrorMessage(e)),
                            behavior: SnackBarBehavior.floating,
                          ));
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
    allergenCtrl.dispose();
    reactionCtrl.dispose();
    notesCtrl.dispose();
    onsetDateCtrl.dispose();
    diagnosedByCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final asyncVal = ref.watch(_allergiesProvider(widget.profileId));

    return Scaffold(
      appBar: AppBar(
        title: Text(T.tr('allergies.title')),
        automaticallyImplyLeading: false,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showFormSheet(),
        tooltip: T.tr('allergies.add'),
        child: const Icon(Icons.add),
      ),
      body: asyncVal.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline, size: 48, color: cs.error),
            const SizedBox(height: 12),
            Text(T.tr('allergies.failed'), style: tt.bodyLarge),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () =>
                  ref.invalidate(_allergiesProvider(widget.profileId)),
              child: Text(T.tr('common.retry')),
            ),
          ]),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.warning_amber_outlined,
                    size: 48, color: cs.outline),
                const SizedBox(height: 12),
                Text(T.tr('allergies.no_data'),
                    style:
                        tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _AllergyCard(
              allergy: items[i],
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

class _AllergyCard extends StatelessWidget {
  final Allergy allergy;
  final VoidCallback onDelete;
  final VoidCallback onTap;
  const _AllergyCard({
    required this.allergy,
    required this.onDelete,
    required this.onTap,
  });

  Color _severityColor(String? severity, ColorScheme cs) {
    switch (severity?.toLowerCase()) {
      case 'severe':
        return cs.error;
      case 'moderate':
        return cs.tertiary;
      default:
        return cs.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final sevColor = _severityColor(allergy.severity, cs);

    return Card(
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
                child: Icon(Icons.warning_amber,
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
                            allergy.allergen,
                            style: tt.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (allergy.severity != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: sevColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              T.tr('severity.${allergy.severity}'),
                              style: TextStyle(
                                fontSize: 10,
                                color: sevColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (allergy.reaction != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        allergy.reaction!,
                        style:
                            tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                    if (allergy.notes != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        allergy.notes!,
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
    );
  }
}
