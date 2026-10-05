local QMC = _G.QuestMasterCompanion
if not QMC then return end

local U = QMC.Util
local Live = QMC.Live

function QMC:TurnInDatabaseCompatibilityCheck()
    local QM = _G.QuestMaster
    if type(QM) ~= "table" then return false, "QuestMaster global is unavailable" end
    if not (QM.DB and type(QM.DB.GetQuestTurnInLocations) == "function") then
        return false, "QuestMaster turn-in database API changed"
    end
    if type(QM.DB.GetQuest) ~= "function" then return false, "QuestMaster quest database API changed" end
    return true
end

function QMC:RestoreTurnInDatabaseBridge(reason)
    local QM = _G.QuestMaster
    local DB = QM and QM.DB
    if DB and self.turnInDBWrapper and self.turnInDBOriginal
        and DB.GetQuestTurnInLocations == self.turnInDBWrapper then
        DB.GetQuestTurnInLocations = self.turnInDBOriginal
    end

    if reason == "manual" then
        self.turnInDBState = "disabled-manual"
    else
        self.turnInDBState = "inactive"
    end
end

function QMC:InstallTurnInDatabaseBridge()
    if not self:Saved().enabled then
        self.turnInDBState = "disabled-manual"
        return false
    end

    local compatible, why = self:TurnInDatabaseCompatibilityCheck()
    if not compatible then
        self.turnInDBState = "incompatible"
        self.turnInDBIncompatibleReason = why
        self:Notify("turn-in database bridge not installed: " .. why .. ".")
        return false
    end

    local QM = _G.QuestMaster
    local DB = QM.DB
    if self.turnInDBWrapper and DB.GetQuestTurnInLocations == self.turnInDBWrapper then
        self.turnInDBState = self.turnInDBFallbackCount > 0 and "needed" or "standby"
        return true
    end

    if self.turnInDBOriginal and DB.GetQuestTurnInLocations ~= self.turnInDBOriginal then
        self.turnInDBState = "superseded"
        return false
    end

    self.turnInDBOriginal = DB.GetQuestTurnInLocations

    -- A few QM systems read DB:GetQuestTurnInLocations directly instead of the
    -- public resolver. This keeps those paths on the same answer without
    -- changing QuestMaster on disk.
    self.turnInDBWrapper = function(selfDB, questId, ...)
        local originalResults = U.Pack(QMC.turnInDBOriginal(selfDB, questId, ...))
        local original = originalResults[1]
        if type(original) == "table" and next(original) ~= nil then
            return U.unpackValues(originalResults, 1, originalResults.n)
        end

        local activeQuest = QM.activeQuests and QM.activeQuests[questId]
        if not activeQuest then
            return U.unpackValues(originalResults, 1, originalResults.n)
        end

        local bundledQuest, dbCheckOK = Live.SafeBundledQuest(QM, questId)
        if not dbCheckOK or bundledQuest then
            return U.unpackValues(originalResults, 1, originalResults.n)
        end

        local verified, source, verifiedOK = Live.SafeVerifiedTurnIn(QM, questId, activeQuest)
        if not verifiedOK or not U.IsUsablePoint(verified) then
            return U.unpackValues(originalResults, 1, originalResults.n)
        end

        QMC.turnInDBFallbackCount = QMC.turnInDBFallbackCount + 1
        QMC.turnInDBLastQuest = questId
        QMC.turnInDBLastSource = source
        QMC.turnInDBState = "needed"
        if source == "Blizzard live POI" then
            QMC.turnInLivePOICount = QMC.turnInLivePOICount + 1
        end

        if not QMC.notifiedTurnInQuests[questId] then
            QMC.notifiedTurnInQuests[questId] = true
            QMC:Notify(
                "bridging " .. tostring(source) .. " for " .. Live.QuestTitle(QM, questId) ..
                " [" .. questId .. "] because QuestMaster's turn-in database had no location."
            )
        end

        return {{
            x = verified.x,
            y = verified.y,
            mapId = verified.mapId,
            npcId = verified.npcId,
        }}
    end

    DB.GetQuestTurnInLocations = self.turnInDBWrapper
    self.turnInDBState = "standby"
    return true
end
