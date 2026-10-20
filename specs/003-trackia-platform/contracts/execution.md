# Contrato de ejecución local

## Comandos

Todos llevan commandId, runId, scope y expectedRevision: prepare, start, pause, resume,
finish, skipStage, extendStage y recordQuantity. prepare acepta plan validado y crea ready;
start exige la aceptación humana de ese snapshot. Comandos repetidos devuelven el resultado
persistido; revisión antigua devuelve conflicto y estado actual, no se reaplica.

Acciones de UI se traducen a IDs estables aunque sus etiquetas cambien. Pause congela
la duración; no crea descanso. Resume continúa el restante. Skip conserva lo parcial
con motivo y pasa de etapa. Extend agrega una duración explícita al restante y registra
la diferencia respecto al plan. Finish termina con parciales y sin inventar objetivos.

## Motor

Máquina de estados y restricciones C05–C09 en [modelo](../data-model.md). En ready,
start; en running, pause/finish/skip/extend según capacidades; en paused, resume/finish;
en waiting, avanzar/finish; en terminal, consulta sin reinicio implícito. recovery_needed
exige resolver antes de resume. Ampliar solo aplica a countdown con delta positivo
validado y duración resultante dentro del límite C06. Rest es una etapa real y opcional.

Transacción: comprobar ámbito/revisión → deduplicar commandId → validar transición →
escribir evento + estado + revisión → emitir actualización UI. Notificación usa eventId
persistido como identidad y recibo local de entrega; al recuperar no se recrean avisos
ya entregados. No se promete entrega exactamente una vez por el SO ante caída en el
límite de envío; se reconcilian IDs y se evita reproducir eventos como avisos nuevos.

Un disparador elapsed solo es válido en countdown. quantity se basa en un registro
numérico validado y deduplicado con unidad compatible; no en una interpretación física
inventada. Al coincidir ambos y un toque, gana la primera transacción válida; demás
peticiones reciben estado ya avanzado. Razón ganadora queda registrada.

## Interrupciones y límites

Una ejecución activa por perfil, incluso entre espacios. Nueva preparación incompatible
muestra conflicto: volver a la activa o finalizar/cancelar explícitamente. Cambiar perfil
no mueve ni cancela la ejecución; su recuperación permanece en su propietario.

Mientras hay proceso, usar tiempo monotónico; persistir checkpoints relevantes. En
recuperación reconciliar evidencia temporal, estado, comandos y avisos; incertidumbre
requiere resolución visible, sin falsificar duración realizada. No depender del tick
visual ni de inferencia IA para progresar. Sonido/vibración/silencio se sujetan a permisos.

API 35 ARM64 es referencia inicial de SC-006/SC-007. Pruebas cubren reloj falso, doble
toque, pausa, cierre/reinicio, cambio de hora, falta de red y proveedor no disponible.
