-- Zeppelins: pins on the world map and minimap for every zeppelin dock,
-- with a tooltip that says where each one goes.
--
-- Dock positions are the zeppelin masters' spots on the zone map. They come
-- from Questie's NPC database, whose Forever data has the same positions for
-- these six as Classic Era. The two Zephras Isle skyboat docks come from
-- community route maps of Forever and are marked as unconfirmed.
local _, ns = ...
local QoL = ns.QoL

local C_Map = _G.C_Map
local MINIMAP_INTERVAL = 0.05 -- seconds between minimap pin updates
local PIN_SIZE = 16
local MINIMAP_PIN_SIZE = 14
local ICON = "Interface\\TaxiFrame\\UI-Taxi-Icon-White"
local PIN_COLOR = { 0.35, 0.85, 1 }

local Z = QoL:RegisterModule("zeppelins", {
    name = "Zeppelins",
    description = "show zeppelin docks and where they go on the map and minimap",
    defaults = {
        enabled = true,
        moved = {}, -- dock id -> { x, y } set with /qol zeppelins here
    },
    slashHelp = {
        "/qol zeppelins - turn the zeppelin pins on or off",
        "/qol zeppelins list - print every zeppelin dock and where it goes",
        "/qol zeppelins here - stand on a platform to move its pin to where you are",
        "/qol zeppelins reset - put every pin back where QoL had it",
        "/qol zeppelins debug - print what QoL sees for the map pins",
    },
})
ns.Zeppelins = Z

-- Zone maps (Classic Era uiMapIDs). The name is a fallback in case the
-- client numbers its maps differently.
local MAPS = {
    durotar = { id = 1411, name = "Durotar" },
    tirisfal = { id = 1420, name = "Tirisfal Glades" },
    stranglethorn = { id = 1434, name = "Stranglethorn Vale" },
    mulgore = { id = 1412, name = "Mulgore" },
    alterac = { id = 1416, name = "Alterac Mountains" },
}

-- One entry per tower; each platform at it has its own zeppelin.
Z.towers = {
    {
        name = "Orgrimmar zeppelin tower", map = "durotar",
        where = "Durotar, just outside Orgrimmar",
        docks = {
            { x = 50.82, y = 13.54, to = "Undercity", toWhere = "Tirisfal Glades", master = "Frezza" },
            { x = 50.69, y = 12.89, to = "Grom'gol Base Camp", toWhere = "Stranglethorn Vale", master = "Snurk Bucksquick" },
        },
    },
    {
        name = "Undercity zeppelin tower", map = "tirisfal",
        where = "Tirisfal Glades, north of the Undercity gates",
        docks = {
            { x = 60.74, y = 58.87, to = "Orgrimmar", toWhere = "Durotar", master = "Zapetta" },
            { x = 61.78, y = 59.18, to = "Grom'gol Base Camp", toWhere = "Stranglethorn Vale", master = "Hin Denburg" },
        },
    },
    {
        name = "Grom'gol zeppelin tower", map = "stranglethorn",
        where = "Grom'gol Base Camp, Stranglethorn Vale",
        docks = {
            { x = 31.43, y = 29.91, to = "Orgrimmar", toWhere = "Durotar", master = "Nez'raz" },
            { x = 31.54, y = 29.36, to = "Undercity", toWhere = "Tirisfal Glades", master = "Squibby Overspeck" },
        },
    },
    {
        name = "Skywatcher Plateau skyboat", map = "mulgore", unconfirmed = true,
        where = "Mulgore, northwest of Thunder Bluff",
        docks = {
            { x = 34.3, y = 25.8, to = "Valanaar", toWhere = "Zephras Isle", kind = "Skyboat" },
        },
    },
    {
        name = "Dalaran skyboat", map = "alterac", unconfirmed = true,
        where = "Alterac Mountains, north side of Dalaran",
        docks = {
            { x = 12.5, y = 51.8, to = "Valanaar", toWhere = "Zephras Isle", kind = "Skyboat" },
        },
    },
}

---------------------------------------------------------------------------
-- Positions
---------------------------------------------------------------------------

local function mapName(id)
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
    return info and info.name
end

