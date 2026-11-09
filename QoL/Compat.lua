-- Shared UI helpers that hide client API differences.
local _, ns = ...
local QoL = ns.QoL

-- items = { { text = "Rename", func = function() end }, ... }
function QoL.ShowContextMenu(owner, items)
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(owner, function(_, root)
            for _, item in ipairs(items) do
                root:CreateButton(item.text, item.func)
            end
        end)
        return
    end

    -- Older clients: UIDropDownMenu.
    if not UIDropDownMenu_Initialize then return end
    QoL.dropdown = QoL.dropdown or CreateFrame("Frame", "QoLContextMenu", UIParent, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(QoL.dropdown, function()
        for _, item in ipairs(items) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = item.text
            info.notCheckable = true
            info.func = item.func
            UIDropDownMenu_AddButton(info)
        end
    end, "MENU")
    ToggleDropDownMenu(1, nil, QoL.dropdown, "cursor", 0, 0)
end

-- A vertical scroll frame with a scroll bar where the client has the
-- template, and plain mouse-wheel scrolling where it doesn't.
function QoL.CreateScrollFrame(parent)
    local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    if ok and scroll then
        -- Only show the scroll bar when there is something to scroll.
        local bar = scroll.ScrollBar
        if bar then
            scroll.scrollBarHideable = true
            local function update(frame)
                local range = frame:GetVerticalScrollRange() or 0
                bar:SetShown(range > 0.5)
                if range <= 0.5 and frame:GetVerticalScroll() ~= 0 then frame:SetVerticalScroll(0) end
            end
            scroll:HookScript("OnScrollRangeChanged", update)
            scroll:HookScript("OnSizeChanged", update)
            scroll:HookScript("OnShow", update)
            update(scroll)
        end
        return scroll
    end

    scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local max = self:GetVerticalScrollRange()
        local value = math.min(max, math.max(0, self:GetVerticalScroll() - delta * 20))
        self:SetVerticalScroll(value)
    end)
    return scroll
end

-- StaticPopup edit box, across client versions.
function QoL.GetPopupEditBox(popup)
    if popup.GetEditBox then return popup:GetEditBox() end
    return popup.EditBox or popup.editBox
end

-- Bags and items. Newer clients moved these into C_Container / C_Item.
local C_Container, C_Item = _G.C_Container, _G.C_Item

QoL.GetContainerNumSlots = (C_Container and C_Container.GetContainerNumSlots) or _G.GetContainerNumSlots
QoL.GetContainerItemLink = (C_Container and C_Container.GetContainerItemLink) or _G.GetContainerItemLink
QoL.GetContainerNumFreeSlots = (C_Container and C_Container.GetContainerNumFreeSlots) or _G.GetContainerNumFreeSlots
QoL.PickupContainerItem = (C_Container and C_Container.PickupContainerItem) or _G.PickupContainerItem
QoL.GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
QoL.GetItemCount = (C_Item and C_Item.GetItemCount) or _G.GetItemCount

-- Item name, or nil while the client is still loading it.
function QoL.GetItemName(item)
    local getInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
    return (getInfo(item))
end

QoL.NUM_BAGS = _G.NUM_BAG_SLOTS or 4 -- backpack is bag 0, then bags 1..NUM_BAGS
