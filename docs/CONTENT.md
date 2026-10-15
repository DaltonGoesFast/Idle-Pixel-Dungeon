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
| alchemy | Brew Starter Elixir | 5 seeds, 2 arcane_resin | elixir_starter | 2 |
| enchanter | Scribe Scroll of Passage | 2 arcane_resin, 20 gold | scroll_passage | 1 |
| guild | Buy Ration | 10 gold | ration | 1 |
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
| sacrificial_fire | caves, prison, sewers, city, halls | Sacrificial Fire | Offer blood (-4 HP) / Leave |
| statue | caves, prison, sewers, city, halls | Animated Statue | Challenge it (fight) / Leave |
| barricade | caves, prison, sewers, city, halls | Barricade | Burn it (1 Torch) / Smash it (-3 HP) / Leave |
| garden | caves, prison, sewers, city, halls | Overgrown Garden | Forage |
| trapped_hall | caves, prison, sewers, city, halls | Trapped Corridor | Search for a safe path (-10 torch) / Disarm the plates (Rogue) / Run through (-5 HP) / Leave |
| odd_wall | caves, prison, sewers, city, halls | Suspicious Wall | Search the wall (-8 torch) / Leave |
| cell_block | caves, prison, city, halls | Locked Cell | Unlock (1 Iron Key) / Pry the bars (-6 HP) / Leave |
| armory | caves, prison, city, halls | Guard Armory | Scavenge / Leave |
| crystal_vein | caves, city, halls | Crystal Vein | Mine it (-12 torch) / Pry a chunk loose (-6 HP) / Leave |

### Arenas

7 shared 8x8 rooms, 4 prison-only, 4 caves-only, 4 city-only, 4 halls-only, 5 boss rooms (data/rooms.json). Legend: # wall . floor " tall grass + door _ chasm ~ shallow water (conducts lightning) H hero start, 1-4 enemy spawn slots (filled in order), B boss ^ visible trap, ? hidden trap (type from the biome's trap pool)

Shared room 0:
```
########
#H.."..#
#..__..#
+..__.1#
#......#
#."."..#
#....2.#
########
```

Shared room 1:
```
###+####
#H."...#
#..#.1.#
#..#...#
#..+..__
#.""..__
#...2..#
########
```

Shared room 2:
```
########
#H.....#
#."..1.#
##+##..#
#..?.__#
#.2..__#
#."^..3#
########
```

Shared room 3:
```
########
#H.""..#
#..##..#
#.~~~.1#
#__~~".#
#__.2..#
#...+.3#
########
```

Shared room 4:
```
#+######
#H...."#
#.##.2.#
#."..._#
#..1.._#
#.##...#
#"...3.#
########
```

Shared room 5:
```
########
#H..+..#
#...#.1#
#"..#..#
###?#+##
#2.....#
#..__^3#
########
```

Shared room 6:
```
########
#H..~~.#
#.".~~1#
#..+~~.#
####..##
#2..~~.#
#."..~3#
########
```

prison room 0:
```
########
#H.#...#
#..#.1.#
#.?..^.#
#..##..#
#.^..?.#
#2...3.#
########
```

prison room 1:
```
########
#H....1#
#.#..#.#
#..?...#
#.^.~~.#
#.#.~#.#
#2..?.3#
########
```

prison room 2:
```
###+####
#H..^..#
#.##.#1#
#.#..?.#
#...#..#
#?#..^.#
#2...#3#
########
```

prison room 3:
```
########
#H.?..^#
#......#
#.#__#.#
#.#__#1#
#..?...#
#2.^..3#
########
```

caves room 0:
```
########
#H..##.#
#.~~..1#
#.~~.#.#
#..^...#
##..?..#
#2...3.#
########
```

caves room 1:
```
########
#H....##
#..#...#
#.###.1#
#..?...#
#__..^.#
#__2.3.#
########
```

caves room 2:
```
####.###
#H.~~..#
#..~~#1#
#.....##
##.?...#
#..#^..#
#2....3#
########
```

caves room 3:
```
########
#H.#...#
#..#.1.#
#..~~..#
#.^~~?.#
#..#...#
#2.#.3.#
########
```

city room 0:
```
########
#H..+..#
#...#..#
#...#.1#
##+##..#
#......#
#.2..""#
########
```

city room 1:
```
########
#H.....#
#.##.#.#
#......#
#.#.##.#
#..1...#
#...~~2#
########
```

city room 2:
```
###+####
#H.....#
#..""..#
#.#..#.#
#..1...#
#.#..#.#
#..^.2.#
########
```

city room 3:
```
########
#H~~...#
#.~~.1.#
#......#
##.##..#
#...?..#
#.2....#
########
```

halls room 0:
```
########
#H.._..#
#..__..#
#.....1#
#.#..#.#
#......#
#.2..".#
########
```

halls room 1:
```
########
#H.....#
#.#~~#.#
#..~~.1#
#......#
#._.._.#
#..2...#
########
```

halls room 2:
```
########
#H..#..#
#...#..#
#.1....#
#####+##
#......#
#..^.2.#
########
```

halls room 3:
```
########
#H"""..#
#.""..1#
#......#
#.__.?.#
#.__...#
#.2....#
########
```

Boss room 0:
```
########
#H...."#
#......#
#."..".#
#...B..#
#__..__#
#"...."#
########
```

Boss room 1:
```
########
#H.....#
#.#..#.#
#..^...#
#...B.^#
#.#..#.#
#..?...#
########
```

Boss room 2:
```
########
#H.....#
#.~~...#
#......#
#..B...#
#...~~.#
#......#
########
```

Boss room 3:
```
########
#H.....#
#.#..#.#
#......#
#..B...#
#.#..#.#
#......#
########
```

Boss room 4:
```
########
#......#
#.#..#.#
#..B...#
#......#
#.#..#.#
#H.....#
########
```
<!-- /GENERATED -->
