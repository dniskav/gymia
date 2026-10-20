# Entrenamiento con controles mínimos

Requisitos del usuario del 08/10/2026. Los ejemplos de fuerza, cinta, fútbol y yoga son abiertos: no definen una lista cerrada de deportes ni campos universales.

## Experiencia solicitada

Preparar primero la actividad: elegir un ejercicio existente, añadir uno o describir al asistente por texto, voz o foto qué se va a hacer y por qué se sustituye otro. El LLM identifica la actividad, consulta el histórico relevante y prepara qué registrar y el descanso. La pantalla actual de estadísticas y tarjetas no será la pantalla de ejecución.

Durante la actividad, mantener una pantalla fija sin scroll de página: nombre/contexto mínimo, control principal Iniciar/Parar, espacio de texto/voz, descanso y salida de la actividad. Solo el historial conversacional tendrá scroll. Con teclado abierto, conservar controles accesibles reduciendo el espacio del chat, sin desplazar toda la pantalla. La selección y el resumen de rutina se consultan fuera del tramo en ejecución.

El control principal no exige peso/reps para comenzar ni terminar. Una actividad continua puede tener un único tramo; fuerza puede tener varios. Inicio, fin y observaciones son comunes, mientras las métricas proceden de la definición de actividad del usuario.

## Parar y descansar · confirmado

Al pulsar Parar, registrar el fin real mediante el reloj de la app e iniciar el descanso inmediatamente. No esperar una transcripción, la respuesta del LLM ni completar el resultado. El usuario puede escribir/dictar lo sucedido durante el descanso.

El descanso nunca bloquea Iniciar: es válido empezar antes, a tiempo o después. Al iniciar un nuevo tramo, cancelar el aviso del descanso anterior; una respuesta tardía del asistente no puede reiniciar el descanso ni cambiar el tramo ya iniciado. Conservar el descanso previsto y, cuando se conozca, el realizado como datos distintos. No modificar el fin de la actividad anterior al registrar sus resultados después.

El descanso proviene de la configuración de esa actividad o de una propuesta del modelo, editable por el usuario. No reutilizar automáticamente el descanso del primer ejercicio de la rutina para todos los demás. Si falta una decisión, mostrar configuración sin fingir una recomendación ya hecha por el modelo. Un descanso de una actividad continua tampoco implica que existan series de fuerza.

## Conservar todo el registro

Guardar el mensaje original con su contexto, actividad/tramo, hora y procedencia antes de depender de la interpretación del LLM. Separar transcripción original, métricas extraídas, observaciones y revisiones; corregir una interpretación no borra lo que dijo el usuario. Si el modelo no responde, el mensaje y los tiempos siguen guardados y su interpretación puede retomarse.

El modelo distingue resultados (reps, carga, goles u otras métricas definidas), sensaciones, molestias y conversación. Ningún contenido se descarta por no encajar en una celda de fuerza. Un relato no cuantificado tampoco se convierte en una medición inventada. Reutilizar el contrato de [datos adaptables](adaptive-data-model.md), ampliando histórico, copias y representación en Sheets sin perder los datos actuales.

Las instrucciones por usuario y actividad pueden compartir observaciones pertinentes entre deportes, manteniendo fecha y contexto. No limitar una molestia de rodilla al gimnasio si es relevante al preparar fútbol; no aplicar una regla de carga/reps a fútbol o yoga. Consultar originales y procedencia antes de afirmar que un antecedente existe. Las recomendaciones siguen siendo responsabilidad del LLM, no un cálculo determinista fijo para todos los deportes.

## Terminar una actividad, un entreno y cerrar el día

Cerrar un entreno no cierra el día. Cerrar el día es una acción explícita para guardar el progreso acumulado en Sheets, sin impedir añadir otra actividad o entreno después ese mismo día. La fecha agrupa progreso, pero no sustituye los IDs de sesiones/actividades.

Un nuevo cierre o guardado del mismo día reconcilia las revisiones y datos nuevos con el destino de la skill; no repite filas ni sobrescribe entrenos distintos por compartir fecha. Conservar trazabilidad del cierre/guardado solicitado y de lo realmente verificado en Google. No presentar el día como bloqueado o definitivamente terminado.

Decisión confirmada: Parar termina el tramo y empieza el descanso; Terminar cierra el ejercicio/actividad; Finalizar día solicita guardar el progreso acumulado en Sheets. No implementar un cierre de día como finalizar automáticamente una actividad en marcha. Al acabar una actividad, volver a preparación para ver pendientes, añadir otra o escoger algo de otra rutina; la rutina orienta, no impide elegir otra actividad.

## Decisiones acordadas y estado

- Iniciar/Parar controla la serie/tramo; Terminar cierra el ejercicio o actividad, como Pec Fly. Después se puede elegir otro.
- Parar inicia descanso inmediatamente. Los originales se conservan automáticamente en el móvil; el guardado de progreso en Sheets corresponde a Finalizar día. No hay un botón de formulario Guardar por cada serie.
- Una propuesta del LLM se muestra antes de aceptar Preparar y después Iniciar. No empezar una serie porque un modelo la describa.
- Finalizar día no bloquea actividad posterior. Se toma como acción de guardado de progreso a Sheets, pendiente de motor/skill/verificación; no atribuir una escritura Google a Terminar un ejercicio.

## Implementación y aceptación

Actualización 0.3.11: el inicio es chat, sin botones de elegir actividad/entrenamiento. El + conserva adjuntos/cámara y permite cargar Excel/CSV o Google Sheets/Drive sin IA. El menú reúne gestión/historial. Una propuesta válida del modelo prepara la actividad sin arrancar el reloj; el panel aparece abajo y el chat se mantiene entre actividades. La disponibilidad del proveedor/modelo se comprueba antes de habilitar conversación/nuevos inicios. Parar y conservar notas siguen disponibles ante desconexión. Aviso local de descanso Android añadido; paneles deportivos avanzados, skills por hoja e histórico completo mediante herramientas siguen pendientes. [Entrega 0.3.11](../../docs/0.3.11-CHAT-FIRST.md).

0.3.10 añade la pantalla fija, preparación desde lista/modelo, definiciones adaptables básicas, registros originales y tramos persistidos con descanso automático. [Entrega y límites](../../docs/0.3.10-ACTIVITY-FOCUS.md). La definición/instrucciones se reutilizan por actividad, sin afirmar que ya existe una skill de Google Sheets por cuenta. Finalizar día es un cierre local en esta entrega: escritura, agregación diaria/verificación y outbox siguen pendientes.

La base implementada conserva actividad/tramo, mensajes originales y métricas básicas, con operaciones transaccionales y contratos acotados del LLM. La interfaz consume ese mismo estado. Cerrar/reabrir recupera tiempos, borradores y descanso; dobles acciones no duplican tramos y un fallo de proveedor no pierde un resultado ya capturado. Ampliar validación semántica, revisiones, herramientas de búsqueda del histórico y conexión con skills de Sheets sobre esta base.

Criterios: una serie de fuerza y una actividad sin reps usan los mismos controles; Parar inicia descanso sin proveedor disponible; Iniciar a 1:40 de un descanso de 2:00 funciona y evita un aviso antiguo; los resultados y notas se recuperan sin pérdida; solo el chat se desplaza; una nueva actividad tras cerrar el día se conserva y el siguiente guardado no duplica en Sheets.
