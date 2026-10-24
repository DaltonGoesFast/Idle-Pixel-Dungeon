# Plan 09: Class Heirlooms, Subclasses, Talents & Trinkets vs. Endgame Scaling

## Status
Ready for implementation — all design decisions locked in via `/grill-me`.

## Problem Statement
Plans 01–04 steepen the numbers curve in Dwarf City (`4–6 DR`, `9–18 Dmg`, `40–50 HP`) and Demon Halls (`5–7 DR`, `12–20 Dmg`, `52–75 HP`), while raising T4/T5 weapon damage (`25–33+`) and Enchanter's Desk upgrade costs (`48 arcane_resin, 24 dark_gold, 1,400 gold` for `+0 -> +3`).

Several class heirlooms, subclasses, and trinkets still use flat early-game numbers from the old curve:

1. **Mage's `mages_staff` & `Battlemage` Identity (`data/items.json:79-95`, `scripts/autoload/game_state.gd:196`, `scripts/core/combat.gd:790-793`):**
   - `mages_staff` is a Tier 1 weapon (`max: [6, 2]`, `dmg_per_levels: 6`). Even at `+3` and Hero `Lv 18`, its melee damage is only `9 + 3 = 12`, which deals `5–7` damage against City/Halls `5–7 DR`.
   - Meanwhile, `Battlemage`'s `battle_recharge` triggers only on every **5th** melee hit and provides no melee damage synergy for keeping `mages_staff` equipped.

2. **Huntress `Spirit Bow` & `Warden` vs. `Sniper` (`scripts/autoload/game_state.gd:250-254`, `data/heroes.json:135-148`, `scripts/core/combat.gd:817, 982`):**
   - The Huntress's innate `Spirit Bow` deals `(1 + lv/5 + 6 + int(lv/2.5)) / 2` (`9` damage at `Lv 20`).
   - Under **Plan 03**, normal Surprise attacks subtract full `m.dr` and no longer knock back.
   - `Sniper` (`bolt_pierce: true`) bypasses `100%` of enemy DR on all bow shots, whereas `Warden` subtracts full `m.dr` (`5–7 DR` in City/Halls), reducing a Lv 20 Warden's bow shot to `2–4` damage, while `Warden`'s `grass_heal` heals only a flat `1 HP`.

3. **`Ring of Force` (`data/items.json:1107-1124`, `scripts/autoload/game_state.gd:207`):**
   - `Ring of Force` grants `force_bonus`: `2 + 1/lvl` (`+5 dmg` at `+3`) when wielding a Tier 1 weapon (`tier <= 1`).
   - With `Ring of Force +3` (`+5`) and a T1 weapon `+3` (`10`), total damage is `15`—barely matching an un-upgraded T4 Longsword `+0` (`15 dmg`) and far behind `Longsword +3` (`25 dmg`) or `Greatsword +3` (`33 dmg`), despite costing a ring slot and `48 arcane_resin + 24 dark_gold + 1,400g`.

4. **Flat-Number Subclasses & `Cape of Thorns` (`data/heroes.json`, `data/items.json`, `scripts/core/combat.gd`):**
   - **Gladiator `Combo` (`data/heroes.json:27-31`, `scripts/core/combat.gd:783`):** Grants `+1 dmg` per consecutive hit (capped at `+3 dmg`). When a T4/T5 weapon hits for `25–33` damage, `+1..+3` is negligible compared to Berserker's `+20%`.
   - **Freerunner (`data/heroes.json:103-108`):** Grants `delay_mult: 0.8` and `dr_add: 1` (`+1 DR` is tiny in City/Halls).
   - **`Cape of Thorns` (`data/items.json:1177-1192`):** Reflects `1 + 0.5/lvl` (`2 dmg` at `+3`) when hit in melee, which is invisible against `50–75 HP` endgame enemies.

---

## Relevant Files & Symbols
- `scripts/autoload/game_state.gd`:
  - `hero_stats(c)` (lines 195–278) — `mages_staff` melee scaling, `Ring of Force` scaling, `Spirit Bow` scaling.
- `scripts/core/combat.gd`:
  - `hit_mob()` (lines 404–410) — 50% DR pierce check for Warden bow shots on surprise / from grass.
  - `_melee_dmg(sur)` & `_melee_perks()` (lines 778–794) — Gladiator `combo`, Battlemage `battle_recharge` & arcane bonus.
  - `_end_hero_turn(cost)` (line 982) — Warden `grass_heal`.
