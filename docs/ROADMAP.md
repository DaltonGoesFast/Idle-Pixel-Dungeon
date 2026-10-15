# Roadmap / TODO

## Next up (suggested order)
- [ ] Playtest pass on the Fold 6: tap targets, text sizes, delve speed (`DelveScreen.SPEED`), fight length.
- [x] Save/restore in-progress fights (v0.4.0).
- [x] Prison biome + Tengu (v0.5.0).
- [x] Traps, searching, hidden doors (v0.5.0).
- [ ] Caves biome (floors 11-15, DM-300) - the Tengu campfire currently only extracts.
- [ ] Tengu's Mask / subclasses (GDD Q D).
- [ ] Mage vs Tengu: blinks waste charges (deeprun 3/10). Consider letting bolts recharge faster in boss fights or a Mage-specific hint.
- [ ] Huntress overwatch tiles, Mage frost wand (slow).
- [ ] More room templates (10x10 variant).
- [ ] Enchantments on a deterministic trigger (e.g. every 3rd hit / on surprise) - GDD Q E.
- [ ] Item comparison UI, gear icons on equip buttons, tooltips/long-press info.
- [x] Settings: volume, haptics, text size (v0.6.0).
- [ ] Settings: delve speed, left-handed layout, reduce motion.
- [x] Developer tools hidden behind a Settings toggle (v0.6.0).
- [ ] Proper launcher icons (adaptive + monochrome) and a splash.
- [ ] Release signing + Play Store AAB (needs gradle build + NDK).

## Known gaps / stubs
- Sewers (1-5, Goo) and Prison (6-10, Tengu) exist; the Tengu campfire ends the run.
- Offline Patrols don't auto-assign the active hero when the app closes (GDD Phase C, second half).
- Facility levels beyond what recipes use: Guild Lv only affects patrol hours; Enchanter Lv only ID speed.
- Dew is collected but only used by patrols/future recipes.
- No tutorial / onboarding text beyond tooltips and the Hint button.