-- Find a zone map by name under Azeroth, for clients with other map IDs.
local function findMapByName(name)
    if not (C_Map and C_Map.GetMapChildrenInfo) then return end
    local ok, children = pcall(C_Map.GetMapChildrenInfo, 947, nil, true)
    if not ok or not children then return end
    for _, info in ipairs(children) do
        if info.name == name then return info.mapID end
    end
end

local function resolveMap(key)
    local m = MAPS[key]
    if m.resolved ~= nil then return m.resolved or nil end
    local id = m.id
    local name = mapName(id)
    -- Only second-guess the ID on English clients, where the name can match.
    if name and name ~= m.name and _G.GetLocale and _G.GetLocale():match("^en") then
        id = findMapByName(m.name) or id
    elseif not name then
        id = findMapByName(m.name)
    end
    m.resolved = id or false
    return id
end

local function vector(x, y)
    if _G.CreateVector2D then return _G.CreateVector2D(x, y) end
end

-- World position of each dock: continent ID, and world X (north) / Y (west).
local function worldPos(dock, mapID)
    if dock.world ~= nil then return dock.world or nil end
    dock.world = false
    if not (mapID and C_Map and C_Map.GetWorldPosFromMapPos) then return end
    local v = vector(dock.x / 100, dock.y / 100)
    if not v then return end
    local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, v)
    if ok and continent and pos then
        local wx, wy = pos:GetXY()
        dock.world = { continent = continent, x = wx, y = wy, pos = pos }
    end
    return dock.world or nil
end

-- Which continent a map is on (0 Eastern Kingdoms, 1 Kalimdor), or nil
-- for maps that span several, such as the world map.
local continentCache = {}
local function mapContinent(uiMapID)
    local c = continentCache[uiMapID]
    if c == nil then
        c = false
        local info = C_Map.GetMapInfo(uiMapID)
        local v = vector(0.5, 0.5)
        if v and not (info and info.mapType and info.mapType <= 1) then
            local ok, continent = pcall(C_Map.GetWorldPosFromMapPos, uiMapID, v)
            if ok and continent then c = continent end
        end
        continentCache[uiMapID] = c
    end
    return c or nil
end

-- Where a dock sits on the map `uiMapID`, as 0-1 fractions, or nil if not on it.
local function positionOnMap(tower, dock, uiMapID)
    local home = resolveMap(tower.map)
    if not home then return end
    if uiMapID == home then return dock.x / 100, dock.y / 100 end
    local w = worldPos(dock, home)
    if not (w and C_Map.GetMapPosFromWorldPos) then return end
    -- Only project onto maps of the dock's own continent (or the world map).
    local continent = mapContinent(uiMapID)
    if continent and continent ~= w.continent then return end
    local ok, pos = pcall(C_Map.GetMapPosFromWorldPos, w.continent, w.pos, uiMapID)
    if not ok or not pos then return end
    local x, y = pos:GetXY()
    if not x or x < 0 or x > 1 or y < 0 or y > 1 then return end
    return x, y
end

---------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------

local function addDockLines(dock)
    local kind = dock.kind or "Zeppelin"
    GameTooltip:AddLine(("%s to %s"):format(kind, dock.to), 1, 0.82, 0)
    GameTooltip:AddLine("  lands in " .. dock.toWhere, 1, 1, 1)
    if dock.master then
        GameTooltip:AddLine("  zeppelin master: " .. dock.master, 0.7, 0.7, 0.7)
    end
end

local function showTooltip(pin)
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    local tower = pin.tower
    GameTooltip:SetText(tower.name, PIN_COLOR[1], PIN_COLOR[2], PIN_COLOR[3])
    GameTooltip:AddLine(tower.where, 0.8, 0.8, 0.8)
    if pin.dock then
        addDockLines(pin.dock)
    else
        for _, dock in ipairs(tower.docks) do addDockLines(dock) end
    end
    if tower.unconfirmed then
        GameTooltip:AddLine("Forever only. Spot taken from community maps, not checked in game.", 1, 0.5, 0.5, true)
    end
    GameTooltip:Show()
end

