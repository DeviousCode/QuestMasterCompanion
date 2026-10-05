local QMC = _G.QuestMasterCompanion
if not QMC then return end

local U = QMC.Util

-- This is intentionally small. The pulse never scans the quest database and
-- never rebuilds the Guide on a timer. It only looks at ACCEPT steps QM already
-- planned, then moves a nearby pickup cluster ahead of an objective if needed.
local PULSE_SECONDS = 5
local PICKUP_CLUSTER_YARDS = 120
local EVENT_REFRESH_DELAY = 0.35

local function DistanceBetween(QM, a, b)
    if not (QM and a and b and a.mapId and b.mapId and a.mapId == b.mapId
        and a.x and a.y and b.x and b.y and QM.HBD
        and type(QM.HBD.GetWorldCoordinatesFromZone) == "function") then
        return math.huge
    end

    local okA, ax, ay = pcall(QM.HBD.GetWorldCoordinatesFromZone, QM.HBD, a.x, a.y, a.mapId)
    local okB, bx, by = pcall(QM.HBD.GetWorldCoordinatesFromZone, QM.HBD, b.x, b.y, b.mapId)
    if not okA or not okB or not ax or not ay or not bx or not by then return math.huge end
    local dx, dy = ax - bx, ay - by
    return (dx * dx + dy * dy) ^ 0.5
end

local function RebuildStops(Guide)
    if type(Guide.BuildStops) == "function" then
        local ok, stops = pcall(Guide.BuildStops, Guide.steps or {})
        Guide.stops = ok and stops or {}
    end
end

local function ApplyRouteChange(QM, Guide, steps, index)
    if type(Guide.OrderIsValid) == "function" then
        local ok, valid = pcall(Guide.OrderIsValid, steps)
        if not ok or not valid then return false end
    end

    Guide.steps = steps
    Guide.index = index or 1
    RebuildStops(Guide)
    if type(Guide.Advance) == "function" then pcall(Guide.Advance, Guide) end
    if type(Guide.Refresh) == "function" then pcall(Guide.Refresh, Guide) end

    if not QM.manualWaypoint and type(Guide.SetWaypointToCurrent) == "function" then
        pcall(Guide.SetWaypointToCurrent, Guide, true, false)
    end
    return true
end

