# Implementation Plan: TrackIA — espacios y actividades adaptables

**Branch**: identificador lógico `003-trackia-platform`, sin cambio de rama | **Date**: 2026-10-20 | **Spec**: [spec.md](spec.md)

**Input**: [Especificación de producto](spec.md). Entrega actual: SDD, sin cambios de runtime.

## Summary

Evolucionar GymIA a TrackIA con una conversación de IA como centro, espacios,
personalidad configurable y actividades compuestas de registros, etapas, tiempo y
ciclos opcionales. Mantener gimnasio como experiencia compatible. Extraer un motor
determinista, un compositor de contexto y repositorios con ámbito explícito. Añadir
bienvenida opcional, continuidad local ante fallos de conexión y destinos múltiples.

Spec Kit: investigación de fase 0 y diseño de fase 1 documentados; desglose de fase 2
en [tasks.md](tasks.md). La bienvenida se adelantó como incremento independiente
con contenido limitado a las capacidades presentes; el resto continúa pendiente.

## Technical Context

**Language/Version**: Dart 3.7.2 / Flutter 3.29.3 de la herramienta local; Kotlin para puentes Android existentes.

**Primary Dependencies**: sqflite, flutter_secure_storage, uuid, file_picker, image_picker,
flutter_markdown_plus, speech_to_text; conservar clientes de IA y puente Google existentes.
No nuevo backend ni dependencia de audio para la primera entrega.

**Storage**: SQLite v4 actual por perfil; migraciones aditivas versionadas para espacios,
planes, ejecuciones, observaciones y jobs. Secretos en almacenamiento seguro. Preferencia
de bienvenida por dispositivo, separada de perfiles, como la apariencia.

**Testing**: flutter_test, integration_test, sqflite_common_ffi y pruebas Kotlin existentes.
La base tiene evidencia histórica de 164 pruebas Flutter y 9 pruebas nativas de la última
entrega; no se han vuelto a ejecutar por este cambio exclusivamente documental.

**Target Platform**: Android API 23+; referencia de aceptación inicial: emulador Android
API 35 ARM64 con configuración registrada en el informe de cada ejecución. iOS mantiene
código compartido pero exige validación propia antes de anunciarse como entrega.

**Project Type**: aplicación móvil Flutter local con adaptadores de proveedores externos.

**Performance Goals**: SC-006 (95/100 acciones locales <300 ms) y SC-007 (reloj visible >=1 Hz).
Medir en el emulador de referencia sin inferir rendimiento universal ni avisos exactos del SO.

**Constraints**: sin red/IA para controles locales; una ejecución activa por perfil en la
primera entrega; no migrar identidad Android/firma, rutas existentes ni clientes OAuth al
cambiar la marca visible. Límites de configuración en [data-model.md](data-model.md).

**Scale/Scope**: varios espacios por perfil, un destino efectivo por operación, planes
lineales iniciales; ramas, carriles paralelos, audio y conectores son incrementos posteriores.

## Constitution Check

Comprobación antes de investigar y después del diseño: los ocho principios pasan como
restricciones del plan, no como certificación del runtime futuro.

| Principio | Antes | Después / evidencia de diseño |
|---|---|---|
| I Actividades abiertas | Pasa | Campos y capacidades, sin taxonomía obligatoria; US1/US8. |
| II Ejecución determinista | Pasa | Comandos tipados, ejecución local y transición transaccional; contrato del motor. |
| III Ámbitos | Pasa | ProfileScope + SpaceScope, snapshots de peticiones y destinos. |
| IV Originales | Pasa | Planes inmutables por revisión, observación original, adaptación legacy y copias. |
| V Permisos | Pasa | Personalidad no concede permisos; etiquetas ligadas a IDs semánticos. |
| VI Efectos verificables | Pasa | Outbox local propuesta, destino capturado, recibos y reconciliación. |
| VII Interfaz | Pasa | Dos temas, navegación, lectores de pantalla y bienvenida no intrusiva. |
| VIII Evidencia | Pasa | Tareas sin marcar, trazabilidad y matriz de pruebas futuras. |

