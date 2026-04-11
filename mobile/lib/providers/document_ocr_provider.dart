import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Lifecycle of an OCR-index mutation (trigger or remove).
enum OcrIndexPhase { idle, running, success, failed }

/// Immutable state for the OCR-index controller. Tracks the most recent
/// mutation so the UI can render a spinner / success / error indicator
/// next to the affected document row.
class OcrIndexState {
  final OcrIndexPhase phase;
  final String? docId;
  final Object? error;

  const OcrIndexState({
    this.phase = OcrIndexPhase.idle,
    this.docId,
    this.error,
  });

  bool get isRunning => phase == OcrIndexPhase.running;

  static const OcrIndexState idle = OcrIndexState();
}

/// StateNotifier driving the OCR-index trigger / remove flow for a single
/// document at a time.
///
/// Endpoints:
///   * `POST   /api/v1/profiles/{profileId}/documents/{docId}/ocr-index`
///   * `DELETE /api/v1/profiles/{profileId}/documents/{docId}/ocr-index`
class DocumentOcrNotifier extends StateNotifier<OcrIndexState> {
  DocumentOcrNotifier(this._ref) : super(OcrIndexState.idle);

  final Ref _ref;

  /// Schedules an OCR pass for [docId]. Resolves with `true` on success.
  Future<bool> triggerOcrIndex(String profileId, String docId) async {
    state = OcrIndexState(phase: OcrIndexPhase.running, docId: docId);
    try {
      final api = _ref.read(apiClientProvider);
      await api.post<dynamic>(
        '/api/v1/profiles/$profileId/documents/$docId/ocr-index',
      );
      state = OcrIndexState(phase: OcrIndexPhase.success, docId: docId);
      return true;
    } catch (e) {
      state = OcrIndexState(
        phase: OcrIndexPhase.failed,
        docId: docId,
        error: e,
      );
      return false;
    }
  }

  /// Removes the OCR index entry for [docId]. Resolves with `true` on
  /// success.
  Future<bool> removeOcrIndex(String profileId, String docId) async {
    state = OcrIndexState(phase: OcrIndexPhase.running, docId: docId);
    try {
      final api = _ref.read(apiClientProvider);
      await api.delete(
        '/api/v1/profiles/$profileId/documents/$docId/ocr-index',
      );
      state = OcrIndexState(phase: OcrIndexPhase.success, docId: docId);
      return true;
    } catch (e) {
      state = OcrIndexState(
        phase: OcrIndexPhase.failed,
        docId: docId,
        error: e,
      );
      return false;
    }
  }

  /// Reset the controller back to idle.
  void reset() {
    state = OcrIndexState.idle;
  }
}

final documentOcrProvider =
    StateNotifierProvider<DocumentOcrNotifier, OcrIndexState>(
  (ref) => DocumentOcrNotifier(ref),
);
