# Plan 12: Balance Outliers, Edge Cases & Cross-System Audit

## Status
Approved — all design decisions locked in via `/grill-me`.

---

## Relevant Files & Symbols
- `scripts/core/combat.gd` (`Combat.setup()`, `Combat.apply_stats()`, `Combat.to_dict()`, `Combat.from_dict()`, `_trigger()`)
- `scripts/autoload/game_state.gd` (`hero_stats()`, `can_patch_up()`, `base_str()`, `upgrade_facility_cost()`)
- `scripts/core/delve.gd` (`advance()`, `defeat_changes()`, `resolve_option()`)
- `data/facilities.json` (`blacksmith` upgrade costs)
- `data/items.json` (`ring_might`, `ring_force`)
- `data/events.json` (HP costs on hazard events)
- `data/traps.json` (`worn_dart`, `poison_dart`)

---

## Locked-In Design Decisions

### 1. High-Priority Cross-Plan Bugs & Formula Fixes

#### A. `Combat.hero` Missing `sub` and `level` Properties (Plans 03 & 09)
- **Problem:**
  - Plan 03 checks `String(hero.get("sub", "")) == "assassin"` for 50% DR pierce.
  - Plan 09 checks `String(hero.get("sub", "")) == "warden"` for 50% DR pierce on grass/surprise bow shots and reads `hero.get("level", 1)` for scaled `grass_heal`.
  - In `Combat.setup()` (`combat.gd:67-76`), `Combat.apply_stats()` (`combat.gd:923-933`), and `Combat.from_dict()`, `c.hero` copies `hs.get("perk", "")` but never copies `hs.get("sub", "")` or `hs.get("level", 1)`.
- **Locked-In Decision:**
  - In `Combat.setup()` and `Combat.apply_stats()`, explicitly assign:
    ```gdscript
    hero.sub = String(hs.get("sub", ""))
    hero.level = int(hs.get("level", 1))
    ```
  - In `Combat.to_dict()` and `Combat.from_dict()`, ensure `sub` and `level` persist across mid-fight serialization.

---

#### B. `Ring of Force` + `mages_staff` Double-Dipping & Fast Weapon DPS Spike (Plan 09)
- **Problem:**
  - Plan 09 scales `Ring of Force` on `tier <= 1` weapons to +25 flat damage at +3 and 18 Str.
  - `mages_staff` is Tier 1 and heirloom; when paired with Battlemage scaling and Ring of Force, it hits for 49 dmg/swing at 1.0 delay (out-damaging Masterwork T5 Greatsword).
  - Adding flat damage directly to fast weapons like `studded_gloves` (0.5 delay) causes 62+ DPS, out-damaging all endgame weapons.
- **Locked-In Decision:**
  1. Exclude heirlooms (`mages_staff`) from `Ring of Force`:
     ```gdscript
     if int(wd.get("tier", 1)) <= 1 and not wd.get("heirloom", false) and rd.has("force_bonus"):
     ```
  2. Scale `Ring of Force` bonus damage by weapon attack speed (`delay`), normalizing DPS across fast and slow Tier-1 weapons:
     ```gdscript
     var force_dmg := fb * maxi(1, 1 + (int(h.str) - 10) / 2)
     dmg += int(round(force_dmg * float(wd.get("delay", 1.0))))
     ```

---

#### C. Blacksmith Lv 1 $\rightarrow$ Lv 2 `dark_gold` Progression Gate (Plans 04, 05, 11)
- **Problem:**
  - Plan 04 sets Blacksmith facility upgrade cost to `{"iron_ore": 35, "dark_gold": 8, "gold": 200}` multiplied by level (`Lv1 -> Lv2` costs 8 `dark_gold`).
  - Plans 05 & 11 remove `dark_gold` from Sewers and Prison patrols/events. Prison delvers need Blacksmith Lv 2 (+2 cap, T3 forging) to prepare for Tengu, but would be locked out without Dark Gold.
- **Locked-In Decision:**
  - Gate `dark_gold` only on facility upgrades from **Lv 2 $\rightarrow$ Lv 3**:
    - **Blacksmith Lv 1 $\rightarrow$ Lv 2:** `{"iron_ore": 35, "gold": 150}`
    - **Blacksmith Lv 2 $\rightarrow$ Lv 3:** `{"iron_ore": 70, "dark_gold": 16, "gold": 400}`
  - Allows Prison delvers to forge T3 and reach +2 cap using Prison iron ore, while reserving Caves+ Dark Gold for Lv 3 (T4/T5 forging & Masterwork).

---

#### D. Death Screen Hardcoded Text vs. Plan 07 Strength Floor
- **Problem:**
  - Plan 07 resets death strength to `base_str(c)` (`10 + 2 * cleared.size()`).
  - `Delve.defeat_changes()` (`scripts/core/delve.gd:454`) still hardcodes `if int(h.str) != 10: lost.append("Strength reset to 10")`.
- **Locked-In Decision:**
  - Match `GameState.end_run("death")`:
    ```gdscript
    var bstr: int = gs.base_str(run.hero)
    if int(h.str) > bstr: lost.append("Strength reset to %d" % bstr)
    ```

---

#### E. Free `patch_up()` Affordability Guard (Plan 04)
- **Problem:**
  - Plan 04 restricts free `patch_up()` to `tier <= 2` gear. `GameState.can_patch_up()` could check affordability against an un-patchable T4 weapon and report a false negative/positive.
