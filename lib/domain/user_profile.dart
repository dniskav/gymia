import 'dart:convert';

/// Google subject IDs are stable; display names and email addresses are not.
class UserProfile {
  const UserProfile({required this.subject, required this.email});
  final String subject;
  final String email;
  String get id =>
      'google_${base64Url.encode(utf8.encode(subject)).replaceAll('=', '')}';

  Map<String, dynamic> toJson() => {'subject': subject, 'email': email};
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final subject = json['subject'] as String;
    final email = json['email'] as String;
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(subject) ||
        !email.contains('@')) {
      throw const FormatException('Identidad de Google no válida.');
    }
    return UserProfile(subject: subject, email: email);
  }
}

String profileStorageKey(String key, String profileId) =>
    profileId == 'local' ? key : '$key.profile.$profileId';
