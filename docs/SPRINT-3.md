# Sprint 3 · Histórico y copias de seguridad

## Entrega
APK Android `releases/gymia-0.3.1.apk`. Instalar encima de 0.2.0 o 0.3.0, sin desinstalar.
El icono de carpeta de la barra superior abre «Tus datos».

## Qué funciona
- Crear un archivo JSON de copia completa y compartirlo con Drive, Archivos u otra app elegida por el usuario. Contiene sesiones acabadas y activas, series, rutinas y descanso en curso.
- Revisar cuántas sesiones y rutinas contiene una copia antes de restaurarla. La restauración sustituye los datos actuales solo tras confirmación; una copia dañada no deja una restauración parcial.
- Desde Google Sheets, usar «Compartir y exportar» → «Enviar una copia» → «Excel» o «CSV» → «GymIA». También se puede elegir una copia XLSX o CSV guardada en el teléfono. La app permite elegir la pestaña del Excel, asignar columnas y revisar sesiones, ejercicios, pesos y repeticiones.
- Mostrar errores por número de fila, omitir esas filas y pedir confirmación del número de sesiones y series nuevas.
- Detectar sesiones duplicadas por fecha/hora al minuto, nombre, orden de ejercicios y series. Reimportar el mismo archivo no duplica sesiones.

## Formato CSV admitido
Una fila por serie; encabezados en la primera línea. Se admiten `,` y `;` como separador y campos entrecomillados. Columnas obligatorias: fecha, ejercicio, peso en kg y repeticiones. Sesión es opcional y, si falta, se llama «Entrenamiento». Los nombres de las columnas se sugieren automáticamente y se pueden cambiar.

Ejemplo:

```csv
Fecha;Sesión;Ejercicio;Peso;Reps
07/10/2026;Empuje;Press banca;60,5;8
07/10/2026;Empuje;Press banca;62,5;6
```

Fechas: `DD/MM/AAAA`, `DD-MM-AAAA`, `AAAA-MM-DD`, opcionalmente con `HH:mm`. Si varias sesiones comparten la misma fecha/hora y nombre, se agrupan. Para mantenerlas separadas, usa nombres o horas distintos. Los CSV de pestañas diferentes se importan por separado. La importación añade sesiones completadas y conserva las existentes y la sesión activa.

El archivo de copia es JSON UTF-8 con `format: gymia-backup` y `version: 1`; está versionado y usa enteros para peso (centésimas de kg) y fechas (milisegundos Unix). El formato está preparado para la futura versión iOS. Límite de archivo: 20 MB. El archivo contiene datos personales de entrenamiento; guárdalo donde prefieras.

## Prueba en el teléfono
1. Actualizar sobre 0.2.0. Confirmar que siguen las rutinas y el historial.
2. Abrir «Tus datos» y elegir «Crear y compartir copia». Guardarla en Drive o Archivos y comprobar que allí aparece el `.json`.
3. Abrir el histórico en Google Sheets y enviarlo como copia Excel o CSV a GymIA. Si se guardó una copia en el teléfono, pulsar «Elegir copia XLSX o CSV». Una hoja nativa de Drive no se puede elegir directamente en el selector de archivos; hay que exportarla como copia.
4. Comprobar la asignación de columnas. Pulsar «Revisar importación» y desplegar una sesión para ver sus series. Revisar los errores por fila y confirmar la importación.
5. Repetir la importación del mismo CSV y comprobar que indica las sesiones duplicadas sin añadirlas de nuevo.
6. Crear una sesión de prueba y después restaurar la copia del paso 2. Confirmar primero la vista de cantidades y la advertencia de sustitución. Verificar que la sesión de prueba desaparece y reaparecen los datos de la copia.

## Verificación de desarrollo
- `flutter analyze` sin problemas.
- 26 pruebas de Dart/SQLite y el flujo de integración Android pasaron: copia completa, restauración, rollback, CSV, duplicados, vista previa e importación.
- La APK release 0.3.0 se instaló encima de 0.2.0 con la misma firma: se conservaron dos sesiones completas, dos series y la sesión activa «Pierna A». Tras recompilar el texto final, se reinstaló 0.3.0 y esos datos seguían presentes.
- En la APK release se abrió el selector de archivos Android con un CSV de prueba y la hoja de compartir con el archivo JSON generado. El manifiesto no solicita permiso de Internet.
- En 0.3.1, `flutter analyze` y 27 pruebas pasaron. La APK se instaló encima de 0.3.0 con la misma firma y conservó las dos sesiones completas, dos series y la sesión activa «Pierna A». En el emulador se seleccionó una copia XLSX con dos pestañas, se eligió «Histórico» y se vio la vista previa de una sesión y dos series. La recepción desde «Enviar una copia» requiere validación final en Google Sheets del teléfono.

La integración directa con la API de Google Sheets queda para otra entrega. La app no pide credenciales de Google ni conexión de red. Todavía falta probar la estructura exacta de la hoja real del usuario.
