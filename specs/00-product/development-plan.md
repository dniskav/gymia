# Hoja de ruta hacia TrackIA

Fecha: 2026-10-20. Estado: diseño. Base entregada: GymIA 0.3.22+25.
[Plan técnico](../003-trackia-platform/plan.md), [tareas](../003-trackia-platform/tasks.md),
[criterios](../003-trackia-platform/quickstart.md) y [plan anterior](history/development-plan.md).

1. Fijar compatibilidad y ámbitos, respaldos/migración, capacidades y persistencia local.
2. Permitir que la IA proponga actividades propias sin categoría obligatoria; conservar
   consulta y registro local básico cuando se interrumpa la conexión.
3. Añadir espacios y personalidades, con contextos separados y compartición explícita.
4. Incorporar motor lineal de tiempos, etapas, descanso/ciclos opcionales y registros flexibles.
5. Probar recuperación, respuestas tardías, avisos y una ejecución activa por perfil.
6. Validar actualización con nombre visible TrackIA, histórico de gimnasio y copias compatibles.
7. Añadir bienvenida opcional y revisitable. Puede adelantarse tras la base con contenido
   limitado a lo que esa versión implemente.
8. Añadir conexiones y destinos por espacio/actividad, trabajos persistidos y recibos.
9. Ampliar capacidades avanzadas por separado: ramas, carriles simultáneos, audio y conectores.

Prioridad inicial P1: historias US1–US4, US6, US7 y US9. Multidestino US5 es P2; extensión
US8 es P3 y su primer incremento valida capacidades/alternativas, no entrega todos los motores.
Cada etapa mantiene utilidad independiente con sus prerequisitos y evidencia. No se asignan
fechas ni se marcan implementaciones por haberlas especificado. No cambiar identidad técnica
ni publicar APK como consecuencia automática de modificar esta hoja de ruta.
