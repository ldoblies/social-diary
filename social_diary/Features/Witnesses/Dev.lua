-- Witnesses' part of /sd testdata (Dev/TestData.lua, TestData.Register):
-- strangers who were there when the made-up route's character died or
-- nearly did, for the plates' witness card (Card.lua). Development
-- tooling: listed in the TOC's do-not-package block, and left out by
-- .pkgmeta.
--
-- Made up, realm 0000, never in the diary: pencilled in as capture would
-- leave them (a record, then a row each, Kind.lua's kinds), at "route",
-- after the route and after Deaths' part (Features/Deaths/Dev.lua, its
-- deaths at the same moments), as the script wrote them after the route
-- before the move. Each row is timed off the stop that counts its death or
-- close call, as the script timed it. One a plate, so each of the card's
-- cases and sizes is on a page of its own (the proposal's checklist).
--
-- They are strangers, not the route and not Tester, so /sd testdata
-- remove does not take them with those: they are forgotten at "remove"
-- (and again before they are written, as a second /sd testdata replaces
-- the first).

local addonName, ns = ...

local TestData = ns.TestData
local Witnesses = ns.Witnesses

-- Who they are (Characters.Observe's fields), by a name for the script
-- below; Witnesses.STRANGERS, for the tests.
local STRANGERS = {
    wenna = { guid = "Player-0000-7E57E580", first = "Wenna", class = "PALADIN", race = "BloodElf", level = 11, sex = 3 },
    numa = { guid = "Player-0000-7E57E581", first = "Numa", class = "DRUID", race = "Tauren", level = 14, sex = 3 },
    grisha = { guid = "Player-0000-7E57E582", first = "Grisha", class = "ROGUE", race = "Orc", level = 17, sex = 3 },
    brakk = { guid = "Player-0000-7E57E586", first = "Brakk", class = "WARRIOR", race = "Orc", level = 15, sex = 2 },
    corvin = { guid = "Player-0000-7E57E584", first = "Corvin", class = "WARLOCK", race = "Scourge", level = 18,
        sex = 2 },
    ilsabet = { guid = "Player-0000-7E57E585", first = "Ilsabet", class = "MAGE", race = "BloodElf", level = 20,
        sex = 3 },
    sefa = { guid = "Player-0000-7E57E587", first = "Sefa", class = "PRIEST", race = "Troll", level = 13, sex = 3 },
}
Witnesses.STRANGERS = STRANGERS

local function Forget()
    for _, who in pairs(STRANGERS) do ns.Characters.Forget(who.guid) end
end

local DUROTAR, BARRENS, STONETALON = 1411, 1413, 1442

TestData.Register("route", function(c)
    local witnessed = {}
    local function Witness(who, kind, at, zone, map, context)
        witnessed[#witnessed + 1] = { who = who, kind = kind, at = at, zone = zone, map = map, context = context }
    end
    local W = STRANGERS

    -- Level 10: killed by a raptor by Razor Hill; Wenna waded in and could
    -- not save you (the witness card, helped, in the row under the plate).
    Witness(W.wenna, Witnesses.HELPED, c.Stop(10, "Razor Hill").to - 700, "Durotar", DUROTAR,
        { npcID = 3123, name = "Bloodtalon Scythemaw" })
    -- Level 11: Numa pulled you out of a close call at the Forgotten Pools:
    -- a rescue's card (the close call had none), with no creature to name,
    -- in the 176 px column.
    Witness(W.numa, Witnesses.SAVED, c.Stop(11, "The Forgotten Pools").to - 1500, "The Barrens", BARRENS,
        { pct = 9 })
    -- Level 13: a centaur raid on the Crossroads, and Corvin watched you
    -- die for three seconds (the watched card in the 176 px column, L).
    Witness(W.corvin, Witnesses.WATCHED, c.Stop(13, "The Crossroads").to - 450, "The Barrens", BARRENS,
        { watched = 3.2, name = "Kolkar Pack Runner", npcID = 3274, subZone = "The Crossroads" })
    -- Level 14: the second death at Camp Taurajo, three strangers only saw,
    -- a glance each (the glance's card, "Ilsabet & two others" and its few
    -- drops of blood, M).
    local taurajo = c.Stop(14, "Camp Taurajo").to
    Witness(W.ilsabet, Witnesses.WATCHED, taurajo - 500, "The Barrens", BARRENS,
        { watched = 1.3, name = "Razormane Hunter", npcID = 3265, subZone = "Camp Taurajo" })
    Witness(W.wenna, Witnesses.WATCHED, taurajo - 500, "The Barrens", BARRENS,
        { watched = 0.9, name = "Razormane Hunter", npcID = 3265, subZone = "Camp Taurajo" })
    Witness(W.sefa, Witnesses.WATCHED, taurajo - 499, "The Barrens", BARRENS,
        { watched = 0.6, name = "Razormane Hunter", npcID = 3265, subZone = "Camp Taurajo" })
    -- At the cap, the first evening at Lushwater Oasis: Grisha stood and
    -- watched you die for six seconds (the merciless card, before Humar's
    -- close call: XL where the plate has a page of its own, smaller where a
    -- week's page shares it out).
    Witness(W.grisha, Witnesses.WATCHED, c.Stop(16, "Lushwater Oasis").to - 400, "The Barrens", BARRENS,
        { watched = 6.4, name = "Oasis Snapjaw", npcID = 3461, subZone = "Lushwater Oasis" })
    -- At the cap, a death on the crag; Brakk tried to save you (the helped
    -- card in a three-plate page's wide column, XL, over Kazzak's close
    -- call).
    Witness(W.brakk, Witnesses.HELPED, c.Stop(16, "Windshear Crag").to - 1500, "Stonetalon Mountains", STONETALON,
        { name = "Bloodfury Harpy", npcID = 4022 })

    -- Pencilled in as strangers, a row each.
    Forget()
    for _, w in ipairs(witnessed) do
        local who = w.who
        ns.Characters.Observe(who.guid, { first = who.first, class = who.class, race = who.race, level = who.level,
            sex = who.sex, faction = "Horde", time = w.at })
        ns.Interactions.Add(who.guid, w.kind, { time = w.at, where = { zone = w.zone, mapID = w.map },
            context = w.context })
    end
end)

TestData.Register("remove", Forget)
