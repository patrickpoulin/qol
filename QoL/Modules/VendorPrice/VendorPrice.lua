-- Vendor price: add an item's vendor sell price to its tooltip.
--
-- Classic-era clients only show "Sell Price" while a vendor window is open.
-- The game still knows every item's price (GetItemInfo's 11th return), so
-- this adds that line everywhere else: bags, bank, character sheet, loot,
-- chat links and the comparison tooltips.
--
-- It never adds a second price: it skips while a vendor window is open, and
-- skips any tooltip that already shows money (newer clients, other addons).
local _, ns = ...
local QoL = ns.QoL

local V = QoL:RegisterModule("price", {
    name = "Vendor price",
    description = "show an item's vendor sell price on its tooltip",
    defaults = {
        enabled = true,
    },
    slashHelp = {
        "/qol price - turn the sell price on item tooltips on or off (or /qol price on / off)",
    },
})
ns.VendorPrice = V

-- Tooltips that show items, besides any the client's tooltip data system reports.
local TOOLTIPS = {
    "GameTooltip", "ItemRefTooltip",
    "ShoppingTooltip1", "ShoppingTooltip2", "ShoppingTooltip3",
    "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2", "ItemRefShoppingTooltip3",
}

local function getItemInfo(item)
    local C_Item = _G.C_Item
    local fn = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
    return fn(item)
end

-- Sell price in copper: a number (0 when vendors won't buy it), or nil while
-- the client is still loading the item.
local function sellPrice(link)
    local price = select(11, getItemInfo(link))
    if type(price) ~= "number" then return nil end
    return price
end

local function itemID(link)
    local id = QoL.GetItemInfoInstant and QoL.GetItemInfoInstant(link)
    return type(id) == "number" and id or nil
end

-- How many items the hovered button holds. Bag, bank and most other item
-- buttons keep it in .count; anything else counts as one.
local function stackCount(tooltip)
    local owner = tooltip.GetOwner and tooltip:GetOwner()
    local count = type(owner) == "table" and rawget(owner, "count")
    if type(count) == "number" and count > 1 then return math.floor(count) end
    return 1
end

-- "12g 3s 40c" with coin icons, for clients without SetTooltipMoney.
local COIN = "|TInterface\\MoneyFrame\\UI-%sIcon:0:0:2:0|t"
local function coinText(copper)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then table.insert(parts, g .. COIN:format("Gold")) end
    if s > 0 then table.insert(parts, s .. COIN:format("Silver")) end
    if c > 0 or #parts == 0 then table.insert(parts, c .. COIN:format("Copper")) end
    return table.concat(parts, " ")
end

local function addMoneyLine(tooltip, label, copper)
    -- SetTooltipMoney names its coin frames after the tooltip, so it needs a named one.
    if _G.SetTooltipMoney and tooltip.GetName and tooltip:GetName() then
        _G.SetTooltipMoney(tooltip, copper, nil, label)
    else
        tooltip:AddDoubleLine(label, coinText(copper), 1, 1, 1, 1, 1, 1)
    end
end

local LABEL = (_G.SELL_PRICE or "Sell Price") .. ":"

local pending = {} -- [tooltip] = itemID still loading
local waiter

local function vendorOpen()
    local merchant = _G.MerchantFrame
    return merchant and merchant:IsShown()
end

local function addPrice(tooltip)
    if not V.db.enabled or tooltip.qolPriceDone or not tooltip.GetItem then return end
    local _, link = tooltip:GetItem()
    if not link then return end
    -- At a vendor the game shows the price itself.
    if vendorOpen() then return end
    -- Something already put money on this tooltip, e.g. the client's own price.
    if (tooltip.shownMoneyFrames or 0) > 0 then return end

    local price = sellPrice(link)
    if price == nil then
        -- Not loaded yet: add it when GET_ITEM_INFO_RECEIVED says it's here.
        local id = itemID(link)
        if id then
            pending[tooltip] = id
            waiter:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        end
        return
    end
    tooltip.qolPriceDone = true
    pending[tooltip] = nil
    if price <= 0 then return end

    local count = stackCount(tooltip)
    if count > 1 then
        addMoneyLine(tooltip, ("%s (%d)"):format(LABEL, count), price * count)
        addMoneyLine(tooltip, "Each:", price)
    else
        addMoneyLine(tooltip, LABEL, price)
    end
end

local function onItemLoaded(id)
    for tooltip, wanted in pairs(pending) do
        if wanted == id then
            pending[tooltip] = nil
            if tooltip:IsShown() then
                local _, link = tooltip:GetItem()
                if link and itemID(link) == id then
                    addPrice(tooltip)
                    tooltip:Show() -- resize to fit the new line
                end
            end
        end
    end
    if not next(pending) then waiter:UnregisterEvent("GET_ITEM_INFO_RECEIVED") end
end

local hooked = {}

local function hookCleared(tooltip)
    if hooked[tooltip] or not tooltip.HookScript then return end
    hooked[tooltip] = true
    tooltip:HookScript("OnTooltipCleared", function(t)
        t.qolPriceDone = nil
        pending[t] = nil
    end)
end

function V:OnEnable()
    local onItem = QoL:Guard("Vendor price", function(tooltip)
        hookCleared(tooltip)
        addPrice(tooltip)
    end)

    waiter = CreateFrame("Frame")
    waiter:SetScript("OnEvent", QoL:Guard("Vendor price", function(_, _, id) onItemLoaded(id) end))

    -- Newer clients build tooltips from data and dropped OnTooltipSetItem.
    local processor, Enum = _G.TooltipDataProcessor, _G.Enum
    if processor and processor.AddTooltipPostCall and Enum and Enum.TooltipDataType
        and Enum.TooltipDataType.Item then
        processor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
            if type(tooltip) == "table" and tooltip.GetItem then onItem(tooltip) end
        end)
        return
    end

    for _, name in ipairs(TOOLTIPS) do
        local tooltip = _G[name]
        if tooltip and tooltip.HasScript and tooltip:HasScript("OnTooltipSetItem") then
            tooltip:HookScript("OnTooltipSetItem", onItem)
        end
    end
end

function V:SetEnabled(on)
    self.db.enabled = on and true or false
    if ns.Todo and ns.Todo.RefreshHelpers then ns.Todo:RefreshHelpers() end
end

function V:OnSlash(args)
    local cmd = (args or ""):lower()
    if cmd == "" then
        self:SetEnabled(not self.db.enabled)
    elseif cmd == "on" or cmd == "off" then
        self:SetEnabled(cmd == "on")
    else
        QoL:Print("unknown command. Type /qol for help.")
        return
    end
    QoL:Print("sell prices on item tooltips are " .. (self.db.enabled and "on" or "off") .. ".")
end
