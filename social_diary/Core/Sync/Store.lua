-- Group sync's store: every author's stream of feed entries, the user's own
-- and the group's, in SocialDiaryDB.sync (ns.SyncData, Core/DB.lua).
--
--   authors[key] = { epoch, top, last, entries = { [seq] = entry } }
--
-- `key` is a character's GUID, or "curated" for the curated stories
-- (Core/Sync/Curated.lua), which travel as one more author. `seq` counts
-- up from 1 within an epoch; `top` is the highest held, `last` the highest
-- with everything below it held too, so a sync that stopped half way asks
-- again from there. An entry is flat (Core/Sync/Wire.lua): `r` its ref,
-- unique within the author ("deaths:1760000000", "note:1760000000"), `k`
-- its kind, `t` when, `z` where, the rest its kind's own. A later entry
-- with the same ref replaces the earlier one, whose seq is then left empty;
-- `del` true means the record is gone.
--
-- The epoch is when the author's stream began. A stream begun again (the
-- user's data deleted, Core/DB.lua's WipeData) has a newer one, and a
-- holder of the older drops its copy for it.

local addonName, ns = ...

ns.Sync = ns.Sync or {}

ns.Sync.CURATED = "curated"

-- A store over the table Data() returns. The addon's is ns.Sync.Store, over
-- the saved one; tests make more, one a simulated player.
function ns.Sync.NewStore(Data)
    local Store = { CURATED = ns.Sync.CURATED }

    -- [author] = { [ref] = seq }, built from the entries when first asked.
    local refsByAuthorAndRef = {}

    function Store.Author(key, create)
        local authors = Data().authors
        local a = authors[key]
        if not a and create then
            a = { epoch = ns.Now(), top = 0, last = 0, entries = {} }
            authors[key] = a
        end
        return a
    end

    local function Refs(key, a)
        local refs = refsByAuthorAndRef[key]
        if refs then return refs end
        refs = {}
        for seq, entry in pairs(a.entries) do
            local before = entry.r and refs[entry.r]
            if entry.r and (not before or before < seq) then refs[entry.r] = seq end
        end
        refsByAuthorAndRef[key] = refs
        return refs
    end

    -- The newest entry with `ref`, and its seq.
    function Store.ByRef(key, ref)
        local a = Store.Author(key)
        if not a then return nil end
        local seq = Refs(key, a)[ref]
        return seq and a.entries[seq], seq
    end

    local function Advance(a)
        while a.last < a.top and (a.entries[a.last + 1] or a.gaps and a.gaps[a.last + 1]) do
            a.last = a.last + 1
            if a.gaps then a.gaps[a.last] = nil end
        end
        if a.gaps and next(a.gaps) == nil then a.gaps = nil end
    end

    -- Puts `entry` at `seq` of `key`'s stream; nil `entry` is a seq known to be
    -- empty (replaced at its holder). An entry older than the newest with its
    -- ref is not kept.
    function Store.Put(key, seq, entry)
        local a = Store.Author(key, true)
        if seq <= a.last or a.entries[seq] then return false end
        if seq > a.top then a.top = seq end
        if entry then
            local refs = Refs(key, a)
            local before = entry.r and refs[entry.r]
            if before and before > seq then
                entry = nil
            elseif before then
                a.entries[before] = nil
                -- Still to be counted held, when the stream catches up to it.
                if before > a.last then
                    a.gaps = a.gaps or {}
                    a.gaps[before] = true
                end
            end
            if entry then
                a.entries[seq] = entry
                if entry.r then refs[entry.r] = seq end
            end
        end
        if not entry then
            a.gaps = a.gaps or {}
            a.gaps[seq] = true
        end
        Advance(a)
        return true
    end

    -- `entry` as the next of the user's own author `key`. Returns its seq.
    function Store.Append(key, entry)
        local a = Store.Author(key, true)
        local seq = a.top + 1
        Store.Put(key, seq, entry)
        return seq
    end

    -- Drops `key`'s stream for one begun at `epoch`.
    function Store.Restart(key, epoch)
        local authors = Data().authors
        authors[key] = { epoch = epoch, top = 0, last = 0, entries = {} }
        refsByAuthorAndRef[key] = nil
        return authors[key]
    end

    -- Every author: { [key] = { epoch, last } }.
    function Store.Vector()
        local vector = {}
        for key, a in pairs(Data().authors) do vector[key] = { epoch = a.epoch, last = a.last } end
        return vector
    end

    -- `key`'s entries from `from` up to `last`, each { seq, entry } (entry
    -- nil where the seq is empty), oldest first, at most `max`.
    function Store.From(key, from, max)
        local a = Store.Author(key)
        local list = {}
        if not a then return list end
        for seq = math.max(from, 1), a.last do
            list[#list + 1] = { seq = seq, entry = a.entries[seq] }
            if max and #list >= max then break end
        end
        return list
    end

    -- `key`'s live entries (the newest with each ref, none deleted), oldest
    -- first: { author, seq, entry }.
    function Store.Live(key)
        local a = Store.Author(key)
        local list = {}
        if not a then return list end
        for seq, entry in pairs(a.entries) do
            if not entry.del then list[#list + 1] = { author = key, seq = seq, entry = entry } end
        end
        table.sort(list, function(x, y) return x.seq < y.seq end)
        return list
    end

    -- The group's data, the user's own streams kept: "stop syncing and forget".
    function Store.ForgetOthers(own)
        local authors = Data().authors
        for key in pairs(authors) do
            if not own[key] then
                authors[key] = nil
                refsByAuthorAndRef[key] = nil
            end
        end
        Data().peers = {}
    end

    -- After the table was emptied under it.
    function Store.Reset()
        refsByAuthorAndRef = {}
    end

    return Store
end

ns.Sync.Store = ns.Sync.NewStore(function() return ns.SyncData() end)

-- PRV-3: nil is "delete everything" (Core/DB.lua's WipeData), which has
-- emptied the saved table already. Someone forgotten leaves the user's own
-- feed as the next derive finds their records changed (Core/Sync/Feed.lua);
-- what other players wrote is theirs.
ns.RegisterStore("sync", function(guid)
    if guid == nil then ns.Sync.Store.Reset() end
end)
