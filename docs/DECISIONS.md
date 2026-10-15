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
| 31 | **Rogue unlocks when any hero reaches Sewers floor 4; Huntress after brewing 5 potions** (GDD Q D examples used floors 8/10 which don't exist yet) | Gives early goals for both the delve and the Camp economy | GameState.check_unlocks |
| 32 | **Rogue Cloak** = 2 charges per fight, hidden 2 ticks, next hit Surprise; **Huntress** = unlimited bow, DR applies | GDD class identities in a deterministic system; no RNG stealth | Combat.hero_cloak / hero_bolt |
| 33 | **Non-Warrior base Barrier 4** (Warrior 6 + Seal 3) | Squishier classes needed some buffer against crabs' chip | data/heroes.json |
| 34 | **Torch drain 0.4/%**: default loadout (2 torches) lasts exactly the 5 floors | The sim showed every run hitting darkness at Goo with 0.5 | core/delve.gd |
| 35 | **Heirlooms (Mage's Staff...) never crack on death** | They're permanent class items in the GDD | GameState.end_run |
| 36 | **Potions are consumed the moment they're drunk** (not refunded on death) | Fixes a refund exploit | combat_screen.gd |

## 37. Mid-fight resume replaces "fight restarts on relaunch"
Supersedes part of #21. The Combat state is serialized to `run.active_fight` after every hero action and every 3 s; on launch main.gd resumes it. This is cheap (small grid) and kills the app-kill exploit.

## 38. Warrior Slam
Adjacent AoE + knockback, cooldown-based. Gives Warrior a crowd answer without stealing Mage's ranged niche.

## 39. Lightning conducts through water, including to the hero
Matches SPD's spirit (lightning + water risk). The hero takes half damage so it's a positioning puzzle, not a trap.

## 40. The "Goo spike" was mostly the bot cornering itself
All v0.4 sim deaths were at Goo with potions unused. Tracing a fight showed the bot dodging a slam into a corner, getting slammed again with no exit, and drinking only at <= 7 HP (a pump hits for 12+). Fixes: the dodge score now values escape tiles, and heal threshold = max(7, 2x nearby incoming damage). Then Goo was retuned so it is not trivial: HT 70, pump every 4 actions (every 3 below half HP), enraged dmg 6. The early fight is gentler (time to learn the telegraph), the second half is the real test.

## 41. Rogue buff = keen eyes, not more cloak
With the fixed bot, Rogue clears the Sewers 9/10 with 2 cloak charges (3 charges was 10/10 - too much). The buff is utility that fits the class and the new trap system: the Rogue reveals adjacent hidden traps as she moves, searches radius 2, always finds hidden doors on a floor search, and has a Rogue-only disarm option in Trapped Corridors.

## 42. Traps are deterministic and one-shot
Room templates mark `^` (visible) and `?` (hidden); the trap type comes from the biome's pool indexed by tile position, so the same room in the same biome always has the same traps (seeded, reproducible, testable). Traps fire once. Mobs know all traps (SPD behaviour) and path around them, which makes traps a hero tool: push enemies onto them.

## 43. Searching costs time, hidden doors cost torch
In combat, Search takes 2 ticks (a real trade-off with enemies approaching). Between floors, the hidden-door search costs 10 torch - the delve's scarce resource - for a 50% chance at a secret cache (Rogue 100%). Both are optional, so ignoring them is never a trap for new players.

## 44. Prison is a continuation, not a separate expedition
At the Goo campfire you choose: extract (bank everything) or press on into the Prison with an unbanked pack. This matches the GDD's push-your-luck extraction loop. A Scroll of Passage still extracts from anywhere. The next campfire (after Tengu) only extracts because Caves aren't built yet.

## 45. Prison numbers
SPD Prison mobs scaled the same way as the Sewers (HT x~0.8, damage collapsed to the average and trimmed where 100% accuracy made them brutal). SPD instant effects became telegraphs: Skeleton's death explosion is a 1-tick 3x3 red area, DM-100's zap a 1-tick red tile, Tengu's shuriken and bombs red tiles. Target hero (GDD): 12-13 Str with tier-2/3 gear. The sim confirms a Lv5 Warrior with Shortsword+1 / Leather+1 wins 99/99 Prison fights and beats Tengu with 2 potions; a Lv1 hero with forged tier-2 gear clears Sewers+Prison in one run 3-10/10 depending on class (Mage is the weakest - Tengu's blinks waste its limited charges).

## 46. Release grouping
v0.5.0 ships items 1-3 of the overnight list together (balance, traps/hidden doors, Prison + Tengu) because Prison rooms are where traps matter and the balance changes were tuned against both. Settings/music/meta-progression = v0.6.0 (the Codex shipped here too: it shares the discovery data with the milestones), onboarding = v0.7.0.

## 47. Milestones are account-wide, one-time, and pay into the stash
The GDD's meta loop is Camp growth, so milestone rewards are materials (and the odd Scroll of Upgrade), not stat bonuses: they speed up facilities without adding a second power curve. Milestones are data (`data/milestones.json`, `stat` + `goal` + `reward`); `GameState.check_milestones()` runs on every `touch()`, so any code path that changes a stat grants them automatically.

## 48. Class unlocks stay early
The GDD example is "Rogue: reach Prison floor 8, Huntress: brew 10 potions". Now that the Prison exists that would be possible, but it would hide half the roster for many hours. Kept Rogue = floor 4, Huntress = 5 potions, Mage = beat Goo, moved into `heroes.json` `unlock_rule` so it is one edit to change.

## 49. Text size scales the theme, not the viewport
`text_scale` multiplies the base font size computed from the screen (clamped 14-60 px). Layout is rebuilt via `settings_changed`, so every screen reflows - important on the Fold cover screen where Huge text must still fit.

## 50. Developer tools hidden by default
The cheats (unlock all, +materials, time skip, wipe) are behind a Settings toggle so a player can't hit them by accident; still available on device for testing.

## 51. Codex discovery is implicit
Entries unlock when a mob appears in a fight, a trap is revealed/triggered/visible, or an item is identified/obtained. Heirlooms of unlocked heroes are always known. No separate "scan" action.

## 52. Tutorial = contextual one-shot cards, not a scripted level
A scripted tutorial run would have to be maintained alongside the real game. Instead, tips fire the first time the player meets a mechanic in a normal run (first fight, first red tile, first trap, first door...). They are data (`data/tutorial.json`), each shown once, and can be replayed or turned off. The welcome is 3 short pages; nothing blocks a player who already knows SPD ("Skip all tips").

## 53. Tips pause the game
While a tip card is open the Delve Bar stops and Auto play waits, so reading never costs progress or HP. Fights are turn-based, so nothing else needs pausing.

## 54. Mage vs Tengu: more staff charges with level, not a Tengu nerf
Tengu blinking away every 15 HP wastes the Mage's walk-up time while her 2 charges recharge, so she was the only class losing (3/10). SPD's staff gains charges as it levels; the simple version is +1 charge every 7 hero levels. The result is very sensitive (every 6 levels = 9/10, every 3-5 = 10/10), so 7 was chosen: 6/10, close to the ~7/10 target, and it changes nothing in the Sewers where the Mage is below Lv7.

## 55. Delve speed is a setting, the x3 button stays
Some players want to watch every encounter, others want to skip the walking. The setting multiplies the base 5%/s; the in-run x3 toggle is a quick "skip this floor" and stacks.

## 56. Caves: SPD mobs, simple versions, and DM-300 telegraphs everything
Floors 11-15 use SPD's bat (life drain), brute (enrages at low HP), gnoll shaman (piercing zap), spinner (poison bite) and DM-300. DM-300 telegraphs a plus-shaped rockfall 2 ticks ahead and a 1-tick toxic gas line (pierces barrier, poisons); below half HP it supercharges once (+2 DR, abilities more often). Everything dangerous is a red tile, matching the readability rule.

## 57. Boss campfires restore +50 torch and satiety
The Caves are long; without a rest, darkness and hunger killed most sim runs before DM-300. Continuing from a boss campfire now rests the party.

## 58. Potions heal a percentage (max(10, 30% HT)); supplies capped at 10
Flat 10 HP potions were useless at Caves HP levels. The cap stops stockpiling from trivialising the Caves.

## 59. Rogue is weak in the Caves for now (0/10 in the sim)
Accepted for v0.9.0 to keep the release stable; subclasses (next milestone) are the planned fix rather than raw stat buffs.

## 60. Screenshot runs can be split (SHOTS=a,b)
Long xvfb screenshot runs on software GL sometimes drop textures in later shots (prison/early shots fine, same shots render correctly when run alone; node counts show no leak). Treated as a test-harness rendering artifact, not a game bug; the exported pck verify still loads every sprite and tileset.

## 61. Subclasses: flat modifiers + one "perk" hook each, picked permanently with Tengu's Mask
SPD gives the subclass choice for Tengu's Mask; we grant the mask on the class's first Tengu kill and keep the choice permanent (no respec) like SPD. Each subclass is data in heroes.json (`dr_add`, `barrier_add`, `surprise_add`, `cloak_add`, `delay_mult`, `bolt_add`, `bolt_pierce`) plus at most one coded perk (rage, combo, battle_recharge, soul_heal, grass_heal) so they stay simple and testable.

## 62. Subclass balance (cavesrun, 10 seeds)
Warrior base 7 / Berserker 10 / Gladiator 8; Huntress 5 / Sniper 8 / Warden 8; Mage 4 / Battlemage 10 / Warlock 4; Rogue 0 / Assassin 7 / Freerunner 8. Subclasses are a reward for beating Tengu, so being stronger than base is intended. Warlock shows no gain in the sim (the bot's Mage dies to darkness/attrition on floors 11-13, not single fights); left as a known issue rather than over-tuning blind. A test asserts the best Rogue subclass reaches >= 4/10.

## 63. Guided first fight: a banner + glowing tile, never an input lock
A scripted fight with locked input would need its own room and code path that could break real play. Instead the real first fight gets a step banner and reuses the Hint highlight (path_step toward the enemy, then the adjacent enemy). Progress is read from the fight state, so any action order works; completion is stored as tutorial_done "guided_fight" and resets with "Replay the tutorial tips".

## 64. Mage's Staff scales with level; Warlock heals from bolts
The plain Mage died to Vampire Bats with full potions: a 3-damage staff vs DR 2 does 1 per hit, so fast drainers out-healed her. SPD's staff grows with the Mage, so the heirloom gets +1 melee damage per 6 levels (per 5 was 8/10, too strong; per 7 left her at 4/10). Warlock kill-heals rarely mattered (deaths were burst, not attrition), so it now heals a third of bolt damage, close to SPD's soul-mark sustain.

## 65. Subclass targets ~8/10 in the Caves sim
Berserker +20% below half HP (9/10), Battlemage every 5th hit (8/10). Values in BALANCE.md.

## 66. SPD chrome + pixel font as the Godot theme; talents as data modifiers
UIKit.make_theme builds StyleBoxTextures from SPD's chrome.png using the regions in SPD Chrome.java (WINDOW, RED_BUTTON, GREY_BUTTON, TAB_*, TOAST). The atlas is upscaled at runtime by a whole factor (font size / 9, 2-6x) with nearest filtering, so borders stay crisp pixel art on both Fold screens. SPD's pixel_font.ttf is the default font, with the engine font as a glyph fallback.
Talents follow SPD's tier idea, simplified: 4 talents per tier, 2 points per tier (Lv3/5 and Lv9/12), each a flat modifier (`ht_add`, `dmg_add`, `dr_add`, `barrier_add`, `search_add`, `surprise_add`, `cloak_add`, `bolt_add`, `charges_add`, `potion_add`). First tries (3 points per tier, +4 HP / +2 Barrier / +1 dmg in tier 1) made every Caves sim 10/10, so tier 1 is utility (+3 HP, +1 Barrier, search, potions) and tier 2 holds the combat stats. Talents reset on death with the level, like SPD. Talent icons from talent_icons.png are not mapped yet (text buttons).

## 67. Backpack: 8 gear slots, Camp gear is "owned", equipping found loot banks it
Materials keep stacking in the pack (like SPD's bags); only gear uses slots. Equipping a found item moves it into the hero's slot, so it is kept like equipped gear (cracked on death, not lost); the item it replaces goes into the backpack flagged owned and comes home whatever happens. This keeps the "equipped gear cracks, the pack is lost" rule simple and never destroys Camp gear. Swapping in a fight costs 1 tick (same as Wait). A full pack parks new loot in run.overflow and the Delve screen opens the Backpack until the player drops something or leaves it; the sim always leaves it.

## 68. Lighting and effects are drawn in GridView._draw, no shaders or Light2D
The Compatibility renderer and phone GPUs favour plain 2D draws. The light is 3x3 dark sub-cells per tile with alpha from the distance to the hero (about 580 small rects, plus 64 cheap line-of-sight checks per frame); a GradientTexture2D version left stray dark bands on the inner screen when it was clipped, so it was replaced. Water scrolls by offsetting the texture region with texture_repeat (the same effect as SPD's water offset) instead of a shader. Particles are plain rect lists with a 160 cap. Lighting is cosmetic only: fights stay deterministic and every enemy is still drawn (dimmed) so tactical information is never hidden.

## 69. Dwarf City: SPD mobs simplified, the King summons instead of phases
Ghouls keep SPD's rule that they only stay dead when no other enemy is left (they rise once). Warlocks reuse the zap telegraph, Monks are just fast, Golems slow and heavy. The King of Dwarves drops SPD's three phases and lifelink: he raises Risen Dwarves on marked tiles (only when none are left) and casts a 3x3 shadow blast. The blast first had a 1-tick fuse, which no one can escape from the centre of a 3x3 in one step, so it is 2 ticks; the bot also learned to walk out of areas wider than one step.

## 70. Smarter bot moved the balance numbers
Once the bot could escape multi-tile telegraphs, every Caves sim rose to 9-10/10, so the bot had been dying to avoidable damage. Caves were retuned (Shaman and Spinner +1 damage, DM-300 HT 160) back to ~8/10 for base classes. Current tables are in BALANCE.md.

## 71. v0.15.1 — "I don't see the UI changes" diagnosis + SPD hardening
- Diagnosis: the v0.15.0 APK already contains pixel_font fontdata and chrome.png and verify_pack loads both; no StyleBoxFlat/LabelSettings/font overrides remain in scripts/. The reported screenshot (smooth sans, flat brown panels) matches pre-v0.13 builds, so the device was on an old install. To make this checkable, the version now shows in the Camp header and at the top of Settings, and build.sh fails if project.godot config/version != export preset version.
- Hardening: project-level gui/theme/custom_font = pixel_font.ttf; the runtime theme is also set on the root Window; pixel font fallback is a SystemFont (avoids a cyclic fallback with the project font).
- Integer pixel text: pixel_font draws 1 font pixel per 100 units of 2048/em, so all text sizes snap to multiples of 20.48 (UIKit.font_px).
- SPD status pane (status_pane.png bg + hp/shield/exp bars + portrait) on Delve and Combat; toolbar.png slots + backpack/wait/search icons on control buttons; progress/slider/scrollbar use chrome.png.

## 72. v0.16.0 — SPD gameplay rendering
- GridView ports SPD's DungeonTileSheet stitching: floor alts by per-cell variance (52.5%/5%), raised wall faces (+1/+2 open sides, RAISED_WALL_DOOR, alt walls), internal wall tops and wall/door/grass overhangs drawn in a walls layer OVER characters (SPD perspective), water edge stitching (WATER+mask over the scrolling water texture), chasm-from-above stitching, raised doors/sideways doors, raised high grass.
- The 8x8 arena is framed by a wall ring (cells outside the grid = WALL, like a SPD room); camera fits arena + ~0.6 tile so the border shows; integer zoom unless that wastes >15% of the screen, then 4 px steps.
- Character animations come from SPD's *Sprite.java via tools/gen_anims.py -> data/anims.json (idle/run/attack/die/zap, fps, frames). Facing flips by horizontal movement/attack; die anim then fade.
- SPD HealthBar (red bg/green hp/pale shield, mobs only when hurt), BuffIndicator small icons (poison, charging, enraged, invisible), FloatingText centred pixel-font numbers.
- Fog/light: per-corner darkness blended across each cell (bilinear like SPD FogOfWar's texture); out-of-LOS = SPD "visited" darkening, torch radius on top.
- Not ported: SPD's Emitter particle classes (kept our pixel particles), shadows, exact SPD fog colours for MAPPED.

## 73. v0.16.1 — readability fixes
- Hint/small labels never go below 3/4 of body size; font_px allows half font-pixel steps above 1x so hints sit between body sizes.
- Toasts moved to 76% of screen height (below the arena / delve card). Combat camera margin 0.3 tile, integer zoom kept unless it wastes >10%.
- SPD icons.png regions added to UIKit (SPD_ICONS, spd_icon, with_icon).

## 74. v0.16.1 — StatusPane is a port of SPD's large StatusPane
- Follows StatusPane.java large layout: bg NinePatch (0,64,41,39 L33 R4), avatar centred at (15,16), level number in the badge strip at (15,33), buffs row at (31,0), HP bar at (30,19) 9 tall with shield drawn under HP like SPD's shieldHP and "HP/HT" (or "HP+shield/HT") centred, EXP row at (30,30).
- Name sits in the buff row beside the portrait (never in a bar). Depth "F#" and danger (skull + living enemies) right-aligned like SPD's depth/danger indicators.
- The EXP row shows compact Torch | Food in delves and Torch | Barrier in fights (no hero EXP bar in this game).
- Buff icons use SPD buffs.png with its real 7x7 grid (18 per row) — fixes wrong icons in v0.16.0 enemy status icons too.

## 75. v0.16.2 — polish + SPD icon sheet
- Toasts during a fight go into the combat log; toasts still floating are cleared when a fight starts.
- Arena origin puts most vertical slack on top (max 0.75 tile) so the raised top wall face shows.
- Barrier shows only as SPD's shield overlay on the HP bar; the bottom row is Torch | Food everywhere.
- SPD icons.png on camp tabs (enter, rankings, backpack, challenge, alchemy, scroll, badges, journal, prefs), delve toolbar (sleep/arrow, busy, talent, prefs, exit) and fight buttons (info, busy, arrow, warning, plus, buffs, target).

## 76. v0.16.2 — resource row + secondary buttons
- Delve resource row uses UIKit.res_chip: icon vertically centred, number immediately after its own icon, fixed chip spacing, HFlow wraps whole chips.
- "Ignore both" (and future skip/cancel actions) use SPD grey_button chrome via UIKit.secondary; real choices keep the red primary button.

## 77. v0.17.0 — Demon Halls (21-25) + Yog-Dzewa
- Halls follow the City (city.next = halls). SPD tiles_halls + water4, halls music. Four Halls rooms (chasms, water, a split room) + a pillared boss room.
- Mobs (SPD sprites/anims): Succubus (HT 70, dmg 16, heals 5 per bite), Ripper Demon (HT 40, dmg 14, acts every 0.6), Evil Eye (beam 20 ignoring DR every 2 actions), Scorpio (spits at range 2-4, poison bite), God's Larva (summon).
- Yog-Dzewa (HT 240, DR 6, dmg 16): immobile; every 3 actions (2 below half HP, +1 larva) alternates larva on 2 marked tiles (only when none are left) and a gaze beam over the hero's row and column (2-tick fuse, 14 ignoring DR). A single diagonal step escapes the beam. No fists/phases yet.
- Tier 5 gear: Greatsword (dmg 20, Str 18) and Plate Armor (DR 5 / barrier 5, Str 18), Blacksmith Lv3 recipes.
- Balance (sim): Lv18 Warrior, Str 18, Greatsword+2/Plate+2 wins 88/88 Halls fights (lowest 13/105 HP) and Yog 4/4 with 3 potions (ends ~10 HP).

## 78. v0.18.0 — icon-only camp tabs on narrow screens
- When the viewport is narrower than 34 x font size (Fold cover), camp tabs show SPD icons only; the selected tab adds its label. All 9 fit without scrolling. Camp resource header uses res_chip spacing.

## 79. v0.18.0 — King of Dwarves lifelink + 3 phases
- Phase 1 (>1/2 HP): summons / shadow blast every 3 actions; while Risen Dwarves live he is lifelinked and takes 2/3 damage.
- Phase 2 (<=1/2): +3 dmg. Phase 3 (<=1/4): throne cracks, no more summons (lifelink ends once his dwarves die).
- Ability cadence stays 3 in every phase: a 2-action cadence with 2-tick blasts left the hero no turn to strike (sim: Lv21 tier-5 heroes died with 120 HP without landing a hit). HT 150 -> 140.
- A heal-per-dwarf lifelink was tried and dropped (King out-healed all damage).
- Sim: Lv14 tier-4 Warrior wins 6/6 King seeds with 3 potions; cityrun 6/6 Warrior, 5/6 Huntress; hallsrun (floors 1-25 in one run, Lv16 tier-5) 3/4.
- UI smoke now continues King -> Demon Halls -> Yog-Dzewa -> extract.

## 80. Items with ID (v0.19.0)
Rings of Evasion/Wealth/Energy and an Artifact slot (Chalice of Blood, Talisman of Foresight, Horn of Plenty) are added. There are six unidentified potions/scrolls with appearances rolled per save. Using one identifies it. Bosses drop an artifact you don't own yet. Teleport skips the next non-boss fight. Wands stay as the class staff, and Ring of Energy adds +1 charge to it.

## 81. Doors and grass rendering (v0.19.1)
This ports SPD's DungeonTileSheet/DungeonWallsTilemap door handling:
- A door that someone stands in shows RAISED_DOOR_OPEN (113) and DOOR_OVERHANG_OPEN (225) above it.
- Sideways doors draw DOOR_SIDEWAYS_OVERHANG(_CLOSED) (208/212) on the walls layer, so the frame sits over the occupant. The wall above shows no sideways tile while the door is open.
- Open/closed is derived from occupancy every frame, so it can't get stuck.
- Tall grass trodden on becomes short grass (SPD HIGH_GRASS→GRASS). It no longer blocks sight, and `combat.trampled` is saved.
- The tall-grass overhang is drawn in the ground pass, so it no longer cuts off the top of characters.

## 82. Surface Camp hub redesign (v0.20.0)
- The tab strip is replaced by a drawn camp scene (`camp_scene.gd`): a night sky with SPD surface clouds and a grass clearing with a campfire, drawn with sewer tiles at an integer scale.
  - Facility NPCs use SPD sprites: Blacksmith → Forge, Wandmaker → Enchanter, Shopkeeper → Guild, alchemy pot tile → Alchemy, chest → Stash.
  - Tapping one opens its page as an SPD chrome window.
  - A red "!" badge marks an affordable upgrade or a finished identification.
- Under the scene: portrait hero slots with level badges, a biome picker and a big Delve button. The scene is stacked on the cover and side by side on the inner screen, which also gets quick-access buttons.
  - The picker lets a hero start in Sewers, or in the biome after any biome they've cleared; the run starts on that biome's first floor.
- Lists are SPD-style item-slot grids (translucent square, count bottom-right, +N top-left, green frame = actionable). Tapping a slot opens an info window with stats, a cost row (unaffordable amounts in red) and the action.
- Facility windows show the NPC, Lv/cap with a level bar and a "Next:" upgrade preview. Identification and patrols show progress bars.
- The pixel font now disables subpixel positioning and hinting. Headless screenshots render at half device resolution, so 1-px glyphs (i) can drop out there but not on the device.

## 83. Camp polish (v0.21.0)
- Camp NPCs play SPD's idle animation tables (Blacksmith 15 fps, Wandmaker 10, Shopkeeper 10). The hero idles using anims.json.
- Holding an item slot for 0.45 s opens a compare window: this item vs the selected hero's equipped one, with better values green and worse red.
- Toasts never float over a window. While a Camp window is open they show in its footer strip, and opening a window clears floating toasts.
- Talents use SPD's TalentsPane look: talent_button.png squares with talent_icons.png icons (indices from SPD Talent.java), names below, and a green pip when learnable. Tapping one shows a detail card with Learn.
- Alchemy uses an SPD WndAlchemy-style pot: ingredient slots (have/need) => result slot, a Brew button, and a recipe picker.

## 84. Paperdoll character screen (v0.21.0)
- `Paperdoll` (scripts/ui/paperdoll.gd) is a Diablo-style screen with a large hero sprite in the centre. The sprite row follows the armor tier, as in SPD's HeroSprite.
  - Left column: weapon, ring, staff/wand. Right column: armor, artifact, class item (seal/staff/cloak/bow). Below: a misc slot (reserved).
- Tapping a slot shows its item and a swap list filtered to that slot, with stat deltas (green better, red worse). At Camp the list comes from the stash, via a hero_stats preview with the item swapped in. In a delve it comes from the pack, via compare_equip and delve_equip, and a swap costs the turn in combat.
- A derived-stats grid sits next to the doll: HP, Dmg, DR, Barrier, Speed, Str, XP, Search, plus bolt, subclass and a Talents link.
- It is used by the Camp Heroes window and the in-delve backpack. On the cover the stats go under the doll; on the inner screen they go to the right.

## 85. Paperdoll fixes, alchemy with found potions (v0.22.0)
- The delve paperdoll goes side by side whenever width > 0.7 × height. The Fold inner screen is roughly square, so the old 1.1 threshold never triggered.
- The misc slot is removed rather than faked. This game has no throwables, and belt supplies already have quick-use buttons in the backpack.
- Six alchemy recipes use found potions/scrolls: Toxic Gas or Shielding (+1 seed) → 2 Healing; Experience → Starter Elixir; Teleportation → Scroll of Passage; Identify/Mapping → Arcane Resin.
  - Brewing with an unidentified ingredient identifies it. Until then the recipe reads "Brew the <appearance>" so the name doesn't spoil the ID.
- Delve Backpack/Talents/Settings panels also take toasts inside the panel.

## 86. Special rooms
Eight SPD-style specials (vault, library, well of health/awareness, laboratory, treasury, shrine, larder) as event cards with room icons; rewards via heal_pct/satiety/identify_pack/artifact keys.

## 87. Yog phases
Yog is shielded while a fist lives. Burning Fist at start, Rotting at 2/3 HP, Bright at 1/3; damage clamps at each threshold. Larva only spawn while unshielded; fists crumble on Yog's death. Bot skips shielded targets.

## 88. Perf pass
grid_view caches LOS keyed on hero pos + terrain hash + unit count; camp_scene redraws at 15 fps only while visible.

## 89. Icon centering
All icons go through PixelIcon: trimmed via SPD assignItemRect sizes (data/item_rects.json), integer scale, floored centre in both axes. Toolbar icons padded to even sizes, button heights even. `icon_audit` screenshot + test_icon_centering guard it.

## 90. Armor tiers on hero sprites + animated delve corridor
GameState.armor_tier(c) (SPD Hero.tier: 0 naked, cloth row 1 … plate row 5) feeds every hero draw: combat units ("row"), status pane portraits, camp fire hero, Heroes-window portraits, paperdoll. test_armor_tiers checks each of the 5 armors gives a distinct frame region.
DelveScene: top-down SPD-tile corridor of the run's biome above the Delve Bar; scroll follows floor progress (160 tiles/floor), hero runs in its armor row, torch light pool with flicker (smaller in darkness), 2-layer parallax dust, seeded side doors/bones/idle biome mobs, gold/dew pops, stops at encounters with the door opening or the enemies appearing. Redraws at 20 fps only while visible.

## 91. Garden and Sacrificial Fire
Garden: forage, rest in the sungrass (+35% HP for 15 food; new "satiety" cost key), Huntress harvest, or beat the deep grass (biome fight, seeds + potion). Sacrificial Fire: blood offering, or lure foes into the flame (biome fight, unknown wand + gold). `"fight": "biome"` rolls a normal encounter for the current floor.

## 92. Yog / Halls retune
Full runs died at Yog arriving with 8-45 HP. Descending onto the final boss floor restores 60% HP (antechamber); Yog HT 120->100, melee 16->14, gaze 12->9; fists 10/8/6 -> 8/7(+1 poison)/6 zap. Hallsrun now 3/4; the test threshold is >= 2/4.

## 93. Touch scrolling
TouchScroll (child of Main) reads pointer input before the GUI: a press inside a scrollable ScrollContainer becomes a drag after a 10-16 px threshold, scrolls the innermost container that can move on that axis, cancels the press under the finger (pointer-out motion + button_mask 0 until release), and keeps momentum with e^-4t friction. Every ScrollContainer gets deadzone 12 and wide SPD scrollbars; buttons use MOUSE_FILTER_PASS. Own hit test so it is unit-testable headless (test_touch_scroll).

## 94. Floor label / screenshot state
Saves clamp run.floor into the run biome's range on load; test_floor_label walks every biome transition. Screenshot delve shots start from a fresh Warrior Sewers run (the "Floor 25 / 5" image was the Yog shot's state leaking).

## 95. Tutorial tip layout
Tips were positioned by hand one frame after creation using the viewport size, so on the inner screen the card was placed before its wrapped text was measured and ran off screen. Now: overlay -> MarginContainer (4% / 0.75 em margins) -> CenterContainer -> card of width min(26 em, screen - 2 margins); title, text and buttons wrap/clip; the card fades in only after two layout passes. test_tip_fit renders every tip page at cover, inner and half-size and checks card and text bounds.

## 96. Sprite aspect + item icons
No TextureRect remains in the UI: every sprite (items, NPC/facility portraits, talent buttons, tiles) is a PixelIcon at a uniform integer scale, centred, never stretched. test_all_icons checks every item/material id (known and unidentified: ring gems, potion colours, scroll runes) resolves to a non-fallback items.png cell with visible pixels.

## 97. Forge/Guild bulk actions
Recipes (Forge "Make", Guild "Buy") and item upgrades open an info window with a quantity picker: [-] slider [+] xN, max = what is affordable (and, for upgrades, the Blacksmith cap), live "Total" cost chips (red when short), and a "<verb> xN" button. GameState: craft_max/craft_n, upgrade_max/upgrade_cost_n/upgrade_item_n (cost rises per level, so the total is summed), all-or-nothing. "Repair all" sits above the Forge gear grid with the cracked count and summed cost; disabled with a reason when nothing is cracked or it is unaffordable. Forge and Guild windows start with a live materials strip (Forge: iron ore, dark gold, gold, resin, Scrolls of Upgrade; Guild: gold, dew, seeds, ore), rebuilt on every state change.

## 98. Rings at the Forge, cracked look, old saves
The Forge grid only listed weapons/armor, so cracked rings/artifacts (death cracks every equipped non-heirloom item) could not be repaired and never appeared there. Cracked rings and artifacts now show in the Forge grid (repair only; they don't upgrade) and count for Repair all. Cracked gear no longer gets a red multiply tint (it turned small gold/red ring sprites into a dark smudge); it keeps true colours with a red frame and "!" badge, also in the paperdoll. Delve backpack potions/scrolls use integer-scaled PixelIcons instead of 1x Button icons. Save load migrates gear missing known/cracked and legacy gem-named ring ids. test_ring_contexts checks the ring sprite in stash/Forge slots (known, unknown, cracked), paperdoll, backpack, the migration, and repairing a cracked ring singly and via Repair all.

## 99. Delve frame rate
The Delve screen rebuilt its whole supplies row (new Controls) and recomputed hero_stats every frame, and the corridor drew ~2400 darkness rects per frame but redrew only at 20 fps. Now: _refresh touches the UI only when a signature (HP/torch/food/buffs, supplies/pack) changes, hero_stats is cached by level+gear; the corridor redraws every frame (60 fps with vsync) and its light is one radial GradientTexture2D quad + 4 rects; hero stats in the scene cached for 0.5 s. Speed x3 no longer snaps: the scroll chases the target with exponential smoothing (gap * (1 - e^-6dt)) instead of a capped step that x3 outran (and a >12-tile snap).

## 100. No alarm sound
The SPD "alert" cue (encounters, Yog telegraphs) and "health_warn" are banned in Sfx.play. Encounters get a soft door_open (doors/specials) or a short haptic (fights); telegraphs only buzz. A test fails if code calls the alarm again.

## 101. Feedback and log
Pickups: gold/dewdrop/item SPD sounds (throttled at 180 ms), a rising item icon with "+N", and a short glow around the hero; respects the SFX volume. Log: GameState.say(text, kind) / log_line(text, kind) store a kind (positive/negative/warning/highlight/info/auto) shown in SPD GLog colours (green/red/orange/yellow/white/blue) under the Delve Bar, 8 lines, rebuilt only on new lines. Small pickups (passive gold/dew, the scrap of iron ore per floor, and any other pack material) are not each a log line. `run.haul` totals them for the whole expedition (spending does not reduce it; old saves seed it from the pack) and the Delve log pins `Collected this delve: N Gold, ...` above the scrolling lines, updated in place. Logged as their own lines: item/reward finds, fight summaries (kills, damage taken, gold, xp), defeats, traps spotted, door/room choices, torch/food warnings (once per floor), floor changes, level ups, auto-battle starts.

## 102. Full Auto
Toggle in the Delve bottom bar (settings.full_auto, saved). Originally it also picked doors, rooms, floors, campfires, overflow drops, and talents. Revised by #105: it is Auto Battle only.

## 105. Auto Battle, not full auto
The Delve bar toggle (still `settings.full_auto`, so old saves keep it) only plays fights. An ambush waits 0.8 s, then combat runs on CombatBot and Continue is pressed. Doors, special rooms, floor ends, campfires, a full backpack, and talent picks stay on screen until you choose. When you are close to dying (<= 30% max HP, or in combat when adjacent enemies/poison can kill you through your HP + Barrier on the next turn), Auto Battle turns off and pauses exploration so you can take manual control or read a Scroll of Passage (available both in the Delve bar/card and directly in the combat toolbar). Pause still holds exploration (including an ambush that has not started).

## 103. Owed Scrolls of Upgrade
Dying with Scrolls of Upgrade in the pack no longer destroys them: they are added to a per-save `owed_sou` counter (stacks across deaths and heroes) and all of them return to the pack on the next boss kill by any hero, with a highlighted log line ("A lost Scroll of Upgrade returns!") and the corridor pickup pop. The count shows on the Camp Delve page and in the Stash. Older saves load with 0 owed. (Supplies already returned to the stash; only pack scrolls were at risk.)

## 106. Toasts never cover a delve menu or duplicate the delve log
Any open delve window — floor, doors, rooms, campfire, backpack, talents, settings, menu — hides the background delve log. New messages go into the window as a short toast above the buttons (and pull in any floating toast already on screen). The window itself does not embed the scrolling log. When no window is open, the delve log is right there on screen, so floating toasts are suppressed and cleared instead of duplicating the log line beside it.

## 107. Spare rings break down at the Forge
Patrols and vaults hand out the same few rings, and a hero wears only one, so copies pile up in the stash with nothing to do. The Forge lists each ring (a count when you have more than one). Breaking one down yields 5 Gold and 1 Arcane Resin — a band and a gem, small next to a floor of gold or an hour of patrol resin. "Break down extras" melts every copy past one spare of each ring, and never a ring someone has equipped. The spare it keeps is the best one: intact, then identified, then higher upgrade level. A queued identification is dropped if that ring is melted. Cracked rings are repaired from the same window; they no longer sit in the weapon grid.

## 108. Item type glyphs
SPD draws a second sprite from `item_icons.png` in the top-right of an inventory slot once a ring is known or a potion/scroll is identified (`Item.icon`, `ItemSpriteSheet.Icons`, `ItemSlot`). The gem, bottle colour, or rune stays the main sprite; the glyph says what it does. Ours uses the same sheet and the same corner: the trimmed glyph is centred in an 8px cell flush with the top-right, at the item's integer scale. Unidentified rings and un-ID'd potions/scrolls omit it. The blue shield on that sheet is Ring of Tenacity and Potion of Shielding. Ring of Force's own glyph is the red mark at film index 5; this game has no Ring of Force, so that cell is unused. `test_item_badges` checks the sheet, the corner, and that identification is what reveals the glyph.

## 104. No softlock after a total wipe
Starting a run never required gear, but a wiped save felt (and played) locked: cracked weapons fell back to starter stats while still applying the cracked item's upgrade level math, cracked armor gave no DR, a broke Camp had no rations/torches and no gold to buy them, and repair ore came only from chests/patrols. Now: cracked/missing weapon or armor uses the class starter weapon + Cloth Armor (free, never cracks, like SPD starting items); the Forge shows a free "Patch up" (cheapest cracked weapon/armor first) whenever no repair is affordable; a broke Camp (0 rations, 0 torches, < 10 gold) gets 1 ration + 1 torch when a run starts; every floor descended yields 1 iron ore. These are runtime rules, so an existing wiped save is playable on load. test_total_wipe covers the reported state.

## 109. Goo death-spiral exit
Playtest (12 Full Auto expeditions x 4 classes x 3 seeds) showed early saves locked into dying to Goo: healing potions were only brewed (seeds) so the stash hit 0 after run 1, deaths drained gold to 0, and a Lv3-4 hero without potions cannot beat Goo. Now: the Guild sells a Potion of Healing for 30 gold (Lv1); killing Goo always puts a Potion of Healing on the belt (unused, it is banked like any supply); a death tops the stash up to 30 gold (`SAFETY_GOLD`, enough for one potion) and never removes gold. test_goo_spiral covers all three.

## 110. Food scaling
Playtest: a Lv24 Mage still ended every run at floor 9-10 because rations ran out (a 3-ration loadout covers about 2 biomes and nothing refilled it). Now every boss kill adds `Delve.BOSS_RATIONS` (2) rations to the belt (unused ones are banked like any supply), and Guild Lv2 sells a Ration Crate (3 rations for 25 gold instead of 30). test_food_sources covers both.

## 111. Ring, potion and scroll rects; tiny sprites one step larger
Root cause of the small/off-centre ring icon (the open on-device question from #98): data/item_rects.json had no entry for the ring gems (224-228), the potion colours (352-360) or the rune scrolls (304-313), so item_rect fell back to the full 16x16 cell and the 8x10 ring was drawn top-left inside a centred 16x16 block. Added SPD's assignItemRect sizes (rings 8x10, potions 12x14, scrolls 15x14). PixelIcon.draw_k() also draws sprites whose longest side is <= 10 px one integer step larger than scale_k(), so a ring is not half the size of the sword next to it; still integer and inside the cell; badges keep scale_k. test_icon_centering checks every icons.json id has a rect and the ring scale step.

## 112. Delve log "missing i" was a screenshot artifact
Playtest saw "Warr or", "P cked up", "Rat on" in delve log screenshots. At native resolution (968x2376 viewport, SHOT_NATIVE=1) every glyph is there: the harness window (484x1188 / 928x1080) is a ~0.5x canvas_items stretch, and with nearest-filtered, non-antialiased pixel font a 1-px column (i, :, .) can vanish. On the Fold the stretch is ~0.93 and the smallest text is 1.5 font px, so >= 1.4 screen px per font pixel: no drops. The screenshot harness now renders at 2x and Lanczos-downsamples to the old sizes, so shots show what the device shows. The game's font sizing is unchanged. (The desktop dev window override, 484x1188, still drops glyphs; it is not a shipped target.)

## 113. Screenshot pickup-pop leak
The "+3" gold pop in delve_enemy / delve_special / delve_auto shots was not a game bug: delve_walk stages a pop (age 0.2 of a 1.1 s life) and the next shots, 12 frames apart on the same DelveScene, captured it again. In play, pops age by real delta and expire. The harness now clears pops and the glow before the following delve shots.

## 114. Facility header: level / max, cap never below level
The Guild header read "Lv 2 / 1" beside a "capped" Upgrade button: the header printed the Scroll-of-Upgrade `cap` (not the facility max), and nothing kept `cap >= level` (the screenshot harness, debug edits or an old save can set a level without the cap). `GameState.facility_cap(id)` = clamp(max(cap, level), 1, max) is used by can_upgrade_facility, apply_sou and on load; the header shows "Lv level / max" and adds "(cap N)" only while the cap is what blocks the next level. test_facility_cap covers the reported state.

## 115. Supply slots show their pack size
Playtest at 42b0c29: with the Guild at Lv2 the Supplies grid showed two identical Ration slots (the single Ration and the new 3-ration crate from #110), both with the same stash count, so you could only tell them apart by opening each. Now `CampScreen.recipe_slot` puts the pack size ("x3") in the slot's top-left corner for any material recipe with `out_n > 1` (the same tag the Alchemy brew card already used for its output), the stash count stays bottom-right, and the buy popup adds "Gives 3 Rations.". No new art: SPD has no crate sprite, and its shops show stack sizes on the item sprite the same way. Test: `test_crate_slot`.

## 116. Dew has a use
Dewdrops (+1 per 12% of every floor, plus events) had no sink at all: nothing in recipes, facilities or the delve spent them, and a 40-expedition campaign ended with 1.7k-6k dew. Alchemy now has "Condense Dew into Healing" (20 dew -> 1 Potion of Healing, Alchemy Lv1), echoing SPD's Dew Vial. This gives dew a purpose and early players a second potion source; it does not by itself stop late-game stockpiling (see the playtest report on gold/dew inflation). test_dew_sink.

## 117. Old in-progress runs load
A run saved before the backpack existed (no `pack_gear`) threw a script error in _fix_types (`run.pack_gear + run.overflow`), which aborted the rest of type fixing and left the run unplayable. `RUN_DEFAULTS` lists every key start_run creates; on load any missing run key gets its start value before types are fixed. test_old_run_load loads a pre-backpack run, advances and extracts it.

## 118. Hero level cap 30
Heroes levelled without limit: a 40-expedition Full Auto campaign reached Lv103 (Mage Lv94 by run 35), with HP, accuracy and stat growth unbounded and the late game trivial. SPD caps at Hero.MAX_LEVEL = 30; `GameState.MAX_LEVEL` = 30 now stops grant_xp (xp held at 0) and over-cap saves load at Lv30. Death still resets to Lv1. test_level_cap.

## 119. Returned Scrolls of Upgrade go to Camp
#103 returned owed Scrolls of Upgrade into the pack on the next boss kill, so abandoning (or dying on) that same run lost them a second time. grant_owed_sou now adds them straight to the Camp stash with a highlighted "return to Camp" log line. Supersedes the "back to the pack" part of #103.

## 121. Rogue: SPD cloak charges
Deep campaign sims had the Rogue dying 26 times in 120 expeditions (Warrior 8, Mage 7, Huntress 9), most of it at Goo, with Sewers-only progress on one seed. SPD's Cloak of Shadows has chargeCap = min(level + 3, 10), i.e. 3 at +0; ours had 2. Cloak charges are now 3 per fight (data/heroes.json). Rogue deaths in the same sim: 26 -> 6 (40 runs x 3 seeds), 7 -> 3 (12 x 3). test_rogue_cloak.

## 124. Camp layout: scene first, one job per window
The hub stacked a wrapping resource bar, a short scene, portraits that repeated Lv/Str, a second stats line, biome buttons with floor ranges, and (wide only) a button grid that duplicated the NPCs. Now:
- The resource strip is one row that scrolls sideways. The scene takes the free space; the dock under it (beside it when wide) holds portraits (face + Lv/Str), one stats line, destination chips (biome name, floors in the tooltip) and Delve, which sits at the dock's foot. On the wide dock the empty middle holds the same patrol cards as the Guild (send / recall); the cover stays lean. The extra Heroes button and the wide quick-access grid are gone: tap the selected portrait for Heroes, the NPCs for facilities.
- CampScene: the sky is capped at 2.5 tiles and spots are placed as fractions of the ground, so a tall cover screen is mostly clearing. Name plates show the page name only; facility level moved to a small badge on the sprite's top-left (the "!" stays top-right). test_camp_npc_hits still covers sprite and plate hits.
- Windows have a footer under the scroller for the page's main action: Descend on Expedition, Upgrade (cost left, button right, reason underneath) and Apply Scroll of Upgrade on facilities.
- Stash (Materials / Potions & scrolls / Gear), Forge (Craft / Upgrade & repair / Rings) and Guild (Supplies / Patrols) split into sections with Journal-style buttons; the choice is remembered while the app runs and a switch scrolls to the top.
- Recipe slots (Forge, Guild, Enchanter) are wider and captioned with the recipe name minus its verb ("Ration Crate", "Leather"). Alchemy recipes are a list of icon + full name (no truncated grid captions).
- Journal lists open milestones as cards and folds finished ones into one "Completed (N)" line. A locked class on the Heroes page shows its unlock progress card instead of a stats card.

## 125. Delve screen: corridor first, cards as windows over it
The percent bar stays the exploration (GDD: UI-driven delving, no hallway walking). The screen around it follows SPD.
- One row holds a depth badge ("Sewers 3"), the bar, and one pip per encounter point, filled once passed. A boss floor's last pip is a skull.
- The corridor is as tall as the rows under it allow, up to 36% of the screen (30% on the wide inner screen). Tiles and sprites scale with it.
- Encounters, the bag, talents, settings, the abandon confirm, and the new Menu open as an SPD window over a light dim. The window fits its contents in the lower middle and only grows up over the corridor when it has to. The dim stops above the toolbar, so the bag and menu stay reachable while a fight waits. Close still only sets an encounter aside.
- The toolbar is square icon slots: Pause, Speed, Auto Battle, Backpack, Talents, Menu. Settings, Scroll of Passage, and Abandon live in Menu, so extracting or abandoning takes a deliberate second tap. A scroll mark on Menu shows a Scroll of Passage is carried.
- Supplies are split into Brought (returns to the stash on every ending) and Found (lost on death). Gear the hero brought and bagged is not counted as found.
- Torch and food are filled bars with an item icon and a percent on the status pane (fights too), orange under 30% and red at 0. Encounter windows do not embed the delve log; reward toasts still sit in the window above the buttons.
- Red edges at or below 30% HP (the Auto Battle stop line), and a short pulse when an ambush opens.
- The campfire lists what extracting banks next to the next biome's floors and Strength gate (red when the hero is under it).
