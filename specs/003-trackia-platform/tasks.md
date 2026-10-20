# Tasks: TrackIA — espacios y actividades adaptables

**Input**: [plan](plan.md), [spec](spec.md), [research](research.md), [modelo](data-model.md) y [contratos](contracts/assistant-proposals.md).

**Prerequisites**: diseño documental completo; implementación todavía pendiente.

**Tests**: incluidos para verificar los criterios de aceptación, datos y efectos exigidos por la especificación. Escribir primero las pruebas relevantes y comprobar el fallo significativo antes de implementar.

**Organization**: una fase por historia, todas las P1 antes de P2/P3; base compartida primero. La bienvenida US9 se adelantó
como incremento independiente de la base de actividades y usa solo capacidades existentes.

## Format: `[ID] [P?] [Story] Description`

[P] indica archivos independientes dentro de la misma fase, después de sus prerequisitos; no autoriza delegación automática. [USn] corresponde a spec.md. Las casillas marcadas tienen evidencia en `docs/TRACKIA-QA.md`; las pendientes
describen trabajo futuro.

## Path Conventions

`lib/`, `test/`, `integration_test/`, `android/` y `docs/` del proyecto Flutter existente; archivos nuevos son propuestas. Módulos fuente descritos en plan.md.

## Phase 1: Setup (Shared Infrastructure)

**Goal**: Fijar fixtures y evidencia de compatibilidad antes de tocar datos.

**Independent Test / Checkpoint**: Fixtures sanitizados y matriz de pruebas disponibles.

- [ ] T001 Crear fixtures sintéticos de BD v4, copia v3, IDs y originales en `test/fixtures/trackia_legacy_fixtures.dart`; no usar datos personales. (FR-028 SC-004).
- [ ] T002 [P] Registrar identidad Android/firma esperada, claves, versión base y capacidades entregadas en `docs/TRACKIA-BASELINE.md`. (FR-001 FR-030).

## Phase 2: Foundational (Blocking Prerequisites)

**Goal**: Ámbitos, capacidades, persistencia y recorrido local mínimo común.

**Independent Test / Checkpoint**: Backfill por perfil idempotente, contratos locales y original de nota persistidos. Bloquea todas las historias.

- [ ] T003 Definir ámbito en `lib/domain/space.dart`: «IDs de entidad no vacíos e inmutables; toda entidad de espacio requiere profileId y spaceId válidos del mismo propietario.» (FR-006 FR-007).
- [ ] T004 [P] Definir revisiones/campos en `lib/domain/activity_definition.dart`: «name y etiquetas visibles tienen entre 1 y 80 caracteres tras quitar espacios extremos; instructions admite de 0 a 8000 caracteres.» «revision y schemaVersion son enteros positivos; una edición incrementa revision y no modifica snapshots aceptados.» «type pertenece a number, text, boolean, choice o attachment; unit es opcional, pero se conserva si existe; un valor ausente no se convierte en cero.» (FR-002 FR-019).
- [ ] T005 Implementar catálogo versionado y validador de capacidades en `lib/application/capability_registry.dart`; mantener aliases gymia-*. (FR-003 FR-037).
- [ ] T006 Crear migraciones aditivas, respaldo y espacio por defecto por perfil en `lib/data/trackia_migrations.dart`; no trasladar datos a otra cuenta. (FR-025 FR-028).
- [ ] T007 Crear persistencia mínima de notas locales en `lib/data/observation_repository.dart`: «runId en una observación es opcional; original y provenance son obligatorios y las correcciones generan revisión sin sobrescribir el original.» (FR-023 FR-024).
- [ ] T008 Crear núcleo transaccional sin reloj obligatorio en `lib/data/activity_run_repository.dart`: «commandId es único por ejecución y sequence es único y creciente por runId; el cambio de estado, evento y revisión se confirman en una transacción.» (FR-012 FR-021).
- [ ] T009 Probar rollback desde respaldo, IDs y backfill repetido en `test/trackia_migrations_test.dart`. (FR-028 SC-004).

