-- Instance visits (INS-1), as prd.md's data model has them.
--
-- db.instances[visitId] = { id, me, instanceID, name, instanceType ("party"
-- or "raid"), difficulty, startedAt, endedAt, members = { { guid, first,
-- surname, class, role } }, bossesKilled = { name, ... }, bossTotal, deaths,
-- wipes, sessionIds }.
--
-- INS-1's capture does not exist yet; /sd testdata writes visits through New
-- and the timeline (TLN-4) reads them through For. This file owns the ids, so
-- capture can land here without anything else learning where visits live.

local addonName, ns = ...

local Instances = {}
ns.Instances = Instances

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
