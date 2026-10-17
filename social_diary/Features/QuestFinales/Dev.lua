-- Quest chain finales' part of /sd testdata (Dev/TestData.lua,
-- TestData.Register): the made-up route's two finales, one at level 10
-- and one at 13, and where the second's chain began, at 11. Development
-- tooling: listed in the TOC's do-not-package block, and left out by
-- .pkgmeta.

local addonName, ns = ...

local TestData = ns.TestData
local DUROTAR, BARRENS = 1411, 1413

-- The route's finales (ns.QuestFinales.Add's records) and chains begun
-- (QuestFinales.Begun's), as capture keeps them: the quest turned in, how
-- many of the chain were done, and where it began when the diary saw its
-- first quest taken; at the level of the stop they are timed by, oldest
-- first.
TestData.Register("route", function(c)
    local j, Stop = c.j, c.Stop
    j.finales, j.chainStarts = {}, {}
    local function Finale(stop, ago, map, x, y, questID, title, n, started)
        j.finales[#j.finales + 1] = { t = stop.to - ago, mapID = map, x = x, y = y, level = stop.level,
            questID = questID, title = title, n = n, started = started }
    end
    -- Level 10: a finale whose chain began before the diary: "a chain of
    -- seven", no more.
    Finale(Stop(10, "Razor Hill"), 200, DUROTAR, 0.45, 0.57, 924, "The Demon Seed", 7)
    -- Level 11: where the Samophlange chain began, at the Sludge Fen, for
    -- its finale at level 13.
    local fen = Stop(11, "The Sludge Fen")
    local samophlange = { t = fen.to - 900, mapID = BARRENS, x = 0.60, y = 0.16, level = fen.level }
    j.chainStarts[894] = samophlange
    -- Level 13: a chain of eight brought to its end at the Crossroads.
    Finale(Stop(13, "The Crossroads"), 150, BARRENS, 0.52, 0.31, 3924, "Samophlange Manual", 8, samophlange)
end)
