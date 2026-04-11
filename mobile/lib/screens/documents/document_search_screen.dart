import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_error_messages.dart';
import '../../core/i18n/translations.dart';
import '../../core/theme/spacing.dart';
import '../../models/common.dart';
import '../../providers/document_search_provider.dart';
import '../../widgets/skeletons.dart';

String _trOr(String key, String fallback) {
  final v = T.tr(key);
  return v == key ? fallback : v;
}

/// Sprint 3 — OCR-indexed document search screen.
///
/// Renders a Material 3 [SearchBar] that delegates each keystroke to
/// [DocumentSearchNotifier], which debounces by 400ms and calls
/// `GET /api/v1/profiles/{profileId}/documents/search?q=...`.
///
/// Tapping a result navigates back to the existing
/// `/documents/:profileId` route via go_router.
class DocumentSearchScreen extends ConsumerStatefulWidget {
  final String profileId;
  const DocumentSearchScreen({super.key, required this.profileId});

  @override
  ConsumerState<DocumentSearchScreen> createState() =>
      _DocumentSearchScreenState();
}

class _DocumentSearchScreenState extends ConsumerState<DocumentSearchScreen> {
  final SearchController _controller = SearchController();

  @override
  void initState() {
    super.initState();
    // Clear any leftover state from a previous visit.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(documentSearchProvider.notifier).clear();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    ref
        .read(documentSearchProvider.notifier)
        .search(widget.profileId, value);
  }

  void _openDocument(BuildContext context, Document doc) {
    // The existing documents list is the canonical "open document" view.
    // We navigate back to it (with the matched profileId) so the user can
    // tap through to preview/share. Replacing here keeps the back stack
    // shallow when arriving from the documents screen itself.
    context.go('/documents/${widget.profileId}');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final async = ref.watch(documentSearchProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_trOr('docs.search', 'Search documents')),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SearchBar(
              controller: _controller,
              hintText: _trOr(
                'docs.search.hint',
                'Search by content, filename, tag...',
              ),
              leading: Icon(Icons.search, color: cs.onSurfaceVariant),
              trailing: [
                if (_controller.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: _trOr('common.clear', 'Clear'),
                    onPressed: () {
                      _controller.clear();
                      ref.read(documentSearchProvider.notifier).clear();
                      setState(() {});
                    },
                  ),
              ],
              onChanged: (value) {
                _onChanged(value);
                setState(() {});
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: async.when(
                data: (results) => _ResultsList(
                  results: results,
                  query: _controller.text,
                  onTap: (doc) => _openDocument(context, doc),
                ),
                loading: () => const SkeletonList(count: 4),
                error: (err, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Text(
                      apiErrorMessage(err),
                      style: TextStyle(color: cs.error),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
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

  final List<Document> results;
  final String query;
  final ValueChanged<Document> onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (query.trim().isEmpty) {
      return Center(
        child: Text(
          _trOr(
            'docs.search.prompt',
            'Type to search OCR-indexed documents.',
          ),
          style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      );
    }

    if (results.isEmpty) {
      final template = _trOr(
        'docs.search.no_results',
        'No documents match "{query}"',
      );
      return Center(
        child: Text(
          template.replaceAll('{query}', query),
          style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, _) => Divider(
        color: cs.outlineVariant,
        height: 1,
      ),
      itemBuilder: (context, i) {
        final doc = results[i];
        final subtitleParts = <String>[
          if (doc.category != null && doc.category!.isNotEmpty) doc.category!,
          if (doc.uploadedAt != null && doc.uploadedAt!.isNotEmpty)
            doc.uploadedAt!,
        ];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.description_outlined,
            color: cs.primary,
          ),
          title: Text(
            doc.filename,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodyLarge,
          ),
          subtitle: subtitleParts.isEmpty
              ? null
              : Text(
                  subtitleParts.join(' \u00b7 '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
          trailing: Icon(
            Icons.chevron_right,
            color: cs.onSurfaceVariant,
          ),
          onTap: () => onTap(doc),
        );
      },
    );
  }
}
