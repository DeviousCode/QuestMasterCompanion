local QMC = _G.QuestMasterCompanion
if not QMC then return end

local U = QMC.Util
local POPUP = "QUESTMASTERCOMPANION_REMOVE_ROUTE_PACKAGE"
local EXTRA_BUTTON_SPACE = 24

local function RouteCount(pkg)
    return type(pkg) == "table" and type(pkg.routes) == "table" and #pkg.routes or 0
end

local function PackageName(pkg, packageId)
    if type(pkg) == "table" and type(pkg.name) == "string" and pkg.name ~= "" then
        return pkg.name
    end
    return tostring(packageId or "route package")
end

local function EnsurePopup()
    if type(StaticPopupDialogs) ~= "table" or type(StaticPopup_Show) ~= "function" then
        return false
    end
    if StaticPopupDialogs[POPUP] then return true end

    StaticPopupDialogs[POPUP] = {
        text = "Remove %s from QuestMaster?\n\nThis removes the whole imported package. Saved route progress is kept in case you import it again.",
        button1 = "Remove",
        button2 = CANCEL or "Cancel",
        OnAccept = function(_, data)
            if data and data.packageId then
                QMC:RemoveRoutePackage(data.packageId)
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    return true
end

local function ButtonsOnRow(row)
    local buttons = {}
    for _, child in ipairs({row:GetChildren()}) do
        if child.GetObjectType and child:GetObjectType() == "Button" then
            buttons[#buttons + 1] = child
        end
    end
    table.sort(buttons, function(a, b)
        local _, _, _, ax = a:GetPoint(1)
        local _, _, _, bx = b:GetPoint(1)
        return (ax or 0) < (bx or 0)
    end)
    return buttons
end

local function ShiftRowForX(row, buttons)
    -- QuestMaster reserves room for three 66px buttons. Keep those buttons the
    -- same size and just slide them left a little so the extra X has its own
    -- space instead of sitting on top of Reset.
    for _, button in ipairs(buttons) do
        local point, relativeTo, relativePoint, x, y = button:GetPoint(1)
        if point then
            button:ClearAllPoints()
            button:SetPoint(point, relativeTo or row, relativePoint or point,
                (x or 0) - EXTRA_BUTTON_SPACE, y or 0)
        end
    end

    -- Give the route name/sub-line the same extra room. These are the only
    -- regions created directly on a QuestMaster library row.
    for _, region in ipairs({row:GetRegions()}) do
        if region.GetObjectType and region:GetObjectType() == "FontString" then
            local leftPoint, leftRelative, leftRelativePoint, leftX, leftY = region:GetPoint(1)
            local rightPoint, rightRelative, rightRelativePoint, rightX, rightY = region:GetPoint(2)
            if leftPoint and rightPoint and tostring(rightPoint):find("RIGHT") then
                region:ClearAllPoints()
                region:SetPoint(leftPoint, leftRelative or row, leftRelativePoint or leftPoint, leftX or 0, leftY or 0)
                region:SetPoint(rightPoint, rightRelative or row, rightRelativePoint or rightPoint,
                    (rightX or 0) - EXTRA_BUTTON_SPACE, rightY or 0)
            end
        end
    end
end

local function AddRemoveButton(QM, row, entry)
    if not (row and entry and entry.packageId) then return false end
    if entry.builtin then return false end

    local buttons = ButtonsOnRow(row)

    -- Current QuestMaster has Start/Continue, Test run, Reset. If upstream
    -- grows another action here later, assume the UI changed and stay out of
    -- the way rather than drawing a second delete control on top of it.
    if #buttons ~= 3 then
        return false, #buttons > 3 and "upstream" or "layout"
    end

    ShiftRowForX(row, buttons)

    local UI = QM.OptionsUI
    local COLORS = UI and UI.COLORS
    if not COLORS then return false, "colors" end

    local remove = CreateFrame("Button", nil, row, "BackdropTemplate")
    remove:SetSize(18, 18)
    remove:SetPoint("TOPRIGHT", -2, -2)
    remove:SetBackdrop(QM:GetBackdrop("card"))
    remove:SetBackdropColor(COLORS.bgLight[1], COLORS.bgLight[2], COLORS.bgLight[3], 1)
    remove:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 1)

    remove.text = remove:CreateFontString(nil, "OVERLAY")
    remove.text:SetFont(QM:GetFont(), (UI.FONT_SIZES and UI.FONT_SIZES.tiny) or 9, "")
    remove.text:SetPoint("CENTER", 0, 1)
    remove.text:SetText("x")
    remove.text:SetTextColor(COLORS.error[1], COLORS.error[2], COLORS.error[3])

    local pkg = entry.package
    local packageId = entry.packageId
    local name = PackageName(pkg, packageId)
    local count = RouteCount(pkg)

    remove:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Remove imported package", 1, 1, 1)
        if count > 1 then
            GameTooltip:AddLine(tostring(count) .. " routes will be removed", 0.75, 0.75, 0.75)
        end
        GameTooltip:Show()
    end)
    remove:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 1)
        GameTooltip:Hide()
    end)
    remove:SetScript("OnClick", function()
        QMC:ConfirmRemoveRoutePackage(packageId, name, count)
    end)

    return true
