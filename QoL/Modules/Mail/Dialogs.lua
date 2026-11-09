-- Add/edit contact window and the remove confirmation.
local _, ns = ...
local QoL = ns.QoL
local M = ns.Mail

local BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 24,
    insets = { left = 6, right = 6, top = 6, bottom = 6 },
}

StaticPopupDialogs["QOL_MAIL_CONFIRM"] = {
    text = "%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data) data.onAccept() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function M:ConfirmRemove(key)
    local c = self.db.contacts[key]
    if not c then return end
    StaticPopup_Show("QOL_MAIL_CONFIRM", ("Remove %s from your contacts?"):format(c.name), nil, {
        onAccept = function() self:RemoveContact(key) end,
    })
end

local function label(parent, text, anchor, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y)
    fs:SetText(text)
    return fs
end

local function setClass(f, token)
    f.class = token
    local text = token and M.ClassName(token) or "Unknown"
    f.classButton:SetText(text)
    f.classButton:GetFontString():SetTextColor(M.ClassColor(token))
end

local function save(f)
    local contact, err = M:SaveContact({
        name = f.nameBox:GetText(),
        class = f.class,
        level = f.levelBox:GetText(),
        note = f.noteBox:GetText(),
    }, f.key)
    if not contact then
        f.error:SetText(err)
        return
    end
    f:Hide()
end

local function createEditor()
    local f = CreateFrame("Frame", "QoLMailEditor", UIParent, "BackdropTemplate")
    f:SetSize(280, 270)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop(BACKDROP)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()
    table.insert(UISpecialFrames, "QoLMailEditor") -- Escape closes it

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", f, "TOP", 0, -14)

    local nameLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -38)
    nameLabel:SetText("Name")
    f.nameBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.nameBox:SetSize(236, 20)
    f.nameBox:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 6, -2)
    f.nameBox:SetAutoFocus(false)
    f.nameBox:SetMaxLetters(64)

    local classLabel = label(f, "Class", nameLabel, -32)
    f.classButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.classButton:SetSize(130, 22)
    f.classButton:SetPoint("TOPLEFT", classLabel, "BOTTOMLEFT", 0, -2)
    f.classButton:SetScript("OnClick", function(btn)
        local items = { { text = "Unknown", func = function() setClass(f, nil) end } }
        for _, token in ipairs(M.ClassList()) do
            table.insert(items, { text = M.ClassName(token), func = function() setClass(f, token) end })
        end
        QoL.ShowContextMenu(btn, items)
    end)

    local levelLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    levelLabel:SetPoint("LEFT", classLabel, "LEFT", 150, 0)
    levelLabel:SetText("Level")
    f.levelBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.levelBox:SetSize(50, 20)
    f.levelBox:SetPoint("TOPLEFT", levelLabel, "BOTTOMLEFT", 6, -2)
    f.levelBox:SetAutoFocus(false)
    f.levelBox:SetNumeric(true)
    f.levelBox:SetMaxLetters(3)

    local noteLabel = label(f, "Note", classLabel, -34)
    local noteBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
    noteBg:SetPoint("TOPLEFT", noteLabel, "BOTTOMLEFT", 0, -4)
    noteBg:SetSize(244, 76)
    noteBg:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    noteBg:SetBackdropColor(0, 0, 0, 0.6)
    f.noteBox = CreateFrame("EditBox", nil, noteBg)
    f.noteBox:SetPoint("TOPLEFT", noteBg, "TOPLEFT", 6, -6)
    f.noteBox:SetPoint("BOTTOMRIGHT", noteBg, "BOTTOMRIGHT", -6, 6)
    f.noteBox:SetMultiLine(true)
    f.noteBox:SetAutoFocus(false)
    f.noteBox:SetMaxLetters(255)
    f.noteBox:SetFontObject("ChatFontNormal")
    noteBg:EnableMouse(true)
    noteBg:SetScript("OnMouseDown", function() f.noteBox:SetFocus() end)

    f.error = f:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
    f.error:SetPoint("TOPLEFT", noteBg, "BOTTOMLEFT", 0, -6)
    f.error:SetPoint("RIGHT", noteBg, "RIGHT", 0, 0)
    f.error:SetJustifyH("LEFT")

    local saveButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    saveButton:SetSize(90, 22)
    saveButton:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 14)
    saveButton:SetText(SAVE or "Save")
    saveButton:SetScript("OnClick", function() save(f) end)

    local cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    cancel:SetSize(90, 22)
    cancel:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 14)
    cancel:SetText(CANCEL)
    cancel:SetScript("OnClick", function() f:Hide() end)

    -- Tab moves between fields; Enter in a one-line box saves.
    local order = { f.nameBox, f.levelBox, f.noteBox }
    for i, box in ipairs(order) do
        box:SetScript("OnTabPressed", function() order[i % #order + 1]:SetFocus() end)
        box:SetScript("OnEscapePressed", function() f:Hide() end)
    end
    f.nameBox:SetScript("OnEnterPressed", function() save(f) end)
    f.levelBox:SetScript("OnEnterPressed", function() save(f) end)

    return f
end

-- key = existing contact to edit, or nil to add one (pre-filled with `name`).
function M:ShowEditor(key, name)
    self.editor = self.editor or createEditor()
    local f = self.editor
    local c = key and self.db.contacts[key]
    f.key = c and key or nil
    f.title:SetText(c and "Edit contact" or "Add contact")
    f.nameBox:SetText(c and c.name or name or "")
    f.levelBox:SetText(c and c.level and tostring(c.level) or "")
    f.noteBox:SetText(c and c.note or "")
    f.error:SetText("")
    setClass(f, c and c.class)

    f:ClearAllPoints()
    if self.panel and self.panel:IsShown() then
        f:SetPoint("TOPLEFT", self.panel, "TOPRIGHT", 4, 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    end
    f:Show()
    if c then f.noteBox:SetFocus() else f.nameBox:SetFocus() end
end
