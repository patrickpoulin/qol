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

-- StaticPopup edit box, across client versions.
function QoL.GetPopupEditBox(popup)
    if popup.GetEditBox then return popup:GetEditBox() end
    return popup.EditBox or popup.editBox
end
