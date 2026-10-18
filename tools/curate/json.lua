-- Just enough JSON for the curation tools: objects, arrays, strings,
-- numbers, booleans and null. Encode sorts object keys, so a file only
-- changes where its content does.

local json = {}

local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n",
    ["\r"] = "\\r", ["\t"] = "\\t" }

local function IsArray(t)
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "number" then return false end
        n = n + 1
    end
    return n == #t
end

local function Encode(v, indent, out)
    local kind = type(v)
    if kind == "nil" then
        out[#out + 1] = "null"
    elseif kind == "boolean" then
        out[#out + 1] = tostring(v)
    elseif kind == "number" then
        out[#out + 1] = v == math.floor(v) and ("%d"):format(v) or ("%.6g"):format(v)
    elseif kind == "string" then
        out[#out + 1] = '"' .. v:gsub('[%c"\\]', function(c)
            return ESCAPES[c] or ("\\u%04x"):format(c:byte())
        end) .. '"'
    elseif kind == "table" then
        local inner = indent .. "  "
        if next(v) == nil then
            out[#out + 1] = IsArray(v) and "[]" or "{}"
        elseif IsArray(v) then
            out[#out + 1] = "[\n"
            for i, item in ipairs(v) do
                out[#out + 1] = inner
                Encode(item, inner, out)
                out[#out + 1] = i < #v and ",\n" or "\n"
            end
            out[#out + 1] = indent .. "]"
        else
            local keys = {}
            for k in pairs(v) do keys[#keys + 1] = tostring(k) end
            table.sort(keys)
            out[#out + 1] = "{\n"
            for i, k in ipairs(keys) do
                out[#out + 1] = inner
                Encode(k, inner, out)
                out[#out + 1] = ": "
                local value = v[k]
                if value == nil then value = v[tonumber(k)] end
                Encode(value, inner, out)
                out[#out + 1] = i < #keys and ",\n" or "\n"
            end
            out[#out + 1] = indent .. "}"
        end
    else
        error("json: cannot encode a " .. kind)
    end
end

function json.encode(v)
    local out = {}
    Encode(v, "", out)
    return table.concat(out)
end

local function Utf8(code)
    if code < 0x80 then return string.char(code) end
    if code < 0x800 then return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40) end
    return string.char(0xE0 + math.floor(code / 0x1000), 0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
end

function json.decode(s)
    local i = 1
    local function Fail(what) error(("json: %s at %d"):format(what, i)) end
    local function Space() i = s:find("[^ \t\r\n]", i) or #s + 1 end
    local Value

    local function String()
        i = i + 1
        local parts = {}
        while true do
            local c = s:sub(i, i)
            if c == "" then Fail("unfinished string") end
            if c == '"' then
                i = i + 1
                return table.concat(parts)
            elseif c == "\\" then
                local e = s:sub(i + 1, i + 1)
                if e == "u" then
                    local code = tonumber(s:sub(i + 2, i + 5), 16) or Fail("bad \\u")
                    if code >= 0xD800 and code < 0xDC00 and s:sub(i + 6, i + 7) == "\\u" then
                        local low = tonumber(s:sub(i + 8, i + 11), 16)
                        code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
                        parts[#parts + 1] = string.char(0xF0 + math.floor(code / 0x40000),
                            0x80 + math.floor(code / 0x1000) % 0x40, 0x80 + math.floor(code / 0x40) % 0x40,
                            0x80 + code % 0x40)
                        i = i + 12
                    else
                        parts[#parts + 1] = Utf8(code)
                        i = i + 6
                    end
                else
                    local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
                    parts[#parts + 1] = map[e] or e
                    i = i + 2
                end
            else
                local j = s:find('["\\]', i) or #s + 1
                parts[#parts + 1] = s:sub(i, j - 1)
                i = j
            end
        end
    end

    function Value()
        Space()
        local c = s:sub(i, i)
        if c == "{" then
            i = i + 1
            local t = {}
            Space()
            if s:sub(i, i) == "}" then i = i + 1 return t end
            while true do
                Space()
                if s:sub(i, i) ~= '"' then Fail("expected a key") end
                local key = String()
                Space()
                if s:sub(i, i) ~= ":" then Fail("expected ':'") end
                i = i + 1
                t[key] = Value()
                Space()
                local d = s:sub(i, i)
                i = i + 1
                if d == "}" then return t end
                if d ~= "," then Fail("expected ',' or '}'") end
            end
        elseif c == "[" then
            i = i + 1
            local t = {}
            Space()
            if s:sub(i, i) == "]" then i = i + 1 return t end
            while true do
                t[#t + 1] = Value()
                Space()
                local d = s:sub(i, i)
                i = i + 1
                if d == "]" then return t end
                if d ~= "," then Fail("expected ',' or ']'") end
            end
        elseif c == '"' then
            return String()
        elseif s:sub(i, i + 3) == "true" then
            i = i + 4
            return true
        elseif s:sub(i, i + 4) == "false" then
            i = i + 5
            return false
        elseif s:sub(i, i + 3) == "null" then
            i = i + 4
            return nil
        else
            local number = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
            if not number or number == "" then Fail("unexpected character") end
            i = i + #number
            return tonumber(number)
        end
    end

    local v = Value()
    Space()
    if i <= #s then Fail("trailing text") end
    return v
end

return json
