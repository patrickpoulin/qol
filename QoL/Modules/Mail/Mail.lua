-- Mail module: an address book at the mailbox. Registration, contacts and "/qol mail".
-- Contacts are only ever added by the player (panel or /qol mail add).
local _, ns = ...
local QoL = ns.QoL

local M = QoL:RegisterModule("mail", {
    name = "Mail",
    description = "address book at the mailbox",
    defaults = {
        -- [key] = { name, class (token like "MAGE"), level, note, seen (time level was last seen) }
        contacts = {},
    },
    charDefaults = {
        panel = true, -- show the Contacts panel on the Send Mail tab
    },
    slashHelp = {
        "/qol mail - list your contacts",
        "/qol mail add <name> - add a contact",
        "/qol mail remove <name> - remove a contact",
        "/qol mail note <name> <text> - set a contact's note",
        "/qol mail show | hide - turn the mailbox panel on or off",
    },
})
ns.Mail = M

local MAX_NAME, MAX_NOTE = 64, 255

----------------------------------------------------------------------
-- Names and classes
----------------------------------------------------------------------

-- Tidy a typed name: trim, capitalise the first letter, keep any "-Realm".
function M.CleanName(name)
    name = (name or ""):match("^%s*(.-)%s*$"):gsub("%s+", "")
    if name == "" then return nil end
    return (name:gsub("^%l", string.upper)):sub(1, MAX_NAME)
end

-- Lookup key: lower case, realm dropped when it is the player's own realm.
function M.KeyFor(name)
    if not name or name == "" then return nil end
    if Ambiguate then
        local ok, short = pcall(Ambiguate, name, "none")
        if ok and type(short) == "string" then name = short end
    end
    return name:lower()
end

local FALLBACK_CLASSES = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN",
    "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER",
}

-- Class tokens this client knows about, in the game's usual order.
function M.ClassList()
    if M.classList then return M.classList end
    local names = LOCALIZED_CLASS_NAMES_MALE or {}
    local list = {}
    for _, token in ipairs(CLASS_SORT_ORDER or FALLBACK_CLASSES) do
        if names[token] or not LOCALIZED_CLASS_NAMES_MALE then
            table.insert(list, token)
        end
    end
    M.classList = list
    return list
end

function M.ClassName(token)
    if not token then return nil end
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token])
        or token:sub(1, 1) .. token:sub(2):lower()
end

-- Localised class name (male or female form) back to its token.
function M.ClassToken(localized)
    if type(localized) ~= "string" or localized == "" then return nil end
    if not M.classByName then
        M.classByName = {}
        for _, map in ipairs({ LOCALIZED_CLASS_NAMES_MALE or {}, LOCALIZED_CLASS_NAMES_FEMALE or {} }) do
            for token, text in pairs(map) do M.classByName[text] = token end
        end
    end
    if M.classByName[localized] then return M.classByName[localized] end
    local upper = localized:upper():gsub("%s", "")
    for _, token in ipairs(M.ClassList()) do
        if token == upper then return token end
    end
end

-- r, g, b for a class token (white when unknown).
function M.ClassColor(token)
    local c = token and ((C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(token))
        or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]))
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

----------------------------------------------------------------------
-- Contacts
----------------------------------------------------------------------

function M:GetContact(name)
    local key = M.KeyFor(name)
    return key and self.db.contacts[key], key
end

-- Contacts sorted by name, optionally filtered by text in the name or note.
function M:GetContacts(filter)
    filter = filter and filter:lower() or ""
    local list = {}
    for key, c in pairs(self.db.contacts) do
        if filter == "" or c.name:lower():find(filter, 1, true)
            or (c.note and c.note:lower():find(filter, 1, true)) then
            table.insert(list, { key = key, contact = c })
        end
    end
    table.sort(list, function(a, b) return a.contact.name:lower() < b.contact.name:lower() end)
    return list
end

local function cleanFields(fields)
    local level = tonumber(fields.level)
    if level then level = math.floor(level) end
    if level and (level < 1 or level > 999) then level = nil end
    local note = fields.note and fields.note:match("^%s*(.-)%s*$") or ""
    return fields.class or nil, level, note ~= "" and note:sub(1, MAX_NOTE) or nil
