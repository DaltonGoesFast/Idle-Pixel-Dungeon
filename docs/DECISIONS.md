# Design decisions

Calls made while building the base game overnight (2026-10-14/15) where the GDD was open or silent. Each is easy to change; the place to change it is noted.

| # | Decision | Why | Where |
|---|---|---|---|
| 1 | **Compatibility renderer** everywhere (not Mobile/Vulkan) | v0.1.0 showed torn scanlines on the Fold 6's Adreno with the Mobile renderer; 2D pixel art gains nothing from Vulkan | project.godot |
| 2 | **Official export templates only** | The size-stripped custom template dropped WebP + text-server modules -> no textures/text (v0.1.1). Size isn't a concern since builds are hosted on GitHub. Gradle is on for the updater permission plugin; `custom_template/*` stays empty | export_presets.cfg |
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
- Stash (Materials / Potions & scrolls / Gear), Forge (Craft / Upgrade & repair / Rings), Enchanter (Scribe / Identify / Attune) and Guild (Supplies / Patrols) split into sections with Journal-style buttons; the choice is remembered while the app runs and a switch scrolls to the top.
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

## 126. Ring swap preview: staff charges, not the raw bonus
The Heroes ring swap list (Paperdoll `_delta_text`) compared `charges_bonus`, so Ring of Energy read "HP +4  Charges +1" for the Warrior, Rogue and Huntress, who have no charged staff (the bonus only adds to a Mage's wand charges; the Spirit Bow is unlimited). The preview now compares the charges the hero's staff actually gets in a fight (`bolt.charges`, 0 without a charged staff). test_ring_charges_delta.

## 127. Delve Brought/Found chips stay 48px
09b3032 enlarged Brought/Found chips with `maxi(48, font_size * 2)`. On the Fold cover `font_size` is 40, so chips became 80px and ate the corridor; UI smoke then sometimes failed the long Huntress run (no Yog, no leftover talents). Cap at a fixed 48px — still larger than the default 32px chip, readable on cover, and safe for layout. test_delve_chips.

## 128. Recommended levels for a smooth difficulty curve (no boss easing)
Only a Strength gate was shown, and the implied levels made the late bosses coin flips. Boss probe on main with typical gear (all 8 class/subclass builds, 3 potions, 10 seeds): DM-300 at Lv9 92%, King at Lv14 71% (Warden 0/10), Yog at Lv18 55%. Per user feedback the bosses are not made easier. Biomes get `rec_level` instead, chosen so the win rate at the recommended level falls smoothly: sewers 4, prison 6, caves 9 (DM-300 92%), city 16 (King 86%), halls 22 (Yog 65%). The Camp expedition text and the "Pressing on" text show it, in red when the hero is under it. Yog stays the hardest fight. Melee builds trail there (Warrior about 4/10), which points at bot/melee positioning, not stats.

## 129. Strength potions once per hero life
The deep campaign sim (40 expeditions x 3 seeds) showed median Strength at bosses of 111-152, because the delve's Strength milestone granted a potion on every expedition. SPD has a fixed number of Potions of Strength per game. Each hero now records the milestones it has claimed in `str_found`, and each pays out once. Death resets the list (the hero restarts). Old saves back-fill an empty list. Sim: run outcomes are the same, and median Str at bosses is 18-20. test_strength_once.

## 130. Late-game gold sinks
The deep sim (DEEP=1, 40 expeditions x 2 seeds x 4 classes) ended with a median of 37.5k gold, because nothing cost much after the facilities hit Lv3. There are now four sinks, each tied to something worth having: (1) Masterwork: with a max-level Blacksmith, weapons and armor go past +3 up to +6 at 200 x (next level)^2 gold (3.2k / 5k / 7.2k) plus ore. (2) Guild retraining: a hero who fell can buy levels back at 20 x Lv^2 gold each, up to 2 below its best level ever, so death stays costly and Goo can't be skipped on a fresh save. (3) Patrol provisioning: half the gold a full-length patrol yields, paid up front. (4) Normal upgrades cost 10 x Lv^2 gold as well. Result: median end gold 2.9k (warrior/rogue/huntress 2-3.5k; mage up to 31k, since its heirloom staff draws less from the Forge). Trade-off: masterwork gear lets the bot push deeper, so total sim deaths go 11 -> 28 with more Halls progress. The recommended levels assume +1/+2 gear, so masterwork is optional power for veterans.

## 131. Goo: an SPD-style first skill check, without a death spiral
Feedback: the game was too easy, and Goo usually fell on the first expedition. In the campaign sim a fresh save's first Goo was won 87% of the time. Goo already had SPD's pump-up slam telegraph (3x damage) and its enraged attacks below half HP. Goo now has HT 90 (SPD 100, ours was 70) and SPD's regeneration in water (+1 HP/turn). The Goo arena gets 2 water tiles, so standing and trading in the pools is punished. Fresh-save first attempt: 27%. Mage is the weakest at 1/25 and recovers on retries. Because a death resets the hero, the old safety nets (30-gold floor, Guild potions) weren't enough on their own: the sim showed pots0 retries and 10/40 campaigns never beating Goo in 6 expeditions. So each Goo death (stats.goo_losses) takes 15 HT off Goo, floored at 70. At the floor Goo no longer enrages. A Goo death also restocks the stash to 2 Potions of Healing, and killing Goo resets the count. Result: Goo is beaten by the 3rd expedition in 80% of campaigns, and only 3/40 still hadn't won after 6 (before: 2/40).

## 132. UI smoke: check the talent pick when it happens
The smoke test's "a talent was learned through the UI" failed about 1 run in 3 on main. Instrumenting it showed the Talents card, the icon and the Learn button were always found, and the talent was added every run. The failure came from the final check: it read `heroes[*].talents` after the whole run, but the last hero then goes through the Tengu, DM-300, King and Yog fights, which are not seeded. When that hero dies (stats.deaths = 1 in the failing runs), end_run resets its level and talents, which is SPD's permadeath reset, so no hero has a talent left. The test now sets `talent_learned_ui` the moment pressing Learn adds the talent, and asserts that flag. The check no longer depends on how the random fights later in the run turn out. No game code changed.

## 134. Larger rooms and SPD surprise
Combat arenas are no longer a fixed 8x8: rooms are 8, 10, or 12 on a side, with Sewers/Prison keeping shared 8x8s and later biomes using larger multi-chamber maps. Extra spawn slots on large rooms are filled by repeating the rolled encounter. Surprise matches Shattered Pixel Dungeon: tall grass and closed doors block sight; a hit is a surprise when the foe cannot see you or just lost sight (step off a door so it closes, or circle a grass tile). Snakes `evade_unless_surprise` (no hit rolls in this game). The Spirit Bow refuses range 1; wands may still zap adjacent. Auto battle / Hint use the same door and grass setups.

## 133. Status pane: one bar height, SPD proportions
a6b9d18/09b3032 drew the torch/food row as a full 16-game-px item cell (HP is 9), so the row was about 1.8x the HP bar and pushed the pane past SPD's 39px background. The bars bled over the right frame and squeezed the level badge. Now the pane is a fixed 39px nine-patch tall, as in SPD's StatusPane. HP sits at (30,19) and the supply row at (30,29), both BAR_H = 9. The supply bars split the HP width equally with a 1px gap and share HP's left and right edges. Icons are fitted to the bar height with an integer scale (`StatusPane.icon_size`). `StatusPane.layout(w, k, n)` is the single source of these rects and is asserted by `test_status_pane_layout` for 968 and 1856 wide panes at k = 2-5. Native crops: /workspace/builds/statusbars/{before,after}/{cover,inner}_pane_crop.png.

## 135. In-game updater (Android / Windows) + TestFlight script (iOS)
Sideloaded Android players were opening GitHub in a browser for every APK. `Updater` checks `releases/latest`, downloads the platform asset, and on Android opens the system installer via `JavaClassWrapper` + Godot's FileProvider. That needs `REQUEST_INSTALL_PACKAGES`, which the stock permission list does not expose, so Gradle is on and `addons/apk_install` injects the permission (still official templates — #2). Windows gets the zip opened in Explorer. iOS has no in-app check: `tools/upload_testflight.sh` archives and uploads; TestFlight delivers the update.

## 136. iOS Info.plist: one ITSAppUsesNonExemptEncryption key
In Godot 4.6+, `app_store_compliance/uses_non_exempt_encryption=false` already writes `<key>ITSAppUsesNonExemptEncryption</key><false/>` into the exported `Info.plist`. `export_presets.cfg` also had the same key in `application/additional_plist_content`, which Godot appends verbatim before `</dict>`, so the exported `builds/ios/spd-tactics/spd-tactics-Info.plist` contained the key twice (`plutil -lint` accepts it on macOS, but duplicate keys in a plist are undefined and App Store Connect / Xcode can warn or pick the wrong one). Cleared `application/additional_plist_content` and added `test_export_presets` in `tests/run_tests.gd` to check that Android/iOS versions match `project.godot`, Android keeps Gradle on, and `additional_plist_content` never re-adds `ITSAppUsesNonExemptEncryption`.

## 137. Only large rooms repeat the encounter
eebef56 added `Delve.fill_mobs`, which repeats the rolled mobs until every digit slot in the room is filled. #134 and CONTENT.md say this is for large rooms, and the test is named "8x8 fill keeps encounter length", but the code applied it to every room. The shared and Sewers 8x8s mostly have 3 slots, so `["crab"]` became three crabs, `["rat","rat"]` three rats, `["gnoll","rat"]` gnoll/rat/gnoll, and the statue special three statues. The 10x10/12x12 maps have only 1-3 slots, so in practice the fill never fired where it was meant to. Playtest of a8e5fe0 (12 runs x 3 seeds per class): deaths 34 -> 91, no class past floor 5, 85 of 100 fresh heroes died before reaching Goo, mostly to the tripled crab on floor 2. Now `fill_mobs` returns the encounter unchanged unless `Delve.is_large_room` (either side > 8). With the fix, the same sim has 45 deaths (2c3a17c: 34), and the fresh-save Goo probe has 10 of 100 heroes dying before Goo instead of 85. The extra deaths are mostly crab + snake + snake on floors 4-5 and Prison guards, which come from the new surprise/sight rules (combat, being reworked separately). Large rooms with spare slots still fill them, so future 10x10/12x12 maps with more slots work as #134 intended.

## 138. Updater: every reply ends the check
Playtest of a8e5fe0 fed crafted `releases/latest` bodies into `Updater._finish_check`. Valid JSON with `"assets": null` (or a string/object), or a non-string `tag_name`, raised a GDScript type error (typed `pick_asset(assets: Array)`, `String(null)`). The function aborted with the state still CHECKING, and `check_now()` refuses to start while CHECKING, so the Settings button sat disabled on "Checking…" until the app restarted. The check also shared the download's 600 s timeout, so a stalled connection looked like a hang for ten minutes. Now `pick_asset` accepts any value and skips entries whose name/url are not strings, `_finish_check` type-checks `tag_name` and uses `JSON.new().parse` (no engine error spam), and the check uses `CHECK_TIMEOUT` = 20 s while downloads keep `DOWNLOAD_TIMEOUT` = 600 s. A non-200 reply shows "Check failed (HTTP n)" (GitHub's unauthenticated limit is 60/hour per IP), and a transport failure still shows "No network". Nothing installs without the player pressing Update; that flow is unchanged.

