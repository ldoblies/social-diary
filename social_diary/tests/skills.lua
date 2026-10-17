-- Your Diary's profession caps (JRN-29): a profession's skill reaching the
-- most its training allows, read off the modern profession API; what was
-- had before the diary looked is never one; training is not one; their
-- moments and ranks.

local T = ...
local mock, F = T.mock, T.F
local Section, Check, Eq = T.Section, T.Check, T.Eq
local DAY = T.DAY
local ns = T.Boot()

local J, R, P = ns.Journey, ns.JourneyRecap, ns.ProfessionCaps
local SELF = F.SELF
local MULGORE = 1412
local FIRST_AID, MINING = 129, 186

local function Skill(slot, name, rank, max, line)
    mock.professions[slot] = { name = name, rank = rank, max = max, line = line }
end

-- A skill change as the client signals it, the burst gathered.
local function Changed(event)
    mock.fire(event or "SKILL_LINES_CHANGED")
    mock.RunTimers()
end

--------------------------------------------------------------------------
Section("what counts as reaching a cap")

local Is = P.IsCap
Check(Is({ rank = 74, max = 75 }, { rank = 75, max = 75 }), "74 to 75 of 75")
Check(Is({ rank = 70, max = 75 }, { rank = 76, max = 75 }), "a climb past the max was not taken for a cap")
Check(not Is({ rank = 75, max = 75 }, { rank = 75, max = 150 }), "training was taken for a cap")
Check(not Is({ rank = 75, max = 75 }, { rank = 75, max = 75 }), "staying at the cap was taken for reaching it")
Check(not Is({ rank = 0, max = 0 }, { rank = 75, max = 75 }), "a reading not yet loaded was taken for a climb")
Check(not Is({ rank = 140, max = 150 }, { rank = 149, max = 150 }), "below the cap")
Check(not Is(nil, { rank = 75, max = 75 }), "a profession just learned, at its cap")
Check(Is({ rank = 299, max = 300 }, { rank = 300, max = 300 }), "the last cap")

--------------------------------------------------------------------------
Section("what is held when the diary first looks is never a cap")

Skill(5, "First Aid", 75, 75, FIRST_AID)
Skill(1, "Mining", 60, 75, MINING)
mock.position = { x = 0.4, y = 0.6 }
mock.fire("PLAYER_ENTERING_WORLD")
local j = ns.db.journey[SELF.guid]
Check(j, "setup: no route")
mock.RunTimers()
Eq(j.skillCaps, nil, "a profession already at its cap at login became a cap")

-- A skill-up under the cap, then training: neither is a moment.
Skill(1, "Mining", 61, 75, MINING)
Changed()
Skill(5, "First Aid", 75, 150, FIRST_AID)
Changed()
Eq(j.skillCaps, nil, "a skill-up or training was kept")

--------------------------------------------------------------------------
Section("a cap reached, where and when")

mock.now = mock.now + 600
mock.position = { x = 0.5, y = 0.25 }
Skill(1, "Mining", 75, 75, MINING)
Changed("CHAT_MSG_SKILL")
Check(j.skillCaps and #j.skillCaps == 1, "the cap was not kept")
local cap = j.skillCaps[1]
Eq(cap.t, mock.now, "when it was reached")
Eq(cap.mapID, MULGORE, "the zone it was reached in")
Eq(cap.x, 0.5, "where it was reached")
Eq(cap.skillLine, MINING, "which profession")
Eq(cap.name, "Mining", "the profession's name")
Eq(cap.rank, 75, "the cap reached")
Check(cap.level, "the level it was reached at")

-- A burst: the chat line and the skill event of one skill-up are one
-- reading, and staying at the cap is nothing new.
mock.fire("CHAT_MSG_SKILL")
mock.fire("SKILL_LINES_CHANGED")
Eq(#mock.timers, 1, "a burst of skill changes was read more than once")
mock.RunTimers()
Eq(#j.skillCaps, 1, "staying at the cap was kept again")

-- Trained, climbed again, and the next cap is one more.
Skill(1, "Mining", 75, 150, MINING)
Changed()
Skill(1, "Mining", 149, 150, MINING)
Changed()
mock.now = mock.now + 60
Skill(1, "Mining", 150, 150, MINING)
Changed()
Eq(#j.skillCaps, 2, "the second cap was not kept")
Eq(j.skillCaps[2].rank, 150, "the second cap's rank")

-- A secret reading is no reading.
local saved = _G.issecretvalue
_G.issecretvalue = function(v) return v == 150 end
Skill(1, "Mining", 150, 150, MINING)
Changed()
_G.issecretvalue = saved
Eq(#j.skillCaps, 2, "a secret skill was read")

--------------------------------------------------------------------------
Section("not watching: a cap reached meanwhile is not one")

ns.JourneyCapture.SetEnabled(false)
Skill(5, "First Aid", 149, 150, FIRST_AID)
Changed()
Skill(5, "First Aid", 150, 150, FIRST_AID)
Changed()
ns.JourneyCapture.SetEnabled(true)
Changed()
Eq(#j.skillCaps, 2, "a cap reached while the route was off was kept")

-- A client without the API reads nothing and breaks nothing.
do
    local G, I = _G.GetProfessions, _G.GetProfessionInfo
    _G.GetProfessions, _G.GetProfessionInfo = nil, nil
    Changed()
    _G.GetProfessions, _G.GetProfessionInfo = G, I
    Eq(#j.skillCaps, 2, "no API, yet a cap")
end

-- Kept to T.skillCaps, the oldest going.
do
    local r = {}
    for i = 1, J.T.skillCaps + 3 do P.Add(r, { t = i, skillLine = MINING, rank = 75 }, {}) end
    Eq(#r.skillCaps, J.T.skillCaps, "more caps kept than T.skillCaps")
    Eq(r.skillCaps[1].t, 4, "the oldest caps were not the ones to go")
end

--------------------------------------------------------------------------
Section("caps on the plates: they rank with the level-up (JRN-29)")

local d0 = mock.now + DAY
local r = {
    startedAt = d0, startLevel = 5, levels = {}, marks = {}, deaths = {},
    segments = {
        { kind = "stop", from = d0, to = d0 + 600, mapID = MULGORE, x = 0.1, y = 0.1, seconds = 600 },
    },
    skillCaps = {
        { t = d0 + 100, mapID = MULGORE, x = 0.7, y = 0.3, level = 5, skillLine = MINING, name = "Mining", rank = 75 },
        -- Reached in a dungeon: no spot of its own, placed by the route.
        { t = d0 + 200, level = 5, skillLine = FIRST_AID, name = "First Aid", rank = 150 },
    },
}
local e = R.Gather(r, d0, d0 + 1000, {})
Eq(#e.skillCaps, 2, "the caps in the stretch")
local moments = R.Moments(r, e, {})
local skills = {}
for _, m in ipairs(moments) do
    if m.kind == "skill" then skills[#skills + 1] = m end
end
Eq(#skills, 2, "a cap has no moment")
Eq(skills[1].cap.name, "Mining", "the moment does not carry its cap")
Eq(skills[1].x, 0.7, "a cap's moment is not where it was reached")
Eq(skills[2].x, 0.1, "a cap with no spot was not placed by the route")
Eq(R.Rank(skills[1]), R.RANK.find, "a cap does not rank with a first found")
Check(R.Rank(skills[1]) < R.RANK.level, "a cap does not outrank a level-up")
Check(R.Rank(skills[1]) < R.RANK.death, "a cap ranks below a death")
Eq(#R.Gather(r, d0 + 150, d0 + 1000, {}).skillCaps, 1, "a cap not in its stretch")
