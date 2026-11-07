-- Threat: show your threat % on the target's unit frame.
--
-- Where the number comes from, first one that works:
--   1. the client's own UnitDetailedThreatSituation (Classic Era and later have it)
--   2. LibThreatClassic2, if another addon (e.g. Details!, ThreatClassic2) ships it
-- If neither is there, nothing is shown and /qol threat debug says why.
local _, ns = ...
local QoL = ns.QoL

-- A plain face in front of the number, tinted with the threat colour:
-- smiling while threat is low, a flat mouth when it's close (yellow, orange),
-- and an open mouth once the mob is on you (red).
local MEDIA = "Interface\\AddOns\\QoL\\Media\\"
local FACES = {
    [0] = MEDIA .. "ThreatFace",
    [1] = MEDIA .. "ThreatFaceFlat",
    [2] = MEDIA .. "ThreatFaceFlat",
    [3] = MEDIA .. "ThreatFaceOpen",
}

local function faceIcon(status, r, g, b)
    return ("|T%s:14:14:0:0:64:64:0:64:0:64:%d:%d:%d|t"):format(FACES[status or 0] or FACES[0],
        math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local UPDATE_INTERVAL = 0.2 -- seconds; backup in case threat events don't fire

local T = QoL:RegisterModule("threat", {
    name = "Threat",
    description = "show your threat % on the target frame",
    defaults = {
        enabled = true, -- on the target frame
        nameplate = true, -- above the target's nameplate
        raw = false, -- false: % of what it takes to pull aggro; true: % of the tank's threat
        point = nil, -- { x, y } offset from the target frame's centre, once you move it
    },
    slashHelp = {
        "/qol threat - turn the threat % on the target frame on or off",
        "/qol threat plate on | off - threat % above the target's nameplate",
        "/qol threat unlock | lock - drag the number where you want it",
        "/qol threat reset - put the number back above the target frame",
        "/qol threat raw on | off - show % of the tank's threat instead of % to pull aggro",
        "/qol threat debug - print what the game reports about threat",
    },
})
ns.Threat = T

local function getThreatLib()
    local LibStub = _G.LibStub
    return LibStub and LibStub("LibThreatClassic2", true)
end

-- Returns isTanking, status, scaledPct, rawPct, threatValue, source.
function T:GetThreat(unit)
    if _G.UnitDetailedThreatSituation then
        local ok, tanking, status, scaled, raw, value = pcall(_G.UnitDetailedThreatSituation, "player", unit)
        if ok and (status or scaled) then
            return tanking, status, scaled, raw, value, "client"
        end
    end
    local lib = getThreatLib()
    if lib and lib.UnitDetailedThreatSituation then
        local ok, tanking, status, scaled, raw, value = pcall(lib.UnitDetailedThreatSituation, lib, "player", unit)
        if ok and (status or scaled) then
            return tanking, status, scaled, raw, value, "LibThreatClassic2"
        end
    end
end

function T:GetSource()
    if _G.UnitDetailedThreatSituation then return "client" end
    local lib = getThreatLib()
    if lib and lib.UnitDetailedThreatSituation then return "LibThreatClassic2" end
end

-- Threat status 0-3: low, high (about to pull), pulled but not top, tanking.
local STATUS_COLORS = {
    [0] = { 0.69, 0.69, 0.69 },
    [1] = { 1, 1, 0.47 },
    [2] = { 1, 0.6, 0 },
    [3] = { 1, 0, 0 },
}

local function statusColor(status)
    if status and _G.GetThreatStatusColor then
        local ok, r, g, b = pcall(_G.GetThreatStatusColor, status)
        if ok and r then return r, g, b end
    end
    local c = STATUS_COLORS[status or 0] or STATUS_COLORS[0]
    return c[1], c[2], c[3]
end

local function anchorFrame()
    return _G.TargetFrame or UIParent
end

function T:ApplyPosition()
    local f, anchor = self.frame, anchorFrame()
    f:ClearAllPoints()
    if self.db.point then
        f:SetPoint("CENTER", anchor, "CENTER", self.db.point[1], self.db.point[2])
    elseif anchor == UIParent then
        f:SetPoint("TOP", UIParent, "TOP", 0, -120)
    else
        -- Just above the target's name, like the newer clients' numeric threat.
        f:SetPoint("BOTTOM", anchor, "TOP", -24, -22)
    end
end

function T:CreateFrame()
    local anchor = anchorFrame()
    local f = CreateFrame("Frame", "QoLThreatFrame", anchor)
    f:SetSize(64, 18)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.6)
    f.bg = bg

    local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER")
    f.text = text

    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(frame)
        if not T.unlocked then return end
        frame:StartMoving()
    end)
    f:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        local a = anchorFrame()
        local fx, fy = frame:GetCenter()
        local ax, ay = a:GetCenter()
        -- Both centres are in this frame's scale when it is parented to the anchor.
        T.db.point = { math.floor(fx - ax + 0.5), math.floor(fy - ay + 0.5) }
        T:ApplyPosition()
    end)

    f:Hide()
    self.frame = f
    self:ApplyPosition()
