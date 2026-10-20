# Contrato de bienvenida — US9

## Presentación

Cinco diapositivas propuestas, adaptadas al catálogo instalado y al nombre visible de esa entrega:

1. **TrackIA te acompaña**: actividades propias para organizar, practicar, aprender o registrar.
2. **Tu contexto, a tu manera**: espacios y personalidad si están disponibles.
3. **Empieza por una intención**: escribir al asistente o configurar manualmente; ejemplos abiertos.
4. **Usa solo lo que necesitas**: tiempos, descansos, pasos y registros disponibles.
5. **Tus datos contigo**: guardado local y conexión opcional a destinos realmente implementados.

No anunciar espacios, ciclos o audio como utilizables si esa versión aún no los admite.
Contenido alternativo explica únicamente las funciones presentes. No solicitar login,
permisos, creación de hoja ni llamadas de IA al abrir o recorrer las diapositivas.

## Navegación y preferencia

- Progreso «Paso n de N», Anterior salvo primer paso, Siguiente salvo último,
  Omitir siempre y Empezar en el último. Gestos complementan botones, no los sustituyen.
- Casilla «No volver a mostrar» con explicación: «Si la dejas sin marcar, verás esta
  bienvenida al abrir la app. Puedes cambiarlo en Ajustes». Valor inicial visual false.
- Entrada automática con autoShow=true. Omitir/Empezar confirman autoShow=!casilla,
  seenVersion y completedAt. Cerrar por sistema no confirma la casilla ni pierde el chat.
- Persistir antes de cerrar; ante fallo mostrar que la preferencia no se pudo guardar y
  permitir continuar conscientemente. No mostrar confirmación de guardado inexistente.
- Entrada manual desde Ajustes → Ayuda → Ver bienvenida funciona aunque autoShow=false.
  La casilla refleja !autoShow; recorrer o cerrar sin confirmar no modifica la preferencia.
  Solo Omitir/Empezar confirma un cambio explícito. Volver a verla no reactiva autoShow.
- Ajustes permite cambiar directamente «Mostrar bienvenida al abrir». Actualizaciones
  no reinician esa preferencia ni fuerzan nueva presentación por seenVersion antiguo.

## Prioridad y acceso

No superponer automáticamente a una ejecución activa (incluida preparada/pausada), a la
recuperación de datos ni a una apertura con archivo/deep link. Conservar la entrada y
posponer la bienvenida hasta un momento seguro de esa sesión. Apertura manual voluntaria
puede mostrarla conservando la ejecución. No detener relojes al abrir/cerrar.

Claro, oscuro y automático; contraste del tema, lectura de pantalla con orden de foco,
texto ampliado al 200%, scroll por diapositiva si hace falta, orientación estrecha y
botones visibles sin depender de un gesto. No altera borrador, historial ni perfil.

## Aceptación

SC-008: cuatro combinaciones (Omitir/Empezar × casilla marcada/sin marcar), tres arranques
por combinación, más reapertura manual y cambio en ajustes. Añadir cierre sin confirmar,
fallo de persistencia, actualización sin reactivación, actividad activa, archivo entrante,
lectura accesible y ambos temas. Preferencias de dispositivo según C13.
