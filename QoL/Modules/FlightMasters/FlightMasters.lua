-- Flight masters: a pin on the world map and minimap for every flight master,
-- coloured by faction, with a tooltip naming the flight master and the town.
--
-- Spots come from QuestieDB's WoW Forever NPC data (build 1.60.1), which has
-- Forever's own positions where they differ from Classic Era (Stormwind,
-- Lakeshire and Light's Hope moved). The Riverglades and Mount Hyjal flight
-- masters are new in Forever and come from that data's in-game traces.
-- Zephras Isle has no flight master in that data; it is reached by skyboat.
-- The druid-only flight masters in Thunder Bluff and Darnassus are left out.
local _, ns = ...
local QoL = ns.QoL

local C_Map = _G.C_Map
local MINIMAP_INTERVAL = 0.05 -- seconds between minimap pin updates
local PIN_SIZE = 14
local MINIMAP_PIN_SIZE = 12
local ICON = "Interface\\TaxiFrame\\UI-Taxi-Icon-White"

local A, H, N = "Alliance", "Horde", nil
local COLORS = {
    Alliance = { 0.3, 0.55, 1 },
    Horde = { 1, 0.3, 0.25 },
    neutral = { 0.4, 1, 0.4 },
}

local function colorOf(master)
    return COLORS[master.faction or "neutral"]
end

local F = QoL:RegisterModule("flights", {
    name = "Flight masters",
    description = "show every flight master on the map and minimap",
    defaults = {
        enabled = true,
        ownFaction = false, -- hide the other faction's flight masters
    },
    slashHelp = {
        "/qol flights - turn the flight master pins on or off",
        "/qol flights mine - show only your faction's flight masters (again to show all)",
        "/qol flights list - print every flight master",
        "/qol flights debug - print what QoL sees for the map pins",
    },
})
ns.FlightMasters = F

