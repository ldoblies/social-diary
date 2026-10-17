-- The registry helper (Core/Registry.lua) on its own: the plates' marks and
-- passes, the margin's kinds and the caption's and prose's words all keep
-- their entries in one, so what it promises is checked here once, with
-- made-up keys, and each registry's own order in its own tests
-- (journey_ui, killer_card, margin_caption, kinds).

local T = ...
local Section, Check, Eq = T.Section, T.Check, T.Eq
local ns = T.Boot()
local Registry = ns.Registry

local function Keys(list, field)
    local out = {}
    for _, spec in ipairs(list) do out[#out + 1] = tostring(spec[field or "key"]) end
    return table.concat(out, " ")
end

-- The error a call raises, without the file and line assert puts first,
-- or nil where it went through.
local function Refused(fn, ...)
    local ok, err = pcall(fn, ...)
    if ok then return nil end
    return (tostring(err):gsub("^[^:]*:%d+: ", ""))
end

--------------------------------------------------------------------------
Section("an order, its default, and the turn at equal orders")

do
    local reg = Registry.New({ what = "Test.Register(key, spec)", order = "order", default = 100 })
    local c = reg:Add("c", { order = 30 })
    reg:Add("late", {})
    reg:Add("a", { order = 10 })
    reg:Add("b", { order = 30 })
    reg:Add("first", { order = 30 })
    Eq(Keys(reg:Ordered()), "a c b first late", "by order, then as they registered")
    Eq(Keys(reg.list), "a c b first late", "the published list")
    Eq(reg:Get("late").order, 100, "the default is not written into the spec")
    Check(reg:Get("c") == c and reg.specs.c == c, "a spec not kept by its key")
    Eq(c.key, "c", "the key is not written into the spec")
    Eq(c.seq, 1, "the first to register is not turn 1")
    Eq(reg:Get("first").seq, 5, "the fifth to register is not turn 5")
    Eq(reg:Get("nobody"), nil, "a key nobody registered")

    -- The key may go in another field (a plate's marks are by `kind`).
    local kinds = Registry.New({ what = "Test.Kind(kind, spec)", key = "kind", order = "at" })
    local spec = kinds:Add("pouch", { at = 5 })
    Eq(spec.kind, "pouch", "the key not written under the registry's field")
    Eq(spec.key, nil, "the key written under `key` as well")
end

--------------------------------------------------------------------------
Section("registering a key again replaces it, at the back of its equals")

do
    local reg = Registry.New({ what = "Test.Register(key, spec)", order = "order", default = 100 })
    local old = reg:Add("a", { order = 20 })
    reg:Add("b", { order = 20 })
    reg:Add("c", { order = 20 })
    local new = reg:Add("a", { order = 20, new = true })
    Eq(Keys(reg:Ordered()), "b c a", "the replaced key not moved behind its equals")
    Check(reg:Get("a") == new and reg:Get("a") ~= old, "the earlier spec kept")
    Eq(#reg:Ordered(), 3, "the earlier spec still in the order")
    Eq(new.seq, 4, "the new spec's turn")
    -- The same table again (a test puts a feature's pass back so).
    reg:Add("b", reg:Get("b"))
    Eq(Keys(reg:Ordered()), "c a b", "the same spec registered again not at the back")
    -- A new order sorts it into its new place.
    reg:Add("c", { order = 5 })
    Eq(Keys(reg:Ordered()), "c a b", "a replaced key not in its new order")
end

--------------------------------------------------------------------------
Section("taking a key out")

do
    local changed = 0
    local reg = Registry.New({ what = "Test.Register(key, spec)", order = "order", default = 100,
        changed = function() changed = changed + 1 end })
    reg:Add("a", { order = 1 })
    local b = reg:Add("b", { order = 2 })
    reg:Add("c", { order = 3 })
    Eq(reg:Remove("b"), b, "Remove does not give back what it took out")
    Eq(Keys(reg:Ordered()), "a c", "the key taken out still in the order")
    Eq(Keys(reg.list), "a c", "the key taken out still in the list")
    Eq(reg:Get("b"), nil, "the key taken out still found")
    Eq(reg.specs.b, nil, "the key taken out still published")
    local before = changed
    Eq(reg:Remove("b"), nil, "taking out a key twice")
    Eq(reg:Remove("nobody"), nil, "taking out a key nobody registered")
    Eq(changed, before, "nothing taken out, and the registry says it changed")
    reg:Add("b", { order = 2 })
    Eq(Keys(reg:Ordered()), "a b c", "a key back in after it left")
end

--------------------------------------------------------------------------
Section("the order is kept, and the same table every time")

do
    local reg = Registry.New({ what = "Test.Register(key, spec)", order = "order", default = 100 })
    local ordered, list = reg:Ordered(), reg.list
    reg:Add("b", { order = 2 })
    Check(reg:Ordered() == ordered and reg:Ordered() == reg:Ordered(), "Ordered() not the same table each call")
    reg:Add("a", { order = 1 })
    Check(reg:Ordered() == ordered and reg.list == list, "a new key made new tables (published ones would go stale)")
    Eq(Keys(ordered), "a b", "the kept table not sorted again after an Add")
    Eq(Keys(list), "a b", "the kept list not sorted again after an Add")
    reg:Remove("a")
    Eq(Keys(ordered), "b", "the kept table not sorted again after a Remove")
    Eq(#list, 1, "the kept list not emptied of what left")
    -- A spec's order is read as it registers, not each time it is asked
    -- for: changed after, the order stays until the next Add or Remove.
    reg:Add("c", { order = 3 })
    reg:Get("c").order = 0
    Eq(Keys(reg:Ordered()), "b c", "the order sorted again without an Add or Remove")
    reg:Add("d", { order = 4 })
    Eq(Keys(reg:Ordered()), "c b d", "the order not sorted again with the next Add")
end

--------------------------------------------------------------------------
Section("what a registry refuses, and why")

do
    local reg = Registry.New({ what = "Test.Register(key, { draw })", order = "order", default = 100,
        check = function(key, spec)
            if key == "taken" then return false, "Test.Register: taken is taken" end
            return type(spec.draw) == "function"
        end })
    local fn = function() end
    Eq(Refused(reg.Add, reg, "a", {}), "Test.Register(key, { draw })", "a spec the check refuses")
    Eq(Refused(reg.Add, reg, 1, { draw = fn }), "Test.Register(key, { draw })", "a key that is not a string")
    Eq(Refused(reg.Add, reg, "a", "draw"), "Test.Register(key, { draw })", "a spec that is not a table")
    Eq(Refused(reg.Add, reg, "taken", { draw = fn }), "Test.Register: taken is taken", "the check's own message")
    Eq(reg:Get("a"), nil, "a refused spec registered anyway")
    Eq(#reg:Ordered(), 0, "a refused spec in the order")
    Eq(Refused(reg.Add, reg, "a", { draw = fn }), nil, "a good spec refused")
    reg:Core("own", { order = 1 }, -1)
    Eq(Refused(reg.Add, reg, "own", { draw = fn }), "Test.Register: a kind may not be called own",
        "a feature took a core entry's key")
    Eq(Refused(reg.Core, reg, "flat", {}, 0), "Test.Register: a core entry is (key, spec, -1 or 1)",
        "a core entry with no side to stand on")
    Check(Refused(Registry.New, {}) ~= nil, "a registry with no message for its refusals")
end

--------------------------------------------------------------------------
Section("the changed callback")

do
    local calls, seen = {}, nil
    local reg
    reg = Registry.New({ what = "Test.Register(key, spec)", order = "order", default = 100,
        changed = function(r)
            seen = r
            calls[#calls + 1] = Keys(reg:Ordered())
        end })
    reg:Core("own", { order = 50 }, 1)
    reg:Add("a", { order = 10 })
    reg:Add("a", { order = 60 })
    reg:Remove("a")
    Eq(table.concat(calls, " | "), "own | a own | own a | own", "changed not asked after each change, sorted")
    Check(seen == reg, "changed not given its registry")
end

--------------------------------------------------------------------------
Section("the core's entries: first or last at their order, never published")

do
    local reg = Registry.New({ what = "Test.Register(key, spec)", order = "order", default = 100 })
    reg:Add("before", { order = 10 })
    reg:Add("tie", { order = 20 })
    reg:Core("people", { order = 20 }, -1)
    reg:Core("road", { order = 20 }, 1)
    reg:Core("doors", { order = -math.huge }, -1)
    reg:Add("tie2", { order = 20 })
    reg:Add("after", { order = 30 })
    reg:Core("more", { order = 20 }, -1)
    Eq(Keys(reg:Ordered()), "doors before people more tie tie2 road after",
        "core entries not first (-1) or last (1) among their equals, in their own turn")
    Eq(Keys(reg.list), "before tie tie2 after", "the published list holds the core's entries")
    Eq(reg:Get("people"), nil, "a core entry found as a feature's")
    Eq(reg.specs.road, nil, "a core entry published as a feature's")
    Eq(reg:Remove("road"), nil, "a core entry taken out as a feature's")
    Eq(#reg:Ordered(), 8, "a core entry gone")
    local own = { order = 5 }
    reg:Core("own", own, 1)
    Eq(own.key, "own", "the core entry's key not written")
    Eq(own.seq, nil, "the core entry given a feature's turn")
    Eq(reg:Add("next", { order = 99 }).seq, 5, "the core's entries counted among the features' turns")
end

--------------------------------------------------------------------------
Section("a registry with no order: as they registered")

do
    local reg = Registry.New({ what = "Test.Register(key, spec)" })
    reg:Add("b", { at = 1 })
    reg:Add("a", { at = 2 })
    reg:Add("c", {})
    Eq(Keys(reg:Ordered()), "b a c", "not in the order they registered")
    reg:Add("b", {})
    Eq(Keys(reg:Ordered()), "a c b", "a key registered again not at the end")
    Eq(reg:Get("c").order, nil, "an order written where the registry has none")
end
