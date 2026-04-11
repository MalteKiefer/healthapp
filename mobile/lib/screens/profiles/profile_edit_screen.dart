import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/translations.dart';
import '../../core/theme/spacing.dart';
import '../../models/profile.dart';
import '../../models/profile_write.dart';
import '../../providers/profile_management_provider.dart';

String _trOr(String key, String fallback) {
  final v = T.tr(key);
  return v == key ? fallback : v;
}

/// Form screen used for both creating a new profile and editing an
/// existing one. Pass [initial] to edit; pass null to create.
class ProfileEditScreen extends ConsumerStatefulWidget {
  final Profile? initial;

  const ProfileEditScreen({super.key, this.initial});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _displayNameCtrl;
  late final TextEditingController _notesCtrl;

  DateTime? _dateOfBirth;
  String? _gender;
  String? _bloodType;

  static const _genderOptions = <String>[
    'female',
    'male',
    'intersex',
    'other',
    'prefer_not_to_say',
  ];

  static const _bloodTypeOptions = <String>[
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
    'O+',
    'O-',
  ];

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _displayNameCtrl = TextEditingController(text: init?.displayName ?? '');
    _notesCtrl = TextEditingController();
    if (init?.dateOfBirth != null && init!.dateOfBirth!.isNotEmpty) {
      _dateOfBirth = DateTime.tryParse(init.dateOfBirth!);
    }
    final sex = init?.biologicalSex;
    if (sex != null && _genderOptions.contains(sex)) {
      _gender = sex;
    }
    final bt = init?.bloodType;
    if (bt != null && _bloodTypeOptions.contains(bt)) {
      _bloodType = bt;
    }
  }

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final management = ref.watch(profileManagementProvider);

    ref.listen<ProfileManagementState>(profileManagementProvider, (prev, next) {
      final err = next.error;
      if (err != null && err != prev?.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err),
            backgroundColor: colors.errorContainer,
          ),
        );
        ref.read(profileManagementProvider.notifier).clearError();
      }
    });

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        title: Text(_isEdit
            ? _trOr('profiles.edit', 'Edit profile')
            : _trOr('profiles.new', 'New profile')),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: _trOr('common.save', 'Save'),
            onPressed: management.isLoading ? null : _submit,
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: management.isLoading,
        child: AutofillGroup(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                TextFormField(
                  controller: _displayNameCtrl,
                  autofillHints: const [AutofillHints.name],
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText:
                        _trOr('profiles.field_display_name', 'Display name'),
                    border: const OutlineInputBorder(),
                    labelStyle: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return _trOr('profiles.display_name_required',
                          'Display name is required');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                _DatePickerField(
                  label: _trOr('profiles.field_dob', 'Date of birth'),
                  value: _dateOfBirth,
                  colors: colors,
                  onChanged: (d) => setState(() => _dateOfBirth = d),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: _gender,
                  decoration: InputDecoration(
                    labelText: _trOr('profiles.field_gender', 'Gender'),
                    border: const OutlineInputBorder(),
                    labelStyle: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  items: _genderOptions
                      .map((g) => DropdownMenuItem(
                            value: g,
                            child: Text(_labelForGender(g)),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _gender = v),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: _bloodType,
                  decoration: InputDecoration(
                    labelText:
                        _trOr('profiles.field_blood_type', 'Blood type'),
                    border: const OutlineInputBorder(),
                    labelStyle: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  items: _bloodTypeOptions
                      .map((b) =>
                          DropdownMenuItem(value: b, child: Text(b)))
                      .toList(),
                  onChanged: (v) => setState(() => _bloodType = v),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _notesCtrl,
                  maxLines: 5,
                  minLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: _trOr('profiles.field_notes', 'Notes'),
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                    labelStyle: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: management.isLoading ? null : _submit,
                  icon: management.isLoading
                      ? SizedBox(
                          height: AppSpacing.md,
                          width: AppSpacing.md,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.onPrimary,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: Text(_isEdit
                      ? _trOr('profiles.save_changes', 'Save changes')
                      : _trOr('profiles.create', 'Create profile')),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: colors.onPrimary,
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _labelForGender(String v) {
    switch (v) {
      case 'female':
        return _trOr('profiles.gender.female', 'Female');
      case 'male':
        return _trOr('profiles.gender.male', 'Male');
      case 'intersex':
        return _trOr('profiles.gender.intersex', 'Intersex');
      case 'other':
        return _trOr('profiles.gender.other', 'Other');
      case 'prefer_not_to_say':
        return _trOr('profiles.gender.prefer_not_to_say', 'Prefer not to say');
      default:
        return v;
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final notesText = _notesCtrl.text.trim();
    final req = ProfileWriteRequest(
      displayName: _displayNameCtrl.text.trim(),
      dateOfBirth: _dateOfBirth?.toIso8601String().split('T').first,
      biologicalSex: _gender,
      bloodType: _bloodType,
      notes: notesText.isEmpty ? null : notesText,
    );

    final notifier = ref.read(profileManagementProvider.notifier);
    final Profile? result = _isEdit
        ? await notifier.update(widget.initial!.id, req)
        : await notifier.create(req);

    if (!mounted) return;
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEdit
              ? _trOr('profiles.updated', 'Profile updated')
              : _trOr('profiles.created', 'Profile created')),
        ),
      );
      Navigator.of(context).pop(result);
    }
  }
}

class _DatePickerField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ColorScheme colors;
  final ValueChanged<DateTime?> onChanged;

  const _DatePickerField({
    required this.label,
    required this.value,
    required this.colors,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? _trOr('common.not_set', 'Not set')
        : value!.toIso8601String().split('T').first;

    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime(now.year - 30, now.month, now.day),
          firstDate: DateTime(1900),
          lastDate: now,
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          labelStyle: TextStyle(color: colors.onSurfaceVariant),
          suffixIcon: value == null
              ? const Icon(Icons.calendar_today)
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => onChanged(null),
                ),
        ),
        child: Text(
          text,
          style: TextStyle(color: colors.onSurface),
        ),
      ),
    );
  }
}
