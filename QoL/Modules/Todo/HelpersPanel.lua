-- The built-in Misc tab (id ref:helpers): on/off switches for small helpers such as threat %.
local _, ns = ...
local QoL = ns.QoL
local T = ns.Todo

local SCROLLBAR_SPACE = 24
local ROW_HEIGHT = 26
local SLIDER_HEIGHT = 40
local HEADER_HEIGHT = 26
local INDENT = 22

table.insert(T.referenceTabs, {
    id = "ref:helpers", name = "Misc", reference = true, panel = "helpers", tasks = {},
})

-- Each helper: label, tooltip, and get/set for its value. A helper with
-- kind = "slider" holds a number from min to max; the rest are checkboxes.
local function petOn() return ns.PetHealth.db.enabled end

local HELPERS = {
    { kind = "header", label = "Threat" },
    {
        label = "Show threat % on the target frame",
        tooltip = "Shows how close you are to pulling aggro from the enemy you have targeted. "
            .. "100% means you pull. Type /qol threat unlock to move it.",
        get = function() return ns.Threat.db.enabled end,
        set = function(on) ns.Threat:SetEnabled(on) end,
    },
    {
        label = "Show threat % above the target's nameplate",
        tooltip = "Shows the same threat % just above your target's nameplate. "
            .. "Nameplates have to be turned on (V by default) for it to show.",
        get = function() return ns.Threat.db.nameplate end,
        set = function(on) ns.Threat:SetPlateEnabled(on) end,
    },

    { kind = "header", label = "Pet health" },
    {
        label = "Warn when your pet's health is low",
        tooltip = "Turns the whole low pet health warning on or off. "
            .. "Type /qol pet test to preview it.",
        get = function() return ns.PetHealth.db.enabled end,
        set = function(on) ns.PetHealth:SetOption("enabled", on) end,
    },
    {
        indent = true, enabledIf = petOn,
        label = "Glow on the pet portrait and health bar",
        tooltip = "A slow orange glow at the warning level, then a fast red pulse at the danger level.",
        get = function() return ns.PetHealth.db.glow end,
        set = function(on) ns.PetHealth:SetOption("glow", on) end,
    },
    {
        indent = true, enabledIf = petOn,
        label = "Big text at the danger level",
        tooltip = "Shows PET and its health above your character. "
            .. "Hunters also see Mend Pet when it's ready to cast.",
        get = function() return ns.PetHealth.db.text end,
        set = function(on) ns.PetHealth:SetOption("text", on) end,
    },
    {
        indent = true, enabledIf = petOn,
        label = "Red screen edges at the danger level",
        tooltip = "Pulses the edges of the screen red while your pet is at the danger level. "
            .. "It looks a lot like your own low health warning.",
        get = function() return ns.PetHealth.db.screen end,
        set = function(on) ns.PetHealth:SetOption("screen", on) end,
    },
    {
        indent = true, enabledIf = petOn,
        label = "Sound at the danger level",
        tooltip = "Plays the raid warning sound once when your pet drops to the danger level. "
            .. "Clients that hide unit health from addons can't play it.",
        get = function() return ns.PetHealth.db.sound end,
        set = function(on) ns.PetHealth:SetOption("sound", on) end,
    },
    {
        kind = "slider", indent = true, enabledIf = petOn,
        label = "Warning level",
        tooltip = "The orange glow starts when your pet's health drops to this %.",
        min = 10, max = 95, step = 5,
        format = function(v) return ("%d%%"):format(v) end,
        get = function() return ns.PetHealth.db.warn end,
        set = function(v) ns.PetHealth:SetWarn(v) end,
    },
    {
        kind = "slider", indent = true, enabledIf = petOn,
        label = "Danger level",
        tooltip = "The red pulse, text and sound start when your pet's health drops to this %.",
        min = 5, max = 90, step = 5,
        format = function(v) return ("%d%%"):format(v) end,
        get = function() return ns.PetHealth.db.danger end,
        set = function(v) ns.PetHealth:SetDanger(v) end,
    },

    { kind = "header", label = "Map" },
    {
        label = "Show zeppelin docks on the map and minimap",
        tooltip = "Puts a pin on every zeppelin platform. Hover it to see where that zeppelin goes. "
            .. "Type /qol zeppelins list to print them all in chat.",
        get = function() return ns.Zeppelins.db.enabled end,
        set = function(on) ns.Zeppelins:SetEnabled(on) end,
    },
    {
        label = "Show boat docks on the map and minimap",
        tooltip = "Puts a gold pin on every boat and ferry dock. Hover it to see where that boat goes. "
            .. "Some dock spots are approximate; stand on the dock and type /qol zeppelins here to fix one.",
        get = function() return ns.Zeppelins.db.boats end,
        set = function(on) ns.Zeppelins:SetBoatsEnabled(on) end,
    },
    {
        label = "Show flight masters on the map and minimap",
        tooltip = "Puts a pin on every flight master: blue for Alliance, red for Horde, green for both. "
            .. "Hover it to see who it is and where. Type /qol flights list to print them all in chat.",
        get = function() return ns.FlightMasters.db.enabled end,
        set = function(on) ns.FlightMasters:SetEnabled(on) end,
    },
    {
        indent = true, enabledIf = function() return ns.FlightMasters.db.enabled end,
        label = "Only my faction's flight masters",
        tooltip = "Hides the other faction's flight masters. Neutral ones, like Ratchet and Marshal's Refuge, still show.",
        get = function() return ns.FlightMasters.db.ownFaction end,
        set = function(on) ns.FlightMasters:SetOwnFactionOnly(on) end,
    },

    { kind = "header", label = "Window" },
    {
        kind = "slider",
        label = "Background opacity",
        tooltip = "How see-through the QoL window's background is. The text and border stay solid.",
        min = 0, max = 1, step = 0.05,
        format = function(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end,
        get = function() return T.db.bgAlpha end,
        set = function(v) T:SetBackgroundAlpha(v) end,
    },

    { kind = "header", label = "Action bar" },
    {
        label = "Hide the gryphons beside the main action bar",
        tooltip = "Hides the two gryphon pictures on the left and right ends of the main action bar. "
            .. "Your buttons and keybinds are untouched, and it works in combat. "
            .. "Type /qol gryphons to switch it from chat.",
        get = function() return ns.ActionBar.db.hideGryphons end,
        set = function(on) ns.ActionBar:SetHideGryphons(on) end,
    },
}

local function setTooltip(frame, helper)
    frame:SetScript("OnEnter", function(f)
        GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
        GameTooltip:SetText(helper.label, 1, 1, 1)
        GameTooltip:AddLine(helper.tooltip, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", GameTooltip_Hide)
end

-- A gold section title with a faint line under it.
local function createHeader(parent, helper)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(HEADER_HEIGHT)
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 5)
    label:SetText(helper.label)
    local line = row:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.25)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 2)
    line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 2)
    row.helper = helper
    row.Refresh = function() end
    return row
