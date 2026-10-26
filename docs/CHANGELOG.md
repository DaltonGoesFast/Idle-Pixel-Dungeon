# Changelog

## Unreleased

- PS Vita export preset for the Godot 4 Vita runtime (960×544, two worker threads, touch layout, face buttons and D-pad). Phone, desktop, and web layouts stay as they are. Saves on a Vita go to `ux0:/data/idlepd-saves/` (DECISIONS #244, +tests).

## 0.50.4
- The player-facing title is Idle PD.
- Launcher icons: Android adaptive FG/BG/mono, Windows `.ico`, and web favicons from `assets/branding/` (DECISIONS #243, +tests).

## 0.50.3
- Update checks re-run when the app resumes (and periodically from Camp), so Android no longer needs a force-close to notice a new release. Camp Settings shows a red badge when an update is ready, and the header Update button appears as soon as the check finishes (DECISIONS #242, +tests).
- A new game starts with free Worn Shortsword and Cloth Armor as party camp gear (visible on the paperdoll). Empty camp slots on load get the same defaults. They never crack; forging a better sword or armor replaces them (DECISIONS #234).
- Cracked rings and artifacts point to the Enchanter for repair, not the Forge.
- The status pane shows SPD depth and floor-feeling icons instead of plain floor text.

## 0.50.2
- Expedition supplies show the pack's carry cap even when the stash is short, and a Buy button on a short row purchases one at the Guild or Enchanter price (DECISIONS #238, +tests).
- A Scroll of Passage can be read from the Bag during a fight. Read asks first, then extracts and banks the pack the same way it does outside combat. The fight ends on Read, so no extra turn is spent, and Auto Battle never reads it (DECISIONS #239, +test).
- Forge item windows shrink to their content. A longer title such as Forge Worn Shortsword no longer leaves a tall empty area under the need line; a note that is taller than the screen scrolls instead (DECISIONS #240, +test).

## 0.50.1
- Forge weapon and armor are shared party gear: craft Scale once and every hero who meets the Str requirement wears it. Under-Str heroes keep Cloth / starter melee instead of fighting crippled. Found weapons stay unique per-hero overrides; Mage Staff and Huntress gloves still fill melee for those classes. Camp gear never cracks on death; found weapon overrides still do. Old saves keep the best forge copies as the camp set (DECISIONS #234, +tests).
- Floors can feel XL, Secret, or Traps, with a quota per biome, and rooms and encounter packs are roughly doubled.
- Combat starts fitted to the room. Drag to pan, and pinch or the mouse wheel to zoom.
- On a very wide Mobile layout the D-pad stays capped so PC fullscreen stays usable, and the side column fills the leftover width.
- Desktop has a Live Editor (top-row 0, or its own window beside the game) for camp and UI layout, text, and balance, with search, undo, and a diff before save.

## 0.50.0
- Enemy vision uses SPD shadowcasting instead of Bresenham, so corner peeks match vanilla FOV and no longer strip awareness / grant Surprise by mistake. After losing you, mobs wander to deterministic search cells instead of freezing in place (DECISIONS #176, +tests).
- Mobile combat is built around an 8-way D-pad with Wait in the center, Attack showing the equipped weapon, and a chrome row for Search, Shove, Slam, and Cloak. The portrait grid shrinks so those controls stay on screen, tips fold into the log, and Wait and Bolt stay put when a status tip wraps. The potion button says Heal and uses the Potion of Healing sprite.
- Settings folds into expandable categories, like the vendor Upgrade tabs.
- The web build shrinks to fit when the browser window is smaller than the phone design size.
- Rats stay in the Sewers. Prison bones fights use skeletons and a thief. A thief who gets away unhit for a few turns escapes with your gold, and a steal is 5% of the gold in your pack.
- A new game starts with empty supplies and 134 gold, enough to buy a full first-delve pack at the Guild (3 rations, 3 torches, 2 healing potions). There is no starting arcane resin; the leftover Scroll of Passage gold stays spare until resin drops. Early runs still get a free Scroll of Passage.

## 0.49.3
- Desktop interface mode: PC combat can use a full-bleed grid, a roomier bottom toolbar, and a combat log on the left. Settings switches Mobile and Desktop and remaps the combat keys. The toolbar Menu opens the same Settings panel as Camp and Delve. Status and delve bars stay phone-width on ultrawide screens, and SPD bar fills keep their rounded corners when they stretch wide.
- Tapping Bolt a second time auto-aims at the last attacker, or the nearest foe, like SPD's QuickSlot.
- Floor finds drop less dew (1, was 2-3) and less gold, so early delves stop turning into free potions.
- The delve no longer repeats "Collected this delve"; the Found bar already shows the haul. Toolbar slots stay the same height when they show a count.

## 0.49.2
- Android home screen can show a patrol widget (a short countdown on the Fold cover, a list when it is taller) and, if you turn on Patrol alerts in Settings, a notification when a patrol is ready to recall. Alerts are off until you enable them. PC and the browser are unchanged, and the game still runs if the Android plugin is not in the build (DECISIONS #229, +tests).
- The post-fight "Wake at Camp" button (and other UIKit buttons) no longer stretch into a tall empty slab when a wrapping label sits beside them. Defeat keeps its message and the button in a normal-height column (DECISIONS #228, +test).
- Camp facilities go to Lv5 (Scroll budget still 22). Blacksmith L1 is repair-only; craft tier matches level (T5 at L5); gear upgrades cap at +1/+2/+3 from L2/L3/L4 (no masterwork +4..+6). Guild pack 3/4/5/7/10 and patrols 2/4/8/12/16h; Alchemy belt 2/2/3/4/5; Enchanter ID/slots/caps extend through L5 (DECISIONS #227).
- Until you beat Goo or use three of them, each delve that starts without a Scroll of Passage gets a free one so you can bank the pack early; unused free scrolls do not enter the stash (DECISIONS #226).
- Camp overhaul: drifting clouds and twinkling stars (firelight still clipped off the sky), all unlocked heroes seated around a roomier fire (tap to select), bubbling alchemy pot with scrolling water, Expedition biome pick via levelicons, and facility "!" when a Scroll can unlock a slot (DECISIONS #225). The camp no longer collapses on the first frame. Seats spread so the four classes are not stacked on the fire. Portrait camp packs NPCs toward the fire and shows patrols in the dock. Wide layouts zoom out, clouds drift slower, a full grass row sits on the horizon with NPCs on top, and web text stays crisp.

## 0.49.1
- Camp horizon grass no longer covers the Forge and Enchanter on wide fullscreen layouts. Side strips stay when the scene is wider than tall, and the NPCs, the hero, and the barrels paint above the grass (+tests).

## 0.49.0
- Class heirlooms and late-game trinkets catch up to City/Halls: Mage's Staff scales with wand level (`+2` per imbued level, `dmg_per_levels` 3) and Battlemage recharges every 3rd hit; Spirit Bow is `3 + level/2` and Warden pierces half DR on surprise/grass shots with stronger Barrier/DR and scaled grass heal; Ring of Force lifts Tier 1 weapons toward the forged sword your Strength can equip (Greatsword at 18+); Gladiator combo is +10% per stack; Ring of Might grants Strength and HP; artifacts level from a 24-hour use meter (patrol + 8h per boss) instead of fight XP; Auto Battle ambushes are rarer (DECISIONS #223, +tests).
- Economy sinks scale with tier: forge, upgrade, and repair costs rise for T4/T5 (and need dark gold / resin), rings and wands pay resin + dark gold + gold up to Desk cap `+0/+1/+3`, and Blacksmith Lv1→2 is ore+gold only (dark gold on Lv2→3). Patrol efficiency caps at 1.0, gear+perk bonuses add to a 1.50 ceiling, biome yields fund about one Tier 5 weapon per four geared Halls patrols, and the fee is one hour of expected gold. Early dark gold leaves Sewers/Prison room rewards; passive gold and event HP costs scale by biome and max HP (DECISIONS #222, +tests).
- Death still resets a hero to Lv1 / 10 Strength, and now also clears their cleared biomes so the delve picker and patrols start at the Sewers again (boss kills, mask, and subclass stay). Cloth Armor and each class's starting weapon never crack, including upgrades. Camp compare and the paperdoll show armor Barrier even when half max HP caps the hero total, Potion of Shielding scales like Healing (`max(10, 30% HT)`) then clamps to that half-HP ceiling, and free Patch up only repairs tier 1–2 weapons and armor (DECISIONS #221, +tests).
- Weapon tiers pull apart: T2 weapons scale slower (Shortsword 7 at +0, Spear 8), T4/T5 scale faster (Greatsword 20 at +0, Longsword +3 = 25), and being under Strength divides weapon damage instead of subtracting 2 per point. Surprise attacks still hit for 1.5x (Assassin 2.5x) but now subtract enemy armor afterward — stealth blades and Assassins pierce half of it — and no longer knock foes back. Worn Dart traps deal `3 + floor/2` damage (DECISIONS #220, +tests).
- On Windows, `tools\playtest.bat` runs the headless suites (`run_tests`, then `ui_smoke`) and saves each run under `builds/playtest/`. When a run finishes it prints pass or fail for each suite and the log path, then waits: press a key for the next numbered run, or close the window to stop. If the console build is not installed, it uses the editor exe at `C:\Users\dalto\Documents\My Games\idlrPD\Godot_v4.7.2-stable_win64.exe` (DECISIONS #219).

## 0.48.0
- Higher-tier armor now blocks much more damage and grants more Barrier per upgrade than Cloth and Leather: Cloth (1 DR, 1 Barrier) and Leather (2 DR, 2 Barrier) gain +0.5 DR and +1 Barrier per level, Mail (3 DR, 4 Barrier) gains +1 DR and +1 Barrier, Scale (5 DR, 6 Barrier) gains +1 DR and +1.5 Barrier, and Plate (7 DR, 8 Barrier) gains +1.5 DR and +2 Barrier. Wearing armor above your Strength now divides its DR by (1 + missing Str) and gives 0 armor Barrier, Dwarf City and Demon Halls enemies hit harder in melee to match tier-4 and tier-5 armor, and the Stash, Compare and Blacksmith windows now show armor Barrier alongside DR (DECISIONS #218, +tests).

## 0.47.0
- The Victory card fits the screen on near-square browser windows such as Chrome on the unfolded Fold: the arena gives up width so the side column (the hero's bars, the card and its buttons, the log) always fits, where before the card, the floor label and the bars ran off the right edge. Each line on the card now shows its SPD sprite (the gold coin, or the potion, scroll, ring, weapon or material found), found items are drawn in SPD's yellow, and a long list scrolls inside the card (DECISIONS #217, +tests).
- Iron Ore now has its own silver-grey ore icon instead of a darker, olive copy of the Dark Gold sprite, so it no longer looks like gold anywhere (Stash, Forge, Victory drops, pickups). The ore pickup icon in the delve used to show plain Dark Gold; it shows Iron Ore now too (DECISIONS #216, +test).
- Using a potion, scroll, ration or torch from the Backpack now shows what happened in a small pop-up over the Bag (the item's sprite and name, the effect, and any milestone it reached), with OK or a tap outside to close it, instead of printing at the top of the Bag window where it was out of sight once you had scrolled down. The Bag stays open underneath. A Potion of Healing now says how much it healed, and a use that can't happen says why (full health, not hungry, torch still bright) instead of doing nothing (DECISIONS #214, +test).
- The Cell Block room's thief stands in front of the prison cells again. Since the cells are drawn whole, he was drawn behind their bars, as if locked in (DECISIONS #213, +test).
- The blue Barrier on the small HP bar over the hero stays blue with many segments. Against weak foes it splits into 9-10 segments only 3-4 pixels wide on a phone, and the dark dividers between them were 2-3 pixels, so the bar looked like dark stripes. Dividers are now at most a third of a segment wide (at least 1 pixel); the segment count is unchanged (DECISIONS #210, +tests).
- Weapon text fixes: the Forge's Worn Shortsword slot now shows its whole name on two lines instead of "Worn Short…", the Compare window drops the "Reach 1 / 1" row unless a Spear, Glaive or Whip is involved, and the Scimitar's speed reads 1.25x instead of 1.2x. The CHANGELOG now says the gnoll strongbox only appears from the Caves (DECISIONS #215, +tests).
- Barrels in delve rooms are whole again. The Larder's and Armory's barrels were drawn as only their lower half and pushed down 4 pixels, so they lost their top rim and sat half a row off the floor. They now use SPD's full barrel (the base in its cell plus its top on the cell above), lined up with the floor tiles like the barrels in the corridor, and no longer stand in front of the room's door. The same fix applies to the Cell Block and Prisoner rooms' prison props, the Abandoned Shop's rocks and barrel, and the Crystal Vein's crystals, which were also missing their tops. The camp's barrels were already whole (DECISIONS #213, +tests).
- Tutorial tips are always the top window. A tip used to open under the window it explains (the door choice tip appeared under the doors card, and the Abandoned Shop's tip hid behind the shop window and blocked its buttons, a softlock); tips now sit on their own top layer above every window, panel, encounter card, result and Defeat window on every screen, even one that opens after the tip, and taps go to the tip first. Tips keep their look and their dimming (DECISIONS #213, +tests).
- Settings has a Wipe save data button on every platform (Android, Windows, web and the editor), above the credits, with a confirm: Wipe permanently deletes heroes, camp, gear and milestones; Cancel keeps everything. The old Wipe save in Developer tools is gone so there is one path. The anonymous telemetry id is kept (DECISIONS #212, +tests).
- An upgraded Round Shield or Greatshield's item window now shows the block it really has: a +1 Round Shield says "blocks 0-5 damage" (it said 0-4 next to its +3 DR), as in SPD (DECISIONS #207, +test).
- Auto Battle and Hint no longer burn Cloak of Shadows charges on easy fights. They spend one on a boss, an emergency (low HP, or a fight that could kill you), a full cloak (the win refills it), an Animated Statue, 3+ foes, or a fight projected to cost half your HP, and they keep the last charge for bosses and emergencies, so the Rogue reaches Goo and Tengu with a full cloak. A Scroll of Recharging's cloak charge now never goes above 3 and stays until spent, and a fight saved by an older version no longer shows "Cloak (4/3)" (DECISIONS #211, +tests).
- Barrier is now blue on the hero's HP bar in combat, both in the status pane (where it was grey) and on the small bar over the hero (where it hid under the green), and it's split into segments, one per enemy hit it will stop: Barrier divided by the hardest-hitting enemy's damage after armor (at least 1, the chip rule), up to 10. The segments drop as hits land. The tutorial now says so (DECISIONS #210, +tests).
- The Forge now makes only each tier's basic sword: Worn Shortsword (3 ore, 20 gold), Shortsword, Sword (Forge Lv2, 8 ore and 2 dark gold, where the Mace was), Longsword and Greatsword. Every other weapon is found. The Animated Statue (every biome) now guards a random weapon instead of a Shortsword, and the guard's footlocker (Prison and deeper) and the gnoll strongbox (Caves and deeper) hold one too, picked with SPD's tier odds for the floor (tier 2-3 early, tier 4-5 deep). Found weapons are identified +0. Daggers and Maces you already have stay (DECISIONS #208, +tests).
- Every Shattered Pixel Dungeon melee weapon is now in the game, with SPD's own damage, Str, upgrade scaling, speed, reach, accuracy, blocking and surprise rules and its SPD sprite and text. The Spear and Glaive hit 2 tiles away and the Whip 3 (walls and bodies in the way block it, as in SPD); tap a foe in reach to swing, and Auto Battle waits for foes to step into reach. The Mace is no longer slow: it swings at normal speed for 3-16 (9) and is "rather accurate", so it now lands some hits on snakes. The Longsword (16 -> 14) and Greatsword (20 -> 17) now match SPD, upgrades follow each weapon's SPD scaling and lower its Str requirement like SPD, and a Dagger surprise hit is now 10 instead of 8. Duelist weapon abilities are not in the game (DECISIONS #207, +tests).
- The Rogue's Cloak of Shadows now works like SPD's: 3 charges for the whole expedition instead of a full refill every fight. Each cleared fight gives 1 charge back (up to 3), and a new expedition starts full. Assassin and Freerunner no longer add a charge, and the Mystical Upgrade talent (+1 charge, not in SPD) is now SPD's Mystical Meal: eating a ration restores 1 charge. The Cloak button shows charges left out of 3 ("Cloak (2/3)") and the delve's Brought row shows "Cloak 2/3". Saves keep the charges; an expedition saved by an older version continues with a full cloak, and a learned Mystical Upgrade becomes Mystical Meal (DECISIONS #206, +tests).
- Closing or reloading the game while an encounter window is open (an Ambush, a boss, a door or a special room, even one set aside with Close) no longer skips it: the window is back after the restart and the Delve Bar waits for it. Before, a reload let the bar walk past the encounter (DECISIONS #205, +test).

## 0.46.0
- Session length now reaches the gameplay data. The browser version sends `session_end` with `navigator.sendBeacon` when the tab is hidden or closed (it never got the engine's pause or close signal, and a normal request dies with the tab), Android also ends a session when the app loses focus, and a session end that can't be sent stays queued for the next launch (DECISIONS #204, +test).
- Identifying at the Enchanter's Desk is no longer a long wait per item. As in SPD, a ring or wand type is learned once: the first Garnet Ring takes the Desk's timer and every other Garnet Ring finishes with it, and a type you already know identifies the moment it's queued (its name shows the type, e.g. "Ring of Might", until then). The timer is 3 / 2 / 1 min at Desk Lv1 / 2 / 3 (was 10 / 7 / 4), each level works on one more type at the same time (1 / 2 / 3), and any item with its own timer has a "Finish 45g" button (15 gold per minute left, at least 5). A queue of 7 Garnet + 2 Ruby Rings at Lv1 now takes 6 minutes instead of 90. Old queues carry over. Patrol curios also alternate Ring of Might and Ring of Tenacity again; a bug made every curio from one patrol the same ring (DECISIONS #203, +tests).
- Reading a Scroll of Passage now asks first: a confirm with "Read" / "Cancel" from the delve Menu, an ambush card, and mid-fight, so a stray tap no longer burns it. Cancel leaves the scroll and spends no turn (DECISIONS #202, +test).
- The browser version no longer has developer options: the "Developer tools" toggle and its Developer section (unlock all heroes, +100 gold and materials, fast-forward timers, wipe save) are gone from Settings on the web. Android, Windows and source runs keep them (DECISIONS #199, +test).
- The game now runs in a browser at https://daltongoesfast.github.io/Idle-Pixel-Dungeon/ on PC and phones, including both Fold screens. Saves stay in the browser (clearing site data erases them), and sound starts after the first tap. `tools/deploy_web.sh` publishes it with each release (DECISIONS #196, +test).
- The game now sends anonymous gameplay data (fights, floors, deaths, bosses, extracts, patrols, milestones, gold spent, session length) to PostHog so balance can be tuned from real play. A random id only, no names or device ids; it queues offline and never slows play. The first launch shows a one-time notice with a Privacy link; docs/PRIVACY.md lists every event and property. Off in tests and sims (DECISIONS #197, +test).
- Gameplay data now only comes from the released game. Copies run from the source (playtests, the developer's own sessions) and automated browsers (`navigator.webdriver`) checking the web version send nothing, so test runs don't mix into the balance data (DECISIONS #198, +test).

## 0.45.0
- Milestones are now 80 SPD-style badges across ten categories (Delving, Bosses with per-hero Goo and Tengu kills, Monsters by type, Wealth, Crafting, Items, Patrols, Camp, Heroes and Feats like Untouchable or By Hand), each with its SPD badge icon and "37 / 50" progress in the Journal's new Milestones tab. Rewards are no longer handed out automatically: a reached milestone waits for a Claim tap (Claim all when two or more are ready), and the Journal button shows how many are waiting. Old saves keep everything already paid, and anything they've already earned under the new list becomes claimable. Rewards stay small (mostly materials; all 80 together give 555 gold) (DECISIONS #195, +tests).
- Closing the app on the Defeat window no longer brings the run back from before the fight. The defeat is saved as soon as the window opens, and it shows again on the next launch (DECISIONS #190, POLISH #70, +test).

## 0.44.2
- The delve's own panels darken the scene behind them again, as they did before v0.44.1: the Bag, Talents, Menu, Settings and the Abandon prompt (DECISIONS #194). Only event and result windows (encounters, doors, special rooms, the floor menu, the campfire and their results) leave the scene at full brightness. The combat Bag, Camp windows, tips and the Defeat window keep their dim (+test).
- After taking the wand out of the Mage's Staff, the Expedition window warns that she has no Bolt, and her Stats panel shows "Bolt: none" until a wand is imbued again (DECISIONS #193, +test).
- The hero window no longer squeezes on wide screens like the unfolded Fold (DECISIONS #192). The slot detail now spans the full window under the hero and Stats, instead of a narrow third column, so "Swap from pack" names stay readable and Equip, Swap and Take are normal one-line buttons in the delve backpack and the Camp Heroes window. The window look is unchanged (+test).
- Gear can come off and move between heroes at Camp (DECISIONS #189). Every equipped weapon, armor, ring, artifact and the Mage's staff wand has an Unequip button (heirlooms stay put), and it goes back to the stash. The Heroes swap list now also shows gear other heroes wear, labeled "Worn by Mage" with what happens to their slot, and Take or Swap moves it over. The Stash item window can unequip a piece or move or swap it to the selected hero, and the Wands list shows the wand in the Mage's Staff. A hero out on patrol (or on the current delve) keeps everything they wear: Unequip, Take and Swap are greyed out with "<Hero> is on patrol", and the gear can't be pulled off them by equipping it on someone else. Old saves load with one wearer per item (+tests).
- An event's result window (after opening a chest or choosing in a special room) no longer darkens the scene behind it either; taps behind it are still blocked. The Defeat window keeps its dim (DECISIONS #191, +test).

## 0.44.1
- A long Defeat list no longer pushes the OK button off the screen (a softlock on phones). The list scrolls, and the window always fits on screen (DECISIONS #187, +test).
- Phone fixes (DECISIONS #187): foes facing left no longer stand a cell to the right of their tile in battle, and ambush foes no longer pile up at the edge of the delve. The hero can no longer get stuck drawn solid white. The Piranha Pool shows real piranhas (dark shapes under the water that leap out) instead of a broken blob. Event windows no longer darken the scene behind them; taps behind them are still blocked.
- Delve walls (DECISIONS #187): the black band between wall tops and wall faces is gone, so faces sit flush under the dark like in SPD, and doors keep their lintels. The Suspicious Wall is a plain wall that sparkles, the barricade is a line of barricade tiles across the corridor with no door next to it, and room scenes no longer have rubble piles.
- A door held open by a death shows just the open door again, like SPD, with no bones on it (DECISIONS #187, replaces #184). It still shuts once someone passes through.
- Gear matters on patrol (DECISIONS #188). Every ring, wand and artifact gives its wearer a patrol perk that grows with its level: Ring of Wealth brings more gold and curios of any ring, the Master Thieves' Armband more gold, Sandals of Nature and the Wand of Regrowth seeds, the Chalice of Blood healing potions, the Horn of Plenty rations, the Talisman of Foresight identified (sometimes +1) curios, the Hourglass longer patrols, the Ring of Elements a cheaper fee, and so on. Higher total gear level (weapon, armor, ring, artifact, staff wand) brings back more materials with no cap, with diminishing returns (+34% at 5 levels, +60% at 16); gold gets none of that bonus. The Guild patrol card lists the hero's gear bonus and perks, and a patrol keeps what the hero set out with (+tests).

## 0.44.0
- Scene nits (DECISIONS #186): library shelves no longer have a wooden post sticking up into the dark at either end. The Dwarf King's carpet is darker, so his red danger tiles stand out on it. Prison torch light stays inside the battle arena, City smoke drifts as faint haze instead of dark squares, and the battle hit flash is SPD's quick white blink (0.05 s).
- Scene polish (DECISIONS #185): boss arenas look like SPD's boss rooms (Goo's sewer drains, Tengu's prison torches, DM-300's pylons, the Dwarf King's throne dais and red carpet, Yog's stained-glass windows and candles). Library bookshelves have SPD's slim wooden top instead of a heavy band, wells pour SPD's healing crosses or question marks, the delve campfire no longer sits on a dark square, faint wind motes drift over chasms in battle, and fireflies blink over the camp clearing (below the horizon, so the sky stays static). Tall grass no longer stands in front of the hero resting at the campfire.

## 0.43.0
- A door held open by the remains of something that died in it now shows SPD bones on the open door, so you can see why it is open. The bones go when someone passes through and the door shuts again (+test).
- Battle scene polish (DECISIONS #183): walls in every biome carry their SPD decorations (Sewers drains drip, Prison torches burn, Caves ore glints, City recesses smoke, Halls lava throws embers), and tall grass grows on grass. Shots now fly SPD's own projectiles: spirit arrows, magic bolts, DM-100 lightning, the Evil Eye's death ray, the Bright Fist's light ray, and shaman and warlock bolts, each from the monster that fired it. Struck characters flash white, and fallen foes are drawn in the right order.
- Delve scene polish (DECISIONS #182): walls and doors have their SPD tops (wall caps, door lintels, bookshelf tops), and the floor ends in SPD's chasm edge instead of a hard cut. Sewers and other corridors get stitched SPD water puddles, every screen shows a biome prop, Prison wall torches burn, City walls smoke and glow green, and Sewers drip. In fights, foes are drawn front-to-back correctly, the hero lunges and the struck foe flashes and recoils, and beaten foes fall with their SPD death frames and fade. The gnoll camp's gnolls no longer overlap.
- Camp and delve scene polish (DECISIONS #181): the camp sky is fully static, grass never grows over barrels or NPCs and sways as one plant, and the campfire warms nearby characters with a flickering glow. In the delve, grass reads as crisp green blades (no muddy moss beside it), it sways, every foe plays its full SPD attack animation, the hero flashes white when a blow lands, and each biome shows its own props along the wall.

## 0.42.0
- The Enchanter's Desk description now says artifacts repair from Lv2, like rings and wands. It still said Lv3 after DECISIONS #170 moved artifact repair to Lv2, so the Desk window told players to save for a level they don't need (+test).
- Every special room now has its own scene on the delve, built from SPD tiles, sprites and particles: piranhas in moving water, sparkling wells, a statue on its pedestal, a chalice on an altar, traps, crystals, bookshelves, a gnoll camp round a fire, and more (DECISIONS #180).
- Camp and delve scene art (DECISIONS #179): the camp campfire now burns with SPD-style flames, sparks and smoke under a flickering glow, the clearing is lit by the fire at night, and grass tufts sway around it. The delve corridor is pixel-perfect, its doors are shut (or locked when they need a key) and only appear where a door card or special room is, the floor exit is SPD stairs, the stray idle mobs and item props are gone, foes run in and stand apart, tall grass hides the hero's legs, torch light covers the whole scene, and a new floor fades in. Tall grass and barrels use SPD's raised tiles with their tops, the camp sky is a dithered night gradient, waiting foes lunge with their attack frames, and leaving a room dips to dark.
- Vendor windows pin a materials bar under the title (Forge, Alchemy, Enchanter, Guild) and collapse the facility level slots behind an Upgrade tab that expands above the shop (+test).
- Stash and Forge gear slots name who has each piece equipped. A worn item shows the hero's name on a colored plate (Warrior, Mage, Rogue, Huntress), shortened only when the slot is too narrow. The Forge keeps its green border for "you can afford this" and its red border for cracked gear. A ring type worn by two heroes shows both faces (+test).
- Owner name plates no longer clip: the name is fitted to the slot it sits on, so Huntress reads "Hunt" where the full word does not fit (the Fold inner and small windows used to cut it off). The faces on a ring worn by several heroes scale with the plate instead of being a speck (+test).
- Enchanter's Desk splits into Scribe, Identify, and Attune tabs, the same section buttons the Forge and Guild use, so the queue and the gear are not one long scroll. Identify shows how many items are still unknown, and Attune shows cracked rings, wands and artifacts (+test).
- Enemies hunt like SPD. A mob tracks your cell only while it can see you. Out of sight it walks to the last cell it saw you on, and if it gets there (or can't get closer) without spotting you it says it lost track of you and stops searching until it sees you again; a cloaked Rogue is chased to where she vanished instead of being ignored. Paths are SPD shortest paths around other mobs (waiting behind a blocker instead of taking a route twice as long) and around traps. Doors shut whenever nobody stands in them. A door something died in stays open (and stops blocking sight) until someone passes through it; after that it shuts normally again. When no door works, Auto Battle ducks behind walls or tall grass against snakes (DECISIONS #176, +tests).
- Lose enemies like in SPD: circle a pillar, tall grass, a door or a corner so a chasing mob loses sight, and it walks to where it last saw you and arrives unaware, so your next hit is a Surprise. Attacking reveals you: the target sees you again until you break sight once more. Auto Battle now plays for this with every class (Huntress shoots first from cover, melee heroes wait behind a pillar or door), at most 8 turns per fight, only against 1-2 foes and never against bosses, then it just fights (DECISIONS #177, +tests).

## 0.41.0
- Unidentified alchemy brews stay on their own flask. The pot was showing the healing yield's description and sprite, so every unknown potion looked like a Potion of Healing (+tests).
- Camp facilities show their levels as slots: filled, open, and locked. A Scroll of Upgrade opens the next slot; materials raise a level into an open slot. The slot row stays compact (+tests).
- Snakes can now be killed at range: wand and staff magic always hits them (as in SPD), and they slip only the first Spirit Bow arrow of each fight. Melee still needs a Surprise (+tests, DECISIONS #172).
- Enchanter: identify bars no longer jump back. Each queued item now fills from when it was queued to when it finishes, so the waiting bars keep their fill when the front item is done (they used to drop to empty). An Enchanter upgrade keeps every bar where it was, and older saves keep filling from where they load (+tests).
- Levelling rings and the staff wand at the Enchanter's Desk no longer costs Scrolls of Upgrade, so all 22 Scrolls go to camp caps. Each level costs 4N resin + 75N² gold instead (was 1 Scroll + 3N resin + 50N² gold). Cracked artifacts can be repaired at Desk Lv2 (was Lv3) (+tests).
- Abandoning an expedition no longer destroys the Scrolls of Upgrade in the pack: like a death, they are owed and return on the next boss kill. Every Scroll is needed to max the Camp, so one abandon after a boss kill used to make that impossible. The abandon confirm says the Scrolls will come back (+tests).
- Upgrade costs no longer stack into a column that cuts off the last number: the Enchanter staff wand row (now on its own line), the Forge Repair all row, and the "Total:" of every upgrade quantity picker show their materials in one row (+test).
- The UI smoke test now opens every special-room card through the real delve screen. v0.40.0 crashed on the four new rooms (no description), and the smoke test missed it because it always picked "Leave" from rolled rooms (+test).
- Camp dock: Delve sits under the destination, and each patrol card keeps the hero, timer, bar and loot with a Recall button beside the name, so the list is not a stack of full-width buttons (+tests).
- Enchanter: every item in the identify queue fills its bar toward when that item finishes. Waiting items used to stay empty until they were the one being identified (+tests).
- The post-fight Continue button is split. Continue and pause turns off x3 speed and Auto Battle, then pauses the delve so you can take a look (+tests).
- Auto Battle and Hint take a Surprise that can land this turn before a normal swing, a cloak, or a door dance. An adjacent foe who has lost sight of you, or a clear Spirit Bow shot, is the attack. Dodging a telegraph, a chasm shove, and a crowd slam still come first. A slam no longer counts snakes, since they slip it (+tests).

## 0.40.1
- Opening a special room that had no description (Trapped Vault, Chained Prisoner, Abandoned Shop, Gnoll Camp) crashed the delve card. Those rooms now have descriptions, and a room with no text still opens (+tests).

## 0.40.0
- The "next attack is a SURPRISE" status line only shows when a foe you can hit right now (adjacent, or a clear Spirit Bow shot) has lost sight of you, not whenever any foe is out of sight (+tests).
- Eleven more vanilla potions and scrolls drop as unknowns: Invisibility, Haste, Levitation, Frost, Paralytic Gas, Liquid Flame, Recharging, Lullaby, Retribution, Terror and Transmutation. Three potions hurt you when drunk blind, so identifying matters more (+tests).
- Camp item details show artifact stats at their current level, what each level adds, and the level / Desk cap / won-fight progress; the compare window lists artifact stats too (+tests).
- Five more vanilla artifacts from boss drops: Cape of Thorns, Ethereal Chains, Timekeeper's Hourglass, Sandals of Nature and Master Thieves' Armband. They start weak and level from won fights up to the Enchanter's Desk cap (+tests).
- Furor, Haste, Elements, Force and Sharpshooting now get stronger when levelled at the Enchanter's Desk (speed and resist bonuses have floors) (+tests).
- Rings, wands and artifacts now level and repair at the Enchanter's Desk: the Desk level caps their level (Lv1: +0), rings and the staff wand cost a Scroll of Upgrade + resin + gold per level, artifacts level slowly from won fights, and repairs need Desk Lv2 (Lv3 for artifacts). New rings and artifacts start weaker (Tenacity +1, Wealth +15%, Energy +2 HP, Chalice +6 HP, Horn x0.8). A levelled imbued wand cracks on death; Patch up no longer covers rings/artifacts (+tests).
- Five more vanilla rings: Furor (faster melee), Haste (faster steps), Sharpshooting (+1 ranged damage), Elements (-33% piercing/elemental damage) and Force (+2 with tier-1 weapons). They join the unknown-ring loot pool, which makes each specific ring rarer (+tests).
- Seven more vanilla wands for the Mage's Staff: Frost (chill), Corrosion (poison), Blast Wave (knockback), Disintegration (pierces the line), Transfusion (heal on hit), Prismatic Light (reveals traps), Regrowth (roots + grass). They drop as unknown wands alongside the old three (+tests).
- `tools/verify_apk.sh` finds Java like the Godot export does: `PATH`, then `JAVA_HOME`, then Editor Settings > Export > Android > Java SDK Path. Without Java it now fails with "JAVA NOT FOUND" and how to fix it (it used to stop on a bare `java: not found`, and before the signing pin it skipped the signature check silently and still printed PASS). A failed `apksigner verify` now fails the script (+test).
- New `docs/POLISH.md`: the polish backlog from today's PRs and playtest reports, grouped by screen with priority and effort, plus what waits for the combat rework.
- Camp upgrades are gated on the whole Scroll of Upgrade supply: raising a facility's cap to Lv2 still costs 1 Scroll, but the Lv3 cap now costs 5 (Blacksmith, Guild) or 4 (Alchemy, Enchanter). Maxing all four facilities takes 22 Scrolls, which is every Scroll the game grants (4 heroes x 5 bosses, first kill only, + Jailbreak + Full Roster). Was 8, reachable by about two heroes clearing the City. The cap button shows the Scroll count; gold and material costs are unchanged; caps on existing saves are kept (+tests).
- New special room in every biome: Trapped Vault. Fight the floor's encounter on a trap-strewn floor (2 visible, 4 hidden) for an unknown ring and gold, or disarm it for free as the Rogue. Special-room fight options can now name their own map (+test).
- New Prison special room: Chained Prisoner. Free them with an Iron Key (ration + gold) or fight a guard and a thief for an unknown scroll, a ration and gold (+test).
- New special room in every biome: Abandoned Shop. Spend gold carried this run on a ration (20), a torch (15) or an unknown potion (35) (+test).
- New special room: Gnoll Camp (Sewers floor 3+ and Prison). Raid three gnolls for an unknown wand, gold and ore, or sneak the stash for torch. Special rooms can now set a `min_floor` (+test).
- Vanilla SPD enemy behaviours: mob shots need a clear line (bodies block them), shamans/warlocks hold range and their bolts debuff (red shaman + warlock: Weakness, blue shaman: Vulnerable), DM-100 lightning x1.5 in water, Evil Eye beam covers the whole line, Spinner webs root, Scorpio stings cripple, Monks disarm every 3rd hit, Succubus blinks in once, Ripper leaps, Golem pulls you to it. Base HP/damage/armor unchanged. Deep-sim deaths 56 -> 70, Goo first try 24% -> 25% (+tests).

## 0.30.0
- Huntress and Mage blind shots, like SPD: the Spirit Bow (tap any tile in range) and wands (Bolt mode) aim at a tile, seen or not. The shot hits the first body on the line and flies through tall grass; walls and closed doors stop it; an empty line wastes it. Wand bolts carry past the aimed tile. Auto Battle takes up to 2 arrows (1 wand charge, keeping one in reserve) at where an unseen foe was last seen, and no longer shoots through bodies (+tests).
- Bats heal like SPD (`dealt - 2`, matching `Bat.attackProc`'s `damage - 4` at our half-damage double-speed scale) instead of a flat 2 on any hit that got through, so armor that blunts the bite also blunts the heal. Caves bat deaths in the deep sim drop 11 -> 7 (+test).
- Barrier closer to SPD: starting Barrier is 1-2 lower (Warrior 5 + Seal 2 + Cloth 1 = 8; others 3 + Cloth 1 = 4), armor upgrades add DR only, encounter Barrier is capped at half of max HP (Shielding at max HP), and Barrier decays by 1/turn after 3 ticks when no enemy is adjacent. Absorbed damage share drops 24% -> 19%, campaign deaths 75 -> 65, fresh Goo first-try wins 32% -> 24% (+tests).
- Guild Patrol cards: "+N curio(s)" now uses a non-wrapping chip label so the text no longer wraps one character per line and stretches the Guild window off the top and bottom of the screen. Added `UIKit.chip_label` / `UIKit.collapsing_labels` and a test across every Camp page.
- Enchanter: a "Queue all (N)" button in the Identifying header queues every unqueued unknown item in stash order, and upgrading the Enchanter now shortens the remaining time on items already in the queue (+tests).
- Expedition rations and torches are capped by Guild level: 3 / 6 / 10 at Guild Lv1 / 2 / 3 (was 10 at any level). The Supplies rows show the cap with an "Upgrade Guild to raise" hint, and Max all and the run start use the same cap. Campaign sim: no depth starvation (+tests).
- In-combat Bag now opens as a viewport-clamped modal window with its own ScrollContainer and a Close button (or tap outside), instead of expanding inline inside the side panel and pushing the combat log off screen (+tests).
- Expedition Supplies: a "Max all" button in the Supplies header sets every row to its max (disabled once they all are) (+test).
- `tools/verify_apk.sh` (and so `tools/build.sh`) now fails if the APK is not signed with the same certificate as the published releases (`tools/release_cert.sha256`). Android only installs an update signed with the same key, so a build signed with another key would make the in-game Update (and sideloading over the old app) fail with "App not installed". Override with `ALLOW_NEW_SIGNING_KEY=1` (+test).
- `tools/build.sh`: unpacking `android_source.zip` now also writes `android/.build_version` (`4.7.2.stable`) and `android/build/.gdignore`, so a headless Android Gradle export works on a fresh clone without opening the editor (+test).
- Guided first fight: an unseen enemy in tall grass no longer pops the "Surprise attack!" modal over Step 1/3 (which hid the move banner and froze the fight until dismissed). The Surprise tip still shows once the guided fight is finished (+test).
- Updater: a malformed GitHub reply (null/odd `assets` or `tag_name`, non-JSON body) now ends in an error instead of a script error that left the Update button stuck on "Checking…" until restart. The release check times out after 20 s (downloads keep 10 min), and an HTTP error such as a rate limit shows its code instead of "No network" (+tests).
- Fights in 8x8 rooms no longer grow: since the larger-rooms change, a lone Sewers crab became three crabs (and a statue three statues) whenever the 8x8 had three spawn slots, so most first runs died on floors 1-4. Only 10x10/12x12 rooms repeat the encounter to fill their slots, as DECISIONS #134 describes (+tests).
- iOS export preset: removed the duplicate `ITSAppUsesNonExemptEncryption` entry from `application/additional_plist_content` (Godot 4.6+ already writes it from `app_store_compliance/uses_non_exempt_encryption`), plus a unit test that checks the Android/iOS presets stay in sync.

## 0.29.0
- In-game Update on Android and Windows: Camp / Settings checks GitHub releases, downloads the APK or zip, and on Android opens the system Install screen. iOS stays on TestFlight; `tools/upload_testflight.sh` archives and uploads on a Mac. Android export uses Gradle so the updater can request install permission (+tests).
- Combat rooms: mixed 8/10/12 layouts, multi-chamber maps for later biomes, larger boss arenas. Grass sway and door open/close fixed. Surprise matches SPD (lost sight after a closing door or circling tall grass); snakes slip every other hit. Wands and the Spirit Bow need line of sight; the bow cannot fire point-blank. Auto battle uses the same surprise setups. (Bot expedition / Yog win-rate thresholds still need a follow-up pass.)
- iOS export preset. A PC or a Mac can write the Xcode project; a Mac with the Apple Team ID signs it and uploads to TestFlight. See `docs/BUILD_IOS.md`.

## 0.28.1
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
