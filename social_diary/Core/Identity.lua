-- Identity: GUIDs and names (NAM-1).
--
-- No single API in this build returns a usable full name, and the ones that
-- come close disagree with each other (prd.md section 7):
--
--   call                  own character              a stranger
--   UnitName              "Ulverston Nye", nil       "Bram", "Redfen"
--   UnitFullName          "Ulverston Nye", <realm>   "Bram", "Redfen"
--   GetPlayerInfoByGUID   "Ulverston", ""            "Bram", <realm>
--   CHAT_MSG_SAY sender   -                          "Bram Redfen"
--
-- So the second return is sometimes the surname, sometimes the realm and
-- sometimes nothing, and the first is sometimes the whole name. Everything
-- that reads a name goes through NormalizeName, which reconciles all four
-- shapes into the same { first, surname } pair (D12).

local addonName, ns = ...

--------------------------------------------------------------------------
-- GUIDs
--------------------------------------------------------------------------

-- The gate every capture path goes through: returns a GUID that is safe to
-- compare and to use as a table key, or nil. A secret can do neither (NFR-4).
--
-- INS-3: only real players go in. Creatures, pets and vehicles have their own
-- GUID prefixes, and C_PartyInfo.IsDelveInProgress showed that an API being
-- present here says nothing about the content behind it -- so the check is
-- the GUID itself, not a content signal.
function ns.SafeGUID(guid)
    local plain = ns.Plain(guid)
    if type(plain) ~= "string" or plain:sub(1, 7) ~= "Player-" then return nil end
    return plain
end

-- A creature's NPC id: Creature-0-server-instance-zone-npcID-spawn. Nil for
-- anything else, players included.
function ns.NpcID(guid)
    guid = ns.Plain(guid)
    if type(guid) ~= "string" then return nil end
    return tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)"))
        or tonumber(guid:match("^Vehicle%-%d+%-%d+%-%d+%-%d+%-(%d+)"))
end

-- The one way a unit token becomes another player's GUID: the token is in
-- use, names a player whose GUID is plain, and is not the user. `opts`:
--
--   visible      the client must also be drawing them. A token is not proof
--                of proximity: target, focus and mouseover reach across the
--                map through a party frame, and UnitIsVisible is the
--                client's own "close enough to be drawn".
--   includeSelf  the user's own GUID counts too (the menus, which need to
--                recognise the user in order to offer nothing).
function ns.PlayerGUIDFromUnit(unit, opts)
    if not unit or not UnitExists(unit) then return nil end

    local guid = ns.SafeGUID(UnitGUID(unit))
    if not guid then return nil end
    if guid == ns.ownGUID and not (opts and opts.includeSelf) then return nil end

    if opts and opts.visible and UnitIsVisible and not ns.Plain(UnitIsVisible(unit)) then
        return nil
    end
    return guid
end

--------------------------------------------------------------------------
-- Unit tokens
--------------------------------------------------------------------------
--
-- The token lists capture walks, spelled once. Shared and read-only: a
-- caller that wants more tokens walks a second list rather than appending.

local Units = {}
ns.Units = Units

-- One per plate the client can show; a plate is drawn by definition.
Units.Plates = {}
for i = 1, 40 do Units.Plates[i] = "nameplate" .. i end

local RAID, PARTY = {}, {}
for i = 1, 40 do RAID[i] = "raid" .. i end
for i = 1, 4 do PARTY[i] = "party" .. i end

-- Every token a group member can be on. In a raid the raidN tokens include
-- the user; in a party they do not, so a caller still drops the user's GUID
-- (ns.PlayerGUIDFromUnit does).
function Units.Group()
    if IsInRaid and IsInRaid() then return RAID end
    return PARTY
end

-- Calls fn(unit) for each token in order. The first non-nil return stops
-- the walk and is returned, so a search reads as one call.
function Units.Each(list, fn)
    for i = 1, #list do
        local found = fn(list[i])
        if found ~= nil then return found end
    end
    return nil
end

