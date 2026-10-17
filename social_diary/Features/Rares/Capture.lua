-- Rare kills capture (Kind.lua): rares and world bosses killed during a
-- together session. PARTY_KILL gives plain attacker and victim GUIDs
-- (Session 1, even under combat lockdown), but no classification: that has
-- to come off a unit token still pointing at the corpse.
--
-- Was a part of Capture/Together.lua. PARTY_KILL is heard by World PvP's
-- capture, this file, Hunts' and the witnesses' (both after Capture/), and
-- the TOC lists this file right after World PvP's, so the order is the
-- old one. None reads what another writes anyway: World PvP takes only
-- players, this only creatures, and it writes only the session's rares.

local addonName, ns = ...

local RARE_KINDS = { rare = true, rareelite = true, worldboss = true }

-- The plates come last, after every token the user points at on purpose.
local VICTIM_UNITS = { "target", "focus", "mouseover" }
for i = 1, 5 do VICTIM_UNITS[#VICTIM_UNITS + 1] = "boss" .. i end

local function FindUnit(guid)
    local function On(unit)
        if UnitExists(unit) and ns.Plain(UnitGUID(unit)) == guid then return unit end
    end
    return ns.Units.Each(VICTIM_UNITS, On) or ns.Units.Each(ns.Units.Plates, On)
end

-- Kills count as together only for participants grouped right now
-- (Sessions.Rare).
local function Grouped(guid)
    return ns.Roster.Has(guid)
end

ns.On("PARTY_KILL", function(_, attacker, victim)
    if not ns.Sessions.Current() then return end

    attacker = ns.SafeGUID(attacker)
    if not attacker or not (attacker == ns.ownGUID or ns.Roster.Has(attacker)) then return end

    victim = ns.Plain(victim)
    if type(victim) ~= "string" or ns.SafeGUID(victim) then return end

    local unit = FindUnit(victim)
    local kind = unit and UnitClassification and ns.Plain(UnitClassification(unit))
    if not kind or not RARE_KINDS[kind] then return end

    local name = ns.Plain((UnitName(unit)))
    local n = ns.Sessions.Rare({ name = name, npcID = ns.NpcID(victim), kind = kind }, Grouped)
    if n > 0 then ns.Debug("%s %s counted for %d participant(s)", kind, tostring(name), n) end
end)
