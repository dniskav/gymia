# Contrato de ámbitos, contexto y destinos

## Ámbitos

Perfil = propietario; espacio = partición de intención; cuenta Google = credencial de
recurso; proveedor IA = autorización de inferencia. No son intercambiables. Un espacio
no necesita cuenta nueva. Peticiones capturan profileId, spaceId y revisión del contexto.
Chat, archivos, borrador, memoria, caché y consultas usan esas claves. La personalidad
del espacio se hereda salvo elección explícita de la actividad; no reescribe hechos.

El compositor integra reglas del producto, capacidades disponibles, personalidad,
plan/estado y fuentes permitidas con procedencia. Compartir entre espacios es una
concesión elegida o una petición acotada, nunca acceso implícito por misma fecha/nombre.
Archivar libera contexto activo, conserva recuperación en su espacio y no cambia ámbito.

## Resolución de destino

Actividad none → solo local. Actividad explicit → binding propio. Actividad inherit →
elección del espacio (none o explicit). Un espacio no hereda del «último usado». Mostrar
la resolución y la cuenta/hoja/pestaña antes del primer envío con esa configuración.
Un binding puede vincularse expresamente a varias actividades/espacios del mismo perfil;
allowedRanges limita también las lecturas enviadas a cada conversación.

Mantener creación de hoja cuando el usuario la pide, lectura fresca, renovación silenciosa
y revisión manual opcional. Revocación o cambio de alcance puede requerir consentimiento
real; no pedirlo de nuevo en cada escritura con autorización válida ni prometer que nunca
será necesario. La personalidad no concede permisos ni cambia al proveedor ChatGPT/Google.

## Trabajos y recibos

Guardar observación y job en transacción local cuando proceda; job captura fuente/revisión,
cuenta, recurso, pestaña, rangos y mapeo. Tokens se resuelven en el almacén autorizado al
momento de operar; no viajan en el snapshot. Cambio de destino afecta trabajos futuros.

Antes de escribir, comprobar cuenta/alcance y leer formato actual con precondiciones de
valores/fórmulas. Si cambiaron incompatiblemente: conflict. Timeout después de enviar:
uncertain, reconciliar recibo/destino antes de repetir. Éxito verificado: confirmed con
recibo. Sin binding: estado local de observación sin job. pending es cola, no confirmación.

Correcciones crean revisión y trabajo nuevo identificado; no sobrescribir silenciosamente
una revisión enviada. No transacción distribuida con Sheets ni garantía global contra
editores ajenos. Cachés y recibos se indexan por propietario, binding y revisión.

## Pruebas previstas

Dos perfiles, dos espacios, dos hojas bajo una cuenta; destino compartido expresamente;
ningún destino; override de actividad; cambio de hoja con pending; cierre y recuperación;
lectura de formato nuevo; fórmulas protegidas; revocación; timeout y recibo ya confirmado.
Transportes controlados primero, autorización/lectura/escritura real como evidencia aparte.