local function createPin(parent, size)
    local pin = CreateFrame("Button", nil, parent)
    pin:SetSize(size, size)
    local tex = pin:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture(ICON)
    tex:SetVertexColor(PIN_COLOR[1], PIN_COLOR[2], PIN_COLOR[3])
    pin.icon = tex
    pin:SetScript("OnEnter", showTooltip)
    pin:SetScript("OnLeave", GameTooltip_Hide)
    pin:Hide()
    return pin
end

---------------------------------------------------------------------------
-- World map
---------------------------------------------------------------------------

-- On a continent or world map the two platforms of a tower overlap, so show
-- one pin per tower there and one per platform on zone maps.
local function isOverviewMap(uiMapID)
    local info = C_Map.GetMapInfo(uiMapID)
    return info and info.mapType and info.mapType <= 2
end

function Z:GetWorldMapCanvas()
    local wm = _G.WorldMapFrame
    if not wm then return end
    if wm.GetCanvas then return wm:GetCanvas() end
    return wm.ScrollContainer and wm.ScrollContainer.Child
end

function Z:AcquireWorldPin(i)
    self.worldPins = self.worldPins or {}
    local pin = self.worldPins[i]
    if not pin then
        pin = createPin(self:GetWorldMapCanvas(), PIN_SIZE)
        self.worldPins[i] = pin
    end
    return pin
end

function Z:RefreshWorldMap()
    local wm = _G.WorldMapFrame
    local canvas = self:GetWorldMapCanvas()
    if not (wm and canvas and wm.GetMapID and C_Map) then return end
    local used = 0
    local mapID = wm:GetMapID()
    if self.db.enabled and mapID and wm:IsShown() then
        local width, height = canvas:GetWidth(), canvas:GetHeight()
        local scale = 1
        if wm.ScrollContainer and wm.ScrollContainer.GetCanvasScale then
            scale = wm.ScrollContainer:GetCanvasScale() or 1
        end
        local overview = isOverviewMap(mapID)
        for _, tower in ipairs(self.towers) do
            local groups = overview and { { dock = nil, at = tower.docks[1] } } or nil
            if not groups then
                groups = {}
                for _, dock in ipairs(tower.docks) do groups[#groups + 1] = { dock = dock, at = dock } end
            end
            for _, g in ipairs(groups) do
                local x, y = positionOnMap(tower, g.at, mapID)
                if x then
                    used = used + 1
                    local pin = self:AcquireWorldPin(used)
                    pin.tower, pin.dock = tower, g.dock
                    -- Keep the pin the same size on screen however far the map is zoomed.
                    pin:SetScale(1 / scale)
                    pin:ClearAllPoints()
                    pin:SetPoint("CENTER", canvas, "TOPLEFT", x * width * scale, -y * height * scale)
                    pin:SetFrameLevel(canvas:GetFrameLevel() + 2000)
                    pin:Show()
                end
            end
        end
    end
    for i = used + 1, #(self.worldPins or {}) do
        self.worldPins[i]:Hide()
    end
    self.worldPinCount = used
end

function Z:HookWorldMap()
    local wm = _G.WorldMapFrame
    if not wm or self.worldMapWatcher then return end
    -- A child of the map runs OnUpdate only while the map is open, and redraws
    -- when the map, its zoom or its size changes.
    local watcher = CreateFrame("Frame", nil, wm)
    local last = {}
    watcher:SetScript("OnUpdate", function()
        local canvas = Z:GetWorldMapCanvas()
        if not canvas then return end
        local scale = wm.ScrollContainer and wm.ScrollContainer.GetCanvasScale
            and wm.ScrollContainer:GetCanvasScale() or 1
        local mapID = wm:GetMapID()
        local w = canvas:GetWidth()
        if mapID ~= last.mapID or scale ~= last.scale or w ~= last.w or Z.db.enabled ~= last.enabled then
            last.mapID, last.scale, last.w, last.enabled = mapID, scale, w, Z.db.enabled
            Z:RefreshWorldMap()
        end
    end)
    watcher:SetScript("OnHide", function() wipe(last) end)
    self.worldMapWatcher = watcher
end

---------------------------------------------------------------------------
-- Minimap
---------------------------------------------------------------------------

-- How many yards across the minimap shows at each zoom level.
local MINIMAP_YARDS = {
    outdoor = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 },
    indoor = { [0] = 300, 240, 180, 120, 80, 50 },
}

