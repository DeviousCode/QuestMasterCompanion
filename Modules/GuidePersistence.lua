local QMC = _G.QuestMasterCompanion
if not QMC then return end

local U = QMC.Util
local Live = QMC.Live

local function CopyWaypoint(wp)
    if type(wp) ~= "table" then return nil end
    return {
        questId = wp.questId,
        objectiveIndex = wp.objectiveIndex,
        x = wp.x,
        y = wp.y,
        mapId = wp.mapId,
        description = wp.description,
        isManual = wp.isManual,
        fromGuide = wp.fromGuide,
    }
end

local function ManualTargetSnapshot(QM)
    if not (QM and QM.manualWaypoint and type(QM.currentWaypoint) == "table") then
        return nil
    end
    local wp = CopyWaypoint(QM.currentWaypoint)
    if not wp or not wp.x or not wp.y or not wp.mapId then return nil end
    return wp
end

local function ManualTargetStillRelevant(QM, snapshot)
    if not snapshot then return false end
    local questId = tonumber(snapshot.questId)
    if not questId or questId == 0 then return true end

    if snapshot.isManual or snapshot.fromGuide then
        -- If the player clicked a Guide pickup directly, I keep that choice even
        -- before the quest is in the log. Otherwise I only keep real active quests.
        if not (QM and QM.activeQuests and QM.activeQuests[questId]) then
            return snapshot.fromGuide and true or false
        end
    end

    return QM and QM.activeQuests and QM.activeQuests[questId] ~= nil
end

local function RestoreManualTarget(QM, snapshot)
    if not (QM and snapshot and type(QM.SetWaypoint) == "function") then return false end
    local questId = tonumber(snapshot.questId)

    -- I re-resolve the same quest first instead of freezing an old coordinate.
    -- That way a player's selected quest can naturally move from objective 1 to
    -- objective 2, then to the turn-in, without QuestMaster picking a new quest.
    if questId and questId > 0 and QM.activeQuests and QM.activeQuests[questId]
        and type(QM.SetWaypointForQuest) == "function" then
        local before = QM.currentWaypoint
        local ok = pcall(QM.SetWaypointForQuest, QM, questId, false)
        local after = QM.currentWaypoint
        if ok and QM.manualWaypoint and after and after.questId == questId then
            return true
        end

        -- If the quest is already complete, I don't send the player back to an
        -- old objective just because the fresh turn-in lookup failed for a frame.
        local ready = false
        if type(QM.IsQuestReady) == "function" then
            local rok, rv = pcall(QM.IsQuestReady, QM, questId)
            ready = rok and rv and true or false
        end
        if ready then return false end
        QM.currentWaypoint = before
    end

    local ok, set = pcall(QM.SetWaypoint, QM,
        snapshot.questId, snapshot.objectiveIndex or 0,
        snapshot.x, snapshot.y, snapshot.mapId,
        snapshot.description, true)
    if ok and set and QM.currentWaypoint then
        QM.currentWaypoint.isManual = snapshot.isManual
        QM.currentWaypoint.fromGuide = snapshot.fromGuide
        return true
    end
    return false
end

local function GuideHasTurnInStep(Guide, questId, mapId)
    for _, step in ipairs((Guide and Guide.steps) or {}) do
        if step and step.kind == "TURNIN" and step.questId == questId
            and (not mapId or step.mapId == mapId) then
            return true
        end
    end
    return false
end

local function LocalReadyTurnIns(QM, Guide)
    local mapId = Guide and Guide.mapId
    if not mapId then return {} end
    local found = {}

    for questId, quest in pairs((QM and QM.activeQuests) or {}) do
        local ready = Live.IsQuestReadyForTurnIn(QM, questId, quest)
        if ready and not GuideHasTurnInStep(Guide, questId, mapId)
            and type(QM.GetQuestTurnInLocation) == "function" then
            local ok, loc = pcall(QM.GetQuestTurnInLocation, QM, questId)
            if ok and U.IsUsablePoint(loc) and loc.mapId == mapId then
                found[#found + 1] = {
                    kind = "TURNIN",
                    questId = questId,
                    title = Live.QuestTitle(QM, questId),
                    level = quest and quest.level,
                    x = loc.x,
                    y = loc.y,
                    mapId = loc.mapId,
                    npcId = loc.npcId,
                    _qmcDistance = Live.DistanceToPointSafe(QM, loc),
                }
            end
        end
    end

    table.sort(found, function(a, b)
        if a._qmcDistance ~= b._qmcDistance then return a._qmcDistance < b._qmcDistance end
        return (a.questId or 0) < (b.questId or 0)
    end)
    for _, step in ipairs(found) do step._qmcDistance = nil end
    return found
end

