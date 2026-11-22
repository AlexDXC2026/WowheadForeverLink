# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).
The addon and the companion app share one version number.

## [Unreleased]

### Added
- Companion app: own dark title bar in one row: navigation on the left, page title in the middle, and **minimize**, **maximize / restore** and **close** on the right with Windows' own glyphs. Drag the title bar to move the window, double-click it to maximize, resize from the thin frame. Maximizing fills the screen without taking focus from the game, and the state is remembered. A minimized window comes back with the shortcut, the tray icon or the next copied link.

### Fixed
- Addon: quests that need a profession skill (for example "Clamlette Surprise", Cooking 225) said only "No previous quests required", so it was not clear why Questie did not show them on the map. The "Can you take it?" lines now show the profession, the required skill and your current skill, marked done or missing.

## [1.3.1] - 2026-11-22

Wowhead Forever Link is a fan project and is still being improved. Please report bugs or wrong quest data in the GitHub issues.

### Fixed
- Addon: "Aeonas's Secret Refuge" (paladin, Harold Riggs in Menethil Harbor) said "No previous quests required". Questie's database leaves out Katherine the Pure's chain before it (Battle at the Mannoroc Coven, The Broken Hammer, A Lost Brother); the addon now adds it and hides Questie's "Available" verdict until it is done.
- Addon: 18 more quests whose previous quest is missing from Questie's database now list it and no longer say "Available" too early: the rest of the paladin Sheath of Light chain (The Broken Hammer, Orders from the Grand Crusader, By The Light's Grace, Aeonas the Vindicated), Katherine the Pure's later paladin quests, the Dead Drop chain and five other chains. Source: each quest's series on Wowhead (WoW Forever) or a player's Wowhead comment.
- Addon: 36 more quests with a previous quest missing from Questie's database, found by checking every WoW Forever/Season of Discovery quest that Questie lists without pre-quests against its Wowhead series and comments: ten paladin quests (Rediscovering the Light, A Paladin's Steed, the Terrordale and Tyr chains), the Felwood Timbermaw chains, the new race starts and other chains.
- Addon: quests reached from either of two chains (Stealing Knowledge, Return to Rageroar) list both under "one of" and no longer say "Available" until one is done.

### Changed
- CurseForge page: it starts with how the links work (click, Ctrl+C) and strongly recommends the companion app, with screenshots of the Wowhead button and of the floating window. `Ctrl+Shift+W` (show or hide the floating window) is now easy to find.

## [1.3.0] - 2026-11-19

Wowhead Forever Link is a fan project and is still being improved. Please report bugs or wrong quest data in the GitHub issues.

### Added
- Addon: **Alt + click on a Questie map icon** (world map or minimap) opens that quest on Wowhead, also for quests you have not taken yet. The icon tooltip shows the hint.
- Addon: for quests not in your log, the link window says whether you can take it, using Questie's database: Questie's availability verdict, the required level and every previous quest, each marked done or missing.
- Addon: quest titles come from Questie when the quest is not in your log.
- Addon: **hovering a Questie "!" icon** (map or minimap) adds the same "can you take it?" lines to its tooltip: Questie's verdict (already completed, in your log, missing pre-quest...), level and previous quests marked done or missing. The lines stay when Questie redraws the tooltip on Shift.
- Addon: **Alt + click an item** (bags, chat link, loot window) opens its quest on Wowhead: one not taken yet first, then one in the log; quests of other races and classes are skipped. Items without such a quest open the item page. The tooltip of a quest item shows the hint. The item's quests come from LibQuestieDB (installed with Questie), indexed in the background after login.
- Addon: **Wowhead icon on RareScanner's "rare found" alert**: NPC page on the loot tab, container contents, or a search for events.

### Fixed
- Addon: "Battle at the Mannoroc Coven" (paladin) said "No previous quests required". Questie's database leaves out its pre-quest, the Althalaxx Orb chain ending in "Return to Delgren"; the addon now adds it, and hides Questie's "Available" verdict while it is not done.
- Companion app: after running for a few minutes, the floating window opened behind the game again. Windows' foreground lock refuses `HWND_TOPMOST` from a background app once its start-up grace period (`ForegroundLockTimeout`) ends. The window is now created topmost from the start, and if Windows still refuses, the call is retried while sharing the game thread's input state (focus does not move).

### Changed
- README and CurseForge page: they say this is an unofficial fan project in progress and where to report problems.

## [1.2.1] - 2026-11-18

### Fixed
- Companion app: the floating window stayed hidden behind the game. `ShowInTaskbar = false` gave it a hidden owner window, and Windows then refused to keep it always on top. It is now shown and raised through Win32 as well.

### Added
- Companion app: the diagnostic log records the real visible and topmost state of the window, and what hid it.

## [1.2.0] - 2026-11-18

First public release.

### Added
- Addon: "View on Wowhead" entry in the right-click menu of the target, focus and boss portraits.
- Addon: links use the client language (English, Spanish, German, French, Italian, Portuguese, Russian, Korean, Chinese) and every text is translated to English and Spanish.
- Addon: English slash keywords (`/wh q`, `/wh last`, `/wh help`) next to the Spanish ones.
- Companion app: tray menu in English or Spanish (follows Windows), diagnostic log switch and "open log folder".
- Companion app: published as a single self-contained `.exe`; no .NET install needed.
- Original icon (magnifier with a quest mark) for the addon, the app and the project.
- Offline test suite run in four client locales, CI on every push and pull request, automated releases.

### Changed
- Project renamed from ClaudeWowhead to **Wowhead Forever Link** (folder `WowheadForeverLink`, saved variables `WowheadForeverLinkDB`).
- Companion app: diagnostic log is off by default.

### Removed
- The Wowhead logo previously borrowed from Questie.

## [1.1.0] - 2026-11-18 (private)

### Added
- Companion app with floating window and Chrome modes.

## [1.0.0] - 2026-11-18 (private)

### Added
- Target frame button, quest log icons, quest details button, quest giver icon, slash commands and key bindings.

[Unreleased]: https://github.com/AlexDXC2026/WowheadForeverLink/compare/v1.3.1...HEAD
[1.3.1]: https://github.com/AlexDXC2026/WowheadForeverLink/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/AlexDXC2026/WowheadForeverLink/compare/v1.2.1...v1.3.0
[1.2.1]: https://github.com/AlexDXC2026/WowheadForeverLink/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/AlexDXC2026/WowheadForeverLink/releases/tag/v1.2.0
