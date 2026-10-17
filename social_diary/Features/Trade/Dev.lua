-- Trade's part of /sd testdata (Dev/TestData.lua, TestData.Register):
-- Tester's three trades, linen to a stranger six days ago, a green staff
-- yesterday, and jerky with the blue just now. Development tooling: listed
-- in the TOC's do-not-package block, and left out by .pkgmeta.
--
-- Each trade lands where capture would have written it among the script's
-- own rows, so Tester's rows keep their order: the first at the "traded"
-- beat (its moment, before the add), the others at "tester", after their
-- session's level-ups. This file loads after Level-ups' Dev.lua (whose
-- level-ups are written at "tester" too) and before Chat's (the TOC), so
-- at both points the trade comes before the whispers about it ("ty!
-- inviting", "omg thank you").

local addonName, ns = ...

local TestData = ns.TestData
local Link = TestData.Link
local MIN = 60

local LINEN = Link(1, 2589, "Linen Cloth")
local JERKY = Link(1, 117, "Tough Jerky")
local STAFF = Link(2, 6505, "Crescent Staff")
-- The blue Tester gave in the last trade, and how long ago (82 min, in
-- today's last session): ns.Trade.GIFT, for any other part of /sd
-- testdata that tells of what came of this trade (it reads it when it
-- writes; this file does not know who does).
local GIFT = { link = Link(3, 6449, "Glowing Lizardscale Cloak"), ago = 82 * MIN }
ns.Trade.GIFT = GIFT

-- Six days ago, with a stranger still.
TestData.Register("beat", function(c)
    if c.at ~= "traded" then return end
    c.Row("trade", c.t, "The Barrens", { context = { given = { { link = LINEN, count = 10 } } } })
end)

TestData.Register("tester", function(c)
    if c.n == 2 then
        -- Yesterday, late in the session: green, so a line of its own.
        c.Row("trade", c.session.startedAt + 150 * MIN, "Stonetalon Mountains",
            { context = { given = { { link = STAFF, count = 1 } } } }, c.session)
    elseif c.n == 4 then
        -- With a blue in it: Tester's gift (GIFT).
        c.Row("trade", c.now - GIFT.ago, "The Barrens",
            { context = { received = { { link = JERKY, count = 5 }, { link = GIFT.link, count = 1 } } } },
            c.session)
    end
end)
