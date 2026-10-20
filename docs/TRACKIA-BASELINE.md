# Base de compatibilidad para TrackIA

Fecha: 20/10/2026. Referencia de actualización: GymIA 0.3.22+25, SQLite v4,
`gymia-backup` v3. El paquete Android de producción es `com.gymia.app` (minSdk
23); el debug usa `.dev`. Cambiar el nombre visible no cambia el paquete ni la
ruta de datos. Una actualización se instala encima, sin desinstalar.

La firma release existente usa un único certificado RSA de 3072 bits. Huella
SHA-256 **pública del certificado** de la referencia local firmada:
`8ec5268d28e98116155e2ed660359f7ddb1fa0d41568146759c28ac01a32aac6`.
Antes de repartir un APK TrackIA, comparar su huella con esta y comprobar
`adb install -r` sobre una copia de prueba de la instalación anterior. La clave
privada, el alias y las contraseñas se guardan fuera de Git.

La BD local sigue en `gymia.sqlite`; cada perfil Google usa
`gymia-<profileId>.sqlite`, sin migrar ni fusionar cuentas. La selección de
perfiles permanece bajo `gymia.profiles.v1`. Las claves de chat, IA, hojas,
apariencia y bienvenida conservan sus nombres `gymia.*` para mantener las
preferencias existentes. No se renombran los canales Android
`com.gymia.app/google-sheets`, `com.gymia.app/chatgpt` ni
`com.gymia.app/rest-notifications`. El lector de copias admite v1, v2 y v3.

Capacidades declarativas presentes en 0.3.22: `gymia-activity`,
`gymia-result`, `gymia-archive`, `gymia-recall`, `gymia-sync` y
`gymia-sheet-plan`, todas en versión 1. No hay todavía motor TrackIA de
etapas/ciclos, audio guiado, espacios seleccionables ni destinos múltiples.
La IA prepara actividades heredadas sin iniciar el reloj; los controles locales
ya iniciados siguen guardando notas si falla el proveedor.

Fixture de compatibilidad: `test/fixtures/trackia_legacy_fixtures.dart` genera
una BD v4 y copia v3 con datos sintéticos. IDs y texto original son aserciones
de migración; no proceden de una persona. El respaldo previo a una migración
debe conservarse fuera de la BD que se actualiza y ser legible por la versión
anterior hasta completar la verificación.
