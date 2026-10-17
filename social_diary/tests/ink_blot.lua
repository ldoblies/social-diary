-- The map sheet's heat as ink blots, its arithmetic alone (UI/Ink/Blot.lua):
-- the grid with its folds, a lone blot round and the size its field says,
-- every level one layer of ink (no piece overlapping another, no crack
-- between them, even where the outline wobbles or splits at a saddle), no
-- piece across a fold or past the map's edge, the rim inside the blot, and
-- the cap. Pure functions over plain tables; tests/reunion.lua checks the
-- same blots as drawn on the sheet.

local T = ...
local Section, Check, Eq = T.Section, T.Check, T.Eq
local ns = T.Boot()
local Blot = ns.UI.InkBlot

local function Area(q)
    return ((q[1] * q[4] - q[3] * q[2]) + (q[3] * q[6] - q[5] * q[4])
        + (q[5] * q[8] - q[7] * q[6]) + (q[7] * q[2] - q[1] * q[8])) / 2
end

local function Covers(q, x, y)
    for c = 1, 7, 2 do
        local x1, y1 = q[c], q[c + 1]
        local x2, y2 = q[(c + 1) % 8 + 1], q[(c + 2) % 8 + 1]
        if (x2 - x1) * (y - y1) - (y2 - y1) * (x - x1) < 0 then return false end
    end
    return true
end

-- The area the outline's lines enclose (holes count against it).
local function Enclosed(lines)
    local sum = 0
    for _, line in ipairs(lines) do
        local n = #line / 2
        for k = 1, n do
            local j = k % n + 1
            sum = sum + line[2 * k - 1] * line[2 * j] - line[2 * j - 1] * line[2 * k]
        end
    end
    return sum / 2
end

-- How many sample points of the box are covered twice or more, sampled
-- off every grid line.
local function Doubled(quads, x0, y0, x1, y1, every)
    local doubled = 0
    for y = y0 + every * 0.377, y1, every do
        for x = x0 + every * 0.613, x1, every do
            local n = 0
            for _, q in ipairs(quads) do
                if Covers(q, x, y) then n = n + 1 end
            end
            if n > 1 then doubled = doubled + 1 end
        end
    end
    return doubled
end

--------------------------------------------------------------------------
Section("the grid")

