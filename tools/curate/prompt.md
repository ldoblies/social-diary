# Curate the group's diaries

You turn the group's synced Social Diary data into short stories that the addon shows in each player's Your Diary in place of its own generated text, and into German day digests for the Gigu-Blitz. Run from the repository root. `tools/curate/config.lua` names the paths; `<out>` below is its `out`.

1. Run `luajit tools/curate/export.lua`. It writes `<out>/feed.json`. If it reports nothing to write, stop and say so.
2. Read `<out>/feed.json` and `<out>/stories.json` (create `{ "stories": [] }` if missing). `todo` lists the slot ids that want a story, new or written again; each slot is in `slots` with its `entries`, `basis` and `t`, and `story` holds the text it has now, if any. `digests` lists the dates that want a digest; that day's entries are in the slot `group:<date>`.
3. Write one story per `todo` id (rules below) and put it in `stories.json` as `{ "id", "title", "text", "t", "basis" }`, copying `t` and `basis` from the slot. Replace an existing story with the same id; keep every other story as it is.
4. Run `luajit tools/curate/build.lua`. It writes the `SocialDiary_Curated` addon the game reads at the next login or `/reload`.
5. For every date in `digests`, write `<out>/digest/<date>.md` (rules below). Never put a `group:` slot into `stories.json`.
6. Report briefly what you wrote. Never commit, never push.

## The entries

Each entry is one thing the diary recorded: `k` its kind, `t` when (Unix time), `z` the zone, `who` the people involved, `lv` the character's level, `writer` the character whose diary it is (group slots only). Kinds: `level`, `death` (`foe`, `env`), `close` (a close call, `pct` health left), `hunt` (quest drops, `luck` bad or good, `kills`, `need`, `expected`), `skill` (profession cap), `finale` (a quest chain's end, `title`, `n`), `first` (a first item of a kind, `what`, `item`, `giver`), `duel`, `pvp` (`won`), `witness` (`role`: watched, helped, saved), `trade`, `campfire`, `together` (time with diary friends, `dur` seconds), `dungeon` (`bosses`, `wipes`, `deaths`), `group`, `note` (what the player wrote themselves, `text`).

## Stories (shown in game, English)

- A story is that character's own diary page for a level (`<guid>:L<n>`) or a week at the cap (`<guid>:W<date>`): first person, past tense, a hand-written travel diary's voice, as that character.
- Two to four short paragraphs separated by a blank line, at most about 700 characters. A title of at most 40 characters.
- Only what the entries say. Never invent people, places, quests, loot or feelings the entries don't support; a quiet slot gets a short story. Turn numbers into words where it reads better ("nearly forty kills"), keep names and places exact.
- Write people's names exactly as the entries give them, first name and surname ("Bram Redfen"): the game links them to their pages by that text. A player's own notes may be quoted.
- No em dashes. No mention of addons, data, entries, syncing or the game's interface.

## Digests (for the Gigu-Blitz, German)

`<out>/digest/<date>.md`: a heading with the date, then one bullet per noteworthy happening of that day across the group, in plain German, naming who (by character name and, where `hordcore/characters/` says who plays it, the person), what, and where. Facts only: the newspaper adds its own tone when an issue is written. Deaths, close calls, dungeon runs, firsts, finished chains, duels and PvP first; levels and campfires only when nothing else happened.