--------------------------------------------------------------------------
-- Names
--------------------------------------------------------------------------

-- There are no realm names in this build, but GetPlayerInfoByGUID still
-- returns one in the slot where UnitName puts the surname, so a name that is
-- really the realm has to be recognised and dropped rather than stored as a
-- surname. Built once, after login, because GetRealmName needs the client up.
local realmNames

local function RealmNames()
    if realmNames then return realmNames end
    realmNames = {}

    local function Add(value)
        if type(value) ~= "string" or value == "" then return end
        local squashed = (value:gsub("%s+", "")):lower()
        realmNames[squashed] = true
    end

    Add(GetRealmName and GetRealmName())
    Add(GetNormalizedRealmName and GetNormalizedRealmName())

    return realmNames
end

-- Session 1 saw "ClassicBetaPvE2" for a stranger on realm "Classic Beta PvE",
-- so a trailing index is stripped before comparing.
function ns.IsRealmName(value)
    local plain = ns.Plain(value)
    if type(plain) ~= "string" or plain == "" then return false end

    local squashed = (plain:gsub("%s+", "")):lower()
    if RealmNames()[squashed] then return true end

    local stem = squashed:match("^(.-)%d+$")
    return stem ~= nil and RealmNames()[stem] == true
end

-- UnitName returns UNKNOWNOBJECT for a unit the client has not resolved yet.
-- Storing that would create a character called "Unknown" and merge strangers
-- into it, so it is treated as "no name read" instead.
local function IsPlaceholderName(name)
    return name == (UNKNOWNOBJECT or "Unknown") or name == (UNKNOWN or "Unknown")
end

-- Reconciles any of the four shapes above into first + surname, or nil.
--
-- The rule that covers every observed case: when there is no usable second
-- part and the first contains a space, the API joined the name -- split it.
-- That handles the user's own character and chat senders alike, and leaves an
-- already-split pair untouched.
function ns.NormalizeName(a, b)
    local first = ns.Plain(a)
    local surname = ns.Plain(b)

    if type(first) ~= "string" or first == "" or IsPlaceholderName(first) then
        return nil
    end

    -- A "Name-Realm" suffix cannot be part of a name: WoW names have no
    -- hyphens. Not seen in this build, but chat and cross-realm APIs produce
    -- it elsewhere and it is cheap to shed.
    local head = first:match("^([^%-]+)%-")
    if head then first = head end

    if type(surname) ~= "string" or surname == "" or ns.IsRealmName(surname) then
        surname = nil
    end

    if not surname then
        local part, rest = first:match("^(%S+)%s+(.+)$")
        if part then first, surname = part, rest end
    end

    return first, surname
end

-- D12: the parts are stored apart and joined here, at read time.
function ns.JoinName(first, surname)
    if not first then return nil end
    if surname and surname ~= "" then return first .. " " .. surname end
    return first
end

--------------------------------------------------------------------------
-- Readers
--------------------------------------------------------------------------

-- The preferred source: a unit token. UnitName splits for other players but
-- joins for the user's own character; NormalizeName absorbs both.
function ns.NameFromUnit(unit)
    if not unit or not UnitExists(unit) then return nil end

    local first, surname = ns.NormalizeName(UnitName(unit))
    if first then return first, surname end

    return ns.NormalizeName(UnitFullName(unit))
end

-- The fallback when there is no unit token -- a chat name, a stored GUID.
-- GetPlayerInfoByGUID yields the first name only, so this fills a blank
-- rather than overwriting what a unit read already knew.
function ns.InfoFromGUID(guid)
    guid = ns.SafeGUID(guid)
    if not guid or not GetPlayerInfoByGUID then return nil end

    local _, class, _, race, sex, name = GetPlayerInfoByGUID(guid)
    local first, surname = ns.NormalizeName(name)

    return {
        guid = guid,
        first = first,
        surname = surname,
        class = ns.Plain(class),
        race = ns.Plain(race),
        sex = ns.Plain(sex),
    }
end
