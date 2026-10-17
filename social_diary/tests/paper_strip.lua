-- The paper strip's card contract (UI/Paper/Strip.lua, the comment over
-- ns.UI.PaperStrip): a card is a strip laid through its hooks, `plan`,
-- `draw`, `again`, `smaller` and `nearest`, using only what that comment
-- lets it (name, picture, under, box, turn, flat, turnsText, overfull;
-- Pad, Least, Paper, WhatLines, Lay, ...). A card built here through the
-- hooks alone pins when each hook is asked, with what, and what the strip
-- does with its answer; and a strip without a card is a person's as it
-- always was.
--
-- The mock measures every string at 6 px a byte and 14 px high.

local T = ...
local Section, Check, Eq = T.Section, T.Check, T.Eq
local ns = T.Boot()

local STRIP, TAPE = ns.UI.PAPER_STRIP.STRIP, ns.UI.PAPER_STRIP.TAPE
local host = CreateFrame("Frame")

-- Where a region was put on its strip (Lay: its middle, from the strip's
-- middle on the screen).
local function At(region)
    local args = region.recorded.points[1].args
    return args[3], args[4]
end

--------------------------------------------------------------------------
Section("a strip without a card")

local plain = ns.UI.PaperStrip(host)
local QUOTE = "a long note about the time we spent fishing off the jetty at Ratchet in the rain"
plain:SetNote({ name = "Bram Redfen", what = "15 min together and a note", quote = QUOTE, seed = "Bram:1" })
local w, h = plain:Layout(20, 300, 160, 40)
Eq(plain.overfull, nil, "a person's strip says it is overfull")
Eq(plain.box[3] .. "x" .. plain.box[4], w .. "x" .. h, "the box is not what it was laid at")
Check(rawget(plain, "Smaller") ~= nil, "a strip has no Smaller of its own for the margin to ask")
local lines = plain.quoteLines
Check(lines >= 2, "the quote is not long enough to give up a line")
Eq(plain:Smaller(), true, "the quote gave up no line")
plain:Layout(20, 300, 160, 40)
Eq(plain.quoteLines, lines - 1, "without a card, Smaller is not the quote's")

