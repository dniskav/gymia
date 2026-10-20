import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A device preference. It is deliberately independent of the active profile.
class WelcomeSettings extends ChangeNotifier {
  WelcomeSettings({
    Future<String?> Function(String)? read,
    Future<void> Function(String, String)? write,
  }) : _read = read ?? ((key) => const FlutterSecureStorage().read(key: key)),
       _write =
           write ??
           ((key, value) =>
               const FlutterSecureStorage().write(key: key, value: value));

  static final instance = WelcomeSettings();
  static const storageKey = 'gymia.welcome.auto_show.v1';
  static const contentVersion = 1;
  final Future<String?> Function(String) _read;
  final Future<void> Function(String, String) _write;

  bool autoShow = true;
  bool busy = false;
  bool offeredThisLaunch = false;
  bool loaded = false;
  int? seenVersion;
  DateTime? completedAt;

  Future<void> load() async {
    final saved = await _read(storageKey);
    if (saved == null || saved == 'true' || saved == 'false') {
      autoShow = saved != 'false';
      seenVersion = null;
      completedAt = null;
    } else {
      try {
        final data = jsonDecode(saved) as Map<String, dynamic>;
        autoShow = data['autoShow'] != false;
        seenVersion = data['seenVersion'] as int?;
        completedAt = DateTime.tryParse(data['completedAt'] as String? ?? '');
      } catch (_) {
        autoShow = true;
        seenVersion = null;
        completedAt = null;
      }
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> select(bool value, {bool completed = false}) async {
    if (busy) throw StateError('La preferencia se está guardando.');
    if (value == autoShow && !completed) return;
    busy = true;
    notifyListeners();
    try {
      final when = completed ? DateTime.now().toUtc() : completedAt;
      final version = completed ? contentVersion : seenVersion;
      await _write(
        storageKey,
        jsonEncode({
          'autoShow': value,
          'seenVersion': version,
          'completedAt': when?.toIso8601String(),
        }),
      );
      autoShow = value;
      seenVersion = version;
      completedAt = when;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
