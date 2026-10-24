# Plan 08: Hero Barrier Cap & Shielding Scaling

## Status
Ready for implementation — all design decisions locked in via `/grill-me`.

## Problem Statement
Plan 01 increases Armor `barrier` and `barrier_per_lvl` so higher-tier armor provides a meaningful per-fight buffer against late-game damage:
- **T3 Mail Armor:** `4 + 1.0/lvl` (`7` at `+3`, `10` at `+6`)
- **T4 Scale Armor:** `6 + 1.5/lvl` (`10` at `+3`, `15` at `+6`)
- **T5 Plate Armor:** `8 + 2.0/lvl` (`14` at `+3`, `20` at `+6`)

Two existing Barrier rules in `scripts/autoload/game_state.gd` and `scripts/core/delve.gd` conflict with these numbers:

1. **The `ht / 2` Maximum Barrier Clamp (`game_state.gd:279`):**
   - At the end of `GameState.hero_stats(c)` (`scripts/autoload/game_state.gd:279`), the hero's maximum Barrier is hard-clamped to **50% of Max HP (`ht / 2`)**:
     ```gdscript
     s.barrier_max = mini(int(s.barrier_max), int(s.ht) / 2)
     ```
   - Hero Max HP is `ht = 20 + 5 * (level - 1)`.
   - Combine Plan 01 armor with innate/heirloom/talent/ring/subclass Barrier sources:
     - Warrior base (`5`) + Broken Seal (`2`) + `Iron Will` (`+1`) + `Ring of Tenacity +3` (`+4`) = `12` before armor.
     - With `Scale +3` (`10`) or `Plate +3` (`14`), total Barrier is `22–26`.
   - When a hero is at Camp at `Lv 1` after a death (`20 HP`, so `ht / 2 = 10`), `s.barrier_max` hits the `10` ceiling immediately. As a result, `GameState.compare_equip()` and `Paperdoll` show **`+0 Barrier`** when comparing or upgrading armor at Camp!

2. **`Potion of Shielding` Flat `+10` & `ht` Clamp (`game_state.gd:533`, `delve.gd:211-213`):**
   - `Potion of Shielding` (`data/items.json:668-675`, `scripts/autoload/game_state.gd:533`) grants a flat **`+10` Barrier** (`run.shield_next += 10`), and `Delve.new_combat()` clamps `c.hero.barrier` to `int(c.hero.ht)`.
   - In Sewers (`20 HP`), `+10` is `50%` of Max HP; in Demon Halls (`80–100 HP`, where enemies hit for `17–20` damage under Plan 01), `+10` is half a single hit. By contrast, `Potion of Healing` (`game_state.gd:613-616`) scales dynamically as `maxi(10, int(ht * 0.30))`.

---

## Relevant Files & Symbols
- `scripts/autoload/game_state.gd`:
  - `hero_stats(c)` (line 279) — `s.barrier_max` cap.
  - `potion_shield(c)` (new helper matching `potion_heal(c)` at lines 613–616).
  - `delve_use_pack(k)` (line 533) — `"potion_shielding"` effect.
- `scripts/core/delve.gd`:
  - `new_combat(gs, ev)` (lines 211–213) — applies `run.shield_next` to `c.hero.barrier`.
- `data/items.json`:
  - `_materials.potion_shielding` (lines 668–675).
- `tests/run_tests.gd`

---

## Locked-In Design Decisions

### 1. Remove the `ht` Cap on `s.barrier_max` in `GameState.hero_stats(c)` (`scripts/autoload/game_state.gd`)
- Remove line 279 (`s.barrier_max = mini(int(s.barrier_max), int(s.ht) / 2)`) from `GameState.hero_stats(c)`.
- Since Plan 01 already zeroes out armor Barrier (`abar = 0`) whenever `armor_str_short > 0` and Plan 07 gates base Strength by cleared biomes, `s.barrier_max` is simply the full sum of class + heirloom + armor + ring + talent + subclass Barrier.
- Camp tooltips, `Paperdoll`, `compare_equip()`, and Lv 1 post-death heroes wearing repaired endgame armor never clip or show false `+0 Barrier` deltas.

### 2. Scale `Potion of Shielding` Like `Potion of Healing` (`max(10, 30% of Max HP)`) Uncapped (`scripts/autoload/game_state.gd`, `scripts/core/delve.gd`, `data/items.json`)
- In `data/items.json` (`_materials.potion_shielding`):
  - Add `"shield": 10, "shield_pct": 0.3` and update `"desc"` to:
    `"Your next fight starts with +max(10, 30% of max HP) Barrier."`
- In `GameState`:
  - Add helper `potion_shield(c: String) -> int`:
    ```gdscript
    func potion_shield(c: String) -> int:
        var p: Dictionary = DB.materials.potion_shielding
        var hs := hero_stats(c)
        return maxi(int(p.get("shield", 10)), int(float(hs.ht) * float(p.get("shield_pct", 0.3))))
    ```
  - In `delve_use_pack("potion_shielding")`:
    ```gdscript
    var sh := potion_shield(c)
    run.shield_next = int(run.get("shield_next", 0)) + sh
    say("A shimmering shield: +%d Barrier in your next fight." % sh)
    ```
- In `Delve.new_combat(gs, ev)` (`scripts/core/delve.gd:211-213`):
  - Stack `run.shield_next` in full on top of `c.hero.barrier` without clamping to `c.hero.ht`:
    ```gdscript
    if int(run.get("shield_next", 0)) > 0:
        c.hero.barrier = int(c.hero.barrier) + int(run.shield_next); run.shield_next = 0
        c._log("Your shield shimmers: +Barrier.")
    ```

---

## Implementation Steps

1. **`scripts/autoload/game_state.gd`:**
   - Remove `s.barrier_max = mini(int(s.barrier_max), int(s.ht) / 2)` from `hero_stats(c)`.
   - Add `potion_shield(c: String) -> int` and update `delve_use_pack("potion_shielding")` to use it.
2. **`scripts/core/delve.gd`:**
   - In `new_combat(gs, ev)`, change `c.hero.barrier = mini(int(c.hero.ht), int(c.hero.barrier) + int(run.shield_next))` to `c.hero.barrier = int(c.hero.barrier) + int(run.shield_next)`.
3. **`data/items.json`:**
   - Update `_materials.potion_shielding` with `"shield": 10, "shield_pct": 0.3` and updated description.
4. **`tests/run_tests.gd`:**
   - Update any test asserting the old `ht / 2` barrier clamp and add unit tests for uncapped gear `barrier_max` and `potion_shield(c)` scaling.
