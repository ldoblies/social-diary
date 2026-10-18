-- Group sync in the game: the conversation (Core/Sync/Protocol.lua) over
-- addon messages.
--
-- The group code names a hidden chat channel, joined with the code as its
-- password and taken out of the chat frames: the players of one group find
-- each other there. Hellos go there, and to the guild and the party as
-- well where the user is in one, in case the channel's addon messages do
-- not reach on this client; everything else is whispered, which outside
-- instances is not held to the client's ten-message allowance.
--
-- What is sent waits in one queue, sent a few at a time: broadcasts within
-- an allowance of their own (ten, one more a second, as the client's), and
-- nothing at all in combat or while the client holds addon messages back
-- (an encounter, a PvP match). A send the client throttles is tried again.

local addonName, ns = ...

local Transport = {}
ns.Sync.Transport = Transport

local Protocol = ns.Sync.Protocol

local PREFIX = "SocialDiary"
Transport.PREFIX = PREFIX

local T = {
    hello = 300,    -- seconds between two hellos
    grew = 30,      -- seconds after the feed grew that a hello says so
    join = 10,      -- seconds after login before the channel is joined
    pump = 0.2,     -- seconds between two sends from the queue
    perPump = 2,    -- sends each time
    bucket = 10,    -- broadcasts at once, one more each second
    queue = 3000,   -- messages waiting, at most
}
Transport.T = T

-- Enum.SendAddonMessageResult, by number: the client's names may change.
local THROTTLED = { [3] = true, [8] = true }
local LOCKDOWN, OFFLINE = 11, 12

local peer, channel
local queue, tokens, refilled, pausedUntil = {}, T.bucket, 0, 0
local lastHello, grewAt = 0, nil

local function Clock()
    return GetTime and GetTime() or ns.Now()
end

local function Code()
    local code = ns.db and ns.Setting("groupCode")
    code = type(code) == "string" and code:match("^%s*(.-)%s*$") or ""
    return code ~= "" and code or nil
end

local function InInstance()
    local inside = IsInInstance and IsInInstance()
    return ns.Plain(inside) == true
end

local function Enqueue(chatType, target, text)
    if #queue >= T.queue then return end
    queue[#queue + 1] = { chatType = chatType, target = target, text = text }
end

local function Broadcast(text)
    local index = channel and GetChannelName and GetChannelName(channel)
    if type(index) == "number" and index > 0 then Enqueue("CHANNEL", index, text) end
    if IsInGuild and IsInGuild() then Enqueue("GUILD", nil, text) end
    if IsInGroup and IsInGroup() and not InInstance() then
        Enqueue(IsInRaid and IsInRaid() and "RAID" or "PARTY", nil, text)
    end
end

local function Heard(sender)
    local peers = ns.SyncData().peers
    peers[sender] = peers[sender] or {}
    peers[sender].seen = ns.Now()
end

-- Whether `sender` is the user: the client echoes broadcasts back.
local function Mine(sender)
    local name = UnitName("player")
    if ns.IsSecret(name) or not name then return false end
    return sender == name or sender:sub(1, #name + 1) == name .. "-"
end

-- The send's result as a number: older clients answer with a boolean.
local function Send(item)
    local results = { pcall(C_ChatInfo.SendAddonMessage, PREFIX, item.text, item.chatType, item.target) }
    if not results[1] then return 9 end
    local result = results[#results]
    if result == true or result == nil then return 0 end
    if result == false then return 9 end
    return tonumber(result) or 0
end

function Transport.Pump()
    if #queue == 0 then return end
    local now = Clock()
    tokens = math.min(T.bucket, tokens + (now - refilled))
    refilled = now
    local lockdown = C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
    if now < pausedUntil or ns.Plain(InCombatLockdown()) == true or ns.Plain(lockdown) == true then return end

    for _ = 1, T.perPump do
        local item = queue[1]
        if not item then return end
        local free = item.chatType == "WHISPER" and not InInstance()
        if not free and tokens < 1 then return end
        local result = Send(item)
        if THROTTLED[result] then
            pausedUntil = now + 2
            return
        elseif result == LOCKDOWN then
            pausedUntil = now + 5
            return
        end
        table.remove(queue, 1)
        if not free then tokens = tokens - 1 end
        if result == OFFLINE then
            for i = #queue, 1, -1 do
                if queue[i].target == item.target then table.remove(queue, i) end
            end
        end
    end
end

function Transport.Hello()
    if not peer then return end
    lastHello, grewAt = ns.Now(), nil
    peer.Hello()
end

-- Every half minute: requests that waited too long, and a hello when one is due.
function Transport.Tick()
    if not peer then return end
    peer.Tick()
    local now = ns.Now()
    if now - lastHello >= T.hello or grewAt and now - grewAt >= T.grew then Transport.Hello() end
end

local function Hide()
    local Remove = ChatFrameUtil and ChatFrameUtil.RemoveChannel or ChatFrame_RemoveChannel
    if not (Remove and channel) then return end
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        local frame = _G["ChatFrame" .. i]
        if frame then pcall(Remove, frame, channel) end
    end
end

function Transport.Stop()
    if channel and LeaveChannelByName then pcall(LeaveChannelByName, channel) end
    peer, channel, queue = nil, nil, {}
end

-- Begins (again) with the code as it is now: none stops.
function Transport.Start()
    Transport.Stop()
    local code = Code()
    if not (code and C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false end
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    channel = Protocol.Channel(code)
    peer = Protocol.New({
        store = ns.Sync.Store,
        tag = Protocol.Tag(code),
        now = ns.Now,
        whisper = function(target, text) Enqueue("WHISPER", target, text) end,
        broadcast = Broadcast,
        own = function(key) return ns.OwnCharacters()[key] ~= nil end,
        heard = Heard,
    })
    if JoinTemporaryChannel then pcall(JoinTemporaryChannel, channel, code) end
    C_Timer.After(2, Hide)
    C_Timer.After(5, Transport.Hello)
    return true
end

-- For the settings page: whether it runs, the channel joined, what waits.
function Transport.Status()
    local index = channel and GetChannelName and GetChannelName(channel)
    local inflight = 0
    for _ in pairs(peer and peer.Inflight() or {}) do inflight = inflight + 1 end
    return { on = peer ~= nil, joined = type(index) == "number" and index > 0, queued = #queue,
        inflight = inflight }
end

-- For tests: the queue as it stands.
function Transport.Queue()
    return queue
end

ns.On("CHAT_MSG_ADDON", function(_, prefix, text, _, sender)
    if not peer or ns.IsSecret(prefix) or ns.IsSecret(text) or ns.IsSecret(sender) then return end
    if prefix ~= PREFIX or type(sender) ~= "string" or Mine(sender) then return end
    peer.Receive(sender, text)
end)

ns.On("SD_FEED_GREW", function()
    grewAt = grewAt or ns.Now()
end)

ns.On("PLAYER_LOGIN", function()
    if not ns.db then return end
    C_Timer.After(T.join, Transport.Start)
    ns.Every(30, Transport.Tick)
    ns.Every(T.pump, Transport.Pump)
end)
