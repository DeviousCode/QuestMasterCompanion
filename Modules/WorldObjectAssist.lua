local QMC = _G.QuestMasterCompanion
if not QMC then return end

local U = QMC.Util

-- Soft-interact world-object marker. The feature ships enabled by default in
-- Companion 0.10.0, while its tuning controls remain under Advanced as
-- experimental because object coverage/filtering will keep evolving.
--
-- The important rule in this module is that QMC never resizes, recolors, or
-- copies Blizzard's pooled SoftTargetFrame/Icon. Blizzard recycles those
-- frames between GameObjects and NPCs, which is how a one-off test change on
-- Equipment Boxes can later turn into a giant red guard speech bubble.
--
-- QMC instead owns one marker frame. It is temporarily parented to the current
-- soft-interact object's SoftTargetFrame and completely redrawn from QMC state
-- whenever the soft target changes.

local COMMON_BLOCK_PATTERNS = {
    "mailbox",
    "chair",
    "stool",
    "bench",
    "seat",
    "hospital bed",
    "anvil",
    "forge",
    "campfire",
    "cooking fire",
    "meeting stone",
    "guild vault",
    "guild bank",
}

local COLORS = {
    gold   = {1.00, 0.72, 0.10},
    orange = {1.00, 0.40, 0.07},
    cyan   = {0.10, 0.82, 1.00},
    green  = {0.20, 1.00, 0.34},
    red    = {1.00, 0.20, 0.18},
    white  = {0.95, 0.95, 1.00},
}

local QUEST_ICON_ATLAS = "QuestNormal"
local QUEST_ICON_TEXTURE = "Interface\\GossipFrame\\AvailableQuestIcon"

local function ApplyQuestIcon(texture)
    if not texture then return false end

    -- Prefer Blizzard's atlas-backed quest marker. The old GossipFrame file is
    -- tiny and turns visibly blocky when the experimental marker is enlarged.
    if texture.SetAtlas then
        local atlasAvailable = true
        if C_Texture and type(C_Texture.GetAtlasInfo) == "function" then
            atlasAvailable = C_Texture.GetAtlasInfo(QUEST_ICON_ATLAS) ~= nil
        end
        if atlasAvailable then
            local ok = pcall(texture.SetAtlas, texture, QUEST_ICON_ATLAS, false)
            if ok then return true end
        end
    end

    texture:SetTexture(QUEST_ICON_TEXTURE)
    return false
end

local COLOR_ORDER = {"gold", "orange", "cyan", "green", "red", "white"}
local COLOR_LABELS = {
    gold = "Gold",
    orange = "Orange",
    cyan = "Cyan",
    green = "Green",
    red = "Red",
    white = "White",
}

local INTERACT_RANGE_ORDER = {"10", "20"}
local INTERACT_RANGE_LABELS = {
    ["10"] = "10 yd",
    ["20"] = "20 yd",
}

local runtime
local marker
local lastGuid
local refreshElapsed = 0
local refreshSerial = 0
local activeQuestObjects = {}
local activeQuestObjectsDirty = true
local questRelevantObjects = {}
local questRelevantObjectsBuilt = false
local policyElapsed = 0
local gamepadActive = false

local QUEST_RELEVANCE_PRIORITY = {
    ["quest starter object"] = 70,
    ["quest-start item source"] = 65,
    ["quest turn-in object"] = 60,
    ["quest objective object"] = 55,
    ["quest objective item source"] = 50,
    ["quest-required item source"] = 45,
    ["quest-linked item source"] = 40,
}

local function Lower(value)
    return string.lower(tostring(value or ""))
end

local function Clamp(value, low, high)
    value = tonumber(value) or low
    if value < low then return low end
    if value > high then return high end
    return value
end

local function ExtractObjectId(guid)
    if type(guid) ~= "string" then return nil end
    -- GameObject-0-server-instance-zone-objectId-spawnUid
    local id = guid:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    return tonumber(id)
end

local function QueryGamepadActive()
    if type(IsUsingGamepad) == "function" then
        local ok, value = pcall(IsUsingGamepad)
        if ok then return not not value end
    end
    return gamepadActive
end

local function ShouldSuspendForGamepad()
    local saved = QMC:Saved()
    return saved.worldObjectAssistSuspendGamepad and gamepadActive
end

local function IsAssistOperational()
    local saved = QMC:Saved()
    return saved.enabled and saved.worldObjectAssistEnabled and not ShouldSuspendForGamepad()
end

local function CurrentObject()
    if type(UnitIsGameObject) ~= "function" or not UnitIsGameObject("softinteract") then return nil end
    if type(UnitIsInteractable) == "function" and not UnitIsInteractable("softinteract") then return nil end

    local name = type(UnitName) == "function" and UnitName("softinteract") or nil
    local guid = type(UnitGUID) == "function" and UnitGUID("softinteract") or nil
    local objectId = ExtractObjectId(guid)
    if not guid then return nil end
    return name or "World Object", guid, objectId
end

local function RebuildActiveQuestObjects()
    wipe(activeQuestObjects)
    activeQuestObjectsDirty = false

    local QM = _G.QuestMaster
    local DB = QM and QM.DB
    if not (QM and DB and type(DB.GetQuest) == "function") then return end

    for questId, active in pairs(QM.activeQuests or {}) do
        if active and not active.isComplete then
            local ok, quest = pcall(DB.GetQuest, DB, questId)
            if ok and type(quest) == "table" and type(quest.objectives) == "table" then
                -- Direct GameObject objectives.
                for _, row in ipairs(quest.objectives[2] or {}) do
                    if type(row) == "table" and tonumber(row[1]) then
                        activeQuestObjects[tonumber(row[1])] = questId
                    end
                end

                -- Item objectives can come from a GameObject. Scavenged Goods ->
                -- Equipment Boxes (164662) is exactly this shape in QuestMaster's DB.
                if type(DB.GetItem) == "function" then
                    for _, row in ipairs(quest.objectives[3] or {}) do
                        local itemId = type(row) == "table" and tonumber(row[1]) or nil
                        if itemId then
                            local itemOK, item = pcall(DB.GetItem, DB, itemId)
                            if itemOK and type(item) == "table" then
                                for _, sourceObjectId in ipairs(item.gatheredFrom or {}) do
                                    sourceObjectId = tonumber(sourceObjectId)
                                    if sourceObjectId then activeQuestObjects[sourceObjectId] = questId end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

local function QuestObjectIsActive(objectId)
    if not objectId then return false end
    if activeQuestObjectsDirty then RebuildActiveQuestObjects() end
    return activeQuestObjects[objectId] ~= nil
end

local function MarkQuestRelevantObject(objectId, reason, questId, itemId)
    objectId = tonumber(objectId)
    if not objectId then return end

    local priority = QUEST_RELEVANCE_PRIORITY[reason] or 1
    local current = questRelevantObjects[objectId]
    if current and (current.priority or 0) >= priority then return end

    questRelevantObjects[objectId] = {
        reason = reason,
        priority = priority,
        questId = tonumber(questId),
        itemId = tonumber(itemId),
    }
end

