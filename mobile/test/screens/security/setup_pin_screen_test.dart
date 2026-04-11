import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/screens/security/setup_pin_screen.dart';
import 'package:healthapp/widgets/pin_numpad.dart';

/// Smoke test for [SetupPinScreen].
///
/// The screen only touches `appLockControllerProvider` lazily inside
/// `_onCompleted` (after the user enters a 6-digit PIN twice). The
/// initial render therefore does not require any provider override —
/// pumping inside a bare [ProviderScope] is enough to verify the lock
/// icon, the prompt copy and the [PinNumpad] all appear.
///
/// The full setupPin → router redirect flow needs a real PinService
/// bound to the app documents directory and is covered by
/// `app_lock_controller_test.dart` and the integration tests.
void main() {
  testWidgets('SetupPinScreen renders prompt and PIN numpad',
      (tester) async {
    // The PIN numpad needs a tall viewport — the default 800x600
    // test surface causes a vertical overflow.
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: SetupPinScreen()),
      ),
    );
    await tester.pump();

    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(PinNumpad), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.text('Wähle einen 6-stelligen PIN'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle(const Duration(seconds: 1));
  });
}
