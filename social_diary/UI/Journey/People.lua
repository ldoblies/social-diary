-- The people on a plate of Your Diary (JRN-22): one margin note each, by
-- their marks' height (People); who a note names (NoteGuid, Named, for the
-- caption not to name them again); a rival's ring (Rival); and how much a
-- person's note matters in the margin, by what they did there (Tier).
--
-- The module and its siblings: UI/Journey/Look.lua.

local addonName, ns = ...

local YourDiary = ns.UI.YourDiary

-- The people on a plate (JRN-22): one note per person, a stranger never
-- grouped with another, ordered by their marks' height so the leaders do
-- not cross. Each { guid, moments, marks (page points), top }.
local function People(plate)
    local groups, byGuid = {}, {}
    for _, m in ipairs(plate.people or {}) do
        local at = plate.where[m]
        local g = m.guid and byGuid[m.guid]
        if not g then
            g = { guid = m.guid, moments = {}, marks = {}, top = at[2] }
            groups[#groups + 1] = g
            if m.guid then byGuid[m.guid] = g end
        end
        g.moments[#g.moments + 1] = m
        local known = false
        for _, p in ipairs(g.marks) do
            if p[1] == at[1] and p[2] == at[2] then known = true end
        end
        if not known then g.marks[#g.marks + 1] = at end
        g.top = math.min(g.top, at[2])
    end
    table.sort(groups, function(a, b) return a.top < b.top end)
    return groups
end

-- Who a note names: its person, if the diary knows them, else no one
-- (a stranger, "someone").
local function NoteGuid(g)
    return g.guid and ns.db.characters[g.guid] ~= nil and g.guid or nil
end

-- Who the first `n` notes name, for the caption not to name them again
-- (Text.PlateCaption's `named`).
local function Named(groups, n)
    local named = { someone = 0 }
    for i = 1, math.min(n, #groups) do
        local guid = NoteGuid(groups[i])
        if guid then named[guid] = true else named.someone = named.someone + 1 end
    end
    return named
end

-- Whether `guid` is a rival: a diary entry tagged "foe".
local function Rival(guid)
    local entry = guid and ns.db.diary[guid]
    for _, tag in ipairs(entry and entry.tags or {}) do
        if tag == "foe" then return true end
    end
    return false
end

-- How much a person's note matters in the margin, by what they did there:
-- 1 for something done together (time in a group, a fight, a note), 2 for
-- a first sighting seen in hindsight, 3 for paths only crossed; a
-- feature's moment joined to theirs says its own (its `person.tier`, Core/
-- JourneyRecap.lua's RegisterMoment: something they gave you is 1). A
-- person is their best moment's tier. (11 Oct, in the client: two first
-- sightings took the column and the killer card was left off.)
local TIER = { session = 1, fight = 1, note = 1, added = 1, first = 2, crossed = 3 }

local function Tier(g)
    local best = 3
    for _, m in ipairs(g.moments) do
        best = math.min(best, TIER[m.kind] or (m.person and m.person.tier) or 2)
    end
    return best
end

YourDiary.People, YourDiary.NoteGuid, YourDiary.Named, YourDiary.Rival, YourDiary.Tier = People, NoteGuid, Named, Rival, Tier
