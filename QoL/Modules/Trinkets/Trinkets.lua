-- Trinkets ("/qol trinkets"): a small window with your two trinket slots.
-- Click a slot to use that trinket. Hover a slot to see the trinkets in your
-- bags, and click one to put it in that slot.
--
-- The game doesn't let anyone change trinkets in combat, so a swap picked in
-- combat is queued and done as soon as combat ends. The slot buttons are
-- secure (so a click can use the trinket), which means the window can only be
-- built, shown, hidden or moved out of combat; those wait for combat to end.
local _, ns = ...
local QoL = ns.QoL

local C_Container, C_Item = _G.C_Container, _G.C_Item

local SLOTS = { 13, 14 } -- INVSLOT_TRINKET1, INVSLOT_TRINKET2
local SIZE = 36
local PAD, GAP = 5, 4
local MENU_SIZE = 30
local MENU_COLUMNS = 4
local MENU_LINGER = 0.25 -- seconds the menu stays after the mouse leaves

local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local EMPTY_ICON = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Trinket"

local M = QoL:RegisterModule("trinkets", {
    name = "Trinkets",
    description = "small window to use and swap your trinkets",
    defaults = {
        enabled = false,
    },
    charDefaults = {
        locked = false,
        point = nil, -- { left, top } relative to the bottom-left of the screen
    },
    slashHelp = {
        "/qol trinkets - show or hide the window (or /qol trinkets on / off)",
        "/qol trinkets lock | unlock | reset",
    },
})
ns.Trinkets = M

M.pending = {} -- [invSlot] = { link = ..., icon = ... } swaps waiting for combat to end

-- Game API ---------------------------------------------------------------

local function itemCooldown(bag, slot)
    local fn = (C_Container and C_Container.GetContainerItemCooldown) or _G.GetContainerItemCooldown
    if not fn then return nil end
    return fn(bag, slot)
end

local function equipLoc(link)
    if not link or not QoL.GetItemInfoInstant then return nil end
    local ok, _, _, _, loc = pcall(QoL.GetItemInfoInstant, link)
    if ok then return loc end
    return nil
end

local function itemIcon(link)
    if not link or not QoL.GetItemInfoInstant then return nil end
    local ok, _, _, _, _, icon = pcall(QoL.GetItemInfoInstant, link)
    if ok then return icon end
    return nil
end

-- Trinkets in the bags: list of { bag, slot, link, icon }.
local function bagTrinkets()
    local list = {}
    for bag = 0, QoL.NUM_BAGS do
        for slot = 1, QoL.GetContainerNumSlots(bag) or 0 do
            local link = QoL.GetContainerItemLink(bag, slot)
            if link and equipLoc(link) == "INVTYPE_TRINKET" then
                table.insert(list, { bag = bag, slot = slot, link = link, icon = itemIcon(link) })
            end
        end
    end
    table.sort(list, function(a, b)
        local na, nb = QoL.GetItemName(a.link) or a.link, QoL.GetItemName(b.link) or b.link
        if na ~= nb then return na < nb end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)
    return list
end

local function findInBags(link)
    for _, item in ipairs(bagTrinkets()) do
        if item.link == link then return item end
    end
    return nil
end

local function equipNow(item, invSlot)
    local equip = (C_Item and C_Item.EquipItemByName) or _G.EquipItemByName
    if equip then
        equip(item.link, invSlot)
        return
    end
    -- Very old clients: pick the item up and drop it on the slot.
    if _G.CursorHasItem and _G.CursorHasItem() then return end
    QoL.PickupContainerItem(item.bag, item.slot)
    PickupInventoryItem(invSlot)
    ClearCursor()
end

-- Swapping -----------------------------------------------------------------

function M:Swap(item, invSlot)
    if InCombatLockdown() or UnitAffectingCombat("player") then
        local queued = self.pending[invSlot]
        if queued and queued.link == item.link then
            -- Picking the queued trinket again cancels it.
            self.pending[invSlot] = nil
            QoL:Print(("cancelled the swap to %s."):format(item.link))
        else
            self.pending[invSlot] = { link = item.link, icon = item.icon }
            -- One trinket can only go in one slot.
            for _, other in ipairs(SLOTS) do
                local q = self.pending[other]
                if other ~= invSlot and q and q.link == item.link then self.pending[other] = nil end
            end
            QoL:Print(("%s goes in when combat ends."):format(item.link))
        end
        self:Refresh()
        return
    end
    self.pending[invSlot] = nil
    equipNow(item, invSlot)
    self:Refresh()
