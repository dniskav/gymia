# TrackIA · primer incremento de implementación

Fecha: 20/10/2026. Estado: bienvenida US9 y base de compatibilidad TrackIA
implementadas y compartidas en APK 0.3.23+26. El nombre visible sigue siendo
GymIA; no se declara completa la evolución general a TrackIA.

La conversación con IA es el centro del producto. La bienvenida describe las funciones
actuales; explica que el proveedor debe estar configurado para usar IA y que los
registros locales permanecen disponibles si se corta la conexión. No anuncia espacios,
personalidades ni temporizadores generales antes de implementarlos.

## Cambio verificado

- Cinco diapositivas con Anterior/Siguiente, Omitir/Empezar, progreso y «No volver a
  mostrar». La elección se confirma solo al salir con Omitir o Empezar y persiste por
  dispositivo. Cerrar con Atrás descarta la casilla no confirmada.
- Menú → Ayuda y bienvenida → Ver bienvenida; revisión manual sin reactivar la apertura
  automática. La opción también puede modificarse directamente en Ayuda.
- Arranque pospuesto mientras hay una actividad activa o se atiende un archivo entrante.
  El recorrido no exige iniciar sesión ni conceder permisos.
- Texto ampliado al 200% y claro/oscuro verificados mediante widget tests.

## Evidencia

- `./scripts/flutter-local.sh analyze`: sin incidencias.
- `./scripts/flutter-local.sh test`: 173 pruebas Flutter aprobadas, incluidas las siete
  combinaciones/casos nuevos de la bienvenida y dos pruebas de entrada automática.
- APK de QA compilado con `./scripts/flutter-local.sh build apk --release` e instalado
  en `emulator-5554` mediante `adb install -r` (instalación sobre los datos existentes).
- Emulador Android: primera apertura muestra «Paso 1 de 5» y controles; al marcar «No
  volver a mostrar» y pulsar Omitir, el siguiente arranque abre el chat; Ayuda permite
  reabrir las diapositivas con la casilla reflejada. La opción de mostrar al abrir quedó
  restaurada tras la prueba. [Captura de la primera diapositiva](screenshots/welcome-dark.png).
- La prueba del fallo de escritura mantiene la pantalla abierta y no afirma haber
  guardado una preferencia que no persistió.

La prueba Android de la bienvenida fue manual. El recorrido automatizado en
`integration_test/` (T050) sigue pendiente. Este informe
no prueba todavía las demás historias del SDD, consentimiento real de proveedores ni iOS.

## Base compatible SQLite v5

- T001–T006 y T009: fixture sintética v4 con copia `gymia-backup` v3, IDs de
  entrenamiento/ejercicio/serie/actividad/mensaje y texto original; ninguna fila
  proviene de un usuario. Identidad, firma esperada, claves y capacidades actuales en
  [la base de compatibilidad](TRACKIA-BASELINE.md).
- La apertura de una BD v4 escribe `*.pre-trackia-v4.json` antes de migrar, añade las
  tablas de espacio y vínculos sin reconstruir las tablas legadas, y crea «Gimnasio»
  para el perfil que posee esa BD. Si se abre con otro `profileId`, falla sin reasignar.
  Reabrir no duplica el espacio; restaurar el respaldo v3 recupera originales e IDs.
- `test/trackia_foundation_test.dart`, `test/trackia_legacy_fixture_test.dart` y
  `test/trackia_migrations_test.dart` cubren ámbito, revisiones, campos opcionales,
  catálogo y migración. `./scripts/flutter-local.sh test`: **179 pruebas aprobadas**;
  `./scripts/flutter-local.sh analyze`: sin incidencias. El esquema nuevo aún no
  almacena observaciones ni ejecuciones TrackIA; T007/T008 siguen pendientes.
- Android API 35 ARM64, AVD de prueba `trackia_qa`, instalación debug nueva:
  `integration_test/workout_flow_test.dart -d emulator-5554` aprobado (sesión
  offline, edición, borrado, recuperación e historial). Este recorrido verifica
  que las funciones legadas siguen operando sobre v5; la migración v4→v5 con
  datos sintéticos se probó en SQLite FFI, no en una instalación Android previa.

## APK 0.3.23+26 compartida

- APK firmada `releases/gymia-0.3.23.apk`, SHA-256
  `5d37f546b9953b4d269d744dbb0e268324afb7b2b5e14fe1a0e3d81a918740c6`;
  el archivo binario no se incluye en Git. `apksigner verify` confirma la misma
  huella de certificado de 0.3.22. `aapt` confirma paquete `com.gymia.app`,
  versionName 0.3.23 y versionCode 26.
- En un AVD limpio Android 35 ARM64: instalar APK firmada 0.3.22, abrir,
  instalar 0.3.23 con `adb install -r` y abrir. La pantalla de bienvenida se
  mostró correctamente. Esta instalación prueba firma/actualización y apertura;
  el recorrido de datos históricos con valores se cubre con las fixtures v4/v3.
