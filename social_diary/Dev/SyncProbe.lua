-- Development tooling: checks on this client what group sync will rely on,
-- before any of it is built. Needs two accounts with the addon, both in
-- the same channel:
--
--   /sd synctest                     what is there: the APIs, the lockdown,
--                                    the channel, what came in so far
--   /sd synctest join <name> <pass>  join a password-protected channel and
--                                    take it out of the chat frames
--   /sd synctest hello               one message over CHANNEL, GUILD and
--                                    PARTY/RAID, each send's result code
--   /sd synctest burst [n]           n (30) whispers in one go to whoever's
--                                    message came in last: is the whisper
--                                    exempt from the 10-message bucket?
--   /sd synctest leave               leave the channel
--
-- The receiving side prints every message, with its channel and sender,
-- and counts the burst so the two ends can be compared.

local addonName, ns = ...

local PREFIX = "SDProbe"
local channel, lastSender
local received = { total = 0, burst = 0 }

local function Resolve(path)
    local value = _G
    for part in path:gmatch("[^%.]+") do
        if type(value) ~= "table" then return nil end
        value = rawget(value, part)
        if value == nil then return nil end
    end
    return value
end

local function Show(value)
    if ns.IsSecret(value) then return "<secret>" end
    return tostring(value)
end

-- The send's result, whatever shape it comes in: older clients return a
-- boolean, newer ones an Enum.SendAddonMessageResult, maybe after others.
local function Send(text, chatType, target)
    local results = { pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, chatType, target) }
    if not results[1] then return "error: " .. tostring(results[2]) end
    local shown = {}
    for i = 2, #results do shown[#shown + 1] = Show(results[i]) end
    return #shown > 0 and table.concat(shown, ", ") or "(nothing returned)"
end

local function ChannelIndex()
    if not channel then return nil end
    local index = GetChannelName(channel)
    return type(index) == "number" and index > 0 and index or nil
end

local function Status()
    for _, path in ipairs({
        "C_ChatInfo.SendAddonMessage", "C_ChatInfo.RegisterAddonMessagePrefix",
        "C_ChatInfo.InChatMessagingLockdown", "C_ChatInfo.GetChannelRosterInfo",
        "JoinTemporaryChannel", "JoinChannelByName", "LeaveChannelByName",
        "ChatFrame_RemoveChannel", "ChatFrameUtil.RemoveChannel",
        "C_EncodingUtil.SerializeCBOR", "C_EncodingUtil.CompressString",
        "C_EncodingUtil.EncodeBase64", "bit.bxor",
    }) do
        DEFAULT_CHAT_FRAME:AddMessage(("   %s  %s"):format(
            Resolve(path) ~= nil and "|cff40c040yes|r" or "|cffc04040no |r", path))
    end
    local lockdown = Resolve("C_ChatInfo.InChatMessagingLockdown")
    ns.Print("lockdown %s, in combat %s", lockdown and Show(lockdown()) or "?", Show(InCombatLockdown()))
    ns.Print("channel %s (index %s), last sender %s", tostring(channel), tostring(ChannelIndex()),
        tostring(lastSender))
    ns.Print("received %d message(s), %d of them burst", received.total, received.burst)
end

local function Join(rest)
    local name, password = rest:match("^(%S+)%s*(%S*)$")
    if not name then
        ns.Print("usage: /sd synctest join <name> <password>")
        return
    end
    channel = name
    local results = { pcall(JoinTemporaryChannel, name, password ~= "" and password or nil) }
    ns.Print("JoinTemporaryChannel: %s", results[1] and "ok" or tostring(results[2]))
    C_Timer.After(2, function()
        ns.Print("channel index after 2s: %s", tostring(ChannelIndex()))
        local remove = Resolve("ChatFrameUtil.RemoveChannel") or Resolve("ChatFrame_RemoveChannel")
        if remove then
            local ok, err = pcall(remove, DEFAULT_CHAT_FRAME, name)
            ns.Print("removed from the chat frame: %s", ok and "ok" or tostring(err))
        else
            ns.Print("no way found to take the channel out of the chat frame")
        end
    end)
end

local function Hello()
    local stamp = "hello " .. tostring(time())
    local index = ChannelIndex()
    ns.Print("CHANNEL: %s", index and Send(stamp, "CHANNEL", index) or "not in the channel")
    ns.Print("GUILD: %s", IsInGuild() and Send(stamp, "GUILD") or "not in a guild")
    if IsInGroup() then
        local chatType = IsInRaid() and "RAID" or "PARTY"
        ns.Print("%s: %s", chatType, Send(stamp, chatType))
    else
        ns.Print("PARTY: not in a group")
    end
end

local function Burst(rest)
    if not lastSender then
        ns.Print("nobody to whisper yet: have the other side send /sd synctest hello")
        return
    end
    local n = tonumber(rest) or 30
    local counts = {}
    for i = 1, n do
        local result = Send(("burst %d/%d"):format(i, n), "WHISPER", lastSender)
        counts[result] = (counts[result] or 0) + 1
    end
    for result, count in pairs(counts) do ns.Print("%d x %s", count, result) end
end

local function Leave()
    if channel then pcall(LeaveChannelByName, channel) end
    ns.Print("left %s", tostring(channel))
    channel = nil
end

ns.On("CHAT_MSG_ADDON", function(_, prefix, text, chatType, sender)
    if ns.IsSecret(prefix) or prefix ~= PREFIX then return end
    received.total = received.total + 1
    if not ns.IsSecret(sender) then lastSender = sender end
    if not ns.IsSecret(text) and text:find("^burst ") then
        received.burst = received.burst + 1
        local i, n = text:match("^burst (%d+)/(%d+)")
        if i ~= n then return end
        ns.Print("burst done: %d received", received.burst)
        return
    end
    ns.Print("%s from %s: %s", Show(chatType), Show(sender), Show(text))
end)

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end

local COMMANDS = { join = Join, hello = Hello, burst = Burst, leave = Leave }

ns.Slash.Register("synctest", function(rest)
    local word, more = rest:match("^(%S*)%s*(.-)$")
    local command = COMMANDS[word]
    if command then ns.Safely(command, more) else ns.Safely(Status) end
end, "group sync probe: channel, addon messages, whisper burst", {
    dev = true, usage = "synctest [join <name> <pass> | hello | burst [n] | leave]" })
