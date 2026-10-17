-- Instance visits' capture (INS-1): the client's signals read and handed to
-- Core/Instances.lua, which keeps the visit and decides when one carries on.
--
-- Inside an instance much of what the client says can come back secret: a
-- party member's GUID (the feasibility report's B1), a boss's name, a role.
-- Whatever reads secret is left out, never guessed. Members also come from
-- the group as last seen outside (Core/Roster.lua), whose GUIDs were plain,
-- so a dungeon that hides its party still knows who went in.
--
-- After Capture/Group.lua and Together.lua in the TOC: on a roster change
-- the roster and the together session are up to date before this file
-- reads them, and on the shared tick the session is too.

local addonName, ns = ...

local Instances = ns.Instances

local TICK_SECONDS = 30

local ROLES = { TANK = true, HEALER = true, DAMAGER = true }

-- The party or raid instance the user is in, as Instances.Enter takes it,
-- or nil. Battlegrounds and arenas are no visit.
local function Inside()
    local inside, kind = IsInInstance()
    if ns.Plain(inside) ~= true then return nil end
    kind = ns.Plain(kind)
    if kind ~= "party" and kind ~= "raid" then return nil end

    local name, _, _, difficulty, _, _, _, id = GetInstanceInfo()
    name, difficulty, id = ns.Plain(name), ns.Plain(difficulty), ns.Plain(id)
    return {
        instanceID = type(id) == "number" and id or nil,
        name = type(name) == "string" and name ~= "" and name or nil,
        instanceType = kind,
        difficulty = type(difficulty) == "string" and difficulty ~= "" and difficulty or nil,
    }
end

local function Role(unit)
    local role = UnitGroupRolesAssigned and ns.Plain(UnitGroupRolesAssigned(unit))
    return type(role) == "string" and ROLES[role] and role or nil
end

-- Names and class from the character's record, which every reading of
-- them went through (Characters.Observe scrubs it).
local function Add(guid, role)
    local first, surname = ns.Characters.Name(guid)
    local record = ns.Characters.Get(guid)
    Instances.Member({ guid = guid, first = first, surname = surname, class = record and record.class, role = role })
end

-- Who is in the group now, as far as it reads; and on entering, the group
-- as last seen outside too. Only then: inside, a member who leaves is not
-- told from one whose GUID went secret, so the roster can keep them.
local function Scan(entering)
    if not Instances.Current() then return end
    ns.Units.Each(ns.Units.Group(), function(unit)
        local guid = ns.PlayerGUIDFromUnit(unit)
        if guid then
            ns.Characters.ObserveUnit(unit)
            Add(guid, Role(unit))
        end
    end)
    if entering and IsInGroup and IsInGroup() then
        for guid in pairs(ns.Roster.Members()) do Add(guid) end
    end
    Instances.Seen(ns.Now())
end

-- Where the user is now, on every event that can move them and every tick.
-- `login`: just logged in, so a visit left behind ended when last seen
-- inside, not now.
local function Check(login)
    if not (ns.db and ns.ownGUID) then return end
    local now = ns.Now()
    local info = Inside()
    if info then
        local _, new = Instances.Enter(info, now)
        Scan(new)
    else
        Instances.Leave(not login and now or nil)
        Instances.Settle(now)
    end
end

ns._test.InstancesCheck = Check

ns.On("PLAYER_ENTERING_WORLD", function(_, isLogin) Check(isLogin) end)
ns.On("ZONE_CHANGED_NEW_AREA", function() Check(false) end)
ns.On("GROUP_ROSTER_UPDATE", function() Scan(false) end)

ns.On("PLAYER_LOGIN", function()
    ns.Every(TICK_SECONDS, function() Check(false) end)
end)

ns.On("PLAYER_LOGOUT", function()
    Instances.Seen(ns.Now())
end)

ns.On("ENCOUNTER_END", function(_, _, name, _, _, success)
    success = ns.Plain(success)
    if success == 1 then
        Instances.Boss(ns.Plain(name))
    elseif success == 0 then
        Instances.Wipe()
    end
end)

ns.On("PLAYER_DEAD", function()
    if not ns.DiedAgain() then Instances.Death() end
end)

-- A group member's GUID is plain here or not at all (SafeGUID drops a
-- secret one); the user's own death is PLAYER_DEAD's.
ns.On("UNIT_DIED", function(_, guid)
    guid = ns.SafeGUID(guid)
    if guid and guid ~= ns.ownGUID and Instances.IsMember(guid) then Instances.Death() end
end)
