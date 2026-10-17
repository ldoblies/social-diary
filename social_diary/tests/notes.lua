-- Notes the user writes into the diary (DIA-11): writing, editing and
-- deleting them, a note about several people, and what removing someone
-- from the diary or forgetting them does to what was written about them.
-- Where they go on the timeline (TLN-10) is tests/timeline.lua's.

local T = ...
local mock, F = T.mock, T.F
local Section, Check, Eq = T.Section, T.Check, T.Eq
local DAY = T.DAY
local ns = T.Boot()

local BRAM, GARRICK, PUG = F.STRANGER.guid, F.GARRICK.guid, F.PUG.guid

local function Fresh()
    T.BlankDiary()
    for _, who in ipairs({ F.STRANGER, F.GARRICK }) do
        mock.SetUnit("target", who)
        ns.Diary.Add(who.guid, { unit = "target", source = "test" })
    end
    mock.SetUnit("target", F.PUG)
    ns.Characters.ObserveUnit("target")
end

--------------------------------------------------------------------------
Section("writing a note (DIA-11)")

Fresh()

local version = ns.dataVersion
local note = ns.Notes.Add(BRAM, "  Helped me with the murloc camp.  ")
Check(note, "no note was written")
Eq(note.text, "Helped me with the murloc camp.", "the text was not trimmed")
Eq(note.time, mock.now, "a note is about now by default")
Check(note.about[BRAM], "the note is not about the person it was written for")
Eq(ns.CountKeys(note.about), 1, "one person by default")
Eq(note.zone, "Mulgore", "where the user was")
Eq(note.me, F.SELF.guid, "which of the user's characters wrote it (DAT-1)")
Eq(note.myLevel, 70, "the user's level")
Check(ns.dataVersion > version, "writing a note did not move the version")
Eq(ns.Notes.Get(note.id), note, "the note is not under its id")

