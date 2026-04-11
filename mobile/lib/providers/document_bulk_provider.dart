import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Returns the trailing path segment of [path], handling both POSIX and
/// Windows separators. Inlined to avoid taking a dependency on the
/// `path` package from this provider.
String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final idx = normalized.lastIndexOf('/');
  return idx == -1 ? normalized : normalized.substring(idx + 1);
}

/// Status of a single file in a bulk upload batch.
enum BulkUploadStatus { pending, uploading, success, failed }

/// Per-file progress entry within a bulk upload batch.
class BulkUploadItem {
  final String filePath;
  final String fileName;
  final BulkUploadStatus status;
  final Object? error;

  const BulkUploadItem({
    required this.filePath,
    required this.fileName,
    this.status = BulkUploadStatus.pending,
    this.error,
  });

  BulkUploadItem copyWith({
    BulkUploadStatus? status,
    Object? error,
    bool clearError = false,
  }) {
    return BulkUploadItem(
      filePath: filePath,
      fileName: fileName,
      status: status ?? this.status,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Aggregate state for a bulk upload session.
class BulkUploadState {
  final List<BulkUploadItem> items;
  final bool inProgress;
  final bool finished;

  const BulkUploadState({
    this.items = const <BulkUploadItem>[],
    this.inProgress = false,
    this.finished = false,
  });

  int get successCount =>
      items.where((i) => i.status == BulkUploadStatus.success).length;
  int get failedCount =>
      items.where((i) => i.status == BulkUploadStatus.failed).length;
  int get totalCount => items.length;

  BulkUploadState copyWith({
    List<BulkUploadItem>? items,
    bool? inProgress,
    bool? finished,
  }) {
    return BulkUploadState(
      items: items ?? this.items,
      inProgress: inProgress ?? this.inProgress,
      finished: finished ?? this.finished,
    );
  }

  static const BulkUploadState idle = BulkUploadState();
}

/// StateNotifier driving the bulk-upload flow.
///
/// Endpoint (logical): `POST /api/v1/profiles/{profileId}/documents/bulk`
///
/// The shared [ApiClient] only exposes a single-file `uploadFile<T>` helper.
/// To keep this Sprint 3 feature self-contained — and avoid touching
/// `api_client.dart` — we issue uploads serially via the existing helper.
/// Each file becomes one `POST /api/v1/profiles/{profileId}/documents`
/// call. State is emitted after every transition (pending -> uploading ->
/// success/failed) so the UI can render a per-file progress list.
class DocumentBulkUploadNotifier extends StateNotifier<BulkUploadState> {
  DocumentBulkUploadNotifier(this._ref) : super(BulkUploadState.idle);

  final Ref _ref;

  /// Starts a bulk upload of [files] for [profileId]. Resolves once every
  /// file has either succeeded or failed. Individual failures do not abort
  /// the batch; the user can inspect per-file errors via [BulkUploadState].
  Future<void> bulkUpload(String profileId, List<File> files) async {
    if (files.isEmpty) {
      state = const BulkUploadState(finished: true);
      return;
    }

    final initial = files
        .map((f) => BulkUploadItem(
              filePath: f.path,
              fileName: _basename(f.path),
            ))
        .toList(growable: false);

    state = BulkUploadState(
      items: initial,
      inProgress: true,
      finished: false,
    );

    final api = _ref.read(apiClientProvider);

    for (var i = 0; i < files.length; i++) {
      _updateItem(i, (it) => it.copyWith(status: BulkUploadStatus.uploading));

      try {
        await api.uploadFile<dynamic>(
          '/api/v1/profiles/$profileId/documents',
          files[i].path,
          _basename(files[i].path),
        );
        _updateItem(
          i,
          (it) => it.copyWith(
            status: BulkUploadStatus.success,
            clearError: true,
          ),
        );
      } catch (e) {
        _updateItem(
          i,
          (it) => it.copyWith(
            status: BulkUploadStatus.failed,
            error: e,
          ),
        );
      }
    }

    state = state.copyWith(inProgress: false, finished: true);
  }

  /// Reset the controller to its idle state. Safe to call after a batch
  /// completes if the user wants to start another upload.
  void reset() {
    state = BulkUploadState.idle;
  }

  void _updateItem(int index, BulkUploadItem Function(BulkUploadItem) f) {
    final next = [...state.items];
    next[index] = f(next[index]);
    state = state.copyWith(items: next);
  }
}

final documentBulkUploadProvider = StateNotifierProvider<
    DocumentBulkUploadNotifier, BulkUploadState>(
  (ref) => DocumentBulkUploadNotifier(ref),
);
