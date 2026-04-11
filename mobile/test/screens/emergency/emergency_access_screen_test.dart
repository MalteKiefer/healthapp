import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/screens/emergency/emergency_access_screen.dart';

void main() {
  testWidgets('EmergencyAccessScreen renders', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: EmergencyAccessScreen(profileId: 'test-profile'),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(Scaffold), findsOneWidget);

    // Drain any pending timers from async providers / network calls.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle(const Duration(seconds: 1));
  });
}
