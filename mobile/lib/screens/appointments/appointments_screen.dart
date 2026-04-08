import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/i18n/translations.dart';
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
        title: Text(T.tr('appointments.delete')),
        content: Text(T.tr('appointments.delete_body')),
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
          .delete('/api/v1/profiles/${widget.profileId}/appointments/$id');
      ref.invalidate(_appointmentsProvider(widget.profileId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _showFormSheet({Appointment? existing}) async {
    final api = ref.read(apiClientProvider);
    final isEdit = existing != null;
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final dateCtrl = TextEditingController();
    final locationCtrl =
        TextEditingController(text: existing?.location ?? '');
    final doctorCtrl = TextEditingController();
    final notesCtrl =
        TextEditingController(text: existing?.preparationNotes ?? '');
    final durationCtrl = TextEditingController(
        text: existing?.durationMinutes?.toString() ?? '');
    final formKey = GlobalKey<FormState>();
    DateTime? selectedDateTime;
    String? selectedDoctorId = existing?.doctorId;
    String? appointmentType = existing?.appointmentType;
    String? status = existing?.status;
    String? recurrence = existing?.recurrence;
    List<int> reminderDays = existing?.reminderDaysBefore ?? [];

    const types = [
      'examination',
      'surgery',
      'vaccination',
      'follow_up',
      'lab',
      'specialist',
      'general_practice',
      'therapy',
      'other',
    ];
    const statuses = ['scheduled', 'completed', 'cancelled', 'missed'];
    const recurrences = ['none', 'weekly', 'monthly', 'quarterly', 'yearly', 'custom'];
    const reminderOptions = [1, 3, 7];

    if (isEdit) {
      try {
        selectedDateTime = DateTime.parse(existing.scheduledAt);
        dateCtrl.text = DateFormat(
                T.lang == 'de'
                    ? 'dd.MM.yyyy \u2013 HH:mm'
                    : 'MMM d, yyyy \u2013 HH:mm')
            .format(selectedDateTime.toLocal());
      } catch (_) {
        dateCtrl.text = existing.scheduledAt;
      }
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
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
                    isEdit
                        ? T.tr('appointments.edit')
                        : T.tr('appointments.add'),
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: titleCtrl,
                    decoration: InputDecoration(
                        labelText: T.tr('appointments.field_title')),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty)
                            ? T.tr('common.required')
                            : null,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: dateCtrl,
                    decoration: InputDecoration(
                      labelText: T.tr('appointments.field_date'),
                      suffixIcon: const Icon(Icons.calendar_today),
                    ),
                    readOnly: true,
                    onTap: () async {
                      final date = await showDatePicker(
                        context: ctx,
                        initialDate: selectedDateTime ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (date == null) return;
                      if (!ctx.mounted) return;
                      final time = await showTimePicker(
                        context: ctx,
                        initialTime: selectedDateTime != null
                            ? TimeOfDay.fromDateTime(selectedDateTime!)
                            : TimeOfDay.now(),
                      );
                      if (time == null) return;
                      selectedDateTime = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute,
                      );
                      dateCtrl.text = DateFormat(
                              T.lang == 'de'
                                  ? 'dd.MM.yyyy \u2013 HH:mm'
                                  : 'MMM d, yyyy \u2013 HH:mm')
                          .format(selectedDateTime!);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: types.contains(appointmentType)
                        ? appointmentType
                        : null,
                    decoration: InputDecoration(
                        labelText: T.tr('appointments.type')),
                    items: types
                        .map((t) => DropdownMenuItem(
                              value: t,
                              child:
                                  Text(T.tr('appointments.type_$t')),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setSheetState(() => appointmentType = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: locationCtrl,
                    decoration: InputDecoration(
                        labelText: T.tr('appointments.field_location')),
                  ),
                  const SizedBox(height: 12),
                  // Doctor / Contact picker
                  TextField(
                    controller: doctorCtrl,
                    decoration: InputDecoration(
                      labelText: T.tr('appointments.field_doctor'),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.contacts_outlined),
                        tooltip: T.tr('contacts.title'),
                        onPressed: () async {
                          final result =
                              await _showContactPicker(ctx);
                          if (result != null) {
                            doctorCtrl.text = result['name'] as String;
                            selectedDoctorId =
                                result['id'] as String?;
                            final addr = result['address'];
                            if (addr != null &&
                                addr.isNotEmpty &&
                                locationCtrl.text.isEmpty) {
                              locationCtrl.text = addr;
                            }
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    decoration: InputDecoration(
                        labelText: T.tr('appointments.field_notes')),
                    maxLines: 2,
                  ),
                  // -- Advanced --
                  ExpansionTile(
                    title: Text(T.tr('common.advanced')),
                    children: [
                      TextField(
                        controller: durationCtrl,
                        decoration: InputDecoration(
                            labelText: T.tr('appointments.duration')),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: statuses.contains(status) ? status : null,
                        decoration: InputDecoration(
                            labelText: T.tr('appointments.status')),
                        items: statuses
                            .map((s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(T.tr(
                                      'appointments.status_$s')),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            setSheetState(() => status = v),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: recurrences.contains(recurrence)
                            ? recurrence
                            : null,
                        decoration: InputDecoration(
                            labelText:
                                T.tr('appointments.recurrence')),
                        items: recurrences
                            .map((r) => DropdownMenuItem(
                                  value: r,
                                  child: Text(T.tr(
                                      'appointments.recurrence_$r')),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            setSheetState(() => recurrence = v),
                      ),
                      const SizedBox(height: 12),
                      // Reminder days (multi-select chips)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          T.tr('appointments.reminder'),
                          style: Theme.of(ctx)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: Theme.of(ctx)
                                      .colorScheme
                                      .onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: reminderOptions.map((d) {
                          final selected = reminderDays.contains(d);
                          return FilterChip(
                            label: Text(
                                T.tr('appointments.reminder_$d')),
                            selected: selected,
                            onSelected: (sel) {
                              setSheetState(() {
                                if (sel) {
                                  reminderDays.add(d);
                                } else {
                                  reminderDays.remove(d);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      if (selectedDateTime == null) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                              content: Text(
                                  T.tr('appointments.date_required'))),
                        );
                        return;
                      }
                      final title = titleCtrl.text.trim();
                      final location = locationCtrl.text.trim();
                      final notes = notesCtrl.text.trim();
                      final duration = int.tryParse(durationCtrl.text.trim());
                      final body = <String, dynamic>{
                        'title': title,
                        'scheduled_at':
                            selectedDateTime!.toUtc().toIso8601String(),
                        if (appointmentType != null)
                          'appointment_type': appointmentType,
                        if (duration != null)
                          'duration_minutes': duration,
                        if (status != null) 'status': status,
                        if (recurrence != null) 'recurrence': recurrence,
                        if (location.isNotEmpty)
                          'location': location,
                        if (selectedDoctorId != null)
                          'doctor_id': selectedDoctorId,
                        if (notes.isNotEmpty)
                          'preparation_notes': notes,
                        if (reminderDays.isNotEmpty)
                          'reminder_days_before': reminderDays,
                      };
                      try {
                        if (isEdit) {
                          await api.patch<dynamic>(
                            '/api/v1/profiles/${widget.profileId}/appointments/${existing.id}',
                            body: body,
                          );
                        } else {
                          await api.post<dynamic>(
                            '/api/v1/profiles/${widget.profileId}/appointments',
                            body: body,
                          );
                        }
                        if (!ctx.mounted) return;
                        Navigator.of(ctx).pop();
                        await Future.delayed(const Duration(milliseconds: 300));
                        if (mounted) {
                          ref.invalidate(
                              _appointmentsProvider(widget.profileId));
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx)
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
  }

  Future<Map<String, String?>?> _showContactPicker(BuildContext ctx) async {
    List<dynamic> contacts = [];
    try {
      final api = ref.read(apiClientProvider);
      final data = await api.get<Map<String, dynamic>>(
          '/api/v1/profiles/${widget.profileId}/contacts');
      contacts = data['items'] as List? ?? [];
    } catch (_) {}

    if (contacts.isEmpty) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text(T.tr('contacts.no_contacts'))),
        );
      }
      return null;
    }

    return showModalBottomSheet<Map<String, String?>>(
      context: ctx,
      builder: (sheetCtx) {
        final searchCtrl = TextEditingController();
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            final query = searchCtrl.text.toLowerCase();
            final filtered = contacts.where((c) {
              final name = (c['name'] ?? '').toString().toLowerCase();
              final spec = (c['specialty'] ?? '').toString().toLowerCase();
              return name.contains(query) || spec.contains(query);
            }).toList();

            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(T.tr('appointments.select_doctor'),
                      style: Theme.of(sheetCtx).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchCtrl,
                    decoration: InputDecoration(
                      hintText: T.tr('common.search'),
                      prefixIcon: const Icon(Icons.search),
                    ),
                    onChanged: (_) => setSheetState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final c = filtered[i];
                        return ListTile(
                          leading: const Icon(Icons.person_outline),
                          title: Text(c['name'] ?? ''),
                          subtitle: c['specialty'] != null
                              ? Text(c['specialty'])
                              : null,
                          onTap: () {
                            Navigator.pop(sheetCtx, {
                              'id': c['id']?.toString() ?? '',
                              'name': c['name']?.toString() ?? '',
                              'address': c['address']?.toString() ?? '',
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final asyncVal = ref.watch(_appointmentsProvider(widget.profileId));

    return Scaffold(
      appBar: AppBar(
        title: Text(T.tr('appointments.title')),
        automaticallyImplyLeading: false,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showFormSheet(),
        tooltip: T.tr('appointments.add'),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                ChoiceChip(
                  label: Text(T.tr('status.upcoming')),
                  selected: _upcomingOnly,
                  onSelected: (_) => setState(() => _upcomingOnly = true),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(T.tr('status.past')),
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
                  Text(T.tr('appointments.failed'), style: tt.bodyLarge),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: () => ref
                        .invalidate(_appointmentsProvider(widget.profileId)),
                    child: Text(T.tr('common.retry')),
                  ),
                ]),
              ),
              data: (items) {
                final now = DateTime.now();
                final list = items.where((a) {
                  final dt = DateTime.tryParse(a.scheduledAt);
                  if (dt == null) return !_upcomingOnly;
                  return _upcomingOnly
                      ? dt.isAfter(now)
                      : dt.isBefore(now);
                }).toList()
                  ..sort((a, b) {
                    return _upcomingOnly
                        ? a.scheduledAt.compareTo(b.scheduledAt)
                        : b.scheduledAt.compareTo(a.scheduledAt);
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
                                ? T.tr('appointments.no_upcoming')
                                : T.tr('appointments.no_past'),
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

class _AppointmentCard extends StatelessWidget {
  final Appointment appointment;
  final VoidCallback onDelete;
  final VoidCallback onTap;
  const _AppointmentCard({
    required this.appointment,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isCompleted =
        appointment.status?.toLowerCase() == 'completed';

    String? dateStr;
    try {
      final d = DateTime.parse(appointment.scheduledAt);
      dateStr = DateFormat(
              T.lang == 'de'
                  ? 'dd.MM.yyyy \u2013 HH:mm'
                  : 'MMM d, yyyy \u2013 HH:mm')
          .format(d.toLocal());
    } catch (_) {
      dateStr = appointment.scheduledAt;
    }

    return Dismissible(
      key: ValueKey(appointment.id),
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
                              child: Text(
                                T.tr('status.completed'),
                                style: const TextStyle(
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
                      if (appointment.location != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          appointment.location!,
                          style: tt.bodySmall?.copyWith(color: cs.outline),
                        ),
                      ],
                      if (appointment.preparationNotes != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          appointment.preparationNotes!,
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
      ),
    );
  }
}
