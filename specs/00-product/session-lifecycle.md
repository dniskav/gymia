# Inicio, cierre y sesiones múltiples

Fecha: 08/10/2026. Requisito del usuario: botón en la pantalla principal para iniciar entreno que pase a finalizar cuando hay sesión activa. Aclaración posterior: finalizar un entreno no equivale a cerrar el día; Cerrar el día sirve para guardar el progreso en Sheets y permite volver a entrenar ese mismo día. [Flujo de entrenamiento mínimo y decisiones pendientes](training-focus.md).

## Sesiones distintas, progreso relacionado

Una sesión tiene ID propio, inicio, fin, estado y actividades/métricas según las definiciones del usuario. La fecha nunca es una clave única para sesiones. Un usuario puede hacer gimnasio por la mañana y fútbol/natación por la tarde, o cualquier combinación: conservarlos como sesiones independientes que pueden relacionarse en el resumen del día y progreso longitudinal.

Las relaciones usan usuario, periodos/zona horaria, objetivos, actividades y métricas comparables. No convertir fútbol a series de fuerza ni mezclar campos incompatibles porque coincida la fecha. Una sesión que cruza medianoche conserva su identidad; una observación diaria (pasos) no se atribuye entera a una sesión sin evidencia. Datos superpuestos de fuentes externas no son esfuerzo adicional por defecto.

La base actual admite varias sesiones consecutivas al día y una activa a la vez. No imponer una sesión por día. El soporte de sesiones simultáneas/importadas con intervalos solapados requiere política propia; no está solicitado como comportamiento de los controles iniciales.

## Pantalla principal

La aclaración más reciente sustituye el control único inicial: elegir/preparar actividad, Iniciar/Parar para cada tramo, Terminar para cerrar esa actividad y Finalizar día para guardar el progreso acumulado. Mantener la conversación, borrador, adjuntos y acceso a los detalles. El estado procede de la base de datos y se restaura al reabrir, no de un booleano temporal del botón.

Confirmación mínima con selector de fecha/hora precargado al abrir y acciones Cancelar/Guardar. Sin instrucciones para modificar ni botones Cambiar fecha/hora: se tocan directamente los campos del selector. El resultado informa de dónde se guardó. Cancelar conserva sesión/descanso. Cerrar guarda la sesión y permite iniciar otra en el mismo día. Comprobar ID/revisión al confirmar; no cerrar una sesión nueva con un diálogo obsoleto.

### Hora de cierre corregible · confirmado por el usuario

Al pulsar finalizar, mostrar fecha y hora actuales y permitir cambiarlas antes de guardar, incluido otro día si se olvidó cerrar. Conservar por separado la finalización indicada y cuándo se registró el cierre, con procedencia sistema/usuario. La hora de captura de una serie no demuestra su hora de ejecución; los datos antiguos sin hora siguen desconocidos.

Si la hora elegida queda antes del inicio, antes de una serie con hora conocida, en el futuro o se solapa con otra sesión, explicar el caso y ofrecer volver/corregir o guardar tal cual. El usuario puede confirmar y conservar ese horario, sin mover ni borrar las series ni corregir la hora automáticamente. Guardar también los avisos para que una revisión manual o con ayuda del LLM sea posterior y voluntaria. No derivar progreso a partir de una duración imposible ni presentar la ausencia de horas antiguas como ausencia demostrada de conflictos.

Ejemplo: última captura 11:00, botón a las 17:00, final real 11:30. Guardar 11:30 conserva la captura y registra que el cierre se hizo a las 17:00. Si el usuario elige 10:00, avisar de la captura posterior y, si confirma, conservar 10:00. La fecha/hora relaciona sesiones, pero no sustituye su ID estable ni obliga a fusionarlas.

Cerrar exige datos de actividad válidos según su definición; una clase o partido registrado no necesita series/reps. Una sesión vacía requiere aclaración, no se convierte en entrenamiento realizado. Desde 0.3.10 el repositorio admite tramos completados de actividades adaptables además de series de fuerza, y sigue rechazando contenedores vacíos. Cancelar una preparación no inventa un tramo realizado.

## Cierre de día y Google Sheets · aclaración posterior

Cerrar el día solicita guardar en Google el progreso acumulado según la skill compatible, sin bloquear registros posteriores de ese mismo día. Un segundo guardado reconcilia lo nuevo o corregido sin duplicar datos. La decisión confirmada asigna el guardado en Sheets a Finalizar día; Terminar un ejercicio conserva sus datos localmente. El guardado local durante la actividad es automático.

Preparar la representación de los registros pendientes según la skill antes de solicitar aprobaciones adicionales cuando necesite aclaraciones/cambios de estructura. Una operación inequívoca ya autorizada por el guardado solicitado no pide otra confirmación redundante. Si falta hoja, conservar datos locales y ofrecer conectar o crear una; no bloquear el entrenamiento básico.

El cierre local y la intención durable de sincronizar se persisten conjuntamente cuando exista el motor de escritura; después se ejecuta Google. No existe transacción atómica entre SQLite y Google Sheets. Sin red, permiso revocado, falta de skill o conflicto: sesión local conservada y estado explícito pendiente/requiere atención, que sobreviva al reinicio. Una segunda sesión puede iniciarse aunque la primera siga pendiente.

Cada escritura se vincula a ID/revisión de sesión y destino, no solo a fecha. Sesiones del mismo día no se sobrescriben. Reintentar reconcilia antes de volver a escribir; no confundir timeout con ausencia de guardado. Solo comunicar «guardado en Google Sheets» tras verificación. Datos tardíos/correcciones generan revisiones trazables.

## Estado de implementación de esta entrega

0.3.9 añade inicio/cierre al chat, fecha/hora editables y avisos confirmables. El cierre desde la pantalla de entrenamiento usa el mismo diálogo. SQLite v3 conserva hora de captura de nuevas series, fin indicado, hora de registro del cierre, procedencia y avisos; el histórico antiguo permanece sin horas inventadas. Copias formato 2, con restauración del formato 1. Iniciar/finalizar no llama al LLM y conserva el chat. El resultado explica que el guardado es local y Sheets no se actualiza todavía; no muestra pendientes ficticios. IDs, tiempos y avisos se facilitan al modelo para distinguir sesiones y ofrecer revisión sin modificar datos. La simplificación posterior del diálogo está en el código de trabajo y no en la APK 0.3.9 entregada.

0.3.10 añade actividades con definiciones JSON, tramos y resultados libres, pantalla fija y diálogo de fecha/hora simplificado. SQLite v4 y copias formato 3 conservan esta información junto al histórico anterior. Terminar vuelve a preparación y conserva el descanso; el siguiente Iniciar lo cancela. Finalizar día cierra solo el contenedor local actual y avisa de que Sheets no se actualiza. Todavía pendientes: agregación diaria, skills por hoja, cola transaccional y escritura Google verificada. Las definiciones adaptables básicas no equivalen a soporte exhaustivo de todos los deportes.
