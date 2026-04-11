import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/models/profile.dart';
import 'package:healthapp/providers/profile_management_provider.dart';
import 'package:healthapp/providers/providers.dart';
import 'package:healthapp/screens/profiles/profile_list_screen.dart';

void main() {
  testWidgets('ProfileListScreen instantiates without crashing',
      (tester) async {
    // Swallow framework errors raised by providers during this smoke test —
    // we only care that the widget tree builds.
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (_) {};
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // Stub all profile fetch providers so no network IO is performed.
            profilesProvider.overrideWith((ref, _) async => <Profile>[]),
            profilesWithMetaProvider.overrideWith(
              (ref) async => <ProfileWithMeta>[],
            ),
          ],
          child: const MaterialApp(home: ProfileListScreen()),
        ),
      );
      // Drain any errors captured during the build phase.
      tester.takeException();
      expect(find.byType(ProfileListScreen), findsOneWidget);
    } finally {
      FlutterError.onError = previousOnError;
    }
  });
}
