-- The built-in CDs tab: pick spells and racials from your spellbook for the
-- cooldown window, and set how that window looks.
-- The data and window live in the Cooldowns module (ns.Cooldowns), which
-- loads after this file, so it is only looked up when the tab is used.
local _, ns = ...
local QoL = ns.QoL
local T = ns.Todo

local SCROLLBAR_SPACE = 24
local ROW_HEIGHT, ICON_SIZE = 24, 20
local CHECK_SIZE = 24
local OPTIONS_HEIGHT = 2 * CHECK_SIZE + 34 -- two rows of checkboxes, then the size slider
local SEARCH_HEIGHT = 26
local BOTTOM_BAR = 26

table.insert(T.referenceTabs, {
    id = "ref:cds", name = "CDs", reference = true, panel = "cds", tasks = {},
})

local function cds() return ns.Cooldowns end

local function formatCooldown(s)
    if not s or s <= 0 then return "" end
    if s >= 3600 then return ("%gh"):format(math.floor(s / 360 + 0.5) / 10) end
    if s >= 60 then return ("%gm"):format(math.floor(s / 6 + 0.5) / 10) end
    return ("%ds"):format(s)
end

local function setTooltip(frame, title, text)
    frame:SetScript("OnEnter", function(f)
        GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        GameTooltip:AddLine(text, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", GameTooltip_Hide)
end

-- A checkbox bound to one of the Cooldowns module's per-character options.
local function createOption(parent, key, label, tooltip)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(CHECK_SIZE, CHECK_SIZE)
    check.label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    check.label:SetPoint("LEFT", check, "RIGHT", 0, 1)
    check.label:SetJustifyH("LEFT")
    check.label:SetWordWrap(false)
    check.label:SetText(label)
    check:SetScript("OnClick", function(btn)
        local C = cds()
        if C then C:SetOption(key, btn:GetChecked() and true or false) end
    end)
    setTooltip(check, label, tooltip)
    check.key = key
    return check
end

-- Icon size slider, built by hand like the Misc tab's.
local function createSizeSlider(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(32)
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
    label:SetText("Icon size")
    local value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    value:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -2)

    local slider = CreateFrame("Slider", nil, row)
    slider:SetOrientation("HORIZONTAL")
    slider:SetHeight(16)
    slider:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)
    slider:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    slider:SetValueStep(1)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    slider:EnableMouse(true)
    slider:EnableMouseWheel(true)
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", slider, "LEFT", 0, 0)
    track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    track:SetHeight(4)
    track:SetColorTexture(0.4, 0.4, 0.45, 0.9)
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local thumb = slider:GetThumbTexture()
    if thumb then thumb:SetSize(32, 32) end

    slider:SetScript("OnValueChanged", function(s, v)
        v = math.floor(v + 0.5)
        value:SetText(("%d px"):format(v))
        local C = cds()
        if C and not s.refreshing then C:SetIconSize(v) end
    end)
    slider:SetScript("OnMouseWheel", function(s, delta) s:SetValue(s:GetValue() + delta) end)
    setTooltip(slider, "Icon size", "How big each icon in the cooldown window is. "
        .. "You can also drag the window's bottom-right corner while it's unlocked.")

    row.Refresh = function(C)
        slider.refreshing = true
        slider:SetMinMaxValues(C.MIN_SIZE, C.MAX_SIZE)
        slider:SetValue(C.charDB.iconSize)
        value:SetText(("%d px"):format(C.charDB.iconSize))
        slider.refreshing = false
    end
    return row
end

local function rowOnEnter(row)
    local entry = row.entry
    if not entry then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if entry.id and GameTooltip.SetSpellByID and pcall(GameTooltip.SetSpellByID, GameTooltip, entry.id) then
        GameTooltip:AddLine(" ")
    else
        GameTooltip:SetText(entry.name, 1, 1, 1)
    end
    if entry.missing then
        GameTooltip:AddLine("Not in this character's spellbook right now, so it isn't shown.", 1, 0.5, 0.5, true)
    end
    GameTooltip:AddLine(row.check:GetChecked() and "Click to stop tracking." or "Click to show it in the cooldown window.",
        0.5, 0.5, 0.5, true)
    GameTooltip:Show()
end

local function toggleRow(row)
    local C = cds()
    if C and row.entry then C:SetTracked(row.entry.name, not C:IsTracked(row.entry.name)) end
end

local function createRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row:SetScript("OnEnter", rowOnEnter)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", toggleRow)

    local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    check:SetSize(22, 22)
    check:SetPoint("LEFT", row, "LEFT", -2, 0)
    check:SetScript("OnClick", function() toggleRow(row) end)
    check:SetScript("OnEnter", function() rowOnEnter(row) end)
    check:SetScript("OnLeave", GameTooltip_Hide)
    row.check = check

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("LEFT", check, "RIGHT", 1, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.cd = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.cd:SetPoint("RIGHT", row, "RIGHT", -4, 0)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
    row.name:SetPoint("RIGHT", row.cd, "LEFT", -4, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    return row
end

function T:CreateCooldownsPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", self.tabStrip, "BOTTOMLEFT", 0, -4)
    panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 4)
    panel:Hide()
    self.cdsPanel = panel

    -- Window settings: two columns of checkboxes, then the size slider.
    panel.options = {
        createOption(panel, "shown", "Show window",
            "Shows the cooldown window. Type /qol cds reset if you lose it off screen."),
        createOption(panel, "locked", "Lock window",
            "Stops the window moving or resizing and lets clicks go through it. "
            .. "Hover the window to get its Unlock button back."),
        createOption(panel, "hideReady", "Hide ready spells",
            "Only shows spells that are on cooldown, so the window is a queue of what comes back next."),
        createOption(panel, "horizontal", "Side by side",
            "Lines the icons up in a row instead of a column. The soonest one is still first."),
    }
    panel.options[1]:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    panel.options[3]:SetPoint("TOPLEFT", panel.options[1], "BOTTOMLEFT", 0, 2)

    panel.size = createSizeSlider(panel)
    panel.size:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -2 * CHECK_SIZE)
    panel.size:SetPoint("RIGHT", panel, "RIGHT", -16, 0)

    local search = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    search:SetHeight(20)
    search:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -OPTIONS_HEIGHT)
    search:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -OPTIONS_HEIGHT)
    search:SetAutoFocus(false)
    search:SetMaxLetters(40)
    search:SetTextInsets(14, 0, 0, 0)
    local icon = search:CreateTexture(nil, "OVERLAY")
    icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", search, "LEFT", 0, -1)
    icon:SetVertexColor(0.6, 0.6, 0.6)
    local hint = search:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("LEFT", icon, "RIGHT", 2, 1)
    hint:SetText("Search your spellbook")
    search:SetScript("OnTextChanged", function(box)
        hint:SetShown(box:GetText() == "" and not box:HasFocus())
        self:RefreshCooldowns()
    end)
    search:SetScript("OnEditFocusGained", function() hint:Hide() end)
    search:SetScript("OnEditFocusLost", function(box) hint:SetShown(box:GetText() == "") end)
    search:SetScript("OnEscapePressed", function(box) box:SetText("") box:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
    panel.search = search

    panel.filter = createOption(panel, "onlyCooldowns", "Only spells with a cooldown",
        "Leaves spells without a cooldown out of the list below. Spells you already track always show.")
    panel.filter:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)

    local scroll = QoL.CreateScrollFrame(panel)
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -(OPTIONS_HEIGHT + SEARCH_HEIGHT))
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -SCROLLBAR_SPACE, BOTTOM_BAR)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    panel.scroll, panel.child, panel.rows = scroll, child, {}

    local empty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("TOPLEFT", scroll, "TOPLEFT", 6, -10)
    empty:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
    empty:SetJustifyH("LEFT")
    panel.empty = empty
