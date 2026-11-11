-- Cooldowns ("/qol cds"): a movable window of spell icons with cooldown
-- timers, for spells and racials picked on the CDs tab. Ready spells sit at
-- the top, then spells on cooldown with the one that comes back soonest first.
local _, ns = ...
local QoL = ns.QoL

local C_Spell, C_SpellBook = _G.C_Spell, _G.C_SpellBook

local MIN_SIZE, MAX_SIZE = 16, 80
local PAD, GAP, HEADER = 4, 3, 18
local GCD = 1.5 -- cooldowns this short are just the global cooldown
local TICK = 0.1

local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local C = QoL:RegisterModule("cds", {
    name = "Cooldowns",
    description = "window of spell and racial cooldown timers",
    -- Per character: each class has its own spells.
    charDefaults = {
        spells = {},       -- tracked spell names, in the order you picked them
        shown = true,
        locked = false,
        point = nil,       -- { left, top } relative to the bottom-left of the screen
        iconSize = 36,
        sideBySide = true, -- icons in a row; off stacks them in a column
        hideReady = false,
        onlyCooldowns = true, -- CDs tab lists only spells that have a cooldown
    },
    slashHelp = {
        "/qol cds - open the CDs tab to pick spells",
        "/qol cds add <spell> | remove <spell> | list",
        "/qol cds show | hide | lock | unlock | reset",
    },
})
ns.Cooldowns = C

-- Spellbook ----------------------------------------------------------------

local function isSecret(v) return QoL.IsSecret(v) end

local function spellIcon(id)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
    return _G.GetSpellTexture and _G.GetSpellTexture(id)
end

local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return _G.GetSpellInfo and (_G.GetSpellInfo(id))
end

-- Base cooldown in seconds, 0 for none, or nil when the client can't say.
local function baseCooldown(id)
    local get = _G.GetSpellBaseCooldown
    if not get then return nil end
    local ok, ms = pcall(get, id)
    if not ok or type(ms) ~= "number" or isSecret(ms) then return nil end
    return ms / 1000
end

-- Calls add(name, spellID, icon, tabName) for every learned, non-passive
-- spell in the player's spellbook.
local function eachSpell(add)
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and _G.Enum and _G.Enum.SpellBookSpellBank then
        local bank = _G.Enum.SpellBookSpellBank.Player
        local spellType = _G.Enum.SpellBookItemType and _G.Enum.SpellBookItemType.Spell
        for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local line = C_SpellBook.GetSpellBookSkillLineInfo(i)
            if line and not line.shouldHide then
                for j = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                    local item = C_SpellBook.GetSpellBookItemInfo(j, bank)
                    if item and item.spellID and not item.isPassive
                        and (spellType == nil or item.itemType == spellType) then
                        add(item.name, item.spellID, item.iconID, line.name)
                    end
                end
            end
        end
        return
    end

    local getTabs, getTab = _G.GetNumSpellTabs, _G.GetSpellTabInfo
    local getItem, isPassive = _G.GetSpellBookItemInfo, _G.IsPassiveSpell
    if not (getTabs and getTab and getItem) then return end
    local book = _G.BOOKTYPE_SPELL or "spell"
    for i = 1, getTabs() do
        local tabName, _, offset, count = getTab(i)
        for j = offset + 1, offset + count do
            local kind, id = getItem(j, book)
            if kind == "SPELL" and id and not (isPassive and isPassive(j, book)) then
                local name = (_G.GetSpellBookItemName and _G.GetSpellBookItemName(j, book)) or spellName(id)
                add(name, id, spellIcon(id), tabName)
            end
        end
    end
end

-- Rebuild the list of spells from the spellbook. Ranks of one spell share a
-- cooldown, so each name appears once, using its highest rank.
function C:ScanSpellbook()
    local list, byName = {}, {}
    local ok, err = pcall(eachSpell, function(name, id, icon, tabName)
        if type(name) ~= "string" or name == "" then return end
        local entry = byName[name]
        if not entry then
            entry = { name = name, tab = tabName }
            byName[name] = entry
            table.insert(list, entry)
        end
        entry.id = id
        entry.icon = icon or spellIcon(id) or entry.icon
    end)
    if not ok then QoL:Print("couldn't read the spellbook: " .. tostring(err)) end
    for _, entry in ipairs(list) do
        entry.cooldown = baseCooldown(entry.id)
    end
    self.spellbook, self.byName = list, byName
    return list
