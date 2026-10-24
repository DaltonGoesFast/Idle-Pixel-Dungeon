# Plan 10: Artifact Leveling Path, CombatBot AI & UI/Codex Alignment

## Status
Ready for implementation. Artifact levels come from use, not from the Desk and not from the old per-fight XP.

## Revision (player review)
`charge_artifact()` after every won fight levels an artifact in a delve or two (`8 / 16 / 24` wins). Plan 04's first draft then swung the other way and made levels a Desk purchase. Both are out.

An equipped, identified, uncracked artifact has one use meter, in hours. Every **24 hours** on that meter grants **+1** level, leftover hours kept. The meter fills from either activity:
- **Patrol:** add the hours actually worked while the artifact was equipped.
- **Delve:** on each biome boss kill during the expedition, add **8 hours**. Three boss kills are one level. One boss kill is a third. Dying or abandoning does not add hours. A boss kill does, even if the hero later dies, because that fight was used.

`+1` is inside the asked-for band: one deep run of three biomes, or three short ones, or a day of patrol (`3 × 8h`, or `24h` if the Guild cap is raised). Cap is still `enchant_cap()` (`+0 / +1 / +3`). Hours bank while the Desk cap is too low and apply when the Desk is upgraded. There is no resin price for the level.

## Problem Statement
Plans 01–04 introduce mechanical changes to Armor (`dr_per_lvl` / `barrier_per_lvl`), Weapons (`tier` min scaling, `stealth` 50% DR pierce), Surprise Attacks (no knockback, normal surprise subtracts DR), and Artifacts (upgradable and repairable at the Enchanter's Desk using `trinket_step_cost`).

Several systems outside the core formulas conflict with these changes or require synchronized updates:

1. **Artifact leveling is the wrong speed (`scripts/autoload/game_state.gd:996-1006`):**
   - `GameState.charge_artifact(c)` levels an equipped artifact for free after `8 / 16 / 24` combat wins. A single deep delve hits `+3`.
   - Plan 04's first draft moved that onto the Desk at `48` resin. Player review rejected both: levels come from use at about one per `1–3` delves or per `24h` of patrol, and the Desk only caps and repairs them. See the revision at the top of this plan.

2. **Enchanter's Desk & Blacksmith UI Guards (`scripts/autoload/game_state.gd`, `scripts/ui/camp_screen.gd`):**
   - `GameState.upgrade_max(uid)` (`scripts/autoload/game_state.gd:1076`) checks:
     ```gdscript
     if g.is_empty() or g.get("cracked", false) or not (DB.item(g.id).type in ["weapon", "armor", "ring", "wand"]): return 0
     ```
     Because `"artifact"` is missing from `upgrade_max()` and `can_upgrade_item(uid)`, the upgrade controls at the Enchanter's Desk remain locked for Artifacts unless updated.
   - `CampScreen._forge_upgrade_section()` (`scripts/ui/camp_screen.gd:1367`) has a legacy filter `and not (cracked and t == "artifact")` that still shows cracked Artifacts in the Blacksmith instead of exclusively in the Enchanter's Desk.

3. **`CombatBot` Auto-Battler Ambush & Surprise Logic (`scripts/core/combat_bot.gd`):**
   - Under Plan 03, surprise attacks no longer knock enemies back 1 tile and normal weapons subtract `m.dr` on surprise.
   - `CombatBot._ambush()` (`scripts/core/combat_bot.gd:258-303`) currently spends up to **`AMBUSH_CAP = 8` turns** and searches up to **4 steps away** to hide behind doors/grass/pillars and wait—burning 4–6 ticks of the hero's starting Barrier decay and even attempting ambushes when wielding `no_surprise` weapons.

4. **Hardcoded UI Text, Codex Formulas & Tutorial Strings:**
   - `CombatScreen._refresh()` (`scripts/ui/combat_screen.gd:178`): Status bar reads `"Surprise ready (1.5x, no DR, knockback)"`.
   - `data/tutorial.json` (line 50): Tutorial prompt reads `"Surprise attacks deal 1.5x damage, ignore armor, and knock enemies back."`
   - `Codex.item_line()` & `Codex.artifact_lines()` (`scripts/core/codex.gd:46-122`): Hardcodes armor/artifact descriptions ("levels by use", `"%d of %d won fights"`).

---

## Relevant Files & Symbols
- `scripts/autoload/game_state.gd`:
  - `charge_artifact(c)` (lines 996–1006)
  - `can_upgrade_item(uid)` & `upgrade_max(uid)` (lines 914–933, 1074–1085)
- `scripts/core/delve.gd`:
  - Call to `gs.charge_artifact(run.hero)` on combat win (line 315)
- `scripts/ui/camp_screen.gd`:
  - `_forge_upgrade_section()` (line 1367) & `_attune_section()` (line 1397)
- `scripts/core/combat_bot.gd`:
  - `AMBUSH_CAP`, `_ambush(c, es)`, and `_cover_step(c, es)` (lines 258–303)
- `scripts/ui/combat_screen.gd`:
  - `_refresh()` (line 178)
- `scripts/core/codex.gd`:
  - `item_line(id)` & `artifact_lines(g, cap)` (lines 43–122)
- `data/items.json` & `data/tutorial.json`:
  - Artifact `"desc"` / codex: hours toward the next level, not a Desk purchase and not the old fight counter. `"surprise"` tutorial tip matches Plan 03.

---

## Locked-In Design Decisions

### 1. Artifacts level by use, up to the Desk cap (`scripts/autoload/game_state.gd`, `scripts/core/delve.gd`, `scripts/ui/camp_screen.gd`)
- **Replace per-fight XP.** `charge_artifact(c)` no longer adds 1 XP per combat win. Delete the `8 * (level + 1)` fight counter.
- **Use meter.** On the artifact: `use_hours` (float). Patrol completion adds worked hours for the equipped artifact. Every boss kill adds 8 hours, including a repeat kill on a later delve. `record_boss_kill` already distinguishes the first kill (Scroll of Upgrade); the artifact meter does not care.
- **Level-up.** While `use_hours >= 24` and `lvl < enchant_cap()`: subtract 24, add 1 level, tell the player. Repeat if a long patrol banks more than one level. If `lvl` is already at the cap, keep the hours.
- **Desk role.** Include `"artifact"` in repair and in the Attune list. Do not include artifacts in the paid upgrade path (`trinket_step_cost`). `can_upgrade_item` / `upgrade_max` stay for weapons, armor, rings, and wands. Artifacts show use progress instead of a buy button.
- Remove the Blacksmith filter exception `and not (cracked and t == "artifact")` so cracked artifacts are repaired at the Desk only (`_attune_section`), not on the forge list.

### 2. Tighten `CombatBot._ambush()` to 1–2 Steps (`AMBUSH_CAP = 3`) & Skip When `no_surprise` (`scripts/core/combat_bot.gd`)
- Lower `AMBUSH_CAP` from `8` to **`3`** turns per fight.
- In `CombatBot._ambush(c, es)`:
  - Immediately return `{}` if `h.get("no_surprise", false)` is true (unless an enemy has `evade_unless_surprise`, which is already handled by `_snake_plan` / `_surprise_setup`).
  - Limit `_cover_step(c, es)` BFS depth from `4` down to **`2` steps** (and require at least one enemy within `cheb <= 3`), so the bot only steps into immediate adjacent/nearby cover rather than burning starting Barrier running across the room.

### 3. Synchronize UI, Codex, Item Descriptions & Tutorial Text (`scripts/ui/combat_screen.gd`, `scripts/core/codex.gd`, `data/items.json`, `data/tutorial.json`)
- **`CombatScreen._refresh()` (`scripts/ui/combat_screen.gd:178`):**
  - Replace `"Surprise ready (1.5x, no DR, knockback)"` with dynamic text reflecting the hero's multiplier and pierce:
    - e.g. `"Surprise ready (%.1fx dmg, can't miss%s)"` where the suffix is `", ignores DR"` if `bolt_pierce`, `", 50% DR pierce"` if stealth weapon / Assassin / Warden grass bow, or `""` otherwise.
- **`data/tutorial.json`:**
  - Update `"surprise"` tip to state that surprise attacks deal `1.5x` damage and never miss, while stealth blades and Assassins also pierce `50%` of enemy armor.
- **`Codex.item_line()`, `Codex.artifact_lines()`, and `data/items.json`:**
  - In `Codex.artifact_lines(g, cap)`: replace `"%d of %d won fights to +%d"` with hours toward the next level, e.g. `"%d / 24h use to +%d (Desk cap +%d)"`.
  - Remove `"levels by use"` only if it still implies the old per-fight counter. The new line above is the description.
  - In `Codex.item_line(id)`: include `"pierces 50% DR on surprise"` for weapons with `surprise_pct`. Assassin's 2.5× and 50% pierce stay subclass text, not a weapon line.

---

## Implementation Steps

1. **`scripts/autoload/game_state.gd` & `scripts/core/delve.gd`:**
   - Replace fight XP in `charge_artifact(c)` with the 24h use meter (patrol hours and +8h per boss kill). Level up to `enchant_cap()` only.
2. **`scripts/ui/camp_screen.gd`:**
   - Artifacts repair in `_attune_section()` and leave `_forge_upgrade_section()`. Show use hours. No buy-level button.
3. **`scripts/core/combat_bot.gd`:**
   - Set `AMBUSH_CAP := 3`, guard `_ambush()` against `h.get("no_surprise", false)`, and cap `_cover_step()` depth at `2`.
4. **`scripts/ui/combat_screen.gd`, `scripts/core/codex.gd`, `data/items.json`, `data/tutorial.json`:**
   - Update all surprise and artifact leveling text strings.
5. **`tests/run_tests.gd`:**
   - Update artifact use-meter tests (24h patrol or 3 boss kills = +1, fight wins do not level) and CombatBot surprise/ambush tests.
