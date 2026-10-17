-- The book's sounds (Style.SOUNDS): a ribbon turning the page, a loose
-- sheet laid on the book and taken off, and the quill when something new is
-- written into the diary. Choosing a person in the list makes none. The map
-- sheet's own rustle is tests/reunion.lua's.

local T = ...
local mock, F = T.mock, T.F
local Section, Check, Eq = T.Section, T.Check, T.Eq
local ns = T.Boot()

local BRAM, GARRICK, PUG = F.STRANGER.guid, F.GARRICK.guid, F.PUG.guid
local PAGE, OPEN, CLOSE, WRITE = "836", "844", "845", "3093"

-- What was played since the last call, as ids joined by commas; every one
-- on the effects channel.
local function Heard()
    local ids = {}
    for _, sound in ipairs(mock.sounds) do
        Eq(sound[2], "SFX", "a sound not on the effects channel")
        ids[#ids + 1] = tostring(sound[1])
    end
    mock.sounds = {}
    return table.concat(ids, ",")
end

T.BlankDiary()
for _, who in ipairs({ F.STRANGER, F.GARRICK }) do
    mock.SetUnit("target", who)
    ns.Diary.Add(who.guid, { unit = "target", source = "test" })
end
ns.UI.ShowJournal(BRAM)
local J = _G.SocialDiaryJournalFrame
local P = J.profile
Heard()

--------------------------------------------------------------------------
Section("the ribbons turn the page")

J.ribbons.nearby:Click()
Eq(Heard(), PAGE, "the ribbon did not turn the page with a sound")
J.ribbons.nearby:Click()
Eq(Heard(), "", "the open page's ribbon turned it again")
J.ribbons.people:Click()
Eq(Heard(), PAGE, "the way back made no sound")

--------------------------------------------------------------------------
Section("choosing a person is silent")

ns.UI.SelectPerson(GARRICK)
ns.UI.SelectPerson(BRAM)
Eq(Heard(), "", "choosing a person made a sound")

--------------------------------------------------------------------------
Section("a new note: the sheet, then the quill")

P.tabNote:Click()
Eq(Heard(), OPEN, "the note sheet was laid on the book without a sound")
P.noteSheet.box:SetText("Showed me the way to Thunder Bluff.")
P.noteSheet.save:Click()
Eq(Heard(), WRITE, "saving a new note did not sound the quill alone")

P.tabNote:Click()
Heard()
P.noteSheet.cancel:Click()
Eq(Heard(), CLOSE, "a cancelled note did not rustle away")

P.tabNote:Click()
Heard()
P.noteSheet.box:SetText("   ")
P.noteSheet.save:Click()
Eq(Heard(), CLOSE, "an empty note was written with the quill")

--------------------------------------------------------------------------
Section("a new person: the quill")

mock.SetUnit("target", F.PUG)
ns.UI.Remember(PUG, { unit = "target", source = "test" })
Eq(Heard(), "", "the quill sounded before Done")
_G.SocialDiaryEntryFrame.form.done:Click()
Eq(Heard(), WRITE, "adding a person did not sound the quill")
ns.UI.Remember(PUG, { unit = "target", source = "test" })
Eq(Heard(), "", "someone already in the diary was written in again")
