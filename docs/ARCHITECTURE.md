# Architecture

## Principles
1. **Content is data.** Numbers and content are in `data/*.json`, loaded once by the `DB` autoload. Code reads `DB.mobs["crab"].dmg`, never literals.
2. **Rules are pure.** `Combat`, `Delve` and `GameState` methods hold the rules and don't touch nodes, so tests and the `CombatBot` can run thousands of fights headless in under a second.
3. **UI is a thin view.** Screens read state, call rule methods, and rebuild when `GameState.changed` fires. Screens are built in code (`UIKit` helpers) to keep diffs reviewable and layouts responsive.
4. **Deterministic combat.** No RNG inside `Combat`. Randomness only picks *content* (which room/encounter/door) via a seeded RNG in `Delve` (`run.seed + floor + salt`), so runs are reproducible.

## Autoloads (project.godot `[autoload]`)
| Name | File | Role |
|---|---|---|
| `DB` | `scripts/autoload/db.gd` | Loads JSON content. `DB.item(id)`, `DB.icon_index(id)`, `DB.display_name(id)` |
| `GameState` | `scripts/autoload/game_state.gd` | Account state: stash `mats`, `gear` instances, `heroes`, `facilities`, `id_queue`, `boss_kills`, `run`. All camp rules (craft, upgrade, repair, identify, patrol, equip, start/end run). Emits `changed` and `toast` |
| `SaveSystem` | `scripts/autoload/save_system.gd` | Saves `GameState.to_dict()` to `user://save.json` on every `changed` (atomic tmp+rename). `SAVE_VERSION` + `migrate()` for future layouts |
| `Sfx` | `scripts/autoload/sfx.gd` | SPD sound effects pool + looping music; silent when headless |

## Core (scripts/core)
- **`Combat`** (`class_name Combat`): an 8x8 arena. `setup(room_rows, hero_stats, hp, mob_ids, darkness)`; hero actions `hero_tap(cell, mode)`, `hero_wait()`, `hero_heal(n)`, `hero_bolt(cell)`. `run_until_hero()` advances the SPD-style clock (each unit has `next`; hero acts on ties; telegraphs resolve at their `at` time). Visual/audio side effects are queued as `events` (`hit`, `move`, `die`, `fall`, `bolt`, `blast`, `telegraph`, `burn`, `heal`, `sfx`) and drained by the view.
- **`CombatBot`**: `suggest(combat)` returns the next sensible action (dodge telegraphs > heal when low > chasm shove > bolt > attack the fastest kill > approach). Used by tests, the **Hint** button and **Auto**.
- **`Delve`**: static functions over `GameState.run`: `plan_floor`, `advance(gs, pct)` (drain, auto-supplies, gathering, starvation, Strength milestones, event triggers), `build_event`, `combat_event`, `pay`/`pay_possible`, `reward`, `descend`.