-- map is the Classic Era / Forever uiMapID of the zone (or city) map the spot
-- is on; zone is its name, used to find the map if the client numbers it differently.
F.masters = {
    -- Eastern Kingdoms
    { name = "Cedrik Prose", title = "Gryphon Master", faction = A, map = 1417, zone = "Arathi Highlands", town = "Refuge Pointe", x = 45.73, y = 46.1 },
    { name = "Urda", title = "Wind Rider Master", faction = H, map = 1417, zone = "Arathi Highlands", town = "Hammerfall", x = 73.02, y = 32.7 },
    { name = "Gorrik", title = "Wind Rider Master", faction = H, map = 1418, zone = "Badlands", town = "Kargath", x = 3.99, y = 44.78 },
    { name = "Alexandra Constantine", title = "Gryphon Master", faction = A, map = 1419, zone = "Blasted Lands", town = "Nethergarde Keep", x = 65.54, y = 24.34 },
    { name = "Borgus Stoutarm", title = "Gryphon Master", faction = A, map = 1428, zone = "Burning Steppes", town = "Morgan's Vigil", x = 84.33, y = 68.33 },
    { name = "Vahgruk", title = "Wind Rider Master", faction = H, map = 1428, zone = "Burning Steppes", town = "Flame Crest", x = 65.69, y = 24.22 },
    { name = "Felicia Maline", title = "Gryphon Master", faction = A, map = 1431, zone = "Duskwood", town = "Darkshire", x = 77.49, y = 44.29 },
    { name = "Georgia", title = "Bat Handler", faction = H, map = 1423, zone = "Eastern Plaguelands", town = "Light's Hope Chapel", x = 70.53, y = 47.55 },
    { name = "Khaelyn Steelwing", title = "Gryphon Master", faction = A, map = 1423, zone = "Eastern Plaguelands", town = "Light's Hope Chapel", x = 71.81, y = 49.6 },
    { name = "Darla Harris", title = "Gryphon Master", faction = A, map = 1424, zone = "Hillsbrad Foothills", town = "Southshore", x = 49.34, y = 52.27 },
    { name = "Zarise", title = "Bat Handler", faction = H, map = 1424, zone = "Hillsbrad Foothills", town = "Tarren Mill", x = 60.14, y = 18.62 },
    { name = "Gryth Thurden", title = "Gryphon Master", faction = A, map = 1455, zone = "Ironforge", town = "Ironforge", x = 55.5, y = 47.74 },
    { name = "Thorgrum Borrelson", title = "Gryphon Master", faction = A, map = 1432, zone = "Loch Modan", town = "Thelsamar", x = 33.94, y = 50.95 },
    { name = "Ariena Stormfeather", title = "Gryphon Master", faction = A, map = 1433, zone = "Redridge Mountains", town = "Lakeshire", x = 25.5, y = 59.41 },
    { name = "Grisha", title = "Wind Rider Master", faction = H, map = 1427, zone = "Searing Gorge", town = "Thorium Point", x = 34.84, y = 30.87 },
    { name = "Lanie Reed", title = "Gryphon Master", faction = A, map = 1427, zone = "Searing Gorge", town = "Thorium Point", x = 37.94, y = 30.86 },
    { name = "Karos Razok", title = "Bat Handler", faction = H, map = 1421, zone = "Silverpine Forest", town = "The Sepulcher", x = 45.62, y = 42.6 },
    { name = "Dungar Longdrink", title = "Gryphon Master", faction = A, map = 1453, zone = "Stormwind City", town = "Stormwind", x = 71.29, y = 72.23 },
    { name = "Gringer", title = "Wind Rider Master", faction = H, map = 1434, zone = "Stranglethorn Vale", town = "Booty Bay", x = 26.87, y = 77.1 },
    { name = "Gyll", title = "Gryphon Master", faction = A, map = 1434, zone = "Stranglethorn Vale", town = "Booty Bay", x = 27.53, y = 77.79 },
    { name = "Thysta", title = "Wind Rider Master", faction = H, map = 1434, zone = "Stranglethorn Vale", town = "Grom'gol Base Camp", x = 32.54, y = 29.35 },
    { name = "Breyk", title = "Wind Rider Master", faction = H, map = 1435, zone = "Swamp of Sorrows", town = "Stonard", x = 46.07, y = 54.83 },
    { name = "Gorkas", title = "Wind Rider Master", faction = H, map = 1425, zone = "The Hinterlands", town = "Revantusk Village", x = 81.7, y = 81.76 },
    { name = "Guthrum Thunderfist", title = "Gryphon Master", faction = A, map = 1425, zone = "The Hinterlands", town = "Aerie Peak", x = 11.07, y = 46.15 },
    { name = "Michael Garrett", title = "Bat Handler", faction = H, map = 1458, zone = "Undercity", town = "Undercity", x = 63.25, y = 48.56 },
    { name = "Bibilfaz Featherwhistle", title = "Gryphon Master", faction = A, map = 1422, zone = "Western Plaguelands", town = "Chillwind Camp", x = 42.92, y = 85.06 },
    { name = "Thor", title = "Gryphon Master", faction = A, map = 1436, zone = "Westfall", town = "Sentinel Hill", x = 56.55, y = 52.64 },
    { name = "Shellei Brondir", title = "Gryphon Master", faction = A, map = 1437, zone = "Wetlands", town = "Menethil Harbor", x = 9.49, y = 59.69 },
    -- Kalimdor
    { name = "Andruk", title = "Wind Rider Master", faction = H, map = 1440, zone = "Ashenvale", town = "Zoram'gar Outpost", x = 12.24, y = 33.8 },
    { name = "Daelyshia", title = "Hippogryph Master", faction = A, map = 1440, zone = "Ashenvale", town = "Astranaar", x = 34.41, y = 47.99 },
    { name = "Vhulgra", title = "Wind Rider Master", faction = H, map = 1440, zone = "Ashenvale", town = "Splintertree Post", x = 73.18, y = 61.59 },
    { name = "Jarrodenus", title = "Hippogryph Master", faction = A, map = 1447, zone = "Azshara", town = "Talrendis Point", x = 11.9, y = 77.59 },
    { name = "Kroum", title = "Wind Rider Master", faction = H, map = 1447, zone = "Azshara", town = "Valormok", x = 21.96, y = 49.62 },
    { name = "Caylais Moonfeather", title = "Hippogryph Master", faction = A, map = 1439, zone = "Darkshore", town = "Auberdine", x = 36.34, y = 45.58 },
    { name = "Baritanas Skyriver", title = "Hippogryph Master", faction = A, map = 1443, zone = "Desolace", town = "Nijel's Point", x = 64.66, y = 10.54 },
    { name = "Thalon", title = "Wind Rider Master", faction = H, map = 1443, zone = "Desolace", town = "Shadowprey Village", x = 21.6, y = 74.13 },
    { name = "Baldruc", title = "Gryphon Master", faction = A, map = 1445, zone = "Dustwallow Marsh", town = "Theramore Isle", x = 67.48, y = 51.3 },
    { name = "Shardi", title = "Wind Rider Master", faction = H, map = 1445, zone = "Dustwallow Marsh", town = "Brackenwall Village", x = 35.56, y = 31.88 },
    { name = "Brakkar", title = "Wind Rider Master", faction = H, map = 1448, zone = "Felwood", town = "Bloodvenom Post", x = 34.44, y = 53.96 },
    { name = "Mishellena", title = "Hippogryph Master", faction = A, map = 1448, zone = "Felwood", town = "Talonbranch Glade", x = 62.49, y = 24.24 },
    { name = "Fyldren Moonfeather", title = "Hippogryph Master", faction = A, map = 1444, zone = "Feralas", town = "Feathermoon Stronghold", x = 30.24, y = 43.25 },
    { name = "Shyn", title = "Wind Rider Master", faction = H, map = 1444, zone = "Feralas", town = "Camp Mojache", x = 75.45, y = 44.36 },
    { name = "Thyssiana", title = "Hippogryph Master", faction = A, map = 1444, zone = "Feralas", town = "Thalanaar", x = 89.5, y = 45.85 },
    { name = "Faustron", title = "Wind Rider Master", faction = H, map = 1450, zone = "Moonglade", town = "Nighthaven", x = 32.09, y = 66.61 },
    { name = "Sindrayl", title = "Hippogryph Master", faction = A, map = 1450, zone = "Moonglade", town = "Nighthaven", x = 48.1, y = 67.34 },
    { name = "Doras", title = "Wind Rider Master", faction = H, map = 1454, zone = "Orgrimmar", town = "Orgrimmar", x = 45.12, y = 63.89 },
    { name = "Cloud Skydancer", title = "Hippogryph Master", faction = A, map = 1451, zone = "Silithus", town = "Cenarion Hold", x = 50.58, y = 34.45 },
    { name = "Runk Windtamer", title = "Wind Rider Master", faction = H, map = 1451, zone = "Silithus", town = "Cenarion Hold", x = 48.68, y = 36.67 },
    { name = "Teloren", title = "Hippogryph Master", faction = A, map = 1442, zone = "Stonetalon Mountains", town = "Stonetalon Peak", x = 36.44, y = 7.18 },
    { name = "Tharm", title = "Wind Rider Master", faction = H, map = 1442, zone = "Stonetalon Mountains", town = "Sun Rock Retreat", x = 45.12, y = 59.84 },
    { name = "Bera Stonehammer", title = "Gryphon Master", faction = A, map = 1446, zone = "Tanaris", town = "Gadgetzan", x = 51.01, y = 29.34 },
    { name = "Bulkrek Ragefist", title = "Wind Rider Master", faction = H, map = 1446, zone = "Tanaris", town = "Gadgetzan", x = 51.6, y = 25.44 },
    { name = "Vesprystus", title = "Hippogryph Master", faction = A, map = 1438, zone = "Teldrassil", town = "Rut'theran Village", x = 58.4, y = 94.02 },
    { name = "Bragok", title = "Flight Master", faction = N, map = 1413, zone = "The Barrens", town = "Ratchet", x = 63.08, y = 37.16 },
    { name = "Devrak", title = "Wind Rider Master", faction = H, map = 1413, zone = "The Barrens", town = "The Crossroads", x = 51.5, y = 30.34 },
    { name = "Omusa Thunderhorn", title = "Wind Rider Master", faction = H, map = 1413, zone = "The Barrens", town = "Camp Taurajo", x = 44.45, y = 59.15 },
    { name = "Nyse", title = "Wind Rider Master", faction = H, map = 1441, zone = "Thousand Needles", town = "Freewind Post", x = 45.14, y = 49.11 },
    { name = "Tal", title = "Wind Rider Master", faction = H, map = 1456, zone = "Thunder Bluff", town = "Thunder Bluff", x = 47, y = 49.83 },
    { name = "Gryfe", title = "Flight Master", faction = N, map = 1449, zone = "Un'Goro Crater", town = "Marshal's Refuge", x = 45.23, y = 5.83 },
    { name = "Maethrya", title = "Hippogryph Master", faction = A, map = 1452, zone = "Winterspring", town = "Everlook", x = 62.33, y = 36.61 },
    { name = "Yugrek", title = "Wind Rider Master", faction = H, map = 1452, zone = "Winterspring", town = "Everlook", x = 60.47, y = 36.3 },
    -- New in WoW Forever
    { name = "Fayran Elthas", title = "Flight Master", faction = A, map = 2482, zone = "Mount Hyjal", x = 68.84, y = 43.99, forever = true },
    { name = "Grakna", title = "Wind Rider Master", faction = H, map = 2548, zone = "Riverglades", x = 59.58, y = 45.13, forever = true },
    { name = "Gretchen Mayberry", title = "Gryphon Master", faction = A, map = 2548, zone = "Riverglades", x = 60.62, y = 81.53, forever = true },
}

