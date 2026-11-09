-- Pet Health: make it obvious when your pet is close to dying.
--
-- Two levels, both a % of the pet's max health:
--   warning (35% by default): a slow orange glow around the pet portrait
--   danger  (20% by default): a fast red pulse, one sound, and big text in the
--                             middle of the screen (with a Mend Pet hint for hunters)
-- An optional red glow at the screen edges joins in at danger; it's off by default.
-- Each level only clears once health is a few % above its line, so the alert
-- doesn't flicker while health hovers right around it.
--
-- Newer clients hide unit health from addons as a "secret value": it can be
-- shown but not compared or used in maths. There the addon can't know the %,
-- so it hands the game two step curves (below danger, between danger and
-- warning) and the game turns pet health into the glows' and text's alpha.
-- That mode has no sound and no hysteresis, since both need the real number.
local _, ns = ...
local QoL = ns.QoL

local NONE, WARN, DANGER, SECRET = 0, 1, 2, 3
local MARGIN = 5 -- % above a line before its alert clears
local SOUND_COOLDOWN = 5 -- seconds between danger sounds
local TEXT_TIME = 4 -- seconds the big text stays up
local TEXT_FADE = 1 -- of which the last second fades out
local MEND_PET_ID = 136 -- any rank; used to get the spell's name in this client's language

local COLORS = {
    [WARN] = { 1, 0.55, 0 },
    [DANGER] = { 1, 0.1, 0.1 },
}
local PULSE_SPEED = { [WARN] = 2.5, [DANGER] = 9, [SECRET] = 5 } -- radians per second

local P = QoL:RegisterModule("pet", {
    name = "Pet Health",
    description = "warn when your pet's health is low",
    defaults = {
        enabled = true,
        glow = true, -- around the pet portrait
        sound = true, -- once on reaching danger
        text = true, -- big text on reaching danger
        screen = false, -- red glow at the screen edges while in danger
        warn = 35,
        danger = 20,
    },
    slashHelp = {
        "/qol pet - turn the low pet health warning on or off",
        "/qol pet test - preview the warning and danger alerts",
        "/qol pet warn <%> | danger <%> - set when each alert starts",
        "/qol pet glow | sound | text | screen on | off - turn one part on or off",
        "/qol pet debug - print what QoL sees about your pet",
    },
})
ns.PetHealth = P

local function refreshHelpers()
    if ns.Todo and ns.Todo.RefreshHelpers then ns.Todo:RefreshHelpers() end
end

local function isSecret(v)
    return _G.issecretvalue ~= nil and _G.issecretvalue(v) == true
end

-- Runs fn and returns its result, or nil if it errors (e.g. on a secret value).
local function try(fn, ...)
    local ok, v = pcall(fn, ...)
    if ok then return v end
end

-- Pet health as a whole %, "secret" when the client won't let addons read
-- it, or nil when there is no living pet to warn about.
function P:GetPetPct()
    if self.testPct then return self.testPct end
    if not UnitExists("pet") then return end
    if try(function() return _G.UnitIsDead("pet") and true or false end) then return end
    if try(function() return _G.UnitOnTaxi and _G.UnitOnTaxi("player") and true or false end) then return end
    local hp, max = _G.UnitHealth("pet"), _G.UnitHealthMax("pet")
    if not isSecret(hp) and not isSecret(max) then
        local pct = try(function()
            if max and max > 0 then return math.floor(hp / max * 100 + 0.5) end
        end)
        if pct then return pct end
    end
    if _G.UnitHealthPercent then
        local v = try(_G.UnitHealthPercent, "pet")
        if type(v) == "number" and not isSecret(v) then
            -- 0 to 1 on most clients; allow for 0 to 100 too.
            return math.floor((v > 1 and v or v * 100) + 0.5)
        end
    end
    return "secret"
end

-- Step curves for the secret-health mode: 1 inside the range, 0 outside.
function P:BuildCurves()
    if self.curves then return true end
    local CU, E = _G.C_CurveUtil, _G.Enum
    if not (CU and CU.CreateCurve and _G.UnitHealthPercent) then
        self.curveError = "this client has no C_CurveUtil.CreateCurve or UnitHealthPercent"
        return false
    end
    local ok, curves = pcall(function()
        local function step(points)
            local c = CU.CreateCurve()
            if E and E.LuaCurveType and E.LuaCurveType.Step then c:SetType(E.LuaCurveType.Step) end
            for _, pt in ipairs(points) do c:AddPoint(pt[1], pt[2]) end
            return c
        end
        local w, d = self.db.warn / 100 + 0.001, self.db.danger / 100 + 0.001
        return {
            danger = step({ { 0, 1 }, { d, 0 } }),
            warnOnly = step({ { 0, 0 }, { d, 1 }, { w, 0 } }),
        }
    end)
    if ok then
        self.curves, self.curveError = curves, nil
        return true
    end
    self.curveError = tostring(curves)
    return false
