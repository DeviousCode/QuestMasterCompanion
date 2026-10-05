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
        if QMC:InstallPatches() then
            U.Print("enabled")
        else
            U.Print("nothing patched; try /qmc status")
        end
    elseif command == "off" or command == "disable" then
        QMC:Saved().enabled = false
        -- The guide assist sits outside the persistence wrapper, so it comes off first.
        QMC:RestoreGuideAssist("manual")
        QMC:RestoreTracker("manual")
        QMC:RestoreGuide("manual")
        QMC:RestoreTurnInDatabaseBridge("manual")
        QMC:RestoreTurnIn("manual")
        QMC:RestoreObjective("manual")
        U.Print("disabled")
    elseif command == "test" then
        QMC:TestQuest(rest)
    elseif command == "refresh" then
        if QMC:RequestGuideAssistRefresh("manual refresh") then
            U.Print("guide pickup scan queued")
        else
            U.Print("guide pickup scan not available")
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
        U.Print("commands: /qmc status | on | off | refresh | test <questID> | notify on|off")
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
    elseif event == "PLAYER_LOGIN" then
        if QMC:Saved().enabled then
            -- Everything is idempotent, and doing it in the same order keeps the
            -- two Guide layers stacked the same way after login or /qmc on.
            QMC:InstallPatches()
        end
    end
end)
