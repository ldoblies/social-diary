-- Group sync's conversation (Core/Sync/Protocol.lua), between players
-- simulated in one process: each its own store and its own protocol, joined
-- by a network that can lose messages. The streams themselves are
-- tests/sync_feed.lua's.

local T = ...
local mock = T.mock
local Section, Check, Eq = T.Section, T.Check, T.Eq
local ns = T.Boot()

local Sync, Protocol, Wire = ns.Sync, ns.Sync.Protocol, ns.Sync.Wire
local TAG = Protocol.Tag("gigus")

local net = { queue = {}, players = {}, sent = 0, drop = nil, longest = 0, log = {} }

-- A player: `key` is their own author, written into their own store.
local function Player(name, key, code)
    local data = { authors = {}, derived = {}, peers = {} }
    local store = Sync.NewStore(function() return data end)
    local p = { name = name, key = key, store = store, data = data, heard = {} }
    p.proto = Protocol.New({
        store = store, tag = code and Protocol.Tag(code) or TAG,
        now = function() return mock.now end,
        whisper = function(target, text) net.queue[#net.queue + 1] = { from = name, to = target, text = text } end,
        broadcast = function(text) net.queue[#net.queue + 1] = { from = name, text = text } end,
        own = function(k) return k == key end,
        heard = function(sender) p.heard[sender] = true end,
    })
    net.players[name] = p
    return p
end

-- `n` entries more on `p`'s own stream, each `size` bytes of text.
local function Write(p, n, size)
    for _ = 1, n do
        local a = p.store.Author(p.key, true)
        p.store.Append(p.key, { r = "note:" .. (a.top + 1), k = "note", t = a.top + 1,
            text = ("x"):rep(size or 10) })
    end
end

-- Delivers until nothing is left, or `limit` messages; `online` (a set of
-- names) leaves out anyone else, and their messages go nowhere.
local function Run(online, limit)
    local delivered = 0
    while #net.queue > 0 and (not limit or delivered < limit) do
        local m = table.remove(net.queue, 1)
        net.sent = net.sent + 1
        net.longest = math.max(net.longest, #m.text)
        net.log[#net.log + 1] = m
        if not net.drop or not net.drop(m) then
            for name, p in pairs(net.players) do
                local to = m.to and name == m.to or not m.to and name ~= m.from
                if to and (not online or online[name]) and (not online or online[m.from]) then
                    p.proto.Receive(m.from, m.text)
                end
            end
        end
        delivered = delivered + 1
    end
    return delivered
end

local function Same(a, b, key)
    local x, y = a.store.Author(key), b.store.Author(key)
    if not (x and y) or x.epoch ~= y.epoch or x.last ~= y.last then return false end
    for seq = 1, x.last do
        local ex, ey = x.entries[seq], y.entries[seq]
        if (ex == nil) ~= (ey == nil) then return false end
        if ex and Wire.Encode(ex) ~= Wire.Encode(ey) then return false end
    end
    return true
end

-- A hello, a while after the last: each side answers one sender's hellos
-- once in Protocol.T.answer.
local function Hello(p)
    mock.now = mock.now + Protocol.T.answer
    p.proto.Hello()
end

local function Online(...)
    local set = {}
    for _, name in ipairs({ ... }) do set[name] = true end
    return set
end

--------------------------------------------------------------------------
Section("two players, each ending up with the other's")

local A = Player("Ann", "Player-1-AAAAAAAA")
local B = Player("Bo", "Player-1-BBBBBBBB")
Write(A, 100)
Write(B, 5)
B.store.Restart(Sync.CURATED, 1000)
B.store.Append(Sync.CURATED, { r = "story:1", k = "story", text = "Once upon a time" })

Hello(A)
Run(Online("Ann", "Bo"))
Check(Same(A, B, A.key), "Bo does not hold Ann's stream")
Check(Same(A, B, B.key), "Ann does not hold Bo's stream")
Check(Same(A, B, Sync.CURATED), "the curated stream did not travel")
Check(net.longest <= 255, "a message longer than 255 bytes: " .. net.longest)
Check(B.heard.Ann and A.heard.Bo, "the players never heard each other")
Eq(next(A.proto.Inflight()), nil, "a request is still in flight at Ann's")
Eq(next(B.proto.Inflight()), nil, "a request is still in flight at Bo's")

local requests = 0
for _, m in ipairs(net.log) do
    if m.text:sub(1, 2) == "R:" and m.from == "Bo" then requests = requests + 1 end
end
Eq(requests, 3, "a hundred entries in batches of 40")

local quiet = net.sent
Hello(A)
Run()
Eq(net.sent - quiet, 1, "a hello answered when both hold the same")

--------------------------------------------------------------------------
Section("an entry longer than a message")

Write(A, 1, 700)
Hello(A)
Run(Online("Ann", "Bo"))
Check(Same(A, B, A.key), "a long entry did not arrive whole")
Eq(#B.store.Author(A.key).entries[101].text, 700, "the long entry's text")

--------------------------------------------------------------------------
Section("a stream handed on by whoever holds it")

local C = Player("Cy", "Player-1-CCCCCCCC")
Write(C, 3)
Hello(C)
Run(Online("Bo", "Cy"))
Check(Same(B, C, A.key), "Ann's stream did not reach Cy through Bo")
Check(Same(B, C, C.key), "Cy's stream did not reach Bo")
Eq(A.store.Author(C.key), nil, "Ann heard Cy while offline")

--------------------------------------------------------------------------
Section("a sync cut off half way goes on from where it stopped")

local D = Player("Di", "Player-1-DDDDDDDD")
Hello(D)
Run(Online("Ann", "Di"), 30)
net.queue = {}
local held = D.store.Author(A.key)
Check(held and held.last > 0 and held.last < 101, "the cut did not fall mid-stream")
local cutAt = held.last

mock.now = mock.now + Protocol.T.inflight + 1
D.proto.Tick()
Eq(next(D.proto.Inflight()), nil, "a request lost with the cut is still waiting")
local from = #net.log
Hello(D)
Run(Online("Ann", "Di"))
local asked
for i = from + 1, #net.log do
    local m = net.log[i]
    local key, seq = m.text:match("^R:%x+:([^:]+):%w+:(%w+)$")
    if m.from == "Di" and key == A.key then asked = asked or Protocol.From36(seq) end
end
Eq(asked, cutAt + 1, "the second sync did not ask from where the first stopped")
Check(Same(A, D, A.key), "Di does not hold Ann's stream in the end")

--------------------------------------------------------------------------
Section("asking one player, not every player who has it")

local E = Player("Ed", "Player-1-EEEEEEEE")
local sentBefore = #net.log
Hello(A)
Hello(B)
Run(Online("Ann", "Bo", "Ed"))
local asks = {}
for i = sentBefore + 1, #net.log do
    local m = net.log[i]
    local key, seq = m.text:match("^R:%x+:([^:]+):%w+:(%w+)$")
    if m.from == "Ed" and key == A.key and seq == "1" then asks[#asks + 1] = m.to end
end
Eq(#asks, 1, "Ann's stream from the start was asked of two players")
Check(Same(A, E, A.key), "Ed does not hold Ann's stream")

--------------------------------------------------------------------------
Section("another group's code is not heard")

local X = Player("Xi", "Player-1-XXXXXXXX", "other group")
Write(X, 2)
Eq(A.proto.Receive("Xi", ("H:%s:00000000"):format(Protocol.Tag("other group"))), false, "another tag heard")
Hello(X)
Run()
Eq(A.store.Author(X.key), nil, "another group's stream arrived")
Eq(X.store.Author(A.key), nil, "the group's stream reached another group")
Eq(A.proto.Receive("Xi", "not a message at all"), false, "noise heard")

--------------------------------------------------------------------------
Section("a stream begun again replaces the old one")

local epoch = A.store.Author(A.key).epoch
A.store.Restart(A.key, epoch + 50)
Write(A, 2)
Hello(A)
Run(Online("Ann", "Bo"))
Eq(B.store.Author(A.key).epoch, epoch + 50, "Bo kept the old epoch")
Eq(B.store.Author(A.key).last, 2, "Bo's copy of the new stream")
Check(Same(A, B, A.key), "the new stream did not arrive whole")

A.store.Restart(A.key, epoch + 90)
Hello(A)
Run(Online("Ann", "Bo"))
Eq(B.store.Author(A.key).epoch, epoch + 90, "an empty new stream did not replace the old")

--------------------------------------------------------------------------
Section("a replaced entry travels as the newer one")

Write(A, 1)
A.store.Append(A.key, { r = "note:1", k = "note", t = 1, text = "changed" })
Hello(A)
Run(Online("Ann", "Bo"))
Eq(B.store.ByRef(A.key, "note:1").text, "changed", "the newer entry")
Check(Same(A, B, A.key), "the streams differ after a replacement")

--------------------------------------------------------------------------
Section("on a network that loses one message in eight, everyone gets there")

local F1 = Player("Fay", "Player-1-FFFFFFFF")
local G1 = Player("Gil", "Player-1-GGGGGGGG")
Write(F1, 60, 300)
Write(G1, 60, 40)
-- A fixed pseudo-random draw, so a failure can be run again as it was.
local seed = 12345
net.drop = function()
    seed = seed * 16807 % 2147483647
    return seed % 8 == 0
end
for _ = 1, 30 do
    Hello(F1)
    Hello(G1)
    Run(Online("Fay", "Gil"))
    mock.now = mock.now + Protocol.T.inflight + 1
    F1.proto.Tick()
    G1.proto.Tick()
end
net.drop = nil
Check(Same(F1, G1, F1.key), "Gil never got all of Fay's")
Check(Same(F1, G1, G1.key), "Fay never got all of Gil's")

--------------------------------------------------------------------------
Section("in the game: the channel, the queue and what is heard")

local Transport = ns.Sync.Transport
Eq(Transport.Start(), false, "started without a code")
ns.SetSetting("groupCode", "  gigus  ")
Check(Transport.Start(), "did not start with a code")
local channel = Protocol.Channel("gigus")
Eq(mock.channels[channel], "gigus", "the channel's password is not the code, trimmed")
Check(not channel:find("gigus", 1, true), "the channel's name gives the code away")

mock.guild = "Hordcore"
mock.RunTimers()
local queue = Transport.Queue()
Eq(#queue, 2, "a hello to the channel and the guild")
Eq(queue[1].chatType, "CHANNEL", "the channel's hello")
Eq(queue[1].target, 5, "the hello goes to the channel's number")
Eq(queue[2].chatType, "GUILD", "the guild's hello")

Transport.Pump()
Eq(#mock.addonSent, 2, "the queue not sent")
Eq(mock.addonSent[1].prefix, Transport.PREFIX, "the prefix")
Check(mock.addonSent[1].text:find("^H:" .. TAG .. ":"), "not a hello under the group's tag")

local function Heard(text, sender)
    mock.fire("CHAT_MSG_ADDON", Transport.PREFIX, text, "CHANNEL", sender)
end
Heard(("H:%s:00000000"):format(TAG), "Tilougil Hutdieb")
Check(#queue > 0 and queue[1].chatType == "WHISPER" and queue[1].target == "Tilougil Hutdieb",
    "a hello that differs was not answered with a whisper")
Check(ns.SyncData().peers["Tilougil Hutdieb"], "the player heard is not listed")

local waiting = #queue
Heard(("H:%s:00000000"):format(TAG), UnitName("player"))
Heard(("H:%s:00000000"):format(TAG), mock.secret("Owlbert Zenmeister"))
Heard(("H:%s:00000000"):format(Protocol.Tag("other")), "Scori Moriendi")
Eq(#queue, waiting, "the user's own echo, a secret sender or another group was answered")

--------------------------------------------------------------------------
Section("in the game: held back, throttled, and the broadcasts' allowance")

mock.addonSent = {}
mock.lockdown = true
Transport.Pump()
Eq(#mock.addonSent, 0, "sent during the client's lockdown")
mock.lockdown = false
mock.inCombat = true
Transport.Pump()
Eq(#mock.addonSent, 0, "sent in combat")
mock.inCombat = false

mock.addonResult = 3
Transport.Pump()
Eq(#queue, waiting, "a throttled message was dropped")
mock.addonResult = 0
Transport.Pump()
Eq(#queue, waiting, "sent while paused after a throttle")
mock.now = mock.now + 3
Transport.Pump()
Check(#queue < waiting, "nothing sent once the pause was over")

while #queue > 0 do Transport.Pump() end
mock.addonSent = {}
for _ = 1, 15 do Transport.Hello() end
for _ = 1, 20 do Transport.Pump() end
Eq(#mock.addonSent, 10, "broadcasts past the allowance in one second")
mock.now = mock.now + 5
for _ = 1, 20 do Transport.Pump() end
Eq(#mock.addonSent, 15, "the allowance did not come back with time")

ns.SetSetting("groupCode", "")
Eq(Transport.Start(), false, "still running with the code cleared")
Eq(mock.channels[channel], nil, "the channel was not left")
Eq(Transport.Status().on, false, "the status says it runs")
