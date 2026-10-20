import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../domain/sheet_context.dart';
import '../domain/user_profile.dart';

class SheetContextStore {
  const SheetContextStore({this.profileId = 'local'});
  final String profileId;
  static const _storage = FlutterSecureStorage();
  String get _key => profileStorageKey('gymia.sheet.context.v1', profileId);
  static final changes = ValueNotifier<int>(0);

  Future<SheetContext?> load() async {
    final source = await _storage.read(key: _key);
    return source == null
        ? null
        : SheetContext.fromJson(jsonDecode(source) as Map<String, dynamic>);
  }

  Future<void> save(SheetContext sheet) async {
    await _storage.write(key: _key, value: jsonEncode(sheet.toJson()));
    changes.value++;
  }

  Future<void> delete() async {
    await _storage.delete(key: _key);
    changes.value++;
  }
}
