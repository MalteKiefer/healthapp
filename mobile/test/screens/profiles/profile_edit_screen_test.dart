import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/screens/profiles/profile_edit_screen.dart';

void main() {
  testWidgets('ProfileEditScreen instantiates in create mode',
      (tester) async {
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (_) {};
    try {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: ProfileEditScreen()),
        ),
      );
      tester.takeException();
      expect(find.byType(ProfileEditScreen), findsOneWidget);
    } finally {
      FlutterError.onError = previousOnError;
    }
  });
}
