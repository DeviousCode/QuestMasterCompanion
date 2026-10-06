local addonName = ...

local QMC = {
    VERSION = "0.10.0",
    ADDON_NAME = addonName,

    objectiveState = "loading",
    objectiveLiveCount = 0,
    objectiveLastQuest = nil,
    objectiveLastSource = nil,

    turnInState = "loading",
    turnInLiveCount = 0,
    turnInLastQuest = nil,
    turnInLastSource = nil,
    liveTurnInCache = {},

    routeImportState = "loading",
    routeImportNormalizeCount = 0,
    routeImportLastReason = nil,

    routeRuntimeState = "loading",
    routeRuntimeAdvanceCount = 0,
    routeRuntimeLiveAcceptCount = 0,
    routeRuntimeLastQuest = nil,
    routeRuntimeLastEvent = nil,

    routeAcceptState = "loading",
    routeAcceptFixCount = 0,
    routeAcceptLastQuest = nil,
    routeAcceptLastSource = nil,
    routeAcceptDiscoveryScanCount = 0,
    routeAcceptDiscoveryHitCount = 0,
    routeAcceptLastDiscoveryQuest = nil,

    routeWaypointState = "loading",
    routeWaypointTagCount = 0,
    routeWaypointProtectCount = 0,
    routeWaypointRehookCount = 0,
    routeWaypointLastQuest = nil,
    routeWaypointLastKind = nil,

    routeEventNavState = "loading",
    routeEventNavCount = 0,
    routeEventNavRehookCount = 0,
    routeEventNavLastQuest = nil,
    routeEventNavLastKind = nil,
    routeEventNavRetryCount = 0,


    routeGuideState = "loading",
    routeGuideParseCount = 0,
    routeGuideImportCount = 0,
    routeGuideBackgroundCount = 0,
    routeGuideCompleteCount = 0,
    routeGuideKillCount = 0,
    routeGuideLastPackage = nil,

    routeRemoveState = "loading",
    routeRemoveCount = 0,
    routeRemoveButtonCount = 0,
    routeRemoveLastPackage = nil,

    worldMarkerOpacityState = "loading",
    worldMarkerOpacityApplyCount = 0,
    worldMarkerOpacitySliderCount = 0,

    worldObjectAssistState = "loading",
    worldObjectAssistShowCount = 0,
    worldObjectAssistBlockCount = 0,
    worldObjectAssistLastName = nil,
    worldObjectAssistLastId = nil,
    worldObjectAssistLastReason = nil,

    notifiedObjectiveQuests = {},
    notifiedTurnInQuests = {},
}

_G.QuestMasterCompanion = QMC

QMC.Util = {}
local U = QMC.Util

U.unpackValues = unpack or table.unpack

function U.Pack(...)
    return { n = select("#", ...), ... }
end

function U.Print(message)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF60C8FFQuestMaster Companion:|r " .. tostring(message))
    else
        print("QuestMaster Companion: " .. tostring(message))
    end
end

function U.GetAddonVersion(name)
    local getter
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        getter = C_AddOns.GetAddOnMetadata
    elseif GetAddOnMetadata then
        getter = GetAddOnMetadata
    end

    if getter then
        local ok, value = pcall(getter, name, "Version")
        if ok and value then return tostring(value) end
    end
    return "unknown"
end

function U.IsUsableObjectiveResult(value)
    return type(value) == "table" and next(value) ~= nil
end

function U.IsUsablePoint(value)
    return type(value) == "table"
        and type(value.mapId) == "number"
        and type(value.x) == "number"
        and type(value.y) == "number"
end

