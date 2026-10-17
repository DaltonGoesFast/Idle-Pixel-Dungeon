# Polish backlog

The cosmetic and feel work saved for the end (DECISIONS #162). Polish that changes how the game plays (a broken screen, unreadable text, a confusing control) still gets its own small PR right away. Sources: today's PRs #40–#51 and the playtest reports in `/workspace/playtest/` (report-*.md, overnight-2026-10-15.md).

Priority: **P1** fix before a public build, **P2** next polish pass, **P3** nice to have. Effort: **S** < 1 h, **M** a few hours, **L** a day or more.

## Combat screen
| # | Item | Source | Pri | Effort |
|---|---|---|---|---|
| 1 | Debuff status icons: weakened, vulnerable, webbed, slowed, poisoned, chilled, rooted, corroded show only in the combat log. Add SPD BuffIndicator icons over the unit and in the hero's status pane | #45, #46 | P1 | M |
| 2 | "They lost sight of you: next attack is a SURPRISE" shows wrongly: `surprise_ready()` is true if ANY foe can't see you, so it appears on guided-fight Step 1/3, at the start of most fights, and with no surprise-able target | reports 4dd90ed, dd2bfb4 | P1 | S |
| 3 | Regrowth's `grow` event has no animation in `grid_view` (grass just appears) | #46 | P3 | S |
| 4 | Wand riders (chill, corrode, knockback, transfusion heal) have no distinct bolt colour or sfx; SPD uses a per-wand MagicMissile effect | #46 | P2 | M |
| 5 | Thorns / Hourglass / Chains / Sandals trigger only a log line; add a short flash or sfx | #49 | P3 | S |
| 6 | Next-fight effects from potions/scrolls (Lullaby, Haste, Frost, Invisibility, ...) apply silently at fight start; show a banner or status icon | #51 | P2 | S |
| 7 | Mob abilities ignore bodies (`sees` / `in_view`) while hero shots stop at the first body; visible as zaps passing through allies | report 4dd90ed | P2 | M |
| 7a | Enemy inspect should show its SPD target cell (where it last saw you) and a "?" over a mob that has lost track (SPD `showLost`); `m.aim`, `m.state` and the `lost` event are already there | DECISIONS #176 | P2 | S |

## Camp: Forge, Enchanter, stash item details
| # | Item | Source | Pri | Effort |
|---|---|---|---|---|
| 8 | Artifact stats (thorns, freeze, root, chain hold, loot %) and their per-level growth aren't shown in the camp item details (only the description text) | #49 | P1 | S |
| 9 | Ring/wand level effects: item popups show `+N` but not what the next level adds ("+1 dmg -> +2 dmg") | #48, #50 | P2 | S |
| 10 | Enchanter "Attune" section is a plain row + grid; restyle to match the Forge Upgrade & repair section (cost chips, cap header) | #48 | P2 | M |
| 11 | Artifact XP progress (fights to next level) isn't shown anywhere | #48 | P2 | S |
| 12 | Forge ring stack with mixed identification: title shows the unknown name while the effect line shows the known copy's description | report dd2bfb4 | P3 | S |
| 13 | New wand riders aren't in the Codex mob/item inspect toast beyond one line | #46 | P3 | S |
| 29 | Forge "Upgrade & repair (N cracked)" and its Cracked count include rings/artifacts that only the Enchanter's Desk can repair (the Forge Repair all also repairs them once the Desk allows). Count and list only Forge items there, or label Desk items | report e6a206d | P3 | S |
| 30 | Attune grid: the staff wand row has no item-slot frame and the Desk items have no captions; ring slots look identical apart from the corner glyph | report e6a206d | P3 | S |

## Delve screen and status pane
| # | Item | Source | Pri | Effort |
|---|---|---|---|---|
| 14 | Status pane torch/food icons are small on the cover screen (integer scale to the 9px bar) | reports 7406e4f onward | P2 | S |
| 15 | Menu window overlaps the "Brought" line while open | report b1a4afa | P3 | S |
| 16 | Potion/scroll badge glyphs float above their icons in the Expedition supply rows | report 4dd90ed | P2 | S |
| 17 | Transmutation gives no before/after of the item it changed | #51 | P3 | S |
| 28 | Fold inner: special-room cards with 3 disabled options (Abandoned Shop when broke) need a scroll; each "can't afford" line under its button pushes Leave half below the card edge. Put the reason inside the button or drop the log lines above the title when the card is tall | report e6a206d | P2 | S |

## Camp windows (Guild, Expedition, Patrol)
| # | Item | Source | Pri | Effort |
|---|---|---|---|---|
| 18 | Cover-screen Guild/Expedition windows keep a large empty gap above the footer (footer-anchored action, DECISIONS #124) | report b1a4afa | P2 | S |
| 19 | Camp UI windows rework (the plan you have Cursor writing) | chat | P2 | L |
| 31 | Wide camp dock (a9883a7): on the Fold inner a patrolling card's title "Warrior   0.7h / 4h" wraps to two lines beside Recall. Shorten it ("0.7/4h") or let Recall shrink | report 2a078e4 | P3 | S |
| 32 | Wide camp dock: with Delve moved up, the inner patrol list shows about 1.3 cards (it was about 2.8), so 3-4 patrols scroll inside a short box. Consider a one-line card (name, time, Recall) with the loot behind a tap | report 2a078e4 | P3 | S |
| 33 | Facility slots at 1.8 font heights (0476bd6): the Locked Scroll icon is small and dimmed to 45%, and the Open "+" is much smaller than the Filled numbers. Use a bigger plus and a less-dimmed icon | report 2a078e4 | P3 | S |
| 34 | Unlock row: `cost_row` expands (DECISIONS #168), so "have N" is pushed to the far right beside Unlock, away from the Scroll cost it qualifies. Keep the chip next to the cost | report 2a078e4 | P3 | S |
| 35 | "Scrolls only unlock a slot, they don't raise the level" now lives only in the Unlock tooltip, and touch screens never show tooltips. The Filled/Open/Locked words carry it for now. A first-Scroll tip could say it once | report 2a078e4 | P3 | S |
| 36 | Scroll of Upgrade has no description in the stash item window (`_materials.scroll_upgrade` has no `desc`). It should say that it unlocks one facility slot | report 2a078e4 | P2 | S |
| 37 | The camp scene's "!" badge fires only when a facility can Upgrade, never when you hold enough Scrolls to Unlock a slot, so nothing points at a first Goo Scroll | report 2a078e4 | P2 | S |

## Rooms and maps
| # | Item | Source | Pri | Effort |
|---|---|---|---|---|
| 20 | City 10x10 rooms have 1 spawn slot and Prison 10x10s have 2 | report 4dd90ed | P2 | S |
| 21 | Dark far halves in 12x12 arenas | report 4dd90ed | P3 | M |
| 22 | Special-room cards (Trapped Vault, Chained Prisoner, Abandoned Shop, Gnoll Camp) use generic icons; give each its SPD sprite | #41–#44 | P3 | S |

## Camp and delve scene art
| # | Item | Source | Pri | Effort |
|---|---|---|---|---|
| 39 | ~~Delve corridor drew tiles and sprites at a fractional scale (soft, uneven pixels)~~ **Done** (DECISIONS #179) | overnight 2026-10-16 | P2 | S |
| 40 | ~~Delve wall showed random locked and crystal doors, and an open door for special rooms; doors never match the "shut unless occupied" rule~~ **Done** (#179) | overnight 2026-10-16 | P1 | S |
| 41 | ~~Idle biome mobs and item props (rotberry seeds, holder outlines, "something") stood in the corridor and overlapped the encounter~~ **Done** (#179) | overnight 2026-10-16 | P2 | S |
| 42 | ~~Delve floor exit was a crystal door; now SPD down stairs~~ **Done** (#179) | overnight 2026-10-16 | P3 | S |
| 43 | ~~Camp campfire was seven orange bars; needs SPD flame particles, sparks, smoke, flicker and a night light pool~~ **Done** (#179) | overnight 2026-10-16 | P2 | M |
| 44 | ~~Encounter foes stacked on one spot and popped in~~ **Done**: one column each, two rows, run in (#179) | overnight 2026-10-16 | P2 | S |
| 45 | ~~SPD water edge stitching~~ **Done** for room water: Piranha Pool and the wells stitch SPD WATER tiles over the scrolling water (#180); corridor puddles too (#182) | overnight 2026-10-16 | P3 | M |
| 46 | ~~Special rooms had no scene of their own on the delve (just a floating icon)~~ **Done** (#180) | overnight 2026-10-16 | P2 | M |
| 47 | ~~Camp sky flickered (twinkling stars, drifting clouds, firelight and darkness quads reaching above the horizon)~~ **Done**: static sky (#181) | user 2026-10-17 | P1 | S |
| 48 | ~~Grass drawn over barrels and NPCs; camp grass sheared at the tile seam when swaying~~ **Done** (#181) | user + Bugbot 2026-10-17 | P1 | S |
| 49 | ~~Delve grass top read as a muddy olive smudge (sewer moss deco beside the clumps)~~ **Done** (#181) | user 2026-10-17 | P2 | S |
| 50 | ~~Delve grass stopped swaying; foe attack frames cut off at 0.3 s; no hit feedback~~ **Done**: sway, SPD attack length, white hit flash (#181) | Bugbot + user 2026-10-17 | P2 | S |
| 51 | ~~Later biomes' corridors had no props of their own~~ **Done**: SPD region deco / statue per biome (#181) | user 2026-10-17 | P3 | S |
| 52 | ~~Delve wall and door tops cut off; floor ended in a hard edge at the void~~ **Done**: SPD wall/door/bookshelf overhang tiles, CHASM_FLOOR / CHASM_WATER bottom edge (#182) | user 2026-10-17 | P1 | M |
| 53 | ~~Foes vanished instantly when a fight ended; no reaction when the hero struck; foes overlapped in the wrong order~~ **Done**: SPD die frames and fade, hit flash and knockback, back-to-front drawing (#182) | user 2026-10-17 | P2 | S |
| 54 | ~~Gnoll camp gnolls overlapped; not every corridor screen had a biome prop; Prison walls had unlit sconces~~ **Done** (#182) | user 2026-10-17 | P2 | S |
| 55 | Combat grid (`grid_view.gd`) still mirrors sprites with a negative source width, which made the gnoll's last die frame vanish in the delve; check whether any combat frames are affected (combat screen, out of scope for scene polish) | fix4 2026-10-17 | P3 | S |

## Code / docs hygiene (no player impact)
| # | Item | Source | Pri | Effort |
|---|---|---|---|---|
| 23 | `ui_kit.gd`: `res_chip`'s doc comment sits on `chip_label`; DECISIONS #146 says `res_chip` uses `SIZE_SHRINK_BEGIN` but the code doesn't | report 4dd90ed | P3 | S |
| 24 | DECISIONS #142 still mentions `MAX_SUPPLY` (removed by #144) | report 4dd90ed | P3 | S |
| 25 | 4x "non-equal opposite anchors" warnings in `test_tip_fit` | report 4dd90ed | P3 | S |
| 26 | `export_plugin.gd.uid` untracked; TestFlight `mktemp` leftover | report 4dd90ed | P3 | S |
| 27 | Combat Bag rect on fold/unfold while open relies on `apply_layout -> _refresh` (untested on device) | report 4dd90ed | P2 | S |
| 38 | `GameState.facility_title` (the "(cap N)" header text) is only used by `test_facility_cap` since the slot header; drop it, or test the slot row instead | report 2a078e4 | P3 | S |

## Deferred until the combat rework lands
These are content or tuning, not polish, but they wait on the same thing:
- **Thrown weapons and bombs.** These need a new combat action and a fight-screen picker for the item and target, which touches the combat input you're reworking.
- **Exotic potions and scrolls.** They need Alchemy recipes that consume a base potion or scroll, and several (Dragon's Breath, Snap Freeze, Psionic Blast) need combat hooks. Shielding and Passage stay as they are.
- **Wand buffs.** In forced-wand sims Frost, Transfusion, Disintegration and Prismatic Light are weaker than Magic Missile (#46), so retune them against the new combat numbers.
- **Enchantments and glyphs** (and Ring of Arcana, Ring of Accuracy), which need base-combat hooks.
