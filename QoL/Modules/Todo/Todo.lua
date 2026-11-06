-- To-do module: registration, lifecycle and "/qol todo" commands.
local _, ns = ...
local QoL = ns.QoL

local T = QoL:RegisterModule("todo", {
    name = "To-Do",
    description = "on-screen to-do list with tabs",
    defaults = {
        nextId = 1,
        tabs = {},
    },
    charDefaults = {
        activeTabId = nil,
        shown = true,
        collapsed = false,
        locked = false,
        point = nil, -- { left, top } relative to the bottom-left of the screen
        width = 260,
        height = 320,
    },
    slashHelp = {
        "/qol todo - show or hide the window",
        "/qol todo add <text> - add a task to the current tab",
        "/qol todo clear - delete ticked tasks on the current tab",
        "/qol todo tab <name or number> - switch tab",
        "/qol todo newtab <name> - create a tab",
        "/qol todo rename <name> - rename the current tab",
        "/qol todo collapse | expand | lock | unlock | reset",
    },
})
ns.Todo = T

function T:OnLoad()
    if #self.db.tabs == 0 then
        self:AddTab("To-Do")
    end
    if not self:GetTab(self.charDB.activeTabId) then
        self.charDB.activeTabId = self.db.tabs[1].id
    end
end

function T:OnEnable()
    self:CreateMainFrame()
    self:Refresh()
end

-- Redraw everything from saved data.
function T:Refresh()
    if not self.frame then return end
    self:UpdateTitle()
    self:RefreshTabs()
    self:RefreshTasks()
end

local function findTab(self, arg)
    local n = tonumber(arg)
    if n and self.db.tabs[n] then return self.db.tabs[n] end
    local lower = arg:lower()
    for _, tab in ipairs(self.db.tabs) do
        if tab.name:lower() == lower then return tab end
    end
end

function T:OnSlash(args)
    local cmd, rest = args:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    if cmd == "" then
        self:SetShown(not self.frame:IsShown())
    elseif cmd == "show" then
        self:SetShown(true)
    elseif cmd == "hide" then
        self:SetShown(false)
    elseif cmd == "collapse" then
        self:SetShown(true)
        self:SetCollapsed(true)
    elseif cmd == "expand" then
        self:SetShown(true)
        self:SetCollapsed(false)
    elseif cmd == "add" then
        if rest == "" then return QoL:Print("usage: /qol todo add <text>") end
        self:AddTask(self:GetActiveTab().id, rest)
        QoL:Print(("added to %s: %s"):format(self:GetActiveTab().name, rest))
    elseif cmd == "clear" then
        local n = self:ClearCompleted(self:GetActiveTab().id)
        QoL:Print(("cleared %d completed task%s."):format(n, n == 1 and "" or "s"))
    elseif cmd == "tab" then
        local tab = findTab(self, rest)
        if not tab then return QoL:Print(("no tab called '%s'."):format(rest)) end
        self:SetActiveTab(tab.id)
    elseif cmd == "newtab" then
        local tab = self:AddTab(rest ~= "" and rest or "New tab")
        self:SetActiveTab(tab.id)
    elseif cmd == "rename" then
        if rest == "" then return QoL:Print("usage: /qol todo rename <name>") end
        self:RenameTab(self:GetActiveTab().id, rest)
    elseif cmd == "lock" or cmd == "unlock" then
        self:SetLocked(cmd == "lock")
        QoL:Print(cmd == "lock" and "window locked." or "window unlocked.")
    elseif cmd == "reset" then
        self:ResetPosition()
    else
        QoL:Print("unknown command. Type /qol for help.")
    end
end
