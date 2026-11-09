-- Task list: scrolling rows, inline edit, add box.
local _, ns = ...
local QoL = ns.QoL
local T = ns.Todo

local ROW_HEIGHT = 22
local SCROLLBAR_SPACE = 24

local function rowOnEnter(row) row.delete:SetAlpha(1) end
local function rowOnLeave(row)
    if not row:IsMouseOver() then row.delete:SetAlpha(0.35) end
end

local function createRow(self, parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:EnableMouse(true)
    row:SetScript("OnEnter", rowOnEnter)
    row:SetScript("OnLeave", rowOnLeave)

    local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    check:SetSize(22, 22)
    check:SetPoint("LEFT", row, "LEFT", -2, 0)
    check:SetScript("OnClick", function(btn)
        self:SetTaskDone(row.tabId, row.taskId, btn:GetChecked())
    end)
    row.check = check

    local delete = CreateFrame("Button", nil, row)
    delete:SetSize(18, 18)
    delete:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    delete:SetNormalFontObject("GameFontDisable")
    delete:SetHighlightFontObject("GameFontRed")
    delete:SetText("x")
    delete:SetAlpha(0.35)
    delete:SetScript("OnClick", function() self:DeleteTask(row.tabId, row.taskId) end)
    delete:SetScript("OnEnter", function() rowOnEnter(row) end)
    delete:SetScript("OnLeave", function() rowOnLeave(row) end)
    row.delete = delete

    -- The label is a button: click it to edit the task in place.
    local label = CreateFrame("Button", nil, row)
    label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    label:SetPoint("RIGHT", delete, "LEFT", -2, 0)
    label:SetHeight(ROW_HEIGHT)
    label.text = label:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label.text:SetAllPoints()
    label.text:SetJustifyH("LEFT")
    label.text:SetWordWrap(false)
    label:SetScript("OnEnter", function() rowOnEnter(row) end)
    label:SetScript("OnLeave", function() rowOnLeave(row) end)
    row.label = label

    local edit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    edit:SetPoint("LEFT", check, "RIGHT", 6, 0)
    edit:SetPoint("RIGHT", delete, "LEFT", -2, 0)
    edit:SetHeight(ROW_HEIGHT - 2)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(200)
    edit:Hide()
    local function stopEditing()
        edit:Hide()
        label:Show()
    end
    edit:SetScript("OnEnterPressed", function(box)
        local text = box:GetText()
        stopEditing()
        self:EditTask(row.tabId, row.taskId, text)
    end)
    edit:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    edit:SetScript("OnEditFocusLost", stopEditing)
    row.edit = edit

    label:SetScript("OnClick", function()
        label:Hide()
        edit:SetText(label.text:GetText() or "")
        edit:Show()
        edit:SetFocus()
        edit:HighlightText()
    end)

    return row
end

function T:CreateTaskList(parent)
    -- Bottom bar: the add box, full width (leaving room for the resize grip).
    local add = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    add:SetHeight(22)
    add:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 6, 0)
    add:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -14, 0)
    add:SetAutoFocus(false)
    add:SetMaxLetters(200)
    add:SetScript("OnEnterPressed", function(box)
        local text = box:GetText()
        box:SetText("")
        if text:match("%S") then
            self:AddTask(self:GetActiveTab().id, text)
            box:SetFocus() -- stay ready for the next task
        else
            box:ClearFocus()
        end
    end)
    add:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    local hint = add:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("LEFT", add, "LEFT", 2, 0)
    hint:SetText("Add a task, press Enter")
    add:SetScript("OnTextChanged", function(box) hint:SetShown(box:GetText() == "") end)
    add:SetScript("OnEditFocusGained", function() hint:Hide() end)
    add:SetScript("OnEditFocusLost", function(box) hint:SetShown(box:GetText() == "") end)
    self.addBox = add

    -- Scrolling list between the tab strip and the bottom bar.
    local scroll = QoL.CreateScrollFrame(parent)
    scroll:SetPoint("TOPLEFT", self.tabStrip, "BOTTOMLEFT", 0, -6)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -SCROLLBAR_SPACE, 28)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    self.scroll, self.scrollChild = scroll, child
    self.rows = {}

    local empty = scroll:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("TOP", scroll, "TOP", 0, -12)
    empty:SetText("No tasks yet. Add one below.")
    self.emptyText = empty

    self:CreateReferencePanel(parent)
    self:CreateFishingPanel(parent)
    self:CreateHelpersPanel(parent)
end

function T:RefreshTasks()
    local tab = self:GetActiveTab()
    local rows = self.rows

    -- Built-in tabs show read-only text instead of tasks.
    self.scroll:SetShown(not tab.reference)
    self.addBox:SetShown(not tab.reference)
    self.fishPanel:SetShown(tab.panel == "fishing")
    self.helpersPanel:SetShown(tab.panel == "helpers")
    self.refPanel:SetShown(tab.reference and not tab.panel)
    if tab.reference then
        self.emptyText:Hide()
        for _, row in ipairs(rows) do row:Hide() end
        if tab.panel == "fishing" then
            self:ShowFishing()
        elseif tab.panel == "helpers" then
            self:ShowHelpers()
        else
            self:ShowReference(tab)
        end
        return
    end

    for i, task in ipairs(tab.tasks) do
        local row = rows[i] or createRow(self, self.scrollChild)
        rows[i] = row
        row.tabId, row.taskId = tab.id, task.id
        row.check:SetChecked(task.done)
        row.label.text:SetText(task.text)
        if task.done then
            row.label.text:SetTextColor(0.5, 0.5, 0.5)
        else
            row.label.text:SetTextColor(1, 1, 1)
        end
        row.edit:Hide()
        row.label:Show()
        row:Show()
    end
    for i = #tab.tasks + 1, #rows do
        rows[i]:Hide()
    end

    self.emptyText:SetShown(#tab.tasks == 0)
    self:LayoutTasks()
end

function T:LayoutTasks()
    if not self.scroll then return end
    self:LayoutReference()
    self:LayoutFishing()
    self:LayoutHelpers()
    local width = self:GetContentWidth() - SCROLLBAR_SPACE
    if not width or width <= 0 then return end
    local tab = self:GetActiveTab()
    local child = self.scrollChild
    child:SetWidth(width)
    for i = 1, #tab.tasks do
        local row = self.rows[i]
        if not row then break end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:SetPoint("RIGHT", child, "RIGHT", 0, 0)
    end
    child:SetHeight(math.max(1, #tab.tasks * ROW_HEIGHT))
end
