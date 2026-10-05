local QMC = _G.QuestMasterCompanion
if not QMC then return end

local U = QMC.Util
local Live = QMC.Live

local function PrintPatchState(label, state, count, lastQuest, reason, verifiedQuest)
    local suffix = ""
    if state == "needed" then
        suffix = " | fallbacks: " .. tostring(count or 0)
        if lastQuest then suffix = suffix .. " | last quest: " .. tostring(lastQuest) end
    elseif state == "incompatible" and reason then
        suffix = " | " .. tostring(reason)
    elseif state == "upstream-fixed" then
        suffix = " | retired for session"
        if verifiedQuest then suffix = suffix .. " | verified quest: " .. tostring(verifiedQuest) end
    end
    U.Print(label .. ": " .. tostring(state) .. suffix)
end

function QMC:Status()
    local settings = self:Saved()
    local QM = _G.QuestMaster
    U.Print("v" .. self.VERSION .. " | QuestMaster v" .. U.GetAddonVersion("QuestMaster"))
    U.Print("setting: " .. (settings.enabled and "on" or "off"))

    PrintPatchState("objective patch", self.objectiveState, self.objectiveFallbackCount,
        self.objectiveLastQuest, self.objectiveIncompatibleReason, self.objectiveUpstreamVerifiedQuest)
    PrintPatchState("turn-in patch", self.turnInState, self.turnInFallbackCount,
        self.turnInLastQuest, self.turnInIncompatibleReason, self.turnInUpstreamVerifiedQuest)
    PrintPatchState("guide persistence patch", self.guideState, self.guideRestoreCount,
        self.guideLastQuest, self.guideIncompatibleReason, nil)
    PrintPatchState("tracker destination patch", self.trackerState, self.trackerCarryCount,
        nil, self.trackerIncompatibleReason, nil)

    U.Print("guide counts: restores " .. tostring(self.guideRestoreCount or 0) ..
        " | blocked " .. tostring(self.guideBlockedAutoCount or 0) ..
        " | zone holds " .. tostring(self.guideTransientGuardCount or 0) ..
        " | turn-ins added " .. tostring(self.guideTurnInRescueCount or 0))

    if self.trackerLastMap then
        U.Print("tracker: map " .. tostring(self.trackerLastMap) ..
            " | added " .. tostring(self.trackerLastCarryCount or 0))
    end
    if self.turnInLastSource then
        U.Print("turn-in source: " .. tostring(self.turnInLastSource) ..
            " | Blizzard map uses " .. tostring(self.turnInLivePOICount or 0))
    end

    if QM then
        if self.objectiveWrapper and QM.GetQuestObjectiveLocationsFixed == self.objectiveWrapper then
            U.Print("objective hook: companion")
        elseif self.objectiveOriginal and QM.GetQuestObjectiveLocationsFixed == self.objectiveOriginal then
            U.Print("objective hook: QuestMaster")
        else
            U.Print("objective hook: changed")
        end

        if self.turnInWrapper and QM.GetQuestTurnInLocation == self.turnInWrapper then
            U.Print("turn-in hook: companion")
        elseif self.turnInOriginal and QM.GetQuestTurnInLocation == self.turnInOriginal then
            U.Print("turn-in hook: QuestMaster")
        else
            U.Print("turn-in hook: changed")
        end

        local Guide = QM.Guide
        if Guide and self.guideRebuildWrapper and self.guideWaypointWrapper and self.guideAutoSelectWrapper
            and Guide.Rebuild == self.guideRebuildWrapper
            and Guide.SetWaypointToCurrent == self.guideWaypointWrapper
            and QM.AutoSelectBestWaypoint == self.guideAutoSelectWrapper then
            U.Print("guide hook: companion")
        elseif Guide and self.guideRebuildOriginal and self.guideWaypointOriginal and self.guideAutoSelectOriginal
            and Guide.Rebuild == self.guideRebuildOriginal
            and Guide.SetWaypointToCurrent == self.guideWaypointOriginal
            and QM.AutoSelectBestWaypoint == self.guideAutoSelectOriginal then
            U.Print("guide hook: QuestMaster")
        else
            U.Print("guide hook: changed")
        end

        if self.trackerCompletedWrapper and self.trackerIncompleteWrapper
            and QM.GetCompletedQuests == self.trackerCompletedWrapper
            and QM.GetIncompleteQuests == self.trackerIncompleteWrapper then
            U.Print("tracker hook: companion")
        elseif self.trackerCompletedOriginal and self.trackerIncompleteOriginal
            and QM.GetCompletedQuests == self.trackerCompletedOriginal
            and QM.GetIncompleteQuests == self.trackerIncompleteOriginal then
            U.Print("tracker hook: QuestMaster")
        else
            U.Print("tracker hook: changed")
        end
    end
