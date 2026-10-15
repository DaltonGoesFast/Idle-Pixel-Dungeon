# Changelog

## Unreleased
- Status pane: the torch and food bars are now the same height as the HP bar (they were nearly twice as tall and spilled past the pane frame). They share its left and right edges, their icons fit the bar, and the level badge is no longer cramped. New layout test covers cover and inner screens.

## 0.28.0
- Delve Brought/Found chips stay at 48px (font_size*2 was 80px on the Fold cover and starved the corridor) (+test).
- UI smoke test: "a talent was learned through the UI" no longer fails at random (about 1 in 3). It is now checked when Learn is pressed, because a later death in the late-boss chain wiped the hero's talents before the end-of-run check.
- Goo is harder and closer to SPD: HT 70->90, it regenerates in water, and its arena has two water pools. First-attempt win rate for a fresh hero goes from 87% to 27%. Safety nets: each Goo death leaves Goo 15 HT weaker (floor 70, and at the floor it no longer enrages) and restocks 2 Potions of Healing (+tests).
- Late-game gold sinks: Masterwork Forge upgrades past +3 up to +6 with a max Blacksmith (3.2k/5k/7.2k gold), Guild retraining after a death (20 x Lv^2 gold per level, up to 2 below the best level reached), patrol provisioning fee (half a full patrol's gold), and normal upgrades cost 10 x Lv^2 gold. Deep sim median stash gold after 40 expeditions: 37.5k -> 2.9k (+test).
- Heroes ring swap list: Ring of Energy shows "Charges +1" only for a hero whose staff gains the charge (the Mage); Warrior, Rogue and Huntress see just "HP +4" (+test).
- Strength: each delve Strength milestone gives its Potion of Strength once per hero life (it was every expedition, so Str reached 111-152 after 40 expeditions; now 18-20) (+test).
- Expedition and campfire texts show a recommended level (sewers 4, prison 6, caves 9, city 16, halls 22), picked from the boss probe for a smooth curve. No boss stat changes (+test).

## 0.27.1
- Patrol progress survives a relaunch. Fast-forward time is saved, so a patrol no longer snaps back to 0% when the game restarts (+test).

## 0.27.0
- Delve screen: taller corridor, encounter cards as windows over it, SPD icon toolbar with a Menu for Settings / Scroll of Passage / Abandon, floor pips, torch and food bars with icons, Brought vs Found (lost on death) rows, low-HP red edges, and a campfire bank preview. Encounter windows keep reward toasts but no longer embed the delve log.
- Rogue: Cloak of Shadows has 3 charges per fight like SPD (was 2); Rogue death rate now in line with other classes (+test).
- Owed Scrolls of Upgrade return straight to the Camp stash on the next boss kill, so the same run can no longer lose them again (+test).
- Heroes cap at level 30 like SPD (was unlimited: Lv100+ in long campaigns); over-cap saves load at 30 (+test).
- Expeditions saved by older versions (before the backpack) load and continue instead of erroring (+test).
- Alchemy: condense 20 dew into a Potion of Healing (dew had no use) (+test).
- Guild supplies: the 3-ration crate slot shows "x3" (and its info says "Gives 3 Rations"), so it no longer looks like a second Ration slot (+test).
- Goo death spiral: Guild sells Potions of Healing (30 gold), Goo always drops one, and a death tops gold up to 30 (+test).
- Food scaling: every boss kill adds 2 rations to the belt; Guild Lv2 sells a 3-ration crate for 25 gold (+test).
- Ring, potion and scroll icons are centred on their real SPD size (missing item rects), and tiny sprites like rings draw one scale step larger (+test).
- Facility headers show "Lv level / max" (plus the Scroll cap only when it blocks), and a cap below the level is repaired; no more "Lv 2 / 1" (+test).
- Screenshot harness renders at 2x and downsamples, so delve-log shots no longer lose 1-px letters (the game was fine at native resolution).
- Screenshots: the staged gold pickup pop no longer leaks from delve_walk into the enemy/room/auto shots.

## 0.26.0
- Identified rings, potions, and scrolls show SPD's small type glyph from item_icons.png in the top-right of the slot. The blue shield is Ring of Tenacity and Potion of Shielding.
- Spare rings break down at the Forge into 5 Gold and 1 Arcane Resin. Extras keeps every worn ring and one spare of each (+test).
- Encounter result window gives each line room, so a short victory no longer clips or shows a scrollbar.
- Floor-clear and other delve menus keep toasts inside the card, above the buttons; when no menu is open, toasts do not float beside the delve log.
- Softlock fix: starter weapon + cloth armor when gear is cracked, free Patch up at the Forge when broke, relief ration/torch, 1 iron ore per floor (+test).
- Scrolls of Upgrade lost on death are owed and return on the next boss kill (any hero); shown in Camp.
- Smooth delve: no per-frame UI rebuilds, 60 fps corridor with a single-quad light, smooth Speed x3 scrolling.
- Auto Battle toggle: plays fights only; doors, rooms, floors, and campfires wait for you (saved setting, +tests).
- Pickup feedback (SPD gold/dew/item sounds, +N icon pops, glow) and a colour-coded SPD-style log of finds, fights, traps, choices, warnings, floors, level ups and auto decisions.
- Removed the alarm sound everywhere (soft door sound / haptic instead).
- Item icons never below 2x (32 px): backpack potion/scroll buttons and carried rings no longer render as dots.
- Cracked rings/artifacts repairable at the Forge and included in Repair all.
- Cracked items keep their colours (red frame + "!") so ring icons stay visible; backpack potion icons scaled properly; old-save ring ids migrated (+tests).
- Forge/Guild quantity picker (-/+ and slider, max = affordable/cap, live total cost) for buying, making and upgrading.
- Forge "Repair all" with total cost; disabled when nothing is cracked or unaffordable.
- Live materials header on Forge and Guild.

## 0.25.0
- Tutorial tips laid out by containers: always on screen with margins, wrapped, fade in once sized (+test).
- No stretched sprites: all UI sprites integer-scaled PixelIcons; every item id resolves to a visible SPD icon (+test).
- Touch scrolling everywhere: drag from buttons/slots, momentum, wide scrollbars, no nested conflicts (+test).
- Floor label can never exceed its biome (+test); screenshot state leak fixed.
- Delve corridor: bigger sprites, lighter walls, door states (closed/open/locked/crystal), 9 prop types, embers, special-room icon in the doorway.
- Garden and Sacrificial Fire rooms reworked; Yog/Halls retune (hallsrun 3/4).

## 0.24.0
- Armor tier visible on hero sprites everywhere (combat, delve, camp, portraits, paperdoll) + test.
- Animated delve corridor above the Delve Bar (biome tiles, run anim, torchlight, parallax, ambient doors/mobs, pickup pops, encounter stop).
## 0.23.0
- Special rooms (8 SPD-style), Yog fist phases, perf pass (LOS cache, camp 15 fps), icon-centering audit (PixelIcon, SPD item rects, icon_audit screenshot).







## 0.22.0
- The delve character screen is side by side on the inner screen. The unused misc slot is removed.
- 6 alchemy recipes for found potions and scrolls; brewing with an unknown ingredient identifies it.
- Toasts show inside delve panels too.

## 0.21.0
- New Diablo-style character screen (paperdoll) in the Camp Heroes window and the delve backpack, with slot swaps and stat deltas.
- Camp NPCs play their SPD idle animations. Hold an item to compare it with what your hero has equipped.
- Toasts show inside open windows. Talents use SPD-style icon buttons. Alchemy has an SPD-style pot.
- Added tests for door open/close, grass layering and trampling, and the paperdoll.

## 0.20.0
- New Surface Camp hub: a drawn camp scene where you tap the NPCs to open the Forge, Enchanter, Alchemy, Guild and Stash.
- Hub controls: portrait hero selector, biome picker (start past biomes you have cleared) and a big Delve button.
- Facility windows show upgrade previews and progress bars. Items appear in SPD item-slot grids; tap a slot for info.
- New screenshot steps for every Camp window.

## 0.19.1
- Fix: doors now open while a character stands in them, with SPD door frames layered over the occupant.
- Fix: tall grass no longer cuts off the tops of characters. Grass you walk through is trampled to short grass, as in SPD.
- New `terrain` screenshot step.

## 0.19.0
- Items with ID: 3 new rings, artifact slot with 3 artifacts, 6 unidentified potions/scrolls usable from the backpack; boss artifact drops; build.sh renders screenshots (non-blocking).
- Fix: identified potions/scrolls were reset on load.

## v0.18.0 — King phases
- King of Dwarves: lifelinked to his Risen Dwarves (takes 2/3 damage while they live), enrages at half HP, throne cracks at 1/4 (no more summons).
- Camp tabs fit the cover screen (icons, selected tab named).
- Full 25-floor run simulated in tests; UI smoke test plays through the Halls to Yog-Dzewa.

## v0.17.0 — Demon Halls
- New biome: Demon Halls, floors 21-25, after the Dwarf City. Succubus, Ripper Demon, Evil Eye, Scorpio.
- Final boss Yog-Dzewa: never moves, hatches larva, sweeps your row and column with its gaze.
- Tier-5 Greatsword and Plate Armor at the Blacksmith (Lv3).

## v0.16.2
- SPD icons on camp tabs, delve toolbar and fight buttons.
- Delve resource row: icons and numbers aligned and grouped; "Ignore both" is a grey secondary button.
- Fight messages go to the combat log instead of floating over it; top wall of the arena visible; barrier shown once (HP bar shield).

## v0.16.1 — SPD status pane
- Status pane rebuilt from SPD's StatusPane: level number in the portrait badge, filled HP bar with shield overlay and centred HP/MaxHP, name beside the portrait, buff icons, depth and danger count, compact Torch/Food (or Barrier) row.
- Toasts no longer cover the arena; the combat arena fills more of the cover screen; hint text is larger.
- Correct SPD buff icons on enemies.

## v0.16.0 — SPD gameplay graphics
- SPD wall autotiling with raised wall faces and wall tops drawn over characters; floor variants; water/chasm/door/grass stitching; arena framed by walls.
- Full SPD character animations (idle/run/attack/die) with facing flip and death fade.
- SPD health bars, status icons and floating damage numbers.
- Smooth SPD-style fog of war + torchlight; bigger, integer-zoomed combat camera.

## v0.15.1
- Version label on Camp and Settings (check you are on this build!).
- SPD status pane (portrait, HP/Torch/Satiety or HP/Barrier bars) in delve and combat.
- SPD toolbar buttons with icons; chrome progress bars, sliders and scrollbars; outlined pixel text.
- Pixel font forced project-wide and snapped to whole-pixel sizes.

## v0.15.0 — 2026-10-15
- **Dwarf City (floors 16-20)**: continue from the DM-300 campfire. SPD City tiles, water and music (city 1-3, boss), 4 new rooms and a boss arena; Prison/Caves door and special events now appear in the City too.
- New mobs: **Dwarven Ghoul** (rises once with half HP 2 ticks after dying, red tile on the corpse, unless it was the last enemy), **Dwarf Warlock** (piercing shadow bolt), **Dwarf Monk** (attacks twice per tick), **Golem** (slow, huge hits, DR 7).
- **King of Dwarves** boss: alternates raising the dead (2 marked tiles, Risen Dwarves appear 2 ticks later) and a 3x3 shadow blast with a 2-tick fuse; enrages below half HP; his dwarves crumble when he dies.
- Tier-4 gear for the City: **Longsword** and **Scale Armor** (Blacksmith Lv3).
- The bot (Hint / Auto / sims) now runs out of large red areas it can't leave in one step instead of standing in them.
- Caves retune after the smarter bot: Gnoll Shaman and Cave Spinner +1 damage, DM-300 HT 160.
- Tests: 159 checks; the UI smoke test now continues from DM-300 into the City and beats the King of Dwarves.

## v0.14.0 — 2026-10-15
- **SPD-style lighting in fights**: torchlight around the hero that shrinks as the torch burns down (radius 6.5 -> 3.2 tiles, 1.8 in darkness), a soft falloff, a warm flickering hero glow, and fog over tiles out of line of sight. Enemies outside the light are dimmed but stay readable. Settings -> "Lighting & fog" turns it off.
- **Animated water**: SPD's own water textures (sewers/prison/caves) scroll slowly under the water tiles.
- **Tall grass sways** a pixel or two.
- **Particles**: blood on HP hits (more on surprise), sparks on blocked/Barrier hits, purple motes on magic, green on poison, splashes when stepping into water. Capped at 160 live particles.

## v0.13.0 — 2026-10-15
- **SPD look**: the UI now uses Shattered Pixel Dungeon's own `chrome.png` 9-patches (window frames, red/grey buttons, tabs, toast frames) and SPD's pixel font, scaled by whole pixels for the Fold cover/inner screens.
- **Talents** (data/talents.json): 2 tiers x 4 SPD-named talents per class. Tier 1 points at Lv3 and Lv5, tier 2 at Lv9 and Lv12 (pick 2 of 4 per tier). Learn them on the Camp Heroes page or mid-delve; a level-up during a delve opens the Talents card. Talents reset with the level on death.
- **Backpack (in-delve inventory)**: 8 gear slots. Equip / unequip / imbue (Mage wands) / drop mid-delve with a stat comparison (Dmg/DR/Barrier/HP/Bolt before -> after); use potions, rations and torches outside fights. In a fight, the new **Bag** button swaps gear for 1 tick. A full backpack holds new loot until you drop something or leave it. Gear you brought from Camp is marked "(yours)": it can't be dropped and comes home even on death (cracked, like equipped gear).
- Backpack and Talents open over door/campfire cards without losing them (the Settings card no longer drops the current card either).
- Caves mobs +1 damage and DM-300 HT 160 to compensate for talents.
- Build: tools/build.sh now fails on any GDScript runtime error in the tests.
- Tests: 152 checks; the UI smoke test learns a talent through the mid-delve card and opens the combat Bag.

## v0.12.0 — 2026-10-15
- **Mage in the Caves**: the Mage's Staff (heirloom) gains +1 melee damage every 6 hero levels. Caves sim 4/10 -> 6/10.
- **Warlock rework**: staff bolts heal a third of the damage dealt; kills heal 20% of the foe's max HP. Caves 4/10 -> 8/10.
- **Toned down**: Berserker +20% (was +30%) below half HP (10 -> 9/10); Battlemage restores a charge every 5th melee hit (was 2nd; 10 -> 8/10).

## v0.11.0 — 2026-10-14
- **Guided first fight**: the first non-boss fight on a save shows a 3-step banner (Move -> Attack -> Finish) with a glowing tile marking exactly what to tap; ranged heroes skip straight to step 3 once they hit. It never blocks input, ends with a short recap, is remembered, honours "Skip all tips", and replays with "Replay the tutorial tips".
- Tests: UI smoke checks the guided fight appears, highlights a tile, completes and is not shown again.

## v0.10.0 — 2026-10-14
- **Tengu's Mask**: beating Tengu with a class grants its mask; choose one of two permanent SPD subclasses in Camp -> Heroes.
- Subclasses (simple versions): Warrior Berserker (rage +30% below half HP) / Gladiator (combo +1 per hit, max +3); Mage Battlemage (every 2nd melee hit restores a staff charge) / Warlock (kills heal 35% of the foe's max HP); Rogue Assassin (surprise +1x, +1 Cloak) / Freerunner (attacks 20% faster, +1 DR, +1 Cloak); Huntress Sniper (bow +1, ignores DR) / Warden (+2 Barrier, +1 DR, tall grass heals).
- Caves sim (Lv8/Str14, tier-3 gear): Rogue 0/10 -> Assassin 7, Freerunner 8.
- Tests: 128 checks; the UI smoke test earns the mask from Tengu and picks a subclass through the Heroes page.

## v0.9.0 — 2026-10-14
- **Caves biome (floors 11-15)**: continue from the Tengu campfire. SPD Caves tiles and music, 4 new rooms, crystal vein special room and den door.
- New mobs: Vampire Bat (drains HP), Gnoll Brute (enrages), Gnoll Shaman (piercing zap), Cave Spinner (poison).
- **DM-300 boss**: telegraphed rockfall and toxic gas, supercharges below half HP.
- Boss campfires restore +50 torch/satiety; potions heal max(10, 30% HT); supplies capped at 10.
- Tests: 117 checks; UI smoke plays through Tengu into the Caves and beats DM-300.

## v0.8.0 — 2026-10-14
- **Mage vs Tengu**: the Mage's Staff gains +1 charge at hero Lv7 (and every 7 levels, `charge_per_levels` in heroes.json). Deep-run Sewers+Prison clears: Mage 3/10 -> 6/10; Sewers unchanged (9/10).
- **Toasts no longer cover tutorial cards**: they are hidden while a tip is open and reappear when it closes.
- **Delve speed setting** (Slow 0.5x / Normal / Fast 1.5x / Faster 2x) in Settings; the in-run x3 button stacks on top.
- Tests: 110 checks; UI smoke checks the speed multiplier and the toast/tip behaviour.

## v0.7.0 — 2026-10-14
- **First-run onboarding**: a 3-page welcome (the Camp -> Delve -> fight -> extract loop and what death costs) on a brand-new save, followed by a supplies tip on the Delve tab.
- **Contextual tutorial tips** (17, data/tutorial.json) shown once each as a modal card: Delve Bar, first fight (2 pages), Surprise, red-tile telegraphs, traps, boss fights, Door Choices, special rooms, floor cleared / hidden doors, campfire, Forge, Journal, and what happens after a death or an extraction. The delve bar and Auto play pause while a tip is open.
- "Next" / "Skip all tips" on every card; Settings has "Tutorial tips ON/OFF" and "Replay the tutorial tips".
- Tests: 109 checks; the UI smoke test checks that the welcome appears on first run, that the core tips fire during real play, and that dismissed tips stay dismissed.

## v0.6.0 — 2026-10-14
- **Settings** (Camp tab and an in-delve Settings card): SFX / music sliders with live percentages, **haptics** toggle (vibrates on damage, traps and telegraphs; Android VIBRATE permission added), **text size** (Small / Normal / Large / Huge, relayouts instantly), tutorial-tip toggles, and the Developer tools are now hidden behind a toggle.
- **Music**: every biome rotates through its SPD tracks per floor (Sewers 1-3, Prison 1-2) with a crossfade; the Camp theme changes after your first Goo kill.
- **Journal tab (meta-progression)**: 10 account milestones with progress bars and one-time stash rewards (data/milestones.json), class unlock progress (now data-driven `unlock_rule`s), per-hero biome clears and lifetime stats (kills, traps found, hidden doors, extractions...).
- **Codex** (Journal -> Codex): bestiary with sprites and generated ability text, traps and items. Entries unlock when you meet them; unknown ones show as "???".
- Save format v2 with a real migration step (back-fills Goo kills so existing saves earn their milestone).
- Tests: 105 checks (milestones, unlock rules, stats/codex from fight results, v1->v2 migration, settings persistence); UI smoke opens the Codex, changes text size and opens the delve Settings card.

## v0.5.0 — 2026-10-14
- **Traps** (SPD Worn Dart, Gripping, Teleportation, Poison Dart) on the combat grid: `^` visible, `?` hidden. Anyone stepping on one fires it once. Mobs know where traps are and path around them, but shove/slam/surprise knockback can push them in. Tap a revealed trap to inspect it.
- **Search** button in fights (2 ticks): reveals hidden traps nearby. Rogue (keen eyes) spots adjacent hidden traps as she moves; Rogue and Huntress search a wider radius.
- **Hidden doors**: every cleared floor offers "Search for hidden doors (-10 torch)" - 50% chance (Rogue: always) of a secret cache. New special cards: Trapped Corridor (Rogue-only disarm option), Suspicious Wall.
- **Prison biome (floors 6-10)**: SPD Prison tiles and music, 4 new Prison rooms full of traps, Skeleton (telegraphed bone burst on death), Crazy Thief (steals gold and flees), DM-100 (telegraphed zap), Prison Guard (chain pull). After Goo, the campfire offers "Extract" or "Descend into the Prison" (nothing is banked until you extract).
- **Tengu** (floor 10 boss): telegraphed shurikens, blinks to the far side every 15 HP lost; below half HP lobs 3x3 bombs with a 2-tick fuse that also hurt other mobs.
- Prison-only Door Choices and specials (Locked Cell, Guard Armory); Offline Patrols work in every cleared biome.
- **Balance**: Goo pumps every 4 actions (every 3 below half HP) and has 70 HT, so the danger ramps up instead of spiking at the start. CombatBot no longer dodges into corners and drinks potions based on incoming damage. Rogue gains keen eyes + wider search.
- Torches/rations found in the delve go straight into usable supplies.
- Tests: 95 checks (traps, poison, search, keen eyes, Prison fights, Tengu, skeleton burst, deep runs); UI smoke now fights Tengu through the real UI with the Prison tileset.

## v0.4.0 — 2026-10-14
- **Warrior Slam**: new ability that hits every adjacent enemy and knocks them back (and into chasms, for a kill).
- **Mid-fight save/resume**: the fight state is serialized into the run, so killing the app mid-fight resumes on the same turn.
- Pending door card persists across app kill; the game also saves on pause, focus-loss and close.
- **Wand of Lightning** (Birch Wand, unidentified): bolt dmg 7; when the target stands in shallow water, the shock conducts to everyone in the connected water, the hero included (half damage).
- Water tiles are now real (animated blue), and there's a new flooded room.
- Tests: 78 checks (lightning chain, slam, combat round-trip); UI smoke test simulates an app kill.

## v0.3.0 - all four classes
- **Rogue** (Cloak of Shadows: hide 2 ticks, next hit is a Surprise; Dagger x2 surprise) - unlocks at Sewers floor 4.
- **Huntress** (Spirit Bow: unlimited arrows in line of sight; fast Studded Gloves) - unlocks after brewing 5 potions.
- Tap a distant enemy to inspect it (HP, damage, DR, speed, special attack).
- Attack lunges, arrow streaks, cloak transparency, new SFX.
- Balance from full-run simulation: torch drain 0.4, Goo HT 50 / DR 0, non-Warrior Barrier 4, gloves 3 dmg. Smarter bot (Hint/Auto) avoids getting cornered by Goo.
- Fixes: potions used in a lost fight were refunded; heirlooms no longer crack.
- `RunSim` + `[fullrun]` test: 10 seeded full expeditions per class.

## v0.2.0 - base game architecture
- **Balance:** crabs beatable (dmg 2 / DR 1 at 0.5 ticks), Warrior Barrier 10 (Broken Seal), Goo boss tuned (HT 55). Bot-verified: starting Warrior wins every sewer encounter.
- **Architecture:** all content in `data/*.json`; autoloads `DB`, `GameState`, `SaveSystem` (versioned JSON save, autosave), `Sfx`; pure `Combat`/`Delve`/`CombatBot`; screens split into Camp / Delve / Combat.
- **Camp:** tabs for Delve loadout (rations, torches, potions, Scroll of Passage, Starter Elixir), Heroes (equip, imbue wands), Stash, Forge (forge/upgrade/repair, caps), Alchemy, Enchanter (real-time ID queue, scribe Passage), Guild (supplies, Offline Patrols), Settings (volume, dev tools).
- **Delve:** floors 1-5 of the Sewers, seeded event schedule, Door Choices, 5 special-room cards, Strength milestones, darkness/starvation penalties, campfire extraction after Goo, Scroll of Passage.
- **Combat:** Goo boss with pump-up telegraph, Gnoll throw telegraph, Mage class (staff bolt, Firebolt burns grass), heavy weapons (1.5 ticks), potions, Hint & Auto (CombatBot).
- **Juice:** tweened movement, hit flash, floating damage numbers, bolt streaks, blasts, SPD sounds & music.
- **Death rules:** pack lost, gear cracked (repair at Forge), hero reset to Lv1 / 10 Str.
- **Tooling:** tests (59 checks), UI smoke test, screenshot capture, APK verifier, `tools/build.sh`, generated balance/content docs.

## v0.1.2
- Back to the official Godot 4.7.2 Android template (the stripped custom template had no WebP/text server -> no textures/text).

## v0.1.1
- Compatibility renderer (fixes torn scanlines on Adreno), pixel snapping, integer grid scale, scrollable log, cover-screen layout fix.

## v0.1.0
- First vertical slice: camp -> delve bar -> 8x8 deterministic combat -> loot/extract.
