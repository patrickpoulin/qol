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
        showAspect = true, -- hunters: small icon of the active aspect
        showGrowl = true,  -- hunters: small icon showing if the pet's Growl autocast is on
    },
    slashHelp = {
        "/qol cds - open the CDs tab to pick spells",
        "/qol cds add <spell> | remove <spell> | list",
        "/qol cds show | hide | lock | unlock | reset",
        "/qol cds debug - print what QoL reads for each tracked spell",
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
    local list, byName, byId = {}, {}, {}
    local ok, err = pcall(eachSpell, function(name, id, icon, tabName)
        if type(name) ~= "string" or name == "" then return end
        local entry = byName[name]
        if not entry then
            entry = { name = name, tab = tabName }
            byName[name] = entry
            table.insert(list, entry)
        end
        entry.id = id
        byId[id] = entry -- every rank, so a cast of any rank finds the spell
        entry.icon = icon or spellIcon(id) or entry.icon
    end)
    if not ok then QoL:Print("couldn't read the spellbook: " .. tostring(err)) end
    for _, entry in ipairs(list) do
        entry.cooldown = baseCooldown(entry.id)
    end
    self.spellbook, self.byName, self.byId = list, byName, byId
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

-- Last cooldown we could read (or guessed from a cast) for each spell name,
-- for when the game hides the numbers in combat: { start, duration }.
local known = {}

-- In combat the game can hide cooldown numbers from addons. When the player
-- casts a tracked spell, guess its cooldown from the spell's base cooldown.
function C:OnSpellCast(spellID)
    self.lastCast = { id = isSecret(spellID) and "hidden" or tostring(spellID), at = _G.GetTime() }
    if type(spellID) ~= "number" or isSecret(spellID) then return end
    local entry = self.byId and self.byId[spellID]
    if not entry or not self:IsTracked(entry.name) then return end
    local base = entry.cooldown or baseCooldown(spellID)
    if base and base > GCD then
        known[entry.name] = { _G.GetTime(), base }
    end
end

-- Fills `state` for one spell:
--   remaining  seconds left (0 when ready), or nil when the client hides it
--   waiting    the cooldown starts when an effect ends (e.g. Stealth)
--   secret     the game hid the numbers; start/duration are then only for
--              the game's own swipe and must not be compared or added
local function readState(state, entry)
    local ok, start, duration, enabled = pcall(getCooldown, entry.id)
    state.start, state.duration, state.secret = nil, nil, false
    state.remaining, state.waiting = 0, false
    if not ok then return end
    if isSecret(start) or isSecret(duration) or isSecret(enabled) then
        state.secret, state.start, state.duration, state.remaining = true, start, duration, nil
        -- Fall back to the last numbers we saw, if that cooldown is still running.
        local k = known[entry.name]
        if k then
            local left = k[1] + k[2] - _G.GetTime()
            if left > 0 then state.remaining = left else known[entry.name] = nil end
        end
        return
    end
    if enabled == false or enabled == 0 then
        state.waiting = true
        return
    end
    if start and duration and start > 0 and duration > GCD then
        state.start, state.duration = start, duration
        state.remaining = math.max(0, start + duration - _G.GetTime())
        known[entry.name] = { start, duration }
    else
        known[entry.name] = nil
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

-- Each icon is a secure button, so clicking it casts the spell. The game
-- doesn't let addons move, resize, show or hide secure buttons in combat, so
-- during a fight the icons stay where they are and only their timers change.
local function createIcon(parent)
    local b = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("useOnKeyDown", false) -- newer clients: act on the release
    b:SetAttribute("type", "spell")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function()
        if not C.charDB.locked and not InCombatLockdown() then parent:StartMoving() end
    end)
    b:SetScript("OnDragStop", function()
        parent:StopMovingOrSizing()
        C:SavePosition()
    end)
    b:SetScript("OnEnter", function(btn)
        if not btn.entry then return end
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        if not (GameTooltip.SetSpellByID and pcall(GameTooltip.SetSpellByID, GameTooltip, btn.entry.id)) then
            GameTooltip:SetText(btn.entry.name, 1, 1, 1)
        end
        GameTooltip:AddLine("Click to cast.", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
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

local function setCooldown(b, start, duration, secret)
    if secret then
        -- Hidden numbers can't be compared, so hand them straight to the game.
        b.cdStart, b.cdDuration = nil, nil
        pcall(b.cd.SetCooldown, b.cd, start, duration)
        return
    end
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

-- Move the window by a few pixels (screen pixels at the window's scale).
function C:Nudge(dx, dy)
    local f = self.frame
    anchorTopLeft(f)
    local left, top = f:GetLeft(), f:GetTop()
    if not left or not top then return end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left + dx, top + dy)
    self:SavePosition()
end

local NUDGE = { UP = { 0, 1 }, DOWN = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } }

-- While the window is unlocked and the mouse is over it, the arrow keys move
-- it 1 pixel (10 with Shift). Every other key still reaches the game. Off in
-- combat, where the game doesn't let addons hold on to keys.
function C:UpdateKeyboard()
    local f = self.frame
    local want = not self.charDB.locked and f:IsShown() and f:IsMouseOver() and not InCombatLockdown()
    if f.keyboard == want then return end
    f.keyboard = want
    if not want and not InCombatLockdown() then pcall(f.SetPropagateKeyboardInput, f, true) end
    pcall(f.EnableKeyboard, f, want)
end

function C:OnKeyDown(key)
    local step = NUDGE[key]
    if InCombatLockdown() then return end
    pcall(self.frame.SetPropagateKeyboardInput, self.frame, not step)
    if step then
        local n = IsShiftKeyDown() and 10 or 1
        self:Nudge(step[1] * n, step[2] * n)
    end
end

function C:ResetPosition()
    if InCombatLockdown() then return QoL:Print("can't move the cooldown window in combat.") end
    self.charDB.point = nil
    self.charDB.shown = true
    self:RestorePosition()
    self:Changed()
    QoL:Print("cooldown window moved back near the centre of the screen.")
end

function C:ApplyLock()
    local f, locked = self.frame, self.charDB.locked
    -- Locked: clicks between the icons go through to the game. The window
    -- holds secure buttons, so this has to wait until combat ends.
    if not InCombatLockdown() then f:EnableMouse(not locked) end
    f:SetBackdropColor(0.05, 0.05, 0.08, locked and 0 or 0.7)
    f:SetBackdropBorderColor(0.5, 0.5, 0.55, locked and 0 or 1)
    f.title:SetShown(not locked and not f.statusShown)
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
        if not self.charDB.locked and not InCombatLockdown() then frame:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        self:SavePosition()
    end)
    if not InCombatLockdown() then pcall(f.SetPropagateKeyboardInput, f, true) end
    f:SetScript("OnKeyDown", function(_, key) self:OnKeyDown(key) end)
    f:SetScript("OnEnter", function(frame)
        if self.charDB.locked then return end
        GameTooltip:SetOwner(frame, "ANCHOR_TOP")
        GameTooltip:SetText("Cooldowns")
        GameTooltip:AddLine("Drag to move, or use the arrow keys while hovering (Shift for 10 pixels). "
            .. "Drag the bottom-right corner to resize.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", GameTooltip_Hide)

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

    self:CreateStatusIcons()

    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.empty:SetJustifyH("LEFT")
    f.empty:SetText("Pick spells on the CDs tab (/qol cds).")

    self.icons = {}
    -- The timer runs on its own frame so it keeps going while the window is
    -- hidden (e.g. locked with every spell ready and "hide ready" on).
    local driver = CreateFrame("Frame", nil, UIParent)
    local elapsed = 0
    driver:SetScript("OnUpdate", function(_, dt)
        if grip.sizing then self:DragResize() end
        self:UpdateKeyboard()
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

-- Draw one icon's texture, cooldown swipe and timer. Safe in combat.
local function paintIcon(b)
    b.icon:SetTexture(b.entry.icon or spellIcon(b.entry.id))
    local st = b.state
    setCooldown(b, st.start, st.duration, st.secret)
    if st.remaining == nil then
        -- Numbers hidden and nothing known: let the game's own countdown show.
        setHideNumbers(b, false)
        b.timer:SetText("")
        b.icon:SetDesaturated(false)
        return
    end
    setHideNumbers(b, true)
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

-- In combat nothing can move: refresh the timers of the icons already shown.
function C:UpdateInCombat()
    for _, b in ipairs(self.icons) do
        if b.placed and b.entry then
            readState(b.state, b.entry)
            paintIcon(b)
        end
    end
    self:PaintStatusIcons()
end

function C:Update()
    local f = self.frame
    if not f then return end
    if InCombatLockdown() then return self:UpdateInCombat() end
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
            if b.spell ~= entry.name then
                b.spell = entry.name
                b:SetAttribute("spell", entry.name)
            end
            readState(b.state, entry)
            if not (db.hideReady and b.state.remaining == 0 and not b.state.waiting) then
                table.insert(order, b)
            end
        end
    end
    table.sort(order, function(a, b)
        local ka, kb = sortKey(a.state), sortKey(b.state)
        if ka ~= kb then return ka < kb end
        return a.index < b.index
    end)

    local size = db.iconSize
    local n = #order
    local empty = n == 0
    local statusCount, statusSize = self:LayoutStatusIcons(size)
    if empty and db.locked and statusCount == 0 then
        f:Hide()
        return
    end

    -- Header: the title, or the hunter status icons, and the lock button.
    local header = statusCount > 0 and statusSize + 6 or HEADER
    local headerWidth = PAD + (statusCount > 0 and statusCount * (statusSize + GAP) or 26) + 4 + 44 + PAD

    -- Size the box around the icons.
    local slots = math.max(n, 1)
    local length = slots * size + (slots - 1) * GAP
    local w, h
    if db.sideBySide then
        w, h = PAD * 2 + length, header + size + PAD
    else
        w, h = PAD * 2 + size, header + length + PAD
    end
    local contentWidth = w - 2 * PAD
    if empty then
        if db.locked then
            w, h = math.max(w, headerWidth), header
        else
            w, h = math.max(w, 150), math.max(h, header + 36)
            f.empty:SetWidth(w - 2 * PAD - 4)
        end
    end
    w = math.max(w, headerWidth)
    if math.abs(f:GetWidth() - w) > 0.5 or math.abs(f:GetHeight() - h) > 0.5 then
        anchorTopLeft(f)
        f:SetSize(w, h)
    end
    f.empty:ClearAllPoints()
    f.empty:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 2, -header - 2)
    f.empty:SetShown(empty and not db.locked)
    local x0 = math.floor((w - contentWidth) / 2) -- centre the icons in a box wider than them

    for _, b in ipairs(self.icons) do b.placed = false end
    local font = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    for k, b in ipairs(order) do
        b.placed = true
        b:SetSize(size, size)
        b:ClearAllPoints()
        if db.sideBySide then
            b:SetPoint("TOPLEFT", f, "TOPLEFT", x0 + (k - 1) * (size + GAP), -header)
        else
            b:SetPoint("TOPLEFT", f, "TOPLEFT", x0, -header - (k - 1) * (size + GAP))
        end
        if b.fontSize ~= size then
            b.fontSize = size
            b.timer:SetFont(font, math.max(8, math.floor(size * 0.42)), "OUTLINE")
        end
        paintIcon(b)
        b:Show()
    end
    for _, b in ipairs(self.icons) do
        if not b.placed then b:Hide() end
    end
    self:PaintStatusIcons()
    f:Show()
end

-- Hunter status icons ------------------------------------------------------------

local GROWL = "Growl"

local function isHunter()
    local _, class = UnitClass("player")
    return class == "HUNTER"
end
C.IsHunter = isHunter

local function getBuff(i)
    local auras = _G.C_UnitAuras
    if auras and auras.GetAuraDataByIndex then
        local data = auras.GetAuraDataByIndex("player", i, "HELPFUL")
        if data then return data.name, data.icon end
        return
    end
    if _G.UnitBuff then
        local name, icon = _G.UnitBuff("player", i)
        return name, icon
    end
end

-- The aspect the player has on: name, icon. Returns false while the game
-- hides buffs from addons, and nil when no aspect is on.
local function activeAspect()
    for i = 1, 40 do
        local ok, name, icon = pcall(getBuff, i)
        if not ok then return false end
        if name == nil then return nil end
        if isSecret(name) then return false end
        if name:find("^Aspect of") then return name, icon end
    end
end

-- The pet's Growl: icon, autocast on. nil when there's no pet or it has no Growl.
local function growlInfo()
    local getInfo = _G.GetPetActionInfo
    if not getInfo or not UnitExists("pet") then return end
    for i = 1, _G.NUM_PET_ACTION_SLOTS or 10 do
        local r = { getInfo(i) }
        local name, icon, autoOn
        if type(r[3]) == "boolean" or r[3] == nil then
            name, icon, autoOn = r[1], r[2], r[6] -- name, texture, isToken, isActive, autoCastAllowed, autoCastEnabled
        else
            name, icon, autoOn = r[1], r[3], r[7] -- older: name, subtext, texture, ...
        end
        if not isSecret(name) and name == GROWL then
            if isSecret(autoOn) then return icon, nil end
            return icon, autoOn and true or false
        end
    end
end

local function createStatus(parent, secure)
    local b
    if secure then
        b = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate,BackdropTemplate")
        b:RegisterForClicks("AnyUp")
        b:SetAttribute("useOnKeyDown", false)
    else
        b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        b:EnableMouse(true)
    end
    b:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:Hide()
    return b
end

function C:CreateStatusIcons()
    local f = self.frame
    local aspect = createStatus(f, false)
    aspect:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:SetText(self.aspectName or "No aspect on", 1, 1, 1)
        GameTooltip:AddLine("The aspect you have on right now.", 0.5, 0.5, 0.5, true)
        GameTooltip:Show()
    end)

    local growl = createStatus(f, true)
    growl:SetAttribute("type", "macro")
    growl:SetAttribute("macrotext", "/petautocasttoggle " .. GROWL)
    growl:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        local on = self.growlOn
        GameTooltip:SetText(on == nil and "Growl" or ("Growl autocast is " .. (on and "on" or "off")), 1, 1, 1)
        GameTooltip:AddLine("Click to turn your pet's Growl autocast on or off.", 0.5, 0.5, 0.5, true)
        GameTooltip:Show()
    end)
    f.aspect, f.growl = aspect, growl