end

function C:GetSpellbook()
    return self.spellbook or self:ScanSpellbook()
end

-- True when the client can tell which spells have a cooldown.
function C:CanFilterCooldowns()
    return _G.GetSpellBaseCooldown ~= nil
end

-- Spells for the CDs tab: tracked ones first, then the rest of the
-- spellbook (optionally only spells with a cooldown) matching `search`.
function C:GetPickList(search)
    search = (search or ""):lower()
    local function matches(name) return search == "" or name:lower():find(search, 1, true) end
    local list, seen = {}, {}
    for _, name in ipairs(self.charDB.spells) do
        if matches(name) then
            local entry = self:GetSpellbook() and self.byName[name]
            table.insert(list, entry or { name = name, missing = true })
        end
        seen[name] = true
    end
    local filter = self.charDB.onlyCooldowns and self:CanFilterCooldowns()
    for _, entry in ipairs(self:GetSpellbook()) do
        if not seen[entry.name] and matches(entry.name)
            and not (filter and entry.cooldown ~= nil and entry.cooldown <= 0) then
            table.insert(list, entry)
        end
    end
    return list
end

-- Tracked spells -------------------------------------------------------------

local function indexOf(list, name)
    for i, v in ipairs(list) do
        if v == name then return i end
    end
end

function C:IsTracked(name)
    return indexOf(self.charDB.spells, name) ~= nil
end

function C:SetTracked(name, on)
    local spells = self.charDB.spells
    local i = indexOf(spells, name)
    if on and not i then
        table.insert(spells, name)
    elseif not on and i then
        table.remove(spells, i)
    end
    self:Changed()
end

-- Spellbook entry for a name typed in chat, ignoring case.
function C:FindSpell(text)
    local lower = text:lower()
    for _, entry in ipairs(self:GetSpellbook()) do
        if entry.name:lower() == lower then return entry end
    end
    for _, name in ipairs(self.charDB.spells) do
        if name:lower() == lower then return { name = name } end
    end
end

function C:SetOption(key, value)
    self.charDB[key] = value
    self:Changed()
end

function C:SetIconSize(size)
    size = math.floor(math.max(MIN_SIZE, math.min(MAX_SIZE, size)) + 0.5)
    if size == self.charDB.iconSize then return end
    self.charDB.iconSize = size
    self:Changed()
end
C.MIN_SIZE, C.MAX_SIZE = MIN_SIZE, MAX_SIZE

-- Redraw the window and the CDs tab after a setting changed.
function C:Changed()
    if self.frame then
        self:ApplyLock()
        self:Update()
    end
    local todo = ns.Todo
    if todo and todo.RefreshCooldowns then todo:RefreshCooldowns() end
end

-- Cooldown state ----------------------------------------------------------------

-- start, duration, enabled for a spell. Values may be secret on newer clients.
local function getCooldown(id)
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(id)
        if info then return info.startTime, info.duration, info.isEnabled end
        return
    end
    if _G.GetSpellCooldown then return _G.GetSpellCooldown(id) end
end

-- Fills `state` for one spell:
--   remaining  seconds left (0 when ready), or nil when the client hides it
--   waiting    the cooldown starts when an effect ends (e.g. Stealth)
local function readState(state, id)
    local ok, start, duration, enabled = pcall(getCooldown, id)
    state.start, state.duration, state.secret = nil, nil, false
    state.remaining, state.waiting = 0, false
    if not ok then return end
    if isSecret(start) or isSecret(duration) or isSecret(enabled) then
        state.secret, state.start, state.duration, state.remaining = true, start, duration, nil
        return
    end
    if enabled == false or enabled == 0 then
        state.waiting = true
        return
    end
    if start and duration and start > 0 and duration > GCD then
        state.start, state.duration = start, duration
        state.remaining = math.max(0, start + duration - _G.GetTime())
    end
