import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/screens/sessions/sessions_screen.dart';

void main() {
  testWidgets('SessionsScreen renders Scaffold and AppBar', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: SessionsScreen()),
      ),
    );
    await tester.pump();
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);

    // Drain any pending timers from async providers / network calls.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle(const Duration(seconds: 1));
  });
}