local xs, isCut = Blot.Axis(10, 50, 0, 4, { 22.5, 31, 70 })
Eq(xs[1], 10, "the grid does not start at its low end")
Eq(xs[#xs], 50, "the grid does not end at its high end")
local cuts, sorted, close = {}, true, false
for i = 1, #xs do
    if isCut[i] then cuts[#cuts + 1] = xs[i] end
    if i > 1 and xs[i] <= xs[i - 1] then sorted = false end
    if i > 1 and xs[i] - xs[i - 1] < 4 / 3 - 1e-9 then close = true end
end
Check(sorted, "the grid is not in order")
Check(not close, "a sample is crowded against a cut")
Eq(#cuts, 2, "the cuts inside the grid are not marked, or the one outside is")
Eq(cuts[1], 22.5, "a fold is not on the grid")
Eq(cuts[2], 31, "a fold is not on the grid")

Eq(Blot.Weight({ from = 0.25, full = 0.55 }, 0.1), 0, "a faint cell weighs on a deep ink")
Eq(Blot.Weight({ from = 0.25, full = 0.55 }, 0.9), 1, "a strong cell does not weigh all on a deep ink")
Check(math.abs(Blot.Weight({ from = -2 / 3, full = 1 }, 0) - 0.4) < 1e-9, "the faintest cell's pale ink is not 0.4")

--------------------------------------------------------------------------
Section("a lone blot")

-- One bump of sigma 8 px, cut at 0.2: a disc of radius 8 * sqrt(2 ln 5).
local level = { sigma = 8, edge = 0.2, from = 0, full = 1 }
local clip = { 0, 0, 200, 200 }
local lone = Blot.Build({ { x = 101, y = 99, t = 1 } }, { level }, { step = 3, clip = clip, rim = 1.3 })
local quads = lone.levels[1]
local area = 0
for _, q in ipairs(quads) do area = area + Area(q) end
local radius = 8 * math.sqrt(2 * math.log(5))
Check(math.abs(area / (math.pi * radius * radius) - 1) < 0.02,
    ("a lone blot is not the size its field says: %.1f of %.1f px2"):format(area, math.pi * radius * radius))

local ys = Blot.Axis(60, 140, 0, 3)
xs = Blot.Axis(60, 140, 0, 3)
local F = Blot.Field({ { x = 101, y = 99, w = 1 } }, 8, xs, ys)
local lines = Blot.Outline(F, xs, ys, 0.2)
Eq(#lines, 1, "a lone blot's outline is not one line")
Check(lines[1].closed, "a lone blot's outline does not close")
local least, most = math.huge, 0
for k = 1, #lines[1] / 2 do
    local d = math.sqrt((lines[1][2 * k - 1] - 101) ^ 2 + (lines[1][2 * k] - 99) ^ 2)
    least, most = math.min(least, d), math.max(most, d)
end
Check(most - least < 0.15, ("a lone blot is not round: %.2f to %.2f px"):format(least, most))
Check(math.abs(least - radius) < 0.15, ("a lone blot's outline is off its field: %.2f, not %.2f"):format(least, radius))
local fill = 0
for _, q in ipairs(Blot.Fill(F, xs, ys, 0.2)) do fill = fill + Area(q) end
Check(math.abs(fill - Enclosed(lines)) < 1e-6, ("the fill is not the outline's inside: %.4f, %.4f"):format(fill, Enclosed(lines)))

local turned = true
for _, q in ipairs(quads) do
    if Area(q) <= 0 then turned = false end
end
Check(turned, "a piece is not in the screen's turn")
Check(#quads < 60, "a lone blot takes too many pieces: " .. #quads)

-- Its rim lies just inside it, all round, about as wide as asked.
local rimArea, inside = 0, true
for _, q in ipairs(lone.rim) do
    rimArea = rimArea + Area(q)
    for c = 1, 7, 2 do
        if math.sqrt((q[c] - 101) ^ 2 + (q[c + 1] - 99) ^ 2) > radius + 0.2 then inside = false end
    end
end
Check(inside, "the rim reaches outside its blot")
local band = 2 * math.pi * radius * 1.3
Check(rimArea > 0.75 * band and rimArea < 1.25 * band, ("the rim is not about its width: %.1f of %.1f px2"):format(rimArea, band))
Eq(Doubled(lone.rim, 70, 70, 130, 130, 0.25), 0, "the rim's pieces overlap")

--------------------------------------------------------------------------
Section("one layer of ink")

-- Cells of a trail, a cluster and a pair a saddle apart, of every
-- strength, on a grid cut by folds and by the map's edge, wobbling.
local points = {}
for k = 0, 11 do points[#points + 1] = { x = 30 + k * 11, y = 40 + k * 3, t = 0.05 } end
for r = 0, 2 do
    for c = 0, 2 do points[#points + 1] = { x = 120 + c * 11, y = 120 + r * 11, t = 1 - 0.1 * (r + c) } end
end
points[#points + 1] = { x = 60, y = 150, t = 0.7 }
points[#points + 1] = { x = 76, y = 162, t = 0.7 }
points[#points + 1] = { x = 4, y = 190, t = 1 }
local levels = {
    { sigma = 7.8, edge = 0.2, from = -2 / 3, full = 1 },
    { sigma = 6.7, edge = 0.29, from = 0.25, full = 0.55 },
    { sigma = 6.1, edge = 0.52, from = 0.6, full = 0.9 },
}
local cutsX, cutsY = { 51.3, 102, 140.7 }, { 64.5, 123 }
clip = { 0, 10, 180, 195 }
for _, warp in ipairs({ false, { 0.9, 19 } }) do
    local name = warp and "wobbling" or "plain"
    local blot = Blot.Build(points, levels, { step = 2.8, clip = clip, cutsX = cutsX, cutsY = cutsY,
        rim = 1.3, warp = warp or nil })
    for n = 1, 3 do
        local quads = blot.levels[n]
        Check(#quads > 0, ("%s: level %d has no ink"):format(name, n))
        Eq(Doubled(quads, 0, 10, 180, 195, 0.7), 0, ("%s: level %d's pieces overlap"):format(name, n))
        local across, past = false, false
        for _, q in ipairs(quads) do
            local x0, x1 = math.min(q[1], q[3], q[5], q[7]), math.max(q[1], q[3], q[5], q[7])
            local y0, y1 = math.min(q[2], q[4], q[6], q[8]), math.max(q[2], q[4], q[6], q[8])
            for _, c in ipairs(cutsX) do
                if x0 < c - 1e-9 and x1 > c + 1e-9 then across = true end
            end
            for _, c in ipairs(cutsY) do
                if y0 < c - 1e-9 and y1 > c + 1e-9 then across = true end
            end
            if x0 < clip[1] or x1 > clip[3] or y0 < clip[2] or y1 > clip[4] then past = true end
        end
        Check(not across, ("%s: a piece of level %d lies across a fold"):format(name, n))
        Check(not past, ("%s: a piece of level %d lies past the map's edge"):format(name, n))
    end
    -- No cracks: the pieces add up to what the outline encloses, where
    -- the blots lie clear of the map's edge.
    local inner = { 20, 25, 175, 185 }
    local inPoints = {}
    for _, p in ipairs(points) do
        if p.x > 40 and p.y < 180 then inPoints[#inPoints + 1] = { x = p.x, y = p.y, w = Blot.Weight(levels[1], p.t) } end
    end
    local gx = Blot.Axis(inner[1], inner[3], 0, 2.8, cutsX)
    local gy = Blot.Axis(inner[2], inner[4], 0, 2.8, cutsY)
    local field = Blot.Field(inPoints, levels[1].sigma, gx, gy, warp or nil)
    local _, gxCut = Blot.Axis(inner[1], inner[3], 0, 2.8, cutsX)
    local sum = 0
    for _, q in ipairs(Blot.Fill(field, gx, gy, levels[1].edge, gxCut)) do sum = sum + Area(q) end
    local outline = Blot.Outline(field, gx, gy, levels[1].edge)
    local closed = true
    for _, line in ipairs(outline) do closed = closed and line.closed end
    Check(closed, name .. ": an outline clear of the edge does not close")
    Check(math.abs(sum - Enclosed(outline)) < 1e-6,
        ("%s: the pieces do not add up to the outline's inside: %.4f, %.4f"):format(name, sum, Enclosed(outline)))
end

-- A saddle: two bumps whose fields only just meet between them, joined
-- through it or not, either way without overlap and adding up.
for _, gap in ipairs({ 20, 22.5, 25 }) do
    local gx, gy = Blot.Axis(0, 80, 0, 2.5), Blot.Axis(0, 60, 0, 2.5)
    local field = Blot.Field({ { x = 40 - gap / 2, y = 30, w = 1 }, { x = 40 + gap / 2, y = 31.3, w = 1 } }, 6, gx, gy)
    local quads = Blot.Fill(field, gx, gy, 0.3)
    Eq(Doubled(quads, 0, 0, 80, 60, 0.4), 0, "pieces overlap at a saddle " .. gap .. " px apart")
    local sum = 0
    for _, q in ipairs(quads) do sum = sum + Area(q) end
    local outline = Blot.Outline(field, gx, gy, 0.3)
    Check(math.abs(sum - Enclosed(outline)) < 1e-6, "the pieces do not add up at a saddle " .. gap .. " px apart")
end

--------------------------------------------------------------------------
Section("the cap")

local many = {}
for k = 1, 400 do
    many[k] = { x = 10 + (k * 37) % 520, y = 10 + (k * 53) % 340, t = (k % 7) / 6 }
end
local capped = Blot.Build(many, levels, { step = 2.8, clip = { 0, 0, 540, 360 }, rim = 1.3, cap = 1400 })
Check(capped.count <= 1400, "a crowded map passed its cap: " .. capped.count)
Check(capped.step > 2.8, "a crowded map was not traced coarser")
local free = Blot.Build({ { x = 50, y = 50, t = 1 } }, levels, { step = 2.8, clip = { 0, 0, 540, 360 }, rim = 1.3, cap = 1400 })
Eq(free.step, 2.8, "a lone blot was traced coarser")