end

-- Place the status icons in the header (out of combat only). Returns how
-- many are shown and their size.
function C:LayoutStatusIcons(size)
    local f, db = self.frame, self.charDB
    local hunter = isHunter()
    local wantAspect = hunter and db.showAspect
    local wantGrowl = hunter and db.showGrowl and growlInfo() ~= nil
    local s = math.max(16, math.floor(size * 0.5))
    local count = 0
    for _, item in ipairs({ { f.aspect, wantAspect }, { f.growl, wantGrowl } }) do
        local b, want = item[1], item[2]
        if want then
            b:SetSize(s, s)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + count * (s + GAP), -3)
            count = count + 1
        end
        b:SetShown(want and true or false)
    end
    f.statusShown = count > 0
    f.title:SetShown(not db.locked and count == 0)
    return count, s
end

-- Refresh the status icons' pictures and colours. Safe in combat.
function C:PaintStatusIcons()
    local f = self.frame
    if f.aspect:IsShown() then
        local name, icon = activeAspect()
        if name ~= false then -- false: the game is hiding buffs; keep what we had
            self.aspectName, self.aspectIcon = name, icon
        end
        if self.aspectName then
            f.aspect.icon:SetTexture(self.aspectIcon)
            f.aspect.icon:SetDesaturated(false)
            f.aspect:SetBackdropBorderColor(0, 0, 0, 1)
        else
            -- No aspect on: a red question mark, so a missing aspect stands out.
            f.aspect.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            f.aspect.icon:SetDesaturated(true)
            f.aspect:SetBackdropBorderColor(1, 0.2, 0.2, 1)
        end
    end
    if f.growl:IsShown() then
        local icon, on = growlInfo()
        if icon then
            self.growlOn = on
            f.growl.icon:SetTexture(icon)
            f.growl.icon:SetDesaturated(on == false)
            f.growl.icon:SetAlpha(on == false and 0.6 or 1)
            if on then
                f.growl:SetBackdropBorderColor(0.2, 1, 0.2, 1)
            elseif on == false then
                f.growl:SetBackdropBorderColor(1, 0.2, 0.2, 1)
            else
                f.growl:SetBackdropBorderColor(0, 0, 0, 1)
            end
        else
            -- Pet gone mid-fight: the button can't hide until combat ends.
            f.growl.icon:SetAlpha(0.2)
        end
    end
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
    -- Not every client has every event; registering an unknown one is an error.
    for _, event in ipairs({ "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "LEARNED_SPELL_IN_SKILL_LINE",
        "PLAYER_REGEN_ENABLED" }) do
        pcall(events.RegisterEvent, events, event)
    end
    if not (events.RegisterUnitEvent and pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_SUCCEEDED", "player")) then
        pcall(events.RegisterEvent, events, "UNIT_SPELLCAST_SUCCEEDED")
    end
    events:SetScript("OnEvent", QoL:Guard("Cooldowns", function(_, event, unit, _, spellID)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            if unit == "player" then self:OnSpellCast(spellID) end
            return
        elseif event == "PLAYER_REGEN_ENABLED" then
            self:Changed() -- catch up on anything combat held back
            return
        end
        self:ScanSpellbook()
        self:Changed()
    end))
end

-- What the window sees, to track down a timer that doesn't show.
local function show(v)
    if isSecret(v) then return "|cffff8800hidden|r" end
    if type(v) == "number" then return ("%.1f"):format(v) end
    return tostring(v)
end

function C:Debug()
    local getCVar = _G.GetCVar
    QoL:Print(("cooldowns debug: in combat %s, secret values %s, C_Spell.GetSpellCooldown %s, game countdown numbers %s"):format(
        tostring(InCombatLockdown() and true or false), tostring(_G.issecretvalue ~= nil),
        tostring(C_Spell ~= nil and C_Spell.GetSpellCooldown ~= nil),
        tostring(getCVar and getCVar("countdownForCooldowns"))))
    if self.lastCast then
        QoL:Print(("last cast seen: spell %s, %.0fs ago"):format(self.lastCast.id, _G.GetTime() - self.lastCast.at))
    else
        QoL:Print("no casts seen yet.")
    end
    if #self.charDB.spells == 0 then return QoL:Print("no spells tracked.") end
    for _, name in ipairs(self.charDB.spells) do
        local entry = self.byName and self.byName[name]
        if not entry then
            QoL:Print(("  %s: not in the spellbook"):format(name))
        else
            local ok, start, duration, enabled = pcall(getCooldown, entry.id)
            local state = {}
            readState(state, entry)
            local k = known[name]
            QoL:Print(("  %s (%d): read %s, start %s, duration %s, enabled %s, left %s, saved %s"):format(
                name, entry.id, tostring(ok), show(start), show(duration), show(enabled),
                show(state.remaining), k and ("%.0fs"):format(k[2]) or "none"))
        end
    end
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
    elseif cmd == "debug" then
        self:Debug()
    elseif cmd == "list" then
        if #self.charDB.spells == 0 then return QoL:Print("no spells tracked. Type /qol cds to pick some.") end
        QoL:Print("tracking: " .. table.concat(self.charDB.spells, ", "))
    else
        QoL:Print("unknown command. Type /qol for help.")
    end
end