end

-- Sort key: ready first, then soonest back, then hidden or waiting ones.
local function sortKey(state)
    if state.remaining == nil then return 1e8 end
    if state.waiting then return 1e9 end
    return state.remaining
end

local function formatTime(s)
    if s >= 3600 then return ("%dh"):format(math.ceil(s / 3600)) end
    if s >= 60 then return ("%d:%02d"):format(math.floor(s / 60), math.floor(s % 60)) end
    return ("%d"):format(math.ceil(s))
end

-- Window ---------------------------------------------------------------------

local function createIcon(parent)
    local b = CreateFrame("Frame", nil, parent)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- trim the default border

    local ok, cd = pcall(CreateFrame, "Cooldown", nil, b, "CooldownFrameTemplate")
    if not ok or not cd then cd = CreateFrame("Cooldown", nil, b) end
    cd:SetAllPoints()
    if cd.SetDrawEdge then cd:SetDrawEdge(false) end
    b.cd = cd

    -- Text sits on its own frame so it draws above the cooldown swipe.
    local overlay = CreateFrame("Frame", nil, b)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(cd:GetFrameLevel() + 2)
    b.timer = overlay:CreateFontString(nil, "OVERLAY")
    b.timer:SetPoint("CENTER", 0, 0)
    b.state = {}
    return b
end

local function setCooldown(b, start, duration)
    if b.cdStart == start and b.cdDuration == duration then return end
    b.cdStart, b.cdDuration = start, duration
    pcall(b.cd.SetCooldown, b.cd, start or 0, duration or 0)
end

local function setHideNumbers(b, hide)
    if b.cd.SetHideCountdownNumbers and b.hideNumbers ~= hide then
        b.hideNumbers = hide
        b.cd:SetHideCountdownNumbers(hide)
    end
end

-- Keep the window's top-left corner where it is when it grows or shrinks.
local function anchorTopLeft(f)
    local left, top = f:GetLeft(), f:GetTop()
    if not left or not top then return end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

function C:SavePosition()
    anchorTopLeft(self.frame)
    self.charDB.point = { self.frame:GetLeft(), self.frame:GetTop() }
end

function C:RestorePosition()
    local f, p = self.frame, self.charDB.point
    f:ClearAllPoints()
    if p and p[1] and p[2] then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p[1], p[2])
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
    end
end

function C:ResetPosition()
    self.charDB.point = nil
    self.charDB.shown = true
    self:RestorePosition()
    self:Changed()
    QoL:Print("cooldown window moved back near the centre of the screen.")
end

function C:ApplyLock()
    local f, locked = self.frame, self.charDB.locked
    f:EnableMouse(not locked) -- locked: clicks go through to the game
    f:SetBackdropColor(0.05, 0.05, 0.08, locked and 0 or 0.7)
    f:SetBackdropBorderColor(0.5, 0.5, 0.55, locked and 0 or 1)
    f.title:SetShown(not locked)
    f.grip:SetShown(not locked)
    f.lock:SetText(locked and "Unlock" or "Lock")
    f.lock:SetShown(not locked)
end