## Phase 3: User Story 1 — Actividad propia (P1, MVP)

**Goal**: Preparar desde la conversación con IA una actividad abierta, validarla e iniciarla
con una acción del usuario; conservar registros locales si se interrumpe la conexión.

**Independent Test / Checkpoint**: El asistente propone una colección sin reloj ni campos
forzados, la app la prepara sin iniciar; una caída de IA permite consultar y guardar notas.

- [ ] T010 [P] [US1] Escribir pruebas del contrato de propuestas y capacidades en `test/activity_proposals_test.dart`. (FR-002 FR-003 FR-004 FR-005 SC-001).
- [ ] T011 [P] [US1] Escribir recuperación de notas y controles locales de una actividad ya preparada ante pérdida del proveedor en `test/manual_activity_test.dart`. (FR-005 SC-001).
- [ ] T012 [US1] Crear editor/duplicación desde cero en `lib/ui/activity_editor.dart`, usando espacio por defecto y núcleo manual de la base. (FR-002 FR-005).
- [ ] T013 [US1] Implementar validador de sobre, revisión y propuesta inline en `lib/application/activity_proposals.dart` según `contracts/assistant-proposals.md`. (FR-003 FR-004 FR-037).
- [ ] T014 [US1] Conectar iniciar/avanzar/finalizar manual y nota en `lib/ui/session_control.dart`; quitar gate de IA de controles locales, preservar gate del asistente. (FR-004 FR-005 FR-018).
- [ ] T015 [US1] Integrar creación/duplicación y preparación inline en `lib/ui/assistant_chat.dart` sin botón Preparar redundante. (FR-002 FR-004).

## Phase 4: User Story 2 — Espacios y personalidad (P1)

**Goal**: Separar contexto y acompañamiento dentro del mismo perfil.

**Independent Test / Checkpoint**: 20 cambios entre dos espacios y dos perfiles; cero filtraciones y compartición acotada visible.

- [ ] T016 [P] [US2] Escribir aislamiento de chat/borrador/archivo/memoria/destino y concesiones en `test/space_isolation_test.dart`. (FR-006 FR-007 FR-010 SC-002).
- [ ] T017 [P] [US2] Escribir pruebas del compositor, celda hostil, personalidad y permisos en `test/assistant_context_test.dart`. (FR-008 FR-009 FR-037).
- [ ] T018 [US2] Implementar revisiones de personalidad sugerida/custom en `lib/domain/persona.dart` y edición en `lib/ui/persona_settings.dart`; aplicar C02/C03 definidos en tareas de base. (FR-008 FR-009).
- [ ] T019 [US2] Implementar repositorio de espacios en `lib/data/space_repository.dart` y controlador en `lib/application/space_controller.dart`; capturar ámbito y recuperar estado por clave. (FR-006 FR-007).
- [ ] T020 [US2] Extraer contextForAi de `lib/ui/assistant_chat.dart` a `lib/application/assistant_context.dart`; separar instrucciones base, personalidad, hechos y fuentes con procedencia. (FR-007 FR-008 FR-009 FR-010 FR-037).
- [ ] T021 [US2] Particionar chats, borradores y adjuntos en `lib/ui/assistant_chat.dart`, y archivos en `lib/data/chat_archive_store.dart`; concesión explícita para consultas interespacio. (FR-007 FR-010).
- [ ] T022 [US2] Añadir selector y edición de espacios en `lib/ui/spaces.dart` y acceso desde `lib/ui/app.dart` en máximo dos acciones. (FR-006 FR-018 SC-009).

## Phase 5: User Story 3 — Tiempo y etapas (P1)

**Goal**: Motor lineal con relojes opcionales, descanso/ciclos y acciones estables.

**Independent Test / Checkpoint**: Ejecutar planes continuo/cíclico/cantidad y verificar pausa, avance y etiquetas sin ambigüedad.

