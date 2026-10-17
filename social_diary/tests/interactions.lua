-- The interaction buffer: what gets stored, its caps, and how long it lasts.

local T = ...
local mock, F = T.mock, T.F
local Section, Check, Eq = T.Section, T.Check, T.Eq
local DAY = T.DAY
local ns = T.Boot()
local Latest = ns._test.LatestInteraction

--------------------------------------------------------------------------
Section("interaction buffer (INT-1 to INT-5)")

local GUID = F.STRANGER.guid
mock.now = 1790000000

local row = ns.Interactions.Add(GUID, "whisper_in", { excerpt = "thanks for the help", theirLevel = 8 })
Check(row, "interaction not recorded")
Eq(row.type, "whisper_in", "type")
Eq(row.time, mock.now, "time")
Eq(row.me, F.SELF.guid, "which of the user's characters was present (DAT-1)")
Eq(row.zone, "Mulgore", "zone not stamped on the row")
Eq(row.mapID, 1412, "map not stamped on the row")
Eq(row.myLevel, 70, "own level")
Eq(row.theirLevel, 8, "their level")
Eq(row.excerpt, "thanks for the help", "chat excerpt")
Eq(ns.Interactions.Count(GUID), 1, "buffer count")

Eq(ns.Interactions.Add(mock.secret("Player-1-2"), "trade", {}), nil, "secret GUID buffered")
Eq(ns.Interactions.Add("Creature-0-1-2", "trade", {}), nil, "creature buffered")
Eq(ns.Interactions.Add(GUID, nil, {}), nil, "typeless interaction buffered")

-- A secret excerpt is dropped, but the row still records that it happened.
row = ns.Interactions.Add(GUID, "say", { excerpt = mock.secret("hello") })
Check(row, "row lost along with its secret excerpt")
Eq(row.excerpt, nil, "secret excerpt stored")

-- The store scrubs the rest of the row too: a secret in `context` is dropped
-- on its own, and so is a secret context or a secret hostile flag (INT-5).
row = ns.Interactions.Add(GUID, "group_join", {
    context = { raid = true, guild = mock.secret("The Rusted Wheel") },
    hostile = mock.secret(true),
})
Check(row, "row lost along with its secret context value")
Eq(row.context.guild, nil, "secret context value stored")
Eq(row.context.raid, true, "a plain context value went with the secret one")
Eq(row.hostile, nil, "secret hostile flag stored")
row = ns.Interactions.Add(GUID, "group_join", { context = mock.secret({ raid = true }) })
Eq(row.context, nil, "secret context stored")

