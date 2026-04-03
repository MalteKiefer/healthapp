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
  final bool requiresTotp;
  final String? challengeToken;
  final int? expiresAt;

  LoginResponse({
    this.userId = '',
    this.role,
    this.pekSalt,
    this.requiresTotp = false,
    this.challengeToken,
    this.expiresAt,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) => LoginResponse(
        userId: json['user_id'] ?? '',
        role: json['role'],
        pekSalt: json['pek_salt'],
        requiresTotp: json['requires_totp'] ?? false,
        challengeToken: json['challenge_token'],
        expiresAt: json['expires_at'],
      );
}