end

-- After combat: do the queued swaps whose trinket is still in the bags.
function M:RunPending()
    for _, invSlot in ipairs(SLOTS) do
        local queued = self.pending[invSlot]
        self.pending[invSlot] = nil
        if queued then
            local item = findInBags(queued.link)
            if item then equipNow(item, invSlot) end
        end
    end
    self:Refresh()
end

-- Window -------------------------------------------------------------------

local function anchorTopLeft(f)
    local left, top = f:GetLeft(), f:GetTop()
    if not left or not top then return end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

function M:SavePosition()
    anchorTopLeft(self.frame)
    self.charDB.point = { self.frame:GetLeft(), self.frame:GetTop() }
end

function M:RestorePosition()
    local f, p = self.frame, self.charDB.point
    f:ClearAllPoints()
    if p and p[1] and p[2] then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p[1], p[2])
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
    end
end

local function startDrag()
    if not M.charDB.locked and not InCombatLockdown() then M.frame:StartMoving() end
end

local function stopDrag()
    M.frame:StopMovingOrSizing()
    M:SavePosition()
end

local function addCooldown(b)
    local ok, cd = pcall(CreateFrame, "Cooldown", nil, b, "CooldownFrameTemplate")
    if not ok or not cd then cd = CreateFrame("Cooldown", nil, b) end
    cd:SetAllPoints(b.icon)
    if cd.SetDrawEdge then cd:SetDrawEdge(false) end
    b.cd = cd
end

local function setCooldown(b, start, duration, enable)
    if QoL.IsSecret(start) or QoL.IsSecret(duration) then
        pcall(b.cd.SetCooldown, b.cd, start, duration)
        return
    end
    if enable == 0 or not start or not duration or duration <= 0 then
        pcall(b.cd.SetCooldown, b.cd, 0, 0)
    else
        pcall(b.cd.SetCooldown, b.cd, start, duration)
    end
end

local function addIconArt(b)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    b:SetBackdropBorderColor(0, 0, 0, 1)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b.icon)
    hl:SetColorTexture(1, 1, 1, 0.15)
end

function M:CreateSlotButton(index, invSlot)
    local f = self.frame
    local b = CreateFrame("Button", "QoLTrinketSlot" .. index, f, "SecureActionButtonTemplate,BackdropTemplate")
    b:SetSize(SIZE, SIZE)
    b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + (index - 1) * (SIZE + GAP), -PAD)
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("useOnKeyDown", false)
    -- Left-click uses the trinket. Other buttons do nothing.
    b:SetAttribute("type1", "macro")
    b:SetAttribute("macrotext1", "/use " .. invSlot)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", startDrag)
    b:SetScript("OnDragStop", stopDrag)
    addIconArt(b)
    addCooldown(b)

    -- The trinket waiting for combat to end, in the corner.
    local overlay = CreateFrame("Frame", nil, b)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(b.cd:GetFrameLevel() + 2)
    b.queued = overlay:CreateTexture(nil, "OVERLAY")
    b.queued:SetSize(SIZE * 0.45, SIZE * 0.45)
    b.queued:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
    b.queued:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.queued:Hide()

    b.invSlot = invSlot
    b:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        if GetInventoryItemLink("player", invSlot) then
            GameTooltip:SetInventoryItem("player", invSlot)
        else
            GameTooltip:SetText(("Trinket slot %d (empty)"):format(index), 1, 1, 1)
        end
        local queued = M.pending[invSlot]
        if queued then
            GameTooltip:AddLine("After combat: " .. queued.link, 1, 0.82, 0, true)
        end
        GameTooltip:AddLine("Click to use. Hover to pick another trinket from your bags.", 0.5, 0.5, 0.5, true)
        GameTooltip:Show()
        M:OpenMenu(btn)
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

