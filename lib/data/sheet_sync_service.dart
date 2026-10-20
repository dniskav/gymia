import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import '../domain/user_profile.dart';
import '../domain/sheet_context.dart';
import '../domain/sheet_sync.dart';
import '../domain/workout.dart';
import 'profile_store.dart';

class SheetSyncService {
  SheetSyncService({required this.profileId});
  final String profileId;
  static const channel = ProfileStore.channel;
  static const storage = FlutterSecureStorage();
  UserProfile? identity;
  String get destinationKey =>
      profileStorageKey('gymia.sheet.destination.v1', profileId);
  String get creationKey =>
      profileStorageKey('gymia.sheet.creation.v1', profileId);
  void checkProfile() {
    if (ProfileStore.instance.activeId != profileId) {
      throw const ValidationException(
        'El perfil cambió. Vuelve al chat de tu cuenta.',
      );
    }
  }

  /// A local-profile export authorizes a destination without moving its records
  /// or switching to another user's database.
  Future<void> authorize({
    bool chooseAccount = false,
    bool interactive = true,
  }) async {
    checkProfile();
    var user = ProfileStore.instance.active;
    if (profileId == 'local') {
      final saved = await storage.read(key: destinationKey);
      if (saved != null && !chooseAccount) {
        user = UserProfile.fromJson(jsonDecode(saved) as Map<String, dynamic>);
      }
      if (user == null || chooseAccount) {
        if (!interactive) {
          throw const ValidationException(
            'Conecta Google una vez desde Enviar a Google Sheets para activar la conexión.',
          );
        }
        final value = await channel.invokeMapMethod<String, dynamic>(
          'connectIdentity',
        );
        if (value == null) {
          throw const ValidationException('Google no devolvió una cuenta.');
        }
        user = UserProfile.fromJson(value);
      }
    }
    if (user == null) {
      throw const ValidationException(
        'Conecta una cuenta de Google para enviar el progreso.',
      );
    }
    final granted = await channel.invokeMethod<bool>('authorizeWrite', {
      'expectedSubject': user.subject,
      'email': user.email,
      'interactive': interactive,
    });
    checkProfile();
    if (granted != true) {
      throw const ValidationException(
        'Google no concedió el permiso de escritura.',
      );
    }
    identity = user;
    if (profileId == 'local') {
      await storage.write(
        key: destinationKey,
        value: jsonEncode(user.toJson()),
      );
    }
  }

  Future<Map<String, dynamic>> call(
    String method,
    Map<String, dynamic> args,
  ) async {
    checkProfile();
    if (identity == null) await authorize(interactive: false);
    final user = identity!;
    Map<String, dynamic>? result;
    try {
      result = await channel.invokeMapMethod<String, dynamic>(method, {
        ...args,
        'expectedSubject': user.subject,
      });
    } on PlatformException catch (e) {
      if (e.code != 'GOOGLE_AUTH_REQUIRED') rethrow;
      await channel.invokeMethod<void>('clearSheetToken', {
        'expectedSubject': user.subject,
      });
      await authorize(interactive: false);
      if (identity!.subject != user.subject) {
        throw const ValidationException(
          'La cuenta cambió. El envío no se redirigirá.',
        );
      }
      result = await channel.invokeMapMethod<String, dynamic>(method, {
        ...args,
        'expectedSubject': user.subject,
      });
    }
    checkProfile();
    if (result == null) {
      throw const ValidationException('Google no confirmó la operación.');
    }
    return result;
  }

