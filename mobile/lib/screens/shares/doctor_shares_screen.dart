import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error_messages.dart';
import '../../core/i18n/translations.dart';
import '../../core/theme/spacing.dart';
import '../../models/doctor_share.dart';
import '../../providers/doctor_shares_provider.dart';
import '../../widgets/skeletons.dart';

String _trOr(String key, String fallback) {
  final v = T.tr(key);
  return v == key ? fallback : v;
}

/// Doctor shares list + create/revoke screen.
///
/// Lists active and expired/revoked shares for a profile. A FAB opens a
/// bottom sheet to create a new share (label + expiry + content scope).
/// Tap to copy the share URL to the clipboard, swipe to revoke.
///
/// Endpoints used:
///   * GET  /api/v1/profiles/{profileId}/shares
///   * POST /api/v1/profiles/{profileId}/share
///   * DELETE /api/v1/profiles/{profileId}/share/{shareId}
class DoctorSharesScreen extends ConsumerWidget {
  final String profileId;
  final String? profileName;

  const DoctorSharesScreen({
    super.key,
    required this.profileId,
    this.profileName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(doctorSharesProvider(profileId));
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    // Surface action errors (create/revoke) as SnackBars.
    ref.listen<DoctorShareActionState>(
      doctorSharesControllerProvider,
      (prev, next) {
        if (next.error != null && next.error != prev?.error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(apiErrorMessage(next.error!)),
              backgroundColor: colors.errorContainer,
            ),
          );
        }
      },
    );

    final sharesTitle = _trOr('shares.title', 'Doctor shares');
    return Scaffold(
      appBar: AppBar(
        title: Text(
          profileName == null ? sharesTitle : '$sharesTitle · $profileName',
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreateSheet(context, ref),
        icon: const Icon(Icons.add_link),
        label: Text(_trOr('shares.add', 'New share')),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(doctorSharesProvider(profileId));
          await ref.read(doctorSharesProvider(profileId).future);
        },
        child: asyncList.when(
          loading: () => const SkeletonList(count: 3),
          error: (err, _) => _ErrorView(
            message: apiErrorMessage(err),
            onRetry: () => ref.invalidate(doctorSharesProvider(profileId)),
          ),
          data: (all) {
            if (all.isEmpty) {
              return _EmptyView(colors: colors, text: text);
            }
            final active = all.where((s) => s.active && !s.isRevoked).toList();
            final inactive =
                all.where((s) => !(s.active && !s.isRevoked)).toList();

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              children: [
                if (active.isNotEmpty) ...[
                  _SectionHeader(
                    label: _trOr('shares.active', 'Active'),
                    colors: colors,
                    text: text,
                  ),
                  ...active.map(
                    (s) => _ShareTile(
                      share: s,
                      profileId: profileId,
                      canRevoke: true,
                    ),
                  ),
                ],
                if (inactive.isNotEmpty) ...[
                  _SectionHeader(
                    label: _trOr('shares.expired', 'Expired / revoked'),
                    colors: colors,
                    text: text,
                  ),
                  ...inactive.map(
                    (s) => _ShareTile(
                      share: s,
                      profileId: profileId,
                      canRevoke: false,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _openCreateSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: _CreateShareSheet(profileId: profileId),
      ),
    );
  }
}

// -- Tile --------------------------------------------------------------------

class _ShareTile extends ConsumerWidget {
  final DoctorShare share;
  final String profileId;
  final bool canRevoke;

  const _ShareTile({
    required this.share,
    required this.profileId,
    required this.canRevoke,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final statusLabel = share.isRevoked
        ? 'Revoked'
        : share.isExpired
            ? 'Expired'
            : 'Expires ${_formatDate(share.expiresAt)}';

    final statusColor = share.isRevoked
        ? colors.error
        : share.isExpired
            ? colors.outline
            : colors.primary;

    final tile = ListTile(
      leading: CircleAvatar(
        backgroundColor: canRevoke
            ? colors.primaryContainer
            : colors.surfaceContainerHighest,
        foregroundColor: canRevoke
            ? colors.onPrimaryContainer
            : colors.onSurfaceVariant,
        child: const Icon(Icons.medical_services_outlined),
      ),
      title: Text(
        share.label.isEmpty ? 'Untitled share' : share.label,
        style: text.titleSmall,
      ),
      subtitle: Text(
        statusLabel,
        style: text.bodySmall?.copyWith(color: statusColor),
      ),
      trailing: canRevoke
          ? Icon(Icons.content_copy_outlined, color: colors.onSurfaceVariant)
          : null,
      onTap: canRevoke ? () => _copyUrl(context, ref) : null,
    );

    if (!canRevoke) {
      return tile;
    }
    return Dismissible(
      key: ValueKey('share-${share.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        color: colors.errorContainer,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Tooltip(
          message: _trOr('shares.revoke', 'Revoke'),
          child: Icon(Icons.link_off, color: colors.onErrorContainer),
        ),
      ),
      confirmDismiss: (_) => _confirmRevoke(context),
      onDismissed: (_) async {
        final messenger = ScaffoldMessenger.of(context);
        final ok = await ref
            .read(doctorSharesControllerProvider.notifier)
            .revoke(profileId: profileId, shareId: share.id);
        if (ok) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Share revoked')),
          );
        }
      },
      child: tile,
    );
  }

  Future<void> _copyUrl(BuildContext context, WidgetRef ref) async {
    // The list endpoint does not return a share URL. If this tile was
    // produced by a create response we may have one cached in the action
    // state; otherwise we copy the share id so the user at least has
    // something to work with.
    final cached =
        ref.read(doctorSharesControllerProvider).lastCreated;
    final url = (cached?.id == share.id && cached?.shareUrl != null)
        ? cached!.shareUrl!
        : share.shareUrl ?? share.id;

    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_trOr('shares.copy_link', 'Share link copied to clipboard')),
      ),
    );
  }