- **Locked-In Decision:**
  - Ensure `can_patch_up()` filters its candidate pool strictly to repairable `tier <= 2` gear:
    ```gdscript
    func can_patch_up() -> String:
        var cr := cracked_gear().filter(func(g): return DB.item(g.id).type in ["weapon", "armor"] and int(DB.item(g.id).get("tier", 1)) <= 2)
        if cr.is_empty(): return "no low-tier gear to patch"
        for g in cr:
            if can_afford(repair_cost(g.uid)): return "you can afford a repair"
        return ""
    ```

---

### 2. Inherent Balance Outliers & Mechanics

#### A. Flat DR Penalty on Fast Weapons (`0.5` delay)
- **Issue:**
  - Flat DR is subtracted on every damage instance (`dmg - m.dr`). Fast weapons (`0.5 delay`) suffer enemy DR twice as often per turn compared to `1.0 delay` weapons, making Stone Gauntlet and Sai deal lower DPS against high-DR Golems and Yog.
- **Locked-In Decision:**
  - **Keep flat DR as-is as an intentional design tradeoff.**
  - Fast weapons dominate unarmored mobs (bats, shamans, larvae) and trigger double on-hit procs/enchantments.
  - Heavy slow weapons (Greatsword, Glaive) maintain their distinct tactical identity as dedicated high-DR breakers.

---

#### B. Redesign `Ring of Might`
- **Issue:**
  - Current `ring_might` grants flat +1 melee damage (+1/lvl) and no Strength, making it strictly inferior to `Ring of Force`.
- **Locked-In Decision:**
  - Redesign `Ring of Might` to grant **Strength** and **Max HP** matching vanilla SPD identity:
    - **Strength Bonus:** `+1 Str` at +0, `+2 Str` at +2/+3.
    - **Max HP Bonus:** `+5 Max HP` base (`+5/lvl` $\rightarrow$ +10 at +1, +15 at +2, +20 at +3).
  - In `GameState.hero_stats()`: `var eff_str := int(h.str) + ring_str_bonus`, allowing heroes to equip next-tier weapons and armor earlier without under-strength penalties.

---

#### C. Biome-Scaled Passive Floor Gathering & Delve Event Costs
- **Issue:**
  - Passive floor gathering (`Delve.advance()`): grants +1 gold every 4% (25g/fl) and +1 dew every 12% (8 dew/fl) identically from Floor 1 to 25.
  - Delve events charge flat -5 HP or -6 HP, which is lethal in Sewers (20 Max HP) but negligible in Demon Halls (100+ Max HP).
- **Locked-In Decision:**
  - **Scale passive gold by biome:**
    - Sewers: +1 gold every 4% (~25g/fl)
    - Prison: +2 gold every 4% (~50g/fl)
    - Caves: +3 gold every 4% (~75g/fl)
    - Dwarf City: +4 gold every 4% (~100g/fl)
    - Demon Halls: +5 gold every 4% (~125g/fl)
  - **Scale delve event HP hazard costs with Max HP:**
    - Convert flat `-5 HP` / `-6 HP` costs to `maxi(5, int(hero_max_hp * 0.15))` or `0.20` for risky choices, keeping hazard decisions impactful across all depths.

---

#### D. Trap Damage Scaling in Late Biomes
- **Issue:**
  - `worn_dart` deals a flat 3 physical damage on all floors (1–25). Late-game heroes with 8–14 DR take 0 damage, neutralizing trap hazards in City and Halls.
- **Locked-In Decision:**
  - Scale physical dart trap damage with floor depth:
    ```gdscript
    var trap_dmg := int(tr.dmg) + int(run.floor / 2)
    ```
  - Sewers (F1–5): ~3–5 dmg (dangerous to 20 HP / 2 DR heroes).
  - Caves (F11–15): ~8–10 dmg (bites through 4–6 DR).
  - Demon Halls (F21–25): ~13–15 dmg (threatening against 8–12 DR).
  - Shoving enemies into dart traps remains a valuable tactical strategy throughout all biomes.

---

## Implementation Checklist
1. [ ] **Cross-Plan Bugfixes:**
   - Update `scripts/core/combat.gd` to assign `hero.sub` and `hero.level` in `setup()`, `apply_stats()`, and serialize in `to_dict()`/`from_dict()`.
   - Update `scripts/autoload/game_state.gd` to exclude heirlooms from `Ring of Force` and scale bonus by `delay`.
   - Update `data/facilities.json` for Blacksmith Lv 1 $\rightarrow$ Lv 2 (35 iron ore, 150 gold) and Lv 2 $\rightarrow$ Lv 3 (70 iron ore, 16 dark gold, 400 gold).
   - Update `scripts/core/delve.gd:defeat_changes()` to check against `base_str`.
   - Update `scripts/autoload/game_state.gd:can_patch_up()` to filter strictly to `tier <= 2`.
2. [ ] **Ring of Might Redesign:**
   - Update `data/items.json:ring_might` with `str_bonus` and `ht_bonus`.
   - Update `scripts/autoload/game_state.gd:hero_stats()` to apply `ring_might` strength bonus to effective strength before evaluating weapon/armor requirements.
   - Update `scripts/core/codex.gd` and camp tooltips.
3. [ ] **Delve Gathering, Events & Trap Scaling:**
   - Update `scripts/core/delve.gd:advance()` to scale gold drip by biome.
   - Update `data/events.json` and `scripts/core/delve.gd:resolve_option()` for percentage-based HP hazard scaling.
   - Update `scripts/core/combat.gd:_trigger()` to scale dart damage with delve depth.
