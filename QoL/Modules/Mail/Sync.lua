-- Keeps contacts' class and level current from what the game already knows:
-- your own characters, the guild roster, online friends, and your target or mouseover.
-- Only updates people who are already contacts; never adds anyone.
local _, ns = ...
local QoL = ns.QoL
local M = ns.Mail

-- Newer clients can hide unit details behind "secret" values; skip those.
local function usable(v)
    if v == nil then return false end
    if issecretvalue and issecretvalue(v) then return false end
    return true
end

local function readUnit(unit)
    if not UnitExists(unit) or not UnitIsPlayer(unit) then return end
    local name = GetUnitName and GetUnitName(unit, true) or UnitName(unit)
    local _, class = UnitClass(unit)
    local level = UnitLevel(unit)
    if not usable(name) then return end
    M:Learn(name, usable(class) and class or nil, usable(level) and level or nil)
end

-- Unit details can be restricted in some situations; never let that raise an error.
local function learnUnit(unit)
    pcall(readUnit, unit)
end

local function learnGuild()
    if not GetNumGuildMembers or not GetGuildRosterInfo then return end
    for i = 1, GetNumGuildMembers() do
        local name, _, _, level, _, _, _, _, _, _, class = GetGuildRosterInfo(i)
        if name then M:Learn(name, class, level) end
    end
end

local function learnFriends()
    if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
        for i = 1, C_FriendList.GetNumFriends() do
            local info = C_FriendList.GetFriendInfoByIndex(i)
            if info and info.name and info.connected then
                M:Learn(info.name, M.ClassToken(info.className), info.level)
            end
        end
    elseif GetNumFriends and GetFriendInfo then
        for i = 1, GetNumFriends() do
            local name, level, class, _, connected = GetFriendInfo(i)
            if name and connected then M:Learn(name, M.ClassToken(class), level) end
        end
    end
end

-- Called when a contact is first added, so known details fill in straight away.
function M:LearnFromGame(name)
    local key = M.KeyFor(name)
    pcall(function()
        if not UnitExists("target") or not UnitIsPlayer("target") then return end
        local target = GetUnitName and GetUnitName("target", true) or UnitName("target")
        if usable(target) and M.KeyFor(target) == key then readUnit("target") end
    end)
    learnGuild()
    learnFriends()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
events:RegisterEvent("GUILD_ROSTER_UPDATE")
events:RegisterEvent("FRIENDLIST_UPDATE")
events:SetScript("OnEvent", function(_, event, arg1)
    if not M.db then return end
    if event == "PLAYER_LOGIN" then
        learnUnit("player")
    elseif event == "PLAYER_LEVEL_UP" then
        local _, class = UnitClass("player")
        M:Learn(UnitName("player"), class, arg1)
    elseif event == "PLAYER_TARGET_CHANGED" then
        learnUnit("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        learnUnit("mouseover")
    elseif event == "GUILD_ROSTER_UPDATE" then
        learnGuild()
    elseif event == "FRIENDLIST_UPDATE" then
        learnFriends()
    end
end)

-- Ask the server for a fresh guild roster (the answer arrives as GUILD_ROSTER_UPDATE).
function M:RequestGuildRoster()
    if not (IsInGuild and IsInGuild()) then return end
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()
    end
end

QoL:GuardScripts("Mail contacts", events, "OnEvent")
