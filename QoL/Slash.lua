-- /qol router: "/qol" lists features, "/qol <feature> ..." goes to that module.
local _, ns = ...
local QoL = ns.QoL

local function printHelp()
    QoL:Print("features:")
    for _, key in ipairs(QoL.moduleOrder) do
        local mod = QoL.modules[key]
        print(("  |cffffd100/qol %s|r - %s"):format(key, mod.description or ""))
        for _, line in ipairs(mod.slashHelp or {}) do
            print("    " .. line)
        end
    end
end

SLASH_QOL1 = "/qol"
SlashCmdList.QOL = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "" or cmd == "help" then
        printHelp()
        return
    end
    local mod = QoL.modules[cmd]
    if mod and mod.OnSlash then
        mod:OnSlash(rest)
    else
        QoL:Print(("unknown feature '%s'. Type /qol for the list."):format(cmd))
    end
end
