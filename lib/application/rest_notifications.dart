import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'workout_controller.dart';

class RestNotificationController extends ChangeNotifier {
  RestNotificationController(this.controller, {this.beforeStart}) {
    controller.addListener(sync);
  }
  final WorkoutController controller;
  final Future<void> Function()? beforeStart;
  static const channel = MethodChannel('com.gymia.app/rest-notifications');
  bool supported = false, enabled = false, exact = false, busy = false;
  String? error;
  String? testStatus;
  bool _disposed = false;
  bool _handlingAction = false;
  String? _scheduled;
  Future<void> _tail = Future.value();

  Future<void> initialize() async {
    try {
      channel.setMethodCallHandler((call) async {
        if (call.method == 'actionAvailable') await handlePendingAction();
      });
      final status = await channel.invokeMapMethod<String, dynamic>('status');
      if (_disposed) return;
      supported = status != null;
      enabled = status?['enabled'] == true && status?['granted'] == true;
      exact = status?['exact'] == true;
      _scheduled = null;
      sync();
      notifyListeners();
      await handlePendingAction();
    } on MissingPluginException {
      /* Android bridge; no fake iOS support. */
    } catch (_) {
      if (!_disposed) {
        error = 'No se pudieron comprobar los avisos.';
        notifyListeners();
      }
    }
  }

