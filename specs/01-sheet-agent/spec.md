> Antecedente de GymIA: conserva el alcance y estado de su versión. La evolución futura se rige por el [SDD de TrackIA](../003-trackia-platform/spec.md); este documento no acredita funciones nuevas.

# Agente de Sheets · skill por usuario y hoja

Estado: requisito confirmado el 08/10/2026; contrato de implementación. La APK 0.3.8 lee hojas y permite consultarlas en el chat. Todavía no genera skills persistentes, importa estructuras arbitrarias ni escribe en Google Sheets.

## Resultado

El usuario elige su hoja de entrenamiento. El asistente entiende su organización, aclara dudas relevantes y conserva una skill reutilizable. GymIA mantiene registros propios vinculados a la fuente. Al registrar o corregir entrenamientos, el agente sabe cómo actualizar la misma hoja en su formato original.

Los registros locales usan el [modelo de actividad adaptable](../00-product/adaptive-data-model.md): una sesión puede mezclar fuerza, cinta y clases sin reps. La skill relaciona las definiciones personalizadas del usuario con la hoja, incluidos tiempo/distancia/energía y nuevas métricas. Si la hoja necesita ampliación, el modelo propone una representación compatible y aprende la regla; no fuerza cardio dentro de columnas de reps.

También admite observaciones/resúmenes sin entrenamiento, por ejemplo pasos diarios de una fuente autorizada. La skill puede mantener una fila por día y métrica conforme a las preferencias del usuario; actualizar el total durante el día o recibir datos tardíos revisa esa fila, sin duplicarla ni crear una sesión ficticia. Conserva fuente, periodo/cobertura y evita sumar datos solapados de teléfono/reloj/aplicaciones.

No existe un encabezado, idioma, distribución de filas o número de series obligatorio. Registro 2026 es una prueba de varias series por fila; también deben probarse filas por serie, bloques por sesión y fórmulas/resúmenes. Una estructura desconocida se interpreta con el LLM; lo que no pueda resolverse con evidencia se conserva y se aclara en el chat.

Sin hoja, sugerir crearla, proponer estructura y hacerlo cuando el usuario elija esa acción. No sustituir una hoja existente por una plantilla ni hacer que tener hoja sea requisito para usar GymIA.

## Responsabilidades

- LLM: interpretar estructura y semántica; proponer la skill, relaciones con registros locales y cambios compatibles; aprender correcciones.
- Motor: autorización, lectura, almacenamiento, validación, reloj, cálculos, correspondencia local/remota, cola de sincronización, escritura y verificación.
- Skill: conocimiento declarativo versionado, reutilizable para lectura y escritura. No es código generado, no concede permisos y no ejecuta operaciones por sí misma.

Las celdas son datos externos. Una nota con instrucciones nunca amplía permisos ni herramientas del agente.

## Identidad y contenido de la skill

Vincularla al perfil de usuario, conexión Google, ID del archivo y pestañas pertinentes. Los títulos no son identidades estables. No reutilizar automáticamente la skill de otro usuario, incluso en archivos compartidos. La conexión actual no expone a Dart una identidad Google estable: resolverla antes de anunciar aislamiento por cuenta, sin inventarla a partir del nombre del archivo.

Estados propuestos: borrador, requiere aclaración, válida para lectura, válida para escritura, requiere revisión. Poder leer no implica tener resuelto el destino para escribir. Una duda bloquea las operaciones que dependan de ella, no consultas con evidencia suficiente.

Contenido mínimo:

1. Versión y revisión; usuario/conexión/archivo; pestañas/bloques; fecha de análisis y procedencia del modelo.
2. Evidencias de estructura: encabezados con coordenadas, marcadores, columnas y fórmulas. Diferenciar cambios de datos de cambios de estructura: agregar una fila de datos no invalida el perfil por sí solo.
3. Lectura: sesiones, ejercicios, fechas y zona horaria conocida, unidades/decimales, series, calentamientos, fallo/casi fallo, parciales, variantes, cardio y notas.
4. Correspondencia con entidades de GymIA: campos representables, originales, celdas de origen, incertidumbres y datos aún no normalizados.
5. Escritura: destinos permitidos, identificación de registros existentes, reglas para nuevas sesiones/correcciones y para N series. Qué hacer si el destino no admite información nueva.
6. Conservación: fórmulas, formato, notas, columnas ajenas, resúmenes y otras pestañas. Una celda con fórmula no es una entrada por defecto.
7. Dudas y correcciones del usuario, con evidencia. Una corrección revisa la skill y permite reinterpretar sin duplicar registros.

Persistir entre sesiones y comprobar compatibilidad al volver a cargar. No regenerar en cada mensaje ni enviar todo el libro al proveedor por defecto. Hojas grandes requieren lectura por bloques; no recortarlas silenciosamente ni asumir que el límite actual de 120 KB resuelve todos los casos.

