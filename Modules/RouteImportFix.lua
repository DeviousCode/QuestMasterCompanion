local QMC = _G.QuestMasterCompanion
if not QMC then return end

local U = QMC.Util

-- WoW can hand pasted route text back with one extra escape layer on it.
local function RemoveEditBoxEscapeLayer(text)
    if type(text) ~= "string" then return text, false end

    local firstLine = text:match("^%s*([^\r\n]+)") or ""
    if firstLine:sub(1, 9) ~= "QMROUTE||" then
        return text, false
    end

    local cleaned = text:gsub("||", "|")
    cleaned = cleaned:gsub("\\\\", "\\")
    return cleaned, true
end

local function CodecAlreadyHandlesEditBoxText(Codec, Schema)
    if type(Codec) ~= "table" or type(Codec.Decode) ~= "function"
        or type(Codec.Checksum) ~= "function" then
        return false
    end

    local schema = Schema and tonumber(Schema.SCHEMA_VERSION) or 1
    local magic = tostring(Codec.MAGIC or "QMROUTE")
    local body = magic .. "|" .. tostring(schema)
    local canonical = body .. "\nEND|" .. Codec.Checksum(body)
    local escaped = canonical:gsub("\\", "\\\\"):gsub("|", "||")
    local ok, pkg = pcall(Codec.Decode, escaped)
    return ok and type(pkg) == "table" and tonumber(pkg.schemaVersion) == schema
end

function QMC:InstallRouteImportFix()
    if not self:Saved().enabled then
        self.routeImportState = "disabled"
        return false
    end

    local QM = _G.QuestMaster
    local Routes = QM and QM.Routes
    local Codec = Routes and Routes.Codec
    local Schema = Routes and Routes.Schema

    if type(Codec) ~= "table" or type(Codec.Decode) ~= "function" then
        self.routeImportState = "incompatible"
        self.routeImportIncompatibleReason = "route codec not found"
        return false
    end

    if self.routeImportWrapper and Codec.Decode == self.routeImportWrapper then
        self.routeImportState = "active"
        return true
    end

    if self.routeImportOriginal and Codec.Decode ~= self.routeImportOriginal then
        self.routeImportState = "changed"
        self.routeImportIncompatibleReason = "route decoder was replaced by another addon/update"
        return false
    end

    local original = Codec.Decode
    self.routeImportOriginal = original
    self.routeImportNeedsEscapeFix = not CodecAlreadyHandlesEditBoxText(Codec, Schema)

    local wrapper = function(text, ...)
        local cleaned = text
        if QMC.routeImportNeedsEscapeFix then
            local changed
            cleaned, changed = RemoveEditBoxEscapeLayer(cleaned)
            if changed then
                QMC.routeImportNormalizeCount = (QMC.routeImportNormalizeCount or 0) + 1
                QMC.routeImportLastReason = "removed WoW EditBox escape layer"
            end
        end

        local prepared, meta, hadGuide, guideError = cleaned, nil, false, nil
        if type(QMC.PreprocessGuideRoute) == "function" then
            prepared, meta, hadGuide, guideError = QMC:PreprocessGuideRoute(cleaned, Codec)
        end
        if guideError then
            return nil, {guideError}
        end

        local out = U.Pack(original(prepared, ...))
        local pkg = out[1]
        if pkg and meta then
            if type(QMC.ValidateGuideMeta) == "function" then
                local ok, errors = QMC:ValidateGuideMeta(pkg, meta)
                if not ok then return nil, errors end
            end
            QMC:RegisterPendingGuideMeta(pkg, meta)
            QMC.routeGuideParseCount = (QMC.routeGuideParseCount or 0) + 1
            QMC.routeGuideState = "active"
            QMC.routeImportLastReason = "read Companion guide tasks"
        elseif hadGuide and not pkg then
            QMC.routeGuideState = "parse-error"
        end

        return U.unpackValues(out, 1, out.n)
    end

    self.routeImportWrapper = wrapper
    Codec.Decode = wrapper
    self.routeImportState = "active"
    self.routeImportIncompatibleReason = nil
    return true
end

function QMC:RestoreRouteImportFix(reason)
    local QM = _G.QuestMaster
    local Codec = QM and QM.Routes and QM.Routes.Codec

    if Codec and self.routeImportWrapper and Codec.Decode == self.routeImportWrapper
        and type(self.routeImportOriginal) == "function" then
        Codec.Decode = self.routeImportOriginal
    end

    self.routeImportWrapper = nil
    self.routeImportOriginal = nil
    self.routeImportState = reason == "manual" and "disabled" or "inactive"
end
