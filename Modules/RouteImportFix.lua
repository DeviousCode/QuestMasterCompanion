local QMC = _G.QuestMasterCompanion
if not QMC then return end

-- WoW escapes | and \\ when text comes back out of an EditBox. QuestMaster's
-- route format uses both of those characters, so a pasted QMROUTE can reach
-- Codec.Decode with one extra UI escape layer on it.
local function RemoveEditBoxEscapeLayer(text)
    if type(text) ~= "string" then return text, false end

    local firstLine = text:match("^%s*([^\r\n]+)") or ""
    if firstLine:sub(1, 9) ~= "QMROUTE||" then
        return text, false
    end

    -- Every real pipe/backslash was doubled by EditBox:GetText(). Halving the
    -- pairs restores the exact package text, including runs of empty | fields
    -- and the route codec's own \\c / \\m style escapes.
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

    -- Mimic one GetText() pass. If QuestMaster can already decode this, there
    -- is nothing for the Companion to patch.
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

    if CodecAlreadyHandlesEditBoxText(Codec, Schema) then
        self.routeImportState = "upstream"
        self.routeImportIncompatibleReason = nil
        return false
    end

    local original = Codec.Decode
    self.routeImportOriginal = original

    local wrapper = function(text, ...)
        local cleaned, changed = RemoveEditBoxEscapeLayer(text)
        if changed then
            QMC.routeImportNormalizeCount = (QMC.routeImportNormalizeCount or 0) + 1
            QMC.routeImportLastReason = "removed WoW EditBox escape layer"
        end
        return original(cleaned, ...)
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
