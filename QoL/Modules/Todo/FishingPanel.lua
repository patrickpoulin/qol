-- The built-in Fishing tab: pole swap button, lure timer and lure buttons.
--
-- Applying a lure needs a secure button (it runs "/use <lure>" then "/use 16").
-- A window that holds secure buttons can't be hidden or moved in combat, so the
-- lure buttons are parked in a hidden frame for the length of each fight.
local _, ns = ...
local QoL = ns.QoL
local T = ns.Todo

local SCROLLBAR_SPACE = 24
local ROW_HEIGHT, ICON_SIZE = 22, 18
local LURE_TOP = 124 -- y offset of the first lure row

table.insert(T.referenceTabs, {
    id = "ref:fishing", name = "Fishing", reference = true, panel = true, tasks = {},
})

local stash = CreateFrame("Frame", nil, UIParent)
stash:Hide()

local MODIFIER_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
}

-- Wait for the next key press and make it the fishing key. Escape cancels.
local function captureKey(button, onDone)
    local catcher = button.catcher
    if not catcher then
        catcher = CreateFrame("Frame", nil, button)
        catcher:EnableKeyboard(true)
        catcher:SetPropagateKeyboardInput(false)
        button.catcher = catcher
    end
    button:SetText("Press a Key...")
    catcher:Show()
    catcher:SetScript("OnKeyDown", function(frame, key)
        if MODIFIER_KEYS[key] then return end
        frame:Hide()
        if key == "ESCAPE" then return onDone(nil, true) end
        local prefix = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
            .. (IsShiftKeyDown() and "SHIFT-" or "")
        onDone(prefix .. key)
    end)
end

local function formatTime(seconds)
    return ("%d:%02d"):format(math.floor(seconds / 60), math.floor(seconds % 60))
end

local function createLureButton(parent, lure)
    local b = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    b:SetHeight(ROW_HEIGHT)
    b:RegisterForClicks("LeftButtonUp")
    b:SetAttribute("useOnKeyDown", false) -- newer clients: act on the release
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext", ("/use item:%d\n/use 16"):format(lure.id))
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(ICON_SIZE, ICON_SIZE)
    b.icon:SetPoint("LEFT", b, "LEFT", 2, 0)
    local _, _, _, _, icon = QoL.GetItemInfoInstant(lure.id)
    b.icon:SetTexture(icon)

    b.count = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.count:SetPoint("RIGHT", b, "RIGHT", -4, 0)

    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.name:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
    b.name:SetPoint("RIGHT", b.count, "LEFT", -4, 0)
    b.name:SetJustifyH("LEFT")
    b.name:SetWordWrap(false)

    b.lure = lure
    b:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(lure.id)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

function T:CreateFishingPanel(parent)
    local F = ns.Fishing
    local scroll = QoL.CreateScrollFrame(parent)
    scroll:SetPoint("TOPLEFT", self.tabStrip, "BOTTOMLEFT", 0, -6)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -SCROLLBAR_SPACE, 4)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    scroll:Hide()
    self.fishPanel = scroll

    local pole = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pole:SetPoint("TOPLEFT", child, "TOPLEFT", 2, 0)
    pole:SetPoint("RIGHT", child, "RIGHT", -2, 0)
    pole:SetJustifyH("LEFT")
    pole:SetWordWrap(false)
    scroll.pole = pole

    local swap = CreateFrame("Button", nil, child, "UIPanelButtonTemplate")
    swap:SetHeight(24)
    swap:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -18)
    swap:SetPoint("RIGHT", child, "RIGHT", 0, 0)
    swap:SetScript("OnClick", function() F:Swap() end)
    swap:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:SetText("Fishing pole")
        GameTooltip:AddLine("Swaps your weapons for your fishing pole, then back again. You can also type /qol fish, or put it in a macro.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    swap:SetScript("OnLeave", GameTooltip_Hide)
    scroll.swap = swap

    local setKey = CreateFrame("Button", nil, child, "UIPanelButtonTemplate")
    setKey:SetSize(100, 22)
    setKey:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -46)
    setKey:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    setKey:SetScript("OnClick", function(btn, mouse)
        if mouse == "RightButton" then
            if btn.catcher then btn.catcher:Hide() end
            return F:SetKey(nil)
        end
        captureKey(btn, function(key, cancelled)
            if cancelled then return self:RefreshFishing() end
            F:SetKey(key)
        end)
    end)
    setKey:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:SetText("Fishing key")
        GameTooltip:AddLine("With your pole on, press it to cast and again when the bobber splashes. It puts on your best lure first if the pole has none. Right-click to clear it.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    setKey:SetScript("OnLeave", GameTooltip_Hide)
    scroll.setKey = setKey

    local keyText = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    keyText:SetPoint("LEFT", child, "LEFT", 2, 0)
    keyText:SetPoint("TOP", setKey, "TOP", 0, -5)
    keyText:SetPoint("RIGHT", setKey, "LEFT", -4, 0)
    keyText:SetJustifyH("LEFT")
    keyText:SetWordWrap(false)
    scroll.keyText = keyText

    local lureStatus = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lureStatus:SetPoint("TOPLEFT", child, "TOPLEFT", 2, -78)
    lureStatus:SetJustifyH("LEFT")
    scroll.lureStatus = lureStatus

    local header = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", child, "TOPLEFT", 2, -102)
    header:SetText("Lures - click one to put it on your pole")
    scroll.header = header

    -- Ticks the lure timer once a second while the tab is open.
    local elapsed = 0
    scroll:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 1 then
            elapsed = 0
            self:UpdateLureStatus()
        end
    end)

    scroll.lureButtons = {}
    self:AttachLureButtons()

    local events = CreateFrame("Frame")
    events:RegisterEvent("BAG_UPDATE_DELAYED")
    events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    events:RegisterEvent("UNIT_INVENTORY_CHANGED")
    events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_INVENTORY_CHANGED" and unit ~= "player" then return end
        if event == "PLAYER_REGEN_DISABLED" then
            -- Combat lockdown starts just after this event, so park the buttons now.
            self:DetachLureButtons()
        elseif event == "PLAYER_REGEN_ENABLED" then
            self:AttachLureButtons()
        end
        if scroll:IsShown() then self:RefreshFishing() end
    end)
