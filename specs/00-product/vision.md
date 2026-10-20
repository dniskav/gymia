# TrackIA — visión y límites

Revisión: 2026-10-20. [SDD vigente](../003-trackia-platform/spec.md).
[Visión anterior de GymIA](history/vision.md), conservada como antecedente.

TrackIA acompaña lo que cada persona quiere hacer, practicar, organizar o registrar.
No exige que una actividad sea un entrenamiento ni que el equipo haya previsto su categoría.
La conversación sigue siendo la entrada principal; configuración y controles locales
permiten usar funciones soportadas sin depender de IA, cuenta externa o hoja.

Cada perfil puede tener espacios con conversación, recuerdos, personalidad y destinos
propios. Una personalidad sugerida o creada por el usuario cambia el tono y la forma de
acompañar. No cambia los hechos, permisos ni semántica de los controles. El usuario puede
compartir información entre espacios explícitamente, con procedencia visible.

Las actividades combinan piezas opcionales: registros, texto, listas, evidencias, etapas,
cronómetro o cuenta atrás, descansos y ciclos. Ejemplos como entrenamiento, estudio,
meditación, cocina, práctica musical o seguimiento de una colección sirven para explorar,
no para cerrar un catálogo. Los datos también pueden existir fuera de una ejecución.

El asistente propone configuraciones declarativas. El motor valida y ejecuta relojes,
transiciones, registros y efectos externos. Preparar no inicia. Etiquetas adaptables no
convierten Pausar en otra acción. Una plantilla nueva no cambia el significado del pasado.

Google Sheets es opcional: espacios o actividades pueden usar destinos distintos, una
misma hoja con alcance explícito, o solo almacenamiento local. Conectar una vez no debe
exigir consentimiento por cada envío válido; revocaciones o nuevos permisos siguen las
condiciones reales de Google. El modelo no edita datos sin el motor y sus verificaciones.

La bienvenida explica las funciones disponibles mediante diapositivas, con navegación,
Omitir, Empezar y «No volver a mostrar». La elección se conserva en el dispositivo; puede
revisarse desde ajustes sin reactivarla. No interrumpe actividad o archivo entrante.

La base actual sigue siendo **GymIA 0.3.22+25**. Este SDD propone la evolución; espacios,
personalidades, motor general y bienvenida todavía requieren implementación. El cambio
visible a TrackIA conservará paquete, firma, cuentas e históricos. Gimnasio continúa como
experiencia compatible. Audio guiado real, ramas, simultaneidad, sensores y reloj requieren
capacidades y validación propias; un prompt o texto de meditación no las implementa.
