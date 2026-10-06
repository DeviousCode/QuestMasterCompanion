local QMC = _G.QuestMasterCompanion
if not QMC then return end

-- Okay, so ACCEPT steps don't always have a saved point, which is fine.
-- TURNIN already knows to use the turn-in resolver, and OBJECTIVE uses the
-- objective resolver like it's supposed to.
--
-- ACCEPT is the weird one. If it doesn't have a point, it currently ends up
-- asking the objective resolver where to go... which isn't really what we want.
--
-- QuestMaster already has a start-location API for exactly this, so I don't
-- need to build anything new here. Just hook ACCEPT into the thing that's
-- already sitting there waiting for it.

local POSITION_EPSILON = 0.0005
local DISCOVERY_SCAN_THROTTLE = 2

local function CurrentMapId()
    if QMC.Live and type(QMC.Live.CurrentMapId) == "function" then
        local ok, mapId = pcall(QMC.Live.CurrentMapId)
        if ok and type(mapId) == "number" and mapId > 0 then return mapId end
    end

    if C_Map and type(C_Map.GetBestMapForUnit) == "function" then
        local ok, mapId = pcall(C_Map.GetBestMapForUnit, "player")
        if ok and type(mapId) == "number" and mapId > 0 then return mapId end
    end
end

local function HasOwnPoint(step)
    return step
        and type(step.map) == "number"
        and type(step.x) == "number"
        and type(step.y) == "number"
end

local function UsablePoint(loc)
    return type(loc) == "table"
        and type(loc.mapId) == "number"
        and type(loc.x) == "number"
        and type(loc.y) == "number"
end

local function NearlySame(a, b)
    return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= POSITION_EPSILON
end

local function WaypointMatchesStart(QM, questId, starts)
    local wp = QM and QM.currentWaypoint
    if not (wp and tonumber(wp.questId or 0) == tonumber(questId or 0)) then return false end

    for _, loc in ipairs(starts or {}) do
        if UsablePoint(loc)
            and wp.mapId == loc.mapId
            and NearlySame(wp.x, loc.x)
            and NearlySame(wp.y, loc.y) then
            return true
        end
    end
    return false
end

function QMC:RefreshRouteAcceptDiscovery(questId, force)
    local QM = _G.QuestMaster
    local Discovery = QM and QM.Discovery
    questId = tonumber(questId)

    if not (QM and Discovery and questId and questId > 0) then return false end
    if type(Discovery.IsEnabled) == "function" then
        local ok, enabled = pcall(Discovery.IsEnabled, Discovery)
        if ok and not enabled then return false end
    end

    local mapId = CurrentMapId()
    if not mapId then return false end

    self.routeAcceptDiscoveryTryAt = self.routeAcceptDiscoveryTryAt or {}
    local now = type(GetTime) == "function" and GetTime() or 0
    local last = self.routeAcceptDiscoveryTryAt[questId]
    if not force and last and (now - last) < DISCOVERY_SCAN_THROTTLE then
        return false
    end
    self.routeAcceptDiscoveryTryAt[questId] = now

    -- This is only for a route pickup we cannot place yet. Ask Discovery for
    -- the current map and its quest lines, then check that one quest again.
    if type(Discovery.ScanMap) == "function" then
        pcall(Discovery.ScanMap, Discovery, mapId, true)
    end
    if type(Discovery.ScanQuestLines) == "function" then
        pcall(Discovery.ScanQuestLines, Discovery, mapId, true)
    end

    if type(QM.InvalidateAvailableQuestCache) == "function" then
        pcall(QM.InvalidateAvailableQuestCache, QM)
    end
    if type(QM.InvalidateQuestLocationCache) == "function" then
        pcall(QM.InvalidateQuestLocationCache, QM, questId)
    end

    self.routeAcceptDiscoveryScanCount = (self.routeAcceptDiscoveryScanCount or 0) + 1
    self.routeAcceptLastDiscoveryQuest = questId

    local starts = type(QM.GetQuestStartLocations) == "function"
        and QM:GetQuestStartLocations(questId) or nil
    if type(starts) == "table" and #starts > 0 then
        self.routeAcceptDiscoveryHitCount = (self.routeAcceptDiscoveryHitCount or 0) + 1
        self.routeAcceptLastSource = "QuestMaster Discovery refresh"
        return true, starts
    end

    return false, starts
end

local function BestStart(QM, starts)
    if type(starts) ~= "table" then return nil end

    local playerMap
    if type(QM.GetPlayerPosition) == "function" then
        local ok, _, _, mapId = pcall(QM.GetPlayerPosition, QM)
        if ok then playerMap = mapId end
    end

    local best, bestDist, bestHere
    for _, loc in ipairs(starts) do
        if UsablePoint(loc) then
            local here = playerMap ~= nil and loc.mapId == playerMap
            local dist = math.huge
            if type(QM.GetDistanceToPoint) == "function" then
                local ok, value = pcall(QM.GetDistanceToPoint, QM, loc.x, loc.y, loc.mapId)
                if ok and type(value) == "number" and value >= 0 then dist = value end
            end

            if not best or (here and not bestHere) or (here == bestHere and dist < bestDist) then
                best, bestDist, bestHere = loc, dist, here
            end
        end
    end
    return best
end

