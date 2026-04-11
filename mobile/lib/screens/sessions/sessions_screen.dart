import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error_messages.dart';
import '../../core/i18n/translations.dart';
import '../../core/theme/spacing.dart';
import '../../models/user_session.dart';
import '../../providers/sessions_provider.dart';
import '../../widgets/skeletons.dart';

/// Returns the localized string for [key], or [fallback] when the
/// translations table has no entry (in which case `T.tr` echoes the
/// key back unchanged).
String _trOr(String key, String fallback) {
  final v = T.tr(key);
  return v == key ? fallback : v;
}

/// Sprint 3: Session management screen.
///
/// Lists all active sessions for the signed-in user, pinning the
/// current session at the top with a "This device" badge. Users can
/// revoke any non-current session individually, or revoke every
/// other session in one go via the top action.
///
/// Backed by:
///   * GET    /api/v1/users/me/sessions
///   * DELETE /api/v1/users/me/sessions/{sessionId}
///   * DELETE /api/v1/users/me/sessions       (revoke all others)
class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final sessionsAsync = ref.watch(sessionsListProvider);
    final actionState = ref.watch(sessionsControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_trOr('sessions.title', 'Active Sessions')),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(sessionsListProvider),
          ),
        ],
      ),
      body: SafeArea(
        child: sessionsAsync.when(
          loading: () => const SkeletonList(count: 4),
          error: (err, _) => _ErrorView(
            message: apiErrorMessage(err),
            onRetry: () => ref.invalidate(sessionsListProvider),
          ),
          data: (sessions) {
            if (sessions.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    'No active sessions found.',
                    style: tt.bodyLarge
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              );
            }

            final hasOthers = sessions.any((s) => !s.isCurrent);

            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(sessionsListProvider);
                await ref.read(sessionsListProvider.future);
              },
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.sm + AppSpacing.xs,
                ),
                itemCount: sessions.length + 1,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: cs.outlineVariant),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _RevokeAllHeader(
                      enabled: hasOthers && !actionState.revokingAll,
                      busy: actionState.revokingAll,
                      onRevokeAll: () => _confirmRevokeAll(context, ref),
                    );
                  }
                  final session = sessions[index - 1];
                  return _SessionTile(
                    session: session,
                    revoking:
                        actionState.revokingIds.contains(session.id),
                    onRevoke: () =>
                        _confirmRevokeOne(context, ref, session),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _confirmRevokeOne(
    BuildContext context,
    WidgetRef ref,
    UserSession session,
  ) async {
    final confirmed = await _showRevokeSheet(
      context,
      title: 'Revoke this session?',
      message:
          'The device using this session will be signed out the next '
          'time it contacts the server.',
      actionLabel: _trOr('sessions.revoke', 'Revoke session'),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(sessionsControllerProvider.notifier)
          .revoke(session.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session revoked')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(e))),
        );
      }
    }
  }

  Future<void> _confirmRevokeAll(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await _showRevokeSheet(
      context,
      title: 'Revoke all other sessions?',
      message:
          'Every device except this one will be signed out. You will '
          'remain signed in here.',
      actionLabel: _trOr('sessions.revoke_all', 'Revoke all others'),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(sessionsControllerProvider.notifier)
          .revokeAllOthers();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Other sessions revoked')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(e))),
        );
      }
    }
  }

  /// Material 3 confirmation bottom sheet. Returns `true` if the
  /// user tapped the destructive action.
  Future<bool?> _showRevokeSheet(
    BuildContext context, {
    required String title,
    required String message,
    required String actionLabel,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final tt = Theme.of(ctx).textTheme;
        return SafeArea(
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
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: cs.error),
                    const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                    Expanded(
                      child: Text(
                        title,
                        style: tt.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
                Text(
                  message,
                  style:
                      tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.errorContainer,
                    foregroundColor: cs.onErrorContainer,
                  ),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(actionLabel),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RevokeAllHeader extends StatelessWidget {
  const _RevokeAllHeader({
    required this.enabled,
    required this.busy,
    required this.onRevokeAll,
  });

  final bool enabled;
  final bool busy;
  final VoidCallback onRevokeAll;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Manage devices that are currently signed in to your '
            'account. Revoke any session you no longer recognise.',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
          FilledButton.tonalIcon(
            onPressed: enabled ? onRevokeAll : null,
            icon: busy
                ? SizedBox(
                    width: AppSpacing.md,
                    height: AppSpacing.md,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.onSecondaryContainer,
                    ),
                  )
                : const Icon(Icons.logout),
            label: Text(
              _trOr('sessions.revoke_all', 'Revoke all other sessions'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.revoking,
    required this.onRevoke,
  });

  final UserSession session;
  final bool revoking;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final deviceLabel = session.device.isNotEmpty
        ? session.device
        : (session.userAgent.isNotEmpty
            ? session.userAgent
            : 'Unknown device');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      leading: CircleAvatar(
        backgroundColor: session.isCurrent
            ? cs.primaryContainer
            : cs.surfaceContainerHighest,
        foregroundColor: session.isCurrent
            ? cs.onPrimaryContainer
            : cs.onSurfaceVariant,
        child: Icon(
          session.isCurrent ? Icons.smartphone : Icons.devices_other,
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              deviceLabel,
              style: tt.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (session.isCurrent) ...[
            const SizedBox(width: AppSpacing.sm),
            _CurrentBadge(),
          ],
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_trOr('sessions.last_seen', 'Last active')}: '
              '${_formatTimestamp(session.lastSeenAt)}',
              style:
                  tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            if (session.ip.isNotEmpty)
              Text(
                'IP: ${session.ip}',
                style:
                    tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            if (session.device.isEmpty && session.userAgent.isNotEmpty)
              Text(
                session.userAgent,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
          ],
        ),
      ),
      trailing: TextButton(
        onPressed: (session.isCurrent || revoking) ? null : onRevoke,
        style: TextButton.styleFrom(foregroundColor: cs.error),
        child: revoking
            ? SizedBox(
                width: AppSpacing.md,
                height: AppSpacing.md,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.error,
                ),
              )
            : Text(_trOr('sessions.revoke', 'Revoke')),
      ),
    );
  }

  String _formatTimestamp(DateTime ts) {
    final now = DateTime.now();
    final diff = now.difference(ts);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays < 7) return '${diff.inDays} d ago';
    final y = ts.year.toString().padLeft(4, '0');
    final m = ts.month.toString().padLeft(2, '0');
    final d = ts.day.toString().padLeft(2, '0');
    final hh = ts.hour.toString().padLeft(2, '0');
    final mm = ts.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}

class _CurrentBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _trOr('sessions.current', 'This device'),
        style: tt.labelSmall?.copyWith(
          color: cs.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: cs.error),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              style: tt.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
