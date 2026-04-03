class Profile {
  final String id;
  final String displayName;
  final String? dateOfBirth;
  final String? biologicalSex;
  final String? bloodType;
  final String? avatarColor;
  final String? createdAt;

  Profile({
    required this.id,
    required this.displayName,
    this.dateOfBirth,
    this.biologicalSex,
    this.bloodType,
    this.avatarColor,
    this.createdAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'],
        displayName: json['display_name'],
        dateOfBirth: json['date_of_birth'],
        biologicalSex: json['biological_sex'],
        bloodType: json['blood_type'],
        avatarColor: json['avatar_color'],
        createdAt: json['created_at'],
      );
}
