# Plan 10: Artifact Leveling Path, CombatBot AI & UI/Codex Alignment

## Status
Ready for implementation — all design decisions locked in via `/grill-me`.

## Problem Statement
Plans 01–04 introduce mechanical changes to Armor (`dr_per_lvl` / `barrier_per_lvl`), Weapons (`tier` min scaling, `stealth` 50% DR pierce), Surprise Attacks (no knockback, normal surprise subtracts DR), and Artifacts (upgradable and repairable at the Enchanter's Desk using `trinket_step_cost`).

Several systems outside the core formulas conflict with these changes or require synchronized updates:

1. **Artifact Dual-Leveling Conflict (`scripts/autoload/game_state.gd:996-1006` vs. Plan 04):**
   - Plan 04 adds `"artifact"` to the Enchanter's Desk upgrade/repair pool using `trinket_step_cost` (`48 arcane_resin, 24 dark_gold, 1,400 gold` for `+0 -> +3`).
   - However, `GameState.charge_artifact(c)` (`scripts/autoload/game_state.gd:998-1006`, called after every combat win in `scripts/core/delve.gd:315`) currently levels up equipped Artifacts **for free** after `8 / 16 / 24` combat wins. If `charge_artifact()` remains active, Artifacts never function as an Enchanter's Desk material sink.

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
  - Artifact `"desc"` strings (`"levels by use"` -> Enchanter's Desk) and `"surprise"` tutorial tip.

---

## Locked-In Design Decisions

### 1. Enchanter's Desk Upgrades Only for Artifacts (`scripts/autoload/game_state.gd`, `scripts/core/delve.gd`, `scripts/ui/camp_screen.gd`)
- **Remove Free Combat XP Leveling:**
  - Make `GameState.charge_artifact(c)` a no-op (or remove the automatic XP level-up) so Artifacts upgrade exclusively at the Enchanter's Desk (`+1` to `+3`) using `trinket_step_cost(next_lvl)` (`arcane_resin + dark_gold + gold`) just like Rings and Wands.
- **Unify Trinket Upgrade Guards & UI:**
  - Include `"artifact"` in `GameState.can_upgrade_item(uid)` and `GameState.upgrade_max(uid)` (`["weapon", "armor", "ring", "wand", "artifact"]`).
  - Remove `and not (cracked and t == "artifact")` from `CampScreen._forge_upgrade_section()` (`camp_screen.gd:1367`) and include `"artifact"` in `CampScreen._attune_section()` (`camp_screen.gd:1397`) so Artifacts are upgraded and repaired in one place at the Enchanter's Desk.

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
  - Remove `"levels by use"` from artifact descriptions in `data/items.json`.
  - In `Codex.artifact_lines(g, cap)`: replace the `"%d of %d won fights to +%d"` line with `"Level +%d / Enchanter cap +%d"` (matching Rings and Wands).
  - In `Codex.item_line(id)`: include `"pierces 50% DR on surprise"` for weapons with `surprise_pct`.

---

## Implementation Steps

1. **`scripts/autoload/game_state.gd` & `scripts/core/delve.gd`:**
   - Disable combat XP leveling in `charge_artifact(c)` and add `"artifact"` to `can_upgrade_item(uid)` and `upgrade_max(uid)`.
2. **`scripts/ui/camp_screen.gd`:**
   - Update `_forge_upgrade_section()` and `_attune_section()` so Artifacts upgrade and repair at the Enchanter's Desk.
3. **`scripts/core/combat_bot.gd`:**
   - Set `AMBUSH_CAP := 3`, guard `_ambush()` against `h.get("no_surprise", false)`, and cap `_cover_step()` depth at `2`.
4. **`scripts/ui/combat_screen.gd`, `scripts/core/codex.gd`, `data/items.json`, `data/tutorial.json`:**
   - Update all surprise and artifact leveling text strings.
5. **`tests/run_tests.gd`:**
   - Update artifact leveling tests and CombatBot surprise/ambush tests.
