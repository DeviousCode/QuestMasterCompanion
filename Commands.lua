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
        QMC:RestoreObjective("manual")
        QMC:RestoreTurnIn("manual")
        QMC:RestoreGuide("manual")
        QMC:RestoreTracker("manual")
        U.Print("disabled")
    elseif command == "test" then
        QMC:TestQuest(rest)
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
        U.Print("commands: /qmc status | on | off | test <questID> | notify on|off")
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
            local QM = _G.QuestMaster
            if QM then
                if QMC.objectiveState ~= "upstream-fixed"
                    and not (QMC.objectiveWrapper and QM.GetQuestObjectiveLocationsFixed == QMC.objectiveWrapper) then
                    QMC:InstallObjectivePatch()
                end
                if QMC.turnInState ~= "upstream-fixed"
                    and not (QMC.turnInWrapper and QM.GetQuestTurnInLocation == QMC.turnInWrapper) then
                    QMC:InstallTurnInPatch()
                end
                if not (QMC.guideRebuildWrapper and QMC.guideWaypointWrapper and QMC.guideAutoSelectWrapper
                    and QM.Guide and QM.Guide.Rebuild == QMC.guideRebuildWrapper
                    and QM.Guide.SetWaypointToCurrent == QMC.guideWaypointWrapper
                    and QM.AutoSelectBestWaypoint == QMC.guideAutoSelectWrapper) then
                    QMC:InstallGuidePersistencePatch()
                end
                if not (QMC.trackerCompletedWrapper and QMC.trackerIncompleteWrapper
                    and QM.GetCompletedQuests == QMC.trackerCompletedWrapper
                    and QM.GetIncompleteQuests == QMC.trackerIncompleteWrapper) then
                    QMC:InstallTrackerZonePatch()
                end
            end
        end
    end
end)
