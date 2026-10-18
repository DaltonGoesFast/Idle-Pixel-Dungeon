# Content

Everything here is data-driven (`data/*.json`). Add content by editing JSON; no code changes are needed for new mobs (melee), rooms, encounter sets, recipes, door choices or special rooms. New *mechanics* (abilities like `throw`/`pump`) live in `scripts/core/combat.gd::_mob_act`.

**Vanilla enemy behaviours (DECISIONS #155).** Mob shots (`throw`, `zap`, `web`) need sight (walls, closed doors, tall grass block it) and a body-free line (`Combat.mob_can_shoot`). Mobs with `holds_range` (shaman, warlock, Bright Fist) stay put while they have a clear shot in range instead of walking into melee. Per-mob keys: `zap_water` (damage multiplier if the hero stands in water), `zap_debuffs` (debuff a zap applies, picked by uid), `zap_beam` (Evil Eye: whole line to range 6), `web_range`/`web_cooldown`/`web_root` (Spinner), `bite_cripple` (Scorpio), `disarm_every`/`disarm_t` (Monk), `ability: blink` + `blink_cooldown` (Succubus), `ability: leap` + `leap_range`/`leap_cooldown` (Ripper), `ability: teleport` + `tele_cooldown` (Golem). Hero debuffs live in `hero.debuffs[id] = expiry time`: `weak` (melee x0.67), `vuln` (damage taken x1.33), `root` (a step spends the turn), `cripple` (steps cost 2 ticks).

**Enemy hunting and doors (DECISIONS #176).** Mobs need no data for this: every mob hunts the last cell it saw the hero on, and gives up there if it still cannot see him. Doors (`+`) shut when empty and block sight; a door something died in stays open until any unit passes through it. Circling a blocker loses a chasing mob, and attacking reveals you (DECISIONS #177).

Assets used (all from Shattered Pixel Dungeon, GPL-3.0): hero sprites (warrior, mage), mobs (rat, snake, gnoll, crab, statue, goo, piranha), `tiles_sewers.png`, `items.png` icons, ~30 sound effects, music (`sewers_1`, `sewers_boss`, `theme_1`).

<!-- GENERATED -->
### Patrol perks (DECISIONS #188)

Worn ring, artifact and the Mage's staff wand, at +0; the step is per item level. Perks are locked in when the patrol starts.

| Item | Type | On patrol |
|---|---|---|
| Ring of Might | ring | +15% iron ore (+5/lvl) |
| Ring of Tenacity | ring | +1 patrol power (+1/lvl) |
| Wand of Magic Missile | wand | +1 patrol power (+1/lvl) |
| Wand of Firebolt | wand | +15% dark gold (+5/lvl) |
| Wand of Lightning | wand | +15% arcane resin (+5/lvl) |
| Wand of Frost | wand | +25% dew (+10/lvl) |
| Wand of Corrosion | wand | +1 patrol power (+1/lvl) |
| Wand of Blast Wave | wand | +1 patrol power (+1/lvl) |
| Wand of Disintegration | wand | +1 patrol power (+1/lvl) |
| Wand of Transfusion | wand | +1 patrol power (+1/lvl) |
| Wand of Prismatic Light | wand | +15% curios (+5/lvl) |
| Wand of Regrowth | wand | +1 seeds/h (+0.5/lvl), +50% dew |
| Ring of Evasion | ring | +15% curios (+5/lvl) |
| Ring of Wealth | ring | +10% gold (+5/lvl), curios: any ring |
| Ring of Energy | ring | +15% arcane resin (+5/lvl) |
| Ring of Furor | ring | +5% materials (not gold) (+2.5/lvl) |
| Ring of Haste | ring | +10% patrol time (+5/lvl) |
| Ring of Sharpshooting | ring | +25% dew (+10/lvl) |
| Ring of Elements | ring | -15% fee (max 50%) (+5/lvl) |
| Ring of Force | ring | +15% dark gold (+5/lvl) |
| Chalice of Blood | artifact | +1 healing potion per 6h (-1/lvl, min 2) |
| Talisman of Foresight | artifact | curios arrive identified, 20% of curios come +1 (+10/lvl) |
| Horn of Plenty | artifact | +1 ration per 4h (-0.5/lvl, min 1.5) |
| Cape of Thorns | artifact | +1 patrol power (+1/lvl) |
| Ethereal Chains | artifact | +15% curios (+5/lvl) |
| Timekeeper's Hourglass | artifact | +1h max (+0.5/lvl) |
| Sandals of Nature | artifact | +1 seeds/h (+0.5/lvl), +1 dew/h (+0.5/lvl) |
| Master Thieves' Armband | artifact | +15% gold (+5/lvl) |

### Recipes

| Facility | Recipe | Cost | Output | Min level |
|---|---|---|---|---|
| blacksmith | Forge Shortsword | 6 iron_ore, 40 gold | shortsword | 1 |
| blacksmith | Forge Dagger | 3 iron_ore, 20 gold | dagger | 1 |
| blacksmith | Forge Leather Armor | 5 iron_ore, 30 gold | leather_armor | 1 |
| blacksmith | Forge Mace | 8 iron_ore, 2 dark_gold | mace | 2 |
| blacksmith | Forge Mail Armor | 10 iron_ore, 3 dark_gold | mail_armor | 2 |
| blacksmith | Forge Longsword | 14 iron_ore, 4 dark_gold | longsword | 3 |
| blacksmith | Forge Scale Armor | 16 iron_ore, 5 dark_gold | scale_armor | 3 |
| blacksmith | Forge Greatsword | 20 iron_ore, 8 dark_gold | greatsword | 3 |
| blacksmith | Forge Plate Armor | 22 iron_ore, 9 dark_gold | plate_armor | 3 |
| alchemy | Brew Potion of Healing | 2 seeds | potion_healing | 1 |
| alchemy | Condense Dew into Healing | 20 dew | potion_healing | 1 |
| alchemy | Brew Starter Elixir | 5 seeds, 2 arcane_resin | elixir_starter | 2 |
| alchemy | Neutralise Toxic Gas | 1 potion_toxic, 1 seeds | potion_healing | 1 |
| alchemy | Thin Shielding into Healing | 1 potion_shielding, 1 seeds | potion_healing | 1 |
| alchemy | Distil Experience | 1 potion_experience, 2 seeds | elixir_starter | 2 |
| alchemy | Rebind Teleportation | 1 scroll_teleport, 1 seeds | scroll_passage | 1 |
| alchemy | Render Identify to Resin | 1 scroll_identify | arcane_resin | 1 |
| alchemy | Render Mapping to Resin | 1 scroll_mapping | arcane_resin | 1 |
| enchanter | Scribe Scroll of Passage | 2 arcane_resin, 20 gold | scroll_passage | 1 |
| guild | Buy Ration | 10 gold | ration | 1 |
| guild | Buy Ration Crate | 25 gold | ration | 2 |
| guild | Buy Potion of Healing | 30 gold | potion_healing | 1 |
| guild | Buy Torch | 8 gold | torch | 1 |

### Door Choices

| Id | Biomes | Door A | Door B |
|---|---|---|---|
| ozone | caves, prison, sewers, city, halls | Door A: Smells of ozone (combat) | Door B: Locked (chest) |
| scratch | caves, prison, sewers, city, halls | Door A: Frantic scratching (combat) | Door B: Damp, quiet (special) |
| glint | caves, prison, sewers, city, halls | Door A: A metallic glint (combat) | Door B: Barred (1 Iron Key) (chest) |
| cells | caves, prison, city, halls | Door A: Rattling bones (combat) | Door B: A guard's footlocker (1 Iron Key) (chest) |
| workshop | caves, prison, city, halls | Door A: Humming machinery (combat) | Door B: A quiet storeroom (special) |
| den | caves, city, halls | Door A: Leathery wings flapping (combat) | Door B: A gnoll camp's strongbox (1 Iron Key) (chest) |

### Special rooms (UI cards)

| Id | Biomes | Title | Options |
|---|---|---|---|
| piranha | caves, prison, sewers, city, halls | Piranha Pool | Wade in (-5 HP) / Distract with a Ration / Leave |
| sacrificial_fire | caves, prison, sewers, city, halls | Sacrificial Fire | Offer blood (-4 HP) / Lure foes into the flame / Leave |
| statue | caves, prison, sewers, city, halls | Animated Statue | Challenge it (fight) / Leave |
| barricade | caves, prison, sewers, city, halls | Barricade | Burn it (1 Torch) / Smash it (-3 HP) / Leave |
| garden | caves, prison, sewers, city, halls | Overgrown Garden | Forage / Rest in the sungrass (+35% HP, -15 food) / Harvest with a ranger's eye / Beat the deep grass |
| trapped_hall | caves, prison, sewers, city, halls | Trapped Corridor | Search for a safe path (-10 torch) / Disarm the plates (Rogue) / Run through (-5 HP) / Leave |
| odd_wall | caves, prison, sewers, city, halls | Suspicious Wall | Search the wall (-8 torch) / Leave |
| cell_block | caves, prison, city, halls | Locked Cell | Unlock (1 Iron Key) / Pry the bars (-6 HP) / Leave |
| armory | caves, prison, city, halls | Guard Armory | Scavenge / Leave |
| crystal_vein | caves, city, halls | Crystal Vein | Mine it (-12 torch) / Pry a chunk loose (-6 HP) / Leave |
| vault | sewers, prison, caves, city, halls | Crystal Vault | Take the ring / Take the potion / Take the gold |
| library | prison, caves, city, halls | Ancient Library | Search the shelves (-8 torch) / Gather arcane dust |
| well_health | sewers, prison, caves, city, halls | Well of Health | Drink deeply / Leave |
| well_awareness | sewers, prison, caves, city, halls | Well of Awareness | Drink / Leave |
| laboratory | prison, caves, city, halls | Alchemy Laboratory | Search the bench / Leave |
| treasury | sewers, prison, caves, city, halls | Collapsed Treasury | Dig it out (-10 torch) / Grab what you can |
| shrine | city, halls | Forgotten Shrine | Offer blood (-12 HP) / Leave |
| larder | sewers, prison, caves, city, halls | Larder | Eat your fill / Pack rations |
| trap_vault | sewers, prison, caves, city, halls | Trapped Vault | Disarm and loot it (Rogue) / Fight the guards among the plates / Leave |
| prisoner | prison | Chained Prisoner | Unlock the shackles (1 Iron Key) / Fight the jailers / Leave |
| abandoned_shop | sewers, prison, caves, city, halls | Abandoned Shop | Buy a ration (20 gold) / Buy a torch (15 gold) / Buy an unknown potion (35 gold) / Leave |
| gnoll_camp | sewers, prison | Gnoll Camp | Raid the camp / Sneak in and grab the stash (-10 torch) / Leave |

### Arenas

10 shared 8x8 rooms, 3 sewers-only, 4 prison-only, 4 caves-only, 4 city-only, 4 halls-only, 5 boss rooms (data/rooms.json). Legend: # wall . floor " tall grass + door _ chasm ~ shallow water (conducts lightning) H hero start, 1-8 enemy spawn slots (filled in order), B boss ^ visible trap, ? hidden trap (type from the biome's trap pool). Rooms are 8x8, 10x10, or 12x12. Every + is a real threshold (open on two opposite sides, walls on the other two).

Shared room 0:
```
########
#H.."..#
#......#
##+##..#
#..__1.#
#."."..#
#....2.#
########
```

Shared room 1:
```
########
#H."...#
#......#
#..##..#
#..+..1#
#..##..#
#."2.__#
########
```

Shared room 2:
```
########
#H.....#
#."..1.#
##+##..#
#..?...#
#.2..__#
#."^..3#
########
```

Shared room 3:
```
########
#H.""..#
#......#
#.~~~.1#
##+##".#
#~~..2.#
#....3.#
########
```

Shared room 4:
```
########
#H...."#
#.##.2.#
#.+....#
#.#1.._#
#.##...#
#"...3.#
########
```

Shared room 5:
```
########
#H.....#
#....1.#
#".....#
###+####
#2.....#
#..__^3#
########
```

Shared room 6:
```
########
#H..~~.#
#.".~~1#
#...~~.#
###+####
#2..~~.#
#."..~3#
########
```

Shared room 7:
```
########
#H.....#
#....1.#
###+####
#.2....#
#..""..#
#....3.#
########
```

Shared room 8:
```
########
#H.""..#
#."....#
#...##.#
#...+1.#
#...#..#
#.2_#.3#
########
```

Shared room 9:
```
########
#H.....#
#.""...#
#..##1.#
#..+...#
#..##""#
#.2..3.#
########
```

sewers room 0:
```
########
#H.....#
#....1.#
###+####
#.2....#
#..""..#
#....3.#
########
```

sewers room 1:
```
########
#H.""..#
#."....#
#...##.#
#...+1.#
#...#..#
#.2_#.3#
########
```

sewers room 2:
```
########
#H.....#
#.""...#
#..##1.#
#..+...#
#..##""#
#.2..3.#
########
```

prison room 0:
```
##########
#H.......#
#........#
#....##.1#
#....+...#
#..###...#
#.^......#
#2.......#
#........#
##########
```

prison room 1:
```
##########
#H....~.1#
#......~.#
#........#
#..##+##.#
#........#
#2....~.3#
#........#
#........#
##########
```

prison room 2:
```
##########
#H.......#
#.##....1#
#.#......#
#.+.#....#
#.#......#
#2...#...#
#....#...#
#........#
##########
```

prison room 3:
```
##########
#H.......#
#........#
#.#__...1#
#.###+##.#
#........#
#2.......#
#........#
#........#
##########
```

caves room 0:
```
##########
#H.......#
#.~~....1#
#.~~.....#
#...##+###
#........#
#2.......#
#........#
#........#
##########
```

caves room 1:
```
##########
#H.......#
#........#
#.......1#
#...##+###
#__......#
#__2.....#
#........#
#........#
##########
```

caves room 2:
```
##########
#H.~~....#
#..~~...1#
#........#
#...##+###
#........#
#2.......#
#."".....#
#........#
##########
```

caves room 3:
```
##########
#H.......#
#....1...#
#..~~##..#
#....+...#
#..~~##..#
#2.......#
#........#
#........#
##########
```

city room 0:
```
##########
#H.......#
#...#....#
#...#.1..#
##+##....#
#........#
#....""..#
#........#
#........#
##########
```

city room 1:
```
##########
#H.......#
#........#
#....#...#
#.#..#..1#
#.##+##..#
#...~~...#
#........#
#........#
##########
```

city room 2:
```
############
#H.........#
#.."".....1#
#..........#
#..........#
##+#########
#..........#
#..........#
#..........#
#......2...#
#..........#
############
```

city room 3:
```
############
#H~~.......#
#.~~.1.....#
#......#...#
#......#...#
#...#..+...#
#...#..#...#
#..........#
#.__.......#
#.__...2...#
#..........#
############
```

halls room 0:
```
############
#H.........#
#..__......#
#......1...#
#....#.#...#
#....#+#...#
#.2..".....#
#..........#
#.__.......#
#..........#
#..........#
############
```

halls room 1:
```
############
#H.........#
#..........#
#......1...#
#..........#
#....##+##.#
#..2.......#
#..........#
#..........#
#."".......#
#..........#
############
```

halls room 2:
```
############
#H.........#
#..........#
#.1........#
#####+######
#..........#
#....2.....#
#..........#
#..........#
#..........#
#..........#
############
```

halls room 3:
```
############
#H.........#
#.""..1....#
#......#...#
#......#...#
#......+...#
#.2....#...#
#..........#
#..........#
#..........#
#..........#
############
```

Boss room 0:
```
##########
#H.......#
#..""....#
#........#
#.~....~.#
#....B...#
#__....__#
#."....".#
#........#
##########
```

Boss room 1:
```
##########
#H.......#
#.#....#.#
#........#
#..^.....#
#....B.^.#
#.#....#.#
#..?.....#
#........#
##########
```

Boss room 2:
```
############
#H.........#
#..........#
#.#......#.#
#...~~.....#
#..........#
#....B.....#
#..........#
#....~~....#
#.#......#.#
#..........#
############
```

Boss room 3:
```
############
#H.........#
#..........#
#.#......#.#
#..........#
#..........#
#....B.....#
#..........#
#..........#
#.#......#.#
#..........#
############
```

Boss room 4:
```
############
#..........#
#.#......#.#
#..........#
#..........#
#....B.....#
#..........#
#..........#
#.#......#.#
#..........#
#H.........#
############
```
<!-- /GENERATED -->

### Vanilla wands (DECISIONS #156)
Imbued into the Mage's Staff (only the Mage zaps). Each bolt ignores DR, gets +1 damage per 2 hero levels like the others, and drops from `item_unknown: wand` rewards (Scroll of Identify / use reveals them). Sprites are SPD's `ItemSpriteSheet` wands.

| Wand | Unknown as | Bolt | Effect | Scaling |
|---|---|---|---|---|
| Frost | Holly | 3 | Target's next action delayed 1 tick | 1.5 ticks from hero Lv 15 |
| Corrosion | Yew | 2 | +3 poison (1/action, ignores DR) | +1 poison per 6 hero levels |
| Blast Wave | Elm | 3 | Knocks the target back 1 tile (bosses immune; chasms kill, walls deal 1) | 2 tiles from Lv 15 |
| Disintegration | Ebony | 4 | Hits every enemy on the line to range (walls stop it) | - |
| Transfusion | Willow | 3 | Heals you 2 HP on a hit | +1 per 10 hero levels |
| Prismatic Light | Rowan | 4 | Reveals hidden traps within 2 tiles of the impact | - |
| Regrowth | Maple | 1 | Roots the target 2 ticks, grows tall grass around the impact | - |

Not ported: Corruption, Living Earth, Warding (all need allied units).

### Vanilla rings (DECISIONS #157)
Flat bonuses like the existing rings. Drop from `item_unknown: ring` rewards; spares melt at the Forge like the others. Levels are in the Enchanter section below.

| Ring | Unknown as | Effect |
|---|---|---|
| Furor | Opal | Melee swings take 15% less time (`delay x0.85`) |
| Haste | Tourmaline | Steps cost 0.85 tick |
| Sharpshooting | Sapphire | +1 Spirit Bow / staff bolt damage |
| Elements | Amethyst | Piercing damage (fire, your own lightning, zaps, traps that pierce) x0.67 |
| Force | Quartz | +2 melee damage with a tier-1 weapon (worn shortsword, dagger, gloves, staff) |

Not ported: Accuracy (no hit roll), Arcana (no enchantments yet).

### Ring, wand and artifact levels (DECISIONS #158)
Leveled and repaired at the **Enchanter's Desk**, not the Forge. Item level cap = Desk level - 1 (Lv1 Desk: +0 only).

| Action | Needs | Cost |
|---|---|---|
| Ring / wand to +N | Desk Lv N+1 | 4N Arcane Resin + 75N^2 gold, no Scroll of Upgrade (+1: 4 resin, 75g; +2: 8 resin, 300g; +3: 12 resin, 675g; +4: 16 resin, 1200g) |
| Artifact to +N | Desk Lv N+1 | No Scrolls: 8N won fights while equipped |
| Repair ring / wand | Desk Lv2 | 2 + level Arcane Resin |
| Repair artifact | Desk Lv2 | 4 + 2 x level resin, 40 + 20 x level gold |

Per level: Might +1 dmg, Tenacity +1 Barrier, Evasion +1 DR per 2 levels, Wealth +5% gold, Energy +2 HP; staff wand +1 bolt dmg and +1 charge per 2 levels; Chalice +3 HP, Talisman +1 search per 2 levels, Horn -5% hunger. New drops start at +0 with lower base power: Tenacity +1 Barrier (was 2), Wealth +15% (was 30%), Energy +2 HP (was 4), Chalice +6 HP (was 15), Horn x0.8 hunger (was 0.6). On death, equipped rings/artifacts crack as before; an imbued wand with levels cracks too (its levels go dormant, base bolt still works). The free Patch up only covers weapons and armor.

### Equipment at Camp (DECISIONS #189)
Every hero has one weapon, armor, ring and artifact slot; the Mage's Staff also holds one wand. At Camp any of these can be unequipped back to the stash (heirlooms like the Mage's Staff stay put). Gear another hero wears can be taken: if you hand back something they can wear, the two heroes swap, otherwise their slot goes empty. The Stash, Forge and Enchanter name the wearer on each piece, and the Wands list shows the staff's wand. While a hero is on patrol or on the current delve, nothing they wear can be unequipped, taken or swapped ("<Hero> is on patrol").

### Vanilla artifacts (DECISIONS #159)
Bosses drop an artifact you don't own yet (as before). They start at +0, gain a level every 8 x (next level) won fights while equipped, and are capped by the Enchanter's Desk (#158).

| Artifact | +0 | Per level |
|---|---|---|
| Cape of Thorns | Melee attackers take 1 dmg back (ignores DR) | +1 per 2 levels |
| Ethereal Chains | Fight start: nearest non-boss 3+ tiles away is dragged next to you | held 0.5 tick per level |
| Timekeeper's Hourglass | Fight start: non-boss enemies frozen 0.5 tick | +0.25 tick |
| Sandals of Nature | Stepping into tall grass roots adjacent enemies 0.5 tick | +0.25 tick |
| Master Thieves' Armband | +10% gold from fights (stacks with Wealth) | +5% |

Not ported: Dried Rose (ally), Alchemist's Toolkit and Unstable Spellbook (need in-fight alchemy/scroll casting), Lloyd's Beacon (extraction rules are the core risk loop), Horn/Chalice already exist.

### Ring levels for the #157 rings (DECISIONS #160)
| Ring | Per level | Floor |
|---|---|---|
| Furor | melee delay -5% | x0.6 |
| Haste | step cost -0.05 tick | 0.6 |
| Elements | piercing dmg taken -7% | x0.4 |
| Force | +1 dmg (tier-1 weapons) | - |
| Sharpshooting | +1 ranged dmg per 2 levels | - |
### Vanilla potions & scrolls (DECISIONS #161)
All drop as unknown consumables (every 4th won fight and `item_unknown` rewards) and are used from the backpack between fights; using one identifies it. Most set a **next-fight** effect.

| Item | Effect |
|---|---|
| Potion of Invisibility | Next fight: unseen for 3 ticks (first blow is a Surprise) |
| Potion of Haste | Next fight: enemies lose their first 1.5 ticks |
| Potion of Levitation | Next fight: you float over traps |
| Potion of Frost (bad) | Next fight: you lose your first 1.5 ticks |
| Potion of Paralytic Gas (bad) | Next fight: you lose your first 2.5 ticks |
| Potion of Liquid Flame (bad) | Now: lose 15% of max HP |
| Scroll of Recharging | Next fight: +1 staff charge, +1 cloak charge |
| Scroll of Lullaby | Next fight: non-boss enemies start asleep 2 ticks |
| Scroll of Retribution | Next fight opens with half your missing HP (min 2) to each non-boss foe |
| Scroll of Terror | Next fight: non-boss foes are knocked back a tile and lose 1 tick |
| Scroll of Transmutation | Now: the first ring or wand in your backpack becomes a different one of its kind |

Unknown looks grow to 9 potion colours (+Charcoal, Silver, Ivory) and 9 runes (+Naudiz, Odal, Tiwaz). Not ported: Mind Vision, Purity, Remove Curse, Mirror Image, Rage, and all exotics except the existing Shielding/Passage.