  String get connectionKey =>
      profileStorageKey('gymia.sheet.connection.v1', profileId);
  Future<Map<String, dynamic>?> connection() async {
    checkProfile();
    final raw = await storage.read(key: connectionKey);
    return raw == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  Future<void> bind(
    SheetContext sheet,
    Map<String, dynamic> snapshot, {
    bool automatic = true,
    bool allowOverwrite = false,
    String instructions = '',
    String layout = '',
  }) async {
    checkProfile();
    if (identity == null) {
      throw const ValidationException(
        'Conecta Google antes de guardar el destino.',
      );
    }
    final old = await connection();
    final same =
        old?['subject'] == identity!.subject &&
        old?['id'] == sheet.id &&
        old?['sheetId'] == (snapshot['properties'] as Map)['sheetId'];
    await storage.write(
      key: connectionKey,
      value: jsonEncode({
        'subject': identity!.subject,
        'email': identity!.email,
        'id': sheet.id,
        'name': sheet.name,
        'title': sheet.title,
        'sheetId': (snapshot['properties'] as Map)['sheetId'],
        'automatic': automatic,
        'allowOverwrite': allowOverwrite,
        'instructions': instructions,
        'layout':
            layout.isNotEmpty ? layout : (same ? (old!['layout'] ?? '') : ''),
        'automaticAfter':
            same ? old!['automaticAfter'] : DateTime.now().toIso8601String(),
      }),
    );
  }

  Future<void> rememberLayout(
    Map<String, dynamic> expected,
    String layout,
  ) async {
    if (layout.isEmpty) return;
    final live = await connection();
    if (live == null ||
        live['subject'] != expected['subject'] ||
        live['id'] != expected['id'] ||
        live['sheetId'] != expected['sheetId']) {
      return;
    }
    await storage.write(
      key: connectionKey,
      value: jsonEncode({...live, 'layout': layout}),
    );
  }

  Future<void> setAutomatic(bool enabled) async {
    final value = await connection();
    if (value == null) return;
    await storage.write(
      key: connectionKey,
      value: jsonEncode({...value, 'automatic': enabled}),
    );
  }

  Future<void> pauseAutomation() async {
    final value = await connection();
    if (value == null) return;
    await storage.write(
      key: connectionKey,
      value: jsonEncode({...value, 'automatic': false}),
    );
  }

  Future<void> disconnectDestination() async {
    checkProfile();
    await storage.delete(key: connectionKey);
    await storage.delete(key: destinationKey);
  }

  Future<List<Map<String, String>>> files() async {
    final results = <Map<String, String>>[];
    var page = '';
    do {
      final data = await call('list', {if (page.isNotEmpty) 'pageToken': page});
      results.addAll([
        for (final f in data['files'] as List)
          Map<String, String>.from(f as Map),
      ]);
      page = data['nextPageToken'] as String? ?? '';
    } while (page.isNotEmpty && results.length < 500);
    return results;
  }

  Future<List<String>> tabs(String id) async {
    checkProfile();
    final result = await channel.invokeListMethod<String>('tabs', {
      'id': id,
      'expectedSubject': identity?.subject,
    });
    checkProfile();
    return result ?? [];
  }

  Future<Map<String, dynamic>> snapshot(SheetContext sheet) async {
    final result = await call('syncSnapshot', {
      'id': sheet.id,
      'title': sheet.title,
    });
    if (utf8.encode(jsonEncode(result['rows'])).length > 120000) {
      throw const ValidationException(
        'La pestaña supera el tamaño admitido para interpretarla completa. Elige una pestaña más pequeña.',
      );
    }
    return result;
  }

  String sourceKey(String workoutId) => '$profileId:$workoutId';
  Future<bool> isSynced(
    SheetContext sheet,
    String workoutId,
    String sourceVersion,
  ) async =>
      (await call('syncStatus', {
        'id': sheet.id,
        'sourceKey': sourceKey(workoutId),
        'sourceVersion': sourceVersion,
      }))['synced'] ==
      true;
  Future<Map<String, dynamic>> write(
    SheetContext sheet,
    String workoutId,
    Map<String, dynamic> snapshot,
    SheetSyncPlan plan,
    String sourceVersion, {
    bool allowOverwrite = false,
  }) => call('writeWorkout', {
    'id': sheet.id,
    'title': sheet.title,
    'sheetId': (snapshot['properties'] as Map)['sheetId'],
    'sourceKey': sourceKey(workoutId),
    'sourceVersion': sourceVersion,
    'allowOverwrite': allowOverwrite,
    'writes':
        plan.writes
            .map(
              (c) => {
                ...c.toJson(),
                'expected':
                    (snapshot['entered'] as Map? ??
                        {})['${c.row}:${c.column}'] ??
                    <String, dynamic>{},
              },
            )
            .toList(),
  });
  Future<SheetContext> create(String name) async {
    // Persist before requesting creation. An interrupted attempt only searches
    // for that same unique title on retry, never blindly creates another file.
    final saved = await storage.read(key: creationKey);
    final pending =
        saved == null
            ? {
              'name': name.trim(),
              'requestId': const Uuid().v4(),
              'subject': identity!.subject,
            }
            : Map<String, dynamic>.from(jsonDecode(saved) as Map);
    if (pending['subject'] != identity!.subject) {
      throw const ValidationException(
        'Hay una creación pendiente con otra cuenta. Reconecta esa cuenta para recuperarla.',
      );
    }
    await storage.write(key: creationKey, value: jsonEncode(pending));
    final data = await call('createSpreadsheet', {
      ...pending,
      'recoverOnly': saved != null,
    });
    return SheetContext(
      id: data['id'] as String,
      name: data['name'] as String,
      title: data['title'] as String,
      loadedAt: DateTime.now(),
      rows: const [canonicalHeaders],
      interpretationPending: false,
    );
  }
}

const canonicalHeaders = [
  'Fecha',
  'Actividad',
  'Serie / tramo',
  'Métricas',
  'Duración (s)',
  'Notas',
  'Sesión GymIA',
];

/// The app's own new-sheet format can be filled without asking the model to
/// reinterpret or abbreviate original notes. Arbitrary existing layouts use a reviewed plan.
SheetSyncPlan? canonicalSheetPlan(
  Map<String, dynamic> source,
  Map<String, dynamic> snapshot,
) {
  final rows =
      (snapshot['rows'] as List)
          .map((r) => List<String>.from(r as List))
          .toList();
  if (rows.isEmpty || jsonEncode(rows.first) != jsonEncode(canonicalHeaders)) {
    return null;
  }
  var row = rows.length;
  final writes = <SheetCellWrite>[];
  void append(List<Object> values) {
    for (var c = 0; c < values.length; c++) {
      if (values[c] != '') writes.add(SheetCellWrite(row, c, values[c]));
    }
    row++;
  }

  String noteText(dynamic message) {
    final attachment = message['attachment'] as Map?;
    return '${message['text']}${attachment == null ? '' : '\nAdjunto conservado en el móvil: ${attachment['name']} (${attachment['mime']})'}';
  }

  String metricsText(dynamic message, dynamic definition) {
    final metrics = message['metrics'] as Map;
    if (metrics.isEmpty) return '';
    return jsonEncode({
      'values': metrics,
      'fields':
          (definition['fields'] as List)
              .where((f) => metrics.containsKey(f['key']))
              .toList(),
    });
  }

  final date = (source['startedAt'] as String).substring(0, 10);
  final linked = <String>{};
  for (final a in source['activities'] as List) {
    final messages = a['messages'] as List;
    final intervals = a['intervals'] as List;
    if (a['exerciseId'] != null && intervals.isNotEmpty) {
      linked.add(a['exerciseId'] as String);
    }
    var n = 0;
    for (final interval in intervals) {
      final notes =
          messages.where((m) => m['intervalId'] == interval['id']).toList();
      append([
        DateTime.parse(
          interval['startedAt'] as String,
        ).toLocal().toIso8601String().substring(0, 10),
        a['definition']['name'] as String,
        ++n,
        notes
            .map((m) => metricsText(m, a['definition']))
            .where((m) => m.isNotEmpty)
            .join('\n'),
        interval['durationSeconds'] as Object? ?? '',
        notes.map(noteText).join('\n'),
        source['id'] as String,
      ]);
    }
    final unbound =
        messages
            .where(
              (m) =>
                  m['intervalId'] == null ||
                  !intervals.any((i) => i['id'] == m['intervalId']),
            )
            .toList();
    if (unbound.isNotEmpty) {
      append([
        date,
        a['definition']['name'] as String,
        '',
        unbound
            .map((m) => metricsText(m, a['definition']))
            .where((m) => m.isNotEmpty)
            .join('\n'),
        '',
        unbound.map(noteText).join('\n'),
        source['id'] as String,
      ]);
    }
    if ((a['draft'] as String).trim().isNotEmpty) {
      append([
        date,
        a['definition']['name'] as String,
        '',
        '',
        '',
        'Borrador sin enviar: ${a['draft']}',
        source['id'] as String,
      ]);
    }
  }
  for (final e in source['exercises'] as List) {
    if (linked.contains(e['id'])) continue;
    var n = 0;
    for (final set in e['sets'] as List) {
      append([
        date,
        e['name'] as String,
        ++n,
        jsonEncode({'weight_kg': set['kg'], 'reps': set['reps']}),
        '',
        '',
        source['id'] as String,
      ]);
    }
  }
  if (writes.isEmpty) {
    throw const ValidationException(
      'Esta sesión no contiene series, tramos ni notas para enviar.',
    );
  }
  final grid = (snapshot['properties'] as Map)['gridProperties'] as Map;
  if (row > (grid['rowCount'] as int) ||
      writes.length > 250 ||
      writes.any(
        (c) => c.value is String && (c.value as String).length > 4000,
      )) {
    throw const ValidationException(
      'Este entrenamiento supera la capacidad del envío. No se han recortado sus notas ni enviado datos parciales.',
    );
  }
  return SheetSyncPlan(
    writes,
    'Añadir el entrenamiento con sus métricas y notas originales, conservando lo que ya hay en la hoja.',
  );
}
