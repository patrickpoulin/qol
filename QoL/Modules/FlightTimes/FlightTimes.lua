-- Flight times ("/qol flighttimes"): learns how long each flight takes by
-- timing your own flights, shows that time on the flight master's map when you
-- hover a destination, and shows a small countdown bar while you fly.
--
-- Works like InFlight and FlightMap: the time of a route is measured from
-- take-off to landing and saved per faction, start and destination (routes
-- can differ by faction even between the same two towns). The latest flight on
-- a route replaces the old time. A route you haven't flown yet says so; QoL
-- ships no preset times, because Forever's routes aren't known to match
-- Classic's. A /reload mid-flight keeps the timer going; a flight cut short by
-- logging out isn't saved.
local _, ns = ...
local QoL = ns.QoL

local GetTime = _G.GetTime

local START_TIMEOUT = 10 -- seconds to wait for take-off after picking a destination
local MIN_FLIGHT = 5      -- shorter "flights" aren't saved
local MAX_RESUME = 3600   -- a saved flight older than this isn't resumed after a reload
local POLL = 0.1
local BAR_WIDTH, BAR_HEIGHT = 220, 18

local M = QoL:RegisterModule("flighttimes", {
    name = "Flight times",
    description = "learn how long flights take, show it on the flight map, and count down while flying",
    defaults = {
        enabled = true,
        times = {}, -- [faction][from][to] = seconds
    },
    charDefaults = {
        point = nil,  -- { left, top } of the countdown bar
        flight = nil, -- the flight in progress, so a /reload can pick it up
    },
    slashHelp = {
        "/qol flighttimes - turn flight times on or off (or on / off)",
        "/qol flighttimes list - print every flight time QoL knows",
        "/qol flighttimes test | reset - preview the countdown bar, or move it back",
        "/qol flighttimes clear - forget every learned flight time",
    },
})
ns.FlightTimes = M

M.nodeNames = {} -- [taxi node index] = name, while the flight map is open
local tooltipHasLine = false -- the flight time is already on the tooltip that's showing

-- Helpers -----------------------------------------------------------------

local function faction()
    return (_G.UnitFactionGroup and _G.UnitFactionGroup("player")) or "Neutral"
end

local function onTaxi()
    return _G.UnitOnTaxi and _G.UnitOnTaxi("player") and true or false
end

-- "Crossroads, The Barrens" -> "Crossroads"
local function shortName(name)
    return name and (name:match("^([^,]+)") or name) or "?"
end

