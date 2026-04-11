import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/profile.dart';
import '../../models/profile_write.dart';
import '../../providers/profile_management_provider.dart';

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
        title: Text(_isEdit ? 'Edit profile' : 'New profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Save',
            onPressed: management.isLoading ? null : _submit,
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: management.isLoading,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _displayNameCtrl,
                decoration: InputDecoration(
                  labelText: 'Display name',
                  border: const OutlineInputBorder(),
                  labelStyle: TextStyle(color: colors.onSurfaceVariant),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Display name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _DatePickerField(
                label: 'Date of birth',
                value: _dateOfBirth,
                colors: colors,
                onChanged: (d) => setState(() => _dateOfBirth = d),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _gender,
                decoration: InputDecoration(
                  labelText: 'Gender',
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
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _bloodType,
                decoration: InputDecoration(
                  labelText: 'Blood type',
                  border: const OutlineInputBorder(),
                  labelStyle: TextStyle(color: colors.onSurfaceVariant),
                ),
                items: _bloodTypeOptions
                    .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                    .toList(),
                onChanged: (v) => setState(() => _bloodType = v),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesCtrl,
                maxLines: 5,
                minLines: 3,
                decoration: InputDecoration(
                  labelText: 'Notes',
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                  labelStyle: TextStyle(color: colors.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: management.isLoading ? null : _submit,
                icon: management.isLoading
                    ? SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.onPrimary,
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(_isEdit ? 'Save changes' : 'Create profile'),
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
    );
  }

  String _labelForGender(String v) {
    switch (v) {
      case 'female':
        return 'Female';
      case 'male':
        return 'Male';
      case 'intersex':
        return 'Intersex';
      case 'other':
        return 'Other';
      case 'prefer_not_to_say':
        return 'Prefer not to say';
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
          content: Text(_isEdit ? 'Profile updated' : 'Profile created'),
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
        ? 'Not set'
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
