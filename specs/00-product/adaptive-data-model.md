> Antecedente de GymIA: conserva el alcance y estado de su versión. La evolución futura se rige por el [SDD de TrackIA](../003-trackia-platform/spec.md); este documento no acredita funciones nuevas.

# Modelo de actividad adaptable · IA como núcleo

Fecha: 08/10/2026. Requisito confirmado: el LLM es el centro de GymIA y adapta las actividades, métricas y representación en Sheets a cada usuario. Este documento propone el contrato técnico. No implica que la migración, las herramientas adaptativas o los conectores estén implementados.

Ampliación confirmada: los ejemplos de actividades/métricas son ilustrativos y abiertos. El progreso incluye observaciones diarias procedentes de varias fuentes aunque ese día no haya sesión de gimnasio. Los pasos del teléfono son un ejemplo, no una excepción que deba resolverse creando un entrenamiento ficticio.

## Decisión de diseño propuesta

Modelo lógico de documentos con núcleo estable y definiciones extensibles por usuario. Mantener inicialmente SQLite como almacenamiento local, combinando campos indexados con documentos JSON versionados y validados en Dart. No crear tablas físicas distintas por usuario ni obligar a todas las actividades a contener peso y reps.

Tener distinto número de ejercicios por sesión ya es compatible con un modelo relacional de uno a muchos. El problema actual es semántico: WorkoutSet exige weight y reps; finalizar exige al menos una serie. Cambiar únicamente el motor a NoSQL no resuelve esas reglas ni define cómo interpretar nuevas métricas.

SQLite puede almacenar JSON como texto. No asumir que todos los dispositivos tienen las mismas funciones JSON o JSONB: validar en la aplicación, comprobar capacidades antes de depender de funciones nativas y proyectar los campos necesarios para consultas. El motor físico puede cambiar después sin cambiar los contratos del agente.

