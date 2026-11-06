-- Tab strip: one button per tab plus "+". Tabs wrap onto extra rows when
-- they don't fit the window width.
local _, ns = ...
local QoL = ns.QoL
local T = ns.Todo

local TAB_HEIGHT, GAP, PAD = 20, 4, 14

local TAB_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
}

local function styleTab(button, selected, reference)
    if reference and not selected then
        button:SetBackdropColor(0.25, 0.2, 0, 0.35)
        button:SetBackdropBorderColor(0.8, 0.65, 0.2, 1)
        button.text:SetFontObject("GameFontNormalSmall")
    elseif selected then
        button:SetBackdropColor(0.2, 0.45, 0.8, 0.45)
        button:SetBackdropBorderColor(0.35, 0.6, 1, 1)
        button.text:SetFontObject("GameFontHighlightSmall")
    else
        button:SetBackdropColor(0, 0, 0, 0.3)
        button:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
        button.text:SetFontObject("GameFontNormalSmall")
    end
end

local function createTabButton(self, parent)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetHeight(TAB_HEIGHT)
    b:SetBackdrop(TAB_BACKDROP)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("CENTER")
    b.text:SetWordWrap(false)
    b:SetScript("OnClick", function(btn, mouse)
        if mouse == "RightButton" then
            if self:GetTab(btn.tabId).reference then
                return QoL:Print("built-in tabs can't be renamed or deleted.")
            end
            QoL.ShowContextMenu(btn, {
                { text = "Rename", func = function() self:PromptRenameTab(btn.tabId) end },
                { text = "Delete", func = function() self:ConfirmDeleteTab(btn.tabId) end },
            })
        else
            self:SetActiveTab(btn.tabId)
        end
    end)
    b:SetScript("OnDoubleClick", function(btn)
        if not self:GetTab(btn.tabId).reference then
            self:PromptRenameTab(btn.tabId)
        end
    end)
    return b
end

function T:CreateTabStrip(parent)
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    strip:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    strip:SetHeight(TAB_HEIGHT)
    strip.buttons = {}

    local add = CreateFrame("Button", nil, strip, "BackdropTemplate")
    add:SetSize(TAB_HEIGHT + 2, TAB_HEIGHT)
    add:SetBackdrop(TAB_BACKDROP)
    add:SetBackdropColor(0, 0, 0, 0.2)
    add:SetBackdropBorderColor(0.4, 0.4, 0.45, 0.8)
    add:SetNormalFontObject("GameFontHighlight")
    add:SetText("+")
    add:SetScript("OnClick", function() self:PromptNewTab() end)
    add:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:SetText("New tab")
        GameTooltip:AddLine("Double-click a tab to rename it. Right-click for more.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    add:SetScript("OnLeave", GameTooltip_Hide)
    strip.add = add

    self.tabStrip = strip
end

-- Your own tabs first, then the built-in reference tabs.
function T:GetStripTabs()
    local list = {}
    for _, tab in ipairs(self.db.tabs) do table.insert(list, tab) end
    for _, tab in ipairs(self.referenceTabs) do table.insert(list, tab) end
    return list
end

function T:RefreshTabs()
    local strip = self.tabStrip
    local active = self:GetActiveTab()
    local tabs = self:GetStripTabs()
    for i, tab in ipairs(tabs) do
        local b = strip.buttons[i] or createTabButton(self, strip)
        strip.buttons[i] = b
        b.tabId = tab.id
        b.text:SetText(tab.name)
        styleTab(b, tab == active, tab.reference)
        b:Show()
    end
    for i = #tabs + 1, #strip.buttons do
        strip.buttons[i]:Hide()
    end
    self:LayoutTabs()
end

-- Place buttons left to right, wrapping to a new row when the next one won't fit.
function T:LayoutTabs()
    local strip = self.tabStrip
    if not strip then return end
    local width = self:GetContentWidth()
    if not width or width <= 0 then return end

    local x, row = 0, 0
    local function place(button, w)
        if x > 0 and x + w > width then
            x, row = 0, row + 1
        end
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", strip, "TOPLEFT", x, -row * (TAB_HEIGHT + GAP))
        x = x + w + GAP
    end

    for i = 1, #self:GetStripTabs() do
        local b = strip.buttons[i]
        if not b then return end
        local w = math.min(b.text:GetUnboundedStringWidth() + PAD, width)
        b:SetWidth(w)
        b.text:SetWidth(w - 6)
        place(b, w)
    end
    place(strip.add, strip.add:GetWidth())
    strip:SetHeight((row + 1) * TAB_HEIGHT + row * GAP)
end