local function MarkItemObjectSources(DB, itemId, reason, questId)
    itemId = tonumber(itemId)
    if not itemId then return end

    local item
    if type(DB.GetItem) == "function" then
        local ok, value = pcall(DB.GetItem, DB, itemId)
        if ok then item = value end
    end

    local gatheredFrom = item and item.gatheredFrom
    if not gatheredFrom and DB.items and DB.itemKeys then
        local raw = DB.items[itemId]
        local key = DB.itemKeys.gatheredFrom or DB.itemKeys.iGatheredFrom or 3
        gatheredFrom = raw and raw[key]
    end

    for _, objectId in ipairs(gatheredFrom or {}) do
        MarkQuestRelevantObject(objectId, reason, questId, itemId)
    end
end

local function RebuildQuestRelevantObjects()
    local QM = _G.QuestMaster
    local DB = QM and QM.DB
    if not (DB and type(DB.quests) == "table" and next(DB.quests)) then
        questRelevantObjectsBuilt = false
        return
    end

    wipe(questRelevantObjects)
    questRelevantObjectsBuilt = true

    local objectKeys = DB.objectKeys or DB.objectSchema or {}
    local itemKeys = DB.itemKeys or DB.itemSchema or {}
    local questKeys = DB.questKeys or DB.questSchema or {}

    for objectId, raw in pairs(DB.objects or {}) do
        local starts = raw[objectKeys.questStarts or objectKeys.oQuestsOffered or 2]
        local ends = raw[objectKeys.questEnds or objectKeys.oQuestsCompleted or 3]
        if type(starts) == "table" and next(starts) then
            MarkQuestRelevantObject(objectId, "quest starter object", starts[1])
        end
        if type(ends) == "table" and next(ends) then
            MarkQuestRelevantObject(objectId, "quest turn-in object", ends[1])
        end
    end

    for questId, raw in pairs(DB.quests or {}) do
        local origin = raw[questKeys.startedBy or questKeys.qOrigin or 2]
        if type(origin) == "table" then
            for _, objectId in ipairs(origin[2] or {}) do
                MarkQuestRelevantObject(objectId, "quest starter object", questId)
            end
            for _, itemId in ipairs(origin[3] or {}) do
                MarkItemObjectSources(DB, itemId, "quest-start item source", questId)
            end
        end

        local destination = raw[questKeys.finishedBy or questKeys.qDestination or 3]
        if type(destination) == "table" then
            for _, objectId in ipairs(destination[2] or {}) do
                MarkQuestRelevantObject(objectId, "quest turn-in object", questId)
            end
        end

        local goals = raw[questKeys.objectives or questKeys.qGoals or 10]
        if type(goals) == "table" then
            for _, row in ipairs(goals[2] or {}) do
                local objectId = type(row) == "table" and tonumber(row[1]) or tonumber(row)
                if objectId then MarkQuestRelevantObject(objectId, "quest objective object", questId) end
            end
            for _, row in ipairs(goals[3] or {}) do
                local itemId = type(row) == "table" and tonumber(row[1]) or tonumber(row)
                if itemId then MarkItemObjectSources(DB, itemId, "quest objective item source", questId) end
            end
        end

        local requiredItems = raw[questKeys.requiredSourceItems or questKeys.qRequiredItems or 21]
        if type(requiredItems) == "table" then
            for _, itemId in ipairs(requiredItems) do
                if tonumber(itemId) then
                    MarkItemObjectSources(DB, itemId, "quest-required item source", questId)
                end
            end
        end
    end

    for itemId, raw in pairs(DB.items or {}) do
        local gatheredFrom = raw[itemKeys.gatheredFrom or itemKeys.iGatheredFrom or 3]
        if type(gatheredFrom) == "table" and next(gatheredFrom) then
            local startQuest = raw[itemKeys.startQuest or itemKeys.iStartsQuest or 5]
            local relatedQuests = raw[itemKeys.relatedQuests or itemKeys.iQuestRelation or 15]
            if startQuest then
                for _, objectId in ipairs(gatheredFrom) do
                    MarkQuestRelevantObject(objectId, "quest-start item source", startQuest, itemId)
                end
            elseif type(relatedQuests) == "table" and next(relatedQuests) then
                for _, objectId in ipairs(gatheredFrom) do
                    MarkQuestRelevantObject(objectId, "quest-linked item source", relatedQuests[1], itemId)
                end
            end
        end
    end
end

local function KnownQuestObject(objectId)
    if not objectId then return nil end
    if not questRelevantObjectsBuilt then RebuildQuestRelevantObjects() end
    return questRelevantObjects[objectId]
end

local function CommonBlockReason(name)
    local lower = Lower(name)
    for _, pattern in ipairs(COMMON_BLOCK_PATTERNS) do
        if lower:find(pattern, 1, true) then return pattern end
    end
    return nil
end

local function ShouldEnhance(name, objectId)
    local saved = QMC:Saved()
    local key = objectId and tostring(objectId) or nil

    if key and saved.worldObjectAssistAllowIds[key] then
        return true, "forced allow"
    end
    if key and saved.worldObjectAssistIgnoreIds[key] then
        return false, "ignored object id"
    end

    if QuestObjectIsActive(objectId) then return true, "active quest object" end

    local known = KnownQuestObject(objectId)
    if known then return true, known.reason, known end

    if saved.worldObjectAssistBlockCommon then
        local reason = CommonBlockReason(name)
        if reason then return false, "common object: " .. reason end
    end

    return true, "default allow"
end

local function HideMarker()
    if marker then
        marker:Hide()
        marker:ClearAllPoints()
        marker:SetParent(UIParent)
    end
end

local function EnsureMarker()
    if marker then return marker end

    marker = CreateFrame("Frame", nil, UIParent)
    marker:SetSize(128, 128)
    marker:SetFrameStrata("HIGH")
    marker:Hide()

    -- The marker is one visual language now: the live icon plus several
    -- translucent copies of that SAME icon that expand and fade outward.
    -- There is deliberately no square/button/glow texture behind it.
    marker.echoes = {}
    for i = 1, 3 do
        local echo = marker:CreateTexture(nil, "ARTWORK", nil, -2)
        ApplyQuestIcon(echo)
        echo:SetPoint("CENTER", marker, "CENTER", 0, 0)
        echo:SetBlendMode("ADD")
        echo:Hide()
        echo.phase = (i - 1) / 3
        marker.echoes[i] = echo
    end

    marker.icon = marker:CreateTexture(nil, "OVERLAY")
    ApplyQuestIcon(marker.icon)
    marker.icon:SetPoint("CENTER", marker, "CENTER", 0, 0)

    -- Optional twinkles are independent accents, never an orbit.
    marker.twinkles = {}
    for i = 1, 8 do
        local star = CreateFrame("Frame", nil, marker)
        star:SetSize(10, 10)
        star:Hide()

        star.h = star:CreateTexture(nil, "OVERLAY")
        star.h:SetPoint("CENTER")
        star.h:SetBlendMode("ADD")

        star.v = star:CreateTexture(nil, "OVERLAY")
        star.v:SetPoint("CENTER")
        star.v:SetBlendMode("ADD")

        star.dot = star:CreateTexture(nil, "OVERLAY")
        star.dot:SetPoint("CENTER")
        star.dot:SetBlendMode("ADD")

        star.phase = (i - 1) / 8
        star.cycleIndex = nil
        marker.twinkles[i] = star
    end

    return marker
