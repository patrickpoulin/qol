-- Spell efficiency: add "Damage per mana" and "Healing per mana" lines to
-- spell tooltips (spellbook, action bars, chat links).
--
-- It reads both numbers from the tooltip the game already shows, so it uses
-- exactly what the player sees: the mana cost line ("345 Mana") and the
-- description ("causes 561 to 715 Fire damage and an additional 72 Fire
-- damage over 8 sec"). A range counts as its average, a damage-over-time or
-- heal-over-time counts in full, and "X each second for N sec" or "X every
-- 2 sec for 10 sec" count every tick. Spells with no mana cost, or no damage
-- or healing number in their text, get no line.
--
-- The numbers are the tooltip's base numbers: the classic tooltip doesn't
-- add spell power, so neither does this.
local _, ns = ...
local QoL = ns.QoL

local S = QoL:RegisterModule("dpm", {
    name = "Damage per mana",
    description = "show damage and healing per mana on spell tooltips",
    defaults = {
        enabled = true,
    },
    slashHelp = {
        "/qol dpm - turn damage/healing per mana on spell tooltips on or off (or /qol dpm on / off)",
        "/qol dpm debug - print what QoL read from the last spell you hovered",
    },
})
ns.SpellEfficiency = S

local COLOR = { 0.45, 0.8, 1 }        -- light blue, like the game's own "use" text
local DETAIL_COLOR = "|cff9d9d9d"     -- grey for the totals after the number

-- "345 Mana" as a Lua pattern, built from the client's own string so it
-- follows the game's wording.
local function costPattern()
    local fmt = _G.MANA_COST or "%d Mana"
    local escaped = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    escaped = escaped:gsub("%%d", "([%%d,]+)"):gsub("%%s", "([%%d,]+)")
    return "^" .. escaped .. "$"
end
local COST_PATTERN

local function toNumber(text)
    if not text then return nil end
    return tonumber((text:gsub(",", "")))
end

-- Mana cost from the tooltip, or from the spell API if the line isn't there.
local function manaCost(lines, spellID)
    COST_PATTERN = COST_PATTERN or costPattern()
    for _, text in ipairs(lines) do
        local cost = toNumber(text:match(COST_PATTERN))
        if cost then return cost end
    end
    local getCost = _G.GetSpellPowerCost or (_G.C_Spell and _G.C_Spell.GetSpellPowerCost)
    if spellID and getCost then
        local ok, costs = pcall(getCost, spellID)
        if ok and type(costs) == "table" then
            for _, c in ipairs(costs) do
                if c.type == 0 and (c.cost or 0) > 0 then return c.cost end
            end
        end
    end
    return nil
end

-- Words after a number that mean it isn't an amount of damage or healing.
local NOT_AMOUNT = {
    sec = true, secs = true, second = true, seconds = true, min = true, mins = true,
    minute = true, minutes = true, hour = true, hours = true,
    yd = true, yds = true, yard = true, yards = true,
    target = true, targets = true, enemy = true, enemies = true, member = true, members = true,
    time = true, times = true, charge = true, charges = true, stack = true, stacks = true,
    mana = true, rage = true, energy = true, level = true, levels = true, rank = true,
    attack = true, attacks = true, additional = true,
}
-- Words before a number that mean the same.
local NOT_AMOUNT_BEFORE = { by = true, level = true, rank = true }

-- "561 to 715" becomes its average, "638".
local function averageRanges(text)
    return (text:gsub("([%d%.]+) to ([%d%.]+)", function(a, b)
        return tostring(((tonumber(a) or 0) + (tonumber(b) or 0)) / 2)
    end))
end

-- How many times a clause's amount lands: "each second for 3 sec" is 3,
-- "every 2 seconds for 10 sec" is 5, anything else (including "over 8 sec",
-- where the number is already the total) is 1.
local function tickCount(clause)
    local each = tonumber(clause:match("each second for ([%d%.]+) sec"))
    if each then return each end
    local every, over = clause:match("every ([%d%.]+) sec%a* for ([%d%.]+) sec")
    every, over = tonumber(every), tonumber(over)
    if every and over and every > 0 then return over / every end
    return 1
end

-- Words that can sit between a number and "damage" in "15 additional
-- Arcane damage" (at most two of them); any other word means the number
-- isn't the damage.
local DAMAGE_WORDS = {
    additional = true, extra = true, bonus = true, ranged = true, melee = true, physical = true,
    weapon = true, arcane = true, fire = true, frost = true, nature = true, shadow = true,
    holy = true, chaos = true,
}

-- Flat damage in a damage clause. Returns the total and whether it is a
-- bonus on top of the weapon hit ("an additional 80 damage", "increases
-- ranged damage by 70", "weapon damage plus 45"), which hunter shots and
-- similar attacks use. Percent-of-weapon damage has no flat number and adds 0.
local function damageAmount(clause, hasEarlier)
    clause = averageRanges(clause)
    local total, bonus = 0, false
    local pos = 1
    while true do
        local s, e, num = clause:find("(%d+%.?%d*)", pos)
        if not s then break end
        pos = e + 1
        local value = tonumber(num) or 0
        local before = clause:sub(1, s - 1)
        local after = clause:sub(e + 1)
        local counted = false
        -- "<n> [word [word]] damage"
        local w1, w2 = after:match("^%s+(%a+)%s+(%a+)%s+damage")
        local w = after:match("^%s+(%a+)%s+damage")
        if after:match("^%s+damage") then
            counted = true
        elseif w and (DAMAGE_WORDS[w] or not NOT_AMOUNT[w]) and w ~= "of" then
            counted = true
            if w == "additional" or w == "extra" or w == "bonus" then bonus = bonus or not hasEarlier end
        elseif w1 and DAMAGE_WORDS[w1] and DAMAGE_WORDS[w2] then
            counted = true
            if w1 == "additional" or w1 == "extra" or w1 == "bonus" then bonus = bonus or not hasEarlier end
        end
        if counted and before:match("additional%s*$") then bonus = bonus or not hasEarlier end
        -- "increases ranged damage by 70", "weapon damage plus 45"
        if not counted and not after:match("^%s*%%") then
            if before:match("increases? [%a ]-damage by%s*$") and not before:match("taken") then
                counted, bonus = true, true
            elseif before:match("damage plus%s*$") then
                counted, bonus = true, true
            end
        end
        if counted then
            total = total + value
            hasEarlier = hasEarlier or value > 0
        end
    end
    return total * tickCount(clause), bonus
end

-- Sum of the healing (or inherited damage) amounts in a clause: every
-- number that isn't a time, distance, %, count or level.
local function clauseAmount(clause)
    clause = averageRanges(clause)
    local total = 0
    local pos = 1
    while true do
        local s, e, num = clause:find("(%d+%.?%d*)", pos)
        if not s then break end
        pos = e + 1
        local before = clause:sub(1, s - 1):match("(%a+)%s*$")
        local after = clause:sub(e + 1)
        local nextWord = after:match("^%s*(%a+)")
        local skip = after:match("^%s*%%") or (nextWord and NOT_AMOUNT[nextWord])
            or (before and NOT_AMOUNT_BEFORE[before])
        if not skip then total = total + (tonumber(num) or 0) end
    end
    return total * tickCount(clause)
end

-- What a clause is about: "damage", "heal", "none" (a shield) or nil (no keyword).
local function clauseKind(clause)
    if clause:find("absorb") then return "none" end
    if clause:find("heal") then return "heal" end
    if clause:find("damage") then return "damage" end
    return nil
end

-- Total damage and healing in a spell's tooltip text (one line per "\n"),
-- and whether the damage is a bonus on top of a weapon hit.
function S.ParseAmounts(text)
    text = text:lower():gsub("\n", "|"):gsub("%.%s", "|"):gsub("%.$", "")
    local damage, heal, bonus = 0, 0, false
    -- Sentences end at ". " (not "1.5") and at line breaks.
    for sentence in text:gmatch("[^|]+") do
        -- "Heals for 93 to 107 and another 98 over 21 sec": the second half
        -- has no keyword of its own, so it keeps the first half's kind.
        local kind
        sentence = sentence:gsub(" and ", "|"):gsub(", then ", "|")
        for clause in sentence:gmatch("[^|]+") do
            local own = clauseKind(clause)
            kind = own or kind
            if kind == "damage" and own == "damage" then
                local amount, isBonus = damageAmount(clause, damage > 0)
                damage = damage + amount
                bonus = bonus or isBonus
            elseif kind == "damage" then
                damage = damage + clauseAmount(clause)
            elseif kind == "heal" then
                heal = heal + clauseAmount(clause)
            end
        end
    end
    return damage, heal, bonus
end

-- The left-hand text of every line of a tooltip.
local function tooltipLines(tooltip)
    local lines = {}
    local name = tooltip.GetName and tooltip:GetName()
    if not name then return lines end
    for i = 1, tooltip:NumLines() do
        local fs = _G[name .. "TextLeft" .. i]
        local text = fs and fs:GetText()
        if text and text ~= "" then table.insert(lines, text) end
    end
    return lines
end

local function format(value)
    if value >= 10 then return ("%.1f"):format(value) end
    return ("%.2f"):format(value)
end

local function addLine(tooltip, label, amount, cost)
    tooltip:AddLine(("%s: %s  %s(%s / %d mana)|r"):format(label, format(amount / cost),
        DETAIL_COLOR, format(amount):gsub("%.0+$", ""), cost), COLOR[1], COLOR[2], COLOR[3])
end

local hooked = {}

-- Forget a tooltip's line once the game clears it for the next thing shown.
local function hookCleared(tooltip)
    if hooked[tooltip] or not tooltip.HookScript then return end
    hooked[tooltip] = true
    tooltip:HookScript("OnTooltipCleared", function(t) t.qolDpmDone = nil end)
end

local function onSpell(tooltip)
    hookCleared(tooltip)
    if not S.db.enabled or tooltip.qolDpmDone then return end
    if not (tooltip.NumLines and tooltip.AddLine) then return end
    local spellID
    if tooltip.GetSpell then
        local _, a, b = tooltip:GetSpell()
        spellID = type(b) == "number" and b or (type(a) == "number" and a or nil)
    end
    local lines = tooltipLines(tooltip)
    if #lines < 2 then return end
    local cost = manaCost(lines, spellID)
    -- Line 1 is the spell name; the rest holds cost, cast time and the description.
    local damage, heal, bonus = S.ParseAmounts(table.concat(lines, "\n", 2))
    S.last = { lines = lines, cost = cost, damage = damage, heal = heal, bonus = bonus }
    if not cost or cost <= 0 then return end
    if damage <= 0 and heal <= 0 then return end
    tooltip.qolDpmDone = true
    if damage > 0 then
        -- A weapon attack's bonus is only part of its damage, so say so.
        addLine(tooltip, bonus and "Bonus damage per mana" or "Damage per mana", damage, cost)
    end
    if heal > 0 then addLine(tooltip, "Healing per mana", heal, cost) end
    tooltip:Show() -- resize to fit the new lines
end

local TOOLTIPS = { "GameTooltip", "ItemRefTooltip" }

function S:OnEnable()
    local handler = QoL:Guard("Damage per mana", onSpell)
    for _, name in ipairs(TOOLTIPS) do
        local tooltip = _G[name]
        if tooltip and tooltip.HasScript and tooltip:HasScript("OnTooltipSetSpell") then
            tooltip:HookScript("OnTooltipSetSpell", handler)
        end
    end
    -- Newer clients build tooltips from data and dropped OnTooltipSetSpell.
    local processor, Enum = _G.TooltipDataProcessor, _G.Enum
    if processor and processor.AddTooltipPostCall and Enum and Enum.TooltipDataType
        and Enum.TooltipDataType.Spell then
        processor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip)
            if type(tooltip) == "table" then handler(tooltip) end
        end)
    end
end

function S:SetEnabled(on)
    self.db.enabled = on and true or false
    if ns.Todo and ns.Todo.RefreshHelpers then ns.Todo:RefreshHelpers() end
end

function S:OnSlash(args)
    local cmd = (args or ""):lower()
    if cmd == "" then
        self:SetEnabled(not self.db.enabled)
    elseif cmd == "on" or cmd == "off" then
        self:SetEnabled(cmd == "on")
    elseif cmd == "debug" then
        local last = self.last
        if not last then
            QoL:Print("hover a spell first, then type /qol dpm debug.")
            return
        end
        QoL:Print(("last spell tooltip: mana %s, damage %s%s, healing %s"):format(tostring(last.cost),
            tostring(last.damage), last.bonus and " (bonus)" or "", tostring(last.heal)))
        for i, text in ipairs(last.lines) do print(("  %d: %s"):format(i, text)) end
        return
    else
        QoL:Print("unknown command. Type /qol for help.")
        return
    end
    QoL:Print("damage and healing per mana on spell tooltips is " .. (self.db.enabled and "on" or "off") .. ".")
end
