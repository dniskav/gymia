# Sprint 1 · Un entrenamiento completo

## Objetivo
Entregar una APK Android que permita iniciar una sesión, añadir ejercicios,
registrar/corregir/eliminar series, finalizar y consultar el entrenamiento sin red.

## Decisión de plataforma
Flutter y Dart para compartir interfaz, dominio y persistencia con iOS.
SQLite mediante sqflite para Android/iOS. El dominio no importa Flutter ni plugins.
El repositorio define el contrato de persistencia; las pantallas usan un controlador.
No hay cuentas, servidor, IA ni permisos de red en la versión distribuida.
El futuro cliente de IA será un servicio independiente, nunca el dueño del histórico.

Se incluyen proyectos Android e iOS. iOS requiere Xcode completo, firma de Apple
y validación en simulador/dispositivo antes de considerarse entregado.
No se garantiza una migración de datos entre teléfonos hasta implementar la
exportación/restauración en la épica E3. Mantener IDs y esquema versionado desde hoy.

## Historias y aceptación
- S1-01: iniciar sesión con nombre y fecha; como máximo una sesión activa.
- S1-02: añadir ejercicios personalizados y series con kg/repeticiones.
- S1-03: editar o eliminar una serie sin modificar las demás.
- S1-04: recuperar una sesión activa tras cerrar completamente la aplicación.
- S1-05: finalizar una sesión con al menos una serie y consultarla en el historial.
- S1-06: realizar todo el recorrido sin conexión.

## Criterio de terminado
Análisis estático sin errores, pruebas de persistencia/validación y flujo de interfaz,
APK generada y firmada, recorrido comprobado en emulador cuando sea posible.
La aceptación de comodidad en un teléfono físico queda a cargo del usuario.

## Fuera de alcance
Rutinas, temporizador, importación Sheets, gráficas, sincronización, IA y publicación
en las tiendas. Los datos locales se pierden al desinstalar o borrar almacenamiento;
actualizar conservando paquete y firma debe preservarlos.

## Entrega 0.1.0 · Verificación
- APK release: `releases/gymia-0.1.0.apk` (47,7 MB), paquete `com.gymia.app`.
- Android mínimo API 23; objetivo API 35. Firma personal verificada con apksigner.
- Análisis estático sin incidencias.
- 13 pruebas unitarias/de widget superadas (validación, SQLite real, controlador y formulario).
- 1 prueba de integración superada en emulador Android 15/API 35: registrar,
  editar, eliminar, reabrir SQLite, finalizar y consultar historial.
- Prueba adicional sobre la APK release en modo avión: crear una serie de
  Sentadilla (20,5 kg × 10), forzar cierre y recuperar, reinstalar con `adb install -r`
  conservando datos, finalizar y comprobar historial tras otro cierre.
- Manifiesto release verificado: no solicita permiso de Internet.
- Capturas reales del emulador: `releases/screenshots/`.
- Aceptación: el usuario ha instalado la APK y confirmado que el recorrido funciona
  en su teléfono. Sprint 1 aceptado. iOS no compilado ni validado.
