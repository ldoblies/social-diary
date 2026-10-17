-- Duels' capture: a challenge, its countdown and its result, read off what
-- the client says (the probes, 15 Oct; .claude/features/duels.md), and
-- kept through Kind.lua's Duels.Added.
--
-- What the client gives, in order:
--   - the challenge: DUEL_REQUESTED("First-Surname") when someone
--     challenges the user (first name and surname joined by a hyphen, as a
--     realm would be), or the user's own StartDuel(unit), hooked (the
--     unit menu calls it with "target"). Neither is a duel yet: it may be
--     declined, time out, or be refused ("Dueling isn't allowed here.").
--   - the countdown: three system lines, DUEL_COUNTDOWN ("Duel starting:
--     %d"), a second apart. The first is the duel's start: told as
--     SD_DUEL_STARTED, before the opponent turns attackable (UNIT_FACTION,
--     about two seconds after the last).
--   - the result: a system line, DUEL_WINNER_KNOCKOUT ("%1$s has defeated
--     %2$s in a duel") or DUEL_WINNER_RETREAT ("%2$s has fled from %1$s in
--     a duel"), with first names and surnames joined by a space. A
--     knockout's comes just after DUEL_FINISHED, a flight's just before,
--     in the same frame; a flight's can come long after combat ended. It
--     is kept, and told as SD_DUEL_FINISHED. A DUEL_FINISHED with no
--     result line a moment after is a duel with no winner (told with
--     outcome nil), or, before any countdown, a challenge called off
--     (nothing).
-- The lines are matched through the client's own global strings, so any
-- locale reads (LOC-1). A result line naming two others (a duel nearby the
-- user only watched) is not the user's: left (not in scope).
--
-- Who the opponent is: the challenge's unit, or the name matched against
-- the units that can name a player near the user (target, focus,
-- mouseover, the nameplates), whose identity is plain in the open world
-- through the whole duel (probe). Not found, the duel is still kept on the
-- route, with nobody.
--
-- Where this loads: the features' block, before Capture/. It listens to
-- DUEL_REQUESTED, DUEL_FINISHED and CHAT_MSG_SYSTEM, which nothing else in
-- the addon does, and hooks StartDuel, which nothing else hooks. The two
-- messages it fires are heard by core first (ns.Duelling, Core/Events.lua,
-- registered at core's load), then by the close-call judge, the route's
-- fighting and the sightings, each reading only ns.Duelling and its own
-- state, so their order among themselves does not matter.

local addonName, ns = ...

local Duels = ns.Duels

-- Seconds after DUEL_FINISHED a result line may still come: in the probes
-- it came in the same frame, before or after.
local WAIT = 1

--------------------------------------------------------------------------
-- The client's lines
--------------------------------------------------------------------------

-- A Lua pattern for one of the client's format strings ("%1$s has
-- defeated %2$s in a duel"), and which argument each capture is: for
-- "%2$s has fled from %1$s", { 2, 1 }.
local function Pattern(fmt)
    if type(fmt) ~= "string" or fmt == "" then return nil end
    local out, order = {}, {}
    local i = 1
    while i <= #fmt do
        local s, e, pos, conv = fmt:find("^%%(%d?)%$?([sd])", i)
        if fmt:sub(i, i + 1) == "%%" then
            out[#out + 1] = "%%"
            i = i + 2
        elseif s then
            order[#order + 1] = tonumber(pos) or (#order + 1)
            out[#out + 1] = conv == "d" and "(%d+)" or "(.+)"
            i = e + 1
        else
            local c = fmt:sub(i, i)
            out[#out + 1] = c:find("[%^%$%(%)%%%.%[%]%*%+%-%?]") and ("%" .. c) or c
            i = i + 1
        end
    end
    return "^" .. table.concat(out) .. "$", order
end

-- `text` read through `fmt`: its arguments in their own order, or nil.
local function Read(fmt, text)
    local pattern, order = Pattern(fmt)
    if not pattern or type(text) ~= "string" then return nil end
    local found = { text:match(pattern) }
    if #found == 0 then return nil end
    local args = {}
    for k, at in ipairs(order) do args[at] = found[k] end
    return args
end

--------------------------------------------------------------------------
-- Who
--------------------------------------------------------------------------

-- First name and surname from a challenge's "First-Surname" or a result
-- line's "First Surname" (ns.NormalizeName would take a hyphen's tail for
-- a realm).
local function Split(name)
    name = ns.Plain(name)
    if type(name) ~= "string" then return nil end
    local first, surname = name:match("^([^%-]+)%-(.+)$")
    if first then return ns.NormalizeName(first, surname) end
    return ns.NormalizeName(name)
end

local function Same(first, surname, f, s)
    return first and f and first:lower() == f:lower() and (surname or ""):lower() == (s or ""):lower()
end

local TOKENS = { "target", "focus", "mouseover" }

-- The player near the user called `name`: their GUID, observed as a unit
-- read is (Characters.ObserveUnit), or nil.
local function Find(name)
    local first, surname = Split(name)
    if not first then return nil end
    local found
    local function Try(unit)
        if found or not ns.Plain(UnitIsPlayer(unit)) then return end
        local f, s = ns.NameFromUnit(unit)
        if Same(first, surname, f, s) then
            found = ns.PlayerGUIDFromUnit(unit)
            if found then ns.Characters.ObserveUnit(unit) end
        end
    end
    for _, unit in ipairs(TOKENS) do Try(unit) end
    for _, unit in ipairs(ns.Units.Plates) do Try(unit) end
    return found
end

-- Whether `name` (a result line's) is the user.
local function IsMe(name)
    local f, s = Split(name)
    local first, surname = ns.NameFromUnit("player")
    return Same(first, surname, f, s)
end

--------------------------------------------------------------------------
-- A duel, from challenge to result
--------------------------------------------------------------------------

local pending   -- the challenge: { guid, name }
local duel      -- the duel under way: { guid, name, since, where }

local function Challenged(guid, name)
    pending = { guid = guid, name = name }
end

ns.On("DUEL_REQUESTED", function(_, name)
    name = ns.Plain(name)
    Challenged(Find(name), name)
end)

-- The user's own challenge (the unit menu, /duel): the unit, or a name.
if hooksecurefunc and type(StartDuel) == "function" then
    hooksecurefunc("StartDuel", function(unit)
        unit = ns.Plain(unit)
        if type(unit) ~= "string" then return end
        if ns.Plain(UnitExists(unit)) and ns.Plain(UnitIsPlayer(unit)) then
            local guid = ns.PlayerGUIDFromUnit(unit)
            if guid then ns.Characters.ObserveUnit(unit) end
            Challenged(guid, ns.JoinName(ns.NameFromUnit(unit)))
        else
            Challenged(Find(unit), unit)
        end
    end)
end

local function Started()
    duel = { guid = pending and pending.guid, name = pending and pending.name, since = ns.Now(), where = ns.Where() }
    pending = nil
    ns.Fire("SD_DUEL_STARTED", duel.guid)
end

-- A result line the user's duel ended with: kept, then told.
local function Ended(outcome, other)
    local d = duel or {}
    duel, pending = nil, nil
    -- The line names the opponent: the challenge's, unless it names
    -- someone else.
    local guid = d.guid
    local first, surname = Split(other)
    local was, wasSurname = Split(d.name)
    if not guid or (was and not Same(was, wasSurname, first, surname)) then guid = Find(other) end
    Duels.Added(guid, outcome, d.since, ns.Now(), d.where or ns.Where())
    ns.Fire("SD_DUEL_FINISHED", guid, outcome)
end

ns.On("CHAT_MSG_SYSTEM", function(_, text)
    text = ns.Plain(text)
    if type(text) ~= "string" then return end
    if not duel and Read(DUEL_COUNTDOWN, text) then return Started() end
    local won = Read(DUEL_WINNER_KNOCKOUT, text)
    if won then
        if IsMe(won[1]) then return Ended("won", won[2]) end
        if IsMe(won[2]) then return Ended("lost", won[1]) end
        return
    end
    local fled = Read(DUEL_WINNER_RETREAT, text)
    if fled then
        if IsMe(fled[2]) then return Ended("fled", fled[1]) end
        if IsMe(fled[1]) then return Ended("they_fled", fled[2]) end
    end
end)

-- The duel over with no result line: no winner. Before any countdown, the
-- challenge was called off, and there was no duel.
ns.On("DUEL_FINISHED", function()
    pending = nil
    local d = duel
    if not d then return end
    ns.After(WAIT, function()
        if duel ~= d then return end
        duel = nil
        ns.Fire("SD_DUEL_FINISHED", d.guid, nil)
    end)
end)

ns._test.Duels = {
    Pattern = Pattern,
    Read = Read,
    Find = Find,
    State = function() return pending, duel end,
}
