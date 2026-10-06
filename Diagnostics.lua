local QMC = _G.QuestMasterCompanion
if not QMC then return end

local U = QMC.Util
local Live = QMC.Live

local function StateLine(label, state, count, lastQuest, reason)
    local line = label .. ": " .. tostring(state)
    if count and count > 0 then line = line .. " | uses: " .. tostring(count) end
    if lastQuest then line = line .. " | last quest: " .. tostring(lastQuest) end
    if reason then line = line .. " | " .. tostring(reason) end
    U.Print(line)
end

function QMC:Status()
    local QM = _G.QuestMaster
    local settings = self:Saved()
    local updated, why = self:HasUpdatedQuestMaster()

    U.Print("v" .. self.VERSION .. " | QuestMaster v" .. U.GetAddonVersion("QuestMaster") .. " | " .. (settings.enabled and "on" or "off"))
    U.Print("QuestMaster update: " .. (updated and "found" or ("not found - " .. tostring(why))))

    StateLine("live objective", self.objectiveState, self.objectiveLiveCount,
        self.objectiveLastQuest, self.objectiveIncompatibleReason)
    StateLine("live turn-in", self.turnInState, self.turnInLiveCount,
        self.turnInLastQuest, self.turnInIncompatibleReason)
    StateLine("route import", self.routeImportState,
        self.routeImportNormalizeCount, nil, self.routeImportIncompatibleReason)
    StateLine("route runtime", self.routeRuntimeState,
        self.routeRuntimeAdvanceCount, self.routeRuntimeLastQuest, self.routeRuntimeIncompatibleReason)
    StateLine("route accept", self.routeAcceptState,
        self.routeAcceptFixCount, self.routeAcceptLastQuest, self.routeAcceptIncompatibleReason)
    StateLine("route waypoint", self.routeWaypointState,
        self.routeWaypointProtectCount, self.routeWaypointLastQuest, self.routeWaypointIncompatibleReason)
    StateLine("route event nav", self.routeEventNavState,
        self.routeEventNavCount, self.routeEventNavLastQuest, self.routeEventNavIncompatibleReason)
    StateLine("route remove", self.routeRemoveState,
        self.routeRemoveCount, nil, self.routeRemoveIncompatibleReason)
    StateLine("world marker opacity", self.worldMarkerOpacityState,
        nil, nil, self.worldMarkerOpacityIncompatibleReason)

    if self.routeAcceptFixCount and self.routeAcceptFixCount > 0 then
        U.Print("route accept: fixes " .. tostring(self.routeAcceptFixCount or 0)
            .. (self.routeAcceptLastQuest and (" | last quest " .. tostring(self.routeAcceptLastQuest)) or "")
            .. (self.routeAcceptLastSource and (" | " .. tostring(self.routeAcceptLastSource)) or ""))
    end

    if self.routeWaypointLastQuest then
        U.Print("route waypoint: tags " .. tostring(self.routeWaypointTagCount or 0)
            .. " | protects " .. tostring(self.routeWaypointProtectCount or 0)
            .. " | rehooks " .. tostring(self.routeWaypointRehookCount or 0)
            .. " | last: " .. tostring(self.routeWaypointLastKind or "step")
            .. " quest " .. tostring(self.routeWaypointLastQuest))
    end

    if self.routeEventNavCount and self.routeEventNavCount > 0 then
        U.Print("route event nav: redirects " .. tostring(self.routeEventNavCount or 0)
            .. " | rehooks " .. tostring(self.routeEventNavRehookCount or 0)
            .. " | last: " .. tostring(self.routeEventNavLastKind or "step")
            .. (self.routeEventNavLastQuest and (" quest " .. tostring(self.routeEventNavLastQuest)) or ""))
    end

    if self.routeRemoveButtonCount and self.routeRemoveButtonCount > 0 then
        U.Print("route remove: X buttons " .. tostring(self.routeRemoveButtonCount or 0)
            .. (self.routeRemoveLastPackage and (" | last: " .. tostring(self.routeRemoveLastPackage)) or ""))
    end

    if self.routeRuntimeLastEvent then
        U.Print("route runtime: event fixes " .. tostring(self.routeRuntimeAdvanceCount or 0)
            .. " | live accepts " .. tostring(self.routeRuntimeLiveAcceptCount or 0)
            .. " | last: " .. tostring(self.routeRuntimeLastEvent))
    end

    if self.objectiveLastSource then U.Print("last objective source: " .. tostring(self.objectiveLastSource)) end
    if self.turnInLastSource then U.Print("last turn-in source: " .. tostring(self.turnInLastSource)) end

    if QM then
        local Engine = QM.Routes and QM.Routes.Engine
        U.Print("hooks: objective " .. ((self.objectiveWrapper and QM.GetQuestObjectiveLocationsFixed == self.objectiveWrapper) and "companion" or "QuestMaster")
            .. " | turn-in " .. ((self.turnInWrapper and QM.GetQuestTurnInLocation == self.turnInWrapper) and "companion" or "QuestMaster")
            .. " | route import " .. ((QM.Routes and QM.Routes.Codec and self.routeImportWrapper and QM.Routes.Codec.Decode == self.routeImportWrapper) and "companion" or "QuestMaster")
            .. " | route runtime " .. ((Engine and Engine.Eval and self.routeRuntimeWrapper and Engine.Eval.EvalQuestInLog == self.routeRuntimeWrapper) and "companion" or "QuestMaster")
            .. " | route accept " .. ((Engine and self.routeAcceptWrapper and Engine.SetWaypointToCurrent == self.routeWaypointSetWrapper and self.routeAcceptInstalledUnderWaypoint) and "companion" or ((Engine and self.routeAcceptWrapper and Engine.SetWaypointToCurrent == self.routeAcceptWrapper) and "companion" or "QuestMaster"))
            .. " | route waypoint " .. ((Engine and self.routeWaypointSetWrapper and Engine.SetWaypointToCurrent == self.routeWaypointSetWrapper and self.routeWaypointHoldWrapper and QM.ManualWaypointHolds == self.routeWaypointHoldWrapper) and "companion" or "QuestMaster")
            .. " | route event nav " .. ((self.routeEventNavWrapper and QM.NavigateAfterQuestEvent == self.routeEventNavWrapper) and "companion" or "QuestMaster")
            .. " | route remove " .. ((self.routeRemoveWrapper and QM.CreateRoutesTab == self.routeRemoveWrapper) and "companion" or "QuestMaster")
            .. " | marker opacity " .. ((self.worldMarkerUpdateWrapper and QM.WorldMarker and QM.WorldMarker.UpdateMarker == self.worldMarkerUpdateWrapper and self.worldMarkerOptionsWrapper and QM.CreateArrowTab == self.worldMarkerOptionsWrapper) and "companion" or "QuestMaster"))
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
    local objectiveOriginal = self.objectiveOriginal or QM.GetQuestObjectiveLocationsFixed
    local turnInOriginal = self.turnInOriginal or QM.GetQuestTurnInLocation

    local qmObjectives
    if type(objectiveOriginal) == "function" then
        local ok, value = pcall(objectiveOriginal, QM, questId)
        if ok then qmObjectives = value end
    end

    local qmTurnIn
    if type(turnInOriginal) == "function" then
        local ok, value = pcall(turnInOriginal, QM, questId)
        if ok then qmTurnIn = value end
    end

    local liveObjectives, liveObjectiveSource = Live.SafeLiveObjectiveLocations(QM, questId, active)
    local liveTurnIn, liveTurnInSource = Live.SafeLiveTurnInPOI(QM, questId, active)

    U.Print("testing " .. Live.QuestTitle(QM, questId) .. " [" .. questId .. "] | active " .. (active and "yes" or "no"))
    U.Print("objective | Blizzard " .. (U.IsUsableObjectiveResult(liveObjectives) and ("yes - " .. tostring(liveObjectiveSource)) or "none")
        .. " | QuestMaster " .. (U.IsUsableObjectiveResult(qmObjectives) and "yes" or "none"))
    U.Print("turn-in   | Blizzard " .. (U.IsUsablePoint(liveTurnIn) and ("yes - " .. tostring(liveTurnInSource)) or "none")
        .. " | QuestMaster " .. (U.IsUsablePoint(qmTurnIn) and "yes" or "none"))

    local entry
    if QM.Discovery and type(QM.Discovery.GetQuest) == "function" then
        local ok, value = pcall(QM.Discovery.GetQuest, QM.Discovery, questId)
        if ok then entry = value end
    end
    if type(entry) == "table" then
        local index = Live.CurrentObjectiveIndex(QM, questId, active)
        local learned = entry.objectivePoints and entry.objectivePoints[index]
        U.Print("Discovery | objective " .. (U.IsUsablePoint(learned) and "yes" or "no")
            .. " | map fallback " .. (U.IsUsablePoint(entry.mapPoint) and "yes" or "no")
            .. " | pickup/start " .. (U.IsUsablePoint(entry.start) and "yes" or "no"))
    end
end
