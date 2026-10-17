-- Campfires (Features/Campfire/Capture.lua): a minute sat out by a fire
-- is one on the route and a "campfire" row on each who sat there too; a
-- minute cut short is nothing; minute after minute at one fire is one
-- campfire.

local T = ...
local mock, F = T.mock, T.F
local Section, Check, Eq = T.Section, T.Check, T.Eq
local ns = T.Boot()

local C = ns.Campfire
local SELF, STRANGER, FRIEND, STRANGER2 = F.SELF, F.STRANGER, F.FRIEND, F.STRANGER2
local COUNTDOWN, BENEFITS = C.COUNTDOWN, 1229741

-- The client's clock to the second, the server's.
_G.GetTime = function() return mock.now end

-- Auras by unit token, as the client lists them.
local auras = {}
local nextID = 100
_G.C_UnitAuras = {
    GetAuraDataByIndex = function(unit, i) return (auras[unit] or {})[i] end,
    GetPlayerAuraBySpellID = function(spellId)
        for _, aura in ipairs(auras.player or {}) do
            if aura.spellId == spellId then return aura end
        end
        return nil
    end,
}
local secret = false
_G.C_Secrets = { ShouldAurasBeSecret = function() return secret end }

local function Aura(spellId, duration)
    nextID = nextID + 1
    return { auraInstanceID = nextID, spellId = spellId, duration = duration,
        expirationTime = mock.now + duration, isHelpful = true }
end

-- The user's countdown begins; returns it.
local function Sit()
    local aura = Aura(COUNTDOWN, 60)
    auras.player = { aura }
    mock.fire("UNIT_AURA", "player", { addedAuras = { aura } })
    return aura
end

-- `seconds` go by, the others looked at as the sweep does.
local function Pass(seconds)
    for _ = 1, seconds, 5 do
        mock.now = mock.now + math.min(5, seconds)
        C.Sweep()
    end
end

-- The countdown goes, `left` seconds before its time (0: it ran out).
local function Gone(aura, left)
    mock.now = aura.expirationTime - (left or 0)
    auras.player = {}
    mock.fire("UNIT_AURA", "player", { removedAuraInstanceIDs = { aura.auraInstanceID },
        addedAuras = (left or 0) == 0 and { Aura(BENEFITS, 3600) } or nil })
end

local function Rows(guid, kind)
    local n = 0
    for _, row in ipairs(ns.db.interactions[guid] or {}) do
        if row.type == (kind or "campfire") then n = n + 1 end
    end
    return n
end

local function Plate(i, def, counting)
    mock.SetUnit("nameplate" .. i, def)
    auras["nameplate" .. i] = counting and { Aura(9999, 0), Aura(COUNTDOWN, 60) } or { Aura(9999, 0) }
end

mock.position = { x = 0.42, y = 0.66 }
mock.zone, mock.subZone = "Mulgore", "Bloodhoof Village"
mock.fire("PLAYER_ENTERING_WORLD")
local j = ns.db.journey[SELF.guid]
Check(j, "setup: no route")

--------------------------------------------------------------------------
Section("a minute sat out")

