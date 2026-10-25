# Plan 03: Surprise Attack Mechanics (Stop T2 From Bypassing Endgame Armor)

## Status
Approved. Assassin stays on this formula (review note below). Do not leave Assassin on the old "ignore all armor, knock back" rule, and do not take away the subclass's 2.5× or 50% pierce.

## Revision (player review)
Assassin is brought onto the new surprise pipeline with everyone else: multiply damage, then subtract armor, no knockback, no full armor ignore. The subclass **keeps** both of its extras on any melee weapon, not only Dagger, Dirk, and Assassin's Blade:
- `2.5×` instead of `1.5×` (the existing `surprise_add: 1.0`)
- `50%` of enemy DR ignored (`eff_dr = int(m.dr) / 2`)

A Glaive or Greatsword on an Assassin will hit very hard. That is accepted. If a playtest one-shots City, tune weapon numbers later. Do not solve it by stripping the pierce or the multiplier. Stealth weapons keep the same `50%` pierce when they are not on an Assassin. Sniper's bow still ignores all DR via `bolt_pierce`.

## Problem Statement
In `scripts/core/combat.gd`, **Surprise Attacks** (triggered by stepping through doors, stepping around 2x2 room pillars, emerging from tall grass, or using Rogue's Cloak of Shadows) currently grant three massive effects simultaneously on *every* weapon:
1. **Damage Multiplier (`combat.gd:406`):** Multiplies `raw` (`hero.dmg + sur_bonus`) by **`1.5x`** (`hero.surprise_mult`), or **`2.5x`** for Assassin, plus **`+0.5x`** from `Lethal Momentum` / `Light Cloak` talents (up to **`2.0x–3.0x`** total).
2. **100% Armor Ignore (`combat.gd:406-408`):**
   ```gdscript
   if surprise: dmg = int(raw * float(hero.surprise_mult))
   elif magic: dmg = raw
   else: dmg = maxi(0, raw - int(m.dr))
   ```
   Whereas a normal hit subtracts `int(m.dr)`, a surprise attack ignores `100%` of enemy DR (`m.dr`).
3. **Universal 1-Tile Knockback (`combat.gd:440-441`):**
   ```gdscript
   elif surprise and not m.get("boss", false):
       knockback(m, m.pos - hero.pos)
   ```
   Every surprise attack (melee or Spirit Bow) pushes non-boss enemies back 1 tile—dealing bonus wall-slam damage (`1`), knocking enemies into chasms for instant kills, and creating a 1-tile gap that allows reach weapons (Spear, Glaive, Whip) or kiting heroes to get free attacks before the enemy can swing back.

### Why This Breaks Endgame Gear Progression
In Dwarf City and Demon Halls, enemies have **`4–7 DR`** (Golems `6 DR`, Succubi `5 DR`, Scorpios `6 DR`, Yog `6 DR`). That armor is specifically designed to stonewall low-tier weapons.
Because rooms have doors, 2x2 pillars, and grass—and `CombatBot` is explicitly programmed to use cover for surprise hits (`DECISIONS #165, #176, #177`)—a hero with a T2 weapon bypasses endgame enemy armor on almost every swing and chains knockbacks.

---

## Comparison: Current vs. Plan 03 vs. Vanilla SPD

| Mechanic on Surprise Attack | Current Game (`combat.gd`) | Plan 03 (Approved) | Vanilla SPD |
|---|---|---|---|
| **Accuracy / Evasion** | **100% hit** (snakes can't slip; inaccurate weapons don't miss) | **100% hit** (unchanged) | **100% hit** (defender's evasion is set to `0`) |
| **Base Damage Multiplier** | **`1.5x`** on all weapons (`2.5x` Assassin) | **`1.5x`** on all weapons (`2.5x` Assassin) | **`1.0x`** (no universal damage multiplier on surprise) |
| **Stealth Weapons (`Dagger`, `Dirk`, `Assassin's Blade`)** | Flat `sur_bonus` (from SPD's min-roll floor) **AND** multiplied by `1.5x` | Flat `sur_bonus` **AND** multiplied by `1.5x` | Rolls between `50%–75%` of max and `100%` of max (modeled by `Weapons.surprise_bonus()`) |
| **Enemy Armor (DR)** | **Ignores 100% of DR** on all weapons | **Subtracts full `m.dr`** after `1.5x` (stealth weapons & Assassin pierce **50% DR**; min `1` dmg) | **Subtracts full enemy DR** (0% armor pierce; Assassin uses *Preparation* execute thresholds) |
| **Knockback** | **1-tile knockback** on every surprise hit (melee or bow) | **None** | **None** |

### Why Plan 03 Differs from Vanilla SPD on Multiplier & Stealth DR Pierce
1. **Why `1.5x` Base Multiplier Instead of Vanilla SPD's `1.0x`:**
   - In Vanilla SPD, normal melee attacks have RNG accuracy (~15–25% miss rate) and RNG damage rolls (`min` to `max`), so a guaranteed hit is already a ~20–30% DPS boost.
   - In **Idle PD**, combat is **deterministic** (`Weapons.dmg()` always deals the average `(min + max) / 2`, and `1.0 acc` weapons never miss normal enemies). If Surprise were `1.0x` like vanilla SPD, stepping through a door or grass with a normal sword would do nothing against any non-snake enemy. Keeping `1.5x` ensures tactical positioning around doors, grass, and pillars remains rewarding.
2. **Why Stealth Weapons & Assassin Pierce 50% DR:**
   - `Dagger`, `Dirk`, and `Assassin's Blade` have lower base max damage than standard weapons of their tier. Giving them `sur_bonus` + `1.5x` + **50% DR pierce** (`eff_dr = int(m.dr) / 2`) on melee ambushes carves out a sharp armor-cracking identity against late-game high-DR enemies.

---

## Gameplay Implications

### A. Stops Low-Tier Weapons from Bypassing Late-Game Armor
Example against a **Dwarf City Golem (`6 DR`, `50 HP`)**:
- **Before Plan 03:**
  - **T2 Shortsword +1 (`10 dmg`)** normal hit: `10 - 6 = 4 dmg` (13 hits).
  - **T2 Shortsword +1 (`10 dmg`)** surprise hit: `10 * 1.5 = 15 dmg` (ignores all 6 DR $\rightarrow$ kills in 4 hits, nearly quadrupling damage).
- **With Plan 03:**
  - **T2 Shortsword +1 (`10 dmg`)** surprise hit: `10 * 1.5 - 6 = 9 dmg` (6 surprise hits; upgrading to T4/T5 is now strongly rewarded).
  - **T3 Dirk +1 (`10 dmg + 2 sur_bonus = 12 raw`)** surprise hit: `12 * 1.5 - 3 (50% DR) = 15 dmg` (gives stealth weapons a clear niche vs. armored targets despite lower base damage).
  - **T4 Longsword +1 (`16 dmg`)** surprise hit: `16 * 1.5 - 6 = 18 dmg` (kills in 3 hits).

### B. Eliminates Infinite Pillar + Reach Kiting Loops
- **Before Plan 03:** Every surprise hit pushed the enemy back 1 tile, dealing `+1` wall-slam damage, knocking enemies into chasms without Warrior's `Shove`, and letting `Spear`/`Glaive`/`Whip` (or Huntress's Spirit Bow) get 2 free attacks per enemy approach around a 2x2 pillar.
- **With Plan 03:** Surprise attacks deal burst damage in place. After striking from behind a door or grass, the enemy remains in melee range and trades blows on their tick unless displaced by **Warrior's `Shove`/`Slam`**, **`Wand of Blast Wave`**, or **`Scroll of Terror`**.

### C. Sharpens Huntress Subclass Identity (`Sniper` vs. `Warden`)
- Previously, firing the Spirit Bow from behind tall grass triggered a Surprise Attack that **ignored 100% of DR** and **knocked the enemy back 1 tile**—making `Sniper`'s signature "Spirit Bow ignores DR" perk redundant whenever shooting from cover and turning the bow into a repulsor.
- With Plan 03, a Spirit Bow surprise shot multiplies arrow damage by `1.5x`, does not knock back, and still subtracts `m.dr` unless the Huntress chose **`Sniper`** (`bolt_pierce`).

---

## Relevant Files & Symbols
- `scripts/core/combat.gd`:
  - `hit_mob(m, raw, surprise, magic, ranged, sure)` (lines 404–444)
- `scripts/core/combat_bot.gd`:
  - `_surprise_strike(c, adj)` (lines 354–371)
  - `_surprise_shot(c, es)` (lines 375–392)
  - `_hits_to_kill(c, e)` (lines 497–506)
- `scripts/core/weapons.gd`:
  - `surprise_bonus(d, lvl)` (lines 54–58)
- `scripts/autoload/game_state.gd`:
  - `hero_stats(c)` (lines 185–280)
- `tests/run_tests.gd` (Combat surprise attack unit tests)

---

## Finalized Design Decisions

### 1. Make Surprise Attacks Respect Enemy DR (`scripts/core/combat.gd`)
- Keep base `surprise_mult` at **`1.5x`** (plus `+0.5x` from `Lethal Momentum` / `Light Cloak` and `+1.0x` for `Assassin`).
- Subtract enemy DR (`m.dr`) **after** applying `hero.surprise_mult`, with a **minimum of `1` damage** (`maxi(1, dmg - eff_dr)`) on non-magic surprise hits.
- **Stealth Weapon & Assassin 50% DR Pierce:**
  - If the attack is a melee swing with a stealth weapon (`not ranged and int(hero.get("sur_bonus", 0)) > 0` — i.e., `Dagger`, `Dirk`, `Assassin's Blade`) **or** the hero's subclass is `Assassin` (`hero.get("sub", "") == "assassin"`), reduce effective enemy DR by 50%: `eff_dr = int(m.dr) / 2`.
  - Sniper's Spirit Bow (`bolt_pierce`) continues to pass `magic = true`, ignoring 100% of DR as before.
  ```gdscript
  if surprise:
      dmg = int(raw * float(hero.surprise_mult))
      if not magic:
          var eff_dr := int(m.dr)
          if (not ranged and int(hero.get("sur_bonus", 0)) > 0) or String(hero.get("sub", "")) == "assassin":
              eff_dr /= 2
          dmg = maxi(1, dmg - eff_dr)
  ```

### 2. Remove Knockback from Surprise Attacks (`scripts/core/combat.gd` & `scripts/core/combat_bot.gd`)
- Remove the `elif surprise and not m.get("boss", false): knockback(m, m.pos - hero.pos)` branch from `hit_mob()` in `scripts/core/combat.gd`.
- Displacement is now exclusively the identity of Warrior (`Shove`, `Slam`), `Wand of Blast Wave`, and `Scroll of Terror`.
- Update `CombatBot._surprise_strike()`, `CombatBot._surprise_shot()`, and `CombatBot._hits_to_kill()` in `scripts/core/combat_bot.gd` so the bot evaluates surprise damage using the new DR formula and no longer assumes a surprise swing knocks enemies into chasms.

### 3. No Per-Mob Surprise Cap Needed
- With enemy DR respected and surprise knockback removed, pillar/grass positioning remains a clean, deterministic tactical tool without allowing low-tier weapons to bypass endgame armor or chain knockbacks.
