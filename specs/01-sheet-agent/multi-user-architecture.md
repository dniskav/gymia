# Google Sheets para múltiples usuarios · propuesta

Revisión: 20/10/2026 sobre `0.3.20+23`. Propuesta actualizada tras recibir por Fairdrop los 12 requisitos y las dos imágenes. Esta revisión modifica solo documentación; no cambia históricos, controles de entrenamiento, APK ni configuración de Google Cloud. La base de identidad se entregó en [0.3.15](../../docs/0.3.15-PROFILES.md), la escritura/creación en [0.3.19](../../docs/0.3.19-SHEETS-WRITE.md) y la conexión reutilizable con cola de primer plano en [0.3.20](../../docs/0.3.20-AUTOMATIC-SHEETS.md).

Petición recibida por Fairdrop: cualquier usuario conecta su propia cuenta y hoja; selección o creación opcional; lectura actualizada, escritura y trabajo sin conexión. Primero revisar arquitectura y proponer; implementar después por etapas. No modificar históricos ni la interfaz de entrenamiento sin consultar.

Ampliación: el mismo texto recibido incluye **Continuar con ChatGPT**, omitido en la primera revisión. Se incorpora en [viabilidad de ChatGPT](../02-chatgpt-sign-in/feasibility.md), con comprobación de requisitos OSS, OAuth oficial, restricciones Android y adaptación del proveedor. Google y ChatGPT son conexiones independientes; compartir email no permite unir identidades ni conceder acceso a Sheets.

Resultado de viabilidad: Google documenta selección Android y acceso de Sheets mediante `drive.file`. El diseño multiusuario es viable. Quedan por ejecutar la prueba de compatibilidad del SDK, OAuth real con dos cuentas y recuperación ante conflictos. La ausencia absoluta de duplicados con múltiples escritores simultáneos no está garantizada por este diseño. ChatGPT tiene viabilidad condicionada a elegibilidad del proyecto y a una prueba real del retorno Android; no se considera habilitado por actualizar esta propuesta.

## Auditoría actual y propuesta para la siguiente etapa

El flujo de producto será: **Usar solo en este móvil**, **Conectar una hoja existente** o **Crear una hoja nueva**. Google es opcional. Al conectarlo, cada usuario elige su cuenta y su archivo. «Hoja de entrenamiento de ejemplo» es solo un ejemplo de prueba; la búsqueda actual no encontró ese nombre ni un ID de hoja personal fijados como destino en `lib` o en el puente Android.

| Área | Código comprobado en 0.3.20 | Cambio propuesto |
| --- | --- | --- |
| Identidad | `ProfileStore` obtiene una identidad comprobada contra userinfo; Android usa AccountPicker y AuthorizationClient | Mantener la separación identidad/autorización; evaluar Credential Manager sin sustituir una identidad por email ni por un JWT sin verificar |
| Aislamiento | `Bootstrap` abre `gymia.sqlite` para Perfil local y `gymia-<perfil>.sqlite` por cuenta; claves de chat, IA, hoja, conexión y cola separadas | Conservar este aislamiento y añadir pruebas reales con dos cuentas; no atribuir el histórico local a la primera cuenta que entre |
| Permisos | Lectura con `spreadsheets.readonly`, escritura con `spreadsheets`; listado con `drive.metadata.readonly` | Migrar lectura, escritura y selección a acceso por archivo con `drive.file`; actualizar también la comprobación nativa de `writeAuthorized`, que hoy exige el scope amplio |
| Selección | Selector propio con listado paginado de Drive y elección de pestaña | Google Picker, filtrado a hojas; guardar únicamente el archivo elegido y comprobar edición y pestaña numérica |
| Creación | SheetsWriter crea libro con encabezados y recupera una respuesta perdida mediante solicitud guardada | Conservar recuperación; permitir también inicializar una pestaña existente realmente vacía tras presentar su estructura |
| Formato existente | Modelo propone coordenadas sobre valores/fórmulas actuales; interpretación breve guardada y revalidada | Perfil declarativo de formato versionado, con evidencias, unidades, zonas permitidas y reglas de correspondencia. Una interpretación no se convierte en permiso para alterar históricos |
| Lectura | Actualiza la caché antes de consultas del chat; avisa al modelo si falló | Exponer claramente antigüedad/estado offline y mantener la lectura de Google separada de importar al historial SQLite |
| Escritura | Sesiones finalizadas, valores esperados, fórmulas protegidas y recibo atómico en metadatos | Añadir identidad por registro/revisión y reconciliación de cambios, sin asumir que fila o fecha identifica una serie |
| Conexión segura | `SheetSyncService` guarda cuenta verificada, libro, ID numérico de pestaña, preferencias e interpretación cifrados | Entidad tipada con UUID de conexión/revisión; separar caché, conexión y perfil de formato. Una pestaña vacía no debe representarse mediante celdas ficticias de SheetContext |
| Sin conexión | Entrenamiento local; cola cifrada recuperable y reintentos con app activa | Outbox en SQLite, intención y cierre local en una transacción; recuperación, estado incierto y conflictos. WorkManager en una fase posterior |
| Cambiar/desconectar | Cambia destino o pausa/desconecta; pendientes conservan cuenta y archivo originales | Comprobar todos los cambios con dos cuentas reales; desconexión local y revocación Google siguen siendo acciones distintas |
| Distribución | No se ha auditado Cloud Console en esta revisión | Preparar audiencia externa, clientes de pruebas/producción, marca, soporte, dominio, privacidad y verificación que corresponda a los permisos finales |

