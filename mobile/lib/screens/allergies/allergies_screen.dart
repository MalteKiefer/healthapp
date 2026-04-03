import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(T.tr('allergies.delete')),
        content: Text(T.tr('allergies.delete_body')),
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
          .delete('/api/v1/profiles/${widget.profileId}/allergies/$id');
      ref.invalidate(_allergiesProvider(widget.profileId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _showAddSheet() async {
    final allergenCtrl = TextEditingController();
    final reactionCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String severity = 'mild';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        minChildSize: 0.45,
        maxChildSize: 0.9,
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
                  Text(T.tr('allergies.add'),
                      style: Theme.of(ctx).textTheme.titleLarge),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: allergenCtrl,
                    decoration: const InputDecoration(labelText: 'Allergen *'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: severity,
                    decoration: const InputDecoration(labelText: 'Severity'),
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
                    decoration: const InputDecoration(labelText: 'Reaction'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(labelText: 'Notes'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      Navigator.pop(ctx);
                      final body = <String, dynamic>{
                        'allergen': allergenCtrl.text.trim(),
                        'severity': severity,
                        if (reactionCtrl.text.trim().isNotEmpty)
                          'reaction': reactionCtrl.text.trim(),
                        if (notesCtrl.text.trim().isNotEmpty)
                          'notes': notesCtrl.text.trim(),
                      };
                      try {
                        await ref.read(apiClientProvider).post<void>(
                              '/api/v1/profiles/${widget.profileId}/allergies',
                              body: body,
                            );
                        ref.invalidate(
                            _allergiesProvider(widget.profileId));
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text('$e')));
                        }
                      }
                    },
                    child: Text(T.tr('allergies.add')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    allergenCtrl.dispose();
    reactionCtrl.dispose();
    notesCtrl.dispose();
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
        onPressed: _showAddSheet,
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
  const _AllergyCard({required this.allergy, required this.onDelete});

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
