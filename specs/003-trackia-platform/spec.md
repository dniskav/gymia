# Feature Specification: TrackIA — espacios y actividades adaptables

**Feature Branch**: sin cambio de rama; identificador de feature `003-trackia-platform`

**Created**: 2026-10-20

**Status**: implementación por incrementos; bienvenida US9 implementada en el checkout y verificada en emulador; las demás historias siguen pendientes

**Input**: Evolucionar GymIA a TrackIA para usos personales diversos; configurar espacios,
personalidades sugeridas o propias, destinos de datos independientes, controles con
etiquetas adaptables, tiempo de actividad y descanso opcionales, ciclos y otras piezas
combinables. Añadir bienvenida por diapositivas, con «No volver a mostrar».

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Explicar mi intención y preparar una actividad propia (Priority: P1)

Quiero explicar al asistente lo que voy a hacer para que proponga una actividad útil sin
elegir una categoría obligatoria. También puedo editarla o configurarla manualmente
como apoyo, y conservar registros locales si se interrumpe la conexión.

**Why this priority**: la generalización debe aportar una actividad útil sin depender de
que el equipo haya creado una plantilla específica para mi caso.

**Independent Test**: el asistente propone una actividad fuera del gimnasio, la app
valida su configuración y el usuario la inicia y guarda una nota; ante una caída de
conexión, puede consultar lo guardado y continuar registros locales básicos.

**Acceptance Scenarios**:

1. **Given** una intención clara comunicada al asistente, **When** propone «Revisar mi
   colección», **Then** veo una configuración sin temporizador ni métricas forzadas;
   prepararla no inicia ningún reloj.
2. **Given** una propuesta validada, **When** la inicio y se corta la conexión con IA,
   **Then** puedo consultar lo guardado y completar notas locales sin perder la actividad.
3. **Given** una propuesta con una capacidad ausente, **When** intento utilizarla,
   **Then** se explica el límite y puedo adaptar la propuesta sin perder lo escrito.

### User Story 2 - Cambiar de espacio y de acompañamiento (Priority: P1)

Quiero un espacio para una intención y otro para otra, con conversaciones y personalidad
propias. Puedo escoger una personalidad sugerida, editarla o crearla desde cero.

**Why this priority**: evita que una misma persona reciba indicaciones de entrenador al
buscar otro tipo de acompañamiento, o que otra cuenta herede sus recuerdos.

**Independent Test**: alternar dos espacios con personalidades distintas y comprobar que
cada uno recupera su conversación, borrador y configuración, sin recuerdos del otro.

**Acceptance Scenarios**:

1. **Given** dos espacios, **When** cambio entre ellos, **Then** recupero el chat y sus
   preferencias; no se copia el historial del espacio anterior.
2. **Given** una personalidad personalizada, **When** cambio tono o nivel de detalle,
   **Then** cambia el acompañamiento futuro, no los resultados registrados ni permisos.
3. **Given** información de otro espacio, **When** autorizo consultarla explícitamente,
   **Then** el asistente recibe solo el alcance elegido e identifica su procedencia.

### User Story 3 - Configurar tiempo, etapas, descansos y ciclos (Priority: P1)

Quiero activar solo las piezas útiles: tiempo libre o definido, etapas sin reloj,
descanso opcional y repetición opcional. Los nombres deben encajar con mi actividad.

**Why this priority**: un mismo motor sirve para intenciones nuevas sin convertirlas
forzosamente en ejercicio, serie y descanso.

**Independent Test**: ejecutar una secuencia con etapa cronometrada, pausa opcional y
etapa manual, con y sin ciclos; comprobar los efectos reales de los controles.

**Acceptance Scenarios**:

1. **Given** una duración definida, **When** inicio y pauso, **Then** la cuenta atrás
   conserva el restante y distingo actividad pausada de etapa de descanso.
2. **Given** un cronómetro o una etapa sin tiempo, **When** avanzo manualmente,
   **Then** la siguiente etapa no necesita una duración inventada para comenzar.
3. **Given** ciclos desactivados y descanso desactivado, **When** finalizo,
   **Then** no aparecen pausas ni repeticiones añadidas por la app.
