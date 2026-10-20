> Documento histórico de GymIA, conservado como antecedente. Para el objetivo actual, ver la [visión de TrackIA](../vision.md).

# GymIA · Visión y límites de responsabilidad

## Fuente y estado

Requisitos aclarados por el usuario el 07–08/10/2026 y contexto leído de un documento privado de contexto (no distribuido) (preparado el 06/10/2026). El documento de contexto incluye antecedentes, propuestas y dudas; no convertir todos sus detalles en decisiones aprobadas. Esta especificación recoge el objetivo confirmado y las diferencias con la implementación. No afirma que las funciones pendientes ya existan.

## Objetivo confirmado

El centro del producto es un asistente LLM conversacional, accesible por texto o voz. La conversación es la experiencia principal de entrenamiento y conserva el ejercicio activo, el contexto, las consultas y las decisiones. El usuario confirmó expresamente esta prioridad el 07/10/2026: el resto de funciones de la app apoya al asistente, no lo relega a una función secundaria.

El motor determinista realiza registros, cálculos, reloj, descansos y persistencia. El LLM entiende lenguaje libre, descripciones de ejercicios o máquinas, ambigüedades, hojas desconocidas, referencias históricas contextualizadas y propuestas. Los comandos inequívocos pueden resolverse localmente y responder en el mismo chat sin gastar una llamada al modelo. Esto es una optimización de ejecución, no una sustitución del asistente como centro de la interfaz. Google Sheets sigue siendo parte del flujo del usuario y debe poder leerse y actualizarse desde GymIA con autorización Google.

Ampliación confirmada el 08/10/2026: las sesiones pueden combinar fuerza, cardio y clases como spinning, yoga, Pilates o CrossFit. El LLM adapta las definiciones y métricas a lo que cada usuario quiere registrar. Repeticiones y peso no son obligatorios para toda actividad. El núcleo conserva identidades, unidades, procedencia y persistencia fiables; el modelo configura y amplía el esquema lógico mediante propuestas validadas. [Modelo de actividad adaptable](../adaptive-data-model.md). La propuesta de almacenamiento es SQLite con documentos JSON versionados; adoptar NoSQL no es un requisito confirmado ni una migración realizada.

Los ejemplos anteriores no limitan los tipos de actividad, métricas o fuentes. El progreso también incluye observaciones y resúmenes diarios sin sesión, por ejemplo pasos del teléfono en días sin gimnasio. El LLM configura e interpreta fuentes accesibles mediante conectores y permisos reales; la app obtiene, deduplica, guarda y mantiene Sheets. Una regla ya aprendida se ejecuta sin llamadas repetidas al modelo para tareas deterministas. El acceso concreto al podómetro/histórico del Xiaomi 11T Pro debe verificarse, no se da por implementado.

Rutinas, historial, temporizador, fotos y controles rápidos se integran como apoyos a la conversación. No obligar al usuario a abandonar el chat ni rellenar formularios para operaciones que ya ha expresado claramente por voz o texto. Los formularios pueden servir para configurar, revisar o corregir cuando resulten útiles.

App compañera en el reloj solicitada el 08/10/2026 para otra fase: entrada por voz al mismo agente, controles de entrenamiento/registro y descanso con aviso visual y vibración. Reloj y móvil comparten conversación, contexto y motor; no crean historiales independientes. [Hoja de ruta y contrato del reloj](../watch-companion.md). Usuario confirma Xiaomi Watch 2, M2320W1, Wear OS 5; funciones planificadas, no implementadas ni probadas. Mantener la prioridad actual en IA, datos adaptables y Sheets.

Navegación confirmada tras probar 0.3.4: abrir directamente en el asistente con botón principal de voz, entrada de texto y adjuntos. La pantalla de entrenamiento anterior queda como sección y ofrece acceso a la misma conversación. En 0.3.5 esta navegación y el dictado inicial están implementados; el motor de acciones desde el chat sigue pendiente. El soporte real de audio/visión depende del modelo configurado.