  Future<bool> _confirmRevoke(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke share?'),
        content: const Text(
          'The link will stop working immediately. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(_trOr('shares.revoke', 'Revoke')),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

// -- Create sheet ------------------------------------------------------------

class _CreateShareSheet extends ConsumerStatefulWidget {
  final String profileId;
  const _CreateShareSheet({required this.profileId});

  @override
  ConsumerState<_CreateShareSheet> createState() => _CreateShareSheetState();
}

class _CreateShareSheetState extends ConsumerState<_CreateShareSheet> {
  final _labelCtrl = TextEditingController();
  DateTime _expiry = DateTime.now().add(const Duration(days: 1));

  // Cosmetic content scope checkboxes. The backend does not currently
  // persist a content-scope list (see doctor_share.go) — selected items are
  // folded into the label text so the recipient / creator still see them.
  final Map<String, bool> _scope = {
    'Vitals': true,
    'Lab results': true,
    'Medications': false,
    'Diagnoses': false,
    'Allergies': false,
    'Documents': false,
  };

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final busy = ref.watch(
      doctorSharesControllerProvider.select((s) => s.busy),
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_trOr('shares.add', 'New doctor share'), style: text.titleLarge),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _labelCtrl,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Label',
                hintText: 'e.g. Dr. Weber — Cardiology visit',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            InkWell(
              onTap: busy ? null : _pickExpiry,
              borderRadius: BorderRadius.circular(AppSpacing.sm),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Expires on',
                  border: OutlineInputBorder(),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatDate(_expiry)),
                    Icon(Icons.calendar_today_outlined,
                        color: colors.onSurfaceVariant),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Content scope', style: text.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            ..._scope.keys.map(
              (k) => CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(k),
                value: _scope[k] ?? false,
                onChanged: busy
                    ? null
                    : (v) => setState(() => _scope[k] = v ?? false),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: busy ? null : _submit,
              icon: busy
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.onPrimary,
                      ),
                    )
                  : const Icon(Icons.link),
              label: Text(busy ? 'Creating…' : _trOr('shares.add', 'Create share')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiry,
      firstDate: now,
      // Server caps at 7 days (168 h); allow a little slack for the picker.
      lastDate: now.add(const Duration(days: 7)),
    );
    if (picked != null) {
      setState(() => _expiry = picked);
    }
  }

  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final selectedScope =
        _scope.entries.where((e) => e.value).map((e) => e.key).toList();
    final baseLabel = _labelCtrl.text.trim();
    final label = [
      if (baseLabel.isNotEmpty) baseLabel,
      if (selectedScope.isNotEmpty) '[${selectedScope.join(", ")}]',
    ].join(' ').trim();

    final hours = _expiry.difference(DateTime.now()).inHours;
    final clampedHours = hours.clamp(1, 168);

    final result = await ref
        .read(doctorSharesControllerProvider.notifier)
        .create(
          profileId: widget.profileId,
          label: label.isEmpty ? 'Doctor share' : label,
          expiresInHours: clampedHours,
          // TODO(encryption): replace with the real ciphertext bundle once
          // the mobile re-encryption flow lands. The server rejects empty
          // strings, so for now this will surface as an error SnackBar.
          encryptedData: '',
        );

    if (!mounted) return;

    if (result != null) {
      navigator.pop();
      if (result.shareUrl != null) {
        await Clipboard.setData(ClipboardData(text: result.shareUrl!));
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              _trOr('shares.copy_link', 'Share created — link copied to clipboard'),
            ),
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('Share created')),
        );
      }
    }
    // On failure the outer ref.listen surfaces the error.
  }
}

// -- Helpers -----------------------------------------------------------------

String _formatDate(DateTime d) {
  final local = d.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$y-$m-$day $hh:$mm';
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final ColorScheme colors;
  final TextTheme text;
  const _SectionHeader({
    required this.label,
    required this.colors,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm + AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Text(
        label.toUpperCase(),
        style: text.labelSmall?.copyWith(
          color: colors.onSurfaceVariant,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final ColorScheme colors;
  final TextTheme text;
  const _EmptyView({required this.colors, required this.text});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: AppSpacing.xxl * 2),
        Icon(
          Icons.share_outlined,
          size: 56,
          color: colors.onSurfaceVariant,
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: Text(
            'No doctor shares yet',
            style: text.titleMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Text(
              'Create a temporary, end-to-end encrypted link to share '
              'selected health records with a doctor.',
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: AppSpacing.xxl * 2),
        Icon(Icons.error_outline, size: 56, color: colors.error),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Text(message, textAlign: TextAlign.center),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: FilledButton.tonal(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ),
      ],
    );
  }
}
