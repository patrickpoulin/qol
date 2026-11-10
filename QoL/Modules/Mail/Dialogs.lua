-- Add/edit contact window and the remove confirmation.
local _, ns = ...
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

local CLASS_COLS, CLASS_W, CLASS_H = 3, 80, 20

local function label(parent, text, anchor, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y)
    fs:SetText(text)
    return fs
end

-- Highlight the chosen class button and dim the rest.
local function setClass(f, token)
    f.class = token
    for _, btn in ipairs(f.classButtons) do
        local chosen = btn.token == token
        btn.selected:SetShown(chosen)
        btn.text:SetAlpha((chosen or not token) and 1 or 0.45)
    end
    f.classText:SetText(token and M.ClassName(token) or "none picked")
    f.classText:SetTextColor(M.ClassColor(token))
end

local function save(f)
    local contact, err = M:SaveContact({
        name = f.nameBox:GetText(),
        class = f.class,
        level = f.level, -- not edited here; kept from what the game last saw
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
    f:SetSize(280, 1) -- height set once the class grid is built
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

    -- Every class as a coloured button: one click picks it, a second click clears it.
    local classLabel = label(f, "Class", nameLabel, -32)
    f.classText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.classText:SetPoint("LEFT", classLabel, "RIGHT", 6, 0)
    f.classButtons = {}
    local classes = M.ClassList()
    for i, token in ipairs(classes) do
        local btn = CreateFrame("Button", nil, f)
        btn:SetSize(CLASS_W, CLASS_H)
        local col, row = (i - 1) % CLASS_COLS, math.floor((i - 1) / CLASS_COLS)
        btn:SetPoint("TOPLEFT", classLabel, "BOTTOMLEFT", col * (CLASS_W + 2), -4 - row * (CLASS_H + 2))
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.5)
        btn.selected = btn:CreateTexture(nil, "BORDER")
        btn.selected:SetAllPoints()
        local r, g, b = M.ClassColor(token)
        btn.selected:SetColorTexture(r, g, b, 0.35)
        btn.selected:Hide()
        btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.text:SetPoint("CENTER")
        btn.text:SetText(M.ClassName(token))
        btn.text:SetTextColor(r, g, b)
        btn.token = token
        btn:SetScript("OnClick", function()
            setClass(f, f.class ~= token and token or nil)
        end)
        table.insert(f.classButtons, btn)
    end
    local classRows = math.max(1, math.ceil(#classes / CLASS_COLS))
    local gridHeight = classRows * (CLASS_H + 2) + 4

    local noteLabel = label(f, "Note", classLabel, -(gridHeight + 6))
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

    -- Name, class grid, note (76), error line and buttons.
    f:SetHeight(38 + 40 + 16 + gridHeight + 6 + 16 + 76 + 22 + 48)

    -- Tab moves between fields; Enter in the name box saves.
    local order = { f.nameBox, f.noteBox }
    for i, box in ipairs(order) do
        box:SetScript("OnTabPressed", function() order[i % #order + 1]:SetFocus() end)
        box:SetScript("OnEscapePressed", function() f:Hide() end)
    end
    f.nameBox:SetScript("OnEnterPressed", function() save(f) end)

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
    f.level = c and c.level or nil
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
