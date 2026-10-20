# Recorrido de revisión y aceptación

El checkout ya incluye la bienvenida US9 y la base de compatibilidad T001–T006/T009;
[evidencia de QA](../../docs/TRACKIA-QA.md).
La evolución general de TrackIA sigue pendiente y aún no hay APK público de esta etapa.

## Revisar los documentos

Desde la raíz del repositorio:

```sh
SPECIFY_FEATURE_DIRECTORY=specs/003-trackia-platform .specify/scripts/bash/check-prerequisites.sh --json --require-spec --require-tasks --include-tasks
python3 scripts/validate-sdd.py
```

El helper puede crear `.specify/feature.json`, ignorado y propio del checkout. No exige
cambiar rama. Flujo: constitución → spec → research/plan/modelo/contratos → tasks →
`$speckit-analyze` (skill local de Codex).
Los helpers oficiales verifican presencia; el validador comprueba estructura y enlaces;
la revisión semántica comprueba coherencia, no ejecuta la app futura.

## Implementación posterior

Elegir un incremento de [tasks.md](tasks.md) y sus dependencias. Las tareas completadas se marcan en el checklist; las demás siguen pendientes.
No confundir un recorrido de aceptación con un resultado medido.
Comprobaciones cuando existan cambios de runtime:

```sh
./scripts/flutter-local.sh analyze
./scripts/flutter-local.sh test
```

Pruebas nativas afectadas usan `:app:testDebugUnitTest` dentro de android con JDK compatible.
Las pruebas integration_test requieren emulador configurado. Documentar versión exacta,
modelo/API/arquitectura, configuración de reloj, tema y evidencia en docs/TRACKIA-QA.md.
Referencia inicial: emulador API 35 ARM64; cualquier validación física se registra aparte.
No reutilizar credenciales privadas o datos personales en fixtures.

## Matriz de aceptación futura

| Historia | Recorrido independiente | Evidencia requerida |
|---|---|---|
| US1 | Pedir a la IA una colección sin tiempo, aceptar plan, completar pasos y guardar nota. Propuesta inline no inicia; ante caída de IA, nota y consulta locales continúan. | Widget + Android local; no gate del proveedor para controles locales. |
| US2 | Dos espacios/personas, luego otro perfil, 20 cambios. Incluir chats, borradores, archivos, memoria y destino. | Cero filtraciones; consulta compartida solo con alcance explícito y origen. |
| US3 | Una continua, una con ciclos, otra con pasos/cantidad; descanso opcional, pausa distinta de rest, etiquetas distintas. | SC-001 cuatro arquetipos contando US1; transición única y acciones estables. |
| US4 | Número con unidad, lista, texto, adjunto y observación sin ejecución; editar interpretación y reabrir. | Originales, IDs y ausencia/ceros intactos. |
| US6 | 20 ejecuciones con pausa/cierre, doble disparador, cambio de hora, red caída y respuesta tardía. | SC-003, reloj reconciliado o incertidumbre explícita, cero eventos duplicados. |
| US7 | Copia de BD GymIA y backup v3, vista previa y actualización in situ con la misma firma/paquete. | SC-004 comparación 100% IDs/valores/originales, recuperación del respaldo, cuentas preservadas. |
| US9 | Omitir/Empezar × casilla sí/no; tres aperturas cada combinación; ajustes y cierre sin confirmar. | SC-008, persistencia/fallo, actualización respeta elección, claro/oscuro, lector y texto 200%. |
| US5 | Dos espacios/hojas, uno compartido y override explícito. Cambiar destino con pending, timeout y revocación. | SC-005 recibos y destinos correctos, lectura fresca, datos/fórmulas ajenos intactos. |
| US8 | Propuesta de ramas, carriles y audio sin adaptador. | Rechazo útil sin perder propuesta; alternativa manual real, ninguna falsa disponibilidad. |

## Medidas transversales

- SC-006: instrumentar desde tap hasta estado visible confirmado; 100 acciones locales,
  al menos 95 <300 ms en referencia; excluir red y documentar muestras, no solo promedio.
- SC-007: muestrear reloj visible >=1 Hz, cerrar/reabrir y verificar origen del tiempo;
  no considerar la animación como prueba de persistencia ni de actividad física.
- SC-009: desde chat, selector de espacio y Apariencia/Ayuda a <=2 acciones de navegación.
- Bienvenida: archivo entrante conservado y ejecución activa no interrumpida; manual
  desde ajustes no reactiva presentación. No login ni permisos al recorrer.
- Accesibilidad/temas: foco, botones, citas y controles con lector, texto 200%, ambas
  apariencias y sistema; no pérdida de borrador o actividad.
- Servicios: separar fixtures y transporte controlado de prueba real de autorización,
  admisión de proveedor y escritura/lectura. Nunca marcar «real verificado» con mocks.

## Criterio de cierre de entrega

Solo marcar una tarea al existir implementación y evidencia correspondiente. Actualizar
README/notas con capacidades realmente presentes. La compilación de QA de la bienvenida no migra históricos ni cambia el nombre visible.
Una publicación de APK requiere su propia versión, verificación y entrega.
