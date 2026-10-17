-- "You" in a record's words (Format.You, UI/Words/Format.lua): the
-- character playing is "you"; in a shared diary another of the user's
-- characters is named, so a line from an alt says whose it was.

local T = ...
local F = T.F
local mock = T.mock
local Section, Eq = T.Section, T.Eq
local ns = T.Boot()

local Format = ns.UI.Format
local You = Format.You
local SELF, STRANGER = F.SELF, F.STRANGER

local ALT = "Player-4707-0A17A17A"
ns.OwnCharacters()[ALT] = { first = "Thessaly", surname = "Vane" }
ns.db.characters[STRANGER.guid] = { guid = STRANGER.guid, names = { { first = "Bram", surname = "Redfen" } } }

-- A row's line on Bram's timeline, as the page asks for it.
local function Line(kind, me, context, extra)
    local row = { type = kind, me = me, time = ns.Now(), zone = "Mulgore", context = context }
    for key, value in pairs(extra or {}) do row[key] = value end
    return ns.Rows.Get(kind).text(row, STRANGER.guid)
end

local function Death(guid)
    local _, text = ns.UI.DescribeItem({ kind = "death", time = ns.Now(),
        death = { guid = guid, zone = "Mulgore", killer = { name = "Plainstrider", source = "recap" } } },
        STRANGER.guid)
    return text
end

--------------------------------------------------------------------------
Section("a diary of its own: always you")

ns.diaryShared = false
Eq(You(ALT, "{You} killed Bram"), "You killed Bram", "an alt was named in a diary of its own")
Eq(You(SELF.guid, "Bram saved {you}"), "Bram saved you", "the braces were left in")
Eq(Line("pvp_kill", ALT), "You killed Bram in Mulgore", "a kill in a diary of its own")

--------------------------------------------------------------------------
Section("a shared diary: the one playing is you, an alt by name")

ns.diaryShared = true
Eq(You(SELF.guid, "{You} killed Bram"), "You killed Bram", "the one playing was named")
Eq(You(nil, "{Your} group killed Bram"), "Your group killed Bram", "a row from before `me` was named")
Eq(You("Player-4707-0BADBAD0", "{You} killed Bram"), "You killed Bram", "a nameless character")

Eq(You(ALT, "{You} killed Bram"), "Thessaly killed Bram", "subject")
Eq(You(ALT, "Bram saved {you}"), "Bram saved Thessaly", "object")
Eq(You(ALT, "{Your} group killed Bram"), "Thessaly's group killed Bram", "possessive")
Eq(You(ALT, "{You've} met twice"), "Thessaly has met twice", "you've")
Eq(You(ALT, "{you're} nearby"), "Thessaly is nearby", "you're")
Eq(You(ALT, "{You were} there"), "Thessaly was there", "you were")
Eq(You(ALT, "{them}"), "them", "an unknown word kept its braces")

-- Each row kind that speaks of the user.
Eq(Line("pvp_kill", ALT), "Thessaly killed Bram in Mulgore", "pvp_kill")
Eq(Line("pvp_kill", ALT, { by = STRANGER.guid }), "Thessaly's group killed Bram in Mulgore (Bram's killing blow)",
    "pvp_kill by the group")
Eq(Line("pvp_death", ALT, { probable = true }), "Bram probably killed Thessaly in Mulgore", "pvp_death")
Eq(Line("pvp_death", SELF.guid), "Bram killed you in Mulgore", "pvp_death, the one playing")
Eq(Line("whisper_out", ALT, nil, { excerpt = "hi" }), 'Thessaly whispered: "hi"', "whisper_out")
Eq(Line("watched_death", ALT), "Bram watched Thessaly die in Mulgore", "watched_death")
Eq(Line("tried_to_help", ALT), "Bram tried to save Thessaly in Mulgore", "tried_to_help")
Eq(Line("saved_you", ALT, { pct = 6 }), "Bram saved Thessaly at 6%\194\160health in Mulgore", "saved_you")
Eq(Line("campfire", ALT), "Thessaly and Bram sat by a campfire together in Mulgore", "campfire")
Eq(Line("duel_series", ALT, { won = 2, fled = 1 }), "Won 2 duels against Bram and lost 1 in Mulgore"
    .. "  \194\183  Thessaly fled once", "duel")

