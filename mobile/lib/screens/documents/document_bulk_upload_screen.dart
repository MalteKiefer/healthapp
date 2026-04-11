import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_error_messages.dart';
import '../../providers/document_bulk_provider.dart';

/// Sprint 3 — bulk document upload screen.
///
/// Lets the user pick multiple files via `file_picker` and uploads them
/// serially through the existing single-file `ApiClient.uploadFile`
/// helper. A per-file progress list is rendered live; the user can tap
/// "Done" to return to the documents list once the batch finishes.
class DocumentBulkUploadScreen extends ConsumerStatefulWidget {
  final String profileId;
  const DocumentBulkUploadScreen({super.key, required this.profileId});

  @override
  ConsumerState<DocumentBulkUploadScreen> createState() =>
      _DocumentBulkUploadScreenState();
}

class _DocumentBulkUploadScreenState
    extends ConsumerState<DocumentBulkUploadScreen> {
  @override
  void initState() {
    super.initState();
    // Reset any leftover state from a previous batch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(documentBulkUploadProvider.notifier).reset();
    });
  }

  Future<void> _pickAndUpload() async {
    final notifier = ref.read(documentBulkUploadProvider.notifier);
    notifier.reset();

    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;

    final files = <File>[
      for (final f in result.files)
        if (f.path != null) File(f.path!),
    ];
    if (files.isEmpty) return;

    await notifier.bulkUpload(widget.profileId, files);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final state = ref.watch(documentBulkUploadProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bulk upload'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.items.isEmpty && !state.inProgress)
              _EmptyPickPrompt(onPick: _pickAndUpload)
            else
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _BatchSummary(state: state),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.separated(
                        itemCount: state.items.length,
                        separatorBuilder: (_, _) => Divider(
                          color: cs.outlineVariant,
                          height: 1,
                        ),
                        itemBuilder: (context, i) {
                          final item = state.items[i];
                          return _BulkRow(item: item);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            if (state.finished)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickAndUpload,
                      icon: const Icon(Icons.add),
                      label: const Text('Upload more'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/documents/${widget.profileId}');
                        }
                      },
                      icon: const Icon(Icons.check),
                      label: const Text('Done'),
                    ),
                  ),
                ],
              )
            else if (state.inProgress)
              Center(
                child: Text(
                  'Uploading ${state.successCount + state.failedCount} '
                  'of ${state.totalCount}...',
                  style:
                      text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPickPrompt extends StatelessWidget {
  const _EmptyPickPrompt({required this.onPick});
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_upload_outlined,
              size: 64,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Select multiple files to upload at once.',
              style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.file_upload),
              label: const Text('Pick files'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BatchSummary extends StatelessWidget {
  const _BatchSummary({required this.state});
  final BulkUploadState state;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final total = state.totalCount;
    final done = state.successCount + state.failedCount;
    final progress = total == 0 ? 0.0 : done / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$done / $total complete',
              style: text.titleSmall?.copyWith(color: cs.onSurface),
            ),
            if (state.failedCount > 0)
              Text(
                '${state.failedCount} failed',
                style: text.labelMedium?.copyWith(color: cs.error),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: state.inProgress && progress == 0 ? null : progress,
            minHeight: 6,
            backgroundColor: cs.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
          ),
        ),
      ],
    );
  }
}

class _BulkRow extends StatelessWidget {
  const _BulkRow({required this.item});
  final BulkUploadItem item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    Widget trailing;
    switch (item.status) {
      case BulkUploadStatus.pending:
        trailing = Icon(
          Icons.schedule,
          color: cs.onSurfaceVariant,
        );
        break;
      case BulkUploadStatus.uploading:
        trailing = SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: cs.primary,
          ),
        );
        break;
      case BulkUploadStatus.success:
        trailing = Icon(
          Icons.check_circle,
          color: cs.primary,
        );
        break;
      case BulkUploadStatus.failed:
        trailing = Icon(
          Icons.error_outline,
          color: cs.error,
        );
        break;
    }

    final subtitle = item.status == BulkUploadStatus.failed && item.error != null
        ? Text(
            apiErrorMessage(item.error!),
            style: text.bodySmall?.copyWith(color: cs.error),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          )
        : Text(
            _statusLabel(item.status),
            style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          );

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.insert_drive_file_outlined,
        color: cs.onSurfaceVariant,
      ),
      title: Text(
        item.fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: text.bodyMedium,
      ),
      subtitle: subtitle,
      trailing: trailing,
    );
  }

  String _statusLabel(BulkUploadStatus s) {
    switch (s) {
      case BulkUploadStatus.pending:
        return 'Waiting';
      case BulkUploadStatus.uploading:
        return 'Uploading...';
      case BulkUploadStatus.success:
        return 'Uploaded';
      case BulkUploadStatus.failed:
        return 'Failed';
    }
  }
}