end

-- The new level for `pct`, starting from the current one (keeps an alert on
-- until health is MARGIN above its line).
function P:NextLevel(pct)
    if type(pct) ~= "number" or not self.db.enabled then return NONE end
    local level, db = self.level or NONE, self.db
    if pct <= db.danger then return DANGER end
    if level == DANGER and pct <= db.danger + MARGIN then return DANGER end
    if pct <= db.warn then return WARN end
    if level >= WARN and pct <= db.warn + MARGIN then return WARN end
    return NONE
end

-- Glow around the pet portrait and a wash over its health bar.
--
-- These are never anchored to the pet frame: a frame anchored to a protected
-- frame (the pet frame is one) can't be shown, hidden or moved in combat, and
-- the game blocks the addon when it tries. Instead they sit on UIParent at the
-- pet frame's screen position, which is only copied while out of combat.
function P:CreateGlow()
    local f = CreateFrame("Frame", "QoLPetHealthGlow", UIParent)
    f:SetFrameStrata("MEDIUM")
    self:AddGlowTextures(f, function(tex) tex:SetTexture("Interface\\Buttons\\UI-ActionButton-Border") end)
    f:Hide()
    self.glow = f

    local b = CreateFrame("Frame", "QoLPetHealthBarGlow", UIParent)
    b:SetFrameStrata("MEDIUM")
    self:AddGlowTextures(b, function(tex) tex:SetColorTexture(1, 1, 1, 0.6) end)
    b:Hide()
    self.barGlow = b
end

-- An orange (warning) and a red (danger) copy of the same glow, so the
-- secret-health mode can fade each one by its own curve.
function P:AddGlowTextures(f, setTexture)
    for level, key in pairs({ [WARN] = "warnTex", [DANGER] = "dangerTex" }) do
        local tex = f:CreateTexture(nil, "OVERLAY")
        setTexture(tex)
        tex:SetBlendMode("ADD")
        tex:SetAllPoints()
        tex:SetVertexColor(COLORS[level][1], COLORS[level][2], COLORS[level][3])
        f[key] = tex
    end
end

-- Copies a region's screen rectangle onto one of our UIParent frames.
local function copyRect(frame, region)
    local left, bottom, width, height = region:GetLeft(), region:GetBottom(), region:GetWidth(), region:GetHeight()
    if not (left and bottom and width and height) or width <= 0 then return false end
    local scale = region:GetEffectiveScale() / UIParent:GetEffectiveScale()
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * scale, bottom * scale)
    frame:SetSize(width * scale, height * scale)
    return true
end

-- Lines the glows up with the pet frame. Only out of combat; in combat they
-- stay where they were last put (the pet frame doesn't move on its own).
function P:PlaceGlow()
    if InCombatLockdown() then return end
    local portrait, petFrame, healthBar = _G.PetPortrait, _G.PetFrame, _G.PetFrameHealthBar
    if not (petFrame and petFrame:IsShown()) then return end
    if portrait and copyRect(self.glow, portrait) then
        -- The glow texture's ring is about half its size, so double it around the portrait.
        local w, h = self.glow:GetWidth(), self.glow:GetHeight()
        local x, y = self.glow:GetLeft(), self.glow:GetBottom()
        self.glow:ClearAllPoints()
        self.glow:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x + w / 2, y + h / 2)
        self.glow:SetSize(w * 2, h * 2)
        self.glowPlaced = true
    end
    if healthBar and copyRect(self.barGlow, healthBar) then
        self.barPlaced = true
    end
end

-- Big text just above your character.
function P:CreateText()
    local f = CreateFrame("Frame", "QoLPetHealthText", UIParent)
    f:SetSize(400, 60)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
    f:SetFrameStrata("HIGH")
    local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    text:SetPoint("TOP", f, "TOP", 0, 0)
    text:SetTextColor(1, 0.1, 0.1)
    f.text = text
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hint:SetPoint("TOP", text, "BOTTOM", 0, -4)
    hint:SetTextColor(0.5, 1, 0.5)
    f.hint = hint
    f:Hide()
    self.textFrame = f