function M.FormatTime(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    if seconds >= 3600 then
        return ("%d:%02d:%02d"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60)
    end
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

function M:GetTime(fromName, toName, fac)
    local byFaction = self.db.times[fac or faction()]
    local byFrom = byFaction and byFaction[fromName]
    return byFrom and byFrom[toName]
end

function M:SaveTime(fromName, toName, fac, seconds)
    local times = self.db.times
    times[fac] = times[fac] or {}
    times[fac][fromName] = times[fac][fromName] or {}
    times[fac][fromName][toName] = math.floor(seconds + 0.5)
end

-- Flight map ----------------------------------------------------------------

-- Remember every node's name while the map is open: by the time a flight
-- starts the map has closed and the names may be gone.
function M:ReadTaxiNodes()
    wipe(self.nodeNames)
    self.currentNode = nil
    local count = _G.NumTaxiNodes and _G.NumTaxiNodes() or 0
    for i = 1, count do
        local name = _G.TaxiNodeName(i)
        self.nodeNames[i] = name
        if _G.TaxiNodeGetType and _G.TaxiNodeGetType(i) == "CURRENT" then
            self.currentNode = name
        end
    end
end

-- Adds the flight time to the tooltip of taxi node `index`, once per tooltip.
function M:AddTooltipLine(index)
    if not (self.db.enabled and index) then return end
    if tooltipHasLine then return end
    if _G.TaxiNodeGetType and _G.TaxiNodeGetType(index) ~= "REACHABLE" then return end
    local from = self.currentNode
    local to = self.nodeNames[index] or (_G.TaxiNodeName and _G.TaxiNodeName(index))
    if not (from and to) then return end
    tooltipHasLine = true
    local t = self:GetTime(from, to)
    if t then
        GameTooltip:AddLine("Flight time: " .. M.FormatTime(t), 0.6, 0.9, 1)
    else
        GameTooltip:AddLine("Flight time: not timed yet", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local function onTaxiButtonEnter(button)
    if GameTooltip:GetOwner() ~= button then return end
    M:AddTooltipLine(button:GetID())
end

-- Classic flight map: TaxiButton1..N, made the first time they're needed.
function M:HookTaxiButtons()
    for i = 1, _G.NUM_TAXI_BUTTONS or 64 do
        local b = _G["TaxiButton" .. i]
        if b and not b.qolFlightTimes then
            b.qolFlightTimes = true
            b:HookScript("OnEnter", QoL:Guard("Flight time tooltip", onTaxiButtonEnter))
        end
    end
end

-- Newer clients' flight map (Blizzard_FlightMap) uses map pins instead.
function M:HookFlightMapPins()
    local mixin = _G.FlightMap_FlightPointPinMixin
    if self.pinsHooked or not mixin or not mixin.OnMouseEnter then return end
    self.pinsHooked = true
    hooksecurefunc(mixin, "OnMouseEnter", QoL:Guard("Flight time tooltip", function(pin)
        local data = pin.taxiNodeData
        if data and data.slotIndex then M:AddTooltipLine(data.slotIndex) end
    end))
end

-- Timing ------------------------------------------------------------------

-- Picked a destination: wait for the take-off.
function M:OnTakeTaxiNode(index)
    local to = self.nodeNames[index] or (_G.TaxiNodeName and _G.TaxiNodeName(index))
    if not (self.currentNode and to) then return end
    self.pending = { from = self.currentNode, to = to, faction = faction(), at = GetTime() }
    self.driver:Show()
end

function M:StartFlight(info, startedAt)
    local now = time()
    startedAt = startedAt or now
    self.flight = {
        from = info.from, to = info.to, faction = info.faction,
        startedAt = startedAt,
        clock = GetTime() - (now - startedAt),
    }
    self.charDB.flight = { from = info.from, to = info.to, faction = info.faction, startedAt = startedAt }
    self.flight.estimate = self:GetTime(info.from, info.to, info.faction)
    self:UpdateBar()
end

function M:EndFlight()
    local f = self.flight
    self.flight = nil
    self.charDB.flight = nil
    if f and not f.test then
        local took = GetTime() - f.clock
        if took >= MIN_FLIGHT then
            local old = f.estimate
            self:SaveTime(f.from, f.to, f.faction, took)
            if self.db.enabled and not old then
                QoL:Print(("flight from %s to %s took %s. Saved for next time."):format(
                    shortName(f.from), shortName(f.to), M.FormatTime(took)))
            end
        end
    end
    self:UpdateBar()
end

function M:Poll()
    if self.pending and not self.flight then
        if onTaxi() then
            local p = self.pending
            self.pending = nil
            self:StartFlight(p)
        elseif GetTime() - self.pending.at > START_TIMEOUT then
            self.pending = nil
        end
    elseif self.flight then
        if self.flight.test then
            if GetTime() - self.flight.clock >= self.flight.estimate then self:EndFlight() end
        elseif not onTaxi() then
            self:EndFlight()
        end
    end
    if self.flight then self:UpdateBar() end
    if not (self.pending or self.flight) then self.driver:Hide() end
end

-- After a /reload in the air, pick the saved flight back up.
function M:ResumeFlight()
    local saved = self.charDB.flight
    if not saved then return end
    if onTaxi() and saved.startedAt and time() - saved.startedAt < MAX_RESUME then
        self:StartFlight(saved, saved.startedAt)
        self.driver:Show()
    else
        self.charDB.flight = nil
    end
end

-- Countdown bar -----------------------------------------------------------

local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

function M:SavePosition()
    local f = self.bar
    local left, top = f:GetLeft(), f:GetTop()
    if not left or not top then return end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    self.charDB.point = { left, top }
end

function M:RestorePosition()
    local f, p = self.bar, self.charDB.point
    f:ClearAllPoints()
    if p and p[1] and p[2] then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p[1], p[2])
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end
end

function M:CreateBar()
    local f = CreateFrame("Frame", "QoLFlightTimerBar", UIParent, "BackdropTemplate")
    f:SetSize(BAR_WIDTH + 10, BAR_HEIGHT + 10)
    f:SetFrameStrata("MEDIUM")
    if f.SetBackdrop then
        f:SetBackdrop(BACKDROP)
        f:SetBackdropColor(0.05, 0.05, 0.08, 0.8)
        f:SetBackdropBorderColor(0.5, 0.5, 0.55, 1)
    end
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(frame) frame:StartMoving() end)
    f:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        M:SavePosition()
    end)
    f:SetScript("OnEnter", function(frame)
        local fl = M.flight
        if not fl then return end
        GameTooltip:SetOwner(frame, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Flight", 1, 1, 1)
        GameTooltip:AddLine(fl.from .. " to " .. fl.to, 1, 0.82, 0, true)
        if fl.estimate then
            GameTooltip:AddLine("Usually takes " .. M.FormatTime(fl.estimate) .. ".", 0.8, 0.8, 0.8, true)
        else
            GameTooltip:AddLine("First time on this route: QoL is timing it for next time.", 0.8, 0.8, 0.8, true)
        end
        GameTooltip:AddLine("Drag to move. /qol flighttimes reset puts it back.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", GameTooltip_Hide)

    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -5)
    bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -5, 5)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.25, 0.6, 1)
    bar:SetMinMaxValues(0, 1)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.5)

    local name = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("LEFT", bar, "LEFT", 4, 0)
    name:SetPoint("RIGHT", bar, "RIGHT", -44, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    local timeText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timeText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    timeText:SetJustifyH("RIGHT")

    f.status, f.name, f.time = bar, name, timeText
    f:Hide()
    self.bar = f
    self:RestorePosition()
end

function M:UpdateBar()
    local f = self.bar
    if not f then return end
    local fl = self.flight
    if not (fl and self.db.enabled) then
        f:Hide()
        return
    end
    local elapsed = GetTime() - fl.clock
    f.name:SetText(shortName(fl.to))
    if fl.estimate and fl.estimate > 0 then
        local left = fl.estimate - elapsed
        f.status:SetStatusBarColor(0.25, 0.6, 1)
        f.status:SetValue(math.max(0, math.min(1, left / fl.estimate)))
        if left >= 0 then
            f.time:SetText(M.FormatTime(left))
        else
            f.time:SetText("+" .. M.FormatTime(-left)) -- running late
        end
    else
        -- Unknown route: count up, so the bar still shows something.
        f.status:SetStatusBarColor(0.6, 0.6, 0.6)
        f.status:SetValue(1)
        f.time:SetText(M.FormatTime(elapsed))
    end
    f:Show()
end

-- Setup and commands --------------------------------------------------------

function M:OnEnable()
    self.driver = CreateFrame("Frame")
    self.driver:Hide()
    local elapsed = 0
    self.driver:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < POLL then return end
        elapsed = 0
        M:Poll()
    end)
    QoL:GuardScripts("Flight timer", self.driver, "OnUpdate")

    self:CreateBar()

    local function reset() tooltipHasLine = false end
    for _, script in ipairs({ "OnTooltipCleared", "OnHide" }) do
        if GameTooltip:HasScript(script) then GameTooltip:HookScript(script, reset) end
    end

    if _G.TakeTaxiNode then
        hooksecurefunc("TakeTaxiNode", QoL:Guard("Flight timer", function(index) M:OnTakeTaxiNode(index) end))
    end

    local events = CreateFrame("Frame")
    events:RegisterEvent("TAXIMAP_OPENED")
    events:RegisterEvent("ADDON_LOADED")
    events:SetScript("OnEvent", QoL:Guard("Flight times", function(_, event, arg1)
        if event == "TAXIMAP_OPENED" then
            M:ReadTaxiNodes()
            M:HookTaxiButtons()
            M:HookFlightMapPins()
            -- The classic map makes its buttons as it draws; catch new ones.
            if C_Timer then C_Timer.After(0, function() M:HookTaxiButtons() end) end
        elseif event == "ADDON_LOADED" and arg1 == "Blizzard_FlightMap" then
            M:HookFlightMapPins()
        end
    end))
    self:HookTaxiButtons()
    self:HookFlightMapPins()

    self:ResumeFlight()
