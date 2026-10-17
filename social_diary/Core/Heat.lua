-- Where you see the people in your diary, as a coarse heat map per map.
--
-- Each diary entry's character record carries heat[mapID][cell] = count on a
-- GRID x GRID grid of the map (50 x 50: a cell is roughly 100 yards on a
-- zone the size of Mulgore). A count is added every time "last seen" reads
-- the location again (Characters.Seen, at most once per 15 seconds per
-- person), so time spent near someone -- questing together, a grouped friend
-- checked every 30 seconds -- builds up heat, and a passing sighting leaves a
-- dot.
--
-- Someone is usually added after you met them, so adding them folds in the
-- sightings already kept of them (Heat.Backfill): one count where each row
-- began, the zone-hour's first position (SIG-4). `record.heatFrom` is when
-- that was last done, or when they left the diary: rows from before it are
-- counted already, live or folded in, and are not counted twice.
--
-- Deliberately coarse and unordered: no timestamps, no routes, only counts.
-- The position is the user's own, as everywhere else in the addon. Instances
-- have no coordinates (ns.Where), so they never appear here.

local addonName, ns = ...

local Heat = {}
ns.Heat = Heat

Heat.GRID = 50

local function Cell(x, y)
    local grid = Heat.GRID
    local col = math.max(0, math.min(grid - 1, math.floor(x * grid)))
    local row = math.max(0, math.min(grid - 1, math.floor(y * grid)))
    return row * grid + col
end

-- The centre of a cell, in the map's 0..1 coordinates.
function Heat.CellXY(cell)
    local grid = Heat.GRID
    local row = math.floor(cell / grid)
    local col = cell % grid
    return (col + 0.5) / grid, (row + 0.5) / grid
end

function Heat.Add(record, where)
    if not (record and where and where.mapID and where.x and where.y) then return end

    record.heat = record.heat or {}
    local map = record.heat[where.mapID]
    if not map then
        map = {}
        record.heat[where.mapID] = map
    end

    local cell = Cell(where.x, where.y)
    map[cell] = (map[cell] or 0) + 1
end

-- Folds `guid`'s sighting rows from before `before` into their heat, the
-- ones since record.heatFrom only. Returns how many were added.
function Heat.Backfill(guid, before)
    local record = ns.Characters.Get(guid)
    if not (record and before) then return 0 end
    local from, added = record.heatFrom or -math.huge, 0
    for _, row in ipairs(ns.Sightings.For(guid)) do
        if row.time and row.time >= from and row.time < before and row.mapID and row.x and row.y then
            Heat.Add(record, row)
            added = added + 1
        end
    end
    record.heatFrom = math.max(from, before)
    return added
end

-- The records a view covers: one person, or everyone in the diary (guid nil).
local function Records(guid)
    local list = {}
    if guid then
        local record = ns.Characters.Get(guid)
        if record then list[1] = record end
    else
        for diaryGUID in ns.Diary.Each() do
            local record = ns.Characters.Get(diaryGUID)
            if record then list[#list + 1] = record end
        end
    end
    return list
end

-- Every map with heat, most-visited first: { { mapID, total }, ... }.
function Heat.Maps(guid)
    local totals = {}
    local records = Records(guid)
    for i = 1, #records do
        for mapID, cells in pairs(records[i].heat or {}) do
            for _, count in pairs(cells) do
                totals[mapID] = (totals[mapID] or 0) + count
            end
        end
    end

    local list = {}
    for mapID, total in pairs(totals) do
        list[#list + 1] = { mapID = mapID, total = total }
    end
    table.sort(list, function(a, b)
        if a.total ~= b.total then return a.total > b.total end
        return a.mapID < b.mapID
    end)
    return list
end

-- One map's cells, summed across the records: cells, highest count, total.
function Heat.Cells(guid, mapID)
    local cells, max, total = {}, 0, 0
    local records = Records(guid)
    for i = 1, #records do
        local map = records[i].heat and records[i].heat[mapID]
        if map then
            for cell, count in pairs(map) do
                local sum = (cells[cell] or 0) + count
                cells[cell] = sum
                if sum > max then max = sum end
                total = total + count
            end
        end
    end
    return cells, max, total
end

-- How strongly each cell is drawn, normalised for how much heat the map
-- holds: { { cell, count, t, crowd }, ... }, strongest first.
--
-- `t` (0..1) is the cell's count blended with its neighbours' (SHADE.blend),
-- over the map's strongest blend, so where you lingered stands out from the
-- trail that led there. It is curved by the map's total: the square root
-- while there are a few sightings, so a single one still shows, easing to
-- straight by SHADE.full sightings, so on a busy map a passing sighting stays
-- a trace instead of joining a band of ink. `crowd` is how many marked cells
-- touch the cell, itself included (1..9), for the map to thin overlapping
-- marks by.
local SHADE = { blend = { side = 0.5, corner = 0.25 }, few = 20, full = 200 }

-- The power a map's strengths (0..1 of its strongest) are raised to, for
-- `total` sightings on it: 0.5 up to SHADE.few, 1 from SHADE.full, eased
-- between them by the logarithm.
function Heat.Power(total)
    total = total or 0
    if total <= SHADE.few then return 0.5 end
    return 0.5 + 0.5 * math.min(1, math.log(total / SHADE.few) / math.log(SHADE.full / SHADE.few))
end

function Heat.Shade(cells, total)
    local grid = Heat.GRID
    local list, strongest = {}, 0
    for cell, count in pairs(cells) do
        local row, col = math.floor(cell / grid), cell % grid
        local blend, crowd = count, 1
        for dr = -1, 1 do
            for dc = -1, 1 do
                local r, c = row + dr, col + dc
                if (dr ~= 0 or dc ~= 0) and r >= 0 and r < grid and c >= 0 and c < grid then
                    local near = cells[r * grid + c]
                    if near then
                        blend = blend + near * ((dr == 0 or dc == 0) and SHADE.blend.side or SHADE.blend.corner)
                        crowd = crowd + 1
                    end
                end
            end
        end
        if blend > strongest then strongest = blend end
        list[#list + 1] = { cell = cell, count = count, blend = blend, crowd = crowd }
    end

    local power = Heat.Power(total)
    for i = 1, #list do
        local entry = list[i]
        entry.t = (entry.blend / strongest) ^ power
        entry.blend = nil
    end
    table.sort(list, function(a, b)
        if a.t ~= b.t then return a.t > b.t end
        return a.cell < b.cell
    end)
    return list
end
