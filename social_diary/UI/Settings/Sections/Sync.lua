-- Settings: Sync (UI/Settings/Page.lua lists the sections; the controls are
-- UI/Settings/Kit.lua's): the group code that shares the diary with
-- friends (Core/Sync/), what goes with it, and forgetting the group's.

local addonName, ns = ...

local Style = ns.Style
local FONT = Style.FONT
local BOOK = ns.UI.Journal.BOOK
local SettingsUI = ns.UI.Settings
local Kit = SettingsUI.Kit
local Switch, DependsOn = Kit.Switch, Kit.DependsOn

local DAY = 24 * 60 * 60

local function Coded()
    return ns.Sync.Feed.On()
end

-- The players heard lately, and whose diaries are held: the group's names
-- as each author's card gives them.
local function StatusText()
    if not Coded() then return "Not syncing." end
    local status = ns.Sync.Transport.Status()
    local now, heard = ns.Now(), 0
    for _, peer in pairs(ns.SyncData().peers) do
        if peer.seen and now - peer.seen < DAY then heard = heard + 1 end
    end
    local own, names = ns.OwnCharacters(), {}
    for key in pairs(ns.SyncData().authors) do
        if not own[key] and key ~= ns.Sync.CURATED then
            local card = ns.Sync.Store.ByRef(key, "me:card")
            names[#names + 1] = card and card.name or "someone not yet named"
        end
    end
    table.sort(names)
    local text = ("%s  ·  %d player%s heard today."):format(
        status.joined and "In the group's channel" or "Joining the group's channel",
        heard, heard == 1 and "" or "s")
    if #names > 0 then text = text .. "\nDiaries held: " .. table.concat(names, ", ") .. "." end
    if status.queued > 0 or status.inflight > 0 then
        text = text .. ("\nSyncing: %d message%s to send."):format(status.queued, status.queued == 1 and "" or "s")
    end
    return text
end

local function Restart()
    ns.Sync.Transport.Start()
    ns.Sync.Feed.Derive()
end

local function BuildSync(pane, c)
    local page = SettingsUI.page

    c:Heading("Group")
    page.groupCode = Kit.Text(c, "Group code", "groupCode", Restart)
    c:Hint("Friends who enter the same code share their diaries with each other whenever two of"
        .. " you are online: your road, the people you met and what you wrote. Chat is never"
        .. " shared. Leave it empty to share nothing.")

    page.shareNotes = Switch(c, "Share my notes", "shareNotes", nil, function() ns.Sync.Feed.Derive() end,
        "Notes you take back are taken back from the group at the next sync too.")
    DependsOn(page.shareNotes, Coded)

    page.showCurated = Switch(c, "Show curated stories", "showCurated", nil, nil,
        "Where the group's editor wrote a story about your road, it stands in for the diary's own"
            .. " words. Off, you always read the diary's own.")

    c:Heading("Status")
    page.syncStatus = Style.Text(pane, FONT.small)
    page.syncStatus:SetWidth(BOOK.RIGHT_W)
    function page.syncStatus:Refresh() self:SetText(StatusText()) end
    c:Place(page.syncStatus, 42, 0, 8)
    page.controls[#page.controls + 1] = page.syncStatus

    c:Heading("Forgetting")
    local ACCENT = Style.ACCENT
    page.forgetGroup = Style.Link(pane, FONT.body, function()
        ns.UI.Dialog.Confirm("Stop syncing and forget the group's diaries?\n\nThe group code is"
            .. " cleared and every diary the group shared with you goes. Your own diary is kept,"
            .. " and so is what you already shared with them.", function()
            ns.SetSetting("groupCode", "")
            ns.Sync.Store.ForgetOthers(ns.OwnCharacters())
            ns.Sync.Transport.Start()
            ns.Print("stopped syncing; the group's diaries are forgotten.")
            SettingsUI.Refresh()
        end)
    end)
    page.forgetGroup:SetText("Stop syncing and forget the group's diaries...")
    page.forgetGroup:SetColor(ACCENT[1], ACCENT[2], ACCENT[3])
    c:Place(page.forgetGroup, 18)
end

SettingsUI.StatusText = StatusText

SettingsUI.RegisterSection("sync", { order = 45, label = "Sync",
    about = "Sharing your diary with friends", build = BuildSync })
