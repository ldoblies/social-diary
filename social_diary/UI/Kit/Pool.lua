-- A pool: what a drawing needs many of (textures, font strings, notes),
-- made as it is first needed and handed out in turn, so a page drawn again
-- and again makes nothing new once it has drawn its busiest. pool:Begin()
-- before a drawing, pool:Next() for each one it wants (made by `make`
-- where the pool has none left, and shown), pool:Finish() after it: the
-- ones not handed out this time are hidden. The pool is its own list
-- (pool[1], pool[2], ... in the order they were made) and `pool.used` is
-- how many this drawing has had, which the margin rolls back by hand to
-- try a note and take it back (UI/Journey/Margin.lua's Mark and Undo).
--
-- The order matters past the look: the same one is handed out again for
-- the same place in the drawing, so a frame keeps its place (and the
-- golden dump's paths stay put, tests/golden/). Used by the right page of
-- Your Diary (UI/Journey/Leaders.lua's Handout: its leaders, dots,
-- headings, captions and every margin kind's notes) and a loose sheet's
-- toolkit (UI/Paper/Sheet.lua's K.Pool, a texture pool on the sheet), once
-- each before. The map plate keeps pools of its own inside its constructor
-- (UI/Journey/Plate.lua, left whole for its own refactor). It makes
-- nothing at load.

local addonName, ns = ...

local Pool = {}
ns.UI.Pool = Pool

-- A pool of what `make()` returns (anything with :Show and :Hide).
function Pool.New(make)
    local pool = { used = 0 }
    function pool:Begin() self.used = 0 end
    function pool:Next()
        self.used = self.used + 1
        local item = self[self.used]
        if not item then
            item = make()
            self[self.used] = item
        end
        item:Show()
        return item
    end
    function pool:Finish()
        for i = self.used + 1, #self do self[i]:Hide() end
    end
    return pool
end
