-- Group sync's conversation: what two players with the same group code say
-- to each other so each ends up holding every author's stream
-- (Core/Sync/Store.lua). Pure: it is handed a store, a clock and two ways
-- to send, so tests can run several players against each other without a
-- client (Core/Sync/Transport.lua wires it to the game).
--
-- Each side asks for what it lacks; nothing is pushed. Anyone holding an
-- author's stream can hand it on, so a friend's diary reaches the user
-- through whoever was online with both.
--
--   H:tag:digest                 broadcast: "here, and this is what I hold"
--                                (a hash of the vector)
--   V:tag:reply:i/n:key,epoch,last;...
--                                whispered to a hello whose digest differs:
--                                what this side holds, author by author, in
--                                n parts; `reply` 1 when it answers a V, so
--                                two players never answer each other forever
--   R:tag:key:epoch:from         "send me key's stream from seq `from`"
--   D:tag:key:epoch:seq:i/n:...  part i of n of the entry at seq (Core/Sync/
--                                Wire.lua's line); n 0 is a seq left empty
--   E:tag:key:epoch:next:more    a batch's end; `more` 1 when the stream
--                                goes on past `next`, which is then asked
--
-- Numbers are base 36. `tag` is a hash of the group code: a message under
-- another group's is not heard, whatever channel it came by.

local addonName, ns = ...

ns.Sync = ns.Sync or {}
local Protocol = {}
ns.Sync.Protocol = Protocol

local Wire = ns.Sync.Wire

local T = {
    batch = 40,     -- entries a request is answered with, at most
    inflight = 60,  -- seconds a request may go unanswered before another peer is asked
    answer = 30,    -- seconds between two vectors whispered to the same hello
    stale = 120,    -- seconds a half-received vector or entry is kept
    size = 255,     -- an addon message's bytes
}
Protocol.T = T

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

local function To36(n)
    n = math.floor(n)
    if n <= 0 then return "0" end
    local s = ""
    while n > 0 do
        local d = n % 36
        s = DIGITS:sub(d + 1, d + 1) .. s
        n = (n - d) / 36
    end
    return s
end

local function From36(s)
    return s and tonumber(s, 36)
end

Protocol.To36, Protocol.From36 = To36, From36

-- The group code's tag, and the name of the channel its players meet in.
function Protocol.Tag(code)
    return Wire.HashHex("SocialDiary:" .. code)
end

function Protocol.Channel(code)
    return "SDiary" .. Wire.HashHex("SocialDiary channel:" .. code)
end

-- Whether stream `b` (as a vector holds it) is ahead of `a`.
local function Ahead(b, a)
    if not b or (b.last or 0) <= 0 and not a then return false end
    if not a then return true end
    if b.epoch ~= a.epoch then return b.epoch > a.epoch end
    return b.last > a.last
end

local function Digest(vector)
    local keys = {}
    for key in pairs(vector) do keys[#keys + 1] = key end
    table.sort(keys)
    local parts = {}
    for i, key in ipairs(keys) do
        parts[i] = key .. "," .. vector[key].epoch .. "," .. vector[key].last
    end
    return Wire.HashHex(table.concat(parts, ";"))
end

--------------------------------------------------------------------------
-- One player
--------------------------------------------------------------------------
--
-- opts:
--   store      a store (ns.Sync.NewStore)
--   tag        Protocol.Tag(code)
--   now        function() → seconds
--   whisper    function(target, text)
--   broadcast  function(text): to everyone in the group's channel
--   own        function(key) → whether the author is one of this side's
--              own characters, never asked for nor taken from others
--   heard      optional function(sender): any valid message from them

function Protocol.New(opts)
    local P = {}
    local store, tag = opts.store, opts.tag
    local inflight = {}    -- [key] = { peer, at, epoch }
    local answered = {}    -- [sender] = when a vector went to their hello
    local vectors = {}     -- [sender] = { n, got, at, reply, items = { [key] = { epoch, last } } }
    local parts = {}       -- [sender .. key .. seq] = { n, got, at, chunks }

    local function Now() return opts.now() end

    function P.Inflight() return inflight end

    -- The vector, as the store holds it.
    local function Mine() return store.Vector() end

    function P.Hello()
        opts.broadcast(("H:%s:%s"):format(tag, Digest(Mine())))
    end

    local function SendVector(target, reply)
        local items = {}
        for key, v in pairs(Mine()) do items[#items + 1] = ("%s,%s,%s"):format(key, To36(v.epoch), To36(v.last)) end
        table.sort(items)
        local room = T.size - #("V:" .. tag .. ":1:99/99:")
        local packs, current = {}, {}
        local used = 0
        for _, item in ipairs(items) do
            if used + #item + 1 > room and #current > 0 then
                packs[#packs + 1] = current
                current, used = {}, 0
            end
            current[#current + 1] = item
            used = used + #item + 1
        end
        packs[#packs + 1] = current
        for i, pack in ipairs(packs) do
            opts.whisper(target, ("V:%s:%d:%d/%d:%s"):format(tag, reply and 1 or 0, i, #packs, table.concat(pack, ";")))
        end
    end

    local function Request(peer, key, epoch, from)
        inflight[key] = { peer = peer, at = Now(), epoch = epoch }
        opts.whisper(peer, ("R:%s:%s:%s:%s"):format(tag, key, To36(epoch), To36(from)))
    end

    -- The next seq this side wants of `key`'s stream at `epoch`.
    local function Wanted(key, epoch)
        local a = store.Author(key)
        if not a or a.epoch ~= epoch then return 1 end
        return a.last + 1
    end

    local function Compare(sender, v)
        local mine = Mine()
        local lacking = false
        for key, theirs in pairs(v.items) do
            if not opts.own(key) and Ahead(theirs, mine[key]) and not inflight[key] then
                Request(sender, key, theirs.epoch, Wanted(key, theirs.epoch))
            end
        end
        for key, held in pairs(mine) do
            if Ahead(held, v.items[key]) then lacking = true end
        end
        if lacking and not v.reply then SendVector(sender, true) end
    end

    local function OnVector(sender, reply, i, n, body)
        local v = vectors[sender]
        if not v or v.n ~= n or Now() - v.at > T.stale then
            v = { n = n, got = {}, count = 0, at = Now(), items = {} }
            vectors[sender] = v
        end
        v.reply = reply
        if v.got[i] then return end
        v.got[i], v.count = true, v.count + 1
        for item in body:gmatch("[^;]+") do
            local key, epoch, last = item:match("^([^,]+),(%w+),(%w+)$")
            if key then v.items[key] = { epoch = From36(epoch), last = From36(last) } end
        end
        if v.count == n then
            vectors[sender] = nil
            Compare(sender, v)
        end
    end

    local function Serve(sender, key, epoch, from)
        local a = store.Author(key)
        if not a or a.epoch ~= epoch then
            opts.whisper(sender, ("E:%s:%s:%s:%s:0"):format(tag, key, To36(a and a.epoch or epoch), To36(from)))
            return
        end
        local list = store.From(key, from, T.batch)
        local next = from
        for _, item in ipairs(list) do
            local base = ("D:%s:%s:%s:%s:"):format(tag, key, To36(epoch), To36(item.seq))
            if item.entry then
                local line = Wire.Encode(item.entry)
                local room = T.size - #base - #"99/99:"
                local n = math.max(1, math.ceil(#line / room))
                for i = 1, n do
                    opts.whisper(sender, base .. ("%d/%d:"):format(i, n) .. line:sub((i - 1) * room + 1, i * room))
                end
            else
                opts.whisper(sender, base .. "0/0:")
            end
            next = item.seq + 1
        end
        opts.whisper(sender, ("E:%s:%s:%s:%s:%d"):format(tag, key, To36(epoch), To36(next),
            next <= a.last and 1 or 0))
    end

    local function Take(key, epoch, seq, entry)
        local a = store.Author(key)
        if a and epoch < a.epoch then return end
        if not a or epoch > a.epoch then store.Restart(key, epoch) end
        store.Put(key, seq, entry)
    end

    local function OnData(sender, key, epoch, seq, i, n, chunk)
        if opts.own(key) then return end
        local flight = inflight[key]
        if flight and flight.peer == sender then flight.at = Now() end
        if n == 0 then
            Take(key, epoch, seq, nil)
            return
        end
        local id = sender .. "\0" .. key .. "\0" .. seq
        local p = parts[id]
        if not p or p.n ~= n then
            p = { n = n, got = 0, at = Now(), chunks = {} }
            parts[id] = p
        end
        if p.chunks[i] then return end
        p.chunks[i], p.got = chunk, p.got + 1
        if p.got < n then return end
        parts[id] = nil
        local entry = Wire.Decode(table.concat(p.chunks))
        if entry then Take(key, epoch, seq, entry) end
    end

    local function OnEnd(sender, key, epoch, next, more)
        local flight = inflight[key]
        if not flight or flight.peer ~= sender then return end
        inflight[key] = nil
        -- A stream begun again with nothing in it yet is still the newer one.
        local a = store.Author(key)
        if not opts.own(key) and (not a or epoch > a.epoch) and flight.epoch == epoch then store.Restart(key, epoch) end
        local wanted = Wanted(key, epoch)
        if more or wanted < next then
            -- More to come, or something of the batch went missing.
            if wanted < next and (flight.retries or 0) >= 3 then return end
            Request(sender, key, epoch, wanted)
            inflight[key].retries = wanted < next and (flight.retries or 0) + 1 or 0
        end
    end

    -- A message from `sender`. Returns whether it was one of this group's.
    function P.Receive(sender, text)
        if type(text) ~= "string" then return false end
        local kind, theirTag, rest = text:match("^(%u):(%x+):(.*)$")
        if not kind or theirTag ~= tag then return false end
        if opts.heard then opts.heard(sender) end

        if kind == "H" then
            local last = answered[sender]
            if rest ~= Digest(Mine()) and (not last or Now() - last >= T.answer) then
                answered[sender] = Now()
                SendVector(sender, false)
            end
        elseif kind == "V" then
            local reply, i, n, body = rest:match("^([01]):(%d+)/(%d+):(.*)$")
            if reply then OnVector(sender, reply == "1", tonumber(i), tonumber(n), body) end
        elseif kind == "R" then
            local key, epoch, from = rest:match("^([^:]+):(%w+):(%w+)$")
            if key then Serve(sender, key, From36(epoch), From36(from)) end
        elseif kind == "D" then
            local key, epoch, seq, i, n, chunk = rest:match("^([^:]+):(%w+):(%w+):(%d+)/(%d+):(.*)$")
            if key then OnData(sender, key, From36(epoch), From36(seq), tonumber(i), tonumber(n), chunk) end
        elseif kind == "E" then
            local key, epoch, next, more = rest:match("^([^:]+):(%w+):(%w+):([01])$")
            if key then OnEnd(sender, key, From36(epoch), From36(next), more == "1") end
        end
        return true
    end

    -- Gives up what waited too long: a request unanswered is asked of the
    -- next peer whose vector says they have it.
    function P.Tick()
        local now = Now()
        for key, flight in pairs(inflight) do
            if now - flight.at > T.inflight then inflight[key] = nil end
        end
        for sender, v in pairs(vectors) do
            if now - v.at > T.stale then vectors[sender] = nil end
        end
        for id, p in pairs(parts) do
            if now - p.at > T.stale then parts[id] = nil end
        end
    end

    return P
end
