-- Zone levels: a "Zone Levels" button on the world map that opens a list of
-- questing zones with their suggested levels. Click a zone to show it on the map.
local _, ns = ...
local QoL = ns.QoL

local Z = QoL:RegisterModule("zones", {
    name = "Zone Levels",
    description = "questing zone level list on the world map",
    -- Factions whose zones are hidden from the list, e.g. { Alliance = true }.
    charDefaults = { hidden = {} },
    slashHelp = {
        "/qol zones - open the world map with the zone level list",
    },
})

local H, A, C = "Horde", "Alliance", "Contested"

-- { name, min, max, faction, note }. min/max nil = level not known yet.
Z.continents = {
    { name = "Eastern Kingdoms", zones = {
        { "Elwynn Forest", 1, 10, A },
        { "Dun Morogh", 1, 10, A },
        { "Tirisfal Glades", 1, 10, H },
        { "Westfall", 10, 20, A },
        { "Loch Modan", 10, 20, A },
        { "Silverpine Forest", 10, 20, H },
        { "Redridge Mountains", 15, 25, A },
        { "Duskwood", 18, 30, A },
        { "Wetlands", 20, 30, A },
        { "Hillsbrad Foothills", 20, 30, C },
        { "Alterac Mountains", 30, 40, C },
        { "Arathi Highlands", 30, 40, C },
        { "Stranglethorn Vale", 30, 45, C },
        { "Riverglades", 35, 45, C, "New in Forever" },
        { "Badlands", 35, 45, C },
        { "Swamp of Sorrows", 35, 45, C },
        { "The Hinterlands", 40, 50, C },
        { "Searing Gorge", 43, 50, C },
        { "Blasted Lands", 45, 55, C },
        { "Burning Steppes", 50, 58, C },
        { "Western Plaguelands", 51, 58, C },
        { "Eastern Plaguelands", 53, 60, C },
    } },
    { name = "Kalimdor", zones = {
        { "Teldrassil", 1, 10, A },
        { "Durotar", 1, 10, H },
        { "Mulgore", 1, 10, H },
        { "Darkshore", 10, 20, A },
        { "The Barrens", 10, 25, H },
        { "Stonetalon Mountains", 15, 27, C },
        { "Ashenvale", 18, 30, C },
        { "Thousand Needles", 25, 35, C },
        { "Desolace", 30, 40, C },
        { "Shen'dralas", nil, nil, C, "New in Forever, level not confirmed (guess 30s-40s)" },
        { "Dustwallow Marsh", 35, 45, C },
        { "Feralas", 40, 50, C },
        { "Tanaris", 40, 50, C },
        { "Azshara", 45, 55, C },
        { "Felwood", 48, 55, C },
        { "Un'Goro Crater", 48, 55, C },
        { "Winterspring", 53, 60, C },
        { "Silithus", 55, 60, C },
        { "Mount Hyjal", 60, 60, C, "New in Forever, endgame (level not official)" },
    } },
    { name = "Skywall", zones = {
        { "Zephras Isle", 1, 12, C, "Skyborne starting zone (both factions)" },
    } },
}

local FACTION_COLOR = {
    [H] = "|cffff5555",
    [A] = "|cff55aaff",
    [C] = "|cffffd100",
}

local ROW_HEIGHT, PANEL_WIDTH, PANEL_HEIGHT = 16, 250, 420

local function levelText(zone)
    local lo, hi = zone[2], zone[3]
    if not lo then return "?" end
    if lo == hi then return tostring(lo) end
    return lo .. "-" .. hi
end

-- Green if you're in the range, grey if you've outlevelled it, red if it's above you.
local function levelColor(zone)
    local lo, hi = zone[2], zone[3]
    if not lo then return "|cffaaaaaa" end
    local level = UnitLevel("player") or 1
    if level < lo then return "|cffff6060" end
    if level > hi then return "|cff909090" end
    return "|cff40ff40"
end

-- Zone name -> uiMapID, built once by walking the client's map list.
function Z:FindMapID(name)
    if not self.mapIDs then
        self.mapIDs = {}
        if C_Map and C_Map.GetMapInfo then
            local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
            for id = 1, 3000 do
                local info = C_Map.GetMapInfo(id)
                if info and info.name and info.mapType == zoneType and not self.mapIDs[info.name] then
                    self.mapIDs[info.name] = id
                end
            end
        end
    end
    return self.mapIDs[name]
end

function Z:ShowZone(zone)
    local id = self:FindMapID(zone[1])
    if id then
        WorldMapFrame:SetMapID(id)
    else
        QoL:Print(("%s isn't on the map yet."):format(zone[1]))
    end
end

