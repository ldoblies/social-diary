-- The page's lifted corner: the bottom corner of the right page turned up,
-- a page turned by it. The introduction's two leaves wear one each: the
-- frontispiece's turns to the front matter (UI/Journal/Frontispiece.lua),
-- the front matter's to Your Diary (UI/Journal/Front.lua).

local addonName, ns = ...

local Style = ns.Style
local FONT = Style.FONT

local BOOK = ns.UI.Journal.BOOK
local BOOK_W = BOOK.BOOK_W

-- The page's lifted corner: how far it lifts, and further under the mouse;
-- the next page seen where it lifts, and the back of this one folded up.
local CORNER = { size = 32, hover = 40, under = { 0.74, 0.62, 0.41 },
    flapLit = { 0.95, 0.89, 0.74 }, flapShade = { 0.84, 0.75, 0.56 }, edge = 0.40 }
-- The open page's outer edge: the stack lies outside it (Style.Book).
local PAGE_RIGHT = BOOK_W - 12

-- The bottom corner of the right page, lifted: the next page shows under
-- it, and the back of this one is folded up over itself. Each is a square
-- with one corner moved onto another, so it draws as a triangle; where
-- the client cannot move a texture's corners, the words alone turn the
-- page. The frontispiece's corner too (UI/Journal/Frontispiece.lua).
function ns.UI.Journal.PageCorner(parent, onTurn)
    local corner = CreateFrame("Button", nil, parent)
    corner:SetPoint("BOTTOMRIGHT", parent, "BOTTOMLEFT", PAGE_RIGHT, 0)

    local under = corner:CreateTexture(nil, "ARTWORK", nil, 0)
    local flap = corner:CreateTexture(nil, "ARTWORK", nil, 1)
    local bends = under.SetVertexOffset ~= nil
    under:SetShown(bends)
    flap:SetShown(bends)
    local VERTEX = Enum and Enum.VertexIndex or {}
    local UL, LR = VERTEX.UpperLeft or 1, VERTEX.LowerRight or 4
    local U, L, S = CORNER.under, CORNER.flapLit, CORNER.flapShade

    -- The fold along the diagonal: a hairline turned to it.
    local edge = corner:CreateTexture(nil, "OVERLAY")
    edge:SetColorTexture(Style.INK[1], Style.INK[2], Style.INK[3], CORNER.edge)
    edge:SetRotation(math.pi / 4)
    edge:SetShown(bends)

    local function Lay(size)
        corner:SetSize(size, size)
        for _, t in ipairs({ under, flap }) do
            t:ClearAllPoints()
            t:SetPoint("BOTTOMRIGHT")
            t:SetSize(size, size)
        end
        if not bends then return end
        -- What lifts: the triangle by the corner, the next page under it.
        under:SetColorTexture(U[1], U[2], U[3], 1)
        under:SetVertexOffset(UL, size, 0)
        -- The flap: the same triangle folded over the diagonal, lit from
        -- the top left.
        Style.Gradient(flap, "HORIZONTAL", { L[1], L[2], L[3], 1 }, { S[1], S[2], S[3], 1 })
        flap:SetVertexOffset(LR, -size, 0)
        edge:SetSize(size * math.sqrt(2), 1)
        edge:SetPoint("CENTER")
    end
    corner.Lay = Lay
    Lay(CORNER.size)

    corner.words = Style.Link(parent, FONT.body, onTurn)
    corner.words:SetText("Turn the page")
    corner.words:SetPoint("BOTTOMRIGHT", parent, "BOTTOMLEFT", PAGE_RIGHT - CORNER.hover - 8, 14)

    corner:SetScript("OnClick", onTurn)
    corner:SetScript("OnEnter", function() Lay(CORNER.hover) end)
    corner:SetScript("OnLeave", function() Lay(CORNER.size) end)
    corner.words:HookScript("OnEnter", function() Lay(CORNER.hover) end)
    corner.words:HookScript("OnLeave", function() Lay(CORNER.size) end)
    return corner
end
