-- The players the tests meet, as unit definitions for wowmock.SetUnit.
--
-- Loaded afresh for every test file: a few tests change a fixture in place
-- (a level-up, someone walking into range), and that must not leak into the
-- next file. Players a single test needs stay in that test, built with
-- Player{}.

local F = {}

local CLASSES = {
    DRUID = { "Druid", "DRUID", 11 },
    MAGE = { "Mage", "MAGE", 8 },
    ROGUE = { "Rogue", "ROGUE", 4 },
    SHAMAN = { "Shaman", "SHAMAN", 7 },
    WARRIOR = { "Warrior", "WARRIOR", 1 },
}

local RACES = {
    Human = { "Human", "Human", 1 },
    Tauren = { "Tauren", "Tauren", 6 },
}

-- Player{ guid = ..., "First", "Surname", class = "DRUID", race = "Tauren",
--         faction = "Horde", sex = 2, level = 1 }
--
-- Builds the tuples the mock's Unit* functions hand back. Anything not given
-- stays nil, as it does for a unit the client knows little about; the other
-- fields (visible, hostile, isPlayer, classification) pass straight through.
-- `fullName = true` answers UnitFullName with the same name, as the client
-- does for other players.
function F.Player(def)
    local unit = {}
    for key, value in pairs(def) do
        if type(key) == "string" then unit[key] = value end
    end

    unit.name = { def[1], def[2] }
    unit.fullName = def.fullName and { def[1], def[2] } or nil
    unit.class = def.class and CLASSES[def.class]
    unit.race = def.race and RACES[def.race]
    unit.faction = def.faction and { def.faction, def.faction }
    return unit
end

-- A copy of `base` with some fields changed: the same person at another
-- level, out of range, or behind a secret GUID.
function F.Like(base, changes)
    local unit = {}
    for key, value in pairs(base) do unit[key] = value end
    for key, value in pairs(changes) do unit[key] = value end
    return unit
end

-- The user's own character: UnitName joins, UnitFullName hands back the realm.
F.SELF = {
    guid = "Player-4707-0ABCDEF1",
    name = { "Ulverston Nye" },
    fullName = { "Ulverston Nye", "ClassicBetaPvE" },
    class = CLASSES.WARRIOR,
    race = RACES.Tauren,
    sex = 2, level = 70,
    faction = { "Horde", "Horde" },
}

-- The other player Session 1 actually observed. Most tests' "A".
F.STRANGER = F.Player{ guid = "Player-4620-00B0B0B0", "Bram", "Redfen", fullName = true,
    class = "DRUID", race = "Tauren", sex = 2, level = 1, faction = "Horde" }

-- "B": a second diary entry, on a different class.
F.GARRICK = F.Player{ guid = "Player-4620-00999999", "Garrick", "Fallow",
    class = "MAGE", race = "Tauren", sex = 2, level = 20, faction = "Horde" }

-- "C": a pick-up group member who never makes it into the diary.
F.PUG = F.Player{ guid = "Player-4620-00DDDDDD", "Norwood", "Sparks",
    class = "WARRIOR", race = "Tauren", sex = 2, level = 10, faction = "Horde" }

-- Sightings (SIG-2): somebody who could attack you.
F.HOSTILE = F.Player{ guid = "Player-4620-00AAAA02", "Romulus", "Lupa",
    class = "ROGUE", race = "Human", sex = 2, level = 5, faction = "Alliance", hostile = true }

-- Seen around (SES-9): a diary entry met by nameplate only.
F.FRIEND = F.Player{ guid = "Player-4620-00BBBB01", "Numa", "Pompilius",
    class = "SHAMAN", race = "Tauren", sex = 2, level = 12, faction = "Horde" }

-- The stranger tooltip (REU-6): a name and a level, nothing more.
F.STRANGER2 = F.Player{ guid = "Player-4620-00BBBB02", "Tullus", "Hostilius", level = 20 }

return F
