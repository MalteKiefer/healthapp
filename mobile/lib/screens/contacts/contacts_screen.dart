import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api/api_error_messages.dart';
import '../../core/i18n/translations.dart';
import '../../models/common.dart';
import '../../providers/providers.dart';
import '../../widgets/delete_confirm_dialog.dart';
import '../../widgets/error_widget.dart';
import '../../widgets/loading_widget.dart';

// -- Provider -----------------------------------------------------------------

final _contactsProvider =
    FutureProvider.family<List<Contact>, String>((ref, profileId) async {
  final api = ref.read(apiClientProvider);
  final crypto = ref.watch(e2eCryptoServiceProvider);
  final data = await api
      .get<Map<String, dynamic>>('/api/v1/profiles/$profileId/contacts');
  final rawItems = (data['items'] as List?) ?? const [];
  final decrypted = await crypto.decryptRows(
    rows: rawItems,
    profileId: profileId,
    entityType: 'contacts',
  );
  return decrypted.map(Contact.fromJson).toList();
});

// -- Screen -------------------------------------------------------------------

class ContactsScreen extends ConsumerStatefulWidget {
  final String profileId;
  const ContactsScreen({super.key, required this.profileId});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  Future<void> _delete(String id) async {
    final confirmed = await showDeleteConfirmDialog(
      context,
      titleKey: 'contacts.delete',
      bodyKey: 'contacts.delete_body',
    );
    if (!confirmed) return;
    await HapticFeedback.mediumImpact();
    try {
      await ref
          .read(apiClientProvider)
          .delete('/api/v1/profiles/${widget.profileId}/contacts/$id');
      ref.invalidate(_contactsProvider(widget.profileId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(apiErrorMessage(e)),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _showFormSheet({Contact? existing}) async {
    final api = ref.read(apiClientProvider);
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final specialtyCtrl =
        TextEditingController(text: existing?.specialty ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final emailCtrl = TextEditingController(text: existing?.email ?? '');
    final facilityCtrl =
        TextEditingController(text: existing?.facility ?? '');
    final countryCtrl =
        TextEditingController(text: existing?.country ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');

    // Parse address into parts if editing
    String existingStreet = '';
    String existingPostal = '';
    String existingCity = '';
    if (isEdit && existing.address != null) {
      final parts = existing.address!.split(', ');
      if (parts.isNotEmpty) existingStreet = parts[0];
      if (parts.length > 1) {
        final cityParts = parts[1].split(' ');
        if (cityParts.isNotEmpty) existingPostal = cityParts[0];
        if (cityParts.length > 1) {
          existingCity = cityParts.sublist(1).join(' ');
        }
      }
    }

    final streetCtrl = TextEditingController(text: existingStreet);
    final cityCtrl = TextEditingController(text: existingCity);
    final postalCtrl = TextEditingController(text: existingPostal);
    final formKey = GlobalKey<FormState>();
    String? contactType = existing?.contactType;
    bool isEmergency = existing?.isEmergencyContact ?? false;

    const contactTypes = [
      'doctor',
      'specialist',
      'hospital',
      'pharmacy',
      'therapist',
      'other'
    ];

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
                    isEdit ? T.tr('contacts.edit') : T.tr('contacts.add'),
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
                  DropdownButtonFormField<String>(
                    value: contactTypes.contains(contactType)
                        ? contactType
                        : null,
                    decoration: InputDecoration(
                        labelText: T.tr('contacts.contact_type')),
                    items: contactTypes
                        .map((t) => DropdownMenuItem(
                              value: t,
                              child: Text(T.tr('contacts.type_$t')),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setSheetState(() => contactType = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: specialtyCtrl,
                    decoration:
                        InputDecoration(labelText: T.tr('field.specialty')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneCtrl,
                    decoration: InputDecoration(labelText: T.tr('field.phone')),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailCtrl,
                    decoration: InputDecoration(labelText: T.tr('field.email')),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: streetCtrl,
                    decoration: InputDecoration(labelText: T.tr('field.street')),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: postalCtrl,
                          decoration:
                              InputDecoration(labelText: T.tr('field.postal_code')),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: cityCtrl,
                          decoration:
                              InputDecoration(labelText: T.tr('field.city')),
                        ),
                      ),
                    ],
                  ),
                  // -- Advanced --
                  ExpansionTile(
                    title: Text(T.tr('common.advanced')),
                    children: [
                      TextField(
                        controller: facilityCtrl,
                        decoration: InputDecoration(
                            labelText: T.tr('contacts.facility')),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: countryCtrl,
                        decoration: InputDecoration(
                            labelText: T.tr('contacts.country')),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: notesCtrl,
                        decoration: InputDecoration(
                            labelText: T.tr('common.notes')),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        title: Text(T.tr('contacts.is_emergency')),
                        value: isEmergency,
                        onChanged: (v) =>
                            setSheetState(() => isEmergency = v),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      Navigator.pop(ctx);
                      final addrParts = [
                        streetCtrl.text.trim(),
                        if (postalCtrl.text.trim().isNotEmpty ||
                            cityCtrl.text.trim().isNotEmpty)
                          '${postalCtrl.text.trim()} ${cityCtrl.text.trim()}'
                              .trim(),
                      ].where((s) => s.isNotEmpty).toList();
                      final body = <String, dynamic>{
                        'name': nameCtrl.text.trim(),
                        if (contactType != null)
                          'contact_type': contactType,
                        if (specialtyCtrl.text.trim().isNotEmpty)
                          'specialty': specialtyCtrl.text.trim(),
                        if (facilityCtrl.text.trim().isNotEmpty)
                          'facility': facilityCtrl.text.trim(),
                        if (phoneCtrl.text.trim().isNotEmpty)
                          'phone': phoneCtrl.text.trim(),
                        if (emailCtrl.text.trim().isNotEmpty)
                          'email': emailCtrl.text.trim(),
                        if (addrParts.isNotEmpty)
                          'address': addrParts.join(', '),
                        if (countryCtrl.text.trim().isNotEmpty)
                          'country': countryCtrl.text.trim(),
                        if (notesCtrl.text.trim().isNotEmpty)
                          'notes': notesCtrl.text.trim(),
                        'is_emergency_contact': isEmergency,
                      };
                      try {
                        final crypto = ref.read(e2eCryptoServiceProvider);
                        final write = await crypto.encryptForWrite(
                          profileId: widget.profileId,
                          entityType: 'contacts',
                          body: body,
                          existingId: isEdit ? existing.id : null,
                        );
                        if (isEdit) {
                          await api.patch<void>(
                            '/api/v1/profiles/${widget.profileId}/contacts/${write.id}',
                            body: write.toBody(),
                          );
                        } else {
                          await api.post<void>(
                            '/api/v1/profiles/${widget.profileId}/contacts',
                            body: write.toBody(),
                          );
                        }
                        ref.invalidate(
                            _contactsProvider(widget.profileId));
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
    specialtyCtrl.dispose();
    phoneCtrl.dispose();
    emailCtrl.dispose();
    streetCtrl.dispose();
    cityCtrl.dispose();
    postalCtrl.dispose();
    facilityCtrl.dispose();
    countryCtrl.dispose();
    notesCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final asyncVal = ref.watch(_contactsProvider(widget.profileId));

    return Scaffold(
      appBar: AppBar(
        title: Text(T.tr('contacts.title')),
        automaticallyImplyLeading: false,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showFormSheet(),
        tooltip: T.tr('contacts.add'),
        child: const Icon(Icons.add),
      ),
      body: asyncVal.when(
        loading: () => const LoadingWidget(),
        error: (e, _) => AppErrorWidget(
          message: T.tr('contacts.failed'),
          onRetry: () => ref.invalidate(_contactsProvider(widget.profileId)),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.contacts_outlined, size: 48, color: cs.outline),
                const SizedBox(height: 12),
                Text(T.tr('contacts.no_data'),
                    style:
                        tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(_contactsProvider(widget.profileId));
            },
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _ContactCard(
                contact: items[i],
                onDelete: () => _delete(items[i].id),
                onTap: () => _showFormSheet(existing: items[i]),
              ),
            ),
          );
        },
      ),
    );
  }
}

// -- Card ---------------------------------------------------------------------

class _ContactCard extends StatelessWidget {
  final Contact contact;
  final VoidCallback onDelete;
  final VoidCallback onTap;
  const _ContactCard({
    required this.contact,
    required this.onDelete,
    required this.onTap,
  });

  void _launchPhone(String phone) {
    launchUrl(Uri(scheme: 'tel', path: phone));
  }

  void _launchEmail(String email) {
    launchUrl(Uri(scheme: 'mailto', path: email));
  }

  void _launchMap(String address) {
    launchUrl(Uri.parse('geo:0,0?q=${Uri.encodeComponent(address)}'));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Dismissible(
      key: ValueKey(contact.id),
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
                child: Icon(Icons.person,
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
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  contact.name,
                                  style: tt.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              if (contact.isEmergencyContact) ...[
                                const SizedBox(width: 6),
                                Icon(Icons.emergency,
                                    size: 16, color: cs.error),
                              ],
                            ],
                          ),
                        ),
                        if (contact.specialty != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: cs.tertiaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              contact.specialty!,
                              style: tt.labelSmall?.copyWith(
                                  color: cs.onTertiaryContainer,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                      ],
                    ),
                    if (contact.phone != null) ...[
                      const SizedBox(height: 4),
                      Tooltip(
                        message: T.tr('field.phone'),
                        child: Semantics(
                          button: true,
                          label: T.tr('field.phone'),
                          child: InkWell(
                        onTap: () => _launchPhone(contact.phone!),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Icon(Icons.phone_outlined,
                                  size: 14, color: cs.primary),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  contact.phone!,
                                  style: tt.bodySmall?.copyWith(
                                    color: cs.primary,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                        ),
                      ),
                    ],
                    if (contact.email != null) ...[
                      const SizedBox(height: 2),
                      Tooltip(
                        message: T.tr('field.email'),
                        child: Semantics(
                          button: true,
                          label: T.tr('field.email'),
                          child: InkWell(
                        onTap: () => _launchEmail(contact.email!),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Icon(Icons.email_outlined,
                                  size: 14, color: cs.primary),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  contact.email!,
                                  style: tt.bodySmall?.copyWith(
                                    color: cs.primary,
                                    decoration: TextDecoration.underline,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                        ),
                      ),
                    ],
                    if (contact.address != null) ...[
                      const SizedBox(height: 2),
                      Tooltip(
                        message: T.tr('field.address'),
                        child: Semantics(
                          button: true,
                          label: T.tr('field.address'),
                          child: InkWell(
                        onTap: () => _launchMap(contact.address!),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.map_outlined,
                                  size: 14, color: cs.primary),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  contact.address!,
                                  style: tt.bodySmall?.copyWith(
                                    color: cs.primary,
                                    decoration: TextDecoration.underline,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                        ),
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
