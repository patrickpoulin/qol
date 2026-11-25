-- Raid frame HoTs: big countdowns for your own heal-over-time spells (Renew,
-- Rejuvenation, Regrowth), just outside the right edge of each of Blizzard's
-- raid frames (and raid-style party frames).
--
-- Combat rules: Blizzard's raid frames are protected. QoL never touches them.
-- It hangs one plain frame (a "holder") off the right edge of each one, and
-- only moves or resizes that holder out of combat. In combat it only changes
-- the text, colour and visibility of the holder's own text and icons, which
-- the game allows. A raid frame that first appears mid-fight gets its holder
-- when combat ends.
local _, ns = ...
local QoL = ns.QoL

local GetTime = _G.GetTime
local C_Spell, C_UnitAuras = _G.C_Spell, _G.C_UnitAuras

local TICK = 0.1          -- seconds between countdown updates
local LOW_TIME = 3        -- seconds left when the number turns yellow
local GAP = 2             -- pixels between the raid frame and the numbers
local FONT = "Fonts\\FRIZQT__.TTF"
local LOW_COLOR = { 1, 0.82, 0 }
local TEST_LENGTH = 15    -- seconds /qol hots test runs for

-- Your own HoTs, per class. Matched by name, so every rank counts. Each
-- spell keeps its own row on the frame, top to bottom in this order, so a
-- spell is always in the same place.
local HOTS = {
    PRIEST = {
        { key = "renew", id = 139, name = "Renew", color = { 1, 1, 1 } },
    },
    DRUID = {
        { key = "rejuv", id = 774, name = "Rejuvenation", color = { 0.85, 0.5, 1 } },
        { key = "regrowth", id = 8936, name = "Regrowth", color = { 0.45, 1, 0.45 } },
    },
}

-- The names Blizzard gives its raid and raid-style party frames. Nameplates
-- use the same unit frame code, so anything else is left alone.
local FRAME_PATTERNS = {
    "^CompactRaidFrame%d+$",
    "^CompactRaidGroup%d+Member%d+$",
    "^CompactPartyFrameMember%d+$",
    "^CompactPartyFramePlayer$",
}

local H = QoL:RegisterModule("hots", {
    name = "Raid frame HoTs",
    description = "big countdowns for your HoTs beside the raid frames",
    defaults = {
        enabled = true,
        size = 16,     -- text height in pixels
        icon = false,  -- spell icon in front of the number
    },
    slashHelp = {
        "/qol hots on | off - turn the big HoT countdowns on or off",
        "/qol hots size <10-30> - how big the numbers are",
        "/qol hots icon on | off - show the spell icon in front of each number",
        "/qol hots test - show sample timers on your raid frames for a few seconds",
        "/qol hots debug - print what QoL sees on each raid frame",
    },
})
ns.RaidHoTs = H

H.frames = {}   -- raid frame -> its holder
H.pending = {}  -- raid frames seen in combat, waiting for a holder

local function spellName(spell)
    local name
    if C_Spell and C_Spell.GetSpellName then
        name = C_Spell.GetSpellName(spell.id)
    elseif _G.GetSpellInfo then
        name = _G.GetSpellInfo(spell.id)
    end
    return name or spell.name
end

local function spellIcon(spell)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(spell.id) end
    if _G.GetSpellTexture then return _G.GetSpellTexture(spell.id) end
end

local function isRaidFrame(frame)
    if type(frame) ~= "table" or not frame.GetName then return false end
    if frame.IsForbidden and frame:IsForbidden() then return false end
    local name = frame:GetName()
    if not name then return false end
    for _, pattern in ipairs(FRAME_PATTERNS) do
        if name:find(pattern) then return true end
    end
    return false
end

local function frameUnit(frame)
    return frame.displayedUnit or frame.unit
end

