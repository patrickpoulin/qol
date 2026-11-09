-- Action bar: hide the gryphon end caps on either side of the main action bar.
--
-- The caps are plain textures, not protected frames, so changing their alpha
-- is allowed in combat and can't taint the action buttons. We fade them to
-- alpha 0 instead of calling Hide(), and hook SetAlpha/Show so a redraw by
-- the game (vehicle, form change, loading screen) can't bring them back.
local _, ns = ...
local QoL = ns.QoL

local A = QoL:RegisterModule("gryphons", {
    name = "Action bar",
    description = "hide the gryphons beside the main action bar",
    defaults = {
        hideGryphons = false,
    },
    slashHelp = {
        "/qol gryphons - hide or show them (or /qol gryphons on / off)",
    },
})
ns.ActionBar = A

-- Words that mark gryphon/wyvern end-cap art in a texture's name, atlas or file.
local CAP_WORDS = { "endcap", "gryphon", "griffon", "wyvern" }

local function safeString(fn, obj)
    if not fn then return nil end
    local ok, v = pcall(fn, obj)
    if ok and type(v) == "string" then return v:lower() end
    return nil
end

local function looksLikeCap(tex, key)
    local texts = {
        key and tostring(key):lower(),
        safeString(tex.GetName, tex),
        safeString(tex.GetAtlas, tex),
        safeString(tex.GetTexture, tex),
        safeString(tex.GetTextureFilePath, tex),
    }
    for _, text in pairs(texts) do
        for _, word in ipairs(CAP_WORDS) do
            if text:find(word, 1, true) then return true end
        end
    end
    return false
end

local function isTexture(obj)
    return type(obj) == "table" and obj.GetObjectType and obj.SetAlpha
        and obj:GetObjectType() == "Texture"
end

-- The frames the end caps can hang off, across client layouts.
local function barFrames()
    local list = {}
    for _, name in ipairs({ "MainMenuBar", "MainActionBar", "MainMenuBarArtFrame",
        "MainMenuBarArtFrameBackground", "MainMenuBarOverlayFrame" }) do
        if _G[name] then table.insert(list, _G[name]) end
    end
    return list
end

local function findCaps()
    local caps, seen = {}, {}
    local function add(tex)
        if isTexture(tex) and not seen[tex] then
            seen[tex] = true
            table.insert(caps, tex)
        end
    end
    -- Known names first.
    add(_G.MainMenuBarLeftEndCap)
    add(_G.MainMenuBarRightEndCap)
    for _, frame in ipairs(barFrames()) do
        local ends = frame.EndCaps
        if type(ends) == "table" then
            add(ends.LeftEndCap)
            add(ends.RightEndCap)
        end
        add(frame.LeftEndCap)
        add(frame.RightEndCap)
    end
    -- Then search the bar and its child frames (two levels deep) for any
    -- texture whose key, name, atlas or file says it is end-cap art.
    local visited = {}
    local function scan(frame, depth)
        if visited[frame] or depth > 3 then return end
        visited[frame] = true
        for key, value in pairs(frame) do
            if isTexture(value) and looksLikeCap(value, key) then add(value) end
        end
        if frame.GetRegions then
            for _, region in ipairs({ frame:GetRegions() }) do
                if isTexture(region) and looksLikeCap(region) then add(region) end
            end
        end
        if frame.GetChildren then
            for _, child in ipairs({ frame:GetChildren() }) do scan(child, depth + 1) end
        end
        if type(frame.EndCaps) == "table" then scan(frame.EndCaps, depth + 1) end
    end
    for _, frame in ipairs(barFrames()) do scan(frame, 1) end
    return caps
end

local function describe(tex)
    return ("%s atlas=%s file=%s"):format(
        tostring(safeString(tex.GetName, tex) or safeString(tex.GetDebugName, tex) or "?"),
        tostring(safeString(tex.GetAtlas, tex)), tostring(safeString(tex.GetTexture, tex)
            or safeString(tex.GetTextureFilePath, tex)))
end

-- Keep an object faded (and, for textures, hidden) whatever the game does to
-- it, while the option is on. Only alpha and visibility of art are touched,
-- never a protected frame, so this is safe in combat.
local function enforce(obj)
    if not A.db.hideGryphons or obj.qolSetting then return end
    obj.qolSetting = true
    obj:SetAlpha(0)
    if obj.qolHideToo then obj:Hide() end
    obj.qolSetting = nil
