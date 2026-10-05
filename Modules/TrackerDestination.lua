local QMC = _G.QuestMasterCompanion
if not QMC then return end

local Live = QMC.Live

local function PassesTrackerNonZoneFilters(QM, quest)
    local profile = QM and QM.db and QM.db.profile
    local filter = profile and profile.filter
    if filter then
        if quest.isRaid and filter.showRaid == false then return false end
        if quest.isDungeon and filter.showDungeon == false then return false end
        if quest.isGroup and not quest.isDungeon and not quest.isRaid and filter.showGroup == false then return false end
        if quest.isPvP and filter.showPvP == false then return false end
    end

    local onlyWatched = profile and profile.tracker and profile.tracker.onlyShowWatched
    if onlyWatched and quest.logIndex and IsQuestWatched and not IsQuestWatched(quest.logIndex) then
        return false
    end
    return true
end

local function ObjectiveOnMap(QM, questId, quest, mapId)
    if not (mapId and quest and type(QM.GetQuestObjectiveLocationsFixed) == "function") then
        return false, math.huge
    end

    local ok, locs = pcall(QM.GetQuestObjectiveLocationsFixed, QM, questId)
    if not ok or type(locs) ~= "table" then return false, math.huge end

    local best = math.huge
    for i, obj in ipairs(quest.objectives or {}) do
        if not obj.finished then
            for _, loc in ipairs(locs[i] or {}) do
                if QMC.Util.IsUsablePoint(loc) and loc.mapId == mapId then
                    best = math.min(best, Live.DistanceToPointSafe(QM, loc))
                end
            end
        end
    end
    return best < math.huge, best
end

local function TurnInOnMap(QM, questId, quest, mapId)
    if not (mapId and type(QM.GetQuestTurnInLocation) == "function") then
        return false, math.huge
    end
    local ok, loc = pcall(QM.GetQuestTurnInLocation, QM, questId)
    if not ok or not QMC.Util.IsUsablePoint(loc) or loc.mapId ~= mapId then return false, math.huge end
    return true, Live.DistanceToPointSafe(QM, loc)
end

local function SortTrackerQuests(QM, list, distanceField)
    local sortBy = QM and QM.db and QM.db.profile and QM.db.profile.tracker
        and QM.db.profile.tracker.sortBy or "distance"
    table.sort(list, function(a, b)
        if sortBy == "level" then
            local al, bl = tonumber(a.level) or 0, tonumber(b.level) or 0
            if al ~= bl then return al < bl end
        else
            local ad = tonumber(a[distanceField]) or 999999
            local bd = tonumber(b[distanceField]) or 999999
            if ad ~= bd then return ad < bd end
        end
        return (a.title or "") < (b.title or "")
    end)
end

function QMC:TrackerCompatibilityCheck()
    local QM = _G.QuestMaster
    if type(QM) ~= "table" then return false, "QuestMaster global is unavailable" end
    if type(QM.GetCompletedQuests) ~= "function" then return false, "completed quest list API changed" end
    if type(QM.GetIncompleteQuests) ~= "function" then return false, "active quest list API changed" end
    return true
end

function QMC:RestoreTracker(reason)
    local QM = _G.QuestMaster
    if QM then
        if self.trackerCompletedWrapper and self.trackerCompletedOriginal
            and QM.GetCompletedQuests == self.trackerCompletedWrapper then
            QM.GetCompletedQuests = self.trackerCompletedOriginal
        end
        if self.trackerIncompleteWrapper and self.trackerIncompleteOriginal
            and QM.GetIncompleteQuests == self.trackerIncompleteWrapper then
            QM.GetIncompleteQuests = self.trackerIncompleteOriginal
        end
    end

    if reason == "manual" then
        self.trackerState = "disabled-manual"
    else
        self.trackerState = "inactive"
    end
end

