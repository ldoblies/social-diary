-- Chat capture (INT-1, Must): whispers, /say, /yell and party lines, each
-- written as a row of its kind (Kind.lua) on the person who said it.
--
-- Whispers are the interaction most likely to hold the reason you wanted to
-- remember somebody, so INT-3 keeps their text -- capped, and only while the
-- character is in the buffer. The cap, and whether text is kept at all, are
-- the core's (a kind's `chat`, Core/Interactions.lua).
--
-- INT-4 is the hard rule here: under chat lockdown, Session 1 saw text, sender
-- *and* guid all come back secret, and all three persisted as nil. So a
-- restricted whisper is not stored at all. The one thing that survives is
-- lineID, which stays plain, and that is what INT-3's fallback counts.
--
-- Who said what in /say and /yell, whoever they are, is also a sighting:
-- that is the Nearby engine's, Capture/Sightings.lua's FromChat, not this.

local addonName, ns = ...

-- INT-3's fallback. A restricted conversation still happened; the diary can
-- say so without keeping anything the client marked secret.
local restrictedLines = {}

local function CountRestricted(lineID)
    lineID = ns.Plain(lineID)
    if lineID == nil then return end

    -- The counter is per session and never persisted: without a sender there
    -- is no GUID to file it under.
    restrictedLines[#restrictedLines + 1] = lineID
    ns.Debug("restricted whisper (line %s) not stored; %d this session",
        tostring(lineID), #restrictedLines)
end

function ns._test.RestrictedChatCount()
    return #restrictedLines
end

-- `guid` has been through SafeGUID already (ns.ChatHandler).
local function Record(kind, text, sender, guid, lineID)
    if not guid then
        -- Either the payload is secret (chat lockdown) or the sender is
        -- somebody the client will not name. Neither is storable.
        CountRestricted(lineID)
        return
    end

    local first, surname = ns.NormalizeName(sender)
    ns.Characters.Observe(guid, { first = first, surname = surname })

    ns.Interactions.Add(guid, kind, { excerpt = text })

    if kind == "whisper_in" then
        ns.Recent.Set("whisper", guid)
    end
end

ns.OnChat("CHAT_MSG_WHISPER", function(text, sender, guid, lineID)
    Record("whisper_in", text, sender, guid, lineID)
end)

-- On WHISPER_INFORM the "sender" is the recipient -- still the other person,
-- which is all the diary cares about.
ns.OnChat("CHAT_MSG_WHISPER_INFORM", function(text, sender, guid, lineID)
    Record("whisper_out", text, sender, guid, lineID)
end)

-- /say and /yell are a Should in INT-1 and were verified plain outside
-- lockdown. They are far noisier than whispers -- one starting zone produced
-- ~60 distinct players in minutes -- so they are only recorded for people
-- already worth recording: anyone in the diary, or anyone the buffer already
-- knows. Blanket capture of nearby chat is a sighting problem, and that is M2.
local function NearbyChat(kind)
    return function(text, sender, guid, lineID)
        if not guid then
            CountRestricted(lineID)
            return
        end

        if not ns.Diary.IsDiary(guid) and ns.Interactions.Count(guid) == 0 then
            return
        end

        Record(kind, text, sender, guid, lineID)
    end
end

ns.OnChat("CHAT_MSG_SAY", NearbyChat("say"))
ns.OnChat("CHAT_MSG_YELL", NearbyChat("yell"))

-- Party chat is where a grouped conversation moves to, so without it a
-- session goes quiet the moment the invite is accepted. Only diary entries'
-- lines are kept: a pickup group's chatter is not worth a buffer row, and the
-- user's own lines (their GUID is never a diary entry) have no one recipient
-- to be filed under.
local function PartyChat(text, sender, guid, lineID)
    if not guid then
        CountRestricted(lineID)
        return
    end

    if not ns.Diary.IsDiary(guid) then return end

    Record("party", text, sender, guid, lineID)
end

ns.OnChat("CHAT_MSG_PARTY", PartyChat)
ns.OnChat("CHAT_MSG_PARTY_LEADER", PartyChat)
