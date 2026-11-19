# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).
The addon and the companion app share one version number.

## [Unreleased]

### Added
- Addon: **Alt + click on a Questie map icon** (world map or minimap) opens that quest on Wowhead, also for quests you have not taken yet. The icon tooltip shows the hint.
- Addon: for quests not in your log, the link window says whether you can take it, using Questie's database: Questie's availability verdict, the required level and every previous quest, each marked done or missing.
- Addon: quest titles come from Questie when the quest is not in your log.
- Addon: **hovering a Questie "!" icon** (map or minimap) adds the same "can you take it?" lines to its tooltip: Questie's verdict (already completed, in your log, missing pre-quest...), level and previous quests marked done or missing. The lines stay when Questie redraws the tooltip on Shift.
- Addon: **Alt + click an item for a quest not taken yet** (bags, chat link, loot window) opens that quest on Wowhead with the "can you take it?" lines. It covers items a quest asks for and items that start a quest, skips quests of other races and classes, and lists the other quests in chat when the item serves several. The item tooltip shows the hint. Uses LibQuestieDB (installed with Questie); the item index is built in the background after login.

### Fixed
- Companion app: after running for a few minutes, the floating window opened behind the game again. Windows' foreground lock refuses `HWND_TOPMOST` from a background app once its start-up grace period (`ForegroundLockTimeout`) ends. The window is now created topmost from the start, and if Windows still refuses, the call is retried while sharing the game thread's input state (focus does not move).

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

[Unreleased]: https://github.com/AlexDXC2026/WowheadForeverLink/compare/v1.2.1...HEAD
[1.2.1]: https://github.com/AlexDXC2026/WowheadForeverLink/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/AlexDXC2026/WowheadForeverLink/releases/tag/v1.2.0
