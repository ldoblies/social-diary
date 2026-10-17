-- Campfires: a minute sat by one, and who sat there too. The countdown
-- watched, and what it leaves written down.
--
-- WoW Forever's campfires give camp benefits after a minute spent sitting
-- near one. While the user sits, "Welcoming Campfire" counts that minute
-- down on them; when it runs out the benefits land, and if they are still
-- sitting a new minute starts a few seconds later (probe, 14 Oct). So:
--
--   a sitting   the countdown, from the moment it appears
--   completed   the countdown ran out rather than went early (they stood
--               up, walked off). Only these count.
--   one fire    a minute done within AGAIN of the last, and close to it,
--               is the same campfire: one record on the route, one row a
--               person, however many minutes they sat
--
-- On a completed minute: the route gets the campfire (Campfire.Added,
-- Kind.lua, while it is kept), and each other player who had their own
-- countdown running while the user's did gets a "campfire" row
-- (Interactions.Add; the row's kind is Kind.lua's). Others are read off
-- the nameplates and the group's tokens: their auras are open to addons
-- out of combat (probe, 14 Oct), and a sitting is out of combat by nature.
-- Once a SWEEP while the user sits, and as a plate comes into view.
-- Nameplates reach further than the fire's warmth, but a countdown
-- running means sitting at a fire, and two fires in one plate's reach are
-- rare.
--
-- The spell IDs are the client's, the same in every language.

local addonName, ns = ...

local Campfire = ns.Campfire

local COUNTDOWN = 1229739   -- "Welcoming Campfire": the minute, counting down
Campfire.COUNTDOWN = COUNTDOWN

local SWEEP = 5             -- seconds between looks at the others while sitting
local EARLY = 1             -- gone with more than this left: they stood up
local AGAIN = 10 * 60       -- a minute done this soon after the last...
local NEAR = 0.01           -- ...this close on the zone map is the same fire
Campfire.AGAIN = AGAIN

local sitting   -- { id, ends, sitters = { [guid] = level or true } } while the countdown runs
local fire      -- the last fire: { at, where, rec, rowed = { [guid] = true } }
local sweeper

local function AurasSecret()
    if not (C_Secrets and C_Secrets.ShouldAurasBeSecret) then return false end
    local ok, secret = pcall(C_Secrets.ShouldAurasBeSecret)
    return not ok or ns.IsSecret(secret) or secret == true
end

-- Whether `unit`'s countdown is running. Read by index: auras are open out
-- of combat, and the calls raise errors rather than lie while they are not
-- (12.1), hence the pcall.
local function Counting(unit)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return false end
    for i = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
        if not ok or aura == nil or ns.IsSecret(aura) then return false end
        if ns.Plain(aura.spellId) == COUNTDOWN then return true end
    end
    return false
end

local function Look(unit)
    if not sitting then return end
    local guid = ns.PlayerGUIDFromUnit(unit)
    if not guid or not ns.Plain(UnitIsPlayer(unit)) then return end
    if not Counting(unit) then return end
    local level = ns.Plain(UnitLevel(unit))
    sitting.sitters[guid] = type(level) == "number" and level > 0 and level or sitting.sitters[guid] or true
end

local function Sweep()
    if not sitting or AurasSecret() then return end
    ns.Units.Each(ns.Units.Group(), Look)
    ns.Units.Each(ns.Units.Plates, Look)
end
Campfire.Sweep = Sweep

local function StopSweeping()
    if sweeper then sweeper:Cancel() end
    sweeper = nil
end

local function Sat(id, ends)
    sitting = { id = id, ends = ends, sitters = {} }
    Sweep()
    if not sweeper then sweeper = ns.Every(SWEEP, Sweep) end
end

-- Whether `where` is the fire last sat by.
local function Same(where, now)
    if not fire or now - fire.at > AGAIN then return false end
    local a = fire.where
    if a.mapID ~= where.mapID then return false end
    if not (a.x and where.x) then return a.subZone == where.subZone end
    return math.abs(a.x - where.x) <= NEAR and math.abs(a.y - where.y) <= NEAR
