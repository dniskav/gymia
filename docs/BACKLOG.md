# Backlog de producto

Plan actualizado: [desarrollo del asistente](../specs/00-product/development-plan.md). Cada entrega debe producir un flujo usable y comprobarse en el teléfono.

Objetivo aclarado el 07–08/10/2026: [visión conversacional y separación motor/LLM](../specs/00-product/vision.md). Las hojas varían por usuario: el agente aprende una skill de lectura y escritura por usuario/hoja, conserva el formato existente y relaciona sus datos con GymIA. Sin hoja, puede sugerir crearla. [Contrato del agente de hojas](../specs/01-sheet-agent/spec.md). Los sprints aceptados aportan una base; no equivalen a que ese flujo esté completo.

Prioridad explícita posterior del usuario: el LLM y el chat por voz/texto son el centro del producto; registro, descansos, historial y Sheets son herramientas de la app que apoyan esa experiencia. El orden inicial de sprints de la tabla siguiente requiere replanificación; no interpretar «Sprint 5 · IA» como autorización para seguir posponiendo el asistente.

| Entrega | Resultado usable | Estado |
| --- | --- | --- |
| Sprint 1 · Registro | Sesión manual, series, correcciones, persistencia e historial | Aceptado por el usuario en su teléfono |
| Sprint 2 · Rutinas | Iniciar desde rutina, consultar valores anteriores y descansos | Aceptado por el usuario en su teléfono |
| Sprint 3 · Histórico | Importar Sheets con vista previa/deduplicación y exportar/restaurar | 0.3.8 verifica autorización Google y lectura API real en emulador: 111 filas, contexto para el asistente y actualización. Pendiente importación estructurada de la hoja por ejercicio y prueba de esta conexión en el teléfono |

## Próximas entregas propuestas

| Orden | Resultado usable | Estado |
| --- | --- | --- |
| 1 · Skills y escritura Sheets | Interpretación por usuario/hoja, registros con procedencia y actualización verificada respetando su formato | 0.3.8 probada en emulador: autorización real, 111 filas, persistencia y nueva lectura. 0.3.19 añade escritura revisada y creación de hojas, con pruebas controladas; quedan skills persistentes, importación estructurada y validación real del nuevo envío |
| 2 · Acciones desde el chat | Registro determinista, contexto persistido y descanso automático; usar la skill para mantener Sheets | 0.3.10 añade foco de actividad, tramos, mensajes originales, descanso automático y propuestas/interpretaciones acotadas del LLM. Búsqueda del histórico completo, revisiones avanzadas y conexión con la skill de Sheets pendientes |
| 3 · Voz | Misma conversación y herramientas mediante dictado y respuesta hablada | Usuario confirma dictado en el móvil; respuesta hablada pendiente |
| 4 · Reloj compañero | Controles, registro, descanso con vibración/aviso visual y voz al mismo asistente del móvil | Fase posterior confirmada. Xiaomi Watch 2 M2320W1, Wear OS 5 informado por el usuario. Depende del motor de acciones/descanso; no implementado ni probado |
| 5 · Contexto y progreso | Máquinas/variantes, fotos, progreso calculado y recordatorios reales | Pendiente |

Las gráficas dejan de ser la siguiente entrega y el LLM deja de posponerse al antiguo Sprint 5. Las entregas anteriores conservan su aceptación y sus límites documentados.

## Siguiente bloque y decisiones pendientes

0.3.20 añade conexión persistida, renovación silenciosa, interpretación recordada y revalidada, lectura previa a cada consulta, envíos desde el chat/al finalizar y cola cifrada de primer plano, además de citas legibles y preguntas normales de interpretación. [Pruebas y límites](0.3.20-AUTOMATIC-SHEETS.md). Pendientes: WorkManager, correcciones remotas por revisión, agregación avanzada y Picker/`drive.file`; OAuth y escritura real de esta entrega se validan en el móvil.

0.3.19 añade envío revisado de sesiones finalizadas, creación consentida de hojas, propuestas acotadas del modelo y recibos atómicos para reconciliar reintentos. [Uso, pruebas y límites](0.3.19-SHEETS-WRITE.md). Quedan pendientes Picker/`drive.file`, skills persistentes de formato, agregación diaria, cola SQLite y correcciones remotas por revisión. La conexión real con los nuevos permisos debe validarse en el móvil; las pruebas nuevas usan transporte Google controlado.

0.3.15 implementa la primera etapa multiusuario: identidad OAuth comprobada contra Google, datos separados por perfil y preservación del histórico en Perfil local. [Pruebas Android y límites](0.3.15-PROFILES.md). La alternancia de cuentas se probó con identidades controladas; el inicio de sesión real con varias cuentas sigue por validar. Picker/`drive.file`, skills y cola siguen pendientes; 0.3.19 añade el envío explícito revisado y creación sobre el adaptador existente.

