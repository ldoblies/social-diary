-- Group sync's feed: the user's diary told as entries other players can
-- read (Core/Sync/Store.lua's streams), one stream a character of the user's.
--
-- Nothing writes the feed as it captures. Derive walks the stores now and
-- then, makes each record's entry, and appends the ones whose line
-- (Core/Sync/Wire.lua) is new or differs from the one fed before: a death
-- whose killer the recap names later is fed again, under the same ref, and
-- replaces the first. The hashes of what was fed are kept per character
-- (sync.derived[guid][ref]), so a login feeds only what moved.
--
-- Sources, each Feed.RegisterSource(name, { collect, deletes }):
--
--   collect  function(Emit): Emit(me, entry) for each record, `me` the
--            character of the user's whose record it is; entry's ref
--            begins with the source's name and ":"
--   deletes  a record no longer found is gone (the user's notes), and fed
--            as such; without it, one no longer found was only let go of
--            (a list's oldest past its cap) and the group keeps it
--
-- The features feed through the registries they already use, so this file
-- names none of them:
--
--   Journey.RegisterList(name, { feed = function(rec, key, j) → kind,
--            fields })   each record of the route's list (or keyed table)
--   Rows.Register(type, { feed = function(row, guid) → kind, fields })
--            each People row of that type; `who`, the person's name, is
--            filled in unless the fields say it
--
-- Chat is never fed: a row kind that carries chat (`chat`) is skipped
-- whatever its spec says, and no entry has an excerpt.

local addonName, ns = ...

ns.Sync = ns.Sync or {}
local Feed = {}
ns.Sync.Feed = Feed

local Wire, Store = ns.Sync.Wire, ns.Sync.Store

local SOURCES, DELETES = {}, {}

function Feed.RegisterSource(name, spec)
    SOURCES[#SOURCES + 1] = { name = name, collect = spec.collect }
    DELETES[name] = spec.deletes or nil
end

-- Whether the user has a group to feed: a code entered (Core/DB.lua).
function Feed.On()
    local code = ns.db and ns.Setting("groupCode")
    return type(code) == "string" and code:match("%S") ~= nil
end

-- Where a record happened, as words: its own zone, else its map's name.
function Feed.Zone(rec)
    local zone = rec.zone
    if type(zone) ~= "string" or zone == "" then zone = rec.mapID and ns.MapName(rec.mapID) or nil end
    return zone
end

-- An entry: `fields` (a table of flat values, or nil) with ref, kind, time
-- and place laid over it.
function Feed.Entry(ref, kind, t, rec, fields)
    local entry = {}
    for key, value in pairs(fields or {}) do entry[key] = value end
    entry.r, entry.k, entry.t = ref, kind, t
    if entry.z == nil and rec then entry.z = Feed.Zone(rec) end
    return entry
end

-- A person's name for an entry: the diary's, first and surname.
function Feed.Name(guid)
    return guid and ns.Characters.FullName(guid) or nil
end

-- Names joined for an entry's field, nil for none.
function Feed.Names(guids)
    local names = {}
    for _, guid in ipairs(guids) do names[#names + 1] = Feed.Name(guid) end
    table.sort(names)
    return #names > 0 and table.concat(names, ", ") or nil
end

-- An item link's name ("[Linen Cloth]" → "Linen Cloth"), or the text.
function Feed.ItemName(link)
    if type(link) ~= "string" then return nil end
    return link:match("%[(.-)%]") or link
end

-- A list of { link, count } as words: "10x Linen Cloth, Copper Bar".
function Feed.Items(list)
    if type(list) ~= "table" or #list == 0 then return nil end
    local parts = {}
    for _, item in ipairs(list) do
        parts[#parts + 1] = ((item.count or 1) > 1 and (item.count .. "x ") or "") .. (Feed.ItemName(item.link) or "?")
    end
    return table.concat(parts, ", ")
end

--------------------------------------------------------------------------
-- Deriving
--------------------------------------------------------------------------

-- The user's characters whose records this diary holds all of: their
-- records not found are gone. The logged-in one, or every one where the
-- diary is shared (Core/DB.lua's DAT-1).
local function Covered()
    if ns.diaryShared then return ns.OwnCharacters() end
    return ns.ownGUID and { [ns.ownGUID] = true } or {}
end

-- Feeds what moved. Returns how many entries were appended.
function Feed.Derive()
    if not Feed.On() then return 0 end
    local derived = ns.SyncData().derived
    local own = ns.OwnCharacters()
    local seen, added = {}, 0

    local function Emit(me, entry)
        if type(me) ~= "string" or not own[me] or not entry or not entry.r then return end
        local refs = seen[me] or {}
        seen[me] = refs
        if refs[entry.r] then return end
        refs[entry.r] = true
        local hashes = derived[me] or {}
        derived[me] = hashes
        local hash = Wire.Hash(Wire.Encode(entry))
        if hashes[entry.r] == hash then return end
        hashes[entry.r] = hash
        Store.Append(me, entry)
        added = added + 1
    end

    for _, source in ipairs(SOURCES) do source.collect(Emit) end

    for me in pairs(Covered()) do
        local hashes = derived[me] or {}
        local found = seen[me] or {}
        for ref in pairs(hashes) do
            local source = ref:match("^([^:]+):")
            if source and DELETES[source] and not found[ref] then
                hashes[ref] = nil
                Store.Append(me, { r = ref, del = true })
                added = added + 1
            end
        end
    end

    if added > 0 then ns.Fire("SD_FEED_GREW", added) end
    return added
end

--------------------------------------------------------------------------
-- The core's sources
--------------------------------------------------------------------------

-- Each character's route: its levels, and every list a feature registered
-- with a `feed`. A list's records are told apart by time, a keyed table's
-- by key.
Feed.RegisterSource("route", { collect = function(Emit)
    for me, j in pairs(ns.db.journey) do
        if type(j) == "table" and not j.test then
            for name, spec in pairs(ns.Journey.LISTS) do
                if spec.feed and type(j[name]) == "table" then
                    local taken = {}
                    for key, rec in pairs(j[name]) do
                        if type(rec) == "table" then
                            local kind, fields = spec.feed(rec, key, j)
                            if kind then
                                local id = type(key) == "string" and key or tostring(rec.t)
                                local ref = "route:" .. name .. ":" .. id
                                local n = (taken[ref] or 0) + 1
                                taken[ref] = n
                                if n > 1 then ref = ref .. "#" .. n end
                                Emit(me, Feed.Entry(ref, kind, rec.t, rec, fields))
                            end
                        end
                    end
                end
            end
        end
    end
end })

Feed.RegisterSource("level", { collect = function(Emit)
    for me, j in pairs(ns.db.journey) do
        if type(j) == "table" and not j.test and type(j.levels) == "table" then
            for level, at in pairs(j.levels) do
                if type(level) == "number" and type(at) == "table" and at.at then
                    local z = at.subZone ~= "" and at.subZone or nil
                    local zone = at.mapID and ns.MapName(at.mapID)
                    Emit(me, Feed.Entry("level:" .. level, "level", at.at, nil,
                        { level = level, z = zone or z, sub = zone and z ~= zone and z or nil }))
                end
            end
        end
    end
end })

-- People rows whose kind feeds. One walk over every row, not one a kind.
Feed.RegisterSource("row", { collect = function(Emit)
    for guid, rows in pairs(ns.db.interactions) do
        if type(rows) == "table" then
            for _, row in ipairs(rows) do
                local spec = type(row) == "table" and ns.Rows.Get(row.type)
                if spec and spec.feed and not spec.chat and row.time then
                    local kind, fields = spec.feed(row, guid)
                    if kind then
                        fields = fields or {}
                        if fields.who == nil then fields.who = Feed.Name(guid) end
                        fields.lv = fields.lv or row.myLevel
                        local ref = ("row:%s:%d:%s"):format(row.type, row.time, Wire.HashHex(guid))
                        Emit(row.me, Feed.Entry(ref, kind, row.time, row, fields))
                    end
                end
            end
        end
    end
end })

-- Together sessions once closed: who, how long, where.
Feed.RegisterSource("session", { collect = function(Emit)
    for _, session in pairs(ns.db.sessions) do
        if type(session) == "table" and session.endedAt and not session.test and session.startedAt then
            local guids, deaths, rares, rare = {}, 0, {}, {}
            for guid, p in pairs(session.participants or {}) do
                guids[#guids + 1] = guid
                for _, r in ipairs(type(p) == "table" and p.rares or {}) do
                    if r.name and not rare[r.name] then
                        rare[r.name] = true
                        rares[#rares + 1] = r.name
                    end
                end
            end
            table.sort(rares)
            for _, n in pairs(session.deaths or {}) do deaths = deaths + (tonumber(n) or 0) end
            local zones = type(session.zones) == "table" and #session.zones > 0
                and table.concat(session.zones, ", ") or nil
            Emit(session.me, Feed.Entry("session:" .. session.startedAt, "together", session.startedAt, nil, {
                who = Feed.Names(guids), z = zones,
                dur = session.endedAt - session.startedAt,
                deaths = deaths > 0 and deaths or nil,
                rares = #rares > 0 and table.concat(rares, ", ") or nil,
            }))
        end
    end
end })

-- Dungeon visits once over: the instance, the group, bosses, wipes.
Feed.RegisterSource("visit", { collect = function(Emit)
    for _, visit in pairs(ns.db.instances) do
        if type(visit) == "table" and visit.endedAt and visit.startedAt and not visit.test then
            local names = {}
            for _, member in ipairs(visit.members or {}) do
                if member.guid ~= visit.me then
                    names[#names + 1] = ns.JoinName(member.first, member.surname) or Feed.Name(member.guid)
                end
            end
            table.sort(names)
            local bosses = type(visit.bossesKilled) == "table" and #visit.bossesKilled > 0
                and table.concat(visit.bossesKilled, ", ") or nil
            Emit(visit.me, Feed.Entry("visit:" .. visit.startedAt, "dungeon", visit.startedAt, nil, {
                z = visit.name, raid = visit.instanceType == "raid" or nil,
                who = #names > 0 and table.concat(names, ", ") or nil, bosses = bosses,
                deaths = (visit.deaths or 0) > 0 and visit.deaths or nil,
                wipes = (visit.wipes or 0) > 0 and visit.wipes or nil,
                dur = visit.endedAt - visit.startedAt,
            }))
        end
    end
end })

-- What the user wrote, while they share it: deleted, or kept back again,
-- it is gone from the group too.
Feed.RegisterSource("note", { deletes = true, collect = function(Emit)
    if ns.Setting("shareNotes") ~= true then return end
    for _, note in pairs(ns.db.notes) do
        if type(note) == "table" and note.time and note.text and not note.test then
            local guids = {}
            for guid in pairs(note.about or {}) do guids[#guids + 1] = guid end
            Emit(note.me, Feed.Entry("note:" .. note.time, "note", note.time, note, {
                text = note.text, who = Feed.Names(guids), lv = note.myLevel,
            }))
        end
    end
end })

-- The author's card: who is writing, as the group sees them. Only the
-- logged-in character's, whose class and race the client can say.
Feed.RegisterSource("me", { collect = function(Emit)
    local guid = ns.ownGUID
    local own = guid and ns.OwnCharacters()[guid]
    if not own then return end
    local begun = ns.db.meta.begun[guid]
    local _, class = UnitClass("player")
    local _, race = UnitRace("player")
    Emit(guid, Feed.Entry("me:card", "me", type(begun) == "table" and begun.time or nil, nil, {
        name = ns.JoinName(own.first, own.surname), level = own.level,
        class = ns.Plain(class), race = ns.Plain(race),
    }))
end })

--------------------------------------------------------------------------
-- When
--------------------------------------------------------------------------

-- At login, once a minute when anything moved and five have passed since
-- the last, and at logout, so the file the client writes holds it all.
local EVERY, QUIET = 60, 300
local lastAt, lastKey = 0, nil

local function Key()
    return ("%d:%d"):format(ns.dataVersion, ns.Journey.version or 0)
end

function Feed.Tick(now)
    now = now or ns.Now()
    if now - lastAt < QUIET or Key() == lastKey then return end
    lastAt = now
    Feed.Derive()
    lastKey = Key()
end

local function Now()
    lastAt = ns.Now()
    Feed.Derive()
    lastKey = Key()
end

ns.On("PLAYER_LOGIN", function()
    if not ns.db then return end
    Now()
    ns.Every(EVERY, Feed.Tick)
end)

ns.On("PLAYER_LOGOUT", function()
    if ns.db then Now() end
end)