function C:CreateWindow()
    local f = CreateFrame("Frame", "QoLCooldownsFrame", UIParent, "BackdropTemplate")
    self.frame = f
    f:SetSize(80, 80)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetBackdrop(BACKDROP)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(frame)
        if not self.charDB.locked then frame:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        self:SavePosition()
    end)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 2, -4)
    f.title:SetText("CDs")

    -- Lock button in the header. While locked it only shows with the mouse over the window.
    local lock = CreateFrame("Button", nil, f, "BackdropTemplate")
    lock:SetSize(44, 14)
    lock:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -3)
    lock:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    lock:SetBackdropColor(0, 0, 0, 0.6)
    lock:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
    lock:SetNormalFontObject("GameFontHighlightSmall")
    lock:SetHighlightFontObject("GameFontNormalSmall")
    lock:SetText("Lock")
    lock:SetScript("OnClick", function() self:SetOption("locked", not self.charDB.locked) end)
    lock:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:SetText(self.charDB.locked and "Unlock the window" or "Lock the window")
        GameTooltip:AddLine("Locked, the window can't be moved or resized and clicks go through it. "
            .. "Hover it to find this button again.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    lock:SetScript("OnLeave", GameTooltip_Hide)
    f.lock = lock

    -- Resize grip: dragging it changes the size of the icons, and the box with them.
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    grip:SetFrameLevel(f:GetFrameLevel() + 10)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function()
        local x, y = _G.GetCursorPosition()
        grip.sizing = { x = x, y = y, size = self.charDB.iconSize }
    end)
    grip:SetScript("OnMouseUp", function() grip.sizing = nil end)
    grip:SetScript("OnHide", function() grip.sizing = nil end)
    f.grip = grip

    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.empty:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 2, -HEADER - 2)
    f.empty:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
    f.empty:SetJustifyH("LEFT")
    f.empty:SetText("Pick spells on the CDs tab (/qol cds).")

    self.icons = {}
    -- The timer runs on its own frame so it keeps going while the window is
    -- hidden (e.g. locked with every spell ready and "hide ready" on).
    local driver = CreateFrame("Frame", nil, UIParent)
    local elapsed = 0
    driver:SetScript("OnUpdate", function(_, dt)
        if grip.sizing then self:DragResize() end
        if self.charDB.locked and f:IsShown() then
            local over = f:IsMouseOver() or lock:IsMouseOver()
            if lock:IsShown() ~= over then lock:SetShown(over) end
        end
        elapsed = elapsed + dt
        if elapsed < TICK then return end
        elapsed = 0
        self:Update()
    end)
    QoL:GuardScripts("Cooldowns", driver, "OnUpdate")

    self:RestorePosition()
    self:ApplyLock()
end

-- Follow the cursor while the grip is held. In a column the box is one icon
-- wide, so its right edge tracks the mouse; in a row its bottom edge does.
function C:DragResize()
    local s = self.frame.grip.sizing
    local x, y = _G.GetCursorPosition()
    local scale = self.frame:GetEffectiveScale()
    local delta = self.charDB.sideBySide and (s.y - y) / scale or (x - s.x) / scale
    self:SetIconSize(s.size + delta)
end

