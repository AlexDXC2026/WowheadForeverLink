# Contributing

## Layout

| Path | Content |
|---|---|
| `WowheadForeverLink/` | The addon, exactly as it is installed in `Interface/AddOns/`. |
| `companion/` | Windows companion app (C#, .NET 8, WinForms + WebView2). |
| `tests/` | Offline addon tests: Lua 5.1 syntax check and a simulated WoW API (`spec.lua`), run in several client locales. |
| `assets/` | Logo and the script that generates every icon size. |
| `docs/` | Texts for the CurseForge page. |

## Workflow

1. Branch from `main`: `feat/<topic>`, `fix/<topic>`, `docs/<topic>`, `chore/<topic>`.
2. Commit with [Conventional Commits](https://www.conventionalcommits.org/): `feat(addon): ...`, `fix(companion): ...`, `docs: ...`, `ci: ...`, `chore: ...`.
3. Add the change under `## [Unreleased]` in `CHANGELOG.md`.
4. Open a pull request. CI must pass (addon tests + companion build).
5. Squash-merge into `main`.

## Releasing

Versions follow [SemVer](https://semver.org/) and are shared by the addon and the app.

1. On a `chore/release-x.y.z` branch:
   - set `## Version: x.y.z` in `WowheadForeverLink/WowheadForeverLink.toc`;
   - set `<Version>x.y.z</Version>` in `companion/WowheadForeverLink.Companion.csproj`;
   - move the `[Unreleased]` notes to a new `## [x.y.z] - YYYY-MM-DD` section and update the links at the bottom.
2. Merge the pull request, then tag `main`:
   ```bash
   git tag -a vx.y.z -m "vx.y.z" && git push origin vx.y.z
   ```
3. The **Release** workflow checks that the tag matches both versions, runs the tests, builds the `.exe`, zips the addon, writes `SHA256SUMS.txt` and publishes the GitHub release with the changelog notes.
4. Upload `WowheadForeverLink-vx.y.z.zip` to CurseForge (game version: WoW Forever) with the same notes.

## Testing in game

Copy `WowheadForeverLink/` to `World of Warcraft/_forever_/Interface/AddOns/`. A newly added addon needs a full game restart; changes to an installed one only need `/reload`. `/wh diag` followed by `/reload` writes the addon status to `WTF/Account/<account>/SavedVariables/WowheadForeverLink.lua`.