end

local function refreshMisc()
    if ns.Todo and ns.Todo.RefreshHelpers then ns.Todo:RefreshHelpers() end
end

function M:SetEnabled(on)
    self.db.enabled = on and true or false
    self:UpdateBar()
    refreshMisc()
end

function M:Test()
    if self.flight and not self.flight.test then
        QoL:Print("you're already flying; the bar is showing your real flight.")
        return
    end
    self.flight = {
        from = "Somewhere, Test", to = "Test Flight, Preview", faction = faction(),
        clock = GetTime(), estimate = 15, test = true,
    }
    self.driver:Show()
    self:UpdateBar()
    if not self.db.enabled then
        QoL:Print("flight times are off. Turn them on to see the bar.")
    end
end

function M:PrintList()
    local count = 0
    for fac, byFrom in pairs(self.db.times) do
        for from, byTo in pairs(byFrom) do
            for to, t in pairs(byTo) do
                if count == 0 then QoL:Print("known flight times:") end
                count = count + 1
                print(("  %s to %s: |cffffffff%s|r (%s)"):format(shortName(from), shortName(to), M.FormatTime(t), fac))
            end
        end
    end
    if count == 0 then
        QoL:Print("no flight times yet. Take a flight and QoL will time it.")
    end
end

function M:OnSlash(args)
    local cmd = (args or ""):lower()
    if cmd == "" or cmd == "on" or cmd == "off" then
        if cmd == "" then
            self:SetEnabled(not self.db.enabled)
        else
            self:SetEnabled(cmd == "on")
        end
        QoL:Print("flight times are " .. (self.db.enabled and "on" or "off") .. ".")
    elseif cmd == "list" then
        self:PrintList()
    elseif cmd == "test" then
        self:Test()
    elseif cmd == "reset" then
        self.charDB.point = nil
        if self.bar then self:RestorePosition() end
        QoL:Print("flight timer moved back to the top of the screen.")
    elseif cmd == "clear" then
        wipe(self.db.times)
        QoL:Print("forgot every flight time.")
    elseif cmd == "debug" then
        local p = function(...) print("  " .. string.format(...)) end
        QoL:Print("flight times debug")
        p("enabled: %s, on taxi: %s, faction: %s", tostring(self.db.enabled), tostring(onTaxi()), faction())
        p("TakeTaxiNode: %s, TaxiButton1: %s, FlightMap pins: %s", tostring(_G.TakeTaxiNode ~= nil),
            tostring(_G.TaxiButton1 ~= nil), tostring(self.pinsHooked == true))
        p("current node: %s", tostring(self.currentNode))
        if self.flight then
            p("flying %s to %s, %.0fs in, estimate %s", self.flight.from, self.flight.to,
                GetTime() - self.flight.clock, tostring(self.flight.estimate))
        end
    else
        QoL:Print("unknown command. Type /qol for help.")
    end
end
