import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../domain/ai_config.dart';
import '../domain/user_profile.dart';

class AiSettingsStore {
  const AiSettingsStore({this.profileId = 'local'});
  final String profileId;
  static const _storage = FlutterSecureStorage();
  String get _key => profileStorageKey('gymia.ai.config.v1', profileId);
  Future<AiConfig?> load() async {
    final source = await _storage.read(key: _key);
    final config =
        source == null
            ? null
            : AiConfig.fromJson(jsonDecode(source) as Map<String, dynamic>);
    if (config != null && config.usesChatGpt && config.profileId != profileId) {
      throw const FormatException(
        'La conexión ChatGPT pertenece a otro perfil.',
      );
    }
    return config;
  }

  Future<void> save(AiConfig config) async {
    config.validate();
    if (config.usesChatGpt && config.profileId != profileId) {
      throw const FormatException(
        'La conexión ChatGPT pertenece a otro perfil.',
      );
    }
    final previous = await load();
    if (previous?.toJson().toString() != config.toJson().toString()) {
      await _storage.delete(key: '$_key.verified');
    }
    await _storage.write(key: _key, value: jsonEncode(config.toJson()));
  }

  Future<void> markVerified(AiConfig config) async {
    final current = await load();
    if (current?.toJson().toString() != config.toJson().toString()) return;
    await _storage.write(
      key: '$_key.verified',
      value: jsonEncode({
        'config': config.toJson(),
        'at': DateTime.now().toIso8601String(),
      }),
    );
  }

  Future<bool> isVerified(AiConfig config) async {
    final source = await _storage.read(key: '$_key.verified');
    if (source == null) return false;
    final value = jsonDecode(source) as Map<String, dynamic>;
    return jsonEncode(value['config']) == jsonEncode(config.toJson());
  }

  Future<bool> recentlyVerified(AiConfig config) async {
    if (!await isVerified(config)) return false;
    final value = jsonDecode((await _storage.read(key: '$_key.verified'))!);
    final elapsed = DateTime.now().difference(
      DateTime.parse(value['at'] as String),
    );
    return !elapsed.isNegative && elapsed.inSeconds < 30;
  }

  Future<void> delete() async {
    await _storage.delete(key: _key);
    await _storage.delete(key: '$_key.verified');
  }
}