end

-- Red glow at the screen edges.
function P:CreateScreenGlow()
    local f = CreateFrame("Frame", "QoLPetHealthScreen", UIParent)
    f:SetAllPoints(UIParent)
    f:SetFrameStrata("BACKGROUND")
    f:EnableMouse(false)
    local tex = f:CreateTexture(nil, "BACKGROUND")
    tex:SetTexture("Interface\\FullScreenTextures\\LowHealth")
    tex:SetBlendMode("ADD")
    tex:SetVertexColor(1, 0, 0)
    tex:SetAllPoints()
    f.tex = tex
    f:Hide()
    self.screenGlow = f
end

-- Spell API moved into C_Spell on newer clients; use whichever this one has.
local function spellName(id)
    local C_Spell = _G.C_Spell
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if _G.GetSpellInfo then return (_G.GetSpellInfo(id)) end
end

local function spellUsable(name)
    if _G.IsUsableSpell then return _G.IsUsableSpell(name) end
    local C_Spell = _G.C_Spell
    if C_Spell and C_Spell.IsSpellUsable then return C_Spell.IsSpellUsable(name) end
end

local function spellCooldown(name)
    if _G.GetSpellCooldown then return _G.GetSpellCooldown(name) end
    local C_Spell = _G.C_Spell
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(name)
        if info then return info.startTime, info.duration end
    end
end

-- "Mend Pet" when a hunter could cast it right now, otherwise nil.
local function mendHint()
    if select(2, _G.UnitClass("player")) ~= "HUNTER" then return end
    local name = spellName(MEND_PET_ID)
    if not name then return end
    if UnitChannelInfo and UnitChannelInfo("player") == name then return end
    if not spellUsable(name) then return end
    local start, duration = spellCooldown(name)
    -- A duration of 1.5s or less is just the global cooldown.
    if start and start > 0 and duration and duration > 1.5 then return end
    return name
end

function P:GetMendHint()
    -- Never let the hint break the rest of the alert.
    local ok, name = pcall(mendHint)
    if ok then return name end
end

function P:PlaySound()
    local now = _G.GetTime()
    if self.lastSound and now - self.lastSound < SOUND_COOLDOWN then return end
    self.lastSound = now
    local kit = _G.SOUNDKIT
    local id = (kit and kit.RAID_WARNING) or 8959
    pcall(_G.PlaySound, id, "Master")
end

function P:ShowText(pct)
    local f = self.textFrame
    f.text:SetText(("PET %d%%"):format(pct))
    f.hint:SetText(self:GetMendHint() or "")
    f.shownAt = _G.GetTime()
    f:SetAlpha(1)
    f:Show()
end

-- Shows or hides the portrait and health bar glows; warnAlpha/dangerAlpha are
-- 0 or 1, or secret values from the curves.
function P:ShowGlows(on, warnAlpha, dangerAlpha)
    self:PlaceGlow()
    local petFrame = _G.PetFrame
    on = on and self.db.glow and petFrame and petFrame:IsShown()
    for _, g in ipairs({ { self.glow, self.glowPlaced }, { self.barGlow, self.barPlaced } }) do
        if on and g[2] then
            g[1].warnTex:SetAlpha(warnAlpha)
            g[1].dangerTex:SetAlpha(dangerAlpha)
            g[1]:Show()
        else
            g[1]:Hide()
        end
    end
end

function P:HideAll()
    self:ShowGlows(false)
    self.textFrame:Hide()
    self.screenGlow:Hide()
end

-- Secret-health mode: the game fades everything by the curves.
function P:UpdateSecret()
    if not self:BuildCurves() then
        if not self.toldUnsupported then
            self.toldUnsupported = true
            QoL:Print("this client hides pet health from addons, so the pet health warning can't run. "
                .. "Type /qol pet debug for details.")
        end
        self.level = NONE
        self:HideAll()
        return
    end
    self.level = SECRET
    local warnAlpha = _G.UnitHealthPercent("pet", false, self.curves.warnOnly)
    local dangerAlpha = _G.UnitHealthPercent("pet", false, self.curves.danger)
    self:ShowGlows(true, warnAlpha, dangerAlpha)

    local f = self.textFrame
    if self.db.text then
        f.text:SetText("PET IN DANGER")
        f.text:SetAlpha(dangerAlpha)
        f.hint:SetText(self:GetMendHint() or "")
        f.hint:SetAlpha(dangerAlpha)
        f.shownAt = false
        f:SetAlpha(1)
        f:Show()
    else
        f:Hide()
    end
    if self.db.screen then
        self.screenGlow.tex:SetAlpha(dangerAlpha)
        self.screenGlow:Show()
    else
        self.screenGlow:Hide()
    end