## Contratos de comportamiento

- Con Chest Press activo, «60k 13r f» registra una única serie de 60 kg, 13 repeticiones completas, al fallo. Una entrada inequívoca se procesa sin llamar al LLM ni exigir un formulario adicional.
- El motor guarda el evento antes de confirmar éxito, obtiene la hora del sistema con segundos y arranca el descanso configurado para ese ejercicio. La respuesta informa lo registrado, hora de registro y descanso restante.
- Hora de registro y final real de la serie son conceptos distintos. Si el usuario lo comunica tarde, no inventar la hora de ejecución. Conservar una hora indicada por el usuario con su procedencia.
- Comandos como «13r», «otra igual» o «bajo a 45» usan el contexto activo y reglas explícitas. Preparar un peso no crea una serie. «Casi F» no equivale a fallo y las parciales no se suman a las completas.
- El estado activo, las variantes y las máquinas se mantienen explícitos. No fusionar bilateral/unilateral, peso por lado/total, agarres o poleas diferentes por parecido del nombre.
- Una descripción ambigua se entrega al LLM con contexto e histórico recuperado. El modelo propone candidatos y, si hace falta, pide una aclaración o muestra referencias visuales. No afirmar coincidencias históricas sin evidencia.
- El LLM devuelve propuestas de acciones; el motor valida y ejecuta. El modelo no modifica SQLite o Sheets directamente, no calcula timestamps y no declara guardado sin un resultado verificado.
- Persistencia, correcciones y sincronización son deterministas e idempotentes. Los reintentos no duplican series y añadir una sesión no sobrescribe filas antiguas.
- Distinguir guardado local, pendiente de sincronización y escritura verificada en Sheets. Sin Internet o sin IA se puede continuar el registro básico.

## Google Sheets por usuario · prioridad confirmada el 08/10/2026

Las hojas pueden tener estructuras diferentes según el usuario. El LLM debe entender la hoja elegida, relacionar su contenido con los datos de GymIA y aprender cómo mantenerla actualizada en su formato original. La prioridad no es solo importar: el usuario debe poder seguir usando su hoja tal cual, también fuera de GymIA.

El agente debe generar y conservar una **skill por usuario y hoja**: un perfil versionado que describe la estructura, las convenciones de lectura y las reglas de escritura. No es código arbitrario generado por el modelo ni una plantilla única impuesta a todos. El LLM interpreta y propone; el motor de la app valida, guarda y ejecuta las operaciones. El contrato detallado y los criterios de aceptación están en [agente de hojas](../../01-sheet-agent/spec.md).

Si no existe una hoja, el asistente puede sugerir crearla y proponer una estructura inicial. Crear una hoja es una acción explícita del usuario, no una condición para usar el chat ni un motivo para reemplazar una hoja existente.

### Hoja de referencia para pruebas

Fuente histórica identificada: hoja personal de prueba (nombre e ID omitidos); pestaña moderna Registro 2026. Lectura API real verificada en 0.3.8: 111 filas. Encabezados: Fecha, Sesión, Grupo, Ejercicio, Calentamiento, Serie 1–4, Notas; una fila por ejercicio. Esta hoja es un ejemplo para validar el agente, no el contrato universal del producto.

El adaptador debe conservar el original y reconocer series múltiples, fallo, parciales, cargas por lado, calentamientos y notas. Hay sesiones con etiquetas textuales (7A, 16A), repeticiones desconocidas, cardio y más de cuatro series. No descartar o completar esos casos silenciosamente. Mantener trazabilidad y presentar conflictos antes de resolverlos.

### Interpretación de hojas con ayuda del LLM · confirmado por el usuario

Si el lector determinista no reconoce la estructura o no puede interpretar una parte de la hoja, debe poder recurrir al modelo. No exigir al usuario que transforme manualmente la hoja para ajustarla al importador. Obtener primero sus celdas con la autorización Google; facilitar al LLM encabezados, bloques, valores originales y contexto de las pestañas relevantes. El acceso Google y la descarga siguen siendo responsabilidad de la app: el modelo interpreta los datos recuperados, no sustituye los permisos OAuth.

