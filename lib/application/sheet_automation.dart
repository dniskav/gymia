import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import '../data/ai_client.dart';
import '../data/sheet_context_store.dart';
import '../data/sheet_sync_service.dart';
import '../data/sheet_plan_service.dart';
import '../domain/sheet_context.dart';
import '../domain/sheet_sync.dart';
import '../domain/workout.dart';
import '../domain/user_profile.dart';
import 'workout_controller.dart';

/// All remote work stays on the captured profile/account/destination. No popup
/// authorization or new destination can be inferred from model output.
class SheetAutomation {
  SheetAutomation(this.controller, {this.client});
  final WorkoutController controller;
  final AiClient? client;
  late final service = SheetSyncService(profileId: controller.profileId);
  String get queueKey =>
      profileStorageKey('gymia.sheet.jobs.v1', controller.profileId);
  String? lastReadError;
  bool busy = false;
  Future<Map<String, dynamic>?> connect() async {
    var config = await service.connection();
    if (config == null) {
      // Upgrade an already-authorized 0.3.19 destination silently. Without an
      // existing grant this exits with reconnect required, never opens OAuth.
      final sheet =
          await SheetContextStore(profileId: controller.profileId).load();
      if (sheet == null || sheet.source != 'google') return null;
      if (controller.profileId == 'local' &&
          await SheetSyncService.storage.read(key: service.destinationKey) ==
              null) {
        return null;
      }
      await service.authorize(interactive: false);
      final snapshot = await service.snapshot(sheet);
      await service.bind(sheet, snapshot, allowOverwrite: true);
      config = await service.connection();
    } else {
      await service.authorize(interactive: false);
      if (service.identity!.subject != config['subject']) {
        throw const ValidationException(
          'La cuenta no corresponde al destino guardado. El envío quedó pendiente.',
        );
      }
    }
    return config;
  }

  SheetContext target(Map<String, dynamic> config) => SheetContext(
    id: config['id'] as String,
    name: config['name'] as String,
    title: config['title'] as String,
    loadedAt: DateTime.now(),
    rows: const [
      ['Pendiente de lectura'],
    ],
  );
  void checkTarget(Map<String, dynamic> config, Map<String, dynamic> snapshot) {
    if ((snapshot['properties'] as Map)['sheetId'] != config['sheetId']) {
      throw const ValidationException(
        'La pestaña cambió de identidad. Selecciona su destino de nuevo.',
      );
    }
  }

  Future<SheetContext?> refresh() async {
    if (busy) return null;
    busy = true;
    try {
      final config = await connect();
      if (config == null) return null;
      final sheet = target(config);
      final snapshot = await service.snapshot(sheet);
      checkTarget(config, snapshot);
      final fresh = await cache(sheet, snapshot);
      lastReadError = null;
      return fresh;
    } finally {
      busy = false;
    }
  }

  Future<SheetContext> cache(
    SheetContext sheet,
    Map<String, dynamic> snapshot,
  ) async {
    final fresh = SheetContext(
      id: sheet.id,
      name: sheet.name,
      title: sheet.title,
      loadedAt: DateTime.now(),
      rows: [
        for (final row in snapshot['rows'] as List)
          List<String>.from(row as List),
      ],
      interpretationPending: false,
    );
    await SheetContextStore(profileId: controller.profileId).save(fresh);
    return fresh;
  }

