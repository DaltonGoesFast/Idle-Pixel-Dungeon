# Plan 07: Strength Progression, Death Reset & Biome Skipping

## Status
Revised. Death does **not** bank Strength. Death resets Strength to 10 and closes biome access. Cloth and starting weapons do not crack.

## Revision (player review)
The permanent Strength floor (`10 + 2` per cleared biome) is withdrawn. It was a different death rule, not a fix for the under-strength penalty.

The penalty still makes "repair a Greatsword and walk into Halls at 10 Strength" a trap. Close the door instead of raising the floor:
- Strength resets to 10. Strength potions in a biome can be earned again (`str_found` clears).
- `heroes[c].cleared` clears, so the delve picker returns to Sewers and this hero cannot patrol a biome until they clear it again.
- `boss_kills` stays. Scrolls of Upgrade, Tengu's Mask, subclasses, and the other heroes are untouched.
- Facilities, stash, and gold stay. Forged gear still cracks, except the pieces below.

Cloth and class starting weapons are the kit you always have. They follow the heirloom rule and never crack, including their upgrades. Dying in Plate still cracks the Plate; the hero fights in starter stats at +0 until they equip an uncracked piece (their own Cloth or starter weapon qualifies).

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
  - `end_run(result)` — reset `str` to 10, clear `cleared`, skip starter cracks
  - `hero_stats(c)`, `compare_equip(uid)`, `compare_text(cmp)`
- `scripts/core/delve.gd`:
  - `defeat_changes()` — "Strength reset to 10", biomes locked
- `scripts/ui/camp_screen.gd`:
  - `start_biomes(c)` (reads `cleared`; no change beyond death clearing it)
  - `gear_lines(g)`
- `scripts/ui/paperdoll.gd`:
  - `_delta_text(a, b)`
- `tests/run_tests.gd`

---

## Locked-In Design Decisions

### 1. Death resets Strength and biome access (`scripts/autoload/game_state.gd`)
Do not add `base_str()` and do not migrate saves up to a cleared-biome floor.

On `end_run("death")`, keep the current hero reset and add the biome lock:
```gdscript
h.level = 1; h.xp = 0; h.str = 10; h.talents = []; h.str_found = []
h.cleared = []
```
- Level still retrains at the Guild up to `best_level - 2`.
- `boss_kills`, mask, and subclass stay. Wiping `cleared` re-locks the delve picker (`CampScreen.start_biomes`) and patrol destinations (`can_patrol` requires `biome in cleared`). It does not re-grant Scrolls of Upgrade.
- Death log: `"back to Lv1 / 10 Str. Biomes locked until you clear them again."`
- `Delve.defeat_changes()` keeps `"Strength reset to 10"` when strength was higher. Add `"Biomes locked"` when `cleared` was not empty. Do not print a banked Strength value.

Re-clearing a biome awards its Strength potions again because `str_found` is empty. That is the way back to 12 / 14 / 16 / 18 Strength.

### 2. Cloth and starting weapons never crack (`scripts/autoload/game_state.gd`)
In the death crack loop, skip an item when `heirloom` is set (already) **or** its id is any class's `start_armor` or `start_weapon`:
- `cloth_armor`
- `worn_shortsword`, `dagger`, `studded_gloves`, `mages_staff`

Upgrades on those items survive death. Every other equipped weapon, armor, ring, wand, and artifact still cracks. `hero_stats` already falls back to the class starter at +0 while the equipped piece is cracked; the player can equip their uncracked Cloth or starter weapon without paying a repair.

### 3. Under-Strength UI Preview & Tooltip Warnings (`scripts/ui/paperdoll.gd`, `scripts/autoload/game_state.gd`, `scripts/ui/camp_screen.gd`)
- **Keep Penalized Delta + Append `"(need Str X)"` Tag:**
  - `Paperdoll._delta_text()` and `GameState.compare_equip()` / `compare_text()` continue to show the real (penalized) stat delta when `h.str < req`, and append `"(need Str %d)" % req` whenever the previewed weapon or armor requires more Strength than the hero currently has.
- **Armor Under-Strength Tooltip Line (`CampScreen.gear_lines(g)`):**
  - When viewing known armor in `CampScreen.gear_lines(g)` where `int(d.get("str", 10)) > int(GameState.heroes.get(chosen_hero, {}).get("str", 10))`, add a warning line matching `Weapons.info_lines()`:
    `"Because of your inadequate strength this armor's protection is reduced and its Barrier is lost."`

---

## Implementation Steps

1. **`scripts/autoload/game_state.gd`:**
   - In `end_run("death")`, set `h.cleared = []` alongside the existing `h.str = 10` and `h.str_found = []`. Do not add a Strength floor.
   - Skip cracking when the item id is a class `start_weapon` or `start_armor`.
   - In `compare_equip(uid)` and `compare_text(cmp)`, include `"need_str": req` when `req > int(h.str)` and append `"(need Str %d)" % int(cmp.need_str)`.
2. **`scripts/core/delve.gd`:**
   - Keep the "Strength reset to 10" defeat line. Mention locked biomes. Do not mention a banked Strength.
3. **`scripts/ui/paperdoll.gd` & `scripts/ui/camp_screen.gd`:**
   - In `Paperdoll` item candidate rows, append `"(need Str %d)" % req` to the delta string when `req > int(h.str)`.
   - In `CampScreen.gear_lines(g)`, add the under-strength warning line for armor when `int(d.get("str", 10)) > hero_str`.
4. **`tests/run_tests.gd`:**
   - Dying sets `str` to 10, clears `cleared`, and leaves `boss_kills` in place.
   - A second clear of Sewers awards its Strength potions again.
   - Cloth and a class starter weapon do not crack; a Tier 3 weapon does.
