local QMC = _G.QuestMasterCompanion
if not QMC then return end

local U = QMC.Util
local Live = QMC.Live

function QMC:TurnInCompatibilityCheck()
    local QM = _G.QuestMaster
    if type(QM) ~= "table" then return false, "QuestMaster global is unavailable" end
    if type(QM.GetQuestTurnInLocation) ~= "function" then return false, "turn-in resolver is unavailable" end
    if not (QM.DB and type(QM.DB.GetQuest) == "function") then return false, "QuestMaster database API changed" end
    if not (QM.Discovery and type(QM.Discovery.GetQuest) == "function") then return false, "QuestMaster Discovery storage API changed" end
    return true
end

function QMC:RestoreTurnIn(reason)
    local QM = _G.QuestMaster
    if QM and self.turnInWrapper and self.turnInOriginal
        and QM.GetQuestTurnInLocation == self.turnInWrapper then
        QM.GetQuestTurnInLocation = self.turnInOriginal
    end

    if reason == "manual" then
        self.turnInState = "disabled-manual"
    elseif reason == "upstream-fixed" then
        self.turnInState = "upstream-fixed"
    else
        self.turnInState = "inactive"
    end
end

function QMC:InstallTurnInPatch()
    if not self:Saved().enabled then
        self.turnInState = "disabled-manual"
        return false
    end

    local compatible, why = self:TurnInCompatibilityCheck()
    if not compatible then
        self.turnInState = "incompatible"
        self.turnInIncompatibleReason = why
        self:Notify("turn-in patch not installed: " .. why .. ".")
        return false
    end

    local QM = _G.QuestMaster
    if self.turnInWrapper and QM.GetQuestTurnInLocation == self.turnInWrapper then
        self.turnInState = self.turnInFallbackCount > 0 and "needed" or "standby"
        return true
    end

    if self.turnInOriginal and QM.GetQuestTurnInLocation ~= self.turnInOriginal then
        self.turnInState = "superseded"
        return false
    end

    self.turnInOriginal = QM.GetQuestTurnInLocation

    -- This one came from Leonid's Letter. I only trust a real learned turnIn or
    -- Blizzard's live quest-map point here. I don't use the pickup/start as a
    -- substitute because it can look valid while it was pointing me backwards.
    self.turnInWrapper = function(selfQM, questId, ...)
        local originalResults = U.Pack(QMC.turnInOriginal(selfQM, questId, ...))
        local originalResult = originalResults[1]

        local activeQuest = selfQM.activeQuests and selfQM.activeQuests[questId]
        if not activeQuest then
            return U.unpackValues(originalResults, 1, originalResults.n)
        end

        local bundledQuest, dbCheckOK = Live.SafeBundledQuest(selfQM, questId)
        if not dbCheckOK or bundledQuest then
            return U.unpackValues(originalResults, 1, originalResults.n)
        end

        local learned, discoveryOK = Live.SafeStrictDiscoveryTurnIn(selfQM, questId)
        if not discoveryOK then
            return U.unpackValues(originalResults, 1, originalResults.n)
        end

        local livePOI, liveOK = Live.SafeLiveTurnInPOI(selfQM, questId, activeQuest)
        local verified = U.IsUsablePoint(learned) and learned or (liveOK and livePOI or nil)
        local source = U.IsUsablePoint(learned) and "learned turn-in" or (U.IsUsablePoint(livePOI) and "Blizzard live POI" or nil)

        -- Same idea as the objective patch: once QM own result matches the
        -- verified turn-in, this wrapper retires itself instead of fighting QM.
        if U.IsUsablePoint(originalResult) and U.IsUsablePoint(verified) and Live.PointsAgree(originalResult, verified) then
            QMC.turnInUpstreamVerifiedQuest = questId
            QMC:RestoreTurnIn("upstream-fixed")
            QMC:Notify(
                "QuestMaster now resolves unknown turn-ins correctly by itself (verified on " ..
                Live.QuestTitle(selfQM, questId) .. " [" .. questId .. "]). Turn-in patch retired for this session."
            )
            return U.unpackValues(originalResults, 1, originalResults.n)
        end

        if U.IsUsablePoint(verified) then
            if not U.IsUsablePoint(originalResult) or not Live.PointsAgree(originalResult, verified) then
                QMC.turnInFallbackCount = QMC.turnInFallbackCount + 1
                if source == "Blizzard live POI" then
                    QMC.turnInLivePOICount = QMC.turnInLivePOICount + 1
                end
                QMC.turnInLastQuest = questId
                QMC.turnInLastSource = source
                QMC.turnInState = "needed"

                if not QMC.notifiedTurnInQuests[questId] then
                    QMC.notifiedTurnInQuests[questId] = true
                    QMC:Notify(
                        "using " .. tostring(source) .. " for " .. Live.QuestTitle(selfQM, questId) ..
                        " [" .. questId .. "] because QuestMaster had no verified turn-in location."
                    )
                end
                return verified
            end
        end

        return U.unpackValues(originalResults, 1, originalResults.n)
    end

    QM.GetQuestTurnInLocation = self.turnInWrapper
    self.turnInState = "standby"
    return true
end
