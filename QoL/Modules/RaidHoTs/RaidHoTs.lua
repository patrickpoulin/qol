-- Raid frame HoTs: big countdowns for your own heal-over-time spells (Renew,
-- Rejuvenation, Regrowth), just outside the right edge of each of Blizzard's
-- raid frames (and raid-style party frames).
--
-- In combat the game hides aura names and times from addons ("secret"
-- values), so QoL can't read or work out how long a HoT has left. It doesn't
-- need to: Blizzard's raid frame already shows your HoTs as small buff icons
-- with a cooldown swipe. QoL copies each of those icons onto a big icon of
-- its own, passing the icon and timing straight through without looking at
-- them, and lets the game draw the countdown numbers on top. Secret values
-- can be handed to the game's widgets like that; they just can't be compared
-- or used in maths.
--
-- Combat rules: Blizzard's raid frames are protected. QoL never touches them
-- or calls their code. It hangs one plain frame (a "holder") off the right
-- edge of each one, and only creates, moves or resizes holders out of combat.
-- In combat it only changes textures, cooldowns and alpha. A raid frame that
-- first appears mid-fight gets its holder when combat ends.
local _, ns = ...
local QoL = ns.QoL

local C_Spell = _G.C_Spell

local GAP = 2             -- pixels between the raid frame and the icons
local ICON_GAP = 2        -- pixels between icons
local ICON_SCALE = 1.75   -- icon edge, as a multiple of the number's size
local FONT = "Fonts\\FRIZQT__.TTF"
local TEST_LENGTH = 15    -- seconds /qol hots test runs for

