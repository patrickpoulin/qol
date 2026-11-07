-- The built-in Helpers tab: on/off switches for small helpers such as threat %.
local _, ns = ...
local QoL = ns.QoL
local T = ns.Todo

local SCROLLBAR_SPACE = 24
local ROW_HEIGHT = 26

table.insert(T.referenceTabs, {
    id = "ref:helpers", name = "Helpers", reference = true, panel = "helpers", tasks = {},
})

-- Each helper: label, tooltip, and get/set for its on/off state.
local HELPERS = {
    {
        label = "Show threat % on the target frame",
        tooltip = "Shows how close you are to pulling aggro from the enemy you have targeted. "
            .. "100% means you pull. Type /qol threat unlock to move it.",
        get = function() return ns.Threat.db.enabled end,
        set = function(on) ns.Threat:SetEnabled(on) end,
    },
}

local function createCheck(parent, helper)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    local label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    label:SetText(helper.label)
    check.label = label
    check:SetScript("OnClick", function(btn) helper.set(btn:GetChecked() and true or false) end)
    check:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        GameTooltip:SetText(helper.label, 1, 1, 1)
        GameTooltip:AddLine(helper.tooltip, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    check:SetScript("OnLeave", GameTooltip_Hide)
    check.helper = helper
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
    for i, helper in ipairs(HELPERS) do
        local check = createCheck(child, helper)
        check:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        scroll.checks[i] = check
    end
    self.helpersPanel = scroll
end

function T:RefreshHelpers()
    local panel = self.helpersPanel
    if not panel then return end
    for _, check in ipairs(panel.checks) do
        check:SetChecked(check.helper.get())
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
    child:SetHeight(#panel.checks * ROW_HEIGHT + 4)
    for _, check in ipairs(panel.checks) do
        check.label:SetWidth(width - 30)
    end
end