function QMC:Saved()
    QuestMasterCompanionDB = QuestMasterCompanionDB or {}
    if QuestMasterCompanionDB.enabled == nil then QuestMasterCompanionDB.enabled = true end
    if QuestMasterCompanionDB.notifications == nil then QuestMasterCompanionDB.notifications = true end
    if QuestMasterCompanionDB.worldMarkerFarAlpha == nil then QuestMasterCompanionDB.worldMarkerFarAlpha = 1.0 end
    if QuestMasterCompanionDB.worldMarkerArrivalAlpha == nil then QuestMasterCompanionDB.worldMarkerArrivalAlpha = 1.0 end
    if QuestMasterCompanionDB.worldObjectAssistEnabled == nil then QuestMasterCompanionDB.worldObjectAssistEnabled = true end
    if QuestMasterCompanionDB.worldObjectAssistVisualVersion == nil or QuestMasterCompanionDB.worldObjectAssistVisualVersion < 4 then
        -- 0.9.10 replaces the square glow/breathe prototype with an atlas-backed
        -- quest icon and same-shape radiating echo. Reset only appearance values;
        -- filtering overrides and enable state remain intact.
        QuestMasterCompanionDB.worldObjectAssistSize = 48
        QuestMasterCompanionDB.worldObjectAssistOpacity = 0.97
        QuestMasterCompanionDB.worldObjectAssistColor = "green"
        QuestMasterCompanionDB.worldObjectAssistGlowStrength = 0.64
        QuestMasterCompanionDB.worldObjectAssistPulse = true
        QuestMasterCompanionDB.worldObjectAssistPulseSpeed = 0.90
        QuestMasterCompanionDB.worldObjectAssistSparkles = false
        QuestMasterCompanionDB.worldObjectAssistSparkleStrength = 0.50
        QuestMasterCompanionDB.worldObjectAssistVisualVersion = 4
    end
    if QuestMasterCompanionDB.worldObjectAssistSize == nil then QuestMasterCompanionDB.worldObjectAssistSize = 54 end
    if QuestMasterCompanionDB.worldObjectAssistOpacity == nil then QuestMasterCompanionDB.worldObjectAssistOpacity = 0.96 end
    if QuestMasterCompanionDB.worldObjectAssistColor == nil then QuestMasterCompanionDB.worldObjectAssistColor = "green" end
    if QuestMasterCompanionDB.worldObjectAssistGlowStrength == nil then QuestMasterCompanionDB.worldObjectAssistGlowStrength = 0.72 end
    if QuestMasterCompanionDB.worldObjectAssistPulse == nil then QuestMasterCompanionDB.worldObjectAssistPulse = true end
    if QuestMasterCompanionDB.worldObjectAssistPulseSpeed == nil then QuestMasterCompanionDB.worldObjectAssistPulseSpeed = 1.00 end
    if QuestMasterCompanionDB.worldObjectAssistSparkles == nil then QuestMasterCompanionDB.worldObjectAssistSparkles = false end
    if QuestMasterCompanionDB.worldObjectAssistSparkleStrength == nil then QuestMasterCompanionDB.worldObjectAssistSparkleStrength = 0.55 end
    if QuestMasterCompanionDB.worldObjectAssistHideBlizzardIcons == nil then QuestMasterCompanionDB.worldObjectAssistHideBlizzardIcons = true end
    if QuestMasterCompanionDB.worldObjectAssistSuspendGamepad == nil then QuestMasterCompanionDB.worldObjectAssistSuspendGamepad = true end
    if QuestMasterCompanionDB.worldObjectAssistRange ~= 10 and QuestMasterCompanionDB.worldObjectAssistRange ~= 20 then QuestMasterCompanionDB.worldObjectAssistRange = 20 end
    if QuestMasterCompanionDB.worldObjectAssistBlockCommon == nil then QuestMasterCompanionDB.worldObjectAssistBlockCommon = true end
    if QuestMasterCompanionDB.worldObjectAssistAutoPosition == nil then QuestMasterCompanionDB.worldObjectAssistAutoPosition = true end
    if QuestMasterCompanionDB.worldObjectAssistOffsetX == nil then QuestMasterCompanionDB.worldObjectAssistOffsetX = 0 end
    if QuestMasterCompanionDB.worldObjectAssistOffsetY == nil then QuestMasterCompanionDB.worldObjectAssistOffsetY = 0 end
    QuestMasterCompanionDB.worldObjectAssistIgnoreIds = QuestMasterCompanionDB.worldObjectAssistIgnoreIds or {}
    QuestMasterCompanionDB.worldObjectAssistAllowIds = QuestMasterCompanionDB.worldObjectAssistAllowIds or {}
    QuestMasterCompanionDB.routeGuideMeta = QuestMasterCompanionDB.routeGuideMeta or {}
    QuestMasterCompanionDB.routeGuideTaskProgress = QuestMasterCompanionDB.routeGuideTaskProgress or {}
    return QuestMasterCompanionDB