Las pruebas documentadas de 0.3.20 incluyen 146 tests Flutter, 9 nativos y recorridos de emulador con transporte Google controlado. Esas pruebas no equivalen a haber comprobado OAuth y escritura reales con múltiples usuarios externos.

### Autenticación y selección propuestas

El cliente OAuth identifica a GymIA; no da acceso a la cuenta personal del desarrollador. Cada acceso usa la concesión del usuario y una identidad estable comprobada. Los tokens siguen gestionados por Android y fuera del contexto de IA. Mantener renovación silenciosa para conexiones ya concedidas; mostrar consentimiento solo al conectar/seleccionar un archivo o cuando Google lo requiera de nuevo.

La documentación actual de Picker Android ofrece `PICKER_OAUTH_TRIGGER` y devuelve `picked_file_ids`. En ese flujo se solicita **solo `drive.file`**, separado de identidad, con `setOptOutIncludingGrantedScopes(true)` y consentimiento explícito al elegir un archivo. No trasladar ese consentimiento forzado a las renovaciones ordinarias. Sheets admite `drive.file` para los archivos autorizados; por tanto no se propone añadir `spreadsheets` encima de él. El listado propio de Drive con el alcance acotado no puede sustituir a Picker para escoger cualquier hoja.

Primera tarea técnica: comprobar disponibilidad de esas APIs en el SDK instalado (`play-services-auth:21.5.0`) y compatibilidad con Android 6/API 23. Si hace falta actualizarlo, concretar una ruta compatible antes de cambiar dependencias o la versión mínima. La propuesta no da esa compatibilidad por validada.

