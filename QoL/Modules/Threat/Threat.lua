-- Threat: show your threat % on the target's unit frame.
--
-- Where the number comes from, first one that works:
--   1. the client's own UnitDetailedThreatSituation (Classic Era and later have it)
--   2. LibThreatClassic2, if another addon (e.g. Details!, ThreatClassic2) ships it
-- If neither is there, nothing is shown and /qol threat debug says why.
local _, ns = ...
local QoL = ns.QoL

local UPDATE_INTERVAL = 0.2 -- seconds; backup in case threat events don't fire

local T = QoL:RegisterModule("threat", {
    name = "Threat",
    description = "show your threat % on the target frame",
    defaults = {
        enabled = true,
        raw = false, -- false: % of what it takes to pull aggro; true: % of the tank's threat
        point = nil, -- { x, y } offset from the target frame's centre, once you move it
    },
    slashHelp = {
        "/qol threat - turn the threat % on or off",
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

function T:Update()
    local f = self.frame
    if not f then return end
    if self.unlocked then
        f.text:SetText("Threat 100%")
        f.text:SetTextColor(1, 1, 1)
        f:Show()
        return
    end
    if not self.db.enabled or not UnitExists("target") or UnitIsDeadOrGhost("target")
        or not UnitCanAttack("player", "target") then
        f:Hide()
        return
    end
    local tanking, status, scaled, raw = self:GetThreat("target")
    local pct = self.db.raw and raw or scaled
    if tanking and not self.db.raw then pct = 100 end
    if not pct then
        f:Hide()
        return
    end
    f.text:SetText(("Threat %d%%"):format(math.floor(pct + 0.5)))
    f.text:SetTextColor(statusColor(status))
    f:Show()
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
}

function T:OnEnable()
    self:CreateFrame()
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
        if T.db.enabled and UnitExists("target") then T:Update() end
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
            self.db.enabled = not self.db.enabled
        else
            self.db.enabled = cmd == "on"
        end
        QoL:Print("threat % is " .. (self.db.enabled and "on" or "off") .. ".")
        if self.db.enabled and not self:GetSource() then
            QoL:Print("this client doesn't report threat. Type /qol threat debug for details.")
        end
        self:Update()
    elseif cmd == "unlock" then
        self:SetUnlocked(true)
    elseif cmd == "lock" then
        self:SetUnlocked(false)
    elseif cmd == "reset" then
        self.db.point = nil
        self:ApplyPosition()
        QoL:Print("threat number moved back above the target frame.")
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
