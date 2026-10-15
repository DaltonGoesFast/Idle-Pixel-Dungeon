# Changelog

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