- [ ] T023 [P] [US3] Escribir pruebas de reloj falso, doble disparador y transición única en `test/activity_engine_test.dart`. (FR-012 FR-013 FR-014 FR-015 FR-021 SC-003).
- [ ] T024 [P] [US3] Escribir pruebas de controles por fase, etiquetas contradictorias y avisos en `test/activity_controls_test.dart`. (FR-016 FR-017 FR-018 FR-020).
- [ ] T025 [US3] Definir plan/etapas en `lib/domain/activity_plan.dart`: «Un plan lineal contiene de 1 a 128 etapas; cycles es opcional y, si existe, es entero entre 1 y 1000.» «clockMode pertenece a none, stopwatch o countdown; durationSeconds es obligatorio solo para countdown y es entero entre 1 y 604800.» «advancement pertenece a manual, elapsed o quantity; elapsed requiere countdown y quantity requiere fieldId numérico y goal finito positivo con unidad compatible.» (FR-012 FR-013 FR-014 FR-019).
- [ ] T026 [US3] Definir estado en `lib/domain/activity_run.dart`: «status de ejecución pertenece a ready, running, paused, waiting, completed, cancelled o recovery_needed; solo hay una ejecución activa por perfil.» (FR-019 FR-027).
- [ ] T027 [US3] Implementar comandos tipados en `lib/application/activity_commands.dart` y motor en `lib/application/activity_engine.dart` según `contracts/execution.md`, reutilizando deduplicación transaccional de base. (FR-015 FR-016 FR-021).
- [ ] T028 [US3] Añadir configuración de tiempo/etapas/ciclos en `lib/ui/activity_editor.dart`, con límites explicados y validación antes de aceptar. (FR-012 FR-013 FR-014).
- [ ] T029 [US3] Crear presentación por fase en `lib/ui/activity_controls.dart`, etiquetas adaptables con IDs estables, sonido/vibración/silencio y permisos; integrar con `lib/application/rest_notifications.dart`. (FR-016 FR-017 FR-018 FR-020 FR-030).

## Phase 6: User Story 4 — Registros y observaciones (P1)

**Goal**: Conservar registros heterogéneos dentro o fuera de una ejecución.

**Independent Test / Checkpoint**: Número con unidad, lista, nota y adjunto; corrección conserva original y snapshot tras reinicio.

- [ ] T030 [P] [US4] Escribir pruebas de originales, unidades, ausencia/ceros y revisiones en `test/observation_repository_test.dart`. (FR-022 FR-023 FR-024 SC-004).
- [ ] T031 [US4] Implementar definición de observación y procedencia en `lib/domain/observation.dart`, ampliando repositorio base en `lib/data/observation_repository.dart` con campos C04 y original C10. (FR-022 FR-024).
- [ ] T032 [US4] Implementar editor/historial y adjuntos con ámbito en `lib/ui/observations.dart`; notas independientes no crean Workout. (FR-022 FR-023).
- [ ] T033 [US4] Conectar cantidades verificadas al motor en `lib/application/observation_commands.dart`, conservando plan/objetivo/resultado y deduplicando por registro. (FR-014 FR-024).

## Phase 7: User Story 6 — Recuperación (P1)

**Goal**: Persistencia fiable, ejecución activa visible y respuestas tardías seguras.

**Independent Test / Checkpoint**: 20 ejecuciones con pausa/cierre, cambio de hora/red y respuesta retrasada sin duplicados.

- [ ] T034 [P] [US6] Escribir recuperación, incertidumbre y respuesta obsoleta en `test/activity_recovery_test.dart`. (FR-011 FR-025 FR-026 FR-027 SC-003 SC-007).
- [ ] T035 [US6] Implementar checkpoints monotónicos, reconciliación y recovery_needed en `lib/application/recovery_service.dart`; no inferir realización física del reloj. (FR-025 FR-026).
- [ ] T036 [US6] Aplicar ámbito/revisión capturados y respuesta en chat de origen en `lib/ui/assistant_chat.dart`; rechazar acciones obsoletas sin cambiar espacio visible. (FR-011).
- [ ] T037 [US6] Añadir banner de ejecución activa y conflicto explícito en `lib/ui/app.dart`; cambio de espacio no cancela, no mueve y no inicia otra ejecución. (FR-025 FR-027).
- [ ] T038 [US6] Verificar cierres, avisos/eventos y falta de red en `integration_test/activity_recovery_android_test.dart`. (FR-025 SC-003 SC-007).

