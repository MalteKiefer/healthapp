import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/notification.dart';
import '../../providers/notifications_provider.dart';
import 'notification_preferences_screen.dart';

/// Full list view of all in-app notifications for the authenticated user.
///
/// Features:
///   * Pull-to-refresh (invalidates [notificationsProvider]).
///   * Unread items are marked with a filled circular indicator
///     (`ColorScheme.primary`).
///   * Tapping an unread item marks it read.
///   * Swipe horizontally to dismiss → DELETE /api/v1/notifications/{id}.
///   * AppBar action "Mark all read" when unread > 0.
///   * AppBar action to navigate to per-channel preferences.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(notificationsProvider);
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          asyncList.maybeWhen(
            data: (result) => result.unreadCount > 0
                ? TextButton(
                    onPressed: () => ref
                        .read(notificationsControllerProvider.notifier)
                        .markAllRead(),
                    child: Text(
                      'Mark all read',
                      style: TextStyle(color: colors.onSurface),
                    ),
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
          IconButton(
            tooltip: 'Preferences',
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const NotificationPreferencesScreen(),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(notificationsProvider);
          await ref.read(notificationsProvider.future);
        },
        child: asyncList.when(
          loading: () => const _LoadingView(),
          error: (err, _) => _ErrorView(
            message: err.toString(),
            onRetry: () => ref.invalidate(notificationsProvider),
          ),
          data: (result) {
            if (result.items.isEmpty) {
              return const _EmptyView();
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: result.items.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                color: colors.outlineVariant,
              ),
              itemBuilder: (ctx, i) {
                final n = result.items[i];
                return Dismissible(
                  key: ValueKey('notif-${n.id}'),
                  direction: DismissDirection.horizontal,
                  background: _swipeBg(colors, alignLeft: true),
                  secondaryBackground: _swipeBg(colors, alignLeft: false),
                  onDismissed: (_) => ref
                      .read(notificationsControllerProvider.notifier)
                      .delete(n.id),
                  child: _NotificationTile(notification: n),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _swipeBg(ColorScheme colors, {required bool alignLeft}) {
    return Container(
      color: colors.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: alignLeft ? Alignment.centerLeft : Alignment.centerRight,
      child: Icon(Icons.delete_outline, color: colors.onErrorContainer),
    );
  }
}

// -- Tile ---------------------------------------------------------------------

class _NotificationTile extends ConsumerWidget {
  final AppNotification notification;
  const _NotificationTile({required this.notification});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final unread = notification.isUnread;

    return ListTile(
      onTap: unread
          ? () => ref
              .read(notificationsControllerProvider.notifier)
              .markRead(notification.id)
          : null,
      leading: CircleAvatar(
        backgroundColor: unread
            ? colors.primaryContainer
            : colors.surfaceContainerHighest,
        foregroundColor:
            unread ? colors.onPrimaryContainer : colors.onSurfaceVariant,
        child: Icon(_iconFor(notification.type), size: 20),
      ),
      title: Text(
        notification.title.isEmpty ? notification.type : notification.title,
        style: text.titleSmall?.copyWith(
          fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
          color: colors.onSurface,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (notification.body.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              notification.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            _formatRelative(notification.createdAt),
            style: text.bodySmall?.copyWith(color: colors.outline),
          ),
        ],
      ),
      trailing: unread
          ? Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
              ),
            )
          : null,
    );
  }

  IconData _iconFor(String type) {
    switch (type) {
      case NotificationTypes.vaccinationDue:
        return Icons.vaccines;
      case NotificationTypes.medicationReminder:
        return Icons.medication;
      case NotificationTypes.appointmentReminder:
        return Icons.event;
      case NotificationTypes.labResultAbnormal:
        return Icons.science;
      case NotificationTypes.emergencyAccessRequest:
        return Icons.emergency;
      case NotificationTypes.sessionNew:
        return Icons.login;
      case NotificationTypes.storageQuotaWarning:
        return Icons.storage;
      case NotificationTypes.familyInvite:
        return Icons.family_restroom;
      case NotificationTypes.keyRotationRequired:
        return Icons.key;
      case NotificationTypes.exportReady:
        return Icons.archive;
      case NotificationTypes.backupFailed:
        return Icons.error_outline;
      default:
        return Icons.notifications_none;
    }
  }

  String _formatRelative(DateTime ts) {
    final diff = DateTime.now().difference(ts);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
    return '${(diff.inDays / 365).floor()}y ago';
  }
}

// -- Status views -------------------------------------------------------------

class _LoadingView extends StatelessWidget {
  const _LoadingView();
  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator()),
        ],
      );
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(Icons.notifications_none, size: 64, color: colors.outline),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'No notifications',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            'You are all caught up.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: colors.outline),
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
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 80),
        Icon(Icons.error_outline, size: 48, color: colors.error),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'Failed to load notifications',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 16),
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
