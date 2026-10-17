-- Chat capture (Features/Chat/): whispers, /say and party lines, and what
-- chat lockdown leaves of a line.

local T = ...
local mock, F = T.mock, T.F
local Section, Check, Eq = T.Section, T.Check, T.Eq
local Whisper = T.Whisper
local ns = T.Boot()
local Latest = ns._test.LatestInteraction

--------------------------------------------------------------------------
Section("whisper capture (INT-1, INT-3, INT-4)")

local GUID = F.STRANGER.guid

Whisper("CHAT_MSG_WHISPER", "thanks for the help!", "Bram Redfen", 663, GUID)
local row = Latest(GUID, "whisper_in")
Check(row, "an incoming whisper was not recorded")
Eq(row.excerpt, "thanks for the help!", "whisper text not stored")
Eq(ns.Recent.Get("whisper"), GUID, "last whisperer not remembered (DIA-3)")
Eq(ns.Characters.FullName(GUID), "Bram Redfen", "the sender was not identified")

Whisper("CHAT_MSG_WHISPER_INFORM", "any time", "Bram Redfen", 664, GUID)
Eq(Latest(GUID, "whisper_out").excerpt, "any time", "outgoing whisper not stored")

-- INT-4: under chat lockdown text, sender and guid are all secret. Nothing is
-- stored, but lineID stays plain and the line is counted.
local before = ns._test.RestrictedChatCount()
Whisper("CHAT_MSG_WHISPER", mock.secret("hidden"), mock.secret("Someone"), 670,
    mock.secret(GUID))
Eq(ns._test.RestrictedChatCount(), before + 1, "a restricted whisper was not counted (INT-3)")
Eq(ns.Interactions.Count(GUID), 2, "a restricted whisper was stored (INT-4)")

-- /say is only kept for people already worth keeping. Garrick is on record,
-- which is not enough.
ns.Characters.Observe(F.GARRICK.guid, { first = "Garrick", surname = "Fallow" })
Whisper("CHAT_MSG_SAY", "anyone for Deadmines?", "Garrick Fallow", 671, F.GARRICK.guid)
Eq(ns.Interactions.For(F.GARRICK.guid), nil, "a stranger's /say was stored")

Whisper("CHAT_MSG_SAY", "on my way", "Bram Redfen", 672, GUID)
Eq(Latest(GUID, "say").excerpt, "on my way",
    "/say from a known character was dropped")

--------------------------------------------------------------------------
Section("party chat")

-- Kept for diary entries only, under either party event.
local FRIEND = F.FRIEND.guid
ns.Diary.Add(FRIEND, { source = "test" })
Whisper("CHAT_MSG_PARTY", "do we need to be grouped", "Numa Pompilius", 680, FRIEND)
Eq(Latest(FRIEND, "party").excerpt, "do we need to be grouped", "a diary entry's party line was dropped")
Whisper("CHAT_MSG_PARTY_LEADER", "ok", "Numa Pompilius", 681, FRIEND)
Eq(Latest(FRIEND, "party").excerpt, "ok", "a diary entry's party-leader line was dropped")

-- Bram has rows in the buffer, which is enough for /say but not for party.
local babaRows = ns.Interactions.Count(GUID)
Whisper("CHAT_MSG_PARTY", "lfg?", "Bram Redfen", 682, GUID)
Eq(ns.Interactions.Count(GUID), babaRows, "party chat from a non-diary character was stored")

-- The user's own lines come back on the same event, under their own GUID.
Whisper("CHAT_MSG_PARTY", "sure", "Ulverston Nye", 683, F.SELF.guid)
Eq(ns.Interactions.For(F.SELF.guid), nil, "the user's own party line was stored")

local restricted = ns._test.RestrictedChatCount()
Whisper("CHAT_MSG_PARTY", mock.secret("hidden"), mock.secret("Numa"), 684, mock.secret(FRIEND))
Eq(ns._test.RestrictedChatCount(), restricted + 1, "a restricted party line was not counted")
