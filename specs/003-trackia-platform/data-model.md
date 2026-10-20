# Modelo de datos propuesto

Estado: diseño, no esquema migrado. Perfil mantiene la BD actual; spaceId es una
partición lógica dentro de ella. Los vínculos usan identidad, nunca nombre visible.

## Entidades y relaciones

| Entidad | Campos y función |
|---|---|
| ProfileScope | profileId existente y referencia de BD; propietario de espacios y autorizaciones. |
| Space | id, profileId, name, personaRevisionId, destinationChoice, revision. |
| PersonaRevision | id, revision, tone, detail, accompaniment, instructions; reutilizable explícitamente. |
| ActivityDefinition | id, profileId, spaceId, revision, name, fields, labels, personaChoice, destinationChoice. Plantilla editable. |
| FieldDefinition | fieldId, type, label, unit, options; identidad independiente de la etiqueta. |
| AcceptedPlan | id, definitionId/revision, scope, schemaVersion, stages, cycles, labels, capabilityVersions, acceptedAt; snapshot. |
| PlanStage | stageId, kind, clockMode, durationSeconds, advancement, goal, nextStageId. Descanso es etapa, no pausa del motor. |
| ActivityRun | id, scope, planId, revision, status, stageId, cycleIndex, activeDuration, checkpoint, uncertainty. |
| RunEvent | eventId, runId, sequence, commandId, expectedRevision, cause, original, recordedAt, reportedAt opcional. |
| Observation | id, scope, runId opcional, definitionSnapshot, original, interpreted, provenance, revision, attachmentRefs. |
| Connection | id, profileId, provider, accountSubject, resourceId, authorizationRef; sin tokens dentro del modelo de conversación. |
| DestinationBinding | id/revision, connectionId, spreadsheetId, tabId, allowedRanges, mappingRevision; compartición explícita. |
| SyncJob | jobId, scope, sourceId/revision/hash, destinationSnapshot, mappingSnapshot, idempotencyKey, status, attempts. |
| SyncReceipt | jobId, verifiedResource/ranges/hash, confirmedAt, evidence; no éxito por respuesta de texto del modelo. |
| WelcomePreferences | device-scoped autoShow, seenVersion, completedAt; no profileId. Estado de casilla en pantalla es transitorio. |

Chat, borrador, archivos, memoria, cachés y contexto de hoja incorporan profileId+spaceId.
Las referencias de adjuntos se validan en ese mismo ámbito. Compartir requiere una concesión
explícita con origen, receptor y alcance, no copiar todos los recuerdos.

## Restricciones normativas de la primera implementación

Estas frases son el contrato de validación; las tareas las reproducen literalmente.
La tabla concentra las restricciones de campos y relaciones para evitar límites implícitos.

| ID | Restricción |
|---|---|
| C01 | IDs de entidad no vacíos e inmutables; toda entidad de espacio requiere profileId y spaceId válidos del mismo propietario. |
| C02 | name y etiquetas visibles tienen entre 1 y 80 caracteres tras quitar espacios extremos; instructions admite de 0 a 8000 caracteres. |
| C03 | revision y schemaVersion son enteros positivos; una edición incrementa revision y no modifica snapshots aceptados. |
| C04 | type pertenece a number, text, boolean, choice o attachment; unit es opcional, pero se conserva si existe; un valor ausente no se convierte en cero. |
| C05 | Un plan lineal contiene de 1 a 128 etapas; cycles es opcional y, si existe, es entero entre 1 y 1000. |
| C06 | clockMode pertenece a none, stopwatch o countdown; durationSeconds es obligatorio solo para countdown y es entero entre 1 y 604800. |
| C07 | advancement pertenece a manual, elapsed o quantity; elapsed requiere countdown y quantity requiere fieldId numérico y goal finito positivo con unidad compatible. |
| C08 | status de ejecución pertenece a ready, running, paused, waiting, completed, cancelled o recovery_needed; solo hay una ejecución activa por perfil. |
| C09 | commandId es único por ejecución y sequence es único y creciente por runId; el cambio de estado, evento y revisión se confirman en una transacción. |
| C10 | runId en una observación es opcional; original y provenance son obligatorios y las correcciones generan revisión sin sobrescribir el original. |
| C11 | destinationChoice de actividad pertenece a none, inherit o explicit; en espacio solo none o explicit; explicit requiere bindingId del mismo perfil e inherit toma la elección del espacio. |
| C12 | SyncJob conserva fuente, revisión, hash, destino y mapeo inmutables; status pertenece a pending, confirmed, conflict o uncertain. |
| C13 | autoShow es booleano con valor inicial true; seenVersion y completedAt son opcionales y no contienen identidad ni credenciales. |
| C14 | Ningún token, secreto ni autorización activa se incorpora a prompts, archivos de copia o recibos de sincronización. |