function M:CreateWindow()
    local f = CreateFrame("Frame", "QoLTrinketsFrame", UIParent, "BackdropTemplate")
    self.frame = f
    f:SetSize(PAD * 2 + SIZE * 2 + GAP, PAD * 2 + SIZE)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetBackdrop(BACKDROP)
    f:SetBackdropColor(0.05, 0.05, 0.08, 0.7)
    f:SetBackdropBorderColor(0.5, 0.5, 0.55, 1)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", startDrag)
    f:SetScript("OnDragStop", stopDrag)

    f.slots = {}
    for i, invSlot in ipairs(SLOTS) do
        f.slots[i] = self:CreateSlotButton(i, invSlot)
    end
    self:CreateMenu()
    self:RestorePosition()
    f:Hide()
end

-- Bag menu -----------------------------------------------------------------
-- A plain (not secure) frame on UIParent, so it can open and close in combat.

function M:CreateMenu()
    local menu = CreateFrame("Frame", "QoLTrinketsMenu", UIParent, "BackdropTemplate")
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:SetBackdrop(BACKDROP)
    menu:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
    menu:SetBackdropBorderColor(0.5, 0.5, 0.55, 1)
    menu.buttons = {}
    menu.empty = menu:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    menu.empty:SetPoint("CENTER")
    menu.empty:SetText("No trinkets in your bags")
    menu:Hide()
    menu.away = 0
    menu:SetScript("OnUpdate", QoL:Guard("Trinkets", function(m, elapsed)
        if m:IsMouseOver() or (m.owner and m.owner:IsMouseOver()) then
            m.away = 0
            return
        end
        m.away = m.away + elapsed
        if m.away >= MENU_LINGER then m:Hide() end
    end))
    self.menu = menu
end

