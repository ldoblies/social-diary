-- Group sync's text form: a feed entry as one line, and a short hash.
--
-- An entry is flat: string keys, values a string, a number or a boolean.
-- Encode writes it with its keys sorted, so one entry always makes the same
-- line, which is what the feed compares to see whether a record changed
-- (Core/Sync/Feed.lua) and what goes over the wire (Core/Sync/Protocol.lua).
--
--   key=value~key=value      a number's value starts with "#", a boolean's
--                            is "!1" or "!0", anything else is a string
--
-- "%", "~", "=", "|" and control characters in keys and strings are written
-- as %XX: "|" starts an escape in WoW's chat text, and an addon message
-- may carry no NUL.

local addonName, ns = ...

local Wire = {}
ns.Sync = ns.Sync or {}
ns.Sync.Wire = Wire

local function Escape(s)
    return (s:gsub("[%%~=|%c]", function(c) return ("%%%02X"):format(c:byte()) end))
end

local function Unescape(s)
    return (s:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

local function Value(v)
    local kind = type(v)
    if kind == "number" then return "#" .. (v == math.floor(v) and ("%d"):format(v) or ("%.4f"):format(v)) end
    if kind == "boolean" then return v and "!1" or "!0" end
    return Escape(tostring(v))
end

function Wire.Encode(entry)
    local keys = {}
    for key, v in pairs(entry) do
        local kind = type(v)
        if type(key) == "string" and (kind == "string" or kind == "number" or kind == "boolean") then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    local parts = {}
    for i, key in ipairs(keys) do parts[i] = Escape(key) .. "=" .. Value(entry[key]) end
    return table.concat(parts, "~")
end

function Wire.Decode(line)
    if type(line) ~= "string" then return nil end
    local entry = {}
    for part in line:gmatch("[^~]+") do
        local key, v = part:match("^([^=]+)=(.*)$")
        if not key then return nil end
        local tag = v:sub(1, 1)
        if tag == "#" then
            entry[Unescape(key)] = tonumber(v:sub(2))
        elseif v == "!1" or v == "!0" then
            entry[Unescape(key)] = v == "!1"
        else
            entry[Unescape(key)] = Unescape(v)
        end
    end
    return entry
end

-- FNV-1a, 32 bits, as a number from 0 to 2^32-1.
function Wire.Hash(s)
    local h = 2166136261
    for i = 1, #s do
        h = bit.bxor(h, s:byte(i))
        h = (bit.band(h, 0xffff) * 16777619 + bit.lshift(bit.band(bit.rshift(h, 16) * 403, 0xffff), 16)) % 4294967296
    end
    return h % 4294967296
end

-- The hash as 8 hex digits.
function Wire.HashHex(s)
    return ("%08x"):format(Wire.Hash(s))
end