local function playerFaction()
    return _G.UnitFactionGroup and _G.UnitFactionGroup("player")
end

function F:IsMasterShown(master)
    if not self.db.enabled then return false end
    if self.db.ownFaction and master.faction then
        local faction = playerFaction()
        if faction and master.faction ~= faction then return false end
    end
    return true
end

---------------------------------------------------------------------------
-- Positions
---------------------------------------------------------------------------

local function mapName(id)
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
    return info and info.name
end

-- Find a zone or city map by name under Azeroth, for clients with other map IDs.
local function findMapByName(name)
    if not (C_Map and C_Map.GetMapChildrenInfo) then return end
    local ok, children = pcall(C_Map.GetMapChildrenInfo, 947, nil, true)
    if not ok or not children then return end
    for _, info in ipairs(children) do
        if info.name == name then return info.mapID end
    end
end

local resolved = {} -- built-in map ID -> map ID to use, or false
local function resolveMap(master)
    local r = resolved[master.map]
    if r ~= nil then return r or nil end
    local id = master.map
    local name = mapName(id)
    -- Only second-guess the ID on English clients, where the name can match.
    if name and name ~= master.zone and _G.GetLocale and _G.GetLocale():match("^en") then
        id = findMapByName(master.zone) or id
    elseif not name then
        id = findMapByName(master.zone)
    end
    resolved[master.map] = id or false
    return id
