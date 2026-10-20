> Antecedente de GymIA: conserva el alcance y estado de su versión. La evolución futura se rige por el [SDD de TrackIA](../003-trackia-platform/spec.md); este documento no acredita funciones nuevas.

# Continuar con ChatGPT en GymIA · viabilidad y propuesta

Revisión: 20/10/2026, código 0.3.20+23 y documentación oficial OpenAI consultada ese día. Incluye los diez requisitos de ChatGPT recibidos junto con la petición multiusuario de Sheets. Revisión previa a implementar: no modifica APK, credenciales, históricos ni interfaz de entrenamiento.

Actualización de implementación: véase [0.3.21](../../docs/0.3.21-CHATGPT.md). El resto de este documento conserva la evaluación previa; no equivale a resultados de admisión real.

## Dictamen y elegibilidad

**Viable como integración propuesta, con condiciones pendientes; todavía no validada de extremo a extremo.** La ruta oficial para clientes de código abierto y ejecución local permite usar el plan ChatGPT sin secreto de cliente ni API key de partner. Las aplicaciones de pago o alojadas remotamente deben seguir la vía de interés/aprobación correspondiente. Fuente: [OpenAI Docs: alcance de la integración OSS](https://developers.openai.com/siwc/token-sharing-open-source).

El quickstart contempla usuarios Plus y Pro elegibles; no autoriza a prometer acceso para cualquier cuenta, workspace o modelo. El inicio de sesión y el permiso de inferencia son capacidades distintas. Fuente: [quickstart oficial](https://developers.openai.com/siwc/quickstart).

La auditoría inicial encontró el proyecto sin LICENSE ni remoto. Tras autorización del propietario se añadió licencia MIT (copyright Dniskav), documentación de contribución y una copia preparada para publicación sin datos personales ni historial privado. La publicación y las comprobaciones se registrarán en `docs/OPEN_SOURCE.md`. `publish_to: none` solo impide publicar el paquete Dart. **Abrir el código no equivale a aprobación de OpenAI:** siguen pendientes condiciones aplicables, modelo de distribución, elegibilidad de cuenta y OAuth real.

## Encaje en el código actual

| Componente comprobado | Adaptación necesaria |
| --- | --- |
| `AiConfig.validate` exige API key | Separar configuración de proveedor y modo de autenticación; OAuth no será una clave pegada en ese campo |
| `AiClient` ya implementa Responses | Añadir resolución de credenciales por registro y un contrato específico para uso del plan |
| Streaming depende de `onText != null` | Forzar transporte SSE en este modo, incluso si el consumidor solo necesita el resultado final; revisar también el planificador Sheets |
| Catálogo y configuración actuales | Catálogo propio por cuenta ChatGPT, separado de catálogos con API key |
| `AiSettingsStore` usa almacenamiento seguro por perfil | Registro OAuth separado, sin copiar tokens al JSON de configuración/verificación |
| Perfiles Google y local ya separados | Vincular opcionalmente una conexión ChatGPT al perfil activo; no fusionar perfiles ni históricos por email |

Conservar OpenCode, OpenAI con API key, Anthropic, Gemini y los demás proveedores. Añadir solo la opción de conexión, cuenta activa, estado, modelos disponibles y desconexión en ajustes IA. No cambiar controles de entrenamiento.

## Autorización y retorno Android

La ruta oficial usa navegador del sistema, PKCE S256, `state`, `nonce` y registro inicial `dynamic_agent_client`; después conserva el ID emitido por cuenta/workspace y un host ID estable. Distingue `openid profile email` de `offline_access resource.invoke chatgpt.tokens.use.direct`. Validar firma JWKS, emisor, audiencia, caducidad, nonce y permisos concedidos antes de activar la cuenta. El retorno requerido es HTTP loopback en `127.0.0.1`, con ruta estable y puerto disponible; no sustituirlo por un esquema Flutter inventado. Fuente: [registro e inicio oficiales](https://developers.openai.com/siwc/token-sharing-open-source/sign-in).

La inferencia técnica es que Flutter Android puede alojar el listener local y abrir el navegador. Eso no demuestra compatibilidad práctica de este flujo en todos los dispositivos. Prototipo necesario: bind exclusivo a loopback antes de abrir navegador, callback de un solo uso, timeout/cancelación, rechazo de retornos inválidos y cierre del listener. Probar regreso a la app, pérdida del proceso y puerto ocupado. No abrir un servidor en `0.0.0.0` ni habilitar HTTP general para las llamadas API. Si Android o el servicio no admiten ese retorno, detener esta ruta y consultar soporte oficial; no recurrir a cookies o endpoints privados.

## Credenciales y ciclo de sesión

Propuesta Android: un registro protegido mediante almacenamiento respaldado por Keystore por perfil/identidad validada/client ID; excluir tokens de logs, chat, exportaciones y diagnósticos. Serializar renovaciones y reemplazar conjuntamente el conjunto de tokens rotados. Al desconectar, detener solicitudes e intentar revocar la sesión por el endpoint descubierto; si no se confirma por falta de red, borrar localmente e informar de la revocación remota pendiente. No confundir borrar localmente con revocar. Fuente: [cuentas, renovación y revocación](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions).

No guardar un estado permanente de «elegible»: revisar scopes y errores de cada operación. Permitir conexión de identidad sin uso del plan y ofrecer las integraciones existentes si se deniega o deja de estar disponible. Fuente: [errores y recuperación](https://developers.openai.com/siwc/token-sharing-open-source/errors-and-recovery).

## Peticiones y límites funcionales

Usar el catálogo autorizado de `https://api.openai.com/v1/models`, cuya respuesta de este modo contiene `models`, `slug`, `display_name` y visibilidad. Enviar el bearer OAuth exclusivamente a la API oficial prevista; inferencia mediante `/v1/responses`. No reutilizar un catálogo fijo de otro proveedor. Fuente: [modelos e inferencia](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference).

El adaptador debe exigir `store:false`, `stream:true`, historial explícito e instrucciones compatibles, y omitir parámetros no admitidos. Esta vía no ofrece las APIs de transcripción/subida de Files ni todos los tools alojados; imágenes y archivos dependen del modelo. El dictado Android actual puede seguir produciendo texto. No promete acceso al historial de ChatGPT. Los límites y políticas de cuenta siguen aplicándose. Fuente: [restricciones de preview](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations).

El modelo puede seguir proponiendo acciones GymIA/Sheets bajo los validadores locales actuales. Conectar ChatGPT no autoriza Google: cada permiso y destino se mantienen separados. Si una respuesta se interrumpe o falla, no ejecutar sus acciones incompletas.

## Entregas y pruebas antes de habilitar

1. Acreditar elegibilidad del proyecto; revisar licencia, publicación y condiciones aplicables sin publicar nada automáticamente.
2. Prototipo aislado Android: navegador real, loopback, PKCE y validación OIDC; cancelación, callback falso/repetido y proceso destruido. Probar emulador y móvil físico.
3. Almacén y autenticación separados: dos registros/workspaces, renovación concurrente, sesión revocada, desconexión offline y aislamiento entre perfiles.
4. Adaptador Responses y catálogo: SSE también en llamadas sin `onText`, finalización confirmada, permiso denegado, modelo no disponible y cuota agotada; conservar los demás proveedores.
5. Recorrido real con cuenta elegible: conectar, inferencia, reiniciar, renovar y revocar. Registrar resultados sin tokens. Solo después considerar la función validada y preparar APK.

Esta revisión valida el encaje arquitectónico y el contrato documental. No se ha intentado OAuth real con ChatGPT, no se ha demostrado elegibilidad OSS de GymIA y no se ha modificado la configuración externa de OpenAI o Google.