El LLM puede proponer relaciones entre columnas, separación de bloques, agrupación de sesiones e interpretación de series o notas. Debe devolver un plan de lectura y registros estructurados con referencias a las celdas de origen y las dudas pendientes. El motor comprueba tipos, rangos, integridad y duplicados; no toma una interpretación semántica como certeza por el mero hecho de pasar esas comprobaciones. La vista previa permite al usuario revisar qué se ha entendido y resolver ambigüedades antes de confirmar.

No inventar repeticiones, fechas, cargas, variantes ni datos ausentes. Conservar el original y los casos que no puedan resolverse. Tratar el contenido de la hoja como datos, nunca como instrucciones que otorguen al modelo permisos o habiliten escrituras. Informar en la interfaz de que interpretar con IA envía el contenido relevante al proveedor configurado; no enviar pestañas ajenas al entrenamiento por defecto.

Una interpretación puede convertirse en la skill reutilizable de esa hoja. Debe incluir tanto importación como actualización, referencias al origen, dudas y reglas confirmadas. Detectar cambios de estructura y volver a interpretar antes de aplicar un perfil incompatible. En 0.3.8 el chat puede recibir las celdas originales para consultarlas; la generación y persistencia de skills y su uso como adaptador de lectura/escritura siguen pendientes.

La escritura debe conservar N series e identificar registros sin depender solo del número visual de fila. La skill especifica los destinos permitidos, cómo ampliar una sesión y qué conservar. El motor comprueba cambios externos, ejecuta operaciones idempotentes y verifica el resultado. El momento automático de sincronización y el alcance de correcciones requieren una política concreta; no quedan decididos por esta visión.

## Implementado y pendiente

Implementado hasta 0.3.8: SQLite local, sesiones manuales, series con peso/reps, historial, rutinas, temporizador manual persistente, copias e importador tabular. Chat como pantalla principal, proveedores configurables, claves protegidas, conversación persistida, dictado y adjuntos según las capacidades del modelo. Lectura Android de Google Sheets verificada con autorización real en el emulador: selección de archivo y pestaña, 111 filas originales, copia persistida y nueva lectura tras reinicio. El chat recibe esa copia para interpretarla; no importa registros ni ejecuta herramientas. La prueba de lectura en el emulador no equivale a una llamada real al LLM en ese dispositivo, donde no hay proveedor configurado.

Pendiente: skills por usuario/hoja, importación semántica a registros con trazabilidad, escritura/sincronización verificada y creación opcional de hojas. También registro conversacional determinista, fallo/parciales y tiempos por serie, descanso automático, variantes y máquinas explícitas, y herramientas validadas del LLM. La conexión Google está probada en el emulador; falta comprobarla en el teléfono. La APK solicita permisos de lectura; deberá solicitar escritura cuando el motor de escritura esté listo.

## Secuencia propuesta de trabajo

Seguir SPEC → PLAN → TASKS → IMPLEMENT → TEST → VERIFY. Prioridad de producto confirmada: asistente LLM y conversación por texto/voz como experiencia principal. Con el chat y la lectura Google disponibles, el siguiente bloque prioritario es aprender la estructura de cada hoja y mantenerla actualizada, ampliando el modelo de datos y las herramientas deterministas necesarias. No limitar el desarrollo a un importador del formato Registro 2026. Las gráficas, reloj y análisis de ejecución quedan después de este flujo; no se dan por implementados.

## Criterio de aceptación del primer flujo conversacional

Iniciar una sesión, seleccionar Chest Press, enviar «60k 13r f», comprobar una única serie persistida con fallo y hora del sistema, ver descanso automático y recuperar todo tras cerrar la app. Repetir el evento no duplica la serie. Enviar «bajo a 45» prepara el peso sin añadir una serie. Todo este recorrido funciona sin red ni llamadas al LLM.