## 139. Don't pop the Surprise modal over the guided first fight
Since #134 made tall grass and closed doors block sight, `combat.surprise_ready()` is true whenever any living enemy cannot see the hero — including turn 0 of a fight whose enemy spawned behind tall grass. In `tests/screenshots.gd`, `guided` (seed 5, event 3, `["rat"]`) rolls shared room 2 (`#H."...# / #..#.1.#`), where the rat is behind `(3,1)` grass. `CombatScreen._refresh()` called `main.tip("surprise")` on frame 0, covering the Step 1/3 banner with the modal and leaving `surprise` in `main.tips.queue` for every later combat screenshot (`combat` through `boss`) because `tip_closed` had already run and `CombatScreen._process` returns early while `main.tip_open()`. A real new player whose first fight rolled a room with grass between `H` and `1` got the same modal on top of Step 1/3 before moving once. Fix: `CombatScreen._refresh()` only triggers `main.tip("surprise")` when `guide == 0 or guide >= 4` (not during guided steps 1–3), and the guided completion line now mentions closing doors and tall grass alongside red tiles and class abilities. Covered by `test_guided_surprise_tip`.

## 140. `build.sh`: write `android/.build_version` and `.gdignore` when unpacking `android_source.zip`
When `Project > Install Android Build Template…` is run in the Godot editor, it unpacks `android_source.zip` into `res://android/build/`, writes `res://android/build/.gdignore` so the resource scanner skips the Gradle project, and writes the template version string (`4.7.2.stable`) to `res://android/.build_version`. Godot's Gradle export step checks `android/.build_version` before invoking Gradle and aborts with `Missing build version file` if it is absent. Both `android/build/` and `android/.build_version` are gitignored, and `tools/build.sh`'s `ensure_android_template()` only unpacked the zip into `android/build/`, so a headless Gradle export on a fresh clone (or after cleaning `android/`) failed even when `android_source.zip` was present. `ensure_android_template()` now also writes `android/.build_version` and `android/build/.gdignore` (including when `android/build/` already exists without `.build_version`). Covered by `test_build_script_android_template`.

