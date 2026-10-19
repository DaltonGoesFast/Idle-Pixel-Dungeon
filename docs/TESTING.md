# Testing

| Command | What it checks |
|---|---|
| `godot --headless --path . res://tests/run_tests.tscn` | Unit + balance tests (exit code 1 on failure). Rules (chip rule, barrier spill, chasm, determinism, tick speeds, surprise, telegraph dodge), **balance** (CombatBot must win every Sewer encounter set in every room with a starting Warrior; Mage >= 90%; Lv3/4 Warrior beats Goo), delve (event count, gathering, seeded schedule, milestones, costs/rewards, death & extraction rules), camp (forge, Str penalty, upgrade caps, SoU, brewing, ID timer, rings, patrols, unlocks) save/load round-trip, **traps** (parse, trigger, search, knockback into traps, teleport, poison, keen eyes, save/restore), **prison** (Lv5 Warrior vs every Prison fight, Tengu blink/bombs, skeleton burst), `[fullrun]` Sewers and `[deeprun]` Sewers+Prison seeded expeditions, **weapons** (all 32 SPD melee weapons' stats and STR formula, reach through walls/bodies/corridors, the bot's reach waits, speed, Flail misses, Mace vs snake, dagger surprise, info text, old saves), **weapon_loot** (the Forge's five swords, the tier split per floor, seeded weapon rewards, which rooms drop them, old saves' Daggers and Maces), **meta** (milestones, unlock rules, codex discovery, save migration, settings persistence) |
| `godot --headless --path . res://tests/ui_smoke.tscn` | Instantiates the real UI and plays Camp -> Delve -> fights (Auto) -> doors/specials -> floor search -> floor 2 -> extract, resizing between Fold cover and inner sizes mid-run, simulates an app kill mid-fight, and for the last class jumps to Prison floor 9 and beats Tengu through the real UI (checks the Prison tileset), earns Tengu's Mask, continues into the Caves and beats DM-300, then picks a subclass on the Heroes page. Also checks the guided first fight (banner, highlighted tile, shown once) |
| `xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/screenshots.tscn` | Saves screenshots of camp/forge/delve/combat/boss at cover (484x1188) and inner (928x1080) sizes into `builds/shots/` (rendered at 2x and downsampled so 1-px font strokes survive; `SHOT_NATIVE=1` keeps the 2x images) |
| `tools/verify_apk.sh builds/spd-tactics-vX.apk` | `apksigner verify` (Java from `PATH`, `JAVA_HOME`, or the Godot editor's Android Java SDK Path; fails if none),  checks the signer matches `tools/release_cert.sha256` (the published releases' certificate, so phones can update in place; `ALLOW_NEW_SIGNING_KEY=1` to override), unpacks the APK's `assets/`, and loads textures, font, JSON data and audio with desktop Godot - catches "no textures / no text" export bugs |
| `tools/build.sh` | All of the above (except screenshots) + exports |

Tips:
- Tests run as **scenes** (not `-s script`) because autoloads (`DB`, `GameState`...) only exist in a normal scene tree.
- Tests set `SaveSystem.autosave = false` and use a separate save path so they never touch your real save.
- To tune balance quickly: edit `data/mobs.json`, run `run_tests.tscn`, read the `[balance]` / `[boss]` lines.


`tests/run_tests.gd [subclass]` covers Tengu's Mask, permanent choice, save/load and each perk hook; `[cavesrun]` prints Caves clears per class and subclass (best Rogue subclass must reach 4/10).

`[updater]` covers version compare, asset pick, and bad GitHub replies (null/odd `assets` or `tag_name`, non-JSON, HTTP 403, no network): each must end in ERROR, never stay on CHECKING. No network access in tests.
`[export presets]` checks Android/iOS/project.godot versions stay in lockstep, Android uses Gradle, and iOS does not duplicate `ITSAppUsesNonExemptEncryption` in `additional_plist_content`.

Screenshots: `SHOTS=caves,dm300` (comma list of step names) renders only those steps; long full runs on software GL can drop textures in later shots (DECISIONS #60).

`[talents]` and `[backpack]` cover tier points, picks, mid-delve HP, death reset, equip/unequip/drop, owned items, overflow, potions outside fights and the in-combat swap. tools/build.sh fails on any "SCRIPT ERROR" in either suite.

`[milestones]` (DECISIONS #195) checks the milestone data (unique ids, categories, material rewards, 40-80 entries, total gold, exactly 2 Scrolls of Upgrade), that a reached milestone waits for Claim and pays once, Claim all, live totals staying reached after a death, the save round trip, old saves (paid stays paid, newly earned becomes claimable, no double pay), and the fight counters and feats. `ui_smoke` checks the Journal count badge, the Claim button and Claim all through the real UI.

`[telemetry]` (DECISIONS #197, #198) checks the live autoload stays suppressed and empty after every suite and sim, that runs from source (the editor binary, e.g. playtest probes under xvfb) and automated browsers (`navigator.webdriver`, including the int `1` the web build's `JavaScriptBridge.eval()` returns for a JS `true`) are suppressed while exported games are not, then uses a detached instance with a key to cover the event and /batch/ shape, no OS user name or device id in the payload, the rate limit, the 1000-event offline cap and reload, HTTP failures (request can't start, no network, 5xx requeue with backoff, 400 drops, 200 clears), the empty-key no-op, gold_spent summing, the new Combat counters, and that Skip tips can't close the data notice. No network access.

`[identify rework]` (DECISIONS #203) checks the 3/2/1 min timers and 1/2/3 slots, the reported 7 Garnet + 2 Ruby queue (one runs, the rest ride along, 6 min total), a known type identifying at once and reading by its real name, parallel slots and offline chaining, Finish now cost/payment/refusal, an upgrade mid-identification, save/load of running/riding/waiting entries, a pre-#203 queue loading, queued items of a type learned elsewhere (waiting or running) identifying on the next tick for free, and the Identify tab's Finish buttons. `[patrol perks]` checks default curios alternate Might / Tenacity.

`[encounter restart]` (DECISIONS #205) saves a run with an Ambush, a boss, a special room, or a set-aside card open, loads it into a new DelveScreen the way Main does on launch (add, lay out), and checks the card is open again, still in the save, has its buttons, and the bar does not move.

`[mob speeds]` and `[victory card]` (DECISIONS #215) check SPD move vs attack speeds (crab and bat bite once per hero turn, monk and ripper twice, counted from the log) and that the Victory card, its buttons, the status pane and the log fit the viewport at 14 window sizes (including the 880x1024 Fold-inner browser), with a sprite on every item and gold line, drops in highlight yellow, and a long list scrolling inside the card. `SHOT_SIZES=web:880x1024 SHOTS=victory,victory_drop` renders the card.