end

local function LibraryRows(content)
    local cards = content and content.qmCards
    local card = type(cards) == "table" and cards[1] or nil
    if not (card and card.content) then return {} end

    local rows = {}
    for _, child in ipairs({card.content:GetChildren()}) do
        local height = child.GetHeight and child:GetHeight() or 0
        local buttons = ButtonsOnRow(child)
        if height >= 28 and height <= 32 and #buttons >= 3 then
            local _, _, _, _, y = child:GetPoint(1)
            rows[#rows + 1] = {frame = child, y = y or 0}
        end
    end

    table.sort(rows, function(a, b) return a.y > b.y end)
    return rows
end

function QMC:ConfirmRemoveRoutePackage(packageId, name, count)
    if not EnsurePopup() then
        U.Print("route remove confirm isn't available")
        return false
    end

    local suffix = count and count > 1 and (" (" .. tostring(count) .. " routes)") or ""
    StaticPopup_Show(POPUP, tostring(name or packageId) .. suffix, nil, {
        packageId = packageId,
    })
    return true
end

function QMC:RemoveRoutePackage(packageId)
    local QM = _G.QuestMaster
    local Routes = QM and QM.Routes
    local Library = Routes and Routes.Library
    local Engine = Routes and Routes.Engine
    if not (Library and type(Library.Remove) == "function") then
        U.Print("route library remove isn't available")
        return false
    end

    if type(Library.IsBuiltin) == "function" and Library:IsBuiltin(packageId) then
        U.Print("bundled QuestMaster routes can't be removed")
        return false
    end

    local pkg = type(Library.Get) == "function" and Library:Get(packageId) or nil
    local name = PackageName(pkg, packageId)

    if Engine and Engine.active and Engine.active.packageId == packageId and type(Engine.Stop) == "function" then
        Engine:Stop()
    end

    local ok, why = Library:Remove(packageId)
    if not ok then
        U.Print("couldn't remove " .. tostring(name) .. ": " .. tostring(why))
        return false
    end

    self.routeRemoveCount = (self.routeRemoveCount or 0) + 1
    self.routeRemoveLastPackage = packageId
    self.routeRemoveState = "used"
    U.Print("removed route package: " .. tostring(name))

    local EditorUI = Routes and Routes.EditorUI
    if EditorUI and type(EditorUI.IsShown) == "function" and EditorUI:IsShown()
        and type(EditorUI.RebuildSoon) == "function" then
        EditorUI:RebuildSoon()
    end
    return true
end

function QMC:DecorateRouteLibrary(content)
    local QM = _G.QuestMaster
    local Library = QM and QM.Routes and QM.Routes.Library
    if not (Library and type(Library.AllRoutes) == "function") then return false end

    local entries = Library:AllRoutes()
    local rows = LibraryRows(content)
    local listed = math.min(#entries, 10, #rows)
    local added = 0

    for i = 1, listed do
        local entry = entries[i]
        if entry and not entry.builtin then
            local ok, why = AddRemoveButton(QM, rows[i].frame, entry)
            if ok then
                added = added + 1
            elseif why == "upstream" then
                self.routeRemoveState = "upstream"
                return false
            end
        end
    end

    self.routeRemoveButtonCount = added
    if self.routeRemoveState ~= "used" then
        self.routeRemoveState = added > 0 and "active" or "standby"
    end
    return added > 0
end


local function PublishedRows(content)
    local rows = {}
    if not content then return rows end

    for _, child in ipairs({content:GetChildren()}) do
        local height = child.GetHeight and child:GetHeight() or 0
        local buttons = ButtonsOnRow(child)
        -- The Route Editor's Published/Installed rows are 24px tall with one
        -- Duplicate button. Draft rows are taller and have two buttons, so
        -- this does not touch those delete controls.
        if height >= 22 and height <= 26 and #buttons == 1 then
            local _, _, _, _, y = child:GetPoint(1)
            rows[#rows + 1] = {frame = child, y = y or 0, button = buttons[1]}
        end
    end

    table.sort(rows, function(a, b) return a.y > b.y end)
    return rows
end

local function AddPublishedRemoveButton(QM, rowInfo, entry)
    if not (rowInfo and rowInfo.frame and rowInfo.button and entry and not entry.builtin) then
        return false
    end

    local row = rowInfo.frame
    local duplicate = rowInfo.button
    local UI = QM.OptionsUI
    local COLORS = UI and UI.COLORS
    if not COLORS then return false end

    -- Keep the Duplicate button the same size; just make a little room for X.
    local point, relativeTo, relativePoint, x, y = duplicate:GetPoint(1)
    if point then
        duplicate:ClearAllPoints()
        duplicate:SetPoint(point, relativeTo or row, relativePoint or point,
            (x or 0) - EXTRA_BUTTON_SPACE, y or 0)
    end

    for _, region in ipairs({row:GetRegions()}) do
        if region.GetObjectType and region:GetObjectType() == "FontString" then
            local leftPoint, leftRelative, leftRelativePoint, leftX, leftY = region:GetPoint(1)
            local rightPoint, rightRelative, rightRelativePoint, rightX, rightY = region:GetPoint(2)
            if leftPoint and rightPoint and tostring(rightPoint):find("RIGHT") then
                region:ClearAllPoints()
                region:SetPoint(leftPoint, leftRelative or row, leftRelativePoint or leftPoint, leftX or 0, leftY or 0)
                region:SetPoint(rightPoint, rightRelative or row, rightRelativePoint or rightPoint,
                    (rightX or 0) - EXTRA_BUTTON_SPACE, rightY or 0)
            end
        end
    end

    local remove = CreateFrame("Button", nil, row, "BackdropTemplate")
    remove:SetSize(18, 18)
    remove:SetPoint("TOPRIGHT", -8, -2)
    remove:SetBackdrop(QM:GetBackdrop("card"))
    remove:SetBackdropColor(COLORS.bgLight[1], COLORS.bgLight[2], COLORS.bgLight[3], 1)
    remove:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 1)

    remove.text = remove:CreateFontString(nil, "OVERLAY")
    remove.text:SetFont(QM:GetFont(), (UI.FONT_SIZES and UI.FONT_SIZES.tiny) or 9, "")
    remove.text:SetPoint("CENTER", 0, 1)
    remove.text:SetText("x")
    remove.text:SetTextColor(COLORS.error[1], COLORS.error[2], COLORS.error[3])

    local pkg = entry.package
    local packageId = entry.packageId
    local name = PackageName(pkg, packageId)
    local count = RouteCount(pkg)

    remove:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Remove imported package", 1, 1, 1)
        if count > 1 then
            GameTooltip:AddLine(tostring(count) .. " routes will be removed", 0.75, 0.75, 0.75)
        end
        GameTooltip:Show()
    end)
    remove:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 1)
        GameTooltip:Hide()
    end)
    remove:SetScript("OnClick", function()
        QMC:ConfirmRemoveRoutePackage(packageId, name, count)
    end)
    return true
