import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api/api_client.dart';
import '../core/auth/auth_service.dart';
import '../models/profile.dart';

// Re-export the app-lock controller provider so callers can import it from
// a single `providers.dart` entry point.
export '../core/security/app_lock/app_lock_controller.dart'
    show appLockControllerProvider;

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

/// Provides the app-wide [AuthService] bound to the encrypted vault.
///
/// Must be overridden in `main.dart` with a concrete instance constructed
/// against the real [EncryptedVault]; tests can override it with a fake.
final authServiceProvider = Provider<AuthService>((ref) {
  throw UnimplementedError(
    'authServiceProvider must be overridden in main.dart with an AuthService '
    'instance bound to the real EncryptedVault',
  );
});

final profilesProvider =
    FutureProvider.family<List<Profile>, String>((ref, _) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get<Map<String, dynamic>>('/api/v1/profiles');
  return (data['items'] as List)
      .map((p) => Profile.fromJson(p as Map<String, dynamic>))
      .toList();
});

final selectedProfileProvider = StateProvider<Profile?>((ref) => null);

final languageProvider = StateProvider<String>((ref) => 'de');
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
// 1 = Monday, 7 = Sunday (ISO weekday convention)
final firstDayOfWeekProvider = StateProvider<int>((ref) => 1);