end

-- A minute sat out: the fire on the route, a row for each who sat too.
local function Completed(sitters)
    local now, where = ns.Now(), ns.Where()
    if not where.mapID or where.instanceID then return end
    if not fire then
        -- After a /reload the last fire is the route's newest, so a sitting
        -- that spans one is still one campfire.
        local list = Campfire.List(ns.Journey.Mine())
        local rec = list[#list]
        if rec then
            fire = { at = rec.t, rec = rec, rowed = {},
                where = { mapID = rec.mapID, x = rec.x, y = rec.y, subZone = rec.subZone } }
            for guid, rows in pairs(ns.db.interactions) do
                for i = #rows, 1, -1 do
                    if rows[i].type == "campfire" and rows[i].time >= rec.t then fire.rowed[guid] = true break end
                end
            end
        end
    end
    if not Same(where, now) then
        fire = { where = where, rowed = {}, rec = Campfire.Added(now, where) }
        ns.Debug("campfire in %s", tostring(where.subZone or where.zone))
    end
    fire.at = now
    for guid, level in pairs(sitters) do
        if not fire.rowed[guid] then
            fire.rowed[guid] = true
            ns.Interactions.Add(guid, "campfire", { where = where,
                theirLevel = type(level) == "number" and level or nil,
                context = { subZone = where.subZone } })
        end
    end
end

-- The countdown on the user: begun, or gone. `info` is UNIT_AURA's.
local function Changed(info)
    if AurasSecret() or ns.IsSecret(info) then return end
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return end
    if not info or info.isFullUpdate then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, COUNTDOWN)
        aura = ok and not ns.IsSecret(aura) and aura or nil
        local id = aura and ns.Plain(aura.auraInstanceID)
        if id and not (sitting and sitting.id == id) then
            Sat(id, ns.Plain(aura.expirationTime))
        elseif not id and sitting then
            -- A full update can drop the countdown without saying how: it
            -- counts only if its time was up.
            local done = type(sitting.ends) == "number" and GetTime() >= sitting.ends - EARLY
            local sitters = sitting.sitters
            sitting = nil
            StopSweeping()
            if done then Completed(sitters) end
        end
        return
    end
    for _, aura in ipairs(info.addedAuras or {}) do
        if not ns.IsSecret(aura) and ns.Plain(aura.spellId) == COUNTDOWN then
            Sat(ns.Plain(aura.auraInstanceID), ns.Plain(aura.expirationTime))
        end
    end
    if not sitting then return end
    for _, id in ipairs(info.removedAuraInstanceIDs or {}) do
        if ns.Plain(id) == sitting.id then
            Sweep()
            local ends, sitters = sitting.ends, sitting.sitters
            sitting = nil
            StopSweeping()
            if type(ends) == "number" and GetTime() >= ends - EARLY then Completed(sitters) end
            return
        end
    end
end

-- The user's auras only: ns.On would hear every nameplate's too, and in a
-- crowd those come many a second.
local frame = CreateFrame("Frame")
frame:RegisterUnitEvent("UNIT_AURA", "player")
frame:SetScript("OnEvent", function(_, _, unit, info)
    if ns.Plain(unit) ~= "player" or not ns.ownGUID then return end
    Changed(info)
end)

ns.On("NAME_PLATE_UNIT_ADDED", function(_, unit)
    unit = ns.Plain(unit)
    if sitting and type(unit) == "string" and not AurasSecret() then Look(unit) end
end)

ns.On("PLAYER_ENTERING_WORLD", function() Changed(nil) end)

function ns._test.Campfire()
    return { sitting = sitting, fire = fire, sweeper = sweeper,
        reset = function() sitting, fire = nil, nil; StopSweeping() end }
end
