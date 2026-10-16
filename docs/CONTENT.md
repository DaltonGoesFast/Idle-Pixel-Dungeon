# Content

Everything here is data-driven (`data/*.json`). Add content by editing JSON; no code changes are needed for new mobs (melee), rooms, encounter sets, recipes, door choices or special rooms. New *mechanics* (abilities like `throw`/`pump`) live in `scripts/core/combat.gd::_mob_act`.

Assets used (all from Shattered Pixel Dungeon, GPL-3.0): hero sprites (warrior, mage), mobs (rat, snake, gnoll, crab, statue, goo, piranha), `tiles_sewers.png`, `items.png` icons, ~30 sound effects, music (`sewers_1`, `sewers_boss`, `theme_1`).

<!-- GENERATED -->
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

### Ring, wand and artifact levels (DECISIONS #158)
Leveled and repaired at the **Enchanter's Desk**, not the Forge. Item level cap = Desk level - 1 (Lv1 Desk: +0 only).

| Action | Needs | Cost |
|---|---|---|
| Ring / wand to +N | Desk Lv N+1 | 1 Scroll of Upgrade + 3N Arcane Resin + 50N^2 gold (+1: 1 SoU, 3 resin, 50g; +2: 1 SoU, 6 resin, 200g; +3: 1 SoU, 9 resin, 450g; +4: 1 SoU, 12 resin, 800g) |
| Artifact to +N | Desk Lv N+1 | No Scrolls: 8N won fights while equipped |
| Repair ring / wand | Desk Lv2 | 2 + level Arcane Resin |
| Repair artifact | Desk Lv3 | 4 + 2 x level resin, 40 + 20 x level gold |

Per level: Might +1 dmg, Tenacity +1 Barrier, Evasion +1 DR per 2 levels, Wealth +5% gold, Energy +2 HP; staff wand +1 bolt dmg and +1 charge per 2 levels; Chalice +3 HP, Talisman +1 search per 2 levels, Horn -5% hunger. New drops start at +0 with lower base power: Tenacity +1 Barrier (was 2), Wealth +15% (was 30%), Energy +2 HP (was 4), Chalice +6 HP (was 15), Horn x0.8 hunger (was 0.6). On death, equipped rings/artifacts crack as before; an imbued wand with levels cracks too (its levels go dormant, base bolt still works). The free Patch up only covers weapons and armor.
### Vanilla rings (DECISIONS #157)
Flat bonuses like the existing rings (rings don't take upgrades here). Drop from `item_unknown: ring` rewards; spares melt at the Forge like the others.

| Ring | Unknown as | Effect |
|---|---|---|
| Furor | Opal | Melee swings take 15% less time (`delay x0.85`) |
| Haste | Tourmaline | Steps cost 0.85 tick |
| Sharpshooting | Sapphire | +1 Spirit Bow / staff bolt damage |
| Elements | Amethyst | Piercing damage (fire, your own lightning, zaps, traps that pierce) x0.67 |
| Force | Quartz | +2 melee damage with a tier-1 weapon (worn shortsword, dagger, gloves, staff) |

Not ported: Accuracy (no hit roll), Arcana (no enchantments yet).

### Ring levels for the #157 rings (DECISIONS #160)
| Ring | Per level | Floor |
|---|---|---|
| Furor | melee delay -5% | x0.6 |
| Haste | step cost -0.05 tick | 0.6 |
| Elements | piercing dmg taken -7% | x0.4 |
| Force | +1 dmg (tier-1 weapons) | - |
| Sharpshooting | +1 ranged dmg per 2 levels | - |
