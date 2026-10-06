local QMC = _G.QuestMasterCompanion
if not QMC then return end

local U = QMC.Util
QMC.Live = QMC.Live or {}
local Live = QMC.Live

local function PlainNumber(value)
    if issecretvalue and issecretvalue(value) then return nil end
    local ok, valueType = pcall(type, value)
    if not ok or valueType ~= "number" then return nil end
    return value
end

local function PlainCoord(value)
    value = PlainNumber(value)
    if not value or value <= 0 or value >= 1 then return nil end
    return value
end

function Live.QuestTitle(QM, questId)
    local active = QM and QM.activeQuests and QM.activeQuests[questId]
    if active and active.title and active.title ~= "" then return active.title end

    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, title = pcall(C_QuestLog.GetTitleForQuestID, questId)
        if ok and type(title) == "string" and title ~= "" then return title end
    end
    return "Quest " .. tostring(questId)
end

function Live.CurrentObjectiveIndex(QM, questId, activeQuest)
    activeQuest = activeQuest or (QM and QM.activeQuests and QM.activeQuests[questId])
    for index, objective in ipairs((activeQuest and activeQuest.objectives) or {}) do
        if not objective.finished then return index end
    end
    return 1
end

function Live.GetQuestUiMapSafe(questId)
    if type(GetQuestUiMapID) ~= "function" then return nil end

    local ok, mapId = pcall(GetQuestUiMapID, questId, true)
    mapId = ok and PlainNumber(mapId) or nil
    if mapId and mapId > 0 then return mapId end

    ok, mapId = pcall(GetQuestUiMapID, questId, false)
    mapId = ok and PlainNumber(mapId) or nil
    if mapId and mapId > 0 then return mapId end
    return nil
end

function Live.CurrentMapId()
    if C_Map and type(C_Map.GetBestMapForUnit) == "function" then
        local ok, mapId = pcall(C_Map.GetBestMapForUnit, "player")
        mapId = ok and PlainNumber(mapId) or nil
        if mapId and mapId > 0 then return mapId end
    end
    return nil
end

function Live.IsQuestReadyForTurnIn(QM, questId, activeQuest)
    if activeQuest and activeQuest.isComplete then return true end
    if QM and type(QM.IsQuestReady) == "function" then
        local ok, ready = pcall(QM.IsQuestReady, QM, questId)
        if ok and ready then return true end
    end
    if C_QuestLog and type(C_QuestLog.IsComplete) == "function" then
        local ok, ready = pcall(C_QuestLog.IsComplete, questId)
        if ok and ready then return true end
    end
    return false
end

local function NextWaypoint(questId)
    if not (C_QuestLog and type(C_QuestLog.GetNextWaypoint) == "function") then return nil end
    local ok, mapId, x, y = pcall(C_QuestLog.GetNextWaypoint, questId)
    if not ok then return nil end
    mapId, x, y = PlainNumber(mapId), PlainCoord(x), PlainCoord(y)
    if mapId and mapId > 0 and x and y then
        return {x = x, y = y, mapId = mapId}
    end
    return nil
end

local function QuestPointOnMap(questId, mapId)
    if not (mapId and C_QuestLog and type(C_QuestLog.GetQuestsOnMap) == "function") then return nil end
    local ok, pois = pcall(C_QuestLog.GetQuestsOnMap, mapId)
    if not ok or type(pois) ~= "table" then return nil end

    for _, poi in ipairs(pois) do
        if type(poi) == "table" then
            local idOK, rawId = pcall(function() return poi.questID or poi.questId end)
            local xOK, rawX = pcall(function() return poi.x end)
            local yOK, rawY = pcall(function() return poi.y end)
            local id = idOK and PlainNumber(rawId) or nil
            local x = xOK and PlainCoord(rawX) or nil
            local y = yOK and PlainCoord(rawY) or nil
            if id == questId and x and y then
                return {x = x, y = y, mapId = mapId}
            end
        end
    end
    return nil
end