## Phase 8: User Story 7 — Actualización compatible (P1)

**Goal**: Cambiar nombre visible y ampliar copias conservando instalación/histórico.

**Independent Test / Checkpoint**: Actualizar copia de GymIA con misma firma, vista previa y comparación 100% de originales/IDs.

- [ ] T039 [P] [US7] Escribir compatibilidad de copia v3, nuevas tablas y restauración sin permisos en `test/trackia_backup_test.dart`. (FR-028 FR-029 SC-004).
- [ ] T040 [US7] Implementar adaptador de históricos en `lib/data/legacy_activity_adapter.dart`; mantener IDs Workout/Exercise/Set y protocolos. (FR-028).
- [ ] T041 [US7] Añadir vista previa de espacio Gimnasio y respaldo/recuperación antes de migrar en `lib/ui/migration_preview.dart`. (FR-028).
- [ ] T042 [US7] Versionar copia en `lib/domain/transfer.dart` y su repositorio en `lib/data/sqlite_workout_repository.dart`, incluyendo nuevos datos/chat recuperables: «Ningún token, secreto ni autorización activa se incorpora a prompts, archivos de copia o recibos de sincronización.»; jobs restaurados no se envían automáticamente. (FR-029 FR-037).
- [ ] T043 [US7] Cambiar solo marca visible en `android/app/src/main/AndroidManifest.xml` y `lib/ui/app.dart`; preservar paquete, firma, rutas y clientes; mantener gimnasio y temas. (FR-001 FR-028 FR-030).
- [ ] T044 [US7] Verificar actualización in situ y restauración del respaldo en `integration_test/trackia_upgrade_android_test.dart`; registrar cuentas/referencias sin secretos. (FR-001 FR-028 FR-029 SC-004).

## Phase 9: User Story 9 — Bienvenida opcional (P1)

**Goal**: Explicar funciones disponibles mediante slides y recordar la elección.

**Independent Test / Checkpoint**: Cuatro combinaciones Omitir/Empezar × casilla, tres arranques, apertura manual y entradas prioritarias.

- [x] T045 [P] [US9] Escribir pruebas de navegación, preferencia, cierre/fallo de guardado y entrada manual en `test/welcome_test.dart`. (FR-039 FR-040 FR-041 FR-042 FR-043 SC-008).
- [x] T046 [US9] Crear preferencia y almacén en `lib/data/welcome_settings_store.dart`: «autoShow es booleano con valor inicial true; seenVersion y completedAt son opcionales y no contienen identidad ni credenciales.»; confirmar solo Omitir/Empezar. (FR-041 FR-042).
- [x] T047 [US9] Crear cinco slides adaptadas a capacidades en `lib/ui/welcome.dart` según `contracts/welcome.md`, progreso, botones, casilla y lector/texto 200%. (FR-039 FR-040 FR-043).
- [x] T048 [US9] Coordinar entrada en `lib/ui/app.dart` y carga de preferencia en `lib/main.dart`; posponer si hay ejecución/archivo sin descartar entrada, respetar supresión al actualizar. (FR-041 FR-043).
- [x] T049 [US9] Añadir Ver bienvenida y Mostrar bienvenida al abrir en `lib/ui/welcome.dart` y acceso desde `lib/ui/assistant_chat.dart`; acceso Ayuda en máximo dos acciones y reapertura no reactiva la preferencia. (FR-042 FR-030 SC-009).
- [ ] T050 [US9] Verificar tres aperturas por combinación, tema/sistema, accesibilidad, archivo entrante y ejecución activa en `integration_test/welcome_android_test.dart`. (FR-039 FR-041 FR-043 SC-008).

