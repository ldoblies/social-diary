-- Settings: About, the last section (UI/Settings/Page.lua lists them; the
-- controls are UI/Settings/Kit.lua's): thanks to those who helped.

local addonName, ns = ...

local Style = ns.Style
local FONT = Style.FONT
local BOOK = ns.UI.Journal.BOOK
local SettingsUI = ns.UI.Settings
local Kit = SettingsUI.Kit
local INDENT = Kit.INDENT

-- The About page's thanks, in the order they were given.
local TESTERS = { "Gunther Guntherino", "Mooguy Mooperson", "Koko Skybluff" }

local function BuildAbout(pane, c)
    local page = SettingsUI.page

    c:Heading("Thanks")
    local intro = Style.Text(pane, FONT.body)
    intro:SetWidth(BOOK.RIGHT_W)
    intro:SetText("Willing impromptu Beta Testers:")
    c:Place(intro, intro:GetStringHeight(), 0, 8)

    page.testers = {}
    for i, name in ipairs(TESTERS) do
        local line = Style.Text(pane, FONT.strong)
        line:SetText(name)
        page.testers[i] = c:Place(line, line:GetStringHeight(), INDENT, 4)
    end
end

SettingsUI.RegisterSection("about", { order = 60, label = "About",
    about = "Thanks to those who helped", build = BuildAbout })
