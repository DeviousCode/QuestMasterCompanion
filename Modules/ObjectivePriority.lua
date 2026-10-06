local QMC = _G.QuestMasterCompanion
if not QMC then return end

local U = QMC.Util
local Live = QMC.Live

function QMC:ObjectiveCompatibilityCheck()
    local QM = _G.QuestMaster
    if type(QM) ~= "table" then return false, "QuestMaster global is unavailable" end
    if type(QM.GetQuestObjectiveLocationsFixed) ~= "function" then return false, "objective resolver changed" end
    return true
end

function QMC:RestoreObjectivePriority(reason)
    local QM = _G.QuestMaster
    if QM and self.objectiveWrapper and self.objectiveOriginal
        and QM.GetQuestObjectiveLocationsFixed == self.objectiveWrapper then
        QM.GetQuestObjectiveLocationsFixed = self.objectiveOriginal
    end
    self.objectiveState = reason == "manual" and "disabled-manual" or "inactive"
end

function QMC:InstallObjectivePriority()
    if not self:Saved().enabled then
        self.objectiveState = "disabled-manual"
        return false
    end

    local compatible, why = self:ObjectiveCompatibilityCheck()
    if not compatible then
        self.objectiveState = "incompatible"
        self.objectiveIncompatibleReason = why
        return false
    end

    local QM = _G.QuestMaster
    if self.objectiveWrapper and QM.GetQuestObjectiveLocationsFixed == self.objectiveWrapper then
        self.objectiveState = self.objectiveLiveCount > 0 and "used" or "standby"
        return true
    end

    if self.objectiveOriginal and QM.GetQuestObjectiveLocationsFixed ~= self.objectiveOriginal then
        self.objectiveState = "changed"
        return false
    end

    self.objectiveOriginal = QM.GetQuestObjectiveLocationsFixed
    self.objectiveWrapper = function(selfQM, questId, ...)
        local results = U.Pack(QMC.objectiveOriginal(selfQM, questId, ...))
        local original = results[1]
        local active = selfQM.activeQuests and selfQM.activeQuests[questId]
        if not active then return U.unpackValues(results, 1, results.n) end

        local live, source = Live.SafeLiveObjectiveLocations(selfQM, questId, active)
        if not U.IsUsableObjectiveResult(live) then
            return U.unpackValues(results, 1, results.n)
        end

        local merged = Live.MergeObjectiveLocations(live, original)
        if not U.IsUsableObjectiveResult(merged) then
            return U.unpackValues(results, 1, results.n)
        end

        local index = Live.CurrentObjectiveIndex(selfQM, questId, active)
        local livePoint = Live.FirstObjectivePoint(live, index)
        local oldPoint = Live.FirstObjectivePoint(original, index)
        if livePoint and not Live.PointsAgree(livePoint, oldPoint) then
            QMC.objectiveLiveCount = QMC.objectiveLiveCount + 1
            QMC.objectiveLastQuest = questId
            QMC.objectiveLastSource = source
            QMC.objectiveState = "used"

            if not QMC.notifiedObjectiveQuests[questId] then
                QMC.notifiedObjectiveQuests[questId] = true
                QMC:Notify("using Blizzard's live objective for " .. Live.QuestTitle(selfQM, questId) .. " [" .. questId .. "]")
            end
        end

        return merged
    end

    QM.GetQuestObjectiveLocationsFixed = self.objectiveWrapper
    self.objectiveState = "standby"
    return true
end
