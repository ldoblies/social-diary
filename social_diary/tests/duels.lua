-- Duels (Features/Duels/Capture.lua): a challenge, its countdown and its
-- result line make a duel, kept as a row on the opponent and a record on
-- the route; back-to-back duels with the same player are one series; a
-- challenge called off is nothing; the duel's start and end are told to
-- core (SD_DUEL_STARTED, SD_DUEL_FINISHED) once each.

local T = ...
local mock, F = T.mock, T.F
local Section, Check, Eq = T.Section, T.Check, T.Eq

-- The client's strings (enUS, as the probe read them, 15 Oct) and the
-- user's challenge, hooked as the client's hooksecurefunc does. Set
-- before the addon loads (the hook is made at load); taken away at the end.
_G.DUEL_COUNTDOWN = "Duel starting: %d"
_G.DUEL_WINNER_KNOCKOUT = "%1$s has defeated %2$s in a duel"
_G.DUEL_WINNER_RETREAT = "%2$s has fled from %1$s in a duel"
local challenged = {}
_G.StartDuel = function(unit) challenged[#challenged + 1] = unit end
_G.hooksecurefunc = function(name, fn)
    local before = _G[name]
    _G[name] = function(...)
        local r = before(...)
        fn(...)
        return r
    end
end

local ns = T.Boot()
local D, test = ns.Duels, ns._test.Duels
local SELF, BRAM, NUMA = F.SELF, F.STRANGER, F.FRIEND
local MINUTE = 60

-- What was told: { message, guid, outcome }.
local told = {}
ns.On("SD_DUEL_STARTED", function(_, guid) told[#told + 1] = { "started", guid } end)
ns.On("SD_DUEL_FINISHED", function(_, guid, outcome) told[#told + 1] = { "finished", guid, outcome } end)

local function System(text)
    mock.fire("CHAT_MSG_SYSTEM", text, "", "", "", "", "", 0, 0, "", 0, 1, "")
end

local function Countdown()
    for n = 3, 1, -1 do
        System(DUEL_COUNTDOWN:format(n))
        mock.now = mock.now + 1
    end
end

local function DuelRows(guid)
    local list = {}
    for _, row in ipairs(ns.db.interactions[guid] or {}) do
        if row.type == D.KIND then list[#list + 1] = row end
    end
    return list
end

mock.position = { x = 0.54, y = 0.51 }
mock.zone, mock.subZone = "Westfall", "Sentinel Hill"
mock.fire("PLAYER_ENTERING_WORLD")
local j = ns.db.journey[SELF.guid]
Check(j, "setup: no route")

--------------------------------------------------------------------------
Section("the client's lines, read through its own strings")

local args = test.Read(DUEL_WINNER_KNOCKOUT, "Bram Redfen has defeated Ulverston Nye in a duel")
Eq(args and args[1], "Bram Redfen", "a knockout's winner")
Eq(args and args[2], "Ulverston Nye", "a knockout's loser")
args = test.Read(DUEL_WINNER_RETREAT, "Ulverston Nye has fled from Bram Redfen in a duel")
Eq(args and args[2], "Ulverston Nye", "who fled: the format's second argument, first in the line")
Eq(args and args[1], "Bram Redfen", "who stayed")
Eq(test.Read(DUEL_COUNTDOWN, "Duel starting: 3") ~= nil, true, "the countdown not read")
Eq(test.Read(DUEL_WINNER_KNOCKOUT, "Quest accepted: The Restless Dead"), nil, "another line read as a duel")
-- Magic characters in a format are text, not pattern.
Eq(test.Read("%s (100%%) won.", "Bram (100%) won.") ~= nil, true, "a format's magic characters")

--------------------------------------------------------------------------
Section("challenged, lost: a row on the opponent and a record on the route")

-- The challenge names them "First-Surname"; they stand on a nameplate.
mock.SetUnit("nameplate3", BRAM)
mock.fire("DUEL_REQUESTED", "Bram-Redfen")
Eq(#told, 0, "a challenge told as a duel")
Countdown()
Eq(#told, 1, "the countdown did not start a duel")
Eq(told[1][1], "started", "the start not told")
Eq(told[1][2], BRAM.guid, "the challenger not found on their nameplate")
Eq(ns.Duelling(BRAM.guid), true, "core does not know a duel is on")

mock.now = mock.now + 20
local first = mock.now
mock.fire("DUEL_FINISHED")
System("Bram Redfen has defeated Ulverston Nye in a duel")
mock.RunTimers()
Eq(#told, 2, "the end not told once")
Eq(told[2][3], "lost", "the end's outcome")
Eq(ns.Duelling(), false, "a duel still on after its end")

local rows = DuelRows(BRAM.guid)
Eq(#rows, 1, "no row on the opponent")
Eq(D.Balance(rows[1].context), "lost", "a lost duel's balance")
Eq(rows[1].context.lost, 1, "the loss not counted")
Eq(rows[1].context.last, "lost", "the latest outcome")
Eq(rows[1].context.subZone, "Sentinel Hill", "where")
Eq(rows[1].time, first, "a row written at another time than the duel's end")
local list = D.List(j)
Eq(#list, 1, "no record on the route")
Eq(list[1].guid, BRAM.guid, "the route's record: who")
Eq(list[1].lost, 1, "the route's record: the loss")
Eq(list[1].mapID, mock.mapID, "the route's record: where")
-- From the countdown's first line, three seconds and the fight before.
Eq(list[1].t, first - 23, "the route's record: from the countdown")

--------------------------------------------------------------------------
Section("one after another: one series")

-- Five minutes on, the user challenges them (the unit menu: "target"), and
-- wins; the series is level, and goes by its latest: won.
mock.now = mock.now + 5 * MINUTE
mock.SetUnit("nameplate3", nil)
mock.SetUnit("target", BRAM)
StartDuel("target")
Eq(challenged[#challenged], "target", "the hook kept the client's StartDuel from running")
Countdown()
Eq(told[3][2], BRAM.guid, "the challenged not read off the unit")
mock.now = mock.now + 15
mock.fire("DUEL_FINISHED")
System("Ulverston Nye has defeated Bram Redfen in a duel")
mock.RunTimers()
rows = DuelRows(BRAM.guid)
Eq(#rows, 1, "a rematch made a second row")
Eq(rows[1].context.won, 1, "the win not counted")
Eq(rows[1].context.lost, 1, "the loss forgotten")
Eq(D.Balance(rows[1].context), "won", "a level series not told by its latest")
Eq(#D.List(j), 1, "a rematch made a second route record")
Eq(D.List(j)[1].won, 1, "the route's series: the win")

-- They flee the third (the line comes before DUEL_FINISHED): two up.
mock.now = mock.now + 10 * MINUTE
mock.fire("DUEL_REQUESTED", "Bram-Redfen")
Countdown()
mock.now = mock.now + 30
System("Bram Redfen has fled from Ulverston Nye in a duel")
mock.fire("DUEL_FINISHED")
mock.RunTimers()
Eq(told[#told][3], "they_fled", "a flight's outcome")
Eq(told[#told - 1][1], "started", "a flight told twice")
rows = DuelRows(BRAM.guid)
Eq(#rows, 1, "within the gap of the last, still one series")
Eq(rows[1].context.theyFled, 1, "their flight not counted")
Eq(D.Balance(rows[1].context), "won", "their flight is the user's")

-- The user flees one, then loses one: two all, the latest lost.
for _, line in ipairs({ "Ulverston Nye has fled from Bram Redfen in a duel",
    "Bram Redfen has defeated Ulverston Nye in a duel" }) do
    mock.now = mock.now + 2 * MINUTE
    StartDuel("target")
    Countdown()
    System(line)
    mock.fire("DUEL_FINISHED")
    mock.RunTimers()
end
rows = DuelRows(BRAM.guid)
Eq(rows[1].context.fled, 1, "the user's flight not counted")
Eq(rows[1].context.lost, 2, "the second loss not counted")
Eq(D.Balance(rows[1].context), "lost", "a series turned not told by its balance")
Eq(D.List(j)[1].fled, 1, "the route's series: the flight")

-- Later than the gap: a new series.
mock.now = mock.now + D.SERIES_GAP + 1
StartDuel("target")
Countdown()
System("Ulverston Nye has defeated Bram Redfen in a duel")
mock.fire("DUEL_FINISHED")
mock.RunTimers()
Eq(#DuelRows(BRAM.guid), 2, "a duel past the gap joined the old series")
Eq(#D.List(j), 2, "a duel past the gap joined the old route record")

--------------------------------------------------------------------------
Section("what is no duel, and a duel with no one found")

-- A challenge called off (declined, timed out): nothing kept, nothing told.
local count, before = #told, #D.List(j)
mock.now = mock.now + 30 * MINUTE
StartDuel("target")
mock.fire("DUEL_FINISHED")
mock.RunTimers()
Eq(#told, count, "a challenge called off was told")
Eq(#D.List(j), before, "a challenge called off was kept")
Eq((test.State()), nil, "a challenge called off left a challenge open")

-- Ended with no winner: told with no outcome, kept nowhere.
StartDuel("target")
Countdown()
mock.fire("DUEL_FINISHED")
mock.RunTimers()
Eq(#told, count + 2, "a duel with no winner not told as begun and over")
Eq(told[#told][3], nil, "a duel with no winner given one")
Eq(#D.List(j), before, "a duel with no winner was kept")
Eq(ns.Duelling(), false, "a duel with no winner still on")

-- Two others' duel, heard nearby: not the user's.
System("Bram Redfen has defeated Numa Pompilius in a duel")
Eq(#told, count + 2, "another's duel was told")
Eq(#D.List(j), before, "another's duel was kept")

-- The line names someone other than the challenge: the line wins.
mock.SetUnit("target", nil)
mock.SetUnit("nameplate5", NUMA)
mock.now = mock.now + 30 * MINUTE
mock.fire("DUEL_REQUESTED", "Bram-Redfen")
Countdown()
System("Numa Pompilius has defeated Ulverston Nye in a duel")
mock.fire("DUEL_FINISHED")
mock.RunTimers()
Eq(told[#told][2], NUMA.guid, "the challenger kept over the line's opponent")
Eq(#DuelRows(NUMA.guid), 1, "no row on the line's opponent")

-- Nobody near by that name: the route keeps the duel, with nobody.
mock.SetUnit("nameplate5", nil)
mock.now = mock.now + 30 * MINUTE
mock.fire("DUEL_REQUESTED", "Ivo-Thatch")
Countdown()
System("Ivo Thatch has defeated Ulverston Nye in a duel")
mock.fire("DUEL_FINISHED")
mock.RunTimers()
local last = D.List(j)[#D.List(j)]
Eq(last.guid, nil, "an opponent made up")
Eq(last.lost, 1, "a duel with someone unread not kept")

-- The route not kept: the row still, no record.
ns.db.settings.keepRoute = false
mock.SetUnit("target", BRAM)
mock.now = mock.now + 30 * MINUTE
before = #D.List(j)
local rowsBefore = #DuelRows(BRAM.guid)
StartDuel("target")
Countdown()
System("Ulverston Nye has defeated Bram Redfen in a duel")
mock.fire("DUEL_FINISHED")
mock.RunTimers()
ns.db.settings.keepRoute = true
Eq(#D.List(j), before, "a duel kept on a route not kept")
Eq(#DuelRows(BRAM.guid), rowsBefore + 1, "no row with the route off")

--------------------------------------------------------------------------
Section("the route lets go of the opponent (PRV-3)")

local LIST = ns.Journey.LISTS.duels
Check(LIST and LIST.forget and LIST.prune, "the duels list registers no forget or prune")
LIST.forget(j, BRAM.guid)
for _, rec in ipairs(D.List(j)) do Check(rec.guid ~= BRAM.guid, "a forgotten opponent kept on the route") end
Eq(D.List(j)[1].won, 1, "forgetting took the duel with it")
-- A stranger the buffer has let go, and not in the diary: given up at
-- login; someone in the diary is kept.
local rec = D.List(j)[1]
rec.guid = NUMA.guid
LIST.prune(j, rec.ended + ns.Cutoff(0) * -1 + 1)
Eq(rec.guid, nil, "a stranger gone from the buffer kept on the route")
rec.guid = NUMA.guid
ns.Diary.Add(NUMA.guid, { source = "test" })
LIST.prune(j, rec.ended + ns.Cutoff(0) * -1 + 1)
Eq(rec.guid, NUMA.guid, "someone in the diary given up")

_G.DUEL_COUNTDOWN, _G.DUEL_WINNER_KNOCKOUT, _G.DUEL_WINNER_RETREAT = nil, nil, nil
_G.StartDuel, _G.hooksecurefunc = nil, nil