## Phase 10: User Story 5 — Destinos por ámbito (P2)

**Goal**: Varios recursos por cuenta, herencia/override explícitos y efectos verificables.

**Independent Test / Checkpoint**: Dos espacios/destinos, hoja compartida expresa y pendiente que conserva destino al cambiar selección.

- [ ] T051 [P] [US5] Escribir resolución, rangos, fórmulas, timeout/recibo y cambio de destino en `test/destination_sync_test.dart`. (FR-031 FR-032 FR-033 FR-034 FR-035 FR-036 SC-005).
- [ ] T052 [US5] Definir vínculos en `lib/domain/destination_binding.dart`: «destinationChoice de actividad pertenece a none, inherit o explicit; en espacio solo none o explicit; explicit requiere bindingId del mismo perfil e inherit toma la elección del espacio.»; registro de conexiones por perfil en `lib/data/destination_repository.dart`. (FR-031 FR-032 FR-033).
- [ ] T053 [US5] Crear jobs/recibos en `lib/domain/sync_job.dart`: «SyncJob conserva fuente, revisión, hash, destino y mapeo inmutables; status pertenece a pending, confirmed, conflict o uncertain.»; persistir outbox transaccional en `lib/data/sync_job_repository.dart`. (FR-035 FR-036).
- [ ] T054 [US5] Implementar resolución y snapshot de destino en `lib/application/destination_resolver.dart`; compartir exige alcance explícito y no herencia del último usado. (FR-032 FR-033 FR-035).
- [ ] T055 [US5] Implementar dispatcher/reconciliación en `lib/application/sync_dispatcher.dart` con adaptadores `lib/data/sheet_sync_service.dart` y `lib/data/sheet_context_store.dart`; mantener lectura fresca/creación autorizada, aislar cachés y tokens. (FR-034 FR-036 FR-037).
- [ ] T056 [US5] Crear selector de destino y estados local/pending/confirmed/conflict/uncertain en `lib/ui/destinations.dart`; explicar cambio solo para futuros trabajos. (FR-031 FR-032 FR-035 FR-036).
- [ ] T057 [US5] Verificar aislamiento y reinicio con transportes controlados en `integration_test/multi_destination_android_test.dart`; documentar autorización y lectura/escritura real separadas en `docs/TRACKIA-SHEETS-QA.md`. (FR-034 FR-036 SC-005).

## Phase 11: User Story 8 — Extensibilidad veraz (P3)

**Goal**: Versionar capacidades avanzadas y ofrecer alternativas reales cuando falten.

**Independent Test / Checkpoint**: Ramas/carriles/audio ausentes no se ejecutan ni se anuncian; propuesta conservada y alternativa útil.

- [ ] T058 [P] [US8] Escribir pruebas de capacidades ausentes/versiones desconocidas en `test/advanced_capabilities_test.dart`. (FR-003 FR-038).
- [ ] T059 [US8] Extender validación de descriptores y alternativa lineal/manual en `lib/application/capability_registry.dart`; ningún adaptador avanzado se marca disponible sin implementación y pruebas. (FR-038).
- [ ] T060 [US8] Especificar contratos de ramas, carriles y audio en `specs/003-trackia-platform/contracts/advanced-capabilities.md` antes de implementarlos; no incluir su runtime en este incremento. (FR-038).

## Phase 12: Polish & Cross-Cutting Concerns

**Goal**: Medir criterios transversales y publicar evidencia por incremento entregado.

**Independent Test / Checkpoint**: Requisitos del incremento cubiertos con resultados, sin anunciar roadmap como disponible.