## Traps & biomes
- `data/traps.json` defines trap effects; `data/biomes.json` gives each biome a trap pool, encounter sets, boss + boss room, music, tileset, secret cache and `next` biome.
- `Combat.setup(..., pool)` parses `^`/`?` from the room and assigns trap types from the pool by position. All unit relocations go through `Combat._place()`, which fires traps (so moves, knockback and the Guard's chain all trigger them).
- `Delve.new_combat(gs, ev)` is the one place a fight is built from an event (CombatScreen and RunSim both use it). `Delve.continue_deeper()` switches `run.biome` at a boss campfire.
- `scripts/core/codex.gd` (class `Codex`) turns mob data into player-facing ability text (inspect toasts, Codex tab).

## Meta-progression, settings, codex
- `GameState.stats` (lifetime counters), `milestones_claimed`, `seen` (codex), `tutorial_done`, `settings` are all in the save (format v2, see `SaveSystem.migrate`).
- `GameState.stat_value(stat)` understands plain stats, `boss:<mob>` and `cleared:<biome>`; milestones and hero `unlock_rule`s both use it.
- `scripts/ui/settings_panel.gd` (class `SettingsPanel`) builds the settings UI into any container; `scripts/ui/codex_view.gd` (class `CodexView`) builds the Codex. `Sfx.buzz()` = haptics, `Sfx.biome_track()` = per-floor music.

## Tutorial
- `data/tutorial.json` holds tips (`title`/`text` or `pages`). `Main.tip(id)` queues one if `GameState.wants_tip(id)`; `scripts/ui/tip_overlay.gd` draws the modal card above every screen and records `GameState.tutorial_done`.
- Triggers: `Main.show_camp` (welcome, after_death/after_extract via `GameState.last_result`), Camp tab changes (`camp_<tab>`), `DelveScreen.on_shown`/`_show_card` (delve_bar, door, special, floor_done, campfire), `CombatScreen._ready`/`_refresh` (first_fight, boss, surprise, telegraph, trap).
- Screens check `Main.tip_open()` to pause.

## The run dictionary (`GameState.run`)
`hero, biome, floor, progress, torch, satiety, hp, pack{mat:n}, pack_gear[], supplies{ration,torch,potion_healing,scroll_passage,...}, seed, events[], next_event, gather, starve, milestones_done[], pending_loot, boss_dead`.
It is saved with the account, so closing the app mid-delve resumes on the Delve Bar (a fight in progress is not saved; you resume just after the event triggered - see DECISIONS.md).

## UI (scripts/ui)
- **`main.gd`**: root. Computes `portrait = width/height < 0.85` (Fold cover ~0.41, inner ~0.86), safe-area margins (mobile only, clamped), font size = `min(w,h)/24` clamped 16..44, builds the theme via `UIKit.make_theme`. Owns screen switching: `show_camp()`, `show_delve()`, `start_combat(event, on_done)`, toasts. The DelveScreen is kept alive while a fight is on top of it.
- **`camp_screen.gd`**: TabContainer pages rebuilt from GameState: Delve (hero + loadout + start), Heroes (equip/imbue), Stash, Forge, Alchemy, Enchanter (ID queue with live timers), Guild (supplies, patrols), Settings (volume, dev cheats, wipe).
- **`delve_screen.gd`**: ticks `Delve.advance` in `_process` (5%/s, x3 toggle) and shows event cards; applies fight results (`_after_fight`).
- **`combat_screen.gd` + `grid_view.gd`**: grid on top (portrait) or left (wide). GridView draws tiles/sprites with integer scaling, tweened movement, hit flash, floating numbers, bolt streaks and pulsing red danger tiles.
- **`ui_kit.gd`**: `UIKit.button/action/label/header/card/icon/icon_row/make_theme`. `action()` shows a disabled button with the reason underneath - use it for anything with requirements.

## Rendering
Compatibility renderer (OpenGL ES 3) on all platforms; `canvas_items` stretch with `expand` aspect from a 968x2376 base; 2D transform/vertex pixel snapping; nearest filtering; lossless (WebP) texture import. See DECISIONS.md for why not Mobile/Vulkan.

## Adding things
- **Mob:** add to `data/mobs.json` (sprite = file in `assets/sprites`, `fw/fh` = SPD `TextureFilm` frame size), reference it in `biomes.json` encounter sets. Special behaviour: add an `ability` and handle it in `Combat._mob_act`.
- **Room:** append an 8-line string array to `data/rooms.json` (`H` hero, `1-4` spawn slots).
- **Recipe / special room / door:** JSON only (`recipes.json`, `events.json`). Rewards: material ids, `item` (known gear id) or `item_unknown` (`ring`/`wand`).
- **Hero class:** add to `heroes.json` + an ability branch in `CombatScreen._refresh`/`Combat`. See ROADMAP for Rogue/Huntress notes.
- **Biome:** add to `biomes.json`, copy SPD's `tiles_<biome>.png`, give GridView the tile sheet (currently hard-wired to sewers - TODO).

## Subclasses and guided fight (v0.10-0.11)
- `heroes.json` `subclasses`: flat stat modifiers applied in `GameState.hero_stats()`; an optional `perk` is copied onto the combat hero and handled in `Combat._melee_dmg/_melee_perks/_kill/_end_hero_turn`.
- `GameState.heroes[c].mask/subclass` (defaults merged into old saves by `from_dict`), `can_choose_subclass/choose_subclass`; Tengu's Mask is granted in `record_boss_kill`.
- `CombatScreen.guide` drives the guided first fight from fight state (`_guide_update`), using `GridView.hint_cell` for the glowing tile.

## Theme, talents, backpack (v0.13)
- `UIKit.chrome(name)` returns an SPD 9-patch StyleBoxTexture; `make_theme` applies it to Button/PanelContainer/TabBar and sets SPD's pixel font.
- `scripts/ui/hero_panels.gd` (HeroPanels) builds the Talents and Backpack panels used by Camp, DelveScreen (`_open_panel`) and CombatScreen (Bag).
- GameState: `talent_*`, `pick_talent`, `auto_pick_talents`; `delve_equip/unequip/drop/use`, `compare_equip`, `resolve_overflow`; `BACKPACK_SLOTS`. Delve `_stow` handles full packs. `Combat.apply_stats` refreshes the hero after a mid-fight swap.
