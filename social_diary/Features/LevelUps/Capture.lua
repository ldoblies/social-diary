-- Level-ups capture: someone seen at a higher level than last time, written
-- as a row of its kind (Kind.lua) on them.
--
-- Every reading of a character lands in Characters.Observe (Core/
-- Characters.lua), which keeps their level and tells a rise as
-- SD_LEVEL_ROSE (guid, from, level): on a live reading only (a backfilled
-- one describes the past), never on a first one (nothing to rise from),
-- after the record is updated. The message is dispatched straight away
-- (ns.Fire), so the row is written inside Observe, where it always was.
--
-- A buffer row for anyone, so a stranger's level-ups are already on their
-- profile when they are added (flow 2), and a timeline moment for a diary
-- entry ("Tester is now level 16"). Timed when it is noticed, which while
-- grouped is the moment it happens (UNIT_LEVEL); otherwise the next time
-- they are seen. The user's own characters are not strangers: an alt in a
-- roster (record.isSelf) and the logged-in character get no row.

local addonName, ns = ...

ns.On("SD_LEVEL_ROSE", function(_, guid, from, level)
    local record = ns.Characters.Get(guid)
    if not record or record.isSelf or guid == ns.ownGUID then return end
    ns.Interactions.Add(guid, "level_up", { context = { from = from, level = level } })
end)
