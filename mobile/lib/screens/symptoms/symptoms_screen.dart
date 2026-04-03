import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/i18n/translations.dart';
import '../../models/common.dart';
import '../../providers/providers.dart';

// -- Provider -----------------------------------------------------------------

final _symptomsProvider =
    FutureProvider.family<List<Symptom>, String>((ref, profileId) async {
  final api = ref.read(apiClientProvider);
  final data = await api
      .get<Map<String, dynamic>>('/api/v1/profiles/$profileId/symptoms');
  return (data['items'] as List)
      .map((e) => Symptom.fromJson(e as Map<String, dynamic>))
      .toList();
});

// -- Screen -------------------------------------------------------------------

class SymptomsScreen extends ConsumerStatefulWidget {
  final String profileId;
  const SymptomsScreen({super.key, required this.profileId});

  @override
  ConsumerState<SymptomsScreen> createState() => _SymptomsScreenState();
}

class _SymptomsScreenState extends ConsumerState<SymptomsScreen> {
  bool _activeOnly = true;

  Future<void> _delete(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(T.tr('symptoms.delete')),
        content: Text(T.tr('symptoms.delete_body')),
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
          .delete('/api/v1/profiles/${widget.profileId}/symptoms/$id');
      ref.invalidate(_symptomsProvider(widget.profileId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _showFormSheet({Symptom? existing}) async {
    final api = ref.read(apiClientProvider);
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    final triggerCtrl =
        TextEditingController(text: existing?.triggerFactors ?? '');
    final bodyRegionCtrl =
        TextEditingController(text: existing?.bodyRegion ?? '');
    final durationMinCtrl = TextEditingController(
        text: existing?.durationMinutes?.toString() ?? '');
    final formKey = GlobalKey<FormState>();
    int intensity = isEdit
        ? (int.tryParse(existing.severity ?? '') ?? 5)
        : 5;
    String? symptomType = existing?.symptomType;

    const symptomTypes = [
      'pain',
      'nausea',
      'fatigue',
      'dizziness',
      'headache',
      'fever',
      'cough',
      'rash',
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
                    isEdit ? T.tr('symptoms.edit') : T.tr('symptoms.add'),
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Name *'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: symptomTypes.contains(symptomType)
                        ? symptomType
                        : null,
                    decoration: InputDecoration(
                        labelText: T.tr('symptoms.symptom_type')),
                    items: symptomTypes
                        .map((t) => DropdownMenuItem(
                              value: t,
                              child: Text(T.tr('symptoms.type_$t')),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setSheetState(() => symptomType = v),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Intensity: $intensity',
                    style: Theme.of(ctx)
                        .textTheme
                        .titleSmall
                        ?.copyWith(
                            color:
                                Theme.of(ctx).colorScheme.onSurfaceVariant),
                  ),
                  Slider(
                    value: intensity.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: intensity.toString(),
                    onChanged: (v) =>
                        setSheetState(() => intensity = v.round()),
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
                        controller: triggerCtrl,
                        decoration: InputDecoration(
                            labelText: T.tr('symptoms.trigger_factors')),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: bodyRegionCtrl,
                        decoration: InputDecoration(
                            labelText: T.tr('symptoms.body_region')),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: durationMinCtrl,
                        decoration: InputDecoration(
                            labelText: T.tr('symptoms.duration_minutes')),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      Navigator.pop(ctx);
                      // Convert comma-separated triggers to array
                      final triggerText = triggerCtrl.text.trim();
                      List<String>? triggerArray;
                      if (triggerText.isNotEmpty) {
                        triggerArray = triggerText
                            .split(',')
                            .map((s) => s.trim())
                            .where((s) => s.isNotEmpty)
                            .toList();
                      }
                      final body = <String, dynamic>{
                        'name': nameCtrl.text.trim(),
                        'severity': intensity.toString(),
                        'recorded_at': isEdit
                            ? (existing.recordedAt ??
                                DateTime.now().toUtc().toIso8601String())
                            : DateTime.now().toUtc().toIso8601String(),
                        'is_ongoing': isEdit ? existing.isOngoing : true,
                        if (symptomType != null)
                          'symptom_type': symptomType,
                        if (notesCtrl.text.trim().isNotEmpty)
                          'notes': notesCtrl.text.trim(),
                        if (triggerArray != null)
                          'trigger_factors': triggerArray,
                        if (bodyRegionCtrl.text.trim().isNotEmpty)
                          'body_region': bodyRegionCtrl.text.trim(),
                        if (int.tryParse(durationMinCtrl.text.trim()) !=
                            null)
                          'duration_minutes':
                              int.tryParse(durationMinCtrl.text.trim()),
                      };
                      try {
                        if (isEdit) {
                          await api.patch<void>(
                            '/api/v1/profiles/${widget.profileId}/symptoms/${existing.id}',
                            body: body,
                          );
                        } else {
                          await api.post<void>(
                            '/api/v1/profiles/${widget.profileId}/symptoms',
                            body: body,
                          );
                        }
                        ref.invalidate(
                            _symptomsProvider(widget.profileId));
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text('$e')));
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
    notesCtrl.dispose();
    triggerCtrl.dispose();
    bodyRegionCtrl.dispose();
    durationMinCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final asyncVal = ref.watch(_symptomsProvider(widget.profileId));

    return Scaffold(
      appBar: AppBar(
        title: Text(T.tr('symptoms.title')),
        automaticallyImplyLeading: false,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showFormSheet(),
        tooltip: T.tr('symptoms.add'),
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
                  label: Text(T.tr('status.resolved')),
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
                  Text(T.tr('symptoms.failed'), style: tt.bodyLarge),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: () =>
                        ref.invalidate(_symptomsProvider(widget.profileId)),
                    child: Text(T.tr('common.retry')),
                  ),
                ]),
              ),
              data: (items) {
                final list = _activeOnly
                    ? items.where((s) => s.isOngoing).toList()
                    : items.where((s) => !s.isOngoing).toList();
                if (list.isEmpty) {
                  return Center(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.sick_outlined,
                              size: 48, color: cs.outline),
                          const SizedBox(height: 12),
                          Text(
                            _activeOnly
                                ? T.tr('symptoms.no_active')
                                : T.tr('symptoms.no_resolved'),
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
                  itemBuilder: (_, i) => _SymptomCard(
                    symptom: list[i],
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

class _SymptomCard extends StatelessWidget {
  final Symptom symptom;
  final VoidCallback onDelete;
  final VoidCallback onTap;
  const _SymptomCard({
    required this.symptom,
    required this.onDelete,
    required this.onTap,
  });

  Color _intensityColor(int? val, ColorScheme cs) {
    if (val == null) return cs.primary;
    if (val >= 8) return cs.error;
    if (val >= 5) return cs.tertiary;
    return cs.primary;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final severityVal = int.tryParse(symptom.severity ?? '');
    final intColor = _intensityColor(severityVal, cs);

    String? dateStr;
    if (symptom.recordedAt != null) {
      try {
        final d = DateTime.parse(symptom.recordedAt!);
        dateStr = DateFormat('MMM d, yyyy').format(d);
      } catch (_) {
        dateStr = symptom.recordedAt;
      }
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onDelete,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.sick,
                        size: 20, color: cs.onPrimaryContainer),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          symptom.name,
                          style: tt.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (dateStr != null)
                          Text(
                            dateStr,
                            style: tt.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  if (severityVal != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: intColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$severityVal/10',
                        style: TextStyle(
                          fontSize: 10,
                          color: intColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (symptom.isOngoing) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
              if (severityVal != null) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: severityVal / 10.0,
                    minHeight: 6,
                    backgroundColor: cs.surfaceContainerHighest,
                    color: intColor,
                  ),
                ),
              ],
              if (symptom.duration != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Duration: ${symptom.duration}',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
              if (symptom.notes != null) ...[
                const SizedBox(height: 4),
                Text(
                  symptom.notes!,
                  style: tt.bodySmall?.copyWith(color: cs.outline),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
