local addonName = ...

local QMC = {
    VERSION = "0.6.0",
    ADDON_NAME = addonName,

    objectiveState = "loading",
    objectiveFallbackCount = 0,
    objectiveLastQuest = nil,
    objectiveUpstreamVerifiedQuest = nil,

    turnInState = "loading",
    turnInFallbackCount = 0,
    turnInLivePOICount = 0,
    turnInLastQuest = nil,
    turnInLastSource = nil,
    turnInUpstreamVerifiedQuest = nil,
    liveTurnInCache = {},

    guideState = "loading",
    guideRestoreCount = 0,
    guideBlockedAutoCount = 0,
    guideTurnInRescueCount = 0,
    guideLastQuest = nil,
    guideLastRescueCount = 0,
    guideTransientGuardCount = 0,

    trackerState = "loading",
    trackerCarryCount = 0,
    trackerLastCarryCount = 0,
    trackerLastMap = nil,

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

function U.IsEmptyTable(value)
    return type(value) == "table" and next(value) == nil
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
    return QuestMasterCompanionDB
end

function QMC:Notify(message)
    if self:Saved().notifications then U.Print(message) end
end

function QMC:InstallPatches()
    self.objectiveIncompatibleReason = nil
    self.turnInIncompatibleReason = nil
    self.guideIncompatibleReason = nil
    self.trackerIncompatibleReason = nil

    local a = self:InstallObjectivePatch()
    local b = self:InstallTurnInPatch()
    local c = self:InstallGuidePersistencePatch()
    local d = self:InstallTrackerZonePatch()
    return a or b or c or d
end
