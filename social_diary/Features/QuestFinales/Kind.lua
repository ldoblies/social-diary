-- Quest chain finales (JRN-28): turning in the last quest of a long chain
-- the user chose, and where the chain began. A feature in a folder of its
-- own:
--
--   Kind.lua     what a finale is to the diary: the route's list, the
--                chains' starts and the recap's moment
--   Data.lua     the chains chosen (QuestFinales.CHAINS), the feature's
--                static data
--   Text.lua     its words: the level's prose, the plates' captions, the
--                mark's tooltip
--   Mark.lua     its mark on the plates (a tailpiece)
--   Capture.lua  the quests taken and turned in, as Capture/Journey.lua
--                passes them on (SD_QUEST_ACCEPTED, SD_QUEST_TURNED_IN)
--   Dev.lua      its part of /sd testdata (never packaged)
--
-- Everything is registered into the core's and the UI's registries, so no
-- file outside this folder names a chain's finale. Its own names are on
-- ns.QuestFinales, made here, the first of its files the TOC loads. The
-- moment's kind is "finale", the route's list "finales", and the chains'
-- starts are kept on the route as j.chainStarts.
--
-- This file: the route's finales and chains begun, and the moment that
-- puts the finales on the plates.

local addonName, ns = ...

local QuestFinales = {}
ns.QuestFinales = QuestFinales

local Journey = ns.Journey

--------------------------------------------------------------------------
-- Quest chain finales (JRN-28)
--------------------------------------------------------------------------
--
-- Turning in the last quest of a chain the user chose (Data.lua):
-- "The end of “Crown of the Earth”, a chain of nine begun in Shadowglen
-- five days before." The server will not hand in a quest whose chain is
-- not done, so the turn-in is the whole proof; the quests of the chain the
-- client says are done give its length, as far as it can tell. Where it
-- began is known only when the diary saw its first quest taken.
--
-- j.chainStarts[questID] = { t, mapID, x, y, level }: a chain's first
-- quest taken, kept by that quest (one first quest may open several
-- chains). j.finales holds each finale, oldest first: { t, mapID, x, y,
-- level, questID, title, n, started }, `n` the quests of the chain done,
-- the finale with them, `started` the chain's start as kept, if it was.
-- The newest 200 finales are kept a character.

Journey.RegisterList("finales", { cap = 200,
    feed = function(rec)
        return "finale", { lv = rec.level, title = rec.title, n = rec.n, since = rec.started and rec.started.t,
            from = rec.started and rec.started.mapID and ns.MapName(rec.started.mapID) }
    end })

local firstOf

-- [first quest] = true, for every chain chosen.
local function Firsts()
    if firstOf then return firstOf end
    firstOf = {}
    for _, chain in pairs(QuestFinales.CHAINS or {}) do
        for _, route in ipairs(chain.routes or {}) do
            if route[1] then firstOf[route[1]] = true end
        end
    end
    return firstOf
end

-- Quest `questID` taken: kept where it opens a chain, the first time.
-- `rec` is { t, level }; here unless `where` says otherwise.
function QuestFinales.Begun(j, questID, rec, where)
    if not (j and type(questID) == "number" and Firsts()[questID]) then return nil end
    j.chainStarts = j.chainStarts or {}
    if j.chainStarts[questID] then return j.chainStarts[questID] end
    local spot = Journey.Spot(where)
    local start = { t = rec and rec.t or ns.Now(), mapID = spot.mapID, x = spot.x, y = spot.y,
        level = rec and rec.level }
    j.chainStarts[questID] = start
    Journey.Touch()
    return start
end

-- Quest `questID` turned in: a finale where it ends a chosen chain. `rec`
-- is { t, level, title, Done }: `title` the client's name for the quest,
-- Done(questID) whether the client has a quest down as done (nil where it
-- cannot say: the chain is then taken as done in full). The route counted
-- is the one most done. Returns the record kept, or nil.
function QuestFinales.Add(j, questID, rec, where)
    local chain = j and QuestFinales.CHAINS and QuestFinales.CHAINS[questID]
    if not chain then return nil end
    for _, f in ipairs(j.finales or {}) do
        if f.questID == questID then return nil end
    end
    rec = rec or {}
    local best, n = nil, -1
    for _, route in ipairs(chain.routes or {}) do
        local done = 1
        for i = 1, #route - 1 do
            if not rec.Done or rec.Done(route[i]) then done = done + 1 end
        end
        if done > n then best, n = route, done end
    end
    if not best then return nil end
    local started = j.chainStarts and j.chainStarts[best[1]]
    return Journey.Append(j, "finales", { t = rec.t, level = rec.level, questID = questID,
        title = rec.title or chain.title, n = n,
        started = started and { t = started.t, mapID = started.mapID, x = started.x, y = started.y,
            level = started.level } or nil }, where)
end

-- A character's finales, oldest first.
function QuestFinales.List(j)
    return Journey.List(j, "finales")
end

--------------------------------------------------------------------------
-- The recap's moment
--------------------------------------------------------------------------

-- JRN-28: a chain's finale, where it was turned in.
--
-- Rank 2, with a first found (Core/JourneyRecap.lua's RANK, Decision 10):
-- after the people you were with (1), before a death, a close call and
-- luck (3), and well before the level's pin (8). Light: its words are all
-- it has, with no card in the margin (the user's choice, 13 Oct), so a
-- plate of finales and places alone is given a print, not a full slot.
-- Its order (50) puts it after the finds and the luck, before the
-- profession caps (60).
ns.JourneyRecap.RegisterMoment("finale", { order = 50, list = "finales", field = "finale", rank = 2, light = true })
