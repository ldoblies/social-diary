-- Curated stories (Core/Sync/Curated.lua) and where they are read: the
-- editor's file taken in, Your Diary's prose replaced while the reader
-- wants it, and the Sync settings page.

local T = ...
local mock, F = T.mock, T.F
local Section, Check, Eq = T.Section, T.Check, T.Eq
local DAY = T.DAY
local ns = T.Boot()
local SELF = F.SELF

mock.now = 1791000000
local now = mock.now
SELF.level = 12
mock.SetUnit("player", SELF)

local Curated, Store, CURATED = ns.Sync.Curated, ns.Sync.Store, ns.Sync.CURATED
local L12 = SELF.guid .. ":L12"

--------------------------------------------------------------------------
Section("the editor's file taken in")

Eq(Curated.Import(), 0, "a story taken in with no file")
_G.SocialDiaryCurated = { epoch = 100, stories = {
    { seq = 2, id = "Player-4620-00777777:L20", title = "Hogger", text = "Hogger won.", t = now - 3600 },
    { seq = 1, id = L12, title = "The Barrens", text = "Bram Redfen and I set out.\n\nThe road was long.",
        t = now - 7200 },
} }
Eq(Curated.Import(), 2, "the stories taken in")
Eq(Curated.Import(), 0, "the same stories taken in twice")
Eq(Store.Author(CURATED).last, 2, "the curated stream's last")

local lines = Curated.Lines(SELF.guid, { kind = "level", level = 12 })
Eq(lines and #lines, 2, "the story's paragraphs")
Eq(lines[1], "Bram Redfen and I set out.", "the first paragraph")
Eq(Curated.Lines(SELF.guid, { kind = "level", level = 11 }), nil, "a level without a story")
Eq(Curated.EntryId(SELF.guid, { kind = "week", week = os.time({ year = 2026, month = 10, day = 12, hour = 0 }) }),
    SELF.guid .. ":W2026-10-12", "a week's id is its Monday")

ns.SetSetting("showCurated", false)
Eq(Curated.Lines(SELF.guid, { kind = "level", level = 12 }), nil, "a story read with curated stories off")
ns.SetSetting("showCurated", true)

Eq(Curated.Import({ epoch = 50, stories = { { seq = 3, id = L12, text = "Older." } } }), 0,
    "an older editor's file taken in")
Eq(Curated.Import({ epoch = 100, stories = { { seq = 3, id = L12, del = true } } }), 1, "a story taken back")
Eq(Curated.Lines(SELF.guid, { kind = "level", level = 12 }), nil, "a story taken back is still read")
-- The editor's file holds each story's newest seq: 5 replaced 4, which
-- comes in empty, or the stream would never be whole.
Eq(Curated.Import({ epoch = 100, stories = { { seq = 5, id = L12, title = "The Barrens",
    text = "Bram Redfen and I set out.\n\nThe road was long.", t = now - 7200 } } }), 1, "a story written again")
Eq(Store.Author(CURATED).last, 5, "a seq the file leaves out stalls the curated stream")

--------------------------------------------------------------------------
Section("Your Diary reads the story in place of its own prose")

local A = F.STRANGER.guid
ns.Characters.Observe(A, { first = "Bram", surname = "Redfen", level = 11, faction = "Horde" })
ns.Diary.Add(A, { source = "test" })

local t0 = now - 3 * DAY
ns.db.journey[SELF.guid] = nil
local j = ns.Journey.Begin(SELF.guid, t0, 11, 1412)
j.segments[1] = { kind = "stop", from = t0, to = t0 + 1800, mapID = 1412, x = 0.4, y = 0.6, r = 50, seconds = 1800,
    subZone = "Red Rocks", levelFrom = 11, levelTo = 12 }
j.levels[12] = { at = t0 + 1000, mapID = 1412, x = 0.4, y = 0.6 }
j.segments[2] = { kind = "stop", from = t0 + 1800, to = t0 + 3600, mapID = 1413, x = 0.5, y = 0.3, r = 40,
    seconds = 1800, subZone = "The Crossroads", levelFrom = 12, levelTo = 12 }
ns.Sessions.New({ me = SELF.guid, source = "group", startedAt = t0 + 2000, endedAt = t0 + 3000,
    participants = { [A] = { since = t0 + 2000, last = t0 + 3000, seconds = 1000, levelStart = 12 } } })
ns.Journey.Touch()

ns.UI.ShowJournal()
ns.UI.SetJournalView("journey")
local page = ns.UI.JourneyPage()
local function Texts()
    local texts = {}
    for _, item in ipairs(page.items) do
        if item.text then texts[#texts + 1] = item.text end
    end
    return table.concat(texts, "\n")
end
Check(Texts():find("The road was long.", 1, true), "the open level does not read the story")
Check(Texts():find("|Hsdperson:" .. A, 1, true), "a name in the story is not a link to their page")

ns.SetSetting("showCurated", false)
ns.UI.RefreshJourneyPage()
Check(not Texts():find("The road was long.", 1, true), "the story is read with curated stories off")
Check(Texts():find("Bram Redfen", 1, true), "the diary's own prose is not back")
ns.SetSetting("showCurated", true)

--------------------------------------------------------------------------
Section("the Sync settings page")

ns.UI.ShowSettings("sync")
local P = ns.UI.SettingsPage()
Eq(P:Section(), "sync", "the Sync section did not open")
Eq(P.syncStatus:GetText(), "Not syncing.", "the status without a code")
Check(P.shareNotes.unavailable, "Share my notes is available without a code")

local TILOU = "Player-4620-00777777"
Store.Restart(TILOU, 500)
Store.Put(TILOU, 1, { r = "me:card", k = "me", name = "Tilougil Hutdieb", class = "MAGE" })
P.groupCode:SetText("  gigus ")
P.groupCode.scripts.OnEditFocusLost(P.groupCode)
Eq(ns.Setting("groupCode"), "gigus", "the code was not written, trimmed")
Check(ns.Sync.Transport.Status().on, "entering a code did not start sync")
Check(Store.ByRef(SELF.guid, "me:card"), "entering a code did not feed the diary")
Check(P.syncStatus:GetText():find("Diaries held: Tilougil Hutdieb", 1, true), "the status does not name Tilou")
Check(not P.shareNotes.unavailable, "Share my notes is unavailable with a code")
