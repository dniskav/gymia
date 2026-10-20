# GymIA · Chat y herramientas de entrenamiento (0.3.22)

Bitácora de entrenamiento offline, construida con Flutter para compartir interfaz,
reglas y persistencia entre Android e iOS. Esta entrega distribuye Android.

## Código abierto

Repositorio: [dniskav/gymia](https://github.com/dniskav/gymia).

Código original bajo [licencia MIT](LICENSE), copyright 2026 Dniskav.
Puedes usarlo, modificarlo y distribuirlo según esa licencia. Las dependencias
conservan [sus licencias propias](THIRD_PARTY_NOTICES.md).
Consulta [cómo contribuir](CONTRIBUTING.md) y la [revisión de publicación](docs/OPEN_SOURCE.md).

El repositorio público contiene el código y pruebas; las APK y capturas de las
entregas locales mencionadas en documentos históricos no se incluyen. Tampoco
incluye claves, firma privada, conversaciones ni bases de datos de usuarios.
La publicación del código no habilita por sí misma OAuth ni el uso de un plan
ChatGPT: esa integración está implementada en Android, con validación de admisión real pendiente, descrita en [viabilidad](specs/02-chatgpt-sign-in/feasibility.md).

## Evolución a TrackIA

El [SDD de TrackIA](specs/README.md) define espacios, personalidades, actividades
adaptables y temporizadores opcionales. La bienvenida por diapositivas y la base de
compatibilidad SQLite v5 ya están implementadas y [probadas localmente](docs/TRACKIA-QA.md) en el código
fuente; el APK público entregado sigue siendo GymIA 0.3.22. La IA continúa siendo el
centro de la experiencia; el guardado local permite continuidad si falla la conexión.

## Funciones
- Tema claro, oscuro o automático desde Menú → Apariencia, con elección guardada en el dispositivo. [Detalles](docs/0.3.22-APPEARANCE.md).
- Continuar con ChatGPT en Android: identidad y permiso de uso del plan por separado, modelos de la cuenta, renovación y desconexión. Solo para cuentas elegibles; otros proveedores se conservan. [Implementación y límites](docs/0.3.21-CHATGPT.md).
- Inicio como chat: micrófono en el campo y + con cámara, fotos, PDF, audio y carga de hojas. Las herramientas de gestión quedan en el menú.
- Verificar proveedor/modelo antes de habilitar asistente y nuevas actividades. Comprobaciones automáticas sin inferencias de pago. Parar y guardar notas de una actividad en curso siguen disponibles sin conexión.
- Conexión Google guardada y renovación silenciosa: leer la hoja actual antes de consultar al modelo; interpretar su formato y enviar sesiones desde el chat o al finalizar, con pendientes recuperables. Crear una hoja nueva si se elige y conservar la revisión manual opcional. [Uso, pruebas y límites de 0.3.20](docs/0.3.20-AUTOMATIC-SHEETS.md).
- Cargar Google Sheets o Excel/CSV sin IA y sin exigir un formato de fuerza. Se conservan celdas originales pendientes de interpretación. El análisis no importa entrenamientos automáticamente.
- Una propuesta del asistente prepara la actividad y muestra controles inferiores. Iniciar/Parar gobierna cada tramo y Terminar cierra el ejercicio; el chat permanece visible entre actividades.
- Respuestas con negritas, listas y tablas; los registros inequívocos de fuerza reciben una confirmación persistente en el chat sin llamar al modelo.
- Panel inferior fijo también con teclado, renombrado sin cerrar la actividad, recuperación de preparaciones y texto del modelo por streaming. [Cambios y pruebas de 0.3.13](docs/0.3.13-FOOTER-STREAMING.md).
- Perfiles Google separados: hoja, chat, claves de IA y base local por cuenta. El histórico anterior sigue en Perfil local. [Identidad, pruebas y límites de 0.3.15](docs/0.3.15-PROFILES.md).
- Scroll libre durante respuestas, flecha para volver al final y archivado local manual o decidido por el modelo, con consulta posterior. [Cambios y pruebas de 0.3.18](docs/0.3.18-CHAT-ARCHIVES.md).
- Iniciar se oculta mientras se escribe, dicta o espera al chat; Parar sigue disponible con el reloj en marcha. [Cambios de 0.3.17](docs/0.3.17-CHAT-COMPOSING.md).
- Seguimiento del último mensaje también para confirmaciones locales y anclaje estable con históricos largos. [Corrección de 0.3.16](docs/0.3.16-CHAT-ANCHOR.md).
- Chat con auto scroll durante la respuesta y panel uniforme con y sin actividad. [Cambios de 0.3.14](docs/0.3.14-CHAT-SCROLL.md).
- Iniciar antes o después del descanso, ajustar su duración y guardar resultados/observaciones sin imponer peso/reps a todos los deportes.
- Avisos locales de descanso en Android, con permisos y cancelación al reiniciar antes. Las alarmas puntuales requieren autorización de Android.
- Clave protegida, catálogo vivo de modelos y URL API editable. Presets OpenCode Go/Zen, OpenAI, Anthropic, Gemini, OpenRouter, DeepSeek, MiniMax y Kimi; ningún respaldo automático de pago.
- Finalizar día conserva el cierre local y permite seguir registrando ese mismo día. El envío con conexión guardada y cola de primer plano está disponible; agregación diaria avanzada, ejecución con app cerrada y correcciones por revisión siguen pendientes.
- Alcance, formatos de adjuntos, límites y validación: [0.3.11-CHAT-FIRST.md](docs/0.3.11-CHAT-FIRST.md).
- Revisión del flujo de actividad en Android: [0.3.12-EMULATOR-QA.md](docs/0.3.12-EMULATOR-QA.md).

El registro manual anterior se conserva en la biblioteca:

- Iniciar una sesión con nombre y fecha (máximo una activa).
- Añadir ejercicios personalizados.
- Registrar peso en kg y repeticiones; editar o eliminar series.
- Aceptar coma o punto decimal y 0 kg para ejercicios sin carga externa.
- Guardar cada operación confirmada en SQLite y recuperar la sesión al volver.
- Finalizar y consultar sesiones en el historial.
- Descartar una sesión con confirmación.
- Crear, editar, ordenar y eliminar rutinas con objetivos y descansos por ejercicio.
- Iniciar una sesión desde una rutina sin contar los objetivos como series realizadas.
- Consultar pesos y repeticiones de la última sesión completada del mismo ejercicio.
- Iniciar, pausar, continuar y reiniciar un descanso configurable y persistente.
- Crear y restaurar copias completas de la bitácora desde «Tus datos».
- En Android, autorizar la cuenta de Google desde GymIA, buscar hojas y elegir una pestaña para cargar y revisar los datos. Requiere el registro OAuth de GymIA en Google Cloud y validación en el teléfono.
- Importar Excel o CSV con asignación de columnas, vista previa, errores por fila y deduplicación. Google Sheets también puede compartir una copia directamente con GymIA.

En la pantalla de actividad, el borrador se conserva y los mensajes se guardan localmente al enviarlos o al cambiar de tramo/terminar. Los resultados no estructurados y las molestias siguen siendo datos originales; interpretar no los reemplaza. El registro manual anterior conserva su botón **Guardar**. El histórico muestra también las actividades y sus notas.
Los datos y notas se conservan localmente. El inicio del flujo con IA requiere un proveedor/modelo verificado y conexión. La importación directa de Google Sheets requiere autorizar una cuenta y conexión; desde 0.3.3 la APK solicita permiso de Internet.

## Instalar
La APK local de esta entrega es `releases/gymia-0.3.22.apk` (no se incluye en Git). Detalles de ChatGPT: [0.3.21-CHATGPT.md](docs/0.3.21-CHATGPT.md); conexión Google: [0.3.20-AUTOMATIC-SHEETS.md](docs/0.3.20-AUTOMATIC-SHEETS.md). La conexión se configura una vez desde «Enviar a Google Sheets» y se reutiliza desde el chat y al finalizar sesiones. Se recuperan concesiones existentes, se renuevan tokens sin ventanas y las revocaciones se comunican como atención necesaria. Citas legibles en el tema oscuro. Las pruebas de los nuevos flujos Google usan transporte controlado; el permiso y envío reales se verifican en el móvil. La identidad y el vínculo a cuenta se verifican de nuevo en esta versión; la autorización real multiusuario aún requiere validación. Conserva UTF-8 y la distinción entre glm-5.3 y glm-5.3-flash para imágenes.
Compatible con Android 6.0 (API 23) o posterior.

1. Copiar la APK al teléfono (por USB, Drive u otro medio elegido).
2. Abrirla y permitir la instalación desde esa aplicación si Android lo solicita.
3. Instalar y abrir **GymIA**.

Para actualizar, instalar la siguiente APK encima, sin desinstalar. Hay que mantener
el paquete `com.gymia.app` y la misma clave de firma.
Antes de desinstalar o borrar almacenamiento, crea una copia desde «Tus datos» y
guárdala fuera del móvil. La restauración sustituye los datos locales tras confirmación.

## Desarrollo
Base comprobada: Flutter 3.29.3 / Dart 3.7.2, JDK 17, SDK Android 35, Gradle 8.9.
Las dependencias quedan fijadas mediante `pubspec.lock`.

```sh
flutter pub get
flutter analyze
flutter test
flutter test integration_test/workout_flow_test.dart -d <id-del-emulador>
flutter test integration_test/routine_flow_test.dart -d <id-del-emulador>
flutter test integration_test/transfer_flow_test.dart -d <id-del-emulador>
flutter test integration_test/chat_activity_flow_test.dart -d <id-del-emulador>
flutter run
```

Para compilar sin la firma privada del mantenedor:

```sh
flutter build apk --debug
```

La APK resultante está en `build/app/outputs/flutter-apk/app-debug.apk` y utiliza
el paquete `com.gymia.app.dev`. El modo local no requiere credenciales Google.
Configura tu proveedor y clave desde ajustes si quieres usar IA; nunca añadas
la clave al código fuente.

### Google en una compilación propia

Para probar la conexión real, crea tu proyecto Google Cloud, habilita Drive API
y Sheets API, configura consentimiento y registra un cliente OAuth Android para
tu paquete y certificado. Para debug, usa `com.gymia.app.dev` y el SHA-1 de tu
propia firma de depuración (`cd android` y después `./gradlew signingReport`).
La implementación 0.3.20 solicita identidad, `spreadsheets.readonly`,
`drive.metadata.readonly` y, al escribir, `spreadsheets`. Declara los permisos
que realmente uses y añade usuarios de prueba mientras la app esté en Testing.
No necesita un secreto de cliente en la APK ni un archivo de cuenta de servicio.
La migración a Picker/`drive.file` está propuesta, todavía no implementada.
La firma y el proyecto OAuth del mantenedor no se transfieren con este código.

En este Mac hay herramientas locales bajo `.tools/` (ignoradas por Git).
`scripts/flutter-local.sh` configura las rutas necesarias sin depender del Java
incompatible que incluye la instalación antigua de Android Studio.

```sh
./scripts/flutter-local.sh analyze
./scripts/flutter-local.sh test
./scripts/flutter-local.sh build apk --release
```

### Firma de Android
Se ha generado una clave personal para mantener actualizaciones instalables.
Se conserva en `.signing/gymia-personal.jks`; `android/key.properties`
contiene su configuración. Ambos son privados, están ignorados y deben conservarse
en una copia segura al trasladar o limpiar el entorno. No regenerarlos para actualizar.

En otro entorno configurar `android/key.properties` con:

```properties
storeFile=/ruta/absoluta/a/la/clave.jks
storePassword=TU_PASSWORD
keyAlias=gymia
keyPassword=TU_PASSWORD
```

Una compilación release sin esta configuración falla expresamente. No se sustituye
la clave personal por la clave de depuración. Las pruebas de integración usan una
base separada y el paquete debug `com.gymia.app.dev`, distinto del paquete personal.
Las pruebas automáticas se ejecutan en un emulador desechable. No instalar una debug
como actualización personal ni usar un teléfono con datos reales para estos tests.

## Rutinas y descansos
Las sesiones conservan una copia independiente de su rutina al iniciarse. Editar o
eliminar una rutina no modifica la sesión activa ni el historial. Las series previstas
se muestran como objetivo; el usuario confirma cada serie que realmente realiza.

«Última vez» busca la última sesión completada anterior a la actual con series del
mismo nombre de ejercicio (ignorando mayúsculas y espacios repetidos). Usa nombres
consistentes para distinguir, por ejemplo, press con barra y press con mancuernas.

El descanso de actividad empieza con Parar. Su duración se puede ajustar sin bloquear el siguiente Iniciar; iniciar cancela el aviso anterior. Los avisos de actividad en Android pueden funcionar en segundo plano con los permisos correspondientes. El temporizador manual anterior sigue disponible en la sección de registro manual:

El temporizador conserva la fecha límite al salir o cerrar la app. Al volver muestra
el tiempo real restante. El aviso sonoro se emite con la pantalla de sesión abierta;
no hay alarmas/notificaciones con la app cerrada. El estado se elimina al finalizar
o descartar la sesión. «Ajustar» configura el tiempo y deja el contador detenido;
«Reiniciar» vuelve a arrancarlo desde la duración completa.

Las migraciones SQLite 1 → 2 → 3 → 4 son aditivas y conservan IDs, histórico y sesión activa. Actividades, tramos, originales, borradores y adjuntos de actividad se almacenan aparte de las series de fuerza antiguas.
Las horas de captura y procedencia desconocidas del histórico siguen siendo null.
Las nuevas copias usan formato 3 y pueden restaurarse copias de formatos 1 y 2. Incluyen los adjuntos guardados en actividad; límite total de copia de 20 MB, sin exportaciones parciales que pierdan datos.

## Estructura
- `lib/domain`: modelos, validación y contrato de repositorio; sin Flutter/plugins.
- `lib/data`: SQLite, transacciones, claves foráneas y esquema versionado.
- `lib/application`: controlador de estado y manejo de operaciones/errores.
- `lib/ui`: pantallas y formularios compartidos Android/iOS.
- `android`, `ios`: configuración propia de cada plataforma.
- `test`: validación, persistencia real en SQLite y formulario.
- `integration_test`: recorrido de usuario sobre SQLite del dispositivo.

## iPhone
El proyecto iOS está preparado y usa el mismo código Dart y el plugin SQLite para
Apple. **No está compilado ni validado para iOS en esta entrega.** Este Mac solo
dispone de Command Line Tools; faltan Xcode completo, configuración de firma y
pruebas en simulador/iPhone. La futura transferencia del histórico entre teléfonos
se puede hacer con el archivo JSON de copia de seguridad del Sprint 3.

## Entorno local
Se ha instalado Rosetta 2 para ejecutar las herramientas de compilación de Flutter
que usan binarios Intel en este Mac Apple Silicon. La app Android y su código
compartido no dependen de Rosetta. El script local utiliza un JDK 17 separado.

Backlog: [docs/BACKLOG.md](docs/BACKLOG.md).
Corrección del selector: [docs/0.3.2-SHEETS.md](docs/0.3.2-SHEETS.md).
Conexión Google y requisitos: [docs/0.3.3-GOOGLE.md](docs/0.3.3-GOOGLE.md).
Entrega actual y prueba de aceptación: [docs/SPRINT-3.md](docs/SPRINT-3.md).
Entrega anterior: [docs/SPRINT-2.md](docs/SPRINT-2.md).
