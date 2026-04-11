import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error_messages.dart';
import '../../core/i18n/translations.dart';
import '../../core/theme/spacing.dart';
import '../../models/calendar_feed.dart';
import '../../providers/calendar_feeds_provider.dart';
import '../../providers/providers.dart';
import '../../widgets/skeletons.dart';
import 'calendar_feed_edit_screen.dart';

/// Returns the translation for [key] if present, otherwise [fallback].
/// `T.tr` returns the key itself when no entry is found, so we use that
/// sentinel to detect missing keys and fall back to the English literal.
String _trOr(String key, String fallback) {
  final v = T.tr(key);
  return v == key ? fallback : v;
}

/// Lists all calendar feeds owned by the current user.
///
/// Endpoints used:
///   * `GET /api/v1/calendar/feeds`            (via [calendarFeedsListProvider])
///   * `DELETE /api/v1/calendar/feeds/{feedId}` (via [calendarFeedsNotifierProvider])
///
/// Each tile shows the feed name, the configured content types, and a
/// copy-URL action that copies the public ICS URL to the clipboard.
class CalendarFeedsScreen extends ConsumerWidget {
  const CalendarFeedsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final feedsAsync = ref.watch(calendarFeedsListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_trOr('calendar.title', 'Calendar feeds')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add),
        label: Text(_trOr('calendar.add', 'New feed')),
      ),
      body: feedsAsync.when(
        loading: () => const SkeletonList(count: 3),
        error: (err, _) => _ErrorState(
          message: apiErrorMessage(err),
          onRetry: () => ref.invalidate(calendarFeedsListProvider),
        ),
        data: (feeds) {
          if (feeds.isEmpty) {
            return _EmptyState(colors: colors);
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(calendarFeedsListProvider),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              itemCount: feeds.length,
              separatorBuilder: (_, i) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final feed = feeds[index];
                return _FeedTile(
                  feed: feed,
                  onTap: () => _openEditor(context, feed: feed),
                  onCopyUrl: () => _copyUrl(context, ref, feed),
                  onDelete: () => _confirmDelete(context, ref, feed),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _openEditor(BuildContext context, {CalendarFeed? feed}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CalendarFeedEditScreen(existing: feed),
      ),
    );
  }

  Future<void> _copyUrl(
    BuildContext context,
    WidgetRef ref,
    CalendarFeed feed,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final colors = Theme.of(context).colorScheme;
    // Prefer the freshly-created URL if we still have it; otherwise build
    // it from the API base URL + token hash. The token-hash form is the
    // identifier the backend looks up at /cal/{token}.ics, so it works as
    // a stable URL once the feed has been created.
    final url = feed.url ??
        buildIcsUrl(ref.read(apiClientProvider).baseUrl, feed.token);
    if (url.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: colors.errorContainer,
          content: Text(
            'No URL available for this feed.',
            style: TextStyle(color: colors.onErrorContainer),
          ),
        ),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: colors.secondaryContainer,
        content: Text(
          'ICS URL copied to clipboard',
          style: TextStyle(color: colors.onSecondaryContainer),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    CalendarFeed feed,
  ) async {
    final colors = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(calendarFeedsNotifierProvider.notifier);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete feed?'),
        content: Text(
          'The ICS URL for "${feed.name}" will stop working. '
          'Calendar apps subscribed to it will fail to refresh.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colors.error,
              foregroundColor: colors.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await notifier.delete(feed.id);
    if (!ok) {
      final err = ref.read(calendarFeedsNotifierProvider).error;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: colors.errorContainer,
          content: Text(
            err != null ? apiErrorMessage(err) : 'Could not delete feed.',
            style: TextStyle(color: colors.onErrorContainer),
          ),
        ),
      );
    }
  }
}

class _FeedTile extends StatelessWidget {
  const _FeedTile({
    required this.feed,
    required this.onTap,
    required this.onCopyUrl,
    required this.onDelete,
  });

  final CalendarFeed feed;
  final VoidCallback onTap;
  final VoidCallback onCopyUrl;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final typesLabel = feed.contentTypes.isEmpty
        ? 'No content types selected'
        : feed.contentTypes
            .map(CalendarFeedContentType.label)
            .join(' \u00B7 ');

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: colors.primaryContainer,
        foregroundColor: colors.onPrimaryContainer,
        child: const Icon(Icons.calendar_month_outlined),
      ),
      title: Text(
        feed.name.isEmpty ? '(unnamed feed)' : feed.name,
        style: text.titleMedium,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Text(
          typesLabel,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Copy ICS URL',
            icon: const Icon(Icons.link),
            onPressed: onCopyUrl,
          ),
          IconButton(
            tooltip: 'Delete',
            icon: Icon(Icons.delete_outline, color: colors.error),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.colors});
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_month_outlined,
              size: 64,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No calendar feeds yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Create a feed to subscribe to your appointments, '
              'medications and more from any calendar app.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: colors.error, size: 48),
            const SizedBox(height: AppSpacing.sm),
            Text(message, textAlign: TextAlign.center),
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
