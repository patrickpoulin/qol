-- To-do data: tabs and tasks. No UI code here; every change calls Refresh().
local _, ns = ...
local QoL = ns.QoL
local T = ns.Todo

local MAX_NAME = 32

local function newId(self)
    local id = self.db.nextId
    self.db.nextId = id + 1
    return id
end

local function clean(text, maxLen)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if maxLen and #text > maxLen then text = text:sub(1, maxLen) end
    return text
end

-- Tabs ---------------------------------------------------------------------

function T:GetTab(id)
    if not id then return end
    for i, tab in ipairs(self.db.tabs) do
        if tab.id == id then return tab, i end
    end
end

function T:GetActiveTab()
    return self:GetTab(self.charDB.activeTabId) or self.db.tabs[1]
end

function T:SetActiveTab(id)
    if self:GetTab(id) then
        self.charDB.activeTabId = id
        self:Refresh()
    end
end

function T:AddTab(name)
    name = clean(name, MAX_NAME)
    if name == "" then name = "New tab" end
    local tab = { id = newId(self), name = name, tasks = {} }
    table.insert(self.db.tabs, tab)
    self:Refresh()
    return tab
end

function T:RenameTab(id, name)
    local tab = self:GetTab(id)
    name = clean(name, MAX_NAME)
    if tab and name ~= "" then
        tab.name = name
        self:Refresh()
    end
end

function T:DeleteTab(id)
    if #self.db.tabs <= 1 then
        QoL:Print("you can't delete your only tab. Rename it instead.")
        return false
    end
    local _, index = self:GetTab(id)
    if not index then return false end
    table.remove(self.db.tabs, index)
    if self.charDB.activeTabId == id then
        local next = self.db.tabs[math.min(index, #self.db.tabs)]
        self.charDB.activeTabId = next.id
    end
    self:Refresh()
    return true
end

-- Tasks --------------------------------------------------------------------

function T:GetTask(tab, taskId)
    for i, task in ipairs(tab.tasks) do
        if task.id == taskId then return task, i end
    end
end

function T:AddTask(tabId, text)
    local tab = self:GetTab(tabId)
    text = clean(text, 200)
    if not tab or text == "" then return end
    local task = { id = newId(self), text = text, done = false, created = time() }
    table.insert(tab.tasks, task)
    self:Refresh()
    return task
end

function T:SetTaskDone(tabId, taskId, done)
    local tab = self:GetTab(tabId)
    local task = tab and self:GetTask(tab, taskId)
    if task then
        task.done = done and true or false
        self:Refresh()
    end
end

function T:EditTask(tabId, taskId, text)
    local tab = self:GetTab(tabId)
    local task = tab and self:GetTask(tab, taskId)
    text = clean(text, 200)
    if task and text ~= "" then
        task.text = text
        self:Refresh()
    end
end

function T:DeleteTask(tabId, taskId)
    local tab = self:GetTab(tabId)
    if not tab then return end
    local _, index = self:GetTask(tab, taskId)
    if index then
        table.remove(tab.tasks, index)
        self:Refresh()
    end
end

function T:CountTasks(tab)
    local done = 0
    for _, task in ipairs(tab.tasks) do
        if task.done then done = done + 1 end
    end
    return #tab.tasks - done, done
end

-- Delete every ticked task on a tab. Returns how many were removed.
function T:ClearCompleted(tabId)
    local tab = self:GetTab(tabId)
    if not tab then return 0 end
    local kept, removed = {}, 0
    for _, task in ipairs(tab.tasks) do
        if task.done then
            removed = removed + 1
        else
            table.insert(kept, task)
        end
    end
    tab.tasks = kept
    self:Refresh()
    return removed
end