end

-- Called when health changes, the pet changes, or a setting changes.
function P:Update()
    if not self.glow then return end
    local pct = self:GetPetPct()
    self.pct = pct
    if pct == "secret" then
        if self.db.enabled then self:UpdateSecret() else self.level = NONE; self:HideAll() end
        return
    end

    local old = self.level or NONE
    local level = self:NextLevel(pct)
    self.level = level
    -- Undo anything the secret mode set.
    self.textFrame.text:SetAlpha(1)
    self.textFrame.hint:SetAlpha(1)
    self.screenGlow.tex:SetAlpha(1)

    if level == DANGER and old ~= DANGER then
        if self.db.sound then self:PlaySound() end
        if self.db.text then self:ShowText(pct) end
    end
    if level ~= DANGER then
        self.textFrame:Hide()
    elseif self.textFrame:IsShown() then
        self.textFrame.text:SetText(("PET %d%%"):format(pct))
    end

    self:ShowGlows(level ~= NONE, level == WARN and 1 or 0, level == DANGER and 1 or 0)
    self.screenGlow:SetShown(level == DANGER and self.db.screen)
end

-- Pulses the glows and fades the text while an alert is up.
function P:Animate()
    local now = _G.GetTime()
    local level = self.level or NONE
    local wave = math.abs(math.sin(now * (PULSE_SPEED[level] or 0)))
    local alpha = level == WARN and (0.45 + 0.4 * wave) or (0.3 + 0.7 * wave)
    self.glow:SetAlpha(alpha)
    self.barGlow:SetAlpha(alpha)
    self.screenGlow:SetAlpha(0.25 + 0.5 * wave)
    local f = self.textFrame
    if f:IsShown() and f.shownAt then
        local age = now - f.shownAt
        if age >= TEXT_TIME then
            f:Hide()
        elseif age > TEXT_TIME - TEXT_FADE then
            f:SetAlpha((TEXT_TIME - age) / TEXT_FADE)
        end
    end
end

local POLL_INTERVAL = 0.2 -- seconds; backup in case health events don't fire for the pet

-- Runs Update or Animate, and on an error says so once in chat and stops,
-- instead of repeating the error several times a second.
function P:SafeCall(method)
    if self.broken then return end
    local ok, err = pcall(self[method], self)
    if not ok then
        self.broken = true
            pcall(self.HideAll, self)
        QoL:Print("|cffff5555pet health warning hit an error and turned itself off until /reload:|r " .. tostring(err))
    end
end

function P:SafeUpdate()
    self:SafeCall("Update")
end

local EVENTS = {
    "UNIT_HEALTH", "UNIT_HEALTH_FREQUENT", "UNIT_MAXHEALTH", "UNIT_PET",
    "PLAYER_ENTERING_WORLD", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "PLAYER_REGEN_ENABLED",
}

function P:OnEnable()
    self:CreateGlow()
    self:CreateText()
    self:CreateScreenGlow()
    local driver = CreateFrame("Frame")
    self.driver = driver
    for _, event in ipairs(EVENTS) do
        -- Unknown events error on some clients; skip them.
        pcall(driver.RegisterEvent, driver, event)
    end
    self.eventCount = 0
    driver:SetScript("OnEvent", function(_, event, unit)
        if (event == "UNIT_HEALTH" or event == "UNIT_HEALTH_FREQUENT" or event == "UNIT_MAXHEALTH")
            and unit ~= "pet" then
            return
        end
        if event == "UNIT_PET" and unit ~= "player" then return end
        P.eventCount = P.eventCount + 1
        P:SafeUpdate()
    end)
    -- Check pet health a few times a second as well as on events, and pulse
    -- the glows every frame while an alert is up.
    local elapsed = 0
    driver:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= POLL_INTERVAL then
            elapsed = 0
            if P.db.enabled and (P.testPct or UnitExists("pet") or (P.level or NONE) ~= NONE) then P:SafeUpdate() end
        end
        if (P.level or NONE) ~= NONE then P:SafeCall("Animate") end
    end)
    self:SafeUpdate()
end

