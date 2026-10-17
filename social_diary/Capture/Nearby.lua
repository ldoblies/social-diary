-- "Seen nearby": REU-5's reunion toast, and "last seen at ... in ...".
--
-- The unit tokens that can name another player without sightings existing
-- yet: nameplates as they appear, plus target, focus and mouseover. Session 1
-- verified all of them give a plain GUID for open-world strangers, nameplates
-- even under combat lockdown. Group members are checked on a slow timer too,
-- since a friend grouped with you shows up on none of those reliably.
--
-- A token is not proof of proximity: mousing over a party frame or targeting
-- from it names someone who may be across the map. UnitIsVisible is the
-- client's own "close enough to be drawn" test, and gates everything here
-- (ns.PlayerGUIDFromUnit's `visible`).
--
-- Diary entries only. Each event costs a GUID read and a table lookup, which
-- matters: one starting zone produced ~60 players in minutes. M2's sighting
-- pipeline (Capture/Sightings.lua) now listens to the same events for
-- everyone, deduplicated, frame-budgeted and paused in cities, but runs
-- beside this file rather than through it until the toast is moved over.
-- Until then these handlers still fire in cities.

local addonName, ns = ...

local GROUP_SECONDS = 30

local Nearby = {}
ns.Nearby = Nearby

local VISIBLE = { visible = true }

local function DiaryGUID(unit)
    local guid = ns.PlayerGUIDFromUnit(unit, VISIBLE)
    if not guid or not ns.Diary.IsDiary(guid) then return nil end
    return guid
end

local function Check(unit)
    local guid = DiaryGUID(unit)
    if not guid then return end

    ns.Characters.Seen(guid)
    ns.Fire("SD_REUNION", guid, "nearby")
end

local function SeenIfDrawn(unit)
    local guid = DiaryGUID(unit)
    if guid then ns.Characters.Seen(guid) end
end

-- Group members in drawing range. No toast: REU-1 already covered the join.
function Nearby.ScanGroup()
    if not ns.ownGUID then return end
    ns.Units.Each(ns.Units.Group(), SeenIfDrawn)
end

ns.On("NAME_PLATE_UNIT_ADDED", function(_, unit)
    unit = ns.Plain(unit)
    if type(unit) == "string" then Check(unit) end
end)

ns.On("PLAYER_TARGET_CHANGED", function() Check("target") end)
ns.On("PLAYER_FOCUS_CHANGED", function() Check("focus") end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() Check("mouseover") end)

ns.On("PLAYER_LOGIN", function()
    ns.Every(GROUP_SECONDS, Nearby.ScanGroup)
end)