## Modelo local y procedencia

Ampliar las entidades antes de importar datos que hoy no caben en WorkoutSet. Reps desconocidas no son cero; fallo no informado no es false. Diferenciar completas/parciales, fallo/casi fallo, trabajo/calentamiento, peso por lado/total y variantes/máquinas. Conservar cardio y notas aunque no se puedan convertir a series de fuerza. Separar hora de registro y ejecución y mantener procedencia.

Cada dato importado conserva archivo, pestaña, coordenadas, valor original y revisión de interpretación. Su identidad local no depende de la posición de una fila. Tras ordenar o insertar filas, localizar de nuevo el origen mediante las reglas y evidencias de la skill. Nunca escribir en una coordenada suponiendo que sigue conteniendo el mismo entrenamiento.

El LLM propone registros tipados; el motor valida integridad y duplicados. Tipos válidos no prueban una interpretación semántica correcta. Mantener originales y dudas. Reimportar no duplica; reinterpretar conserva trazabilidad.

## Escritura en la hoja existente · prioridad de producto

Preparar cambios desde una intención del usuario y una skill compatible. Aceptar operaciones acotadas sobre el archivo conectado, sin destinos arbitrarios ni sustitución de toda la hoja como atajo.

Secuencia propuesta:

1. Guardar evento local y operación de sincronización con ID estable. Una consulta o sugerencia no genera una escritura.
2. Leer destinos actuales, fórmulas y evidencias del registro. La copia del chat no basta para escribir.
3. Preparar destinos concretos y valores previos esperados. Mostrar diferencias al corregir datos existentes y aclarar ambigüedades. No repetir confirmaciones para operaciones inequívocas ya autorizadas.
4. Validar vínculo al evento, compatibilidad y celdas modificables. No agregar columnas auxiliares, renombrar pestañas ni crear hojas sustitutas silenciosamente.
5. Aplicar mediante las APIs adecuadas, releer y verificar la correspondencia. Solo después comunicar guardado en Google Sheets.
6. Ante timeout, reconciliar antes de repetir: Google puede haber guardado. Usar vínculos y estado pendiente; si no se puede distinguir el resultado, señalarlo sin reintentar a ciegas.

Leer antes de escribir reduce conflictos, pero no proporciona comparación condicional atómica frente a otros editores. Explicitar esa limitación y comprobar el resultado; no prometer ausencia total de conflictos. Un cambio externo en el destino conserva ambas versiones y requiere resolución. Cambios fuera del destino se conservan.

La skill debe resolver N series. Si falta destino para una quinta serie, proponer una extensión compatible sin perderla ni sobrescribir notas. Sin conexión se guarda localmente; cola y estados sobreviven al reinicio. Distinguir local, pendiente, requiere aclaración/conflicto y verificado.

La lectura actual usa spreadsheets.readonly. Solicitar escritura cuando el motor esté listo y se active la función; mantener Drive con el alcance mínimo. Política elegida por el usuario el 08/10/2026: sincronizar al confirmar «Finalizar entreno» desde la pantalla principal. Una escritura se vincula a ID/revisión de sesión y destino, no a una fecha única; admitir varias sesiones al día con estructuras/métricas distintas. Conservar cierre local y cola durable cuando la escritura necesite reintento o aclaración. [Contrato del ciclo de sesión](../00-product/session-lifecycle.md). «Actualizar la copia» y «escribir en Google» son operaciones diferentes.

## Aceptación

- Dos usuarios con estructuras distintas reciben skills independientes: varias series por ejercicio y filas por serie, sin exigir encabezados de GymIA.
- La skill persiste y sirve para lectura y escritura. Cambiar de cuenta no aplica la de la cuenta anterior.
- Reps desconocidas, casi F, parciales y kg por lado conservan significado y originales.
- Una sesión nueva mantiene convenciones y N series; fórmulas, notas y otras pestañas no cambian fuera de operaciones explícitas.
- Ordenar/insertar filas no provoca escribir en otro entrenamiento. Cambiar encabezados o semántica obliga a revisar los mapeos afectados.
- Ediciones externas se conservan o aparecen como conflicto. Una respuesta perdida se reconcilia sin duplicar.
- El chat solo confirma Sheets tras verificar; los estados pendientes persisten sin red.
- Sin hoja, se ofrece crearla sin crear ni sustituir archivos antes de elegir esa acción.

Primera entrega: skill de lectura/escritura, registros con procedencia y actualización verificada. Probar al menos dos estructuras, fallos y conflictos con transporte simulado, y escritura real en una hoja de prueba autorizada antes de mutaciones del histórico personal. No anunciar «cualquier hoja» por tener dos adaptadores fijos; los casos todavía no actualizables permanecen consultables y requieren aclaración o extensión.

Esta especificación define el siguiente bloque; no cambia permisos ni datos por sí misma.
