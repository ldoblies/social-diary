-- Writes the stories the editor wrote (stories.json, beside feed.json) into
-- the small addon the game reads them from, SocialDiary_Curated
-- (social_diary/Core/Sync/Curated.lua takes it in at login).
--
--   luajit tools/curate/build.lua
--
-- Each story keeps a number (seq) until its words change, when it gets the
-- next one; a story taken out of stories.json goes out as taken back. The
-- numbers live in curated_state.json, beside stories.json: losing it
-- begins the stream again under a new epoch, which every player then
-- takes in whole.

local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
package.path = here .. "/?.lua;" .. package.path
local json = require("json")
local config = dofile(here .. "/config.lua")

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

local function Hash(s)
    local h = 2166136261
    for i = 1, #s do
        h = bit.bxor(h, s:byte(i))
        h = (bit.band(h, 0xffff) * 16777619 + bit.lshift(bit.band(bit.rshift(h, 16) * 403, 0xffff), 16)) % 4294967296
    end
    return ("%08x"):format(h % 4294967296)
end

local storiesFile = assert(Read(config.out .. "/stories.json"), "no stories.json in " .. config.out)
local stories = json.decode(storiesFile).stories or {}

local statePath = config.out .. "/curated_state.json"
local stateFile = Read(statePath)
local state = stateFile and json.decode(stateFile) or { epoch = os.time(), next = 1, ids = {} }
state.ids = state.ids or {}

local seen, changed = {}, 0
for _, story in ipairs(stories) do
    assert(type(story.id) == "string" and type(story.text) == "string", "a story without an id or text")
    seen[story.id] = true
    local hash = Hash((story.title or "") .. "\0" .. story.text .. "\0" .. tostring(story.t))
    local kept = state.ids[story.id]
    if not kept or kept.hash ~= hash or kept.del then
        state.ids[story.id] = { seq = state.next, hash = hash }
        state.next = state.next + 1
        changed = changed + 1
    end
end
for id, kept in pairs(state.ids) do
    if not seen[id] and not kept.del then
        state.ids[id] = { seq = state.next, del = true }
        state.next = state.next + 1
        changed = changed + 1
    end
end

local byId = {}
for _, story in ipairs(stories) do byId[story.id] = story end
local ids = {}
for id in pairs(state.ids) do ids[#ids + 1] = id end
table.sort(ids, function(a, b) return state.ids[a].seq < state.ids[b].seq end)

local lines = {
    "-- Written by tools/curate/build.lua: the group's curated stories for Social Diary.",
    "-- Do not edit: the next build writes it again.",
    ("SocialDiaryCurated = { epoch = %d, stories = {"):format(state.epoch),
}
for _, id in ipairs(ids) do
    local kept, story = state.ids[id], byId[id]
    if kept.del then
        lines[#lines + 1] = ("    { seq = %d, id = %q, del = true },"):format(kept.seq, id)
    else
        lines[#lines + 1] = ("    { seq = %d, id = %q, t = %s, title = %q, text = %q },"):format(kept.seq, id,
            tonumber(story.t) and ("%d"):format(story.t) or "nil", story.title or "", story.text)
    end
end
lines[#lines + 1] = "} }"

local folder = config.addons .. "/SocialDiary_Curated"
local probe = io.open(folder .. "/Curated.lua", "ab")
if probe then
    probe:close()
elseif package.config:sub(1, 1) == "\\" then
    os.execute(('mkdir "%s"'):format((folder:gsub("/", "\\"))))
else
    os.execute(('mkdir -p "%s"'):format(folder))
end
Write(folder .. "/SocialDiary_Curated.toc", table.concat({
    "## Interface: " .. (config.interface or "16001"),
    "## Title: Social Diary Curated",
    "## Notes: The group's stories for Social Diary, written by its editor.",
    "## Author: tools/curate/build.lua",
    "Curated.lua",
    "",
}, "\n"))
Write(folder .. "/Curated.lua", table.concat(lines, "\n") .. "\n")
Write(statePath, json.encode(state))

print(("%d stories, %d new or changed -> %s"):format(#stories, changed, folder))
