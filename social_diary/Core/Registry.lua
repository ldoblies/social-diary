-- One way to keep a registry: the specs a feature hands in by name, in
-- their order, so each list a feature plugs into (a plate's marks and
-- passes, the margin's kinds, the caption's words, the entry's prose)
-- stores, sorts, replaces and takes out the same way rather than each with
-- its own copy of the loop (.claude/ui-refactor-plan.md, decision 7, 2d).
--
--   local marks = ns.Registry.New({
--       what = "Plate.RegisterMark(kind, { draw = ... })",  -- the assert's message
--       key = "kind",            -- the spec field the key is written into
--       order = "order",         -- the spec field it sorts by; none: as registered
--       default = 100,           -- written into spec[order] where it is nil
--       check = function(key, spec) return type(spec.draw) == "function" end,
--       changed = function(registry) ... end,  -- after each Add, Core, Remove
--   })
--
-- Add(key, spec)     a feature's entry. Registering a key again replaces
--                    the earlier one, which moves to the back of its equals
--                    (as if it had just registered). The spec is the
--                    caller's own table and is written into, as every
--                    registry here always did: spec[key] the key, spec.seq
--                    its turn (1, 2, ... in the order the features
--                    registered), spec[order] the default where it had none.
--                    Refused (an error with `what`, or the message `check`
--                    returns second) where key is not a string, spec not a
--                    table, or `check` says no; and where the key is a core
--                    entry's ("<name>: a kind may not be called <key>").
-- Core(key, spec, rank)   the diary's own entry, written in the file that
--                    owns the registry: it stands among the features' in
--                    Ordered(), but is not one of them (not in `specs` nor
--                    `list`, which the tests read as "the registered
--                    kinds"). `rank` says where it goes among equal orders:
--                    -1 before every feature's (the margin's people, the
--                    prose's own paragraphs), 1 after (the deaths on the
--                    road). It is how "core first at equal numbers" is
--                    said once, as data, rather than as an `if` in each
--                    loop that draws.
-- Remove(key)        takes a feature's entry out; nothing where none.
-- Get(key)           a feature's spec, or nil.
-- Ordered()          every entry, core included, by order, then rank, then
--                    the turn it registered in. The same table every call,
--                    sorted again only by Add, Core and Remove (plates draw
--                    often; registering happens as the files load), so a
--                    hot loop may ipairs it freely.
-- specs, list        the features' entries by key, and in Ordered()'s
--                    order without the core's: tables the registry keeps
--                    up to date in place, for a module to publish as it
--                    always has (Plate.MARKS and MARK_ORDER, ...).

local addonName, ns = ...

local Registry = {}
Registry.__index = Registry
ns.Registry = Registry

function Registry.New(opts)
    assert(type(opts) == "table" and type(opts.what) == "string", "Registry.New({ what, ... })")
    local self = setmetatable({
        what = opts.what,
        -- The name the refusals give: what's call without its arguments.
        name = opts.what:match("^[%w_%.:]+") or opts.what,
        keyField = opts.key or "key",
        orderField = opts.order,
        default = opts.default,
        check = opts.check,
        changed = opts.changed,
        specs = {},
        list = {},
        core = {},
        all = {},
        -- Each entry's place among its equals: { rank, seq }. Kept here,
        -- not on the spec, so a core entry's table carries nothing it did
        -- not bring.
        place = {},
        turns = 0,     -- the features' turns (spec.seq)
        coreTurns = 0, -- the core's, among themselves
    }, Registry)
    local place, field = self.place, self.orderField
    function self.before(a, b)
        if field then
            local oa, ob = a[field], b[field]
            if oa ~= ob then return oa < ob end
        end
        local pa, pb = place[a], place[b]
        if pa[1] ~= pb[1] then return pa[1] < pb[1] end
        return pa[2] < pb[2]
    end
    return self
end

-- Sorts every entry again into `all`, and the features' into `list`, both
-- in place: a module that published them keeps the same tables.
local function Sort(self)
    local all, list = self.all, self.list
    for i = #all, 1, -1 do all[i] = nil end
    for _, spec in pairs(self.core) do all[#all + 1] = spec end
    for _, spec in pairs(self.specs) do all[#all + 1] = spec end
    table.sort(all, self.before)
    for i = #list, 1, -1 do list[i] = nil end
    for _, spec in ipairs(all) do
        if self.place[spec][1] == 0 then list[#list + 1] = spec end
    end
    if self.changed then self.changed(self) end
end

function Registry:Add(key, spec)
    local ok, why = type(key) == "string" and type(spec) == "table", nil
    if ok and self.check then ok, why = self.check(key, spec) end
    assert(ok, why or self.what)
    assert(not self.core[key], self.name .. ": a kind may not be called " .. tostring(key))
    local old = self.specs[key]
    if old then self.place[old] = nil end
    self.turns = self.turns + 1
    spec[self.keyField], spec.seq = key, self.turns
    if self.orderField and spec[self.orderField] == nil then spec[self.orderField] = self.default end
    self.specs[key] = spec
    self.place[spec] = { 0, self.turns }
    Sort(self)
    return spec
end

function Registry:Core(key, spec, rank)
    assert(type(key) == "string" and type(spec) == "table" and (rank == -1 or rank == 1),
        self.name .. ": a core entry is (key, spec, -1 or 1)")
    self.coreTurns = self.coreTurns + 1
    spec[self.keyField] = key
    if self.orderField and spec[self.orderField] == nil then spec[self.orderField] = self.default end
    self.core[key] = spec
    self.place[spec] = { rank, self.coreTurns }
    Sort(self)
    return spec
end

function Registry:Remove(key)
    local old = self.specs[key]
    if not old then return nil end
    self.specs[key] = nil
    self.place[old] = nil
    Sort(self)
    return old
end

function Registry:Get(key)
    return self.specs[key]
end

function Registry:Ordered()
    return self.all
end