-- One buff by index: name, expirationTime, source. Newer clients first.
local function getAura(unit, i)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local data = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL|PLAYER")
        if data then return true, data.name, data.expirationTime, data.sourceUnit end
        return false
    end
    if _G.UnitAura then
        local name, _, _, _, _, expires, source = _G.UnitAura(unit, i, "HELPFUL|PLAYER")
        if name then return true, name, expires, source end
    end
    return false
end

-- The player's tracked HoTs on a unit: { [spell key] = expirationTime }.
-- Values the game keeps secret are skipped rather than shown wrong.
function H:ScanUnit(unit, out)
    wipe(out)
    if not unit or not UnitExists(unit) then return out end
    for i = 1, 40 do
        local ok, found, name, expires, source = pcall(getAura, unit, i)
        if not ok or not found then break end
        if not (QoL.IsSecret(name) or QoL.IsSecret(expires) or QoL.IsSecret(source)) then
            local key = self.byName[name]
            local mine = source == nil or source == "player" or source == "pet" or source == "vehicle"
            if key and mine and expires and expires > 0 then
                -- Two copies can't happen for your own HoT, but keep the longest.
                if not out[key] or expires > out[key] then out[key] = expires end
            end
        end
    end
    return out
end

-- Holders -------------------------------------------------------------------

function H:CreateHolder(frame)
    local holder = CreateFrame("Frame", nil, frame)
    holder:SetSize(1, 1)
    holder.rows = {}
    holder.expires = {}
    for i, spell in ipairs(self.spells) do
        local row = {}
        row.text = holder:CreateFontString(nil, "OVERLAY")
        row.text:SetJustifyH("LEFT")
        row.icon = holder:CreateTexture(nil, "OVERLAY")
        row.icon:SetTexture(spellIcon(spell))
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.text:Hide()
        row.icon:Hide()
        holder.rows[i] = row
    end
    self.frames[frame] = holder
    self:LayoutHolder(frame, holder)
    return holder
end

-- Places a holder and its rows. Out of combat only.
function H:LayoutHolder(frame, holder)
    local size = self.db.size
    holder:ClearAllPoints()
    holder:SetPoint("TOPLEFT", frame, "TOPRIGHT", GAP, 0)
    holder:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", GAP, 0)
    holder:SetWidth(size * 3)
    holder:SetFrameStrata(frame:GetFrameStrata())
    holder:SetFrameLevel(frame:GetFrameLevel() + 10)

    -- Rows centred on the frame, each one text line tall.
    local count = #holder.rows
    local rowHeight = size + 1
    for i, row in ipairs(holder.rows) do
        local y = ((count + 1) / 2 - i) * rowHeight
        row.text:SetFont(FONT, size, "OUTLINE")
        row.icon:SetSize(size, size)
        row.icon:ClearAllPoints()
        row.icon:SetPoint("LEFT", holder, "LEFT", 0, y)
        row.text:ClearAllPoints()
        if self.db.icon then
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 2, 0)
        else
            row.text:SetPoint("LEFT", holder, "LEFT", 0, y)
        end
    end
    holder:Show()
end

function H:LayoutAll()
    if InCombatLockdown() then
        self.layoutPending = true
        return false
    end
    self.layoutPending = nil
    for frame, holder in pairs(self.frames) do
        self:LayoutHolder(frame, holder)
    end
    return true
end

-- Called for every raid frame Blizzard sets up or refreshes.
function H:Track(frame)
    if not self.spells or not isRaidFrame(frame) then return end
    local holder = self.frames[frame]
    if not holder then
        if InCombatLockdown() then
            self.pending[frame] = true
            return
        end
        holder = self:CreateHolder(frame)
    end
    self:ScanFrame(frame, holder)
end

-- Blizzard's raid frames that already exist (e.g. after /reload).
function H:FindFrames()
    local function try(name)
        local frame = _G[name]
        if frame then self:Track(frame) end
    end
    for i = 1, 80 do try("CompactRaidFrame" .. i) end
    for g = 1, 8 do
        for m = 1, 5 do try(("CompactRaidGroup%dMember%d"):format(g, m)) end
    end
    for i = 1, 5 do try("CompactPartyFrameMember" .. i) end
    try("CompactPartyFramePlayer")