end

local function Frac(value)
    return value - math.floor(value)
end

local function TwinklePosition(star, index, cycleIndex, radius)
    if star.cycleIndex == cycleIndex then return end
    star.cycleIndex = cycleIndex

    -- Deterministic pseudo-random placement keeps the effect stable without
    -- touching Lua's global random seed. The position changes only while the
    -- star is fully faded out at a cycle boundary.
    local seedA = math.sin((cycleIndex + 1) * (index + 7) * 12.9898) * 43758.5453
    local seedB = math.sin((cycleIndex + 3) * (index + 11) * 78.233) * 24634.6345
    local angle = Frac(seedA) * math.pi * 2
    local distance = radius * (0.68 + 0.30 * Frac(seedB))
    local x = math.cos(angle) * distance
    local y = math.sin(angle) * distance

    star:ClearAllPoints()
    star:SetPoint("CENTER", marker, "CENTER", x, y)
end

local function ApplyMarkerVisual()
    local saved = QMC:Saved()
    local m = EnsureMarker()
    local size = Clamp(saved.worldObjectAssistSize, 24, 96)
    local opacity = Clamp(saved.worldObjectAssistOpacity, 0.30, 1.00)
    local echoStrength = Clamp(saved.worldObjectAssistGlowStrength, 0.00, 1.00)
    local rgb = COLORS[saved.worldObjectAssistColor] or COLORS.green
    local r, g, b = rgb[1], rgb[2], rgb[3]

    m.baseSize = size
    m.baseOpacity = opacity
    m.baseEchoStrength = echoStrength
    m.markerR, m.markerG, m.markerB = r, g, b
    m:SetSize(size * 2.65, size * 2.65)
    m:SetAlpha(1)

    ApplyQuestIcon(m.icon)
    m.icon:ClearAllPoints()
    m.icon:SetPoint("CENTER", m, "CENTER", 0, 0)
    m.icon:SetSize(size, size)
    m.icon:SetVertexColor(r, g, b, 1)
    m.icon:SetAlpha(opacity)
    m.icon:Show()

    for _, echo in ipairs(m.echoes or {}) do
        ApplyQuestIcon(echo)
        echo:ClearAllPoints()
        echo:SetPoint("CENTER", m, "CENTER", 0, 0)
        echo:SetVertexColor(r, g, b, 1)
        echo:SetSize(size, size)
        echo:SetAlpha(0)
        echo:SetShown(saved.worldObjectAssistPulse and echoStrength > 0.01)
    end

    local twinkleStrength = Clamp(saved.worldObjectAssistSparkleStrength, 0.20, 1.00)
    local starSize = math.max(5, size * (0.075 + 0.055 * twinkleStrength))
    for _, star in ipairs(m.twinkles or {}) do
        star:SetSize(starSize, starSize)
        star.h:SetSize(starSize, math.max(1, starSize * 0.16))
        star.v:SetSize(math.max(1, starSize * 0.16), starSize)
        star.dot:SetSize(math.max(1, starSize * 0.20), math.max(1, starSize * 0.20))
        star.h:SetColorTexture(math.min(1, r + 0.35), math.min(1, g + 0.35), math.min(1, b + 0.35), 1)
        star.v:SetColorTexture(math.min(1, r + 0.35), math.min(1, g + 0.35), math.min(1, b + 0.35), 1)
        star.dot:SetColorTexture(1, 1, 1, 1)
        star:SetAlpha(0)
        star:SetShown(saved.worldObjectAssistSparkles and true or false)
    end
end

local function UpdatePulse()
    if not (marker and marker:IsShown()) then return end
    local saved = QMC:Saved()
    local now = type(GetTime) == "function" and GetTime() or 0
    local speed = Clamp(saved.worldObjectAssistPulseSpeed, 0.4, 2.5)
    local size = marker.baseSize or 48
    local opacity = marker.baseOpacity or 0.95
    local echoStrength = marker.baseEchoStrength or 0.65

    -- Keep the readable center icon essentially still. The pulse is an echo:
    -- three copies of the exact same quest icon radiate outward and fade away.
    marker.icon:SetSize(size, size)
    marker.icon:SetAlpha(opacity)

    if saved.worldObjectAssistPulse and echoStrength > 0.01 then
        local echoRate = speed * 0.72
        for _, echo in ipairs(marker.echoes or {}) do
            local cycle = Frac(now * echoRate + (echo.phase or 0))
            local ease = 1 - cycle
            local scale = 1.00 + cycle * (0.72 + 0.28 * echoStrength)
            local alpha = ease * ease * (0.16 + 0.34 * echoStrength) * opacity
            echo:SetSize(size * scale, size * scale)
            echo:SetAlpha(alpha)
            echo:Show()
        end
    else
        for _, echo in ipairs(marker.echoes or {}) do
            echo:Hide()
        end
    end

    if saved.worldObjectAssistSparkles then
        local strength = Clamp(saved.worldObjectAssistSparkleStrength, 0.20, 1.00)
        local twinkleRate = 0.75 + speed * 0.28
        local radius = size * (0.82 + 0.32 * strength)
        for i, star in ipairs(marker.twinkles or {}) do
            local total = now * twinkleRate + (star.phase or 0)
            local cycleIndex = math.floor(total)
            local cycle = Frac(total)
            TwinklePosition(star, i, cycleIndex, radius)

            local alpha = math.sin(math.pi * cycle)
            alpha = alpha * alpha * alpha * alpha
            star:SetAlpha(alpha * strength * opacity)
            star:Show()
        end
    else
        for _, star in ipairs(marker.twinkles or {}) do
            star:Hide()
        end
    end
end

local function PositionMarker(m, plate, softFrame)
    local saved = QMC:Saved()
    local size = Clamp(saved.worldObjectAssistSize, 24, 96)
    local xOffset = Clamp(saved.worldObjectAssistOffsetX, -80, 80)
    local yOffset = Clamp(saved.worldObjectAssistOffsetY, -80, 140)

    m:ClearAllPoints()

    local unitFrame = plate and plate.UnitFrame
    local nameRegion = unitFrame and unitFrame.name
    if saved.worldObjectAssistAutoPosition and nameRegion and nameRegion.IsShown and nameRegion:IsShown() then
        local visualRadius = size * 0.5
        if saved.worldObjectAssistPulse then
            local strength = Clamp(saved.worldObjectAssistGlowStrength, 0.00, 1.00)
            local maxEchoScale = 1.72 + 0.28 * strength
            visualRadius = math.max(visualRadius, size * maxEchoScale * 0.5)
        end
        if saved.worldObjectAssistSparkles then
            local sparkleStrength = Clamp(saved.worldObjectAssistSparkleStrength, 0.20, 1.00)
            visualRadius = math.max(visualRadius, size * (0.82 + 0.32 * sparkleStrength))
        end

        m:SetParent(unitFrame)
        m:SetPoint("CENTER", nameRegion, "TOP", xOffset, visualRadius + 8 + yOffset)
        return
    end

    m:SetParent(softFrame)
    m:SetPoint("CENTER", softFrame, "CENTER", xOffset, yOffset)
end

