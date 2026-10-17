-- Campfires' part of /sd testdata (Dev/TestData.lua, TestData.Register):
-- the made-up route's fires, each placed for a case on Your Diary's plates,
-- and the row of the fire sat by with Tester. Development tooling: listed
-- in the TOC's do-not-package block, and left out by .pkgmeta.

local addonName, ns = ...

local TestData = ns.TestData
local MIN, DAY = 60, 24 * 60 * 60
local BARRENS, ORGRIMMAR, STONETALON = 1413, 1454, 1442

-- Sat by a fire with Tester, 41 minutes into their first session (which
-- began 300 s into the evening six days ago): the row on Tester, and the
-- same fire on the route.
local WITH_TESTER = 41 * MIN

-- Capture.lua's row, in the session it was sat by in.
TestData.Register("tester", function(c)
    if c.n ~= 1 then return end
    c.Row("campfire", c.session.startedAt + WITH_TESTER, "The Barrens", { context = { subZone = "Lushwater Oasis" } },
        c.session)
end)

-- The route's fires (ns.Campfire.Add's records), as capture keeps them: one
-- a sitting, where its first minute was done; oldest first.
TestData.Register("route", function(c)
    local j, Stop = c.j, c.Stop
    j.campfires = {}
    local function Campfire(at, map, x, y, sub, zone)
        j.campfires[#j.campfires + 1] = { t = at, mapID = map, x = x, y = y, subZone = sub, zone = zone }
    end
    -- Level 11: a campfire in the valley, on FL's print, where its slip has
    -- no room under the caption: the words say it (the user's Rule B, 14
    -- Oct).
    Campfire(Stop(11, "Valley of Strength").to - 500, ORGRIMMAR, 0.53, 0.69, "Valley of Strength", "Orgrimmar")
    -- Level 12: one at the crag, on the full plate: its slip in the
    -- narrowest column (122 px), after the lucky card.
    Campfire(Stop(12, "Windshear Crag").to - 1000, STONETALON, 0.70, 0.58, "Windshear Crag",
        "Stonetalon Mountains")
    -- Level 13: one by the lizards, in the hour after the Crossroads the
    -- route did not keep, on FL's print, where its slip has no room under
    -- the caption, and the words, long already, have no room to say it
    -- either: left to its mark (Plated's filler rule, 14 Oct).
    Campfire(Stop(13, "The Crossroads").to + 3600 - 1500, BARRENS, 0.17, 0.27, nil, "The Barrens")
    -- Level 15: two about thirty yards apart, the first sat by twice: two
    -- marks, one slip, its leader to the nearer.
    local raptors = Stop(15, "Raptor Grounds").to
    Campfire(raptors - 1900, BARRENS, 0.42, 0.84, "Raptor Grounds", "The Barrens")
    Campfire(raptors - 1000, BARRENS, 0.47, 0.81, "Raptor Grounds", "The Barrens")
    Campfire(raptors - 300, BARRENS, 0.42, 0.84, "Raptor Grounds", "The Barrens")
    -- At the cap: one on the week's light plate, its slip under the print's
    -- caption.
    Campfire(Stop(16, "Valley of Strength").to - 600, ORGRIMMAR, 0.51, 0.69, "Valley of Strength", "Orgrimmar")
    -- And the one sat by with Tester (the row above), on the spot of your
    -- time together: the ring keeps its place and the fire steps aside.
    Campfire(c.now - 6 * DAY + 300 + WITH_TESTER, BARRENS, 0.55, 0.42, "Lushwater Oasis", "The Barrens")
end)
