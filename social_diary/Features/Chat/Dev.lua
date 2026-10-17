-- Chat's part of /sd testdata (Dev/TestData.lua, TestData.Register):
-- Tester's whispers, from the first words with a stranger six days ago to
-- "same time tomorrow?" just now. Development tooling: listed in the TOC's
-- do-not-package block, and left out by .pkgmeta.
--
-- Each line lands where capture would have written it among the script's
-- own rows, so Tester's rows keep their order: the ones between the
-- script's rows at a "beat" (before and after the first trade, as a session
-- begins, at the end), the rest at "tester", after a session's rows. This
-- file loads after Trade's Dev.lua and before Campfire's (the TOC), so
-- the thanks come after the trade, and the first session's lines before
-- the fire sat by with Tester.

local addonName, ns = ...

local TestData = ns.TestData
local MIN = 60

-- A conversation of whispers, 20 s apart from `start`: "<" theirs, ">"
-- yours.
local function Whispers(c, start, zone, session, lines)
    for i, line in ipairs(lines) do
        c.Row(line[1] == ">" and "whisper_out" or "whisper_in", start + i * 20, zone,
            { excerpt = line[2] }, session)
    end
end

TestData.Register("beat", function(c)
    if c.at == "met" then
        -- Six days ago, a stranger still: then the trade, the thanks, and
        -- the add (TLN-8: the add sits above the exchange).
        Whispers(c, c.t, "The Barrens", nil, {
            { "<", "hey, you doing the Kolkar quests too?" },
            { ">", "yeah, want to group?" },
            { "<", "sure, but got any spare linen first?" },
        })
    elseif c.at == "traded" then
        c.Row("whisper_in", c.t + 20, "The Barrens", { excerpt = "ty! inviting" })
    elseif c.at == "began" and c.n == 2 then
        -- Yesterday's session, before the dungeon.
        Whispers(c, c.t + 5 * MIN, "The Barrens", c.session, {
            { ">", "WC after these?" }, { "<", "yes! finding a tank" }, { "<", "Brom is in" },
            { ">", "omw" }, { "<", "summoning stone is south" },
        })
    elseif c.at == "now" then
        c.Row("whisper_in", c.now - 5 * MIN, "Durotar", { excerpt = "same time tomorrow?" })
    end
end)

TestData.Register("tester", function(c)
    local start = c.session.startedAt
    if c.n == 1 then
        Whispers(c, start + 5 * MIN, "The Barrens", c.session, {
            { "<", "centaur over there" }, { ">", "got it" }, { "<", "nice pull" },
            { ">", "need water?" }, { "<", "all good" }, { ">", "next camp" },
        })
    elseif c.n == 2 then
        -- After the green staff changed hands.
        Whispers(c, start + 160 * MIN, "Stonetalon Mountains", c.session, {
            { "<", "omg thank you" }, { ">", "it's an upgrade for you" }, { "<", "gn!" },
        })
    elseif c.n == 3 then
        Whispers(c, start + 10 * MIN, "Razorfen Kraul", c.session, {
            { "<", "careful, patrol" }, { ">", "oom" }, { "<", "drinking" },
        })
    end
end)
