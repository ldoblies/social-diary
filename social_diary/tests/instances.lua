-- Instance visits (INS-1): ids, who was in them, and forgetting (PRV-3).
-- How they show on the timeline is in timeline.lua.

local T = ...
local mock, F = T.mock, T.F
local Section, Check, Eq = T.Section, T.Check, T.Eq
local ns = T.Boot()
local Instances = ns.Instances

local A, B = F.STRANGER.guid, F.GARRICK.guid

local function Member(guid, first)
    return { guid = guid, first = first }
end

--------------------------------------------------------------------------
Section("visits get ids from meta.nextVisitId")

Eq(ns.db.meta.nextVisitId, 1, "nextVisitId is not in the schema's defaults")

local wc = Instances.New({ name = "Wailing Caverns", startedAt = 100, endedAt = 200,
    members = { Member(A, "Bram"), Member(B, "Garrick") } })
local rfk = Instances.New({ name = "Razorfen Kraul", startedAt = 300, members = { Member(A, "Bram") } })
Eq(wc.id, 1, "first visit id")
Eq(rfk.id, 2, "second visit id")
Eq(ns.db.meta.nextVisitId, 3, "the counter did not move on")
Eq(ns.db.instances[1], wc, "a visit is not stored under its id")
Eq(wc.me, F.SELF.guid, "a visit does not record which of the user's characters was there")
Eq(#Instances.All(), 2, "All")

--------------------------------------------------------------------------
Section("For: the visits someone was in")

Eq(#Instances.For(A), 2, "visits with A")
local withB = Instances.For(B)
Eq(#withB, 1, "visits with B")
Eq(withB[1], wc, "B's visit")
Eq(#Instances.For(F.PUG.guid), 0, "visits with someone who was in none")
Eq(#Instances.For(mock.secret("Player-1-2")), 0, "a secret GUID matched")
Eq(#Instances.For(nil), 0, "nil matched")

--------------------------------------------------------------------------
Section("forgetting (PRV-3)")

-- Through the registry, as Characters.Forget walks it: the person leaves
-- the member list, the visit stays.
ns.Characters.Observe(B, { first = "Garrick", surname = "Fallow" })
ns.Characters.Forget(B)
Eq(#Instances.For(B), 0, "a forgotten person is still in a visit")
Eq(#wc.members, 1, "forgetting B took someone else too")
Eq(ns.db.instances[1], wc, "forgetting a member dropped the visit")

Eq(Instances.Remove(2), true, "Remove")
Eq(Instances.Remove(2), false, "Remove twice")
Eq(#Instances.All(), 1, "Remove left the visit")

Instances.New({ name = "Ragefire Chasm", startedAt = 400, members = {} })
Eq(ns.db.meta.nextVisitId, 4, "a removed id was given out again")
ns.ForgetEverywhere(nil)
Eq(next(ns.db.instances), nil, "forgetting everyone left visits")

--------------------------------------------------------------------------
-- Capture (Capture/Instances.lua)
--------------------------------------------------------------------------

local STRANGER, PUG, GARRICK = F.STRANGER, F.PUG, F.GARRICK
local Check_ = ns._test.InstancesCheck
local GRACE = Instances.GRACE

-- Every value in a visit, however deep, is plain.
local function NoSecrets(t, path)
    for k, v in pairs(t) do
        Check(not issecretvalue(k) and not issecretvalue(v), "a secret stored at " .. path .. "." .. tostring(k))
        if type(v) == "table" then NoSecrets(v, path .. "." .. tostring(k)) end
    end
end

local function MemberOf(visit, guid)
    for _, m in ipairs(visit.members) do
        if m.guid == guid then return m end
    end
    return nil
end

local function Enter(name, id)
    mock.inInstance, mock.instanceName, mock.instanceID = true, name, id
    mock.fire("PLAYER_ENTERING_WORLD", false, false)
end

local function Leave()
    mock.inInstance = false
    mock.fire("PLAYER_ENTERING_WORLD", false, false)
end

--------------------------------------------------------------------------
Section("an old diary gets a place for the open visit")

ns.db.meta.openVisits = nil
ns.InitDB()
Eq(type(ns.db.meta.openVisits), "table", "meta.openVisits is not in the schema's defaults")

--------------------------------------------------------------------------
Section("entering a dungeon starts a visit, with the group as it went in")

mock.now = 1790000000
T.BlankDiary()
ns._test.SettleGroup()
mock.groupSize = 3
mock.SetUnit("party1", F.Like(STRANGER, { role = "HEALER" }))
mock.SetUnit("party2", PUG)
ns.Diary.Add(STRANGER.guid, { source = "test" })
mock.fire("GROUP_ROSTER_UPDATE")
local session = ns.Sessions.Current()
Check(session, "setup: no together session with a diary entry in the group")

local before = ns.db.meta.nextVisitId
local t0 = mock.now
Enter("Wailing Caverns", 43)
local visit = Instances.Current()
Check(visit, "entering a dungeon started no visit")
Eq(visit.id, before, "the visit was not stored under the next id")
Eq(ns.db.instances[visit.id], visit, "the visit is not in db.instances")
Eq(visit.me, F.SELF.guid, "me")
Eq(visit.instanceID, 43, "instanceID")
Eq(visit.name, "Wailing Caverns", "name")
Eq(visit.instanceType, "party", "instanceType")
Eq(visit.difficulty, "Normal", "difficulty")
Eq(visit.startedAt, t0, "startedAt")
Eq(visit.endedAt, nil, "a visit under way has an end")
Eq(#visit.members, 2, "the group's two members")
Check(not MemberOf(visit, F.SELF.guid), "the user is among the members")
local bram = MemberOf(visit, STRANGER.guid)
Eq(bram and bram.first, "Bram", "first name")
Eq(bram and bram.surname, "Redfen", "surname")
Eq(bram and bram.class, "DRUID", "class token")
Eq(bram and bram.role, "HEALER", "role")
Eq(MemberOf(visit, PUG.guid).role, nil, "a role of NONE was stored")
Eq(visit.sessionIds[1], session.id, "the together session is not the visit's")
Eq(#visit.sessionIds, 1, "the session was noted twice")
Eq(visit.deaths, 0, "deaths")
Eq(visit.wipes, 0, "wipes")
Eq(visit.bossTotal, nil, "bossTotal")

--------------------------------------------------------------------------
Section("inside, a secret party stores nothing secret and loses no one")

mock.now = mock.now + 60
mock.SetUnit("party1", F.Like(STRANGER, { guid = mock.secret(STRANGER.guid) }))
mock.SetUnit("party2", F.Like(PUG, { role = mock.secret("TANK"), name = mock.secret("Norwood") }))
mock.fire("GROUP_ROSTER_UPDATE")
Check_(false)
Eq(#visit.members, 2, "a member behind a secret GUID was dropped or doubled")
Eq(MemberOf(visit, PUG.guid).role, nil, "a secret role was stored")
Eq(MemberOf(visit, PUG.guid).first, "Norwood", "a secret name wiped the one read before")
NoSecrets(visit, "visit")

-- Someone joining mid-run, readable, is added; someone leaving stays.
mock.SetUnit("party1", F.Like(GARRICK, { role = "TANK" }))
mock.SetUnit("party2", nil)
mock.fire("GROUP_ROSTER_UPDATE")
Eq(#visit.members, 3, "a member who joined inside was not added, or one who left was dropped")
Eq(MemberOf(visit, GARRICK.guid).role, "TANK", "the new member's role")

--------------------------------------------------------------------------
Section("bosses, wipes and deaths")

mock.fire("ENCOUNTER_END", 585, "Lady Anacondra", 1, 5, 1)
mock.fire("ENCOUNTER_END", 585, "Lady Anacondra", 1, 5, 1)
mock.fire("ENCOUNTER_END", 593, "Skum", 1, 5, 0)
mock.fire("ENCOUNTER_END", 594, mock.secret("Lord Serpentis"), 1, 5, 1)
mock.fire("ENCOUNTER_END", 595, "Mutanus", 1, 5, mock.secret(1))
Eq(#visit.bossesKilled, 1, "a boss killed twice, a wipe or a secret counted as a kill")
Eq(visit.bossesKilled[1], "Lady Anacondra", "the boss's name")
Eq(visit.wipes, 1, "the wipe")

mock.fire("PLAYER_DEAD")
mock.fire("PLAYER_DEAD")
Eq(visit.deaths, 1, "one death told twice was counted twice")
mock.fire("PLAYER_UNGHOST")
mock.fire("UNIT_DIED", PUG.guid)
mock.fire("UNIT_DIED", mock.secret(GARRICK.guid))
mock.fire("UNIT_DIED", "Creature-0-4620-1-10-3653-00001")
mock.fire("UNIT_DIED", F.HOSTILE.guid)
Eq(visit.deaths, 2, "a member's death, and only a member's, counts")
NoSecrets(visit, "visit")

--------------------------------------------------------------------------
Section("a reload or relog inside carries the visit on")

local id = visit.id
mock.now = mock.now + 60
mock.fire("PLAYER_ENTERING_WORLD", false, true)
Eq(Instances.Current(), visit, "a reload inside started another visit")
Eq(ns.db.meta.nextVisitId, id + 1, "a reload gave out an id")

mock.fire("PLAYER_LOGOUT")
mock.now = mock.now + 5 * 60
mock.fire("PLAYER_ENTERING_WORLD", true, false)
Eq(Instances.Current(), visit, "a relog inside started another visit")
Eq(visit.endedAt, nil, "a relog inside ended the visit")

--------------------------------------------------------------------------
Section("leaving ends it; coming back within the grace carries it on")

mock.now = mock.now + 10 * 60
local left = mock.now
Leave()
Eq(visit.endedAt, left, "leaving did not end the visit")
Eq(Instances.Current(), nil, "a visit left is still under way")
mock.fire("ENCOUNTER_END", 593, "Skum", 1, 5, 1)
mock.fire("PLAYER_DEAD")
mock.fire("PLAYER_UNGHOST")
Eq(#visit.bossesKilled + visit.deaths, 3, "something outside counted on the visit")

-- A corpse run.
mock.now = mock.now + 8 * 60
Check_(false)
Enter("Wailing Caverns", 43)
Eq(Instances.Current(), visit, "coming back within the grace started another visit")
Eq(visit.endedAt, nil, "the visit came back ended")

-- Out, and a different dungeon at once: a visit of its own.
mock.now = mock.now + 60
Leave()
local wcEnd = mock.now
mock.now = mock.now + 60
Enter("Razorfen Kraul", 47)
local rfk = Instances.Current()
Check(rfk and rfk ~= visit, "another dungeon carried the last visit on")
Eq(visit.endedAt, wcEnd, "the last visit's end moved")
Eq(rfk.id, id + 1, "the new visit's id")

-- Out of it, and back after the grace: a new visit.
Leave()
local rfkEnd = mock.now
mock.now = mock.now + GRACE + 60
Check_(false)
Eq(ns.db.meta.openVisits[F.SELF.guid], nil, "a visit past its grace is still open")
Enter("Razorfen Kraul", 47)
local rfk2 = Instances.Current()
Check(rfk2 and rfk2 ~= rfk, "coming back after the grace carried the visit on")
Eq(rfk.endedAt, rfkEnd, "the old visit's end moved")

-- Logged out inside, and in again outside long after: it ended when last
-- seen inside.
local seen = mock.now
mock.fire("PLAYER_LOGOUT")
mock.now = mock.now + 3 * 3600
mock.inInstance = false
mock.fire("PLAYER_ENTERING_WORLD", true, false)
Eq(rfk2.endedAt, seen, "a visit left by a logout did not end when last seen inside")

--------------------------------------------------------------------------
Section("the visit on a member's timeline (TLN-4)")

local function FindVisit(items)
    for _, item in ipairs(items) do
        if item.kind == "visit" and item.visit == visit then return item end
        local inner = item.all and FindVisit(item.all)
        if inner then return inner end
    end
    return nil
end

local item = FindVisit(ns.Timeline.For(STRANGER.guid))
Check(item, "the visit is not on the member's timeline")
local _, text, _, icon, full = ns.UI.DescribeItem(item, STRANGER.guid)
Eq(text, ("Wailing Caverns, %d min, 1 boss"):format(math.floor((wcEnd - t0) / 60)), "the visit's headline")
Eq(icon, "dungeon", "the visit's icon")
Check(full:find("2 deaths  ·  1 wipe  ·  with Norwood and Garrick  ·  killed Lady Anacondra", 1, true),
    "the visit's details: " .. tostring(full))

--------------------------------------------------------------------------
Section("dungeon groups on the Recently nearby page")

local day = ns.DayStart(t0)
local norwood
for _, e in ipairs(ns.Sightings.DayEntries(day)) do
    if e.guid == PUG.guid then norwood = e end
end
Check(norwood, "a dungeon group member is not on the day's list")
-- Still in the roster, so in Razorfen Kraul too: the latest that day.
Check(norwood and (norwood.zone == "Wailing Caverns" or norwood.zone == "Razorfen Kraul"),
    "where they were: " .. tostring(norwood and norwood.zone))
local listed = false
for _, d in ipairs(ns.Sightings.Days()) do
    if d.start == day then listed = true end
end
Check(listed, "the dungeon's day is not among the days")

--------------------------------------------------------------------------
Section("a solo run is not kept, until someone joins")

mock.groupSize = 0
mock.ClearUnits()
mock.SetUnit("player", F.SELF)
mock.fire("GROUP_ROSTER_UPDATE")
Check(next(ns.Roster.Members()) == nil, "setup: the roster is not empty")

local stored = ns.CountKeys(ns.db.instances)
local next0 = ns.db.meta.nextVisitId
mock.now = mock.now + 60
Enter("Ragefire Chasm", 389)
Check(Instances.Current(), "no visit under way alone")
mock.fire("ENCOUNTER_END", 1, "Taragaman the Hungerer", 1, 5, 1)
Eq(ns.CountKeys(ns.db.instances), stored, "a visit with nobody in it was stored")
Leave()
mock.now = mock.now + GRACE + 60
Check_(false)
Eq(ns.CountKeys(ns.db.instances), stored, "a solo visit was stored on its way out")
Eq(ns.db.meta.nextVisitId, next0, "a solo visit took an id")

-- Alone in, then joined: kept from the door, with what it saw alone.
local soloStart = mock.now
Enter("Ragefire Chasm", 389)
mock.fire("ENCOUNTER_END", 1, "Taragaman the Hungerer", 1, 5, 1)
mock.now = mock.now + 120
mock.groupSize = 2
mock.SetUnit("party1", PUG)
mock.fire("GROUP_ROSTER_UPDATE")
local joined = Instances.Current()
Eq(ns.db.instances[joined.id], joined, "a visit someone joined was not stored")
Eq(joined.startedAt, soloStart, "the stored visit does not start at the door")
Eq(joined.bossesKilled[1], "Taragaman the Hungerer", "what it saw alone was lost")

--------------------------------------------------------------------------
Section("forgetting a member of a captured visit (PRV-3)")

ns.Characters.Forget(PUG.guid)
Check(not MemberOf(visit, PUG.guid), "a forgotten person is still in the visit")
Eq(ns.db.instances[visit.id], visit, "forgetting a member dropped the visit")
Eq(#visit.members, 2, "forgetting one member took another")
