# SPD Tactics (working title)

A hybrid semi-idle dungeon-management RPG and deterministic tactical roguelite built in **Godot 4.7** on top of
[Shattered Pixel Dungeon](https://github.com/00-Evan/shattered-pixel-dungeon)'s art, sounds and stats.
Design doc: `docs/GDD.txt`. Targets Android (Galaxy Z Fold 6 cover + inner screens) and desktop. An iOS export produces an Xcode project for TestFlight (`docs/BUILD_IOS.md`).

**Play in the browser:** https://daltongoesfast.github.io/spd-tactics-builds/ (PC and phones; saves stay in that browser). APK and Windows builds are on the [Releases](https://github.com/DaltonGoesFast/spd-tactics-builds/releases) page.

**Loop:** Surface Camp (craft, equip, identify, patrol) -> Delve Bar (UI-driven exploration with torch/satiety drain,
Door Choices, special-room cards) -> 8x8 deterministic combat (fixed damage, DR + Barrier, telegraphs, surprise attacks,
chasm knockback) -> extract at the floor-5 campfire after Goo, or die and lose the pack.

## Quick start
```bash
godot --path .                                   # play on desktop (window is the Fold cover aspect; resize to test inner)
godot --headless --path . res://tests/run_tests.tscn   # rules/balance/economy/save tests
godot --headless --path . res://tests/ui_smoke.tscn    # drives the whole UI loop
tools/build.sh                                   # tests + Android/Linux/Windows exports + APK verification
```
Open the folder in the Godot 4.7 editor (standard build, not .NET) or in Cursor - all game code is GDScript in `scripts/`.

## Layout
| Path | What |
|---|---|
| `data/` | All content & balance (JSON): heroes, mobs, items, recipes, facilities, rooms, biomes, events, icon indices |
| `scripts/autoload/` | `DB` (content), `GameState` (account + run rules), `SaveSystem` (versioned JSON save), `Sfx` |
| `scripts/core/` | Pure logic, no nodes: `Combat`, `CombatBot`, `Delve` |
| `scripts/ui/` | Screens built in code: `main`, `camp_screen`, `delve_screen`, `combat_screen`, `grid_view`, `ui_kit` |
| `scenes/main.tscn` | Entry scene |
| `tests/` | Headless test scenes + screenshot capture |
| `tools/` | `build.sh`, `verify_apk.sh`, `gen_docs.py` |
| `docs/` | Architecture, decisions, balance, content, testing, Android and iOS builds, roadmap, changelog |

## Docs
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) - how the code fits together
- [docs/DECISIONS.md](docs/DECISIONS.md) - design calls made where the GDD was open
- [docs/BALANCE.md](docs/BALANCE.md) / [docs/CONTENT.md](docs/CONTENT.md) - numbers and content (partly generated)
- [docs/TESTING.md](docs/TESTING.md), [docs/BUILD_ANDROID.md](docs/BUILD_ANDROID.md), [docs/BUILD_IOS.md](docs/BUILD_IOS.md), [docs/ROADMAP.md](docs/ROADMAP.md), [docs/CHANGELOG.md](docs/CHANGELOG.md)

## License
GPL-3.0 (see `LICENSE`) because it reuses Shattered Pixel Dungeon assets and values. Credits in `CREDITS.md`.
