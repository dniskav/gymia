# Sprint 2 · Entrenar con tu rutina

## Objetivo y entregable
APK Android 0.2.0, actualizable sobre 0.1.0 con el mismo paquete y firma.
Compartir interfaz, reglas y SQLite con el proyecto iOS, aún sin validar en iPhone.

## Historias
- S2-01: crear una rutina con nombre y ejercicios; configurar series previstas,
  rango de repeticiones y descanso por ejercicio.
- S2-02: editar, reordenar y eliminar rutinas con confirmación; salir del editor
  con cambios pendientes exige confirmar su descarte.
- S2-03: empezar una sesión desde una rutina. Los objetivos se copian como una
  instantánea independiente; no se registran series hasta pulsar Guardar.
- S2-04: mostrar pesos y repeticiones de la última sesión completada que contiene
  series del mismo ejercicio. Ignorar mayúsculas y espacios repetidos; no unir
  automáticamente nombres distintos ni variantes de ejercicios.
- S2-05: temporizador configurable, iniciar, pausar, continuar y reiniciar.
- S2-06: conservar historial y sesión activa al actualizar desde Sprint 1.

## Reglas y límites
- Una sola sesión activa. Intentar entrenar otra rutina lleva a la sesión existente.
- 1–50 ejercicios por rutina; 1–30 series previstas; 1–999 repeticiones.
- Descansos de 5 a 1800 segundos, por defecto 90.
- Se puede registrar más o menos series que las previstas. El objetivo es una guía.
- Cambiar o eliminar una rutina no modifica las sesiones ya iniciadas/finalizadas.
- Última vez usa sesiones anteriores al inicio del entrenamiento actual. Si una
  sesión más reciente tiene el ejercicio sin series, busca la anterior con datos.
- Añadir serie precarga la última serie de esta sesión o la primera de la sesión
  anterior; no la guarda automáticamente.
- El descanso se inicia explícitamente; «Descansar Ns» usa el tiempo del ejercicio.
- El contador persiste su fecha límite en SQLite. Recupera el tiempo restante al
  cambiar de pantalla, suspender o volver a abrir la app; pausar conserva milisegundos.
- El aviso visual/sonoro se produce con la pantalla de sesión abierta. No se
  programan notificaciones de sistema ni alarmas con la app cerrada en este sprint.
- No hay sincronización, IA ni copia externa todavía.

## Migración
Esquema SQLite 1 → 2, aditivo y transaccional. Conserva IDs y filas originales.
Se añaden rutinas, objetivos copiados y estado de descanso. Sin borrado/recreación
del histórico. La versión debug usa paquete `.dev` para no reemplazar la APK personal.

## Prueba de aceptación en el móvil
1. Instalar 0.2.0 encima de 0.1.0, sin desinstalar. Comprobar el historial anterior.
2. En Rutinas, crear «Pierna A»: Sentadilla (3 series, 8–12 reps, 90s) y Prensa
   (3 series, 10–15 reps, 120s). Guardar.
3. Editar la rutina: mover Prensa arriba, cambiar un objetivo y guardar. Reabrir
   el editor y comprobar que los cambios se conservan.
4. Pulsar Entrenar. Ver el orden y objetivos; el contador de series debe estar en 0.
5. Registrar una serie real. Iniciar descanso, pausar, continuar y reiniciar.
6. Ajustar a 5 segundos para comprobar el final. Probar también salir y volver
   durante un descanso de 90 segundos: debe descontar el tiempo transcurrido.
7. Finalizar y volver a entrenar la misma rutina. Comprobar «Última vez».
8. Volver a Rutinas y eliminarla con confirmación. La sesión activa y el historial
   deben conservar sus ejercicios y datos.
9. Repetir las acciones principales en modo avión.

## Verificación de la entrega 0.2.0
- Análisis estático sin incidencias y `git diff --check` correcto.
- 22 pruebas unitarias/de widget superadas. Incluyen migración del esquema v1,
  rutinas persistentes, orden, objetivos sin series realizadas, protección de las
  sesiones, búsquedas de última sesión y pausa/reanudación del contador con reloj controlado.
- 2 recorridos de integración superados en Android 15/API 35: el recorrido original
  del Sprint 1 y crear/editar/reordenar rutina, entrenar, gestionar descanso, volver a
  entrenar con valores anteriores y eliminar rutina conservando sesión e historial.
- Actualización real `adb install -r` de la APK 0.1.0 a 0.2.0 en modo avión:
  sesión finalizada Sentadilla 40 kg × 8 y sesión activa Remo 20 kg × 12 conservadas.
  La sesión migrada pudo finalizarse. Una nueva rutina de Sentadilla mostró los
  valores anteriores del Sprint 1, con 0 series realizadas y objetivos separados.
- Firma verificada y certificado idéntico a 0.1.0. VersionCode 2, paquete `com.gymia.app`.
- Contador de la APK release recuperado tras cierre forzado: pasó de 1:28 antes del
  cierre a 1:21 al volver, sin reiniciarse ni detenerse durante la ausencia.
- APK release sin permiso de Internet. Capturas reales en `releases/screenshots/sprint-2/`.
- APK: `releases/gymia-0.2.0.apk`; checksum en `releases/gymia-0.2.0.sha256`.

## Estado
Lista para aceptación del usuario en su teléfono. iOS aún no compilado ni validado.
