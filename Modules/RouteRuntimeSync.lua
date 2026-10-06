local QMC = _G.QuestMasterCompanion
if not QMC then return end

local U = QMC.Util

local ACCEPT_EVENT_DELAY = 0.10

local function LiveIsOnQuest(questId)
    if type(questId) ~= "number" or questId <= 0 then return nil end
    if not (C_QuestLog and C_QuestLog.IsOnQuest) then return nil end

    local ok, value = pcall(C_QuestLog.IsOnQuest, questId)
    if ok then return value and true or false end
    return nil
end

local function ResolveAcceptedQuestId(QM, arg1, arg2)
    local QL = QM and QM.QL
    if QL and type(QL.ResolveQuestEvent) == "function" then
        local ok, _, questId = pcall(QL.ResolveQuestEvent, arg1, arg2)
        if ok and type(questId) == "number" and questId > 0 then return questId end
    end

    if type(arg2) == "number" and arg2 > 0 then return arg2 end
    if type(arg1) == "number" and arg1 > 0 then return arg1 end
    return nil
end

function QMC:RouteRuntimeCompatibilityCheck()
    local QM = _G.QuestMaster
    local Routes = QM and QM.Routes
    local Engine = Routes and Routes.Engine
    local Eval = Engine and Engine.Eval

    if type(QM) ~= "table" then return false, "QuestMaster global is unavailable" end
    if type(Engine) ~= "table" then return false, "route engine not found" end
    if type(Eval) ~= "table" or type(Eval.EvalQuestInLog) ~= "function" then
        return false, "route quest evaluator changed"
    end
    if type(Engine.CurrentStep) ~= "function" or type(Engine.OnStepFinished) ~= "function" then
        return false, "route step API changed"
    end
    return true
end

local function EnsureRuntimeEvents()
    if QMC.routeRuntimeEventFrame or type(CreateFrame) ~= "function" then return end

    local frame = CreateFrame("Frame")
    QMC.routeRuntimeEventFrame = frame
    frame:RegisterEvent("QUEST_ACCEPTED")
    frame:SetScript("OnEvent", function(_, event, arg1, arg2)
        if event ~= "QUEST_ACCEPTED" or not QMC:Saved().enabled then return end

        local QM = _G.QuestMaster
        local Engine = QM and QM.Routes and QM.Routes.Engine
        if not Engine or not Engine.active then return end

        local questId = ResolveAcceptedQuestId(QM, arg1, arg2)
        if not questId then return end

        QMC.routeRuntimeLastQuest = questId
        QMC.routeRuntimeLastEvent = "quest accepted"

        local function CheckCurrentStep()
            if not QMC:Saved().enabled then return end
            local nowQM = _G.QuestMaster
            local nowEngine = nowQM and nowQM.Routes and nowQM.Routes.Engine
            if not (nowEngine and nowEngine.active) then return end

            local step = nowEngine:CurrentStep()
            if step and step.kind == "ACCEPT" and tonumber(step.questId) == questId then
                -- QUEST_ACCEPTED itself is proof. If QuestMaster's cached quest
                -- scan has not caught up yet, do not leave the route sitting on
                -- an accept the player just completed.
                nowEngine:OnStepFinished(step)
                QMC.routeRuntimeAdvanceCount = (QMC.routeRuntimeAdvanceCount or 0) + 1
                QMC.routeRuntimeState = "used"
                return
            end

            -- QuestMaster may already have advanced on its own. A light
            -- re-evaluate is still useful for the next step, especially when
            -- another ACCEPT in the route was already picked up out of order.
            if type(nowEngine.ScheduleEvaluate) == "function" then
                pcall(nowEngine.ScheduleEvaluate, nowEngine)
            end
        end

        if C_Timer and C_Timer.After then
            C_Timer.After(ACCEPT_EVENT_DELAY, CheckCurrentStep)
        else
            CheckCurrentStep()
        end
    end)
end

function QMC:InstallRouteRuntimeSync()
    if not self:Saved().enabled then
        self.routeRuntimeState = "disabled-manual"
        return false
    end

    local compatible, why = self:RouteRuntimeCompatibilityCheck()
    if not compatible then
        self.routeRuntimeState = "incompatible"
        self.routeRuntimeIncompatibleReason = why
        return false
    end

    local QM = _G.QuestMaster
    local Engine = QM.Routes.Engine
    local Eval = Engine.Eval

    if self.routeRuntimeWrapper and Eval.EvalQuestInLog == self.routeRuntimeWrapper then
        EnsureRuntimeEvents()
        self.routeRuntimeState = (self.routeRuntimeAdvanceCount > 0 or self.routeRuntimeLiveAcceptCount > 0)
            and "used" or "standby"
        return true
    end

    if self.routeRuntimeOriginal and Eval.EvalQuestInLog ~= self.routeRuntimeOriginal then
        self.routeRuntimeState = "changed"
        self.routeRuntimeIncompatibleReason = "route evaluator was replaced by another addon/update"
        return false
    end

    local original = Eval.EvalQuestInLog
    self.routeRuntimeOriginal = original

    local wrapper = function(cond, ...)
        local questId = cond and tonumber(cond.questId)
        local live = LiveIsOnQuest(questId)
        if live == true then
            QMC.routeRuntimeLiveAcceptCount = (QMC.routeRuntimeLiveAcceptCount or 0) + 1
            QMC.routeRuntimeLastQuest = questId
            QMC.routeRuntimeLastEvent = "Blizzard says quest is in log"
            QMC.routeRuntimeState = "used"
            return true
        end
        return original(cond, ...)
    end

    self.routeRuntimeWrapper = wrapper
    Eval.EvalQuestInLog = wrapper
    self.routeRuntimeState = "standby"
    self.routeRuntimeIncompatibleReason = nil
    EnsureRuntimeEvents()
    return true
end

function QMC:RestoreRouteRuntimeSync(reason)
    local QM = _G.QuestMaster
    local Eval = QM and QM.Routes and QM.Routes.Engine and QM.Routes.Engine.Eval

    if Eval and self.routeRuntimeWrapper and Eval.EvalQuestInLog == self.routeRuntimeWrapper
        and type(self.routeRuntimeOriginal) == "function" then
        Eval.EvalQuestInLog = self.routeRuntimeOriginal
    end

    self.routeRuntimeWrapper = nil
    self.routeRuntimeOriginal = nil
    self.routeRuntimeState = reason == "manual" and "disabled-manual" or "inactive"
end
