import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/i18n/translations.dart';
import '../../models/common.dart';
import '../../providers/providers.dart';

// -- Provider -----------------------------------------------------------------

final _documentsProvider =
    FutureProvider.family<List<Document>, String>((ref, profileId) async {
  final api = ref.read(apiClientProvider);
  final data = await api
      .get<Map<String, dynamic>>('/api/v1/profiles/$profileId/documents');
  return (data['items'] as List)
      .map((e) => Document.fromJson(e as Map<String, dynamic>))
      .toList();
});

// -- Category translation -----------------------------------------------------

String _categoryLabel(String? cat) {
  if (cat == null) return T.tr('doc.other');
  final key = 'doc.$cat';
  final translated = T.tr(key);
  return translated == key ? cat : translated;
}

// -- Screen -------------------------------------------------------------------

class DocumentsScreen extends ConsumerStatefulWidget {
  final String profileId;
  const DocumentsScreen({super.key, required this.profileId});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  String? _selectedCategory;

  Future<void> _delete(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(T.tr('documents.delete')),
        content: Text(T.tr('documents.delete_body')),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(T.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(T.tr('common.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(apiClientProvider)
          .delete('/api/v1/profiles/${widget.profileId}/documents/$id');
      ref.invalidate(_documentsProvider(widget.profileId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _showEditSheet(Document doc) async {
    const categories = [
      'lab_result',
      'imaging',
      'prescription',
      'referral',
      'vaccination_record',
      'discharge_summary',
      'report',
      'legal',
      'other',
    ];

    final filenameCtrl = TextEditingController(text: doc.filename);
    String? selectedCategory = doc.category;
    final formKey = GlobalKey<FormState>();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Form(
          key: formKey,
          child: StatefulBuilder(
            builder: (ctx, setSheetState) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                Text(
                  T.tr('documents.edit'),
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: filenameCtrl,
                  decoration: InputDecoration(
                    labelText: T.tr('documents.field_filename'),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty)
                          ? T.tr('common.required')
                          : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: categories.contains(selectedCategory)
                      ? selectedCategory
                      : null,
                  decoration: InputDecoration(
                    labelText: T.tr('documents.field_category'),
                  ),
                  items: categories
                      .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text(_categoryLabel(c)),
                          ))
                      .toList(),
                  onChanged: (v) => setSheetState(() => selectedCategory = v),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    Navigator.pop(ctx);
                    final body = <String, dynamic>{
                      'filename_enc': filenameCtrl.text.trim(),
                      if (selectedCategory != null)
                        'category': selectedCategory,
                    };
                    try {
                      await ref.read(apiClientProvider).patch<void>(
                            '/api/v1/profiles/${widget.profileId}/documents/${doc.id}',
                            body: body,
                          );
                      ref.invalidate(_documentsProvider(widget.profileId));
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('$e')));
                      }
                    }
                  },
                  child: Text(T.tr('common.save')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    filenameCtrl.dispose();
  }

  Future<void> _openDocument(Document doc) async {
    final mimeType = doc.mimeType ?? '';

    if (mimeType.startsWith('image/')) {
      await _showImageViewer(doc);
    } else if (mimeType.contains('pdf')) {
      await _downloadPdf(doc);
    } else {
      _showFileInfo(doc);
    }
  }

  Future<void> _shareDocument(Document doc) async {
    try {
      final bytes = await ref.read(apiClientProvider).getBytes(
            '/api/v1/profiles/${widget.profileId}/documents/${doc.id}/download',
          );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${doc.filename}');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: doc.filename);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _showImageViewer(Document doc) async {
    Uint8List? bytes;
    try {
      bytes = await ref.read(apiClientProvider).getBytes(
            '/api/v1/profiles/${widget.profileId}/documents/${doc.id}/download',
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler beim Laden: $e')));
      }
      return;
    }
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text(doc.filename),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(ctx),
            ),
          ),
          body: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Center(
              child: Image.memory(bytes!, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _downloadPdf(Document doc) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PDF wird heruntergeladen...')),
    );
    try {
      await ref.read(apiClientProvider).getBytes(
            '/api/v1/profiles/${widget.profileId}/documents/${doc.id}/download',
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${doc.filename} heruntergeladen')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler beim Laden: $e')));
      }
    }
  }

  void _showFileInfo(Document doc) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(doc.filename),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (doc.category != null)
              Text('Kategorie: ${_categoryLabel(doc.category)}'),
            if (doc.mimeType != null) Text('Typ: ${doc.mimeType}'),
            if (doc.fileSize != null)
              Text('Größe: ${_formatFileSize(doc.fileSize)}'),
            if (doc.uploadedAt != null) Text('Hochgeladen: ${doc.uploadedAt}'),
            if (doc.notes != null) ...[
              const SizedBox(height: 8),
              Text('Notizen: ${doc.notes}'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(T.tr('common.cancel')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final asyncVal = ref.watch(_documentsProvider(widget.profileId));

    return Scaffold(
      appBar: AppBar(
        title: Text(T.tr('documents.title')),
        automaticallyImplyLeading: false,
      ),
      body: asyncVal.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline, size: 48, color: cs.error),
            const SizedBox(height: 12),
            Text(T.tr('documents.failed'), style: tt.bodyLarge),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () =>
                  ref.invalidate(_documentsProvider(widget.profileId)),
              child: Text(T.tr('common.retry')),
            ),
          ]),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.folder_outlined, size: 48, color: cs.outline),
                const SizedBox(height: 12),
                Text(T.tr('documents.no_data'),
                    style:
                        tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            );
          }

          // Collect categories for filter chips
          final categories = items
              .map((d) => d.category)
              .where((c) => c != null && c.isNotEmpty)
              .toSet()
              .toList()
            ..sort();

          final filtered = _selectedCategory == null
              ? items
              : items
                  .where((d) => d.category == _selectedCategory)
                  .toList();

          return Column(
            children: [
              if (categories.isNotEmpty)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(T.tr('common.all')),
                          selected: _selectedCategory == null,
                          onSelected: (_) =>
                              setState(() => _selectedCategory = null),
                        ),
                      ),
                      ...categories.map((c) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(_categoryLabel(c)),
                              selected: _selectedCategory == c,
                              onSelected: (_) =>
                                  setState(() => _selectedCategory = c),
                            ),
                          )),
                    ],
                  ),
                ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          T.tr('documents.no_category'),
                          style: tt.bodyLarge
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (_, i) => _DocumentCard(
                          document: filtered[i],
                          onDelete: () => _delete(filtered[i].id),
                          onTap: () => _showEditSheet(filtered[i]),
                          onOpen: () => _openDocument(filtered[i]),
                          onShare: () => _shareDocument(filtered[i]),
                          formatSize: _formatFileSize,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// -- Card ---------------------------------------------------------------------

class _DocumentCard extends StatelessWidget {
  final Document document;
  final VoidCallback onDelete;
  final VoidCallback onTap;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final String Function(int?) formatSize;
  const _DocumentCard({
    required this.document,
    required this.onDelete,
    required this.onTap,
    required this.onOpen,
    required this.onShare,
    required this.formatSize,
  });

  IconData _fileIcon(String? mimeType, String filename) {
    if (mimeType != null) {
      if (mimeType.startsWith('image/')) return Icons.image;
      if (mimeType.contains('pdf')) return Icons.picture_as_pdf;
      if (mimeType.contains('word') || mimeType.contains('document'))
        return Icons.description;
      if (mimeType.contains('spreadsheet') || mimeType.contains('excel'))
        return Icons.table_chart;
    }
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return Icons.image;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      default:
        return Icons.insert_drive_file;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    String? dateStr;
    if (document.uploadedAt != null) {
      try {
        final d = DateTime.parse(document.uploadedAt!);
        dateStr = DateFormat('MMM d, yyyy').format(d);
      } catch (_) {
        dateStr = document.uploadedAt;
      }
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onDelete,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _fileIcon(document.mimeType, document.filename),
                  size: 20,
                  color: cs.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            document.filename,
                            style: tt.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (document.category != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: cs.tertiaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _categoryLabel(document.category),
                              style: tt.labelSmall?.copyWith(
                                  color: cs.onTertiaryContainer,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (dateStr != null) dateStr,
                        if (document.fileSize != null)
                          formatSize(document.fileSize),
                      ].join(' \u00b7 '),
                      style:
                          tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.open_in_new, size: 18),
                tooltip: T.tr('common.open'),
                onPressed: onOpen,
              ),
              IconButton(
                icon: const Icon(Icons.share, size: 18),
                tooltip: T.tr('common.share'),
                onPressed: onShare,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
