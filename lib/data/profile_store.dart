import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../domain/user_profile.dart';

/// The original database remains the local profile. Connecting an account
/// never claims, copies or uploads existing records.
class ProfileStore extends ChangeNotifier {
  ProfileStore._();
  static final instance = ProfileStore._();
  static const storage = FlutterSecureStorage();
  static const channel = MethodChannel('com.gymia.app/google-sheets');
  static const registryKey = 'gymia.profiles.v1';
  String _activeId = 'local';
  final Map<String, UserProfile> _profiles = {};
  bool busy = false;
  int generation = 0;
  String get activeId => _activeId;
  UserProfile? get active => _profiles[_activeId];
  List<UserProfile> get profiles => List.unmodifiable(_profiles.values);

  Future<void> load() async {
    final raw = await storage.read(key: registryKey);
    if (raw == null) {
      _profiles.clear();
      _activeId = 'local';
      return;
    }
    final value = jsonDecode(raw) as Map<String, dynamic>;
    final profiles = <String, UserProfile>{};
    for (final row in value['profiles'] as List) {
      final profile = UserProfile.fromJson(
        Map<String, dynamic>.from(row as Map),
      );
      profiles[profile.id] = profile;
    }
    final selected = value['active'] as String;
    if (selected != 'local' && !profiles.containsKey(selected)) {
      throw const FormatException('El perfil guardado no está disponible.');
    }
    _profiles
      ..clear()
      ..addAll(profiles);
    _activeId = selected;
  }

  Future<void> _commit(String id, Map<String, UserProfile> next) async {
    await storage.write(
      key: registryKey,
      value: jsonEncode({
        'active': id,
        'profiles': next.values.map((p) => p.toJson()).toList(),
      }),
    );
    try {
      await const MethodChannel(
        'com.gymia.app/rest-notifications',
      ).invokeMethod<void>('cancel');
    } on MissingPluginException {
      // No notification bridge on iOS or in widget tests.
    } on PlatformException {
      // Account isolation must not depend on notification availability.
    }
    _profiles
      ..clear()
      ..addAll(next);
    _activeId = id;
    generation++;
    notifyListeners();
  }

  Future<void> connect({String? expectedSubject}) async {
    if (busy) return;
    busy = true;
    try {
      final result = await channel.invokeMapMethod<String, dynamic>(
        'connectIdentity',
        {if (expectedSubject != null) 'expectedSubject': expectedSubject},
      );
      if (result == null) {
        throw const FormatException('Google no devolvió una identidad.');
      }
      final profile = UserProfile.fromJson(result);
      if (expectedSubject != null && profile.subject != expectedSubject) {
        throw const FormatException(
          'La cuenta seleccionada no corresponde al perfil.',
        );
      }
      await _commit(profile.id, {..._profiles, profile.id: profile});
    } finally {
      busy = false;
    }
  }

  /// Disconnect is local; it is not a destructive revoke or account deletion.
  Future<void> useLocal() async {
    if (busy || _activeId == 'local') return;
    busy = true;
    try {
      await channel.invokeMethod<void>('disconnect');
      await _commit('local', {..._profiles});
    } finally {
      busy = false;
    }
  }

  /// Every read from Google must prove it belongs to the captured profile.
  Future<void> authorizeSheets({required String profileId}) async {
    final profile = _profiles[profileId];
    if (profile == null || profileId != activeId) {
      throw const FormatException(
        'Conecta tu cuenta de Google desde Cuenta y datos.',
      );
    }
    final granted = await channel.invokeMethod<bool>('authorize', {
      'expectedSubject': profile.subject,
      'email': profile.email,
    });
    if (activeId != profileId) {
      throw const FormatException('La cuenta cambió durante la autorización.');
    }
    if (granted != true) {
      throw const FormatException('Google no concedió acceso a Sheets.');
    }
  }
}