- `data/heroes.json` — Subclass definitions (`gladiator`, `battlemage`, `freerunner`, `warden`).
- `data/items.json` — `mages_staff` (lines 79–95), `ring_force` (lines 1107–1124), `cape_thorns` (lines 1177–1192).
- `tests/run_tests.gd`

---

## Locked-In Design Decisions

### 1. Scale `mages_staff` with `wand_lvl` + Hero Level & Buff `Battlemage` (`data/items.json`, `scripts/autoload/game_state.gd`, `scripts/core/combat.gd`, `data/heroes.json`)
- **`mages_staff` Melee Scaling:**
  - In `data/items.json`, buff `mages_staff.dmg_per_levels` from `6` to **`3`** (`+1 melee damage every 3 hero levels`).
  - In `GameState.hero_stats(c)`, when `wd.id == "mages_staff"` (or `wd.get("heirloom", false)` for Mage), also add **`+2 * wnl`** (`+2` melee damage per uncracked imbued wand level `wand_lvl`).
  - At `Lv 18`, a `mages_staff +3` (`9` base) + `Lv 18 / 3` (`+6`) + `+3` imbued wand (`+6`) reaches **`21` melee damage**—staying competitive into late biomes while rewarding investing in both the Blacksmith and Enchanter's Desk.
- **`Battlemage` Subclass Buff:**
  - When wielding `mages_staff`, `Battlemage` deals **`+wand_lvl` bonus arcane damage** (or `+1 + wand_lvl` melee damage) AND `battle_recharge` restores `+1` staff charge every **3rd** melee hit (down from every 5th hit).
  - Update `data/heroes.json` (`mage.subclasses.battlemage.desc`):
    `"Melee hits with the staff deal +wand level bonus damage, and every 3rd melee hit restores 1 staff charge."`

### 2. Buff `Spirit Bow` Level Scaling & `Warden` Subclass (`scripts/autoload/game_state.gd`, `scripts/core/combat.gd`, `data/heroes.json`)
- **`Spirit Bow` Base Damage Formula (`game_state.gd:252-254`):**
  - Update `s.bolt.dmg` for `"shoot"` from `(1 + lv / 5 + 6 + int(lv / 2.5)) / 2` to:
    ```gdscript
    s.bolt = {"dmg": 3 + lv / 2, "charges": 0, "infinite": true, "recharge": 0,
        "name": "the Spirit Bow", "magic": false}
    ```
  - Gives `3` dmg at `Lv 1`, `8` dmg at `Lv 10`, and `13` dmg at `Lv 20` (vs `9` previously).
- **`Warden` Subclass Buffs (`data/heroes.json`, `scripts/core/combat.gd`):**
  - Increase `Warden` passive defenses in `data/heroes.json` from `barrier_add: 2, dr_add: 1` to **`barrier_add: 4, dr_add: 2`**.
  - **50% DR Pierce on Surprise / Grass Bow Shots:** When `hero.get("sub", "") == "warden"`, Spirit Bow shots fired as a Surprise attack **or** while the Warden is standing on tall/trampled grass (`tile(hero.pos) == T.GRASS or trampled.has(hero.pos)`) pierce **50% of enemy DR** (`eff_dr = int(m.dr) / 2`), matching Stealth weapons in Plan 03 while keeping `Sniper`'s `100%` DR ignore (`bolt_pierce`) on all shots distinct.
  - **Scaled `grass_heal` (`combat.gd:982`):** Ending a turn on tall or trampled grass heals **`1 + int(hero.get("level", 1)) / 8` HP** (`1 HP` at Lv 1–7, `2 HP` at Lv 8–15, `3 HP` at Lv 16+).