local function RefreshMarker(force, serial)
    if serial and serial ~= refreshSerial then return end

    local saved = QMC:Saved()
    if not IsAssistOperational() then
        HideMarker()
        lastGuid = nil
        return
    end

    local name, guid, objectId = CurrentObject()
    if not guid then
        HideMarker()
        lastGuid = nil
        return
    end

    local enhance, reason = ShouldEnhance(name, objectId)
    QMC.worldObjectAssistLastName = name
    QMC.worldObjectAssistLastId = objectId
    QMC.worldObjectAssistLastReason = reason

    if not enhance then
        if force or guid ~= lastGuid then
            QMC.worldObjectAssistBlockCount = (QMC.worldObjectAssistBlockCount or 0) + 1
        end
        HideMarker()
        lastGuid = guid
        return
    end

    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("softinteract")
    local softFrame = plate and plate.UnitFrame and plate.UnitFrame.SoftTargetFrame
    if not (softFrame and softFrame.IsShown and softFrame:IsShown()) then
        -- The soft-interact GUID can arrive a fraction before the nameplate.
        HideMarker()
        return
    end

    -- Guard against a pooled/recycled plate being handed to us while the
    -- soft-interact token is still transitioning. If GetUnit is available,
    -- only attach when that plate's unit resolves to the same GUID.
    if plate.GetUnit and type(UnitGUID) == "function" then
        local plateUnit = plate:GetUnit()
        if plateUnit then
            local plateGuid = UnitGUID(plateUnit)
            if plateGuid and plateGuid ~= guid then
                HideMarker()
                return
            end
        end
    end

    local m = EnsureMarker()
    ApplyMarkerVisual()

    PositionMarker(m, plate, softFrame)
    if m.SetFrameLevel and softFrame.GetFrameLevel then
        m:SetFrameLevel((softFrame:GetFrameLevel() or 1) + 8)
    end

    m:Show()
    UpdatePulse()
    if force or guid ~= lastGuid then
        QMC.worldObjectAssistShowCount = (QMC.worldObjectAssistShowCount or 0) + 1
    end
    lastGuid = guid
end

local function QueueRefresh(hideFirst)
    refreshSerial = refreshSerial + 1
    local serial = refreshSerial
    if hideFirst then HideMarker() end

    local function later(delay)
        if C_Timer and C_Timer.After then
            C_Timer.After(delay, function() RefreshMarker(true, serial) end)
        elseif delay == 0 then
            RefreshMarker(true, serial)
        end
    end

    later(0)
    later(0.03)
    later(0.08)
    later(0.16)
end

local function InteractAnyValue()
    if Enum and Enum.SoftTargetEnableFlags and Enum.SoftTargetEnableFlags.Any ~= nil then
        return Enum.SoftTargetEnableFlags.Any
    end
    return 3
end

local function DesiredInteractRange()
    local value = tonumber(QMC:Saved().worldObjectAssistRange)
    return value == 10 and 10 or 20
end

local function CanChangeSecureCVar()
    return not (type(InCombatLockdown) == "function" and InCombatLockdown())
end

local function ApplyInteractRangePolicy()
    local saved = QMC:Saved()
    if type(GetCVar) ~= "function" or type(SetCVar) ~= "function" then return false end
    if not CanChangeSecureCVar() then return false end

    if saved.worldObjectAssistPreviousSoftTargetInteractRange == nil then
        saved.worldObjectAssistPreviousSoftTargetInteractRange = tostring(GetCVar("SoftTargetInteractRange") or "10")
    end

    local target = tostring(DesiredInteractRange())
    local ok = pcall(SetCVar, "SoftTargetInteractRange", target)
    return ok and tostring(GetCVar("SoftTargetInteractRange") or "") == target
end

local function RestoreInteractRangeAfterFeature()
    local saved = QMC:Saved()
    local previous = saved.worldObjectAssistPreviousSoftTargetInteractRange
    if previous == nil then return true end
    if type(GetCVar) ~= "function" or type(SetCVar) ~= "function" then return false end
    if not CanChangeSecureCVar() then return false end

    local current = tostring(GetCVar("SoftTargetInteractRange") or "")
    local desired = tostring(DesiredInteractRange())
    -- Only undo a value QMC itself owns. If the player changed the CVar to
    -- something else manually while the feature was active, leave it alone.
    if current == desired then
        pcall(SetCVar, "SoftTargetInteractRange", tostring(previous))
    end
    saved.worldObjectAssistPreviousSoftTargetInteractRange = nil
    return true
end

local function EnableInteractKeyForFeature()
    local saved = QMC:Saved()
    if type(GetCVar) ~= "function" or type(SetCVar) ~= "function" then return false end

    if saved.worldObjectAssistPreviousSoftTargetInteract == nil then
        saved.worldObjectAssistPreviousSoftTargetInteract = tostring(GetCVar("softTargetInteract") or "1")
    end
    SetCVar("softTargetInteract", tostring(InteractAnyValue()))
    return true
end

local function RestoreInteractKeyAfterFeature()
    local saved = QMC:Saved()
    local previous = saved.worldObjectAssistPreviousSoftTargetInteract
    if previous ~= nil and type(SetCVar) == "function" then
        local current = type(GetCVar) == "function" and tostring(GetCVar("softTargetInteract") or "") or ""
        -- Only undo our own change. If the player changed the Blizzard setting
        -- again while the experiment was running, respect that newer choice.
        if current == tostring(InteractAnyValue()) then
            SetCVar("softTargetInteract", tostring(previous))
        end
    end
    saved.worldObjectAssistPreviousSoftTargetInteract = nil
end

local function ApplyBlizzardInteractIconPolicy()
    local saved = QMC:Saved()
    if type(GetCVar) ~= "function" or type(SetCVar) ~= "function" then return false end

    if saved.worldObjectAssistHideBlizzardIcons then
        if saved.worldObjectAssistPreviousSoftTargetIconInteract == nil then
            saved.worldObjectAssistPreviousSoftTargetIconInteract = tostring(GetCVar("SoftTargetIconInteract") or "1")
        end
        SetCVar("SoftTargetIconInteract", "0")
    else
        local previous = saved.worldObjectAssistPreviousSoftTargetIconInteract
        if previous ~= nil then
            local current = tostring(GetCVar("SoftTargetIconInteract") or "")
            if current == "0" then SetCVar("SoftTargetIconInteract", tostring(previous)) end
            saved.worldObjectAssistPreviousSoftTargetIconInteract = nil
        end
    end
    return true
end

local function RestoreBlizzardInteractIconPolicy()
    local saved = QMC:Saved()
    local previous = saved.worldObjectAssistPreviousSoftTargetIconInteract
    if previous ~= nil and type(SetCVar) == "function" then
        local current = type(GetCVar) == "function" and tostring(GetCVar("SoftTargetIconInteract") or "") or ""
        if current == "0" then SetCVar("SoftTargetIconInteract", tostring(previous)) end
    end
    saved.worldObjectAssistPreviousSoftTargetIconInteract = nil
end

local function SuspendPoliciesForGamepad()
    HideMarker()
    lastGuid = nil
    refreshSerial = refreshSerial + 1
    RestoreBlizzardInteractIconPolicy()
    RestoreInteractRangeAfterFeature()
    RestoreInteractKeyAfterFeature()
    QMC.worldObjectAssistState = "suspended-gamepad"
