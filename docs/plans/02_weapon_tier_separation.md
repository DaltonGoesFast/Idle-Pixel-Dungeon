# Plan 02: Weapon Tier Separation & Fixing T2 Outliers

## Status
Ready for implementation — all design decisions locked in.

## Problem Statement
Tier 2 weapons currently match or outperform Tier 3, Tier 4, and even base Tier 5 weapons due to three overlapping issues in `data/items.json`, `scripts/core/weapons.gd`, and `scripts/autoload/game_state.gd`:

1. **Deterministic Damage Compression (`Weapons.dmg`, `scripts/core/weapons.gd:15-28`):**
   - Damage is calculated as `floor((min + max) / 2)`, where `min = tier + lvl` and `max = base_max + lvl * max_per_lvl`.
   - Because `min` only increases by `+1` per tier and `+1` per level for all weapons, almost all tier separation depends on `base_max` and `max_per_lvl`.

2. **Over-Tuned T2 Outliers (`data/items.json:96-187`):**
   - **Spear (T2):** Has `max: [20, 4]`, `delay: 1.5`, `reach: 2`.
     - Base average damage at `+0` is **11** (`(2 + 20) / 2`), which ties **T3 Sword +0 (11)** and **T5 Greatshield +0 (11)**, and beats **T3 Mace/Scimitar/Whip +0 (9)**.
     - Its upgrade scaling is `+1 min / +4 max` (**+2.5 avg dmg/lvl**)—the exact same scaling as T3 Sword! At `+3`, a T2 Spear deals **18 dmg** (beating T4 Longsword +1 at 17 and T5 Greatsword +0 at 17) while *also* having `reach: 2` (which gives a free kiting hit before melee enemies can close in).
   - **Sickle (T2):** Has `max: [20, 3]`, `acc: 0.68`. Base damage is **11**, and at `+3` it deals **17 dmg** (tying **T5 Greatsword +0**).
   - **Shortsword (T2):** Has `max: [15, 3]`. Base is **8**, scaling at **+2.0 dmg/lvl**. At `+3` it deals **14 dmg** (tying **T4 Longsword +0**), and at Masterwork `+6` it deals **20 dmg** (beating **T5 Greatsword +0** at 17).
   - **Dirk (T2):** Has `max: [12, 3]`, `surprise_pct: 0.67`. Scales at `+2.0 dmg/lvl` plus `+67%` bonus toward max on every surprise attack before the `1.5x–3.0x` surprise multiplier.

3. **Flat Under-Strength Damage Penalty (`GameState.hero_stats`, `scripts/autoload/game_state.gd:200-201`):**
   - Currently, being under-strength on a weapon only subtracts a flat `-2 * str_short` from damage (`dmg = maxi(1, dmg - 2 * str_short)`).
   - On high-tier weapons with higher base and upgraded damage, a 10-Str hero on Floor 1 can brute-force a T4/T5 weapon right through the flat `-2 * str_short` penalty.

---

## Relevant Files & Symbols
- `data/items.json` (lines 1–490: weapon definitions for T1–T5)
- `scripts/core/weapons.gd`:
  - `min_dmg(d, lvl)` (lines 15–17)
  - `max_dmg(d, lvl)` (lines 19–23)
  - `dmg(d, lvl)` (lines 25–28)
  - `str_req(d, lvl)` (lines 30–35)
- `scripts/autoload/game_state.gd`:
  - `hero_stats(c)` (lines 185–215: weapon damage, `block_dr`, and under-strength penalty)
- `tests/run_tests.gd` (Weapon damage, tier separation, and under-strength unit tests)

---

## Locked-In Design Decisions

### 1. Bring T2 Weapons in Line with Tier 2 Scaling (`data/items.json`)
Standardize `max_per_lvl` on T2 weapons to **`+2 max/lvl`** (so T2 scales at **`+1 min / +2 max` = +1.5 avg dmg/lvl** instead of T3 scaling) and pull down the T2 base `max[0]` outliers:

| Weapon ID | Tier | Old `max` `[base, per_lvl]` | Old `+0 / +3 / +6` Dmg | New `max` `[base, per_lvl]` | New `+0 / +1 / +2 / +3 / +6` Dmg | Notes |
| :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| `shortsword` | T2 | `[15, 3]` | `8 / 14 / 20` | **`[13, 2]`** | **`7 / 9 / 10 / 12 / 16`** | Reliable 1.0 spd T2 baseline |
| `hand_axe` | T2 | `[12, 3]` | `7 / 13 / 19` | **`[11, 2]`** | **`6 / 8 / 9 / 11 / 15`** | Accurate (`1.32x` acc) |
| `spear` | T2 | `[20, 4]` | `11 / 18 / 26` | **`[15, 2]`** | **`8 / 10 / 11 / 13 / 17`** | `reach: 2`, `delay: 1.5`; no longer out-scales T3 Sword |
| `quarterstaff`| T2 | `[12, 3]` | `7 / 13 / 19` | **`[11, 2]`** | **`6 / 8 / 9 / 11 / 15`** | Grants `+1 flat DR` (`block: [2, 0]`) |
| `dirk` | T2 | `[12, 3]` | `7 / 13 / 19` | **`[10, 2]`** | **`6 / 7 / 9 / 10 / 15`** | Has `0.67` surprise bonus |
| `sickle` | T2 | `[20, 3]` | `11 / 17 / 23` | **`[16, 2]`** | **`9 / 10 / 12 / 13 / 18`** | Low accuracy (`0.68x`) tradeoff |

*(Tier 1 and Tier 3 weapons remain at their current SPD v4 numbers in `data/items.json`.)*

### 2. Buff T4 & T5 Upgrade Floor (`scripts/core/weapons.gd`) & Base `max[0]` (`data/items.json`)
- **Min Damage Scaling (`Weapons.min_dmg`):**
  - Change `Weapons.min_dmg(d, lvl)` from `tier + lvl` to:
    ```gdscript
    static func min_dmg(d: Dictionary, lvl: int) -> int:
        var t := int(d.get("tier", 1))
        return t + maxi(0, lvl) * maxi(1, t - 2)
    ```
  - T1–T3 continue to gain `+1 min/lvl`; T4 gains **`+2 min/lvl`**; T5 gains **`+3 min/lvl`**.
- **Proportional Base `max[0]` Bump across All 14 T4 & T5 Weapons (`data/items.json`):**
  - Keep all T4/T5 weapons strictly proportional to their SPD v4 archetypes (no new mechanics on Runic Blade or Crossbow):

| Weapon ID | Tier | Base Str | Old `max` | Old `+0 / +3 / +6` | New `max` | New `+0 / +1 / +2 / +3 / +6` Dmg | Archetype Notes |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| `longsword` | T4 | 16 | `[25, 5]` | `14 / 23 / 32` | **`[26, 5]`** | **`15 / 18 / 22 / 25 / 36`** | T4 baseline (forged) |
| `battle_axe` | T4 | 16 | `[20, 5]` | `12 / 21 / 30` | **`[22, 5]`** | **`13 / 16 / 20 / 23 / 34`** | Accurate (`1.24x` acc) |
| `flail` | T4 | 16 | `[35, 8]` | `19 / 33 / 47` | **`[36, 8]`** | **`20 / 25 / 30 / 35 / 50`** | `0.8x` acc, `no_surprise` |
| `runic_blade` | T4 | 16 | `[20, 6]` | `12 / 22 / 33` | **`[22, 6]`** | **`13 / 17 / 21 / 25 / 37`** | Higher per-lvl `max[1]` |
| `assassins_blade`| T4 | 16 | `[20, 5]` | `12 / 21 / 30` | **`[22, 5]`** | **`13 / 16 / 20 / 23 / 34`** | `0.5` surprise roll bonus |
| `crossbow` | T4 | 16 | `[20, 4]` | `12 / 19 / 27` | **`[22, 4]`** | **`13 / 16 / 19 / 22 / 31`** | Found T4 melee |
| `katana` | T4 | 16 | `[20, 5]` | `12 / 21 / 30` | **`[22, 5]`** | **`13 / 16 / 20 / 23 / 34`** | `+2 flat DR` (`block: [3, 0]`) |
| `greatsword` | T5 | 18 | `[30, 6]` | `17 / 27 / 38` | **`[35, 6]`** | **`20 / 24 / 29 / 33 / 47`** | T5 baseline (forged) |
| `war_hammer` | T5 | 18 | `[24, 6]` | `14 / 24 / 35` | **`[28, 6]`** | **`16 / 21 / 25 / 30 / 43`** | Accurate (`1.20x` acc) |
| `glaive` | T5 | 18 | `[40, 8]` | `22 / 35 / 49` | **`[47, 8]`** | **`26 / 31 / 37 / 42 / 59`** | `reach: 2`, `delay: 1.5` |
| `greataxe` | T5 | 20 | `[45, 6]` | `25 / 35 / 46` | **`[53, 6]`** | **`29 / 33 / 38 / 42 / 56`** | Heavy (`20 Str` req) |
| `greatshield` | T5 | 18 | `[18, 4]` | `11 / 18 / 26` | **`[21, 4]`** | **`13 / 16 / 20 / 23 / 34`** | `block: [6, 2]` (`+3..+9 DR`) |
| `gauntlet` | T5 | 18 | `[15, 3]` | `10 / 16 / 22` | **`[19, 3]`** | **`12 / 15 / 18 / 21 / 30`** | Fast (`0.5` delay) |
| `war_scythe` | T5 | 18 | `[40, 6]` | `22 / 32 / 43` | **`[47, 6]`** | **`26 / 30 / 35 / 39 / 53`** | `0.8x` acc |