  /// Applies an explicit chat edit to the already-bound sheet. Cell addresses
  /// and displayed old values are checked against a new Google snapshot.
  Future<String> directEdit(String answer, String operationKey) async {
    if (busy) {
      throw const ValidationException('Hay otra operación de Google en curso.');
    }
    busy = true;
    try {
      final config = await connect();
      if (config == null) {
        throw const ValidationException(
          'Conecta y elige tu hoja una vez desde Enviar a Google Sheets.',
        );
      }
      final sheet = target(config);
      final snapshot = await service.snapshot(sheet);
      checkTarget(config, snapshot);
      final plan = SheetSyncPlan.parse(
        answer,
        snapshot,
        allowOverwrite: config['allowOverwrite'] == true,
        fence: 'gymia-sheet-edit',
        requireExpected: true,
      );
      final live = await service.connection();
      if (live == null ||
          live['subject'] != config['subject'] ||
          live['id'] != config['id'] ||
          live['sheetId'] != config['sheetId'] ||
          live['title'] != config['title'] ||
          live['allowOverwrite'] != config['allowOverwrite']) {
        throw const ValidationException(
          'La conexión cambió. No se modificó la hoja.',
        );
      }
      final editId = 'edit/${sha256.convert(utf8.encode(operationKey))}';
      final version = jsonEncode({
        'request': operationKey,
        'writes': plan.writes.map((cell) => cell.toJson()).toList(),
      });
      final result = await service.write(
        sheet,
        editId,
        snapshot,
        plan,
        version,
        allowOverwrite: config['allowOverwrite'] == true,
      );
      if (result['synced'] != true) {
        throw const ValidationException(
          'Google no confirmó la edición. Comprueba la hoja antes de reintentar.',
        );
      }
      String suffix = '';
      try {
        final after = await service.snapshot(sheet);
        final entered = after['entered'] as Map;
        final verified = plan.writes.every((cell) {
          final value = entered['${cell.row}:${cell.column}'] as Map?;
          if (cell.value is bool) return value?['boolValue'] == cell.value;
          if (cell.value is num) {
            return value?['numberValue'] is num &&
                (value!['numberValue'] as num).toDouble() ==
                    (cell.value as num).toDouble();
          }
          return value?['stringValue'] == cell.value;
        });
        await cache(sheet, after);
        if (!verified) {
          suffix =
              'Google aceptó la operación, pero la lectura posterior no confirmó todas las celdas. Comprueba la hoja antes de reintentar.';
        }
      } catch (_) {
        suffix =
            'Google aceptó la operación, pero no se pudo verificar la lectura posterior. Comprueba la hoja antes de reintentar.';
      }
      return suffix.isEmpty
          ? 'Google Sheets confirmó la edición en «${sheet.name} / ${sheet.title}»: ${plan.summary} (${plan.writes.map((cell) => cell.address).join(', ')}).'
          : suffix;
    } finally {
      busy = false;
    }
  }

  Future<List<Map<String, dynamic>>> jobs() async {
    service.checkProfile();
    final raw = await SheetSyncService.storage.read(key: queueKey);
    return raw == null
        ? []
        : [
          for (final j in jsonDecode(raw) as List)
            Map<String, dynamic>.from(j as Map),
        ];
  }

  Future<void> saveJobs(List<Map<String, dynamic>> jobs) async {
    service.checkProfile();
    await SheetSyncService.storage.write(
      key: queueKey,
      value: jsonEncode(jobs),
    );
  }

  Future<void> enqueue(
    String workoutId,
    Map<String, dynamic> config, {
    String guidance = '',
    bool automatic = false,
  }) async {
    final list = await jobs();
    if (list.any(
      (j) =>
          j['workoutId'] == workoutId &&
          j['id'] == config['id'] &&
          j['sheetId'] == config['sheetId'] &&
          j['subject'] == config['subject'],
    )) {
      return;
    }
    await saveJobs([
      ...list,
      {
        ...config,
        'workoutId': workoutId,
        'guidance': guidance,
        'automaticJob': automatic,
        'status': 'pending',
        'attempts': 0,
      },
    ]);
  }

  Future<void> enqueueCompleted() async {
    final config = await service.connection();
    if (config == null || config['automatic'] != true) return;
    final after = DateTime.parse(config['automaticAfter'] as String);
    for (final w in controller.history) {
      if ((w.finishedRecordedAt ?? w.finishedAt!).isBefore(after)) continue;
      await enqueue(w.id, config, automatic: true);
    }
  }

  Future<String?> synchronize(
    String workoutId, {
    String guidance = '',
    bool retry = false,
  }) async {
    if (busy) {
      throw const ValidationException(
        'Hay otra operación de Google en curso. El envío se conserva pendiente.',
      );
    }
    busy = true;
    try {
      final config = await connect();
      if (config == null) {
        throw const ValidationException(
          'Conecta y elige tu hoja una vez desde Enviar a Google Sheets.',
        );
      }
      if (config['automatic'] != true && !retry) {
        throw const ValidationException(
          'El envío desde el chat está pausado. Actívalo en la conexión de Google Sheets.',
        );
      }
      await enqueue(workoutId, config, guidance: guidance);
      final queued =
          (await jobs())
              .where(
                (j) =>
                    j['workoutId'] == workoutId &&
                    j['id'] == config['id'] &&
                    j['sheetId'] == config['sheetId'] &&
                    j['subject'] == config['subject'],
              )
              .firstOrNull;
      final originalGuidance = queued?['guidance'] as String? ?? '';
      return await perform(
        workoutId,
        config,
        originalGuidance.isEmpty || originalGuidance == guidance
            ? guidance
            : '$originalGuidance\nConversación posterior: $guidance',
      );
    } catch (e) {
      await recordFailure(workoutId, e);
      rethrow;
    } finally {
      busy = false;
    }
  }

