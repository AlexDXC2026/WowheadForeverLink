# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).
The addon and the companion app share one version number.

## [Unreleased]

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

[Unreleased]: https://github.com/AlexDXC2026/WowheadForeverLink/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/AlexDXC2026/WowheadForeverLink/releases/tag/v1.2.0
