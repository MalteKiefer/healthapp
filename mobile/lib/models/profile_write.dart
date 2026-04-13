import '../models/profile.dart';

/// Request body shape for creating or updating a profile via the REST API.
///
/// Mirrors the web client's `Partial<Profile>` structural fields. Content
/// fields (date_of_birth, biological_sex, blood_type, rhesus_factor) are
/// sent in plaintext on mobile for now; the server accepts both legacy
/// plaintext fields used by the web
/// client. Encryption parity will be added in a later sprint.
class ProfileWriteRequest {
  final String? id;
  final String displayName;
  final String? dateOfBirth;
  final String? biologicalSex;
  final String? bloodType;
  final String? rhesusFactor;
  final String? avatarColor;
  final String? notes;

  const ProfileWriteRequest({
    this.id,
    required this.displayName,
    this.dateOfBirth,
    this.biologicalSex,
    this.bloodType,
    this.rhesusFactor,
    this.avatarColor,
    this.notes,
  });

  /// Builds the JSON body sent to `POST /api/v1/profiles` and
  /// `PATCH /api/v1/profiles/{id}`. Null fields are omitted so PATCH
  /// semantics stay partial.
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'display_name': displayName,
    };
    if (id != null) map['id'] = id;
    if (dateOfBirth != null) map['date_of_birth'] = dateOfBirth;
    if (biologicalSex != null) map['biological_sex'] = biologicalSex;
    if (bloodType != null) map['blood_type'] = bloodType;
    if (rhesusFactor != null) map['rhesus_factor'] = rhesusFactor;
    if (avatarColor != null) map['avatar_color'] = avatarColor;
    if (notes != null) map['notes'] = notes;
    return map;
  }
}

/// Best-effort JSON serializer for an existing read-only [Profile]. Used
/// when we need to round-trip an existing profile through the write API
/// (e.g. to pre-populate an edit form before sending a PATCH).
Map<String, dynamic> profileToJson(Profile p) {
  return <String, dynamic>{
    'id': p.id,
    'display_name': p.displayName,
    if (p.dateOfBirth != null) 'date_of_birth': p.dateOfBirth,
    if (p.biologicalSex != null) 'biological_sex': p.biologicalSex,
    if (p.bloodType != null) 'blood_type': p.bloodType,
    if (p.avatarColor != null) 'avatar_color': p.avatarColor,
    if (p.createdAt != null) 'created_at': p.createdAt,
  };
}
