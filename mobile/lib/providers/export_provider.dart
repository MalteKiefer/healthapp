import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/api/api_client.dart';
import '../core/api/api_error_messages.dart';
import '../models/export_schedule.dart';
import 'providers.dart';

/// Immutable state for one-shot export / import operations.
class ExportState {
  final bool busy;
  final String? activeFormat;
  final String? error;
  final String? lastFilename;

  const ExportState({
    this.busy = false,
    this.activeFormat,
    this.error,
    this.lastFilename,
  });

  ExportState copyWith({
    bool? busy,
    String? activeFormat,
    String? error,
    String? lastFilename,
    bool clearError = false,
    bool clearActive = false,
    bool clearFilename = false,
  }) {
    return ExportState(
      busy: busy ?? this.busy,
      activeFormat: clearActive ? null : (activeFormat ?? this.activeFormat),
      error: clearError ? null : (error ?? this.error),
      lastFilename:
          clearFilename ? null : (lastFilename ?? this.lastFilename),
    );
  }

  static const ExportState idle = ExportState();
}

/// Controller responsible for downloading and importing health-data export
/// payloads. Each export request streams the response into memory as bytes,
/// writes a temporary file via `path_provider`, and then triggers the system
/// share sheet via `share_plus`.
class ExportController extends StateNotifier<ExportState> {
  ExportController(this._api) : super(ExportState.idle);

  final ApiClient _api;

  /// GET /api/v1/profiles/{profileId}/export/fhir
  Future<bool> exportFhir(String profileId) =>
      _downloadAndShare(
        profileId: profileId,
        format: ExportFormats.fhir,
        path: '/api/v1/profiles/$profileId/export/fhir',
      );

  /// GET /api/v1/profiles/{profileId}/export/pdf
  Future<bool> exportPdf(String profileId) =>
      _downloadAndShare(
        profileId: profileId,
        format: ExportFormats.pdf,
        path: '/api/v1/profiles/$profileId/export/pdf',
      );

  /// GET /api/v1/profiles/{profileId}/export/ics
  Future<bool> exportIcs(String profileId) =>
      _downloadAndShare(
        profileId: profileId,
        format: ExportFormats.ics,
        path: '/api/v1/profiles/$profileId/export/ics',
      );

  /// POST /api/v1/profiles/{profileId}/import/fhir
  ///
  /// Uploads a FHIR JSON bundle as raw request bytes. The caller supplies
  /// the bytes (typically from `file_picker`).
  Future<bool> importFhir(String profileId, Uint8List bytes) async {
    state = state.copyWith(
      busy: true,
      activeFormat: 'import-fhir',
      clearError: true,
      clearFilename: true,
    );
    try {
      // Send the bundle as a JSON body. ApiClient.post forwards `data` to
      // dio which will treat the Uint8List as a raw body when the content
      // type is application/fhir+json.
      await _api.post<dynamic>(
        '/api/v1/profiles/$profileId/import/fhir',
        body: bytes,
      );
      state = ExportState.idle;
      return true;
    } catch (e) {
      state = ExportState(error: apiErrorMessage(e));
      return false;
    }
  }

  Future<bool> _downloadAndShare({
    required String profileId,
    required String format,
    required String path,
  }) async {
    state = state.copyWith(
      busy: true,
      activeFormat: format,
      clearError: true,
      clearFilename: true,
    );
    try {
      final bytes = await _api.getBytes(path);
      final filename =
          'healthvault-$profileId-$format.${ExportFormats.extension(format)}';
      final file = await _writeTempFile(filename, bytes);
      await Share.shareXFiles(
        [
          XFile(
            file.path,
            mimeType: ExportFormats.mimeType(format),
            name: filename,
          ),
        ],
        subject: ExportFormats.label(format),
      );
      state = ExportState(lastFilename: filename);
      return true;
    } catch (e) {
      state = ExportState(error: apiErrorMessage(e));
      return false;
    }
  }

  Future<File> _writeTempFile(String filename, Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  void reset() {
    state = ExportState.idle;
  }
}

/// State-notifier provider exposing [ExportController].
final exportControllerProvider =
    StateNotifierProvider<ExportController, ExportState>((ref) {
  return ExportController(ref.read(apiClientProvider));
});
