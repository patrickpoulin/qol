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
    "CopyTable", "time",
    -- Frames and UI
    "CreateFrame", "UIParent", "GameTooltip", "GameTooltip_Hide",
    "StaticPopup_Show", "MenuUtil",
    "UIDropDownMenu_Initialize", "UIDropDownMenu_CreateInfo",
    "UIDropDownMenu_AddButton", "ToggleDropDownMenu",
    -- Items, gear and combat
    "GetInventoryItemID", "GetInventoryItemLink", "GetWeaponEnchantInfo",
    "InCombatLockdown", "C_Timer", "ClearCursor", "PickupInventoryItem", "GetBuildInfo",
    "GetCVar", "SetCVar", "UnitChannelInfo", "ClearOverrideBindings",
    "SetOverrideBinding", "SetOverrideBindingClick",
    "IsAltKeyDown", "IsControlKeyDown", "IsShiftKeyDown",
    -- Units and threat
    "UnitExists", "UnitIsDeadOrGhost", "UnitCanAttack", "UnitName", "UnitAffectingCombat",
    "strjoin", "tostringall",
    -- Global strings
    "ACCEPT", "CANCEL", "YES", "NO",
}
