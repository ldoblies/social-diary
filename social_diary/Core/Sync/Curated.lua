-- Curated stories: the diary's records written up as stories outside the
-- game, by the group's editor (tools/curate/), and read in place of the
-- diary's own words where there is one and the reader wants them
-- (showCurated).
--
-- They come in as a small addon of their own, SocialDiary_Curated, which
-- the editor's tools write and which sets one global:
--
--   SocialDiaryCurated = { epoch, stories = { { seq, id, title, text, t,
--                          del }, ... } }
--
-- Imported at login into the "curated" author's stream (Core/Sync/
-- Store.lua), they travel to the rest of the group as any stream does. The
-- tools number the stories, so every character of the editor's imports the
-- same seqs. A story's id says what it is about:
--
--   <guid>:L<level>       a character's level on Your Diary
--   <guid>:W<yyyy-mm-dd>  a week after the cap, by its Monday

local addonName, ns = ...

local Curated = {}
ns.Sync.Curated = Curated

local Store = ns.Sync.Store
local CURATED = ns.Sync.CURATED

-- Takes in the editor's file (the global, unless given). Returns how many
-- stories were new.
function Curated.Import(file)
    file = file or _G.SocialDiaryCurated
    if type(file) ~= "table" or type(file.epoch) ~= "number" or type(file.stories) ~= "table" then return 0 end
    local a = Store.Author(CURATED)
    if a and a.epoch > file.epoch then return 0 end
    if not a or a.epoch < file.epoch then Store.Restart(CURATED, file.epoch) end
    local stories = {}
    for _, story in ipairs(file.stories) do
        if type(story) == "table" and type(story.seq) == "number" and type(story.id) == "string" then
            stories[#stories + 1] = story
        end
    end
    -- The file holds each story's newest seq only: a seq it does not hold
    -- went to a version since replaced, and is taken in as empty, or the
    -- stream would never be whole.
    local bySeq, top = {}, 0
    for _, story in ipairs(stories) do
        bySeq[story.seq] = story
        top = math.max(top, story.seq)
    end
    local n = 0
    for seq = Store.Author(CURATED).last + 1, top do
        local story = bySeq[seq]
        local entry = story and { r = "story:" .. story.id, k = "story", id = story.id, t = story.t,
            title = story.title, text = story.text, del = story.del or nil }
        if Store.Put(CURATED, seq, entry) and entry then n = n + 1 end
    end
    return n
end

-- The story about `id`, while curated stories are read.
function Curated.Story(id)
    if ns.Setting("showCurated") ~= true then return nil end
    local entry = Store.ByRef(CURATED, "story:" .. id)
    if not entry or entry.del or type(entry.text) ~= "string" or not entry.text:match("%S") then return nil end
    return entry
end

-- The id of a Your Diary entry (Core/JourneyRecap.lua's) of `guid`'s.
function Curated.EntryId(guid, e)
    if e.kind == "week" and e.week then return ("%s:W%s"):format(guid, date("%Y-%m-%d", e.week)) end
    if e.level then return ("%s:L%d"):format(guid, e.level) end
    return nil
end

-- The story's paragraphs (split at blank lines), or nil.
function Curated.Paragraphs(text)
    local list = {}
    for paragraph in (text .. "\n\n"):gmatch("(.-)\n%s*\n") do
        paragraph = paragraph:match("^%s*(.-)%s*$")
        if paragraph ~= "" then list[#list + 1] = paragraph end
    end
    return #list > 0 and list or nil
end

-- A Your Diary entry's curated paragraphs, or nil for the diary's own.
function Curated.Lines(guid, e)
    local id = guid and Curated.EntryId(guid, e)
    local story = id and Curated.Story(id)
    return story and Curated.Paragraphs(story.text) or nil
end

ns.On("PLAYER_LOGIN", function()
    if ns.db then Curated.Import() end
end)
