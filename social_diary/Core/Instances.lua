-- Instance visits (INS-1), as prd.md's data model has them.
--
-- db.instances[visitId] = { id, me, instanceID, name, instanceType ("party"
-- or "raid"), difficulty, startedAt, endedAt, members = { { guid, first,
-- surname, class, role } }, bossesKilled = { name, ... }, bossTotal, deaths,
-- wipes, sessionIds }.
--
-- `deaths` counts the whole group's, the user's included; `bossTotal` is
-- never captured (nothing in the client says it for every dungeon), so
-- readers do without it. Capture/Instances.lua reads the client and hands
-- it here; /sd testdata writes visits through New and the timeline (TLN-4)
-- reads them through For.
--
-- A visit begins on entering a party or raid instance and ends on leaving
-- it, unless the user comes back to the same instance within GRACE (a
-- corpse run, a summon, a relog): then it carries on. Which visit each
-- character is in is meta.openVisits[charGUID] = { id or pending, seen },
-- `seen` the last time they were known to be inside, so a visit left by a
-- crash ends then rather than never.
--
-- Nothing shows a visit without members, so one is only stored (given an
-- id) once someone besides the user is in it; until then it waits as
-- `pending`, holding no one's name.

local addonName, ns = ...

local Instances = {}
ns.Instances = Instances

local GRACE = 15 * 60
Instances.GRACE = GRACE

-- Stores a new visit under the next id and returns it. The caller's table is
-- kept, not copied: it is the record.
function Instances.New(visit)
    local meta = ns.db.meta
    local id = meta.nextVisitId or 1
    meta.nextVisitId = id + 1

    visit.id = id
    visit.me = visit.me or ns.ownGUID
    ns.db.instances[id] = visit
    return visit
end

