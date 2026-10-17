-- Tester's rows (in stored order) and the testdata route, after TestData.Write
-- at a fixed now; sessions as their index, not their id. Run through
-- tests/golden/golden.sh (a harness farm). Not a test: diff before/after.
local T = ...
local mock, F = T.mock, T.F
local ns = T.Boot()
local out = {}
local function W(s) out[#out + 1] = s end
local sessionIndex = {}
local function Dump(v, depth, seen)
    depth = depth or 0
    local t = type(v)
    if t == "string" then return ("%q"):format(v) end
    if t ~= "table" then return tostring(v) end
    seen = seen or {}
    if seen[v] or depth > 8 then return "<seen>" end
    seen[v] = true
    local keys = {}
    for k, x in next, v do if type(x) ~= "function" and type(x) ~= "userdata" then keys[#keys + 1] = k end end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do
        local x = v[k]
        if k == "session" and type(x) ~= "table" and x ~= nil then x = "S" .. tostring(sessionIndex[x] or "?") end
        parts[#parts + 1] = tostring(k) .. "=" .. Dump(x, depth + 1, seen)
    end
    seen[v] = nil
    return "{" .. table.concat(parts, ",") .. "}"
end
T.BlankDiary()
local now = ns.Now()
ns.TestData.Write(now)
local G = ns.TestData.GUID
local sessions = ns.Sessions.For(G) or {}
for i, s in ipairs(sessions) do sessionIndex[s.id] = i end
W("== sessions " .. #sessions)
for i, s in ipairs(sessions) do W(("S%d %s %s %s"):format(i, tostring(s.startedAt and s.startedAt - now), tostring(s.endedAt and s.endedAt - now), tostring(s.source))) end
W("== rows")
for i, row in ipairs(ns.Interactions.For(G) or {}) do
    local copy = {}
    for k, x in pairs(row) do copy[k] = x end
    copy.time = row.time - now
    W(i .. " " .. Dump(copy))
end
W("== tints")
for _, key in ipairs({ "whisper", "party", "talk", "trade", "campfire" }) do
    W(key .. " " .. table.concat({ ns.Style.ArtTint(key) }, ",") .. " " .. Dump(ns.Style.ART[key]))
end
W("== kinds")
for _, kind in ipairs(ns.Rows.All()) do W(kind .. " " .. Dump(ns.Rows.Get(kind))) end
W("== route")
local j = ns.Journey.For(ns.ownGUID) or ns.Journey.Mine()
W(Dump(j))
io.write(table.concat(out, "\n"), "\n")
