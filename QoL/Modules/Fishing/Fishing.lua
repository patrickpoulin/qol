-- Fishing: swap between your weapons and a fishing pole, and track lures.
-- The UI lives on the Fishing tab of the to-do window (Modules/Todo/FishingPanel.lua).
local _, ns = ...
local QoL = ns.QoL

local MAIN_HAND, OFF_HAND = 16, 17
local WEAPON_CLASS, FISHING_POLE_SUBCLASS = 2, 20
local OFF_HAND_DELAY = 0.5 -- seconds; lets the main-hand swap finish first
local CHECK_DELAY = 1.5 -- seconds; then check that the swap went through

local F = QoL:RegisterModule("fish", {
    name = "Fishing",
    description = "swap to your fishing pole and back, apply lures",
    defaults = {
        key = nil, -- one-key fishing key, e.g. "F" or "SHIFT-F"
        autoLure = true,
        fishingSettings = true, -- interact key and fishing sound while the pole is on
    },
    charDefaults = {
        savedCVars = nil, -- your own settings while the fishing ones are on
        mainHand = nil, -- item links of what you held before the swap
        offHand = nil,
    },
    slashHelp = {
        "/qol fish - swap to your fishing pole, or back to your weapons",
        "/qol fish tab - open the Fishing tab",
        "/qol fish key <key> | off - set the one-key fishing key (cast, then reel in)",
        "/qol fish autolure on | off - let the key put on your best lure first",
        "/qol fish settings on | off - interact key and fishing sound while the pole is on",
        "/qol fish debug - print what QoL sees, to help fix swap problems",
    },
})
ns.Fishing = F

-- Lures in the order shown on the tab. Bonus is fishing skill, as in Classic.
F.lures = {
    { id = 6529, name = "Shiny Bauble", bonus = 25 },
    { id = 6530, name = "Nightcrawlers", bonus = 50 },
    { id = 6811, name = "Aquadynamic Fish Lens", bonus = 50 },
    { id = 6532, name = "Bright Baubles", bonus = 75 },
    { id = 7307, name = "Flesh Eating Worm", bonus = 75 },
    { id = 6533, name = "Aquadynamic Fish Attractor", bonus = 100 },
}

function F.IsFishingPole(item)
    if not item then return false end
    local _, _, _, _, _, classID, subclassID = QoL.GetItemInfoInstant(item)
    return classID == WEAPON_CLASS and subclassID == FISHING_POLE_SUBCLASS
end

function F:IsPoleEquipped()
    return self.IsFishingPole(GetInventoryItemID("player", MAIN_HAND))
end

function F:GetEquippedPoleLink()
    if self:IsPoleEquipped() then
        return GetInventoryItemLink("player", MAIN_HAND)
    end
end

-- First bag item that passes `test(link)`: returns link, bag, slot.
local function findInBags(test)
    for bag = 0, QoL.NUM_BAGS do
        for slot = 1, QoL.GetContainerNumSlots(bag) or 0 do
            local link = QoL.GetContainerItemLink(bag, slot)
            if link and test(link) then
                return link, bag, slot
            end
        end
    end
end

local function itemID(link)
    return link and tonumber(link:match("item:(%d+)"))
end

-- First fishing pole found in your bags: link, bag, slot.
function F:FindPoleInBags()
    return findInBags(self.IsFishingPole)
end

-- A saved weapon in your bags: the exact item if it's there, else one with the same ID.
local function findSaved(link)
    local found, bag, slot = findInBags(function(l) return l == link end)
    if found then return found, bag, slot end
    local id = itemID(link)
    return findInBags(function(l) return itemID(l) == id end)
end

-- Put the item in bag/slot into an equipment slot, like dragging it onto the
-- character window. Whatever was in that slot goes back into the bag.
local function equipFromBag(bag, slot, invSlot)
    ClearCursor()
    QoL.PickupContainerItem(bag, slot)
    PickupInventoryItem(invSlot)
    ClearCursor()
end

-- Watch for an error message from the game while a swap is running.
local errorWatch = CreateFrame("Frame")
errorWatch:SetScript("OnEvent", function(_, _, ...)
    local msg
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "string" then msg = v end
    end
    if msg then QoL:Print("the game said: " .. msg) end
end)

local function watchErrors()
    errorWatch:RegisterEvent("UI_ERROR_MESSAGE")
    C_Timer.After(CHECK_DELAY, function() errorWatch:UnregisterEvent("UI_ERROR_MESSAGE") end)
end

local function freeBagSlots()
    local free = 0
    for bag = 0, QoL.NUM_BAGS do
        free = free + (QoL.GetContainerNumFreeSlots(bag) or 0)
    end
    return free
end

-- Seconds left on the lure on your main hand, or nil if there isn't one.
function F:GetLureTimeLeft()
    if not self:IsPoleEquipped() then return end
    local hasEnchant, expiration = GetWeaponEnchantInfo()
    if hasEnchant and expiration then
        return expiration / 1000
    end
