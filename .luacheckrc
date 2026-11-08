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
    "CopyTable", "time", "UnitLevel", "C_Map", "Enum",
    -- Frames and UI
    "CreateFrame", "UIParent", "GameTooltip", "GameTooltip_Hide",
    "StaticPopup_Show", "MenuUtil", "WorldMapFrame", "ToggleWorldMap",
    "UIDropDownMenu_Initialize", "UIDropDownMenu_CreateInfo",
    "UIDropDownMenu_AddButton", "ToggleDropDownMenu",
    -- Global strings
    "ACCEPT", "CANCEL", "YES", "NO",
}
