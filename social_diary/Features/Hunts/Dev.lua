-- Hunts' part of /sd testdata (Dev/TestData.lua, TestData.Register): the
-- made-up route's quest drops counted, so Your Diary's plates have their
-- tallies and stars, the hunt card, the lucky card in its sizes and S on
-- a light plate's print. Development tooling: listed in the TOC's
-- do-not-package block, and left out by .pkgmeta.
--
-- The list as capture keeps it (Kind.lua, j.hunts; Kind.lua's Done), at
-- "route", after the route (and after the other features' parts: nothing
-- else reads j.hunts while the route is written): each hunt at the stop
-- it ended at, timed off that stop's end as the script timed it when it
-- wrote them, at the stop's level. Ten hunts, so the character's usual is
-- known (Hunts.UsualLuck): usual ones, which never show, bad luck and
-- good. Item IDs as QuestieDB has them (the hunt card's icon); the
-- harpies' talons and the Kolkar key keep none, as an old record.
-- Nothing else writes j.hunts, so writing it after the route leaves the
-- route as it was.

local addonName, ns = ...

local TestData = ns.TestData
local DUROTAR, BARRENS, STONETALON = 1411, 1413, 1442

TestData.Register("route", function(c)
    local j = c.j
    j.hunts = {}
    local function Hunt(stop, at, map, x, y, quest, need, kills, npcID, name, extra)
        local hunt = { t = at, mapID = map, x = x, y = y, level = stop.level, questID = quest[1],
            title = quest[2], item = quest[3], need = need, kills = kills, npcID = npcID, name = name }
        for key, value in pairs(extra or {}) do hunt[key] = value end
        j.hunts[#j.hunts + 1] = hunt
    end

    -- Level 10, grinding by Razor Hill.
    local stop = c.Stop(10, "Razor Hill")
    Hunt(stop, stop.to - 300, DUROTAR, 0.46, 0.55, { 817, "Practical Prey", "Durotar Tiger Fur" }, 4, 7, 3121,
        "Durotar Tiger", { itemID = 4892 })

    -- Level 11, the Forgotten Pools.
    stop = c.Stop(11, "The Forgotten Pools")
    Hunt(stop, stop.to - 200, BARRENS, 0.46, 0.45, { 845, "The Zhevra", "Zhevra Hooves" }, 4, 6, 3242,
        "Zhevra Runner", { itemID = 5086 })
    -- Good luck on a full plate with a caption column (LuckyCard.lua's
    -- L): four beaks off the first four, where forty were expected.
    Hunt(stop, stop.to - 100, BARRENS, 0.44, 0.46, { 844, "Plainstrider Menace", "Plainstrider Beak" }, 4, 4,
        3244, "Greater Plainstrider", { expected = 40, itemID = 5087 })

    -- Level 12, Windshear Crag.
    stop = c.Stop(12, "Windshear Crag")
    Hunt(stop, stop.to - 300, STONETALON, 0.71, 0.61, { 6284, "Harpies Threaten", "Witchwing Talon" }, 6, 11,
        4022, "Bloodfury Harpy", { itemID = 5064 })
    -- Good luck in a narrow column (the lucky card's M, two lines on its
    -- tag): the remains off the first, where nine were expected.
    Hunt(stop, stop.to - 250, STONETALON, 0.72, 0.62, { 6283, "Bloodfury Bloodline", "Bloodfury Ripper's Remains" },
        1, 1, 4024, "Bloodfury Ripper", { expected = 9 })

    -- Level 13, back at the Crossroads after the Wailing Caverns.
    stop = c.Stop(13, "The Crossroads")
    Hunt(stop, stop.to - 2000, BARRENS, 0.50, 0.40, { 867, "Harpy Raiders", "Harpy Talon" }, 8, 13, 3276,
        "Witchwing Harpy")
    -- Then good luck out west, in the hour after that stop the route did
    -- not keep: a light plate after the full one. Its print would be
    -- tucked into the full plate's row (F+L), but the lucky card's S will
    -- not go on the smaller print, so the page is FL and S lies on the
    -- snapshot, its corner come unstuck (LuckyCard.lua). The blood off
    -- four lizards, where 33 were expected.
    Hunt(stop, stop.to + 3600 - 1800, BARRENS, 0.16, 0.25, { 907, "Enraged Thunder Lizards", "Thunder Lizard Blood" },
        3, 4, 3239, "Thunder Lizard", { expected = 33 })

    -- Level 14, Camp Taurajo. Good luck (EXT-3): the one item off the
    -- first kill, where ten were expected; and seven off four, where 58
    -- were.
    stop = c.Stop(14, "Camp Taurajo")
    Hunt(stop, stop.to - 900, BARRENS, 0.46, 0.59, { 852, "Hezrul's Head", "Hezrul's Head" }, 1, 1, 3396,
        "Hezrul Bloodmark", { expected = 10, itemID = 5025 })
    Hunt(stop, stop.to - 300, BARRENS, 0.48, 0.60, { 4021, "Counterattack!", "Kolkar Booty Key" }, 7, 4, 3275,
        "Kolkar Marauder", { expected = 58.3 })

    -- Level 15, the Raptor Grounds. The bad luck: five horns took 26
    -- raptors of two kinds, where twelve were expected (EXT-2).
    stop = c.Stop(15, "Raptor Grounds")
    Hunt(stop, stop.to - 400, BARRENS, 0.43, 0.83, { 865, "Raptor Horns", "Intact Raptor Horn" }, 5, 26, 3256,
        "Sunscale Scytheclaw", { expected = 12, itemID = 5055,
            byKind = { [3256] = { n = 17, name = "Sunscale Scytheclaw" },
                [3254] = { n = 9, name = "Sunscale Lashtail" } } })
end)
