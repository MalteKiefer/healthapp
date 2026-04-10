import 'dart:convert';

class PinAttemptTracker {
  PinAttemptTracker({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  int _failedAttempts = 0;
  DateTime? _lockoutUntil;
  DateTime? _lastInteractionAt;
  bool _wipeRequested = false;

  int get failedAttempts => _failedAttempts;
  DateTime? get lockoutUntil => _lockoutUntil;
  bool get wipeRequested => _wipeRequested;

  bool get isLocked {
    if (_lockoutUntil == null) return false;
    return _now().isBefore(_lockoutUntil!);
  }

  static Duration lockoutFor(int attempts) {
    switch (attempts) {
      case 5:
        return const Duration(minutes: 1);
      case 6:
        return const Duration(minutes: 5);
      case 7:
        return const Duration(minutes: 15);
      case 8:
        return const Duration(minutes: 30);
      case 9:
        return const Duration(hours: 1);
      default:
        return Duration.zero;
    }
  }

  static bool shouldWipe(int attempts) => attempts >= 10;

  void recordFailure() {
    _failedAttempts += 1;
    final now = _now();
    _lastInteractionAt = now;
    if (shouldWipe(_failedAttempts)) {
      _wipeRequested = true;
      return;
    }
    final d = lockoutFor(_failedAttempts);
    if (d > Duration.zero) {
      _lockoutUntil = now.add(d);
    }
  }

  void reset() {
    _failedAttempts = 0;
    _lockoutUntil = null;
    _wipeRequested = false;
  }

  void touchInteraction() {
    final now = _now();
    if (_lastInteractionAt != null && now.isBefore(_lastInteractionAt!)) {
      if (_lockoutUntil != null) {
        final extra = _lockoutUntil!.difference(now);
        _lockoutUntil = now.add(extra + extra);
      }
    }
    _lastInteractionAt = now;
  }

  Map<String, dynamic> toJson() => {
        'failedAttempts': _failedAttempts,
        'lockoutUntil': _lockoutUntil?.toIso8601String(),
        'lastInteractionAt': _lastInteractionAt?.toIso8601String(),
        'wipeRequested': _wipeRequested,
      };

  static PinAttemptTracker fromJson(
    Map<String, dynamic> json, {
    DateTime Function()? now,
  }) {
    final t = PinAttemptTracker(now: now);
    t._failedAttempts = json['failedAttempts'] as int? ?? 0;
    final lu = json['lockoutUntil'] as String?;
    t._lockoutUntil = lu == null ? null : DateTime.parse(lu);
    final li = json['lastInteractionAt'] as String?;
    t._lastInteractionAt = li == null ? null : DateTime.parse(li);
    t._wipeRequested = json['wipeRequested'] as bool? ?? false;
    return t;
  }

  String toStoredString() => jsonEncode(toJson());

  static PinAttemptTracker fromStoredString(
    String s, {
    DateTime Function()? now,
  }) =>
      fromJson(jsonDecode(s) as Map<String, dynamic>, now: now);
}