end

-- Updating ------------------------------------------------------------------

function H:ScanFrame(frame, holder)
    holder.unit = frameUnit(frame)
    self:ScanUnit(holder.unit, holder.expires)
end

function H:ScanAll()
    for frame, holder in pairs(self.frames) do
        self:ScanFrame(frame, holder)
    end
end

function H:OnUnitAura(unit)
    if not self.db.enabled then return end
    for frame, holder in pairs(self.frames) do
        if frameUnit(frame) == unit then self:ScanFrame(frame, holder) end
    end
end

local function formatTime(left)
    if left >= 60 then return ("%dm"):format(math.ceil(left / 60)) end
    return ("%d"):format(math.ceil(left))
end

-- Text, colour and visibility only, so it is safe in combat.
function H:Render()
    local now = GetTime()
    local testing = self.testUntil and now < self.testUntil
    if self.testUntil and not testing then self.testUntil = nil end
    for frame, holder in pairs(self.frames) do
        local visible = self.db.enabled and frame:IsVisible()
        if visible and holder.unit ~= frameUnit(frame) then
            -- Blizzard moved a different player into this frame.
            self:ScanFrame(frame, holder)
        end
        for i, row in ipairs(holder.rows) do
            local spell = self.spells[i]
            local expires = holder.expires[spell.key]
            if testing then expires = self.testStart + TEST_LENGTH - (i - 1) * 4 end
            local left = expires and (expires - now)
            if visible and left and left > 0 then
                local c = left <= LOW_TIME and LOW_COLOR or spell.color
                row.text:SetText(formatTime(left))
                row.text:SetTextColor(c[1], c[2], c[3])
                row.text:Show()
                row.icon:SetShown(self.db.icon)
            else
                row.text:Hide()
                row.icon:Hide()
            end
        end
    end
end

function H:StartTicker()
    if self.ticker then return end
    self.ticker = C_Timer.NewTicker(TICK, QoL:Guard("Raid frame HoTs", function() H:Render() end))
end

function H:StopTicker()
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
    self:Render() -- hides every number
end

-- Setup ---------------------------------------------------------------------

function H:OnEnable()
    local _, class = UnitClass("player")
    self.spells = HOTS[class]
    if not self.spells then return end -- nothing to track for this class

    self.byName = {}
    for _, spell in ipairs(self.spells) do
        self.byName[spellName(spell)] = spell.key
        self.byName[spell.name] = spell.key
    end

    local track = QoL:Guard("Raid frame HoTs", function(frame) H:Track(frame) end)
    for _, fn in ipairs({ "CompactUnitFrame_SetUnit", "CompactUnitFrame_UpdateAll", "CompactUnitFrame_SetUpFrame" }) do
        if type(_G[fn]) == "function" then hooksecurefunc(fn, track) end
    end

    local f = CreateFrame("Frame")
    f:RegisterEvent("UNIT_AURA")
    f:RegisterEvent("GROUP_ROSTER_UPDATE")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", QoL:Guard("Raid frame HoTs", function(_, event, unit)
        if event == "UNIT_AURA" then
            H:OnUnitAura(unit)
        elseif event == "PLAYER_REGEN_ENABLED" then
            for frame in pairs(H.pending) do
                H.pending[frame] = nil
                H:Track(frame)
            end
            if H.layoutPending then H:LayoutAll() end
        else
            H:FindFrames()
            H:ScanAll()
        end
    end))
    self.events = f

    self:FindFrames()
    if self.db.enabled then self:StartTicker() end
end

function H:SetEnabled(on)
    self.db.enabled = on and true or false
    if not self.spells then return end
    if self.db.enabled then
        self:FindFrames()
        self:ScanAll()
        self:StartTicker()
    else
        self:StopTicker()
    end
end