end

local function setHidden(obj, hide, hideToo)
    if not obj.qolHooked then
        obj.qolHooked = true
        obj.qolHideToo = hideToo
        hooksecurefunc(obj, "SetAlpha", enforce)
        hooksecurefunc(obj, "Show", enforce)
        if obj.SetShown then hooksecurefunc(obj, "SetShown", enforce) end
    end
    obj.qolSetting = true
    obj:SetAlpha(hide and 0 or 1)
    if hideToo then
        if hide then obj:Hide() else obj:Show() end
    end
    obj.qolSetting = nil
end

local function isProtected(frame)
    if not frame.IsProtected then return false end
    local ok, protected = pcall(frame.IsProtected, frame)
    return not ok or protected
end

-- The frames that hold the caps (e.g. MainActionBar.EndCaps), so the whole
-- holder fades too. The action bar itself and anything protected are skipped.
local function findHolders(caps)
    local holders, seen, bars = {}, {}, {}
    for _, bar in ipairs(barFrames()) do bars[bar] = true end
    local function add(frame)
        if type(frame) == "table" and frame.SetAlpha and not seen[frame] and not bars[frame]
            and frame.GetObjectType and frame:GetObjectType() ~= "Texture" and not isProtected(frame) then
            seen[frame] = true
            table.insert(holders, frame)
        end
    end
    for _, bar in ipairs(barFrames()) do add(bar.EndCaps) end
    for _, tex in ipairs(caps) do
        if tex.GetParent then add(tex:GetParent()) end
    end
    return holders
end

function A:Apply()
    local hide = self.db.hideGryphons
    self.caps = findCaps()
    self.holders = findHolders(self.caps)
    for _, tex in ipairs(self.caps) do setHidden(tex, hide, true) end
    for _, frame in ipairs(self.holders) do setHidden(frame, hide, false) end
end

function A:SetHideGryphons(on)
    self.db.hideGryphons = on
    self:Apply()
    if ns.Todo and ns.Todo.RefreshHelpers then ns.Todo:RefreshHelpers() end
end

function A:OnEnable()
    self:Apply()
    -- Some layouts build the bar art a moment after login.
    if C_Timer then C_Timer.After(2, function() A:Apply() end) end
    -- The bar can be rebuilt after a loading screen; check again then.
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", QoL:Guard("Action bar", function() A:Apply() end))
end

function A:PrintDebug()
    local caps = findCaps()
    QoL:Print(("gryphons hidden: %s, end caps found: %d"):format(tostring(self.db.hideGryphons), #caps))
    for _, tex in ipairs(caps) do
        local okA, alpha = pcall(tex.GetAlpha, tex)
        local okS, shown = pcall(tex.IsShown, tex)
        print(("  cap: %s alpha=%s shown=%s"):format(describe(tex), okA and tostring(alpha) or "?",
            okS and tostring(shown) or "?"))
    end
    for _, frame in ipairs(findHolders(caps)) do
        print("  holder: " .. tostring(safeString(frame.GetDebugName, frame) or "?"))
    end
    local names = {}
    for _, frame in ipairs(barFrames()) do
        table.insert(names, safeString(frame.GetName, frame) or "?")
    end
    print("  bar frames: " .. (#names > 0 and table.concat(names, ", ") or "none"))
    if #caps == 0 then
        -- List the bar's textures so the right ones can be picked out.
        local n = 0
        for _, frame in ipairs(barFrames()) do
            for _, region in ipairs({ frame:GetRegions() }) do
                if isTexture(region) and n < 15 then
                    n = n + 1
                    print("  texture: " .. describe(region))
                end
            end
        end
    end
end

function A:OnSlash(args)
    local cmd = (args or ""):lower()
    if cmd == "" then
        self:SetHideGryphons(not self.db.hideGryphons)
    elseif cmd == "on" or cmd == "off" then
        self:SetHideGryphons(cmd == "on")
    elseif cmd == "debug" then
        self:PrintDebug()
        return
    else
        QoL:Print("unknown command. Type /qol for help.")
        return
    end
    QoL:Print("action bar gryphons are " .. (self.db.hideGryphons and "hidden" or "shown") .. ".")
end
