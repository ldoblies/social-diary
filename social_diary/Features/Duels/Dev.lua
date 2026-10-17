-- Duels' part of /sd testdata (Dev/TestData.lua, TestData.Register): a
-- series with Tester, as a row and on the route, and the made-up route's
-- other duels, each placed for a case on Your Diary's plates. Development
-- tooling: listed in the TOC's do-not-package block, and left out by
-- .pkgmeta.

local addonName, ns = ...

local TestData = ns.TestData
local MIN, DAY = 60, 24 * 60 * 60
local BARRENS, STONETALON, ORGRIMMAR = 1413, 1442, 1454

-- Duelled Tester five times, 50 minutes into their first session (which
-- began 300 s into the evening six days ago), after the campfire (41 min):
-- lost three, won two, the last lost. Its row, and the same series on the
-- route, at the edge of Lushwater Oasis.
local WITH_TESTER = 50 * MIN
local SERIES = { won = 2, lost = 3, last = "lost" }

TestData.Register("tester", function(c)
    if c.n ~= 1 then return end
    local t = c.session.startedAt + WITH_TESTER
    c.Row(ns.Duels.KIND, t, "The Barrens", { context = { won = SERIES.won, lost = SERIES.lost, last = SERIES.last,
        ended = t + 8 * MIN, subZone = "Lushwater Oasis" } }, c.session)
end)

-- The route's duels (ns.Duels.Added's records), as capture keeps them:
-- one a series, where its first duel started; oldest first.
TestData.Register("route", function(c)
    local j, Stop = c.j, c.Stop
    j.duels = {}
    local function Duel(at, map, x, y, sub, zone, counts, guid)
        local rec = { t = at, ended = at + 2 * MIN, guid = guid, mapID = map, x = x, y = y, subZone = sub,
            zone = zone, last = counts.last }
        for _, key in ipairs({ "won", "lost", "fled", "theyFled" }) do rec[key] = counts[key] end
        j.duels[#j.duels + 1] = rec
    end
    -- Level 11: two won and one lost against Tester in the valley, on FL's
    -- print: the note across the print's foot (variant D, signed 15 Oct),
    -- as the campfire's slip finds no room under that caption.
    Duel(Stop(11, "Valley of Strength").to - 900, ORGRIMMAR, 0.56, 0.66, "Valley of Strength", "Orgrimmar",
        { won = 2, lost = 1, last = "won" }, TestData.GUID)
    -- Level 12: a single duel won at the crag, with someone the diary
    -- never read: the full plate's filler.
    Duel(Stop(12, "Windshear Crag").to - 1500, STONETALON, 0.68, 0.60, "Windshear Crag", "Stonetalon Mountains",
        { won = 1, last = "won" })
    -- Level 15: a stranger fled from the user's duel by the raptors, then a
    -- flight of the user's own, a few yards on: a win, then a loss.
    local raptors = Stop(15, "Raptor Grounds").to
    Duel(raptors - 2400, BARRENS, 0.45, 0.82, "Raptor Grounds", "The Barrens", { theyFled = 1, last = "they_fled" })
    Duel(raptors - 700, BARRENS, 0.46, 0.83, "Raptor Grounds", "The Barrens", { fled = 1, last = "fled" })
    -- And the series with Tester (the row above), on the spot of your time
    -- together.
    local t = c.now - 6 * DAY + 300 + WITH_TESTER
    Duel(t, BARRENS, 0.56, 0.43, "Lushwater Oasis", "The Barrens", SERIES, TestData.GUID)
    j.duels[#j.duels].ended = t + 8 * MIN
end)