end

function QMC:Notify(message)
    if self:Saved().notifications then U.Print(message) end
end

-- QuestMaster still version 2.5.0, even though the newer builds are
-- pretty different. Check for code that only exists in the current update
-- instead of trusting the version number.
function QMC:HasUpdatedQuestMaster()
    local QM = _G.QuestMaster
    local Guide = QM and QM.Guide
    local Engine = QM and QM.Routes and QM.Routes.Engine

    if type(QM) ~= "table" then return false, "QuestMaster isn't loaded" end
    if type(QM.GetQuestTurnInLocations) ~= "function" then return false, "unified turn-ins not found" end
    if type(QM.ManualWaypointHolds) ~= "function" then return false, "manual waypoint support not found" end
    if type(QM.NavigateAfterQuestEvent) ~= "function" then return false, "latest navigation update not found" end
    if not (Guide and type(Guide.FollowPlayer) == "function" and type(Guide.PickupsFirst) == "function") then
        return false, "latest Guide update not found"
    end
    if not (Engine and type(Engine.SetWaypointToCurrent) == "function" and type(Engine.CurrentStep) == "function") then
        return false, "route engine not found"
    end
    return true
end

function QMC:InstallPatches()
    self.objectiveIncompatibleReason = nil
    self.turnInIncompatibleReason = nil
    self.routeImportIncompatibleReason = nil
    self.routeRuntimeIncompatibleReason = nil
    self.routeAcceptIncompatibleReason = nil
    self.routeWaypointIncompatibleReason = nil
    self.routeEventNavIncompatibleReason = nil
    self.routeGuideIncompatibleReason = nil
    self.routeRemoveIncompatibleReason = nil
    self.worldMarkerOpacityIncompatibleReason = nil
    self.worldObjectAssistIncompatibleReason = nil

    local updated, why = self:HasUpdatedQuestMaster()
    self.upstreamReady = updated
    self.upstreamReason = why
    if not updated then
        self.objectiveState = "waiting-upstream"
        self.turnInState = "waiting-upstream"
        self.routeRuntimeState = "waiting-upstream"
        self.routeAcceptState = "waiting-upstream"
        self.routeWaypointState = "waiting-upstream"
        self.routeEventNavState = "waiting-upstream"
        self.routeGuideState = "waiting-upstream"
        self.routeRemoveState = "waiting-upstream"
        self.worldMarkerOpacityState = "waiting-upstream"
        self.worldObjectAssistState = "waiting-upstream"
        return self:InstallRouteImportFix()
    end

    local a = self:InstallObjectivePriority()
    local b = self:InstallTurnInPriority()
    local c = self:InstallRouteImportFix()
    local d = self:InstallRouteRuntimeSync()
    local e = self:InstallRouteAcceptLocation()
    local f = self:InstallRouteWaypointSync()
    local g = self:InstallRouteEventNavigation()
    local h = self:InstallGuideTasks()
    local i = self:InstallRouteLibraryRemove()
    local j = self:InstallWorldMarkerOpacity()
    local k = self:InstallWorldObjectAssist()
    return a or b or c or d or e or f or g or h or i or j or k
end
