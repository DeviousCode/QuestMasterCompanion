local QMC = _G.QuestMasterCompanion
if not QMC then return end

local U = QMC.Util

local function SplitFields(line)
    local fields = {}
    local start = 1
    while true do
        local at = line:find("|", start, true)
        if not at then
            fields[#fields + 1] = line:sub(start)
            break
        end
        fields[#fields + 1] = line:sub(start, at - 1)
        start = at + 1
    end
    return fields
end

local UNESCAPE = {
    ["\\"] = "\\",
    p = "|",
    c = ":",
    s = ";",
    m = ",",
    n = "\n",
}

local ESCAPE = {
    ["\\"] = "\\\\",
    ["|"] = "\\p",
    [":"] = "\\c",
    [";"] = "\\s",
    [","] = "\\m",
    ["\n"] = "\\n",
    ["\r"] = "",
}

local function Unescape(value)
    if not value or value == "" then return "" end
    return (value:gsub("\\(.)", function(c) return UNESCAPE[c] or c end))
end

local function Escape(value)
    if value == nil then return "" end
    return (tostring(value):gsub("[\\|:;,\n\r]", ESCAPE))
end

local function ParseKillTargets(value)
    local out = {}
    value = Unescape(value)
    for entry in tostring(value or ""):gmatch("[^;]+") do
        local npc, name = entry:match("^%s*(%d+)%s*:%s*(.-)%s*$")
        if not npc then npc = entry:match("^%s*(%d+)%s*$") end
        npc = tonumber(npc)
        if npc and npc > 0 then
            out[#out + 1] = {npcId = npc, name = name ~= "" and name or ("NPC " .. tostring(npc))}
        end
    end
    return out
end

local function SerializeKillTargets(targets)
    local out = {}
    for _, target in ipairs(targets or {}) do
        out[#out + 1] = tostring(target.npcId) .. ":" .. tostring(target.name or ("NPC " .. tostring(target.npcId)))
    end
    return table.concat(out, ";")
end

local function TrimmedLines(text)
    text = tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    local out = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= "" then out[#out + 1] = trimmed end
    end
    return out
end

local function RouteMeta(meta, routeId)
    if not routeId then return nil end
    meta.routes[routeId] = meta.routes[routeId] or {
        groups = {},
        steps = {},
        backgrounds = {},
    }
    return meta.routes[routeId]
end

-- These QMC lines are just author notes until the Companion sees them. We pull
-- them out, hand QuestMaster a normal route, and keep the extra bits ourselves.
function QMC:PreprocessGuideRoute(text, Codec)
    if type(text) ~= "string" or not text:find("QMC|", 1, true) then
        return text, nil, false
    end
    if type(Codec) ~= "table" or type(Codec.Checksum) ~= "function" then
        return nil, nil, true, "Companion guide tasks could not find QuestMaster's route checksum"
    end

    local lines = TrimmedLines(text)
    if #lines < 3 then return text, nil, false end

    local last = SplitFields(lines[#lines])
    if last[1] ~= "END" then return text, nil, false end

    -- Don't accidentally repair a bad paste while stripping our own lines.
    local bodyLines = {}
    for i = 1, #lines - 1 do bodyLines[#bodyLines + 1] = lines[i] end
    local body = table.concat(bodyLines, "\n")
    if last[2] and last[2] ~= "" and last[2]:lower() ~= Codec.Checksum(body) then
        return text, nil, false
    end

    local meta = {version = 3, routes = {}, directiveCount = 0}
    local cleaned = {}
    local currentRouteId, currentStepId, activeGroup
    local seenSteps = {}

    for i = 1, #lines - 1 do
        local line = lines[i]
        local fields = SplitFields(line)
        local tag = fields[1]

        if tag == "R" then
            if activeGroup then
                return nil, nil, true, "QMC group '" .. tostring(activeGroup) .. "' was not closed before the next route"
            end
            currentRouteId = Unescape(fields[2])
            currentStepId = nil
            activeGroup = nil
            seenSteps[currentRouteId] = seenSteps[currentRouteId] or {}
            RouteMeta(meta, currentRouteId)
            cleaned[#cleaned + 1] = line

        elseif tag == "S" then
            currentStepId = Unescape(fields[2])
            if currentRouteId and currentStepId ~= "" then
                seenSteps[currentRouteId][currentStepId] = true
                if activeGroup then
                    local rm = RouteMeta(meta, currentRouteId)
                    local sm = rm.steps[currentStepId] or {}
                    sm.group = activeGroup
                    rm.steps[currentStepId] = sm
                    local group = rm.groups[activeGroup]
                    group.steps[#group.steps + 1] = currentStepId
                end
            end
            cleaned[#cleaned + 1] = line

        elseif tag == "QMC" then
            meta.directiveCount = meta.directiveCount + 1
            local command = string.upper(tostring(fields[2] or ""))

            if command == "GROUP" then
                if not currentRouteId then
                    return nil, nil, true, "QMC GROUP needs to be inside a route"
                end
                if activeGroup then
                    return nil, nil, true, "QMC groups can't be nested yet"
                end

                local groupId = Unescape(fields[3])
                local title = Unescape(fields[4])
                if groupId == "" then return nil, nil, true, "QMC GROUP is missing its id" end

                local rm = RouteMeta(meta, currentRouteId)
                if rm.groups[groupId] then
                    return nil, nil, true, "QMC group '" .. groupId .. "' is used twice in the same route"
                end
                rm.groups[groupId] = {id = groupId, title = title ~= "" and title or groupId, steps = {}}
                activeGroup = groupId
                currentStepId = nil

            elseif command == "ENDGROUP" then
                if not activeGroup then return nil, nil, true, "QMC ENDGROUP does not have an open group" end
                local named = Unescape(fields[3])
                if named ~= "" and named ~= activeGroup then
                    return nil, nil, true, "QMC ENDGROUP says '" .. named .. "' but '" .. activeGroup .. "' is open"
                end
                activeGroup = nil
                currentStepId = nil

            elseif command == "BACKGROUND" then
                if not (currentRouteId and currentStepId) then
                    return nil, nil, true, "QMC BACKGROUND needs to sit right under a route step"
                end

                local untilStep
                for f = 3, #fields do
                    local key, value = tostring(fields[f] or ""):match("^([%w_]+)=(.*)$")
                    if key == "until" then untilStep = Unescape(value) end
                end

                local rm = RouteMeta(meta, currentRouteId)
                local sm = rm.steps[currentStepId] or {}
                if sm.background then
                    return nil, nil, true, "QMC BACKGROUND is already set on step '" .. currentStepId .. "'"
                end
                sm.background = {untilStepId = untilStep ~= "" and untilStep or nil}
                rm.steps[currentStepId] = sm
                rm.backgrounds[#rm.backgrounds + 1] = currentStepId

            elseif command == "XP" then
                if not (currentRouteId and currentStepId) then
                    return nil, nil, true, "QMC XP needs to sit right under a route step"
                end

                local level, minimum
                for f = 3, #fields do
                    local key, value = tostring(fields[f] or ""):match("^([%w_]+)=(.*)$")
                    if key == "level" then level = tonumber(Unescape(value)) end
                    if key == "min" then minimum = tonumber(Unescape(value)) end
                end

                if not level or level < 1 or level ~= math.floor(level) then
                    return nil, nil, true, "QMC XP on '" .. currentStepId .. "' needs a whole level"
                end
                if not minimum or minimum < 0 or minimum ~= math.floor(minimum) then
                    return nil, nil, true, "QMC XP on '" .. currentStepId .. "' needs a whole min XP value"
                end

                local rm = RouteMeta(meta, currentRouteId)
                local sm = rm.steps[currentStepId] or {}
                if sm.xp then
                    return nil, nil, true, "QMC XP is already set on step '" .. currentStepId .. "'"
                end
                sm.xp = {level = level, min = minimum}
                rm.steps[currentStepId] = sm

            elseif command == "KILL" then
                if not (currentRouteId and currentStepId) then
                    return nil, nil, true, "QMC KILL needs to sit right under a route step"
                end

                local count, targets
                for f = 3, #fields do
                    local key, value = tostring(fields[f] or ""):match("^([%w_]+)=(.*)$")
                    if key == "count" then count = tonumber(Unescape(value)) end
                    if key == "targets" then targets = ParseKillTargets(value) end
                end

                if not count or count < 1 or count ~= math.floor(count) then
                    return nil, nil, true, "QMC KILL on '" .. currentStepId .. "' needs a whole count"
                end
                if not targets or #targets == 0 then
                    return nil, nil, true, "QMC KILL on '" .. currentStepId .. "' needs at least one target"
                end

                local rm = RouteMeta(meta, currentRouteId)
                local sm = rm.steps[currentStepId] or {}
                if sm.kill then
                    return nil, nil, true, "QMC KILL is already set on step '" .. currentStepId .. "'"
                end
                sm.kill = {count = count, targets = targets}
                rm.steps[currentStepId] = sm

            elseif command == "TIP" then
                if not (currentRouteId and currentStepId) then
                    return nil, nil, true, "QMC TIP needs to sit under a route step"
                end

                local tip = Unescape(fields[3])
                if tip == "" then return nil, nil, true, "QMC TIP on '" .. currentStepId .. "' is empty" end

                local rm = RouteMeta(meta, currentRouteId)
                local sm = rm.steps[currentStepId] or {}
                sm.tip = tip
                rm.steps[currentStepId] = sm

            else
                return nil, nil, true, "unknown QMC route command '" .. tostring(fields[2]) .. "'"
            end

        else
            cleaned[#cleaned + 1] = line
        end
    end

    if activeGroup then
        return nil, nil, true, "QMC group '" .. tostring(activeGroup) .. "' was not closed"
    end

    for routeId, rm in pairs(meta.routes) do
        for _, stepId in ipairs(rm.backgrounds) do
            local bg = rm.steps[stepId] and rm.steps[stepId].background
            if bg and bg.untilStepId and not (seenSteps[routeId] and seenSteps[routeId][bg.untilStepId]) then
                return nil, nil, true, "QMC BACKGROUND on '" .. stepId .. "' points at missing step '" .. bg.untilStepId .. "'"
            end
        end
    end

    if meta.directiveCount == 0 then return text, nil, false end

    local cleanBody = table.concat(cleaned, "\n")
    local prepared = cleanBody .. "\nEND|" .. Codec.Checksum(cleanBody)
    return prepared, meta, true
end

function QMC:ValidateGuideMeta(pkg, meta)
    if type(meta) ~= "table" or type(meta.routes) ~= "table" then return true end

    local QM = _G.QuestMaster
    local Schema = QM and QM.Routes and QM.Routes.Schema
    local errors = {}

    for _, route in ipairs(pkg.routes or {}) do
        local rm = meta.routes[route.routeId]
        if rm then
            local stepById, indexById = {}, {}
            for index, step in ipairs(route.steps or {}) do
                stepById[step.stepId] = step
                indexById[step.stepId] = index
            end

            for _, stepId in ipairs(rm.backgrounds or {}) do
                local step = stepById[stepId]
                local bg = rm.steps[stepId] and rm.steps[stepId].background
                if not step then
                    errors[#errors + 1] = "QMC background step '" .. tostring(stepId) .. "' does not exist"
                elseif Schema and type(Schema.StepAutoDetects) == "function" and not Schema.StepAutoDetects(step) then
                    errors[#errors + 1] = "QMC background step '" .. tostring(stepId) .. "' needs an auto-detected QuestMaster step"
                elseif bg and bg.untilStepId then
                    local stopAt = indexById[bg.untilStepId]
                    if not stopAt then
                        errors[#errors + 1] = "QMC background step '" .. tostring(stepId) .. "' has a missing until step"
                    elseif stopAt <= indexById[stepId] then
                        errors[#errors + 1] = "QMC background step '" .. tostring(stepId) .. "' needs an until step later in the route"
                    end
                end
            end

            for stepId, sm in pairs(rm.steps or {}) do
                local step = stepById[stepId]
                if sm.xp and not step then
                    errors[#errors + 1] = "QMC XP step '" .. tostring(stepId) .. "' does not exist"
                end
                if sm.kill then
                    if not step then
                        errors[#errors + 1] = "QMC KILL step '" .. tostring(stepId) .. "' does not exist"
                    elseif not (step.map and step.x and step.y) then
                        errors[#errors + 1] = "QMC KILL step '" .. tostring(stepId) .. "' needs a waypoint"
                    end
                end
            end
        end
    end

    if #errors > 0 then return false, errors end
    return true
end

QMC.routeGuidePending = QMC.routeGuidePending or setmetatable({}, {__mode = "k"})

function QMC:RegisterPendingGuideMeta(pkg, meta)
    if type(pkg) ~= "table" or type(meta) ~= "table" then return end
    self.routeGuidePending[pkg] = meta
end

function QMC:GuideMetaForPackage(pkg)
    if type(pkg) ~= "table" then return nil end
    local pending = self.routeGuidePending and self.routeGuidePending[pkg]
    if pending then return pending end

    local saved = self:Saved().routeGuideMeta
    local packageMeta = saved and saved[pkg.packageId]
    return packageMeta and packageMeta[tostring(pkg.contentVersion)] or nil
end

function QMC:SaveGuideMeta(pkg, meta)
    if type(pkg) ~= "table" or not pkg.packageId or not pkg.contentVersion then return end
    local saved = self:Saved()
    saved.routeGuideMeta = saved.routeGuideMeta or {}
    saved.routeGuideMeta[pkg.packageId] = saved.routeGuideMeta[pkg.packageId] or {}

    if meta and meta.directiveCount and meta.directiveCount > 0 then
        saved.routeGuideMeta[pkg.packageId][tostring(pkg.contentVersion)] = meta
        self.routeGuideLastPackage = pkg.packageId
        self.routeGuideImportCount = (self.routeGuideImportCount or 0) + 1
    else
        saved.routeGuideMeta[pkg.packageId][tostring(pkg.contentVersion)] = nil
    end
end

local function GroupForStep(routeMeta, stepId)
    local sm = routeMeta and routeMeta.steps and routeMeta.steps[stepId]
    return sm and sm.group or nil
end

function QMC:InjectGuideRoute(text, pkg, meta, Codec)
    if type(text) ~= "string" or type(meta) ~= "table" or not meta.directiveCount or meta.directiveCount <= 0 then
        return text
    end

    local lines = TrimmedLines(text)
    if #lines < 2 then return text end

    local bodyLines = {}
    for i = 1, #lines - 1 do bodyLines[#bodyLines + 1] = lines[i] end

    local out = {}
    local currentRouteMeta, currentStepId, openGroup

    local function BeforeNextStep(nextGroup)
        if currentStepId and currentRouteMeta then
            local sm = currentRouteMeta.steps and currentRouteMeta.steps[currentStepId]
            local bg = sm and sm.background
            if bg then
                local line = "QMC|BACKGROUND"
                if bg.untilStepId then line = line .. "|until=" .. Escape(bg.untilStepId) end
                out[#out + 1] = line
            end

            local xp = sm and sm.xp
            if xp then
                out[#out + 1] = "QMC|XP|level=" .. tostring(xp.level) .. "|min=" .. tostring(xp.min)
            end

            local kill = sm and sm.kill
            if kill then
                out[#out + 1] = "QMC|KILL|count=" .. tostring(kill.count)
                    .. "|targets=" .. Escape(SerializeKillTargets(kill.targets))
            end

            if sm and sm.tip and sm.tip ~= "" then
                out[#out + 1] = "QMC|TIP|" .. Escape(sm.tip)
            end
        end

        if openGroup and openGroup ~= nextGroup then
            out[#out + 1] = "QMC|ENDGROUP|" .. Escape(openGroup)
            openGroup = nil
        end

        if nextGroup and nextGroup ~= openGroup and currentRouteMeta then
            local group = currentRouteMeta.groups and currentRouteMeta.groups[nextGroup]
            if group then
                out[#out + 1] = "QMC|GROUP|" .. Escape(group.id) .. "|" .. Escape(group.title)
                openGroup = nextGroup
            end
        end

        currentStepId = nil
    end

    for _, line in ipairs(bodyLines) do
        local fields = SplitFields(line)
        local tag = fields[1]

        if tag == "R" then
            BeforeNextStep(nil)
            local routeId = Unescape(fields[2])
            currentRouteMeta = meta.routes and meta.routes[routeId] or nil
            out[#out + 1] = line

        elseif tag == "S" then
            local stepId = Unescape(fields[2])
            local nextGroup = GroupForStep(currentRouteMeta, stepId)
            BeforeNextStep(nextGroup)
            currentStepId = stepId
            out[#out + 1] = line

        else
            out[#out + 1] = line
        end
    end

    BeforeNextStep(nil)
    local body = table.concat(out, "\n")
    return body .. "\nEND|" .. Codec.Checksum(body)
end

local function ActiveRouteMeta(active)
    local meta = active and QMC:GuideMetaForPackage(active.package)
    return meta and meta.routes and meta.routes[active.routeId] or nil
end

local function IsBehind(status, STATUS)
    return status == STATUS.DONE or status == STATUS.SKIPPED
end

local function BackgroundConfig(active, stepId)
    local rm = ActiveRouteMeta(active)
    local sm = rm and rm.steps and rm.steps[stepId]
    return sm and sm.background or nil
end

local function XPConfig(active, stepId)
    local rm = ActiveRouteMeta(active)
    local sm = rm and rm.steps and rm.steps[stepId]
    return sm and sm.xp or nil
end

local function KillConfig(active, stepId)
    local rm = ActiveRouteMeta(active)
    local sm = rm and rm.steps and rm.steps[stepId]
    return sm and sm.kill or nil
end

local function TipForStep(active, stepId)
    local rm = ActiveRouteMeta(active)
    local sm = rm and rm.steps and rm.steps[stepId]
    return sm and sm.tip or nil
end

local function ReadPlayerXP()
    if type(UnitLevel) ~= "function" or type(UnitXP) ~= "function" then return nil end
    local okLevel, level = pcall(UnitLevel, "player")
    local okXP, xp = pcall(UnitXP, "player")
    if not okLevel or not okXP or type(level) ~= "number" or type(xp) ~= "number" then return nil end
    return level, xp
end

local function XPDone(config)
    if not config then return nil end
    local level, xp = ReadPlayerXP()
    if not level then return nil end
    if level > config.level then return true end
    if level < config.level then return false end
    return xp >= config.min
end

local function KillProgressBucket(active, create)
    if not active then return nil end

    if active.preview then
        if create then active.qmcKillProgress = active.qmcKillProgress or {} end
        return active.qmcKillProgress
    end

    local saved = QMC:Saved()
    if create then saved.routeGuideTaskProgress = saved.routeGuideTaskProgress or {} end
    local root = saved.routeGuideTaskProgress
    if not root then return nil end

    local character = type(UnitGUID) == "function" and UnitGUID("player") or nil
    if not character then
        local name = type(UnitName) == "function" and UnitName("player") or "player"
        local realm = type(GetRealmName) == "function" and GetRealmName() or "realm"
        character = tostring(name) .. "@" .. tostring(realm)
    end

    local packageId = tostring(active.packageId or "")
    local version = tostring(active.contentVersion or "")
    local routeId = tostring(active.routeId or "")
    if create then
        root[character] = root[character] or {}
        root[character][packageId] = root[character][packageId] or {}
        root[character][packageId][version] = root[character][packageId][version] or {}
        root[character][packageId][version][routeId] = root[character][packageId][version][routeId] or {}
    end
    return root[character] and root[character][packageId] and root[character][packageId][version]
        and root[character][packageId][version][routeId] or nil
end

local function ReadKillProgress(active, stepId)
    local bucket = KillProgressBucket(active, false)
    return tonumber(bucket and bucket[stepId]) or 0
end

local function WriteKillProgress(active, stepId, value)
    local bucket = KillProgressBucket(active, true)
    if not bucket then return end
    bucket[stepId] = math.max(0, math.floor(tonumber(value) or 0))
end

local function KillDone(active, stepId, config)
    if not config then return nil end
    return ReadKillProgress(active, stepId) >= (config.count or 1)
end

local function RegisterBackground(active, stepId)
    active.qmcBackground = active.qmcBackground or {}
    if not active.qmcBackground[stepId] then
        active.qmcBackground[stepId] = true
        QMC.routeGuideBackgroundCount = (QMC.routeGuideBackgroundCount or 0) + 1
    end
end

local function RecordBackgroundDone(active, step, STATUS)
    if not (active and step and active.store) then return end
    local recorded = active.store:GetStepStatus(active.packageId, active.routeId,
        active.contentVersion, step.stepId)
    if recorded == STATUS.DONE then return end

    active.store:SetStepStatus(active.packageId, active.routeId,
        active.contentVersion, step.stepId, STATUS.DONE)
    QMC.routeGuideCompleteCount = (QMC.routeGuideCompleteCount or 0) + 1
end

function QMC:UpdateGuideBackgrounds(Engine)
    local active = Engine and Engine.active
    if not active then return end

    local rm = ActiveRouteMeta(active)
    local Schema = _G.QuestMaster and _G.QuestMaster.Routes and _G.QuestMaster.Routes.Schema
    local STATUS = Schema and Schema.STATUS
    if not (rm and STATUS) then
        active.qmcBackground = nil
        return
    end

    active.qmcBackground = active.qmcBackground or {}

    -- Rebuild the tiny watch list on resume too. This only walks QMC background
    -- entries, not the whole route.
    for _, stepId in ipairs(rm.backgrounds or {}) do
        local index = active.indexById and active.indexById[stepId]
        local sm = rm.steps and rm.steps[stepId]
        local bg = sm and sm.background
        local untilIndex = bg and bg.untilStepId and active.indexById and active.indexById[bg.untilStepId]

        if index and index < active.index and (not untilIndex or active.index < untilIndex) then
            local step = active.stepById and active.stepById[stepId]
            local status = step and Engine:EvaluateStep(step, {active = active}) or STATUS.UNKNOWN
            active.status[stepId] = status
            if IsBehind(status, STATUS) then
                if status == STATUS.DONE then RecordBackgroundDone(active, step, STATUS) end
                active.qmcBackground[stepId] = nil
            else
                RegisterBackground(active, stepId)
            end
        elseif untilIndex and active.index >= untilIndex then
            active.qmcBackground[stepId] = nil
        elseif index and active.index <= index then
            active.qmcBackground[stepId] = nil
        end
    end

    for stepId in pairs(active.qmcBackground) do
        local step = active.stepById and active.stepById[stepId]
        local bg = BackgroundConfig(active, stepId)
        local untilIndex = bg and bg.untilStepId and active.indexById and active.indexById[bg.untilStepId]

        if untilIndex and active.index >= untilIndex then
            active.qmcBackground[stepId] = nil
        elseif not step then
            active.qmcBackground[stepId] = nil
        else
            local status = Engine:EvaluateStep(step, {active = active})
            active.status[stepId] = status
            if IsBehind(status, STATUS) then
                if status == STATUS.DONE then RecordBackgroundDone(active, step, STATUS) end
                active.qmcBackground[stepId] = nil
            end
        end
    end
end

local function CurrentGroup(active)
    local step = active and active.route and active.route.steps and active.route.steps[active.index]
    if not step then return nil end
    local rm = ActiveRouteMeta(active)
    local groupId = GroupForStep(rm, step.stepId)
    return groupId and rm.groups and rm.groups[groupId] or nil
end

local function IsGroupedTask(active, step)
    if not (active and step and step.stepId) then return false end
    local rm = ActiveRouteMeta(active)
    return GroupForStep(rm, step.stepId) ~= nil
end

local function SafeItemCount(itemId)
    if C_Item and C_Item.GetItemCount then
        local ok, count = pcall(C_Item.GetItemCount, itemId)
        if ok and type(count) == "number" then return count end
    end
    if _G.GetItemCount then
        local ok, count = pcall(_G.GetItemCount, itemId)
        if ok and type(count) == "number" then return count end
    end
end

local function StepProgress(QM, step)
    if not step then return nil end

    if (step.kind == "BUY" or step.kind == "COLLECT" or step.kind == "VENDOR") and step.itemId then
        local have = SafeItemCount(step.itemId)
        if have then return tostring(have) .. "/" .. tostring(step.count or 1) end
    end

    if step.questId and step.objective and QM.activeQuests then
        local quest = QM.activeQuests[step.questId]
        local objective = quest and quest.objectives and quest.objectives[step.objective]
        if objective and objective.current and objective.required and objective.required > 0 then
            return tostring(objective.current) .. "/" .. tostring(objective.required)
        end
    end
end

local GuideBlock

local function BuildGuideBlock(parent)
    if GuideBlock then
        GuideBlock:SetParent(parent)
        return GuideBlock
    end

    local block = CreateFrame("Frame", "QuestMasterCompanionGuideTasksBlock", parent)
    block:SetHeight(20)

    block.divider = block:CreateTexture(nil, "ARTWORK")
    block.divider:SetHeight(1)
    block.divider:SetPoint("TOPLEFT", 2, 0)
    block.divider:SetPoint("TOPRIGHT", -2, 0)
    block.divider:SetColorTexture(0.32, 0.34, 0.38, 0.5)

    block.group = block:CreateFontString(nil, "OVERLAY")
    block.group:SetJustifyH("LEFT")
    block.group:SetWordWrap(false)

    GuideBlock = block
    return block
end

local function RenderGuideBlock(parent, yOffset, Engine)
    local active = Engine and Engine.active
    if not active then
        if GuideBlock then GuideBlock:Hide() end
        return 0
    end

    -- Background jobs stay quiet now. QuestMaster already shows those quest
    -- objectives below, so drawing them twice just ate tracker space.
    QMC:UpdateGuideBackgrounds(Engine)
    local group = CurrentGroup(active)
    if not group then
        if GuideBlock then GuideBlock:Hide() end
        return 0
    end

    local QM = _G.QuestMaster
    local Schema = QM and QM.Routes and QM.Routes.Schema
    local STATUS = Schema and Schema.STATUS
    local block = BuildGuideBlock(parent)
    local font = type(QM.GetFont) == "function" and QM:GetFont() or "Fonts\\FRIZQT__.TTF"
    local size = tonumber(QM.db and QM.db.profile and QM.db.profile.tracker and QM.db.profile.tracker.fontSize) or 11
    local small = math.max(8, size - 1)
    local used = 8

    block:ClearAllPoints()
    block:SetPoint("TOPLEFT", 1, -(yOffset + 3))
    block:SetWidth(parent:GetWidth() - 2)

    local done = 0
    for _, stepId in ipairs(group.steps or {}) do
        local step = active.stepById and active.stepById[stepId]
        if step and STATUS then
            local status = Engine:EvaluateStep(step, {active = active})
            if IsBehind(status, STATUS) then done = done + 1 end
        end
    end

    block.group:ClearAllPoints()
    block.group:SetPoint("TOPLEFT", 8, -used)
    block.group:SetPoint("TOPRIGHT", -6, -used)
    block.group:SetFont(font, small, "")
    block.group:SetText(tostring(group.title) .. "  |cFF888888" .. done .. "/" .. #(group.steps or {}) .. "|r")
    block.group:SetTextColor(1.0, 0.82, 0.2)
    block.group:Show()
    used = used + 18

    block:SetHeight(used + 3)
    block:Show()
    return used + 5
end

local KillDetails

local function BuildKillDetails(routeBlock)
    if KillDetails then
        KillDetails:SetParent(routeBlock)
        return KillDetails
    end

    local frame = CreateFrame("Frame", "QuestMasterCompanionKillTaskDetails", routeBlock)
    frame.lines = {}
    for i = 1, 8 do
        local line = frame:CreateFontString(nil, "OVERLAY")
        line:SetJustifyH("LEFT")
        line:SetWordWrap(false)
        frame.lines[i] = line
    end
    KillDetails = frame
    return frame
end

local function ShiftDown(frame, amount)
    if not (frame and amount and amount > 0 and frame.GetNumPoints) then return end
    local points = {}
    for i = 1, frame:GetNumPoints() do
        local point, relativeTo, relativePoint, x, y = frame:GetPoint(i)
        points[#points + 1] = {point, relativeTo, relativePoint, x or 0, y or 0}
    end
    if #points == 0 then return end
    frame:ClearAllPoints()
    for _, point in ipairs(points) do
        frame:SetPoint(point[1], point[2], point[3], point[4], point[5] - amount)
    end
end

local function EnsureRouteTooltipHooks(routeBlock, Engine)
    if not (routeBlock and routeBlock.rows) then return end

    for _, row in ipairs(routeBlock.rows) do
        if row and not row.qmcGuideTipHooked and row.HookScript then
            row:HookScript("OnEnter", function(self)
                if QMC.routeGuideState ~= "active" then return end
                local entry = self.entry
                local step = entry and entry.step
                local active = Engine.active
                if not (step and active and GameTooltip) then return end

                local tip = TipForStep(active, step.stepId)
                local kill = KillConfig(active, step.stepId)
                if not tip and not kill then return end

                if tip and tip ~= "" then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine(tip, 0.9, 0.9, 0.9, true)
                end
                if kill then
                    local current = math.min(ReadKillProgress(active, step.stepId), kill.count or 1)
                    GameTooltip:AddLine("Kills: " .. tostring(current) .. "/" .. tostring(kill.count or 1), 1.0, 0.82, 0.2)
                end
                GameTooltip:Show()
            end)
            row.qmcGuideTipHooked = true
        end
    end
end

local function RenderKillTaskInline(Engine)
    local active = Engine and Engine.active
    local step = active and Engine:CurrentStep()
    local kill = step and KillConfig(active, step.stepId)
    local routeBlock = _G.QuestMasterRouteBlock

    if not (kill and routeBlock and routeBlock.rows and routeBlock.rows[1]) then
        if KillDetails then KillDetails:Hide() end
        if routeBlock then EnsureRouteTooltipHooks(routeBlock, Engine) end
        return 0
    end

    EnsureRouteTooltipHooks(routeBlock, Engine)

    local currentRow = routeBlock.rows[1]
    if not currentRow:IsShown() then
        if KillDetails then KillDetails:Hide() end
        return 0
    end

    local QM = _G.QuestMaster
    local font = type(QM.GetFont) == "function" and QM:GetFont() or "Fonts\\FRIZQT__.TTF"
    local size = tonumber(QM.db and QM.db.profile and QM.db.profile.tracker and QM.db.profile.tracker.fontSize) or 11
    local small = math.max(8, size - 1)
    local rowHeight = tonumber(currentRow:GetHeight()) or 15
    local lineCount = math.min(#(kill.targets or {}), 7) + 1
    local extra = rowHeight * lineCount
    local details = BuildKillDetails(routeBlock)

    details:ClearAllPoints()
    details:SetPoint("TOPLEFT", currentRow, "BOTTOMLEFT", 16, 0)
    details:SetPoint("TOPRIGHT", currentRow, "BOTTOMRIGHT", -4, 0)
    details:SetHeight(extra)

    local lineIndex = 1
    for i, target in ipairs(kill.targets or {}) do
        if lineIndex > 7 then break end
        local line = details.lines[lineIndex]
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", 0, -((lineIndex - 1) * rowHeight))
        line:SetPoint("TOPRIGHT", 0, -((lineIndex - 1) * rowHeight))
        line:SetHeight(rowHeight)
        line:SetFont(font, small, "")
        line:SetText(tostring(target.name or ("NPC " .. tostring(target.npcId))))
        line:SetTextColor(0.62, 0.64, 0.69)
        line:Show()
        lineIndex = lineIndex + 1
    end

    local progress = details.lines[lineIndex]
    local current = math.min(ReadKillProgress(active, step.stepId), kill.count or 1)
    progress:ClearAllPoints()
    progress:SetPoint("TOPLEFT", 0, -((lineIndex - 1) * rowHeight))
    progress:SetPoint("TOPRIGHT", 0, -((lineIndex - 1) * rowHeight))
    progress:SetHeight(rowHeight)
    progress:SetFont(font, small, "")
    progress:SetText("Kills  " .. tostring(current) .. "/" .. tostring(kill.count or 1))
    progress:SetTextColor(1.0, 0.82, 0.2)
    progress:Show()

    for i = lineIndex + 1, #details.lines do details.lines[i]:Hide() end
    details:Show()

    -- QuestMaster rows are deliberately one line tall. Slide the rest of its
    -- block down instead of stuffing a paragraph into that one line.
    for i = 2, #(routeBlock.rows or {}) do
        local row = routeBlock.rows[i]
        if row and row:IsShown() then ShiftDown(row, extra) end
    end
    for _, button in ipairs({routeBlock.confirmButton, routeBlock.skipButton, routeBlock.undoButton, routeBlock.pauseButton}) do
        if button and button:IsShown() then ShiftDown(button, extra) end
    end

    routeBlock:SetHeight((routeBlock:GetHeight() or 0) + extra)
    return extra
end

local function NpcIdFromGUID(guid)
    if type(guid) ~= "string" then return nil end
    local index = 0
    for part in guid:gmatch("[^-]+") do
        index = index + 1
        if index == 6 then return tonumber(part) end
    end
end

local function KillTargetMatches(config, npcId)
    if not (config and npcId) then return false end
    for _, target in ipairs(config.targets or {}) do
        if target.npcId == npcId then return true end
    end
    return false
end

local function CreatureIdFromGUID(guid)
    if type(guid) ~= "string" then return nil end

    if C_CreatureInfo and type(C_CreatureInfo.GetCreatureID) == "function" then
        local ok, npcId = pcall(C_CreatureInfo.GetCreatureID, guid)
        if ok and tonumber(npcId) then return tonumber(npcId) end
    end

    return NpcIdFromGUID(guid)
end

local function HandlePartyKill(Engine, attackerGUID, targetGUID)
    local active = Engine and Engine.active
    local step = active and not active.paused and Engine:CurrentStep()
    local config = step and KillConfig(active, step.stepId)
    if not config then return end

    local npcId = CreatureIdFromGUID(targetGUID)
    if not KillTargetMatches(config, npcId) then return end

    local current = ReadKillProgress(active, step.stepId)
    if current >= config.count then return end

    WriteKillProgress(active, step.stepId, math.min(config.count, current + 1))
    active.status[step.stepId] = nil
    QMC.routeGuideKillCount = (QMC.routeGuideKillCount or 0) + 1

    -- Refresh right away so the counter feels live, then let the normal route
    -- evaluation move us to the vendor when the last kill lands.
    Engine:Refresh()
    if type(Engine.ScheduleEvaluate) == "function" then
        Engine:ScheduleEvaluate()
    else
        Engine:Evaluate()
        Engine:Refresh()
    end
end

function QMC:GuideTasksCompatibilityCheck()
    local QM = _G.QuestMaster
    local Routes = QM and QM.Routes
    local Codec = Routes and Routes.Codec
    local Library = Routes and Routes.Library
    local Engine = Routes and Routes.Engine
    local Tracker = Routes and Routes.Tracker
    local Schema = Routes and Routes.Schema

    if not (Codec and type(Codec.Encode) == "function" and type(Codec.Checksum) == "function") then
        return false, "route codec changed"
    end
    if not (Library and type(Library.Store) == "function") then return false, "route library changed" end
    if not (Engine and type(Engine.Advance) == "function" and type(Engine.Evaluate) == "function"
        and type(Engine.EvaluateStep) == "function" and type(Engine.StepLabel) == "function"
        and type(Engine.UpcomingSteps) == "function") then
        return false, "route engine changed"
    end
    if not (Tracker and type(Tracker.Render) == "function") then return false, "route tracker changed" end
    if not (Schema and Schema.STATUS and type(Schema.StepAutoDetects) == "function") then
        return false, "route schema changed"
    end
    return true
end

function QMC:InstallGuideTasks()
    if not self:Saved().enabled then
        self.routeGuideState = "disabled"
        return false
    end

    local compatible, why = self:GuideTasksCompatibilityCheck()
    if not compatible then
        self.routeGuideState = "incompatible"
        self.routeGuideIncompatibleReason = why
        return false
    end

    local QM = _G.QuestMaster
    local Routes = QM.Routes
    local Codec, Library, Engine, Tracker = Routes.Codec, Routes.Library, Routes.Engine, Routes.Tracker

    if self.routeGuideStoreWrapper and Library.Store == self.routeGuideStoreWrapper
        and self.routeGuideEncodeWrapper and Codec.Encode == self.routeGuideEncodeWrapper
        and self.routeGuideAdvanceWrapper and Engine.Advance == self.routeGuideAdvanceWrapper
        and self.routeGuideEvaluateWrapper and Engine.Evaluate == self.routeGuideEvaluateWrapper
        and self.routeGuideEvaluateStepWrapper and Engine.EvaluateStep == self.routeGuideEvaluateStepWrapper
        and self.routeGuideUpcomingWrapper and Engine.UpcomingSteps == self.routeGuideUpcomingWrapper
        and self.routeGuideStepLabelWrapper and Engine.StepLabel == self.routeGuideStepLabelWrapper
        and self.routeGuideTrackerWrapper and Tracker.Render == self.routeGuideTrackerWrapper then
        self.routeGuideState = "active"
        return true
    end

    self.routeGuideStoreOriginal = Library.Store
    self.routeGuideEncodeOriginal = Codec.Encode
    self.routeGuideAdvanceOriginal = Engine.Advance
    self.routeGuideEvaluateOriginal = Engine.Evaluate
    self.routeGuideEvaluateStepOriginal = Engine.EvaluateStep
    self.routeGuideUpcomingOriginal = Engine.UpcomingSteps
    self.routeGuideStepLabelOriginal = Engine.StepLabel
    self.routeGuideTrackerOriginal = Tracker.Render

    local originalStore = self.routeGuideStoreOriginal
    self.routeGuideStoreWrapper = function(library, pkg, source, ...)
        local out = U.Pack(originalStore(library, pkg, source, ...))
        if out[1] and type(pkg) == "table" then
            local pending = QMC.routeGuidePending and QMC.routeGuidePending[pkg]
            QMC:SaveGuideMeta(pkg, pending)
            if QMC.routeGuidePending then QMC.routeGuidePending[pkg] = nil end
        end
        return U.unpackValues(out, 1, out.n)
    end

    local originalEncode = self.routeGuideEncodeOriginal
    self.routeGuideEncodeWrapper = function(pkg, ...)
        local out = U.Pack(originalEncode(pkg, ...))
        if type(out[1]) == "string" then
            local meta = QMC:GuideMetaForPackage(pkg)
            if meta then out[1] = QMC:InjectGuideRoute(out[1], pkg, meta, Codec) end
        end
        return U.unpackValues(out, 1, out.n)
    end

    local originalAdvance = self.routeGuideAdvanceOriginal
    self.routeGuideAdvanceWrapper = function(engine, ...)
        local moved = originalAdvance(engine, ...)
        local active = engine.active
        local Schema = Routes.Schema
        local STATUS = Schema and Schema.STATUS
        if not (active and STATUS) then return moved end

        while true do
            local step, index = engine:CurrentStep()
            local bg = step and BackgroundConfig(active, step.stepId)
            if not (step and bg) then break end

            local status = engine:EvaluateStep(step, {active = active})
            active.status[step.stepId] = status
            if IsBehind(status, STATUS) then
                if originalAdvance(engine) then moved = true end
            else
                RegisterBackground(active, step.stepId)
                active.index = index + 1
                active.store:SetIndex(active.packageId, active.routeId, active.contentVersion, active.index)
                moved = true
                originalAdvance(engine)
            end
        end

        QMC:UpdateGuideBackgrounds(engine)
        return moved
    end

    local originalEvaluateStep = self.routeGuideEvaluateStepOriginal
    self.routeGuideEvaluateStepWrapper = function(engine, step, context, ...)
        local status = originalEvaluateStep(engine, step, context, ...)
        local active = type(context) == "table" and context.active or engine.active
        local STATUS = Routes.Schema and Routes.Schema.STATUS
        if not (step and active and STATUS) then return status end

        local kill = KillConfig(active, step.stepId)
        if kill then
            local recorded = active.store and active.store:GetStepStatus(active.packageId, active.routeId,
                active.contentVersion, step.stepId)
            if recorded == STATUS.DONE or recorded == STATUS.SKIPPED then return status end
            if status == STATUS.BLOCKED then return status end
            return KillDone(active, step.stepId, kill) and STATUS.DONE or STATUS.PENDING
        end

        local xp = XPConfig(active, step.stepId)
        if not xp then return status end
        if status == STATUS.DONE or status == STATUS.SKIPPED or status == STATUS.BLOCKED then
            return status
        end

        local done = XPDone(xp)
        if done == true then return STATUS.DONE end
        if done == false then return STATUS.PENDING end
        return STATUS.UNKNOWN
    end

    local originalEvaluate = self.routeGuideEvaluateOriginal
    self.routeGuideEvaluateWrapper = function(engine, ...)
        local out = U.Pack(originalEvaluate(engine, ...))
        QMC:UpdateGuideBackgrounds(engine)
        return U.unpackValues(out, 1, out.n)
    end

    local originalUpcoming = self.routeGuideUpcomingOriginal
    self.routeGuideUpcomingWrapper = function(engine, count, ...)
        local wanted = math.max(1, tonumber(count) or 4)
        local raw = originalUpcoming(engine, 12, ...) or {}
        local out = {}
        for _, entry in ipairs(raw) do
            local step = entry and entry.step
            if not (step and BackgroundConfig(engine.active, step.stepId)) then
                out[#out + 1] = entry
                if #out >= wanted then break end
            end
        end
        return out
    end

    local originalStepLabel = self.routeGuideStepLabelOriginal
    self.routeGuideStepLabelWrapper = function(engine, step, ...)
        local label = originalStepLabel(engine, step, ...)
        if not step then return label end

        local xp = XPConfig(engine.active, step.stepId)
        if xp then
            local level, current = ReadPlayerXP()
            if level == xp.level and current then
                return "Grind XP  |cFFFFD700" .. tostring(current) .. "/" .. tostring(xp.min) .. "|r"
            end
            return label
        end

        if not IsGroupedTask(engine.active, step) then return label end

        if (step.kind == "BUY" or step.kind == "COLLECT" or step.kind == "VENDOR") and step.itemId then
            local have = SafeItemCount(step.itemId)
            if have ~= nil then
                return label .. "  |cFFFFD700" .. tostring(have) .. "/" .. tostring(step.count or 1) .. "|r"
            end
        end

        return label
    end

    local originalTracker = self.routeGuideTrackerOriginal
    self.routeGuideTrackerWrapper = function(tracker, parent, yOffset, ...)
        local used = originalTracker(tracker, parent, yOffset, ...) or 0
        local inline = RenderKillTaskInline(Engine)
        local extra = RenderGuideBlock(parent, (yOffset or 0) + used + inline, Engine)
        return used + inline + extra
    end

    Library.Store = self.routeGuideStoreWrapper
    Codec.Encode = self.routeGuideEncodeWrapper
    Engine.Advance = self.routeGuideAdvanceWrapper
    Engine.EvaluateStep = self.routeGuideEvaluateStepWrapper
    Engine.Evaluate = self.routeGuideEvaluateWrapper
    Engine.UpcomingSteps = self.routeGuideUpcomingWrapper
    Engine.StepLabel = self.routeGuideStepLabelWrapper
    Tracker.Render = self.routeGuideTrackerWrapper

    if not self.routeGuideXPFrame and type(CreateFrame) == "function" then
        local frame = CreateFrame("Frame")
        if pcall(frame.RegisterEvent, frame, "PLAYER_XP_UPDATE") then
            frame:SetScript("OnEvent", function()
                local active = Engine.active
                local step = active and Engine:CurrentStep()
                if not (step and XPConfig(active, step.stepId)) then return end
                wipe(active.status)
                if type(Engine.ScheduleEvaluate) == "function" then
                    Engine:ScheduleEvaluate()
                else
                    Engine:Evaluate()
                    Engine:Refresh()
                end
            end)
            self.routeGuideXPFrame = frame
        end
    end

    if not self.routeGuideKillFrame and type(CreateFrame) == "function" then
        local frame = CreateFrame("Frame")
        if pcall(frame.RegisterEvent, frame, "PARTY_KILL") then
            frame:SetScript("OnEvent", function(_, _, attackerGUID, targetGUID)
                HandlePartyKill(Engine, attackerGUID, targetGUID)
            end)
            self.routeGuideKillFrame = frame
        end
    end

    self.routeGuideState = "active"
    self.routeGuideIncompatibleReason = nil
    return true
end

function QMC:RestoreGuideTasks(reason)
    local QM = _G.QuestMaster
    local Routes = QM and QM.Routes
    local Codec = Routes and Routes.Codec
    local Library = Routes and Routes.Library
    local Engine = Routes and Routes.Engine
    local Tracker = Routes and Routes.Tracker

    if Library and self.routeGuideStoreWrapper and Library.Store == self.routeGuideStoreWrapper
        and type(self.routeGuideStoreOriginal) == "function" then
        Library.Store = self.routeGuideStoreOriginal
    end
    if Codec and self.routeGuideEncodeWrapper and Codec.Encode == self.routeGuideEncodeWrapper
        and type(self.routeGuideEncodeOriginal) == "function" then
        Codec.Encode = self.routeGuideEncodeOriginal
    end
    if Engine and self.routeGuideAdvanceWrapper and Engine.Advance == self.routeGuideAdvanceWrapper
        and type(self.routeGuideAdvanceOriginal) == "function" then
        Engine.Advance = self.routeGuideAdvanceOriginal
    end
    if Engine and self.routeGuideEvaluateWrapper and Engine.Evaluate == self.routeGuideEvaluateWrapper
        and type(self.routeGuideEvaluateOriginal) == "function" then
        Engine.Evaluate = self.routeGuideEvaluateOriginal
    end
    if Engine and self.routeGuideEvaluateStepWrapper and Engine.EvaluateStep == self.routeGuideEvaluateStepWrapper
        and type(self.routeGuideEvaluateStepOriginal) == "function" then
        Engine.EvaluateStep = self.routeGuideEvaluateStepOriginal
    end
    if Engine and self.routeGuideUpcomingWrapper and Engine.UpcomingSteps == self.routeGuideUpcomingWrapper
        and type(self.routeGuideUpcomingOriginal) == "function" then
        Engine.UpcomingSteps = self.routeGuideUpcomingOriginal
    end
    if Engine and self.routeGuideStepLabelWrapper and Engine.StepLabel == self.routeGuideStepLabelWrapper
        and type(self.routeGuideStepLabelOriginal) == "function" then
        Engine.StepLabel = self.routeGuideStepLabelOriginal
    end
    if Tracker and self.routeGuideTrackerWrapper and Tracker.Render == self.routeGuideTrackerWrapper
        and type(self.routeGuideTrackerOriginal) == "function" then
        Tracker.Render = self.routeGuideTrackerOriginal
    end

    if self.routeGuideXPFrame then
        if self.routeGuideXPFrame.UnregisterAllEvents then
            pcall(self.routeGuideXPFrame.UnregisterAllEvents, self.routeGuideXPFrame)
        end
        self.routeGuideXPFrame = nil
    end

    if self.routeGuideKillFrame then
        if self.routeGuideKillFrame.UnregisterAllEvents then
            pcall(self.routeGuideKillFrame.UnregisterAllEvents, self.routeGuideKillFrame)
        end
        self.routeGuideKillFrame = nil
    end

    if GuideBlock then GuideBlock:Hide() end
    if KillDetails then KillDetails:Hide() end
    self.routeGuideEvaluateStepWrapper = nil
    self.routeGuideEvaluateStepOriginal = nil
    self.routeGuideUpcomingWrapper = nil
    self.routeGuideUpcomingOriginal = nil
    self.routeGuideState = reason == "manual" and "disabled" or "inactive"
end