end

-- What the swap button will do next: "equip", "unequip", or nil with a reason.
function F:GetSwapState()
    if self:IsPoleEquipped() then
        if self.charDB.mainHand then return "unequip" end
        return nil, "Equip Your Weapon by Hand"
    end
    if self:FindPoleInBags() then return "equip" end
    return nil, "No Fishing Pole in Your Bags"
end

function F:Swap()
    if InCombatLockdown() then
        return QoL:Print("you can't swap weapons in combat.")
    end
    local state, reason = self:GetSwapState()
    if state == "equip" then
        local mainHand = GetInventoryItemLink("player", MAIN_HAND)
        local offHand = GetInventoryItemLink("player", OFF_HAND)
        -- The pole is two-handed, so an off-hand item has to go into your bags.
        if offHand and freeBagSlots() < 1 then
            return QoL:Print("your bags are full, so there's no room for your off-hand.")
        end
        local _, bag, slot = self:FindPoleInBags()
        self.charDB.mainHand, self.charDB.offHand = mainHand, offHand
        watchErrors()
        equipFromBag(bag, slot, MAIN_HAND)
        C_Timer.After(CHECK_DELAY, function()
            if not self:IsPoleEquipped() then
                self.charDB.mainHand, self.charDB.offHand = nil, nil
                QoL:Print("the pole didn't equip. Type /qol fish debug and send what it prints.")
            end
        end)
    elseif state == "unequip" then
        local mainHand, offHand = self.charDB.mainHand, self.charDB.offHand
        local _, bag, slot = findSaved(mainHand)
        if not bag then
            return QoL:Print(("can't find %s in your bags."):format(mainHand))
        end
        self.charDB.mainHand, self.charDB.offHand = nil, nil
        watchErrors()
        equipFromBag(bag, slot, MAIN_HAND)
        if offHand then
            C_Timer.After(OFF_HAND_DELAY, function()
                if InCombatLockdown() then return end
                local _, offBag, offSlot = findSaved(offHand)
                if offBag then equipFromBag(offBag, offSlot, OFF_HAND) end
            end)
        end
    else
        QoL:Print(reason .. ".")
    end
end

local function describe(item)
    if not item then return "nothing" end
    local _, itemType, subType, _, _, classID, subclassID = QoL.GetItemInfoInstant(item)
    return ("%s (%s / %s, class %s, subclass %s)"):format(
        tostring(item), tostring(itemType), tostring(subType), tostring(classID), tostring(subclassID))
end

function F:PrintDebug()
    local p = function(...) print("  " .. string.format(...)) end
    QoL:Print("fishing debug")
    p("client build %s, interface %s", tostring((select(2, GetBuildInfo()))), tostring((select(4, GetBuildInfo()))))
    p("C_Container: %s, PickupContainerItem: %s, GetItemInfoInstant: %s",
        tostring(_G.C_Container ~= nil), tostring(QoL.PickupContainerItem ~= nil), tostring(QoL.GetItemInfoInstant ~= nil))
    p("in combat: %s", tostring(InCombatLockdown()))
    p("main hand: %s", describe(GetInventoryItemLink("player", MAIN_HAND)))
    p("off hand: %s", describe(GetInventoryItemLink("player", OFF_HAND)))
    p("pole equipped: %s", tostring(self:IsPoleEquipped()))
    local link, bag, slot = self:FindPoleInBags()
    p("pole in bags: %s", link and ("%s at bag %d slot %d"):format(link, bag, slot) or "none found")
    if not link then
        -- Show every weapon in the bags so we can see how the pole is classed.
        findInBags(function(l)
            local _, _, _, _, _, classID = QoL.GetItemInfoInstant(l)
            if classID == WEAPON_CLASS then p("bag weapon: %s", describe(l)) end
        end)
    end
    local state, reason = self:GetSwapState()
    p("swap state: %s", tostring(state or reason))
    p("saved weapons: %s / %s", tostring(self.charDB.mainHand), tostring(self.charDB.offHand))
end

function F:OnSlash(args)
    local cmd = (args or ""):lower()
    if cmd == "" or cmd == "swap" then
        self:Swap()
    elseif cmd:match("^key") then
        local key = args:match("^%S+%s+(%S+)")
        if not key then return QoL:Print("usage: /qol fish key F (or SHIFT-F, or off)") end
        self:SetKey(key:lower() ~= "off" and key:upper() or nil)
    elseif cmd:match("^autolure") then
        self:SetAutoLure(not cmd:match("off$"))
    elseif cmd:match("^settings") then
        self:SetFishingSettings(not cmd:match("off$"))
    elseif cmd == "debug" then
        self:PrintDebug()
    elseif cmd == "tab" then
        local todo = ns.Todo
        todo:SetShown(true)
        todo:SetCollapsed(false)
        todo:SetActiveTab("ref:fishing")
    else
        QoL:Print("unknown command. Type /qol for help.")
    end
end