local function MergeLocalTurnIns(QM, Guide)
    if not Guide then return 0 end
    local added = LocalReadyTurnIns(QM, Guide)
    if #added == 0 then return 0 end

    local combined = {}
    for _, step in ipairs(Guide.steps or {}) do combined[#combined + 1] = step end
    for _, step in ipairs(added) do combined[#combined + 1] = step end

    local route = combined
    local px, py = 0.5, 0.5
    if type(Guide.PlayerPosition) == "function" then
        local ok, _, x, y = pcall(Guide.PlayerPosition, Guide)
        if ok then px, py = x or px, y or py end
    end
    if type(Guide.PlanRoute) == "function" then
        local ok, planned = pcall(Guide.PlanRoute, combined, px, py)
        if ok and type(planned) == "table" then route = planned end
    end

    Guide.steps = route
    Guide.index = 1
    if type(Guide.BuildStops) == "function" then
        local ok, stops = pcall(Guide.BuildStops, route)
        Guide.stops = ok and stops or {}
    else
        Guide.stops = {}
    end

    if type(Guide.Advance) == "function" then pcall(Guide.Advance, Guide) end

    -- If there is a real hand-in on this map, I don't let the Guide call the
    -- zone finished yet. This is what kept the Undercity turn-ins visible.
    Guide.nextZone = nil

    if type(Guide.unplaced) == "table" then
        local localIds = {}
        for _, step in ipairs(added) do localIds[step.questId] = true end
        local kept = {}
        for _, entry in ipairs(Guide.unplaced) do
            if not localIds[entry.questId] then kept[#kept + 1] = entry end
        end
        Guide.unplaced = kept
    end

    if type(Guide.Refresh) == "function" then pcall(Guide.Refresh, Guide) end
    return #added
end

function QMC:GuideCompatibilityCheck()
    local QM = _G.QuestMaster
    if type(QM) ~= "table" then return false, "QuestMaster global is unavailable" end
    local Guide = QM.Guide
    if type(Guide) ~= "table" then return false, "QuestMaster Guide is unavailable" end
    if type(Guide.Rebuild) ~= "function" then return false, "Guide rebuild API changed" end
    if type(Guide.SetWaypointToCurrent) ~= "function" then return false, "Guide waypoint API changed" end
    if type(QM.SetWaypointForQuest) ~= "function" then return false, "quest waypoint API changed" end
    if type(QM.AutoSelectBestWaypoint) ~= "function" then return false, "auto waypoint API changed" end
    return true
end

function QMC:RestoreGuide(reason)
    local QM = _G.QuestMaster
    local Guide = QM and QM.Guide
    if Guide then
        if self.guideRebuildWrapper and self.guideRebuildOriginal
            and Guide.Rebuild == self.guideRebuildWrapper then
            Guide.Rebuild = self.guideRebuildOriginal
        end
        if self.guideWaypointWrapper and self.guideWaypointOriginal
            and Guide.SetWaypointToCurrent == self.guideWaypointWrapper then
            Guide.SetWaypointToCurrent = self.guideWaypointOriginal
        end
    end
    if QM and self.guideAutoSelectWrapper and self.guideAutoSelectOriginal
        and QM.AutoSelectBestWaypoint == self.guideAutoSelectWrapper then
        QM.AutoSelectBestWaypoint = self.guideAutoSelectOriginal
    end

    if reason == "manual" then
        self.guideState = "disabled-manual"
    else
        self.guideState = "inactive"
    end
end

function QMC:InstallGuidePersistencePatch()
    if not self:Saved().enabled then
        self.guideState = "disabled-manual"
        return false
    end

    local compatible, why = self:GuideCompatibilityCheck()
    if not compatible then
        self.guideState = "incompatible"
        self.guideIncompatibleReason = why
        self:Notify("guide persistence patch not installed: " .. why .. ".")
        return false
    end

    local QM = _G.QuestMaster
    local Guide = QM.Guide

    local rebuildOwned = self.guideRebuildWrapper and (Guide.Rebuild == self.guideRebuildWrapper
        or (self.guideAssistRebuildWrapper and Guide.Rebuild == self.guideAssistRebuildWrapper
            and self.guideAssistRebuildOriginal == self.guideRebuildWrapper))

    if rebuildOwned and self.guideWaypointWrapper and self.guideAutoSelectWrapper
        and Guide.SetWaypointToCurrent == self.guideWaypointWrapper
        and QM.AutoSelectBestWaypoint == self.guideAutoSelectWrapper then
        self.guideState = (self.guideRestoreCount > 0 or self.guideBlockedAutoCount > 0
            or self.guideTurnInRescueCount > 0 or self.guideTransientGuardCount > 0)
            and "needed" or "standby"
        return true
    end

    local rebuildIsExpectedOriginal = not self.guideRebuildOriginal or Guide.Rebuild == self.guideRebuildOriginal
    local rebuildIsAssistLayer = self.guideAssistRebuildWrapper and Guide.Rebuild == self.guideAssistRebuildWrapper
        and self.guideAssistRebuildOriginal == self.guideRebuildWrapper
    if (self.guideRebuildOriginal and not rebuildIsExpectedOriginal and not rebuildIsAssistLayer)
        or (self.guideWaypointOriginal and Guide.SetWaypointToCurrent ~= self.guideWaypointOriginal)
        or (self.guideAutoSelectOriginal and QM.AutoSelectBestWaypoint ~= self.guideAutoSelectOriginal) then
        self.guideState = "superseded"
        return false
    end

    self.guideRebuildOriginal = Guide.Rebuild
    self.guideWaypointOriginal = Guide.SetWaypointToCurrent
    self.guideAutoSelectOriginal = QM.AutoSelectBestWaypoint

    -- Your auto-select already tries to respect manual choices. The odd bit i
    -- saw was just during zone changes, when activeQuests can be empty for a
    -- moment. This guard only covers that tiny window and otherwise leaves you alone.
    self.guideAutoSelectWrapper = function(selfQM, force, ...)
        local wp = selfQM.currentWaypoint
        local questId = wp and tonumber(wp.questId)
        if selfQM.manualWaypoint and questId and questId > 0
            and not (selfQM.activeQuests and selfQM.activeQuests[questId])
            and Live.QuestStillOnClient(questId) then
            QMC.guideTransientGuardCount = QMC.guideTransientGuardCount + 1
            QMC.guideLastQuest = questId
            QMC.guideState = "needed"
            return
        end
        return QMC.guideAutoSelectOriginal(selfQM, force, ...)
    end

    -- A player click should win. Automatic Guide steering is the only thing I
    -- block here; manual=true still lets a new Guide step become the new choice.
    self.guideWaypointWrapper = function(selfGuide, silent, manual, ...)
        if not manual then
            local snapshot = ManualTargetSnapshot(QM)
            if snapshot and (ManualTargetStillRelevant(QM, snapshot)
                or (tonumber(snapshot.questId) and Live.QuestStillOnClient(snapshot.questId))) then
                QMC.guideBlockedAutoCount = QMC.guideBlockedAutoCount + 1
                QMC.guideLastQuest = snapshot.questId
                QMC.guideState = "needed"
                return false
            end
        end
        return QMC.guideWaypointOriginal(selfGuide, silent, manual, ...)
    end

    self.guideRebuildWrapper = function(selfGuide, force, ...)
        local snapshot = ManualTargetSnapshot(QM)
        local results = U.Pack(QMC.guideRebuildOriginal(selfGuide, force, ...))

        -- I merge real turn-ins for the destination map even if the rebuilt Guide
        -- also found fresh accepts/objectives there. That was the piece that made
        -- cross-zone hand-ins disappear in cities like Undercity.
        local carried = MergeLocalTurnIns(QM, selfGuide)
        if carried > 0 then
            QMC.guideTurnInRescueCount = QMC.guideTurnInRescueCount + carried
            QMC.guideLastRescueCount = carried
            QMC.guideState = "needed"

            if not snapshot and type(selfGuide.SetWaypointToCurrent) == "function" then
                pcall(selfGuide.SetWaypointToCurrent, selfGuide, true, false)
            end
        end

        if snapshot and (ManualTargetStillRelevant(QM, snapshot)
            or (tonumber(snapshot.questId) and Live.QuestStillOnClient(snapshot.questId))) then
            local before = QM.currentWaypoint
            local same = before and QM.manualWaypoint
                and before.questId == snapshot.questId
                and (before.objectiveIndex or 0) == (snapshot.objectiveIndex or 0)
                and before.x == snapshot.x and before.y == snapshot.y and before.mapId == snapshot.mapId

            local questId = tonumber(snapshot.questId)
            local shouldRefreshQuest = questId and questId > 0
                and ((QM.activeQuests and QM.activeQuests[questId]) or Live.QuestStillOnClient(questId))

            if shouldRefreshQuest or not same then
                if RestoreManualTarget(QM, snapshot) then
                    QMC.guideRestoreCount = QMC.guideRestoreCount + 1
                    QMC.guideLastQuest = snapshot.questId
                    QMC.guideState = "needed"
                end
            end
        end

        return U.unpackValues(results, 1, results.n)
    end

    QM.AutoSelectBestWaypoint = self.guideAutoSelectWrapper
    Guide.SetWaypointToCurrent = self.guideWaypointWrapper
    Guide.Rebuild = self.guideRebuildWrapper
    self.guideState = "standby"
    return true
end
