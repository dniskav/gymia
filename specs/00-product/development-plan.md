# Plan de desarrollo · asistente conversacional

Actualizado el 08/10/2026. Mantener Flutter/SQLite y los datos existentes. El LLM es el centro del chat; la app ejecuta las operaciones deterministas. Cada entrega debe producir un flujo usable y verificable.

## Base disponible · 0.3.10

Chat principal, proveedores configurables, claves protegidas, conversación persistida, dictado y adjuntos según el modelo. El usuario confirmó voz y texto en el teléfono. Registro manual, rutinas, historial, descanso manual, copias e importador tabular disponibles.

Autorización y lectura Google real verificadas en el emulador: selección de archivo/pestaña, 111 filas de Registro 2026, copia conservada tras reiniciar y nueva lectura. Cliente OAuth Android creado y Sheets API habilitada. Falta configurar el proveedor IA en ese emulador: no dar por probada allí la llamada al LLM. La copia se facilita al chat, pero no se importan registros automáticamente ni se escribe en Google Sheets.

0.3.9 añadió catálogos de modelos consultados al proveedor, URL API personalizada y cierre con fecha/hora corregible. 0.3.10 añade preparación de actividad, ejecución fija con Iniciar/Parar, descanso persistido, resultados originales y definiciones/métricas JSON básicas. El modelo propone actividades y campos mediante respuestas validadas; falta el motor de skills de hojas y herramientas para consultar todo el histórico. Las entradas completas de fuerza inequívocas se registran sin llamada al modelo. [Entrega y límites](../../docs/0.3.10-ACTIVITY-FOCUS.md).

## 1. Próxima entrega prioritaria · aprender y mantener la hoja de cada usuario

### Resultado

El agente entiende la hoja elegida, conserva una skill por usuario/hoja y sabe mantenerla actualizada en su formato existente. Registro 2026 es un caso de prueba, no el formato obligatorio. Sin hoja, puede sugerir crearla.

Contrato: [skill por usuario y hoja](../01-sheet-agent/spec.md). La escritura verificada en la hoja existente forma parte de esta entrega.

### Tareas, en orden de dependencia

1. Definir contratos tipados de skill, registros propuestos y operaciones de escritura. Resolver identidad de usuario/conexión Google antes de anunciar aislamiento por cuenta. Guardar revisiones y evidencias de estructura; las reglas no conceden permisos.
2. Implementar el [modelo de actividad adaptable](adaptive-data-model.md): documentos con núcleo estable, métricas/definiciones por usuario y almacenamiento inicial SQLite+JSON. Una sesión admite fuerza, cardio y clases sin reps. Ampliar entidades, finalización, histórico y copias para datos desconocidos, fallo/casi fallo, parciales, calentamientos, carga por lado, variantes, tiempo/distancia/energía y procedencia. Conservar IDs y copias anteriores. El LLM propone/amplía definiciones mediante herramientas validadas, sin generar tablas físicas por usuario.
   Incluir observaciones independientes y resúmenes diarios que no requieran sesión. Las actividades y fuentes citadas son ejemplos abiertos. Probar un día con pasos sin gimnasio y reglas de actualización diaria sin duplicados, cobertura desconocida y fuentes solapadas. El agente configura conectores implementados; no inventa acceso a una fuente.
3. Añadir herramientas del LLM para inspeccionar bloques relevantes, proponer la skill y aclarar dudas. Validar propuestas, incorporar correcciones y reutilizar el perfil; detectar cambios de estructura. No enviar pestañas ajenas al entrenamiento por defecto.
4. Importar registros con vínculos estables a su fuente, sin duplicar al reimportar. La coordenada visual no es la identidad del registro. Mantener casos no representables y originales.
5. Preparar escritura con destinos concretos y valores previos esperados; conservar fórmulas, formato y datos ajenos. La skill define cómo agregar sesiones, corregir y conservar N series. Mostrar dudas y conflictos cuando correspondan.
6. Implementar cola durable, reconciliación e idempotencia; leer antes de escribir y verificar después. Un timeout deja un resultado desconocido. Documentar la limitación de concurrencia entre lectura y escritura.
7. Solicitar escritura de Sheets cuando el motor esté listo; mantener Drive con alcance mínimo. Probar nuevas filas, correcciones, ordenación/inserción, cambios de estructura, fórmulas, reintentos y falta de red.
8. Verificar escritura real en una hoja de prueba autorizada y probar al menos dos formatos diferentes. Entregar APK con estados local/pendiente/conflicto/verificado. No afirmar compatibilidad universal.
9. Añadir propuesta y creación opcional cuando el usuario no tenga hoja. No reemplazar la existente ni imponer una plantilla a quienes tienen histórico.

### Aceptación

Un usuario con varias series por fila y otro con filas por serie conservan sus formatos y tienen skills de lectura/escritura persistidas. Una sesión nueva aparece sin perder una quinta serie ni tocar fórmulas o sesiones antiguas. Reimportar o reintentar no duplica. Cambios externos se conservan o se muestran como conflicto. Solo se comunica guardado en Google tras releer y verificar.

## 2. Entrenar desde la misma conversación

### Resultado

Registrar series por texto/voz y consultar al LLM desde el chat central. El modelo usa las herramientas anteriores para consultar el histórico y mantener Sheets. Los controles manuales sirven de apoyo y corrección.

