-- Reads the group's diaries out of the editor's SavedVariables (what the
-- addon's group sync holds, social_diary/Core/Sync/) and writes feed.json:
-- every writer's entries cut into the slots a story is written for, which
-- slots want a story, new or written again, and which days want a German
-- digest for the Gigu-Blitz.
--
--   luajit tools/curate/export.lua
--
-- A slot is what one story is about, by the id the addon reads it under
-- (social_diary/Core/Sync/Curated.lua):
--
--   <guid>:L<level>        a character's level, from reaching it to the next
--   <guid>:W<yyyy-mm-dd>   a week at the level cap, by its Monday
--
-- A slot wants a story once it is over (the next level reached, the week
-- gone) and its story, if any, was written from other entries than it
-- holds now (`basis`, a hash of them). The group's days (group:<yyyy-mm-dd>,
-- everyone's entries) are slots too, but only for the digest: a day over
-- with no <out>/digest/<date>.md yet wants one.

local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
package.path = here .. "/?.lua;" .. package.path
local json = require("json")
local config = dofile(here .. "/config.lua")

local DAY = 24 * 60 * 60
local CURATED = "curated"

local function Read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function Write(path, s)
    local f = assert(io.open(path, "wb"))
    f:write(s)
    f:close()
end

-- FNV-1a over a string, as the addon hashes (Core/Sync/Wire.lua).
local function Hash(s)
    local h = 2166136261
    for i = 1, #s do
        h = bit.bxor(h, s:byte(i))
        h = (bit.band(h, 0xffff) * 16777619 + bit.lshift(bit.band(bit.rshift(h, 16) * 403, 0xffff), 16)) % 4294967296
    end
    return ("%08x"):format(h % 4294967296)
end

-- An entry as one line, keys sorted, for the basis.
local function Line(e)
    local keys = {}
    for k in pairs(e) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. tostring(e[k]) end
    return table.concat(parts, "~")
end

local function Monday(t)
    local d = os.date("*t", t)
    local back = (d.wday + 5) % 7
    return os.time({ year = d.year, month = d.month, day = d.day - back, hour = 0 })
end

local function DayStart(t)
    local d = os.date("*t", t)
    return os.time({ year = d.year, month = d.month, day = d.day, hour = 0 })
end

--------------------------------------------------------------------------

local chunk = assert(loadfile(config.savedVariables), "cannot read " .. config.savedVariables)
local env = {}
setfenv(chunk, env)
chunk()
local sync = env.SocialDiaryDB and env.SocialDiaryDB.sync
assert(sync and sync.authors, "no group sync data in " .. config.savedVariables)

local now = os.time()
local maxLevel = config.maxLevel or 60

-- Every writer's live entries (the newest under each ref, none taken back).
local writers, stories = {}, {}
for key, a in pairs(sync.authors) do
    local byRef = {}
    for seq, e in pairs(a.entries or {}) do
        if e.r and (not byRef[e.r] or byRef[e.r].seq < seq) then byRef[e.r] = { seq = seq, e = e } end
    end
    local entries = {}
    for _, item in pairs(byRef) do
        if not item.e.del then entries[#entries + 1] = item.e end
    end
    table.sort(entries, function(x, y) return (x.t or 0) < (y.t or 0) end)
    if key == CURATED then
        for _, e in ipairs(entries) do stories[e.id] = { title = e.title, text = e.text } end
    else
        local card = {}
        for _, e in ipairs(entries) do
            if e.k == "me" then card = e end
        end
        writers[#writers + 1] = { key = key, name = card.name, class = card.class, race = card.race,
            level = card.level, entries = entries }
    end
end
table.sort(writers, function(x, y) return (x.name or x.key) < (y.name or y.key) end)

local slots, byId = {}, {}
local function Slot(id, fields)
    local slot = byId[id]
    if not slot then
        slot = fields
        slot.id, slot.entries = id, {}
        byId[id] = slot
        slots[#slots + 1] = slot
    end
    return slot
end

for _, w in ipairs(writers) do
    -- Levels reached, in order: a level's slot runs to the next.
    local levels = {}
    for _, e in ipairs(w.entries) do
        if e.k == "level" and e.t then levels[#levels + 1] = { level = e.level, t = e.t } end
    end
    table.sort(levels, function(x, y) return x.t < y.t end)
    local capAt
    for _, l in ipairs(levels) do
        if l.level >= maxLevel then capAt = l.t end
    end

    for _, e in ipairs(w.entries) do
        if e.t and e.k ~= "me" then
            local slot
            if capAt and e.t >= capAt then
                local monday = Monday(e.t)
                local week = os.date("%Y-%m-%d", monday)
                slot = Slot(("%s:W%s"):format(w.key, week), { kind = "week", writer = w.key, name = w.name,
                    week = week, from = monday, to = monday + 7 * DAY, closed = now >= monday + 7 * DAY })
            else
                -- The level being played when it happened: the last one
                -- reached at or before it, else the one before the first.
                local level, from, to = levels[1] and levels[1].level - 1 or nil, nil, levels[1] and levels[1].t
                for i, l in ipairs(levels) do
                    if l.t <= e.t then
                        level, from, to = l.level, l.t, levels[i + 1] and levels[i + 1].t
                    end
                end
                if level and level < maxLevel then
                    slot = Slot(("%s:L%d"):format(w.key, level), { kind = "level", writer = w.key, name = w.name,
                        level = level, from = from, to = to, closed = to ~= nil })
                end
            end
            if slot then slot.entries[#slot.entries + 1] = e end

            local day = DayStart(e.t)
            local date = os.date("%Y-%m-%d", day)
            local group = Slot("group:" .. date, { kind = "day", date = date, from = day, to = day + DAY,
                closed = now >= day + DAY })
            local copy = {}
            for k, v in pairs(e) do copy[k] = v end
            copy.writer = w.name or w.key
            group.entries[#group.entries + 1] = copy
        end
    end
end

-- What the editor wrote so far (stories.json), by id, with its basis.
local written = {}
local storiesPath = config.out .. "/stories.json"
local storiesFile = Read(storiesPath)
for _, story in ipairs(storiesFile and json.decode(storiesFile).stories or {}) do written[story.id] = story end

table.sort(slots, function(x, y) return (x.from or 0) < (y.from or 0) end)
local todo, digests = {}, {}
for _, slot in ipairs(slots) do
    table.sort(slot.entries, function(x, y) return (x.t or 0) < (y.t or 0) end)
    local lines = {}
    for i, e in ipairs(slot.entries) do lines[i] = Line(e) end
    slot.basis = Hash(table.concat(lines, "\n"))
    slot.t = slot.to and math.min(slot.to, now) or now
    local story = written[slot.id]
    slot.story = story and story.text or stories[slot.id] and stories[slot.id].text or nil
    if slot.kind == "day" then
        if slot.closed and not Read(config.out .. "/digest/" .. slot.date .. ".md") then
            digests[#digests + 1] = slot.date
        end
    elseif slot.closed and (not story or story.basis ~= slot.basis) then
        todo[#todo + 1] = slot.id
    end
end

-- The newest first, at most config.maxPerRun a run.
local limit = config.maxPerRun or 30
local wanted = {}
for i = #todo, math.max(1, #todo - limit + 1), -1 do wanted[#wanted + 1] = todo[i] end

Write(config.out .. "/feed.json", json.encode({
    generatedAt = os.date("%Y-%m-%d %H:%M", now),
    writers = (function()
        local list = {}
        for _, w in ipairs(writers) do
            list[#list + 1] = { key = w.key, name = w.name, class = w.class, race = w.race, level = w.level }
        end
        return list
    end)(),
    slots = slots,
    todo = wanted,
    waiting = #todo - #wanted,
    digests = digests,
}))

print(("%d writers, %d slots, %d stories to write now (%d more waiting), %d digests -> %s/feed.json")
    :format(#writers, #slots, #wanted, #todo - #wanted, #digests, config.out))
