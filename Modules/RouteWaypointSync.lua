local QMC = _G.QuestMasterCompanion
if not QMC then return end

local POSITION_EPSILON = 0.0005

local function NearlySame(a, b)
    return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= POSITION_EPSILON
end

local function StepWaypointPoint(step)
    if not step then return nil end
    if type(step.map) ~= "number" or type(step.x) ~= "number" or type(step.y) ~= "number" then
        return nil
    end
    return step.map, step.x / 100, step.y / 100
end

local function RefreshRouteArrowText(QM)
    local wp = QM and QM.currentWaypoint
    local arrow = _G.QuestMasterArrow
    local objective = arrow and arrow.objective
    if not (wp and objective and type(objective.SetText) == "function") then return end

    local settings = QM.db and QM.db.profile and QM.db.profile.arrow
    if settings and settings.showObjective == false then return end

    local text = wp.description
    if type(text) ~= "string" or text == "" then return end

    if type(QM.ArrowShorten) == "function" then
        local ok, short = pcall(QM.ArrowShorten, text, 50)
        if ok and short then text = short end
    end

    -- DrawArrow bails out early when the new step is already inside the
    -- arrival range, so that little line can keep the last step's text.
    -- The waypoint is already right here, just freshen the label too.
    objective:SetText(text)
    if type(objective.Show) == "function" then objective:Show() end
end

local function RouteWaypointStillCurrent(QM, Engine)
    if not (Engine and Engine.active and not Engine.active.paused and type(Engine.CurrentStep) == "function") then
        return false
    end

    local wp = QM and QM.currentWaypoint
    if not (wp and wp.fromRoute) then return false end

    local step = Engine:CurrentStep()
    if not step then return false end

    if wp.routeStepId and step.stepId and wp.routeStepId ~= step.stepId then return false end
    if tonumber(wp.questId or 0) ~= tonumber(step.questId or 0) then return false end
    if tonumber(wp.objectiveIndex or 0) ~= tonumber(step.objective or 0) then return false end

    local map, x, y = StepWaypointPoint(step)
    if map then
        return wp.mapId == map and NearlySame(wp.x, x) and NearlySame(wp.y, y)
    end

    -- A route step with no saved point can borrow QuestMaster's live/DB point.
    -- In that case the step id plus quest/objective pair is the stable part.
    return true
end

function QMC:RouteWaypointCompatibilityCheck()
    local QM = _G.QuestMaster
    local Engine = QM and QM.Routes and QM.Routes.Engine

    if type(QM) ~= "table" then return false, "QuestMaster global is unavailable" end
    if type(Engine) ~= "table" then return false, "route engine not found" end
    if type(Engine.SetWaypointToCurrent) ~= "function" or type(Engine.CurrentStep) ~= "function" then
        return false, "route waypoint API changed"
    end
    if type(QM.ManualWaypointHolds) ~= "function" then
        return false, "manual waypoint API changed"
    end
    return true
end

