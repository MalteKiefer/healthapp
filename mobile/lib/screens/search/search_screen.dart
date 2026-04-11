import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/translations.dart';
import '../../core/theme/spacing.dart';
import '../../models/search_result.dart';
import '../../providers/providers.dart';
import '../../providers/search_provider.dart';
import '../../widgets/skeletons.dart';

/// Returns the translation for [key], falling back to [fallback] when the
/// key is missing (i.e. [T.tr] echoes the key back).
String _trOr(String key, String fallback) {
  final v = T.tr(key);
  return v == key ? fallback : v;
}

/// Global search screen (Sprint 4 client-side rewrite).
///
/// Top-level screen that lets the user search across every health domain
/// (medications, labs, vitals, appointments, tasks, diary, contacts,
/// diagnoses, allergies, symptoms, vaccinations, documents). The legacy
/// `GET /api/v1/search` endpoint was retired (410 Gone), so [searchProvider]
/// now fetches each domain list for the currently selected profile and
/// filters them in memory. Keystrokes are still debounced by 400ms.
///
/// Tapping a row routes the user to the relevant profile-scoped route.
/// If the result itself carries no `profile_id`, we fall back to the
/// currently selected profile. If no profile is selected either, the tap
/// is a no-op and a SnackBar explains the situation.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    ref.read(searchProvider.notifier).query(value);
  }

  /// Navigate to the domain-specific profile-scoped route.
  /// Returns `true` on success, `false` if no profileId could be resolved.
  bool _navigateTo(BuildContext context, SearchResult result) {
    // Prefer the profile the result itself is attached to.
    final profileId =
        result.profileId ?? ref.read(selectedProfileProvider)?.id;
    if (profileId == null || profileId.isEmpty) return false;

    // Vitals / home don't take a profileId segment in exactly the same way
    // as the others (see app_router.dart), but every domain we expose as a
    // search type currently uses `/<domain>/<profileId>`.
    final route = '${result.type.routeBase}/$profileId';
    context.go(route);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final async = ref.watch(searchProvider);

    final query = _controller.text;
    final isLoading = async.isLoading || async.isRefreshing;

    return Scaffold(
      appBar: AppBar(
        title: Text(_trOr('search.title', 'Search')),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.search,
              // Explicitly disable browser/OS autofill: this is a free-form
              // search field, never an email/username/password. Setting this
              // to null prevents the platform from polluting the field with
              // saved-credential suggestions.
              autofillHints: null,
              autofocus: false,
              decoration: InputDecoration(
                hintText: _trOr(
                  'search.hint',
                  'Search medications, labs, diagnoses...',
                ),
                prefixIcon: Icon(Icons.search, color: cs.onSurfaceVariant),
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Clear',
                        onPressed: () {
                          _controller.clear();
                          ref.read(searchProvider.notifier).clear();
                          setState(() {});
                        },
                      )
                    : null,
                filled: true,
                fillColor: cs.surfaceContainerHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.lg),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm + 2,
                ),
              ),
              onChanged: (value) {
                _onChanged(value);
                setState(() {});
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: isLoading && query.trim().isNotEmpty
                  ? const SkeletonList(count: 5)
                  : async.when(
                      data: (results) => _ResultsList(
                        results: results,
                        query: query,
                        onTap: (r) {
                          final ok = _navigateTo(context, r);
                          if (!ok) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Select a profile first to open this result.',
                                ),
                              ),
                            );
                          }
                        },
                      ),
                      loading: () => const SkeletonList(count: 5),
                      error: (err, _) => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Text(
                            'Search failed: $err',
                            style: TextStyle(color: cs.error),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.sm,
                bottom: AppSpacing.xs,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 14,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.xs + 2),
                  Flexible(
                    child: Text(
                      _trOr(
                        'search.local_hint',
                        'Search happens locally on your device',
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultsList extends StatelessWidget {
  const _ResultsList({
    required this.results,
    required this.query,
    required this.onTap,
  });

  final List<SearchResult> results;
  final String query;
  final ValueChanged<SearchResult> onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (query.trim().isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            _trOr(
              'search.empty_state',
              'Start typing to search across all your health data.',
            ),
            style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (results.isEmpty) {
      final base = _trOr('search.no_results', 'No results');
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            '$base "$query"',
            style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // Group by type, preserving enum declaration order for a stable UI.
    final grouped = <SearchResultType, List<SearchResult>>{};
    for (final r in results) {
      grouped.putIfAbsent(r.type, () => []).add(r);
    }
    final orderedTypes = SearchResultType.values
        .where((t) => grouped.containsKey(t))
        .toList();

    // Flatten into (header, items...) entries for a single ListView.
    final entries = <Object>[];
    for (final t in orderedTypes) {
      entries.add(t); // header sentinel
      entries.addAll(grouped[t]!);
    }

    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox.shrink(),
      itemBuilder: (context, i) {
        final item = entries[i];
        if (item is SearchResultType) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs,
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.sm,
            ),
            child: Text(
              item.label,
              style: text.labelLarge?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }
        final r = item as SearchResult;
        return Card(
          elevation: 0,
          color: cs.surfaceContainerLow,
          margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: cs.primaryContainer,
              child: Icon(
                _iconFor(r.type),
                color: cs.onPrimaryContainer,
                size: 20,
              ),
            ),
            title: Text(
              r.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: (r.subtitle != null || r.matchedSnippet != null)
                ? Text(
                    r.matchedSnippet ?? r.subtitle ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  )
                : null,
            trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            onTap: () => onTap(r),
          ),
        );
      },
    );
  }

  IconData _iconFor(SearchResultType t) {
    switch (t) {
      case SearchResultType.medication:
        return Icons.medication_outlined;
      case SearchResultType.lab:
        return Icons.science_outlined;
      case SearchResultType.vital:
        return Icons.monitor_heart_outlined;
      case SearchResultType.appointment:
        return Icons.event_outlined;
      case SearchResultType.task:
        return Icons.check_circle_outline;
      case SearchResultType.diary:
        return Icons.book_outlined;
      case SearchResultType.contact:
        return Icons.person_outline;
      case SearchResultType.diagnosis:
        return Icons.assignment_outlined;
      case SearchResultType.allergy:
        return Icons.warning_amber_outlined;
      case SearchResultType.symptom:
        return Icons.sick_outlined;
      case SearchResultType.vaccination:
        return Icons.vaccines_outlined;
      case SearchResultType.document:
        return Icons.description_outlined;
      case SearchResultType.unknown:
        return Icons.help_outline;
    }
  }
}