local earlier = ns.Notes.Add(BRAM, "We met at the well.", { time = mock.now - DAY })
Check(earlier.id ~= note.id, "two notes share an id")
local list = ns.Notes.For(BRAM)
Eq(#list, 2, "notes about Bram")
Eq(list[1], earlier, "notes are not oldest first")
Eq(#ns.Notes.For(GARRICK), 0, "a note about Bram shows up for Garrick")

Eq(ns.Notes.Add(BRAM, "   "), nil, "a blank note was written")
Eq(ns.Notes.Add(BRAM, nil), nil, "a note without text was written")
Eq(ns.Notes.Add(PUG, "Who?"), nil, "a note about someone outside the diary (DIA-1)")
Eq(ns.Notes.Add("Creature-0-4620-1-6-3098-1", "A boar"), nil, "a note about a creature")
Eq(ns.Notes.Add(mock.secret(BRAM), "Secret"), nil, "a note about a secret GUID")
Eq(#ns.Notes.Add(BRAM, ("z"):rep(3000)).text, ns.Diary.MAX_NOTE_CHARS, "a note is not capped in length")

--------------------------------------------------------------------------
Section("a note about several people")

Fresh()

local group = ns.Notes.Add({ BRAM, GARRICK, PUG }, "Deadmines, all three bosses.")
Eq(ns.CountKeys(group.about), 2, "the note is not about both diary entries, and only them")
Eq(ns.Notes.For(BRAM)[1], group, "the group note is missing from Bram's notes")
Eq(ns.Notes.For(GARRICK)[1], group, "the group note is missing from Garrick's notes")
Eq(table.concat(ns.Notes.Others(group, BRAM), ","), GARRICK, "who else it is about, from Bram's page")

local solo = ns.Notes.Add(BRAM, "Just the two of us.")
Check(ns.Notes.AddPerson(solo.id, GARRICK), "Garrick was not added to the note")
Check(not ns.Notes.AddPerson(solo.id, GARRICK), "Garrick was added twice")
Check(not ns.Notes.AddPerson(solo.id, PUG), "someone outside the diary was added to a note")
Eq(#ns.Notes.For(GARRICK), 2, "Garrick's notes after being added to one")
Check(ns.Notes.RemovePerson(solo.id, BRAM), "Bram was not taken off the note")
Check(not ns.Notes.RemovePerson(solo.id, GARRICK), "the last person was taken off a note")
Check(ns.Notes.Get(solo.id), "taking the last person off deleted the note")
Check(not ns.Notes.RemovePerson(solo.id, BRAM), "taking off someone the note is not about")

--------------------------------------------------------------------------
Section("editing and deleting a note")

Fresh()

note = ns.Notes.Add(BRAM, "Helped me.")
local written = note.time
mock.now = mock.now + 60
Check(ns.Notes.Edit(note.id, "Helped me with the murlocs."), "the edit failed")
Eq(note.text, "Helped me with the murlocs.", "the text did not change")
Eq(note.edited, mock.now, "when it was edited")
Eq(note.time, written, "editing moved the note's time")

note.edited = nil
Check(ns.Notes.Edit(note.id, "Helped me with the murlocs."), "the same text again failed")
Eq(note.edited, nil, "the same text again counts as an edit")

Check(ns.Notes.Edit(note.id, "  "), "emptying a note failed")
Eq(ns.Notes.Get(note.id), nil, "an emptied note is still there")

note = ns.Notes.Add(BRAM, "To be deleted.")
Check(ns.Notes.Delete(note.id), "the delete failed")
Eq(ns.Notes.Get(note.id), nil, "a deleted note is still there")
Check(not ns.Notes.Delete(note.id), "deleting twice succeeded")
Check(not ns.Notes.Edit(note.id, "Back?"), "editing a deleted note succeeded")

--------------------------------------------------------------------------
Section("removing and forgetting (DIA-7, PRV-3, DAT-3)")

Fresh()

local mine = ns.Notes.Add(BRAM, "Bram only.")
local shared = ns.Notes.Add({ BRAM, GARRICK }, "Both of them.")

-- Out of the diary with the history kept: the user's writing stays, and
-- the buffer's prune does not reach it.
ns.Diary.Remove(BRAM, "keep")
ns.Interactions.Prune(mock.now + 400 * DAY)
Eq(ns.Notes.Get(mine.id), mine, "a note went when its person left the diary")
Eq(#ns.Notes.For(BRAM), 2, "Bram's notes after leaving the diary")

-- Back in the diary, back on the page.
mock.SetUnit("target", F.STRANGER)
ns.Diary.Add(BRAM, { unit = "target" })
Eq(#ns.Notes.For(BRAM), 2, "Bram's notes did not come back")

-- Purged: out of every note, and a note about nobody else goes.
ns.Diary.Remove(BRAM, "purge")
Eq(ns.Notes.Get(mine.id), nil, "a note about only Bram outlived the purge")
Eq(ns.Notes.Get(shared.id), shared, "a note also about Garrick went with Bram")
Eq(shared.about[BRAM], nil, "Bram is still in the shared note")
Eq(#ns.Notes.For(GARRICK), 1, "Garrick's notes after Bram was purged")

ns.WipeData()
Eq(ns.Notes.Count(), 0, "delete everything left notes behind (PRV-3)")
Eq(ns.db.meta.nextNoteId, 1, "delete everything kept the note ids going")

--------------------------------------------------------------------------
Section("who else a note could be about")

-- Everyone ever in a session with Bram, the latest together first; the
-- ones in a session going on at a time, by name.
Fresh()
local NOW = mock.now
local function Session(id, start, guids)
    local participants = {}
    for _, guid in ipairs(guids) do participants[guid] = { since = start, last = start + 600, seconds = 600 } end
    return { id = id, me = F.SELF.guid, source = "group", startedAt = start, endedAt = start + 600,
        participants = participants, others = 0, zones = { "Mulgore" }, deaths = {} }
end
mock.SetUnit("target", F.FRIEND)
ns.Diary.Add(F.FRIEND.guid, { unit = "target" })
ns.db.sessions = {
    [1] = Session(1, NOW - 3 * DAY, { BRAM, GARRICK }),
    [2] = Session(2, NOW - DAY, { BRAM, F.FRIEND.guid, PUG }),
    [3] = Session(3, NOW - 5 * DAY, { BRAM, GARRICK, F.FRIEND.guid }),
}
Eq(table.concat(ns.Notes.Together(BRAM), ","), F.FRIEND.guid .. "," .. GARRICK,
    "together, latest first, diary entries only")
Eq(table.concat(ns.Notes.Companions(BRAM, NOW - 5 * DAY + 60), ","), GARRICK .. "," .. F.FRIEND.guid,
    "the companions are not by name")
