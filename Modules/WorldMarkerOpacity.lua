local QMC = _G.QuestMasterCompanion
if not QMC then return end

local U = QMC.Util

local function Clamp01(v)
    v = tonumber(v) or 0
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function MarkerDistance(QM)
    if C_Navigation and type(C_Navigation.GetDistance) == "function" then
        local ok, yards = pcall(C_Navigation.GetDistance)
        if ok and type(yards) == "number" and yards >= 0 then return yards end
    end

    local wp = QM and QM.currentWaypoint
    if wp and type(wp.x) == "number" and type(wp.y) == "number" and type(wp.mapId) == "number"
        and type(QM.GetDistanceToPoint) == "function" then
        local ok, yards = pcall(QM.GetDistanceToPoint, QM, wp.x, wp.y, wp.mapId)
        if ok and type(yards) == "number" and yards < 99999 then return yards end
    end
    return nil
end

local function ApplyOpacity(QM, WM)
    if not QMC:Saved().enabled then return end
    local f = WM and WM.marker
    if not f or not f.SetAlpha or (f.IsShown and not f:IsShown()) then return end

    local saved = QMC:Saved()
    local farAlpha = Clamp01(saved.worldMarkerFarAlpha)
    local arrivalAlpha = Clamp01(saved.worldMarkerArrivalAlpha)
    local arrive = 10
    if QM.db and QM.db.profile and QM.db.profile.arrow then
        arrive = tonumber(QM.db.profile.arrow.arrivalDist) or 10
    end
    if arrive <= 0 then arrive = 10 end

    local yards = MarkerDistance(QM)
    local alpha = farAlpha
    if yards then
        if yards <= arrive then
            alpha = arrivalAlpha
        elseif yards < arrive * 3 then
            local t = (yards - arrive) / (arrive * 2)
            alpha = arrivalAlpha + (farAlpha - arrivalAlpha) * t
        end
    end

    f:SetAlpha(Clamp01(alpha))
end

local function FindWorldMarkerCard(QM, content)
    if not content then return nil end
    local wanted = string.upper((QM.L and QM.L["WORLD_MARKER"]) or "WORLD MARKER")

    for _, card in ipairs(content.qmCards or {}) do
        for _, region in ipairs({card:GetRegions()}) do
            if region and region.GetText then
                local text = region:GetText()
                if type(text) == "string" and string.upper(text) == wanted then return card end
            end
        end
    end

    -- Current QuestMaster puts World Marker third on the Navigation tab.
    return content.qmCards and content.qmCards[3] or nil
end

local function NextContentY(parent)
    local deepest = 0
    for _, child in ipairs({parent:GetChildren()}) do
        if child and child.IsShown and child:IsShown() and child.GetPoint then
            local point, relativeTo, _, _, y = child:GetPoint(1)
            if point and point:find("^TOP") and (not relativeTo or relativeTo == parent) and type(y) == "number" then
                local h = child:GetHeight() or 0
                local bottom = -y + h
                if bottom > deepest then deepest = bottom end
            end
        end
    end
    return -(deepest + 8)
end

local function MakeSlider(QM, parent, y, label, getValue, setValue)
    local width = parent:GetWidth()
    if not width or width < 100 then width = 470 end
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, 50)
    row:SetPoint("TOPLEFT", 0, y)

    local font = type(QM.GetFont) == "function" and QM:GetFont() or "Fonts\\FRIZQT__.TTF"

    local name = row:CreateFontString(nil, "OVERLAY")
    name:SetFont(font, 12, "")
    name:SetPoint("TOPLEFT", 0, -1)
    name:SetText(label)
    name:SetTextColor(0.94, 0.94, 0.96)

    local value = row:CreateFontString(nil, "OVERLAY")
    value:SetFont(font, 12, "")
    value:SetPoint("TOPRIGHT", 0, -1)
    value:SetTextColor(1.0, 0.82, 0.2)

    local track = row:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(1, 1, 1, 0.12)
    track:SetPoint("TOPLEFT", 0, -23)
    track:SetPoint("TOPRIGHT", 0, -23)
    track:SetHeight(5)

    local slider = CreateFrame("Slider", nil, row)
    slider:SetOrientation("HORIZONTAL")
    slider:SetPoint("TOPLEFT", 0, -16)
    slider:SetPoint("TOPRIGHT", 0, -16)
    slider:SetHeight(18)
    slider:SetMinMaxValues(0, 100)
    slider:SetValueStep(5)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end

    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local thumb = slider:GetThumbTexture()
    if thumb then thumb:SetSize(24, 24) end

    local low = row:CreateFontString(nil, "OVERLAY")
    low:SetFont(font, 9, "")
    low:SetPoint("TOPLEFT", track, "BOTTOMLEFT", 0, -3)
    low:SetText("0%")
    low:SetTextColor(0.5, 0.5, 0.55)

    local high = row:CreateFontString(nil, "OVERLAY")
    high:SetFont(font, 9, "")
    high:SetPoint("TOPRIGHT", track, "BOTTOMRIGHT", 0, -3)
    high:SetText("100%")
    high:SetTextColor(0.5, 0.5, 0.55)

    slider:SetScript("OnValueChanged", function(_, raw)
        local rounded = math.floor((raw or 0) / 5 + 0.5) * 5
        value:SetText(tostring(rounded) .. "%")
        setValue(rounded / 100)
    end)

    local start = math.floor(Clamp01(getValue()) * 100 + 0.5)
    slider:SetValue(start)
    value:SetText(tostring(start) .. "%")

    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel", function(self, delta)
        if IsShiftKeyDown and IsShiftKeyDown() then
            local v = math.max(0, math.min(100, self:GetValue() + delta * 5))
            self:SetValue(v)
        end
    end)

    QMC.worldMarkerOpacitySliderCount = (QMC.worldMarkerOpacitySliderCount or 0) + 1
    return y - 56