end

-- World position of a flight master: continent ID, and world X (north) / Y (west).
local function worldPos(master)
    if master.world ~= nil then return master.world or nil end
    master.world = false
    local mapID = resolveMap(master)
    if not (mapID and C_Map and C_Map.GetWorldPosFromMapPos and _G.CreateVector2D) then return end
    local v = _G.CreateVector2D(master.x / 100, master.y / 100)
    local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, v)
    if ok and continent and pos then
        local wx, wy = pos:GetXY()
        master.world = { continent = continent, x = wx, y = wy }
    end
    return master.world or nil
end

-- Where a flight master sits on the map `uiMapID`, as 0-1 fractions, or nil.
-- Its own map shows it directly; a parent map (continent, or the zone around a
-- city) places it through the rectangle its map covers there. Maps that don't
-- contain its map have no rectangle, so nothing leaks onto the wrong map.
local function positionOnMap(master, uiMapID)
    local home = resolveMap(master)
    if not home then return end
    if uiMapID == home then return master.x / 100, master.y / 100 end
    if not C_Map.GetMapRectOnMap then return end
    local ok, left, right, top, bottom = pcall(C_Map.GetMapRectOnMap, home, uiMapID)
    if not ok or not left or not right or right <= left or not top or not bottom or bottom <= top then return end
    local x = left + (right - left) * master.x / 100
    local y = top + (bottom - top) * master.y / 100
    if x <= 0 or x >= 1 or y <= 0 or y >= 1 then return end
    return x, y
end