end

local function ApplyFeaturePolicies()
    local saved = QMC:Saved()
    if not (saved.enabled and saved.worldObjectAssistEnabled) then return false end

    if ShouldSuspendForGamepad() then
        SuspendPoliciesForGamepad()
        return false
    end

    EnableInteractKeyForFeature()
    ApplyBlizzardInteractIconPolicy()
    ApplyInteractRangePolicy()
    QMC.worldObjectAssistState = "active"
    return true
end

local function UpdateGamepadState(value)
    local newValue = not not value
    if gamepadActive == newValue then return false end
    gamepadActive = newValue

    local saved = QMC:Saved()
    if saved.enabled and saved.worldObjectAssistEnabled and saved.worldObjectAssistSuspendGamepad then
        if gamepadActive then
            SuspendPoliciesForGamepad()
        else
            ApplyFeaturePolicies()
            QueueRefresh(true)
        end
    end
    return true
end

local function EnsureRuntime()
    if runtime then return runtime end

    runtime = CreateFrame("Frame")
    runtime:RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED")
    runtime:RegisterEvent("PLAYER_ENTERING_WORLD")
    runtime:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    runtime:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    runtime:RegisterEvent("QUEST_LOG_UPDATE")
    runtime:RegisterEvent("QUEST_ACCEPTED")
    runtime:RegisterEvent("QUEST_TURNED_IN")
    runtime:RegisterEvent("QUEST_REMOVED")
    runtime:RegisterEvent("PLAYER_REGEN_ENABLED")
    pcall(runtime.RegisterEvent, runtime, "GAME_PAD_ACTIVE_CHANGED")
    runtime:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_ENTERING_WORLD" or event == "QUEST_LOG_UPDATE" or event == "QUEST_ACCEPTED"
            or event == "QUEST_TURNED_IN" or event == "QUEST_REMOVED" then
            activeQuestObjectsDirty = true
        end

        if event == "GAME_PAD_ACTIVE_CHANGED" then
            local isActive = ...
            gamepadActive = not not isActive
            local saved = QMC:Saved()
            if saved.enabled and saved.worldObjectAssistEnabled and saved.worldObjectAssistSuspendGamepad then
                if gamepadActive then
                    SuspendPoliciesForGamepad()
                else
                    ApplyFeaturePolicies()
                end
            end
            QueueRefresh(true)
            return
        end

        if event == "PLAYER_ENTERING_WORLD" then
            gamepadActive = QueryGamepadActive()
            if QMC:Saved().worldObjectAssistEnabled and QMC:Saved().enabled then
                -- Reapply the client policies after a reload/login unless active
                -- gamepad input has suspended World Object Assist.
                ApplyFeaturePolicies()
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            if IsAssistOperational() then
                ApplyInteractRangePolicy()
            else
                -- A gamepad switch can happen in combat. Secure range changes
                -- are retried here as soon as combat ends.
                RestoreInteractRangeAfterFeature()
            end
        end

        QueueRefresh(event == "PLAYER_SOFT_INTERACT_CHANGED" or event == "PLAYER_ENTERING_WORLD")
    end)
    runtime:SetScript("OnUpdate", function(_, elapsed)
        UpdatePulse()

        refreshElapsed = refreshElapsed + (elapsed or 0)
        if refreshElapsed >= 0.25 then
            refreshElapsed = 0
            RefreshMarker(false, refreshSerial)
        end

        policyElapsed = policyElapsed + (elapsed or 0)
        if policyElapsed >= 1.0 then
            policyElapsed = 0
            local saved = QMC:Saved()

            -- GAME_PAD_ACTIVE_CHANGED is the normal path; polling IsUsingGamepad
            -- here is a cheap safety net for reloads/clients that miss an edge.
            local queriedGamepad = QueryGamepadActive()
            if queriedGamepad ~= gamepadActive then
                UpdateGamepadState(queriedGamepad)
            end

            if IsAssistOperational() and type(GetCVar) == "function" then
                if tostring(GetCVar("softTargetInteract") or "") ~= tostring(InteractAnyValue()) then
                    EnableInteractKeyForFeature()
                end
                if saved.worldObjectAssistHideBlizzardIcons and tostring(GetCVar("SoftTargetIconInteract") or "") ~= "0" then
                    ApplyBlizzardInteractIconPolicy()
                end
                if tostring(GetCVar("SoftTargetInteractRange") or "") ~= tostring(DesiredInteractRange()) then
                    ApplyInteractRangePolicy()
                end
            end
        end
    end)
    return runtime
end

function QMC:SetWorldObjectAssistHideBlizzardIcons(value)
    local saved = self:Saved()
    saved.worldObjectAssistHideBlizzardIcons = not not value
    if IsAssistOperational() then
        ApplyBlizzardInteractIconPolicy()
        QueueRefresh(false)
    end
end

function QMC:SetWorldObjectAssistRange(value)
    local saved = self:Saved()
    saved.worldObjectAssistRange = tonumber(value) == 10 and 10 or 20
    if IsAssistOperational() then
        ApplyInteractRangePolicy()
        QueueRefresh(false)
    end
end

function QMC:SetWorldObjectAssistSuspendGamepad(value)
    local saved = self:Saved()
    saved.worldObjectAssistSuspendGamepad = not not value
    gamepadActive = QueryGamepadActive()

    if saved.enabled and saved.worldObjectAssistEnabled then
        if saved.worldObjectAssistSuspendGamepad and gamepadActive then
            SuspendPoliciesForGamepad()
        else
            ApplyFeaturePolicies()
            QueueRefresh(true)
        end
    end
end

function QMC:SetWorldObjectAssistEnabled(value, source)
    local saved = self:Saved()
    saved.worldObjectAssistEnabled = not not value

    if saved.worldObjectAssistEnabled and saved.enabled then
        EnsureRuntime()
        gamepadActive = QueryGamepadActive()
        local active = ApplyFeaturePolicies()
        QueueRefresh(true)
        if source == "ui" or source == "command" then
            if active then
                local suffix = saved.worldObjectAssistHideBlizzardIcons and "; generic Interact icons hidden" or ""
                U.Print("world-object marker on; WoW Interact Key enabled" .. suffix)
            else
                U.Print("world-object marker on; suspended while gamepad input is active")
            end
        end
    else
        HideMarker()
        lastGuid = nil
        refreshSerial = refreshSerial + 1
        RestoreBlizzardInteractIconPolicy()
        RestoreInteractRangeAfterFeature()
        RestoreInteractKeyAfterFeature()
        self.worldObjectAssistState = saved.worldObjectAssistEnabled and "waiting-companion" or "disabled"
        if source == "ui" or source == "command" then
            U.Print("world-object marker off")
        end
    end
end

function QMC:GetWorldObjectAssistCurrent()
    local name, guid, objectId = CurrentObject()
    if not guid then return nil end
    local enhance, reason, known = ShouldEnhance(name, objectId)
    return {
        name = name,
        guid = guid,
        objectId = objectId,
        enhance = enhance,
        reason = reason,
        activeQuest = QuestObjectIsActive(objectId),
        knownQuest = known or KnownQuestObject(objectId),
    }
