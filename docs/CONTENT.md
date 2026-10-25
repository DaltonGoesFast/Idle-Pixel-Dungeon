# Content

Everything here is data-driven (`data/*.json`). Add content by editing JSON; no code changes are needed for new mobs (melee), rooms, encounter sets, recipes, door choices or special rooms. New *mechanics* (abilities like `throw`/`pump`) live in `scripts/core/combat.gd::_mob_act`.

**Vanilla enemy behaviours (DECISIONS #155).** Mob shots (`throw`, `zap`, `web`) need sight (walls, closed doors, tall grass block it) and a body-free line (`Combat.mob_can_shoot`). Mobs with `holds_range` (shaman, warlock, Bright Fist) stay put while they have a clear shot in range instead of walking into melee. Per-mob keys: `zap_water` (damage multiplier if the hero stands in water), `zap_debuffs` (debuff a zap applies, picked by uid), `zap_beam` (Evil Eye: whole line to range 6), `web_range`/`web_cooldown`/`web_root` (Spinner), `bite_cripple` (Scorpio), `disarm_every`/`disarm_t` (Monk), `ability: blink` + `blink_cooldown` (Succubus), `ability: leap` + `leap_range`/`leap_cooldown` (Ripper), `ability: teleport` + `tele_cooldown` (Golem). Hero debuffs live in `hero.debuffs[id] = expiry time`: `weak` (melee x0.67), `vuln` (damage taken x1.33), `root` (a step spends the turn), `cripple` (steps cost 2 ticks).

**Enemy hunting and doors (DECISIONS #176).** Mobs need no data for this: every mob hunts the last cell it saw the hero on, and gives up there if it still cannot see him. Doors (`+`) shut when empty and block sight; a door something died in stays open until any unit passes through it. Circling a blocker loses a chasing mob, and attacking reveals you (DECISIONS #177).

Assets used (all from Shattered Pixel Dungeon, GPL-3.0): hero sprites (warrior, mage), mobs (rat, snake, gnoll, crab, statue, goo, piranha), `tiles_sewers.png`, `items.png` icons, ~30 sound effects, music (`sewers_1`, `sewers_boss`, `theme_1`).

**Floor feelings (DECISIONS #237).** Each biome plans at least one feeling on a non-boss floor, rarely two (distinct). The plan resets when entering a new biome. Announced in the delve log. **XL** biases large rooms and denser packs, ensures a special, grants a spare ration when leaving the floor. **Secret** forces Suspicious Wall, Search always finds (richer gold). **Traps** biases trap-dense maps and forces Trapped Vault. Dark / Water / Grass / Chasm and trinket overrides are out of scope for now.

<!-- GENERATED -->
### Patrol perks (DECISIONS #188)

Worn ring, artifact and the Mage's staff wand, at +0; the step is per item level. Perks are locked in when the patrol starts.

| Item | Type | On patrol |
|---|---|---|
| Cape of Thorns | artifact | +1 patrol power (+1/lvl) |
| Chalice of Blood | artifact | +1 healing potion per 6h (-1/lvl, min 2) |
| Ethereal Chains | artifact | +15% curios (+5/lvl) |
| Horn of Plenty | artifact | +1 ration per 4h (-0.5/lvl, min 1.5) |
| Ring of Elements | ring | -15% fee (max 50%) (+5/lvl) |
| Ring of Energy | ring | +15% arcane resin (+5/lvl) |
| Ring of Evasion | ring | +15% curios (+5/lvl) |
| Ring of Force | ring | +15% dark gold (+5/lvl) |
| Ring of Furor | ring | +5% materials (not gold) (+2.5/lvl) |
| Ring of Haste | ring | +10% patrol time (+5/lvl) |
| Ring of Might | ring | +15% iron ore (+5/lvl) |
| Ring of Sharpshooting | ring | +25% dew (+10/lvl) |
| Ring of Tenacity | ring | +1 patrol power (+1/lvl) |
| Ring of Wealth | ring | curios: any ring, +10% gold (+5/lvl) |
| Sandals of Nature | artifact | +1 dew/h (+0.5/lvl), +1 seeds/h (+0.5/lvl) |
| Talisman of Foresight | artifact | curios arrive identified, 20% of curios come +1 (+10/lvl) |
| Master Thieves' Armband | artifact | +15% gold (+5/lvl) |
| Timekeeper's Hourglass | artifact | +1h max (+0.5/lvl) |
| Wand of Blast Wave | wand | +1 patrol power (+1/lvl) |
| Wand of Corrosion | wand | +1 patrol power (+1/lvl) |
| Wand of Disintegration | wand | +1 patrol power (+1/lvl) |
| Wand of Firebolt | wand | +15% dark gold (+5/lvl) |
| Wand of Frost | wand | +25% dew (+10/lvl) |
| Wand of Lightning | wand | +15% arcane resin (+5/lvl) |
| Wand of Magic Missile | wand | +1 patrol power (+1/lvl) |
| Wand of Prismatic Light | wand | +15% curios (+5/lvl) |
| Wand of Regrowth | wand | +50% dew, +1 seeds/h (+0.5/lvl) |
| Wand of Transfusion | wand | +1 patrol power (+1/lvl) |

### Milestones (DECISIONS #195)

80 milestones. A reached milestone waits in the Journal until the player taps Claim. All rewards together: 555.0 gold, 3.0 ration, 2.0 scroll of passage, 72.0 iron ore, 13.0 torch, 19.0 dark gold, 15.0 arcane resin, 2.0 iron key, 63.0 dew, 21.0 seeds, 2.0 scroll of upgrade, 4.0 healing potion.

| Category | Milestone | Goal | Reward |
|---|---|---|---|
| Delving | First Steps | Complete an expedition (extract). | 30.0 gold, 1.0 ration |
| Delving | Veteran | Complete 10 expeditions. | 100.0 gold, 1.0 scroll of passage |
| Delving | Seasoned Delver | Complete 25 expeditions. | 2.0 iron ore, 1.0 scroll of passage |
| Delving | Deep Dive | Reach floor 6 (the Prison). | 40.0 gold, 2.0 torch |
| Delving | Into the Caves | Reach floor 11 (the Caves). | 2.0 iron ore, 1.0 torch |
| Delving | Dwarven Metropolis | Reach floor 16 (the City). | 1.0 dark gold, 1.0 torch |
| Delving | Demon Halls | Reach floor 21 (the Halls). | 1.0 dark gold, 3.0 iron ore |
| Delving | Trap Sense | Find 10 hidden traps. | 2.0 arcane resin |
| Delving | Secret Keeper | Discover 3 hidden doors. | 1.0 dark gold, 2.0 iron key |
| Delving | Explorer | Explore 10 special rooms. | 5.0 dew, 1.0 seeds |
| Delving | Treasure Hunter | Open 10 chests behind doors. | 8.0 dew |
| Bosses | Slime Time | Defeat Goo. | 5.0 iron ore, 3.0 seeds |
| Bosses | Jailbreak | Defeat Tengu. | 3.0 dark gold, 1.0 scroll of upgrade |
| Bosses | Clockwork Breaker | Defeat DM-300. | 1.0 dark gold, 3.0 iron ore |
| Bosses | Regicide | Defeat the King of Dwarves. | 1.0 dark gold, 3.0 iron ore |
| Bosses | Happy End | Defeat Yog-Dzewa. | 3.0 arcane resin, 3.0 dark gold, 100.0 gold |
| Bosses | Full Roster | Clear the Sewers with all four heroes. | 1.0 scroll of upgrade |
| Bosses | Full Roster II | Clear the Prison with all four heroes. | 1.0 dark gold, 2.0 iron ore |
| Bosses | Goo Slayer: Warrior | Defeat Goo with the Warrior. | 1.0 iron ore, 1.0 seeds |
| Bosses | Goo Slayer: Mage | Defeat Goo with the Mage. | 1.0 iron ore, 1.0 seeds |
| Bosses | Goo Slayer: Rogue | Defeat Goo with the Rogue. | 1.0 iron ore, 1.0 seeds |
| Bosses | Goo Slayer: Huntress | Defeat Goo with the Huntress. | 1.0 iron ore, 1.0 seeds |
| Bosses | Tengu Slayer: Warrior | Defeat Tengu with the Warrior. | 1.0 iron ore, 1.0 torch |
| Bosses | Tengu Slayer: Mage | Defeat Tengu with the Mage. | 1.0 iron ore, 1.0 torch |
| Bosses | Tengu Slayer: Rogue | Defeat Tengu with the Rogue. | 1.0 iron ore, 1.0 torch |
| Bosses | Tengu Slayer: Huntress | Defeat Tengu with the Huntress. | 1.0 iron ore, 1.0 torch |
| Monsters | Monsters Slain I | Defeat 20 monsters. | 1.0 iron ore |
| Monsters | Exterminator | Defeat 100 monsters. | 80.0 gold, 6.0 iron ore |
| Monsters | Monsters Slain III | Defeat 500 monsters. | 3.0 iron ore, 1.0 healing potion |
| Monsters | Rat Catcher | Defeat 50 rats. | 1.0 seeds |
| Monsters | Snake Charmer | Defeat 20 sewer snakes. | 6.0 dew |
| Monsters | Gnoll Hunter | Defeat 40 gnolls (scouts, shamans and brutes). | 1.0 iron ore |
| Monsters | Crab Cracker | Defeat 25 sewer crabs. | 1.0 ration |
| Monsters | Bone Collector | Defeat 25 skeletons. | 2.0 iron ore |
| Monsters | Thief Taker | Defeat 10 crazy thieves. | 25.0 gold |
| Monsters | Dwarf Bane | Defeat 30 of the city's dwarves, ghouls and golems. | 1.0 dark gold, 1.0 iron ore |
| Monsters | Demon Hunter | Defeat 30 demons in the Halls. | 2.0 arcane resin |
| Monsters | Ambusher | Land 25 surprise attacks. | 5.0 dew, 1.0 torch |
| Monsters | Ambusher II | Land 150 surprise attacks. | 2.0 iron ore |
| Wealth | Gold Collected I | Bank 500 gold at Camp (extractions and patrols). | 1.0 iron ore |
| Wealth | Gold Collected II | Bank 2500 gold at Camp. | 2.0 iron ore |
| Wealth | Gold Collected III | Bank 10000 gold at Camp. | 1.0 arcane resin, 1.0 dark gold |
| Wealth | Big Spender I | Spend 1000 gold. | 1.0 torch |
| Wealth | Big Spender II | Spend 5000 gold. | 3.0 iron ore |
| Crafting | Item Level I | Upgrade gear 5 times. | 1.0 iron ore |
| Crafting | Fine Steel | Own a +3 item. | 2.0 iron ore |
| Crafting | Masterwork | Own a +5 item. | 1.0 arcane resin, 1.0 dark gold |
| Crafting | Forged in Fire | Forge 3 items at the Blacksmith. | 1.0 iron ore |
| Crafting | Master Brewer | Brew 10 potions. | 1.0 healing potion, 5.0 seeds |
| Crafting | Items Crafted II | Brew 40 potions. | 8.0 dew, 2.0 seeds |
| Items | Treasure Seeker | Find 10 pieces of gear in the dungeon. | 1.0 torch |
| Items | Researcher I | Identify 5 items, potions or scrolls. | 1.0 seeds |
| Items | Researcher II | Identify 25 items, potions or scrolls. | 5.0 dew, 1.0 seeds |
| Items | Potion Drinker | Drink 15 potions. | 6.0 dew |
| Items | Scroll Reader | Read 10 scrolls. | 1.0 arcane resin |
| Items | Food Eaten I | Eat 20 rations. | 1.0 ration |
| Items | Collector | Own 3 different artifacts. | 8.0 dew |
| Items | Bestiary | Discover 20 kinds of monster. | 1.0 seeds |
| Patrols | On Patrol | Bring a hero back from patrol. | 1.0 iron ore |
| Patrols | Patrol Captain | Complete 10 patrols. | 2.0 iron ore |
| Patrols | Night Watch | Patrol for 24 hours in total. | 1.0 iron ore |
| Patrols | Curio Hunter | Bring back 10 curios from patrols. | 1.0 arcane resin |
| Patrols | Well Equipped | Have one hero wear 10 gear levels. | 2.0 iron ore |
| Patrols | Armed to the Teeth | Have one hero wear 20 gear levels. | 1.0 dark gold, 2.0 iron ore |
| Camp | Builder | Upgrade a Camp facility. | 1.0 iron ore |
| Camp | Thriving Camp | Make 8 facility upgrades. | 1.0 dark gold, 2.0 iron ore |
| Camp | Scroll Mason | Raise a facility's cap with a Scroll of Upgrade. | 1.0 arcane resin |
| Camp | Master of the Camp | Raise every facility's cap to the maximum. | 2.0 arcane resin, 100.0 gold |
| Camp | Full Camp | Unlock all four heroes. | 1.0 seeds, 1.0 torch |
| Heroes | Level Reached I | Reach level 5 with any hero. | 1.0 healing potion |
| Heroes | Level Reached II | Reach level 10 with any hero. | 2.0 iron ore |
| Heroes | Talented | Have one hero hold 4 talents. | 6.0 dew |
| Heroes | Masked | Choose a subclass with Tengu's Mask. | 1.0 seeds, 1.0 torch |
| Heroes | All Masks | Choose a subclass for all four heroes. | 1.0 dark gold, 2.0 iron ore |
| Feats | Untouchable | Defeat a boss without losing any HP. | 1.0 arcane resin, 50.0 gold |
| Feats | By Hand | Defeat a boss without Auto Battle. | 30.0 gold, 1.0 iron ore |
| Feats | Teetotaller | Defeat a boss without drinking a potion. | 1.0 iron ore |
| Feats | Close Call | Win a fight with 10% HP or less. | 1.0 healing potion |
| Feats | Crowd Control | Defeat 6 or more enemies in one fight. | 6.0 dew, 1.0 iron ore |
| Feats | Heavy Pockets | Extract with 300 or more gold in the pack. | 1.0 dark gold |

### Recipes

| Facility | Recipe | Cost | Output | Min level |
|---|---|---|---|---|
| alchemy | Brew Potion of Healing | 2.0 seeds | potion_healing | 1.0 |
| alchemy | Condense Dew into Healing | 20.0 dew | potion_healing | 1.0 |
| alchemy | Brew Starter Elixir | 2.0 arcane_resin, 5.0 seeds | elixir_starter | 2.0 |
| alchemy | Neutralise Toxic Gas | 1.0 potion_toxic, 1.0 seeds | potion_healing | 1.0 |
| alchemy | Thin Shielding into Healing | 1.0 potion_shielding, 1.0 seeds | potion_healing | 1.0 |
| alchemy | Distil Experience | 1.0 potion_experience, 2.0 seeds | elixir_starter | 2.0 |
| alchemy | Rebind Teleportation | 1.0 scroll_teleport, 1.0 seeds | scroll_passage | 1.0 |
| alchemy | Render Identify to Resin | 1.0 scroll_identify | arcane_resin | 1.0 |
| alchemy | Render Mapping to Resin | 1.0 scroll_mapping | arcane_resin | 1.0 |
| blacksmith | Forge Worn Shortsword | 25.0 gold, 4.0 iron_ore | worn_shortsword | 2.0 |
| blacksmith | Forge Shortsword | 60.0 gold, 10.0 iron_ore | shortsword | 2.0 |
| blacksmith | Forge Leather Armor | 60.0 gold, 12.0 iron_ore | leather_armor | 2.0 |
| blacksmith | Forge Sword | 150.0 gold, 24.0 iron_ore | sword | 3.0 |
| blacksmith | Forge Mail Armor | 150.0 gold, 28.0 iron_ore | mail_armor | 3.0 |
| blacksmith | Forge Longsword | 15.0 dark_gold, 350.0 gold, 45.0 iron_ore | longsword | 4.0 |
| blacksmith | Forge Scale Armor | 15.0 dark_gold, 350.0 gold, 45.0 iron_ore | scale_armor | 4.0 |
| blacksmith | Forge Greatsword | 15.0 arcane_resin, 30.0 dark_gold, 700.0 gold, 70.0 iron_ore | greatsword | 5.0 |
| blacksmith | Forge Plate Armor | 15.0 arcane_resin, 30.0 dark_gold, 700.0 gold, 70.0 iron_ore | plate_armor | 5.0 |
| enchanter | Scribe Scroll of Passage | 2.0 arcane_resin, 20.0 gold | scroll_passage | 1.0 |
| guild | Buy Ration | 10.0 gold | ration | 1.0 |
| guild | Buy Ration Crate | 25.0 gold | ration | 2.0 |
| guild | Buy Potion of Healing | 30.0 gold | potion_healing | 1.0 |
| guild | Buy Torch | 8.0 gold | torch | 1.0 |

### Door Choices

| Id | Biomes | Door A | Door B |
|---|---|---|---|
| ozone | caves, prison, sewers, city, halls | Door A: Smells of ozone (combat) | Door B: Locked (chest) |
| scratch | caves, sewers, city, halls | Door A: Frantic scratching (combat) | Door B: Damp, quiet (special) |
| glint | caves, prison, sewers, city, halls | Door A: A metallic glint (combat) | Door B: Barred (1 Iron Key) (chest) |
| cells | caves, prison, city, halls | Door A: Rattling bones (combat) | Door B: A guard's footlocker (1 Iron Key) (chest) |
| workshop | caves, prison, city, halls | Door A: Humming machinery (combat) | Door B: A quiet storeroom (special) |
| den | caves, city, halls | Door A: Leathery wings flapping (combat) | Door B: A gnoll camp's strongbox (1 Iron Key) (chest) |

### Special rooms (UI cards)

| Id | Biomes | Title | Options |
|---|---|---|---|
| piranha | caves, prison, sewers, city, halls | Piranha Pool | Wade in (-HP) / Distract with a Ration / Leave |
| sacrificial_fire | caves, prison, sewers, city, halls | Sacrificial Fire | Offer blood (-HP) / Lure foes into the flame / Leave |
| statue | caves, prison, sewers, city, halls | Animated Statue | Challenge it (fight) / Leave |
| barricade | caves, prison, sewers, city, halls | Barricade | Burn it (1 Torch) / Smash it (-HP) / Leave |
| garden | caves, prison, sewers, city, halls | Overgrown Garden | Forage / Rest in the sungrass (+35% HP, -15 food) / Harvest with a ranger's eye / Beat the deep grass |
| trapped_hall | caves, prison, sewers, city, halls | Trapped Corridor | Search for a safe path (-10 torch) / Disarm the plates (Rogue) / Run through (-HP) / Leave |
| odd_wall | caves, prison, sewers, city, halls | Suspicious Wall | Search the wall (-8 torch) / Leave |
| cell_block | caves, prison, city, halls | Locked Cell | Unlock (1 Iron Key) / Pry the bars (-HP) / Leave |
| armory | caves, prison, city, halls | Guard Armory | Scavenge / Leave |
| crystal_vein | caves, city, halls | Crystal Vein | Mine it (-12 torch) / Pry a chunk loose (-HP) / Leave |
| vault | sewers, prison, caves, city, halls | Crystal Vault | Take the ring / Take the potion / Take the gold |
| library | prison, caves, city, halls | Ancient Library | Search the shelves (-8 torch) / Gather arcane dust |
| well_health | sewers, prison, caves, city, halls | Well of Health | Drink deeply / Leave |
| well_awareness | sewers, prison, caves, city, halls | Well of Awareness | Drink / Leave |
| laboratory | prison, caves, city, halls | Alchemy Laboratory | Search the bench / Leave |
| treasury | sewers, prison, caves, city, halls | Collapsed Treasury | Dig it out (-10 torch) / Grab what you can |
| shrine | city, halls | Forgotten Shrine | Offer blood (-HP) / Leave |
| larder | sewers, prison, caves, city, halls | Larder | Eat your fill / Pack rations |
| trap_vault | sewers, prison, caves, city, halls | Trapped Vault | Disarm and loot it (Rogue) / Fight the guards among the plates / Leave |
| prisoner | prison | Chained Prisoner | Unlock the shackles (1 Iron Key) / Fight the jailers / Leave |
| abandoned_shop | sewers, prison, caves, city, halls | Abandoned Shop | Buy a ration (20 gold) / Buy a torch (15 gold) / Buy an unknown potion (35 gold) / Leave |
| gnoll_camp | sewers, prison | Gnoll Camp | Raid the camp / Sneak in and grab the stash (-10 torch) / Leave |

### Arenas

20 shared 8x8 rooms, 10 sewers-only, 8 prison-only, 8 caves-only, 8 city-only, 8 halls-only, 5 boss rooms (data/rooms.json). Legend: # wall . floor " tall grass + door _ chasm ~ shallow water (conducts lightning) H hero start, 1-8 enemy spawn slots (filled in order), B boss ^ visible trap, ? hidden trap (type from the biome's trap pool). Rooms are 8x8, 10x10, or 12x12. Every + is a real threshold (open on two opposite sides, walls on the other two).

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

Shared room 10:
```
########
#H.....#
#.^....#
##+##..#
#.?..1.#
#....2.#
#.^..3.#
########
```

Shared room 11:
```
########
#H.""..#
#."....#
#......#
###+####
#1.^..?#
#2....3#
########
```

Shared room 12:
```
########
#H.....#
#.~~...#
#.~##1.#
#..+...#
#.~##2.#
#.~~.3.#
########
```

Shared room 13:
```
########
#H__...#
#.__...#
#......#
##+##1.#
#......#
#.2..3.#
########
```

Shared room 14:
```
########
#H...."#
#.####.#
#.+..1.#
#.####.#
#2.....#
#..."3.#
########
```

Shared room 15:
```
########
#H.....#
#......#
#.##1.##
#..+...#
#.##2.##
#....3.#
########
```

Shared room 16:
```
########
#H.^.?.#
#......#
###+####
#1.....#
#..""..#
#2.^..3#
########
```

Shared room 17:
```
########
#H~~~~.#
#.~~~~1#
#......#
##+#####
#2.....#
#....3.#
########
```

Shared room 18:
```
########
#H.....#
#.."1".#
#......#
#..##+##
#2.....#
#.__.3.#
########
```

Shared room 19:
```
########
#H.....#
#......#
#1.....#
#####+##
#.?^..2#
#....3.#
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

sewers room 3:
```
########
#H.^...#
#.?....#
##+##..#
#.^..1.#
#....2.#
#.?..3.#
########
```

sewers room 4:
```
########
#H..~~.#
#.^##..#
#..+..1#
#..##..#
#2.?~..#
#....3.#
########
```

sewers room 5:
```
########
#H"""".#
#."""".#
###+####
#1.....#
#..^..2#
#....3.#
########
```

sewers room 6:
```
##########
#H.......#
#..""....#
#........#
#...##+###
#........#
#.1......#
#....~~..#
#.2......#
##########
```

sewers room 7:
```
##########
#H.......#
#.^......#
#....?..1#
#..##+##.#
#........#
#2.^.....#
#....?...#
#........#
##########
```

sewers room 8:
```
##########
#H~~.....#
#.~~.....#
#........#
#.###+####
#........#
#1.......#
#.__.....#
#2.......#
##########
```

sewers room 9:
```
##########
#H.......#
#.####...#
#.#..#..1#
#.#..+...#
#.#..#...#
#2####...#
#........#
#........#
##########
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

prison room 4:
```
##########
#H.......#
#.^..?...#
#.......1#
#..##+##.#
#........#
#2.^..?..#
#........#
#........#
##########
```

prison room 5:
```
##########
#H.......#
#.##.....#
#.#....1.#
#.+......#
#.#....2.#
#.##.....#
#........#
#........#
##########
```

prison room 6:
```
##########
#H.""....#
#."".....#
#.......1#
###+######
#........#
#2.......#
#..__....#
#........#
##########
```

prison room 7:
```
##########
#H.......#
#...?....#
#.^..##1.#
#....+...#
#.^..##2.#
#...?....#
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

caves room 4:
```
##########
#H.......#
#.^..~~..#
#.?.....1#
#...##+###
#........#
#2.^.....#
#....~~..#
#........#
##########
```

caves room 5:
```
##########
#H__.....#
#.__.....#
#.......1#
#...##+###
#........#
#2.......#
#."".....#
#........#
##########
```

caves room 6:
```
##########
#H.......#
#.####...#
#.#..#.1.#
#.#..+...#
#.#..#...#
#2####...#
#.~......#
#.~......#
##########
```

caves room 7:
```
##########
#H.^.?...#
#........#
#.......1#
#####+####
#........#
#2.^..?..#
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

city room 4:
```
##########
#H.......#
#.^..?...#
#...#...1#
##+##....#
#........#
#2.^..?..#
#........#
#........#
##########
```

city room 5:
```
############
#H.........#
#..^...?..1#
#..........#
#..........#
##+#########
#..........#
#.2.^......#
#.....?....#
#..........#
#..........#
############
```

city room 6:
```
############
#H.........#
#.####.....#
#.#..#....1#
#.#..+.....#
#.#..#.....#
#.####.....#
#.2........#
#..........#
#.~.~......#
#..........#
############
```

city room 7:
```
##########
#H.......#
#."".....#
#.......1#
#.#..##+##
#.#......#
#2.......#
#.__.....#
#........#
##########
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

halls room 4:
```
############
#H.........#
#.^....?...#
#......1...#
#....#.#...#
#....#+#...#
#.2........#
#.^....?...#
#.__.......#
#..........#
#..........#
############
```

halls room 5:
```
############
#H.........#
#..........#
#.1........#
#####+######
#..........#
#....2.....#
#.^........#
#.....?....#
#..........#
#..........#
############
```

halls room 6:
```
############
#H~~.......#
#.~~.......#
#......1...#
#....##+##.#
#..2.......#
#..........#
#.__.......#
#.__.......#
#."".......#
#..........#
############
```

halls room 7:
```
############
#H.........#
#.####.....#
#.#..#.1...#
#.#..+.....#
#.#..#.....#
#.####.2...#
#..........#
#.^...?....#
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
