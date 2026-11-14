# Claudito para Omarchy

Un muñequito en pixel art para [Omarchy](https://omarchy.org/) que muestra lo
que está haciendo [Claude Code](https://claude.com/claude-code), con un
sombrero o casco distinto para cada tipo de trabajo, y un widget en la barra con
los límites y el uso de tu plan de Claude.

*[Read in English](README.md)*

Es la versión solo para Omarchy de
[Claudito](https://github.com/coricogit/claudito), que también tiene widgets
para KDE Plasma 6.

| Claude Code está… | Sombrero | Animación |
|---|---|---|
| Pensando en tu mensaje | Gorro con hélice | Gira la hélice, mira arriba, "…" |
| Editando o escribiendo archivos | Casco de obra | Martillea |
| Ejecutando comandos | Casco de minero | Teclea rápido, con la linterna |
| Leyendo o buscando código | Gorra de detective | Pasa la lupa |
| Buscando en la web | Salacot de explorador | Camina |
| Dirigiendo subagentes | Gorra de capitán | Señala adelante |
| Planificando tareas | Sombrero de mago | Destellos |
| Creando artifacts, skills, llamadas MCP | Boina | Pinta |
| Esperando tu permiso o respuesta | (se queda el sombrero) | Saluda, globo "!" |
| Falló una herramienta | — | Gota de sudor |
| Terminó | Gorro de fiesta | Salta con estrellas |
| Nada en 10 minutos | Gorro de dormir | Zzz |

## Qué incluye

- **En la barra**: un mini Claudito y cuánto llevas de la ventana de 5 horas.
  Da saltitos mientras Claude Code trabaja y suda cerca del límite. Al hacer
  clic muestra:
  - tu plan y tu cuenta (el email queda oculto hasta que haces clic)
  - los límites del plan: ventana de 5 horas y semanal, con cuándo se reinicia cada una
  - la sesión actual de Claude Code: nombre, modelo, proyecto, contexto usado,
    tiempo, líneas cambiadas y coste equivalente en API
  - tokens escritos y leídos, respuestas y sesiones de hoy, 7 y 30 días, una
    gráfica de 14 días y los proyectos y modelos que más usas
  - los ajustes del muñequito del escritorio
- **En el escritorio**: Claudito en una esquina de la pantalla, debajo de tus
  ventanas como un widget de escritorio, con un rótulo de lo que está haciendo
  y en qué proyecto. Desde el panel de la barra puedes ocultarlo, ponerlo
  encima de las ventanas y elegir su esquina y tamaño. Haz clic en él para darle
  un toque.

El panel sigue el tema y el idioma de Omarchy (inglés y español) y se maneja con
el teclado (`j`/`k`, `h`/`l`, Enter).

## Instalación

Necesitas Omarchy, Python 3 y `jq` (los dos vienen con Omarchy).

```bash
omarchy plugin add https://github.com/coricogit/omarchy-claudito.git --enable
~/.config/omarchy/plugins/corico.claudito/setup
```

La primera línea añade el plugin y lo pone en la barra. La segunda lo conecta
con Claude Code: añade `claudito-hook` como hook asíncrono y
`claudito-statusline` como status line en `~/.claude/settings.json`. Respeta el
resto de tus ajustes y hooks, no toca una status line que ya tengas y guarda
una copia en `settings.json.claudito-backup`. También puedes saltarte la
segunda línea y pulsar **Conectar con Claude Code** en el panel de la barra.

Las sesiones nuevas de Claude Code usan los hooks automáticamente. En una sesión
que ya estaba abierta, ejecuta `/hooks` una vez.

Para actualizar: `omarchy plugin update corico.claudito`.

Para quitarlo, desconéctalo antes para que Claude Code no siga llamando a un
hook que ya no existe:

```bash
~/.config/omarchy/plugins/corico.claudito/setup --remove
omarchy plugin remove corico.claudito
```

Para mostrar u ocultar el muñequito con un atajo:
`omarchy-shell corico.claudito toggle`.

## Cómo funciona

`claudito-hook` se ejecuta en los eventos de sesión, mensaje, herramientas,
notificaciones y fin. Guarda la actividad de cada sesión en
`$XDG_RUNTIME_DIR/claudito/state.json` (una carpeta en RAM que solo puede leer tu
usuario) y el plugin lee ese archivo. Si tienes varias sesiones abiertas, sigue
la más reciente. El rótulo muestra nombres de archivo, patrones de búsqueda,
dominios web y la descripción de los comandos de terminal, nunca el contenido
de los archivos.

Los límites del plan y la sesión en vivo salen de la status line de Claude
Code, que `claudito-statusline` guarda al lado, así que se actualizan mientras
Claude Code está abierto. El historial sale de tus transcripciones locales en
`~/.claude/projects` (las lee `claudito-usage` y las guarda en caché en
`~/.cache/claudito`) y la cuenta, de `claude auth status`. No se envía nada a
ningún sitio.

Los ajustes del muñequito se guardan en `~/.local/state/claudito/omarchy.json`.