end

-- Add or save a contact. `oldKey` is set when editing an existing one.
-- Returns the contact, or nil and a message.
function M:SaveContact(fields, oldKey)
    local name = M.CleanName(fields.name)
    if not name then return nil, "enter a name." end
    local key = M.KeyFor(name)
    if key ~= oldKey and self.db.contacts[key] then
        return nil, ("%s is already in your contacts."):format(name)
    end

    local class, level, note = cleanFields(fields)
    local old = oldKey and self.db.contacts[oldKey]
    if oldKey then self.db.contacts[oldKey] = nil end
    local contact = {
        name = name,
        class = class,
        level = level,
        note = note,
        seen = old and old.level == level and old.seen or nil,
    }
    self.db.contacts[key] = contact
    if not oldKey then self:LearnFromGame(name) end
    self:Refresh()
    return contact
end

function M:RemoveContact(key)
    if not self.db.contacts[key] then return false end
    self.db.contacts[key] = nil
    self:Refresh()
    return true
end

-- The game saw this character: refresh class and level if they are a contact.
-- Never adds anyone, and never blanks a value with an unknown one.
function M:Learn(name, class, level)
    local contact = self:GetContact(name)
    if not contact then return end
    local changed = false
    if class and contact.class ~= class then
        contact.class, changed = class, true
    end
    level = tonumber(level)
    if level and level > 0 then
        if contact.level ~= level then contact.level, changed = level, true end
        contact.seen = time()
    end
    if changed then self:Refresh() end
end

function M:Refresh()
    if self.RefreshPanel then self:RefreshPanel() end
end

----------------------------------------------------------------------
-- /qol mail
----------------------------------------------------------------------

local function describe(c)
    local bits = {}
    if c.level then table.insert(bits, ("level %d"):format(c.level)) end
    if c.class then table.insert(bits, M.ClassName(c.class)) end
    local line = c.name
    if #bits > 0 then line = line .. " (" .. table.concat(bits, " ") .. ")" end
    if c.note then line = line .. " - " .. c.note end
    return line
end

function M:OnSlash(args)
    local cmd, rest = args:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    if cmd == "" or cmd == "list" then
        local list = self:GetContacts()
        if #list == 0 then
            return QoL:Print("no contacts yet. Add one with /qol mail add <name> or the + on the mailbox panel.")
        end
        QoL:Print(("%d contact%s:"):format(#list, #list == 1 and "" or "s"))
        for _, item in ipairs(list) do print("  " .. describe(item.contact)) end
    elseif cmd == "add" then
        if rest == "" then return QoL:Print("usage: /qol mail add <name>") end
        local contact, err = self:SaveContact({ name = rest })
        if not contact then return QoL:Print(err) end
        QoL:Print("added " .. describe(contact))
    elseif cmd == "remove" then
        if rest == "" then return QoL:Print("usage: /qol mail remove <name>") end
        local _, key = self:GetContact(rest)
        if not self:RemoveContact(key) then
            return QoL:Print(("%s isn't in your contacts."):format(rest))
        end
        QoL:Print("removed " .. rest .. ".")
    elseif cmd == "note" then
        local name, text = rest:match("^(%S+)%s*(.-)$")
        local contact, key = self:GetContact(name)
        if not contact then
            return QoL:Print(name and ("%s isn't in your contacts."):format(name) or "usage: /qol mail note <name> <text>")
        end
        self:SaveContact({ name = contact.name, class = contact.class, level = contact.level, note = text }, key)
        QoL:Print(text ~= "" and ("note saved for %s."):format(contact.name) or ("note cleared for %s."):format(contact.name))
    elseif cmd == "show" or cmd == "hide" then
        self.charDB.panel = cmd == "show"
        self:UpdatePanelShown()
        QoL:Print(cmd == "show" and "contacts panel on." or "contacts panel off.")
    else
        QoL:Print("unknown command. Type /qol for help.")
    end
end
