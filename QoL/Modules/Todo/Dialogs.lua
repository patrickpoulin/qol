-- Popups for naming tabs and confirming deletes.
local _, ns = ...
local QoL = ns.QoL
local T = ns.Todo

local function acceptText(popup, data)
    local text = QoL.GetPopupEditBox(popup):GetText()
    data.onAccept(text)
end

StaticPopupDialogs["QOL_TODO_NAME_TAB"] = {
    text = "%s",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    maxLetters = 32,
    OnShow = function(self, data)
        local box = QoL.GetPopupEditBox(self)
        box:SetText(data.initial or "")
        box:HighlightText()
        box:SetFocus()
    end,
    OnAccept = acceptText,
    EditBoxOnEnterPressed = function(self, data)
        local popup = self:GetParent()
        acceptText(popup, data)
        popup:Hide()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["QOL_TODO_CONFIRM"] = {
    text = "%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data) data.onAccept() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function T:PromptNewTab()
    StaticPopup_Show("QOL_TODO_NAME_TAB", "Name the new tab:", nil, {
        initial = "",
        onAccept = function(text)
            local tab = self:AddTab(text)
            self:SetActiveTab(tab.id)
        end,
    })
end

function T:PromptRenameTab(tabId)
    local tab = self:GetTab(tabId)
    if not tab or T.RefuseReference(tab, "renamed") then return end
    StaticPopup_Show("QOL_TODO_NAME_TAB", "Rename tab:", nil, {
        initial = tab.name,
        onAccept = function(text) self:RenameTab(tabId, text) end,
    })
end

function T:ConfirmDeleteTab(tabId)
    local tab = self:GetTab(tabId)
    if not tab or T.RefuseReference(tab, "deleted") then return end
    if #self.db.tabs <= 1 then
        return QoL:Print("you can't delete your only tab. Rename it instead.")
    end
    local msg = ("Delete the tab \"%s\" and its %d task%s?"):format(tab.name, #tab.tasks, #tab.tasks == 1 and "" or "s")
    StaticPopup_Show("QOL_TODO_CONFIRM", msg, nil, {
        onAccept = function() self:DeleteTab(tabId) end,
    })
end

function T:ConfirmClearCompleted()
    local tab = self:GetActiveTab()
    local _, done = self:CountTasks(tab)
    if done == 0 then return end
    local msg = ("Delete %d completed task%s from \"%s\"?"):format(done, done == 1 and "" or "s", tab.name)
    StaticPopup_Show("QOL_TODO_CONFIRM", msg, nil, {
        onAccept = function() self:ClearCompleted(tab.id) end,
    })
end