end

function QMC:TestQuest(questId)
    questId = tonumber(questId)
    if not questId then
        U.Print("usage: /qmc test <questID>")
        return
    end

    local QM = _G.QuestMaster
    if type(QM) ~= "table" then
        U.Print("QuestMaster isn't loaded")
        return
    end

    local active = QM.activeQuests and QM.activeQuests[questId]
    local bundled = nil
    if QM.DB and type(QM.DB.GetQuest) == "function" then
        bundled = select(1, Live.SafeBundledQuest(QM, questId))
    end

    local count = active and active.objectives and #active.objectives or 1
    if count < 1 then count = 1 end

    local learnedObjectives = select(1, Live.SafeDiscoveryObjectives(QM, questId, count))
    local learnedTurnIn = select(1, Live.SafeStrictDiscoveryTurnIn(QM, questId))
    local liveTurnIn = select(1, Live.SafeLiveTurnInPOI(QM, questId, active))

    local objectiveOriginal = self.objectiveOriginal or QM.GetQuestObjectiveLocationsFixed
    local turnInOriginal = self.turnInOriginal or QM.GetQuestTurnInLocation

    local originalObjectives
    if type(objectiveOriginal) == "function" then
        local ok, value = pcall(objectiveOriginal, QM, questId)
        if ok then originalObjectives = value end
    end

    local originalTurnIn
    if type(turnInOriginal) == "function" then
        local ok, value = pcall(turnInOriginal, QM, questId)
        if ok then originalTurnIn = value end
    end

    U.Print("testing " .. Live.QuestTitle(QM, questId) .. " [" .. questId .. "]")
    U.Print("active " .. (active and "yes" or "no") .. " | bundled " .. (bundled and "yes" or "no"))
    U.Print("objective | QM " ..
        (U.IsUsableObjectiveResult(originalObjectives) and "usable" or (U.IsEmptyTable(originalObjectives) and "empty table" or "nil/other")) ..
        " | learned " .. (U.IsUsableObjectiveResult(learnedObjectives) and "usable" or "none"))
    U.Print("turn-in   | QM " .. (U.IsUsablePoint(originalTurnIn) and "usable" or "none") ..
        " | learned " .. (U.IsUsablePoint(learnedTurnIn) and "usable" or "none") ..
        " | live POI: " .. (U.IsUsablePoint(liveTurnIn) and ("usable map " .. tostring(liveTurnIn.mapId)) or "none"))

    if active and not bundled and U.IsUsableObjectiveResult(learnedObjectives)
        and (originalObjectives == nil or U.IsEmptyTable(originalObjectives)) then
        U.Print("objective: fallback needed")
    elseif active and not bundled and U.IsUsableObjectiveResult(learnedObjectives)
        and U.IsUsableObjectiveResult(originalObjectives) then
        U.Print("objective: QuestMaster already handles it")
    end

    local verified = U.IsUsablePoint(learnedTurnIn) and learnedTurnIn or liveTurnIn
    if active and not bundled and U.IsUsablePoint(verified) then
        if U.IsUsablePoint(originalTurnIn) and Live.PointsAgree(originalTurnIn, verified) then
            U.Print("turn-in: QuestMaster matches")
        elseif U.IsUsablePoint(learnedTurnIn) then
            U.Print("turn-in: using learned location")
        else
            U.Print("turn-in: using Blizzard map")
        end
    elseif active and not bundled and Live.IsQuestReadyForTurnIn(QM, questId, active) then
        U.Print("turn-in: ready, no location found")
    end
end
