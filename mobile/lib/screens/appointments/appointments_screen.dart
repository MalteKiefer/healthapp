import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/common.dart';
import '../../providers/providers.dart';

// -- Provider -----------------------------------------------------------------

final _appointmentsProvider =
    FutureProvider.family<List<Appointment>, String>((ref, profileId) async {
  final api = ref.read(apiClientProvider);
  final data = await api
      .get<Map<String, dynamic>>('/api/v1/profiles/$profileId/appointments');
  return (data['items'] as List)
      .map((e) => Appointment.fromJson(e as Map<String, dynamic>))
      .toList();
});

// -- Screen -------------------------------------------------------------------

class AppointmentsScreen extends ConsumerStatefulWidget {
  final String profileId;
  const AppointmentsScreen({super.key, required this.profileId});

  @override
  ConsumerState<AppointmentsScreen> createState() =>
      _AppointmentsScreenState();
}

class _AppointmentsScreenState extends ConsumerState<AppointmentsScreen> {
  bool _upcomingOnly = true;

  Future<void> _delete(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Appointment'),
        content: const Text('This appointment will be permanently removed.'),
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
          .delete('/api/v1/profiles/${widget.profileId}/appointments/$id');
      ref.invalidate(_appointmentsProvider(widget.profileId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _showAddSheet() async {
    final titleCtrl = TextEditingController();
    final dateCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final doctorCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    DateTime? selectedDateTime;

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
                Text('Add Appointment',
                    style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 20),
                TextFormField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Title *'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dateCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Date & Time',
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  readOnly: true,
                  onTap: () async {
                    final date = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (date == null) return;
                    if (!ctx.mounted) return;
                    final time = await showTimePicker(
                      context: ctx,
                      initialTime: TimeOfDay.now(),
                    );
                    if (time == null) return;
                    selectedDateTime = DateTime(
                      date.year,
                      date.month,
                      date.day,
                      time.hour,
                      time.minute,
                    );
                    dateCtrl.text = DateFormat('MMM d, yyyy \u2013 HH:mm')
                        .format(selectedDateTime!);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: locationCtrl,
                  decoration: const InputDecoration(labelText: 'Location'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: doctorCtrl,
                  decoration: const InputDecoration(labelText: 'Doctor'),
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
                      'title': titleCtrl.text.trim(),
                      if (selectedDateTime != null)
                        'scheduled_at':
                            selectedDateTime!.toUtc().toIso8601String(),
                      if (locationCtrl.text.trim().isNotEmpty)
                        'location': locationCtrl.text.trim(),
                      if (doctorCtrl.text.trim().isNotEmpty)
                        'doctor_name': doctorCtrl.text.trim(),
                      if (notesCtrl.text.trim().isNotEmpty)
                        'notes': notesCtrl.text.trim(),
                    };
                    try {
                      await ref.read(apiClientProvider).post<void>(
                            '/api/v1/profiles/${widget.profileId}/appointments',
                            body: body,
                          );
                      ref.invalidate(
                          _appointmentsProvider(widget.profileId));
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('$e')));
                      }
                    }
                  },
                  child: const Text('Add Appointment'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    titleCtrl.dispose();
    dateCtrl.dispose();
    locationCtrl.dispose();
    doctorCtrl.dispose();
    notesCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final asyncVal = ref.watch(_appointmentsProvider(widget.profileId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Appointments'),
        automaticallyImplyLeading: false,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSheet,
        tooltip: 'Add appointment',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Upcoming'),
                  selected: _upcomingOnly,
                  onSelected: (_) => setState(() => _upcomingOnly = true),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Past'),
                  selected: !_upcomingOnly,
                  onSelected: (_) => setState(() => _upcomingOnly = false),
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
                  Text('Failed to load', style: tt.bodyLarge),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: () => ref
                        .invalidate(_appointmentsProvider(widget.profileId)),
                    child: const Text('Retry'),
                  ),
                ]),
              ),
              data: (items) {
                final now = DateTime.now();
                final list = items.where((a) {
                  final dt = DateTime.tryParse(a.scheduledAt ?? '');
                  if (dt == null) return !_upcomingOnly;
                  return _upcomingOnly
                      ? dt.isAfter(now)
                      : dt.isBefore(now);
                }).toList()
                  ..sort((a, b) {
                    final da = a.scheduledAt ?? '';
                    final db = b.scheduledAt ?? '';
                    return _upcomingOnly
                        ? da.compareTo(db)
                        : db.compareTo(da);
                  });

                if (list.isEmpty) {
                  return Center(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.event_outlined,
                              size: 48, color: cs.outline),
                          const SizedBox(height: 12),
                          Text(
                            _upcomingOnly
                                ? 'No upcoming appointments'
                                : 'No past appointments',
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
                  itemBuilder: (_, i) => _AppointmentCard(
                    appointment: list[i],
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

// -- Card ---------------------------------------------------------------------

class _AppointmentCard extends StatelessWidget {
  final Appointment appointment;
  final VoidCallback onDelete;
  const _AppointmentCard(
      {required this.appointment, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isCompleted =
        appointment.status?.toLowerCase() == 'completed';

    String? dateStr;
    if (appointment.scheduledAt != null) {
      try {
        final d = DateTime.parse(appointment.scheduledAt!);
        dateStr = DateFormat('MMM d, yyyy \u2013 HH:mm').format(d.toLocal());
      } catch (_) {
        dateStr = appointment.scheduledAt;
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
                child: Icon(Icons.event,
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
                            appointment.title,
                            style: tt.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (isCompleted)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Completed',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.green,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (dateStr != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        dateStr,
                        style: tt.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                    if (appointment.location != null ||
                        appointment.doctorName != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (appointment.location != null)
                            appointment.location!,
                          if (appointment.doctorName != null)
                            appointment.doctorName!,
                        ].join(' \u00b7 '),
                        style: tt.bodySmall?.copyWith(color: cs.outline),
                      ),
                    ],
                    if (appointment.notes != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        appointment.notes!,
                        style: tt.bodySmall?.copyWith(color: cs.outline),
                        maxLines: 1,
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
