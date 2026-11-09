-- QoL core: namespace, saved data, module registry.
local ADDON_NAME, ns = ...

local QoL = {
    modules = {},
    moduleOrder = {},
}
ns.QoL = QoL
_G.QoL = QoL -- handy for /dump while debugging

local DB_VERSION = 1

function QoL:Print(...)
    print("|cff33ff99QoL|r:", ...)
end

-- Fill missing keys in `target` from `defaults` (deep for plain tables).
local function applyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            target[k] = type(v) == "table" and CopyTable(v) or v
        elseif type(v) == "table" and type(target[k]) == "table" then
            applyDefaults(target[k], v)
        end
    end
    return target
end
QoL.ApplyDefaults = applyDefaults

-- A module is a table with optional fields:
--   name, description, defaults, charDefaults, slashHelp (list of lines)
--   OnLoad(self)          saved data is ready (self.db, self.charDB)
--   OnEnable(self)        player is in the world; build UI here
--   OnSlash(self, args)   handles "/qol <key> <args>"
-- True for the "secret" values newer clients hand out in restricted
-- situations (raids, combat). Comparing or doing maths on one is an error.
function QoL.IsSecret(v)
    local check = _G.issecretvalue
    return check ~= nil and v ~= nil and check(v) and true or false
end

-- Wraps a handler that runs often (events, OnUpdate, hooks). The first error
-- is printed once and switches the handler off until /reload, so one bad
-- value can't flood the game with errors (which makes it offer to turn
-- addons off).
function QoL:Guard(label, fn)
    local broken = false
    return function(...)
        if broken then return end
        local ok, err = pcall(fn, ...)
        if not ok then
            broken = true
            QoL:Print(("|cffff5555%s hit an error and is paused until /reload:|r %s"):format(label, tostring(err)))
        end
    end
end

-- Guard scripts a frame already has, e.g. QoL:GuardScripts("Pins", f, "OnUpdate").
function QoL:GuardScripts(label, frame, ...)
    for i = 1, select("#", ...) do
        local name = select(i, ...)
        local fn = frame:GetScript(name)
        if fn then frame:SetScript(name, QoL:Guard(label, fn)) end
    end
end

function QoL:RegisterModule(key, module)
    assert(not self.modules[key], "QoL module already registered: " .. key)
    module.key = key
    self.modules[key] = module
    table.insert(self.moduleOrder, key)
    return module
end

function QoL:GetModule(key)
    return self.modules[key]
end

local function migrate(db)
    db.version = db.version or DB_VERSION
    -- Future shape changes go here, e.g.:
    -- if db.version < 2 then ... db.version = 2 end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        QoLDB = QoLDB or {}
        QoLCharDB = QoLCharDB or {}
        migrate(QoLDB)
        QoLDB.modules = QoLDB.modules or {}

        for _, key in ipairs(QoL.moduleOrder) do
            local mod = QoL.modules[key]
            QoLDB.modules[key] = applyDefaults(QoLDB.modules[key] or {}, mod.defaults or {})
            QoLCharDB[key] = applyDefaults(QoLCharDB[key] or {}, mod.charDefaults or {})
            mod.db = QoLDB.modules[key]
            mod.charDB = QoLCharDB[key]
            if mod.OnLoad then mod:OnLoad() end
        end
        events:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        for _, key in ipairs(QoL.moduleOrder) do
            local mod = QoL.modules[key]
            if mod.OnEnable then
                -- Report a failure in chat instead of silently showing nothing.
                local ok, err = pcall(mod.OnEnable, mod)
                if not ok then
                    QoL:Print(("|cffff5555%s failed to start:|r %s"):format(mod.name or key, tostring(err)))
                end
            end
        end
        QoL:Print("loaded. Type /qol to show the window or list commands.")
    end
end)
