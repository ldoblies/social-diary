-- Group sync's feed and store (Core/Sync/): what of the diary is fed, fed
-- again when it changes, and taken back when it is gone; the streams' seqs,
-- their gaps and their epochs. The wire between players is
-- tests/sync_protocol.lua's.

local T = ...
local mock, F = T.mock, T.F
local Section, Check, Eq = T.Section, T.Check, T.Eq
local ns = T.Boot()

local Feed, Store, Wire = ns.Sync.Feed, ns.Sync.Store, ns.Sync.Wire
local SELF, BRAM = F.SELF.guid, F.STRANGER.guid

-- `key`'s live entries of kind `k`.
local function Live(key, k)
    local list = {}
    for _, item in ipairs(Store.Live(key)) do
        if item.entry.k == k then list[#list + 1] = item.entry end
    end
    return list
end

--------------------------------------------------------------------------
Section("nothing is fed without a group code")

T.BlankDiary()
mock.SetUnit("target", F.STRANGER)
ns.Diary.Add(BRAM, { unit = "target", source = "test" })
Eq(Feed.On(), false, "sync is on before a code is entered")
Eq(Feed.Derive(), 0, "fed without a code")
Eq(Store.Author(SELF), nil, "a stream began without a code")

--------------------------------------------------------------------------
Section("the diary fed, chat left out")

ns.SetSetting("groupCode", "gigus")
Check(Feed.On(), "a code does not turn sync on")

local j = ns.Journey.Mine() or ns.Journey.Begin(SELF, mock.now - 3600, 69, 1412)
ns.Journey.Level(j, 70, mock.now - 600, { mapID = 1412, subZone = "Red Cloud Mesa" })
local death = ns.Deaths.Died(mock.now - 300)
ns.db.interactions[BRAM] = {
    { type = "trade", time = mock.now - 200, me = SELF, zone = "Mulgore", myLevel = 70,
        context = { given = { { link = "|cffffffff|Hitem:2589|h[Linen Cloth]|h|r", count = 10 } }, moneyReceived = 500 } },
    { type = "whisper_in", time = mock.now - 100, me = SELF, excerpt = "the secret words" },
}
local note = ns.Notes.Add(BRAM, "Bram knows every murloc by name.")

local fed = Feed.Derive()
Check(fed >= 5, "too little fed: " .. fed)
local card = Store.ByRef(SELF, "me:card")
Eq(card and card.name, "Ulverston Nye", "the author's card names the character")
Eq(card.class, "WARRIOR", "the author's class")

local levels = Live(SELF, "level")
Eq(#levels, 1, "levels fed")
Eq(levels[1].level, 70, "the level reached")
Eq(levels[1].sub, "Red Cloud Mesa", "the subzone it was reached in")

local deaths = Live(SELF, "death")
Eq(#deaths, 1, "deaths fed")
Eq(deaths[1].t, death.t, "the death's time")

local trades = Live(SELF, "trade")
Eq(#trades, 1, "trades fed")
Eq(trades[1].who, "Bram Redfen", "a row names the person")
Eq(trades[1].gave, "10x Linen Cloth", "what was given, as plain words")
Eq(trades[1].moneyGot, 500, "the money received")

Eq(#Live(SELF, "note"), 1, "notes fed")
Eq(Live(SELF, "note")[1].text, note.text, "a note's text")

for _, item in ipairs(Store.Live(SELF)) do
    Check(item.entry.excerpt == nil, "an entry carries an excerpt")
    Check(not Wire.Encode(item.entry):find("secret words", 1, true), "chat reached the feed")
end

local a = Store.Author(SELF)
Eq(a.last, a.top, "an own stream has no holes")
Eq(Feed.Derive(), 0, "fed again with nothing changed")

--------------------------------------------------------------------------
Section("a record that changes is fed again, replacing the first")

local before = select(2, Store.ByRef(SELF, deaths[1].r))
ns.Deaths.Killer(death, { npcID = 3035, name = "Flatland Cougar", source = "recap" })
Eq(Feed.Derive(), 1, "the named killer was not fed")
local again, seq = Store.ByRef(SELF, deaths[1].r)
Eq(again.foe, "Flatland Cougar", "the killer")
Check(seq > before, "the new entry is not later")
Eq(a.entries[before], nil, "the first entry is still held")
Eq(#Live(SELF, "death"), 1, "one death, not two")
Eq(Store.From(SELF, before, 1)[1].entry, nil, "the emptied seq is not handed out as empty")

--------------------------------------------------------------------------
Section("a note deleted, or kept back, is gone from the group too")

local second = ns.Notes.Add(BRAM, "And every murloc knows him.", { time = mock.now - 50 })
Feed.Derive()
Eq(#Live(SELF, "note"), 2, "two notes fed")
ns.Notes.Delete(second.id)
Eq(Feed.Derive(), 1, "a deleted note's tombstone")
Eq(#Live(SELF, "note"), 1, "the deleted note is still live")
Eq(Store.ByRef(SELF, "note:" .. second.time).del, true, "the tombstone")

ns.SetSetting("shareNotes", false)
Feed.Derive()
Eq(#Live(SELF, "note"), 0, "notes kept back are still live")
ns.SetSetting("shareNotes", true)
Feed.Derive()
Eq(#Live(SELF, "note"), 1, "notes shared again were not fed again")

--------------------------------------------------------------------------
Section("a hunt is fed only when it was luck")

j.hunts = { { t = mock.now - 40, level = 70, title = "Plainstrider Meat", item = "Plainstrider Meat",
    need = 7, kills = 8, npcID = 2955, name = "Plainstrider" } }
Feed.Derive()
Eq(#Live(SELF, "hunt"), 0, "an ordinary hunt was fed")
j.hunts[2] = { t = mock.now - 30, level = 70, title = "Plainstrider Meat", item = "Plainstrider Meat",
    need = 7, kills = 31, expected = 9, npcID = 2955, name = "Plainstrider" }
Feed.Derive()
Eq(#Live(SELF, "hunt"), 1, "a hunt of bad luck was not fed")
Eq(Live(SELF, "hunt")[1].luck, "bad", "its luck")

--------------------------------------------------------------------------
Section("a stream received out of order")

local OTHER = "Player-4620-00777777"
Check(Store.Put(OTHER, 2, { r = "level:2", k = "level", t = 2 }), "seq 2 refused")
Eq(Store.Author(OTHER).last, 0, "last moved past a missing seq")
Check(Store.Put(OTHER, 1, { r = "level:1", k = "level", t = 1 }), "seq 1 refused")
Eq(Store.Author(OTHER).last, 2, "last did not catch up")
Eq(Store.Put(OTHER, 2, { r = "level:2", k = "level", t = 2 }), false, "a seq taken twice")
Store.Put(OTHER, 3, nil)
Eq(Store.Author(OTHER).last, 3, "an empty seq does not count as held")
Store.Put(OTHER, 4, { r = "level:1", k = "level", t = 1, sub = "again" })
Eq(Store.ByRef(OTHER, "level:1").sub, "again", "a later entry does not replace by ref")
Eq(Store.Author(OTHER).entries[1], nil, "the replaced entry is still held")

local vector = Store.Vector()
Eq(vector[OTHER].last, 4, "the vector's last")
local epoch = vector[OTHER].epoch
Store.Restart(OTHER, epoch + 10)
Eq(Store.Author(OTHER).last, 0, "a new epoch kept the old stream")
Eq(Store.ByRef(OTHER, "level:1"), nil, "a new epoch kept the old refs")

--------------------------------------------------------------------------
Section("forgetting the group keeps the user's own; deleting everything does not")

Store.Put(OTHER, 1, { r = "level:1", k = "level", t = 1 })
Store.ForgetOthers(ns.OwnCharacters())
Eq(Store.Author(OTHER), nil, "the group's stream was kept")
Check(Store.Author(SELF), "the user's own stream went with the group's")

ns.WipeData()
Eq(next(ns.SyncData().authors), nil, "delete everything kept the streams")
Eq(next(ns.SyncData().derived), nil, "delete everything kept what was fed")
Eq(Store.ByRef(SELF, "me:card"), nil, "the refs outlived the wipe")
