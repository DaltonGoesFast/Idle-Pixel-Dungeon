# Roadmap / TODO

## Next up (suggested order)
- [ ] Playtest pass on the Fold 6: tap targets, text sizes, delve speed (`DelveScreen.SPEED`), fight length.
- [ ] Save/restore in-progress fights (DECISIONS #21).
- [ ] Prison biome (floors 6-10): `tiles_prison.png`, Prison mobs (skeleton, thief, DM-100, guard), Tengu boss, make GridView's tile sheet come from the biome.
- [ ] Rogue (Cloak of Shadows: break line of sight -> guaranteed surprise) and Huntress (Spirit Bow: ranged, ricochet, overwatch tiles) classes; unlock milestones (GDD Q D).
- [ ] Warrior leap/slam ability with telegraphed landing; Mage wand variety (frost slows, lightning chains through water).
- [ ] Water conducts lightning, traps (SPD trap tiles), more room templates (10x10 variant).
- [ ] Enchantments on a deterministic trigger (e.g. every 3rd hit / on surprise) - GDD Q E.
- [ ] Item comparison UI, gear icons on equip buttons, tooltips/long-press info.
- [ ] Settings: delve speed, left-handed layout, reduce motion.
- [ ] Hide the Developer tab behind a debug flag for public builds.
- [ ] Proper launcher icons (adaptive + monochrome) and a splash.
- [ ] Release signing + Play Store AAB (needs gradle build + NDK).

## Known gaps / stubs
- Only Sewers (floors 1-5) and Goo exist; the floor-5 campfire ends the run.
- Offline Patrols don't auto-assign the active hero when the app closes (GDD Phase C, second half).
- Facility levels beyond what recipes use: Guild Lv only affects patrol hours; Enchanter Lv only ID speed.
- Dew is collected but only used by patrols/future recipes.
- No tutorial / onboarding text beyond tooltips and the Hint button.
