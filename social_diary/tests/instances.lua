-- Instance visits (INS-1): ids, who was in them, and forgetting (PRV-3).
-- How they show on the timeline is in timeline.lua.

local T = ...
local mock, F = T.mock, T.F
local Section, Check, Eq = T.Section, T.Check, T.Eq
local ns = T.Boot()
local Instances = ns.Instances

local A, B = F.STRANGER.guid, F.GARRICK.guid

local function Member(guid, first)
    return { guid = guid, first = first }
end

--------------------------------------------------------------------------
Section("visits get ids from meta.nextVisitId")

Eq(ns.db.meta.nextVisitId, 1, "nextVisitId is not in the schema's defaults")

local wc = Instances.New({ name = "Wailing Caverns", startedAt = 100, endedAt = 200,
    members = { Member(A, "Bram"), Member(B, "Garrick") } })
local rfk = Instances.New({ name = "Razorfen Kraul", startedAt = 300, members = { Member(A, "Bram") } })
Eq(wc.id, 1, "first visit id")
Eq(rfk.id, 2, "second visit id")
Eq(ns.db.meta.nextVisitId, 3, "the counter did not move on")
Eq(ns.db.instances[1], wc, "a visit is not stored under its id")
Eq(wc.me, F.SELF.guid, "a visit does not record which of the user's characters was there")
Eq(#Instances.All(), 2, "All")

--------------------------------------------------------------------------
Section("For: the visits someone was in")

Eq(#Instances.For(A), 2, "visits with A")
local withB = Instances.For(B)
Eq(#withB, 1, "visits with B")
Eq(withB[1], wc, "B's visit")
Eq(#Instances.For(F.PUG.guid), 0, "visits with someone who was in none")
Eq(#Instances.For(mock.secret("Player-1-2")), 0, "a secret GUID matched")
Eq(#Instances.For(nil), 0, "nil matched")

--------------------------------------------------------------------------
Section("forgetting (PRV-3)")

-- Through the registry, as Characters.Forget walks it: the person leaves
-- the member list, the visit stays.
ns.Characters.Observe(B, { first = "Garrick", surname = "Fallow" })
ns.Characters.Forget(B)
Eq(#Instances.For(B), 0, "a forgotten person is still in a visit")
Eq(#wc.members, 1, "forgetting B took someone else too")
Eq(ns.db.instances[1], wc, "forgetting a member dropped the visit")

Eq(Instances.Remove(2), true, "Remove")
Eq(Instances.Remove(2), false, "Remove twice")
Eq(#Instances.All(), 1, "Remove left the visit")

Instances.New({ name = "Ragefire Chasm", startedAt = 400, members = {} })
Eq(ns.db.meta.nextVisitId, 4, "a removed id was given out again")
ns.ForgetEverywhere(nil)
Eq(next(ns.db.instances), nil, "forgetting everyone left visits")