4. **Given** avance automático configurado para un plan que yo inicié, **When** vence
   la etapa, **Then** ocurre una sola transición, se muestra la siguiente fase y queda
   registrado que el avance fue por tiempo, sin una llamada al asistente.
5. **Given** etiquetas adaptadas como «Bloque» o «Práctica», **When** pulso Pausar,
   **Then** siempre pausa; el cambio de texto no altera el significado de la acción.

### User Story 4 - Conservar lo que realmente registré (Priority: P1)

Quiero registrar cantidades, texto, listas, sensaciones y adjuntos que tengan sentido
para mí, incluidos datos independientes de una sesión o un temporizador.

**Why this priority**: actividades diversas dejan evidencias diferentes; no todo es una
medición ni toda observación corresponde a una actividad en ejecución.

**Independent Test**: guardar un registro numérico con unidad, una observación libre y
una lista; corregir su interpretación y recuperar sus originales tras reiniciar.

**Acceptance Scenarios**:

1. **Given** una observación sin sesión, **When** la guardo, **Then** no se crea un
   entrenamiento ficticio ni se exige peso, repeticiones o duración.
2. **Given** una sugerencia y un resultado, **When** consulto el historial,
   **Then** se distinguen el objetivo previsto, lo registrado y su procedencia.
3. **Given** una plantilla revisada, **When** abro una ejecución anterior,
   **Then** conserva los campos, unidades y significado con los que se registró.

### User Story 5 - Elegir dónde guardar cada cosa (Priority: P2)

Quiero guardar localmente o vincular distintos espacios y actividades a hojas distintas.
También puedo reunir actividades compatibles en una misma hoja si lo configuro.

**Why this priority**: separar acompañamiento no obliga a duplicar cuentas ni a usar
una única hoja para datos con estructuras diferentes.

**Independent Test**: asignar dos destinos a dos espacios, generar registros y verificar
que cada envío llega únicamente al destino capturado al solicitarlo.

**Acceptance Scenarios**:

1. **Given** una cuenta y dos hojas autorizadas, **When** vinculo un espacio a cada una,
   **Then** leer y escribir usa su destino; las conexiones no mezclan cachés ni trabajos.
2. **Given** una actividad con destino propio, **When** el espacio tiene otro,
   **Then** se muestra la elección explícita de la actividad antes de enviar.
3. **Given** un trabajo pendiente y un cambio de hoja, **When** reintento,
   **Then** no se redirige silenciosamente al nuevo destino.
4. **Given** ausencia de hoja, **When** registro una actividad,
   **Then** se guarda localmente y puedo conectar o crear una hoja después.

### User Story 6 - Interrumpir y volver sin perder el estado (Priority: P1)

Quiero que una interrupción, un cambio de espacio o una caída del proveedor no borren
lo que hago ni provoquen avisos, registros o transiciones duplicados.

**Why this priority**: el reloj y los registros deben ser fiables incluso sin asistente.

**Independent Test**: pausar, cerrar, reabrir y recuperar una ejecución; provocar
respuesta tardía y falta de red conservando su contexto y registros.

**Acceptance Scenarios**:

1. **Given** una ejecución en marcha, **When** cambio de espacio,
   **Then** no se detiene ni se traslada; veo que sigue activa y cómo volver a ella.
2. **Given** el límite inicial de una ejecución activa por perfil, **When** intento
   iniciar otra, **Then** puedo volver a la activa o resolverla explícitamente.
3. **Given** una respuesta de IA iniciada en otro espacio o etapa, **When** llega tarde,
   **Then** no altera el espacio o etapa que ahora está visible ni ejecuta acciones obsoletas.
4. **Given** un cambio de hora o una recuperación incierta, **When** reabro,
   **Then** se informa de la incertidumbre sin inventar tiempo realizado.

### User Story 7 - Actualizar GymIA conservando mis datos (Priority: P1)

Quiero reconocer TrackIA como evolución de mi app y conservar entrenamientos, cuentas,
preferencias y archivos, sin repetir trabajo ni perder acceso al modo gimnasio.