local function onRowEnter(row)
    local zone = row.zone
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(zone[1])
    GameTooltip:AddLine(("Level %s, %s"):format(levelText(zone), zone[4]), 1, 1, 1)
    if zone[5] then GameTooltip:AddLine(zone[5], 0.6, 0.8, 1, true) end
    GameTooltip:AddLine("Click to show it on the map.", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

function Z:CreatePanel()
    local map = WorldMapFrame
    local anchor = map.ScrollContainer or map

    local button = CreateFrame("Button", nil, map, "UIPanelButtonTemplate")
    button:SetSize(100, 22)
    button:SetText("Zone Levels")
    button:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -8, -8)
    button:SetFrameLevel(anchor:GetFrameLevel() + 100)
    button:SetScript("OnClick", function() self.panel:SetShown(not self.panel:IsShown()) end)
    self.button = button

    local panel = CreateFrame("Frame", nil, map, "BackdropTemplate")
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    panel:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -4)
    panel:SetFrameLevel(button:GetFrameLevel())
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    panel:SetBackdropColor(0, 0, 0, 0.85)
    panel:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
    panel:EnableMouse(true)
    panel:Hide()
    self.panel = panel

    -- Faction filters: click one to hide or show its zones.
    self.filters = {}
    local prev
    for _, faction in ipairs({ H, A, C }) do
        local f = CreateFrame("Button", nil, panel)
        f:SetHeight(16)
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.text:SetPoint("LEFT")
        f.faction = faction
        if prev then
            f:SetPoint("LEFT", prev, "RIGHT", 10, 0)
        else
            f:SetPoint("TOPLEFT", 8, -4)
        end
        f:SetScript("OnClick", function()
            local hidden = self.charDB.hidden
            hidden[faction] = not hidden[faction] or nil
            self:RefreshRows()
        end)
        f:SetScript("OnEnter", function(btn)
            GameTooltip:SetOwner(btn, "ANCHOR_TOP")
            GameTooltip:SetText(("Click to %s %s zones"):format(
                self.charDB.hidden[faction] and "show" or "hide", faction))
            GameTooltip:Show()
        end)
        f:SetScript("OnLeave", GameTooltip_Hide)
        table.insert(self.filters, f)
        prev = f
    end

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -22)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(PANEL_WIDTH - 32)
    scroll:SetScrollChild(child)

    self.child = child
    self.rows, self.headers = {}, {}
    for _, continent in ipairs(self.continents) do
        local header = child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetText(continent.name)
        header.rows = {}
        table.insert(self.headers, header)
        for _, zone in ipairs(continent.zones) do
            local row = CreateFrame("Button", nil, child)
            row:SetHeight(ROW_HEIGHT)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.name:SetPoint("LEFT", 6, 0)
            row.level = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.level:SetPoint("RIGHT", -4, 0)
            row.zone = zone
            row:SetScript("OnClick", function() self:ShowZone(zone) end)
            row:SetScript("OnEnter", onRowEnter)
            row:SetScript("OnLeave", GameTooltip_Hide)
            table.insert(self.rows, row)
            table.insert(header.rows, row)
        end
    end

    panel:SetScript("OnShow", function() self:RefreshRows() end)
end

-- Level colours depend on your level, so redraw each time the list opens.
-- Also lays out the list, skipping zones of hidden factions.
function Z:RefreshRows()
    local hidden = self.charDB.hidden
    for _, f in ipairs(self.filters) do
        local color = hidden[f.faction] and "|cff606060" or FACTION_COLOR[f.faction]
        f.text:SetText(color .. f.faction .. "|r")
        f:SetWidth(f.text:GetStringWidth())
    end

    local child, y = self.child, 0
    for _, header in ipairs(self.headers) do
        local any = false
        for _, row in ipairs(header.rows) do
            if not hidden[row.zone[4]] then any = true end
        end
        header:SetShown(any)
        if any then
            header:SetPoint("TOPLEFT", child, "TOPLEFT", 2, -y - 2)
            y = y + ROW_HEIGHT + 4
            for _, row in ipairs(header.rows) do
                local show = not hidden[row.zone[4]]
                row:SetShown(show)
                if show then
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
                    row:SetPoint("RIGHT", child, "RIGHT")
                    y = y + ROW_HEIGHT
                end
            end
            y = y + 6
        else
            for _, row in ipairs(header.rows) do row:Hide() end
        end
    end
    child:SetHeight(math.max(1, y))

    for _, row in ipairs(self.rows) do
        local zone = row.zone
        local star = zone[5] and " |cff88ccff*|r" or ""
        row.name:SetText(FACTION_COLOR[zone[4]] .. zone[1] .. "|r" .. star)
        row.level:SetText(levelColor(zone) .. levelText(zone) .. "|r")
    end
end

function Z:OnEnable()
    if WorldMapFrame then return self:CreatePanel() end
    -- The world map can load on demand; build the button once it appears.
    local loader = CreateFrame("Frame")
    loader:RegisterEvent("ADDON_LOADED")
    loader:SetScript("OnEvent", function()
        if WorldMapFrame then
            loader:UnregisterAllEvents()
            self:CreatePanel()
        end
    end)
end

function Z:OnSlash()
    if not self.panel then return QoL:Print("the world map isn't available.") end
    if not WorldMapFrame:IsShown() then
        if ToggleWorldMap then ToggleWorldMap() else WorldMapFrame:Show() end
    end
    self.panel:Show()
end
