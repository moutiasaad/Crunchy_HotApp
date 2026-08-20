/// The signed-in customer (or guest).
class User {
  final String  email;
  final String? name;
  final String? phone;
  final int     loyaltyPoints;
  final bool    isGuest;

  const User({
    required this.email,
    this.name,
    this.phone,
    this.loyaltyPoints = 0,
    this.isGuest = false,
  });

  /// Anonymous browsing session — has no email or profile.
  const User.guest()
      : email = '',
        name = null,
        phone = null,
        loyaltyPoints = 0,
        isGuest = true;

  /// Parse the `user` object from `POST /auth/otp/verify` and `GET /me`.
  factory User.fromJson(Map<String, dynamic> j) => User(
        email:         (j['email']          ?? '') as String,
        name:           j['name']           as String?,
        phone:          j['phone']          as String?,
        loyaltyPoints: (j['loyalty_points'] ?? 0)  as int,
        isGuest: false,
      );

  bool get isProfileComplete => (name?.isNotEmpty ?? false) && (phone?.isNotEmpty ?? false);

  User copyWith({String? name, String? phone, int? loyaltyPoints}) => User(
        email: email,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        loyaltyPoints: loyaltyPoints ?? this.loyaltyPoints,
        isGuest: isGuest,
      );
}
