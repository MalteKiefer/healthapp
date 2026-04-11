import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/screens/security/lock_screen.dart';
import 'package:healthapp/widgets/pin_numpad.dart';

/// Smoke test for [LockScreen].
///
/// Like [SetupPinScreen], the lock screen only reaches into
/// `appLockControllerProvider` after the user enters a PIN or taps
/// "PIN vergessen?". The initial build is therefore safe to pump in a
/// plain [ProviderScope]. We assert that the title, the [PinNumpad]
/// and the "forgot PIN" affordance render.
///
/// Full unlock / wipe behaviour is exercised in
/// `app_lock_controller_test.dart` and the security integration tests.
void main() {
  testWidgets('LockScreen renders PIN entry UI and forgot-PIN action',
      (tester) async {
    // The PIN numpad needs a tall viewport — the default 800x600
    // test surface causes a vertical overflow.
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: LockScreen()),
      ),
    );
    await tester.pump();

    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(PinNumpad), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsOneWidget);
    expect(find.text('PIN eingeben'), findsOneWidget);
    expect(find.text('PIN vergessen?'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle(const Duration(seconds: 1));
  });
}
