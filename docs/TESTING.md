# Testing

| Command | What it checks |
|---|---|
| `godot --headless --path . res://tests/run_tests.tscn` | Unit + balance tests (exit code 1 on failure). Rules (chip rule, barrier spill, chasm, determinism, tick speeds, surprise, telegraph dodge), **balance** (CombatBot must win every Sewer encounter set in every room with a starting Warrior; Mage >= 90%; Lv3/4 Warrior beats Goo), delve (event count, gathering, seeded schedule, milestones, costs/rewards, death & extraction rules), camp (forge, Str penalty, upgrade caps, SoU, brewing, ID timer, rings, patrols, unlocks) and save/load round-trip |
| `godot --headless --path . res://tests/ui_smoke.tscn` | Instantiates the real UI and plays Camp -> Delve -> fights (Auto) -> doors/specials -> floor 2 -> extract, resizing between Fold cover and inner sizes mid-run |
| `xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/screenshots.tscn` | Saves screenshots of camp/forge/delve/combat/boss at cover (484x1188) and inner (928x1080) window sizes into `builds/shots/` |
| `tools/verify_apk.sh builds/spd-tactics-vX.apk` | `apksigner verify`, unpacks the APK's `assets/`, and loads textures, font, JSON data and audio with desktop Godot - catches "no textures / no text" export bugs |
| `tools/build.sh` | All of the above (except screenshots) + exports |

Tips:
- Tests run as **scenes** (not `-s script`) because autoloads (`DB`, `GameState`...) only exist in a normal scene tree.
- Tests set `SaveSystem.autosave = false` and use a separate save path so they never touch your real save.
- To tune balance quickly: edit `data/mobs.json`, run `run_tests.tscn`, read the `[balance]` / `[boss]` lines.
