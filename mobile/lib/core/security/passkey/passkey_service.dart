import 'dart:typed_data';

/// Abstraction for platform passkey (FIDO2 / WebAuthn) integration.
///
/// Each implementation talks to the OS credential manager:
///   Android 14+ -> androidx.credentials CredentialManager
///   iOS 16+     -> AuthenticationServices ASAuthorizationController
///
/// The actual registration and assertion flows require a backend
/// issuing a challenge and verifying the attestation / assertion.
/// Until the Go API gains WebAuthn endpoints the implementation
/// returns `PasskeySupport.unavailable` and throws on all methods.
enum PasskeySupport {
  unavailable,
  available,
  enrolled,
}

class PasskeyRegistrationRequest {
  const PasskeyRegistrationRequest({
    required this.rpId,
    required this.rpName,
    required this.userId,
    required this.userName,
    required this.userDisplayName,
    required this.challenge,
  });

  final String rpId;
  final String rpName;
  final Uint8List userId;
  final String userName;
  final String userDisplayName;
  final Uint8List challenge;
}

class PasskeyAssertionRequest {
  const PasskeyAssertionRequest({
    required this.rpId,
    required this.challenge,
    this.allowedCredentialIds = const [],
  });

  final String rpId;
  final Uint8List challenge;
  final List<Uint8List> allowedCredentialIds;
}

class PasskeyBackendUnavailable implements Exception {
  const PasskeyBackendUnavailable();
  @override
  String toString() =>
      'PasskeyBackendUnavailable: server-side WebAuthn endpoints are not yet implemented';
}

abstract class PasskeyService {
  /// Query whether the OS supports platform passkeys at all and whether
  /// the user has any credential enrolled for the current relying party.
  Future<PasskeySupport> support();

  /// Starts the native credential creation flow. Returns the opaque
  /// attestation blob the backend must verify.
  ///
  /// Throws [PasskeyBackendUnavailable] until the server endpoints land.
  Future<Uint8List> register(PasskeyRegistrationRequest request);

  /// Starts the native assertion flow. Returns the opaque signature
  /// blob the backend must verify.
  ///
  /// Throws [PasskeyBackendUnavailable] until the server endpoints land.
  Future<Uint8List> authenticate(PasskeyAssertionRequest request);
}

/// Production impl delegating to the native MethodChannel.
/// Until the backend lands, every method throws [PasskeyBackendUnavailable]
/// so callers can surface a friendly "coming soon" UI instead of crashing.
class PasskeyMethodChannelService implements PasskeyService {
  const PasskeyMethodChannelService();

  @override
  Future<PasskeySupport> support() async {
    // TODO(passkey-backend): wire up native MethodChannel probe.
    return PasskeySupport.unavailable;
  }

  @override
  Future<Uint8List> register(PasskeyRegistrationRequest request) async {
    // TODO(passkey-backend): invoke 'healthvault.security/passkey#register'
    // on the MethodChannel and forward the request fields.
    throw const PasskeyBackendUnavailable();
  }

  @override
  Future<Uint8List> authenticate(PasskeyAssertionRequest request) async {
    // TODO(passkey-backend): invoke 'healthvault.security/passkey#authenticate'.
    throw const PasskeyBackendUnavailable();
  }
}

/// Dart-only fake for unit tests.
class FakePasskeyService implements PasskeyService {
  FakePasskeyService({this.reportedSupport = PasskeySupport.available});
  final PasskeySupport reportedSupport;

  @override
  Future<PasskeySupport> support() async => reportedSupport;

  @override
  Future<Uint8List> register(PasskeyRegistrationRequest request) async {
    return Uint8List.fromList([0xAA, 0xBB, 0xCC]);
  }

  @override
  Future<Uint8List> authenticate(PasskeyAssertionRequest request) async {
    return Uint8List.fromList([0x11, 0x22, 0x33]);
  }
}