-- INT-3: excerpts are capped in length ...
row = ns.Interactions.Add(GUID, "say", { excerpt = ("y"):rep(400) })
Eq(#row.excerpt, 254 + 3, "excerpt not truncated to the cap")

-- ... and in number, by dropping the text off old rows rather than the rows.
for _ = 1, 55 do
    ns.Interactions.Add(GUID, "say", { excerpt = "line" })
end
local withText, total = 0, 0
for _, r in ipairs(ns.Interactions.For(GUID)) do
    total = total + 1
    if r.excerpt then withText = withText + 1 end
end
Eq(withText, 50, "excerpt line cap (INT-3)")
Check(total > 50, "rows were deleted instead of their text")

-- INT-3's off switch.
ns.db.settings.storeChat = false
row = ns.Interactions.Add(GUID, "say", { excerpt = "not stored" })
Eq(row.excerpt, nil, "chat stored while chat storage is off")
ns.db.settings.storeChat = true

Eq(Latest(GUID).type, "say", "latest interaction")
Eq(Latest(GUID, "trade"), nil, "latest of a type never recorded")

-- The first row is still here; only its text fell off the far end of the cap.
local oldest = Latest(GUID, "whisper_in")
Check(oldest, "the oldest row was deleted rather than emptied")
Eq(oldest.excerpt, nil, "the oldest excerpt should have been trimmed by now")
Eq(oldest.theirLevel, 8, "the trimmed row lost the rest of its content")

-- The per-character ceiling.
for _ = 1, 260 do
    ns.Interactions.Add(GUID, "say", {})
end
Eq(ns.Interactions.Count(GUID), 250, "per-character row ceiling")

-- Diary entries have no ceiling: their history is kept for good.
local KEPT = F.GARRICK.guid
ns.Characters.Observe(KEPT, { first = "Garrick", surname = "Fallow" })
ns.Diary.Add(KEPT, { source = "test" })
for i = 1, 300 do
    ns.Interactions.Add(KEPT, "whisper_in", { excerpt = "line " .. i })
end
Eq(ns.Interactions.Count(KEPT), 300, "a diary entry's history was cut at the ceiling")

-- ... and with no maximum, every line of it keeps its text.
ns.db.settings.chatUnlimited = true
ns.Interactions.Add(KEPT, "whisper_in", { excerpt = "line 301" })
local withText = 0
for _, r in ipairs(ns.Interactions.For(KEPT)) do
    if r.excerpt then withText = withText + 1 end
end
Eq(withText, 51, "no maximum did not keep every new line")
ns.db.settings.chatUnlimited = false
ns.Diary.Remove(KEPT, "purge")

--------------------------------------------------------------------------
Section("retention (INT-2, D3)")

ns.db.interactions = {}

local OTHER = F.GARRICK.guid
ns.Interactions.Add(GUID, "trade", { time = mock.now - 40 * DAY })
ns.Interactions.Add(GUID, "trade", { time = mock.now - 2 * DAY })
ns.Interactions.Add(OTHER, "trade", { time = mock.now - 40 * DAY })

local dropped = ns.Interactions.Prune(mock.now)
Eq(dropped, 2, "wrong number of rows pruned at 30 days")
Eq(ns.Interactions.Count(GUID), 1, "recent row pruned")
Eq(ns.Interactions.For(OTHER), nil, "a character with nothing left should go too")

-- Diary entries keep everything: their history is the product (INT-2).
ns.db.diary[GUID] = { guid = GUID, addedAt = mock.now, tags = {} }
ns.Interactions.Add(GUID, "trade", { time = mock.now - 400 * DAY })
Eq(ns.Interactions.Prune(mock.now), 0, "a diary entry's history was pruned")
Eq(ns.Interactions.Count(GUID), 2, "a diary entry lost rows")
ns.db.diary[GUID] = nil

Check(ns.Interactions.Forget(GUID), "Forget reported nothing to forget")
Eq(ns.Interactions.For(GUID), nil, "Forget left rows behind")

--------------------------------------------------------------------------
Section("rows written after the fact: where and session")

ns.db.interactions = {}
local row = ns.Interactions.Add(GUID, "trade", { time = mock.now - DAY, where = { zone = "The Barrens" } })
Eq(row.zone, "The Barrens", "the given place was not used")
Eq(row.mapID, nil, "the user's map was stamped over the given place")

-- With the entry together in an open session, a row is stamped unless it
-- says otherwise.
ns.Characters.Observe(GUID, { first = "Bram", surname = "Redfen" })
ns.Diary.Add(GUID, { source = "test" })
local session = ns.Sessions.Together(GUID, "group", true)
Check(session, "setup: no session")
Eq(ns.Interactions.Add(GUID, "whisper_in", { time = mock.now }).session, session.id, "setup: not stamped")
Eq(ns.Interactions.Add(GUID, "whisper_in", { time = mock.now, session = false }).session, nil,
    "session = false still stamped the open session")
Eq(ns.Interactions.Add(GUID, "whisper_in", { time = mock.now, session = 4242 }).session, 4242,
    "the given session was not stamped")
ns.Sessions.Forget(nil)

--------------------------------------------------------------------------
Section("Interactions.Since (the picker's buffer)")

ns.db.interactions = {}
local OLD, NEW = "Player-4620-00511101", "Player-4620-00511102"
ns.Interactions.Add(OLD, "trade", { time = mock.now - 7200 })
ns.Interactions.Add(NEW, "whisper_in", { time = mock.now - 600 })
ns.Interactions.Add(GUID, "trade", { time = mock.now - 7200 })
ns.Interactions.Add(GUID, "say", { time = mock.now - 60 })
local since = ns.Interactions.Since(mock.now - 3600)
Eq(#since, 2, "everyone with a row in the last hour")
Eq(since[1].guid, GUID, "not newest first")
Eq(since[1].type, "say", "not the latest row")
Eq(since[2].guid, NEW, "the second")
Eq(since[2].time, mock.now - 600, "its time")
Eq(#ns.Interactions.Since(mock.now), 0, "rows before `since`")