end

function T:ShowCooldowns()
    self.cdsPanel:Show()
    self:RefreshCooldowns()
end

function T:RefreshCooldowns()
    local panel = self.cdsPanel
    if not panel or not panel:IsShown() then return end
    local C = cds()
    if not (C and C.charDB) then
        panel.empty:SetText("The cooldown window isn't loaded.")
        panel.empty:Show()
        return
    end

    for _, check in ipairs(panel.options) do check:SetChecked(C.charDB[check.key]) end
    panel.filter:SetChecked(C.charDB.onlyCooldowns)
    panel.filter:SetShown(C:CanFilterCooldowns())
    panel.size.Refresh(C)

    local list = C:GetPickList(panel.search:GetText())
    local rows, child = panel.rows, panel.child
    for i, entry in ipairs(list) do
        local row = rows[i] or createRow(child)
        rows[i] = row
        row.entry = entry
        local tracked = C:IsTracked(entry.name)
        row.check:SetChecked(tracked)
        row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.icon:SetDesaturated(entry.missing and true or false)
        row.name:SetText(entry.name)
        if entry.missing then
            row.name:SetTextColor(0.6, 0.6, 0.6)
        elseif tracked then
            row.name:SetTextColor(1, 0.82, 0)
        else
            row.name:SetTextColor(1, 1, 1)
        end
        row.cd:SetText(formatCooldown(entry.cooldown))
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:SetPoint("RIGHT", child, "RIGHT", 0, 0)
        row:Show()
    end
    for i = #list + 1, #rows do rows[i]:Hide() end

    if #list > 0 then
        panel.empty:Hide()
    else
        panel.empty:SetText(panel.search:GetText() ~= "" and "No matches." or "No spells found in your spellbook.")
        panel.empty:Show()
    end
    self:LayoutCooldowns()
end

function T:LayoutCooldowns()
    local panel = self.cdsPanel
    if not panel or not panel:IsShown() then return end
    local width = self:GetContentWidth()
    if width <= 0 then return end
    -- Second column of checkboxes starts halfway across.
    local half = math.floor(width / 2)
    for i, check in ipairs(panel.options) do
        check.label:SetWidth(math.max(1, half - CHECK_SIZE - 4))
        if i % 2 == 0 then
            check:ClearAllPoints()
            check:SetPoint("LEFT", panel.options[i - 1], "LEFT", half, 0)
        end
    end
    panel.filter.label:SetWidth(math.max(1, width - CHECK_SIZE - 20))

    local shown = 0
    for _, row in ipairs(panel.rows) do
        if row:IsShown() then shown = shown + 1 end
    end
    panel.child:SetWidth(math.max(1, width - SCROLLBAR_SPACE))
    panel.child:SetHeight(math.max(1, shown * ROW_HEIGHT))
end
