-- The journal's pages (.claude/ui-refactor-plan.md, decision 4 and 2b):
-- what the book needs to know of each to wire it in. Each page's own file
-- registers it, and the book (UI/Journal/Book.lua) makes a container for
-- every page, builds it, hangs its ribbon, refreshes it as it is turned
-- to and lays the stack beneath for it, all from here. What is drawn by
-- hand round the pages keeps its hand-placed positions and reads only each
-- page's colour and label from here (Journal.Ribbons): the front matter's
-- contents (UI/Journal/Front.lua), the parcel's closed book
-- (UI/Windows/Intro/Torn.lua) and the empty People page's arrow
-- (UI/Journal/Empty.lua). tests/pages.lua fails where a ribbon page has
-- no cut-out in the contents (unless it says contents = false) or no
-- ribbon in the parcel.
--
--   Journal.RegisterPage(key, {
--       order    = 10,   ribbon order, left to right (and the contents'); gaps
--       ribbon   = { colour = "green", label = "Your Diary" },
--                        Style.RIBBONS' cloth and the tooltip's words; nil for
--                        a flyleaf, which has none
--       leaf     = 1,    a ribbon page's place in the stack: n from the
--                        front, -n from the back
--       flyleaf  = 0,    a page without a ribbon, before the stack: 0 the
--                        first leaf, 1 the second
--       leaves   = fn,   optional: function() -> n, a leaf inside the page
--                        (People: the selected person's entry), or nil
--       contents = false,  optional: a ribbon page the front matter's
--                        contents leave out on purpose (the settings)
--       buildOrder = 10, when it is built as the book is made, among the
--                        others; see below
--       build    = function(container, panel),  once, as the book is made
--       refresh  = function(),  optional: each time it is turned to
--   })
--
-- Pages register as their files load, before the book is first made; the
-- book is made once, so a page registered or removed after that is refused.
--
-- The build order is not the ribbon order, and is kept apart from it on
-- purpose: the book has always built People's pieces first, then the
-- frontispiece, the front matter, Your Diary, Recently nearby and the
-- settings, and every frame, font and event handler a page makes is
-- numbered and run in that order (the golden dump, tests/golden/). So each
-- page says its turn (buildOrder); those that say none come after, as they
-- registered. Pages() is by `order`, BuildOrder() by buildOrder.
--
-- The containers are made by key, alphabetically (ByKey()): the order the
-- golden dump has always seen them made in, its `pairs` walking keys sorted.

local addonName, ns = ...

local J = ns.UI.Journal

-- Built pages after those that say their turn, as they registered.
local LATE = 1000

local ribbons, byKey, buildOrder = {}, {}, {}

local function Check(key, spec)
    if type(spec.build) ~= "function" then return false, "Journal.RegisterPage: " .. key .. " has no build" end
    for _, field in ipairs({ "refresh", "leaves" }) do
        if spec[field] ~= nil and type(spec[field]) ~= "function" then
            return false, "Journal.RegisterPage: " .. key .. "'s " .. field .. " is not a function"
        end
    end
    if spec.buildOrder ~= nil and type(spec.buildOrder) ~= "number" then
        return false, "Journal.RegisterPage: " .. key .. "'s buildOrder is not a number"
    end
    if spec.ribbon ~= nil then
        local r = spec.ribbon
        if type(r) ~= "table" or type(r.colour) ~= "string" or type(r.label) ~= "string" then
            return false, "Journal.RegisterPage: " .. key .. "'s ribbon is not { colour, label }"
        end
        if type(spec.leaf) ~= "number" or spec.leaf == 0 or spec.leaf % 1 ~= 0 or spec.flyleaf ~= nil then
            return false, "Journal.RegisterPage: " .. key .. " has a ribbon, so a leaf (n or -n) and no flyleaf"
        end
    elseif spec.flyleaf ~= 0 and spec.flyleaf ~= 1 or spec.leaf ~= nil then
        return false, "Journal.RegisterPage: " .. key .. " has no ribbon, so a flyleaf (0 or 1) and no leaf"
    end
    return true
end

local function BuildBefore(a, b)
    local oa, ob = a.buildOrder or LATE, b.buildOrder or LATE
    if oa ~= ob then return oa < ob end
    return a.seq < b.seq
end

-- Everything read from the pages, sorted again as one registers or goes:
-- the ribbons in their order, the pages by key and in their build order.
local function Changed(registry)
    for i = #ribbons, 1, -1 do ribbons[i] = nil end
    for i = #byKey, 1, -1 do byKey[i] = nil end
    for i = #buildOrder, 1, -1 do buildOrder[i] = nil end
    for _, spec in ipairs(registry:Ordered()) do
        if spec.ribbon then
            ribbons[#ribbons + 1] = { key = spec.key, colour = spec.ribbon.colour, label = spec.ribbon.label,
                page = spec }
        end
        byKey[#byKey + 1] = spec
        buildOrder[#buildOrder + 1] = spec
    end
    table.sort(byKey, function(a, b) return a.key < b.key end)
    table.sort(buildOrder, BuildBefore)
end

local pages = ns.Registry.New({
    what = "Journal.RegisterPage(key, { order, ribbon = { colour, label }, leaf or flyleaf, build, ... })",
    order = "order",
    default = 100,
    check = Check,
    changed = Changed,
})

local function NotMade(what)
    assert(not J.journal, "Journal." .. what .. ": the book is already made; pages register as their files load")
end

function J.RegisterPage(key, spec)
    NotMade("RegisterPage")
    return pages:Add(key, spec)
end

-- Takes a page out again (the tests' own pages).
function J.RemovePage(key)
    NotMade("RemovePage")
    return pages:Remove(key)
end

-- A page's spec, or nil.
function J.Page(key)
    return pages:Get(key)
end

-- Every page, by order (the flyleaves, which give none, last).
function J.Pages()
    return pages:Ordered()
end

-- The ribbon pages, left to right: { key, colour, label, page = spec }.
-- The same table every call, kept up to date in place.
function J.Ribbons()
    return ribbons
end

-- Every page by key, alphabetically: the order their containers are made in.
function J.PagesByKey()
    return byKey
end

-- Every page in the order the book builds them.
function J.BuildOrder()
    return buildOrder
end

-- How many pages lie in the stack (the ribbon pages), and how many before
-- it (the flyleaves).
function J.StackCounts()
    local stacked, flyleaves = 0, 0
    for _, spec in ipairs(pages:Ordered()) do
        if spec.flyleaf then flyleaves = flyleaves + 1 else stacked = stacked + 1 end
    end
    return stacked, flyleaves
end
