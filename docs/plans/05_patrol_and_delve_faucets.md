# Plan 05: Taming Material Faucets (Patrol Multipliers & Floor Drops)

## Status
Ready for implementation — design decisions finalized via review.

## Problem Statement
Material income currently snowballs out of control because **Offline Patrols** multiply four separate bonuses together across up to 3 simultaneous idle heroes, while **Active Delves** also award high free event payouts and leak `dark_gold` in the Sewers:

1. **Compounding Multiplicative Patrol Math (`GameState.patrol_preview`, `scripts/autoload/game_state.gd:1497-1640`):**
   - Up to 3 idle heroes can patrol while 1 hero delves.
   - Each patrolling hero's reward is calculated as:
     $$\text{Reward} = \text{base\_rate} \times \text{worked} \times \text{eff} \times \text{gear\_mult} \times \text{perk\_bonus}$$
     - `worked`: Up to `8h` (`+2.5h` from Timekeeper's Hourglass) $\times$ `(1 + Ring of Haste time_pct)` = **10–13+ effective hours**.
     - `eff`: `clamp((power + patrol_power) / (str_gate + 2), 0.25, 1.25)` = easily **1.25x**.
     - `gear_mult`: `1.0 + 0.15 * sqrt(total_gear_lvl)` = **1.35x–1.60x**.
     - `perk_bonus`: Ring of Wealth / Might / Furor / Energy / wand / artifact perks = **1.15x–1.35x**.
   - **Combined Multiplier:** `1.25 * 1.50 * 1.25` = **~2.35x per hour** (or **~3.0x** with Hourglass/Haste).
   - With base rates in `data/biomes.json` (`3–8 ore/hr`, `1–5 dark_gold/hr`, `1–5 resin/hr`) and curios dropping every `2h`, a single 8-hour cycle across 3 heroes dumps **150–300+ Iron Ore, 40–80+ Dark Gold, 50–100+ Arcane Resin, and 10–15 Rings**.

2. **Generous Free Delve Event Payouts & Early `dark_gold` Leak (`data/events.json`):**
   - `glint` ("Door A: A metallic glint", fight 1 crab) can spawn in **Sewers** (`events.json:63-92`) and awards `4 iron_ore, 1 dark_gold` before the player ever leaves Biome 1.
   - `armory` ("Guard Armory", `events.json:478-499`) gives **`+5 iron_ore, +1 torch` for free** (`Scavenge` has zero cost or risk).
   - `crystal_vein` ("Crystal Vein", `events.json:501-533`) gives **`+3 dark_gold, +3 iron_ore`** for `-12 torch_fuel`.

---

## Relevant Files & Symbols
- `scripts/autoload/game_state.gd`:
  - `patrol_efficiency(c, biome)` (lines 1498–1500)
  - `PATROL_GEAR_K` / `patrol_gear_mult_for(lvl)` (lines 1503, 1519–1520)
  - `patrol_preview(c)` (lines 1613–1640)
- `data/biomes.json` (`patrol_yield_per_hour` and `patrol_curio_every_hours` per biome)
- `data/events.json` (`glint`, `armory`, `crystal_vein`)
- `tests/run_tests.gd` (`test_patrol_perks` and economy/event tests)

---

## Finalized Design & Solution

### 1. Additive Patrol Bonus Multiplier Capped at `1.50x` (`scripts/autoload/game_state.gd`)
Keep hourly patrol rates linear across the full patrol duration (no penalty for 4h/8h Guild caps), and tame multiplier stacking:
- **Cap Base Efficiency at `1.00` (was `1.25`):**
  - In `GameState.patrol_efficiency(c, biome)`:
    ```gdscript
    func patrol_efficiency(c: String, biome: String) -> float:
        var pw := float(power_rating(c)) + float(patrol_perks(c).fx.get("power", 0.0))
        return clampf(pw / (float(DB.biomes[biome].str_gate) + 2.0), 0.25, 1.0)
    ```
  - Meeting the biome's strength gate gives `100%` efficiency (`1.0x`); under-geared heroes still scale from `0.25..1.0` and benefit from patrol power perks (`Ring of Tenacity`, `Cape of Thorns`).
- **Lower `PATROL_GEAR_K` and Combine Gear + Perk Bonuses Additively (`PATROL_MULT_CAP := 1.50`):**
  - Lower `PATROL_GEAR_K` from `0.15` to **`0.08`** (`+8%` at Lv1, `+18%` at Lv5, `+25%` at Lv10, `+32%` at Lv16).
  - In `GameState.patrol_preview(c)`:
    - Combine `gear_bonus` and `perk_bonus` additively on top of `1.0`, clamped to `PATROL_MULT_CAP` (`1.50`):
      ```gdscript
      const PATROL_GEAR_K := 0.08
      const PATROL_MULT_CAP := 1.50
      ```
      ```gdscript
      for k in b.patrol_yield_per_hour:
          var gear_bonus := (gm - 1.0) if k != "gold" else (gm - 1.0) * PATROL_GOLD_GEAR_SHARE
          var perk_bonus := ((allp if k != "gold" else 0.0) + float(fx.get(k + "_pct", 0.0))) / 100.0
          var mult := minf(PATROL_MULT_CAP, 1.0 + gear_bonus + perk_bonus)
          out[k] = float(b.patrol_yield_per_hour[k]) * worked * eff * mult
      ```

### 2. Rebalance Base `patrol_yield_per_hour` & Curio Intervals (`data/biomes.json`)
Lower base hourly patrol yields by ~35–40% and slow curio (ring) drops from `2h` to `4h` in Sewers/Prison/Caves and `3h` in City/Halls. Prison retains a `0.5/hr` `dark_gold` trickle (supporting Plan 04's Blacksmith Lv1$\rightarrow$Lv2 and Enchanter Lv2 `+1` trinket costs), while Caves+ is the main `dark_gold` source:

| Biome | Current `/hr` (`Gold / Ore / D.Gold / Resin / Dew / Seeds`) | Finalized `/hr` (`Gold / Ore / D.Gold / Resin / Dew / Seeds`) | `patrol_curio_every_hours` |
| :--- | :--- | :--- | :--- |
| **Sewers** | `15g / 3 ore / 0 dg / 1 resin / 4 dew / 2 seeds` | **`12g / 2 ore / 0 dg / 0.5 resin / 3 dew / 2 seeds`** | **`4`** (was `3`) |
| **Prison** | `25g / 5 ore / 1 dg / 2 resin / 3 dew` | **`18g / 3 ore / 0.5 dg / 1 resin / 2 dew`** | **`4`** (was `2`) |
| **Caves** | `35g / 7 ore / 2 dg / 2 resin / 3 dew` | **`25g / 4 ore / 1 dg / 1.5 resin / 2 dew`** | **`4`** (was `2`) |
| **City** | `45g / 8 ore / 3 dg / 3 resin / 3 dew` | **`35g / 5 ore / 1.5 dg / 2 resin / 2 dew`** | **`3`** (was `2`) |
| **Halls** | `60g / 6 ore / 5 dg / 5 resin / 3 dew` | **`45g / 4 ore / 2.5 dg / 3 resin / 2 dew`** | **`3`** (was `2`) |

### 3. Delve Event & Drop Adjustments (`data/events.json`)
- **Remove `dark_gold` from Sewers (`glint` door, `data/events.json:63-74`):**
  - Replace `dark_gold: 1` on `glint` Door A (`"Door A: A metallic glint"`, fight 1 crab) with `gold: 10`, and reduce `iron_ore` from `4` to `3` (`{"iron_ore": 3, "gold": 10}`).
- **Trim `Guard Armory` (`armory`, `data/events.json:478-499`):**
  - Reduce free `Scavenge` reward from `{"iron_ore": 5, "torch": 1}` $\rightarrow$ **`{"iron_ore": 2, "torch": 1}`**.
- **Trim `Crystal Vein` (`crystal_vein`, `data/events.json:501-533`):**
  - Already gated to `["caves", "city", "halls"]`.
  - Reduce `"Mine it (-12 torch)"` reward from `{"dark_gold": 3, "iron_ore": 3}` $\rightarrow$ **`{"dark_gold": 2, "iron_ore": 2}`**.
- **Preserve Core Baseline Loops:**
  - Keep the guaranteed `+1 iron_ore` on floor descent in `Delve.descend()` (`scripts/core/delve.gd:522`).
  - Keep Blacksmith spare ring melting (`GameState.ring_break_yield()`) at `{"gold": 5, "arcane_resin": 1}`.
