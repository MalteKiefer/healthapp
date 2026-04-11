import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../models/profile.dart';
import '../models/profile_write.dart';
import 'providers.dart';

/// Async state carried by [profileManagementProvider]. Tracks the last
/// mutation so the UI can show spinners, success toasts and error banners
/// without losing state on widget rebuilds.
class ProfileManagementState {
  final bool isLoading;
  final String? error;
  final Profile? lastMutated;

  const ProfileManagementState({
    this.isLoading = false,
    this.error,
    this.lastMutated,
  });

  ProfileManagementState copyWith({
    bool? isLoading,
    String? error,
    Profile? lastMutated,
    bool clearError = false,
    bool clearLastMutated = false,
  }) {
    return ProfileManagementState(
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      lastMutated:
          clearLastMutated ? null : (lastMutated ?? this.lastMutated),
    );
  }
}

/// Controller for write operations against `/api/v1/profiles`.
///
/// After every successful mutation the list provider is invalidated so
/// consumers re-fetch the freshest data from the server.
class ProfileManagementNotifier extends StateNotifier<ProfileManagementState> {
  ProfileManagementNotifier(this._ref) : super(const ProfileManagementState());

  final Ref _ref;

  ApiClient get _api => _ref.read(apiClientProvider);

  Future<Profile?> create(ProfileWriteRequest req) async {
    return _run(() async {
      final body = req.toJson();
      final raw = await _api.post<Map<String, dynamic>>(
        '/api/v1/profiles',
        body: body,
      );
      return Profile.fromJson(raw);
    });
  }

  Future<Profile?> update(String id, ProfileWriteRequest req) async {
    return _run(() async {
      final body = req.toJson()..remove('id');
      final raw = await _api.patch<Map<String, dynamic>>(
        '/api/v1/profiles/$id',
        body: body,
      );
      return Profile.fromJson(raw);
    });
  }

  Future<bool> delete(String id) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _api.delete('/api/v1/profiles/$id');
      _invalidateList();
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  Future<bool> archive(String id) async {
    return _runVoid(() async {
      await _api.post<dynamic>('/api/v1/profiles/$id/archive');
    });
  }

  Future<bool> unarchive(String id) async {
    return _runVoid(() async {
      await _api.post<dynamic>('/api/v1/profiles/$id/unarchive');
    });
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  Future<Profile?> _run(Future<Profile> Function() op) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final p = await op();
      _invalidateList();
      state = state.copyWith(isLoading: false, lastMutated: p);
      return p;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return null;
    }
  }

  Future<bool> _runVoid(Future<void> Function() op) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await op();
      _invalidateList();
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  void _invalidateList() {
    // profilesProvider is a FutureProvider.family keyed by a String; the
    // app convention (see home_screen.dart) is to use the empty string as
    // the key, so we invalidate that entry.
    _ref.invalidate(profilesProvider(''));
  }
}

final profileManagementProvider =
    StateNotifierProvider<ProfileManagementNotifier, ProfileManagementState>(
  (ref) => ProfileManagementNotifier(ref),
);

/// Raw list provider that also surfaces the `archived_at` field so the
/// list screen can split active vs archived profiles. The existing
/// [Profile] model does not carry `archived_at`, so we keep the raw map
/// alongside the parsed model.
class ProfileWithMeta {
  final Profile profile;
  final String? archivedAt;
  final Map<String, dynamic> raw;

  const ProfileWithMeta({
    required this.profile,
    required this.archivedAt,
    required this.raw,
  });

  bool get isArchived => archivedAt != null && archivedAt!.isNotEmpty;
}

final profilesWithMetaProvider =
    FutureProvider<List<ProfileWithMeta>>((ref) async {
  // Re-fetch when the plain profilesProvider is invalidated by forcing a
  // dependency on it.
  await ref.watch(profilesProvider('').future);
  final api = ref.read(apiClientProvider);
  final data = await api.get<Map<String, dynamic>>('/api/v1/profiles');
  final items = (data['items'] as List?) ?? const [];
  return items.map((item) {
    final map = item as Map<String, dynamic>;
    return ProfileWithMeta(
      profile: Profile.fromJson(map),
      archivedAt: map['archived_at'] as String?,
      raw: map,
    );
  }).toList();
});
