# Plan 04: Tier-Scaled Forging, Upgrade & Repair Costs (Fixing Material Sinks)

## Status
Ready for implementation — design decisions finalized via review.

## Problem Statement
Players accumulate massive stockpiles of `iron_ore`, `dark_gold`, `arcane_resin`, `seeds`, and `dew` very early because all camp sinks are tiny, flat, one-time costs gated behind Scrolls of Upgrade (`SoU`):

1. **Facility Upgrades Cost Almost Nothing in Materials (`data/facilities.json`, `GameState.facility_upgrade_cost`):**
   - Upgrading all 4 camp facilities from Lv1 $\rightarrow$ Lv3 costs a grand total of:
     - **Blacksmith Lv1 $\rightarrow$ Lv3:** `30 iron_ore`, `150 gold`
     - **Alchemy Pot Lv1 $\rightarrow$ Lv3:** `24 seeds`, `120 gold`
     - **Enchanter's Desk Lv1 $\rightarrow$ Lv3:** `9 arcane_resin`, `120 gold`
     - **Guild Hall Lv1 $\rightarrow$ Lv3:** `300 gold`
   - Because facility caps require **22 Scrolls of Upgrade** (`cap_scrolls` across the 4 facilities, earned from first-time boss kills per hero class + milestones), players sit on hundreds of materials while working through boss progression.

2. **Item Upgrade Costs Ignore Item Tier and Never Use `dark_gold` or `arcane_resin` (`GameState.upgrade_step_cost`, `scripts/autoload/game_state.gd:900-913`):**
   - Formula: `iron_ore = 4 * next_lvl`, `gold = per * next_lvl^2` (`per = 10` for `+1..+3`, `per = 200` for Masterwork `+4..+6`).
   - Upgrading a **T1 Cloth Armor** to `+3` costs the exact same (`24 iron_ore, 140 gold`) as upgrading a **T5 Greatsword** to `+3`!
   - Even Masterwork `+4..+6` only costs `60 iron_ore` total (`15,400 gold` is the only bottleneck).

3. **Trinkets (Rings, Wands, Artifacts) & Repairs Are Too Cheap (`scripts/autoload/game_state.gd:935-995`):**
   - Forged gear is permanent (never lost on death; repairs only cost `2 + tier + lvl` iron ore, and `patch_up()` repairs any weapon/armor for free if broke).
   - Trinket (Ring/Wand) upgrades cap at `+2` (`enchanter_level - 1`), costing only `12 arcane_resin` total per trinket and zero `dark_gold`, while Artifacts cannot be upgraded at the Enchanter's Desk at all.

---

## Relevant Files & Symbols
- `data/facilities.json` (Facility `upgrade_cost`)
- `data/recipes.json` (Blacksmith forging recipes)
- `scripts/autoload/game_state.gd`:
  - `upgrade_step_cost(next_lvl, tier)` / `item_upgrade_cost(uid)` / `upgrade_cost_n(uid, n)` (lines 900–913, 1057–1060)
  - `repair_cost(uid)` (lines 935–939)
  - `can_patch_up()` / `patch_up()` (lines 1079–1095)
  - `enchant_cap()` / `trinket_step_cost(next_lvl)` / `trinket_repair_cost(t, lvl)` / `can_upgrade_item(uid)` (lines 914–975)
- `scripts/ui/camp_screen.gd`:
  - `FAC_MATS` (line 404 — add `dark_gold` to `enchanter`, `dew` to `alchemy`)
  - `_preview()` (line 937 — Enchanter Lv3 cap preview)
  - `_forge_upgrade_section()` / `_attune_section()` (lines 1367, 1397 — allow Artifacts to upgrade & repair in Enchanter Attune section)
- `tests/run_tests.gd` (Economy cost unit tests)

---

## Finalized Design & Solution