Sin límite de duración para stopwatch. Descanso desactivado se omite, nunca se simula
con duración cero. Sus etapas activadas usan el mismo contrato de cuenta atrás, por lo
que no heredan el límite de 30 minutos del descanso manual legado. Escalados mayores de
etapas/ciclos requieren una capacidad nueva, no truncado silencioso.

## Estado, tiempo y concurrencia

`ready → running ↔ paused`; `running → waiting` si el reloj termina y el avance es manual;
`waiting → running` al avanzar, o al cerrar el plan `→ completed`. Una actividad sin reloj
sigue running hasta la acción o cantidad verificada. `cancelled` conserva parciales;
`recovery_needed` conserva checkpoint y solo continúa tras resolver incertidumbre.
Estados activos para C08: ready, running, paused, waiting y recovery_needed.

Finalizar una etapa no demuestra que se alcanzó su objetivo físico. El evento conserva
causa user/elapsed/quantity/recovery, duración prevista, medida y confirmación humana si
la hay. Nunca generar resultados físicos por haber consumido tiempo.

La duración activa se obtiene del reloj monotónico del proceso y checkpoints; el widget
solo representa. Tras cierre/reinicio, evidencia temporal fiable permite reconstrucción;
si no puede verificarse (incluido cambio de reloj), se entra en recovery_needed. Reproducir
un evento no repite una transición ni un aviso. Recuperar múltiples vencimientos usa una
transacción acotada al tamaño del plan y no lanza una ráfaga de avisos pasados.
Una ejecución compuesta futura puede contener carriles; no implica varias ejecuciones
activas por perfil ni habilita simultaneidad antes de entregar esa capacidad.

## Migraciones y copias

1. Preservar bases y claves por perfil. Copia verificable antes de aplicar migraciones.
2. Crear espacio Gimnasio por defecto y adaptar IDs legados, sin reescribir originales
   ni fabricar ejecuciones a partir de observaciones. Vista previa de la asignación.
3. Adaptador mantiene Workout/Exercise/WorkoutSet, gymia-backup y protocolos anteriores;
   no exigir que todo registro nuevo tenga workoutId. Backfill idempotente, con rollback
   mediante respaldo probado; transacción de esquema no equivale a downgrade automático.
4. Nueva versión de copia incorpora espacios, planes, eventos, observaciones, preferencias
   de espacio y referencias de chat/adjuntos recuperables; mantiene lector de v3 y límites
   de entrada existentes hasta versionar explícitamente el formato. Conservar originales.
5. No exportar tokens ni conexiones activas. Referencias de destinos restauradas quedan
   desactivadas hasta revalidar propietario y permisos; jobs restaurados requieren
   reconciliación explícita y no se despachan automáticamente.
6. Pendientes antiguos conservan destino y propietario antiguos; importarlos no consulta
   la conexión recién seleccionada. La preferencia de bienvenida es de dispositivo y no
   forma parte de una copia de datos de otro perfil.
