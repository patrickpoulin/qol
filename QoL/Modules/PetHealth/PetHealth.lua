-- Pet Health: make it obvious when your pet is close to dying.
--
-- Two levels, both a % of the pet's max health:
--   warning (35% by default): a slow orange glow around the pet portrait
--   danger  (20% by default): a fast red pulse, one sound, and big text in the
--                             middle of the screen (with a Mend Pet hint for hunters)
-- An optional red glow at the screen edges joins in at danger; it's off by default.
-- Each level only clears once health is a few % above its line, so the alert
-- doesn't flicker while health hovers right around it.
local _, ns = ...
local QoL = ns.QoL

local NONE, WARN, DANGER = 0, 1, 2
local MARGIN = 5 -- % above a line before its alert clears
local SOUND_COOLDOWN = 5 -- seconds between danger sounds
local TEXT_TIME = 4 -- seconds the big text stays up
local TEXT_FADE = 1 -- of which the last second fades out
local MEND_PET_ID = 136 -- any rank; used to get the spell's name in this client's language

local COLORS = {
    [WARN] = { 1, 0.55, 0 },
    [DANGER] = { 1, 0.1, 0.1 },
}
local PULSE_SPEED = { [WARN] = 2.5, [DANGER] = 9 } -- radians per second

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

-- Pet health as a whole %, or nil when there is no living pet to warn about.
function P:GetPetPct()
    if self.testPct then return self.testPct end
    if not UnitExists("pet") or _G.UnitIsDead("pet") then return end
    if _G.UnitOnTaxi and _G.UnitOnTaxi("player") then return end
    local max = _G.UnitHealthMax("pet")
    if not max or max <= 0 then return end
    return math.floor(_G.UnitHealth("pet") / max * 100 + 0.5)
end

-- The new level for `pct`, starting from the current one (keeps an alert on
-- until health is MARGIN above its line).
function P:NextLevel(pct)
    if not pct or not self.db.enabled then return NONE end
    local level, db = self.level or NONE, self.db
    if pct <= db.danger then return DANGER end
    if level == DANGER and pct <= db.danger + MARGIN then return DANGER end
    if pct <= db.warn then return WARN end
    if level >= WARN and pct <= db.warn + MARGIN then return WARN end
    return NONE
end

-- Glow around the pet portrait. Our own frame on top of the pet frame, so
-- combat lockdown never gets in the way.
function P:CreateGlow()
    local f = CreateFrame("Frame", "QoLPetHealthGlow", UIParent)
    f:SetFrameStrata("MEDIUM")
    local tex = f:CreateTexture(nil, "OVERLAY")
    tex:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    tex:SetBlendMode("ADD")
    tex:SetAllPoints()
    f.tex = tex
    -- A solid wash over the pet's health bar too, so it reads at a glance.
    local bar = f:CreateTexture(nil, "OVERLAY")
    bar:SetColorTexture(1, 1, 1, 0.6)
    bar:SetBlendMode("ADD")
    bar:Hide()
    f.bar = bar
    f:Hide()
    self.glow = f
end

function P:PlaceGlow()
    local f = self.glow
    local portrait = _G.PetPortrait
    local petFrame = _G.PetFrame
    f:ClearAllPoints()
    if portrait and petFrame and petFrame:IsShown() then
        local size = (portrait:GetWidth() or 37) * 2
        f:SetSize(size, size)
        f:SetPoint("CENTER", portrait, "CENTER", 0, 0)
        f:SetFrameLevel(petFrame:GetFrameLevel() + 10)
        local healthBar = _G.PetFrameHealthBar
        f.bar:ClearAllPoints()
        if healthBar then
            f.bar:SetAllPoints(healthBar)
            f.bar:Show()
        else
            f.bar:Hide()
        end
        return true
    end
    return false
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

