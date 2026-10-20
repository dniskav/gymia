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
