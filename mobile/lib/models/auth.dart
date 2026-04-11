class LoginRequest {
  final String email;
  final String authHash;

  LoginRequest({required this.email, required this.authHash});

  Map<String, dynamic> toJson() => {
        'email': email,
        'auth_hash': authHash,
      };
}

class LoginResponse {
  final String userId;
  final String? role;
  final String? pekSalt;
  final String? identityPrivkeyEnc;
  final String? signingPrivkeyEnc;
  final bool requiresTotp;
  final String? challengeToken;
  final int? expiresAt;

  LoginResponse({
    this.userId = '',
    this.role,
    this.pekSalt,
    this.identityPrivkeyEnc,
    this.signingPrivkeyEnc,
    this.requiresTotp = false,
    this.challengeToken,
    this.expiresAt,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) => LoginResponse(
        userId: json['user_id'] as String? ?? '',
        role: json['role'] as String?,
        pekSalt: json['pek_salt'] as String?,
        identityPrivkeyEnc: json['identity_privkey_enc'] as String?,
        signingPrivkeyEnc: json['signing_privkey_enc'] as String?,
        requiresTotp: json['requires_totp'] as bool? ?? false,
        challengeToken: json['challenge_token'] as String?,
        expiresAt: (json['expires_at'] as num?)?.toInt(),
      );
}