function H:SetSize(size)
    size = math.max(10, math.min(30, math.floor(size + 0.5)))
    self.db.size = size
    if self.spells and not self:LayoutAll() then
        QoL:Print("the new size shows when combat ends.")
    end
end

function H:SetIcon(on)
    self.db.icon = on and true or false
    if self.spells and not self:LayoutAll() then
        QoL:Print("the change shows when combat ends.")
    end
end

local function countFrames()
    local n = 0
    for _ in pairs(H.frames) do n = n + 1 end
    return n
end

function H:Test()
    if not self.spells then
        return QoL:Print("your class has no HoTs QoL tracks (priests and druids do).")
    end
    self:FindFrames()
    local shown = 0
    for frame in pairs(self.frames) do
        if frame:IsVisible() then shown = shown + 1 end
    end
    if shown == 0 then
        return QoL:Print("no raid frames are showing. Join a group, or turn on "
            .. "Use Raid-Style Party Frames in the game's options.")
    end
    if not self.db.enabled then QoL:Print("the countdowns are turned off. Type /qol hots on.") end
    self.testStart = GetTime()
    self.testUntil = self.testStart + TEST_LENGTH
    QoL:Print(("showing sample timers on %d raid frames for %d seconds."):format(shown, TEST_LENGTH))
end

function H:PrintDebug()
    local _, class = UnitClass("player")
    QoL:Print(("hots: class %s, on: %s, size %d, icon: %s, in combat: %s"):format(
        tostring(class), tostring(self.db.enabled), self.db.size, tostring(self.db.icon),
        tostring(InCombatLockdown() and true or false)))
    if not self.spells then
        return print("  no HoTs tracked for this class.")
    end
    local names = {}
    for _, spell in ipairs(self.spells) do table.insert(names, spellName(spell)) end
    print(("  tracking: %s"):format(table.concat(names, ", ")))
    print(("  aura API: %s"):format(C_UnitAuras and C_UnitAuras.GetAuraDataByIndex and "C_UnitAuras"
        or (_G.UnitAura and "UnitAura") or "none"))
    local pending = 0
    for _ in pairs(self.pending) do pending = pending + 1 end
    print(("  raid frames: %d (waiting for combat to end: %d)"):format(countFrames(), pending))
    local now = GetTime()
    for frame, holder in pairs(self.frames) do
        if frame:IsVisible() then
            local unit = frameUnit(frame)
            local parts = {}
            for _, spell in ipairs(self.spells) do
                local e = holder.expires[spell.key]
                if e then table.insert(parts, ("%s %.1fs"):format(spell.key, e - now)) end
            end
            print(("  %s: %s (%s) %s"):format(frame:GetName(), tostring(unit),
                tostring(unit and UnitName(unit)), #parts > 0 and table.concat(parts, ", ") or "no HoTs"))
        end
    end
end

function H:OnSlash(args)
    local cmd, rest = (args or ""):lower():match("^(%S*)%s*(.-)$")
    if cmd == "" then
        self:SetEnabled(not self.db.enabled)
    elseif cmd == "on" or cmd == "off" then
        self:SetEnabled(cmd == "on")
    elseif cmd == "size" then
        local n = tonumber(rest)
        if not n then return QoL:Print(("HoT number size is %d. Type /qol hots size 10 to 30."):format(self.db.size)) end
        self:SetSize(n)
        return QoL:Print(("HoT number size set to %d."):format(self.db.size))
    elseif cmd == "icon" then
        if rest == "on" or rest == "off" then
            self:SetIcon(rest == "on")
        else
            self:SetIcon(not self.db.icon)
        end
        return QoL:Print("spell icons are " .. (self.db.icon and "on." or "off."))
    elseif cmd == "test" then
        return self:Test()
    elseif cmd == "debug" then
        return self:PrintDebug()
    else
        return QoL:Print("unknown command. Type /qol for help.")
    end
    QoL:Print("raid frame HoT countdowns are " .. (self.db.enabled and "on." or "off."))
end
