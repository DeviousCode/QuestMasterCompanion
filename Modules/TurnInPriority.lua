local QMC = _G.QuestMasterCompanion
if not QMC then return end

local U = QMC.Util
local Live = QMC.Live

function QMC:TurnInCompatibilityCheck()
    local QM = _G.QuestMaster
    if type(QM) ~= "table" then return false, "QuestMaster global is unavailable" end
    if type(QM.GetQuestTurnInLocation) ~= "function" then return false, "turn-in resolver changed" end
    return true
end

function QMC:RestoreTurnInPriority(reason)
    local QM = _G.QuestMaster
    if QM and self.turnInWrapper and self.turnInOriginal
        and QM.GetQuestTurnInLocation == self.turnInWrapper then
        QM.GetQuestTurnInLocation = self.turnInOriginal
    end
    self.turnInState = reason == "manual" and "disabled-manual" or "inactive"
end

function QMC:InstallTurnInPriority()
    if not self:Saved().enabled then
        self.turnInState = "disabled-manual"
        return false
    end

    local compatible, why = self:TurnInCompatibilityCheck()
    if not compatible then
        self.turnInState = "incompatible"
        self.turnInIncompatibleReason = why
        return false
    end

    local QM = _G.QuestMaster
    if self.turnInWrapper and QM.GetQuestTurnInLocation == self.turnInWrapper then
        self.turnInState = self.turnInLiveCount > 0 and "used" or "standby"
        return true
    end

    if self.turnInOriginal and QM.GetQuestTurnInLocation ~= self.turnInOriginal then
        self.turnInState = "changed"
        return false
    end

    self.turnInOriginal = QM.GetQuestTurnInLocation
    self.turnInWrapper = function(selfQM, questId, ...)
        local results = U.Pack(QMC.turnInOriginal(selfQM, questId, ...))
        local original = results[1]
        local active = selfQM.activeQuests and selfQM.activeQuests[questId]
        if not active then return U.unpackValues(results, 1, results.n) end

        local live, source = Live.SafeLiveTurnInPOI(selfQM, questId, active)
        if not U.IsUsablePoint(live) then
            return U.unpackValues(results, 1, results.n)
        end

        if not Live.PointsAgree(live, original) then
            QMC.turnInLiveCount = QMC.turnInLiveCount + 1
            QMC.turnInLastQuest = questId
            QMC.turnInLastSource = source
            QMC.turnInState = "used"

            if not QMC.notifiedTurnInQuests[questId] then
                QMC.notifiedTurnInQuests[questId] = true
                QMC:Notify("using Blizzard's live turn-in for " .. Live.QuestTitle(selfQM, questId) .. " [" .. questId .. "]")
            end
        end

        return live
    end

    QM.GetQuestTurnInLocation = self.turnInWrapper
    self.turnInState = "standby"
    return true
end
