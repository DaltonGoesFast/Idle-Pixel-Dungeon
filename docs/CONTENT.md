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
| alchemy | Brew Potion of Healing | 2 seeds | potion_healing | 1 |
| alchemy | Brew Starter Elixir | 5 seeds, 2 arcane_resin | elixir_starter | 2 |
| enchanter | Scribe Scroll of Passage | 2 arcane_resin, 20 gold | scroll_passage | 1 |
| guild | Buy Ration | 10 gold | ration | 1 |
| guild | Buy Torch | 8 gold | torch | 1 |

### Door Choices

| Id | Door A | Door B |
|---|---|---|
| ozone | Door A: Smells of ozone (combat) | Door B: Locked (chest) |
| scratch | Door A: Frantic scratching (combat) | Door B: Damp, quiet (special) |
| glint | Door A: A metallic glint (combat) | Door B: Barred (1 Iron Key) (chest) |

### Special rooms (UI cards)

| Id | Title | Options |
|---|---|---|
| piranha | Piranha Pool | Wade in (-5 HP) / Distract with a Ration / Leave |
| sacrificial_fire | Sacrificial Fire | Offer blood (-4 HP) / Leave |
| statue | Animated Statue | Challenge it (fight) / Leave |
| barricade | Barricade | Burn it (1 Torch) / Smash it (-3 HP) / Leave |
| garden | Overgrown Garden | Forage |

### Arenas

6 handcrafted 8x8 rooms + 1 boss room (data/rooms.json). Legend: # wall . floor " tall grass + door _ chasm ~ water(cosmetic) H hero start, 1-4 enemy spawn slots (filled in order), B boss

Room 0:
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

Room 1:
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

Room 2:
```
########
#H.....#
#."..1.#
##+##..#
#....__#
#.2..__#
#.."..3#
########
```

Room 3:
```
########
#H.""..#
#..##..#
#.....1#
#__..".#
#__.2..#
#...+.3#
########
```

Room 4:
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

Room 5:
```
########
#H..+..#
#...#.1#
#"..#..#
#####+##
#2.....#
#..__.3#
########
```

Room 6:
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
<!-- /GENERATED -->