Eq(Death(ALT), "Thessaly died to Plainstrider near Mulgore", "a death on the timeline")
Eq(Death(SELF.guid), "You died to Plainstrider near Mulgore", "a death on the timeline, the one playing")
Eq(Death(STRANGER.guid), "Bram died to Plainstrider near Mulgore", "their death")

--------------------------------------------------------------------------
Section("no bare you in an alt's lines: every row kind, and /sd testdata")

-- A "you" word outside a quote: a line that skipped Format.You. Chat keeps
-- what was said, which may say "you" to anyone.
local function Bare(text)
    if type(text) ~= "string" then return nil end
    local plain = text:gsub('"[^"]*"', ""):lower()
    return plain:match("%f[%a]you%f[%A]") or plain:match("%f[%a]your%f[%A]")
        or plain:match("%f[%a]yours%f[%A]")
end

local function NoYou(text, what)
    Eq(Bare(text), nil, what .. " says you for another character: " .. tostring(text))
end

-- Every kind's words on a row the alt wrote, with a context rich enough to
-- reach each branch a kind has, and with none.
local RICH = { by = STRANGER.guid, probable = true, spell = "Ambush", pct = 6, watched = 6, won = 2, lost = 1,
    fled = 1, theyFled = 1, last = "fled", level = 12, raid = true, subZone = "Red Cloud Mesa",
    name = "Plainstrider" }
for _, kind in ipairs(ns.Rows.All()) do
    if ns.Rows.Get(kind).text then
        NoYou(Line(kind, ALT, RICH, { excerpt = "hi" }), kind)
        NoYou(Line(kind, ALT, {}), kind .. " (bare)")
        NoYou(Line(kind, ALT, nil), kind .. " (no context)")
    end
end

-- The test entry and the features' strangers, written by the character
-- playing; then another character plays, and all of it is the alt's.
T.BlankDiary()
SlashCmdList.SOCIALDIARY("testdata")
ns.UI.CloseJournal()
local playing = ns.ownGUID
ns.ownGUID = ALT

local function Describe(item, guid, what)
    local _, text, sub, _, full = ns.UI.DescribeItem(item, guid)
    NoYou(text, what)
    NoYou(sub, what .. "'s details")
    NoYou(full, what .. "'s tooltip")
    for _, child in ipairs(item.all or {}) do Describe(child, guid, what .. " > " .. tostring(child.kind)) end
end

local people = 0
for guid in pairs(ns.db.interactions) do
    people = people + 1
    for _, item in ipairs(ns.Timeline.For(guid)) do Describe(item, guid, tostring(item.kind)) end
end
T.Check(people > 1, "/sd testdata wrote nobody's rows")

ns.ownGUID = playing
SlashCmdList.SOCIALDIARY("testdata remove")
ns.UI.CloseJournal()

--------------------------------------------------------------------------
Section("whose meeting it was: the profile, the toast and the tooltip")

local function Plain(text) return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

local function Meet(me)
    ns.ownGUID = me
    mock.now = mock.now + 60
    ns.Interactions.Add(STRANGER.guid, "trade")
    ns.ownGUID = playing
end

local function Story()
    ns.UI.ShowJournal(STRANGER.guid)
    for _, line in ipairs(_G.SocialDiaryJournalFrame.profile.timeline.data) do
        if line.prose == "story" then return Plain(line.text) end
    end
end

local function Toast()
    return Plain(ns.UI.ReunionText(ns.UI.Toast.Snapshot(STRANGER.guid, "group")).stories[1])
end