**Why this priority**: una generalización no justifica romper la experiencia entregada.

**Independent Test**: actualizar una instalación con datos anteriores y comparar IDs,
valores, originales, cuentas y preferencias antes y después de la migración autorizada.

**Acceptance Scenarios**:

1. **Given** una instalación GymIA con histórico, **When** llega la actualización de
   nombre visible, **Then** se instala como actualización y los datos siguen disponibles.
2. **Given** una futura asignación a espacios, **When** reviso su vista previa,
   **Then** se propone un espacio Gimnasio sin atribuir datos locales a otra cuenta.
3. **Given** una copia antigua, **When** la restauro mediante el flujo correspondiente,
   **Then** conserva sus originales y no activa conexiones remotas automáticamente.

### User Story 8 - Ampliar experiencias sin promesas ficticias (Priority: P3)

Quiero poder incorporar secuencias, decisiones o tiempos simultáneos cuando una actividad
los necesite, y saber cuándo una experiencia requiere una capacidad todavía ausente.

**Why this priority**: el diseño debe permitir crecer sin imponer desde el principio
un constructor complejo a quien solo necesita un registro o un temporizador.

**Independent Test**: una configuración futura de pasos condicionales o simultáneos
se acepta solo si sus capacidades están disponibles; en otro caso se conserva como
propuesta y se ofrece una alternativa compatible.

**Acceptance Scenarios**:

1. **Given** una receta con pasos solapados, **When** el motor no admite simultaneidad,
   **Then** no la ejecuta como si la admitiera y permite pasar a una secuencia manual.
2. **Given** una solicitud de guía hablada, **When** no hay capacidad de voz guiada,
   **Then** no se presenta un texto o un temporizador como si fuera audio programado.
3. **Given** una versión que habilita ramas o carriles, **When** valido un plan,
   **Then** compruebo sus límites y puedo explicar qué ocurrirá en cada alternativa.

### User Story 9 - Entender TrackIA con una bienvenida opcional (Priority: P1)

Quiero una bienvenida por diapositivas que explique para qué sirve la app y cómo empezar,
y elegir si quiero volver a verla. Puedo recuperarla después desde ajustes.

**Why this priority**: el producto ampliado necesita una explicación accesible que no
obligue a configurar una cuenta, una personalidad o una hoja antes de conocerlo.

**Independent Test**: completar, omitir, cerrar y reabrir la bienvenida, con y sin
«No volver a mostrar», y abrirla manualmente después.

**Acceptance Scenarios**:

1. **Given** una instalación sin preferencia, **When** la abro, **Then** veo diapositivas
   con Anterior/Siguiente, progreso, Omitir y Empezar; no solicita credenciales por sí sola.
2. **Given** «No volver a mostrar» marcado, **When** pulso Omitir o Empezar,
   **Then** se guarda la elección y las aperturas posteriores van a la app.
3. **Given** la opción sin marcar, **When** termino u omito y vuelvo a abrir,
   **Then** la bienvenida puede aparecer de nuevo; el comportamiento está explicado.
4. **Given** la bienvenida desactivada, **When** elijo Ver bienvenida en ajustes,
   **Then** puedo recorrerla sin que eso reactive su apertura automática.
5. **Given** datos existentes y tema claro u oscuro, **When** abro la bienvenida,
   **Then** se conserva el contexto, es legible y no interrumpe una actividad en marcha.

### Edge Cases

- Dos acciones simultáneas, doble toque o llegada del objetivo al mismo tiempo que vence
  un reloj: se registra una sola transición y se conserva el motivo ganador.
- Descanso omitido, final anticipado, ampliación o reinicio: conservar duración prevista,
  tiempo registrado y decisión, sin reescribir la ejecución anterior.
- Cambio de plantilla o personalidad durante una ejecución: mostrar qué afecta al futuro;
  el plan de la ejecución iniciada no cambia silenciosamente.
- Datos y etiquetas coincidentes entre espacios: los nombres no sustituyen a su identidad.
- Permiso externo revocado, respuesta incierta, filas movidas, formato cambiado o nueva
  cuenta: conservar datos y trabajos con estados claros, sin reintentos ciegos.
