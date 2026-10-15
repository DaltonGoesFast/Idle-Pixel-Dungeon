# Changelog

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