end

-- Create the lure buttons (first time) and put them on the panel.
function T:AttachLureButtons()
    if InCombatLockdown() then return end
    local panel = self.fishPanel
    local child = panel:GetScrollChild()
    for i, lure in ipairs(ns.Fishing.lures) do
        local b = panel.lureButtons[i] or createLureButton(child, lure)
        panel.lureButtons[i] = b
        b:SetParent(child)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -LURE_TOP - (i - 1) * ROW_HEIGHT)
        b:SetPoint("RIGHT", child, "RIGHT", 0, 0)
        b:Show()
    end
end

function T:DetachLureButtons()
    if InCombatLockdown() then return end
    for _, b in ipairs(self.fishPanel.lureButtons) do
        b:SetParent(stash)
        b:ClearAllPoints()
    end
end

function T:UpdateLureStatus()
    local F, panel = ns.Fishing, self.fishPanel
    local left = F:GetLureTimeLeft()
    if left then
        panel.lureStatus:SetText("Lure on your pole: |cff33ff99" .. formatTime(left) .. " left|r")
    elseif F:IsPoleEquipped() then
        panel.lureStatus:SetText("Lure on your pole: |cffff6060none|r")
    else
        panel.lureStatus:SetText("|cff999999Equip your pole to use a lure.|r")
    end
end

function T:RefreshFishing()
    local F, panel = ns.Fishing, self.fishPanel
    if not panel then return end
    local equipped = F:GetEquippedPoleLink()
    local inBags = F:FindPoleInBags()

    if equipped then
        panel.pole:SetText("Pole: " .. equipped .. " |cff33ff99(equipped)|r")
    elseif inBags then
        panel.pole:SetText("Pole: " .. inBags .. " |cff999999(in bags)|r")
    else
        panel.pole:SetText("|cffff6060No fishing pole in your bags.|r")
    end

    local state, reason = F:GetSwapState()
    if state == "equip" then
        panel.swap:SetText("Equip Fishing Pole")
    elseif state == "unequip" then
        local name = QoL.GetItemName(F.charDB.mainHand)
        panel.swap:SetText(name and ("Swap Back to " .. name) or "Swap Back to Weapons")
    else
        panel.swap:SetText(reason)
    end
    panel.swap:SetEnabled(state ~= nil)

    local key = F.db.key
    panel.keyText:SetText(key and ("Fishing key: |cff33ff99" .. key .. "|r") or "Fishing key: |cff999999not set|r")
    panel.setKey:SetText(key and "Change Key" or "Set Key")

    self:UpdateLureStatus()

    local inCombat = InCombatLockdown()
    panel.header:SetText(inCombat and "Lures - back after combat"
        or "Lures - click one to put it on your pole")
    if inCombat then return end -- buttons are parked; leave them alone
    local poleEquipped = equipped ~= nil
    for _, b in ipairs(panel.lureButtons) do
        local lure = b.lure
        local count = QoL.GetItemCount(lure.id) or 0
        b.name:SetText(("%s |cff999999+%d|r"):format(QoL.GetItemName(lure.id) or lure.name, lure.bonus))
        b.count:SetText(count > 0 and ("x" .. count) or "")
        local usable = count > 0 and poleEquipped
        b:SetEnabled(usable)
        b:SetAlpha(count > 0 and 1 or 0.4)
        b.icon:SetDesaturated(not usable)
    end
end

function T:ShowFishing()
    self.fishPanel:Show()
    self:RefreshFishing()
    self:LayoutFishing()
end

function T:LayoutFishing()
    local panel = self.fishPanel
    if not panel or not panel:IsShown() then return end
    local width = self:GetContentWidth() - SCROLLBAR_SPACE
    if width <= 0 then return end
    local child = panel:GetScrollChild()
    child:SetWidth(width)
    child:SetHeight(LURE_TOP + #ns.Fishing.lures * ROW_HEIGHT + 4)
end
