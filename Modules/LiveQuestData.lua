local QMC = _G.QuestMasterCompanion
if not QMC then return end

local U = QMC.Util
QMC.Live = QMC.Live or {}
local Live = QMC.Live

function Live.QuestTitle(QM, questId)
    local active = QM and QM.activeQuests and QM.activeQuests[questId]
    if active and active.title and active.title ~= "" then
        return active.title
    end

    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, title = pcall(C_QuestLog.GetTitleForQuestID, questId)
        if ok and type(title) == "string" and title ~= "" then
            return title
        end
    end

    return "Quest " .. tostring(questId)
end

function Live.SafeBundledQuest(QM, questId)
    if not (QM and QM.DB and type(QM.DB.GetQuest) == "function") then
        return nil, false
    end

    local ok, quest = pcall(QM.DB.GetQuest, QM.DB, questId)
    if not ok then return nil, false end
    return quest, true
end

function Live.SafeDiscoveryObjectives(QM, questId, objectiveCount)
    if not (QM and QM.Discovery and type(QM.Discovery.GetObjectiveLocations) == "function") then
        return nil, false
    end

    local ok, result = pcall(QM.Discovery.GetObjectiveLocations, QM.Discovery, questId, objectiveCount or 1)
    if not ok then return nil, false end
    return result, true
end

-- Small note: I intentionally read entry.turnIn directly here instead
-- of calling Discovery:GetTurnInLocation(). The public getter can fall back to
-- entry.start, and that was what sent Leonid's Letter back to the pickup NPC.
function Live.SafeStrictDiscoveryTurnIn(QM, questId)
    if not (QM and QM.Discovery and type(QM.Discovery.GetQuest) == "function") then
        return nil, false
    end

    local ok, entry = pcall(QM.Discovery.GetQuest, QM.Discovery, questId)
    if not ok then return nil, false end
    local point = entry and entry.turnIn
    if not U.IsUsablePoint(point) then return nil, true end
    return {x = point.x, y = point.y, mapId = point.mapId}, true
end

function Live.IsQuestReadyForTurnIn(QM, questId, activeQuest)
    if activeQuest and activeQuest.isComplete then return true end
    if QM and type(QM.IsQuestReady) == "function" then
        local ok, ready = pcall(QM.IsQuestReady, QM, questId)
        if ok and ready then return true end
    end
    if C_QuestLog and C_QuestLog.IsComplete then
        local ok, ready = pcall(C_QuestLog.IsComplete, questId)
        if ok and ready then return true end
    end
    return false
end

function Live.GetQuestUiMapSafe(questId)
    if type(GetQuestUiMapID) ~= "function" then return nil end

    local ok, mapId = pcall(GetQuestUiMapID, questId, true)
    if ok and type(mapId) == "number" and mapId > 0 then return mapId end

    ok, mapId = pcall(GetQuestUiMapID, questId, false)
    if ok and type(mapId) == "number" and mapId > 0 then return mapId end
    return nil
end

function Live.CurrentMapId()
    if C_Map and type(C_Map.GetBestMapForUnit) == "function" then
        local ok, mapId = pcall(C_Map.GetBestMapForUnit, "player")
        if ok and type(mapId) == "number" and mapId > 0 then return mapId end
    end
    return nil
end

-- Another little edge case i hit: during a zone swap the activeQuests table
-- can be empty for a moment even though Blizzard still has the quest in the log.
-- This only checks the live journal so we don't throw away a real player choice.
function Live.QuestStillOnClient(questId)
    questId = tonumber(questId)
    if not questId or questId <= 0 then return false end

    if C_QuestLog and type(C_QuestLog.IsOnQuest) == "function" then
        local ok, value = pcall(C_QuestLog.IsOnQuest, questId)
        if ok and value ~= nil then return value and true or false end
    end

    if C_QuestLog and type(C_QuestLog.GetLogIndexForQuestID) == "function" then
        local ok, index = pcall(C_QuestLog.GetLogIndexForQuestID, questId)
        if ok and type(index) == "number" and index > 0 then return true end
    end

    return false
end

function Live.SafeLiveTurnInPOI(QM, questId, activeQuest)
    local cached = QMC.liveTurnInCache[questId]
    if U.IsUsablePoint(cached) then
        return {x = cached.x, y = cached.y, mapId = cached.mapId}, true
    end

    if not Live.IsQuestReadyForTurnIn(QM, questId, activeQuest) then
        return nil, true
    end

    if not (C_QuestLog and type(C_QuestLog.GetQuestsOnMap) == "function") then
        return nil, false
    end

    local mapId = Live.GetQuestUiMapSafe(questId)
    if not mapId then return nil, true end

    local ok, pois = pcall(C_QuestLog.GetQuestsOnMap, mapId)
    if not ok or type(pois) ~= "table" then return nil, false end

    for _, poi in ipairs(pois) do
        if type(poi) == "table" then
            local id = tonumber(poi.questID or poi.questId)
            local x, y = tonumber(poi.x), tonumber(poi.y)
            if id == questId and x and y then
                local loc = {x = x, y = y, mapId = mapId}
                QMC.liveTurnInCache[questId] = loc

                -- Blizzard already knows the right place here, so I also hand the
                -- map back to QM Discovery scan when it is available. That lets
                -- QM keep the point instead of user owning it forever.
                if QM and QM.Discovery and type(QM.Discovery.ScanMap) == "function" then
                    pcall(QM.Discovery.ScanMap, QM.Discovery, mapId, true)
                end

                return {x = x, y = y, mapId = mapId}, true
            end
        end
    end

    return nil, true
end

function Live.PointsAgree(a, b)
    if not (U.IsUsablePoint(a) and U.IsUsablePoint(b)) then return false end
    if a.mapId ~= b.mapId then return false end
    local dx, dy = a.x - b.x, a.y - b.y
    return (dx * dx + dy * dy) <= 0.0004
end

function Live.DistanceToPointSafe(QM, loc)
    if not (QM and U.IsUsablePoint(loc) and type(QM.GetDistanceToPoint) == "function") then
        return math.huge
    end
    local ok, d = pcall(QM.GetDistanceToPoint, QM, loc.x, loc.y, loc.mapId)
    return (ok and type(d) == "number") and d or math.huge
end