end

-- Dims a setting whose parent switch is off.
local function refreshEnabled(item, check)
    local helper = item.helper
    if not helper.enabledIf then return end
    local on = helper.enabledIf() and true or false
    item:SetAlpha(on and 1 or 0.45)
    if check and check.SetEnabled then check:SetEnabled(on) end
end

-- A plain horizontal slider: built by hand so it doesn't depend on
-- slider templates that differ between clients.
local function createSlider(parent, helper)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(SLIDER_HEIGHT)
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -2)
    label:SetText(helper.label)
    local value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    value:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -2)

    local slider = CreateFrame("Slider", nil, row)
    slider:SetOrientation("HORIZONTAL")
    slider:SetHeight(16)
    slider:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
    slider:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    slider:SetMinMaxValues(helper.min, helper.max)
    slider:SetValueStep(helper.step)
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
        v = math.floor(v / helper.step + 0.5) * helper.step
        value:SetText(helper.format(v))
        if not s.refreshing then helper.set(v) end
    end)
    slider:SetScript("OnMouseWheel", function(s, delta)
        s:SetValue(s:GetValue() + delta * helper.step)
    end)
    setTooltip(slider, helper)

    row.helper, row.slider, row.label = helper, slider, label
    row.Refresh = function()
        slider.refreshing = true
        slider:SetValue(helper.get())
        value:SetText(helper.format(helper.get()))
        slider.refreshing = false
        refreshEnabled(row)
    end
    return row
end

local function createCheck(parent, helper)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    local label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    label:SetText(helper.label)
    check.label = label
    check:SetScript("OnClick", function(btn) helper.set(btn:GetChecked() and true or false) end)
    setTooltip(check, helper)
    check.helper = helper
    check.Refresh = function()
        check:SetChecked(helper.get())
        refreshEnabled(check, check)
    end
    return check
end

function T:CreateHelpersPanel(parent)
    local scroll = QoL.CreateScrollFrame(parent)
    scroll:SetPoint("TOPLEFT", self.tabStrip, "BOTTOMLEFT", 0, -6)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -SCROLLBAR_SPACE, 4)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    scroll:Hide()

    scroll.checks = {}
    local y = 0
    for i, helper in ipairs(HELPERS) do
        local item
        local x = helper.indent and INDENT or 0
        if helper.kind == "header" then
            item = createHeader(child, helper)
            item:SetPoint("RIGHT", child, "RIGHT", 0, 0)
            -- A little extra space above every heading but the first.
            if i > 1 then y = y + 6 end
            item:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
            y = y + HEADER_HEIGHT
        elseif helper.kind == "slider" then
            item = createSlider(child, helper)
            item:SetPoint("RIGHT", child, "RIGHT", 0, 0)
            item:SetPoint("TOPLEFT", child, "TOPLEFT", x, -y - 2)
            y = y + SLIDER_HEIGHT + 2
        else
            item = createCheck(child, helper)
            item:SetPoint("TOPLEFT", child, "TOPLEFT", x, -y)
            y = y + ROW_HEIGHT
        end
        scroll.checks[i] = item
    end
    scroll.contentHeight = y
    self.helpersPanel = scroll
end

function T:RefreshHelpers()
    local panel = self.helpersPanel
    if not panel then return end
    for _, item in ipairs(panel.checks) do
        item.Refresh()
    end
end

function T:ShowHelpers()
    self.helpersPanel:Show()
    self:RefreshHelpers()
    self:LayoutHelpers()
end

function T:LayoutHelpers()
    local panel = self.helpersPanel
    if not panel or not panel:IsShown() then return end
    local width = self:GetContentWidth() - SCROLLBAR_SPACE
    if width <= 0 then return end
    local child = panel:GetScrollChild()
    child:SetWidth(width)
    child:SetHeight(panel.contentHeight + 4)
    for _, item in ipairs(panel.checks) do
        if not item.helper.kind then
            item.label:SetWidth(width - 30 - (item.helper.indent and INDENT or 0))
        end
    end
end