end

local function getTargetPlate()
    local np = _G.C_NamePlate
    if not (np and np.GetNamePlateForUnit) then return end
    local ok, plate = pcall(np.GetNamePlateForUnit, "target")
    if ok then return plate end
end

function T:CreatePlateFrame()
    local f = CreateFrame("Frame", "QoLThreatPlateFrame", UIParent)
    f:SetSize(64, 16)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.5)
    local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER")
    f.text = text
    f:Hide()
    self.plateFrame = f
end

-- Moves the nameplate number onto the target's current nameplate, if it has one.
function T:AttachToPlate()
    local f = self.plateFrame
    local plate = getTargetPlate()
    if not plate then
        f:Hide()
        return false
    end
    if f.plate ~= plate then
        f:SetParent(plate)
        f:ClearAllPoints()
        -- Sit right on the name; the plate frame itself reaches well above it.
        -- Other nameplate addons (e.g. Plater) may not have these fields.
        local uf = plate.UnitFrame
        local name = uf and (uf.name or uf.Name)
        local bar = uf and (uf.healthBar or uf.HealthBar)
        if name and name.IsShown and name:IsShown() then
            f:SetPoint("BOTTOM", name, "TOP", 0, 0)
        elseif bar then
            f:SetPoint("BOTTOM", bar, "TOP", 0, 14)
        else
            f:SetPoint("CENTER", plate, "CENTER", 0, 20)
        end
        f:SetFrameLevel(plate:GetFrameLevel() + 10)
        f.plate = plate
    end
    return true
end

-- Returns the text and colour to show, or nil when there is nothing to show.
function T:GetDisplay()
    if not UnitExists("target") or UnitIsDeadOrGhost("target") or not UnitCanAttack("player", "target") then
        return
    end
    local tanking, status, scaled, raw = self:GetThreat("target")
    local pct = self.db.raw and raw or scaled
    if tanking and not self.db.raw then pct = 100 end
    if not pct then return end
    local r, g, b = statusColor(status)
    return ("%s %d%%"):format(faceIcon(status, r, g, b), math.floor(pct + 0.5)), r, g, b
end

function T:Update()
    local f, pf = self.frame, self.plateFrame
    if not f then return end
    local text, r, g, b
    if self.db.enabled or self.db.nameplate then
        text, r, g, b = self:GetDisplay()
    end

    if self.unlocked then
        f.text:SetText(faceIcon(3, 1, 0, 0) .. " 100%")
        f.text:SetTextColor(1, 1, 1)
        f:Show()
    elseif self.db.enabled and text then
        f.text:SetText(text)
        f.text:SetTextColor(r, g, b)
        f:Show()
    else
        f:Hide()
    end

    if self.db.nameplate and text and self:AttachToPlate() then
        pf.text:SetText(text)
        pf.text:SetTextColor(r, g, b)
        pf:Show()
    else
        pf:Hide()
    end
end

function T:SetPlateEnabled(on)
    self.db.nameplate = on
    if on and not getTargetPlate() and not (_G.C_NamePlate and _G.C_NamePlate.GetNamePlateForUnit) then
        QoL:Print("this client can't link nameplates to your target. Type /qol threat debug for details.")
    end
    self:Update()
    if ns.Todo and ns.Todo.RefreshHelpers then ns.Todo:RefreshHelpers() end
end

function T:SetEnabled(on)
    self.db.enabled = on
    if on and not self:GetSource() then
        QoL:Print("this client doesn't report threat. Type /qol threat debug for details.")
    end
    self:Update()
    if ns.Todo and ns.Todo.RefreshHelpers then ns.Todo:RefreshHelpers() end
end

function T:SetUnlocked(unlocked)
    self.unlocked = unlocked
    self.frame:EnableMouse(unlocked)
    if unlocked then
        QoL:Print("drag the threat number where you want it, then type /qol threat lock.")
    end
    self:Update()
end