end

function QMC:WorldObjectAssistIgnoreCurrent()
    local info = self:GetWorldObjectAssistCurrent()
    if not (info and info.objectId) then
        U.Print("object ignore: face a soft-interact GameObject first")
        return false
    end
    local saved = self:Saved()
    local key = tostring(info.objectId)
    saved.worldObjectAssistAllowIds[key] = nil
    saved.worldObjectAssistIgnoreIds[key] = info.name or true
    QueueRefresh(true)
    U.Print("object ignore: " .. tostring(info.name) .. " [" .. key .. "]")
    return true
end

function QMC:WorldObjectAssistAllowCurrent()
    local info = self:GetWorldObjectAssistCurrent()
    if not (info and info.objectId) then
        U.Print("object allow: face a soft-interact GameObject first")
        return false
    end
    local saved = self:Saved()
    local key = tostring(info.objectId)
    saved.worldObjectAssistIgnoreIds[key] = nil
    saved.worldObjectAssistAllowIds[key] = info.name or true
    QueueRefresh(true)
    U.Print("object allow: " .. tostring(info.name) .. " [" .. key .. "]")
    return true
end

function QMC:WorldObjectAssistClearCurrent()
    local info = self:GetWorldObjectAssistCurrent()
    if not (info and info.objectId) then
        U.Print("object clear: face a soft-interact GameObject first")
        return false
    end
    local saved = self:Saved()
    local key = tostring(info.objectId)
    saved.worldObjectAssistIgnoreIds[key] = nil
    saved.worldObjectAssistAllowIds[key] = nil
    QueueRefresh(true)
    U.Print("object filter cleared: " .. tostring(info.name) .. " [" .. key .. "]")
    return true
end

function QMC:ResetWorldObjectAssistAppearance(source)
    local saved = self:Saved()
    saved.worldObjectAssistSize = 48
    saved.worldObjectAssistOpacity = 0.97
    saved.worldObjectAssistColor = "green"
    saved.worldObjectAssistGlowStrength = 0.64
    saved.worldObjectAssistPulse = true
    saved.worldObjectAssistPulseSpeed = 0.90
    saved.worldObjectAssistSparkles = false
    saved.worldObjectAssistSparkleStrength = 0.50
    saved.worldObjectAssistAutoPosition = true
    saved.worldObjectAssistOffsetX = 0
    saved.worldObjectAssistOffsetY = 0
    QueueRefresh(false)
    if source == "command" then U.Print("object marker appearance reset") end
end

function QMC:WorldObjectAssistDebugCurrent()
    local info = self:GetWorldObjectAssistCurrent()
    if not info then
        U.Print("object debug: no soft-interact GameObject")
        return
    end
    local iconCVar = type(GetCVar) == "function" and GetCVar("SoftTargetIconInteract") or "?"
    U.Print("object: " .. tostring(info.name)
        .. " | id " .. tostring(info.objectId or "?")
        .. " | " .. (info.enhance and "highlight" or "normal")
        .. " | " .. tostring(info.reason)
        .. (info.activeQuest and " | active quest match" or "")
        .. (info.knownQuest and (" | quest-linked"
            .. (info.knownQuest.questId and (" q" .. tostring(info.knownQuest.questId)) or "")
            .. (info.knownQuest.itemId and (" item" .. tostring(info.knownQuest.itemId)) or "")) or "")
        .. " | Blizzard icon " .. tostring(iconCVar))
end

local function FindDebugCard(QM, content)
    if not content then return nil end
    local wanted = string.upper((QM.L and QM.L["DEBUG_TOOLS"]) or "DEBUG TOOLS")
    for _, card in ipairs(content.qmCards or {}) do
        for _, region in ipairs({card:GetRegions()}) do
            if region and region.GetText then
                local text = region:GetText()
                if type(text) == "string" and string.upper(text) == wanted then return card end
            end
        end
    end
    return content.qmCards and content.qmCards[2] or nil
end

local function NextY(parent)
    local deepest = 0
    for _, child in ipairs({parent:GetChildren()}) do
        if child and child.IsShown and child:IsShown() and child.GetPoint then
            local point, relativeTo, _, _, y = child:GetPoint(1)
            if point and point:find("^TOP") and (not relativeTo or relativeTo == parent) and type(y) == "number" then
                local bottom = -y + (child:GetHeight() or 0)
                if bottom > deepest then deepest = bottom end
            end
        end
    end
    for _, region in ipairs({parent:GetRegions()}) do
        if region and region.IsShown and region:IsShown() and region.GetPoint then
            local point, relativeTo, _, _, y = region:GetPoint(1)
            if point and point:find("^TOP") and (not relativeTo or relativeTo == parent) and type(y) == "number" then
                local bottom = -y + (region:GetHeight() or 0)
                if bottom > deepest then deepest = bottom end
            end
        end
    end
    return -(deepest + 12)
end

local function AddCheck(parent, font, y, labelText, description, checked, onClick)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", -4, y + 4)
    check:SetChecked(checked)
    check:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)

    local label = parent:CreateFontString(nil, "OVERLAY")
    label:SetFont(font, 11, "")
    label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    label:SetText(labelText)
    label:SetTextColor(0.88, 0.88, 0.92)

    if description then
        local desc = parent:CreateFontString(nil, "OVERLAY")
        desc:SetFont(font, 9, "")
        desc:SetPoint("TOPLEFT", 24, y - 20)
        desc:SetPoint("RIGHT", -2, 0)
        desc:SetJustifyH("LEFT")
        desc:SetText(description)
        desc:SetTextColor(0.56, 0.56, 0.61)
        return y - 48
    end
    return y - 30
end

local function AddSlider(parent, font, y, labelText, minValue, maxValue, step, current, formatter, onChange)
    local label = parent:CreateFontString(nil, "OVERLAY")
    label:SetFont(font, 10, "")
    label:SetPoint("TOPLEFT", 0, y)
    label:SetText(labelText)
    label:SetTextColor(0.84, 0.84, 0.89)

    local value = parent:CreateFontString(nil, "OVERLAY")
    value:SetFont(font, 10, "")
    value:SetPoint("TOPRIGHT", 0, y)
    value:SetTextColor(1.0, 0.82, 0.2)

    local slider = CreateFrame("Slider", nil, parent)
    slider:SetOrientation("HORIZONTAL")
    slider:SetPoint("TOPLEFT", 0, y - 17)
    slider:SetPoint("TOPRIGHT", 0, y - 17)
    slider:SetHeight(18)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local thumb = slider:GetThumbTexture()
    if thumb then thumb:SetSize(22, 22) end
    slider:SetScript("OnValueChanged", function(_, raw)
        local rounded = math.floor(((tonumber(raw) or current) - minValue) / step + 0.5) * step + minValue
        rounded = Clamp(rounded, minValue, maxValue)
        value:SetText(formatter(rounded))
        onChange(rounded)
    end)
    slider:SetValue(current)
    value:SetText(formatter(current))
    return y - 46
end