Plate(1, STRANGER, true)
Plate(2, STRANGER2, false)
local aura = Sit()
Check(ns._test.Campfire().sitting, "the countdown was not taken for sitting")
Pass(30)
Gone(aura)
Eq(#C.List(j), 1, "the campfire on the route")
local rec = C.List(j)[1]
Eq(rec.mapID, 1412, "its map")
Eq(rec.x, 0.42, "its x")
Eq(rec.subZone, "Bloodhoof Village", "its subzone")
Eq(rec.t, mock.now, "its time")
Eq(Rows(STRANGER.guid), 1, "the one who sat too has no row")
Eq(Rows(STRANGER2.guid), 0, "one who only stood by got a row")
local row = ns.db.interactions[STRANGER.guid][#ns.db.interactions[STRANGER.guid]]
Eq(row.context.subZone, "Bloodhoof Village", "the row's subzone")
Eq(row.zone, "Mulgore", "the row's zone")
Eq(row.theirLevel, STRANGER.level, "their level")
Check(not ns._test.Campfire().sitting, "still sitting after the countdown went")

--------------------------------------------------------------------------
Section("minute after minute at one fire is one campfire")

mock.now = mock.now + 5
Plate(3, FRIEND, true)      -- sits down for the second minute
aura = Sit()
Pass(60)
Gone(aura)
Eq(#C.List(j), 1, "a second minute at the same fire was a second campfire")
Eq(Rows(STRANGER.guid), 1, "a second row for the same sitting")
Eq(Rows(FRIEND.guid), 1, "one who joined for the second minute has no row")

--------------------------------------------------------------------------
Section("a minute cut short is nothing")

ns._test.Campfire().reset()
mock.now = mock.now + 3600
mock.position = { x = 0.6, y = 0.3 }
mock.ClearUnits()
auras = {}
Plate(1, STRANGER2, true)
aura = Sit()
Pass(20)
Gone(aura, 25)
Eq(#C.List(j), 1, "standing up early was a campfire")
Eq(Rows(STRANGER2.guid), 0, "standing up early gave a row")

--------------------------------------------------------------------------
Section("another fire, or the same one much later, is another campfire")

aura = Sit()
Pass(60)
Gone(aura)
Eq(#C.List(j), 2, "a fire across the zone was the first one")
Eq(Rows(STRANGER2.guid), 1, "the second fire's companion")

mock.now = mock.now + C.AGAIN + 60
aura = Sit()
Pass(60)
Gone(aura)
Eq(#C.List(j), 3, "the same fire hours later was the same campfire")

--------------------------------------------------------------------------
Section("a /reload in the middle of a sitting")

ns._test.Campfire().reset()
mock.now = mock.now + 5
aura = Sit()
Pass(60)
Gone(aura)
Eq(#C.List(j), 3, "a reload made the same fire a new campfire")
Eq(Rows(STRANGER2.guid), 2, "a reload gave the same sitting a second row")

-- Already counting down when the world loads: picked up from the full scan.
ns._test.Campfire().reset()
mock.now = mock.now + 5
aura = Aura(COUNTDOWN, 60)
auras.player = { aura }
mock.fire("UNIT_AURA", "player", { isFullUpdate = true })
Check(ns._test.Campfire().sitting, "a countdown already running was missed")
mock.now = aura.expirationTime
auras.player = {}
mock.fire("UNIT_AURA", "player", { isFullUpdate = true })
Eq(#C.List(j), 3, "a full update's finished minute made a new campfire at the same fire")
Check(not ns._test.Campfire().sitting, "still sitting after a full update dropped the countdown")

--------------------------------------------------------------------------
Section("auras closed, others' units, the route off")

ns._test.Campfire().reset()
mock.now = mock.now + 7200
mock.position = { x = 0.2, y = 0.2 }
secret = true
aura = Sit()
Check(not ns._test.Campfire().sitting, "a countdown read while auras were secret")
secret = false

-- Another unit's countdown is not the user's.
auras.nameplate1 = { Aura(COUNTDOWN, 60) }
mock.fire("UNIT_AURA", "nameplate1", { addedAuras = auras.nameplate1 })
Check(not ns._test.Campfire().sitting, "someone else's countdown was taken for the user's")

-- The route not kept: the rows still come, the route gets nothing.
ns.db.settings.keepRoute = false
Plate(1, FRIEND, true)
aura = Sit()
Pass(60)
Gone(aura)
Eq(#C.List(j), 3, "a campfire went on a route not kept")
Eq(Rows(FRIEND.guid), 2, "with the route off, no row for the one who sat too")
ns.db.settings.keepRoute = true

-- Inside an instance: nothing.
ns._test.Campfire().reset()
mock.inInstance = true
aura = Sit()
Pass(60)
Gone(aura)
mock.inInstance = false
Eq(#C.List(j), 3, "a campfire inside an instance")
Eq(Rows(FRIEND.guid), 2, "a row inside an instance")
