-- The Contacts panel beside the mail window, shown on the Send Mail tab.
local _, ns = ...
local QoL = ns.QoL
local M = ns.Mail

local PANEL_WIDTH = 210
local ROW_HEIGHT = 32
local SCROLLBAR_SPACE = 26

local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local function ago(seconds)
    if seconds < 3600 then return "just now" end
    if seconds < 86400 then
        local h = math.floor(seconds / 3600)
        return ("%d hour%s ago"):format(h, h == 1 and "" or "s")
    end
    local d = math.floor(seconds / 86400)
    return ("%d day%s ago"):format(d, d == 1 and "" or "s")
end

local function detailLine(c)
    local bits = {}
    if c.level then table.insert(bits, ("Level %d"):format(c.level)) end
    if c.class then table.insert(bits, M.ClassName(c.class)) end
    return table.concat(bits, " ")
end

-- Put a name in the Send Mail "To" box and move on to the subject.
function M:FillRecipient(name)
    local box = SendMailNameEditBox
    if not box then
        return QoL:Print("couldn't find the mail To field on this client.")
    end
    box:SetText(name)
    box:SetCursorPosition(#name)
    if SendMailSubjectEditBox then
        SendMailSubjectEditBox:SetFocus()
    end
end

-- Best guess at who you want to add: the To field, then your target.
function M:GuessNewName()
    local typed = SendMailNameEditBox and SendMailNameEditBox:GetText()
    if typed and typed:match("%S") then return typed end
    local ok, name = pcall(function()
        if UnitExists("target") and UnitIsPlayer("target") and not UnitIsUnit("target", "player") then
            return GetUnitName and GetUnitName("target", true) or UnitName("target")
        end
    end)
    if ok and type(name) == "string" and not (issecretvalue and issecretvalue(name)) then
        return name
    end
    return ""
end

local function rowOnEnter(row)
    local c = M.db.contacts[row.key]
    if not c then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(c.name, M.ClassColor(c.class))
    local detail = detailLine(c)
    if detail ~= "" then GameTooltip:AddLine(detail, 1, 1, 1) end
    if c.note then GameTooltip:AddLine(c.note, 1, 0.82, 0, true) end
    if c.level and c.seen then
        GameTooltip:AddLine("Level seen " .. ago(time() - c.seen), 0.6, 0.6, 0.6)
    end
    GameTooltip:AddLine("Click to send to. Right-click to edit or remove.", 0.5, 0.5, 0.5, true)
    GameTooltip:Show()
end

local function rowOnClick(row, button)
    local c = M.db.contacts[row.key]
    if not c then return end
    if button == "RightButton" then
        local key = row.key
        QoL.ShowContextMenu(row, {
            { text = "Edit", func = function() M:ShowEditor(key) end },
            { text = "Remove", func = function() M:ConfirmRemove(key) end },
        })
    else
        M:FillRecipient(c.name)
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

    row.note = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.note:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 3)
    row.note:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 3)
    row.note:SetJustifyH("LEFT")
    row.note:SetWordWrap(false)
    return row
end

function M:CreatePanel()
    if self.panel or not MailFrame then return end

    local p = CreateFrame("Frame", "QoLMailPanel", MailFrame, "BackdropTemplate")
    p:SetWidth(PANEL_WIDTH)
    p:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 2, 0)
    p:SetPoint("BOTTOMLEFT", MailFrame, "BOTTOMRIGHT", 2, 0)
    p:SetBackdrop(BACKDROP)
    p:SetBackdropColor(0, 0, 0, 0.85)
    p:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    p:EnableMouse(true)
    self.panel = p

    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -10)
    title:SetText("Contacts")

    local add = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    add:SetSize(56, 20)
    add:SetPoint("TOPRIGHT", p, "TOPRIGHT", -8, -6)
    add:SetText("+ Add")
    add:SetScript("OnClick", function() self:ShowEditor(nil, self:GuessNewName()) end)

    local search = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    search:SetHeight(20)
    search:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -32)
    search:SetPoint("TOPRIGHT", p, "TOPRIGHT", -10, -32)
    search:SetAutoFocus(false)
    search:SetMaxLetters(40)
    local hint = search:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("LEFT", search, "LEFT", 2, 0)
    hint:SetText("Search")
    search:SetScript("OnTextChanged", function(box)
        hint:SetShown(box:GetText() == "" and not box:HasFocus())
        self:RefreshPanel()
    end)
    search:SetScript("OnEditFocusGained", function() hint:Hide() end)
    search:SetScript("OnEditFocusLost", function(box) hint:SetShown(box:GetText() == "") end)
    search:SetScript("OnEscapePressed", function(box) box:SetText("") box:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
    self.searchBox = search

    local scroll = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", p, "TOPLEFT", 6, -58)
    scroll:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -SCROLLBAR_SPACE, 8)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(PANEL_WIDTH - 6 - SCROLLBAR_SPACE, 1)
    scroll:SetScrollChild(child)
    self.scrollChild = child
    self.rows = {}

    local empty = p:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("TOPLEFT", scroll, "TOPLEFT", 6, -10)
    empty:SetPoint("RIGHT", p, "RIGHT", -10, 0)
    empty:SetJustifyH("LEFT")
    self.emptyText = empty

    -- Follow the Send Mail tab. Without it, show whenever the mail window is open.
    if SendMailFrame then
        SendMailFrame:HookScript("OnShow", function() self:UpdatePanelShown() end)
        SendMailFrame:HookScript("OnHide", function() self:UpdatePanelShown() end)
    end
    p:SetScript("OnShow", function() self:RefreshPanel() end)
    self:UpdatePanelShown()
end

function M:UpdatePanelShown()
    if not self.panel then return end
    local onSendTab = not SendMailFrame or SendMailFrame:IsShown()
    self.panel:SetShown(self.charDB.panel and onSendTab)
end

function M:RefreshPanel()
    if not self.panel or not self.panel:IsShown() then return end
    local filter = self.searchBox:GetText()
    local list = self:GetContacts(filter)
    local rows, child = self.rows, self.scrollChild

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
    child:SetHeight(math.max(1, #list * ROW_HEIGHT))

    if #list > 0 then
        self.emptyText:Hide()
    else
        self.emptyText:SetText(filter ~= "" and "No matches." or "No contacts yet. Click + Add to save someone.")
        self.emptyText:Show()
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("MAIL_SHOW")
events:SetScript("OnEvent", function()
    if not M.db then return end
    M:CreatePanel()
    M:UpdatePanelShown()
    M:RefreshPanel()
    M:RequestGuildRoster()
end)