- **Baseline Progression Summary (Forged Swords):**
  - **T1 Worn Shortsword:** `+0: 5`, `+3: 10`, `+6: 14`
  - **T2 Shortsword:** `+0: 7`, `+3: 12`, `+6: 16`
  - **T3 Sword:** `+0: 11`, `+3: 18`, `+6: 26`
  - **T4 Longsword:** `+0: 15`, `+3: 25`, `+6: 36`
  - **T5 Greatsword:** `+0: 20`, `+3: 33`, `+6: 47`

### 3. Uniform Blacksmith Upgrade Cap (`scripts/autoload/game_state.gd`)
- **No tier-specific cap.** All weapon tiers continue to use the standard Blacksmith `forge_cap()` (`+1..+3`, or `+6` Masterwork at Blacksmith Lv3), matching Plan 01.
- Because a Masterwork **T2 Shortsword +6 (`16 dmg`)** is strictly weaker than a **T3 Sword +3 (`18 dmg`)** and an un-upgraded **T5 Greatsword +0 (`20 dmg`)**, low-tier weapons naturally fall off without arbitrary cap rules, while preserving niche T1/Ring-of-Force Masterwork builds.

### 4. Weapon Strength Requirements & Proportional Under-Strength Penalty (`scripts/core/weapons.gd` & `scripts/autoload/game_state.gd`)
- **Keep SPD `Weapons.str_req(d, lvl)` unchanged:**
  - Base Str stays `10 / 12 / 14 / 16 / 18` (`20` for Greataxe), and upgrades continue to reduce required Str by `-1` at `+1`, `-2` at `+3`, and `-3` at `+6`.
- **Proportional Under-Strength Penalty in `GameState.hero_stats(c)` (matching Plan 01):**
  - When `str_short > 0` (`Weapons.str_req(wd, wl) > int(h.str)`):
    - Divide weapon damage (including heirloom `dmg_per_levels`) by `1 + str_short`:
      `dmg = maxi(1, int(dmg / (1 + str_short)))`
    - Zero out weapon defensive blocking (`w_block_dr = 0 if str_short > 0 else Weapons.block_dr(wd, wl)`).
    - Keep `no_surprise = wd.get("no_surprise", false) or str_short > 0`.

---

## Implementation Steps

1. **`scripts/core/weapons.gd`:**
   - Update `min_dmg(d: Dictionary, lvl: int) -> int` to `int(d.get("tier", 1)) + maxi(0, lvl) * maxi(1, int(d.get("tier", 1)) - 2)`.
   - Update header/method doc comments.
2. **`data/items.json`:**
   - Update `_note` to reflect `min = tier + lvl * max(1, tier - 2)` and the proportional under-strength weapon penalty.
   - Update `max` and `+0` `"dmg"` on all 6 T2 weapons, all 7 T4 weapons, and all 7 T5 weapons per the tables above.
3. **`scripts/autoload/game_state.gd`:**
   - In `hero_stats(c)` (around lines 195–202):
     - Replace `dmg = maxi(1, dmg - 2 * str_short)` with `if str_short > 0: dmg = maxi(1, int(dmg / (1 + str_short)))`.
     - Gate weapon `Weapons.block_dr(wd, wl)` on `str_short == 0`.
4. **`tests/run_tests.gd`:**
   - Update weapon damage expectations (`Weapons.dmg`, `Weapons.min_dmg`, `Weapons.max_dmg`) and under-strength weapon penalty tests to verify T2/T4/T5 separation and proportional Str penalties.