- Distribuida directamente por Fairdrop. Las actividades abiertas, notas
  independientes, espacios seleccionables y relojes generales siguen pendientes.

## Corrección 0.3.24+27 · apertura de bitácoras grandes

- La migración v4→v5 ya no rechaza el respaldo previo cuando los adjuntos superan
  20 MB. Escribe el JSON por páginas en un archivo temporal y lo renombra al
  completarse; conserva respaldos previos si se reintenta una migración fallida.
- La prueba `trackia_migrations_test.dart` reproduce el bloqueo anterior con seis
  adjuntos de 3 MB y verifica que la actualización abre y conserva sus datos.
  `./scripts/flutter-local.sh test --reporter expanded`: **180 pruebas aprobadas**;
  `./scripts/flutter-local.sh analyze`: sin incidencias.
- Si la apertura falla por otra causa, la pantalla ofrece «Ver detalle técnico»
  para poder identificarla sin borrar los datos del usuario.
- APK firmada `releases/gymia-0.3.24.apk`, SHA-256
  `b0a9c2d6df9aa854257d57cf03c63bdbe12b2f5fbd7e44f224d8a48e05b65b0b`.
  `apksigner verify` confirma el certificado previo; `aapt` confirma
  `com.gymia.app`, versionName 0.3.24 y versionCode 27. Instalada encima de
  0.3.23 en el AVD Android 35 ARM64; abre la bienvenida correctamente. La
  migración con adjuntos se verificó en SQLite FFI, sin datos reales del usuario.

## Corrección 0.3.25+28 · adjuntos grandes en Android

- Una captura de la 0.3.24 mostró `Row too big to fit into CursorWindow` al
  leer `activity_messages` durante la copia previa. Era un fallo diferente
  del límite total de 20 MB: una sola fila con un adjunto grande excedía el
  límite de lectura de Android. La copia ahora excluye esa columna de la
  consulta de filas y lee su contenido en fragmentos de 64 KiB.
- La lectura individual de adjuntos usa también fragmentos; la interpretación
  de mensajes ya no consulta el adjunto cuando solo necesita métricas.
- Prueba de integración en Android API 35 ARM64 con un adjunto sintético de
  3 MB: migración v4→v5, carga del historial, lectura del adjunto y contenido
  exacto del respaldo, todo aprobado. La suite Flutter pasó **180 pruebas**
  y `analyze` no informó incidencias. No se usaron datos del usuario.
- APK firmada `releases/gymia-0.3.25.apk`, SHA-256
  `2ae8bf489674b1e6827aada24394ef3c7a2f8dac0216d2995ef690637754ee93`;
  paquete `com.gymia.app`, versionName 0.3.25 y versionCode 28. El certificado
  coincide con el de 0.3.24. En el emulador se instaló 0.3.24 y luego
  0.3.25 mediante `adb install -r`; la versión nueva abrió correctamente.

## 0.3.26+29 · marca TrackIA y diagnósticos

- Nombre visible TrackIA en Android, iOS y chat. Icono y logo derivados de la
  referencia elegida por el usuario: reloj turquesa, flecha naranja y nombre
  debajo del símbolo en la bienvenida. Tema claro y oscuro armonizados con
  turquesa/naranja. El identificador `com.gymia.app`, claves locales y nombres
  de los bloques del protocolo se conservan para actualizar sin perder datos.
- La bienvenida permite deslizar entre sus cinco páginas y muestra cinco
  indicadores con la posición actual. Una prueba de widget verifica ida y
  vuelta con el gesto; en el emulador se observó el paso 1→2 y el cambio de
  indicador.
- Google Sheets: botones para probar lectura actual con resumen del modelo y
  escritura con un marcador propuesto por la IA, sin sesión finalizada. La
  escritura crea una pestaña oculta temporal, escribe una celda y la elimina
  mediante una solicitud por lotes. Pruebas de interfaz con transporte simulado
  y prueba Kotlin del lote y su validación aprobadas. La cuenta de Google real
  debe comprobarse en el teléfono conectado; el emulador no prueba su OAuth.
- Notificaciones: botón de aviso inmediato sin actividad. Las dos pruebas de
  integración Android (aviso inmediato y alarma de descanso) pasaron en API 35
  con los permisos concedidos.
- Suite Flutter: 182 pruebas aprobadas; `analyze` sin incidencias. APK firmada
  `releases/trackia-0.3.26.apk`, SHA-256
  `011b35534549514958b81932146475e57f9f86b6e4dd8ff9fe5731041809b96a`,
  paquete `com.gymia.app`, versionCode 29. `apksigner` confirma la misma firma
  que 0.3.25. Instalada con `adb install -r` encima de 0.3.25 y abierta.
