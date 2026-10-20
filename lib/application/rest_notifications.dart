import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'workout_controller.dart';

class RestNotificationController extends ChangeNotifier {
  RestNotificationController(this.controller) {
    controller.addListener(sync);
  }
  final WorkoutController controller;
  static const channel = MethodChannel('com.gymia.app/rest-notifications');
  bool supported = false, enabled = false, exact = false, busy = false;
  String? error;
  bool _disposed = false;
  String? _scheduled;
  Future<void> _tail = Future.value();

  Future<void> initialize() async {
    try {
      final status = await channel.invokeMapMethod<String, dynamic>('status');
      if (_disposed) return;
      supported = status != null;
      enabled = status?['enabled'] == true && status?['granted'] == true;
      exact = status?['exact'] == true;
      _scheduled = null;
      sync();
      notifyListeners();
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
            'Permite las notificaciones de GymIA en los ajustes de Android para recibir avisos.';
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

  void sync() {
    if (_disposed || !supported || !controller.loaded) return;
    final activity =
        controller.focus?.running != null
            ? null
            : controller.activities
                .where(
                  (a) =>
                      a.restEndsAt != null &&
                      a.restEndsAt!.isAfter(controller.now()),
                )
                .firstOrNull;
    final end = activity?.restEndsAt;
    final spec =
        enabled && end != null
            ? '${activity!.id}:${end.millisecondsSinceEpoch}'
            : 'cancel';
    if (_scheduled == spec) return;
    _scheduled = spec;
    _tail = _tail.catchError((_) {}).then((_) async {
      if (_disposed || _scheduled != spec) return;
      try {
        if (spec == 'cancel') {
          await channel.invokeMethod<void>('cancel');
        } else {
          await channel.invokeMethod<void>('schedule', {
            'id': activity!.id,
            'end': end!.millisecondsSinceEpoch,
            'name': activity.definition.name,
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
    controller.removeListener(sync);
    super.dispose();
  }
}
