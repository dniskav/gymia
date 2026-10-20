> Antecedente de GymIA: conserva el alcance y estado de su versión. La evolución futura se rige por el [SDD de TrackIA](../003-trackia-platform/spec.md); este documento no acredita funciones nuevas.

# GymIA en el reloj · app compañera

Fecha: 08/10/2026. Añadido a la hoja de ruta por petición del usuario. Estado: fase posterior, propuesta especificada y sin implementación. Dispositivo informado y confirmado por el usuario: Xiaomi Watch 2, modelo M2320W1, Wear OS 5. Falta validar GymIA en ese hardware; recibir llamadas o controlar alarmas no constituye una prueba de funcionamiento de la app. El usuario confirma expresamente que este trabajo queda para otra fase: contemplar sus contratos ahora, sin iniciar el módulo ni desplazar el núcleo IA/datos/Sheets.

## Objetivo

Entrenar e interactuar con el mismo asistente desde la muñeca sin sacar el teléfono. La IA sigue siendo el núcleo: reloj y móvil comparten conversación, contexto y herramientas deterministas. No crear otro asistente con histórico o decisiones independientes.

Funciones solicitadas, como ejemplos abiertos: hablar al agente desde el reloj; controles para iniciar, pausar/parar y registrar; ejercicio/actividad actual; descanso restante y aviso de fin con vibración y presentación visual. La interfaz del reloj se adapta al tipo de actividad y preferencias del usuario, sin exigir peso/reps a todo registro.

## Entregas

### A. Controles y descanso

- Abrir/continuar una sesión del móvil y mostrar actividad actual, último registro y descanso.
- Botones grandes para iniciar sesión/actividad, registrar y pausar/reanudar descanso. Distinguir pausar descanso de finalizar sesión; «parar» no debe tener un efecto ambiguo.
- Registrar una serie con peso/reps/esfuerzo visibles y editables, o un bloque con los campos pertinentes de su definición. Repetir la última serie solo con esa intención explícita, no inventar datos por pulsar un botón genérico.
- Mostrar confirmación real del motor, con estado guardado en móvil o pendiente de conexión. Las operaciones pendientes nunca se anuncian como guardadas en Sheets.
- Fin del descanso: vibración, tarjeta con texto/indicador visual y actividad siguiente cuando se conozca; miniatura opcional. Respetar permisos y ajustes del sistema, incluido No molestar; no prometer vibración o encendido forzado en todas las configuraciones.
- Mantener cuenta atrás sin llamadas al LLM. Si se cambia o cancela en el móvil, actualizar el reloj y cancelar el aviso anterior.

### B. Voz al mismo asistente

- Pulsar para hablar en el reloj, obtener entrada de voz y enviarla a la conversación del móvil; mostrar transcripción y una respuesta breve adecuada a la pantalla.
- Usar el mismo contexto, parser local, definiciones adaptativas y herramientas que en el móvil. «60 kilos, 13 al fallo» usa el ejercicio activo; ante ambigüedad se pregunta en la conversación.
- La primera propuesta mantiene proveedor/credenciales y coordinación IA en el móvil. El reloj no necesita otra API key ni ejecutar un LLM local. Dictado y audio directo son capacidades distintas; elegir la ruta disponible y probada.
- Reconocimiento de voz/offline y respuesta hablada dependen del reloj, servicios y permisos. No suponer que usar su micrófono equivale a activar Bluetooth en el dictado actual del teléfono.
- Consultar y registrar por voz puede requerir conexión al móvil/proveedor; mostrar disponibilidad sin confundir el envío con una acción ejecutada.

### C. Extensiones posteriores

Acceso rápido con Tile/complicación; respuesta hablada cuando el dispositivo la admita; integrar sensores autorizados al modelo de observaciones; evaluar autonomía fuera del móvil. La versión compañera no implica entrenamiento y LLM totalmente autónomos. Pasos/pulso requieren su propio conector, permisos, cobertura y deduplicación: no se obtienen automáticamente por instalar la app del reloj.

## Propuesta técnica y consistencia

Para Wear OS + Android, evaluar un módulo de reloj nativo Kotlin/Compose y un puente Android en el móvil Flutter. Mantener Flutter para la app actual; no reescribirla para incorporar el reloj. Confirmar versiones y dependencias cuando se implemente.

Data Layer permite controles y transferencia entre reloj Wear OS y móvil Android emparejado; requiere paquetes y firma coincidentes. Definir un protocolo versionado de comandos, respuestas y estado mínimo (sesión/actividad, revisión, descanso), sin enviar todo el histórico ni secretos al reloj. Esta vía no cubre un reloj Wear OS emparejado con iPhone. [Comunicación oficial](https://developer.android.com/training/wearables/data/overview).

El móvil ejecuta y persiste las operaciones del MVP. Cada acción del reloj tiene ID estable y revisión/contexto de destino. Mantener pendientes locales y un recibo tras persistir en el móvil: los reenvíos después de desconexión no duplican series ni reinician descansos. Revalidar si cambió la sesión/actividad mientras el reloj estaba desconectado. No confiar en que el transporte proporcione por sí solo entrega exactamente una vez.

El descanso tiene ID y revisión, duración y estado compartidos. Calcular el tiempo visible con referencia temporal y ajuste de desfase, no con un contador nuevo cada vez que se abre la pantalla. Cuando el reloj ya tiene un descanso válido, proponer un aviso local para no depender de recibir un mensaje justo al terminar. Definir caducidad y reconciliación tras desconexión: un reloj desconectado podría desconocer una cancelación en el móvil, por lo que no prometer consistencia absoluta en ese caso. Evitar avisos duplicados por un mismo descanso y distinguir reloj/móvil según una política configurable.

No mantener pantalla, micrófono o conexión activos continuamente. Diseñar recuperación con app en segundo plano, pantalla apagada y límites de batería de ambos dispositivos. Verificar en el hardware real; compartir alarmas nativas no garantiza el mismo comportamiento para GymIA.

Fuentes verificadas al especificar: [entrada por voz](https://developer.android.com/training/wearables/user-input/voice), [notificaciones Wear OS](https://developer.android.com/training/wearables/notifications), [actividad en curso y temporizadores](https://developer.android.com/training/wearables/notifications/ongoing-activity). Estas APIs establecen viabilidad general, no una prueba del reloj del usuario.

## Orden y aceptación

Construir después del motor de acciones/descanso persistente del chat. Definir ahora el protocolo para reutilizar esos eventos y no duplicar reglas en el reloj. La escritura en Sheets usa la misma cola/skill del móvil y no otra implementación en el reloj.

En esa fase, validar en emulador Wear OS emparejado y después en el Xiaomi Watch 2 M2320W1 con Wear OS 5 del usuario:

- Iniciar/continuar desde reloj y ver la misma sesión en móvil.
- Registrar una acción y comprobar una sola persistencia; desconectar/reconectar/reintentar no duplica.
- Recuperar ejercicio y descanso al reabrir; cambiar pausa/duración en un dispositivo se refleja en el otro cuando hay conexión.
- Aviso visual y vibración al finalizar con pantalla apagada/móvil bloqueado en configuraciones que lo permitan; cancelar no deja un aviso obsoleto cuando el cambio se sincronizó.
- Hablar al reloj produce el mismo registro o consulta del chat; confirmar peso/reps/esfuerzo y contexto reales, sin micrófono del móvil como requisito de esa entrada.
- Sin conexión, el estado pendiente queda visible y persiste; no ejecutar después sobre una sesión distinta sin comprobarlo.
- Probar una actividad sin reps para conservar el modelo extensible, sin tratar los ejemplos iniciales como una lista cerrada.
