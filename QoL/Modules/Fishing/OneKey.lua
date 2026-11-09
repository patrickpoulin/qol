-- One-key fishing. While your pole is on, your fishing key:
--   * puts your best lure on the pole if it has none (when auto lure is on),
--   * otherwise casts Fishing,
--   * and while the line is out, acts as the game's Interact key, so pressing it
--     when the bobber splashes reels it in.
-- The pole also turns on the interact key and fishing sound (louder effects, no
-- music or ambience). Your own settings come back when the pole comes off.
--
-- Key bindings can't change in combat, so the key is released when a fight starts.
local _, ns = ...
local QoL = ns.QoL
local F = ns.Fishing

local FISHING_SPELL = 7620
local INTERACT_CVAR, INTERACT_ON = "SoftTargetInteract", "3"
local FISHING_CVARS = {
    -- name, value while fishing
    { INTERACT_CVAR, INTERACT_ON },
    { "Sound_SFXVolume", "1" },
    { "Sound_EnableMusic", "0" },
    { "Sound_EnableAmbience", "0" },
    { "Sound_MasterVolume", "1" },
    { "Sound_EnableDialog", "0" }, -- NPC chatter
    { "Sound_EnableSoundWhenGameIsInBG", "1" }, -- hear the splash while alt-tabbed
}

local function fishingSpellName()
    local C_Spell = _G.C_Spell
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(FISHING_SPELL)
    end
    return (_G.GetSpellInfo(FISHING_SPELL)) or "Fishing"
end

-- Invisible secure button that the key clicks: casts, or applies a lure.
local castButton = CreateFrame("Button", "QoLFishCastButton", UIParent, "SecureActionButtonTemplate")
castButton:SetSize(1, 1)
castButton:SetAttribute("type", "macro")
-- Newer clients run secure clicks on key down or up per the user's setting, and
-- need both registered; older ones would fire twice, so only the release there.
if GetCVar("ActionButtonUseKeyDown") ~= nil then
    castButton:RegisterForClicks("AnyUp", "AnyDown")
    castButton:SetAttribute("useOnKeyDown", false)
else
    castButton:RegisterForClicks("AnyUp")
end

local owner = CreateFrame("Frame") -- owns our override bindings
local bound -- what the key is bound to right now: "cast", "interact" or nil

function F:BestLureInBags()
    for i = #self.lures, 1, -1 do
        local lure = self.lures[i]
        if (QoL.GetItemCount(lure.id) or 0) > 0 then return lure end
    end
end

-- Point the cast button at the next thing the key should do.
function F:UpdateCastAction()
    if InCombatLockdown() then return end
    local lure = self.db.autoLure and not self:GetLureTimeLeft() and self:BestLureInBags()
    local text
    if lure then
        text = ("/use item:%d\n/use 16"):format(lure.id)
    else
        text = "/cast " .. fishingSpellName()
    end
    castButton:SetAttribute("macrotext", text)
end

local function setBinding(mode)
    if InCombatLockdown() or bound == mode then return end
    ClearOverrideBindings(owner)
    bound = nil
    local key = F.db.key
    if not key or not mode then return end
    if mode == "cast" then
        SetOverrideBindingClick(owner, true, key, "QoLFishCastButton", "LeftButton")
    else
        SetOverrideBinding(owner, true, key, "INTERACTTARGET")
    end
    bound = mode
end

-- Turn on the fishing settings, saving yours first (once, so a /reload with the
-- pole on doesn't save the fishing values as yours).
local function applyFishingCVars()
    if not F.db.fishingSettings then return end
    local saved = F.charDB.savedCVars or {}
    F.charDB.savedCVars = saved
    for _, cvar in ipairs(FISHING_CVARS) do
        if saved[cvar[1]] == nil then saved[cvar[1]] = GetCVar(cvar[1]) end
    end
    for _, cvar in ipairs(FISHING_CVARS) do
        if GetCVar(cvar[1]) ~= nil then SetCVar(cvar[1], cvar[2]) end
    end
end

local function restoreCVars()
    local saved = F.charDB.savedCVars
    if not saved then return end
    for name, value in pairs(saved) do
        SetCVar(name, value)
    end
    F.charDB.savedCVars = nil
end

-- Called whenever the pole, combat state or key changes.
function F:UpdateFishingMode()
    if InCombatLockdown() then return end
    local fishing = self:IsPoleEquipped()
    if fishing then
        applyFishingCVars()
        self:UpdateCastAction()
        if bound ~= "interact" then setBinding("cast") end
    else
        restoreCVars()
        setBinding(nil)
    end
end

function F:SetKey(key)
    if InCombatLockdown() then return QoL:Print("you can't change keys in combat.") end
    setBinding(nil)
    self.db.key = key
    self:UpdateFishingMode()
    if key then
        QoL:Print(("fishing key is %s. Equip your pole, press it to cast, and again when the bobber splashes."):format(key))
    else
        QoL:Print("fishing key cleared.")
    end
    if ns.Todo.RefreshFishing then ns.Todo:RefreshFishing() end
end

function F:SetFishingSettings(on)
    if InCombatLockdown() then return QoL:Print("try again after combat.") end
    self.db.fishingSettings = on
    if on then
        if self:IsPoleEquipped() then applyFishingCVars() end
    else
        restoreCVars()
    end
    QoL:Print(on and "fishing settings on: interact key, loud effects, no music while the pole is on."
        or "fishing settings off.")
end

function F:SetAutoLure(on)
    self.db.autoLure = on
    self:UpdateCastAction()
    QoL:Print(on and "your fishing key will put on your best lure when the pole has none."
        or "auto lure off.")
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("UNIT_INVENTORY_CHANGED")
events:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
events:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, unit)
    if not F.db then return end -- saved data not loaded yet
    if event == "PLAYER_REGEN_DISABLED" then
        -- Lockdown starts just after this event: let go of the key now.
        setBinding(nil)
        return
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        if unit == "player" and UnitChannelInfo("player") == fishingSpellName() then
            setBinding("interact")
        end
        return
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if unit ~= "player" then return end
        -- Wait a moment so the press that reels in doesn't also cast again.
        C_Timer.After(0.3, function()
            if bound == "interact" then setBinding(nil) end
            F:UpdateFishingMode()
        end)
        return
    elseif event == "UNIT_INVENTORY_CHANGED" and unit ~= "player" then
        return
    end
    F:UpdateFishingMode()
end)

QoL:GuardScripts("One-key fishing", events, "OnEvent")
