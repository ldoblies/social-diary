-- Notes the user writes into the diary (DIA-11).
--
-- The entry's own `note` (DIA-6) is one standing line about who someone is.
-- These are the dated ones: "Helped me with the murloc camp", written on the
-- day, and placed on the timeline among everything else (TLN-10).
--
-- One table for everyone, not one list per GUID like the buffer: a note is
-- about one person by default, but a group event can be about several, and
-- it is still one note. `about` is a set of GUIDs. Nothing keeps an index
-- per person; notes are written by hand, so there are never so many that a
-- walk over all of them costs anything, and an index would be a second copy
-- of `about` to keep in step.
--
-- They are the user's writing, so nothing removes them on its own (DAT-3):
-- not the buffer's prune, and not "remove from the diary, keep the history"
-- (DIA-7), after which they come back with the person if they are added
-- again. Only deleting everything about someone takes them out.

local addonName, ns = ...

local Notes = {}
ns.Notes = Notes

--------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------

function Notes.Get(id)
    return ns.db.notes[id]
end

local function ByTime(a, b)
    if a.time ~= b.time then return a.time < b.time end
    return a.id < b.id
end

-- Everything written about `guid`, oldest first, like the other stores.
function Notes.For(guid)
    guid = ns.SafeGUID(guid)
    local list = {}
    if not guid then return list end

    for _, note in pairs(ns.db.notes) do
        if note.about[guid] then list[#list + 1] = note end
    end
    table.sort(list, ByTime)
    return list
end

-- Whom a note is about besides `guid`, sorted so the page names them in the
-- same order every time.
function Notes.Others(note, guid)
    local list = {}
    for other in pairs(note.about) do
        if other ~= guid then list[#list + 1] = other end
    end
    table.sort(list)
    return list
end

function Notes.Count()
    return ns.CountKeys(ns.db.notes)
end

-- Whom a note about `guid` at `time` could also be about: the other diary
-- entries in a together session with them that was going on then. The group
-- event the note is likely about, offered first when linking others; by
-- name.
function Notes.Companions(guid, time)
    guid = ns.SafeGUID(guid)
    local list, seen = {}, {}
    if not guid then return list end

    for _, session in ipairs(ns.Sessions.For(guid)) do
        if session.startedAt <= time and time <= (session.endedAt or ns.Now()) then
            for other in pairs(session.participants) do
                if other ~= guid and not seen[other] and ns.Diary.IsDiary(other) then
                    seen[other] = true
                    list[#list + 1] = other
                end
            end
        end
    end
    local function Name(g) return (ns.Characters.FullName(g) or g):lower() end
    table.sort(list, function(a, b) return Name(a) < Name(b) end)
    return list
end

-- Every other diary entry who was ever in a together session with `guid`,
-- the latest together first: who else is likely in a note about them.
function Notes.Together(guid)
    guid = ns.SafeGUID(guid)
    local list, last = {}, {}
    if not guid then return list end

    for _, session in ipairs(ns.Sessions.For(guid)) do
        for other in pairs(session.participants) do
            if other ~= guid and ns.Diary.IsDiary(other)
                and (not last[other] or session.startedAt > last[other]) then
                if not last[other] then list[#list + 1] = other end
                last[other] = session.startedAt
            end
        end
    end
    table.sort(list, function(a, b)
        if last[a] ~= last[b] then return last[a] > last[b] end
        return a < b
    end)
    return list
end

--------------------------------------------------------------------------
-- Writing
--------------------------------------------------------------------------

local function Clean(text)
    return ns.Diary.Clean(text, ns.Diary.MAX_NOTE_CHARS)
end

-- `guids` is one GUID or a list of them. Only diary entries can be written
-- about; anyone else is left out, and with nobody left there is no note.
-- `opts` may carry `time`, for a note about earlier than now, and `where`, a
-- location in the shape of ns.Where().
--
-- Returns the note, or nil when there was nothing to write or nobody to
-- write it about.
function Notes.Add(guids, text, opts)
    opts = opts or {}
    text = Clean(text)
    if not text then return nil end

    if type(guids) ~= "table" then guids = { guids } end
    local about, any = {}, false
    for i = 1, #guids do
        local guid = ns.SafeGUID(guids[i])
        if guid and ns.Diary.IsDiary(guid) then
            about[guid] = true
            any = true
        end
    end
    if not any then return nil end

    local meta = ns.db.meta
    local id = meta.nextNoteId
    meta.nextNoteId = id + 1

    local where = opts.where or ns.Where()
    local note = {
        id = id,
        time = opts.time or ns.Now(),
        text = text,
        about = about,
        me = ns.ownGUID,
        myLevel = ns.Plain(UnitLevel("player")),
        zone = where.zone,
        mapID = where.mapID,
        x = where.x,
        y = where.y,
        instanceID = where.instanceID,
    }

    ns.db.notes[id] = note
    ns.Touch()
    return note
end

-- New text for a note. Empty text deletes it, the way clearing a line in a
-- book takes it out.
function Notes.Edit(id, text)
    local note = Notes.Get(id)
    if not note then return false end

    text = Clean(text)
    if not text then return Notes.Delete(id) end
    if text == note.text then return true end

    note.text = text
    note.edited = ns.Now()
    ns.Touch()
    return true
end

function Notes.Delete(id)
    if not Notes.Get(id) then return false end
    ns.db.notes[id] = nil
    ns.Touch()
    return true
end

-- Another diary entry the note is also about (a group event).
function Notes.AddPerson(id, guid)
    local note = Notes.Get(id)
    guid = ns.SafeGUID(guid)
    if not note or not guid or not ns.Diary.IsDiary(guid) then return false end
    if note.about[guid] then return false end

    note.about[guid] = true
    ns.Touch()
    return true
end

-- Never the last one: a note about nobody would be gone from every page,
-- and deleting is Delete's, which says so.
function Notes.RemovePerson(id, guid)
    local note = Notes.Get(id)
    guid = ns.SafeGUID(guid)
    if not note or not guid or not note.about[guid] then return false end
    if ns.CountKeys(note.about) == 1 then return false end

    note.about[guid] = nil
    ns.Touch()
    return true
end

--------------------------------------------------------------------------
-- Forgetting (PRV-3)
--------------------------------------------------------------------------

-- Everyone (nil) empties the table. One person comes out of every note, and
-- a note about nobody else goes with them.
ns.RegisterStore("notes", function(guid)
    if guid == nil then
        wipe(ns.db.notes)
        return
    end
    for id, note in pairs(ns.db.notes) do
        note.about[guid] = nil
        if next(note.about) == nil then ns.db.notes[id] = nil end
    end
end)
