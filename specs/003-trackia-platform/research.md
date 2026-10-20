# Investigación y decisiones — TrackIA

Fecha: 2026-10-20. Documentación de diseño; no certifica funciones futuras.
La base contrastada es GymIA 0.3.22+25. Se revisaron código, notas de entrega y una
revisión de arquitectura independiente de solo lectura durante el flujo Spec Kit.

## Base existente y diferencias con el objetivo

| Área | Evidencia en el repositorio | Estado y diferencia |
|---|---|---|
| Identidad | `lib/data/profile_store.dart`, `lib/domain/user_profile.dart` | Perfil local o Google; no hay espacios dentro de cada perfil. |
| Persistencia | `lib/data/sqlite_workout_repository.dart`, `lib/data/sqlite_activity_repository.dart` | SQLite v4, BD por perfil, índices de ejecución activa. No copiar una BD por espacio. |
| Actividad | `lib/domain/activity.dart`, `lib/domain/workout.dart` | FocusActivity tiene campos adaptables pero exige workoutId; Workout/Exercise/Set conserva fuerza. No hay observaciones autónomas generales. |
| Tiempo | `lib/ui/activity_focus.dart`, `lib/domain/rest_timer.dart` | Tramos manuales y descanso persistido. No existe motor general de etapas, ciclos o cuenta atrás de actividad. |
| Asistente | `lib/ui/assistant_chat.dart`, `lib/data/ai_settings_store.dart` | contextForAi incluye instrucciones de gimnasio; configuración, chat y archivos por perfil, sin personalidad por espacio. |
| Disponibilidad | `lib/application/ai_availability.dart`, `lib/ui/session_control.dart` | Nuevas actividades sujetas a disponibilidad del modelo; FR-005 requiere separar los controles locales de esa condición. |
| Hojas | `lib/application/sheet_automation.dart`, `lib/data/sheet_sync_service.dart` | Una conexión/contexto por perfil, lecturas frescas, recibos y pendientes cifrados. No hay registro multidestino ni outbox transaccional SQLite. |
| Copias | `lib/domain/transfer.dart`, `lib/domain/transfer_repository.dart` | gymia-backup v3, tablas explícitas, límite de entrada 20 MB. No es copia completa de chats/secretos. |
| Apariencia | `lib/data/theme_settings.dart`, `lib/ui/appearance.dart` | Claro/oscuro/sistema, preferencia de dispositivo. No hay bienvenida por diapositivas. |
| Plataforma | `pubspec.yaml`, `android/app/build.gradle.kts` | Flutter/Dart, Android minSdk 23, paquete com.gymia.app; preservar identidad y firma. |

La evidencia histórica de [perfiles](../../docs/0.3.15-PROFILES.md),
[archivos de chat](../../docs/0.3.18-CHAT-ARCHIVES.md),
[Sheets](../../docs/0.3.20-AUTOMATIC-SHEETS.md),
[ChatGPT](../../docs/0.3.21-CHATGPT.md) y
[temas](../../docs/0.3.22-APPEARANCE.md) sigue siendo válida para su entrega.
Las pruebas controladas de OAuth/Sheets no sustituyen una autorización y operación
real con cuentas elegibles. No se afirma compatibilidad iOS verificada.

## Decisiones de diseño

| Decisión | Razón | Alternativa descartada |
|---|---|---|
| Espacios dentro del perfil existente | Conserva identidad y permite varias intenciones por persona. | Perfil o BD nuevos por cada personalidad: mezcla identidad con preferencias. |
| Definición editable, plan aceptado y ejecución separados | Preserva significado de datos y evita modificar un reloj en marcha al editar una plantilla. | Un JSON mutable compartido entre plantilla e histórico. |
| Motor puro de comandos y eventos persistidos | Transiciones, recuperación y doble toque verificables sin IA. | Hacer que el modelo controle ticks o decidir de nuevo cada fase. |
| Primera entrega lineal, una ejecución activa por perfil | Incremento comprobable con la persistencia actual; cambiar de espacio no la detiene. | Paralelismo y ramas completos antes de validar el recorrido básico. |
| Campos con IDs, unidades y originales | La etiqueta visible puede cambiar; la identidad de un dato no. | Columnas identificadas solo por nombre o todo reducido a peso/repeticiones. |
| Registro de conexiones y trabajos con destino capturado | Varios espacios pueden usar recursos distintos o compartir explícitamente uno. | Leer siempre la conexión que esté seleccionada al reintentar. |
| Compositor de contexto extraído del widget | Permite probar aislamiento, personalidad, capacidades y respuestas tardías. | Añadir más condiciones al prompt de gimnasio dentro de assistant_chat.dart. |
| SQLite con documentos versionados y tablas de eventos/jobs | Aprovecha infraestructura existente y transacciones locales. | Migración a NoSQL sin necesidad demostrada. |
| Preparación automática validada, inicio explícito | Respeta el flujo actual sin un segundo botón Preparar innecesario. | Pedir otra confirmación para repetir una intención clara. |
| Bienvenida de dispositivo, revisitable | Explica el producto sin exigir cuenta ni repetirse si se desactiva. | Guardar la supresión por cuenta, o reactivarla en cada actualización. |
| Capacidades avanzadas declaradas por versión | Admite crecimiento sin presentar un temporizador como audio guiado real. | Catálogo cerrado de casos o promesas de conectores ausentes. |

## Bienvenida incorporada al alcance

Propuesta de cinco diapositivas: propósito, espacios/personalidad, crear actividad,
controles y registros, datos opcionales. Cada pantalla usa el catálogo de capacidades
instaladas: no anuncia como disponible una etapa del plan que aún no se haya entregado.
La supresión se guarda al pulsar Omitir o Empezar, no al marcar la casilla. Abrir desde
ajustes no modifica la supresión. Actividad activa o archivo entrante posponen la
presentación automática; el contenido solicitado conserva prioridad.

## Riesgos y respuesta prevista

- Migraciones: respaldo y comparación de originales/IDs antes de habilitar el nuevo esquema.
- Fugas: claves de ámbito en chats, archivos, memorias, caché, jobs y respuestas tardías.
- Recuperación temporal: reloj monotónico mientras el proceso vive, persistencia duradera;
  reinicio/cambio de hora que impida comprobar el tiempo obliga a mostrar incertidumbre.
- Efectos externos: recibo y reconciliación; no prometer transacción distribuida o bloqueo
  de otros editores de Google Sheets.
- Exceso de generalidad: cuatro recorridos distintos antes de añadir ramas o simultaneidad.
- Bienvenida intrusiva: omisión accesible, supresión persistente y reapertura voluntaria.

No quedan decisiones de producto bloqueantes para preparar el plan. Límites técnicos
iniciales y fases son propuestas explícitas, revisables antes de implementar.