0.3.11 cambia el inicio a chat puro con micrófono en el campo y adjuntos/carga de hojas en +. El panel de ejecución aparece al preparar la actividad con el modelo y la conversación se mantiene entre actividades. Disponibilidad de IA verificada y avisos locales Android implementados. Hojas de formato propio se cargan sin IA, pendientes de interpretación. 0.3.12 corrige el contrato de preparación, muestra Markdown y conserva confirmaciones deterministas en el chat; [revisión en Android y límites](0.3.12-EMULATOR-QA.md). La siguiente prioridad sigue siendo skills/herramientas para historial completo y escritura Sheets; paneles deportivos avanzados y avisos en el reloj permanecen para fases posteriores.
- Implementar la skill de lectura y escritura por usuario/hoja. Registro 2026 es un caso de prueba, no un formato obligatorio; no construir únicamente un adaptador fijo para esa pestaña.
- Ampliar entidades para reps desconocidas, fallo/casi fallo, parciales, calentamientos, variantes, carga por lado y procedencia antes de importar sin pérdida.
- Modelo adaptable confirmado: sesiones mixtas de fuerza, cardio y clases; definiciones/métricas por usuario configuradas por el LLM. Propuesta: núcleo estable con documentos JSON versionados sobre SQLite, sin exigir reps/peso ni cambiar a NoSQL solo por variar ejercicios. [Contrato y ejemplos](../specs/00-product/adaptive-data-model.md). Health Connect/HealthKit se contemplan como conectores posteriores; el flujo Strava API → LLM está restringido por su política actual.
- Ampliación: observaciones de múltiples fuentes y progreso diario sin sesión. Ejemplo abierto: pasos del teléfono y una fila diaria actualizable, con origen/cobertura y sin duplicar teléfono/reloj. Comprobar acceso real a los pasos del Xiaomi 11T Pro; no asumir que su contador visible publica un histórico accesible. Conectores y reglas persistentes ejecutan lo determinista; el LLM configura e interpreta.
- Validar propuestas del LLM, guardar/reutilizar la skill, aprender correcciones y comprobar cambios de estructura. Resolver identidad de usuario/conexión para no mezclar perfiles entre cuentas.
- Mantener Sheets actualizado está confirmado. Parar termina el tramo; Terminar cierra el ejercicio y guarda localmente; Finalizar día solicita guardar el progreso en Sheets y permite entrenar después. El contrato define destinos acotados, conservación de fórmulas, conflictos y verificación; 0.3.19 permite el envío explícito con recibos; faltan agregación diaria, cola y correcciones por revisión. [Ciclo de sesión](../specs/00-product/session-lifecycle.md).
- [Pantalla de ejecución mínima](../specs/00-product/training-focus.md): 0.3.10 implementa preparación con lista/modelo, pantalla fija con Iniciar/Parar y registro libre. Parar fija fin/descanso sin bloquear Iniciar, y Terminar conserva el descanso al volver a elegir actividad. Se guardan originales, borradores, tramos y definiciones; métricas básicas adaptables sin imponer fuerza. La interfaz anterior queda para biblioteca/registro manual e histórico. 0.3.19 conecta estos datos con el envío explícito a Sheets.
- Varias sesiones al día, con ID y métricas propios, relacionadas para analizar progreso sin fusionarlas por fecha. La base admite sesiones consecutivas; fútbol/natación y otros datos dependen del modelo adaptable. El nuevo control principal guarda localmente y explica que Sheets todavía no se actualiza.
- Probar diferentes formatos y escritura real en una hoja de prueba antes de activar mutaciones sobre el histórico personal.
- Ofrecer creación opcional si no hay hoja; no crear otra para eludir la interpretación de la existente.
- Proveedor confirmado: OpenCode Go con claves propias. Usuario confirma texto y voz; herramientas y visión deben comprobarse para el modelo elegido.
- Reloj: [plan de app compañera](../specs/00-product/watch-companion.md) para otra fase, según aclaración expresa del usuario. Xiaomi Watch 2 M2320W1 con Wear OS 5 confirmado por él; prueba real pendiente. Primero controles/descanso y después voz al mismo chat. Reutilizar motor/IDs, mostrar pendientes al desconectar y probar aviso con móvil bloqueado. No iniciar ahora el módulo ni equiparar alarmas nativas a funcionamiento validado de GymIA.
- Activación de iOS: Xcode, firma y dispositivo para validación.

## Cambio de arquitectura aceptado durante Sprint 1
El usuario pide facilitar una futura versión iPhone. Se sustituye la propuesta
Android nativa inicial por Flutter compartido. Android sigue siendo la primera
plataforma entregada; no se añade iOS al criterio de aceptación de este sprint.