---------------------------------------------------------------------------
-- Pins and tooltips
---------------------------------------------------------------------------

local function showTooltip(pin)
    local m = pin.master
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    local c = colorOf(m)
    GameTooltip:SetText(m.name, c[1], c[2], c[3])
    GameTooltip:AddLine(m.title, 1, 0.82, 0)
    GameTooltip:AddLine(m.town and (m.town .. ", " .. m.zone) or m.zone, 1, 1, 1)
    GameTooltip:AddLine(m.faction or "Neutral: both factions can fly here", c[1], c[2], c[3])
    if m.forever then
        GameTooltip:AddLine("New in WoW Forever. Spot taken from Questie's data, not checked by QoL in game.",
            0.7, 0.7, 0.7, true)
    end
    GameTooltip:Show()
end

local function createPin(parent, size)
    local pin = CreateFrame("Button", nil, parent)
    pin:SetSize(size, size)
    local tex = pin:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture(ICON)
    pin.icon = tex
    pin:SetScript("OnEnter", showTooltip)
    pin:SetScript("OnLeave", GameTooltip_Hide)
    pin:Hide()
    return pin
end

local function setPinMaster(pin, master)
    pin.master = master
    local c = colorOf(master)
    pin.icon:SetVertexColor(c[1], c[2], c[3])
end

---------------------------------------------------------------------------
-- World map
---------------------------------------------------------------------------

function F:GetWorldMapCanvas()
    local wm = _G.WorldMapFrame
    if not wm then return end
    if wm.GetCanvas then return wm:GetCanvas() end
    return wm.ScrollContainer and wm.ScrollContainer.Child
end

function F:AcquireWorldPin(i)
    self.worldPins = self.worldPins or {}
    local pin = self.worldPins[i]
    if not pin then
        pin = createPin(self:GetWorldMapCanvas(), PIN_SIZE)
        self.worldPins[i] = pin
    end
    return pin
end

function F:RefreshWorldMap()
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
        for _, master in ipairs(self.masters) do
            if self:IsMasterShown(master) then
                local x, y = positionOnMap(master, mapID)
                if x then
                    used = used + 1
                    local pin = self:AcquireWorldPin(used)
                    setPinMaster(pin, master)
                    -- Keep the pin the same size on screen however far the map is zoomed.
                    pin:SetScale(1 / scale)
                    pin:ClearAllPoints()
                    pin:SetPoint("CENTER", canvas, "TOPLEFT", x * width * scale, -y * height * scale)
                    pin:SetFrameLevel(canvas:GetFrameLevel() + 1990)
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

function F:HookWorldMap()
    local wm = _G.WorldMapFrame
    if not wm or self.worldMapWatcher then return end
    -- A child of the map runs OnUpdate only while the map is open, and redraws
    -- when the map, its zoom, its size or the settings change.
    local watcher = CreateFrame("Frame", nil, wm)
    local last = {}
    watcher:SetScript("OnUpdate", function()
        local canvas = F:GetWorldMapCanvas()
        if not canvas then return end
        local scale = wm.ScrollContainer and wm.ScrollContainer.GetCanvasScale
            and wm.ScrollContainer:GetCanvasScale() or 1
        local mapID = wm:GetMapID()
        local w = canvas:GetWidth()
        local shown = (F.db.enabled and 1 or 0) + (F.db.ownFaction and 2 or 0)
        if mapID ~= last.mapID or scale ~= last.scale or w ~= last.w or shown ~= last.shown then
            last.mapID, last.scale, last.w, last.shown = mapID, scale, w, shown
            F:RefreshWorldMap()
        end
    end)
    watcher:SetScript("OnHide", function() wipe(last) end)
    QoL:GuardScripts("Flight master pins", watcher, "OnUpdate")
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

