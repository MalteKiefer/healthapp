/// Data models for Two-Factor Authentication (TOTP).
///
/// Backed by the `/api/v1/auth/2fa/*` endpoints on the health server.
library;

/// Response from `GET /api/v1/auth/2fa/setup`.
///
/// The server returns a freshly generated TOTP secret plus a
/// provisioning URI (an `otpauth://totp/...` URL) suitable for
/// rendering as a QR code in an authenticator app. This secret is
/// stored encrypted on the server but is NOT yet active — the user
/// must confirm possession of the secret by POSTing a valid code to
/// `/api/v1/auth/2fa/enable` before 2FA is actually enforced.
class TwoFactorSetup {
  /// Base32-encoded shared secret. Shown as a fallback for users who
  /// cannot scan a QR code.
  final String secret;

  /// `otpauth://totp/...` provisioning URI. Encode this as a QR code.
  final String provisioningUri;

  const TwoFactorSetup({
    required this.secret,
    required this.provisioningUri,
  });

  factory TwoFactorSetup.fromJson(Map<String, dynamic> json) => TwoFactorSetup(
        secret: (json['secret'] ?? '') as String,
        // Server field is `provisioning_uri`; accept `qr_url` as a
        // fallback in case older servers used that name.
        provisioningUri:
            (json['provisioning_uri'] ?? json['qr_url'] ?? '') as String,
      );

  Map<String, dynamic> toJson() => {
        'secret': secret,
        'provisioning_uri': provisioningUri,
      };
}

/// Simple status wrapper describing whether 2FA is currently enabled
/// for the signed-in user. The backend does not expose a dedicated
/// status endpoint, so callers typically derive this from the login
/// response or local state after enable/disable actions succeed.
class TwoFactorStatus {
  final bool enabled;
  final List<String> recoveryCodes;

  const TwoFactorStatus({
    required this.enabled,
    this.recoveryCodes = const [],
  });

  factory TwoFactorStatus.fromJson(Map<String, dynamic> json) =>
      TwoFactorStatus(
        enabled: (json['enabled'] ?? false) as bool,
        recoveryCodes: (json['codes'] is List)
            ? (json['codes'] as List).map((e) => e.toString()).toList()
            : const [],
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'codes': recoveryCodes,
      };

  TwoFactorStatus copyWith({
    bool? enabled,
    List<String>? recoveryCodes,
  }) =>
      TwoFactorStatus(
        enabled: enabled ?? this.enabled,
        recoveryCodes: recoveryCodes ?? this.recoveryCodes,
      );
}