### 1. Tier-Scaled Weapon & Armor Upgrades (`scripts/autoload/game_state.gd`)
Material requirements follow item tier / base strength requirement:
- **T1–T3 (STR 10–14):** Cost **`iron_ore` + `gold`** (no `dark_gold` required for T3).
- **T4 (STR 16):** Cost **`iron_ore` + `dark_gold` + `gold`**.
- **T5 (STR 18–20):** Cost **`iron_ore` + `dark_gold` + `arcane_resin` + `gold`**.
- **Masterwork (`+4..+6` at Blacksmith Lv3):** Scales by `tier` and adds `dark_gold` (for T3+) and `arcane_resin` (for T4+).

Update `GameState.upgrade_step_cost(next_lvl: int, tier := 1) -> Dictionary`:
- `iron_ore = 4 * tier * next_lvl` (or `10 * tier * next_lvl` for Masterwork `next_lvl > 3`)
- `gold = (200 if next_lvl > 3 else 15 * tier) * next_lvl * next_lvl`
- `dark_gold`:
  - For `+1..+3`: `0` for T1–T3; `4 * next_lvl` for T4; `6 * next_lvl` for T5.
  - For Masterwork `+4..+6`: `3 * next_lvl` for T3; `5 * next_lvl` for T4; `8 * next_lvl` for T5.
- `arcane_resin`:
  - For `+1..+3`: `0` for T1–T4; `3 * next_lvl` for T5.
  - For Masterwork `+4..+6`: `2 * next_lvl` for T3; `3 * next_lvl` for T4; `5 * next_lvl` for T5.

| Upgrade Step | T1 (`STR 10`) | T2 (`STR 12`) | T3 (`STR 14`) | T4 (`STR 16`) | T5 (`STR 18–20`) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **+0 $\rightarrow$ +1** | `4` Ore, `15`g | `8` Ore, `30`g | `12` Ore, `45`g | `16` Ore, **`4` D.Gold**, `60`g | `20` Ore, **`6` D.Gold**, **`3` Resin**, `75`g |
| **+1 $\rightarrow$ +2** | `8` Ore, `60`g | `16` Ore, `120`g | `24` Ore, `180`g | `32` Ore, **`8` D.Gold**, `240`g | `40` Ore, **`12` D.Gold**, **`6` Resin**, `300`g |
| **+2 $\rightarrow$ +3** | `12` Ore, `135`g | `24` Ore, `270`g | `36` Ore, `405`g | `48` Ore, **`12` D.Gold**, `540`g | `60` Ore, **`18` D.Gold**, **`9` Resin**, `675`g |
| **Total (+0 $\rightarrow$ +3)** | **`24` Ore, `210`g** | **`48` Ore, `420`g** | **`72` Ore, `630`g** | **`96` Ore, `24` D.Gold, `840`g** | **`120` Ore, `36` D.Gold, `18` Resin, `1,050`g** |

### 2. Blacksmith Forging Recipes (`data/recipes.json`)
Keep the existing 9 Blacksmith recipes (1 standard sword + 1 armor per tier; other weapon archetypes remain delve-drop only), aligned with the same material tier rules:
- **T1 (`worn_shortsword`):** `4 iron_ore, 25 gold`
- **T2 (`shortsword`, `leather_armor`):** `10–12 iron_ore, 60 gold`
- **T3 (`sword`, `mail_armor` — STR 14):** `24–28 iron_ore, 150 gold` (uses `iron_ore + gold` only; no `dark_gold`)
- **T4 (`longsword`, `scale_armor` — STR 16):** `45 iron_ore, 15 dark_gold, 350 gold`
- **T5 (`greatsword`, `plate_armor` — STR 18):** `70 iron_ore, 30 dark_gold, 15 arcane_resin, 700 gold`

