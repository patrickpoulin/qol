-- The built-in Contacts tab: the mail address book (names, class, level and
-- notes) inside the QoL window, so it can be read and edited anywhere.
-- The contacts themselves live in the Mail module (ns.Mail), which loads after
-- this file, so it is only looked up when the tab is used.
local _, ns = ...
local QoL = ns.QoL
local T = ns.Todo

local SCROLLBAR_SPACE = 24
local ROW_HEIGHT = 34
local TOP_BAR = 26 -- search box and + Add button

table.insert(T.referenceTabs, {
    id = "ref:contacts", name = "Contacts", reference = true, panel = "contacts", tasks = {},
})

local function mail() return ns.Mail end

local function atSendMail()
    return SendMailFrame and SendMailFrame:IsShown() and SendMailNameEditBox ~= nil
end

local function rowOnEnter(row)
    local M = mail()
    local c = M and M.db.contacts[row.key]
    if not c then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(c.name, M.ClassColor(c.class))
    local bits = {}
    if c.level then table.insert(bits, ("Level %d"):format(c.level)) end
    if c.class then table.insert(bits, M.ClassName(c.class)) end
    if #bits > 0 then GameTooltip:AddLine(table.concat(bits, " "), 1, 1, 1) end
    if c.note then GameTooltip:AddLine(c.note, 1, 0.82, 0, true) end
    GameTooltip:AddLine(atSendMail() and "Click to send to. Right-click to edit or remove."
        or "Click to edit. Right-click to edit or remove.", 0.5, 0.5, 0.5, true)
    GameTooltip:Show()
end

local function rowOnClick(row, button)
    local M = mail()
    local c = M and M.db.contacts[row.key]
    if not c then return end
    local key = row.key
    if button == "RightButton" then
        QoL.ShowContextMenu(row, {
            { text = "Edit", func = function() M:ShowEditor(key) end },
            { text = "Remove", func = function() M:ConfirmRemove(key) end },
        })
    elseif atSendMail() then
        M:FillRecipient(c.name)
    else
        M:ShowEditor(key)
    end
end

local function createRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row:SetScript("OnEnter", rowOnEnter)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", rowOnClick)

    row.level = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.level:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -3)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -3)
    row.name:SetPoint("RIGHT", row.level, "LEFT", -4, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.note = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.note:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 3)
    row.note:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 3)
    row.note:SetJustifyH("LEFT")
    row.note:SetWordWrap(false)
    row.note:SetTextColor(0.8, 0.8, 0.8)
    return row
end

function T:CreateContactsPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", self.tabStrip, "BOTTOMLEFT", 0, -6)
    panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 4)
    panel:Hide()
    self.contactsPanel = panel

    local add = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    add:SetSize(56, 20)
    add:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14, 0)
    add:SetText("+ Add")
    add:SetScript("OnClick", function()
        local M = mail()
        if M then M:ShowEditor(nil, M:GuessNewName()) end
    end)

    local search = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    search:SetHeight(20)
    search:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, 0)
    search:SetPoint("RIGHT", add, "LEFT", -8, 0)
    search:SetAutoFocus(false)
    search:SetMaxLetters(40)
    local hint = search:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("LEFT", search, "LEFT", 2, 0)
    hint:SetText("Search names and notes")
    search:SetScript("OnTextChanged", function(box)
        hint:SetShown(box:GetText() == "" and not box:HasFocus())
        self:RefreshContacts()
    end)
    search:SetScript("OnEditFocusGained", function() hint:Hide() end)
    search:SetScript("OnEditFocusLost", function(box) hint:SetShown(box:GetText() == "") end)
    search:SetScript("OnEscapePressed", function(box) box:SetText("") box:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
    panel.search = search

    local scroll = QoL.CreateScrollFrame(panel)
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -TOP_BAR)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -SCROLLBAR_SPACE, 0)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    panel.scroll, panel.child, panel.rows = scroll, child, {}

    local empty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("TOPLEFT", scroll, "TOPLEFT", 6, -10)
    empty:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
    empty:SetJustifyH("LEFT")
    panel.empty = empty
end

function T:ShowContacts()
    self.contactsPanel:Show()
    self:RefreshContacts()
end

function T:RefreshContacts()
    local panel = self.contactsPanel
    if not panel or not panel:IsShown() then return end
    local M = mail()
    local list = (M and M.db) and M:GetContacts(panel.search:GetText()) or {}
    local rows, child = panel.rows, panel.child

    for i, item in ipairs(list) do
        local row = rows[i] or createRow(child)
        rows[i] = row
        local c = item.contact
        row.key = item.key
        row.name:SetText(c.name)
        row.name:SetTextColor(M.ClassColor(c.class))
        row.level:SetText(c.level and tostring(c.level) or "")
        row.note:SetText(c.note or "")
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:SetPoint("RIGHT", child, "RIGHT", 0, 0)
        row:Show()
    end
    for i = #list + 1, #rows do rows[i]:Hide() end

    if not M then
        panel.empty:SetText("The mail address book isn't loaded.")
        panel.empty:Show()
    elseif #list > 0 then
        panel.empty:Hide()
    else
        panel.empty:SetText(panel.search:GetText() ~= "" and "No matches."
            or "No contacts yet. Click + Add to save someone.")
        panel.empty:Show()
    end
    self:LayoutContacts()
end

function T:LayoutContacts()
    local panel = self.contactsPanel
    if not panel or not panel:IsShown() then return end
    local width = self:GetContentWidth() - SCROLLBAR_SPACE
    if width <= 0 then return end
    local shown = 0
    for _, row in ipairs(panel.rows) do
        if row:IsShown() then shown = shown + 1 end
    end
    panel.child:SetWidth(width)
    panel.child:SetHeight(math.max(1, shown * ROW_HEIGHT))
end