local function CycleValue(order, current)
    local index = 1
    for i, value in ipairs(order) do
        if value == current then index = i break end
    end
    return order[(index % #order) + 1]
end

local function AddCycle(parent, font, y, labelText, order, labels, getValue, setValue)
    local label = parent:CreateFontString(nil, "OVERLAY")
    label:SetFont(font, 10, "")
    label:SetPoint("LEFT", 0, y - 12)
    label:SetText(labelText)
    label:SetTextColor(0.84, 0.84, 0.89)

    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(118, 23)
    button:SetPoint("TOPRIGHT", 0, y)
    button:SetText(labels[getValue()] or tostring(getValue()))
    button:SetScript("OnClick", function(self)
        local nextValue = CycleValue(order, getValue())
        setValue(nextValue)
        self:SetText(labels[nextValue] or tostring(nextValue))
        QueueRefresh(false)
    end)
    return y - 31
end

local function MakeOptions(order, labels)
    local out = {}
    for _, value in ipairs(order) do
        out[#out + 1] = { value = value, text = labels[value] or tostring(value) }
    end
    return out
end

local function AddSettings(QM, content)
    if not QMC:Saved().enabled then return end
    local card = FindDebugCard(QM, content)
    if not (card and card.content) or card.qmcWorldObjectAssistControls then return end
    card.qmcWorldObjectAssistControls = true

    local UI = QM.OptionsUI
    local extraHeight = 800
    card:SetHeight((card:GetHeight() or 169) + extraHeight)
    if content.GetHeight and content.SetHeight then
        content:SetHeight((content:GetHeight() or 0) + extraHeight)
    end

    local font = type(QM.GetFont) == "function" and QM:GetFont() or "Fonts\\FRIZQT__.TTF"
    local y = NextY(card.content)

    local header = card.content:CreateFontString(nil, "OVERLAY")
    header:SetFont(font, 12, "")
    header:SetPoint("TOPLEFT", 0, y)
    header:SetText("QuestMaster Companion - World Object Assist (Experimental controls)")
    header:SetTextColor(1.0, 0.82, 0.2)
    y = y - 26

    local note = card.content:CreateFontString(nil, "OVERLAY")
    note:SetFont(font, 9, "")
    note:SetPoint("TOPLEFT", 0, y)
    note:SetPoint("RIGHT", -2, 0)
    note:SetJustifyH("LEFT")
    note:SetText("World Object Assist ships enabled in Companion 0.10.0. These Advanced controls remain experimental while quest-object coverage is tuned. Known quest starters, turn-ins, objectives, reverse-quest items, and quest-linked collectibles are recognized; unknown GameObjects still use the denylist fallback.")
    note:SetTextColor(0.60, 0.60, 0.66)
    y = y - 42

    if UI and UI.Toggle and UI.Slider and UI.Dropdown then
        y = UI.Toggle(card.content, y,
            "Enhanced world-object marker",
            "Enables WoW's Interact Key scanner and anchors a QMC-owned quest marker to the selected GameObject.",
            function() return QMC:Saved().worldObjectAssistEnabled end,
            function(v) QMC:SetWorldObjectAssistEnabled(v, "ui") end)

        y = UI.Toggle(card.content, y,
            "Hide Blizzard generic interact icons",
            "Removes the extra gear/speech/anvil/mail icons while keeping soft-interact detection alive. Real quest !/? markers are untouched.",
            function() return QMC:Saved().worldObjectAssistHideBlizzardIcons end,
            function(v) QMC:SetWorldObjectAssistHideBlizzardIcons(v) end)

        y = UI.Toggle(card.content, y,
            "Suspend while gamepad is active",
            "Restores Blizzard's normal controller interaction behavior while gamepad input is active, then resumes World Object Assist when keyboard/mouse becomes active again.",
            function() return QMC:Saved().worldObjectAssistSuspendGamepad end,
            function(v) QMC:SetWorldObjectAssistSuspendGamepad(v) end)

        y = UI.Dropdown(card.content, y, "Detection range", MakeOptions(INTERACT_RANGE_ORDER, INTERACT_RANGE_LABELS),
            function() return tostring(tonumber(QMC:Saved().worldObjectAssistRange) == 10 and 10 or 20) end,
            function(v) QMC:SetWorldObjectAssistRange(tonumber(v)) end)

        y = UI.Slider(card.content, y, "Quest icon size", 24, 96, 4,
            function() return tonumber(QMC:Saved().worldObjectAssistSize) or 54 end,
            function(v) QMC:Saved().worldObjectAssistSize = v; QueueRefresh(false) end,
            function(v) return tostring(math.floor(v + 0.5)) .. " px" end)

        y = UI.Toggle(card.content, y, "Auto position above object name",
            "Keeps the icon and echo above the object label as marker size/effects change. Off uses the native soft-interact anchor.",
            function() return QMC:Saved().worldObjectAssistAutoPosition end,
            function(v) QMC:Saved().worldObjectAssistAutoPosition = v; QueueRefresh(false) end)

        y = UI.Slider(card.content, y, "Vertical offset", -80, 140, 2,
            function() return tonumber(QMC:Saved().worldObjectAssistOffsetY) or 0 end,
            function(v) QMC:Saved().worldObjectAssistOffsetY = v; QueueRefresh(false) end,
            function(v) return string.format("%+.0f px", v) end)

        y = UI.Slider(card.content, y, "Horizontal offset", -80, 80, 2,
            function() return tonumber(QMC:Saved().worldObjectAssistOffsetX) or 0 end,
            function(v) QMC:Saved().worldObjectAssistOffsetX = v; QueueRefresh(false) end,
            function(v) return string.format("%+.0f px", v) end)

        y = UI.Dropdown(card.content, y, "Quest icon color", MakeOptions(COLOR_ORDER, COLOR_LABELS),
            function() return QMC:Saved().worldObjectAssistColor end,
            function(v) QMC:Saved().worldObjectAssistColor = v; QueueRefresh(false) end)

        y = UI.Slider(card.content, y, "Opacity", 0.30, 1.00, 0.05,
            function() return tonumber(QMC:Saved().worldObjectAssistOpacity) or 0.96 end,
            function(v) QMC:Saved().worldObjectAssistOpacity = v; QueueRefresh(false) end,
            function(v) return tostring(math.floor(v * 100 + 0.5)) .. "%" end)

        y = UI.Slider(card.content, y, "Echo strength", 0.00, 1.00, 0.05,
            function() return tonumber(QMC:Saved().worldObjectAssistGlowStrength) or 0.72 end,
            function(v) QMC:Saved().worldObjectAssistGlowStrength = v; QueueRefresh(false) end,
            function(v) return tostring(math.floor(v * 100 + 0.5)) .. "%" end)

        y = UI.Toggle(card.content, y, "Radiating pulse", "Repeats the quest icon outward in fading waves, like an echo.",
            function() return QMC:Saved().worldObjectAssistPulse end,
            function(v) QMC:Saved().worldObjectAssistPulse = v; QueueRefresh(false) end)

        y = UI.Slider(card.content, y, "Pulse speed", 0.40, 2.50, 0.15,
            function() return tonumber(QMC:Saved().worldObjectAssistPulseSpeed) or 1.00 end,
            function(v) QMC:Saved().worldObjectAssistPulseSpeed = v end,
            function(v) return string.format("%.2fx", v) end)

        y = UI.Toggle(card.content, y, "Twinkle effect", "Small independent stars fade in and out around the quest icon. They do not orbit.",
            function() return QMC:Saved().worldObjectAssistSparkles end,
            function(v) QMC:Saved().worldObjectAssistSparkles = v; QueueRefresh(false) end)

        y = UI.Slider(card.content, y, "Twinkle strength", 0.20, 1.00, 0.10,
            function() return tonumber(QMC:Saved().worldObjectAssistSparkleStrength) or 0.55 end,
            function(v) QMC:Saved().worldObjectAssistSparkleStrength = v; QueueRefresh(false) end,
            function(v) return tostring(math.floor(v * 100 + 0.5)) .. "%" end)

        y = UI.Toggle(card.content, y, "Skip common utility objects", nil,
            function() return QMC:Saved().worldObjectAssistBlockCommon end,
            function(v) QMC:Saved().worldObjectAssistBlockCommon = v; QueueRefresh(true) end)
    else
        local saved = QMC:Saved()
        y = AddCheck(card.content, font, y, "Enhanced world-object marker", nil,
            saved.worldObjectAssistEnabled, function(v) QMC:SetWorldObjectAssistEnabled(v, "ui") end)
        y = AddCheck(card.content, font, y, "Hide Blizzard generic interact icons", nil,
            saved.worldObjectAssistHideBlizzardIcons, function(v) QMC:SetWorldObjectAssistHideBlizzardIcons(v) end)
        y = AddCheck(card.content, font, y, "Suspend while gamepad is active",
            "Restores Blizzard controller behavior while gamepad input is active.",
            saved.worldObjectAssistSuspendGamepad, function(v) QMC:SetWorldObjectAssistSuspendGamepad(v) end)
        y = AddCycle(card.content, font, y, "Detection range", INTERACT_RANGE_ORDER, INTERACT_RANGE_LABELS,
            function() return tostring(tonumber(QMC:Saved().worldObjectAssistRange) == 10 and 10 or 20) end,
            function(v) QMC:SetWorldObjectAssistRange(tonumber(v)) end)
        y = AddSlider(card.content, font, y, "Quest icon size", 24, 96, 4,
            tonumber(saved.worldObjectAssistSize) or 54,
            function(v) return tostring(math.floor(v + 0.5)) .. " px" end,
            function(v) QMC:Saved().worldObjectAssistSize = v; QueueRefresh(false) end)
        y = AddCheck(card.content, font, y, "Auto position above object name", nil,
            saved.worldObjectAssistAutoPosition, function(v) QMC:Saved().worldObjectAssistAutoPosition = v; QueueRefresh(false) end)
        y = AddSlider(card.content, font, y, "Vertical offset", -80, 140, 2,
            tonumber(saved.worldObjectAssistOffsetY) or 0,
            function(v) return string.format("%+.0f px", v) end,
            function(v) QMC:Saved().worldObjectAssistOffsetY = v; QueueRefresh(false) end)
        y = AddSlider(card.content, font, y, "Horizontal offset", -80, 80, 2,
            tonumber(saved.worldObjectAssistOffsetX) or 0,
            function(v) return string.format("%+.0f px", v) end,
            function(v) QMC:Saved().worldObjectAssistOffsetX = v; QueueRefresh(false) end)
        y = AddCycle(card.content, font, y, "Quest icon color", COLOR_ORDER, COLOR_LABELS,
            function() return QMC:Saved().worldObjectAssistColor end,
            function(v) QMC:Saved().worldObjectAssistColor = v end)
        y = AddSlider(card.content, font, y, "Echo strength", 0.00, 1.00, 0.05,
            tonumber(saved.worldObjectAssistGlowStrength) or 0.72,
            function(v) return tostring(math.floor(v * 100 + 0.5)) .. "%" end,
            function(v) QMC:Saved().worldObjectAssistGlowStrength = v; QueueRefresh(false) end)
        y = AddCheck(card.content, font, y, "Radiating pulse", nil,
            saved.worldObjectAssistPulse,
            function(v) QMC:Saved().worldObjectAssistPulse = v; QueueRefresh(false) end)
        y = AddCheck(card.content, font, y, "Twinkle effect", nil,
            saved.worldObjectAssistSparkles,
            function(v) QMC:Saved().worldObjectAssistSparkles = v; QueueRefresh(false) end)
    end

    local reset = CreateFrame("Button", nil, card.content, "UIPanelButtonTemplate")
    reset:SetSize(150, 24)
    reset:SetPoint("TOPLEFT", 0, y)
    reset:SetText("Reset marker appearance")
    reset:SetScript("OnClick", function() QMC:ResetWorldObjectAssistAppearance("ui") end)

    local tip = card.content:CreateFontString(nil, "OVERLAY")
    tip:SetFont(font, 9, "")
    tip:SetPoint("TOPLEFT", 0, y - 32)
    tip:SetPoint("RIGHT", -2, 0)
    tip:SetJustifyH("LEFT")
    tip:SetText("Filtering commands: /qmc object ignore | allow | clear | debug | list. Debug reports active-quest, quest-start, turn-in, objective, reverse-item, quest-linked, or default-allow reasons.")
    tip:SetTextColor(0.56, 0.56, 0.61)
end

function QMC:InstallWorldObjectAssist()
    local QM = _G.QuestMaster
    if type(QM) ~= "table" or type(QM.CreateAdvancedTab) ~= "function" then
        self.worldObjectAssistState = "unavailable"
        self.worldObjectAssistIncompatibleReason = "QuestMaster Advanced settings not found"
        return false
    end

    if QM.CreateAdvancedTab == self.worldObjectAssistOptionsWrapper then
        if self:Saved().worldObjectAssistEnabled and self:Saved().enabled then
            EnsureRuntime()
            gamepadActive = QueryGamepadActive()
            ApplyFeaturePolicies()
        end
        return false
    end

    self.worldObjectAssistOptionsOriginal = QM.CreateAdvancedTab
    local original = self.worldObjectAssistOptionsOriginal
    self.worldObjectAssistOptionsWrapper = function(qm, content)
        local out = U.Pack(original(qm, content))
        AddSettings(qm, content)
        return U.unpackValues(out, 1, out.n)
    end
    QM.CreateAdvancedTab = self.worldObjectAssistOptionsWrapper

    EnsureRuntime()
    if self:Saved().worldObjectAssistEnabled and self:Saved().enabled then
        gamepadActive = QueryGamepadActive()
        ApplyFeaturePolicies()
        QueueRefresh(true)
    else
        self.worldObjectAssistState = "disabled"
    end
    return true
end

function QMC:RestoreWorldObjectAssist(reason)
    local QM = _G.QuestMaster
    if QM and self.worldObjectAssistOptionsWrapper and QM.CreateAdvancedTab == self.worldObjectAssistOptionsWrapper
        and self.worldObjectAssistOptionsOriginal then
        QM.CreateAdvancedTab = self.worldObjectAssistOptionsOriginal
    end
    HideMarker()
    lastGuid = nil
    refreshSerial = refreshSerial + 1
    RestoreBlizzardInteractIconPolicy()
    RestoreInteractRangeAfterFeature()
    RestoreInteractKeyAfterFeature()
    self.worldObjectAssistState = reason == "manual" and "disabled" or "restored"
end