end

function QMC:DecoratePublishedRoutePackages()
    local QM = _G.QuestMaster
    local Routes = QM and QM.Routes
    local Library = Routes and Routes.Library
    local frame = _G.QuestMasterRouteEditor
    local content = frame and frame.content
    if not (Library and type(Library.All) == "function" and content) then return false end

    local entries = Library:All()
    local rows = PublishedRows(content)

    -- Only the editor's Drafts home view has one 24px Published row for every
    -- installed package. If that shape does not match, we are on another view
    -- and should leave it alone.
    if #rows ~= #entries then return false end

    local added = 0
    for i, entry in ipairs(entries) do
        if entry and not entry.builtin and AddPublishedRemoveButton(QM, rows[i], entry) then
            added = added + 1
        end
    end
    return added > 0
end

function QMC:RouteLibraryRemoveCompatibilityCheck()
    local QM = _G.QuestMaster
    local Library = QM and QM.Routes and QM.Routes.Library
    if type(QM) ~= "table" then return false, "QuestMaster global is unavailable" end
    if type(QM.CreateRoutesTab) ~= "function" then return false, "Routes tab API changed" end
    if type(Library) ~= "table" or type(Library.AllRoutes) ~= "function" or type(Library.Remove) ~= "function" then
        return false, "route library API changed"
    end
    if not (QM.OptionsUI and QM.OptionsUI.COLORS) then return false, "QuestMaster route UI isn't ready" end
    local EditorUI = QM.Routes and QM.Routes.EditorUI
    if not (EditorUI and type(EditorUI.Draw) == "function") then return false, "Route Editor UI changed" end
    return true
