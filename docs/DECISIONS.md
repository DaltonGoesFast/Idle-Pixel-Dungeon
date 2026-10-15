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
