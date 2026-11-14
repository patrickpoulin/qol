std = "lua51"
max_line_length = false
exclude_files = { ".luacheckrc" }
ignore = {
    "212/self", -- unused self in methods
}

globals = {
    "QoL", "QoLDB", "QoLCharDB",
    "SLASH_QOL1", "SlashCmdList", "StaticPopupDialogs",
}

read_globals = {
    -- Lua / WoW helpers
    "CopyTable", "time", "wipe", "UnitLevel", "C_Map", "Enum",
    -- Frames and UI
    "CreateFrame", "hooksecurefunc", "UIParent", "GameTooltip", "GameTooltip_Hide",
    "StaticPopup_Show", "MenuUtil", "WorldMapFrame", "ToggleWorldMap",
    "UIDropDownMenu_Initialize", "UIDropDownMenu_CreateInfo",
    "UIDropDownMenu_AddButton", "ToggleDropDownMenu",
    -- Items, gear and combat
    "GetInventoryItemID", "GetInventoryItemLink", "GetInventoryItemTexture", "GetInventoryItemCooldown", "GetWeaponEnchantInfo",
    "InCombatLockdown", "C_Timer", "ClearCursor", "PickupInventoryItem", "GetBuildInfo",
    "GetCVar", "SetCVar", "UnitChannelInfo", "ClearOverrideBindings",
    "SetOverrideBinding", "SetOverrideBindingClick",
    "IsAltKeyDown", "IsControlKeyDown", "IsShiftKeyDown",
    -- Units and threat
    "UnitExists", "UnitIsDeadOrGhost", "UnitCanAttack", "UnitName", "UnitAffectingCombat",
    "strjoin", "tostringall",
    -- Global strings
    "ACCEPT", "CANCEL", "YES", "NO",
    -- Mail module
    "SAVE", "UISpecialFrames", "Ambiguate", "issecretvalue",
    "MailFrame", "SendMailFrame", "SendMailNameEditBox", "SendMailSubjectEditBox",
    "CLASS_SORT_ORDER", "LOCALIZED_CLASS_NAMES_MALE", "LOCALIZED_CLASS_NAMES_FEMALE",
    "RAID_CLASS_COLORS", "C_ClassColor",
    "UnitExists", "UnitIsPlayer", "UnitIsUnit", "UnitName", "GetUnitName", "UnitClass", "UnitLevel",
    "IsInGuild", "GuildRoster", "C_GuildInfo", "GetNumGuildMembers", "GetGuildRosterInfo",
    "C_FriendList", "GetNumFriends", "GetFriendInfo",
}
