-- Deaths' part of /sd testdata (Dev/TestData.lua, TestData.Register): the
-- made-up route's deaths with what killed them, so Your Diary's plates
-- have killer cards (and the witnesses, Features/Witnesses/Dev.lua's, a
-- death to have watched). Development tooling: listed in the TOC's do-not-package
-- block, and left out by .pkgmeta.
--
-- The list as capture keeps it (Kind.lua, j.deaths), at "route", after the
-- route: each death in a stop that counts it (act.deaths), timed off that
-- stop's end as the script timed it when it wrote them, so the witnesses'
-- rows, written at the same moments (after this, at "route"), still find
-- them. Nothing
-- else writes j.deaths, so writing it after the route leaves the route as
-- it was. A session's deaths (Tester's sessions' deathLog) are fields of
-- the session the script makes whole, and stay there.

local addonName, ns = ...

local TestData = ns.TestData
local DUROTAR, BARRENS, STONETALON = 1411, 1413, 1442

TestData.Register("route", function(c)
    local j = c.j
    j.deaths = {}
    local function Death(at, map, x, y, npcID, name, extra)
        local d = { t = at, mapID = map, x = x, y = y, npcID = npcID, name = name }
        for key, value in pairs(extra or {}) do d[key] = value end
        j.deaths[#j.deaths + 1] = d
    end
    -- Level 10: killed by a raptor grinding by Razor Hill; Wenna waded in
    -- and could not save you (the witness card, helped, in the row under
    -- the plate).
    Death(c.Stop(10, "Razor Hill").to - 700, DUROTAR, 0.44, 0.57, 3123, "Bloodtalon Scythemaw", { spell = "Rend" })
    -- Level 13: a centaur raid on the Crossroads, and Corvin watched you die
    -- (the watched card in the 176 px column, L).
    Death(c.Stop(13, "The Crossroads").to - 450, BARRENS, 0.51, 0.31, 3274, "Kolkar Pack Runner",
        { spell = "Rend" })
    -- Level 14: two deaths at Camp Taurajo; the second, three strangers
    -- only saw (the glance's card, M).
    local taurajo = c.Stop(14, "Camp Taurajo").to
    Death(taurajo - 2000, BARRENS, 0.46, 0.57, 3275, "Kolkar Marauder")
    Death(taurajo - 500, BARRENS, 0.48, 0.59, 3265, "Razormane Hunter", { spell = "Shoot" })
    -- At the cap, the first evening at Lushwater Oasis: Grisha stood and
    -- watched you die (the merciless card).
    Death(c.Stop(16, "Lushwater Oasis").to - 400, BARRENS, 0.55, 0.43, 3461, "Oasis Snapjaw", { spell = "Bite" })
    -- At the cap, on the crag; Brakk tried to save you (the helped card, XL).
    Death(c.Stop(16, "Windshear Crag").to - 1500, STONETALON, 0.72, 0.62, 4022, "Bloodfury Harpy")
end)