-- Walks through warning then danger so you can see and hear each alert.
function P:Test()
    if self.testing then return end
    self.testing = true
    QoL:Print("pet health test: warning, then danger, then back to normal.")
    if not UnitExists("pet") then
        QoL:Print("summon your pet first to see the glow around its portrait.")
    end
    local steps = {
        { 0, self.db.warn }, { 3, self.db.danger }, { 8, nil },
    }
    for _, step in ipairs(steps) do
        C_Timer.After(step[1], function()
            P.testPct = step[2]
            if not step[2] then P.testing = nil end
            P:SafeUpdate()
        end)
    end
end

function P:SetOption(key, on)
    self.db[key] = on
    self:SafeUpdate()
    refreshHelpers()
end

local function roundPct(v, lo, hi)
    return math.max(lo, math.min(hi, math.floor((tonumber(v) or 0) / 5 + 0.5) * 5))
end

-- Keeps danger below warning: moving one past the other pushes the other along.
function P:SetWarn(v)
    self.db.warn = roundPct(v, 10, 95)
    self.curves = nil
    if self.db.danger >= self.db.warn then self.db.danger = self.db.warn - 5 end
    self:SafeUpdate()
    refreshHelpers()
end

function P:SetDanger(v)
    self.db.danger = roundPct(v, 5, 90)
    self.curves = nil
    if self.db.danger >= self.db.warn then self.db.warn = self.db.danger + 5 end
    self:SafeUpdate()
    refreshHelpers()
end

function P:PrintDebug()
    -- Each line on its own, so one failing line doesn't hide the rest.
    local p = function(fmt, ...)
        local n, args = select("#", ...), { ... }
        local ok, line = pcall(function() return string.format(fmt, tostringall(unpack(args, 1, n))) end)
        print("  " .. (ok and line or ("(line failed: " .. tostring(line) .. ")")))
    end
    local db = self.db
    QoL:Print("pet health debug")
    p("client %s, started: %s, stopped by an error: %s", (select(1, GetBuildInfo())),
        self.glow ~= nil and self.driver ~= nil, self.broken)
    p("on: %s, glow: %s, sound: %s, text: %s, screen: %s", db.enabled, db.glow, db.sound, db.text, db.screen)
    p("warning at %s%%, danger at %s%%", db.warn, db.danger)
    p("pet: %s (%s), health: %s / %s", UnitExists("pet"), UnitName("pet"), _G.UnitHealth("pet"), _G.UnitHealthMax("pet"))
    p("health is secret: %s, UnitHealthPercent: %s, C_CurveUtil: %s",
        isSecret(_G.UnitHealth("pet")), _G.UnitHealthPercent ~= nil, _G.C_CurveUtil ~= nil)
    p("pet %%: %s, alert level: %s (0 none, 1 warning, 2 danger, 3 secret mode)", (self:GetPetPct()), self.level)
    p("curves: %s, curve problem: %s", self.curves ~= nil, self.curveError)
    p("PetFrame shown: %s, glow placed: %s, bar placed: %s, in combat: %s",
        _G.PetFrame and _G.PetFrame:IsShown(), self.glowPlaced, self.barPlaced, InCombatLockdown())
    p("pet health events seen: %s", self.eventCount)
end

local PARTS = { glow = "glow around the pet portrait", sound = "danger sound",
    text = "danger text", screen = "red glow at the screen edges" }

function P:OnSlash(args)
    local cmd, rest = (args or ""):lower():match("^(%S*)%s*(.-)$")
    if cmd == "" or cmd == "on" or cmd == "off" then
        local on
        if cmd == "" then on = not self.db.enabled else on = cmd == "on" end
        self:SetOption("enabled", on)
        QoL:Print("low pet health warning is " .. (self.db.enabled and "on" or "off") .. ".")
    elseif cmd == "debug" then
        self:PrintDebug()
    elseif cmd == "test" then
        self:Test()
    elseif cmd == "warn" or cmd == "danger" then
        if not tonumber(rest) then
            QoL:Print(("%s is at %d%%. Type /qol pet %s <number> to change it."):format(cmd, self.db[cmd], cmd))
            return
        end
        if cmd == "warn" then self:SetWarn(rest) else self:SetDanger(rest) end
        QoL:Print(("warning at %d%%, danger at %d%%."):format(self.db.warn, self.db.danger))
    elseif PARTS[cmd] then
        local on
        if rest == "" then on = not self.db[cmd] else on = rest ~= "off" end
        self:SetOption(cmd, on)
        QoL:Print(PARTS[cmd] .. " is " .. (on and "on" or "off") .. ".")
    else
        QoL:Print("unknown command. Type /qol for help.")
    end
end