- Propuesta de código libre, widget arbitrario, acción no disponible o destino ajeno:
  rechazar la acción; conservar el texto y ofrecer configuración válida.
- La app cerrada, un reinicio del dispositivo o un aviso retrasado no prueban que la
  persona haya realizado físicamente una actividad durante ese intervalo.
- Bienvenida interrumpida: no guardar «No volver a mostrar» solo por haber marcado una
  casilla antes de abandonar; confirmar esa elección mediante Omitir o Empezar.
- Apertura mediante archivo compartido o ejecución activa: la bienvenida no bloquea el
  acceso urgente; se ofrece después sin perder el archivo o la ejecución.

## Requirements *(mandatory)*

### Functional Requirements

**Producto y configuración**

- **FR-001**: El nombre de producto objetivo DEBE ser TrackIA y el gimnasio DEBE seguir
  siendo una experiencia disponible, sin convertirse en la categoría obligatoria.
- **FR-002**: El usuario DEBE crear, editar y duplicar actividades desde plantillas abiertas
  o desde cero; una actividad desconocida no se rechaza solo por su nombre o categoría.
- **FR-003**: Toda capacidad solicitada DEBE comprobarse antes de ejecutar; no se aceptan
  planes cuyo comportamiento la app no pueda realizar.
- **FR-004**: La preparación asistida DEBE mostrar el plan sin iniciar relojes; no se exige
  un botón adicional de Preparar para repetir una intención inequívoca ya autorizada.
- **FR-005**: La conversación con IA DEBE ser el recorrido principal cuando su proveedor
  esté disponible. Si falla la conexión, consultar lo guardado y registrar datos básicos
  localmente NO DEBE exigir IA, cuenta externa ni una hoja.

**Espacios, personalidad y contexto**

- **FR-006**: Cada perfil DEBE admitir varios espacios identificados de forma estable.
- **FR-007**: Conversaciones, borradores, adjuntos, memorias y archivos DEBEN pertenecer a
  un espacio; cambiarlo DEBE recuperar su estado y no mezclarlo con el anterior.
- **FR-008**: Cada espacio DEBE permitir personalidad sugerida o personalizada; una
  actividad puede tener una elección propia explícita.
- **FR-009**: Las personalidades DEBEN configurar tono, detalle, forma de acompañar e
  instrucciones de comportamiento sin modificar permisos o hechos del historial.
- **FR-010**: Consultar información de otro espacio DEBE exigir un alcance de compartición
  elegido o una petición explícita; la respuesta DEBE identificar la procedencia.
- **FR-011**: Una respuesta tardía DEBE conservar el alcance de su petición original y no
  mutar una ejecución, etapa, perfil o espacio distinto.

**Motor y presentación**

- **FR-012**: Cada etapa DEBE poder carecer de reloj, medir tiempo libre o tener cuenta atrás.
- **FR-013**: Descansos y ciclos DEBEN ser opcionales e independientes de la categoría.
- **FR-014**: Un plan DEBE definir etapas, orden, repetición y criterio de avance; se DEBEN
  admitir avance manual, por tiempo o por cantidad registrada cuando estén habilitados.
- **FR-015**: El usuario DEBE elegir transición manual o automática antes de iniciar el plan;
  una transición automática no constituye permiso general para que el agente opere controles.
- **FR-016**: Iniciar, pausar, continuar, finalizar, omitir y ampliar DEBEN tener semántica
  estable; las acciones disponibles dependen de la fase y capacidades del plan.
- **FR-017**: Las etiquetas de actividad, etapa, tiempo y controles DEBEN ser adaptables;
  no pueden ocultar o invertir el efecto real de una acción.
- **FR-018**: La pantalla DEBE mostrar fase activa, progreso relevante y qué ocurrirá después,
  conservando la conversación y sin presentar controles que no correspondan.
- **FR-019**: El motor DEBE conservar plan aceptado y revisiones; editar la plantilla no
  modifica una ejecución iniciada sin una operación explícita compatible.
