# TrackIA Constitution

## Core Principles

### I. Actividades abiertas y capacidades explícitas

TrackIA DEBE representar intenciones y actividades mediante piezas reutilizables.
Las plantillas sugeridas NO DEBEN ser un catálogo cerrado ni imponer campos de
un deporte a otra actividad. Una capacidad solo se anuncia cuando existe un
adaptador o motor implementado y validado; una descripción del modelo no la crea.

### II. Conversación y ejecución determinista

El asistente propone, interpreta y acompaña. La app DEBE validar y ejecutar los
relojes, transiciones, cálculos, registros y operaciones externas. El progreso de
un temporizador NO DEBE depender de una respuesta del modelo. Los registros y
controles locales configurados DEBEN seguir siendo utilizables sin IA ni red.

### III. Espacios e identidad sin mezclas implícitas

Perfil propietario, espacio TrackIA, cuenta Google y registro ChatGPT son
identidades distintas. Cada operación DEBE capturar su propietario y alcance.
Chats, memorias, personalidad y destinos pertenecen a su ámbito; consultar otro
espacio exige un alcance explícito. Cambiar de espacio no redirige trabajos ni
mueve registros. Coincidir en email, fecha o nombre no prueba identidad.

### IV. Datos originales y compatibilidad

La app DEBE conservar originales, IDs, unidades, procedencia y revisiones.
Desconocido, no aplicable y cero son estados distintos. Las propuestas no son
hechos realizados. Cambiar una plantilla o personalidad NO DEBE reinterpretar
el pasado. Una migración requiere respaldo, comprobación y recuperación; la
modificación de históricos debe estar expresamente dentro del trabajo autorizado.

### V. Personalización subordinada a permisos

Las personalidades y etiquetas DEBEN poder adaptarse sin alterar permisos,
semántica de controles ni límites del motor. Ningún prompt, adjunto o celda
puede conceder acceso a otra cuenta, ejecutar código libre o fingir un resultado.
La app DEBE distinguir contenido consultado de instrucciones autorizadas.

### VI. Persistencia local y efectos externos verificables

Guardar localmente, pendiente, conflicto y confirmado remotamente DEBEN ser
estados diferentes. Una operación externa captura destino y revisión inmutables.
Ante respuesta incierta se reconcilia antes de repetir. No prometer atomicidad
entre servicios ni ausencia universal de duplicados con escritores independientes.
Los tokens permanecen protegidos, fuera de prompts, exportaciones y logs.

### VII. Interfaz adaptable y accesible

La interfaz DEBE mostrar solo controles pertinentes, fase activa, estado y efecto
de la siguiente acción. Las etiquetas no sustituyen a las acciones semánticas.
El cambio de tema, espacio o personalidad NO DEBE borrar chat, borradores o
actividad. Claro, oscuro, automático, lectura de citas y navegación accesible
se conservan como parte de la calidad de cada entrega.

### VIII. Evidencia antes de afirmar disponibilidad

Cada entrega DEBE vincular requisitos, tareas, criterios y evidencia. Pruebas con
transportes simulados no prueban consentimiento ni servicio real; compilar iOS
no equivale a haberlo probado. Los documentos DEBEN distinguir estado entregado,
objetivo acordado y propuesta de implementación. No marcar una tarea realizada
por haber escrito su especificación.

## Product and Compatibility Boundaries

El nombre de producto objetivo es TrackIA. La base entregada sigue siendo GymIA
0.3.22+25 en Android. El gimnasio se conserva como plantilla y experiencia de
compatibilidad. El repositorio, paquete Android, firma, claves de almacenamiento,
IDs de protocolos y clientes OAuth no se renombran automáticamente al cambiar
el nombre visible. Las integraciones existentes y el perfil local permanecen.

Esta constitución no convierte audio guiado, sensores, colaboración, reloj,
automatizaciones de terceros o ejecución exacta en segundo plano en funciones
entregadas. Se diseñan como capacidades y etapas separadas con evidencia propia.

## Development Workflow and Quality Gates

Seguir constitución → especificación → aclaraciones necesarias → plan → tareas →
análisis → implementación autorizada → verificación. El alcance de esta entrega
es el SDD; no incluye renombrar la app instalada ni migrar sus datos.

Antes de implementar una etapa, comprobar sus dependencias y requisitos. Probar
las transiciones y efectos relevantes, aislamiento, migraciones y fallos reales;
no añadir pruebas que solo reproduzcan cambios triviales. Mantener la entrega
usable y documentar qué evidencia falta. No introducir un framework genérico sin
un recorrido independiente que lo necesite y pueda verificarse.

## Governance

Esta constitución rige las nuevas especificaciones de TrackIA. Las instrucciones
del propietario y el alcance autorizado de cada tarea prevalecen. Los documentos
históricos conservan valor como evidencia de la versión que describen; la nueva
visión y los contratos vigentes resuelven contradicciones para el trabajo futuro.

Registrar en el SDD toda modificación de principios y su razón. Una redefinición
incompatible aumenta versión mayor; una ampliación, menor; una aclaración, parche.
Revisar efectos en especificación, plan, contratos y tareas, sin reescribir los
originales históricos como si hubieran descrito TrackIA desde el principio.

**Version**: 1.0.0 | **Ratified**: 2026-10-20 | **Last Amended**: 2026-10-20