function C:Update()
    local f = self.frame
    if not f then return end
    local db = self.charDB
    if not db.shown then
        f:Hide()
        return
    end

    -- Work out each tracked spell's state and the order to show them in.
    local order = self.order or {}
    wipe(order)
    self.order = order
    for i, name in ipairs(db.spells) do
        local entry = self.byName and self.byName[name]
        if entry then
            local b = self.icons[i] or createIcon(f)
            self.icons[i] = b
            b.entry, b.index = entry, i
            readState(b.state, entry.id)
            if not (db.hideReady and b.state.remaining == 0 and not b.state.waiting) then
                table.insert(order, b)
            end
        end
    end
    for i = #db.spells + 1, #self.icons do self.icons[i]:Hide() end
    table.sort(order, function(a, b)
        local ka, kb = sortKey(a.state), sortKey(b.state)
        if ka ~= kb then return ka < kb end
        return a.index < b.index
    end)

    local size = db.iconSize
    local n = #order
    local empty = n == 0
    if empty and db.locked then
        f:Hide()
        return
    end

    -- Size the box around the icons, keeping room for the title and lock button.
    local slots = math.max(n, 1)
    local length = slots * size + (slots - 1) * GAP
    local w, h
    if db.sideBySide then
        w, h = PAD * 2 + length, HEADER + size + PAD
    else
        w, h = PAD * 2 + size, HEADER + length + PAD
    end
    local contentWidth = w - 2 * PAD
    if empty then
        w, h = math.max(w, 150), math.max(h, HEADER + 36)
        f.empty:SetWidth(w - 2 * PAD - 4)
    end
    w = math.max(w, 70)
    if math.abs(f:GetWidth() - w) > 0.5 or math.abs(f:GetHeight() - h) > 0.5 then
        anchorTopLeft(f)
        f:SetSize(w, h)
    end
    f.empty:SetShown(empty)
    local x0 = math.floor((w - contentWidth) / 2) -- centre the icons in a box wider than them

    for _, b in ipairs(self.icons) do b.placed = false end
    local font = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    for k, b in ipairs(order) do
        b.placed = true
        b:SetSize(size, size)
        b:ClearAllPoints()
        if db.sideBySide then
            b:SetPoint("TOPLEFT", f, "TOPLEFT", x0 + (k - 1) * (size + GAP), -HEADER)
        else
            b:SetPoint("TOPLEFT", f, "TOPLEFT", x0, -HEADER - (k - 1) * (size + GAP))
        end
        if b.fontSize ~= size then
            b.fontSize = size
            b.timer:SetFont(font, math.max(8, math.floor(size * 0.42)), "OUTLINE")
        end
        b.icon:SetTexture(b.entry.icon or spellIcon(b.entry.id))

        local st = b.state
        if st.secret then
            -- The client hides the numbers: let the game's own swipe and countdown show them.
            setHideNumbers(b, false)
            setCooldown(b, st.start, st.duration)
            b.timer:SetText("")
            b.icon:SetDesaturated(false)
        else
            setHideNumbers(b, true)
            setCooldown(b, st.start, st.duration)
            local cooling = st.remaining > 0
            b.icon:SetDesaturated(cooling or st.waiting)
            if cooling then
                b.timer:SetText(formatTime(st.remaining))
                if st.remaining < 5 then
                    b.timer:SetTextColor(1, 0.82, 0)
                else
                    b.timer:SetTextColor(1, 1, 1)
                end
            else
                b.timer:SetText("")
            end
        end
        b:Show()
    end
    for _, b in ipairs(self.icons) do
        if not b.placed then b:Hide() end
    end
    f:Show()
end

-- Lifecycle and slash ----------------------------------------------------------

function C:OnLoad()
    self.charDB.horizontal = nil -- replaced by sideBySide, which defaults to on
end

function C:OnEnable()
    self:ScanSpellbook()
    self:CreateWindow()
    self:Update()

    local events = CreateFrame("Frame")
    events:RegisterEvent("SPELLS_CHANGED")
    events:RegisterEvent("LEARNED_SPELL_IN_TAB")
    events:SetScript("OnEvent", QoL:Guard("Cooldowns", function()
        self:ScanSpellbook()
        self:Changed()
    end))
end

function C:OpenTab()
    local todo = ns.Todo
    if todo and todo.frame then
        todo:SetShown(true)
        if todo.charDB.collapsed then todo:SetCollapsed(false) end
        todo:SetActiveTab("ref:cds")
    end
end

function C:OnSlash(args)
    local cmd, rest = args:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    if cmd == "" or cmd == "tab" then
        self:OpenTab()
    elseif cmd == "show" or cmd == "hide" then
        self:SetOption("shown", cmd == "show")
    elseif cmd == "lock" or cmd == "unlock" then
        self:SetOption("locked", cmd == "lock")
        QoL:Print(cmd == "lock" and "cooldown window locked." or "cooldown window unlocked.")
    elseif cmd == "reset" then
        self:ResetPosition()
    elseif cmd == "add" or cmd == "remove" then
        if rest == "" then return QoL:Print(("usage: /qol cds %s <spell name>"):format(cmd)) end
        local entry = self:FindSpell(rest)
        if not entry then return QoL:Print(("'%s' isn't in your spellbook."):format(rest)) end
        self:SetTracked(entry.name, cmd == "add")
        QoL:Print(("%s %s."):format(cmd == "add" and "tracking" or "stopped tracking", entry.name))
    elseif cmd == "list" then
        if #self.charDB.spells == 0 then return QoL:Print("no spells tracked. Type /qol cds to pick some.") end
        QoL:Print("tracking: " .. table.concat(self.charDB.spells, ", "))
    else
        QoL:Print("unknown command. Type /qol for help.")
    end
end
