/// Authenticated user model.
///
/// The Firebase UID is the canonical identifier. Nothing sensitive (passwords,
/// MQTT credentials, API keys, tokens) is stored here — those remain in
/// [`SecureStorage`](lib/secure_storage.dart) and are never uploaded to Firestore.
class AppUser {
  const AppUser({
    required this.uid,
    required this.email,
    this.displayName,
    this.photoUrl,
    this.emailVerified = false,
    this.provider = 'unknown',
  });

  final String uid;
  final String email;
  final String? displayName;
  final String? photoUrl;
  final bool emailVerified;
  final String provider; // 'google' | 'password' | 'anonymous'

  bool get isAnonymous => provider == 'anonymous';

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'email': email,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'emailVerified': emailVerified,
        'provider': provider,
      };

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        uid: (json['uid'] as String?) ?? '',
        email: (json['email'] as String?) ?? '',
        displayName: (json['displayName'] as String?),
        photoUrl: (json['photoUrl'] as String?),
        emailVerified: json['emailVerified'] == true,
        provider: (json['provider'] as String?) ?? 'unknown',
      );

  String get displayNameOrEmail => displayName.isNotEmptyOrNull ? displayName! : email;

  bool get hasPhoto => photoUrl != null && photoUrl!.isNotEmpty;
}

// Extension to avoid importing `package:collection` for a single null check.
extension _StringNullCheck on String? {
  bool get isNotEmptyOrNull => this != null && this!.isNotEmpty;
}
