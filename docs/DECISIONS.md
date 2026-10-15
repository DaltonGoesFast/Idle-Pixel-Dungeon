# Design decisions

Calls made while building the base game overnight (2026-10-14/15) where the GDD was open or silent. Each is easy to change; the place to change it is noted.

| # | Decision | Why | Where |
|---|---|---|---|
| 1 | **Compatibility renderer** everywhere (not Mobile/Vulkan) | v0.1.0 showed torn scanlines on the Fold 6's Adreno with the Mobile renderer; 2D pixel art gains nothing from Vulkan | project.godot |
| 2 | **Official export templates only** | The size-stripped custom template dropped WebP + text-server modules -> no textures/text (v0.1.1). Size isn't a concern since builds are hosted on GitHub | export_presets.cfg |
| 3 | **Ranges collapse to floor(avg)** | Deterministic combat; matches GDD "fixed damage" | BALANCE.md |
| 4 | **Crab nerf: dmg 4->2, DR 2->1** (still 0.5 tick) | Unbeatable without RNG misses; keeps its GDD role of stripping Barrier | data/mobs.json |
| 5 | **Goo HT 100->55**, pump-up every 3rd action hits all 8 neighbours for 3x after 1 tick | Every hit lands, so SPD HP made a 40-turn fight; the telegraph is the skill check | data/mobs.json |
| 6 | **Barrier refreshes 100% every fight** (GDD Q B) | Simple, readable; attrition already comes from HP persisting across a floor | Combat.setup |
| 7 | **Surprise = x1.5, ignores DR, 1-tile knockback** (all three of the GDD options, dagger x2) | Makes doors/grass worth kiting through; knockback enables chasm combos | Combat.hit_mob |
| 8 | **Warrior Lv1: 20 HP (SPD), Barrier 10 (6 base + 3 Broken Seal + 1 cloth), DR 1, dmg 5** | GDD example was 20/3/1/3; higher Barrier makes the Warrior the "tank" and survives sewer swarms | data/heroes.json |
| 9 | **Torch 0 = darkness (fights start with 0 Barrier); Satiety 0 = -1 HP per 5%, never lethal** (GDD Q C) | Both hurt, neither is an instant loss; torches/rations auto-used under 20% | core/delve.gd |
| 10 | **Strength potions at fixed milestones**: floor 2 @50%, floor 4 @50% (GDD Q C) | Predictable progression; matches "2 per biome" | data/biomes.json |
| 11 | **Mage unlocks on the first Goo kill by any hero** (GDD Q D example) | Gives the first boss a reward beyond the SoU | GameState.record_boss_kill |
| 12 | **Scroll of Upgrade drops on first boss kill per class** -> raises a facility's level cap by 1 (max 3) | GDD 20-scroll capstone system (only Sewers exists yet = 2 scrolls) | GameState.apply_sou |
| 13 | **Gear upgrades capped at +Blacksmith level** | GDD "SoUs unlock higher upgrade caps (+1 -> +2 -> +3)" | GameState.can_upgrade_item |
| 14 | **Unidentified rings can't be equipped**; wands must be identified before imbuing | Makes the Enchanter's Desk queue matter | GameState.can_equip |
| 15 | **ID timer 10 / 7 / 4 min by desk level**, queued sequentially, real time | GDD "identify over time" without being an all-day wait | GameState.identify_seconds |
| 16 | **Offline patrol**: real-time, capped 2/4/8 h by Guild level; yield/h from biome data x efficiency (power / (gate+2), clamped 0.25-1.25); 1 un-ID'd ring per 3 h | GDD Phase C; recall any time | GameState.patrol_* |
| 17 | **Abandon run = lose pack, keep hero & gear** (not a death) | Gives an out without the full death penalty; supplies return | GameState.end_run |
| 18 | **Unused supplies always return to the stash**, even on death | They were packed, not found; avoids feel-bad | GameState.end_run |
| 19 | **Keys:** Door B can use an Iron Key from the pack or the stash | Keys are rare; stash keys would otherwise be useless | Delve.pay |
| 20 | **Descending heals 20% HT**; chasm-killed loot (halved) is recovered on descend | GDD "collectable on the next floor's UI" | Delve.descend |
| 21 | **Mid-fight app close resumes on the Delve Bar after that event** (fight forfeited without penalty) | Saving full combat state wasn't worth it yet | DelveScreen |
| 22 | **Campfire extraction only after Goo on floor 5** (and Scroll of Passage any time) | GDD; Prison isn't built yet so the campfire ends the run | Delve.is_campfire |
| 23 | **Content RNG is seeded** (run seed + floor + salt); combat has none | Reproducible runs, testable balance | core/delve.gd |
| 24 | **UI built in code** (UIKit) rather than .tscn per screen | Responsive layouts for Fold cover/inner, easy to diff/edit in Cursor | scripts/ui |
| 25 | **Portrait threshold = aspect < 0.85** | Fold cover ~0.41 -> stacked; inner ~0.86 -> side by side | main.gd |
| 26 | **Heavy weapons (Mace) cost 1.5 ticks** | GDD tick system | data/items.json |
| 27 | **Mage bolt = imbued wand: dmg from SPD avg (MM 2-8 -> 5) + level/2, 2 charges, +1 charge per 4 ticks, ignores DR**, line of sight within 6 | GDD "ranged, telegraph-free bolt"; Firebolt burns connected grass | Combat.hero_bolt |
| 28 | **Starter Elixir** sets a hero below Lv3 to Lv3 (Alchemy Lv2) | GDD "boost a reset hero to a deeper biome's baseline" | GameState.use_elixir |
| 29 | **Death:** pack lost, equipped weapon/armor/ring cracked (unusable until repaired: 2 + tier + level ore), hero -> Lv1/10 Str | GDD section 6 | GameState.end_run |
| 30 | **Developer tab** (unlock heroes, +materials, fast-forward timers, wipe) left in the Settings page | Testing on device; remove or hide before a public release | camp_screen.gd |
