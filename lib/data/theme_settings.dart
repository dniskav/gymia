import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Appearance belongs to this device; switching accounts preserves it.
class ThemeSettings extends ChangeNotifier {
  ThemeSettings();
  static final instance = ThemeSettings();
  static const storageKey = 'gymia.appearance.v1'; // Preference name, not a credential. gitleaks:allow
  static const _storage = FlutterSecureStorage();
  ThemeMode mode = ThemeMode.dark;
  bool busy = false;

  Future<void> load() async {
    final saved = await _storage.read(key: storageKey);
    mode =
        ThemeMode.values.where((m) => m.name == saved).firstOrNull ??
        ThemeMode.dark;
    notifyListeners();
  }

  Future<void> select(ThemeMode next) async {
    if (busy || mode == next) return;
    busy = true;
    notifyListeners();
    try {
      await _storage.write(key: storageKey, value: next.name);
      mode = next;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