  Future<void> toggle(bool value) async {
    if (busy || !supported) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final granted = await channel.invokeMethod<bool>('enable', {
        'enabled': value,
      });
      if (_disposed) return;
      enabled = granted == true;
      if (value && !enabled) {
        error =
            'Permite las notificaciones de TrackIA en los ajustes de Android para recibir avisos.';
      }
      _scheduled = null;
      sync();
    } catch (_) {
      error = 'No se pudo cambiar el aviso. Vuelve a intentarlo.';
    } finally {
      if (!_disposed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> allowExact() => channel.invokeMethod<void>('exactSettings');

  Future<void> testNotification() async {
    if (busy || !supported) return;
    busy = true;
    testStatus = null;
    error = null;
    notifyListeners();
    try {
      final posted = await channel.invokeMethod<bool>('test');
      if (_disposed) return;
      testStatus =
          posted == true
              ? 'Aviso enviado a Android. Comprueba el móvil y, si usas reloj, sus ajustes de notificaciones.'
              : 'Activa los avisos y concede el permiso de notificaciones en Android antes de probar.';
    } catch (_) {
      if (!_disposed) error = 'No se pudo enviar el aviso de prueba.';
    } finally {
      if (!_disposed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> handlePendingAction() async {
    if (_disposed || _handlingAction) return;
    _handlingAction = true;
    try {
      final action = await channel.invokeMapMethod<String, dynamic>(
        'pendingAction',
      );
      if (action == null || _disposed) return;
      final id = action['id'] as String?;
      final end = (action['end'] as num?)?.toInt();
      final kind = action['kind'] as String?;
      final revision = (action['revision'] as num?)?.toInt();
      final profileId = action['profileId'] as String?;
      final requestedAt = (action['requestedAt'] as num?)?.toInt();
      if (id == null ||
          end == null ||
          kind == null ||
          revision == null ||
          profileId == null ||
          requestedAt == null) {
        return;
      }
      for (var attempt = 0; controller.busy && attempt < 20; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      if (_disposed || controller.busy) return;
      await controller.refresh();
      if (_disposed) return;
      final activity = controller.focus;
      final now = controller.now().millisecondsSinceEpoch;
      bool matchesReadyActivity() {
        final current = controller.focus;
        if (current?.id != id) return false;
        if (kind == 'running') {
          return revision > 0 &&
              current?.running?.startedAt.millisecondsSinceEpoch == revision;
        }
        if (current?.running != null) return false;
        if (kind == 'rest') {
          return end > 0 &&
              current?.restEndsAt?.millisecondsSinceEpoch == end &&
              requestedAt >= end;
        }
        if (kind == 'prepared') {
          return revision > 0 &&
              current?.createdAt.millisecondsSinceEpoch == revision &&
              current?.intervals.isEmpty == true &&
              current?.restEndsAt == null;
        }
        return false;
      }

      var success =
          profileId == controller.profileId &&
          activity?.id == id &&
          requestedAt > 0 &&
          now - requestedAt < const Duration(hours: 1).inMilliseconds &&
          (kind == 'running'
              ? activity!.intervals.any(
                (interval) =>
                    interval.startedAt.millisecondsSinceEpoch == revision &&
                    interval.endedAt != null &&
                    interval.endedAt!.millisecondsSinceEpoch >=
                        requestedAt - 2000,
              )
              : activity?.running != null &&
                  activity!.running!.startedAt.millisecondsSinceEpoch >=
                      requestedAt - 2000);
      if (!success &&
          profileId == controller.profileId &&
          matchesReadyActivity() &&
          now - requestedAt < const Duration(hours: 1).inMilliseconds) {
        try {
          await beforeStart?.call();
          await controller.refresh();
          if (!_disposed &&
              controller.profileId == profileId &&
              matchesReadyActivity()) {
            success = await controller.run(
              () =>
                  kind == 'running'
                      ? controller.activityRepository!.stopInterval(id)
                      : controller.activityRepository!.startInterval(id),
            );
          }
        } catch (_) {
          success = false;
        }
      }
      await channel.invokeMethod<bool>('completeAction', {
        'id': id,
        'end': end,
        'profileId': profileId,
        'kind': kind,
        'revision': revision,
        'success': success,
      });
      if (!success && !_disposed) {
        error = 'El aviso era de otra actividad o ya no estaba vigente.';
        notifyListeners();
      }
    } on MissingPluginException {
      // The bridge is available only on Android.
    } catch (_) {
      if (!_disposed) {
        error = 'No se pudo ejecutar la acción del aviso.';
        notifyListeners();
      }
    } finally {
      _handlingAction = false;
    }
  }

  void sync() {
    if (_disposed || !supported || !controller.loaded) return;
    final running = controller.focus?.running;
    final runningActivity = running == null ? null : controller.focus;
    final restActivity = controller.focus?.running == null &&
            controller.focus?.restEndsAt?.isAfter(controller.now()) == true
        ? controller.focus
        : null;
    final end = restActivity?.restEndsAt;
    final prepared = controller.focus;
    final showPrepared =
        prepared != null &&
        prepared.running == null &&
        prepared.intervals.isEmpty &&
        prepared.restEndsAt == null;
    final spec =
        enabled && end != null
            ? 'rest:${restActivity!.id}:${end.millisecondsSinceEpoch}'
            : enabled && runningActivity != null
            ? 'running:${runningActivity.id}:${running!.startedAt.millisecondsSinceEpoch}'
            : enabled && showPrepared
            ? 'prepared:${prepared.id}:${prepared.createdAt.millisecondsSinceEpoch}'
            : 'cancel';
    if (_scheduled == spec) return;
    _scheduled = spec;
    _tail = _tail.catchError((_) {}).then((_) async {
      if (_disposed || _scheduled != spec) return;
      try {
        if (spec == 'cancel') {
          await channel.invokeMethod<void>('cancel');
        } else if (end != null) {
          await channel.invokeMethod<void>('schedule', {
            'id': restActivity!.id,
            'end': end.millisecondsSinceEpoch,
            'name': restActivity.definition.name,
            'profileId': controller.profileId,
          });
        } else if (runningActivity != null) {
          await channel.invokeMethod<bool>('running', {
            'id': runningActivity.id,
            'revision': running!.startedAt.millisecondsSinceEpoch,
            'name': runningActivity.definition.name,
            'profileId': controller.profileId,
          });
        } else if (showPrepared) {
          await channel.invokeMethod<bool>('prepared', {
            'id': prepared.id,
            'revision': prepared.createdAt.millisecondsSinceEpoch,
            'name': prepared.definition.name,
            'profileId': controller.profileId,
          });
        }
      } catch (_) {
        if (!_disposed) {
          _scheduled = null;
          error = 'No se pudo programar el aviso de descanso.';
          notifyListeners();
        }
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    channel.setMethodCallHandler(null);
    controller.removeListener(sync);
    super.dispose();
  }
}