local EVENTS = {
    "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE",
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
}

function T:OnEnable()
    self:CreateFrame()
    self:CreatePlateFrame()
    self.events = {}
    local driver = CreateFrame("Frame")
    for _, event in ipairs(EVENTS) do
        -- Unknown events error on some clients; skip them and rely on the timer.
        self.events[event] = pcall(driver.RegisterEvent, driver, event)
    end
    driver:SetScript("OnEvent", function() T:Update() end)
    local elapsed = 0
    driver:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < UPDATE_INTERVAL then return end
        elapsed = 0
        if (T.db.enabled or T.db.nameplate) and UnitExists("target") then T:Update() end
    end)

    -- LibThreatClassic2 only tracks threat while someone listens to it.
    local lib = getThreatLib()
    if lib and lib.RegisterCallback then
        pcall(lib.RegisterCallback, T, "ThreatUpdated", function() T:Update() end)
    end
end

function T:PrintDebug()
    local p = function(...) print("  " .. string.format(...)) end
    QoL:Print("threat debug")
    p("client build %s, interface %s", tostring((select(2, GetBuildInfo()))), tostring((select(4, GetBuildInfo()))))
    p("UnitDetailedThreatSituation: %s, UnitThreatSituation: %s, GetThreatStatusColor: %s",
        tostring(_G.UnitDetailedThreatSituation ~= nil), tostring(_G.UnitThreatSituation ~= nil),
        tostring(_G.GetThreatStatusColor ~= nil))
    local lib = getThreatLib()
    p("LibStub: %s, LibThreatClassic2: %s", tostring(_G.LibStub ~= nil), tostring(lib ~= nil))
    p("using: %s", tostring(self:GetSource() or "nothing - no threat API found"))
    for _, event in ipairs(EVENTS) do
        if self.events and self.events[event] == false then p("event %s: not available", event) end
    end
    p("TargetFrame: %s, enabled: %s, raw: %s, moved: %s", tostring(_G.TargetFrame ~= nil),
        tostring(self.db.enabled), tostring(self.db.raw), tostring(self.db.point ~= nil))
    p("nameplate: %s, C_NamePlate.GetNamePlateForUnit: %s, target has a nameplate: %s",
        tostring(self.db.nameplate), tostring(_G.C_NamePlate ~= nil and _G.C_NamePlate.GetNamePlateForUnit ~= nil),
        tostring(getTargetPlate() ~= nil))
    if not UnitExists("target") then
        p("no target - target an enemy you are fighting and run this again")
        return
    end
    p("target: %s, can attack: %s, in combat: %s", tostring(UnitName("target")),
        tostring(UnitCanAttack("player", "target")), tostring(UnitAffectingCombat("target")))
    if _G.UnitDetailedThreatSituation then
        p("client detailed: %s", strjoin(", ", tostringall(pcall(_G.UnitDetailedThreatSituation, "player", "target"))))
    end
    if _G.UnitThreatSituation then
        p("client situation: %s", strjoin(", ", tostringall(pcall(_G.UnitThreatSituation, "player", "target"))))
    end
    if lib and lib.UnitDetailedThreatSituation then
        p("lib detailed: %s", strjoin(", ", tostringall(pcall(lib.UnitDetailedThreatSituation, lib, "player", "target"))))
    end
end

function T:OnSlash(args)
    local cmd = (args or ""):lower()
    if cmd == "" or cmd == "on" or cmd == "off" then
        if cmd == "" then
            self:SetEnabled(not self.db.enabled)
        else
            self:SetEnabled(cmd == "on")
        end
        QoL:Print("threat % is " .. (self.db.enabled and "on" or "off") .. ".")
    elseif cmd == "unlock" then
        self:SetUnlocked(true)
    elseif cmd == "lock" then
        self:SetUnlocked(false)
    elseif cmd == "reset" then
        self.db.point = nil
        self:ApplyPosition()
        QoL:Print("threat number moved back above the target frame.")
    elseif cmd:match("^plate") then
        self:SetPlateEnabled(not cmd:match("off$"))
        QoL:Print("threat % above the nameplate is " .. (self.db.nameplate and "on" or "off") .. ".")
    elseif cmd:match("^raw") then
        self.db.raw = not cmd:match("off$")
        QoL:Print(self.db.raw and "showing % of the tank's threat." or "showing % to pull aggro (100% = you pull).")
        self:Update()
    elseif cmd == "debug" then
        self:PrintDebug()
    else
        QoL:Print("unknown command. Type /qol for help.")
    end
end