Referencia técnica: [JSON en SQLite](https://www.sqlite.org/json1.html). La recomendación de conservar SQLite es una decisión de ingeniería para esta app, no una obligación de esa documentación.

## Entidades comunes

- Usuario/perfil: preferencias, tipos de actividad y métricas configuradas, unidades de presentación, revisiones y conexiones autorizadas.
- Sesión: ID, usuario, nombre, estado, fechas/procedencia, lista ordenada de actividades. Puede mezclar fuerza, cinta y una clase; no exige el mismo número ni tipo de actividades cada día.
- Actividad: ID, sesión, definición/revisión, nombre y variante/máquina cuando corresponda; métricas y lista opcional de bloques o registros. Una clase puede ser una actividad completa sin series.
- Registro/bloque: serie, intervalo, vuelta, ronda, postura u otro segmento definido. Puede tener métricas diferentes según su tipo; no requiere reps para un intervalo de carrera.
- Medición: clave semántica, valor tipado, unidad cuando corresponda, estado del dato, origen y tiempo conocido. Distinguir medición, dato declarado y cálculo/estimación. Conservar el texto original cuando ayude a interpretarlo.
- Observación independiente: medición puntual o de un intervalo, sin sesión obligatoria. Puede proceder de sensor, conector, hoja o declaración del usuario. Mantener periodo, zona horaria, cobertura conocida, fuente/revisión y vínculo opcional a una actividad.
- Resumen diario: vista o registro derivado de observaciones y actividades del usuario, con reglas de agregación explícitas y procedencia. Puede tener pasos sin entrenamiento; no es un WorkoutSet ni requiere una sesión para existir.
- Definición de actividad/métrica: ID estable, revisión, significado, tipo de valor, unidades admitidas, aplicabilidad, validaciones y presentación. Campos habituales normalizados y extensiones del usuario.
- Evento/operación: intención y resultado persistidos con ID estable, revisión de datos y estado de sincronización. Evita duplicados y permite reanudar escrituras.

Los vínculos a Sheets y otras fuentes tienen identidad/procedencia propias. El formato de la hoja no define la identidad local de una sesión. La skill relaciona las dos representaciones.

Un usuario puede entrenar varias veces al día con actividades distintas. La sesión es una entidad individual con ID, no «el entrenamiento de la fecha». Gimnasio por la mañana y fútbol/natación por la tarde conservan sus propios registros y métricas; comparten usuario, periodos y objetivos para analizar progreso. El resumen diario no fusiona ni sustituye esas sesiones. [Inicio/cierre y sincronización](session-lifecycle.md).

## Fuentes múltiples y progreso sin entrenamiento

El modelo lógico admite datos fuera de las sesiones: pasos diarios, mediciones puntuales u otras métricas que el usuario quiera incluir. No obligar a toda observación a seguir sesión → actividad → serie. Las definiciones por usuario indican su alcance (registro, actividad, intervalo o día), unidad, origen y cómo se utiliza en el progreso. Las categorías iniciales no son un catálogo cerrado.

El agente puede descubrir conectores implementados, explicar disponibilidad, proponer conectar una fuente, solicitar autorización mediante el flujo de la plataforma y configurar qué leer y cómo representarlo. No puede acceder a cualquier aplicación por describirla ni generar un conector operativo desde una instrucción libre. Una fuente nueva necesita un adaptador compatible con su API/sensor/formato y condiciones de acceso. El modelo interpreta la semántica y adapta el perfil; el adaptador obtiene los datos y el motor valida, calcula y persiste.

Para pasos diarios, una regla persistente propuesta por el agente puede significar: obtener el total disponible del día, guardar una observación/resumen y mantener una fila en la hoja según su skill. Una vez configurada, la app ejecuta lecturas y actualizaciones deterministas sin llamar al LLM por cada paso ni por cada sincronización. El modelo consulta después los resúmenes para explicar el progreso y proponer cambios según los objetivos del usuario.

No sumar sin más teléfono + reloj + aplicación: pueden representar los mismos pasos. Cada métrica define prioridades y resolución de solapamientos. Con Health Connect, usar agregación para pasos y conservar la procedencia y política aplicada. [Lecturas agregadas y deduplicación](https://developer.android.com/health-and-fitness/health-connect/aggregate-data). No asumir que esa deduplicación resuelve todos los tipos de datos o fuentes ajenas a Health Connect.

La identidad de un resumen diario incluye usuario, métrica/alcance y periodo definido. Releer actualiza el mismo resumen y su fila; no añade una fila cada vez. Conservar revisiones y cambios de fuente. Datos tardíos pueden corregir días previos sin duplicarlos. No confundir la observación original con el agregado ni volver a sumar el agregado con sus componentes.

Definir límites del día y zona horaria; considerar viajes y días que no duran 24 horas. Diferenciar total parcial del día en curso, periodo completo conocido y cobertura incompleta. No declarar cero pasos si falta permiso, no hay datos o el sensor no estuvo registrado. No prometer ejecución exacta a medianoche: Android puede diferir trabajo en segundo plano; sincronizar con el periodo correcto cuando se ejecute y recuperar días pendientes.

### Xiaomi 11T Pro del usuario · viabilidad pendiente de probar

El usuario indica que su teléfono muestra pasos diarios. Eso no demuestra que GymIA pueda leer el histórico de la aplicación que los muestra. Comprobar en el teléfono versión Android, fuente de esos pasos y vías de exportación/integración antes de prometer el mismo total.

Opciones documentadas de Android:

- Health Connect permite leer registros y totales de pasos autorizados. Su conteo propio en el dispositivo requiere Android 14 y SDK Extension 20 o superior; comprobar capacidades reales. Si la aplicación del usuario publica sus pasos allí, evaluar esa fuente. [Guía de pasos](https://developer.android.com/health-and-fitness/health-connect/features/steps).
- Sensor TYPE_STEP_COUNTER, si está disponible, con ACTIVITY_RECOGNITION en Android 10 o superior. Es acumulado desde el reinicio mientras el sensor estuvo activado, no un historial diario de la app Xiaomi. Necesita seguimiento, referencias de contador, manejo de reinicios y cobertura; una lectura actual no permite reconstruir los días previos. [Sensor de pasos](https://developer.android.com/develop/sensors-and-location/sensors/sensors_motion).

No escoger una vía silenciosamente como equivalente a la otra. Mostrar origen y cobertura del dato y permitir al usuario definir qué fuente quiere usar. Esta viabilidad aún no está probada en su Xiaomi.

## Ejemplos de perfiles

| Actividad | Datos posibles | Estructura |
| --- | --- | --- |
| Chest Press | Carga, base de carga total/por lado, reps completas, parciales, esfuerzo/fallo, calentamiento, descanso | Series |
| Cinta | Duración, distancia, velocidad, inclinación, energía indicada por máquina, pulso | Actividad continua o intervalos |
| Spinning | Duración, resistencia declarada, cadencia, potencia, pulso y energía cuando existan | Clase continua o bloques |
| Yoga/Pilates | Duración, modalidad, instructor, dificultad percibida, notas; posturas/bloques opcionales | Clase sin reps obligatorias |
| CrossFit | Duración, rondas, movimientos, reps, cargas, límites de tiempo, modalidad del circuito | Bloques con registros de tipos distintos |

Son ejemplos iniciales, no una lista cerrada ni campos obligatorios universales. Las preferencias del usuario determinan qué recoge. No mostrar métricas irrelevantes ni llenar una clase de yoga con reps=0 o peso=0.

Para fuerza, no reducir esfuerzo a un booleano que pierda «casi fallo» o «no informado». Admitir fallo, cerca del fallo, sin fallo declarado y desconocido; opcionalmente RIR/RPE con su definición. En cardio, fallo de fuerza puede no aplicar.

Ausente, desconocido, no recogido y no aplicable son estados distintos de cero. No exigir informar todos para guardar una actividad: algunos campos permiten ausencia y otros deben aclararse para una operación concreta. Calorías no indicadas no se inventan; calorías de máquina o estimadas conservan ese origen. Duración transcurrida y en movimiento, velocidad media y velocidad fijada en la cinta son conceptos distintos.

## Qué puede adaptar el modelo

El LLM puede proponer una definición de cinta para un usuario que quiera tiempo/distancia y ampliar esa definición después para añadir inclinación. También puede crear una definición personalizada para una actividad no prevista. Devuelve cambios declarativos tipados: nombre, significado, campos, unidades, validaciones y cómo se representan en la hoja.

El motor valida y guarda la revisión de la definición, registra los valores y actualiza las vistas desde esa definición. Reutiliza métricas estándar cuando signifiquen lo mismo; evita duplicar «tiempo», «duración» y «minutos» por cambios de etiqueta. Si el significado es diferente, crear una clave distinta. No permitir SQL, código, migraciones físicas o fórmulas ejecutables arbitrarias propuestas por el modelo.

Cada registro referencia la revisión de definición con que se creó. Cambiar una unidad o etiqueta no reinterpreta automáticamente el histórico. Conservar valores originales y convertir mediante reglas conocidas; un cambio de significado exige otra definición o una migración explícita y trazable.

La configuración del usuario amplía campos y presentación, pero no cambia IDs, procedencia, reglas de persistencia ni permisos. Las consultas de progreso usan métricas comparables, unidades compatibles y variantes equivalentes. No sumar tiempo de una actividad y de sus intervalos como si fueran dos entrenamientos: las definiciones especifican el alcance y las proyecciones de agregación.

## Ejemplo conversacional y Sheets

Usuario: «Hoy también hice 20 minutos de cinta, 2 km y la máquina marcaba 140 kcal. Quiero guardar la cinta a partir de ahora».

1. El agente reconoce cardio, reutiliza o propone su definición de cinta y registra duración, distancia y energía con origen declarado/máquina. No exige reps, no inventa velocidad fijada ni pulso. Un cálculo de velocidad media, si se necesita y es compatible con los tiempos, lo realiza la app y lo etiqueta como derivado.
2. La app guarda una actividad de cinta dentro de la sesión actual, junto a las actividades de fuerza. El número de actividades de otra sesión puede ser distinto.
3. La skill de la hoja prepara una fila o bloque compatible con su estructura. Usa los destinos existentes para tiempo/distancia/energía; si faltan, propone añadir columnas o un bloque adecuado según lo que quiera el usuario. No pone minutos en «Serie 1» como reps ni reemplaza la hoja.
4. El motor valida, conserva fórmulas y notas, detecta conflictos y verifica la escritura antes de confirmar Sheets. La nueva regla queda en la skill para futuras sesiones.

La intención del usuario autoriza registrar lo expresado. La autorización para modificar la estructura de su hoja debe quedar clara; no repetir confirmaciones de una acción ya especificada, pero tampoco derivar un permiso para reestructurar todo el libro de una entrada de entrenamiento.

## Integraciones de salud y deporte

Diseñar conectores independientes que conviertan datos autorizados a estas entidades, conservando IDs externos y procedencia para no duplicar una actividad registrada también por el usuario. Importar no equivale a enviar al proveedor LLM: mantener alcance de autorización y elegibilidad por origen. Los cálculos deterministas no requieren subir cada muestra de pulso al modelo.

- Android: Health Connect dispone de tipos de ejercicio, distancia, velocidad y energía, con permisos por tipo. [Tipos y permisos oficiales](https://developer.android.com/health-and-fitness/health-connect/data-types).
- iOS: HealthKit proporciona acceso a entrenamiento/datos de salud mediante autorización. [HealthKit](https://developer.apple.com/documentation/healthkit), [autorización](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data).
- Strava: la API usa OAuth, pero su política vigente al consultar el 08/10/2026 restringe incorporar datos de la API al contexto de aplicaciones IA (§5.3). Su MCP tiene una excepción para uso personal y no habilita acceso de terceros/comercial (§3.5). No prometer el flujo API → LLM de GymIA ni eludir la restricción copiando esos datos a Sheets. Evaluar un acceso permitido antes de incluirlo como función. [Autorización](https://developers.strava.com/docs/authentication/), [política API](https://www.strava.com/legal/api_policy).

Estos conectores son posibilidades de arquitectura, todavía no funciones implementadas. HealthKit/Health Connect tampoco garantizan que toda métrica de cualquier dispositivo esté disponible o que toda utilización del dato sea admisible con solo autorizar la lectura.

## Orden de implementación

1. Definir contrato de documentos, catálogo extensible de métricas y definiciones por usuario; incluir fuerza, cardio, clase sin series y observaciones independientes/resúmenes diarios en pruebas.
2. Migración aditiva y compatible de los datos existentes. Mantener IDs, kilos y reps exactos; datos no informados siguen desconocidos. Adaptar repositorio, finalización, histórico, copias y restauración al mismo contrato.
3. Herramientas del agente para proponer/ampliar definiciones y registrar actividades. Validaciones y vistas generadas por definición; no exigir una pantalla de formulario distinta para cada deporte.
4. Vincular las definiciones y registros a la skill de lectura/escritura de cada hoja y verificar una sesión mixta en una hoja de prueba.
5. Integrar conectores cuando haya acceso, permisos y pruebas adecuados. No bloquear el registro conversacional de cinta/yoga esperando Strava o HealthKit.

Aceptación mínima: una sesión de fuerza+cinta, una clase de yoga sin reps, una actividad personalizada y un día con pasos pero sin entrenamiento se guardan y recuperan. Las definiciones permanecen y respetan el histórico al revisarse. Sheets recibe una representación compatible verificada, con una sola fila por resumen diario configurado; releer actualiza en lugar de duplicar. No se confunden ausencias con cero, estimaciones con mediciones ni fuentes solapadas con actividad adicional.