### 3. Scale `Ring of Force` with Hero Strength (`scripts/autoload/game_state.gd`, `data/items.json`, `scripts/core/codex.gd`)
- When wielding a Tier 1 weapon (`int(wd.get("tier", 1)) <= 1`), `Ring of Force` scales its `(2 + lvl)` base bonus by `maxi(1, 1 + (int(h.str) - 10) / 2)`:
  ```gdscript
  if int(wd.get("tier", 1)) <= 1 and rd.has("force_bonus"):
      var fb := int(rd.get("force_bonus", 0)) + trinket_bonus(r, "force_bonus")
      dmg += fb * maxi(1, 1 + (int(h.str) - 10) / 2)
  ```
  - At `10 Str` (Sewers), `+0` gives `+2 dmg` (unchanged).
  - At `14 Str` (Caves), `+1` (`fb = 3`) gives `3 * 3 = +9 dmg`.
  - At `16 Str` (City), `+2` (`fb = 4`) gives `4 * 4 = +16 dmg`.
  - At `18 Str` (Halls), `+3` (`fb = 5`) gives `5 * 5 = +25 dmg` (bringing a T1 weapon + `Ring of Force +3` to `35 dmg`, competitive with a T5 Greatsword `+3` at `33 dmg`).
- Update `ring_force.desc` in `data/items.json` and `Codex.item_line()` to note that the Tier-1 damage bonus multiplies with Strength above 10.

### 4. Scale Gladiator `Combo`, `Freerunner`, and `Cape of Thorns` (`scripts/core/combat.gd`, `data/heroes.json`, `data/items.json`)
- **Gladiator `Combo` (`combat.gd:783`, `data/heroes.json:27-31`):**
  - Each stack (up to 3 stacks) adds **`+10%` melee damage (minimum `+1` per stack)**:
    ```gdscript
    "combo":
        var stacks := mini(int(hero.combo), 3)
        d += maxi(stacks, int(d * 0.10 * stacks))
    ```
  - Early game (`10 dmg` weapon): `+1 / +2 / +3` damage (unchanged). Late game (`30 dmg` weapon): `+3 / +6 / +9` damage (`+30%` at 3 stacks).
- **Freerunner (`data/heroes.json:103-108`):**
  - Increase `dr_add` from `1` to **`2`** (alongside its `delay_mult: 0.8` 20% faster attacks).
- **`Cape of Thorns` (`data/items.json:1177-1192`):**
  - Increase base `"thorns"` from `1` to **`2`** and `"per_level": {"thorns": 1}` (was `0.5`), reflecting `2 / 3 / 4 / 5` true damage at `+0 / +1 / +2 / +3`.

---

## Implementation Steps

1. **`data/items.json` & `data/heroes.json`:**
   - Update `mages_staff` (`dmg_per_levels: 3`), `ring_force` (`desc`), and `cape_thorns` (`thorns: 2`, `per_level.thorns: 1`).
   - Update `gladiator`, `battlemage`, `freerunner`, and `warden` stats and descriptions in `data/heroes.json`.
2. **`scripts/autoload/game_state.gd`:**
   - In `hero_stats(c)`:
     - Add `+2 * wnl` to `dmg` when `c == "mage"` and `wd.get("id", "") == "mages_staff"` (or `def.start_weapon == "mages_staff"` when wearing `mages_staff`), plus `+wnl` when `h.get("subclass", "") == "battlemage"`.
     - Multiply `Ring of Force` `fb` by `maxi(1, 1 + (int(h.str) - 10) / 2)`.
     - Update `Spirit Bow` `s.bolt.dmg` to `3 + lv / 2` and store `s.level = lv` on `s` so `Combat` can read `hero.level` for `Warden`'s `grass_heal`.
3. **`scripts/core/combat.gd`:**
   - In `_melee_dmg(sur)`: update `"combo"` to `var stacks := mini(int(hero.combo), 3); d += maxi(stacks, int(d * 0.10 * stacks))`.
   - In `_melee_perks()`: change `battle_recharge` from `hero.combo % 5 == 0` to `hero.combo % 3 == 0`.
   - In `hit_mob()` / `hero_bolt()`: apply `eff_dr = int(m.dr) / 2` on Spirit Bow shots when `String(hero.get("sub", "")) == "warden"` and (`surprise` or `tile(hero.pos) == T.GRASS` or `trampled.has(hero.pos)`).
   - In `_end_hero_turn(cost)`: update `grass_heal` to heal `mini(int(hero.ht) - int(hero.hp), 1 + int(hero.get("level", 1)) / 8)`.
4. **`tests/run_tests.gd`:**
   - Add unit tests for `mages_staff` + `wand_lvl` scaling, `Battlemage` 3-hit recharge, `Spirit Bow` & `Warden` grass/surprise 50% pierce, `Ring of Force` Strength scaling, Gladiator `%` combo, and `Cape of Thorns` `2 + 1/lvl`.
