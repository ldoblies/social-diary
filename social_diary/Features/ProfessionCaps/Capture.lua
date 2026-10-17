-- Profession caps (JRN-29): a profession's skill as far as it can go, read
-- off the client as it changes.
--
-- Forever has the modern profession API, not the classic skill lines
-- (probe 12 Oct: GetNumSkillLines is nil; GetProfessionInfo gives "First
-- Aid", 1, 75, 129). Each change reads every profession and holds it
-- against the last reading, by the profession's id; the first reading
-- after the diary was not watching only sets the mark, as the bags' does
-- (Features/Firsts/Capture.lua). CHAT_MSG_SKILL's words can be secret, so
-- it is a cue to read and never read itself; a burst of skill-ups (a
-- mining run) is one reading.
--
-- Watching is the route's: a cap is kept only while the route is
-- (ns.Journey.Kept: "Keep my own route" on, the logged-in character's own
-- route and not /sd testdata's). While it is not, nothing is held, so a
-- cap reached meanwhile is not one. The first reading after entering the
-- world waits for SD_WORLD_SETTLED (Core/Events.lua), the moment the bags
-- are read for the firsts, when the client has the professions loaded.
-- A cap reached goes on the route (ProfessionCaps.Add, Kind.lua).

local addonName, ns = ...

local ProfessionCaps = ns.ProfessionCaps

local SKILLS = {
    settle = 1,    -- seconds a burst of skill changes is gathered into one reading
}

-- The last reading, { [skillLine] = { rank, max, name } }; nil while there
-- is none since the diary last watched.
local skills
local skillsDue = false

local function Level()
    local level = ns.Plain(UnitLevel("player"))
    return type(level) == "number" and level or nil
end

-- Every profession the character has, by its id; nil where the client
-- has no such API.
local function Professions()
    if not (GetProfessions and GetProfessionInfo) then return nil end
    local list = {}
    -- pairs: an empty slot (no second profession, no fishing) is a nil.
    for _, index in pairs({ GetProfessions() }) do
        local name, _, rank, max, _, _, line = GetProfessionInfo(index)
        name, rank, max, line = ns.Plain(name), ns.Plain(rank), ns.Plain(max), ns.Plain(line)
        if type(line) == "number" and type(rank) == "number" and type(max) == "number" then
            list[line] = { rank = rank, max = max, name = type(name) == "string" and name ~= "" and name or nil }
        end
    end
    return list
end

local function ReadSkills()
    skillsDue = false
    local j = ns.Journey.Kept()
    local now = j and Professions()
    if not now then
        skills = nil
        return
    end
    if skills then
        for line, s in pairs(now) do
            if ProfessionCaps.IsCap(skills[line], s) then
                local cap = ProfessionCaps.Add(j, { t = ns.Now(), level = Level(), skillLine = line, name = s.name,
                    rank = s.rank })
                if cap then ns.Debug("profession cap: %s %d", tostring(cap.name), cap.rank) end
            end
        end
    end
    skills = now
end

local function SkillsChanged()
    if skillsDue then return end
    skillsDue = true
    ns.After(SKILLS.settle, ReadSkills)
end

ns.On("SKILL_LINES_CHANGED", SkillsChanged)
ns.On("CHAT_MSG_SKILL", SkillsChanged)
ns.On("SD_WORLD_SETTLED", function() ReadSkills() end)
