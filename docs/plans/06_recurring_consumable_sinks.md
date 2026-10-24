# Plan 06: Recurring Consumable & Camp Sinks (FOR LATER — DO NOT IMPLEMENT)

> [!IMPORTANT]
> **DO NOT IMPLEMENT OR WORK ON THIS PLAN.**
> This plan is explicitly parked for later evaluation. Agents and developers must completely ignore this file until the user explicitly directs otherwise.

## Status
**PARKED / FOR LATER — IGNORE UNTIL EXPLICITLY REQUESTED.**
Split out from Plan 04 (`04_tier_scaled_sinks_and_costs.md`) for separate evaluation only after tier-scaled gear, trinket, repair, and facility costs are live and playtested.

---

## Context
Once a player has forged and upgraded their endgame gear, facilities, and trinkets, materials (`iron_ore`, `dark_gold`, `arcane_resin`, `seeds`, `dew`) may eventually accumulate if there are no repeatable consumables or endless sinks to spend them on.

---

## Candidate Ideas to Explore Later

### 1. Craftable Delve Consumables (Alchemy / Enchanter)
Allow converting `iron_ore`, `dark_gold`, and `arcane_resin` into delve potions and scrolls:
- **Brewing Combat Potions (Alchemy Pot):**
  - e.g., `Potion of Shielding`, `Potion of Haste`, `Potion of Invisibility` using `seeds + dew + iron_ore / dark_gold`.
- **Scribing Combat Scrolls (Enchanter's Desk):**
  - e.g., `Scroll of Recharging`, `Scroll of Lullaby`, `Scroll of Retribution` using `arcane_resin + dark_gold + gold`.
- **Loadout Integration Question:**
  - Currently only `SUPPLY_KEYS` (`ration`, `torch`, `potion_healing`, `scroll_passage`, `elixir_starter`) can be packed at the start of an expedition (`camp_screen.gd:497`), while combat potions/scrolls live in `run.pack`. Making crafted combat potions/scrolls usable from Camp would require either adding them to `SUPPLY_KEYS` (with belt/scroll caps) or loading them into `run.pack` on run start.

### 2. Temporary Next-Run Camp Buffs (Blacksmith / Enchanter)
- **Whetstone / Armor Polish:** Spend `15 iron_ore + 3 dark_gold` at the Blacksmith to grant `+2 dmg` or `+2 Barrier` for the next delve.
- **Arcane Attunement:** Spend `arcane_resin + dark_gold` at the Enchanter's Desk to grant `+1 staff/cloak charge` or bonus starting Barrier on the next delve.

### 3. Bulk Material Conversions
- Trade excess `iron_ore`, `dark_gold`, or `arcane_resin` at existing facilities for always-packable supplies (`ration`, `torch`, `potion_healing`, `scroll_passage`).
