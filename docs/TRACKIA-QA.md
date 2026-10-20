# TrackIA · primer incremento de implementación

Fecha: 20/10/2026. Estado: bienvenida US9 implementada en el código fuente y probada
localmente. La aplicación visible y el APK público siguen siendo GymIA 0.3.22+25; no
se declara completa la evolución general a TrackIA ni se ha distribuido este APK de QA.

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

La prueba Android fue manual. El recorrido automatizado en `integration_test/` (T050)
sigue pendiente; también falta una publicación de APK con versión propia. Este informe
no prueba todavía las demás historias del SDD, consentimiento real de proveedores ni iOS.
