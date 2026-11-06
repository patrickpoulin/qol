-- The to-do window: title bar, move, resize, collapse, lock.
local _, ns = ...
local QoL = ns.QoL
local T = ns.Todo

local TITLE_HEIGHT = 26
local MIN_W, MIN_H, MAX_W, MAX_H = 200, 160, 600, 900

local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

-- Always anchor by the top-left corner so collapsing keeps the title in place.
local function anchorTopLeft(f)
    local left, top = f:GetLeft(), f:GetTop()
    if not left or not top then return end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

function T:SavePosition()
    local f = self.frame
    anchorTopLeft(f)
    self.charDB.point = { f:GetLeft(), f:GetTop() }
    if not self.charDB.collapsed then
        self.charDB.width = math.floor(f:GetWidth() + 0.5)
        self.charDB.height = math.floor(f:GetHeight() + 0.5)
    end
end

function T:RestorePosition()
    local f, p = self.frame, self.charDB.point
    f:ClearAllPoints()
    if p and p[1] and p[2] then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p[1], p[2])
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

function T:ResetPosition()
    self.charDB.point = nil
    self:RestorePosition()
    self:SetShown(true)
    QoL:Print("window moved to the centre of the screen.")
end

function T:SetShown(shown)
    self.charDB.shown = shown and true or false
    self.frame:SetShown(shown)
end

function T:SetCollapsed(collapsed)
    local f = self.frame
    if collapsed and not self.charDB.collapsed then
        self:SavePosition() -- remember the expanded size first
    end
    self.charDB.collapsed = collapsed and true or false
    anchorTopLeft(f)
    if collapsed then
        f.content:Hide()
        f.grip:Hide()
        f:SetResizeBounds(MIN_W, TITLE_HEIGHT, MAX_W, TITLE_HEIGHT)
        f:SetHeight(TITLE_HEIGHT)
        f.collapseButton:SetText("+")
    else
        f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
        f:SetHeight(self.charDB.height)
        f.content:Show()
        f.grip:SetShown(not self.charDB.locked)
        f.collapseButton:SetText("-")
    end
    self:UpdateTitle()
end

function T:SetLocked(locked)
    self.charDB.locked = locked and true or false
    self.frame.grip:SetShown(not locked and not self.charDB.collapsed)
end

function T:UpdateTitle()
    local f = self.frame
    local tab = self:GetActiveTab()
    if self.charDB.collapsed and tab then
        local left = self:CountTasks(tab)
        f.title:SetText(("QoL To-Do  |cffaaaaaa%s (%d left)|r"):format(tab.name, left))
    else
        f.title:SetText("QoL To-Do")
    end
end

local function makeTitleButton(parent, text)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(20, 20)
    b:SetNormalFontObject("GameFontHighlightLarge")
    b:SetHighlightFontObject("GameFontNormalLarge")
    b:SetText(text)
    return b
end

function T:CreateMainFrame()
    local f = CreateFrame("Frame", "QoLTodoFrame", UIParent, "BackdropTemplate")
    self.frame = f
    f:SetSize(self.charDB.width, self.charDB.height)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
    f:SetBackdrop(BACKDROP)
    f:SetBackdropColor(0.05, 0.05, 0.08, 0.85)
    f:SetBackdropBorderColor(0.5, 0.5, 0.55, 1)

    -- Title bar: drag to move, double-click to collapse.
    local bar = CreateFrame("Button", nil, f)
    bar:SetPoint("TOPLEFT", 4, -3)
    bar:SetPoint("TOPRIGHT", -4, -3)
    bar:SetHeight(TITLE_HEIGHT - 4)
    bar:RegisterForDrag("LeftButton")
    bar:RegisterForClicks("LeftButtonUp")
    bar:SetScript("OnDragStart", function()
        if not self.charDB.locked then f:StartMoving() end
    end)
    bar:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        self:SavePosition()
    end)
    bar:SetScript("OnDoubleClick", function()
        self:SetCollapsed(not self.charDB.collapsed)
    end)

    local close = makeTitleButton(bar, "x")
    close:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    close:SetScript("OnClick", function()
        self:SetShown(false)
        QoL:Print("to-do hidden. Type /qol todo to show it again.")
    end)

    local collapse = makeTitleButton(bar, "-")
    collapse:SetPoint("RIGHT", close, "LEFT", -2, 0)
    collapse:SetScript("OnClick", function()
        self:SetCollapsed(not self.charDB.collapsed)
    end)
    f.collapseButton = collapse

    local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", bar, "LEFT", 6, 0)
    title:SetPoint("RIGHT", collapse, "LEFT", -4, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    f.title = title

    -- Everything below the title bar; hidden when collapsed.
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -TITLE_HEIGHT)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
    f.content = content

    -- Resize grip in the bottom-right corner.
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(content:GetFrameLevel() + 5)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function()
        if not self.charDB.locked then
            anchorTopLeft(f)
            f:StartSizing("BOTTOMRIGHT")
        end
    end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        self:SavePosition()
    end)
    f.grip = grip

    f:SetScript("OnSizeChanged", function()
        if self.LayoutTabs then self:LayoutTabs() end
        if self.LayoutTasks then self:LayoutTasks() end
    end)

    self:CreateTabStrip(content)
    self:CreateTaskList(content)

    self:RestorePosition()
    self:SetLocked(self.charDB.locked)
    self:SetCollapsed(self.charDB.collapsed)
    f:SetShown(self.charDB.shown)
end