- **FR-020**: Sonido, vibración y silencio DEBEN ser opciones para avisos; su disponibilidad
  real depende de permisos y capacidad del dispositivo.
- **FR-021**: El motor DEBE resolver una transición una sola vez aunque coincidan varios
  disparadores o se repita una petición.

**Datos, interrupciones y compatibilidad**

- **FR-022**: Un registro DEBE admitir datos definidos por el usuario, texto y evidencias
  compatibles; no se exige que todas las actividades tengan cifras ni temporizador.
- **FR-023**: DEBEN poder guardarse observaciones independientes de una ejecución.
- **FR-024**: Originales, interpretación, objetivo y resultado DEBEN distinguirse, con
  unidades y procedencia; ausencia de dato no equivale a cero.
- **FR-025**: El estado confirmado DEBE sobrevivir a interrupciones; recuperar una ejecución
  no genera nuevos registros o avisos repetidos por sí mismo.
- **FR-026**: La recuperación DEBE distinguir tiempo previsto, tiempo registrado e incierto;
  no puede afirmar ejecución física solo porque avanzó un reloj.
- **FR-027**: Cambiar de espacio DEBE mantener visible la existencia de una ejecución en marcha;
  iniciar otra respetará el límite de concurrencia que indique la versión instalada.
- **FR-028**: Actualizar DEBE conservar los datos, sus IDs y acceso al modo gimnasio; cualquier
  traslado de históricos DEBE tener vista previa, respaldo y recuperación comprobable.
- **FR-029**: Las copias DEBEN incluir los nuevos datos recuperables y seguir aceptando las
  versiones antiguas compatibles; restaurar no activa accesos remotos por sí solo.
- **FR-030**: Tema claro, oscuro, automático, dictado, accesibilidad y navegación existentes
  DEBEN mantenerse en los nuevos flujos.

**Destinos y capacidades**

- **FR-031**: Cada perfil DEBE poder conservar varias conexiones de datos autorizadas.
- **FR-032**: El usuario DEBE poder elegir ningún destino, destino del espacio o destino
  propio de la actividad; no se elige una hoja por semejanza de nombre o por fecha.
- **FR-033**: Una misma hoja DEBE poder vincularse explícitamente a varios espacios o
  actividades compatibles sin conceder lectura implícita de todo su contenido a cada chat.
- **FR-034**: Leer y escribir DEBE respetar cuenta, archivo, pestaña, alcance y formato
  autorizados, conservando datos ajenos y fórmulas.
- **FR-035**: Cada trabajo DEBE conservar su fuente, revisión y destino; cambiar el destino
  afecta a trabajos futuros, no redirige los pendientes silenciosamente.
- **FR-036**: La app DEBE distinguir local, pendiente, confirmado, conflicto e incierto;
  solo confirma guardado externo con evidencia y reconcilia antes de repetir.
- **FR-037**: Una personalidad o dato consultado NO DEBE ampliar permisos ni ofrecer
  capacidades ausentes; los proveedores y sus condiciones de acceso se conservan separados.
- **FR-038**: Ramas, carriles simultáneos, guía hablada y conectores DEBEN habilitarse por
  capacidad y versión cuando se implementen; su ausencia tendrá una explicación útil.

**Bienvenida**

- **FR-039**: La app DEBE ofrecer una bienvenida por diapositivas con progreso, Anterior,
  Siguiente, Omitir y Empezar, sin exigir login para recorrerla.
- **FR-040**: Las diapositivas DEBEN explicar el propósito abierto, espacios/personas,
  creación de actividad, controles y destinos opcionales, mostrando solo funciones disponibles.
- **FR-041**: «No volver a mostrar» DEBE persistirse al terminar u omitir; sin marcarlo,
  la bienvenida vuelve en aperturas posteriores, según la elección explicada en pantalla.
- **FR-042**: Ajustes DEBE permitir Ver bienvenida y cambiar su apertura automática;
  revisitarla manualmente no cambia esa preferencia.
- **FR-043**: La bienvenida DEBE ser legible en ambos temas, usable con lector de pantalla
  y texto ampliado, y no debe descartar un archivo entrante o una ejecución activa.

