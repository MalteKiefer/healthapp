import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error_messages.dart';
import '../../core/i18n/translations.dart';
import '../../core/theme/spacing.dart';
import '../../models/calendar_feed.dart';
import '../../models/profile.dart';
import '../../providers/calendar_feeds_provider.dart';
import '../../providers/providers.dart';
import '../../widgets/skeletons.dart';

/// Returns the translation for [key] if present, otherwise [fallback].
/// `T.tr` returns the key itself when no entry is found, so we use that
/// sentinel to detect missing keys and fall back to the English literal.
String _trOr(String key, String fallback) {
  final v = T.tr(key);
  return v == key ? fallback : v;
}

/// Create / edit form for a calendar feed.
///
/// Pass [existing] to edit; pass null to create. On a successful create,
/// the screen displays the one-time plaintext ICS URL with a copy button
/// before popping back to the list.
class CalendarFeedEditScreen extends ConsumerStatefulWidget {
  const CalendarFeedEditScreen({super.key, this.existing});

  final CalendarFeed? existing;

  @override
  ConsumerState<CalendarFeedEditScreen> createState() =>
      _CalendarFeedEditScreenState();
}

class _CalendarFeedEditScreenState
    extends ConsumerState<CalendarFeedEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  String? _selectedProfileId;
  late Set<String> _selectedTypes;
  bool _verboseMode = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameCtrl = TextEditingController(text: existing?.name ?? '');
    _selectedProfileId = existing?.profileId;
    _selectedTypes = existing == null
        ? <String>{
            CalendarFeedContentType.appointments,
            CalendarFeedContentType.medications,
            CalendarFeedContentType.tasks,
          }
        : existing.contentTypes.toSet();
    _verboseMode = existing?.verboseMode ?? false;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.existing != null;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final mutation = ref.watch(calendarFeedsNotifierProvider);
    // The profiles list is loaded with an arbitrary cache key — every
    // existing screen passes an empty string, see providers.dart.
    final profilesAsync = ref.watch(profilesProvider(''));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEdit
              ? _trOr('calendar.edit', 'Edit calendar feed')
              : _trOr('calendar.add', 'New calendar feed'),
        ),
        actions: [
          TextButton(
            onPressed: mutation.busy ? null : _submit,
            child: Text(
              _isEdit ? 'Save' : 'Create',
              style: TextStyle(color: colors.primary),
            ),
          ),
        ],
      ),
      body: profilesAsync.when(
        loading: () => const SkeletonCard(),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(apiErrorMessage(err)),
          ),
        ),
        data: (profiles) => _buildForm(context, profiles, mutation),
      ),
    );
  }

  Widget _buildForm(
    BuildContext context,
    List<Profile> profiles,
    CalendarFeedsMutationState mutation,
  ) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    // Auto-pick a default profile when creating, if none is set yet.
    if (_selectedProfileId == null && profiles.isNotEmpty) {
      _selectedProfileId = profiles.first.id;
    }

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          TextFormField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Family medical calendar',
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return 'Please enter a name.';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Profile', style: text.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String>(
            initialValue: _selectedProfileId,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
            items: profiles
                .map(
                  (p) => DropdownMenuItem<String>(
                    value: p.id,
                    child: Text(p.displayName),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _selectedProfileId = v),
            validator: (v) =>
                (v == null || v.isEmpty) ? 'Please pick a profile.' : null,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            _trOr('calendar.content_types', 'Content types'),
            style: text.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Choose what should be included in the ICS feed.',
            style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            elevation: 0,
            color: colors.surfaceContainerHighest,
            child: Column(
              children: CalendarFeedContentType.all
                  .map(
                    (type) => CheckboxListTile(
                      value: _selectedTypes.contains(type),
                      title: Text(CalendarFeedContentType.label(type)),
                      onChanged: (checked) {
                        setState(() {
                          if (checked == true) {
                            _selectedTypes.add(type);
                          } else {
                            _selectedTypes.remove(type);
                          }
                        });
                      },
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SwitchListTile(
            value: _verboseMode,
            title: const Text('Verbose mode'),
            subtitle: Text(
              'Include full details (titles, notes) in calendar events. '
              'When off, events use generic labels for privacy.',
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            onChanged: (v) => setState(() => _verboseMode = v),
          ),
          if (mutation.error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                apiErrorMessage(mutation.error!),
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: mutation.busy ? null : _submit,
            child: mutation.busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isEdit ? 'Save changes' : 'Create feed'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedTypes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick at least one content type.')),
      );
      return;
    }

    final notifier = ref.read(calendarFeedsNotifierProvider.notifier);
    final name = _nameCtrl.text.trim();
    final profileId = _selectedProfileId!;
    final types = _selectedTypes.toList();

    if (_isEdit) {
      final ok = await notifier.update(
        feedId: widget.existing!.id,
        name: name,
        profileId: profileId,
        extraProfileIds: widget.existing!.extraProfileIds,
        contentTypes: types,
        verboseMode: _verboseMode,
      );
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop();
      }
    } else {
      final feed = await notifier.create(
        name: name,
        profileId: profileId,
        contentTypes: types,
        verboseMode: _verboseMode,
      );
      if (!mounted) return;
      if (feed != null) {
        await _showCreatedDialog(feed);
        if (!mounted) return;
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _showCreatedDialog(CalendarFeed feed) async {
    final colors = Theme.of(context).colorScheme;
    // Prefer the URL the backend hands back on create — it has the
    // plaintext token embedded. Fall back to building one from the API
    // base URL only if for some reason the server didn't return one.
    final url = feed.url ??
        buildIcsUrl(ref.read(apiClientProvider).baseUrl, feed.token);

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Feed created'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Subscribe to this URL from any calendar app. '
              'You can copy it again later from the feeds list.',
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                url,
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: colors.onSurface,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard')),
                );
              }
            },
            child: const Text('Copy URL'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
