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

-- Every place the end caps have lived: the 1.x layout uses globals, the newer
-- layout keeps them under MainMenuBar.EndCaps.
local function findCaps()
    local caps, seen = {}, {}
    local function add(tex)
        if tex and not seen[tex] and tex.SetAlpha then
            seen[tex] = true
            table.insert(caps, tex)
        end
    end
    add(_G.MainMenuBarLeftEndCap)
    add(_G.MainMenuBarRightEndCap)
    local bar = _G.MainMenuBar
    local ends = bar and bar.EndCaps
    if ends then
        add(ends.LeftEndCap)
        add(ends.RightEndCap)
    end
    local art = _G.MainMenuBarArtFrame
    if art then
        add(art.LeftEndCap)
        add(art.RightEndCap)
    end
    return caps
end

function A:Apply()
    local hide = self.db.hideGryphons
    self.caps = findCaps()
    for _, tex in ipairs(self.caps) do
        if not tex.qolHooked then
            tex.qolHooked = true
            -- Whatever the game sets, put our alpha back while the option is on.
            local function enforce(t)
                if A.db.hideGryphons and not t.qolSetting and t:GetAlpha() ~= 0 then
                    t.qolSetting = true
                    t:SetAlpha(0)
                    t.qolSetting = nil
                end
            end
            hooksecurefunc(tex, "SetAlpha", enforce)
            hooksecurefunc(tex, "Show", enforce)
        end
        tex.qolSetting = true
        tex:SetAlpha(hide and 0 or 1)
        tex.qolSetting = nil
    end
end

function A:SetHideGryphons(on)
    self.db.hideGryphons = on
    self:Apply()
    if ns.Todo and ns.Todo.RefreshHelpers then ns.Todo:RefreshHelpers() end
end

function A:OnEnable()
    self:Apply()
    -- The bar can be rebuilt after a loading screen; check again then.
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function() A:Apply() end)
end

function A:OnSlash(args)
    local cmd = (args or ""):lower()
    if cmd == "" then
        self:SetHideGryphons(not self.db.hideGryphons)
    elseif cmd == "on" or cmd == "off" then
        self:SetHideGryphons(cmd == "on")
    elseif cmd == "debug" then
        QoL:Print(("gryphons hidden: %s, end caps found: %d"):format(
            tostring(self.db.hideGryphons), #findCaps()))
        return
    else
        QoL:Print("unknown command. Type /qol for help.")
        return
    end
    QoL:Print("action bar gryphons are " .. (self.db.hideGryphons and "hidden" or "shown") .. ".")
end
