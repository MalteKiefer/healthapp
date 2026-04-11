import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/profile.dart';
import '../../providers/profile_management_provider.dart';
import '../../providers/providers.dart';
import 'profile_edit_screen.dart';

/// Lists all profiles with edit, delete, archive/unarchive actions.
/// Archived profiles live under a collapsible section at the bottom.
class ProfileListScreen extends ConsumerWidget {
  const ProfileListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
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
        title: const Text('Profiles'),
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
                return _EmptyState(colors: colors);
              }

              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(profilesProvider(''));
                  await ref.read(profilesWithMetaProvider.future);
                },
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    if (active.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No active profiles. Tap + to create one.',
                          style: TextStyle(color: colors.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ...active.map(
                      (p) => _ProfileTile(
                        meta: p,
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
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline,
                        color: colors.error, size: 48),
                    const SizedBox(height: 12),
                    Text('Failed to load profiles: $e',
                        style: TextStyle(color: colors.onSurface),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () =>
                          ref.invalidate(profilesWithMetaProvider),
                      child: const Text('Retry'),
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
        label: const Text('New profile'),
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
        title: const Text('Delete profile?'),
        content: Text(
          'This permanently deletes "${p.displayName}" and all its data. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: colors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
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
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onArchive;
  final VoidCallback? onUnarchive;

  const _ProfileTile({
    required this.meta,
    required this.onEdit,
    required this.onDelete,
    required this.onArchive,
    required this.onUnarchive,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final p = meta.profile;
    final subtitleBits = <String>[
      if (p.dateOfBirth != null && p.dateOfBirth!.isNotEmpty) p.dateOfBirth!,
      if (p.biologicalSex != null && p.biologicalSex!.isNotEmpty)
        p.biologicalSex!,
      if (p.bloodType != null && p.bloodType!.isNotEmpty) p.bloodType!,
    ];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
          style: TextStyle(color: colors.onSurface),
        ),
        subtitle: subtitleBits.isEmpty
            ? null
            : Text(
                subtitleBits.join('  •  '),
                style: TextStyle(color: colors.onSurfaceVariant),
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
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            if (onArchive != null)
              const PopupMenuItem(value: 'archive', child: Text('Archive')),
            if (onUnarchive != null)
              const PopupMenuItem(
                  value: 'unarchive', child: Text('Unarchive')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
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
  final void Function(Profile) onEdit;
  final void Function(Profile) onDelete;
  final void Function(Profile) onUnarchive;

  const _ArchivedSection({
    required this.colors,
    required this.archived,
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
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: widget.colors.surface,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: widget.colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Archived (${widget.archived.length})',
                      style: TextStyle(
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

  const _EmptyState({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 64, color: colors.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'No profiles yet',
              style: TextStyle(
                color: colors.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the button below to create your first profile.',
              style: TextStyle(color: colors.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
