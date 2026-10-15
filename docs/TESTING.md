# Testing

| Command | What it checks |
|---|---|
| `godot --headless --path . res://tests/run_tests.tscn` | Unit + balance tests (exit code 1 on failure). Rules (chip rule, barrier spill, chasm, determinism, tick speeds, surprise, telegraph dodge), **balance** (CombatBot must win every Sewer encounter set in every room with a starting Warrior; Mage >= 90%; Lv3/4 Warrior beats Goo), delve (event count, gathering, seeded schedule, milestones, costs/rewards, death & extraction rules), camp (forge, Str penalty, upgrade caps, SoU, brewing, ID timer, rings, patrols, unlocks) save/load round-trip, **traps** (parse, trigger, search, knockback into traps, teleport, poison, keen eyes, save/restore), **prison** (Lv5 Warrior vs every Prison fight, Tengu blink/bombs, skeleton burst), `[fullrun]` Sewers and `[deeprun]` Sewers+Prison seeded expeditions, **meta** (milestones, unlock rules, codex discovery, save migration, settings persistence) |
| `godot --headless --path . res://tests/ui_smoke.tscn` | Instantiates the real UI and plays Camp -> Delve -> fights (Auto) -> doors/specials -> floor search -> floor 2 -> extract, resizing between Fold cover and inner sizes mid-run, simulates an app kill mid-fight, and for the last class jumps to Prison floor 9 and beats Tengu through the real UI (checks the Prison tileset), earns Tengu's Mask, continues into the Caves and beats DM-300, then picks a subclass on the Heroes page. Also checks the guided first fight (banner, highlighted tile, shown once) |
| `xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/screenshots.tscn` | Saves screenshots of camp/forge/delve/combat/boss at cover (484x1188) and inner (928x1080) sizes into `builds/shots/` (rendered at 2x and downsampled so 1-px font strokes survive; `SHOT_NATIVE=1` keeps the 2x images) |
| `tools/verify_apk.sh builds/spd-tactics-vX.apk` | `apksigner verify`, checks the signer matches `tools/release_cert.sha256` (the published releases' certificate, so phones can update in place; `ALLOW_NEW_SIGNING_KEY=1` to override), unpacks the APK's `assets/`, and loads textures, font, JSON data and audio with desktop Godot - catches "no textures / no text" export bugs |
| `tools/build.sh` | All of the above (except screenshots) + exports |

Tips:
- Tests run as **scenes** (not `-s script`) because autoloads (`DB`, `GameState`...) only exist in a normal scene tree.
- Tests set `SaveSystem.autosave = false` and use a separate save path so they never touch your real save.
- To tune balance quickly: edit `data/mobs.json`, run `run_tests.tscn`, read the `[balance]` / `[boss]` lines.


`tests/run_tests.gd [subclass]` covers Tengu's Mask, permanent choice, save/load and each perk hook; `[cavesrun]` prints Caves clears per class and subclass (best Rogue subclass must reach 4/10).

Screenshots: `SHOTS=caves,dm300` (comma list of step names) renders only those steps; long full runs on software GL can drop textures in later shots (DECISIONS #60).

`[talents]` and `[backpack]` cover tier points, picks, mid-delve HP, death reset, equip/unequip/drop, owned items, overflow, potions outside fights and the in-combat swap. tools/build.sh fails on any "SCRIPT ERROR" in either suite.
