-- The People index and the data version it is kept by (JNL-1, JNL-6):
-- what moves ns.dataVersion, what must not, and that the index follows.

local T = ...
local mock, F = T.mock, T.F
local Section, Check, Eq = T.Section, T.Check, T.Eq
local ns = T.Boot()

local A, B = F.STRANGER, F.PUG
local Builds = ns._test.PeopleBuilds

local function Names(list)
    local names = {}
    for i = 1, #list do names[i] = list[i].name end
    return table.concat(names, ",")
end

mock.mapID, mock.zone, mock.inInstance, mock.pvpType = 1412, "Mulgore", false, nil
mock.position = { x = 0.5, y = 0.5 }
mock.fire("PLAYER_ENTERING_WORLD", false, false)

ns.Characters.Observe(A.guid, { first = "Bram", surname = "Redfen", level = 12, faction = "Horde" })
ns.Diary.Add(A.guid, { source = "test" })

--------------------------------------------------------------------------
Section("the data version (People index)")

local v = ns.dataVersion
ns.Diary.SetNote(A.guid, "met at the well")
Check(ns.dataVersion > v, "a diary edit did not move the data version")

-- A rename reaches the list: name, sort order and search.
Eq(Names(ns.People.Query({ search = "redfen" })), "Bram Redfen", "before the rename")
ns.Characters.Observe(A.guid, { first = "Bram", surname = "Moonhoof" })
Eq(Names(ns.People.Query({})), "Bram Moonhoof", "a rename did not reach the People list")
Eq(Names(ns.People.Query({ search = "moonhoof" })), "Bram Moonhoof", "the new name is not searchable")
Eq(Names(ns.People.Query({ search = "redfen" })), "Bram Moonhoof", "the old name is no longer searchable (DIA-9)")
Eq(ns.People.Stats(A.guid).sortName, "bram moonhoof", "sort name not renamed")

-- A level or faction change is indexed too.
ns.Characters.Observe(A.guid, { level = 13 })
Eq(ns.People.Stats(A.guid).levelNow, 13, "a level-up did not reach the index")

-- Observing without a change keeps the index: the same name, a first-name-
-- only read (DIA-2a), the same level, a field the index does not copy.
ns.People.Index()
local built = Builds()
v = ns.dataVersion
ns.Characters.Observe(A.guid, { first = "Bram", surname = "Moonhoof", level = 13, faction = "Horde" })
ns.Characters.Observe(A.guid, { first = "Bram" })
ns.Characters.Observe(A.guid, { guild = "Some Guild", class = "DRUID" })
Eq(ns.dataVersion, v, "an unchanged observation moved the data version")
ns.People.Index()
Eq(Builds(), built, "an unchanged observation rebuilt the index")

-- A stranger is not in the index: their renames and rows change nothing.
ns.Characters.Observe(B.guid, { first = "Norwood", surname = "Sparks", level = 10 })
ns.Characters.Observe(B.guid, { first = "Norwood", surname = "Longs", level = 11 })
ns.Interactions.Add(B.guid, "trade", {})
Eq(ns.dataVersion, v, "a stranger moved the data version")

-- A diary entry's row is a meeting.
ns.Interactions.Add(A.guid, "trade", {})
Check(ns.dataVersion > v, "a diary entry's trade did not move the data version")
Eq(ns.People.Stats(A.guid).timesMet, 1, "the trade is not a meeting")

-- Opening the journal twice with nothing written in between builds once.
ns.UI.ShowJournal()
built = Builds()
ns.UI.CloseJournal()
ns.UI.ShowJournal()
Eq(Builds(), built, "reopening an unchanged journal rebuilt the index")
ns.UI.SetJournalView("people")
Eq(Builds(), built, "turning to People rebuilt an unchanged index")
ns.UI.RefreshJournal()
Eq(Builds(), built, "RefreshJournal rebuilt an unchanged index")

-- ... and a write in between is seen on the next open.
ns.UI.CloseJournal()
ns.Diary.AddTag(A.guid, "friend")
ns.UI.ShowJournal()
Eq(Builds(), built + 1, "a write while closed was not picked up on opening")
Eq(Names(ns.People.Query({ tag = "friend" })), "Bram Moonhoof", "the tag is not in the index")

-- A mouseover on an unchanged diary entry: sightings, "last seen", the
-- nearby toast's stats. None of it is a write the index reads.
built, v = Builds(), ns.dataVersion
local Unit = F.Like(A, { name = { "Bram", "Moonhoof" }, level = 13 })
mock.SetUnit("mouseover", Unit)
mock.fire("UPDATE_MOUSEOVER_UNIT")
ns._test.DrainSightings()
Check(#ns.Sightings.For(A.guid) > 0, "the mouseover never reached the sightings")
Check(ns.Characters.Get(A.guid).seen, "the mouseover did not set last seen")
ns.People.Index()
Eq(ns.dataVersion, v, "a mouseover on an unchanged diary entry moved the data version")
Eq(Builds(), built, "a mouseover on an unchanged diary entry rebuilt the index")
mock.SetUnit("mouseover", nil)
ns.UI.CloseJournal()

-- Together (the trade above opened the session): a pulse in the same second
-- as the last one changes nothing the index reads; a later one does.
mock.now = mock.now + 10
ns.Sessions.Together(A.guid, "nearby", true)
local seconds = ns.People.Stats(A.guid).seconds
v = ns.dataVersion
ns.Sessions.Together(A.guid, "nearby")
Eq(ns.dataVersion, v, "a same-second pulse moved the data version")
mock.now = mock.now + 30
ns.Sessions.Together(A.guid, "nearby")
Check(ns.dataVersion > v, "time together did not move the data version")
Eq(ns.People.Stats(A.guid).seconds, seconds + 30, "time together not in the index")

-- Forgetting someone drops them from the index.
ns.Characters.Forget(A.guid)
Eq(Names(ns.People.Query({})), "", "a forgotten entry is still indexed")
