-- Built-in reference tabs: read-only text that ships with the addon.
-- They sit after your own tabs and can't be renamed, deleted or given tasks.
local _, ns = ...
local T = ns.Todo

local SCROLLBAR_SPACE = 24

local function h(text) return "|cffffd100" .. text .. "|r" end
local function p(name) return "|cff88ccff" .. name .. "|r" end

local PROFESSIONS = table.concat({
    h("Professions"),
    "2 primary professions, plus all 3 secondary: Cooking, First Aid and Fishing.",
    "Skill cap 300: Apprentice, Journeyman, Expert, Artisan.",
    "No passive bonuses. Professions pay off through the camp buff each one adds.",
    "",
    h("Campfires"),
    "Cooking 1 unlocks a Basic Campfire.",
    "Each player adds one object from their profession.",
    "A Basic Campfire holds 3 objects; upgraded Cooking fires hold 5 or 10.",
    "Sit or craft at the camp for 1 minute to get every buff for 1 hour.",
    "Camp buffs don't stack with the class buffs they copy, and are a bit weaker (8% stats vs 10% from Kings).",
    "",
    h("Camp objects"),
    p("First Aid") .. " - First Aid Kit: Stamina",
    p("Fishing") .. " - Fishing Bowl: +8% all stats",
    p("Alchemy") .. " - Mana Well: mana every 5 sec",
    p("Blacksmithing") .. " - Sharpening Wheel: Strength (one source says AP)",
    p("Enchanting") .. " - Enchanted Lute: armor, stats, resistances",
    p("Herbalism") .. " - Incense Candle: Intellect",
    p("Leatherworking") .. " - Camp Tent: rested XP (5% of a level)",
    p("Skinning") .. " - Camp Chair: +2% crit",
    p("Tailoring") .. " - Faction Banner: Spirit",
    p("Engineering") .. " - Reagent Bot: reagent vendor",
    p("Mining") .. " - no camp object listed",
    "",
    "First camp items come at skill 20. Better versions (skill 140+) drop as blueprints in dungeons and raids.",
    "",
    "|cff888888Sources: Blizzard, Warcraft Tavern, Timesaver (Nov 2026).|r",
}, "\n")

T.referenceTabs = {
    { id = "ref:professions", name = "Professions", text = PROFESSIONS, reference = true, tasks = {} },
}

function T:GetReferenceTab(id)
    for _, tab in ipairs(self.referenceTabs) do
        if tab.id == id then return tab end
    end
end

function T:CreateReferencePanel(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
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
