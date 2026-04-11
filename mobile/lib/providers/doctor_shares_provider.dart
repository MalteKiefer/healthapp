import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/doctor_share.dart';
import 'providers.dart';

/// Family provider that fetches the list of doctor shares for a profile.
///
/// Endpoint: `GET /api/v1/profiles/{profileId}/shares`
///
/// Response shape (see `HandleListShares` in
/// `api/internal/api/handlers/doctor_share.go`):
///
/// ```json
/// { "items": [ { "share_id": "...", "label": "...", ... } ] }
/// ```
final doctorSharesProvider =
    FutureProvider.family<List<DoctorShare>, String>((ref, profileId) async {
  final api = ref.read(apiClientProvider);
  final raw = await api.get<Map<String, dynamic>>(
    '/api/v1/profiles/$profileId/shares',
  );
  final items = (raw['items'] as List?) ?? const [];
  return items
      .whereType<Map<String, dynamic>>()
      .map((j) => DoctorShare.fromJson(j, profileId: profileId))
      .toList(growable: false);
});

/// Immutable state for the create/revoke flow.
class DoctorShareActionState {
  final bool busy;
  final Object? error;

  /// Non-null right after a successful create — the list endpoint does not
  /// return the share URL, so the UI caches it here to show / copy.
  final DoctorShare? lastCreated;

  const DoctorShareActionState({
    this.busy = false,
    this.error,
    this.lastCreated,
  });

  DoctorShareActionState copyWith({
    bool? busy,
    Object? error,
    DoctorShare? lastCreated,
    bool clearError = false,
    bool clearLastCreated = false,
  }) {
    return DoctorShareActionState(
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
      lastCreated:
          clearLastCreated ? null : (lastCreated ?? this.lastCreated),
    );
  }

  static const DoctorShareActionState idle = DoctorShareActionState();
}

/// StateNotifier that performs create + revoke on doctor shares.
///
/// Create: `POST /api/v1/profiles/{profileId}/share`
///   body: { "encrypted_data": "...", "expires_in_hours": 24, "label": "..." }
///   returns: { "share_id", "share_url", "expires_at" }
///
/// Revoke: `DELETE /api/v1/profiles/{profileId}/share/{shareId}`
///
/// Both mutations invalidate [doctorSharesProvider] for the affected profile
/// so the list is re-fetched.
///
/// NOTE: The backend stores an opaque end-to-end-encrypted `encrypted_data`
/// bundle — the temp key lives only in the URL fragment and never touches the
/// server. The mobile client does not yet implement the in-app record-set
/// selection / re-encryption flow (that belongs to a later sprint), so for
/// now this notifier sends an empty placeholder bundle. The server rejects
/// empty `encrypted_data`, so callers should treat create errors as expected
/// until the encryption step is wired up. The scaffolding below is what the
/// screen layer needs to drive the UI today.
class DoctorSharesNotifier extends StateNotifier<DoctorShareActionState> {
  DoctorSharesNotifier(this._ref) : super(DoctorShareActionState.idle);

  final Ref _ref;

  /// Creates a new share for [profileId]. [expiresInHours] is clamped
  /// server-side to the range [1, 168]. [encryptedData] is the opaque
  /// ciphertext bundle produced by the client's encryption layer.
  Future<DoctorShare?> create({
    required String profileId,
    required String label,
    required int expiresInHours,
    required String encryptedData,
  }) async {
    state = state.copyWith(busy: true, clearError: true, clearLastCreated: true);
    try {
      final api = _ref.read(apiClientProvider);
      final raw = await api.post<Map<String, dynamic>>(
        '/api/v1/profiles/$profileId/share',
        body: {
          'encrypted_data': encryptedData,
          'expires_in_hours': expiresInHours,
          'label': label,
        },
      );
      final expiresRaw = raw['expires_at'] as String?;
      final created = DoctorShare(
        id: (raw['share_id'] as String?) ?? '',
        profileId: profileId,
        label: label,
        shareUrl: raw['share_url'] as String?,
        createdAt: DateTime.now(),
        expiresAt: expiresRaw != null
            ? DateTime.parse(expiresRaw).toLocal()
            : DateTime.now().add(Duration(hours: expiresInHours)),
        revokedAt: null,
        active: true,
      );
      state = DoctorShareActionState(lastCreated: created);
      _ref.invalidate(doctorSharesProvider(profileId));
      return created;
    } catch (e) {
      state = DoctorShareActionState(error: e);
      return null;
    }
  }

  /// Revokes an existing share. Invalidates the list on success.
  Future<bool> revoke({
    required String profileId,
    required String shareId,
  }) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final api = _ref.read(apiClientProvider);
      await api.delete('/api/v1/profiles/$profileId/share/$shareId');
      state = state.copyWith(busy: false);
      _ref.invalidate(doctorSharesProvider(profileId));
      return true;
    } catch (e) {
      state = DoctorShareActionState(error: e);
      return false;
    }
  }

  void reset() {
    state = DoctorShareActionState.idle;
  }
}

final doctorSharesControllerProvider =
    StateNotifierProvider<DoctorSharesNotifier, DoctorShareActionState>(
  (ref) => DoctorSharesNotifier(ref),
);
