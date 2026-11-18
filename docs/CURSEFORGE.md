# Wowhead Forever Link

**Open Wowhead (WoW Forever) for any NPC's loot or any quest, straight from the game.**

Right-click a portrait, click the small magnifier next to your target, or the icon next to any quest — the addon builds the right Wowhead link (always the **Forever** section, in **your client language**) and shows it ready to copy.

## Features

- **Right-click a portrait** (target, focus or boss) → **View on Wowhead**.
- **Button next to the target frame**: opens the NPC page on the **Loot** tab — trash, good and quest drops with their drop rates. *Shift + drag* to move it.
- **Quest log**: an icon on every quest, plus a **Wowhead** button in the quest details.
- **Quest giver window**: check a quest on Wowhead before accepting it.
- **Questie map icons**: **Alt + click** a quest icon on the map or minimap to open it on Wowhead, and see right away if you can take it: required level and previous quests, each marked done or missing.
- **Key bindings**: Wowhead for your target, or for whatever is under the mouse.
- **Client language**: English, Español, Deutsch, Français, Italiano, Português, Русский, 한국어, 中文.
- Works in combat and instances whenever the game allows reading the unit; otherwise it falls back to what it read when you targeted it.

## Commands

| Command | Action |
|---|---|
| `/wh` | Loot of your target |
| `/wh q <id>` | Quest by ID |
| `/wh <text>` | Search Wowhead |
| `/wh last` | Show the last link again |
| `/wh reset` | Move the target button back to its place |

## Why do I have to press Ctrl+C?

WoW addons cannot open a browser or write to the clipboard — no addon can. The link appears pre-selected: press **Ctrl+C** and paste it in your browser.

## Optional: open links automatically (Windows)

Want it to open by itself, even in a **floating window on top of the game** (like the Steam overlay)? Use the free companion app:

**[Download WowheadForeverLink-Companion.exe](https://github.com/AlexDXC2026/WowheadForeverLink/releases/latest/download/WowheadForeverLink-Companion.exe)** · [Source code and details on GitHub](https://github.com/AlexDXC2026/WowheadForeverLink)

- Single `.exe`, nothing to install. Lives next to the clock.
- Opens every Wowhead link you copy from WoW in a **floating window** (does not steal focus from the game; `Ctrl+Shift+W` shows/hides it) or in **Chrome** — your choice.
- It is a normal Windows window: it never reads, injects into or modifies the game.
- It only reacts to wowhead.com links copied while WoW is the active window; anything else on your clipboard is ignored and never stored.
- Open source (MIT). Each release publishes SHA-256 checksums.

## Feedback

Bugs and ideas: [GitHub issues](https://github.com/AlexDXC2026/WowheadForeverLink/issues).

*Not affiliated with Wowhead or Blizzard Entertainment.*

---

## Español

**Abre Wowhead (WoW Forever) con el botín de cualquier PNJ o cualquier misión, desde el juego.**

- **Clic derecho en un retrato** → **Ver en Wowhead**.
- **Botón junto al marco del objetivo**: ficha del PNJ en la pestaña **Botín** (normal, bueno y de misión, con porcentajes).
- **Registro de misiones** y **ventana del PNJ**: icono para ver la misión en Wowhead.
- **Iconos de Questie en el mapa**: **Alt + clic** abre la misión en Wowhead y te dice si puedes cogerla (nivel y misiones previas hechas o pendientes).
- Enlaces siempre a la sección **Forever**, en el **idioma de tu cliente**.
- Comandos: `/wh`, `/wh m <id>`, `/wh <texto>`, `/wh ultima`, `/wh reset`.

Ningún addon puede abrir el navegador: el enlace aparece seleccionado, pulsas **Ctrl+C** y lo pegas. Si quieres que se abra solo, incluso en una **ventana flotante encima del juego**, descarga el programa gratuito **[WowheadForeverLink-Companion.exe](https://github.com/AlexDXC2026/WowheadForeverLink/releases/latest/download/WowheadForeverLink-Companion.exe)** (un único `.exe`, sin instalar nada, código abierto).