-- Every visit, in no particular order.
function Instances.All()
    local list = {}
    for _, visit in pairs(ns.db.instances) do list[#list + 1] = visit end
    return list
end

-- The visits a character was a member of. Few enough to scan: a handful a
-- night, not a sighting stream.
function Instances.For(guid)
    guid = ns.SafeGUID(guid)
    local list = {}
    if not guid then return list end

    for _, visit in pairs(ns.db.instances) do
        for _, member in ipairs(visit.members or {}) do
            if member.guid == guid then
                list[#list + 1] = visit
                break
            end
        end
    end
    return list
end

-- One visit, by id. /sd testdata takes its made-up visits out this way.
function Instances.Remove(id)
    if ns.db.instances[id] == nil then return false end
    ns.db.instances[id] = nil
    return true
end

-- PRV-3: a visit's member list holds names, so a forgotten person leaves
-- it. The visit itself stays: it is the user's history, and the other
-- members'. nil forgets every visit.
function Instances.Forget(guid)
    if guid == nil then
        wipe(ns.db.instances)
        return
    end
    for _, visit in pairs(ns.db.instances) do
        local members = visit.members or {}
        for i = #members, 1, -1 do
            if members[i].guid == guid then table.remove(members, i) end
        end
    end
end
ns.RegisterStore("instances", Instances.Forget)

--------------------------------------------------------------------------
-- The visit under way
--------------------------------------------------------------------------

local function State()
    if not (ns.db and ns.ownGUID) then return nil end
    return ns.db.meta.openVisits[ns.ownGUID]
end

local function VisitOf(state)
    if not state then return nil end
    if state.id then return ns.db.instances[state.id] end
    return state.pending
end

-- The visit the user is inside now, stored or pending, or nil.
function Instances.Current()
    local visit = VisitOf(State())
    if visit and not visit.endedAt then return visit end
    return nil
end

-- In the party or raid instance `info` describes ({ instanceID, name,
-- instanceType, difficulty }) at `now`: the same visit carried on, or a new
-- one. Returns the visit and whether it is new.
function Instances.Enter(info, now)
    if not (ns.db and ns.ownGUID) then return nil end
    local state = State()
    local visit = VisitOf(state)
    if visit and visit.instanceID == info.instanceID and visit.name == info.name
        and now - (visit.endedAt or state.seen or now) <= GRACE then
        if visit.endedAt then
            visit.endedAt = nil
            ns.Touch()
        end
        state.seen = now
        return visit, false
    end

    if visit and not visit.endedAt then visit.endedAt = state.seen or now end
    visit = {
        instanceID = info.instanceID, name = info.name, instanceType = info.instanceType,
        difficulty = info.difficulty, startedAt = now, me = ns.ownGUID,
        members = {}, bossesKilled = {}, deaths = 0, wipes = 0, sessionIds = {},
    }
    ns.db.meta.openVisits[ns.ownGUID] = { pending = visit, seen = now }
    ns.Touch()
    return visit, true
end

-- Out of the instance: the visit ends `at`, or when last known inside,
-- and stays open for GRACE in case the user comes back.
function Instances.Leave(at)
    local state = State()
    local visit = VisitOf(state)
    if not visit or visit.endedAt then return false end
    visit.endedAt = at or state.seen
    ns.Touch()
    return true
end

-- Drops the open visit once it can no longer carry on: GRACE gone since it
-- ended, or the visit itself gone (forgotten, /sd testdata remove).
function Instances.Settle(now)
    local state = State()
    if not state then return end
    local visit = VisitOf(state)
    if not visit or (visit.endedAt and now - visit.endedAt > GRACE) then
        ns.db.meta.openVisits[ns.ownGUID] = nil
    end
end

-- Still inside at `now`; and the together session open now is part of the
-- visit (TLN-4 nests one in the other).
function Instances.Seen(now)
    local visit = Instances.Current()
    if not visit then return end
    State().seen = now
    local session = ns.Sessions.Current()
    if not session then return end
    for _, id in ipairs(visit.sessionIds) do
        if id == session.id then return end
    end
    visit.sessionIds[#visit.sessionIds + 1] = session.id
    ns.Touch()
end

-- Someone in the group: `member` is { guid, first, surname, class, role },
-- every field plain. Added once and kept even after they leave; a later
-- reading fills in what an earlier one could not.
function Instances.Member(member)
    local visit = Instances.Current()
    local guid = ns.SafeGUID(member.guid)
    if not visit or not guid or guid == ns.ownGUID then return false end

    local known
    for _, m in ipairs(visit.members) do
        if m.guid == guid then known = m break end
    end
    if known then
        for _, key in ipairs({ "first", "surname", "class", "role" }) do
            if member[key] ~= nil then known[key] = member[key] end
        end
    else
        visit.members[#visit.members + 1] = { guid = guid, first = member.first, surname = member.surname,
            class = member.class, role = member.role }
    end

    local state = State()
    if state.pending then
        Instances.New(visit)
        state.id, state.pending = visit.id, nil
    end
    ns.Touch()
    return not known
end

function Instances.IsMember(guid)
    local visit = Instances.Current()
    if not visit then return false end
    for _, m in ipairs(visit.members) do
        if m.guid == guid then return true end
    end
    return false
end

-- A boss killed, by name, once however often it falls.
function Instances.Boss(name)
    local visit = Instances.Current()
    if not visit or type(name) ~= "string" or name == "" then return false end
    for _, killed in ipairs(visit.bossesKilled) do
        if killed == name then return false end
    end
    visit.bossesKilled[#visit.bossesKilled + 1] = name
    ns.Touch()
    return true
end

function Instances.Wipe()
    local visit = Instances.Current()
    if not visit then return false end
    visit.wipes = (visit.wipes or 0) + 1
    ns.Touch()
    return true
end

function Instances.Death()
    local visit = Instances.Current()
    if not visit then return false end
    visit.deaths = (visit.deaths or 0) + 1
    ns.Touch()
    return true
end
