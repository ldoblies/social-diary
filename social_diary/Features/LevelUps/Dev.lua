-- Level-ups' part of /sd testdata (Dev/TestData.lua, TestData.Register):
-- Tester's level-ups, 18 in the first session six days ago, 19 to 21
-- yesterday (one in Wailing Caverns), 22 in Razorfen Kraul today, five
-- rows, the three of yesterday's a climb when folded. Development tooling:
-- listed in the TOC's do-not-package block, and left out by .pkgmeta.
--
-- Each written as UNIT_LEVEL would have stored it (Capture.lua: from the
-- level before), at "tester", after its session's own rows. This file
-- loads before Trade's and Chat's Dev.lua (the TOC), so a session's
-- level-ups come before the trade and the whispers written at the same
-- point, as when they were the script's own.

local addonName, ns = ...

local TestData = ns.TestData
local MIN = 60

local function LevelUp(c, time, zone, level)
    c.Row("level_up", time, zone, { context = { from = level - 1, level = level } }, c.session)
end

TestData.Register("tester", function(c)
    local t = c.session.startedAt
    if c.n == 1 then
        LevelUp(c, t + 32 * MIN, "The Barrens", 18)
    elseif c.n == 2 then
        LevelUp(c, t + 30 * MIN, "The Barrens", 19)
        LevelUp(c, t + 95 * MIN, "Wailing Caverns", 20)
        LevelUp(c, t + 140 * MIN, "Stonetalon Mountains", 21)
    elseif c.n == 3 then
        LevelUp(c, t + 25 * MIN, "Razorfen Kraul", 22)
    end
end)
