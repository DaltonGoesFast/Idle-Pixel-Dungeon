# Roadmap / TODO

## Next up (suggested order)
- [ ] Real-device playtest on the Fold 6 (cover + inner): text sizes, tip card sizing at Huge text, haptic strength, Prison difficulty for a human player (the sim bot is better than a new player).
- [x] Mage vs Tengu (v0.8.0: 6/10).
- [x] Caves biome, floors 11-15, DM-300 (v0.9.0).
- [x] Tengu's Mask + 2 subclasses per class (v0.10.0); Rogue Caves 0 -> 7-8/10.
- [x] Warlock rework + Mage Caves help (v0.12.0).
- [x] SPD UI theme (chrome.png, pixel font), talents, in-delve backpack (v0.13.0).
- [x] Visuals pass: lighting/fog tied to torch, animated water, grass sway, particles (v0.14.0).
- [ ] On-device perf check on the Fold 6 (lighting draws ~650 rects/frame).
- [x] Dwarf City floors 16-20 + King of Dwarves (v0.15.0).
- [x] Demon Halls 21-25 + Yog-Dzewa (v0.17.0; fists/phases not yet).
- [x] King of Dwarves lifelink + 3 phases (v0.18.0).
- [ ] Talent icons (talent_icons.png), toolbar/status pane art.
- [ ] Rogue without subclass still 0/10 in the Caves (subclass is the intended fix).
- [x] Guided first-fight tutorial (v0.11.0).
- [ ] Playtest pass on the Fold 6: tap targets, text sizes, delve speed (`DelveScreen.SPEED`), fight length.
- [x] Save/restore in-progress fights (v0.4.0).
- [x] Prison biome + Tengu (v0.5.0).
- [x] Traps, searching, hidden doors (v0.5.0).
- [ ] Caves biome (floors 11-15, DM-300) - the Tengu campfire currently only extracts.
- [ ] Tengu's Mask / subclasses (GDD Q D).
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
- Tutorial is tips only (v0.7.0); there is no guided first fight with forced moves.
