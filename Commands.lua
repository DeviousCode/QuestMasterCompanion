local QMC = _G.QuestMasterCompanion
if not QMC then return end

local U = QMC.Util

local function HandleSlashCommand(input)
    input = tostring(input or "")
    local command, rest = input:match("^%s*(%S*)%s*(.-)%s*$")
    command = string.lower(command or "")

    if command == "" or command == "status" then
        QMC:Status()
    elseif command == "on" or command == "enable" then
        QMC:Saved().enabled = true
        if QMC:InstallPatches() then U.Print("enabled") else U.Print("nothing installed; try /qmc status") end
    elseif command == "off" or command == "disable" then
        QMC:Saved().enabled = false
        QMC:RestoreWorldObjectAssist("manual")
        QMC:RestoreWorldMarkerOpacity("manual")
        QMC:RestoreGuideTasks("manual")
        QMC:RestoreRouteLibraryRemove("manual")
        QMC:RestoreRouteEventNavigation("manual")
        QMC:RestoreRouteWaypointSync("manual")
        QMC:RestoreRouteAcceptLocation("manual")
        QMC:RestoreRouteRuntimeSync("manual")
        QMC:RestoreRouteImportFix("manual")
        QMC:RestoreTurnInPriority("manual")
        QMC:RestoreObjectivePriority("manual")
        U.Print("disabled")
    elseif command == "test" then
        QMC:TestQuest(rest)
    elseif command == "object" or command == "objects" then
        local sub = string.lower((rest or ""):match("^%s*(%S*)") or "")
        if sub == "on" or sub == "enable" then
            QMC:SetWorldObjectAssistEnabled(true, "command")
        elseif sub == "off" or sub == "disable" then
            QMC:SetWorldObjectAssistEnabled(false, "command")
        elseif sub == "ignore" then
            QMC:WorldObjectAssistIgnoreCurrent()
        elseif sub == "allow" then
            QMC:WorldObjectAssistAllowCurrent()
        elseif sub == "clear" then
            QMC:WorldObjectAssistClearCurrent()
        elseif sub == "debug" or sub == "status" then
            QMC:WorldObjectAssistDebugCurrent()
        elseif sub == "reset" then
            QMC:ResetWorldObjectAssistAppearance("command")
        elseif sub == "list" then
            local saved = QMC:Saved()
            local ignored, allowed = {}, {}
            for id, name in pairs(saved.worldObjectAssistIgnoreIds or {}) do ignored[#ignored + 1] = tostring(name) .. " [" .. tostring(id) .. "]" end
            for id, name in pairs(saved.worldObjectAssistAllowIds or {}) do allowed[#allowed + 1] = tostring(name) .. " [" .. tostring(id) .. "]" end
            table.sort(ignored); table.sort(allowed)
            U.Print("object filters | ignored " .. tostring(#ignored) .. " | forced allow " .. tostring(#allowed))
            for i = 1, math.min(#ignored, 12) do U.Print("ignore: " .. ignored[i]) end
            for i = 1, math.min(#allowed, 12) do U.Print("allow: " .. allowed[i]) end
            if #ignored > 12 or #allowed > 12 then U.Print("object filters: list shortened in chat") end
        else
            U.Print("usage: /qmc object on|off|ignore|allow|clear|debug|list|reset")
        end
    elseif command == "notify" then
        local value = string.lower(rest or "")
        if value == "on" then
            QMC:Saved().notifications = true
            U.Print("notifications on")
        elseif value == "off" then
            QMC:Saved().notifications = false
            U.Print("notifications off")
        else
            U.Print("usage: /qmc notify on|off")
        end
    else
        U.Print("commands: /qmc status | on | off | test <questID> | object on|off|ignore|allow|clear|debug|list|reset | notify on|off")
    end
end

SLASH_QUESTMASTERCOMPANION1 = "/qmc"
SLASH_QUESTMASTERCOMPANION2 = "/qmcompanion"
SlashCmdList["QUESTMASTERCOMPANION"] = HandleSlashCommand

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == QMC.ADDON_NAME then
        QMC:Saved()
        QMC:InstallPatches()
    elseif event == "PLAYER_LOGIN" and QMC:Saved().enabled then
        QMC:InstallPatches()
    end
end)