function QMC:InstallTrackerZonePatch()
    if not self:Saved().enabled then
        self.trackerState = "disabled-manual"
        return false
    end

    local compatible, why = self:TrackerCompatibilityCheck()
    if not compatible then
        self.trackerState = "incompatible"
        self.trackerIncompatibleReason = why
        self:Notify("tracker destination patch not installed: " .. why .. ".")
        return false
    end

    local QM = _G.QuestMaster
    if self.trackerCompletedWrapper and self.trackerIncompleteWrapper
        and QM.GetCompletedQuests == self.trackerCompletedWrapper
        and QM.GetIncompleteQuests == self.trackerIncompleteWrapper then
        self.trackerState = self.trackerCarryCount > 0 and "needed" or "standby"
        return true
    end

    if (self.trackerCompletedOriginal and QM.GetCompletedQuests ~= self.trackerCompletedOriginal)
        or (self.trackerIncompleteOriginal and QM.GetIncompleteQuests ~= self.trackerIncompleteOriginal) then
        self.trackerState = "superseded"
        return false
    end

    self.trackerCompletedOriginal = QM.GetCompletedQuests
    self.trackerIncompleteOriginal = QM.GetIncompleteQuests

    -- This keeps QM normal zone filter intact, but gives destination data a
    -- chance too. The example that exposed it was a Tirisfal quest turning in
    -- inside Undercity: the journal label said one zone while the i was
    -- standing in the correct destination zone.
    self.trackerCompletedWrapper = function(selfQM, ...)
        local list = QMC.trackerCompletedOriginal(selfQM, ...) or {}
        local profile = selfQM.db and selfQM.db.profile
        if not (profile and profile.tracker and profile.tracker.zoneFilter) then return list end

        local mapId = Live.CurrentMapId()
        if not mapId then return list end
        local present = {}
        for _, q in ipairs(list) do if q and q.id then present[q.id] = true end end

        local added = 0
        for questId, quest in pairs(selfQM.activeQuests or {}) do
            if quest and quest.isComplete and not present[questId]
                and PassesTrackerNonZoneFilters(selfQM, quest) then
                local localTurnIn, dist = TurnInOnMap(selfQM, questId, quest, mapId)
                if localTurnIn then
                    quest.turnInDistance = dist
                    list[#list + 1] = quest
                    present[questId] = true
                    added = added + 1
                end
            end
        end

        if added > 0 then
            SortTrackerQuests(selfQM, list, "turnInDistance")
            QMC.trackerCarryCount = QMC.trackerCarryCount + added
            QMC.trackerLastCarryCount = added
            QMC.trackerLastMap = mapId
            QMC.trackerState = "needed"
        end
        return list
    end

    -- Same idea for unfinished cross-zone quests: if the real unfinished
    -- objective is on this map, I keep it visible even if its journal header is not.
    self.trackerIncompleteWrapper = function(selfQM, ...)
        local list = QMC.trackerIncompleteOriginal(selfQM, ...) or {}
        local profile = selfQM.db and selfQM.db.profile
        if not (profile and profile.tracker and profile.tracker.zoneFilter) then return list end

        local mapId = Live.CurrentMapId()
        if not mapId then return list end
        local present = {}
        for _, q in ipairs(list) do if q and q.id then present[q.id] = true end end

        local added = 0
        for questId, quest in pairs(selfQM.activeQuests or {}) do
            if quest and not quest.isComplete and not present[questId]
                and PassesTrackerNonZoneFilters(selfQM, quest) then
                local localObjective, dist = ObjectiveOnMap(selfQM, questId, quest, mapId)
                if localObjective then
                    quest.objectiveDistance = dist
                    list[#list + 1] = quest
                    present[questId] = true
                    added = added + 1
                end
            end
        end

        if added > 0 then
            SortTrackerQuests(selfQM, list, "objectiveDistance")
            QMC.trackerCarryCount = QMC.trackerCarryCount + added
            QMC.trackerLastCarryCount = added
            QMC.trackerLastMap = mapId
            QMC.trackerState = "needed"
        end
        return list
    end

    QM.GetCompletedQuests = self.trackerCompletedWrapper
    QM.GetIncompleteQuests = self.trackerIncompleteWrapper
    self.trackerState = "standby"
    return true
end
