# Social Diary

A World of Warcraft addon that remembers the people you meet in the open world
(groups, trades, whispers, fights, deaths, sightings, reunions) and presents them,
plus your own journey (levels, firsts, zones, sessions), as a hand-written,
paper-styled journal. Open with `/sd`.

Fork of [Social Diary](https://github.com/social-diary/social_diary) by social-diary
(remote `upstream`). Keep their copyright notice in `LICENSE` and `CREDITS.md`.

The addon lives in `social_diary/`; paths below are relative to it.

## Target game: WoW Forever

This is **WoW Forever** (currently in beta): a classic-era game (classic content,
rules and world) running on the **retail addon API**. Use retail API names and
patterns (`C_*` namespaces, Settings API, AddonCompartment, etc.), but expect
classic gameplay. Interface version is in `social_diary.toc`.

## Where to find what

| Path | Contents |
|---|---|
| `social_diary.toc` | Load order, SavedVariables (`SocialDiaryDB`, `SocialDiaryCharDB`) |
| `Core/` | Data model and logic: DB, identity, people, diary, timeline, journey, sessions, reunions, slash commands, event wiring; the registries features plug into (`Rows.lua`, `Journey.RegisterList`, `JourneyRecap.RegisterMoment`) |
| `Core/Bridges/` | Optional integrations (Questie) |
| `Capture/` | Game-event listeners for the diary's substrate (group, sessions, sightings, the journey route) |
| `UI/` | A folder per area: `Style/` (the design system: tokens, art, sounds, drawing, book, cover, widgets, a person's pieces), `Kit/` (shared frames, lists, keys, the confirm popups), `Paper/` (loose sheets, strips, note and link sheets), `Ink/` (trail, blots), `Map/` (map art, overlays, the heat-map sheet), `Words/` (timeline wording), `Journal/` (the book and its pages), `Journey/` (Your Diary: page, plates, words), `Settings/` (the page, its kit, the quiet list, macros, `Sections/` one file per section), `Windows/` (entry, picker, `Reunion/` the reunion toast, `Intro/` the login parcel), `Blizzard/` (tooltip and Social tab hooks, the AddOns settings signpost, key bindings) |
| `Features/<Name>/` | One detection each, whole (chat, trade, level-ups, World PvP, rare kills, deaths, witnesses, close calls, hunts, firsts found, quest finales, profession caps, campfires, duels): its row kind, route list, recap moment, mark, margin note, words, capture, static data and test data, registered into `Core/` and `UI/`. Core never names a feature |
| `Dev/` | Debug tools and test data (not for release) |
| `tests/` | Offline test suite against a WoW API mock (`wowmock.lua`). Run from `social_diary/`: `luajit tests/run.lua` (`-v` verbose, or pass file names). Add new files to `FILES` in `run.lua` |
| `CHANGELOG.md` | Release notes |
| `README.md`, `CREDITS.md`, `CONTRIBUTING.md` | Install, privacy, credits; contributor guide |

Never commit images (`*.png` is gitignored) or anything recorded from real players (names, GUIDs, chat). Tests and examples use invented names.

## Rules

The addon is live, so players' saved data has to survive every update. Never drop, move or reinterpret saved fields without a migration: bump the matching schema in `Core/DB.lua`, add a `STEPS` entry, and test it on an old-shaped table.
