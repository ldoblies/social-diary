-- A zone's map art as the player's own world map shows it, for the sheets
-- and plates that print it (UI/Map/HeatSheet.lua, UI/Journey/Plate.lua).
--
-- A classic zone's base art is only its frame: the mountains round the
-- edge and the neighbours' names, the inside plain parchment. What fills
-- it in is the overlay of each area the character has explored, laid over
-- the base the way Blizzard's MapExplorationPinMixin lays it:
-- C_MapExplorationInfo.GetExploredMapTextures gives each explored area's
-- size and offset in the layer's pixels and its own tiles, row by row. An
-- area's last row and column are cut from a tile only as big as they need,
-- the least power of two from 16 up. Areas drawn only under the mouse
-- (isShownByMouseOver) are left off, as the world map leaves them. Where
-- the character has not been stays the base's plain parchment, unless the
-- revealMap setting ("Always show the whole map") asks for every area:
-- those the client does not hand back come from UI/Map/OverlayData.lua,
-- the client's own overlay tables, and are laid the same way.
--
-- Nothing here touches WorldMapFrame, so there is nothing to taint.

local addonName, ns = ...

local MapArt = {}
ns.UI.MapArt = MapArt

-- The least power of two from 16 up that holds `pixels`.
local function FileSize(pixels)
    local size = 16
    while size < pixels do size = size * 2 end
    return size
end

-- An area's tiles, as pieces (see MapArt.For), onto `pieces`: AW by AH
-- at x, y, its files row by row.
local function AddArea(pieces, AW, AH, x, y, files, TW, TH)
    local wide, tall = math.ceil(AW / TW), math.ceil(AH / TH)
    for j = 1, tall do
        local h = j < tall and TH or AH - (tall - 1) * TH
        local fh = j < tall and TH or FileSize(h)
        for k = 1, wide do
            local file = files[(j - 1) * wide + k]
            if file then
                local w = k < wide and TW or AW - (wide - 1) * TW
                pieces[#pieces + 1] = { file = file, explored = true,
                    x = x + (k - 1) * TW, y = y + (j - 1) * TH,
                    w = w, h = h, fw = k < wide and TW or FileSize(w), fh = fh }
            end
        end
    end
end

-- The areas' tiles onto `pieces`: the explored ones the client hands back,
-- and with `all` every other one the map has. Returns how many areas.
local function AddAreas(pieces, mapID, TW, TH, all)
    local Explored = C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures
    local seen, count = {}, 0
    for _, area in ipairs(Explored and Explored(mapID) or {}) do
        local files, AW, AH = area.fileDataIDs, area.textureWidth, area.textureHeight
        if files and not area.isShownByMouseOver and AW and AW > 0 and AH and AH > 0 then
            seen[AW .. ":" .. AH .. ":" .. area.offsetX .. ":" .. area.offsetY] = true
            AddArea(pieces, AW, AH, area.offsetX, area.offsetY, files, TW, TH)
            count = count + 1
        end
    end
    local data = all and ns.UI.MapOverlayData and ns.UI.MapOverlayData[mapID]
    for _, area in ipairs(data or {}) do
        local AW, AH, x, y, files = area[1], area[2], area[3], area[4], area[5]
        if not seen[AW .. ":" .. AH .. ":" .. x .. ":" .. y] then
            AddArea(pieces, AW, AH, x, y, files, TW, TH)
            count = count + 1
        end
    end
    return count
end

-- The map's art layer and its pieces, or nil when the API or the art is
-- missing. A piece is one texture file over x..x+w, y..y+h of the layer's
-- pixels, the file `fw` by `fh` of them; the base's tiles come first, then
-- the areas' (`explored`), and then how many areas. `all` is every area,
-- explored or not (the revealMap setting by default).
function MapArt.For(mapID, all)
    if all == nil then all = ns.Setting("revealMap") == true end
    if not (C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures) then return nil end
    local layers = C_Map.GetMapArtLayers(mapID)
    local layer = layers and layers[1]
    if not layer or not layer.layerWidth or layer.layerWidth <= 0 then return nil end
    local textures = C_Map.GetMapArtLayerTextures(mapID, 1)
    if not textures or #textures == 0 then return nil end

    local TW, TH = layer.tileWidth, layer.tileHeight
    local cols, rows = math.ceil(layer.layerWidth / TW), math.ceil(layer.layerHeight / TH)
    local pieces = {}
    for row = 1, rows do
        for col = 1, cols do
            local file = textures[(row - 1) * cols + col]
            if file then
                pieces[#pieces + 1] = { file = file, x = (col - 1) * TW, y = (row - 1) * TH,
                    w = TW, h = TH, fw = TW, fh = TH }
            end
        end
    end
    local areas = AddAreas(pieces, mapID, TW, TH, all)
    return layer, pieces, areas
end

-- The part of the art shown, in the layer's pixels: x0, y0, x1, y1. A
-- number is the old symmetric crop, that share of the edge cut all round; a
-- table is a window { x0, y0, x1, y1 } (a plate's close-up, JRN-21).
function MapArt.Window(layer, window)
    local LW, LH = layer.layerWidth, layer.layerHeight
    if type(window) == "table" then return window[1], window[2], window[3], window[4] end
    local crop = window or 0
    return crop * LW, crop * LH, (1 - crop) * LW, (1 - crop) * LH
end

-- Prints the pieces into the box mx, my, mw (its height follows) on a loose
-- sheet, showing `window` of the art (MapArt.Window), cut along the mesh
-- (`Split`, `Bend`, UI/Paper/Sheet.lua), each piece taking its part of its
-- file and its facet's light on the `tint`. The base's tiles come from
-- `tiles`, the explored areas' from `explored`, a pool drawn over it.
-- `open`: printed past the sheet's edge too (Split's `open`), where a
-- plate's picture is drawn round its window. Returns how many of each
-- were printed.
function MapArt.Print(layer, pieces, window, mx, my, mw, tint, K, tiles, explored, open)
    local Split, Bend = K.Split, K.Bend
    -- The part of the art shown, in its pixels, and its scale.
    local x0, y0, x1, y1 = MapArt.Window(layer, window)
    local scale = mw / (x1 - x0)
    local counts = { tiles = 0, explored = 0 }
    for _, p in ipairs(pieces) do
        local ix0, ix1 = math.max(p.x, x0), math.min(p.x + p.w, x1)
        local iy0, iy1 = math.max(p.y, y0), math.min(p.y + p.h, y1)
        if ix1 > ix0 and iy1 > iy0 then
            local kind = p.explored and "explored" or "tiles"
            local pool = p.explored and explored or tiles
            counts[kind] = counts[kind] + 1
            local sx0, sy0 = mx + (ix0 - x0) * scale, my + (iy0 - y0) * scale
            local sx1, sy1 = mx + (ix1 - x0) * scale, my + (iy1 - y0) * scale
            Split(sx0, sy0, sx1, sy1, function(a, b, c, d, light)
                local piece = pool:Next()
                piece:SetTexture(p.file)
                local px0, px1 = x0 + (a - mx) / scale, x0 + (c - mx) / scale
                local py0, py1 = y0 + (b - my) / scale, y0 + (d - my) / scale
                piece:SetTexCoord((px0 - p.x) / p.fw, (px1 - p.x) / p.fw, (py0 - p.y) / p.fh, (py1 - p.y) / p.fh)
                piece:SetVertexColor(tint[1] * light, tint[2] * light, tint[3] * light)
                Bend(piece, a, b, c, d, true)
            end, open)
        end
    end
    return counts.tiles, counts.explored
end