end

local function AddOpacityControls(QM, content)
    if not QMC:Saved().enabled then return end
    local card = FindWorldMarkerCard(QM, content)
    if not card or not card.content or card.qmcOpacityControls then return end
    card.qmcOpacityControls = true

    local y = NextContentY(card.content)
    y = MakeSlider(QM, card.content, y, "Far marker opacity",
        function() return QMC:Saved().worldMarkerFarAlpha end,
        function(v) QMC:Saved().worldMarkerFarAlpha = Clamp01(v) end)
    MakeSlider(QM, card.content, y, "Arrival marker opacity",
        function() return QMC:Saved().worldMarkerArrivalAlpha end,
        function(v) QMC:Saved().worldMarkerArrivalAlpha = Clamp01(v) end)
end

function QMC:InstallWorldMarkerOpacity()
    local QM = _G.QuestMaster
    local WM = QM and QM.WorldMarker
    if type(QM) ~= "table" or type(WM) ~= "table" or type(WM.UpdateMarker) ~= "function"
        or type(QM.CreateArrowTab) ~= "function" then
        self.worldMarkerOpacityState = "unavailable"
        self.worldMarkerOpacityIncompatibleReason = "World Marker settings not found"
        return false
    end

    if WM.UpdateMarker == self.worldMarkerUpdateWrapper and QM.CreateArrowTab == self.worldMarkerOptionsWrapper then
        self.worldMarkerOpacityState = "active"
        return false
    end

    self.worldMarkerUpdateOriginal = WM.UpdateMarker
    self.worldMarkerOptionsOriginal = QM.CreateArrowTab

    local originalUpdate = self.worldMarkerUpdateOriginal
    self.worldMarkerUpdateWrapper = function(wm, dt)
        local out = U.Pack(originalUpdate(wm, dt))
        ApplyOpacity(QM, wm)
        return U.unpackValues(out, 1, out.n)
    end

    local originalOptions = self.worldMarkerOptionsOriginal
    self.worldMarkerOptionsWrapper = function(qm, content)
        local out = U.Pack(originalOptions(qm, content))
        AddOpacityControls(qm, content)
        return U.unpackValues(out, 1, out.n)
    end

    WM.UpdateMarker = self.worldMarkerUpdateWrapper
    QM.CreateArrowTab = self.worldMarkerOptionsWrapper
    self.worldMarkerOpacityState = "active"
    return true
end

function QMC:RestoreWorldMarkerOpacity(reason)
    local QM = _G.QuestMaster
    local WM = QM and QM.WorldMarker
    if WM and self.worldMarkerUpdateWrapper and WM.UpdateMarker == self.worldMarkerUpdateWrapper
        and self.worldMarkerUpdateOriginal then
        WM.UpdateMarker = self.worldMarkerUpdateOriginal
    end
    if QM and self.worldMarkerOptionsWrapper and QM.CreateArrowTab == self.worldMarkerOptionsWrapper
        and self.worldMarkerOptionsOriginal then
        QM.CreateArrowTab = self.worldMarkerOptionsOriginal
    end
    self.worldMarkerOpacityState = reason == "manual" and "disabled" or "restored"
end
