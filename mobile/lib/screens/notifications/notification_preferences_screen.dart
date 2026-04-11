import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error_messages.dart';
import '../../core/i18n/translations.dart';
import '../../core/theme/spacing.dart';
import '../../models/notification.dart';
import '../../providers/notification_preferences_provider.dart';
import '../../widgets/skeletons.dart';

/// Returns the translation for [key] if present, otherwise [fallback].
/// `T.tr` returns the key itself when no entry is found, so we use that
/// sentinel to detect missing keys and fall back to the English literal.
String _trOr(String key, String fallback) {
  final v = T.tr(key);
  return v == key ? fallback : v;
}

/// Lets the user toggle which notification types the server should emit
/// for them. Loads from and saves to `/api/v1/notifications/preferences`.
///
/// Edits are held in local state (`_draft`) and only persisted when the
/// user taps "Save", at which point
/// [NotificationPreferencesController.save] is called.
class NotificationPreferencesScreen extends ConsumerStatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  ConsumerState<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends ConsumerState<NotificationPreferencesScreen> {
  NotificationPreferences? _draft;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(notificationPreferencesProvider);
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_trOr('notifications.preferences', 'Notification preferences')),
        actions: [
          if (_draft != null)
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      'Save',
                      style: TextStyle(color: colors.onSurface),
                    ),
            ),
        ],
      ),
      body: async.when(
        loading: () => const SkeletonCard(),
        error: (err, _) => Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, color: colors.error, size: 48),
                const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
                Text(
                  'Failed to load preferences',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  apiErrorMessage(err),
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton.tonal(
                  onPressed: () =>
                      ref.invalidate(notificationPreferencesProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (loaded) {
          final prefs = _draft ?? loaded;
          return ListView(
            children: [
              _SectionHeader(label: 'Health reminders', color: colors),
              SwitchListTile(
                title: const Text('Medication reminders'),
                subtitle: const Text(
                    'Alerts when scheduled doses are due.'),
                value: prefs.medicationReminder,
                onChanged: (v) => _update(
                    prefs.copyWith(medicationReminder: v)),
              ),
              SwitchListTile(
                title: const Text('Appointment reminders'),
                subtitle: const Text(
                    'Reminders before upcoming appointments.'),
                // Backend currently has no dedicated flag; reuse medication
                // reminder toggle slot in UI until one exists. For now we
                // treat this as a read-only hint tied to medicationReminder.
                value: prefs.medicationReminder,
                onChanged: (v) => _update(
                    prefs.copyWith(medicationReminder: v)),
              ),
              SwitchListTile(
                title: const Text('Vaccination due'),
                subtitle: Text(
                    'Alert ${prefs.vaccinationDueDays} days before a vaccination is due.'),
                value: prefs.vaccinationDue,
                onChanged: (v) =>
                    _update(prefs.copyWith(vaccinationDue: v)),
              ),
              if (prefs.vaccinationDue)
                ListTile(
                  title: const Text('Lead time (days)'),
                  trailing: DropdownButton<int>(
                    value: _clampDays(prefs.vaccinationDueDays),
                    items: const [7, 14, 30, 60, 90]
                        .map((d) => DropdownMenuItem(
                              value: d,
                              child: Text('$d'),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      _update(prefs.copyWith(vaccinationDueDays: v));
                    },
                  ),
                ),
              SwitchListTile(
                title: const Text('Abnormal lab results'),
                subtitle: const Text(
                    'Notify when a result is flagged as out of range.'),
                value: prefs.labResultAbnormal,
                onChanged: (v) =>
                    _update(prefs.copyWith(labResultAbnormal: v)),
              ),
              const Divider(height: 1),
              _SectionHeader(label: 'Account & security', color: colors),
              SwitchListTile(
                title: const Text('New sign-in alerts'),
                subtitle: const Text(
                    'Notify when a new session signs in to your account.'),
                value: prefs.sessionNew,
                onChanged: (v) => _update(prefs.copyWith(sessionNew: v)),
              ),
              SwitchListTile(
                title: const Text('Emergency access requests'),
                subtitle: const Text(
                    'Someone is requesting your emergency kit.'),
                value: prefs.emergencyAccess,
                onChanged: (v) =>
                    _update(prefs.copyWith(emergencyAccess: v)),
              ),
              SwitchListTile(
                title: const Text('Key rotation required'),
                subtitle: const Text(
                    'Action needed to rotate your encryption keys.'),
                value: prefs.keyRotationRequired,
                onChanged: (v) =>
                    _update(prefs.copyWith(keyRotationRequired: v)),
              ),
              const Divider(height: 1),
              _SectionHeader(label: 'Other', color: colors),
              SwitchListTile(
                title: const Text('Family invites'),
                subtitle: const Text(
                    'Alerts when someone invites you to a family.'),
                value: prefs.familyInvite,
                onChanged: (v) =>
                    _update(prefs.copyWith(familyInvite: v)),
              ),
              SwitchListTile(
                title: const Text('Export ready'),
                subtitle: const Text(
                    'When a data export you requested is ready to download.'),
                value: prefs.exportReady,
                onChanged: (v) =>
                    _update(prefs.copyWith(exportReady: v)),
              ),
              SwitchListTile(
                title: const Text('Storage quota warnings'),
                subtitle: const Text(
                    'Warn when account storage is nearly full.'),
                value: prefs.storageQuotaWarning,
                onChanged: (v) =>
                    _update(prefs.copyWith(storageQuotaWarning: v)),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          );
        },
      ),
    );
  }

  void _update(NotificationPreferences next) {
    setState(() => _draft = next);
  }

  int _clampDays(int days) {
    const allowed = [7, 14, 30, 60, 90];
    if (allowed.contains(days)) return days;
    // Snap to nearest allowed value for the dropdown.
    var best = allowed.first;
    var bestDiff = (days - best).abs();
    for (final d in allowed) {
      final diff = (days - d).abs();
      if (diff < bestDiff) {
        best = d;
        bestDiff = diff;
      }
    }
    return best;
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(notificationPreferencesControllerProvider.notifier)
          .save(draft);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _draft = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preferences saved')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final ColorScheme color;
  const _SectionHeader({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md + AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color.primary,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
