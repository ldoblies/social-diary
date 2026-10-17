-- Hunts (JRN-26 bad luck, EXT-3 good luck): how many kills a quest's
-- drops took, and whether that was bad luck or good. A feature in a folder
-- of its own:
--
--   Kind.lua       what a hunt is to the route: the hunts under way and
--                  finished, the drop rates' reckoning, bad and good luck,
--                  and the two recap moments one list makes (`luck`,
--                  `fortune`)
--   Text.lua       its words: a hunt in a few words, its tooltips, the
--                  cards' words, the level's prose and the plates' caption
--   Mark.lua       its marks on the plates: the tally (bad luck) and the
--                  lucky star (good luck)
--   HuntCard.lua   bad luck's card in the plate's margin, and its note
--   LuckyCard.lua  good luck's card in the margin, its note, and S, good
--                  luck told on a light plate's print (the plate's pass
--                  that draws it over the picture)
--   Capture.lua    the quest log, the kills, the loot window and the
--                  party's loot read while a quest's drops are counted
--   Dev.lua        its part of /sd testdata: the made-up route's hunts
--                  (never packaged)
--
-- Everything is registered into the core's and the UI's registries, so
-- no file outside this folder names a hunt's list, words, marks or cards.
-- Its own names are on ns.Hunts, made here, the first of its files the
-- TOC loads.
--
-- What stays core, because it is the diary's substrate and not this
-- feature's detection:
--   - the creature names read off units for a while (Core/
--     CreatureNames.lua: Note, Of, j.names): a kill names its creature
--     there too, and this list is registered `readNames` (its own reading:
--     the finished hunts oldest first, then the ones under way), so
--     CreatureNames.Of takes a creature's name from it where none was read
--     lately;
--   - QuestieDB (Core/Bridges/Questie.lua, ns.QuestieBridge): a creature's
--     name for every kind, and for the hunts the item a quest wants, who
--     drops it and at what rate, asked at call time;
--   - the shared words (Text.Count, Plural, ItemWord, Items, NUMBER,
--     WORDS, When) and a creature's display looked up as a killer's is
--     (ns.Deaths.LookUp, the deaths' own, asked guarded);
--   - the route's gate (Journey.Kept) and its login pruning
--     (Journey.Prune, which asks this list's `prune`).
--
-- Besides its list (j.hunts), the route keeps the hunts under way
-- (j.hunting, below): written and read by this feature alone, saved so a
-- hunt carries over a logout.
--
-- This file: the hunts, their writers and readers, the luck read off them,
-- and the moments that put them on the plates.

local addonName, ns = ...

local Hunts = {}
ns.Hunts = Hunts

local Journey = ns.Journey

-- D14: the numbers, to tune with real hunts. Seconds.
local T = {
    huntAge = 30 * 86400,   -- a count still open this long is given up
    luckExtra = 8,      -- bad luck: at least this many kills more than items...
    luckRatio = 3,      -- ...and this many kills an item, or more...
    luckUsual = 2,      -- ...and this many times the character's usual, once
    luckKnown = 5,      -- this many drops have been counted
    luckOver = 1.25,    -- with the drop rate known: luckExtra kills more than
                        -- expected, and this many times it (EXT-2)
    fortune = 8,        -- good luck: an eighth of the kills expected, or fewer (EXT-3)
    rateDoubt = 1e-4,   -- a drop rate under which a hunt this slow had less than this
                        -- chance is taken for wrong, and the next source tried
}
Hunts.T = T

--------------------------------------------------------------------------
-- Hunts: how many kills a quest's drops took
--------------------------------------------------------------------------
--
-- A quest that wants items off creatures ("Plainstrider Meat: 3/7") is a
-- hunt from the moment it is seen with none of them, to the moment it has
-- them all. On the way, every creature the user or their group kills is
-- counted by kind, and the loot window says which kinds the items came off
-- (GetLootSourceInfo, probe 11 Oct: the corpse's plain GUID). The count is
-- the kills of those kinds: "it took 31 Plainstriders for 7 meat". Where
-- the user runs QuestieDB (EXT-2), it says every kind that drops the item
-- from the start, so a kind counts that never dropped it into the user's
-- own loot window (a group member looted it, or it simply never dropped);
-- and Questie's drop rates say how many kills it should have taken.
--
-- A group member on the same quest loots the same drops: an item they
-- take off a corpse is not there for the user (12 Oct, the user: "if they
-- loot it, I can't"). The party's loot messages say what they took, and
-- those count with the user's own, so the kills are set against every
-- item the group's kills gave: `shared`, the group's copies.
--
-- j.hunting[key] is a hunt under way, key "questID:objective": { questID,
-- index, title, item, itemID, need, since, kills = { [npcID] = n }, from =
-- { [npcID] = true }, names = { [npcID] = name }, shared }. Kills are counted for
-- every kind, because the first drop is what says which kind counted.
-- Saved, so a hunt carries over a logout; given up after T.huntAge (the
-- list's `prune`, at login), or when the quest leaves the log.
--
-- j.hunts holds each one finished, oldest first: { t, mapID, x, y, level,
-- questID, title, item, itemID, need, shared, kills, npcID, name, byKind,
-- expected, display }. `itemID` from QuestieDB, else from the loot link
-- (for the item's icon; older records have none). The creature is the kind that dropped it most often killed;
-- `byKind` each kind's own kills, { [npcID] = { n, name } }, where there
-- were more kinds than one; `expected` the kills the drop rates said it
-- would take, to a tenth, where every kind killed has a rate. A hunt whose
-- items never came off a creature (a plant, a chest) or were never seen
-- looted keeps nothing. Whether one was bad luck or good is decided when
-- it is read (BadLuck, GoodLuck). The newest 400 are kept a character.
--
-- Its creatures' names are as read off their units, so the list is
-- registered `readNames`; with a reading of its own, which the name
-- cache asked before the list was registered (Core/Journey.lua kept it then): the
-- finished hunts oldest first (the default reads a list newest first),
-- then the hunts under way, which are not on the list. Kept as it was, so
-- no creature's name changes where two hunts kept one kind under two
-- names.

local LIST = "hunts"

Journey.RegisterList(LIST, { cap = 400,
    readNames = function(j, npcID)
        for _, hunt in ipairs(j.hunts or {}) do
            if hunt.npcID == npcID and hunt.name then return hunt.name end
        end
        for _, hunt in pairs(j.hunting or {}) do
            if hunt.names and hunt.names[npcID] then return hunt.names[npcID] end
        end
        return nil
    end,
    -- A hunt open too long is given up.
    prune = function(j, now)
        for key, hunt in pairs(j.hunting or {}) do
            if now - hunt.since > T.huntAge then j.hunting[key] = nil end
        end
    end })

function Hunts.Key(questID, index)
    return questID .. ":" .. index
end

-- Whether objective `index` of `questID` is being counted.
function Hunts.Hunting(j, questID, index)
    return j and j.hunting and j.hunting[Hunts.Key(questID, index)] or nil
end

-- A hunt begins: `info` is { questID, index, title, item, need, t, and
-- where QuestieDB says, itemID and droppers, the kinds that drop it }.
function Hunts.Begin(j, info)
    if not j or type(info.questID) ~= "number" or type(info.need) ~= "number" or info.need < 1 then return nil end
    if type(info.item) ~= "string" or info.item == "" then return nil end
    local key = Hunts.Key(info.questID, info.index)
    j.hunting = j.hunting or {}
    if j.hunting[key] then return j.hunting[key] end
    local hunt = { questID = info.questID, index = info.index, title = info.title, item = info.item,
        itemID = info.itemID, need = info.need, since = info.t or ns.Now(), kills = {}, from = {}, names = {} }
    for _, npcID in ipairs(info.droppers or {}) do hunt.from[npcID] = true end
    j.hunting[key] = hunt
    return hunt
end

-- A creature of kind `npcID` killed by the user or their group, counted
-- in every hunt under way. `name` when it could be read.
function Hunts.Kill(j, npcID, name)
    if not (j and j.hunting and npcID) then return end
    for _, hunt in pairs(j.hunting) do
        hunt.kills[npcID] = (hunt.kills[npcID] or 0) + 1
        if name and not hunt.names[npcID] then hunt.names[npcID] = name end
    end
    ns.CreatureNames.Note(npcID, name)
end

-- Item `item` (its name, `itemID` where the link says) seen in the loot
-- of a creature of kind `npcID`: that kind drops it, for every hunt after
-- it. Whether any was.
function Hunts.Drop(j, item, npcID, name, itemID)
    if not (j and j.hunting and npcID and item) then return false end
    local any = false
    for _, hunt in pairs(j.hunting) do
        if hunt.item == item or hunt.item:find(item, 1, true) then
            hunt.from[npcID] = true
            if name and not hunt.names[npcID] then hunt.names[npcID] = name end
            if not hunt.itemID and hunt.item == item then hunt.itemID = itemID end
            any = true
        end
    end
    return any
end

-- Item `item` (its name, `itemID` where the link says), `n` of them,
-- looted by a group member: gone from the user's hunts for it. Whether any
-- was.
function Hunts.Shared(j, item, itemID, n)
    if not (j and j.hunting and item) then return false end
    local any = false
    for _, hunt in pairs(j.hunting) do
        if (itemID and hunt.itemID == itemID) or hunt.item == item then
            hunt.shared = (hunt.shared or 0) + (n or 1)
            any = true
        end
    end
    if any then Journey.Touch() end
    return any
end

-- How many items a finished hunt's kills gave: the user's, and the
-- group's copies (`shared`).
function Hunts.Items(hunt)
    return (hunt.need or 0) + (hunt.shared or 0)
end

-- How likely a hunt is at least this slow: `kills` for `items` where
-- each kill drops one at `p`, the chance the first kills - 1 gave fewer
-- than `items` (a binomial tail, summed in logs).
local function Slow(kills, items, p)
    if items < 1 or kills <= items then return 1 end
    p = math.min(math.max(p, 1e-6), 1 - 1e-9)
    local n, sum = kills - 1, 0
    local lp, lq = math.log(p), math.log(1 - p)
    local lc = 0 -- log C(n, i)
    for i = 0, items - 1 do
        if i > 0 then lc = lc + math.log(n - i + 1) - math.log(i) end
        sum = sum + math.exp(lc + i * lp + (n - i) * lq)
    end
    return sum
end
Hunts.Slow = Slow

-- Whether `expected` kills for `items` can be believed of a hunt that
-- took `kills`: a rate under which it had less than T.rateDoubt chance is
-- wrong (12 Oct, in the client: 37 kills for 6 Red Linen Bandanas at the
-- 66% QuestieDB's server data gives every Defias that drops one, where
-- Wowhead has 37%).
function Hunts.Believable(kills, items, expected)
    if not (expected and expected > 0 and items > 0) then return false end
    return Slow(kills, items, items / expected) >= T.rateDoubt
end

-- The kills `need` items should have taken, at each kind's own rate
-- (percent, `Rate(npcID)`), weighted by the kills of each: nil unless
-- every kind killed has one. To a tenth.
local function Expected(byKind, kills, need, Rate)
    if not Rate then return nil end
    local items = 0
    for npcID, k in pairs(byKind) do
        local rate = Rate(npcID)
        if type(rate) ~= "number" or rate <= 0 then return nil end
        items = items + k.n * rate / 100
    end
    if items <= 0 then return nil end
    return math.floor(need * kills / items * 10 + 0.5) / 10
end
Hunts.Expected = Expected

-- The first of `rates` (Rate functions, the best source first) whose
-- expectation can be believed (Hunts.Believable): nil without one.
local function Rated(byKind, kills, items, rates)
    for _, Rate in ipairs(rates or {}) do
        local expected = Expected(byKind, kills, items, Rate)
        if expected and Hunts.Believable(kills, items, expected) then return expected end
    end
    return nil
end

-- The hunt for objective `index` of `questID` done, here and now unless
-- `where` says otherwise. `rec` is { t, level, Rates }: Rate(itemID,
-- npcID) functions, the drop rate in percent where it is known (EXT-2),
-- the best source first, the next where the first cannot be believed. Returns the record
-- kept, or nil when there was nothing to count.
function Hunts.Done(j, questID, index, rec, where)
    local key = Hunts.Key(questID, index)
    local hunt = j and j.hunting and j.hunting[key]
    if not hunt then return nil end
    j.hunting[key] = nil
    local kills, npcID, most, byKind, kinds = 0, nil, -1, {}, 0
    for id in pairs(hunt.from) do
        local n = hunt.kills[id] or 0
        if n > 0 then
            kills, kinds = kills + n, kinds + 1
            byKind[id] = { n = n, name = hunt.names[id] or ns.CreatureNames.Of(j, id) }
            if n > most or (n == most and id < npcID) then npcID, most = id, n end
        end
    end
    if kills == 0 then return nil end
    local rates = {}
    for _, Rate in ipairs(hunt.itemID and rec and rec.Rates or {}) do
        rates[#rates + 1] = function(id) return Rate(hunt.itemID, id) end
    end
    local spot = Journey.Spot(where)
    local shared = hunt.shared and hunt.shared > 0 and hunt.shared or nil
    local done = { t = rec and rec.t or ns.Now(), mapID = spot.mapID, x = spot.x, y = spot.y,
        level = rec and rec.level, questID = questID, title = hunt.title, item = hunt.item, itemID = hunt.itemID, need = hunt.need,
        shared = shared, kills = kills, npcID = npcID, name = byKind[npcID].name, byKind = kinds > 1 and byKind or nil,
        expected = Rated(byKind, kills, hunt.need + (shared or 0), rates) }
    -- On the list as Journey.Append keeps one (the newest T.hunts), with
    -- the record's fields in their own order.
    j.hunts = j.hunts or {}
    j.hunts[#j.hunts + 1] = done
    while #j.hunts > Journey.T[LIST] do table.remove(j.hunts, 1) end
    Journey.Touch()
    return done
end

-- The quest `questID` has left the log: what was being counted for it is
-- given up.
function Hunts.Gone(j, questID)
    if not (j and j.hunting) then return end
    for key, hunt in pairs(j.hunting) do
        if hunt.questID == questID then j.hunting[key] = nil end
    end
end

-- A character's finished hunts, oldest first.
function Hunts.List(j)
    return Journey.List(j, LIST)
end

-- The character's usual kills an item: the median over its hunts, once
-- T.luckKnown have been counted.
function Hunts.UsualLuck(j)
    local ratios = {}
    for _, hunt in ipairs(Hunts.List(j)) do ratios[#ratios + 1] = hunt.kills / Hunts.Items(hunt) end
    if #ratios < T.luckKnown then return nil end
    table.sort(ratios)
    local mid = (#ratios + 1) / 2
    return (ratios[math.floor(mid)] + ratios[math.ceil(mid)]) / 2
end

-- Whether `hunt` was bad luck. With the drop rates known (EXT-2):
-- T.luckExtra kills more than expected, and T.luckOver times it. Without:
-- T.luckExtra kills more than the items its kills gave (the user's and
-- the group's, Hunts.Items), T.luckRatio kills an
-- item or more, and, once the character's usual is known, T.luckUsual
-- times it. `usual` saves working it out again (false: too few hunts to
-- know).
function Hunts.BadLuck(j, hunt, usual)
    if not hunt then return false end
    if hunt.expected then
        return hunt.kills >= hunt.expected + T.luckExtra and hunt.kills >= hunt.expected * T.luckOver
    end
    local items = Hunts.Items(hunt)
    if hunt.kills - items < T.luckExtra then return false end
    local ratio = hunt.kills / items
    if ratio < T.luckRatio then return false end
    if usual == nil then usual = Hunts.UsualLuck(j) end
    return not usual or ratio >= usual * T.luckUsual
end

-- A hunt kept before the drop rates were read (EXT-2), or while QuestieDB
-- was away, given them where QuestieDB is here now: its item by the quest,
-- and the kills it should have taken, kept in the record as capture would
-- have (12 Oct, in the client: 37 Defias Rogue Wizards for 6 Red Linen
-- Bandanas, from before, had no rate, and its card none to show). The
-- kinds are the ones it kept: one, or its `byKind`. A rate kept that
-- cannot be believed (Hunts.Believable) is read again the same way, and
-- dropped where no source can be. Whether it has a rate.
function Hunts.Rated(hunt)
    if not hunt then return false end
    local items = Hunts.Items(hunt)
    if hunt.expected and Hunts.Believable(hunt.kills or 0, items, hunt.expected) then return true end
    local Q = ns.QuestieBridge
    if not (Q and Q.On() and hunt.questID and hunt.need and hunt.kills and hunt.kills > 0) then
        return hunt.expected ~= nil
    end
    local itemID = hunt.itemID or Q.ItemFor(hunt.questID, hunt.item)
    local byKind = hunt.byKind or (hunt.npcID and { [hunt.npcID] = { n = hunt.kills } })
    if not (itemID and byKind) then return hunt.expected ~= nil end
    hunt.itemID = itemID
    hunt.expected = Rated(byKind, hunt.kills, items, {
        function(id) return Q.DropRate(itemID, id) end,
        function(id) return Q.WowheadRate(itemID, id) end,
    })
    return hunt.expected ~= nil
end

-- Whether `hunt` was good luck (EXT-3): with the drop rates known, an
-- eighth of the kills expected or fewer (T.fortune). Never without them.
function Hunts.GoodLuck(hunt)
    return hunt ~= nil and hunt.expected ~= nil and hunt.kills * T.fortune <= hunt.expected
end

--------------------------------------------------------------------------
-- The recap's moments: one list, two kinds
--------------------------------------------------------------------------

-- JRN-26: a quest's drops that took bad luck, where the last came; EXT-3:
-- and good luck. One list, the hunts, makes both: `luck` gathers them
-- (its `gather` reads the list once, the character's usual worked out
-- once, and puts each hunt in the level's e.hunts or e.fortunes, or
-- neither), and `fortune` gathers nothing of its own (its entry,
-- e.fortunes, is filled by luck's, which comes first: order 30 < 40).
-- Both rank 3, with a death and a close call (Decision 10's list: deaths,
-- close calls, then bad or good luck with a quest's drops). Bad luck is
-- full (its card goes in the margin); good luck light
-- (the user's choice, 13 Oct: words only, or S on a light plate's print,
-- LuckyCard.lua).
ns.JourneyRecap.RegisterMoment("luck", { order = 30, entry = "hunts", field = "hunt", rank = 3,
    gather = function(j, a, b, e)
        local usual = Hunts.UsualLuck(j) or false
        for _, hunt in ipairs(Hunts.List(j)) do
            if hunt.t >= a and hunt.t < b then
                Hunts.Rated(hunt)
                if Hunts.BadLuck(j, hunt, usual) then
                    e.hunts[#e.hunts + 1] = hunt
                elseif Hunts.GoodLuck(hunt) then
                    e.fortunes[#e.fortunes + 1] = hunt
                end
            end
        end
    end })
ns.JourneyRecap.RegisterMoment("fortune", { order = 40, entry = "fortunes", field = "hunt", rank = 3, light = true,
    gather = function() end })
