-- Fishing: swap between your weapons and a fishing pole, and track lures.
-- The UI lives on the Fishing tab of the to-do window (Modules/Todo/FishingPanel.lua).
local _, ns = ...
local QoL = ns.QoL

local MAIN_HAND, OFF_HAND = 16, 17
local WEAPON_CLASS, FISHING_POLE_SUBCLASS = 2, 20
local OFF_HAND_DELAY = 0.5 -- seconds; lets the main-hand swap finish first

local F = QoL:RegisterModule("fish", {
    name = "Fishing",
    description = "swap to your fishing pole and back, apply lures",
    charDefaults = {
        mainHand = nil, -- item links of what you held before the swap
        offHand = nil,
    },
    slashHelp = {
        "/qol fish - swap to your fishing pole, or back to your weapons",
        "/qol fish tab - open the Fishing tab",
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

-- First fishing pole found in your bags, as an item link.
function F:FindPoleInBags()
    for bag = 0, QoL.NUM_BAGS do
        for slot = 1, QoL.GetContainerNumSlots(bag) or 0 do
            local link = QoL.GetContainerItemLink(bag, slot)
            if link and self.IsFishingPole(link) then
                return link
            end
        end
    end
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
        return nil, "Equip your weapon by hand"
    end
    if self:FindPoleInBags() then return "equip" end
    return nil, "No fishing pole in your bags"
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
        self.charDB.mainHand, self.charDB.offHand = mainHand, offHand
        EquipItemByName(self:FindPoleInBags(), MAIN_HAND)
    elseif state == "unequip" then
        local mainHand, offHand = self.charDB.mainHand, self.charDB.offHand
        self.charDB.mainHand, self.charDB.offHand = nil, nil
        EquipItemByName(mainHand, MAIN_HAND)
        if offHand then
            C_Timer.After(OFF_HAND_DELAY, function()
                if not InCombatLockdown() then EquipItemByName(offHand, OFF_HAND) end
            end)
        end
    else
        QoL:Print(reason .. ".")
    end
end

function F:OnSlash(args)
    local cmd = (args or ""):lower()
    if cmd == "" or cmd == "swap" then
        self:Swap()
    elseif cmd == "tab" then
        local todo = ns.Todo
        todo:SetShown(true)
        todo:SetCollapsed(false)
        todo:SetActiveTab("ref:fishing")
    else
        QoL:Print("unknown command. Type /qol for help.")
    end
end
