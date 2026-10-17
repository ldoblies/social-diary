-- The turned plane: how what lies on the diary's paper at a slant is put
-- there. Frames cannot turn in the client, only textures and font strings,
-- so a piece of paper is laid out flat about a point and every piece of it
-- is turned with it as it is placed; where the client can move a texture's
-- corners (SetVertexOffset), a piece can be any four-sided shape, and the
-- paper's uneven cut, its tear and its shadow's mitre are quads. Written
-- twice and more before, once a file; here once:
--   Surface.New(owner)  a plane turned about a point of owner's parent:
--                       a paper strip (UI/Paper/Strip.lua) and every card
--                       laid on one. Set, Out, Screen, In, Place, Quad (below)
--   Surface.Corners     a texture's four corners moved onto points on the
--                       screen: the plane's Quad and a loose sheet's facets
--                       (UI/Paper/Sheet.lua), which bend with its mesh
--   Surface.Unbend      a texture's corners put back, before it is placed
--                       square again (one bent, then "Flat paper only")
--   Surface.Turned      a point u, v of something turned about ox, oy
--                       (the box on a find card, Features/Firsts/Card.lua;
--                       a lucky card's slips, Features/Hunts/LuckyCard.lua;
--                       a strip's tape)
--   Surface.Width       a font string measured unbounded
--   Surface.Seed        a number from a string, the same every time: what
--                       a slip turns and tears by
--
-- The arithmetic is the copies', operation for operation and in the same
-- order: the golden dump (tests/golden/) reads the results to many places,
-- and the slips lie where they always did. Where two copies were not the
-- same to the last operation, each stayed with its file, not made one
-- here: a loose sheet's Screen (it drifts with the mesh, and turns a point
-- from the sheet's top left), Place (from a box's top left, with a shadow's
-- offset) and Wrap (words joined by one space, not their own spacing);
-- Style.Quad and the parcel's kit (UI/Windows/Intro/Scene.lua), which put
-- a quad on its bounding box; and the page's leaders (UI/Journey/Leaders.lua),
-- which turn the other way round.
--
-- Pure placing and arithmetic: it makes nothing at load, so its place in
-- the TOC (before the strip) moves no frame.

local addonName, ns = ...

local Surface = {}
ns.UI.Surface = Surface

-- The corners' numbers for SetVertexOffset.
local VERTEX = Enum and Enum.VertexIndex or {}
local UL, LL, UR, LR = VERTEX.UpperLeft or 1, VERTEX.LowerLeft or 2, VERTEX.UpperRight or 3, VERTEX.LowerRight or 4

-- A number from a string, the same every time.
function Surface.Seed(key)
    local seed = 0
    key = tostring(key or "")
    for i = 1, #key do seed = (seed + key:byte(i) * i) % 100003 end
    return seed
end

-- Text measured unbounded: a font string still sized for its last text
-- reports only what fits.
function Surface.Width(text)
    if text.GetUnboundedStringWidth then return text:GetUnboundedStringWidth() or 0 end
    return text:GetStringWidth() or 0
end

-- The point u, v (y down) of something turned by c, s (its turn's cosine
-- and sine) about ox, oy, both y down.
local function Turned(ox, oy, u, v, c, s)
    return ox + u * c + v * s, oy - u * s + v * c
end
Surface.Turned = Turned

-- Puts back the corners of a texture bent before (Corners marks it), or it
-- would keep its old shape.
local function Unbend(region)
    if region.bent then
        region:SetVertexOffset(UL, 0, 0)
        region:SetVertexOffset(LL, 0, 0)
        region:SetVertexOffset(UR, 0, 0)
        region:SetVertexOffset(LR, 0, 0)
        region.bent = nil
    end
end
Surface.Unbend = Unbend

-- Places `region` w by h with its middle where its corners' middle is, on
-- `anchor`'s middle, and moves its corners onto these points on the screen
-- (from that middle, y up): a square about as big bent to them.
local function Corners(region, anchor, w, h, ulx, uly, llx, lly, urx, ury, lrx, lry)
    local mx, my = (ulx + llx + urx + lrx) / 4, (uly + lly + ury + lry) / 4
    region:ClearAllPoints()
    region:SetPoint("CENTER", anchor, "CENTER", mx, my)
    region:SetSize(w, h)
    if region.SetRotation then region:SetRotation(0) end
    region:SetVertexOffset(UL, ulx - (mx - w / 2), uly - (my + h / 2))
    region:SetVertexOffset(LL, llx - (mx - w / 2), lly - (my - h / 2))
    region:SetVertexOffset(UR, urx - (mx + w / 2), ury - (my + h / 2))
    region:SetVertexOffset(LR, lrx - (mx + w / 2), lry - (my - h / 2))
    region.bent = true
end
Surface.Corners = Corners

-- A plane on `owner` (a frame whose middle is the plane's), its points
-- from that middle, y down. plane.Set(turn, cx, cy, bends) lays it: turned
-- `turn` (radians, as SetRotation), its middle at cx, cy of owner's parent
-- (y down), and whether corners move as laid now. Then:
--   Out(lx, ly) → x, y      a point of it on owner's parent (y down)
--   Screen(lx, ly) → X, Y   a point of it on the screen, from owner's
--                           middle, y up (where a frame is set)
--   In(x, y) → lx, ly       a point of owner's parent, turned into it, from
--                           its middle (y down)
--   Place(region, lx, ly, w, h, more)
--                           `region` w by h with its middle at lx, ly,
--                           turned with it and `more`
--   Quad(region, x1, y1, x2, y2, x3, y3, x4, y4) → bool
--                           `region` over four points of it, upper left,
--                           upper right, lower right, lower left: false
--                           where corners cannot move, for the caller to
--                           place a box
-- Each a function of its own (no self), for its user to keep in locals.
function Surface.New(owner)
    local turn, cos, sin, cx, cy, bends = 0, 1, 0, 0, 0, false
    local plane = {}

    function plane.Set(t, x, y, b)
        turn, cos, sin = t, math.cos(t), math.sin(t)
        cx, cy, bends = x, y, b
    end

    local function Out(lx, ly)
        return Turned(cx, cy, lx, ly, cos, sin)
    end

    local function Screen(lx, ly)
        return lx * cos + ly * sin, lx * sin - ly * cos
    end

    function plane.In(x, y)
        local dx, dy = x - cx, y - cy
        return dx * cos - dy * sin, dx * sin + dy * cos
    end

    function plane.Place(region, lx, ly, w, h, more)
        Unbend(region)
        local X, Y = Screen(lx, ly)
        region:ClearAllPoints()
        region:SetPoint("CENTER", owner, "CENTER", X, Y)
        region:SetSize(w, h)
        if region.SetRotation then region:SetRotation(turn + (more or 0)) end
    end

    function plane.Quad(region, x1, y1, x2, y2, x3, y3, x4, y4)
        if not bends then return false end
        local ulx, uly = Screen(x1, y1)
        local urx, ury = Screen(x2, y2)
        local lrx, lry = Screen(x3, y3)
        local llx, lly = Screen(x4, y4)
        local w = math.max(0.1, math.sqrt(((x2 + x3) - (x1 + x4)) ^ 2 + ((y2 + y3) - (y1 + y4)) ^ 2) / 2)
        local h = math.max(0.1, math.sqrt(((x4 + x3) - (x1 + x2)) ^ 2 + ((y4 + y3) - (y1 + y2)) ^ 2) / 2)
        Corners(region, owner, w, h, ulx, uly, llx, lly, urx, ury, lrx, lry)
        return true
    end

    plane.Out, plane.Screen = Out, Screen
    return plane
end