-- Blizzard gets first say for the objective the player is actually on right now.
-- This does not use Discovery's start/map fallback.
function Live.SafeLiveObjectiveLocations(QM, questId, activeQuest)
    if not activeQuest or activeQuest.isComplete then return nil, nil end
    if Live.IsQuestReadyForTurnIn(QM, questId, activeQuest) then return nil, nil end

    local index = Live.CurrentObjectiveIndex(QM, questId, activeQuest)
    local point = NextWaypoint(questId)
    if point then return {[index] = {point}}, "Blizzard waypoint" end

    local maps, seen = {}, {}
    local function AddMap(mapId)
        mapId = PlainNumber(mapId)
        if mapId and mapId > 0 and not seen[mapId] then
            seen[mapId] = true
            maps[#maps + 1] = mapId
        end
    end
    AddMap(Live.CurrentMapId())
    AddMap(Live.GetQuestUiMapSafe(questId))

    for _, mapId in ipairs(maps) do
        point = QuestPointOnMap(questId, mapId)
        if point then return {[index] = {point}}, "Blizzard map" end
    end
    return nil, nil
end

function Live.MergeObjectiveLocations(primary, fallback)
    local merged = {}
    if type(fallback) == "table" then
        for index, list in pairs(fallback) do merged[index] = list end
    end
    if type(primary) == "table" then
        for index, list in pairs(primary) do merged[index] = list end
    end
    return next(merged) and merged or nil
end

function Live.FirstObjectivePoint(locations, index)
    local list = type(locations) == "table" and locations[index]
    local point = type(list) == "table" and list[1]
    return U.IsUsablePoint(point) and point or nil
end

function Live.PointsAgree(a, b)
    if not (U.IsUsablePoint(a) and U.IsUsablePoint(b)) then return false end
    if a.mapId ~= b.mapId then return false end
    local dx, dy = a.x - b.x, a.y - b.y
    return (dx * dx + dy * dy) <= 0.0004
end

function Live.ClearTurnInCache()
    wipe(QMC.liveTurnInCache)
end

-- Ready quests use Blizzard's current waypoint/map before QuestMaster's saved or
-- bundled answer. The result is cached only for this quest state/session.
function Live.SafeLiveTurnInPOI(QM, questId, activeQuest)
    if not Live.IsQuestReadyForTurnIn(QM, questId, activeQuest) then return nil, nil end

    local cached = QMC.liveTurnInCache[questId]
    if U.IsUsablePoint(cached) then
        return {x = cached.x, y = cached.y, mapId = cached.mapId}, cached.source
    end

    local point = NextWaypoint(questId)
    local source = point and "Blizzard waypoint" or nil

    if not point then
        local maps, seen = {}, {}
        local function AddMap(mapId)
            mapId = PlainNumber(mapId)
            if mapId and mapId > 0 and not seen[mapId] then
                seen[mapId] = true
                maps[#maps + 1] = mapId
            end
        end
        -- If Blizzard exposes more than one hand-in, prefer the map we're on.
        AddMap(Live.CurrentMapId())
        AddMap(Live.GetQuestUiMapSafe(questId))
        for _, mapId in ipairs(maps) do
            point = QuestPointOnMap(questId, mapId)
            if point then
                source = "Blizzard map"
                break
            end
        end
    end

    if not point then return nil, nil end

    QMC.liveTurnInCache[questId] = {
        x = point.x, y = point.y, mapId = point.mapId, source = source,
    }

    -- Let QuestMaster learn the same map too when it can.
	-- The Companion shouldn't have to own a Forever-only point... forever.
	-- Get it? Forever? ...yeah. Note to self: touch grass.
    if QM and QM.Discovery and type(QM.Discovery.ScanMap) == "function" then
        pcall(QM.Discovery.ScanMap, QM.Discovery, point.mapId, true)
    end

    return point, source
end

-- Turn-in cache only. Objective locations stay live because progress can move them.
if CreateFrame then
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("QUEST_ACCEPTED")
    frame:RegisterEvent("QUEST_TURNED_IN")
    frame:RegisterEvent("QUEST_REMOVED")
    frame:SetScript("OnEvent", function()
        Live.ClearTurnInCache()
    end)
end
