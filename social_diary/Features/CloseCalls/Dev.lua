-- Close calls' part of /sd testdata (Dev/TestData.lua, TestData.Register):
-- the made-up route's close calls, so Your Diary's plates have their
-- crosses and the cards of the creatures that nearly got you, each case
-- of the card on a page of its own. Development tooling: listed in the
-- TOC's do-not-package block, and left out by .pkgmeta.
--
-- The list as capture keeps it (Kind.lua, j.closeCalls), at "route",
-- after the route (and after Deaths' part, before the witnesses', whose
-- rescue at the Forgotten Pools is timed at this list's first close
-- call): each close call in the stop it was fought at, timed off that
-- stop's end as the script timed it when it wrote them, at the stop's
-- level. Nothing else writes j.closeCalls, so writing it after the route
-- leaves the route as it was.

local addonName, ns = ...

local TestData = ns.TestData
local BARRENS, STONETALON = 1413, 1442

TestData.Register("route", function(c)
    local j = c.j
    j.closeCalls = {}
    local function Close(stop, ago, map, x, y, pct, seconds, foe)
        local call = { t = stop.to - ago, mapID = map, x = x, y = y, level = stop.level, pct = pct,
            seconds = seconds }
        for key, value in pairs(foe or {}) do call[key] = value end
        j.closeCalls[#j.closeCalls + 1] = call
    end
    -- Level 11, the Forgotten Pools: a close call with no creature
    -- targeted: its cross, and no card (Numa's rescue, the witnesses').
    Close(c.Stop(11, "The Forgotten Pools"), 1500, BARRENS, 0.44, 0.44, 9, 70)
    -- Level 12, the grinding stop west of the Crossroads (it has no
    -- subzone): an elite of level 29 and two more, with no display kept:
    -- no picture, the chart and its tag (on a plate of three, where the
    -- margin is tight).
    Close(c.Stop(12, nil), 500, BARRENS, 0.31, 0.29, 4, 95, { npcID = 4442, name = "Razormane Battleguard",
        rank = "elite", foeLevel = 29, foes = 3 })
    -- Level 14, Camp Taurajo: one common creature of level 13, with its
    -- display: its card cut in ink over the chart, "Lv 13" on its tag, no
    -- deed. The Murloc Streamrunner (735) and its display (527) are the
    -- pair seen in the client (10 Oct), out of its own zone.
    Close(c.Stop(14, "Camp Taurajo"), 1200, BARRENS, 0.48, 0.57, 6, 48, { npcID = 735,
        name = "Murloc Streamrunner", display = 527, foeLevel = 13 })
    -- Level 15, the Raptor Grounds: an old record, kept before levels
    -- were: a common creature and one more, no tag.
    Close(c.Stop(15, "Raptor Grounds"), 1500, BARRENS, 0.45, 0.81, 7, 30, { npcID = 3256,
        name = "Sunscale Scytheclaw", foes = 2 })
    -- At the cap, the first evening at Lushwater Oasis: a rare of level 23
    -- and another with it, out at 1%: the barest bar.
    Close(c.Stop(16, "Lushwater Oasis"), 900, BARRENS, 0.57, 0.41, 1, 38, { npcID = 5828,
        name = "Humar the Pridelord", rank = "rare", foeLevel = 23, foes = 2 })
    -- At the cap, on the crag: a boss with a skull for its level, made up
    -- for the tag: "Lv ?? (Boss)".
    Close(c.Stop(16, "Windshear Crag"), 800, STONETALON, 0.70, 0.60, 3, 120, { npcID = 12397,
        name = "Lord Kazzak", rank = "worldboss", foeLevel = -1 })
end)
