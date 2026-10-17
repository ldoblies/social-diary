-- Profession caps' part of /sd testdata (Dev/TestData.lua,
-- TestData.Register): the made-up route's caps, one at level 11 and one at
-- 12, each on the plate of the zone it was reached in. Development
-- tooling: listed in the TOC's do-not-package block, and left out by
-- .pkgmeta.

local addonName, ns = ...

local TestData = ns.TestData
local ORGRIMMAR, STONETALON = 1454, 1442
local FIRST_AID, MINING = 129, 186

-- The route's caps (ns.ProfessionCaps.Add's records), as capture keeps
-- them, at the level of the stop they are timed by; oldest first.
TestData.Register("route", function(c)
    local j, Stop = c.j, c.Stop
    j.skillCaps = {}
    local function Cap(stop, ago, map, x, y, skillLine, name, rank)
        j.skillCaps[#j.skillCaps + 1] = { t = stop.to - ago, mapID = map, x = x, y = y, level = stop.level,
            skillLine = skillLine, name = name, rank = rank }
    end
    -- Level 11: First Aid at its first cap, bandaging in the city.
    Cap(Stop(11, "Valley of Strength"), 300, ORGRIMMAR, 0.55, 0.67, FIRST_AID, "First Aid", 75)
    -- Level 12: Mining at its second cap, off the crag's veins.
    Cap(Stop(12, "Windshear Crag"), 700, STONETALON, 0.73, 0.59, MINING, "Mining", 150)
end)
