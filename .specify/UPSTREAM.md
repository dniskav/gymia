# Procedencia de Spec Kit

Herramientas y skills oficiales de [GitHub Spec Kit](https://github.com/github/spec-kit),
versión fijada [v1.2.2](https://github.com/github/spec-kit/tree/v1.2.2), licencia
[MIT de sus autores](SPEC-KIT-LICENSE). Las plantillas y skills conservan sus instrucciones
originales; la constitución y los documentos de specs/ son propios de TrackIA.

Inicialización de referencia, realizada en directorio temporal vacío antes de copiar
`.specify/` y `.agents/skills/` al proyecto existente:

```sh
uvx --from git+https://github.com/github/spec-kit.git@v1.2.2 specify init /tmp/trackia-speckit-bootstrap --integration codex --integration-options='--skills' --script sh --ignore-agent-tools --non-interactive
```

No se reemplazó el código de la app, no se cambió la rama existente y no se publican
punteros locales de feature. El identificador de trabajo es `003-trackia-platform`.
Para seleccionar el SDD en otro checkout, usar la variable `SPECIFY_FEATURE_DIRECTORY`
según [quickstart](../specs/003-trackia-platform/quickstart.md). No hay extensiones ni
hooks adicionales configurados en esta entrega.

Flujo aplicado: constitución → especificación → investigación/plan/modelo/contratos →
tareas → análisis de consistencia de solo lectura. La bienvenida solicitada durante
el trabajo se incorporó como US9 antes de generar tareas. No se ejecutó speckit-implement.