function QMC:RouteAcceptCompatibilityCheck()
    local QM = _G.QuestMaster
    local Engine = QM and QM.Routes and QM.Routes.Engine

    if type(QM) ~= "table" then return false, "QuestMaster global is unavailable" end
    if type(Engine) ~= "table" then return false, "route engine not found" end
    if type(Engine.SetWaypointToCurrent) ~= "function" or type(Engine.CurrentStep) ~= "function" then
        return false, "route waypoint API changed"
    end
    if type(Engine.StepLabel) ~= "function" then return false, "route label API changed" end
    if type(QM.GetQuestStartLocations) ~= "function" then return false, "quest-start resolver not found" end
    if type(QM.SetWaypoint) ~= "function" then return false, "QuestMaster waypoint API changed" end
    return true
end

function QMC:InstallRouteAcceptLocation()
    if not self:Saved().enabled then
        self.routeAcceptState = "disabled-manual"
        return false
    end

    local compatible, why = self:RouteAcceptCompatibilityCheck()
    if not compatible then
        self.routeAcceptState = "incompatible"
        self.routeAcceptIncompatibleReason = why
        return false
    end

    local QM = _G.QuestMaster
    local Engine = QM.Routes.Engine

    if self.routeAcceptWrapper and Engine.SetWaypointToCurrent == self.routeAcceptWrapper then
        self.routeAcceptState = (self.routeAcceptFixCount or 0) > 0 and "used" or "standby"
        return true
    end

    if self.routeAcceptWrapper and Engine.SetWaypointToCurrent ~= self.routeAcceptWrapper then
        -- RouteWaypointSync intentionally wraps this module after it installs.
        -- If that is the wrapper currently on top, our hook is still active.
        if self.routeWaypointSetWrapper and Engine.SetWaypointToCurrent == self.routeWaypointSetWrapper
            and self.routeWaypointOriginalSet == self.routeAcceptWrapper then
            self.routeAcceptInstalledUnderWaypoint = true
            self.routeAcceptState = (self.routeAcceptFixCount or 0) > 0 and "used" or "standby"
            return true
        end

        self.routeAcceptWrapper = nil
        self.routeAcceptOriginal = nil
        self.routeAcceptInstalledUnderWaypoint = nil
    end

    local original = Engine.SetWaypointToCurrent
    self.routeAcceptOriginal = original

    local wrapper = function(engine, silent, ...)
        local step = engine and engine:CurrentStep()

        -- Authored points are deliberate route overrides. Leave them entirely
        -- to QuestMaster. This bridge exists only for location-free ACCEPT.
        if not step or step.kind ~= "ACCEPT" or HasOwnPoint(step) or not step.questId then
            return original(engine, silent, ...)
        end

        local starts = QM:GetQuestStartLocations(step.questId)
        if type(starts) ~= "table" or #starts == 0 then
            -- A follow-up quest may have appeared only after the last hand-in.
            -- Give Discovery one targeted refresh before giving up on the pickup.
            local _, refreshed = QMC:RefreshRouteAcceptDiscovery(step.questId, false)
            if type(refreshed) == "table" and #refreshed > 0 then
                starts = refreshed
            else
                starts = QM:GetQuestStartLocations(step.questId)
            end
        end
        if type(starts) ~= "table" or #starts == 0 then
            return original(engine, silent, ...)
        end

        -- Let QuestMaster have first shot at resolving this on its own.
        -- If a future build already returns one of the actual quest-start points,
        -- there's nothing for us to fix here, so just leave it alone.
        --
        -- In the current build, ACCEPT usually falls back to an objective point
        -- (or returns nothing), so we only step in when that happens and replace it
        -- with the proper quest-start location below.
        local originalOK = original(engine, true, ...)
        if originalOK and WaypointMatchesStart(QM, step.questId, starts) then
            QMC.routeAcceptState = "upstream-handled"
            return true
        end

        local loc = BestStart(QM, starts)
        if not loc then return originalOK end

        local ok = QM:SetWaypoint(step.questId, 0, loc.x, loc.y, loc.mapId,
            engine:StepLabel(step), true)
        if ok then
            QMC.routeAcceptFixCount = (QMC.routeAcceptFixCount or 0) + 1
            QMC.routeAcceptLastQuest = step.questId
            QMC.routeAcceptLastSource = "QuestMaster quest-start resolver"
            QMC.routeAcceptState = "used"

            if not silent then
                local L = QM.L
                local prefix = L and L["MSG_PREFIX"] or "QuestMaster:"
                print(string.format("%s %s", prefix, engine:StepLabel(step)))
            end
            return true
        end

        return originalOK
    end

    self.routeAcceptWrapper = wrapper
    self.routeAcceptInstalledUnderWaypoint = nil
    Engine.SetWaypointToCurrent = wrapper
    self.routeAcceptState = "standby"
    self.routeAcceptIncompatibleReason = nil
    return true
end

function QMC:RestoreRouteAcceptLocation(reason)
    local QM = _G.QuestMaster
    local Engine = QM and QM.Routes and QM.Routes.Engine

    -- If RouteWaypointSync is on top of us, restore its original pointer so it
    -- no longer calls this module, without tearing that independent module out.
    if Engine and self.routeWaypointSetWrapper and Engine.SetWaypointToCurrent == self.routeWaypointSetWrapper
        and self.routeWaypointOriginalSet == self.routeAcceptWrapper
        and type(self.routeAcceptOriginal) == "function" then
        self.routeWaypointOriginalSet = self.routeAcceptOriginal
    elseif Engine and self.routeAcceptWrapper and Engine.SetWaypointToCurrent == self.routeAcceptWrapper
        and type(self.routeAcceptOriginal) == "function" then
        Engine.SetWaypointToCurrent = self.routeAcceptOriginal
    end

    self.routeAcceptWrapper = nil
    self.routeAcceptOriginal = nil
    self.routeAcceptInstalledUnderWaypoint = nil
    self.routeAcceptState = reason == "manual" and "disabled-manual" or "inactive"
end