local function menuButton(menu, i)
    local b = menu.buttons[i]
    if b then return b end
    b = CreateFrame("Button", nil, menu, "BackdropTemplate")
    b:SetSize(MENU_SIZE, MENU_SIZE)
    b:RegisterForClicks("LeftButtonUp")
    addIconArt(b)
    addCooldown(b)
    b:SetScript("OnClick", function(btn)
        if btn.item and menu.owner then
            M:Swap(btn.item, menu.owner.invSlot)
            if not InCombatLockdown() then menu:Hide() end
        end
    end)
    b:SetScript("OnEnter", function(btn)
        if not btn.item then return end
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        GameTooltip:SetBagItem(btn.item.bag, btn.item.slot)
        local line = InCombatLockdown() and "Click to swap it in when combat ends."
            or "Click to put it in this slot."
        GameTooltip:AddLine(line, 0.5, 0.5, 0.5, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    menu.buttons[i] = b
    return b
end

function M:FillMenu()
    local menu = self.menu
    local items = bagTrinkets()
    local count = #items
    local cols = math.max(1, math.min(MENU_COLUMNS, count))
    local rows = math.max(1, math.ceil(count / MENU_COLUMNS))
    for i, item in ipairs(items) do
        local b = menuButton(menu, i)
        b.item = item
        b.icon:SetTexture(item.icon or EMPTY_ICON)
        setCooldown(b, itemCooldown(item.bag, item.slot))
        local queued = menu.owner and self.pending[menu.owner.invSlot]
        b:SetBackdropBorderColor(queued and queued.link == item.link and 1 or 0,
            queued and queued.link == item.link and 0.82 or 0, 0, 1)
        -- Fill from the bottom row up, so the first trinkets sit next to the slot.
        local col, row = (i - 1) % MENU_COLUMNS, math.floor((i - 1) / MENU_COLUMNS)
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", menu, "BOTTOMLEFT", PAD + col * (MENU_SIZE + GAP), PAD + row * (MENU_SIZE + GAP))
        b:Show()
    end
    for i = count + 1, #menu.buttons do
        menu.buttons[i].item = nil
        menu.buttons[i]:Hide()
    end
    menu.empty:SetShown(count == 0)
    if count == 0 then
        menu:SetSize(menu.empty:GetStringWidth() + PAD * 4, MENU_SIZE + PAD * 2)
    else
        menu:SetSize(PAD * 2 + cols * MENU_SIZE + (cols - 1) * GAP, PAD * 2 + rows * MENU_SIZE + (rows - 1) * GAP)
    end
end

function M:OpenMenu(owner)
    local menu = self.menu
    menu.owner = owner
    menu.away = 0
    menu:ClearAllPoints()
    menu:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", -PAD, 2)
    self:FillMenu()
    menu:Show()
end

-- Refresh ------------------------------------------------------------------

function M:Refresh()
    local f = self.frame
    if not f then return end
    for _, b in ipairs(f.slots) do
        local invSlot = b.invSlot
        local link = GetInventoryItemLink("player", invSlot)
        b.icon:SetTexture((link and (GetInventoryItemTexture("player", invSlot) or itemIcon(link))) or EMPTY_ICON)
        b.icon:SetDesaturated(not link)
        if link and GetInventoryItemCooldown then
            setCooldown(b, GetInventoryItemCooldown("player", invSlot))
        else
            setCooldown(b, 0, 0)
        end
        local queued = self.pending[invSlot]
        b.queued:SetShown(queued ~= nil)
        if queued then b.queued:SetTexture(queued.icon or EMPTY_ICON) end
        b:SetBackdropBorderColor(queued and 1 or 0, queued and 0.82 or 0, 0, 1)
    end
    if self.menu and self.menu:IsShown() then self:FillMenu() end
end

-- Showing, hiding and locking (out of combat only) ---------------------------

function M:Apply()
    if InCombatLockdown() then
        self.applyAfterCombat = true
        return
    end
    self.applyAfterCombat = nil
    if self.db.enabled and not self.frame then self:CreateWindow() end
    local f = self.frame
    if not f then return end
    f:SetShown(self.db.enabled)
    -- Locked: the background lets clicks through and can't be dragged.
    f:EnableMouse(not self.charDB.locked)
    f:SetBackdropColor(0.05, 0.05, 0.08, self.charDB.locked and 0 or 0.7)
    f:SetBackdropBorderColor(0.5, 0.5, 0.55, self.charDB.locked and 0 or 1)
    if not self.db.enabled and self.menu then self.menu:Hide() end
    if self.db.enabled then self:Refresh() end
end

local function refreshMisc()
    if ns.Todo and ns.Todo.RefreshHelpers then ns.Todo:RefreshHelpers() end
end

function M:SetEnabled(on)
    self.db.enabled = on and true or false
    if not on then wipe(self.pending) end
    self:Apply()
    if InCombatLockdown() then
        QoL:Print(("the trinket window will %s when combat ends."):format(on and "appear" or "hide"))
    end
    refreshMisc()
end

function M:SetLocked(on)
    self.charDB.locked = on and true or false
    self:Apply()
    refreshMisc()
end

function M:ResetPosition()
    self.charDB.point = nil
    if InCombatLockdown() then
        self.applyAfterCombat = true
        return
    end
    if self.frame then self:RestorePosition() end
end

-- Events -------------------------------------------------------------------

function M:OnEnable()
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    f:RegisterEvent("BAG_UPDATE")
    f:RegisterEvent("BAG_UPDATE_COOLDOWN")
    f:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", QoL:Guard("Trinkets", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            if M.applyAfterCombat then
                M:Apply()
                if M.frame then M:RestorePosition() end
            end
            if M.db.enabled then M:RunPending() end
            return
        end
        if M.db.enabled then M:Refresh() end
    end))
    self:Apply()
end

function M:OnSlash(args)
    local cmd = (args or ""):lower()
    if cmd == "" then
        self:SetEnabled(not self.db.enabled)
    elseif cmd == "on" or cmd == "off" then
        self:SetEnabled(cmd == "on")
    elseif cmd == "lock" or cmd == "unlock" then
        self:SetLocked(cmd == "lock")
        QoL:Print("trinket window " .. cmd .. "ed.")
        return
    elseif cmd == "reset" then
        self:ResetPosition()
        QoL:Print("trinket window moved back below the centre of the screen.")
        return
    else
        QoL:Print("unknown command. Type /qol for help.")
        return
    end
    QoL:Print("trinket window " .. (self.db.enabled and "on" or "off") .. ".")
end