### Tareas

- Persistir contexto de sesión, ejercicio activo y peso preparado. El contexto del proveedor no es la única fuente del estado.
- Parser local para entradas inequívocas: 60k 13r f, 13r, otra igual, bajo a 45. Aclarar si falta contexto. Una sugerencia o preparar peso no registra una serie.
- Guardar serie, recibo del evento y descanso en una transacción. Reloj del sistema e ID estable; reintentar no duplica ni reinicia descanso. Dos series iguales realizadas son dos eventos distintos.
- Separar hora de registro y ejecución; conservar procedencia y desconocidos. Reutilizar las entidades ampliadas para Sheets.
- Herramientas acotadas del LLM para consultar histórico, proponer identidad de ejercicio y ejecutar acciones validadas. Serializar mutaciones y comprobar contexto ante respuestas tardías.
- Responder tras persistir: ejercicio, peso, reps, fallo, número de serie, hora y descanso. Mostrar sincronización por separado.
- Voz y texto usan el mismo motor, con transcripción revisable. Sin red, comandos claros siguen funcionando y Google queda pendiente.

### Aceptación

Chest Press activo: Parar fija el fin del tramo y arranca descanso con hora del sistema; 60k 13r f guarda su resultado 60×13F sin llamar al modelo. Bajo a 45 solo prepara peso, sin inventar una serie realizada. Casi F y parciales conservan significado. Reabrir recupera sesión y descanso; reintentar no duplica. Una descripción ambigua consulta al LLM con histórico y pide aclaración si hace falta. La sincronización con la skill de la hoja del usuario permanece pendiente.

### Inicio/cierre desde la pantalla principal · confirmado el 08/10/2026

La aclaración más reciente define Iniciar/Parar para el tramo, Terminar para cerrar el ejercicio y Finalizar día para solicitar el guardado acumulado en Sheets sin impedir entrenar después ese mismo día. Cada actividad y contenedor tiene ID propio; varios del mismo día se conservan separados y se relacionan al analizar progreso. [Contrato y estado del control](session-lifecycle.md). 0.3.10 implementa los controles y las métricas adaptables básicas sobre la base local; escritura/cola/agregación siguen dependiendo del bloque 1.

Experiencia de ejecución solicitada: [controles mínimos durante la actividad](training-focus.md). Preparación desde lista o asistente, después pantalla fija y solo chat desplazable. Parar inicia descanso inmediatamente; Iniciar no espera al contador. El resultado libre se conserva aunque no sea una métrica de rutina. Este flujo requiere el estado persistido de actividad/tramo y el modelo adaptable, no solo quitar tarjetas de la pantalla actual.

## 3. App compañera en el reloj · añadido el 08/10/2026

Petición confirmada para una fase posterior: app vinculada al móvil, controles para iniciar/pausar/parar/registrar, hablar al mismo asistente y aviso de descanso con vibración y presentación visual. [Alcance, dependencias y aceptación](watch-companion.md). Dispositivo confirmado por el usuario: Xiaomi Watch 2, M2320W1, Wear OS 5. La compatibilidad real se probará en esa fase; no iniciar ahora el módulo del reloj.

Entregas: A) controles y descanso compartidos, B) voz al mismo chat, C) accesos rápidos y sensores/autonomía evaluados después. Reutilizar motor y eventos del móvil, con IDs estables para no duplicar acciones al reconectar. Propuesta: módulo Wear OS y puente Android, manteniendo Flutter en móvil. Probar pantalla apagada, móvil bloqueado y pérdida de conexión; no asumir que manejar alarmas nativas demuestra funcionamiento de GymIA. La primera versión mantiene coordinación IA/Google en el móvil y no exige otra API key en el reloj.

Este bloque sigue al motor de acciones/descanso persistente; no desplaza el aprendizaje y mantenimiento de la hoja. La interfaz adaptativa y los contratos del agente deben contemplar desde ahora que el reloj es otra entrada al mismo núcleo.

## 4. Enriquecer el asistente

Respuesta hablada y controles durante el descanso; referencias visuales según capacidades reales del proveedor; recuperación por máquina, variante y técnica; progreso calculado y recordatorios. Análisis de ejecución requiere especificación y dispositivos de prueba. Estas funciones no desplazan la prioridad de mantener la hoja del usuario.

## Decisiones abiertas

- Política de escritura confirmada: Finalizar día solicita guardar el progreso; Terminar un ejercicio conserva datos locales. Falta implementar intención durable, agregación diaria y verificación; permitir otra sesión después de cerrar el día o mientras se resuelven pendientes. No anunciar escritura antes de implementarla.
- Cambios de formato cuando la hoja no admite información nueva. La skill propone una extensión y el usuario decide; no agregar columnas ni sustituir la hoja silenciosamente.
- Identidad Google estable y mínima para asociar skills a cuentas; la conexión actual no debe fingir que ya la proporciona.
- Activación de iOS: Xcode, firma y dispositivo para validación.

Proveedor inicial confirmado: OpenCode Go con claves propias. Existen Go/Zen, OpenAI, Claude, Gemini, OpenRouter y API personalizada. Validar herramientas y visión para el modelo usado. No cambiar de proveedor ni usar respaldo de pago automáticamente.