local function Tooltip()
    local lines = {}
    ns.UI.OnUnitTooltip({ AddLine = function(_, text) lines[#lines + 1] = text end }, { guid = STRANGER.guid })
    return lines[#lines]
end

-- The same words as ever: a diary of its own, and the alt reading its own.
local function AsEver(story, toast, tooltip, what)
    for _, view in ipairs({ { false, playing }, { true, ALT } }) do
        ns.diaryShared, ns.ownGUID = view[1], view[2]
        T.Check(Story():find(story), what .. ", the profile: " .. Story())
        Eq(Toast(), toast, what .. ", the toast")
        Eq(Tooltip(), tooltip, what .. ", the tooltip")
    end
    ns.diaryShared, ns.ownGUID = true, playing
end

T.BlankDiary()
ns.diaryShared = true
ns.ownGUID = ALT
ns.Diary.Add(STRANGER.guid, { source = "test" })
ns.ownGUID = playing

Meet(ALT)
T.Check(Story():find("^Thessaly met Bram once in Mulgore on "), "met once by the alt: " .. Story())
Eq(Toast(), "Thessaly met them once, today in Mulgore.", "the toast, met once by the alt")
Eq(Tooltip(), "Met 1 time  ·  last as Thessaly today", "the tooltip, met once by the alt")
AsEver("^You met Bram once in Mulgore on ", "You've met once, today in Mulgore.", "Met 1 time  ·  last today",
    "met once")

Meet(playing)
T.Check(Story():find("^Thessaly first met Bram in Mulgore on .* You've crossed paths 2 times%."),
    "first met by the alt: " .. Story())
Eq(Toast(), "You've crossed paths 2 times, last today in Mulgore.", "the toast, last met by the one playing")
Eq(Tooltip(), "Met 2 times  ·  last today", "the tooltip, last met by the one playing")

Meet(ALT)
Eq(Toast(), "You've crossed paths 3 times, last as Thessaly today in Mulgore.", "the toast, last met by the alt")
Eq(Tooltip(), "Met 3 times  ·  last as Thessaly today", "the tooltip, last met by the alt")
AsEver("^You first met Bram in Mulgore on ", "You've crossed paths 3 times, last today in Mulgore.",
    "Met 3 times  ·  last today", "met three times")
ns.UI.CloseJournal()

--------------------------------------------------------------------------
Section("whose it was on the timeline: every kind of item")

-- /sd testdata written by the alt, and the kinds it does not write.
T.BlankDiary()
ns.ownGUID = ALT
SlashCmdList.SOCIALDIARY("testdata")
ns.UI.CloseJournal()
ns.ownGUID = playing

local function Up(level) return { time = mock.now, row = { type = "level_up", me = ALT, context = { level = level } } } end
local MADE = {
    { kind = "climb", time = mock.now, ups = { Up(5), Up(6) } },
    { kind = "first", time = mock.now, first = { me = ALT, subZone = "Red Cloud Mesa", level = 5 } },
}

local function Words(item, guid)
    local _, text, sub, _, full = ns.UI.DescribeItem(item, guid)
    return text .. "\n" .. (sub or "") .. "\n" .. (full or "")
end

-- Every line names the alt, in itself, its details or its tooltip, but
-- their own death, which is theirs; or, `mine` false, none does.
local named = {}
local function Walk(item, guid, mine)
    local words = Words(item, guid)
    local says = words:find("Thessaly", 1, true) ~= nil
    if not mine then
        Eq(says, false, item.kind .. " named the alt: " .. words)
    elseif not (item.kind == "death" and item.death.guid == guid) then
        Eq(says, true, item.kind .. " does not say whose it was: " .. words)
        named[item.kind] = true
    end
    for _, child in ipairs(item.all or {}) do Walk(child, guid, mine) end
    for _, child in ipairs(item.lines or {}) do Walk(child, guid, mine) end
end

local function WalkAll(mine)
    for guid in pairs(ns.db.diary) do
        for _, item in ipairs(ns.Timeline.For(guid)) do Walk(item, guid, mine) end
        for _, item in ipairs(MADE) do Walk(item, guid, mine) end
    end
end

WalkAll(true)
for _, kind in ipairs({ "session", "visit", "exchange", "row", "climb", "rare", "death", "around", "note",
    "first", "added" }) do
    T.Check(named[kind], kind .. ": no line of this kind on the timeline")
end

ns.diaryShared = false
WalkAll(false)
ns.diaryShared, ns.ownGUID = true, ALT
WalkAll(false)
ns.ownGUID = playing

SlashCmdList.SOCIALDIARY("testdata remove")
ns.UI.CloseJournal()

ns.diaryShared = false
ns.OwnCharacters()[ALT] = nil
ns.db.characters[STRANGER.guid] = nil
