import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/translations.dart';
import '../../core/theme/spacing.dart';
import '../../models/profile.dart';
import '../../providers/profile_management_provider.dart';
import '../../providers/providers.dart';
import '../../widgets/skeletons.dart';
import 'profile_edit_screen.dart';

/// Lists all profiles with edit, delete, archive/unarchive actions.
/// Archived profiles live under a collapsible section at the bottom.
class ProfileListScreen extends ConsumerWidget {
  const ProfileListScreen({super.key});

  /// Returns the translated string for [key], or [fallback] if the key is
  /// not registered (i.e. `T.tr` returned the key unchanged).
  String _trOr(String key, String fallback) {
    final v = T.tr(key);
    return v == key ? fallback : v;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final listAsync = ref.watch(profilesWithMetaProvider);
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
        title: Text(_trOr('profiles.title', 'Profiles')),
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
      ),
      body: Stack(
        children: [
          listAsync.when(
            data: (items) {
              final active = items.where((p) => !p.isArchived).toList();
              final archived = items.where((p) => p.isArchived).toList();

              if (items.isEmpty) {
                return _EmptyState(colors: colors, trOr: _trOr);
              }

              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(profilesProvider(''));
                  await ref.read(profilesWithMetaProvider.future);
                },
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  children: [
                    if (active.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Text(
                          _trOr(
                            'profiles.no_active',
                            'No active profiles. Tap + to create one.',
                          ),
                          style: textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ...active.map(
                      (p) => _ProfileTile(
                        meta: p,
                        trOr: _trOr,
                        onEdit: () => _openEdit(context, p.profile),
                        onDelete: () => _confirmDelete(context, ref, p.profile),
                        onArchive: () => ref
                            .read(profileManagementProvider.notifier)
                            .archive(p.profile.id),
                        onUnarchive: null,
                      ),
                    ),
                    if (archived.isNotEmpty)
                      _ArchivedSection(
                        colors: colors,
                        archived: archived,
                        trOr: _trOr,
                        onEdit: (p) => _openEdit(context, p),
                        onDelete: (p) => _confirmDelete(context, ref, p),
                        onUnarchive: (p) => ref
                            .read(profileManagementProvider.notifier)
                            .unarchive(p.id),
                      ),
                  ],
                ),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: SkeletonList(count: 5),
            ),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline,
                        color: colors.error, size: 48),
                    const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
                    Text(
                      '${_trOr('profiles.load_failed', 'Failed to load profiles')}: $e',
                      style: textTheme.bodyMedium?.copyWith(
                        color: colors.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
                    FilledButton(
                      onPressed: () =>
                          ref.invalidate(profilesWithMetaProvider),
                      child: Text(_trOr('common.retry', 'Retry')),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (management.isLoading)
            Positioned.fill(
              child: ColoredBox(
                color: colors.scrim.withValues(alpha: 0.2),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEdit(context, null),
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        icon: const Icon(Icons.person_add),
        label: Text(_trOr('profiles.add', 'New profile')),
      ),
    );
  }

  void _openEdit(BuildContext context, Profile? initial) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileEditScreen(initial: initial),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Profile p,
  ) async {
    final colors = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_trOr('profiles.delete_confirm', 'Delete profile?')),
        content: Text(
          _trOr(
            'profiles.delete_body',
            'This permanently deletes "${p.displayName}" and all its data. '
                'This cannot be undone.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(_trOr('common.cancel', 'Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: colors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(_trOr('common.delete', 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(profileManagementProvider.notifier).delete(p.id);
    }
  }
}

class _ProfileTile extends StatelessWidget {
  final ProfileWithMeta meta;
  final String Function(String, String) trOr;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onArchive;
  final VoidCallback? onUnarchive;

  const _ProfileTile({
    required this.meta,
    required this.trOr,
    required this.onEdit,
    required this.onDelete,
    required this.onArchive,
    required this.onUnarchive,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final p = meta.profile;
    final subtitleBits = <String>[
      if (p.dateOfBirth != null && p.dateOfBirth!.isNotEmpty) p.dateOfBirth!,
      if (p.biologicalSex != null && p.biologicalSex!.isNotEmpty)
        p.biologicalSex!,
      if (p.bloodType != null && p.bloodType!.isNotEmpty) p.bloodType!,
    ];

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + AppSpacing.xs,
        vertical: AppSpacing.xs + 2,
      ),
      color: colors.surfaceContainer,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colors.primaryContainer,
          foregroundColor: colors.onPrimaryContainer,
          child: Text(
            p.displayName.isNotEmpty ? p.displayName[0].toUpperCase() : '?',
          ),
        ),
        title: Text(
          p.displayName,
          style: textTheme.titleMedium?.copyWith(color: colors.onSurface),
        ),
        subtitle: subtitleBits.isEmpty
            ? null
            : Text(
                subtitleBits.join('  •  '),
                style: textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
        trailing: PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: colors.onSurfaceVariant),
          onSelected: (v) {
            switch (v) {
              case 'edit':
                onEdit();
                break;
              case 'archive':
                onArchive?.call();
                break;
              case 'unarchive':
                onUnarchive?.call();
                break;
              case 'delete':
                onDelete();
                break;
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'edit',
              child: Text(trOr('common.edit', 'Edit')),
            ),
            if (onArchive != null)
              PopupMenuItem(
                value: 'archive',
                child: Text(trOr('profiles.archive', 'Archive')),
              ),
            if (onUnarchive != null)
              PopupMenuItem(
                value: 'unarchive',
                child: Text(trOr('profiles.unarchive', 'Unarchive')),
              ),
            PopupMenuItem(
              value: 'delete',
              child: Text(trOr('common.delete', 'Delete')),
            ),
          ],
        ),
        onTap: onEdit,
      ),
    );
  }
}

class _ArchivedSection extends StatefulWidget {
  final ColorScheme colors;
  final List<ProfileWithMeta> archived;
  final String Function(String, String) trOr;
  final void Function(Profile) onEdit;
  final void Function(Profile) onDelete;
  final void Function(Profile) onUnarchive;

  const _ArchivedSection({
    required this.colors,
    required this.archived,
    required this.trOr,
    required this.onEdit,
    required this.onDelete,
    required this.onUnarchive,
  });

  @override
  State<_ArchivedSection> createState() => _ArchivedSectionState();
}

class _ArchivedSectionState extends State<_ArchivedSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: widget.colors.surface,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm + AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: widget.colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      '${widget.trOr('profiles.archived_section', 'Archived')} '
                      '(${widget.archived.length})',
                      style: textTheme.titleSmall?.copyWith(
                        color: widget.colors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded)
            ...widget.archived.map(
              (p) => _ProfileTile(
                meta: p,
                trOr: widget.trOr,
                onEdit: () => widget.onEdit(p.profile),
                onDelete: () => widget.onDelete(p.profile),
                onArchive: null,
                onUnarchive: () => widget.onUnarchive(p.profile),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final ColorScheme colors;
  final String Function(String, String) trOr;

  const _EmptyState({required this.colors, required this.trOr});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 64, color: colors.onSurfaceVariant),
            const SizedBox(height: AppSpacing.md),
            Text(
              trOr('profiles.empty_title', 'No profiles yet'),
              style: textTheme.titleMedium?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              trOr(
                'profiles.empty_body',
                'Tap the button below to create your first profile.',
              ),
              style: textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
