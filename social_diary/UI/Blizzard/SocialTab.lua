-- A side tab on the Social window (O) that opens the journal.
--
-- The window's own tabs are unnamed 55x55 buttons stacked down its right
-- edge, 3 apart, built from the client's common-sidetab atlases. Ours copies
-- their art and hangs below the last one that is shown. It is a plain child
-- button: it never joins Blizzard's tab system (taint), so it is never
-- "selected". Clicking it closes the Social window and opens the journal.

local addonName, ns = ...

local GAP = 3

-- Book glyphs in the style of the window's gold tab icons, then the item icon.
local ICON_ATLASES = { "Campaign-QuestLog-LoreBook", "loreobject-32x32" }

local tab

local function HasAtlas(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local function SetAtlasOr(texture, atlas, color)
    if HasAtlas(atlas) then
        texture:SetAtlas(atlas)
    else
        texture:SetColorTexture(unpack(color))
    end
end

-- Blizzard's tabs, told apart from the window's other buttons by their parts.
local function NativeTabs(window)
    local tabs = {}
    for _, child in ipairs({ window:GetChildren() }) do
        if child ~= tab and child.Icon and child.SelectedTexture and child.HighlightTexture then
            tabs[#tabs + 1] = child
        end
    end
    return tabs
end

local function Place(window)
    local last
    for _, native in ipairs(NativeTabs(window)) do
        if native:IsShown() and (not last or native:GetBottom() < last:GetBottom()) then
            last = native
        end
    end
    tab:ClearAllPoints()
    if last then
        tab:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -GAP)
    else
        tab:SetPoint("TOPLEFT", window, "TOPRIGHT", 0, -122)
    end
end

local function Build(window)
    tab = CreateFrame("Button", nil, window)
    tab:SetSize(55, 55)

    local bg = tab:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(55, 60)
    bg:SetPoint("CENTER")
    SetAtlasOr(bg, "common-sidetab", { 0.12, 0.09, 0.06, 1 })
    if HasAtlas("common-sidetab-mask") then
        local mask = tab:CreateMaskTexture()
        mask:SetAllPoints(bg)
        mask:SetAtlas("common-sidetab-mask")
        bg:AddMaskTexture(mask)
    end

    tab.icon = tab:CreateTexture(nil, "ARTWORK")
    tab.icon:SetPoint("CENTER", -4, 0)
    local atlas
    for _, name in ipairs(ICON_ATLASES) do
        if HasAtlas(name) then atlas = name break end
    end
    if atlas then
        tab.icon:SetSize(33, 33)
        tab.icon:SetAtlas(atlas)
    else
        tab.icon:SetSize(28, 28)
        ns.Style.SetTexture(tab.icon, "book", 0.6, 0.45, 0.2, 1)
        tab.icon:SetTexCoord(unpack(ns.Style.ICON_CROP))
    end
    -- Like the window's inactive tabs: muted until pointed at.
    tab.icon:SetAlpha(0.75)

    local hover = tab:CreateTexture(nil, "HIGHLIGHT")
    hover:SetSize(55, 60)
    hover:SetPoint("CENTER")
    if HasAtlas("common-sidetab-hover") then hover:SetAtlas("common-sidetab-hover") end

    ns.Style.Tooltip(tab, { { "Social Diary" }, { "Open your journal.", 1, 1, 1 } }, "ANCHOR_RIGHT",
        function(self, over) self.icon:SetAlpha(over and 1 or 0.75) end)
    tab:SetScript("OnClick", function()
        if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
        HideUIPanel(window)
        ns.UI.ShowJournal()
    end)

    -- Tabs come and go (Recruit a Friend, for one), so follow the last one.
    local function Replace() Place(window) end
    window:HookScript("OnShow", Replace)
    for _, native in ipairs(NativeTabs(window)) do
        native:HookScript("OnShow", Replace)
        native:HookScript("OnHide", Replace)
    end
    Place(window)
end

local function TryBuild()
    if tab or not SocialUIFrame then return end
    Build(SocialUIFrame)
end

ns.On("PLAYER_LOGIN", TryBuild)

-- In case the window is load-on-demand.
ns.On("ADDON_LOADED", function()
    if not tab then TryBuild() end
end)
