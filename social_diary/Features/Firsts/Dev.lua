-- Firsts found's part of /sd testdata (Dev/TestData.lua,
-- TestData.Register): the made-up route's five firsts, so Your Diary's
-- plates have their pouches and cards, and a giver's margin note. The
-- first bag, green, shoulders and epic as the route went, and the first
-- blue Tester's gift, in today's last trade. Development tooling: listed
-- in the TOC's do-not-package block, and left out by .pkgmeta.
--
-- The firsts as capture keeps them (Kind.lua, j.firsts: keyed by kind), at
-- "route", after the route: each at the stop it was found at, timed off
-- that stop's end as the script timed it when it wrote them, at the
-- stop's level, in the order the script wrote them (bag, green,
-- shoulders, epic, blue). The blue is the trade's (ns.Trade.GIFT,
-- Features/Trade/Dev.lua: the cloak, and how long ago): found as it was
-- received, from Tester. Nothing else reads j.firsts while the route is
-- written, so writing it after the route leaves the route as it was.

local addonName, ns = ...

local TestData = ns.TestData
local Link = TestData.Link
local DUROTAR, BARRENS = 1411, 1413

local POUCH = Link(1, 4496, "Small Brown Pouch")
local BRACERS = Link(2, 6070, "Wolfskin Bracers")
local SHOULDERS = Link(1, 1806, "Rawhide Shoulderpads")
local GUTWRENCHER = Link(4, 5616, "Gutwrencher")

TestData.Register("route", function(c)
    local j = c.j
    j.firsts = {}
    local function Find(kind, stop, at, map, x, y, link, from, giver)
        j.firsts[kind] = { t = at, mapID = map, x = x, y = y, level = stop.level, link = link, from = from,
            guid = giver }
    end

    -- Level 10, grinding by Razor Hill: a bag looted.
    local stop = c.Stop(10, "Razor Hill")
    Find("bag", stop, stop.to - 400, DUROTAR, 0.47, 0.54, POUCH, "loot")
    -- Level 11, the Sludge Fen: a quest's green.
    stop = c.Stop(11, "The Sludge Fen")
    Find("uncommon", stop, stop.to - 200, BARRENS, 0.61, 0.14, BRACERS, "quest")
    -- Level 13, back at the Crossroads after the Wailing Caverns: shoulders
    -- bought.
    stop = c.Stop(13, "The Crossroads")
    Find("shoulder", stop, stop.to - 250, BARRENS, 0.53, 0.31, SHOULDERS, "vendor")
    -- Level 15, the Raptor Grounds: an epic looted.
    stop = c.Stop(15, "Raptor Grounds")
    Find("epic", stop, stop.to - 700, BARRENS, 0.45, 0.80, GUTWRENCHER, "loot")
    -- At the cap, at the Crossroads in today's last session: Tester's gift,
    -- in the trade of that session.
    local gift = ns.Trade.GIFT
    stop = c.Stop(16, "The Crossroads")
    Find("rare", stop, c.now - gift.ago, BARRENS, 0.535, 0.31, gift.link, "trade", TestData.GUID)
end)