-- Called when health changes, the pet changes, or a setting changes.
function P:Update()
    if not self.glow then return end
    local pct = self:GetPetPct()
    local old = self.level or NONE
    local level = self:NextLevel(pct)
    self.level = level
    self.pct = pct

    if level == DANGER and old ~= DANGER then
        if self.db.sound then self:PlaySound() end
        if self.db.text then self:ShowText(pct) end
    end
    if level ~= DANGER then
        self.textFrame:Hide()
    elseif self.textFrame:IsShown() then
        self.textFrame.text:SetText(("PET %d%%"):format(pct))
    end

    local c = COLORS[level]
    if level ~= NONE and self.db.glow and self:PlaceGlow() then
        self.glow.tex:SetVertexColor(c[1], c[2], c[3])
        self.glow.bar:SetVertexColor(c[1], c[2], c[3])
        self.glow:Show()
    else
        self.glow:Hide()
    end
    self.screenGlow:SetShown(level == DANGER and self.db.screen)
end

-- Pulses the glows and fades the text while an alert is up.
function P:Animate()
    local now = _G.GetTime()
    local level = self.level or NONE
    local wave = math.abs(math.sin(now * (PULSE_SPEED[level] or 0)))
    if self.glow:IsShown() then
        self.glow:SetAlpha(level == DANGER and (0.3 + 0.7 * wave) or (0.45 + 0.4 * wave))
    end
    if self.screenGlow:IsShown() then
        self.screenGlow:SetAlpha(0.25 + 0.5 * wave)
    end
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

local EVENTS = {
    "UNIT_HEALTH", "UNIT_HEALTH_FREQUENT", "UNIT_MAXHEALTH", "UNIT_PET",
    "PLAYER_ENTERING_WORLD", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED",
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
        P:Update()
    end)
    -- Check pet health a few times a second as well as on events, and pulse
    -- the glows every frame while an alert is up.
    local elapsed = 0
    driver:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= POLL_INTERVAL then
            elapsed = 0
            if P.db.enabled and (P.testPct or UnitExists("pet") or (P.level or NONE) ~= NONE) then P:Update() end
        end
        if (P.level or NONE) ~= NONE then P:Animate() end
    end)
    self:Update()
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
            P:Update()
        end)
    end
end

function P:SetOption(key, on)
    self.db[key] = on
    self:Update()
    refreshHelpers()
end

local function roundPct(v, lo, hi)
    return math.max(lo, math.min(hi, math.floor((tonumber(v) or 0) / 5 + 0.5) * 5))
end

-- Keeps danger below warning: moving one past the other pushes the other along.
function P:SetWarn(v)
    self.db.warn = roundPct(v, 10, 95)
    if self.db.danger >= self.db.warn then self.db.danger = self.db.warn - 5 end
    self:Update()
    refreshHelpers()
end

function P:SetDanger(v)
    self.db.danger = roundPct(v, 5, 90)
    if self.db.danger >= self.db.warn then self.db.warn = self.db.danger + 5 end
    self:Update()
    refreshHelpers()
end

function P:PrintDebug()
    local p = function(...) print("  " .. string.format(...)) end
    local db = self.db
    QoL:Print("pet health debug")
    p("started: %s, on: %s, glow: %s, sound: %s, text: %s, screen: %s",
        tostring(self.glow ~= nil and self.driver ~= nil), tostring(db.enabled), tostring(db.glow),
        tostring(db.sound), tostring(db.text), tostring(db.screen))
    p("warning at %s%%, danger at %s%%", tostring(db.warn), tostring(db.danger))
    p("pet: %s (%s), dead: %s, health: %s / %s", tostring(UnitExists("pet")), tostring(UnitName("pet")),
        tostring(_G.UnitIsDead("pet")), tostring(_G.UnitHealth("pet")), tostring(_G.UnitHealthMax("pet")))
    p("on taxi: %s, pet %%: %s, alert level: %s (0 none, 1 warning, 2 danger)",
        tostring(_G.UnitOnTaxi and _G.UnitOnTaxi("player")), tostring(self:GetPetPct()), tostring(self.level))
    local pf, portrait = _G.PetFrame, _G.PetPortrait
    p("PetFrame: %s (shown: %s), PetPortrait: %s, glow shown: %s",
        tostring(pf ~= nil), tostring(pf and pf:IsShown()), tostring(portrait ~= nil),
        tostring(self.glow and self.glow:IsShown()))
    p("pet health events seen: %s", tostring(self.eventCount))
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
