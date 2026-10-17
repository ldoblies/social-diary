-- The label tucked under the book: back to the introduction. Shown while
-- the introduction (the frontispiece, UI/Journal/Frontispiece.lua, and the
-- front matter, UI/Journal/Front.lua) is unfinished; the book refreshes it
-- as its pages turn (UI/Journal/Book.lua).
--
-- A reader who leaves the introduction by a ribbon, before its last corner,
-- finds a label tucked under the book on the pages they turn to: back to
-- the introduction, OK, or Dismiss for good. It goes once the introduction
-- has been turned through to its end (introDone), or dismissed. A loose
-- sheet (UI/Paper/Sheet.lua) hanging below the book's right page, clear of
-- the ribbons, folded once and turned a little like the slip at login.

local addonName, ns = ...

local Style = ns.Style
local FONT = Style.FONT

local LABEL = { w = 300, h = 46, margin = 16, line = 23, right = -70, below = 6 }
local LABEL_CREASE = {
    columns = { 0, 0.5, 1 }, rows = { 0, 1 }, folds = { columns = { [2] = 1 }, rows = {} },
    crumple = 0.4, drift = 0.3, edge = 0.5, wander = 0, shift = 2, lean = 2,
}

local label

local function BuildLabel(journal)
    local host = CreateFrame("Frame", nil, journal)
    host:SetSize(LABEL.w + 40, LABEL.h + 30)
    host:SetPoint("TOPRIGHT", journal, "BOTTOMRIGHT", LABEL.right, -LABEL.below)
    host:Hide()

    local view, K = ns.UI.LooseSheet(host, LABEL.w, LABEL.h, { crease = LABEL_CREASE, quiet = true })
    view:EnableMouse(false)
    local S, M = view.sheet, LABEL.margin
    host.view = view

    host.text = Style.Text(S, FONT.body)
    host.text:SetText("Back to the introduction?")
    host.ok = K.Link(FONT.strong, function() ns.UI.Journal.TurnTo("frontispiece") end)
    host.ok:SetText("OK")
    host.dismiss = K.Link(FONT.body, function()
        ns.SetSetting("introDone", true)
        ns.UI.Journal.RefreshIntroLabel()
    end)
    host.dismiss:SetText("Dismiss")

    function host:Lay()
        K.Fall("label" .. (ns.ownGUID or ""))
        K.Lay()
        K.PlaceText(self.text, M, LABEL.line)
        local x = LABEL.w - M - K.Width(self.dismiss.label)
        self.dismiss:PlaceAt(x, LABEL.line)
        self.ok:PlaceAt(x - 14 - K.Width(self.ok.label), LABEL.line)
    end
    host:SetScript("OnHide", function() view:Hide(true) end)
    return host
end

-- Shown on any of the ribbons' pages while the introduction is unfinished;
-- hidden on its own leaves (the flyleaves, UI/Journal/Pages.lua) and once
-- it is done.
function ns.UI.Journal.RefreshIntroLabel()
    local open = ns.UI.Journal.Page(ns.UI.JournalView())
    local journal = ns.UI.JournalShowing() and ns.UI.JournalFrame()
    local due = journal and not ns.Setting("introDone") and not (open and open.flyleaf)
    if not due then
        if label and label:IsShown() then label:Hide() end
        return
    end
    label = label or BuildLabel(journal)
    label:Show()
    -- The book closing put the sheet away with it.
    if label.view:IsShown() then return end
    label:Lay()
    label.view:Show()
end

-- Test hook: the label.
function ns.UI.IntroLabel()
    return label
end
