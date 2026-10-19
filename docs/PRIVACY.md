# Privacy: gameplay data

SPD Tactics sends **anonymous gameplay data** so the game's balance can be tuned from real play
(where heroes die, how hard bosses are, how much gold and loot runs bring back). It is collected
from every player on every platform (Android, Windows and the browser version). The first launch
shows a short notice about it.

## What is never collected
- No names, accounts, e-mail addresses, contacts or free text you type.
- No device identifiers (no advertising id, Android id, serial number, phone model or OS user name).
- No location. IP-based location lookup is switched off on every event (`$geoip_disable`), and
  no person profiles are created (`$process_person_profile: false`).
- Nothing from outside the game: no other apps, files or browsing.

## How you are identified
A random id (a UUID such as `3f0c…-…`) is created on first launch and stored only in the game's own
data folder (`user://telemetry.cfg`). It is not linked to you, your device or your save; reinstalling
or clearing the app's data makes a new one. Each launch also gets a random session id.

## Where it goes
Events are sent over HTTPS to [PostHog](https://posthog.com) (US cloud, `us.i.posthog.com`), the
analytics service the developer uses. Like any web request, PostHog receives your IP address in
transit; the game asks it not to derive a location from it. While offline, events wait in a small
local file (`user://telemetry_queue.json`, at most 1000 events) and are sent later.
Only the released game sends: copies run from the source code, automated tests and automated
browsers (`navigator.webdriver`) send nothing.

## Every property sent
Each event carries: `version` (game version), `platform` (android / windows / web), `class` (the hero
class on the current expedition, or empty at Camp), `session_id`, the random `distinct_id`, and a timestamp.

| Event | When | Extra properties |
|---|---|---|
| `app_open` | launch, or coming back after 30+ min | `returning`, `resume`, `queued` |
| `notice_seen` | OK on the first-launch notice | none |
| `run_start` | an expedition begins | `biome`, `floor`, `hero_level`, `gear_level`, `power`, `heroes` (unlocked classes and their levels), `supplies` (counts packed), `runs` |
| `floor_reached` | each new floor | `biome`, `floor`, `hp`, `torch`, `satiety`, `gold` (in the pack) |
| `fight_end` | every fight | `biome`, `floor`, `enemies` (monster ids), `result` (win / loss), `turns`, `hp_before`, `hp_after`, `hp_lost`, `dmg_in`, `dmg_out`, `auto_battle`, `surprises`, `potions`, `kills`, `boss`, `hero_level`, `gear_level` |
| `boss_fight` | every boss fight | `boss`, `biome`, `result`, `gear_level`, `hero_level`, `attempt` (this class's try number at this boss), `turns`, `hp_lost`, `auto_battle` |
| `death` | an expedition ends in death | `biome`, `floor`, `cause` (e.g. `fight:rat,gnoll` / `boss:goo`), `hero_level`, `gear_level`, `fights_won`, `gold_lost` |
| `extract` | loot is banked at Camp | `biome`, `floor`, `gold`, `loot` (material counts), `gear_found`, `hero_level`, `gear_level`, `fights_won` |
| `abandon` | an expedition is abandoned | `biome`, `floor`, `hero_level`, `gear_level`, `fights_won`, `gold_lost` |
| `patrol_start` | a hero leaves on patrol | `biome`, `max_hours`, `eff`, `gear_level`, `gear_mult`, `perks` (perk ids), `fee_gold`, `hero_level` |
| `patrol_end` | a patrol is collected | `biome`, `hours`, `curios`, `yield` (material counts), `perks`, `gear_level`, `eff` |
| `milestone_claimed` | Claim on a milestone | `milestone` (id), `category`, `reward` |
| `facility_upgrade` | a Camp building levels up | `facility`, `level`, `cost` |
| `gold_spent` | summed every 5 minutes and at session end | `sink` (`craft_guild`, `item_upgrade`, `repair`, `train`, `facility_upgrade`, `patrol_fee`, `staff_wand`…), `gold`, `count` |
| `session_end` | the app goes to the background or closes (in the browser: the tab is hidden or closed) | `duration_s` (time in the app), `reason`, `dropped` (events skipped by the rate limit) |
| `save_wiped` | Wipe is confirmed in Settings | none |

All values are game numbers, booleans or ids from the game's own data files. The game sends at most
30 events a minute and at most 50 per request.

## Questions
Open an issue on [the repository](https://github.com/DaltonGoesFast/spd-tactics-builds/issues).
