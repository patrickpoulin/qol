-- The to-do window: title bar, move, resize, collapse, lock.
local _, ns = ...
local QoL = ns.QoL
local T = ns.Todo

local TITLE_HEIGHT = 26
local CONTENT_INSET = 6 -- content frame inset on each side
local COLLAPSED_WIDTH = 110
local MIN_W, MIN_H, MAX_W, MAX_H = 200, 160, 600, 900

local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

-- Expand/collapse arrow: points right when collapsed, down when expanded.
local ARROW_TEXTURE = "Interface\\ChatFrame\\ChatFrameExpandArrow"

local function setArrow(button, collapsed)
    local rotation = collapsed and 0 or -math.pi / 2
    button.arrow:SetRotation(rotation)
    button.glow:SetRotation(rotation)
end

-- Always anchor by the top-left corner so collapsing keeps the title in place.
local function anchorTopLeft(f)
    local left, top = f:GetLeft(), f:GetTop()
    if not left or not top then return end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

-- Width available inside the window, worked out from the window's own size.
-- Child frames' sizes can lag a frame behind a resize, so layout uses this.
function T:GetContentWidth()
    return self.charDB.collapsed and self.charDB.width - 2 * CONTENT_INSET
        or self.frame:GetWidth() - 2 * CONTENT_INSET
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
        f:SetResizeBounds(COLLAPSED_WIDTH, TITLE_HEIGHT, COLLAPSED_WIDTH, TITLE_HEIGHT)
        f:SetSize(COLLAPSED_WIDTH, TITLE_HEIGHT)
        setArrow(f.collapseButton, true)
    else
        f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
        f:SetSize(self.charDB.width, self.charDB.height)
        f.content:Show()
        f.grip:SetShown(not self.charDB.locked)
        if self.LayoutTabs then self:LayoutTabs() end
        if self.LayoutTasks then self:LayoutTasks() end
        setArrow(f.collapseButton, false)
    end
    self:UpdateTitle()
end

function T:SetLocked(locked)
    self.charDB.locked = locked and true or false
    self.frame.grip:SetShown(not locked and not self.charDB.collapsed)
end

function T:UpdateTitle()
    self.frame.title:SetText("QoL")
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

    -- Windows-style close button in the top-right corner.
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    close:SetFrameLevel(bar:GetFrameLevel() + 2)
    close:SetScript("OnClick", function()
        self:SetShown(false)
        QoL:Print("hidden. Type /qol to show it again.")
    end)

    -- Collapse/expand triangle at the left of the title.
    local collapse = CreateFrame("Button", nil, bar)
    collapse:SetSize(14, 14)
    collapse:SetPoint("LEFT", bar, "LEFT", 2, 0)
    collapse.arrow = collapse:CreateTexture(nil, "ARTWORK")
    collapse.arrow:SetAllPoints()
    collapse.arrow:SetTexture(ARROW_TEXTURE)
    collapse.glow = collapse:CreateTexture(nil, "HIGHLIGHT")
    collapse.glow:SetAllPoints()
    collapse.glow:SetTexture(ARROW_TEXTURE)
    collapse.glow:SetBlendMode("ADD")
    collapse:SetScript("OnClick", function()
        self:SetCollapsed(not self.charDB.collapsed)
    end)
    f.collapseButton = collapse

    local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", collapse, "RIGHT", 4, 0)
    title:SetPoint("RIGHT", bar, "RIGHT", -24, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    f.title = title

    -- Everything below the title bar; hidden when collapsed.
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", f, "TOPLEFT", CONTENT_INSET, -TITLE_HEIGHT)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -CONTENT_INSET, CONTENT_INSET)
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
        if self.charDB.collapsed then return end
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
