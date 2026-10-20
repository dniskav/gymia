# Contrato de propuestas del asistente

La conversación entrega datos declarativos, nunca Dart, SQL, código ejecutable o widgets.
El adaptador conserva los bloques gymia-* ya soportados; una nueva versión TrackIA no
renombra ni rompe silenciosamente esos identificadores.

## Sobre lógico

`schemaVersion`, `proposalId`, `profileId`, `spaceId`, `requestId`, `contextRevision`,
`expectedRunRevision` cuando aplica, `requiredCapabilities` y payload tipado. La app
asigna el ámbito de la petición; no confía en un propietario elegido por el modelo.

Payloads admitidos por capacidad: proponer definición/plan, sugerir personalidad,
registrar observación con original, consultar datos de ámbito permitido, proponer trabajo
externo. Se valida esquema, propietario, límites C01–C14 y capacidades antes de preparar.
Un error conserva el texto y muestra el motivo/alternativa; no ejecuta parcialmente.

## Autoridad y presentación

- Una intención clara permite preparar una propuesta válida e insertarla inline sin
  segundo botón Preparar. Preparar no inicia relojes ni concede nuevas autorizaciones.
- Iniciar corresponde a acción explícita del usuario sobre un plan aceptado. Avances
  automáticos ya configurados pertenecen al motor; un mensaje no concede control general.
- Acción semántica y etiqueta visible son campos diferentes: start/pause/resume/finish/
  skip/extend mantienen su efecto, iconografía y descripción accesible. Rechazar etiquetas
  contradictorias; no reetiquetar una acción destructiva como una acción inocua.
- La personalidad solo configura comportamiento. Instrucciones base del producto, permisos,
  capacidades y datos recuperados no se sustituyen por un prompt de usuario/celda.
- Una respuesta tardía se conserva en su chat de origen; cualquier acción requiere que
  contexto y revisión sigan vigentes. En otro caso se muestra como propuesta obsoleta,
  sin alterar el espacio visible ni el plan actual.
- Se excluyen tokens y datos de otros ámbitos. Consulta interespacio requiere concesión
  explícita acotada, con origen visible; no confundir espacio TrackIA con cuenta/proveedor.

## Pruebas de contrato previstas

Propuesta válida y legacy, JSON inválido, capacidad ausente, propietario ajeno, revisión
obsoleta, etiquetas engañosas, personalidad que pide ampliar permisos, celda hostil y
respuesta retrasada. Probar el contexto fuera del widget de chat y sin proveedor real.