end

function QMC:InstallRouteLibraryRemove()
    if not self:Saved().enabled then
        self.routeRemoveState = "disabled-manual"
        return false
    end

    local compatible, why = self:RouteLibraryRemoveCompatibilityCheck()
    if not compatible then
        self.routeRemoveState = "incompatible"
        self.routeRemoveIncompatibleReason = why
        return false
    end

    local QM = _G.QuestMaster

    if self.routeRemoveWrapper and QM.CreateRoutesTab == self.routeRemoveWrapper then
        if self.routeRemoveState == "loading" then self.routeRemoveState = "standby" end
        return true
    end

    if self.routeRemoveOriginal and QM.CreateRoutesTab ~= self.routeRemoveOriginal then
        self.routeRemoveState = "changed"
        self.routeRemoveIncompatibleReason = "Routes tab builder was replaced by another addon/update"
        return false
    end

    local original = QM.CreateRoutesTab
    self.routeRemoveOriginal = original

    local wrapper = function(selfQM, content, ...)
        local result = U.Pack(original(selfQM, content, ...))
        if QMC:Saved().enabled then
            local ok, err = pcall(QMC.DecorateRouteLibrary, QMC, content)
            if not ok then
                QMC.routeRemoveState = "error"
                QMC.routeRemoveIncompatibleReason = tostring(err)
            end
        end
        return U.unpackValues(result, 1, result.n)
    end

    self.routeRemoveWrapper = wrapper
    QM.CreateRoutesTab = wrapper

    local EditorUI = QM.Routes.EditorUI
    if self.routeRemoveEditorOriginal and EditorUI.Draw ~= self.routeRemoveEditorOriginal then
        self.routeRemoveState = "changed"
        self.routeRemoveIncompatibleReason = "Route Editor draw function was replaced by another addon/update"
        return false
    end

    local originalEditorDraw = EditorUI.Draw
    self.routeRemoveEditorOriginal = originalEditorDraw
    local editorWrapper = function(editor, ...)
        local result = U.Pack(originalEditorDraw(editor, ...))
        if QMC:Saved().enabled then
            pcall(QMC.DecoratePublishedRoutePackages, QMC)
        end
        return U.unpackValues(result, 1, result.n)
    end
    self.routeRemoveEditorWrapper = editorWrapper
    EditorUI.Draw = editorWrapper

    self.routeRemoveState = "standby"
    self.routeRemoveIncompatibleReason = nil
    EnsurePopup()
    return true
end

function QMC:RestoreRouteLibraryRemove(reason)
    local QM = _G.QuestMaster
    if QM and self.routeRemoveWrapper and QM.CreateRoutesTab == self.routeRemoveWrapper
        and type(self.routeRemoveOriginal) == "function" then
        QM.CreateRoutesTab = self.routeRemoveOriginal
    end

    local EditorUI = QM and QM.Routes and QM.Routes.EditorUI
    if EditorUI and self.routeRemoveEditorWrapper and EditorUI.Draw == self.routeRemoveEditorWrapper
        and type(self.routeRemoveEditorOriginal) == "function" then
        EditorUI.Draw = self.routeRemoveEditorOriginal
    end

    self.routeRemoveWrapper = nil
    self.routeRemoveOriginal = nil
    self.routeRemoveEditorWrapper = nil
    self.routeRemoveEditorOriginal = nil
    self.routeRemoveState = reason == "manual" and "disabled-manual" or "inactive"
end