- [ ] T061 Medir 100 acciones, refresco >=1 Hz, navegación <=2 pasos, temas y accesibilidad en `integration_test/trackia_acceptance_android_test.dart`; registrar muestras/referencia en `docs/TRACKIA-QA.md`. (FR-030 SC-006 SC-007 SC-009).
- [ ] T062 Ejecutar matriz de `specs/003-trackia-platform/quickstart.md` para las historias entregadas y adjuntar resultados/faltantes en `docs/TRACKIA-QA.md`. (SC-001 SC-002 SC-003 SC-004 SC-005 SC-008).
- [ ] T063 Actualizar capacidades realmente entregadas y límites en `README.md`, `docs/BACKLOG.md` y `specs/003-trackia-platform/traceability.md`; ejecutar análisis y pruebas afectadas antes de APK. (FR-001 FR-037 FR-038).

## Dependencies & Execution Order

Todas las historias dependen de fases 1–2. Orden recomendado P1: US1 → US2 → US3 → US4 → US6 → US7 → US9. Después US5 (P2) y US8 (P3). Dependencias estrictas adicionales: US6 requiere US3; US5 requiere US2 y US4; US7 valida la base y las historias que incluya su entrega. US1 usa espacio por defecto y notas mínimas de la base, sin esperar selector US2 o campos completos US4. US2/US4 pueden probarse independientemente con fixtures de base. US9 se adelantó sin cambiar el esquema de datos ni depender de la base de
actividades, usando contenido de las capacidades ya existentes; la base sigue
bloqueando las demás historias. US8 no requiere implementar motores avanzados: valida y especifica límites.

Las tareas de pruebas [P] dentro de cada historia pueden redactarse juntas. Después modelos → repositorios → servicios → UI → integración. No ejecutar en paralelo cambios del mismo archivo aunque pertenezcan a historias distintas.

## Parallel Examples by Story

- US1: T010 y T011 puede escribirse junto a revisión de sus fixtures/contrato; la implementación espera modelos y servicios previos. No paralelizar archivos compartidos.
- US2: T016 y T017 puede escribirse junto a revisión de sus fixtures/contrato; la implementación espera modelos y servicios previos. No paralelizar archivos compartidos.
- US3: T023 y T024 puede escribirse junto a revisión de sus fixtures/contrato; la implementación espera modelos y servicios previos. No paralelizar archivos compartidos.
- US4: T030 puede escribirse junto a revisión de sus fixtures/contrato; la implementación espera modelos y servicios previos. No paralelizar archivos compartidos.
- US6: T034 puede escribirse junto a revisión de sus fixtures/contrato; la implementación espera modelos y servicios previos. No paralelizar archivos compartidos.
- US7: T039 puede escribirse junto a revisión de sus fixtures/contrato; la implementación espera modelos y servicios previos. No paralelizar archivos compartidos.
- US9: T045 puede escribirse junto a revisión de sus fixtures/contrato; la implementación espera modelos y servicios previos. No paralelizar archivos compartidos.
- US5: T051 puede escribirse junto a revisión de sus fixtures/contrato; la implementación espera modelos y servicios previos. No paralelizar archivos compartidos.
- US8: T058 puede escribirse junto a revisión de sus fixtures/contrato; la implementación espera modelos y servicios previos. No paralelizar archivos compartidos.

## Implementation Strategy

MVP: base + US1, con una propuesta de IA para actividad sin tiempo, aceptación humana
y nota persistida; probar continuidad local ante pérdida del proveedor. Validar antes de ampliar. Después añadir espacios/personas y motor lineal, registros y recuperación. Migración/identidad se verifican antes de distribuir una actualización. La bienvenida puede entregarse como incremento independiente con contenido acorde a esa versión. Multidestino y capacidades avanzadas quedan detrás de sus pruebas y límites. Cada entrega se verifica con quickstart.md y actualiza solo las capacidades presentes.

## Notes

Ninguna casilla se marca por redactar el SDD. No hay despliegue, migración ni APK en la entrega documental. Evitar reescribir históricos, repetir consentimientos innecesarios o afirmar que un servicio real se probó usando mocks.
