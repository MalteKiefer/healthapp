import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/core/security/security_state.dart';

void main() {
  group('SecurityState', () {
    test('has all expected values', () {
      expect(SecurityState.values, containsAll([
        SecurityState.unregistered,
        SecurityState.loggedInNoPin,
        SecurityState.locked,
        SecurityState.unlocking,
        SecurityState.unlocked,
        SecurityState.wiped,
        SecurityState.migrationPending,
      ]));
    });

    test('isGated returns true for states where router must block content', () {
      expect(SecurityState.unregistered.isGated, isTrue);
      expect(SecurityState.loggedInNoPin.isGated, isTrue);
      expect(SecurityState.locked.isGated, isTrue);
      expect(SecurityState.migrationPending.isGated, isTrue);
      expect(SecurityState.unlocked.isGated, isFalse);
      expect(SecurityState.unlocking.isGated, isTrue);
    });
  });
}
