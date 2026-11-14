-- Built-in reference tabs: read-only text that ships with the addon.
-- They sit after your own tabs and can't be renamed, deleted or given tasks.
local _, ns = ...
local QoL = ns.QoL
local T = ns.Todo

local SCROLLBAR_SPACE = 24

local function h(text) return "|cffffd100" .. text .. "|r" end
local function p(name) return "|cff88ccff" .. name .. "|r" end

local function tier(skill, name, effect)
    return "  |cffaaaaaa" .. skill .. "|r " .. name .. " - " .. effect
end

local PROFESSIONS = table.concat({
    h("Camp Objects"),
    "Each profession has three camp objects, at skill 20, 140 and 300.",
    "Skill 20 is trained (trainer or the Camping 101 quest). 140 and 300 are blueprints from dungeons and raids.",
    "A higher tier replaces the one below at your camp and keeps its buff, so 140 and 300 add something on top.",
    "",
    p("Alchemy"),
    tier(20, "Mana Well", "mana every 5 sec"),
    tier(140, "Fermenter", "makes some reagents"),
    tier(300, "Alchemy Laboratory", "crafting station for some recipes"),
    p("Blacksmithing"),
    tier(20, "Sharpening Wheel", "Strength"),
    tier(140, "Anvil", "craft Blacksmithing plans at camp"),
    tier(300, "Master Forge", "crafting station for some plans"),
    p("Enchanting"),
    tier(20, "Enchanted Lute", "armor, stats, resistances"),
    tier(140, "Arcane Salvager", "better disenchanting"),
    tier(300, "Arcane Forge", "crafting station for some formulas"),
    p("Engineering"),
    tier(20, "Reagent Bot", "reagent vendor (no buff)"),
    tier(140, "Repair Bot", "vendor that also repairs"),
    tier(300, "Anarchist's Workbench", "crafting station for some schematics"),
    p("First Aid"),
    tier(20, "First Aid Kit", "Stamina"),
    tier(140, "Toxin Study", "healing potions and anti-venom"),
    tier(300, "Plague Doctor's Laboratory", "healing potions and poultices"),
    p("Fishing"),
    tier(20, "Fishing Bowl", "+8% all stats"),
    tier(140, "Fishing Rack", "uncommon fish"),
    tier(300, "Fishing Hut", "rare fish"),
    p("Herbalism"),
    tier(20, "Incense Candle", "Intellect"),
    tier(140, "Greenhouse", "grows herbs from seeds"),
    tier(300, "Seed Hybridizer", "turns seeds into rarer ones"),
    p("Leatherworking"),
    tier(20, "Camp Tent", "rested XP (5% of a level)"),
    tier(140, "Tanning Rack", "makes some leather materials"),
    tier(300, "Sewing Machine", "crafting station for some patterns"),
    p("Mining"),
    tier(20, "Lodestone", "melee attack power"),
    tier(140, "Rock Garden", "spawns an ore node over time"),
    tier(300, "Molten Foundry", "smelting station"),
    p("Skinning"),
    tier(20, "Camp Chair", "+2% crit"),
    tier(140, "Field Guide", "read it to learn Track Beasts"),
    tier(300, "Trapper's Workbench", "holds a trap"),
    p("Tailoring"),
    tier(20, "Faction Banner", "Spirit"),
    tier(140, "Spinning Wheel", "makes some cloth materials"),
    tier(300, "Loom", "crafting station for some patterns"),
    p("Cooking") .. " - no buff object, it builds the campfires:",
    tier(1, "Basic Campfire", "holds 3 objects"),
    tier(90, "Journeyman Campfire", "holds 5 objects"),
    tier(220, "Expert Campfire", "holds 10 objects"),
    tier(140, "Cookie's Feast", "Stamina food"),
    tier(300, "Iron Oven", "crafting station for top recipes"),
    "",
    h("Campfires"),
    "Cooking 1 unlocks a Basic Campfire.",
    "Each player adds one object. Objects share a 1 hour cooldown.",
    "Sit or craft at the camp for a minute to get the buffs.",
    "Camp buffs don't stack with the class buffs they copy, and are a bit weaker (8% stats vs 10% from Kings).",
}, "\n")

T.referenceTabs = {
    { id = "ref:professions", name = "Campfires", text = PROFESSIONS, reference = true, tasks = {} },
}

function T:GetReferenceTab(id)
    for _, tab in ipairs(self.referenceTabs) do
        if tab.id == id then return tab end
    end
end

function T:CreateReferencePanel(parent)
    local scroll = QoL.CreateScrollFrame(parent)
    scroll:SetPoint("TOPLEFT", self.tabStrip, "BOTTOMLEFT", 0, -6)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -SCROLLBAR_SPACE, 4)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)

    local text = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", child, "TOPLEFT", 2, 0)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetSpacing(2)
    scroll.text = text
    scroll:Hide()
    self.refPanel = scroll
end

function T:ShowReference(tab)
    local panel = self.refPanel
    panel.text:SetText(tab.text)
    panel:Show()
    self:LayoutReference()
end

function T:LayoutReference()
    local panel = self.refPanel
    if not panel or not panel:IsShown() then return end
    local width = self:GetContentWidth() - SCROLLBAR_SPACE
    if width <= 0 then return end
    panel:GetScrollChild():SetWidth(width)
    panel.text:SetWidth(width - 4)
    panel:GetScrollChild():SetHeight(math.max(1, panel.text:GetStringHeight() + 8))
end
