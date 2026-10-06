local QMC = _G.QuestMasterCompanion
if not QMC then return end

-- QuestMaster's normal post-accept/turn-in helper rebuilds the normal Guide
-- about a second after the quest event. That is right when no imported route
-- is playing, but a running route already has its own next step. Let the route
-- settle and put its own waypoint back instead of handing the arrow to Guide.

local function RouteIsPlaying(Engine)
    if not Engine then return false end
    if type(Engine.IsActive) == "function" and not Engine:IsActive() then return false end
    if type(Engine.IsPaused) == "function" and Engine:IsPaused() then return false end
    return Engine.active ~= nil
end

function QMC:RouteEventNavigationCompatibilityCheck()
    local QM = _G.QuestMaster
    local Engine = QM and QM.Routes and QM.Routes.Engine

    if type(QM) ~= "table" then return false, "QuestMaster global is unavailable" end
    if type(QM.NavigateAfterQuestEvent) ~= "function" then
        return false, "post-quest navigation API changed"
    end
    if type(Engine) ~= "table" then return false, "route engine not found" end
    if type(Engine.CurrentStep) ~= "function" or type(Engine.SetWaypointToCurrent) ~= "function" then
        return false, "route waypoint API changed"
    end
    if type(Engine.Evaluate) ~= "function" then
        return false, "route evaluate API changed"
    end
    return true
end

function QMC:InstallRouteEventNavigation()
    if not self:Saved().enabled then
        self.routeEventNavState = "disabled-manual"
        return false
    end

    local compatible, why = self:RouteEventNavigationCompatibilityCheck()
    if not compatible then
        self.routeEventNavState = "incompatible"
        self.routeEventNavIncompatibleReason = why
        return false
    end

    local QM = _G.QuestMaster

    if self.routeEventNavWrapper and QM.NavigateAfterQuestEvent == self.routeEventNavWrapper then
        self.routeEventNavState = (self.routeEventNavCount or 0) > 0 and "used" or "standby"
        return true
    end

    -- QuestMaster is changing quickly. If this function was replaced between
    -- install passes, wrap the current copy instead of keeping a stale one.
    if self.routeEventNavWrapper then
        self.routeEventNavRehookCount = (self.routeEventNavRehookCount or 0) + 1
        self.routeEventNavWrapper = nil
        self.routeEventNavOriginal = nil
    end

    local original = QM.NavigateAfterQuestEvent
    self.routeEventNavOriginal = original

    local wrapper = function(selfQM, ...)
        local Engine = selfQM.Routes and selfQM.Routes.Engine
        if not RouteIsPlaying(Engine) then
            return original(selfQM, ...)
        end

        -- Match QuestMaster's own one-shot behavior. QUEST_ACCEPTED and the
        -- later log refresh can both ask for navigation; only one delayed pass
        -- is useful.
        if selfQM.navigateAfterQuestPending then return end
        selfQM.navigateAfterQuestPending = true

        local delay = tonumber(selfQM.NAVIGATE_AFTER_QUEST) or 1

        local function Go()
            selfQM.navigateAfterQuestPending = false

            if not QMC:Saved().enabled then
                return original(selfQM)
            end

            local nowEngine = selfQM.Routes and selfQM.Routes.Engine
            if not RouteIsPlaying(nowEngine) then
                return original(selfQM)
            end

            -- The quest log should be settled now. First let the route advance
            -- if the event completed its current step, then seat the waypoint
            -- on whatever step is current after that evaluation.
            pcall(nowEngine.Evaluate, nowEngine)

            local step = nowEngine:CurrentStep()
            if not step then return end

            local ok, placed = pcall(nowEngine.SetWaypointToCurrent, nowEngine, true)
            if ok and placed then
                QMC.routeEventNavCount = (QMC.routeEventNavCount or 0) + 1
                QMC.routeEventNavLastQuest = step.questId
                QMC.routeEventNavLastKind = step.kind
                QMC.routeEventNavState = "used"
            end

            if type(nowEngine.Refresh) == "function" then
                pcall(nowEngine.Refresh, nowEngine)
            end
        end

        if C_Timer and C_Timer.After then
            C_Timer.After(delay, Go)
        else
            Go()
        end
    end

    self.routeEventNavWrapper = wrapper
    QM.NavigateAfterQuestEvent = wrapper
    self.routeEventNavState = "standby"
    self.routeEventNavIncompatibleReason = nil
    return true
end

function QMC:RestoreRouteEventNavigation(reason)
    local QM = _G.QuestMaster

    if QM and self.routeEventNavWrapper and QM.NavigateAfterQuestEvent == self.routeEventNavWrapper
        and type(self.routeEventNavOriginal) == "function" then
        QM.NavigateAfterQuestEvent = self.routeEventNavOriginal
    end

    self.routeEventNavWrapper = nil
    self.routeEventNavOriginal = nil
    self.routeEventNavState = reason == "manual" and "disabled-manual" or "inactive"
end
