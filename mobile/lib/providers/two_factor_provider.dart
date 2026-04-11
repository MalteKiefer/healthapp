import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../models/two_factor.dart';
import 'providers.dart';

/// Fetches a fresh TOTP setup (secret + provisioning URI) from the
/// server. This is a [FutureProvider.autoDispose] so that every time
/// the setup screen is opened a new secret is generated — the server
/// overwrites any pending (un-enabled) secret on each call.
final twoFactorSetupProvider =
    FutureProvider.autoDispose<TwoFactorSetup>((ref) async {
  final api = ref.read(apiClientProvider);
  final data =
      await api.get<Map<String, dynamic>>('/api/v1/auth/2fa/setup');
  return TwoFactorSetup.fromJson(data);
});

/// State object for the enable / disable / regenerate flow.
class TwoFactorState {
  final bool loading;
  final String? error;

  /// Populated after a successful enable or regenerate call. Contains
  /// the plaintext recovery codes — shown to the user exactly once.
  final List<String> recoveryCodes;

  /// Set to true once enable succeeds or disable is confirmed.
  final bool success;

  const TwoFactorState({
    this.loading = false,
    this.error,
    this.recoveryCodes = const [],
    this.success = false,
  });

  TwoFactorState copyWith({
    bool? loading,
    String? error,
    List<String>? recoveryCodes,
    bool? success,
  }) =>
      TwoFactorState(
        loading: loading ?? this.loading,
        error: error,
        recoveryCodes: recoveryCodes ?? this.recoveryCodes,
        success: success ?? this.success,
      );
}

class TwoFactorController extends StateNotifier<TwoFactorState> {
  TwoFactorController(this._api) : super(const TwoFactorState());

  final ApiClient _api;

  /// POST /api/v1/auth/2fa/enable with the user's 6-digit TOTP code.
  ///
  /// On success the server returns the initial batch of recovery
  /// codes as `{codes: [...]}`. These are stored on [state] so the UI
  /// can render them to the user.
  Future<void> enable(String code) async {
    state = state.copyWith(loading: true, error: null, success: false);
    try {
      final data = await _api.post<Map<String, dynamic>>(
        '/api/v1/auth/2fa/enable',
        body: {'code': code},
      );
      final codes = (data['codes'] is List)
          ? (data['codes'] as List).map((e) => e.toString()).toList()
          : <String>[];
      state = state.copyWith(
        loading: false,
        recoveryCodes: codes,
        success: true,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  /// POST /api/v1/auth/2fa/disable.
  ///
  /// The backend requires both the current TOTP code AND the user's
  /// current auth hash (password-derived) as a guard against a
  /// session-hijack attacker turning 2FA off. The caller is
  /// responsible for passing [currentAuthHash] derived the same way
  /// as during login.
  Future<void> disable({
    required String code,
    required String currentAuthHash,
  }) async {
    state = state.copyWith(loading: true, error: null, success: false);
    try {
      await _api.post<Map<String, dynamic>>(
        '/api/v1/auth/2fa/disable',
        body: {
          'code': code,
          'current_auth_hash': currentAuthHash,
        },
      );
      state = state.copyWith(
        loading: false,
        success: true,
        recoveryCodes: const [],
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  /// POST /api/v1/auth/2fa/recovery-codes — regenerates the user's
  /// 10 recovery codes, invalidating any previous batch.
  Future<void> regenerateRecoveryCodes() async {
    state = state.copyWith(loading: true, error: null, success: false);
    try {
      final data = await _api.post<Map<String, dynamic>>(
        '/api/v1/auth/2fa/recovery-codes',
      );
      final codes = (data['codes'] is List)
          ? (data['codes'] as List).map((e) => e.toString()).toList()
          : <String>[];
      state = state.copyWith(
        loading: false,
        recoveryCodes: codes,
        success: true,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  /// POST /api/v1/auth/login/2fa — second-factor step of login.
  ///
  /// The server returns a `loginResponse` with cookies set on
  /// success. The caller (challenge screen) should then trigger
  /// `appLockControllerProvider.notifier.onLoginSuccess()`.
  Future<void> submitLoginChallenge({
    required String userId,
    required String code,
    required String challengeToken,
  }) async {
    state = state.copyWith(loading: true, error: null, success: false);
    try {
      await _api.post<Map<String, dynamic>>(
        '/api/v1/auth/login/2fa',
        body: {
          'user_id': userId,
          'code': code,
          'challenge_token': challengeToken,
        },
      );
      state = state.copyWith(loading: false, success: true);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  void reset() {
    state = const TwoFactorState();
  }
}

final twoFactorControllerProvider =
    StateNotifierProvider<TwoFactorController, TwoFactorState>((ref) {
  return TwoFactorController(ref.read(apiClientProvider));
});