function QMC:InstallRouteWaypointSync()
    if not self:Saved().enabled then
        self.routeWaypointState = "disabled-manual"
        return false
    end

    local compatible, why = self:RouteWaypointCompatibilityCheck()
    if not compatible then
        self.routeWaypointState = "incompatible"
        self.routeWaypointIncompatibleReason = why
        return false
    end

    local QM = _G.QuestMaster
    local Engine = QM.Routes.Engine

    if self.routeWaypointSetWrapper and self.routeWaypointHoldWrapper
        and Engine.SetWaypointToCurrent == self.routeWaypointSetWrapper
        and QM.ManualWaypointHolds == self.routeWaypointHoldWrapper then
        self.routeWaypointState = (self.routeWaypointProtectCount or 0) > 0 and "used" or "standby"
        return true
    end

    -- QuestMaster has been moving quickly. If it replaces one of these during
    -- startup, just hook the new function on the next install pass instead of
    -- getting stuck on a stale wrapper from earlier in the load.
    if self.routeWaypointSetWrapper or self.routeWaypointHoldWrapper then
        self.routeWaypointRehookCount = (self.routeWaypointRehookCount or 0) + 1
        self.routeWaypointSetWrapper = nil
        self.routeWaypointHoldWrapper = nil
        self.routeWaypointOriginalSet = nil
        self.routeWaypointOriginalHold = nil
    end

    local originalSet = Engine.SetWaypointToCurrent
    local originalHold = QM.ManualWaypointHolds
    self.routeWaypointOriginalSet = originalSet
    self.routeWaypointOriginalHold = originalHold

    local setWrapper = function(engine, silent, ...)
        local oldWaypoint = QM.currentWaypoint
        local oldRouteStep = oldWaypoint and oldWaypoint.fromRoute and oldWaypoint.routeStepId or nil
        local ok = originalSet(engine, silent, ...)
        local step = engine and engine:CurrentStep()

        if ok and engine and engine.active and QM.currentWaypoint then
            local wp = QM.currentWaypoint
            if step then
                wp.fromRoute = true
                wp.routeStepId = step.stepId
                wp.routeKind = step.kind
                RefreshRouteArrowText(QM)

                QMC.routeWaypointTagCount = (QMC.routeWaypointTagCount or 0) + 1
                QMC.routeWaypointLastQuest = step.questId or wp.questId
                QMC.routeWaypointLastKind = step.kind
                QMC.routeWaypointState = "used"
            end
        elseif step and oldRouteStep and oldRouteStep ~= step.stepId
            and QM.currentWaypoint == oldWaypoint and type(QM.ClearWaypoint) == "function" then
            -- New route step has nowhere usable to point right now. Don't leave
            -- the last step's marker sitting there pretending it is still current.
            QM:ClearWaypoint()
            QMC.routeWaypointStaleClearCount = (QMC.routeWaypointStaleClearCount or 0) + 1
            QMC.routeWaypointLastKind = step.kind
            QMC.routeWaypointState = "used"
        end
        return ok
    end

    local holdWrapper = function(selfQM, ...)
        local nowEngine = selfQM.Routes and selfQM.Routes.Engine
        if RouteWaypointStillCurrent(selfQM, nowEngine) then
            -- Imported route ACCEPT steps are manual waypoints, but the quest
            -- is not in the log yet. QuestMaster's normal check sees that and
            -- can hand the arrow to some active objective instead. A current
            -- route step owns its waypoint until the route itself moves on.
            QMC.routeWaypointProtectCount = (QMC.routeWaypointProtectCount or 0) + 1
            QMC.routeWaypointState = "used"
            return true
        end
        return originalHold(selfQM, ...)
    end

    self.routeWaypointSetWrapper = setWrapper
    self.routeWaypointHoldWrapper = holdWrapper
    Engine.SetWaypointToCurrent = setWrapper
    QM.ManualWaypointHolds = holdWrapper
    self.routeWaypointState = "standby"
    self.routeWaypointIncompatibleReason = nil

    -- A saved route can already be active before the Companion's PLAYER_LOGIN
    -- pass. Re-seat its current step once so it gets the route tag too.
    if Engine.active and not Engine.active.paused then
        pcall(Engine.SetWaypointToCurrent, Engine, true)
    end
    return true
end

function QMC:RestoreRouteWaypointSync(reason)
    local QM = _G.QuestMaster
    local Engine = QM and QM.Routes and QM.Routes.Engine

    if Engine and self.routeWaypointSetWrapper and Engine.SetWaypointToCurrent == self.routeWaypointSetWrapper
        and type(self.routeWaypointOriginalSet) == "function" then
        Engine.SetWaypointToCurrent = self.routeWaypointOriginalSet
    end

    if QM and self.routeWaypointHoldWrapper and QM.ManualWaypointHolds == self.routeWaypointHoldWrapper
        and type(self.routeWaypointOriginalHold) == "function" then
        QM.ManualWaypointHolds = self.routeWaypointOriginalHold
    end

    self.routeWaypointSetWrapper = nil
    self.routeWaypointHoldWrapper = nil
    self.routeWaypointOriginalSet = nil
    self.routeWaypointOriginalHold = nil
    self.routeWaypointState = reason == "manual" and "disabled-manual" or "inactive"
end
