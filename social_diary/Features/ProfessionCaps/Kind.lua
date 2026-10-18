-- Profession caps (JRN-29): a profession's skill reaching the most its
-- training allows, and where. A feature in a folder of its own:
--
--   Kind.lua     what a cap is to the diary: the route's list and the
--                recap's moment
--   Text.lua     its words: the level's prose, the plates' captions, the
--                mark's tooltip
--   Mark.lua     its mark on the plates (a flight of stairs)
--   Capture.lua  the professions read off the client as their skill
--                changes, and a cap reached written down
--   Dev.lua      its part of /sd testdata (never packaged)
--
-- Everything is registered into the core's and the UI's registries, so no
-- file outside this folder names a profession's cap. Its own names are on
-- ns.ProfessionCaps, made here, the first of its files the TOC loads. The
-- moment's kind is "skill" and the route's list "skillCaps" ("skill", not
-- "cap": the recap's capAt is the level cap).
--
-- This file: the route's list of caps reached, and the moment that puts
-- them on the plates.

local addonName, ns = ...

local ProfessionCaps = {}
ns.ProfessionCaps = ProfessionCaps

--------------------------------------------------------------------------
-- The route's list: as far as the training goes
--------------------------------------------------------------------------
--
-- A profession's skill climbs to the most its training allows (75, 150,
-- 225, 300 on Forever: probe 12 Oct) and stops there until the next
-- trainer. Reaching it is the moment kept; training, and learning the
-- profession, are not (the user's choice, 12 Oct).
--
-- j.skillCaps holds each, oldest first: { t, mapID, x, y, level, skillLine,
-- name, rank }. `skillLine` is the client's id for the profession (the
-- same in every language), `name` how the client called it then, `rank`
-- the cap reached. The newest 100 are kept a character.

local Journey = ns.Journey
Journey.RegisterList("skillCaps", { cap = 100,
    feed = function(rec) return "skill", { lv = rec.level, skill = rec.name, rank = rec.rank } end })

-- Whether a profession went from below its cap to it between two
-- readings, each { rank, max }. Only a rank that climbed under a max that
-- stayed put: a max that moved is training, or a reading not loaded yet.
function ProfessionCaps.IsCap(before, now)
    if not (before and now) then return false end
    return type(now.max) == "number" and now.max > 0 and now.max == before.max
        and type(now.rank) == "number" and type(before.rank) == "number"
        and before.rank < now.rank and now.rank >= now.max
end

-- A cap reached on route `j`, here and now unless `where` says otherwise
-- (in ns.Where's shape; nowhere inside an instance, where the recap places
-- it by time). `rec` is { t, level, skillLine, name, rank }.
function ProfessionCaps.Add(j, rec, where)
    if not (j and rec and rec.skillLine and rec.rank) then return nil end
    return Journey.Append(j, "skillCaps", { t = rec.t, level = rec.level, skillLine = rec.skillLine,
        name = rec.name, rank = rec.rank }, where)
end

-- A character's profession caps, oldest first.
function ProfessionCaps.List(j)
    return Journey.List(j, "skillCaps")
end

--------------------------------------------------------------------------
-- The recap's moment
--------------------------------------------------------------------------

-- A profession at its cap, where the last skill-up came; one reached in a
-- dungeon has no spot of its own, and is placed by the route at its time.
--
-- Rank 2, with a first found and a chain's finale (Core/JourneyRecap.lua's
-- RANK, Decision 10): after the people you were with (1), before a death,
-- a close call and luck (3), and well before the level's pin (8), as a
-- level is reached anyway. Light: its words are all it has, with no card in the
-- margin (the user's choice, 13 Oct), so a plate of caps and places alone
-- is given a print, not a full slot. Its order (60) puts it after the
-- chains' ends among the features' moments.
ns.JourneyRecap.RegisterMoment("skill", { order = 60, list = "skillCaps", field = "cap", rank = 2, light = true })