  Future<String> perform(
    String workoutId,
    Map<String, dynamic> config,
    String guidance,
  ) async {
    // Read directly from the repository: a pending/restored UI cannot supply a stale source.
    final workouts = await controller.repository.load();
    final workout =
        workouts.where((w) => w.id == workoutId && !w.isActive).firstOrNull;
    if (workout == null) {
      throw const ValidationException(
        'La sesión no está finalizada o no está en este perfil.',
      );
    }
    final activities =
        await controller.activityRepository?.loadActivities() ?? [];
    final source = sheetWorkoutSource(workout, activities);
    final version = jsonEncode(source);
    final sheet = target(config);
    if (service.identity!.subject != config['subject']) {
      throw const ValidationException(
        'La cuenta cambió. No se redirigirá el envío pendiente.',
      );
    }
    var already = await service.isSynced(sheet, workoutId, version);
    if (!already) {
      final snapshot = await service.snapshot(sheet);
      checkTarget(config, snapshot);
      final plan = await SheetPlanService(
        profileId: controller.profileId,
        client: client,
      ).prepare(
        sheet: sheet,
        source: source,
        snapshot: snapshot,
        allowOverwrite: config['allowOverwrite'] == true,
        instructions: config['instructions'] as String? ?? '',
        layout: config['layout'] as String? ?? '',
        conversation: guidance,
      );
      final current =
          (await controller.repository.load())
              .where((w) => w.id == workoutId && !w.isActive)
              .firstOrNull;
      final currentActivities =
          await controller.activityRepository?.loadActivities() ?? [];
      if (current == null ||
          jsonEncode(sheetWorkoutSource(current, currentActivities)) !=
              version) {
        throw const ValidationException(
          'El entrenamiento cambió mientras se preparaba el envío. Se conserva pendiente.',
        );
      }
      // The connection may have been paused or changed while the provider answered.
      final live = await service.connection();
      if (live == null ||
          live['subject'] != config['subject'] ||
          live['id'] != config['id'] ||
          live['sheetId'] != config['sheetId'] ||
          live['automatic'] != true ||
          live['allowOverwrite'] != config['allowOverwrite'] ||
          live['instructions'] != config['instructions'] ||
          live['title'] != config['title']) {
        throw const ValidationException(
          'La conexión cambió o está pausada. El envío conserva su destino original.',
        );
      }
      final result = await service.write(
        sheet,
        workoutId,
        snapshot,
        plan,
        version,
        allowOverwrite: config['allowOverwrite'] == true,
      );
      if (result['synced'] != true) {
        throw const ValidationException(
          'Google no confirmó el recibo; el envío se conserva pendiente.',
        );
      }
      // Keep learned structure only on the same still-active connection.
      await service.rememberLayout(config, plan.layout);
    }
    final list = await jobs();
    for (final job in list) {
      if (job['workoutId'] == workoutId &&
          job['id'] == config['id'] &&
          job['sheetId'] == config['sheetId'] &&
          job['subject'] == config['subject']) {
        job['status'] = 'sent';
        job['lastError'] = null;
        job.remove('guidance');
        job.remove('instructions');
        job.remove('layout');
      }
    }
    await saveJobs(list);
    String suffix = '';
    try {
      await cache(sheet, await service.snapshot(sheet));
    } catch (_) {
      suffix =
          ' La copia del chat no pudo refrescarse; el recibo del envío sí está confirmado.';
    }
    return 'Google Sheets confirmado: «${workout.name}» enviado a «${sheet.name} / ${sheet.title}». ${already ? 'El recibo existente evita duplicarlo.' : 'Recibo comprobado.'}$suffix';
  }

  Future<void> recordFailure(String id, Object error) async {
    final list = await jobs();
    for (final j in list.where(
      (j) => j['workoutId'] == id && j['status'] != 'sent',
    )) {
      final question = error is SheetClarification;
      final permanent =
          error is ValidationException ||
          error is PlatformException &&
              {
                'GOOGLE_RECONNECT_REQUIRED',
                'GOOGLE_FORBIDDEN',
                'GOOGLE_NOT_FOUND',
                'GOOGLE_ACCOUNT_MISMATCH',
                'GOOGLE_SYNC',
              }.contains(error.code);
      j['status'] =
          question
              ? 'question'
              : permanent
              ? 'attention'
              : 'pending';
      j['lastError'] = question ? error.question : error.toString();
      final n = (j['attempts'] as int? ?? 0) + 1;
      j['attempts'] = n;
      j['retryAfter'] =
          DateTime.now()
              .add(
                Duration(seconds: (30 * (1 << n.clamp(0, 7))).clamp(60, 3600)),
              )
              .toIso8601String();
    }
    await saveJobs(list);
  }
}
