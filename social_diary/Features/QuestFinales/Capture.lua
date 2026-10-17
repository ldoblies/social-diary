-- Quest chain finales (JRN-28): a chain's first quest taken, and its last
-- turned in, as the route's capture passes them on.
--
-- Capture/Journey.lua counts every quest taken and turned in on the route
-- (Journey.Act) and then fires SD_QUEST_ACCEPTED / SD_QUEST_TURNED_IN
-- (Core/Events.lua) with the quest's id, at the point in its handler
-- where this capture used to run, so the order of what is written is what
-- it was when both were in one file. A turn-in reaches Capture/Journey.lua
-- through Capture/Together.lua's QUEST_TURNED_IN handler, after the
-- session's own count.
--
-- Watching is the route's: a chain's start or end is kept only while the
-- route is (ns.Journey.Kept: "Keep my own route" on, the logged-in
-- character's own route and not /sd testdata's). A finale goes on the
-- route (QuestFinales.Add, Kind.lua), a chain's start on j.chainStarts
-- (QuestFinales.Begun).

local addonName, ns = ...

local QuestFinales = ns.QuestFinales

local function Level()
    local level = ns.Plain(UnitLevel("player"))
    return type(level) == "number" and level or nil
end

-- Whether the client has quest `questID` down as done; nil where it
-- cannot say.
local function Completed()
    local Q = C_QuestLog
    local Is = Q and Q.IsQuestFlaggedCompleted or IsQuestFlaggedCompleted
    if not Is then return nil end
    return function(questID) return ns.Plain(Is(questID)) == true end
end

-- A chain's first quest taken is kept, for where it began.
ns.On("SD_QUEST_ACCEPTED", function(_, questID)
    local j = ns.Journey.Kept()
    if j then QuestFinales.Begun(j, questID, { t = ns.Now(), level = Level() }) end
end)

-- A quest turned in: a chain's finale where it ends one.
ns.On("SD_QUEST_TURNED_IN", function(_, questID)
    local j = ns.Journey.Kept()
    if not j or not QuestFinales.CHAINS[questID] then return end
    local Q = C_QuestLog
    local title = Q and Q.GetTitleForQuestID and ns.Plain(Q.GetTitleForQuestID(questID))
    local finale = QuestFinales.Add(j, questID, { t = ns.Now(), level = Level(),
        title = type(title) == "string" and title ~= "" and title or nil, Done = Completed() })
    if finale then ns.Debug("chain finale: %s, %d quests", tostring(finale.title), finale.n) end
end)
