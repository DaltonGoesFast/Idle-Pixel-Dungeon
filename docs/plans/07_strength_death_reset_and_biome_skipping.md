# Plan 07: Strength Progression, Death Reset & Biome Skipping

## Status
Ready for implementation — all design decisions locked in via `/grill-me`.

## Problem Statement
Plans 01 and 02 replace the flat `-1 DR / -2 Dmg` under-strength penalty with severe proportional penalties:
- **Weapons (Plan 02):** `dmg = maxi(1, int(dmg / (1 + str_short)))`, `w_block_dr = 0`, `no_surprise = true`.
- **Armor (Plan 01):** `adr = adr / (1 + armor_str_short)`, `abar = 0`.

Across the rest of the game, Hero Strength (`str`) interacts with death resets, biome skipping, Patrol efficiency, and Camp UI in ways that break under these stricter penalties:

1. **Death Reset + Biome Skipping Trap:**
   - When a hero dies (`GameState.end_run("death")` in `scripts/autoload/game_state.gd:1782`), their stats reset to `level = 1`, `str = 10`, and `str_found = []`.
   - `CampScreen.start_biomes(c)` (`scripts/ui/camp_screen.gd:206-210`) allows a hero who has cleared earlier biomes to launch a new delve directly into **Prison (`str_gate: 12`)**, **Caves (`str_gate: 14`)**, **Dwarf City (`str_gate: 15`)**, or **Demon Halls (`str_gate: 17`)**.
   - Meanwhile, Guild `GameState.train(c)` (`scripts/autoload/game_state.gd:778-797`) only retrains **Hero Level** up to `train_cap(c)` (`best_level - 2`)—it never restores **Strength**. Strength potions (`strength_potions_at` in `data/biomes.json`) are only awarded at floor/progress milestones (`[f1, 50]`, `[f3, 50]`) inside a delve (`scripts/core/delve.gd:88-97`).
   - If a player repairs their T4/T5 kit after a death and starts directly in Caves, City, or Halls at `10 Str`, they have skipped the `4–8` Strength Potions from earlier biomes and enter with crippled gear.

2. **Camp Patrol Efficiency & Power Rating Penalty:**
   - `GameState.power_rating(c)` (`scripts/autoload/game_state.gd:618-620`) and `GameState.patrol_efficiency(c, biome)` (`scripts/autoload/game_state.gd:1509-1511`) call `hero_stats(c)` directly at Camp.
   - A hero sitting at Camp with `10 Str` after a death—while wearing repaired T3–T5 gear—has their `power_rating(c)` tanked by the `1 / (1 + str_short)` divisor and `0` barrier/block.

3. **Camp Paperdoll & Equipment Comparison Feedback:**
   - `GameState.compare_equip(uid)` (`scripts/autoload/game_state.gd:442-458`) and `Paperdoll._delta_text()` (`scripts/ui/paperdoll.gd:138-152`) evaluate items against the hero's current `str`. When previewing an item from a higher tier where `req > h.str`, the UI shows negative stat deltas without indicating that the penalty is due to missing Strength, and armor tooltips in `CampScreen.gear_lines()` lack the under-strength warning line that weapons have in `Weapons.info_lines()`.

---

## Relevant Files & Symbols
- `scripts/autoload/game_state.gd`:
  - `base_str(c)` / `cleared_str_keys(c)` (new helpers)
  - `hero_stats(c)` (lines 185–280)
  - `compare_equip(uid)` & `compare_text(cmp)` (lines 442–467)
  - `end_run(result)` (lines 1765–1788)
- `scripts/core/delve.gd`:
  - `advance_room` / floor progress milestone check (lines 88–97) and boss kill biome clear
- `scripts/ui/camp_screen.gd`:
  - `gear_lines(g)` (lines 782–803)
- `scripts/ui/paperdoll.gd`:
  - `_delta_text(a, b)` / slot comparison preview (lines 128–152)
- `tests/run_tests.gd`

---

## Locked-In Design Decisions

