-- Golden dump of every People row type through the core and the ledger:
-- what Add stores, last seen, sessions, counts, the picker's reasons, the
-- timeline's folding and its words and icons, people stats, sightings' marks.
-- Run through tests/golden/golden.sh (a harness farm). Not a test: diff before/after.
local T = ...
local mock, F = T.mock, T.F
local ns = T.Boot()

local out = {}
local function W(s) out[#out + 1] = s end

local function Dump(v, depth, seen)
    depth = depth or 0
    local t = type(v)
    if t == "string" then return ("%q"):format(v) end
    if t ~= "table" then return tostring(v) end
    if v.type and v.time and depth > 0 then return "row:" .. tostring(v.type) .. "@" .. tostring(v.time) end
    seen = seen or {}
    if seen[v] or depth > 5 then return "<seen>" end
    seen[v] = true
    local keys = {}
    for k, x in next, v do if type(x) ~= "function" and type(x) ~= "userdata" then keys[#keys + 1] = k end end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. Dump(v[k], depth + 1, seen) end
    seen[v] = nil
    return "{" .. table.concat(parts, ",") .. "}"
end

local TYPES = { "trade", "whisper_in", "whisper_out", "say", "yell", "party", "group_join", "group_leave",
    "level_up", "pvp_kill", "pvp_death", "watched_death", "tried_to_help", "saved_you", "campfire", "duel" }
local CONTEXT = {
    trade = { given = { { link = "[Linen Cloth]", count = 2, quality = 1 } }, moneyReceived = 150 },
    group_join = { raid = false },
    level_up = { from = 11, level = 12 },
    pvp_kill = { by = "you" },
    pvp_death = { probable = true },
    watched_death = { watched = 6, subZone = "Lushwater Oasis", name = "Sunscale Lashtail" },
    tried_to_help = { subZone = "Lushwater Oasis" },
    saved_you = { pct = 9, name = "Razormane Hunter" },
    campfire = { subZone = "Lushwater Oasis" },
}

T.BlankDiary()
local PAL, STR = F.FRIEND.guid, F.STRANGER.guid
mock.SetUnit("target", F.FRIEND)
ns.Diary.Add(PAL)
local t0 = ns.Now() - 3600
for i, kind in ipairs(TYPES) do
    for _, guid in ipairs({ PAL, STR }) do
        -- Live (time nil): last seen, sessions; then a dated one.
        ns.Interactions.Add(guid, kind, { excerpt = "hello " .. kind, context = CONTEXT[kind], theirLevel = 12 })
        ns.Interactions.Add(guid, kind, { time = t0 + i * 30, excerpt = "then " .. kind, context = CONTEXT[kind],
            where = { zone = "The Barrens", mapID = 1413, x = 0.5, y = 0.5 } })
    end
    -- Outside any session, days apart, so each folds on its own; twice
    -- and three times, for the exchanges.
    for n = 1, 3 do
        ns.Interactions.Add(PAL, kind, { time = t0 - i * 86400 * 2 + n * 20, excerpt = "old " .. kind,
            context = CONTEXT[kind], session = false, where = { zone = "Mulgore", mapID = 1412, x = 0.4, y = 0.4 } })
    end
    -- A stranger of their own with this one row, for the picker's reason.
    local lone = ("Player-4620-00C0C0%02d"):format(i)
    ns.Interactions.Add(lone, kind, { time = ns.Now() - 600 - i, context = CONTEXT[kind], session = false })
end

for _, guid in ipairs({ PAL, STR }) do
    W("== " .. guid)
    for _, row in ipairs(ns.Interactions.For(guid) or {}) do
        local copy = {}
        for k, x in pairs(row) do if k ~= "time" then copy[k] = x end end
        copy.live = row.time > t0 + 1000 or nil
        W("ROW " .. Dump(copy))
    end
    W("COUNT " .. tostring(ns.Interactions.Count(guid)))
    local c = ns.db.characters and ns.db.characters[guid]
    W("SEEN " .. Dump(c and { lastSeen = c.lastSeen ~= nil, zone = c.lastZone or c.zone } or {}))
    W("SESSIONS " .. #(ns.Sessions.For(guid) or {}))
    for _, s in ipairs(ns.Sessions.For(guid) or {}) do W("HIGHLIGHTS " .. Dump(ns.Sessions.Highlights(s))) end
    W("STATS " .. Dump(ns.People.Stats(guid)))
end
W("== since")
W(Dump(ns.Interactions.Since(0)))
W("== candidates")
for _, c in ipairs(ns.Candidates()) do W("CAND " .. Dump(c)) end
W("== timeline")
local function Items(list, depth)
    for _, item in ipairs(list or {}) do
        local when, text, sub, icon, story = ns.UI.DescribeItem(item, PAL)
        W(("%sITEM %s | %s | %s | %s | %s | %s"):format(("  "):rep(depth), tostring(item.kind), tostring(text),
            tostring(sub), tostring(icon), tostring(story and Dump(story) or nil), tostring(when)))
        Items(item.children, depth + 1)
    end
end
Items(ns.Timeline.For(PAL), 0)
W("== single rows")
for _, kind in ipairs(TYPES) do
    local when, text, sub, icon = ns.UI.DescribeItem({ kind = "row", time = 0,
        row = { type = kind, excerpt = "hi", zone = "The Barrens", context = CONTEXT[kind] } }, PAL)
    W(("ONE %s | %s | %s | %s"):format(kind, tostring(text), tostring(sub), tostring(icon)))
    W(("ART %s | %s"):format(kind, Dump(ns.Style.ART[icon or ""] or "nil")))
end
W("== nearby")
for _, d in ipairs(ns.Sightings.Days() or {}) do W("DAY " .. Dump(ns.Sightings.OnDay(d.start or d))) end

io.write(table.concat(out, "\n"), "\n")