local function ClusterAccepts(QM, Guide, anchor, startIndex, allowSingle)
    if not (anchor and anchor.kind == "ACCEPT") then return 0 end
    local steps = Guide.steps or {}
    startIndex = math.max(1, tonumber(startIndex) or 1)

    local selected = {}
    local selectedCount = 0
    for i = startIndex, #steps do
        local step = steps[i]
        if step and step.kind == "ACCEPT" and step.mapId == anchor.mapId
            and DistanceBetween(QM, anchor, step) <= PICKUP_CLUSTER_YARDS then
            selected[i] = true
            selectedCount = selectedCount + 1
        end
    end
    if selectedCount < (allowSingle and 1 or 2) then return 0 end

    local prefix, cluster, rest = {}, {}, {}
    for i = 1, startIndex - 1 do prefix[#prefix + 1] = steps[i] end

    -- Keep the anchor first, then take the closest pickup from the last one. (Flag: B6)
    local anchorIndex
    for i = startIndex, #steps do
        if steps[i] == anchor then anchorIndex = i break end
    end
    if not anchorIndex or not selected[anchorIndex] then return 0 end

    cluster[#cluster + 1] = anchor
    selected[anchorIndex] = nil
    local cursor = anchor
    while #cluster < selectedCount do
        local bestIndex, bestDist
        for i = startIndex, #steps do
            if selected[i] then
                local d = DistanceBetween(QM, cursor, steps[i])
                if not bestDist or d < bestDist then
                    bestIndex, bestDist = i, d
                end
            end
        end
        if not bestIndex then break end
        cluster[#cluster + 1] = steps[bestIndex]
        cursor = steps[bestIndex]
        selected[bestIndex] = nil
    end

    local clusterSet = {}
    for _, step in ipairs(cluster) do clusterSet[step] = true end
    for i = startIndex, #steps do
        if not clusterSet[steps[i]] then rest[#rest + 1] = steps[i] end
    end

    local changed = false
    for n, step in ipairs(cluster) do
        if steps[startIndex + n - 1] ~= step then changed = true break end
    end
    if not changed then return 0 end

    local combined = {}
    for _, step in ipairs(prefix) do combined[#combined + 1] = step end
    for _, step in ipairs(cluster) do combined[#combined + 1] = step end
    for _, step in ipairs(rest) do combined[#combined + 1] = step end

    if not ApplyRouteChange(QM, Guide, combined, startIndex) then return 0 end
    return #cluster
end

local function NearestKnownAccept(QM, Guide)
    if not (QM and Guide and type(QM.GetDistanceToPoint) == "function") then return nil, 0 end
    local startIndex = math.max(1, tonumber(Guide.index) or 1)
    local current = Guide.steps and Guide.steps[startIndex]
    if current and current.kind == "TURNIN" then return nil, 0 end

    local best, bestDist, nearby = nil, math.huge, 0
    for i = startIndex, #(Guide.steps or {}) do
        local step = Guide.steps[i]
        if step and step.kind == "ACCEPT" and step.x and step.y and step.mapId then
            local ok, dist = pcall(QM.GetDistanceToPoint, QM, step.x, step.y, step.mapId)
            if ok and type(dist) == "number" and dist <= PICKUP_CLUSTER_YARDS then
                nearby = nearby + 1
                if dist < bestDist then best, bestDist = step, dist end
            end
        end
    end
    return best, nearby
end

function QMC:GuideAssistCompatibilityCheck()
    local QM = _G.QuestMaster
    if type(QM) ~= "table" then return false, "QuestMaster global is unavailable" end
    local Guide = QM.Guide
    if type(Guide) ~= "table" then return false, "QuestMaster Guide is unavailable" end
    if type(Guide.Rebuild) ~= "function" then return false, "Guide rebuild API changed" end
    if type(Guide.InvalidateScan) ~= "function" then return false, "Guide scan API changed" end
    if type(Guide.BuildStops) ~= "function" then return false, "Guide stop API changed" end
    if type(Guide.OrderIsValid) ~= "function" then return false, "Guide route API changed" end
    return true
end

function QMC:RequestGuideAssistRefresh(reason)
    if not self:Saved().enabled or self.guideAssistState == "incompatible" then return false end
    local QM = _G.QuestMaster
    local Guide = QM and QM.Guide
    if not Guide then return false end

    -- Invalidate now so whichever rebuild happens next gets a fresh pickup list.
    if type(Guide.InvalidateScan) == "function" then pcall(Guide.InvalidateScan, Guide) end
    if type(QM.InvalidateAvailableQuestCache) == "function" then
        pcall(QM.InvalidateAvailableQuestCache, QM)
    end

    self.guideAssistLastReason = reason
    if self.guideAssistRefreshPending then return true end
    self.guideAssistRefreshPending = true
    local generation = self.guideAssistRefreshGeneration or 0

    if not (C_Timer and C_Timer.After) then
        self.guideAssistRefreshPending = false
        return false
    end

    C_Timer.After(EVENT_REFRESH_DELAY, function()
        if generation ~= (QMC.guideAssistRefreshGeneration or 0) then return end
        QMC.guideAssistRefreshPending = false
        if not QMC:Saved().enabled then return end
        local nowQM = _G.QuestMaster
        local nowGuide = nowQM and nowQM.Guide
        if not (nowGuide and type(nowGuide.Rebuild) == "function") then return end

        -- No force here. QM own two-second rebuild throttle gets the last word,
        -- so bursts of quest events still collapse into one normal rebuild.
        pcall(nowGuide.Rebuild, nowGuide, false)
        QMC.guideAssistRefreshCount = QMC.guideAssistRefreshCount + 1
        if QMC.guideAssistState ~= "incompatible" then QMC.guideAssistState = "needed" end
    end)
    return true
end

function QMC:GuideAssistPulse()
    if not self:Saved().enabled then return end
    local QM = _G.QuestMaster
    local Guide = QM and QM.Guide
    if not (Guide and type(Guide.steps) == "table" and #Guide.steps > 0) then return end

    local currentIndex = math.max(1, tonumber(Guide.index) or 1)
    local current = Guide.steps[currentIndex]

    -- If QM already sent us to a pickup, finish that little hub before starting
    -- an objective. This does not rescan anything.
    if current and current.kind == "ACCEPT" then
        local moved = ClusterAccepts(QM, Guide, current, currentIndex)
        if moved > 0 then
            self.guideAssistClusterCount = self.guideAssistClusterCount + moved
            self.guideAssistPulseCount = self.guideAssistPulseCount + 1
            self.guideAssistLastNearbyCount = moved
            self.guideAssistLastReason = "pickup cluster"
            self.guideAssistState = "needed"
        end
        return
    end

    -- Walking into a hub while QM is pointing at an objective is the other
    -- useful case. Check the ACCEPT steps it already knows, nothing more.
    local nearest, nearby = NearestKnownAccept(QM, Guide)
    if nearest then
        local moved = ClusterAccepts(QM, Guide, nearest, currentIndex, true)
        if moved > 0 then
            self.guideAssistClusterCount = self.guideAssistClusterCount + moved
            self.guideAssistPulseCount = self.guideAssistPulseCount + 1
            self.guideAssistLastNearbyCount = nearby
            self.guideAssistLastReason = "nearby pickup"
            self.guideAssistState = "needed"
        end
    end
end

function QMC:RestoreGuideAssist(reason)
    local QM = _G.QuestMaster
    local Guide = QM and QM.Guide
    if Guide and self.guideAssistRebuildWrapper and self.guideAssistRebuildOriginal
        and Guide.Rebuild == self.guideAssistRebuildWrapper then
        Guide.Rebuild = self.guideAssistRebuildOriginal
    end

    if self.guideAssistTicker and self.guideAssistTicker.Cancel then
        pcall(self.guideAssistTicker.Cancel, self.guideAssistTicker)
    end
    self.guideAssistTicker = nil
    self.guideAssistRefreshPending = false
    self.guideAssistRefreshGeneration = (self.guideAssistRefreshGeneration or 0) + 1

    -- The inner Guide wrapper can be recreated by /qmc on, so don't keep a
    -- stale pointer to the old one after this layer is removed.
    self.guideAssistRebuildOriginal = nil
    self.guideAssistRebuildWrapper = nil

    if reason == "manual" then
        self.guideAssistState = "disabled-manual"
    else
        self.guideAssistState = "inactive"
    end
end

local function EnsureAssistEvents()
    if QMC.guideAssistEventFrame or not CreateFrame then return end
    local frame = CreateFrame("Frame")
    QMC.guideAssistEventFrame = frame
    frame:RegisterEvent("QUEST_ACCEPTED")
    frame:RegisterEvent("QUEST_TURNED_IN")
    frame:RegisterEvent("QUEST_REMOVED")
    frame:RegisterEvent("PLAYER_LEVEL_UP")
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    frame:SetScript("OnEvent", function(_, event)
        if not QMC:Saved().enabled then return end
        local reason = event == "QUEST_ACCEPTED" and "quest accepted"
            or event == "QUEST_TURNED_IN" and "quest turned in"
            or event == "QUEST_REMOVED" and "quest removed"
            or event == "PLAYER_LEVEL_UP" and "level changed"
            or "zone changed"
        QMC:RequestGuideAssistRefresh(reason)
    end)
end

function QMC:InstallGuideAssist()
    if not self:Saved().enabled then
        self.guideAssistState = "disabled-manual"
        return false
    end

    local compatible, why = self:GuideAssistCompatibilityCheck()
    if not compatible then
        self.guideAssistState = "incompatible"
        self.guideAssistIncompatibleReason = why
        self:Notify("guide assist not installed: " .. why .. ".")
        return false
    end

    local QM = _G.QuestMaster
    local Guide = QM.Guide
    if self.guideAssistRebuildWrapper and Guide.Rebuild == self.guideAssistRebuildWrapper then
        if not self.guideAssistTicker and C_Timer and C_Timer.NewTicker then
            self.guideAssistTicker = C_Timer.NewTicker(PULSE_SECONDS, function() QMC:GuideAssistPulse() end)
        end
        EnsureAssistEvents()
        self.guideAssistState = (self.guideAssistRefreshCount > 0 or self.guideAssistClusterCount > 0)
            and "needed" or "standby"
        return true
    end

    if self.guideAssistRebuildOriginal and Guide.Rebuild ~= self.guideAssistRebuildOriginal then
        self.guideAssistState = "superseded"
        return false
    end

    self.guideAssistRebuildOriginal = Guide.Rebuild
    self.guideAssistRebuildWrapper = function(selfGuide, force, ...)
        local results = U.Pack(QMC.guideAssistRebuildOriginal(selfGuide, force, ...))
        local index = math.max(1, tonumber(selfGuide.index) or 1)
        local current = selfGuide.steps and selfGuide.steps[index]
        if current and current.kind == "ACCEPT" then
            local moved = ClusterAccepts(QM, selfGuide, current, index)
            if moved > 0 then
                QMC.guideAssistClusterCount = QMC.guideAssistClusterCount + moved
                QMC.guideAssistLastNearbyCount = moved
                QMC.guideAssistLastReason = "rebuild pickup cluster"
                QMC.guideAssistState = "needed"
            end
        end
        return U.unpackValues(results, 1, results.n)
    end

    Guide.Rebuild = self.guideAssistRebuildWrapper
    EnsureAssistEvents()
    if C_Timer and C_Timer.NewTicker then
        self.guideAssistTicker = C_Timer.NewTicker(PULSE_SECONDS, function() QMC:GuideAssistPulse() end)
    end
    self.guideAssistState = "standby"
    return true
end