function F:CreateMinimapPins()
    self.minimapPins = {}
    for _, master in ipairs(self.masters) do
        local pin = createPin(_G.Minimap, MINIMAP_PIN_SIZE)
        pin:SetFrameLevel(_G.Minimap:GetFrameLevel() + 5)
        setPinMaster(pin, master)
        self.minimapPins[#self.minimapPins + 1] = pin
    end
end

local function hideMinimapPins()
    for _, pin in ipairs(F.minimapPins or {}) do pin:Hide() end
end

function F:UpdateMinimap()
    local minimap = _G.Minimap
    if not (self.minimapPins and self.db.enabled and minimap and minimap:IsVisible() and _G.UnitPosition) then
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
        local w = worldPos(pin.master)
        local shown = false
        if w and w.continent == instance and self:IsMasterShown(pin.master) then
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

function F:OnEnable()
    if not C_Map then return end
    if _G.Minimap then
        self:CreateMinimapPins()
        local driver = CreateFrame("Frame")
        local elapsed = 0
        driver:SetScript("OnUpdate", function(_, dt)
            elapsed = elapsed + dt
            if elapsed < MINIMAP_INTERVAL then return end
            elapsed = 0
            F:UpdateMinimap()
        end)
        QoL:GuardScripts("Flight master pins", driver, "OnUpdate")
        self.minimapDriver = driver
    end
    self:HookWorldMap()
    -- The world map can load on demand; hook it as soon as it appears.
    if not _G.WorldMapFrame then
        local loader = CreateFrame("Frame")
        loader:RegisterEvent("ADDON_LOADED")
        loader:SetScript("OnEvent", function()
            if _G.WorldMapFrame then
                F:HookWorldMap()
                loader:UnregisterAllEvents()
            end
        end)
    end
end

local function refresh()
    F:UpdateMinimap()
    F:RefreshWorldMap()
    if ns.Todo and ns.Todo.RefreshHelpers then ns.Todo:RefreshHelpers() end
end

function F:SetEnabled(on)
    self.db.enabled = on
    refresh()
end

function F:SetOwnFactionOnly(on)
    self.db.ownFaction = on
    refresh()
end

function F:PrintList()
    QoL:Print("flight masters (blue Alliance, red Horde, green both):")
    for _, m in ipairs(self.masters) do
        local c = colorOf(m)
        print(("  |cff%02x%02x%02x%s|r, %s - %s%s (%.1f, %.1f)%s"):format(
            math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255), m.name, m.title,
            m.town and (m.town .. ", ") or "", m.zone, m.x, m.y,
            m.forever and " (Forever)" or ""))
    end
end

function F:PrintDebug()
    local p = function(...) print("  " .. string.format(...)) end
    QoL:Print("flight masters debug")
    p("enabled: %s, own faction only: %s, faction: %s", tostring(self.db.enabled),
        tostring(self.db.ownFaction), tostring(playerFaction()))
    p("C_Map: %s, UnitPosition: %s, WorldMapFrame: %s", tostring(C_Map ~= nil),
        tostring(_G.UnitPosition ~= nil), tostring(_G.WorldMapFrame ~= nil))
    local missing = 0
    for _, m in ipairs(self.masters) do
        local id = resolveMap(m)
        local w = worldPos(m)
        if not id or not w then
            missing = missing + 1
            p("|cffff5555%s|r (%s): map %s, world %s", m.name, m.zone, tostring(id), tostring(w ~= nil))
        end
    end
    p("%d of %d flight masters placed", #self.masters - missing, #self.masters)
    local px, py, instance
    if _G.UnitPosition then
        local _
        px, py, _, instance = _G.UnitPosition("player")
    end
    p("you: continent %s, world %s, %s", tostring(instance), tostring(px), tostring(py))
    p("world map pins shown: %d", self.worldPinCount or 0)
end

function F:OnSlash(args)
    local cmd = (args or ""):lower()
    if cmd == "" or cmd == "on" or cmd == "off" then
        if cmd == "" then
            self:SetEnabled(not self.db.enabled)
        else
            self:SetEnabled(cmd == "on")
        end
        QoL:Print("flight master pins are " .. (self.db.enabled and "on" or "off") .. ".")
    elseif cmd == "mine" then
        self:SetOwnFactionOnly(not self.db.ownFaction)
        QoL:Print(self.db.ownFaction and "showing only your faction's flight masters."
            or "showing every faction's flight masters.")
    elseif cmd == "list" then
        self:PrintList()
    elseif cmd == "debug" then
        self:PrintDebug()
    else
        QoL:Print("unknown command. Type /qol for help.")
    end
end