Gobernanza: [constitución](../../.specify/memory/constitution.md). Sin excepciones a sus principios.

## Project Structure

### Documentation (this feature)

```text
specs/003-trackia-platform/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── traceability.md
├── checklists/requirements.md
├── contracts/
│   ├── assistant-proposals.md
│   ├── execution.md
│   ├── spaces-and-destinations.md
│   └── welcome.md
└── tasks.md
```

### Source Code (repository root)

Rutas propuestas de implementación; su presencia en este árbol no significa que existan.
Los nombres exactos de archivos por tarea están fijados en tasks.md dentro de estos módulos.

```text
lib/
├── domain/           # space, persona, activity_definition, activity_plan, activity_run,
│                    # observation, destination_binding, sync_job, welcome_preferences
├── application/      # activity_engine, activity_commands, assistant_context,
│                    # space_controller, recovery_service, destination_resolver,
│                    # sync_dispatcher, welcome_coordinator, capability_registry
├── data/             # migrations, space_repository, activity_run_repository,
│                    # observation_repository, destination_repository, sync_job_repository,
│                    # welcome_settings_store, legacy_activity_adapter
├── ui/               # espacios, personalidad, editor de actividad, controles y bienvenida
└── main.dart         # composición; conservar rutas y proveedores existentes
android/app/src/main/ # puentes y avisos existentes, identidad del paquete conservada
android/app/src/test/ # verificaciones del puente existentes
 test/               # unidades, contratos, widgets, migración, fallos
 integration_test/   # recorridos Android y datos persistentes
 docs/               # evidencia de cada entrega, sin secretos
```

**Structure Decision**: ampliar el proyecto Flutter existente por módulos pequeños;
no un framework de plugins, nuevo servicio remoto ni una aplicación paralela. Reutilizar
repositorios, importación y adaptadores compatibles mediante capas explícitas.

## Delivery increments

Orden de referencia: base compatible → US1 centrada en IA → US2 → US3 → US4 → US6 → US7 → US9 → US5 → US8.
La bienvenida puede adelantarse tras la base y mostrar solo las funciones presentes.
Las historias P1 preceden al multidestino P2 y capacidades avanzadas P3.

1. **Base y compatibilidad**: fixtures, ámbitos, migraciones reversibles, protocolo y motor
   transaccional. Preparar espacio por defecto sin reasignar datos entre perfiles.
2. **Actividad abierta y espacios**: propuestas del asistente como recorrido principal,
   con configuración manual y guardado local de respaldo; personalidad y contexto
   extraído del widget. Historial de gimnasio mediante adaptador, sin forzar nuevos workouts.
3. **Ejecución y registros**: etapas lineales, métricas/observaciones, recuperación, avisos
   y protección frente a respuestas tardías; validar cuatro tipos de actividad.
4. **Actualización y bienvenida**: marca visible preservando paquete/firma, copias y vista
   previa de migración; slides que describan únicamente lo que incluya esa entrega.
5. **Multidestino**: registro de conexiones, selección explícita y outbox/recibos persistidos.
   Mantener lectura fresca y creación de hoja autorizada del adaptador existente.
6. **Expansión**: capacidad de ramas/carriles/audio especificada y probada individualmente.
   US8 inicialmente entrega validación y alternativa compatible; no implementa todos esos motores.

Cada incremento termina con su prueba independiente de quickstart y evidencia. La
implementación solo comienza en un trabajo posterior que la incluya en su alcance.

## Complexity Tracking

Sin violaciones de constitución. La separación definición/plan/ejecución y el job local
son necesarios para conservar revisiones y recuperar fallos; no se añaden infraestructura
distribuida ni un constructor visual general. Investigación y alternativas: [research.md](research.md).