## 141. Pin the release signing certificate
The in-game updater (#135) hands the downloaded APK to Android's installer, and the Settings text promises "Same signing key as previous sideloads keeps your save". Android only installs an update signed with the same certificate, and the releases have not used one key throughout. v0.26.0 is signed by `CN=Android Debug` (SHA-256 `73a874e9…`, the box's `~/Android/debug.keystore`), while v0.27.0, v0.27.1, v0.28.0 and v0.28.1 are signed by `CN=Godot, OU=Godot Engine, O=Stichting Godot` (`c18cebfa…`, a Godot-generated debug keystore). Exporting a8e5fe0 on the box today, with Gradle or without, signs with `73a874e9…`. A release cut from the box would therefore not install over v0.28.1, and the updater would end in "App not installed" (or the player would have to uninstall and lose the save). `tools/release_cert.sha256` now pins the certificate of the latest releases. `verify_apk.sh` compares the APK's signer and fails on a mismatch. `ALLOW_NEW_SIGNING_KEY=1` turns the failure into a warning for a deliberate key change, and the pin file should then be updated in the same commit. The digest is public: it is in every APK. Fixing the box's keystore setting is a machine config change outside the repo, so it is left for the owner.

## 142. Expedition Supplies: Max all
Filling a pack meant tapping + up to ten times per row. The Supplies header now has a "Max all" button that sets every supply to the same max its row shows (`CampScreen.supply_max()`: stash count capped by belt size for potions, 1 for Passage, MAX_SUPPLY otherwise), so the button and the rows can never disagree. It is disabled when every row is already at its max (`supplies_all_max()`), the same way + greys out. Covered by `test_max_all_supplies`.

## 143. In-combat Bag as a viewport-clamped modal window
In `CombatScreen`, tapping `Bag` built `HeroPanels.backpack` inline inside `side` between the action toolbar and `log_scroll`. On the Fold cover (484x1188, where the grid already takes 484px on top) and on the Fold inner (928x1080), the paperdoll + 8-slot pack grid + consumable buttons needed ~560px, which crushed `log_scroll` to its minimum and pushed the bottom of the side column past the viewport (`side` has no outer `ScrollContainer`). `_refresh_bag()` now opens a modal overlay (`bag_layer`, Chrome `window`, dimmed backdrop, `Close` button, inner `ScrollContainer` with `UIKit.touch_scroll`) sized by `CombatScreen.bag_rect(vs)`, the same pattern Camp pages and Delve's Backpack panel use. Tapping outside or pressing `Close` dismisses it; equipping an item still closes the window and spends the hero's turn. Added a `combat_bag` screenshot step and `test_combat_bag_fits` in `tests/run_tests.gd`.

## 144. Guild level caps rations and torches per expedition
Packing 10 rations and 10 torches from the first run made both supplies a non-decision, and the Guild's level only changed patrol hours. Now `facilities.guild.pack_cap` = [3, 6, 10] by Guild level. `GameState.supply_cap(k)` is the single rule: belt size for potions, 1 Passage, the Guild cap for rations and torches, 10 otherwise. The Supplies rows, Max all (#142, via `supply_max`) and `start_run` all use it, so a crafted loadout can't exceed it either. Below Guild max the Supplies section says "Rations and torches: pack cap N at Guild LvX. Upgrade Guild to raise (LvY: M)", and the torch tip only fires below the cap.
Values come from the deep campaign sim (`auto_campaign.gd` with SUPPLY_WANT=10, i.e. a player who always packs the max; 4 classes x 2 seeds x 40 runs, main + #26):

| pack cap by Guild level | deaths | extracts | HP/food stops | mean end floor |
|---|---|---|---|---|
| 10/10/10 (before) | 78 | 92 | 102 | 13.8 |
| 4/7/10 | 78 | 91 | 110 | 13.6 |
| **3/6/10** | **58** | **93** | 127 | **14.4** |

With 3/6/10, runs stop for food somewhat more often, but extracts and depth hold and deaths do not rise (the bot stops before starving), so there is no starvation spiral. The sim's Guild reaches Lv2-3 within the first few Sewers runs. The tests that model a late campaign (deep Prison/Caves/City runs with 6-9 rations) now set Guild Lv3.

## 145. Enchanter: Queue all + upgrades shorten running identifications
Two small Enchanter friction points:
1. Queueing several unknown rings/wands after a deep run meant tapping each slot, opening its info popup, and pressing "Queue for identification" one by one. The Identifying header now has a `Queue all (N)` button (`GameState.enqueue_identify_all()`, backed by `GameState.identify_candidates()`) that appends every unqueued unknown item in stash order, chaining `ready_at` back-to-back by `identify_seconds()`. It is disabled when nothing is left to queue.
2. Upgrading the Enchanter (30m -> 15m -> 6m) only affected items queued *after* the upgrade, because each queue entry stores an absolute `ready_at` timestamp. `GameState.upgrade_facility("enchanter")` now calls `rescale_identify(old_sec, new_sec)`: the front item keeps its progress fraction (`remaining * new_sec / old_sec`), and every item behind it chains at `new_sec` each. Covered by `test_identify_queue_all`.

## 146. Non-wrapping chip labels inside HFlowContainer / HBoxContainer
In `CampScreen._patrol_list`, a patrolling hero with pending curios added `UIKit.label("+%d curios" % y._curios, 0.8)` directly to an `HFlowContainer`. `UIKit.label` defaults to `AUTOWRAP_WORD_SMART` with `custom_minimum_size.x = 0`. Inside an `HFlowContainer` (or an `HBoxContainer` when the label does not expand), Godot queries the label's minimum width, gets `0`, and wraps the text one character per line (`+\n1\n\nc\nu\nr\ni\no\ns`), making the patrol card ~330px tall and stretching the Guild window past the 1188px Fold cover viewport. Added `UIKit.chip_label(text, scale, col)` (`AUTOWRAP_OFF`, `SIZE_SHRINK_BEGIN`) and used it in `res_chip` and `_patrol_list` (also singular/plural `+1 curio` / `+2 curios`). Added `UIKit.collapsing_labels(root)` and `test_no_collapsing_labels` in `tests/run_tests.gd` to audit every Camp page.

## 147. Barrier closer to SPD (redo of #22 on the v0.29 combat)
In Shattered Pixel Dungeon, only the Warrior's Broken Seal gives a free per-fight shield (`maxShield = 1 + tier + armor.level`, decaying out of combat), and `ShieldBuff` fades by 1/turn. Here every class started every fight with `base_barrier + heirloom_barrier + armor.barrier + armor_level` that never decayed, which absorbed 24.4% of all post-DR damage across a 40-expedition campaign and let heroes walk through multi-fight floors without HP attrition. Redone on top of v0.29 + #26 (the 8x8 room fix):
- `base_barrier`: Warrior 6 -> 5 (`heirloom_barrier` 3 -> 2, so Lv1 Warrior in Cloth starts at 8 Barrier instead of 10); Mage/Rogue/Huntress 4 -> 3 (start at 4 Barrier in Cloth instead of 5).
- Armor upgrades (`al`) add DR only, not Barrier (`GameState.hero_stats`).
- `barrier_max` is capped at `ht / 2` (`GameState.hero_stats`), and Potion of Shielding is capped at `ht` (`Delve.new_combat`).
- `Combat._decay_barrier()`: when no enemy is adjacent and `time > 3.0` (so the 3-tick opening approach across the room keeps its full shield), `hero.barrier` drops by 1 at the end of the hero's turn.
Deep campaign sim (`tools/auto_campaign.gd`, 4 classes x 2 seeds x 40 runs, on v0.29 + #26): absorbed share 24.4% -> 18.8%, total deaths 75 -> 65 (fewer overconfident deep pushes on inflated Barrier), extractions 106 -> 111, fresh-save first-try Goo wins 32/100 -> 24/100 (closer to the #131 ~25% target). Covered by `test_barrier_spd`.

## 148. Bat drain like SPD (redo of #25 on the v0.29 combat)
SPD `Bat.attackProc` heals `damage - 4`, so armor that blunts a bite also blunts the heal. Here a bat healed a flat 2 on any bite that got through, even a 1-damage bite into heavy armor, so a geared hero at the Caves entry could not out-damage two bats. Our bat bites at about half SPD's damage, twice as often, so the offset is halved to `drain_over: 2` (heal = dealt - 2). On v0.29 + #26 the problem still reproduces: bat sets were the top Caves-entry killer (11 of the 13 f11 deaths). Deep campaign (4 classes x 2 seeds x 40 runs): deaths involving bats 11 -> 7, total deaths 75 -> 74; the f11 deaths move to brute+brute (5 -> 10), which is a separate Caves-entry wall. `test_bat_drain` checks the heal at hero DR 0 and DR 4.

## 149. Blind targeting through tall grass (SPD Ballistica)
v0.29 made tall grass and closed doors block sight, and `can_bolt` required sight, so a foe one tile into grass could not be shot at all and Huntress/Mage had to walk into melee. In SPD you aim at a cell. `Ballistica.PROJECTILE` (thrown/bow) stops at the target, the first char, or solid terrain; `MAGIC_BOLT` (wands) ignores the target cell and flies on. HIGH_GRASS is LOS_BLOCKING but not SOLID; DOOR is SOLID. Now:
- `can_bolt(tile)`: any non-wall tile within BOLT_RANGE. The Spirit Bow still refuses range 1, and also refuses a shot whose first body would be adjacent.
- `bolt_impact(tile)` / `bolt_victim(tile)` walk the Bresenham line: the first unit is hit; a wall or closed door stops the shot on the tile before it; arrows stop at the aimed tile; wand bolts continue to range. Grass does not stop shots and is not trampled.
- A shot with no victim logs "The shot hits nothing." and spends the turn (and a wand charge). Burning bolts still ignite grass where they land.
- Input: the bow fires on any distant tap. A wand needs Bolt mode for an empty tile, so a mis-tap never spends a charge.
- Sight memory: when it is the hero's turn, every enemy in the hero's sight records `last_seen = [x, y]` (plain array, so it saves and restores with the fight).
- CombatBot only takes aimed shots at foes it can see whose line is clear of other bodies (`_can_shoot`; before, it could shoot through bodies). With nothing in sight and nothing adjacent, it shoots at an unseen foe's `last_seen`: up to 2 arrows per sighting, or 1 wand charge while 2+ remain.
Covered by `test_blind_shots` (hidden rat in grass hit, empty tile wastes the shot, the first body takes it, a closed door stops it, a wand bolt carries past, last_seen survives save/load, the bot's blind shot).

## 150. `verify_apk.sh` finds Java the way the Godot export does
`apksigner` is a Java program, but Godot's Android export finds Java through its own editor setting (`export/android/java_sdk_path`), not `PATH`. A machine can export an APK and still have no `java` on `PATH`; the playtest box is one (`/workspace/tools/jdk17` lives only in `editor_settings-4.7.tres`). Before #141 that was hidden: `"$BT/apksigner" verify "$APK" && echo "ok apksigner"` is an `&&` list, which `set -e` does not stop on, so a failed signature check (or "java: not found") was skipped silently and the script still printed `VERIFY: PASS` (the a8e5fe0 playtest's `verify-apk` log shows exactly this). Since #141 the certificate check's command substitution fails under `pipefail`, so `verify_apk.sh` and `build.sh` now stop with only `exec: java: not found` and exit 127, with no hint about what to fix. Now `verify_apk.sh`:
- uses `java` from `PATH` if there is one, else `$JAVA_HOME`, else `export/android/java_sdk_path` from the newest `editor_settings-4*.tres` (Linux `~/.config/godot`, macOS `~/Library/Application Support/Godot`, Windows `%APPDATA%/Godot`), and prints `ok java from …` when it had to look;
- otherwise fails with `JAVA NOT FOUND` and the three ways to fix it;
- fails if `apksigner verify` fails (no more silent skip), and fails clearly if the signer digest can't be read, instead of printing "signed by  but …".
The certificate pin itself (#141) is unchanged. Covered by `test_verify_apk_java`, which runs the script against a stub SDK, a stub JDK and a stub editor settings file.

## 150. Camp maxes only after every hero beats every boss
Facility caps were raised by 1 Scroll of Upgrade each, so maxing the camp (4 facilities x 2 cap raises) took 8 Scrolls. Supply: `record_boss_kill` grants 1 Scroll per hero per boss on the first kill only, 4 heroes x 5 bosses (Goo, Tengu, DM-300, Dwarf King, Yog) = 20, plus the Jailbreak and Full Roster milestones (+1 each) = **22**. Owed Scrolls (lost on death, returned by `grant_owed_sou` on the next boss kill) are the same Scrolls coming back, not new supply, so they are not counted. Gold and materials were never the gate: in the v0.30 deep sim heroes end campaigns with 800-4500 gold, while the Lv3 costs are at most 200 gold / 20 ore / 16 seeds / 6 resin.
New `cap_scrolls` per facility in `data/facilities.json`, cost to raise cap C -> C+1 = `cap_scrolls[C-1]`:
| Facility | Cap 1->2 | Cap 2->3 | Total |
|---|---|---|---|
| Blacksmith | 1 | 5 | 6 |
| Guild Hall | 1 | 5 | 6 |
| Alchemy Pot | 1 | 4 | 5 |
| Enchanter's Desk | 1 | 4 | 5 |
| **All** | 4 | 18 | **22** (was 8) |
The first Goo kill still buys a Lv2 cap; all four Lv2 caps cost 4 Scrolls (one hero through Dwarf King, or a couple of heroes past Goo). The Lv3 caps need 18 more, so the last one lands only with the final first kills (Yog on the last hero). Blacksmith and Guild are the steeper 5s because they gate gear +3 and the 10-supply pack. `apply_sou` spends all the Scrolls at once or none. `GameState.total_sou_supply()` / `total_sou_to_max()` compute both sides from data, and `test_camp_sou_budget` asserts cost >= supply (and == supply, so it stays reachable); adding a boss, hero or Scroll milestone without raising `cap_scrolls` fails the test. Existing saves keep caps they already raised.
Estimate from the v0.30 deep sim (one hero, 40 expeditions per campaign, 8 campaigns): a hero earns 3-5 Scrolls (2-4 boss first kills + Jailbreak) and no sim hero beat Yog. Before: 5 Scrolls = 5 of 8 caps by run 12-34, and two heroes' campaigns (~60-80 expeditions) maxed the camp. After: the same 5 Scrolls buy the four Lv2 caps plus 1 toward a Lv3; two heroes (~9-10 Scrolls) get one Lv3 facility; maxing needs all 20 boss first kills, i.e. 160+ expeditions at sim pace.

## 151. Trapped Vault: special-room fights can use their own map
Special-room fights (`"fight"` options) always used a random ordinary room, so a room's theme never reached the battlefield. A fight option may now carry `"room"`: its own map in rooms.json legend (`Delve.special_fight_event`, used by DelveScreen; without `room` it behaves exactly as before). First user: `trap_vault` (all biomes) - fight this floor's encounter on an 8x8 with 2 visible and 4 hidden traps from the biome pool, for an unknown ring + 20 gold; a Rogue disarms it for the same loot; or leave. The map has a real doorway so snake encounters still get their threshold (the snake rule in `combat_event`). No combat numbers change.
Iteration in the deep campaign sim (4 classes x 2 seeds x 40 runs): a first doorless map with 12 traps killed 43 of 121 challengers (36%; snakes in the open plus traps). The shipped map: 143 fights, 5 deaths (3.5%, close to the Animated Statue's ~2%), 72 free Rogue disarms, seen ~200 times per campaign set. 3 of the 5 deaths were Huntress on Sewers floor 4 vs crab+snake+snake, the same spot that is already the top non-boss killer. Covered by `test_trap_vault`.

## 152. Chained Prisoner (Prison special room)
SPD's Prison is full of captives, but no special room used that theme. `prisoner` (Prison only) offers: unlock the shackles with 1 Iron Key (ration + 10 gold), fight the jailers (a guard + a thief, the floor-7+ Prison pair, in a normal Prison room) for an unknown scroll + ration + 15 gold, or leave. Pure data in `events.json`; no combat numbers change.
Deep campaign sim (4 classes x 2 seeds x 40 runs, Auto policy, plus a pass that forces the fight): seen 45 times per campaign set, 71 jailer fights, 0 deaths, 4% mean HP lost (max 80%). The key option is what the Auto policy takes when it has a key. Covered by `test_prisoner`.

## 153. Abandoned Shop (gold sink inside a run)
Gold found during a run had no use until extraction, and SPD has shops on the way down. `abandoned_shop` (all biomes) lets the hero spend gold carried in the pack this run: ration 20, torch 15, unknown potion 35, or leave. Stash gold is not usable (same rule as every other run cost: `Delve.pay` only reaches run supplies, the pack, and stash keys). Bought rations/torches go straight to supplies (`Delve.reward`). Pack gold is lost on death anyway, so this is a real choice: bank it or turn it into survival now. Pure data.
Deep campaign sim (4 classes x 2 seeds x 40 runs): seen 197 times; the Auto policy (which buys the first affordable line, usually a ration) bought something on every visit. No deaths attributable. Covered by `test_abandoned_shop`.

## 154. Gnoll Camp mini-boss room + floor gate for special rooms
Sewers had no optional 'big fight for big loot' beyond the single statue. `gnoll_camp` (Sewers and Prison) is a three-gnoll raid for an unknown wand + 25 gold + 3 iron ore, or sneak the stash for 10 torch (10 gold + 1 ore), or leave. Three bodies at once is too much for floor 1-2, so special rooms gain an optional `min_floor` (`Delve._for_biome`, also used by door cards); the camp uses `min_floor: 3`. Existing entries have no `min_floor` and are unaffected. No combat numbers change.
Deep campaign sim (4 classes x 2 seeds x 40 runs, plus a pass that forces the raid): 140 raids on floors 3-10, 0 deaths, 2% mean HP lost (max 74%). It is a safe loot room on today's combat; if the combat rework makes gnolls tougher, re-check it. Covered by `test_gnoll_camp`.

## 155. Vanilla SPD enemy behaviours
Most mobs were stat blocks with SPD's names; their signature tricks were missing. Compared every `data/mobs.json` entry with `actors/mobs/*.java` in 00-Evan/shattered-pixel-dungeon and added the ones that fit a turn-based 8-12 tile room. Base HT, damage and DR are unchanged; each behaviour has its own key.
- **Shots need a line** (`Combat.mob_can_shoot`, SPD Ballistica PROJECTILE): gnoll spears, DM-100/shaman/warlock zaps and spinner webs need sight (walls, closed doors, tall grass block it, matching #149) and stop at the first body. The Evil Eye's beam ignores bodies.
- **Casters hold range** (`holds_range`: shaman, warlock, Bright Fist): with a clear shot at range 2-4 they stay put and reload instead of walking into melee, like SPD's `canAttack` via bolt. Tried on gnolls and DM-100s too: Sewers floor 1-2 deaths at doors to gnoll pairs and Prison DM-100 pairs (10 deaths) turned the Warrior's early game into a wall (deep-sim deaths 56 -> 125, one Warrior seed never left the Sewers), so those two keep closing in. Vanilla gnolls are melee anyway (the thrower is the Trickster).
- **DM-100** lightning x1.5 when you stand in water (`zap_water`).
- **Shaman colours** (`zap_debuffs`, chosen by uid): red = Weakness (melee x0.67), blue = Vulnerable (damage taken x1.33), 3 turns. Purple (Hex) is skipped: we have no accuracy roll for it to affect. **Warlock** shadow bolt = Weakness.
- **Evil Eye** (`zap_beam`): the telegraph covers the whole line through you to range 6 and the eye charges while it is up (SPD DisintegrationRay); step sideways.
- **Spinner** (`ability: web`): every 4 actions spits a web at range 2-4 (red tile); hit = rooted 2 turns (you can attack, a step spends the turn).
- **Scorpio** bite cripples 2 turns (steps cost 2 ticks). Holding range was tried and dropped: cripple + spit from range killed a Lv18 tier-5 Warrior in 8 of 32 Halls fights.
- **Monk** every 3rd hit knocks your weapon aside (Weakness 2 turns), our version of SPD's disarm.
- **Succubus** (`ability: blink`): once per fight blinks next to a hero it sees at range 3+, only if no other enemy is adjacent. Unlimited / stacked blinks let two succubi gank the Halls test Warrior (2 losses).
- **Ripper Demon** (`ability: leap`): telegraphed leap onto your tile from range 2-4 (its melee damage), then lands there; cooldown 4.
- **Golem** (`ability: teleport`): every 6 actions pulls a hero it sees at range 3+ to its side, so its slowness is no longer a free kite.
- Already in place and left alone: crab/bat/monk/ripper speed, bat drain, thief steal-and-flee, guard chain, ghoul revive, skeleton bone burst, brute enrage, Goo/Tengu/DM-300/King/Yog kits.
- Skipped: Necromancer, Fire Elemental, Swarm of Flies (not in the game; new mobs are content, not behaviour), Succubus charm (would need charm handling in Auto Battle and the UI), Brute "dies raging" (our below-half enrage is the stand-in), Golem self-teleport.
- Hero debuffs live in `hero.debuffs[id] = expiry time` (saved with the fight). They only show in the log for now; status icons are a polish item.

Deep campaign sim (`balrun.sh`, 4 classes x 2 seeds x 40 runs, plus 25-seed Goo first try):

| | v0.30 (9687597) | #155 |
|---|---|---|
| total deaths | 56 | 70 |
| Sewers / Prison / Caves / City / Halls deaths | 35 / 1 / 7 / 9 / 4 | 38 / 1 / 9 / 14 / 8 |
| deaths W / M / R / H | 13 / 25 / 7 / 11 | 13 / 33 / 10 / 14 |
| Goo first try | 24% | 25% |
| top killers (non-boss) | crab+snake+snake 15, golem pair 6 | crab+snake+snake 15, succubus pair 5 |

Covered by `test_vanilla_mobs`.

## 156. Vanilla wands for the Mage's Staff
SPD has 13 wands; we had 3. Wands here are only bolts cast through the Mage's Staff (one imbued at a time), so each new wand is a bolt with a lower base damage than Magic Missile (5) plus a vanilla-style rider, applied in `Combat._wand_effects` after the hit: Frost (3, target `next` +1 tick, +0.5 from Lv 15), Corrosion (2, +3 poison, +1 per 6 hero levels), Blast Wave (3, `knockback` 1 tile, 2 from Lv 15; bosses immune), Disintegration (4, also hits every other enemy on the bolt line, walls still stop it), Transfusion (3, heals the caster 2, +1 per 10 levels), Prismatic Light (4, `_reveal` traps r2; SPD's blind is skipped because mob sight is not modelled per-unit), Regrowth (1, roots 2 ticks, grows tall grass on open floor around the impact). They are sidegrades, not upgrades: lower raw damage keeps the game from getting easier, and bolt damage/charges still scale with hero level as before. All join the `item_unknown: wand` loot pool; there is no wand shop, so loot is the only source. The bot needs no new logic (same `hero_bolt` call; riders apply automatically). Skipped: Corruption, Living Earth, Warding (need ally units).
Sim (4 classes x 2 seeds x 40 runs) is byte-identical to the v0.30 baseline (56 deaths) because the campaign bot never imbues an unidentified loot wand. Forcing each wand on the Mage (mage-only, 2 seeds x 40 runs; Magic Missile baseline 25 deaths): Blast Wave 21, Corrosion 19, Regrowth 31, Prismatic Light 35, Frost 39, Transfusion 39, Disintegration 38. No wand trivializes the Mage; Corrosion and Blast Wave are the only ones that help it. Covered by `test_vanilla_wands`.

## 157. Vanilla rings
SPD has 12 rings; we had 5. Added as flat, always-on bonuses read in `GameState.hero_stats` (same model as #80): Furor `delay_mult 0.85` (SPD: attack speed), Haste `move_cost 0.85` (hero step cost in `Combat.hero_tap`; SPD: movement speed), Sharpshooting `bolt_bonus +1` (bow and staff bolts), Elements `elem_resist 0.67` (multiplies `hit_hero` damage when `pierce` is set, which is how fire, lightning, zaps and piercing traps arrive), Force `force_bonus +2` while the weapon is tier 1 (SPD: unarmed/weak-weapon damage). Values are small on purpose so a ring never outweighs a tier of gear. All join the `item_unknown: ring` pool. Skipped: Accuracy (combat is deterministic; the only miss is snake evasion, and the user wants the crab+snake threat kept), Arcana (no enchantments/glyphs yet; add with them).
Sim, 4 classes x 2 seeds x 40 runs vs v0.30 (`bal_v030`): deaths 56 -> 75 (warrior 13 -> 12, mage 25 -> 34, rogue 7 -> 9, huntress 11 -> 20), median end gold 2004 -> 690, Goo first try unchanged at 24%. The game gets harder, mostly because a bigger pool makes Tenacity/Might/Wealth rarer; no new ring made a class easier. Covered by `test_vanilla_rings`.

## 158. Ring, wand and artifact levels gated by the Enchanter's Desk
User request: these items should start weak and need Camp investment before they can be levelled or repaired. Design:
- **One facility.** The Enchanter's Desk ("wandmaker" NPC) owns rings, wands and artifacts. A new artifact facility would need a new Camp building, NPC and scene slot for a single item type, so artifacts use the Desk's top level instead. Item level cap = `enchanter level - 1`, so a fresh camp can't level them at all. This works with either Desk max (3 now, more if #40 raises it); with #40 the Desk's own Scroll gate makes high caps cost the endgame Scrolls.
- **Rings and the staff wand** gain levels for `1 Scroll of Upgrade + 3N Arcane Resin + 50N^2 gold` (N = next level). Spending a Scroll here competes with the facility caps from #40, which is the point. Per-level effects come from an item's `per_level` table (`GameState.trinket_bonus`; fractional steps round down, e.g. Evasion +1 DR per 2 levels). The imbued wand's level lives on the hero (`wand_lvl`) and moves with it when re-imbued: +1 bolt dmg per level, +1 charge per 2.
- **Artifacts** never take Scrolls (as in SPD). They gain 1 XP per won fight while equipped and level at `8 x next level` XP, up to the same Desk cap (`GameState.charge_artifact`, called from `Delve` on a win).
- **Cracking/repair.** Equipped rings/artifacts already crack on death. An imbued wand with levels now cracks too: its levels go dormant and the base bolt keeps working, so the Mage is never disarmed. Repair needs Desk Lv2 for rings/wands (`2 + lvl` resin) and Lv3 for artifacts (`4 + 2*lvl` resin, `40 + 20*lvl` gold). `can_repair` carries the gate; Repair all skips items whose gate isn't met; the free Patch up (#104) only covers weapons and armor, since a ring isn't needed to keep playing.
- **Weaker +0 items.** Tenacity +2 -> +1 Barrier, Wealth x1.3 -> x1.15, Energy +4 -> +2 HP, Chalice +15 -> +6 HP, Horn hunger x0.6 -> x0.8. Might/Evasion stay at +1 (can't go lower). These are item values, not base combat stats.
- **UI.** The Enchanter page gets an "Attune" section: the staff wand row (Upgrade/Repair) and a grid of known rings, wands and cracked artifacts that opens the same gear popup the Forge uses.
Sim (4 classes x 2 seeds x 40 runs) vs v0.30: deaths 56 -> 71 (warrior 13 -> 14, mage 25 -> 33, rogue 7 -> 9, huntress 11 -> 15), median end gold 2004 -> 1103, Goo first try 24% unchanged. The campaign bot doesn't level rings, so this measures the weaker +0 items and the repair gate. Covered by `test_trinket_upgrades` plus the updated ring repair and chalice tests. #46 (wands) and #47 (rings) work without this PR; their new items simply have no `per_level` table yet, so levels don't boost them until one is added.

## 159. Vanilla artifacts
Built on #158 (branched from `vanilla/trinket-upgrades`, since it needs `per_level`, `trinket_bonus_f` and `charge_artifact`). SPD artifacts are active items with charge; the tactics format has no artifact button, so each becomes a passive or fight-start effect with a small +0 value that grows per level: Cape of Thorns (`thorns` 1 + 0.5/lvl, dealt back to a melee attacker after its hit, ignores DR; SPD reflects part of the damage), Ethereal Chains (`chain_pull`: at fight start the nearest non-boss 3+ tiles away is dragged adjacent; +0.5 tick hold per level; SPD pulls with a chain), Timekeeper's Hourglass (`freeze_start` 0.5 + 0.25/lvl ticks on non-bosses at fight start; SPD stops time), Sandals of Nature (`grass_root` 0.5 + 0.25/lvl ticks on enemies next to you when you step into tall grass; SPD roots from plants), Master Thieves' Armband (`loot_mult` 1.1 + 0.05/lvl on fight gold, multiplied with Wealth; SPD steals from shops/foes). Ethereal Chains is a double-edged pick: it pulls a ranged foe into melee, which helps melee heroes and hurts the Huntress. They join the boss artifact drop pool via `type: artifact`. Skipped: Dried Rose (ally), Alchemist's Toolkit / Unstable Spellbook (need in-fight alchemy or scroll casting), Lloyd's Beacon (free extraction would undo the boss-campfire extraction rule).
Sim (4 classes x 2 seeds x 40 runs) vs #48 (`bal_trinket`): deaths 71 -> 70 (warrior 14 -> 14, mage 33 -> 30, rogue 9 -> 10, huntress 15 -> 16), median end gold 1103 -> 1845, Goo first try 24% unchanged; Warrior goes deeper (14/13 -> 19/20). Still harder than v0.30 (56 deaths). Covered by `test_vanilla_artifacts`.

## 160. Per-level values for the #157 rings
Stacked on #47 (rings) and #48 (Enchanter levels). The new rings get `per_level` tables like the old ones: Furor `delay_mult -0.05`/level (floor x0.6), Haste `move_cost -0.05`/level (floor 0.6 tick), Elements `elem_resist -0.07`/level (floor x0.4), Force `+1` dmg/level with tier-1 weapons, Sharpshooting `+0.5` (so +1 every 2 levels). Steps are about half of each ring's +0 value so a Scroll spent here is worth roughly as much as one on Might (+1 dmg). The floors stop a deep-cap Desk (if #40 raises its max) from turning speed rings into double turns. The campaign bot doesn't level rings, so the sim can't see this change; covered by `test_ring_levels`.

## 161. Vanilla potions and scrolls (next-fight model)
SPD potions and scrolls act on the current dungeon level. Here they're used from the backpack between fights (`GameState.delve_use_pack`), so they follow Potion of Shielding's model: they queue a `run.next_fx` entry that `Delve.new_combat` hands to `Combat.apply_fx` once at the start of the next fight. Added potions: Invisibility (`hidden_until` 3), Haste (enemies +1.5 ticks), Levitation (`_trigger` skips the hero), and three bad potions that punish blind drinking like SPD's harmful ones: Frost (hero +1.5 ticks), Paralytic Gas (+2.5 ticks), Liquid Flame (-15% max HP now). Added scrolls: Recharging (+1 staff/cloak charge), Lullaby (non-bosses +2 ticks), Retribution (each non-boss takes max(2, missing HP / 2), ignoring DR), Terror (non-bosses knocked back a tile and +1 tick), Transmutation (first backpack ring/wand becomes another of its type). Bosses resist the crowd-control effects. Unknown looks grow to 9 colours and 9 runes (SPD's remaining Charcoal/Silver/Ivory, Naudiz/Odal/Tiwaz) so no two share an icon. Skipped: Mind Vision (sight is per-fight and short-range, so no real effect), Purity (no lingering gas between fights), Remove Curse (no curses yet), Mirror Image (needs allies), Rage (aggro is already total in small rooms), and the exotics (they need Alchemy recipes that consume a base potion/scroll; the 2 we have, Shielding and Passage, stay as they are).
Sim: the default campaign bot never uses unknown consumables, so 4 classes x 2 seeds x 40 runs is identical to v0.30 (56 deaths). With the bot drinking/reading every unknown blind (`USE_PACK=1`, harness only): v0.30 69 deaths -> 72, median end gold 2452 -> 1714. Tuning: a first pass (Frost 1.5, Paralytic 2.5, Flame 20%) gave 97 deaths; a soft pass (1.0 / 2.0 / 15%) gave 61, easier than baseline; the shipped values (1.5 / 2.5 / 15%) land slightly harder. Covered by `test_vanilla_consumables`.

## 162. Polish backlog in docs/POLISH.md
Visual and feel polish is batched for the end, after combat and balance settle, so it isn't redone. Polish that changes how the game plays (broken screen, unreadable text, confusing control) is still fixed right away in small PRs. Everything else goes into `docs/POLISH.md`, grouped by screen with a priority (P1 before a public build, P2 next pass, P3 nice to have) and an effort (S/M/L). Content blocked on the combat rework (thrown weapons and bombs, exotics, wand retuning, enchantments) is listed there in a separate deferred section. Agents append to it when a PR or playtest report notes a polish item.

## 163. SURPRISE status line only for a hittable Surprise
`Combat.surprise_ready()` is true when any living foe can't see the hero, so the fight status line said "next attack is a SURPRISE" at the start of most fights (a foe behind a door or in grass), on guided-fight step 1, and with nothing in reach. New `Combat.surprise_now()` is true only when a foe that `surprise_against` would surprise is adjacent (melee), or, for the Spirit Bow, is the first body on a legal shot (`can_bolt` + `bolt_victim`). Wand bolts are magic and never surprise, so they don't count. The status line uses `surprise_now()`. The one-time Surprise tutorial tip keeps `surprise_ready()`, because it teaches the idea of breaking line of sight, and the #139 guided-fight guard still applies. Covered by `test_surprise_now`.

## 164. Artifact stats in camp item details
POLISH.md item 8: the camp popups showed only an artifact's description, so the effect of levels (#158/#159) was invisible. `Codex.artifact_lines(g, cap)` builds one line per artifact stat (Max HP, Search radius, Hunger, Thorns, Opening freeze, Grass root, Chain hold, Fight gold) from the item's base value plus `per_level` x level. It uses the same rounding as `GameState` (`floor` for integer stats, percent for multipliers) and adds the step ("+5% per level", "+1 every 2 levels"). A last line shows "Level +L / cap +C - x of y won fights to +L+1", or that the Desk caps it. `CampScreen.gear_lines` appends these lines, and `gear_stats` adds the same values so the compare window lines up artifacts side by side. Stacked on #49. Covered by `test_artifact_lines`.

## 165. Auto Battle cashes a Surprise before a normal swing
A Surprise is `dmg * surprise_mult`, ignores DR, and knocks back, but CombatBot cleared every adjacent non-snake before it would take one, and it only bothered when the foe was a snake, had DR, or would fall into a chasm. A rat standing in the open was hit first, and the foe who had lost sight of the hero kept the window until they walked into view. Hint and Auto now take that hit (or a Spirit Bow shot, which can surprise; a wand bolt cannot) before a normal swing, a cloak, or a snake door-dance. Dodge, a chasm shove, and a slam of 3+ foes the slam can actually hurt still come first — a slam is not a Surprise, so snakes no longer count toward that crowd. Covered by `test_bot_surprise_priority`.

## 166. Camp dock: Delve under the destination, patrols underneath
The wide dock used to pin Delve at the foot and let patrol cards fill the middle (#124). On a short window the first card was clipped down to its Recall button (name, timer and loot gone) and the disabled reason ("hero is on patrol") fell off the bottom. Delve now sits directly under the biome chips, with its reason, and the patrol list scrolls in the space below. A patrolling card puts the name and time on the same row as Recall, then the bar and the loot chips, so the info stays attached to the button. The cover dock is unchanged: no patrol list, recall still lives at the Guild. Covered by `test_camp_dock`.

## 167. UI smoke renders every special-room card
v0.40.0 crashed mid-delve on Trapped Vault, Chained Prisoner, Abandoned Shop and Gnoll Camp: `_card_special` read `sp.text`, which those four rooms lacked (fixed on main in e6a206d). The data test only covered `DB.specials` fields, and `tests/ui_smoke.gd` only met specials by chance and always tapped the last option. The smoke test now sets each `DB.specials` entry as the pending card, calls `_show_card()`, and checks that the card and its first option button render, so any new room that the UI can't draw fails the smoke test. Checked against v0.40.0 data, where it hits the script error.

## 168. Cost rows never stack one material per line
Playtest of e6a206d: the Enchanter's Attune row (staff wand) showed its Scroll / resin / gold cost as a column at the right edge, and the last number was clipped at the panel edge (the gold "200" on the Fold inner screen, "50" on the cover). `CampScreen.cost_row` is an HFlowContainer, whose minimum width is its widest chip, so inside an HBoxContainer without `SIZE_EXPAND` it gets that width and wraps every chip. The same layout hit the Forge's "Cracked: N" Repair all row (ore + resin + gold once rings or artifacts are cracked) and the quantity picker's "Total:" in every Forge/Desk upgrade popup. Now `cost_row` expands by default (no effect inside a VBox), the quantity picker's cost host expands, and the staff wand's cost sits on its own line under the wand name, so a long name doesn't wrap into half the row. `UIKit.collapsing_flows(root)` finds a flow that would stack (a flow, or an HBox around it, sitting in an HBox without `SIZE_EXPAND`); `test_no_stacked_cost_rows` runs it on every Camp page plus the weapon and ring upgrade popups at the Fold cover and inner sizes (it found exactly those 4 spots on main).

## 169. Abandoning a run owes its Scrolls of Upgrade instead of destroying them
Playtest of e6a206d: `end_run("abandon")` dropped the whole pack, Scrolls of Upgrade included, while a death already owed them (#103). Since #150 the Camp needs exactly every Scroll the game grants (22 = 22, `test_camp_sou_budget`), and each Scroll is a one-time drop (first kill of a boss per hero, two milestones), so one abandon after a boss kill (descend into the next biome, get hurt, Menu > Abandon) made a fully upgraded Camp impossible for the rest of the save. In the deep campaign sim (4 classes x 2 seeds x 40 runs) 4 Scrolls were destroyed this way. Abandon now uses the same `GameState._owe_pack_sou()` as death: the Scrolls are added to `owed_sou` and return to the Camp stash on the next boss kill by any hero, with the same log line. The rest of the pack is still lost, so abandoning is not a free extraction; owing (rather than banking) the Scrolls keeps abandon from being a way to bank a boss Scroll without reaching the campfire. The abandon confirm says so when the pack holds Scrolls (`DelveScreen.abandon_text`). Covered by `test_owed_sou`.

## 170. Trinket levels cost no Scrolls; artifact repair at Desk Lv2
The camp rebalance (#150) makes the 22 Scrolls of Upgrade the game grants exactly the cost of maxing the camp, but #158 also charged 1 Scroll for every ring or staff-wand level, so the two systems competed for the same fixed supply and the camp could never be maxed by anyone who levelled a ring. `trinket_step_cost(N)` is now 4N Arcane Resin + 75N² gold, with no Scroll (was 3N resin + 50N² gold + 1 Scroll), and the Desk level still sets the cap (Desk Lv - 1). The higher resin and gold keep it a real investment. Artifact repair needs Desk Lv2 like rings and wands (was Lv3), so a cracked artifact isn't stuck behind the Desk's steep Lv3 Scroll cost. `test_trinket_upgrades` checks the new costs and the Lv2 artifact repair, and `test_camp_sou_budget` checks that no trinket level spends a Scroll.

## 171. Identify bars fill from when each item was queued
The first whole-wait bars anchored every row on the current front item's slot (`front.ready_at - identify_seconds()`). That anchor moves when the front item finishes, so each waiting bar dropped from about 50% (or 33%) back to 0 in the same second, every time. Each `id_queue` entry now stores `queued_at`, and `identify_progress` fills from it to the entry's own `ready_at`. A bar starts empty when queued, only moves forward, and still ends exactly at the item's finish. `rescale_identify` (Enchanter upgrade) moves `queued_at` with `ready_at`, so every bar keeps its fill and only the rest gets faster. Saves from before this load with today's front-slot anchor frozen as `queued_at`. Covered in `test_identify_queue_all` (the "never jump back" check fails on the old anchor: 0.50/0.33 -> 0.00/0.00).

## 172. Snakes: magic always hits, bows after one slip
Requested by the user: ranged heroes must be able to kill snakes. In SPD magic never misses, so wand and staff bolts (and other magic damage) now always hit a snake. Spirit Bow arrows are physical, so a snake slips the first arrow of each fight (`slipped_shot` on the mob), then every later arrow connects. This keeps a small cost for the Huntress without making snakes a wall. Melee is unchanged: only a Surprise connects. Considered and rejected: a dodge on the first arrow every turn, which with one shot per turn would block every arrow.

## 173. Enchanter's Desk uses the same section tabs as the Forge and Guild
The Desk stacked scribe recipes, the identify queue, and attune on one page. Rings, wands and artifacts landing on the Desk (#158) made that scroll long. It now uses `_switcher` (Scribe / Identify / Attune). Identify's count is queued items plus unknowns still waiting to be queued; Attune's count is cracked trinkets, including a cracked staff wand. The identify timer still rebuilds the window once a second, and only while that tab is open. `test_enchanter_tabs`.

## 174. Equipped gear is labeled with the hero's name
The stash marked a worn item with that hero's initial (W, M, R, H) in the corner, and the Forge upgrade grid did not say who had a piece at all: its green border means the upgrade is affordable, and red means cracked. Both now draw a colored name plate along the bottom of the slot (Warrior orange, Mage blue, Rogue purple, Huntress yellow). The full class name is used when it fits; a short form (War, Hunt) only when the column is narrower than the word. Gear grids use slightly wider columns than material grids so all four names fit on a phone. A ring type worn by more than one hero shows each hero's face on that one stack, since two names do not fit. The Forge border is unchanged. The Desk's Attune grid uses the same plate. Covered by `test_equipped_owner_marks`.

## 175. Vendor materials bar and Upgrade fold
Forge and Guild already showed a live materials strip inside the scrolling facility header (#97); Alchemy and the Desk had none, and every vendor opened with the full level-slot card. All four vendor windows now pin that strip under the title (outside the scroller): Forge keeps iron ore / dark gold / gold / resin / Scrolls of Upgrade; Guild keeps gold / dew / seeds / ore; Alchemy shows seeds / dew / gold / Scrolls; Enchanter shows resin / gold / Scrolls. The facility level block (slots, Unlock, next-level cost) collapses behind a full-width Upgrade tab that shows `Lv n / max`, the blocking `(cap n)` note, and `!` when an upgrade is affordable. It starts closed; open/closed is remembered per facility for the session (`fac_open`), so Unlock and level-up rebuilds leave it open. Craft, brew, scribe and supplies stay in the scroll under the fold. Covered by `test_vendor_mats_fold` (and `test_facility_cap` opens the fold first).

## 179. Camp and delve scene art: whole-pixel scale, SPD fire and light, doors that match their state
Scene art only; window chrome is unchanged. Shared effects live in `scripts/ui/scene_fx.gd` (stateless, a few dozen quads, no per-frame allocation). **Delve corridor:** tiles are drawn at a whole multiple of 16 px (`pk()`) and sprites at a rounded ~1.5x of that (`sk()`; bosses ~1.35x more), so every pixel is square on the Fold and PC. Wall doors use SPD's raised door tiles and are always closed unless something stands in them (the combat door rule proposed in PR #62): passing side rooms are closed doors; a door card shows door A and door B two tiles apart, each locked only if that door costs a key; a special room shows its closed door with the room's icon floating above. The crystal door for a cleared floor is replaced by SPD's down stairs on the floor. The idle biome mobs that stood by the wall (they never fought, so they read as a bug) and the random item props (seeds, holder outlines, "something", chests, ore) are removed; only bones remain, and nothing decorative is drawn in the 6 columns where an encounter stands. Combat foes stand one per column across two floor rows facing the hero, use each sprite's own animation set (the King and the ghoul minion animate again: anims were looked up by mob id instead of sprite), and run in over 0.45 s when the encounter appears. Tall grass clumps on the near row draw SPD's high grass over the hero's legs and sway one pixel. Torch light darkens the whole scene to 78% away from the hero with no visible ring; a lit torch widens it and adds a warm glow. A new floor fades in from black; pickups add a pixel spark burst. A boss campfire event shows a fire. **Camp:** the campfire is SPD's embers tile under FlameParticle-style flames (yellow to orange to red, shrinking and rising), sparks and smoke, with a flickering warm glow; the clearing darkens to night away from the fire (the sky and name plates are drawn outside the darkness so they stay readable); SPD grass tufts sway around the clearing away from the path and NPCs; barrels stand by the Forge and the Guild. Redraw rates are unchanged (camp 15 fps, delve 60 fps). Water puddles were left out because SPD's water needs edge stitching (POLISH #34).

## 180. Every special room has its own delve scene
When a special-room card opens, the corridor floor ahead of the room's (closed) door shows a small scene built only from SPD art: level tiles of the current biome, `terrain_features.png` (traps, plants, crystals, rubble, barrels, bars, tables), animated biome water (`waterN.png`, drifting), mob and item sprites, and the #179 particles plus a new `SceneFX.twinkle` sparkle. One table, `DelveScene.ROOM_SCENES`, covers all 22 specials: Piranha Pool (water with SPD's submerged piranhas, one leaping every few seconds), Sacrificial Fire (pedestal + fire), Animated Statue (statue on a pedestal), Barricade, Overgrown Garden (grass and plants), Trapped Corridor (visible traps), Suspicious Wall (rubble + sparkle on the wall), Locked Cell (bars + thief + key), Guard Armory, Crystal Vein, Crystal Vault (special floor + crystal chest), Ancient Library (bookshelves + scrolls), Wells of Health and Awareness (SPD well tile over moving water, red or blue sparkle), Alchemy Laboratory (pot, potions, seed), Collapsed Treasury, Forgotten Shrine (chalice on an altar), Larder, Trapped Vault, Chained Prisoner (bars + guard + key), Abandoned Shop (table of goods), Gnoll Camp (three gnolls round a fire). A special with no entry falls back to the floating icon. The piranha sprite is 16x16 (SPD PiranhaSprite), not 12 wide. Door cards keep the two doors from #179; their contents are hidden until chosen, so they get no scene. `tests/screenshots.gd` gains `ROOM_SHOTS=1` (one shot per special) and `SHOT_PC=1` (adds a 1280x800 window).
