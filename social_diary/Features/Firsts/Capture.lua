-- Firsts found (JRN-24): the first bag, shoulders, green, blue and epic,
-- read off the bags as they change, and how each came.
--
-- Found, not worn: the moment it came into the bags. Everything comes in
-- by the bags (a bag the client puts in a bag slot itself still changes
-- them), so each BAG_UPDATE_DELAYED reads them all, and what is worn,
-- until every kind is found; after that nothing is read.
--
-- What is held the first time the bags are read after the diary was not
-- watching (a login, a /reload, the route's capture back on) was had out
-- of sight, never a first (Firsts.Held, Kind.lua). That reading waits a
-- few seconds after entering the world (SD_WORLD_SETTLED, Core/Events.lua:
-- fired by Capture/Journey.lua, whose own bag reading this was, in a
-- timer queued straight before the message's), or for the bags' own
-- update, and an empty backpack is not read at all: bags not yet loaded
-- are not "none".
--
-- How a first came: a trade completed just before, which held it (from
-- whom: SD_TRADE_COMPLETED, fired by the trade's capture as it stores the
-- trade, with who it was with and what was received), else whichever
-- window was open or had just closed.
--
-- Event order. This file is in the TOC's features' block, before
-- Capture/, where the reading was a block of Capture/Journey.lua; checked
-- event by event (15 Oct): BAG_UPDATE_DELAYED, MAIL_SHOW/CLOSED,
-- MERCHANT_SHOW/CLOSED, QUEST_COMPLETE and QUEST_FINISHED have no other
-- listener; LOOT_OPENED is also the hunts' (Features/Hunts/Capture.lua,
-- after Capture/, so still after this), and here it only notes the
-- window's state, which nothing else reads; LOOT_CLOSED has no other. The
-- login reading is the first listener of SD_WORLD_SETTLED (Firsts load
-- before Profession caps, the other one), so it runs where its own timer
-- ran, straight before the message, as before. The trade's hand-off
-- comes at the point the trade's capture set it (synchronous), and is
-- read only here. So every order is the old one.
--
-- Watching is the route's: firsts are kept only while the route is
-- (ns.Journey.Kept: "Keep my own route" on, the logged-in character's own
-- route and not /sd testdata's), and the diary stops watching while it is
-- not, so the first reading after it comes back only arms.

local addonName, ns = ...

local Firsts = ns.Firsts

local FIRSTS = {
    source = 10,   -- how fresh a trade or a closed window still says how it came
}

local function Level()
    local level = ns.Plain(UnitLevel("player"))
    return type(level) == "number" and level or nil
end

local watching = false
-- How the next find may have come: each window's state (true while it is
-- open, else when it closed).
local windows = {}
-- The last trade completed: { guid, t, received } (SD_TRADE_COMPLETED).
local lastTrade

local function Window(kind, open)
    windows[kind] = open or ns.Now()
end

local function Fresh(kind, now)
    local w = windows[kind]
    return w == true or (w ~= nil and now - w <= FIRSTS.source)
end

local function ItemID(link)
    return tonumber(type(link) == "string" and link:match("item:(%d+)") or nil)
end

-- An item as Firsts.Kinds reads it, from its link: the instant info needs
-- no item cache.
local function Item(link, quality)
    link = ns.Plain(link)
    local id = ItemID(link)
    if not id or not (C_Item and C_Item.GetItemInfoInstant) then return nil end
    local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(id)
    return { link = link, itemID = id, quality = ns.Plain(quality), equipLoc = ns.Plain(equipLoc),
        classID = ns.Plain(classID), subclassID = ns.Plain(subclassID) }
end

local function Worn(slot)
    return Item(GetInventoryItemLink("player", slot), GetInventoryItemQuality("player", slot))
end

-- Everything in the bags, in the bag slots and worn; nil while the
-- backpack does not read.
local function Held()
    local C = C_Container
    if not (C and C.GetContainerNumSlots) or (ns.Plain(C.GetContainerNumSlots(0)) or 0) <= 0 then return nil end
    local items = {}
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, ns.Plain(C.GetContainerNumSlots(bag)) or 0 do
            local info = C.GetContainerItemInfo(bag, slot)
            if info then items[#items + 1] = Item(info.hyperlink, info.quality) end
        end
        if bag > 0 and C.ContainerIDToInventoryID then items[#items + 1] = Worn(C.ContainerIDToInventoryID(bag)) end
    end
    for slot = 1, 19 do items[#items + 1] = Worn(slot) end
    return items
end

-- How `item` came, as far as can be told: received in a trade just now
-- (from whom), else whichever window was open or just closed.
local function Came(item, now)
    local trade = lastTrade
    if trade and now - trade.t <= FIRSTS.source then
        for _, r in ipairs(trade.received or {}) do
            if ItemID(r.link) == item.itemID then return "trade", trade.guid end
        end
    end
    for _, kind in ipairs({ "mail", "vendor", "quest", "loot" }) do
        if Fresh(kind, now) then return kind end
    end
    return nil
end

local function Read()
    local j = ns.Journey.Kept()
    if not j then
        watching = false
        return
    end
    if j.firsts and not Firsts.Looking(j) then return end
    local items = Held()
    if not items then return end
    if not watching or not j.firsts then
        local held = {}
        for _, item in ipairs(items) do
            for _, kind in ipairs(Firsts.Kinds(item)) do held[kind] = true end
        end
        Firsts.Held(j, held)
        watching = true
        return
    end
    local now = ns.Now()
    for _, item in ipairs(items) do
        for _, kind in ipairs(Firsts.Kinds(item)) do
            if j.firsts[kind] == nil then
                local from, guid = Came(item, now)
                Firsts.Found(j, kind, { t = now, level = Level(), link = item.link, from = from, guid = guid })
            end
        end
    end
end

ns.On("BAG_UPDATE_DELAYED", Read)

for kind, events in pairs({ mail = { "MAIL_SHOW", "MAIL_CLOSED" }, vendor = { "MERCHANT_SHOW", "MERCHANT_CLOSED" },
    quest = { "QUEST_COMPLETE", "QUEST_FINISHED" }, loot = { "LOOT_OPENED", "LOOT_CLOSED" } }) do
    ns.On(events[1], function() Window(kind, true) end)
    ns.On(events[2], function() Window(kind) end)
end

-- A trade completed: a first found just after it, among what was
-- received, was a gift from who it was with.
ns.On("SD_TRADE_COMPLETED", function(_, guid, received)
    lastTrade = { guid = guid, t = ns.Now(), received = received }
end)

-- The first reading after entering the world, which only arms.
ns.On("SD_WORLD_SETTLED", function() Read() end)
