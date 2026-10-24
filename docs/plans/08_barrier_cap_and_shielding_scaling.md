# Plan 08: Hero Barrier Cap & Shielding Scaling

## Status
Revised. **Keep the half-HP Barrier cap.** Plan 01's larger armor Barrier is fine; this plan no longer removes the clamp that contains it.

## Revision (player review)
Barrier is already too strong. Deleting `s.barrier_max = mini(barrier_max, ht / 2)` would make it stronger, and it would let a level-1 hero in Plate walk around with more Barrier than health.

What the cap actually does:
- Max HP is `20 + 5 * (level - 1)`. The cap is half of that.
- Level 1: 20 HP, cap **10**. A Warrior already has 7 from class and Broken Seal, so armor can add about 3 before the rest is clipped. Plate's 8–20 Barrier mostly does not show at level 1. That is why camp compare draws `+0 Barrier` after a death, and it is also why the cap matters.
- Level 16: about 95 HP, cap **47**. Plate +3 (14) plus class Barrier fits under the cap. Late-game Plate is not restrained by this clamp. Plate's endgame strength is a later pass (Plan 01), not a reason to delete the cap.

Fix the lying compare UI. Do not fix it by removing the cap.

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

### 1. Keep the `ht / 2` cap (`scripts/autoload/game_state.gd`)
- Leave `s.barrier_max = mini(int(s.barrier_max), int(s.ht) / 2)` in place (DECISIONS #147).
- Camp compare and Paperdoll must not pretend clipped Barrier is a `+0` upgrade. Show the armor's own Barrier from `armor_barrier(ad, al)`, and when the hero's cap eats the increase, append `"capped at half max HP (%d)" % (ht / 2)`.
- The compare delta can show the unclamped armor change and the cap note together. It must not remove the clamp from `hero_stats()`.

### 2. Scale `Potion of Shielding` Like `Potion of Healing`, still inside the cap
- In `data/items.json` (`_materials.potion_shielding`):
  - Add `"shield": 10, "shield_pct": 0.3` and update `"desc"` to:
    `"Your next fight starts with +max(10, 30% of max HP) Barrier, up to half your max HP."`
- `GameState.potion_shield(c)` returns `maxi(10, int(ht * 0.30))`.
- In `Delve.new_combat`, add `shield_next` and then clamp to the same ceiling as gear: `c.hero.barrier = mini(int(c.hero.ht) / 2, int(c.hero.barrier) + int(run.shield_next))`. Extra potion Barrier past the cap is wasted. Potions do not stack through the ceiling.

---

## Implementation Steps

1. **`scripts/autoload/game_state.gd` and camp compare UI:**
   - Keep the `ht / 2` clamp in `hero_stats(c)`.
   - Add `potion_shield(c)` and use it from `delve_use_pack("potion_shielding")`.
   - Paperdoll / `compare_equip` show armor Barrier before the cap, with a cap note when the hero total will not rise.
2. **`scripts/core/delve.gd`:**
   - In `new_combat`, apply `shield_next` and clamp `c.hero.barrier` to `int(c.hero.ht) / 2`.
3. **`data/items.json`:**
   - Update `_materials.potion_shielding` with `"shield": 10, "shield_pct": 0.3` and the capped description.
4. **`tests/run_tests.gd`:**
   - Assert the `ht / 2` clamp still holds for geared heroes and for Shielding potions. Assert compare text still reports armor Barrier when the hero is level 1.
