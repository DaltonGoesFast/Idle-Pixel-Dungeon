# Plan 01: Armor Tier Scaling (Separating T2 Leather from T4/T5 Armor)

## Status
Ready for implementation, with the review notes below. Plate's power and the Barrier cap are intentionally not solved here.

## Revision (player review)
- **Leather's tradeoff is the goal.** Less damage reduction, more Barrier. Cloth and Leather stay on `+0.5 DR / +1 Barrier` per level. Do not "fix" Leather by giving it Plate's reduction.
- **Plate is allowed to be strong.** The City and Halls damage bumps stay. A later pass will deal with Plate being too much. Do not nerf Plate's DR or Barrier in this plan.
- **The half-HP Barrier cap stays** (Plan 08). Armor can still grant Barrier; the cap is what keeps that buffer from becoming a second health bar. At level 1 the cap is 10, so most of Plate's Barrier does not show until max HP grows. That is accepted.
- **City playtest bar:** Dwarf City should be dangerous in Leather and a Tier 2 weapon. Scale armor and a Tier 4 weapon are the intended kit. Surviving City in Masterwork Leather is a failure of this plan.

## Problem Statement
Currently, Tier 2 (Leather) armor remains viable all the way through Dwarf City and Demon Halls because armor base stats and upgrade scaling are completely flat across all tiers:
1. **Tiny Base Stat Spacing (`data/items.json`):**
   - Each armor tier only adds **+1 flat DR** and **+1 Barrier** (`T1 Cloth: 1/1`, `T2 Leather: 2/2`, `T3 Mail: 3/3`, `T4 Scale: 4/4`, `T5 Plate: 5/5`).
2. **Flat Upgrade Scaling (`scripts/autoload/game_state.gd`):**
   - In `GameState.hero_stats()` (`game_state.gd:197-198`), every upgrade level adds **+1 DR** regardless of tier:
     ```gdscript
     var dr := int(ad.get("dr", 0)) + al + Weapons.block_dr(wd, wl)
     ```
   - Upgrades add **+0 Barrier** (`int(ad.get("barrier", 0))`).
   - Unlike vanilla Shattered Pixel Dungeon (where armor upgrades scale max block by `+tier` per level, making Plate scale 5x faster than Cloth), Leather (`T2`) gains the exact same `+1 DR/lvl` as Plate (`T5`).
3. **Endgame Impact:**
   - **Leather +3** has **5 DR**—identical to base **Plate +0**, while only requiring **12 Strength**.
   - **Masterwork Leather +6** has **8 DR**, which negates most of Dwarf City mob damage (`5–9 dmg`) and half of Demon Halls mob damage (`12–16 dmg`).
   - At any equal upgrade level, the gap between T2 Leather and T5 Plate is only **3 flat DR and 3 starting Barrier**.

---

## Relevant Files & Symbols
- `data/items.json` (lines 491–540: `cloth_armor`, `leather_armor`, `mail_armor`, `scale_armor`, `plate_armor` definitions)
- `data/mobs.json` (Dwarf City and Demon Halls mob physical `dmg` values)
- `scripts/autoload/game_state.gd`:
  - `hero_stats(c)` (lines 185–280)
  - `armor_dr(ad, al)` / `armor_barrier(ad, al)` helpers
- `scripts/ui/camp_screen.gd`:
  - `gear_stats(g)` (line 719: Compare table DR & Barrier rows)
  - `gear_lines(g)` (lines 790–791: Stash item window stats)
  - `_recipe_lines(r)` (line 1111: Forge recipe stats)
  - `_open_gear_forge(uid)` (line 1130: Blacksmith upgrade preview)
- `tests/run_tests.gd` (Unit tests asserting armor DR, Barrier, and under-strength penalties)

---

## Locked-In Design Decisions

1. **Armor Base & Per-Level Scaling (`data/items.json`):**
   - Use explicit `dr_per_lvl` and `barrier_per_lvl` fields with `floor(per_lvl * lvl)` integer rounding, widened base stats on T3–T5, and toned-down T3–T5 per-level scaling so endgame armor doesn't become invulnerable:

| Armor ID | Tier | Base Str | Old Base (`DR / Bar`) | New Base (`DR / Bar`) | Scaling (`+DR / +Bar` per lvl) | +1 (`DR / Bar`) | +2 (`DR / Bar`) | +3 (`DR / Bar`) | +6 (`DR / Bar`) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `cloth_armor` | 1 | 10 | `1 / 1` | `1 / 1` | `+0.5 / +1.0` | `1 / 2` | `2 / 3` | **`2 / 4`** | `4 / 7` |
| `leather_armor` | 2 | 12 | `2 / 2` | `2 / 2` | `+0.5 / +1.0` | `2 / 3` | `3 / 4` | **`3 / 5`** | `5 / 8` |
| `mail_armor` | 3 | 14 | `3 / 3` | `3 / 4` | `+1.0 / +1.0` | `4 / 5` | `5 / 6` | **`6 / 7`** | `9 / 10` |
| `scale_armor` | 4 | 16 | `4 / 4` | `5 / 6` | `+1.0 / +1.5` | `6 / 7` | `7 / 9` | **`8 / 10`** | `11 / 15` |
| `plate_armor` | 5 | 18 | `5 / 5` | `7 / 8` | `+1.5 / +2.0` | `8 / 10` | `10 / 12` | **`11 / 14`** | `16 / 20` |

2. **Armor Upgrade Cap:**
   - **No tier-specific cap.** All armor tiers continue to use the standard Blacksmith `forge_cap()` (`+1..+3`, or `+6` Masterwork). Because **Leather +6** (`5 DR / 8 Bar`) is strictly weaker than un-upgraded **Plate +0** (`7 DR / 8 Bar`) and Masterwork steps cost `200 * lvl²` gold, low-tier armor naturally falls off without special cap rules.