### 1. Permanent Strength Floor from Cleared Biomes (`scripts/autoload/game_state.gd`)
- Each biome in `heroes[c].cleared` permanently locks in the `+2 Strength` from that biome's two Strength Potion milestones (`strength_potions_at` in `data/biomes.json`):
  - `base_str(c) -> int`: `10 + 2 * heroes[c].get("cleared", []).size()`
    - 0 cleared (Sewers start): **`10 Str`**
    - Sewers cleared (Prison unlocked): **`12 Str`**
    - Prison cleared (Caves unlocked): **`14 Str`**
    - Caves cleared (City unlocked): **`16 Str`**
    - City cleared (Halls unlocked): **`18 Str`**
    - Halls cleared: **`20 Str`**
  - `cleared_str_keys(c) -> Array`: returns all `"%d_%d" % [int(m[0]), int(m[1])]` keys from `DB.biomes[b].strength_potions_at` for every `b in heroes[c].get("cleared", [])`.
- **On Death (`GameState.end_run("death")`):**
  - Instead of resetting `h.str = 10` and `h.str_found = []`, reset:
    ```gdscript
    h.str = base_str(c)
    h.str_found = cleared_str_keys(c)
    ```
  - Update the death log message (`game_state.gd:1784`) from `"back to Lv1 / 10 Str"` to `"back to Lv1 / %d Str" % h.str`.
  - **Level still resets to `1`** (retrainable at the Guild Hall up to `best_level - 2` via `train(c)`), and **equipped gear still cracks** (requiring Blacksmith/Enchanter repair).
- **On Biome Clear & Save Migration:**
  - Whenever a hero clears a biome (or when loading an existing save in `GameState`), ensure `h.str = maxi(int(h.str), base_str(c))` and all `cleared_str_keys(c)` are present in `h.str_found` so re-running an already-cleared biome never double-awards Strength potions.

### 2. Under-Strength UI Preview & Tooltip Warnings (`scripts/ui/paperdoll.gd`, `scripts/autoload/game_state.gd`, `scripts/ui/camp_screen.gd`)
- **Keep Penalized Delta + Append `"(need Str X)"` Tag:**
  - `Paperdoll._delta_text()` and `GameState.compare_equip()` / `compare_text()` continue to show the real (penalized) stat delta when `h.str < req`, and append `"(need Str %d)" % req` whenever the previewed weapon or armor requires more Strength than the hero currently has.
- **Armor Under-Strength Tooltip Line (`CampScreen.gear_lines(g)`):**
  - When viewing known armor in `CampScreen.gear_lines(g)` where `int(d.get("str", 10)) > int(GameState.heroes.get(chosen_hero, {}).get("str", 10))`, add a warning line matching `Weapons.info_lines()`:
    `"Because of your inadequate strength this armor's protection is reduced and its Barrier is lost."`

---

## Implementation Steps

1. **`scripts/autoload/game_state.gd`:**
   - Add `base_str(c: String) -> int` and `cleared_str_keys(c: String) -> Array`.
   - In `end_run("death")`, set `h.str = base_str(c)` and `h.str_found = cleared_str_keys(c)`.
   - In save load / migration (`_migrate()` or `load_dict()`), ensure `h.str = maxi(int(h.get("str", 10)), base_str(c))` and merge `cleared_str_keys(c)` into `h.str_found`.
   - In `compare_equip(uid)` and `compare_text(cmp)`, include `"need_str": req` when `req > int(h.str)` and append `"(need Str %d)" % int(cmp.need_str)`.
2. **`scripts/ui/paperdoll.gd` & `scripts/ui/camp_screen.gd`:**
   - In `Paperdoll` item candidate rows, append `"(need Str %d)" % req` to the delta string when `req > int(h.str)`.
   - In `CampScreen.gear_lines(g)`, add the under-strength warning line for armor when `int(d.get("str", 10)) > hero_str`.
3. **`tests/run_tests.gd`:**
   - Add unit tests verifying that clearing a biome raises `base_str(c)` by `+2`, dying resets `h.str` to `base_str(c)` rather than `10`, and re-running a cleared biome does not award duplicate Strength potions.
