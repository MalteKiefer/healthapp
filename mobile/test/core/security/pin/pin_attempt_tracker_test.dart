import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/core/security/pin/pin_attempt_tracker.dart';

void main() {
  group('PinAttemptTracker.lockoutFor', () {
    test('no lockout for attempts 1-4', () {
      for (var n = 1; n <= 4; n++) {
        expect(PinAttemptTracker.lockoutFor(n), Duration.zero);
      }
    });

    test('lockout escalates 1m/5m/15m/30m/1h at 5-9', () {
      expect(PinAttemptTracker.lockoutFor(5), const Duration(minutes: 1));
      expect(PinAttemptTracker.lockoutFor(6), const Duration(minutes: 5));
      expect(PinAttemptTracker.lockoutFor(7), const Duration(minutes: 15));
      expect(PinAttemptTracker.lockoutFor(8), const Duration(minutes: 30));
      expect(PinAttemptTracker.lockoutFor(9), const Duration(hours: 1));
    });

    test('attempt 10 signals wipe', () {
      expect(PinAttemptTracker.shouldWipe(10), isTrue);
      expect(PinAttemptTracker.shouldWipe(9), isFalse);
    });
  });

  group('PinAttemptTracker state', () {
    late PinAttemptTracker tracker;
    late DateTime fakeNow;

    setUp(() {
      fakeNow = DateTime(2026, 4, 10, 12, 0, 0);
      tracker = PinAttemptTracker(now: () => fakeNow);
    });

    test('initial state has 0 failures and no lockout', () {
      expect(tracker.failedAttempts, 0);
      expect(tracker.isLocked, isFalse);
    });

    test('recordFailure increments and sets lockoutUntil at threshold', () {
      for (var i = 0; i < 4; i++) {
        tracker.recordFailure();
        expect(tracker.isLocked, isFalse);
      }
      tracker.recordFailure();
      expect(tracker.failedAttempts, 5);
      expect(tracker.isLocked, isTrue);
      expect(tracker.lockoutUntil, fakeNow.add(const Duration(minutes: 1)));
    });

    test('isLocked becomes false after lockout expires', () {
      for (var i = 0; i < 5; i++) tracker.recordFailure();
      expect(tracker.isLocked, isTrue);
      fakeNow = fakeNow.add(const Duration(minutes: 2));
      expect(tracker.isLocked, isFalse);
    });

    test('reset zeroes state', () {
      for (var i = 0; i < 5; i++) tracker.recordFailure();
      tracker.reset();
      expect(tracker.failedAttempts, 0);
      expect(tracker.isLocked, isFalse);
      expect(tracker.lockoutUntil, isNull);
    });

    test('recordFailure at 10 marks wipeRequested', () {
      for (var i = 0; i < 10; i++) tracker.recordFailure();
      expect(tracker.wipeRequested, isTrue);
    });

    test('clock rollback doubles the current lockout as tamper guard', () {
      for (var i = 0; i < 5; i++) tracker.recordFailure();
      final originalUntil = tracker.lockoutUntil!;
      fakeNow = fakeNow.subtract(const Duration(hours: 1));
      tracker.touchInteraction();
      expect(tracker.lockoutUntil!.isAfter(originalUntil), isTrue);
    });
  });

  group('PinAttemptTracker serialization', () {
    test('toJson/fromJson round-trip', () {
      final now = DateTime(2026, 4, 10);
      final t = PinAttemptTracker(now: () => now);
      t.recordFailure();
      t.recordFailure();

      final json = t.toJson();
      final restored = PinAttemptTracker.fromJson(json, now: () => now);
      expect(restored.failedAttempts, 2);
    });
  });
}
