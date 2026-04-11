import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/core/auth/auth_service.dart';
import 'package:healthapp/core/security/secure_store/encrypted_vault.dart';
import 'package:healthapp/providers/providers.dart';
import 'package:healthapp/screens/login/login_screen.dart';

/// Minimal in-memory [AuthService] stub for the login smoke test.
///
/// The real provider throws by default (it must be overridden in
/// `main.dart` with a vault-backed instance). We don't exercise the
/// full sign-in flow here, so we just need a no-op object whose
/// `loadCredentials` returns null and whose mutators do nothing.
class _FakeAuthService implements AuthService {
  @override
  Future<StoredCredentials?> loadCredentials() async => null;

  @override
  Future<void> saveCredentials(StoredCredentials c) async {}

  @override
  Future<void> clearCredentials() async {}

  // The screen never touches `vault` directly, but `implements`
  // requires us to satisfy the interface.
  @override
  EncryptedVault get vault => throw UnimplementedError();
}

/// Smoke test for [LoginScreen].
///
/// We don't exercise the full sign-in flow (which needs a real
/// [AuthService] / [ApiClient] backed by network + keystore). We only
/// pump the widget inside a minimal [ProviderScope] with the auth
/// service provider overridden by a no-op fake, and assert that the
/// core form scaffolding renders without throwing.
void main() {
  testWidgets('LoginScreen renders email, password and sign-in button',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(_FakeAuthService()),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    // First frame — async initState side effects may still be pending.
    await tester.pump();

    // Form fields: email, password, server URL.
    expect(find.byType(TextField), findsAtLeastNWidgets(2));
    // Primary action button.
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);

    // Drain pending timers / futures from the throwing provider.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle(const Duration(seconds: 1));
  });
}
