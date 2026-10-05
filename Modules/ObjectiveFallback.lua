local QMC = _G.QuestMasterCompanion
if not QMC then return end

local U = QMC.Util
local Live = QMC.Live

function QMC:ObjectiveCompatibilityCheck()
    local QM = _G.QuestMaster
    if type(QM) ~= "table" then return false, "QuestMaster global is unavailable" end
    if type(QM.GetQuestObjectiveLocationsFixed) ~= "function" then return false, "objective resolver is unavailable" end
    if not (QM.DB and type(QM.DB.GetQuest) == "function") then return false, "QuestMaster database API changed" end
    if not (QM.Discovery and type(QM.Discovery.GetObjectiveLocations) == "function") then return false, "QuestMaster objective Discovery API changed" end
    return true
end

function QMC:RestoreObjective(reason)
    local QM = _G.QuestMaster
    if QM and self.objectiveWrapper and self.objectiveOriginal
        and QM.GetQuestObjectiveLocationsFixed == self.objectiveWrapper then
        QM.GetQuestObjectiveLocationsFixed = self.objectiveOriginal
    end

    if reason == "manual" then
        self.objectiveState = "disabled-manual"
    else
        self.objectiveState = "inactive"
    end
end

function QMC:InstallObjectivePatch()
    if not self:Saved().enabled then
        self.objectiveState = "disabled-manual"
        return false
    end

    local compatible, why = self:ObjectiveCompatibilityCheck()
    if not compatible then
        self.objectiveState = "incompatible"
        self.objectiveIncompatibleReason = why
        self:Notify("objective patch not installed: " .. why .. ".")
        return false
    end

    local QM = _G.QuestMaster
    if self.objectiveWrapper and QM.GetQuestObjectiveLocationsFixed == self.objectiveWrapper then
        self.objectiveState = self.objectiveFallbackCount > 0 and "needed" or "standby"
        return true
    end

    if self.objectiveOriginal and QM.GetQuestObjectiveLocationsFixed ~= self.objectiveOriginal then
        self.objectiveState = "superseded"
        return false
    end

    self.objectiveOriginal = QM.GetQuestObjectiveLocationsFixed

    -- This is the empty-table case i ran into with newer Forever quests.
    -- QM gets first shot every time. One quest working does not mean every
    -- resolver path is fixed, so this stays around and only fills real holes.
    self.objectiveWrapper = function(selfQM, questId, ...)
        local originalResults = U.Pack(QMC.objectiveOriginal(selfQM, questId, ...))
        local originalResult = originalResults[1]

        local activeQuest = selfQM.activeQuests and selfQM.activeQuests[questId]
        if not activeQuest then
            return U.unpackValues(originalResults, 1, originalResults.n)
        end

        local bundledQuest, dbCheckOK = Live.SafeBundledQuest(selfQM, questId)
        if not dbCheckOK or bundledQuest then
            return U.unpackValues(originalResults, 1, originalResults.n)
        end

        local objectiveCount = (activeQuest.objectives and #activeQuest.objectives) or 1
        if objectiveCount < 1 then objectiveCount = 1 end

        local learned, discoveryOK = Live.SafeDiscoveryObjectives(selfQM, questId, objectiveCount)
        if not discoveryOK then
            return U.unpackValues(originalResults, 1, originalResults.n)
        end

        if (originalResult == nil or U.IsEmptyTable(originalResult)) and U.IsUsableObjectiveResult(learned) then
            QMC.objectiveFallbackCount = QMC.objectiveFallbackCount + 1
            QMC.objectiveLastQuest = questId
            QMC.objectiveState = "needed"

            if not QMC.notifiedObjectiveQuests[questId] then
                QMC.notifiedObjectiveQuests[questId] = true
                QMC:Notify(
                    "using learned objective location for " .. Live.QuestTitle(selfQM, questId) ..
                    " [" .. questId .. "] because QuestMaster returned no usable objective location."
                )
            end
            return learned
        end

        return U.unpackValues(originalResults, 1, originalResults.n)
    end

    QM.GetQuestObjectiveLocationsFixed = self.objectiveWrapper
    self.objectiveState = "standby"
    return true
end