function Z:CreateMinimapPins()
    self.minimapPins = {}
    for _, tower in ipairs(self.towers) do
        for _, dock in ipairs(tower.docks) do
            local pin = createPin(_G.Minimap, MINIMAP_PIN_SIZE)
            pin:SetFrameLevel(_G.Minimap:GetFrameLevel() + 5)
            pin.tower, pin.dock = tower, dock
            self.minimapPins[#self.minimapPins + 1] = pin
        end
    end
end

local function hideMinimapPins()
    for _, pin in ipairs(Z.minimapPins or {}) do pin:Hide() end
end

function Z:UpdateMinimap()
    local minimap = _G.Minimap
    if not (self.db.enabled and minimap and minimap:IsVisible() and _G.UnitPosition) then
        hideMinimapPins()
        return
    end
    -- UnitPosition gives world X (north) first, then world Y (west).
    local px, py, _, instance = _G.UnitPosition("player")
    if not py then
        hideMinimapPins()
        return
    end
    local zoom = minimap:GetZoom() or 0
    local indoors = _G.IsIndoors and _G.IsIndoors()
    local yards = (indoors and MINIMAP_YARDS.indoor or MINIMAP_YARDS.outdoor)[zoom] or 466
    local radiusPx = minimap:GetWidth() / 2
    local pxPerYard = radiusPx / (yards / 2)
    local rotate = _G.GetCVar("rotateMinimap") == "1"
    local facing = rotate and _G.GetPlayerFacing and _G.GetPlayerFacing() or 0
    local cosF, sinF = math.cos(facing), math.sin(facing)

    for _, pin in ipairs(self.minimapPins) do
        local w = worldPos(pin.dock, resolveMap(pin.tower.map))
        local shown = false
        if w and w.continent == instance then
            -- World X grows to the north and world Y to the west.
            local dx, dy = py - w.y, w.x - px -- yards east, yards north
            if rotate then
                dx, dy = dx * cosF + dy * sinF, -dx * sinF + dy * cosF
            end
            local x, y = dx * pxPerYard, dy * pxPerYard
            if x * x + y * y <= (radiusPx - 4) ^ 2 then
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", minimap, "CENTER", x, y)
                shown = true
            end
        end
        pin:SetShown(shown)
    end
end

---------------------------------------------------------------------------
-- Setup and commands
---------------------------------------------------------------------------

function Z:OnEnable()
    if not C_Map then return end
    if _G.Minimap then
        self:CreateMinimapPins()
        local driver = CreateFrame("Frame")
        local elapsed = 0
        driver:SetScript("OnUpdate", function(_, dt)
            elapsed = elapsed + dt
            if elapsed < MINIMAP_INTERVAL then return end
            elapsed = 0
            Z:UpdateMinimap()
        end)
        self.minimapDriver = driver
    end
    self:HookWorldMap()
    -- The world map can load on demand; hook it as soon as it appears.
    if not _G.WorldMapFrame then
        local loader = CreateFrame("Frame")
        loader:RegisterEvent("ADDON_LOADED")
        loader:SetScript("OnEvent", function()
            if _G.WorldMapFrame then
                Z:HookWorldMap()
                loader:UnregisterAllEvents()
            end
        end)
    end
end

---------------------------------------------------------------------------
-- Moving a pin by hand
---------------------------------------------------------------------------

local function dockID(tower, dock)
    return tower.map .. ":" .. (dock.master or dock.to)
end

-- Put each dock at its built-in spot, or where the player moved it.
function Z:ApplyMoved()
    for _, tower in ipairs(self.towers) do
        for _, dock in ipairs(tower.docks) do
            dock.homeX = dock.homeX or dock.x
            dock.homeY = dock.homeY or dock.y
            local m = self.db.moved[dockID(tower, dock)]
            dock.x, dock.y = m and m[1] or dock.homeX, m and m[2] or dock.homeY
            dock.world = nil
        end
    end
    if self.minimapPins then self:UpdateMinimap() end
    self:RefreshWorldMap()
end

function Z:OnLoad()
    self:ApplyMoved()
end

-- Move the closest dock on the player's current zone map to where they stand.
function Z:MoveNearestDockHere()
    local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local pos = mapID and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then
        QoL:Print("can't read your map position here.")
        return
    end
    local x, y = pos:GetXY()
    x, y = x * 100, y * 100
    local best, bestTower, bestDist
    for _, tower in ipairs(self.towers) do
        if resolveMap(tower.map) == mapID then
            for _, dock in ipairs(tower.docks) do
                local d = (dock.x - x) ^ 2 + (dock.y - y) ^ 2
                if not bestDist or d < bestDist then best, bestTower, bestDist = dock, tower, d end
            end
        end
    end
    if not best or bestDist > 25 then -- within 5 map units
        QoL:Print(("no zeppelin dock near you (you are at %.1f, %.1f on map %s)."):format(x, y, tostring(mapID)))
        return
    end
    self.db.moved[dockID(bestTower, best)] = { math.floor(x * 100 + 0.5) / 100, math.floor(y * 100 + 0.5) / 100 }
    self:ApplyMoved()
    QoL:Print(("moved the pin for the %s to %s to %.2f, %.2f. /qol zeppelins reset puts it back."):format(
        (best.kind or "zeppelin"):lower(), best.to, x, y))
end

function Z:SetEnabled(on)
    self.db.enabled = on
    self:UpdateMinimap()
    self:RefreshWorldMap()
    if ns.Todo and ns.Todo.RefreshHelpers then ns.Todo:RefreshHelpers() end
end

function Z:PrintList()
    QoL:Print("zeppelin docks:")
    for _, tower in ipairs(self.towers) do
        print(("  |cffffd100%s|r - %s%s"):format(tower.name, tower.where,
            tower.unconfirmed and " (Forever, not checked in game)" or ""))
        for _, dock in ipairs(tower.docks) do
            print(("    %.1f, %.1f: %s to %s, %s%s"):format(dock.x, dock.y, dock.kind or "Zeppelin",
                dock.to, dock.toWhere, dock.master and (" (" .. dock.master .. ")") or ""))
        end
    end
end

function Z:PrintDebug()
    local p = function(...) print("  " .. string.format(...)) end
    QoL:Print("zeppelins debug")
    p("enabled: %s, C_Map: %s, UnitPosition: %s, WorldMapFrame: %s",
        tostring(self.db.enabled), tostring(C_Map ~= nil), tostring(_G.UnitPosition ~= nil),
        tostring(_G.WorldMapFrame ~= nil))
    for key in pairs(MAPS) do
        local id = resolveMap(key)
        p("%s: map %s (%s)", key, tostring(id), tostring(id and mapName(id)))
    end
    local px, py, instance
    if _G.UnitPosition then
        local _
        px, py, _, instance = _G.UnitPosition("player")
    end
    p("you: continent %s, world %s, %s", tostring(instance), tostring(px), tostring(py))
    for _, tower in ipairs(self.towers) do
        local w = worldPos(tower.docks[1], resolveMap(tower.map))
        p("%s: continent %s, world %s, %s", tower.name, tostring(w and w.continent),
            tostring(w and w.x), tostring(w and w.y))
    end
    p("world map pins shown: %d", self.worldPinCount or 0)
end

function Z:OnSlash(args)
    local cmd = (args or ""):lower()
    if cmd == "" or cmd == "on" or cmd == "off" then
        if cmd == "" then
            self:SetEnabled(not self.db.enabled)
        else
            self:SetEnabled(cmd == "on")
        end
        QoL:Print("zeppelin pins are " .. (self.db.enabled and "on" or "off") .. ".")
    elseif cmd == "here" then
        self:MoveNearestDockHere()
    elseif cmd == "reset" then
        wipe(self.db.moved)
        self:ApplyMoved()
        QoL:Print("zeppelin pins are back where QoL had them.")
    elseif cmd == "list" then
        self:PrintList()
    elseif cmd == "debug" then
        self:PrintDebug()
    else
        QoL:Print("unknown command. Type /qol for help.")
    end
end