Fuentes: [Picker Android y parámetros de autorización](https://developers.google.com/workspace/drive/picker/guides/desktop-mobile-picker), [permisos aceptados por Sheets](https://developers.google.com/workspace/sheets/api/scopes).

### Almacenamiento y sincronización propuestos

Conservar SQLite por perfil y entrenamiento local. Introducir interfaces pequeñas para identidad/autorización, selección, API de Sheets, conexiones, perfiles de formato y trabajos de sincronización. El coordinador estará fuera de widgets; el puente nativo seguirá encapsulando Google. Migrar solo metadatos de conexión/cola cuando se implemente esa etapa, conservando los destinos originales; cualquier traslado o modificación del histórico requiere aprobación aparte.

La conexión contendrá UUID, perfil, sujeto Google, libro, pestaña numérica, alcance autorizado y versión de configuración. El formato tendrá una revisión independiente. El outbox contendrá ID de operación, ID/revisión del registro, conexión y destino inmutables, contenido y estado. Los tokens no forman parte del outbox ni de las copias exportadas. Un archivo nuevo no hereda silenciosamente trabajos del anterior.

Los envíos usarán lectura actual, validación de correspondencia, valores esperados, escritura acotada, recibo y verificación. Una sesión/serie no se identifica por la fecha ni por tener los mismos kilos/repeticiones. Mantener detección de respuesta perdida antes de repetir. La siguiente etapa deberá soportar revisiones posteriores y relocalizar registros si se ordenan filas; 0.3.20 aún exige revisión cuando cambia una sesión ya enviada.

Para «bidireccional», distinguir dos resultados: consultar los datos actuales de la hoja y enviar nuevos registros ya existen; **aplicar ediciones remotas a los registros locales** necesita procedencia, correspondencias y política de conflictos. No importar ni reescribir automáticamente el histórico del móvil. La primera propuesta mostrará diferencias y resolverá el conflicto antes de aplicar una corrección histórica.

### Etapas siguientes, en orden

1. **Acceso mínimo y selección:** prueba compatible del SDK/Picker, migración a `drive.file`, validación de cuenta/archivo editable y de renovación silenciosa. Verificar con dos cuentas reales y una hoja que la app no conocía. Mantener el modo local.
2. **Configurar la hoja:** tres opciones del flujo de conexión; inicialización consentida de pestañas vacías y perfil declarativo versionado para formatos existentes, sin sobrescribir valores ni fórmulas. Probar dos formatos diferentes, no solo el ejemplo personal.
3. **Sincronización duradera y revisiones:** outbox SQLite, revisión por registro, cierre/intención atómicos localmente, reinicio/modo avión, respuestas inciertas, filas movidas y destino cambiado. Resolver cambios remotos mediante diferencias explícitas. Después evaluar WorkManager.
4. **Distribución externa:** configurar y verificar marca, permisos finales, clientes y certificados, audiencia, privacidad y acceso de usuario externo. Preparación documental desde la etapa 1; publicación solo tras pruebas reales.

Con `drive.file` se reduce el acceso y el alcance está clasificado como no sensible, pero eso no sustituye la preparación/verificación de marca que corresponda. Los scopes amplios actuales de Sheets sí están clasificados como sensibles. El texto público de privacidad deberá reflejar también que el usuario puede enviar contenido de su hoja a su proveedor IA configurado. No se consideran ya publicados ni verificados los clientes de Google Cloud. Referencias: [scopes](https://developers.google.com/workspace/sheets/api/scopes), [verificación de marca](https://developers.google.com/identity/protocols/oauth2/production-readiness/brand-verification), [scopes sensibles](https://developers.google.com/identity/protocols/oauth2/production-readiness/sensitive-scope-verification).

## Hallazgos iniciales anteriores a 0.3.15 (referencia histórica)

- `android/.../GoogleSheetsBridge.kt` ya usa `AuthorizationClient` y permite elegir cuenta. Solicita `spreadsheets.readonly` y `drive.metadata.readonly`. El token permanece en memoria nativa y las operaciones disponibles son autorizar, listar, consultar pestañas y leer. No devuelve una identidad estable, no crea/escribe hojas y no ofrece desconexión/revocación explícita.
- `lib/ui/google_sheets_import.dart` invoca directamente ese canal y lista hojas con Drive. Separar esta pantalla del transporte facilitará probar cuentas, selección y sincronización.
- `lib/data/sheet_context_store.dart` guarda una sola instantánea con la clave global `gymia.sheet.context.v1`. Aunque usa almacenamiento seguro, no separa usuarios ni conexiones.
- `lib/domain/sheet_context.dart` representa una copia de una pestaña para el asistente, rechaza pestañas vacías y limita su tamaño a 120 KB. No debe convertirse en el registro de conexiones ni en la base de sincronización.
- `lib/data/sqlite_workout_repository.dart` abre `gymia.sqlite` con esquema v4. El entrenamiento local y las actividades tienen IDs propios, pero no hay aislamiento por perfil ni cola remota. La sincronización debe aprovechar esas identidades sin usar la fecha como clave.
- Los flujos revisados reciben el ID del archivo seleccionado; no encontré un Spreadsheet ID personal fijado en ellos. La carencia principal es el aislamiento y la escritura, no sustituir un ID fijo existente.
- El contrato `spec.md` ya contempla interpretación por usuario/hoja, conservación de fórmulas y reconciliación. Esta propuesta concreta la identidad y el acceso. Mantiene la política de `session-lifecycle.md`: Terminar guarda localmente; Finalizar día solicita sincronizar.

## Autenticación y permisos

Propuesta Android: mantener un adaptador nativo detrás de interfaces Dart. Usar Sign in with Google mediante Credential Manager para identidad y `AuthorizationClient` para acceso a datos. Son flujos distintos. No introducir Firebase ni un servidor solo para poder conectar Sheets.

La identidad se vincula al identificador estable de Google (`sub`, con su emisor), obtenido mediante el flujo de identidad validado. Email y nombre sirven para mostrar la cuenta; no son claves. La autorización de Drive debe fijarse a esa misma cuenta: una discrepancia detiene el flujo. Un JWT decodificado sin validación no constituye prueba de identidad. Si se añade backend, este verificará firma, emisor, audiencia y caducidad.

Solicitar identidad mínima (`openid` y email para mostrar la cuenta; perfil adicional solo si se utiliza). Solicitar `drive.file` al conectar/seleccionar/crear una hoja. Sheets acepta este alcance para leer y escribir archivos autorizados: no hace falta añadir `spreadsheets` por defecto. Retirar de este flujo los permisos globales de lectura y metadatos.

El cliente OAuth y el proyecto Cloud pertenecen a GymIA, pero cada acceso usa el consentimiento y la cuenta del usuario. El ID de cliente identifica la aplicación; no es una credencial personal del desarrollador. Sin cuentas de servicio, claves privadas ni secretos de cliente dentro de la APK.

Tokens de acceso efímeros gestionados por el SDK nativo; renovar autorización cuando proceda. No guardar tokens en SQLite, logs, copias, el contexto de IA ni preferencias. El trabajo sin conexión significa conservar una cola local, no pedir acceso OAuth de servidor ni guardar un refresh token manualmente.

Fuente: [identidad y autorización Android](https://developer.android.com/identity/authorization).

## Seleccionar o crear

Usar Google Picker filtrado a `application/vnd.google-apps.spreadsheet`. Con `drive.file`, la lista propia de Drive solo muestra archivos ya autorizados y no sustituye a Picker para elegir cualquier hoja existente.

La documentación Android actual ofrece Picker integrado en autorización mediante `PICKER_OAUTH_TRIGGER`; el resultado incluye `picked_file_ids`. Es la primera opción a validar. Exige comprobar/actualizar la versión del SDK: el proyecto usa `play-services-auth:21.5.0`. La selección es explícita; la renovación normal del token no debe abrir el selector ni pedir consentimiento en cada sincronización.

Comprobar que el archivo sigue disponible, es una hoja y tiene capacidad de edición antes de habilitar escritura. Conservar el `spreadsheetId` del libro y los `sheetId` numéricos de sus pestañas, además de sus nombres visibles. Un nombre no identifica un destino estable.

Crear una hoja es una acción elegida por el usuario. Tras crearla con Sheets API, verificarla y asociarla a su cuenta. Si la respuesta se pierde, reconciliar antes de repetir para evitar crear varios libros.

Una pestaña vacía requiere un modelo de conexión independiente de `SheetContext`; comprobar también fórmulas y contenido no visible, presentar estructura y crear encabezados solo tras aceptación. Propuesta inicial para hojas nuevas: IDs de sesión/registro/revisión, fechas con zona, actividad, métrica, valor, unidad y notas, admitiendo fuerza y otras actividades.

Para una hoja existente: inspección de pestañas, valores, fórmulas, formatos y estructura por bloques; propuesta de correspondencia con evidencias y aclaraciones. Persistir un perfil declarativo versionado por usuario/conexión/archivo. El LLM propone interpretación; el motor valida y ejecuta operaciones acotadas. No renombrar pestañas, añadir columnas, importar al histórico o reemplazar datos automáticamente. «Hoja de entrenamiento de ejemplo» queda exclusivamente como caso de prueba.

Fuentes: [Picker Android](https://developers.google.com/workspace/drive/picker/guides/desktop-mobile-picker), [alcances aceptados por Sheets](https://developers.google.com/workspace/sheets/api/scopes).

## Almacenamiento y separación de cuentas

Interfaces propuestas: `GoogleIdentityGateway`, `GoogleAuthorizationGateway`, `SheetPickerGateway`, `SheetsGateway`, `SheetConnectionRepository` y `SheetSyncCoordinator`. La UI solicita acciones; el coordinador no depende de widgets. El adaptador Android implementa Google; las interfaces permiten un futuro adaptador iOS sin prometer compatibilidad ya validada.

Propuesta: base SQLite por perfil local, con un pequeño registro de perfiles. En cada perfil:

| Entidad | Contenido |
| --- | --- |
| Conexión | Cuenta estable, conexión UUID, archivo, pestañas numéricas, permisos, estado y revisión |
| Perfil de hoja | Correspondencia declarativa, evidencia estructural y versión validada |
| Caché | Datos originales, fórmulas necesarias, origen y fecha de última lectura |
| Vínculos remotos | Registro local ↔ identidad remota, revisión y última verificación |
| Cola de salida | Operación UUID, registro/revisión, destino inmutable, contenido y estado |

Guardar cifrado con `flutter_secure_storage` el vínculo cuenta/perfil y la selección del archivo, con claves separadas por perfil/conexión. SQLite puede guardar referencias operativas dentro del almacenamiento privado de la app; no confundir eso con cifrado completo de la base. Las copias exportadas no incluyen credenciales ni activan conexiones automáticamente al restaurarlas.

Antes de habilitar perfiles, diseñar la transición del histórico, chat y contexto globales. Conservarlos como perfil local legado; no atribuirlos a la primera cuenta que inicie sesión. Cualquier vinculación o traslado del histórico requiere consultar al usuario. Cambiar cuenta limpia el contexto visible de Sheets/IA y carga solo el perfil correspondiente; respuestas asíncronas de la cuenta anterior no se aplican a la nueva.

Cambiar de hoja crea un nuevo vínculo. La cola anterior conserva su destino y queda pausada, nunca redirigida al archivo nuevo. Desconectar detiene trabajos, invalida resultados pendientes y elimina tokens/contexto activo. Distinguir desconectar localmente de revocar el acceso concedido en Google. No borrar entrenamientos ni archivos de Drive al desconectar.

## Sincronización sin conexión y reconciliación

SQLite sigue siendo la fuente del registro inmediato. Al solicitar guardar en Sheets, persistir la intención en la misma transacción local que corresponda. Cada trabajo captura perfil, cuenta, conexión, archivo, pestaña, ID de registro y revisión: no lee el destino de una preferencia global al ejecutarse.

1. Recuperar acceso para la cuenta correcta y leer el destino actualizado.
2. Validar permisos, correspondencia estructural y valores esperados; comparar con la última base conocida.
3. Localizar la identidad remota antes de insertar. Un registro igual por contenido puede ser otra serie real: no deduplicar solo por peso, reps, fecha o posición.
4. Escribir solo las celdas autorizadas, conservando fórmulas, formato y contenido ajeno. Las correcciones del histórico requieren revisión explícita.
5. Releer, verificar datos e identidad y marcar la revisión sincronizada.

Estados: pendiente, en curso, verificado, requiere autorización, requiere configuración, conflicto y resultado incierto. Reintentos con espera creciente para errores transitorios y cuotas. Un 401 renueva o solicita acceso; un 403/404 requiere comprobar permisos/disponibilidad. No reintentar indiscriminadamente errores permanentes.

Para hojas nuevas, incluir IDs estables y revisiones en la estructura aceptada. Para hojas existentes, acordar una identidad recuperable: columna auxiliar, metadatos asociados a filas o una correspondencia inequívoca compatible. Añadir metadatos también es una mutación que debe explicarse y acordarse. Si no hay identidad suficiente, no habilitar reintentos automáticos de inserciones ambiguas.

Un timeout no demuestra que Google no guardara. Primero buscar ID/revisión remotos y verificar; si no puede resolverse, dejar resultado incierto y pedir revisión. Serializar trabajos por destino y evitar trabajadores simultáneos del mismo perfil. `values.append` por sí solo no proporciona la deduplicación necesaria.

Sheets no aporta una transacción distribuida con SQLite ni una garantía general de escritura condicional frente a otros editores. La primera versión cubre un escritor GymIA por destino y detecta conflictos con cambios externos; no prometer ausencia de duplicados con varios móviles escribiendo simultáneamente. Para admitirlos con garantías adicionales habrá que coordinar escritores o ampliar el diseño. Ordenar o insertar filas exige relocalizar las identidades antes de escribir.

Ejecutar inicialmente al abrir/reanudar, al solicitar sincronización y al recuperar red con la app activa. Una fase posterior puede usar WorkManager y restricciones de red para trabajo diferido; Android no garantiza ejecución inmediata y una autorización interactiva requiere volver a la app.

Las consultas remotas actualizan la caché; sin red muestran fecha y estado de la copia. Importar registros al histórico es otra acción, con vista previa y autorización, no una consecuencia de leer la hoja.

Referencia de la operación de inserción: [Sheets values.append](https://developers.google.com/workspace/sheets/api/reference/rest/v4/spreadsheets.values/append).

## Consentimiento para usuarios externos

Preparar una configuración de producción separada de pruebas: audiencia externa, marca GymIA, contacto de soporte, dominio verificado, página pública y política de privacidad que explique Google, almacenamiento local, sincronización y el envío voluntario de datos al proveedor IA. Registrar clientes Android con los paquetes y certificados correspondientes; contemplar la firma de Play si se distribuye por esa vía.

Habilitar las APIs necesarias y declarar exactamente los permisos utilizados. `drive.file` es no sensible, pero siguen aplicando las exigencias de marca y políticas; no equivale a publicación automática sin revisión. Si una función futura exige scopes sensibles/restringidos, justificarla y tramitar la verificación que corresponda antes de distribuirla. Mientras esté en Testing solo podrán acceder los usuarios de prueba autorizados.

Esta revisión no ha inspeccionado ni cambiado la configuración actual de Cloud Console. La configuración pública y la solicitud de verificación se prepararán en su etapa; no se consideran ya completadas.

Fuente: [preparación y verificación de marca OAuth](https://developers.google.com/identity/protocols/oauth2/production-readiness/brand-verification).

## Etapas y comprobación del plan original

| Etapa | Entrega comprobable |
| --- | --- |
| 1. Identidad y aislamiento | Dos cuentas alternan sin compartir hoja, caché, chat ni pendientes. Cancelar/revocar no pierde datos. Plan de transición del legado revisado antes de modificarlo. |
| 2. Picker y conexión | Elegir cualquier hoja autorizada con `drive.file`, recordar selección por cuenta, cambiar y desconectar. Validación real con dos cuentas, cancelación y permisos de solo lectura. |
| 3. Crear y configurar | Crear hoja o inicializar pestaña vacía con vista previa; interpretar dos formatos existentes sin escribir ni importar automáticamente. |
| 4. Escritura verificada | Una sesión nueva en hoja de prueba, conservación de fórmulas e histórico, identificación remota y lectura posterior. |
| 5. Cola y conflictos | Modo avión, reinicio, token caducado, timeout tras guardado remoto, filas movidas, cambio de cuenta/hoja y reintentos sin duplicar. |
| 6. Distribución externa | Consentimiento y privacidad preparados, permisos revisados, configuración pública y verificación aplicable; prueba con usuario externo. |

Revisar diseño ahora; implementar cada etapa después de acordarla. La primera implementación no incluirá cambios en los controles de entrenamiento ni migraciones del histórico sin consulta previa.