### 3. Tier-Scaled Death Repairs & "Patch Up" Restriction (`scripts/autoload/game_state.gd`)
- **Weapon/Armor Repair Costs (`repair_cost(uid)`):**
  - **T1–T3:** `iron_ore = (2 + lvl) * tier`
  - **T4:** `iron_ore = (2 + lvl) * tier`, `dark_gold = 2 + int(lvl / 2)`
  - **T5:** `iron_ore = (2 + lvl) * tier`, `dark_gold = 4 + lvl`, `arcane_resin = 2 + int(lvl / 2)`
- **Free "Patch Up" Restriction (`can_patch_up()`, `patch_up()`):**
  - Only **T1 and T2** weapons/armor (`int(DB.item(g.id).get("tier", 1)) <= 2`) qualify for the Blacksmith's free `patch_up()`.
  - T3+ items (`tier >= 3`) never get repaired for free—dying while broke with cracked endgame gear sends you back to Sewers/Prison tier gear (or starter gear) until you farm the materials to repair your T3–T5 pieces.

### 4. Expensive Trinket (Ring, Wand & Artifact) Upgrades & Repairs (`scripts/autoload/game_state.gd`, `scripts/ui/camp_screen.gd`)
- **Enchanter Cap (`enchant_cap()`):**
  - Raise Enchanter's Desk Lv3 cap from `+2` to **`+3`**:
    - `Lv1`: `+0`
    - `Lv2`: `+1`
    - `Lv3`: `+3` (`[0, 1, 3][clampi(facility_level("enchanter") - 1, 0, 2)]`)
- **Artifacts Level at Enchanter's Desk:**
  - Allow **Artifacts** (alongside Rings and Wands) to be upgraded directly in the Enchanter's Desk **Attune** tab using `trinket_step_cost(next_lvl)`. (Combat XP via `charge_artifact` can still supplement or remain capped by `enchant_cap()`).
- **Trinket Upgrade Cost (`trinket_step_cost(next_lvl)`):**
  - Upgrading Rings, Wands, and Artifacts is always expensive and **always costs `arcane_resin`, `dark_gold`, and `gold`**:
    - `arcane_resin = 8 * next_lvl` (`8 / 16 / 24`, total `48` resin for `+3`)
    - `dark_gold = 4 * next_lvl` (`4 / 8 / 12`, total `24` dark gold for `+3`)
    - `gold = 100 * next_lvl * next_lvl` (`100 / 400 / 900`, total `1,400` gold for `+3`)
- **Trinket Repair Cost (`trinket_repair_cost(t, lvl)`):**
  - Always requires `arcane_resin` + `dark_gold` (+ `gold` for artifacts):
    - Rings/Wands: `{"arcane_resin": 3 + 2 * lvl, "dark_gold": 1 + lvl}`
    - Artifacts: `{"arcane_resin": 5 + 2 * lvl, "dark_gold": 2 + lvl, "gold": 50 + 25 * lvl}`

### 5. Facility Upgrade Material Costs (`data/facilities.json`)
Keep `upgrade_cost` as a single base dictionary multiplied by current facility level `L` (`Lv1->2` = `1x`, `Lv2->3` = `2x`), with substantially higher material requirements:
- **Blacksmith (`upgrade_cost`):** `{"iron_ore": 35, "dark_gold": 8, "gold": 200}` (Total Lv1$\rightarrow$Lv3: `105 iron_ore, 24 dark_gold, 600 gold`)
- **Alchemy Pot (`upgrade_cost`):** `{"seeds": 25, "dew": 35, "gold": 150}` (Total Lv1$\rightarrow$Lv3: `75 seeds, 105 dew, 450 gold`)
- **Enchanter's Desk (`upgrade_cost`):** `{"arcane_resin": 15, "gold": 150}` (Total Lv1$\rightarrow$Lv3: `45 arcane_resin, 450 gold`)
- **Guild Hall (`upgrade_cost`):** `{"gold": 250, "iron_ore": 20}` (Total Lv1$\rightarrow$Lv3: `750 gold, 60 iron_ore`)
