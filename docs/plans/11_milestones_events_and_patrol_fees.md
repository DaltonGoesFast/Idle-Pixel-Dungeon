# Plan 11: Early-Biome `dark_gold` Gates, Patrol Fee Math & Milestones

## Status
Ready for implementation — all design decisions locked in via `/grill-me`.

## Problem Statement
Plans 04 and 05 overhaul the material and gold economy:
- **Plan 04** scales mid-to-late upgrade costs (`iron_ore`, `dark_gold`, `arcane_resin`, `gold`) and requires `8 dark_gold` for Blacksmith Lv 1 $\rightarrow$ Lv 2 and `4 dark_gold` for Enchanter Lv 2 `+1` trinket upgrades.
- **Plan 05** reduces `patrol_yield_per_hour` across `data/biomes.json` (keeping `0 dark_gold` in Sewers and a `0.5/hr` `dark_gold` trickle in Prison) and removes `dark_gold` from the Sewers `"glint"` door event.

Two adjacent economy systems require alignment with Plans 04 and 05:

1. **Remaining Prison Event `dark_gold` Faucets (`data/events.json`):**
   - While Plan 05 removed `dark_gold` from `"glint"` (Sewers) and set Prison patrols to a controlled `0.5/hr` trickle, two repeatable delve events that spawn in **Prison** still award `1–2 dark_gold` per room:
     - **Door Choice `"cells"` (`data/events.json:95-127`):** Spawns in `["caves", "prison", "city", "halls"]`; Door A (`"Rattling bones"`, fight 2 skeletons) rewards **`+2 dark_gold, +10 gold`**.
     - **Special Room `"cell_block"` (`data/events.json:442-476`):** Spawns in `["caves", "prison", "city", "halls"]`; `"Unlock (1 Iron Key)"` rewards **`+2 dark_gold`** + unknown wand, and `"Pry the bars (-6 HP)"` rewards **`+1 dark_gold, +10 gold`**.

2. **Patrol Upfront Provisioning Fee Can Exceed Patrol Gold Payout (`scripts/autoload/game_state.gd:1489-1492`):**
   - `GameState.patrol_fee(biome, c)` currently charges `50%` of **raw `patrol_max_hours()`** gold upfront without factoring in `patrol_efficiency(c, biome)` (`0.25..1.00`):
     ```gdscript
     func patrol_fee(biome: String, c := "") -> Dictionary:
         var g := float(DB.biomes[biome].patrol_yield_per_hour.get("gold", 0)) * patrol_max_hours() / 2.0
         if c != "" and heroes.has(c): g *= 1.0 - minf(PATROL_FEE_CUT_MAX, float(patrol_perks(c).fx.get("fee_cut_pct", 0.0))) / 100.0
         return {"gold": int(g)}
     ```
   - With an upgraded Guild Hall (`patrol_max_hours() == 8`), `patrol_fee()` charges **`4.0 hours` worth of 100%-efficiency gold** upfront (`8 * 0.5`).
   - If a hero has `< 0.50` efficiency (or if the player recalls the patrol after 2–3 hours instead of waiting the full 8 hours), **the player loses net gold by sending a hero on patrol**, and upgrading the Guild Hall from Lv 1 (`2h`) to Lv 3 (`8h`) quadruples the upfront fee.

---

## Relevant Files & Symbols
- `scripts/autoload/game_state.gd`:
  - `patrol_fee(biome, c)` (lines 1489–1492)
- `data/events.json`:
  - `"cells"` (lines 95–127)
  - `"cell_block"` (lines 442–476)
- `data/biomes.json`:
  - `prison.secret_cache` (lines 222–226 — kept at `1 dark_gold`)
- `data/milestones.json`:
  - Milestone definitions (kept at their current small/symbolic `1–5` material rewards)
- `tests/run_tests.gd`

---

## Locked-In Design Decisions

### 1. Align Early-Biome `dark_gold` Faucets with Plan 05 (`data/events.json`, `data/biomes.json`)
- **Zero `dark_gold` in Sewers:** Handled by Plan 05 (`"glint"` Door A reward changed from `{"iron_ore": 4, "dark_gold": 1}` to `{"iron_ore": 3, "gold": 10}`).
- **Replace `dark_gold` in `"cells"` and `"cell_block"` with `iron_ore` / `arcane_resin` (`data/events.json`):**
  - **`"cells"` Door A (`"Rattling bones"`):** Replace `{"dark_gold": 2, "gold": 10}` with **`{"iron_ore": 3, "arcane_resin": 1, "gold": 15}`**.
  - **`"cell_block"` (`"Locked Cell"`):**
    - Option 1 (`"Unlock (1 Iron Key)"`): Replace `{"item_unknown": "wand", "dark_gold": 2}` with **`{"item_unknown": "wand", "arcane_resin": 2, "iron_ore": 3}`**.
    - Option 2 (`"Pry the bars (-6 HP)"`): Replace `{"dark_gold": 1, "gold": 10}` with **`{"iron_ore": 3, "gold": 15}`**.
- **Controlled Prison `dark_gold` Trickle Kept Intact:**
  - Prison retains its `0.5/hr` patrol yield (Plan 05), `prison.secret_cache` (`1 dark_gold`), and `jailbreak` Tengu milestone (`3 dark_gold`), providing a controlled trickle to fund Blacksmith Lv 2 (`8 dark_gold`) and Enchanter Lv 2 (`4 dark_gold`) without allowing players to farm T4/T5 `dark_gold` in Prison rooms.

### 2. Flat 1-Hour Base Gold Patrol Fee Scaled by Hero Efficiency (`scripts/autoload/game_state.gd`)
- Update `GameState.patrol_fee(biome: String, c := "") -> Dictionary` to charge **1.0 hour of expected gold** (scaled by the hero's `patrol_efficiency(c, biome)` when `c != ""` and reduced by `Ring of Elements` `fee_cut_pct`), independent of `patrol_max_hours()`:
  ```gdscript
  func patrol_fee(biome: String, c := "") -> Dictionary:
      var g := float(DB.biomes[biome].patrol_yield_per_hour.get("gold", 0))
      if c != "" and heroes.has(c):
          g *= patrol_efficiency(c, biome)
          g *= 1.0 - minf(PATROL_FEE_CUT_MAX, float(patrol_perks(c).fx.get("fee_cut_pct", 0.0))) / 100.0
      return {"gold": maxi(1, int(round(g)))}
  ```
- **Why this works:**
  - Upgrading the Guild Hall from `2h` to `8h` no longer quadruples the upfront fee.
  - Any patrol lasting more than 1 hour (even with a low-efficiency hero or early recall at 2h) is guaranteed to be net-positive on gold.

### 3. Keep Milestone Rewards Small & Symbolic (`data/milestones.json`)
- Leave `data/milestones.json` rewards at their current small, symbolic amounts (`1–5` materials and fixed `scroll_upgrade` counts). No changes needed to `data/milestones.json`.

---

## Implementation Steps

1. **`data/events.json`:**
   - Update `"cells"` Door A and `"cell_block"` options 1 & 2 to award `iron_ore` / `arcane_resin` / `gold` instead of `dark_gold`.
2. **`scripts/autoload/game_state.gd`:**
   - Update `patrol_fee(biome, c)` to charge 1 hour of efficiency-scaled gold (`maxi(1, int(round(g)))`).
3. **`tests/run_tests.gd`:**
   - Update/add unit tests for `patrol_fee(biome, c)` verifying that an 8h Guild patrol fee does not exceed a 2h recall payout and scales with `patrol_efficiency` and `fee_cut_pct`.