### Key Entities *(include if feature involves data)*

- **Perfil**: propietario del contexto y sus autorizaciones; no equivale a espacio.
- **Espacio**: ámbito de conversación, memorias, preferencias y destinos elegidos.
- **Personalidad**: comportamiento versionado, independiente de los hechos registrados.
- **Definición de actividad**: plantilla editable de campos, instrucciones y etiquetas.
- **Plan y etapa**: configuración aceptada de ejecución, criterios de avance y repetición.
- **Ejecución y evento**: estado persistido, tiempos registrados, acciones y revisiones.
- **Observación**: original y su interpretación, dentro o fuera de una ejecución.
- **Conexión y vínculo de destino**: cuenta/recurso autorizado y elección por ámbito.
- **Trabajo y recibo**: intención de efecto externo, destino capturado y resultado verificado.
- **Preferencias de bienvenida**: mostrar automáticamente, versión vista y revisión manual.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: La matriz de validación permite completar cuatro actividades construidas
  desde piezas: una sin tiempo, una continua, una con ciclos y una de pasos con cantidades;
  al menos una se crea desde cero sin plantilla específica.
- **SC-002**: En 20 cambios entre dos espacios de un perfil y dos perfiles diferentes,
  ningún chat, borrador, memoria, adjunto o destino aparece en un ámbito no autorizado.
- **SC-003**: Tras pausar y reabrir, 20 ejecuciones de prueba conservan estado y registros;
  cero transiciones duplicadas ante doble toque o disparadores simultáneos.
- **SC-004**: Las copias y migraciones de la colección de prueba conservan el 100% de IDs,
  valores y originales; los datos desconocidos siguen desconocidos.
- **SC-005**: En la prueba de dos espacios y dos destinos, todos los envíos llegan solo al
  destino capturado; reintentar un envío ya confirmado no crea otro registro.
- **SC-006**: Los controles locales responden y muestran su nuevo estado en menos de
  300 ms en al menos 95 de 100 acciones medidas en el dispositivo de referencia,
  sin contar la latencia de servicios externos.
- **SC-007**: En el dispositivo de referencia y con la app visible, la presentación del
  reloj se actualiza al menos una vez por segundo; tras recuperar la app coincide con
  los tiempos persistidos o muestra incertidumbre, sin prometer avisos exactos del sistema.
- **SC-008**: Los cuatro recorridos de bienvenida —terminar/omitir, con/sin desactivar—
  cumplen su preferencia en tres aperturas seguidas; Ver bienvenida funciona después.
- **SC-009**: Una configuración requiere como máximo dos acciones de navegación desde el
  chat para entrar en el selector de espacio o en Apariencia/Ayuda, excluido editar datos.

## Assumptions

- La IA es el centro de la experiencia. El modo local mantiene continuidad y datos si
  se pierde la conexión; no se presenta como sustituto del asistente. El uso de IA depende
  de conexión, proveedor configurado y sus autorizaciones reales.
- Requisitos de producto acordados en esta conversación; el orden y arquitectura del plan
  son propuestas revisables. Ninguna función nueva se declara entregada por este SDD.
- Primera entrega general: planes lineales, una ejecución activa por perfil, varios espacios.
  Cambiar de espacio no cancela esa ejecución. El límite se explica y no se usa como límite
  conceptual permanente de TrackIA.
- No hay selección automática de espacio por horario ni compartición general de memorias.
  Se pueden añadir posteriormente como opciones explícitas.
- Cada actividad elige un destino efectivo por operación en la primera entrega; envío a
  varios destinos a la vez queda para otra capacidad, sin cambiar el modelo de identidades.
- Bienvenida propuesta de cinco diapositivas; cantidad editable según contenido real.
  «No volver a mostrar» se aplica al dispositivo y no se revoca silenciosamente al actualizar.
- Audio guiado con pausas, sensores, reloj y colaboración requieren capacidades propias;
  no se consideran incluidos por disponer de voz de entrada o temporizadores.
- La app actual sigue siendo GymIA 0.3.22; el cambio visible de nombre será una entrega
  posterior que conserve instalación, autorizaciones y datos.