3. **Strength Requirement & Under-Strength Penalty (`scripts/autoload/game_state.gd`):**
   - **Fixed STR requirement:** Armor STR requirements stay fixed at base `str` (`10 / 12 / 14 / 16 / 18` — no upgrade STR discount on armor; `Weapons.str_req` continues returning `base` for non-weapons).
   - **Under-strength penalty:** When `hero_str < armor_str`:
     - Effective armor DR is divided by `1 + missing_str`: `armor_dr = int(armor_dr / (1 + missing_str))` (applied before adding weapon `block_dr` or ring/talent/subclass DR).
     - Effective armor Barrier is **`0`** (the hero only keeps class base/heirloom/ring/talent/subclass Barrier).

4. **Moderate (Halfway) Dwarf City & Demon Halls Mob Physical Damage Bump (`data/mobs.json`):**
   - Raise Dwarf City and Demon Halls physical `dmg` roughly halfway toward the aggressive numbers so Scale/Plate feel balanced without over-tuning before playtesting:
     - **Dwarf City:**
       - `ghoul` (Dwarven Ghoul): `dmg` `9 -> 11`
       - `warlock` (Dwarf Warlock): melee `dmg` `7 -> 9` (magic `zap_dmg` stays `9` ignoring DR)
       - `monk` (Dwarf Monk, `0.5` delay): `dmg` `5 -> 7`
       - `golem` (Golem, `1.5` delay): `dmg` `15 -> 18`
       - `dking` (King of Dwarves): `dmg` `8 -> 10` (+3 in Phase 2 = `13`; `blast_dmg` stays `8` ignoring DR)
       - `ghoul_minion` (Risen Dwarf): `dmg` `6 -> 8`
     - **Demon Halls:**
       - `succubus` (Succubus): `dmg` `16 -> 19`
       - `ripper` (Ripper Demon, `0.6` delay): `dmg` `14 -> 17`
       - `eye` (Evil Eye): melee `dmg` `12 -> 15` (`zap_dmg` stays `20` ignoring DR)
       - `scorpio` (Scorpio): `dmg` `16 -> 20`
       - `larva` (God's Larva): `dmg` `9 -> 12`
       - `yog` (Yog-Dzewa): melee `dmg` `14 -> 17` (`beam_dmg` stays `9` ignoring DR)
       - `fist_burning` (Burning Fist): `dmg` `8 -> 13`
       - `fist_rotting` (Rotting Fist): `dmg` `7 -> 12` (+1 poison)
       - `fist_bright` (Bright Fist): melee `dmg` `6 -> 10` (`zap_dmg` `6 -> 7` ignoring DR)

5. **Out of Scope / Next Plan Note (Early/Mid-Game Offense):**
   - A Rogue with `+2 Mail` and a `+2 Mace` still one-shots regular Caves enemies via door/grass Surprise attacks (`x1.5–x2.5` ignoring DR, noted in DECISIONS #206). This armor plan does not change Caves Mail DR (`3 + lvl` before and after) or Surprise damage; we will address mid-game Surprise / offensive scaling in a separate follow-up plan.

---

## Implementation Steps

### 1. Update `data/items.json` & `data/mobs.json`
- Add `dr_per_lvl` and `barrier_per_lvl` and update base `dr` and `barrier` on `cloth_armor`, `leather_armor`, `mail_armor`, `scale_armor`, and `plate_armor`.
- Update City and Halls mob `dmg` (and `tuned` notes) in `data/mobs.json`.

### 2. Update `GameState` Armor Formulas (`scripts/autoload/game_state.gd`)
- Add static/helper functions `armor_dr(ad: Dictionary, al: int) -> int` and `armor_barrier(ad: Dictionary, al: int) -> int`:
  ```gdscript
  static func armor_dr(ad: Dictionary, al: int) -> int:
      return int(ad.get("dr", 0)) + int(floor(float(ad.get("dr_per_lvl", 1.0)) * maxi(0, al)))

  static func armor_barrier(ad: Dictionary, al: int) -> int:
      return int(ad.get("barrier", 0)) + int(floor(float(ad.get("barrier_per_lvl", 0.0)) * maxi(0, al)))
  ```
- In `GameState.hero_stats(c)`:
  ```gdscript
  var adr := armor_dr(ad, al)
  var abar := armor_barrier(ad, al)
  var armor_str_short := maxi(0, int(ad.get("str", 10)) - int(h.str))
  if armor_str_short > 0:
      adr = adr / (1 + armor_str_short)
      abar = 0
  var dr := adr + Weapons.block_dr(wd, wl)
  var barrier := int(def.base_barrier) + int(def.heirloom_barrier) + abar
  ```

### 3. Update UI Tooltips & Previews (`scripts/ui/camp_screen.gd`)
- In `gear_stats(g)`: use `GameState.armor_dr(d, lv)` for `"DR"` and add `"Barrier": GameState.armor_barrier(d, lv)` when `d.has("barrier")`.
- In `gear_lines(g)` and `_recipe_lines(r)`: show both `DR` and `Barrier` alongside `Str`.
- In `_open_gear_forge(uid)`: show the `DR` and `Barrier` upgrade step preview for armor when upgrading at the Blacksmith.

### 4. Update Tests & Docs (`tests/run_tests.gd`, `docs/DECISIONS.md`, `docs/CHANGELOG.md`)
- Update and add assertions in `tests/run_tests.gd` for `armor_dr`, `armor_barrier`, under-strength armor penalties (`adr / (1 + missing_str)` and `0` armor barrier), and City/Halls combat expectations.
- Log DECISIONS #218 and add an Unreleased entry in `docs/CHANGELOG.md`.