-- What a card may ask of it.
local l, t, r, b = plain:Pad()
Eq(table.concat({ l, t, r, b }, ","), table.concat(STRIP.pad, ","), "Pad is not the strip's margins")
local reach = STRIP.pad[1] + 70 + 4 + TAPE.w / 2
Eq(plain:Least(70, 0.8, 4), math.ceil(math.max(reach / 0.8, reach + TAPE.inset)), "Least, with a clearance")
reach = STRIP.pad[1] + 70 + TAPE.w / 2
Eq(plain:Least(70, 0.8), math.ceil(math.max(reach / 0.8, reach + TAPE.inset)), "Least, without one")
Eq(plain:Paper(), STRIP.paper, "the stock as laid is not the strip's")
local shown = plain:WhatLines()
Check(plain.shownLines >= 2, "what happened is not long enough for two lines")
Eq(#shown, plain.shownLines, "WhatLines is not the lines shown")
for i = 1, plain.shownLines do Eq(shown[i], plain.lines[i], "WhatLines' line " .. i) end
local fresh = ns.UI.PaperStrip(host)
Eq(fresh:Paper(), STRIP.paper, "unlaid, the stock is not the strip's")
Eq(#fresh:WhatLines(), 0, "unlaid, a strip shows lines")
local stock = { 1, 0.9, 0.8 }
fresh:SetNote({ name = "", strong = true, size = { 40, 20 }, paper = stock, seed = "tag" })
fresh:Layout(0, 0, 40)
Eq(fresh:Paper(), stock, "a slip of its own stock says the strip's")

-- The look, for what is drawn like a strip without being one.
local LOOK = ns.UI.PAPER_LOOK
for _, key in ipairs({ "paper", "edge", "flatEdge", "shadow", "balance" }) do
    Eq(LOOK[key], STRIP[key], "PAPER_LOOK." .. key)
end
for _, key in ipairs({ "slant", "tint", "alpha", "flatAlpha", "ends", "endAlpha", "line", "shine", "shineAlpha",
    "edge", "edgeAlpha", "flatEdge" }) do
    Eq(LOOK.tape[key], TAPE[key], "PAPER_LOOK.tape." .. key)
end

--------------------------------------------------------------------------
Section("a card through its hooks: plan, draw, again")

-- A card that keeps a picture's room over its name and a room under it,
-- draws a texture in each, and logs every hook asked. `opts`: at (the
-- width to lay at), more (a size draw adds), tall (again while h > room,
-- once), steps (what smaller gives up).
local log = {}
local function Log(...) log[#log + 1] = table.concat({ ... }, " ") end
local opts = {}
local card = {}
local strip = ns.UI.PaperStrip(host, card)
local pic, under = strip:CreateTexture(), strip:CreateTexture()
local note = { name = "Tester", what = "made up for the test", strong = true, seed = "card:1" }
local plans = 0
function card.plan(s, n, width, room, again)
    Log("plan", tostring(s == strip), tostring(n == note), width, tostring(room), tostring(again))
    n.picture = { w = 30, h = opts.small and 10 or 20, gap = 2 }
    n.under = { w = 40, h = 10, gap = 1, after = 2 }
    n.least = opts.least
    s.overfull = width < 100
    plans = plans + 1
    return { n = plans }, opts.at
end
function card.draw(s, plan, w, h)
    Log("draw", tostring(s == strip), plan.n, w, h)
    -- The rooms as laid, drawn in.
    s:Lay(pic, s.picture.lx, s.picture.ly, s.picture.w, s.picture.h)
    s:Lay(under, s.under.lx, s.under.ly, s.under.w, s.under.h)
    if opts.more then return w + opts.more, h + opts.more end
end
function card.again(s, w, h, room)
    Log("again", tostring(s == strip), w, h, tostring(room))
    if opts.tall and room and h > room then
        opts.small = true
        return true
    end
    return false
end
strip:SetNote(note)

-- Once: planned, laid, drawn, asked whether again.
w, h = strip:Layout(10, 20, 160, 500)
Eq(#log, 3, "a laying asked the hooks other than plan, draw, again")
Eq(log[1], "plan true true 160 500 false", "plan's arguments")
Eq(log[2], "draw true 1 " .. w .. " " .. h, "draw's arguments: plan's plan, the size laid")
Eq(log[3], "again true " .. w .. " " .. h .. " 500", "again's arguments")
Eq(strip.overfull, false, "plan's overfull was not kept")
-- The rooms plan asked for, where draw found them.
Eq(strip.picture.w .. "x" .. strip.picture.h, "30x20", "the picture's room is not plan's")
Eq(strip.under.w .. "x" .. strip.under.h, "40x10", "the room under the name is not plan's")
local x, y = At(pic)
Eq(x .. "," .. y, strip.picture.X .. "," .. strip.picture.Y, "draw's picture is not in its room")
x, y = At(under)
Eq(x .. "," .. y, strip.under.X .. "," .. strip.under.Y, "draw's drawing is not in the room under the name")
Check(strip.picture.ly < strip.under.ly, "the picture's room is not over the room under the name")
Eq(strip.box[1] .. "," .. strip.box[2] .. "," .. strip.box[3] .. "," .. strip.box[4],
    "10,20," .. w .. "," .. h, "the box is not as laid")
Check(strip:IsShown(), "the card was drawn on a strip not shown")

-- Narrow: plan's overfull.
log = {}
strip:Layout(10, 20, 80)
Eq(strip.overfull, true, "plan's overfull, narrow")
Eq(log[1], "plan true true 80 nil false", "no room: plan's `room` is nil")

-- Again: too tall for `room`, laid once more, plan told so; asked once.
log = {}
opts.tall = true
w, h = strip:Layout(10, 20, 160, 40)
Eq(#log, 5, "laid again, the hooks asked are not plan, draw, again, plan, draw")
Eq(log[1], "plan true true 160 40 false", "the first laying's plan")
local first = tonumber(log[2]:match("^draw true %d+ %d+ (%d+)$"))
Check(first and first > 40, "the first laying is not too tall for the room")
Check(log[3]:match("^again true %d+ (%d+) 40$") == tostring(first), "again's arguments, too tall: " .. log[3])
Eq(log[4], "plan true true 160 40 true", "the second laying's plan is not told it is again")
Eq(log[5], "draw true " .. plans .. " " .. w .. " " .. h, "the second laying's draw")
Eq(h, first - 10, "laid again, its size is not the second laying's")
Eq(strip.picture.h, 10, "laid again, the picture's room is not the second plan's")
opts.tall, opts.small = nil, nil

-- plan's `at`: the slip laid at that width, not the column's.
opts.least = 200
w = strip:Layout(10, 20, 160)
Eq(w, 160, "a least wider than the column, laid at the column")
opts.at = 120
log = {}
w = strip:Layout(10, 20, 160)
Eq(w, 120, "plan's `at` is not the width it was laid at")
Eq(log[1], "plan true true 160 nil false", "plan is told the column, not `at`")
Eq(log[2], "draw true " .. plans .. " 120 " .. strip.box[4], "draw is told the width laid at")
opts.at, opts.least = nil, nil

-- draw's size: the note's instead, Layout's and the box's.
opts.more = 10
local w0, h0 = strip:Layout(10, 20, 160)
opts.more = nil
local w1, h1 = strip:Layout(10, 20, 160)
Eq(w0 .. "x" .. h0, (w1 + 10) .. "x" .. (h1 + 10), "draw's size is not what Layout returns")
opts.more = 10
strip:Layout(10, 20, 160)
Eq(strip.box[3] .. "x" .. strip.box[4], w0 .. "x" .. h0, "draw's size is not the box's")
opts.more = nil

--------------------------------------------------------------------------
Section("a card through its hooks: smaller, nearest")

-- smaller: the card's, instead of the quote's.
local steps = 2
function card.smaller(s)
    Log("smaller", tostring(s == strip))
    if steps == 0 then return false end
    steps = steps - 1
    return true
end
note.quote = QUOTE
strip:SetNote(note)
strip:Layout(10, 20, 160)
local quoted = strip.quoteLines
Check(quoted >= 2, "the card's quote is not long enough to give up a line")
log = {}
Eq(strip:Smaller(), true, "the card's smaller, first step")
Eq(strip:Smaller(), true, "the card's smaller, second step")
Eq(strip:Smaller(), false, "the card's smaller, nothing left")
Eq(table.concat(log, "/"), "smaller true/smaller true/smaller true", "smaller's arguments")
strip:Layout(10, 20, 160)
Eq(strip.quoteLines, quoted, "with a card's smaller, the quote still gave up a line")
note.quote = nil
strip:SetNote(note)

-- nearest: given the slip's own nearest point, its answer is the strip's.
local twin = ns.UI.PaperStrip(host)
local only = {}
local lone = ns.UI.PaperStrip(host, only)
local same = { name = "Tester", what = "made up for the test", seed = "card:2" }
twin:SetNote(same)
lone:SetNote(same)
twin:Layout(30, 40, 150)
lone:Layout(30, 40, 150)
local asked
function only.nearest(s, px, py, sx, sy)
    asked = { s, px, py, sx, sy }
    return sx + 1, sy - 1
end
local tx, ty = twin:Nearest(400, 10)
local nx, ny = lone:Nearest(400, 10)
Check(asked and asked[1] == lone and asked[2] == 400 and asked[3] == 10, "nearest's strip and point")
Eq(asked[4] .. "," .. asked[5], tx .. "," .. ty, "nearest is not given the slip's own nearest point")
Eq(nx .. "," .. ny, (tx + 1) .. "," .. (ty - 1), "nearest's answer is not the strip's")
-- And a card with no nearest, no draw, no plan lies as a person's strip.
Eq(lone.box[3] .. "x" .. lone.box[4], twin.box[3] .. "x" .. twin.box[4], "a card of no hooks lies otherwise")