-- Your own HoTs, per class. When the game lets QoL read a buff's name, buffs
-- not on this list (e.g. Power Word: Fortitude) are left out. Matched by
-- name, so every rank counts.
local HOTS = {
    PRIEST = {
        { id = 139, name = "Renew" },
    },
    DRUID = {
        { id = 774, name = "Rejuvenation" },
        { id = 8936, name = "Regrowth" },
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

-- Every way Blizzard's code can start or stop a buff's cooldown swipe. Each
-- call is repeated on QoL's big icon with the same arguments.
local COOLDOWN_METHODS = {
    "SetCooldown", "SetCooldownDuration", "SetCooldownUNIX",
    "SetCooldownFromExpirationTime", "SetCooldownFromDurationObject", "Clear",
}

local H = QoL:RegisterModule("hots", {
    name = "Raid frame HoTs",
    description = "big countdowns for your HoTs beside the raid frames",
    defaults = {
        enabled = true,
        size = 16,     -- countdown number height in pixels
        icons = true,  -- false: numbers only, no icon or swipe
    },
    slashHelp = {
        "/qol hots on | off - turn the big HoT countdowns on or off",
        "/qol hots size <10-30> - how big the numbers are",
        "/qol hots icon on | off - show each number on its spell's icon",
        "/qol hots test - show sample timers on your raid frames for a few seconds",
        "/qol hots debug - print what QoL sees on each raid frame",
    },
})
ns.RaidHoTs = H

H.frames = {}   -- raid frame -> its holder
H.pending = {}  -- raid frames seen in combat, waiting for a holder
H.slotFor = {}  -- Blizzard buff icon -> QoL's big icon

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

function H:OnLoad()
    self.db.icon = nil -- 0.24.0's "icon beside the number" setting, replaced by icons
end

-- The font the game draws countdown numbers in, at our size.
function H:CountdownFont()
    if not self.font then
        self.font = _G.CreateFont("QoLRaidHoTsCountdownFont")
    end
    self.font:SetFont(FONT, self.db.size, "OUTLINE")
    return self.font
end

-- Big icons -----------------------------------------------------------------

-- Shown only while its Blizzard buff icon is, and the buff is one we track.
-- Alpha rather than Show/Hide, so it is always allowed in combat.
function H:RefreshSlot(slot)
    if slot.testing then return end
    local on = self.db.enabled and slot.buff:IsShown() and not slot.skip
    slot:SetAlpha(on and 1 or 0)
end

-- Sets the number's font on the cooldown. Newer clients take a font object;
-- older ones only have the font string the cooldown makes for the number.
function H:StyleCountdown(cd)
    if cd.SetCountdownFont then
        pcall(cd.SetCountdownFont, cd, "QoLRaidHoTsCountdownFont")
    end
    for _, region in ipairs({ cd:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "FontString" then
            region:SetFont(FONT, self.db.size, "OUTLINE")
        end
    end
    cd.qolSize = self.db.size
end

function H:CreateSlot(holder, buff)
    local slot = CreateFrame("Frame", nil, holder)
    slot.buff = buff
    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetAllPoints()
    slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local cd = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
    cd:SetAllPoints()
    if cd.SetDrawEdge then cd:SetDrawEdge(false) end
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(false) end
    if buff.cooldown and buff.cooldown.GetReverse and cd.SetReverse then
        cd:SetReverse(buff.cooldown:GetReverse())
    end
    slot.cd = cd
    slot:SetAlpha(0)

    -- Copy everything Blizzard does to its small icon onto the big one.
    local guard = function(fn) return QoL:Guard("Raid frame HoTs", fn) end
    if buff.icon then
        hooksecurefunc(buff.icon, "SetTexture", guard(function(_, texture)
            if not slot.testing then slot.icon:SetTexture(texture) end
        end))
        slot.icon:SetTexture(buff.icon:GetTexture())
    end
    if buff.cooldown then
        for _, method in ipairs(COOLDOWN_METHODS) do
            if type(buff.cooldown[method]) == "function" and type(cd[method]) == "function" then
                hooksecurefunc(buff.cooldown, method, guard(function(_, ...)
                    if slot.testing then return end
                    cd[method](cd, ...)
                    -- The number's font string can be made on first use.
                    if cd.qolSize ~= H.db.size then H:StyleCountdown(cd) end
                end))
            end
        end
    end
    buff:HookScript("OnShow", guard(function() H:RefreshSlot(slot) end))
    buff:HookScript("OnHide", guard(function() H:RefreshSlot(slot) end))

    self.slotFor[buff] = slot
    self:RefreshSlot(slot)
    return slot
end

-- Blizzard fills a buff icon with this; it tells us which buff it is, when
-- the game lets us read the name.
local function onSetBuff(buff, unitOrAura, index, filter)
    local slot = H.slotFor[buff]
    if not slot then return end
    local name
    if type(unitOrAura) == "table" then
        name = unitOrAura.name
    elseif unitOrAura and index and _G.UnitBuff then
        local ok, n = pcall(_G.UnitBuff, unitOrAura, index, filter)
        if ok then name = n end
    end
    if name == nil or QoL.IsSecret(name) then
        slot.skip = false -- can't tell, so show it
    else
        slot.skip = not H.byName[name]
    end
    H:RefreshSlot(slot)
end

-- Holders -------------------------------------------------------------------

-- Adds big icons for any of the raid frame's buff icons that don't have one.
-- Out of combat only.
function H:AddSlots(frame, holder)
    local added = false
    for i, buff in ipairs(frame.buffFrames or {}) do
        if not holder.slots[i] then
            holder.slots[i] = self:CreateSlot(holder, buff)
            added = true
        end
    end
    return added
end

function H:CreateHolder(frame)
    local holder = CreateFrame("Frame", nil, frame)
    holder:SetSize(1, 1)
    holder.slots = {}
    self.frames[frame] = holder
    self:AddSlots(frame, holder)
    self:LayoutHolder(frame, holder)
    return holder
end

-- Places a holder and its icons. Out of combat only.
function H:LayoutHolder(frame, holder)
    local size = self.db.size
    local iconSize = math.floor(size * ICON_SCALE + 0.5)
    holder:ClearAllPoints()
    holder:SetPoint("LEFT", frame, "RIGHT", GAP, 0)
    holder:SetSize(iconSize, iconSize)
    holder:SetFrameStrata(frame:GetFrameStrata())
    holder:SetFrameLevel(frame:GetFrameLevel() + 10)
    holder:Show()

    -- Side by side, in the same order as Blizzard's own buff icons.
    for i, slot in ipairs(holder.slots) do
        slot:ClearAllPoints()
        slot:SetSize(iconSize, iconSize)
        slot:SetPoint("LEFT", holder, "LEFT", (i - 1) * (iconSize + ICON_GAP), 0)
        slot.icon:SetShown(self.db.icons)
        if slot.cd.SetDrawSwipe then slot.cd:SetDrawSwipe(self.db.icons) end
        self:StyleCountdown(slot.cd)
    end
end

function H:LayoutAll()
    if InCombatLockdown() then
        self.layoutPending = true
        return false
    end
    self.layoutPending = nil
    self:CountdownFont()
    for frame, holder in pairs(self.frames) do
        self:LayoutHolder(frame, holder)
    end
    return true
end

-- Called for every raid frame Blizzard sets up or refreshes.
function H:Track(frame)
    if not self.spells or not isRaidFrame(frame) then return end
    if InCombatLockdown() then
        local holder = self.frames[frame]
        if not holder or #holder.slots < #(frame.buffFrames or {}) then self.pending[frame] = true end
        return
    end
    local holder = self.frames[frame]
    if not holder then
        self:CreateHolder(frame)
    elseif self:AddSlots(frame, holder) then
        self:LayoutHolder(frame, holder)
    end
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

function H:RefreshAll()
    for _, slot in pairs(self.slotFor) do self:RefreshSlot(slot) end
end

-- Setup ---------------------------------------------------------------------

function H:OnEnable()
    local _, class = UnitClass("player")
    self.spells = HOTS[class]
    if not self.spells then return end -- nothing to track for this class

    self.byName = {}
    for _, spell in ipairs(self.spells) do
        self.byName[spellName(spell)] = true
        self.byName[spell.name] = true
    end
    self:CountdownFont()

    local track = QoL:Guard("Raid frame HoTs", function(frame) H:Track(frame) end)
    for _, fn in ipairs({ "CompactUnitFrame_SetUnit", "CompactUnitFrame_UpdateAll",
        "CompactUnitFrame_SetUpFrame", "CompactUnitFrame_SetMaxBuffs" }) do
        if type(_G[fn]) == "function" then hooksecurefunc(fn, track) end
    end
    if type(_G.CompactUnitFrame_UtilSetBuff) == "function" then
        hooksecurefunc("CompactUnitFrame_UtilSetBuff", QoL:Guard("Raid frame HoTs", onSetBuff))
    end

    local f = CreateFrame("Frame")
    f:RegisterEvent("GROUP_ROSTER_UPDATE")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", QoL:Guard("Raid frame HoTs", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            for frame in pairs(H.pending) do
                H.pending[frame] = nil
                H:Track(frame)
            end
            if H.layoutPending then H:LayoutAll() end
        else
            H:FindFrames()
        end
    end))
    self.events = f

    self:FindFrames()
end

function H:SetEnabled(on)
    self.db.enabled = on and true or false
    if not self.spells then return end
    self:FindFrames()
    self:RefreshAll()
end

function H:SetSize(size)
    size = math.max(10, math.min(30, math.floor(size + 0.5)))
    self.db.size = size
    if self.spells and not self:LayoutAll() then
        QoL:Print("the new size shows when combat ends.")
    end
end

function H:SetIcon(on)
    self.db.icons = on and true or false
    if self.spells and not self:LayoutAll() then
        QoL:Print("the change shows when combat ends.")
    end
end

-- Sample timers on every raid frame's first icons, then back to normal.
function H:Test()
    if not self.spells then
        return QoL:Print("your class has no HoTs QoL tracks (priests and druids do).")
    end
    if InCombatLockdown() then return QoL:Print("try the test out of combat.") end
    self:FindFrames()
    local shown = 0
    local now = _G.GetTime()
    for frame, holder in pairs(self.frames) do
        if frame:IsVisible() then
            shown = shown + 1
            for i, slot in ipairs(holder.slots) do
                local spell = self.spells[i]
                if spell then
                    slot.testing = true
                    slot.icon:SetTexture(spellIcon(spell))
                    slot.cd:SetCooldown(now, TEST_LENGTH - (i - 1) * 4)
                    if slot.cd.qolSize ~= self.db.size then self:StyleCountdown(slot.cd) end
                    slot:SetAlpha(1)
                end
            end
        end
    end
    if shown == 0 then
        return QoL:Print("no raid frames are showing. Join a group, or turn on "
            .. "Use Raid-Style Party Frames in the game's options.")
    end
    if not self.db.enabled then QoL:Print("the countdowns are turned off. Type /qol hots on.") end
    QoL:Print(("showing sample timers on %d raid frames for %d seconds."):format(shown, TEST_LENGTH))
    C_Timer.After(TEST_LENGTH, QoL:Guard("Raid frame HoTs", function() H:EndTest() end))
end

function H:EndTest()
    for _, slot in pairs(self.slotFor) do
        if slot.testing then
            slot.testing = nil
            slot.cd:Clear()
            -- Back to Blizzard's icon; its timing comes back on the next buff update.
            if slot.buff.icon then slot.icon:SetTexture(slot.buff.icon:GetTexture()) end
            self:RefreshSlot(slot)
        end
    end
end

function H:PrintDebug()
    local _, class = UnitClass("player")
    QoL:Print(("hots: class %s, on: %s, size %d, icons: %s, in combat: %s, secret values: %s"):format(
        tostring(class), tostring(self.db.enabled), self.db.size, tostring(self.db.icons),
        tostring(InCombatLockdown() and true or false), tostring(_G.issecretvalue ~= nil)))
    if not self.spells then
        return print("  no HoTs tracked for this class.")
    end
    local names = {}
    for _, spell in ipairs(self.spells) do table.insert(names, spellName(spell)) end
    print(("  tracking: %s"):format(table.concat(names, ", ")))
    print(("  Blizzard hooks: UtilSetBuff %s"):format(tostring(type(_G.CompactUnitFrame_UtilSetBuff) == "function")))
    local frames, pending = 0, 0
    for _ in pairs(self.frames) do frames = frames + 1 end
    for _ in pairs(self.pending) do pending = pending + 1 end
    print(("  raid frames: %d (waiting for combat to end: %d)"):format(frames, pending))
    for frame, holder in pairs(self.frames) do
        if frame:IsVisible() then
            local parts = {}
            for i, slot in ipairs(holder.slots) do
                local state = not slot.buff:IsShown() and "empty"
                    or (slot.skip and "not a HoT") or "shown"
                table.insert(parts, ("%d %s"):format(i, state))
            end
            local unit = frame.displayedUnit or frame.unit
            print(("  %s: %s, %d buff icons: %s"):format(frame:GetName(), tostring(unit),
                #holder.slots, #parts > 0 and table.concat(parts, ", ") or "none"))
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
            self:SetIcon(not self.db.icons)
        end
        return QoL:Print("spell icons are " .. (self.db.icons and "on." or "off."))
    elseif cmd == "test" then
        return self:Test()
    elseif cmd == "debug" then
        return self:PrintDebug()
    else
        return QoL:Print("unknown command. Type /qol for help.")
    end
    QoL:Print("raid frame HoT countdowns are " .. (self.db.enabled and "on." or "off."))
end
