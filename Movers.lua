--[[--------------------------------------------------------------------------
    CorpUI - poignees de deplacement (facon ElvUI)
    "Deverrouiller l interface" (onglet General) affiche :
      - une grille plein ecran (axes du centre en rouge, pas reglable) ;
      - une poignee bleue sur chaque cadre deplacable ;
      - un petit panneau de reglage : cadre selectionne, X / Y saisissables
        (centre du cadre, 0 0 = milieu de l ecran), miroir (X -> -X),
        fleches 1 px (Maj = 10), aimantation, pas de la grille, verrouiller.
    En glissant, le cadre s aimante aux bords et aux centres des autres
    cadres deja places et a ceux de l ecran (Maj enfoncee = pas d aimant).
    Les fleches du clavier deplacent aussi le cadre selectionne.
    Position enregistree : coin haut-gauche (store.rel = "BOTTOMLEFT"),
    arrondie a l unite. Rien ne bouge en combat ; entrer en combat
    reverrouille l interface.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

ns.movers = {}
ns.moversShown = false

local SNAP = 8          -- distance d aimantation
local grid, guides, panel
local selected, dragging

local function opts()
    local r = ns.InitRoot()
    r.movers = r.movers or {}
    if r.movers.grid == nil then r.movers.grid = 32 end
    if r.movers.snap == nil then r.movers.snap = true end
    return r.movers
end

---------------------------------------------------------------------------
-- Grille
---------------------------------------------------------------------------

local function pixelLine(t, vertical)
    if vertical then t:SetWidth(1) else t:SetHeight(1) end
    if t.SetSnapToPixelGrid then
        pcall(t.SetSnapToPixelGrid, t, false)
        pcall(t.SetTexelSnappingBias, t, 0)
    end
end

local function buildGrid()
    if not grid then
        grid = CreateFrame("Frame", "CorpUIGrid", UIParent)
        grid:SetAllPoints(UIParent)
        grid:SetFrameStrata("BACKGROUND")
        grid.lines = {}
    end
    for _, t in ipairs(grid.lines) do t:Hide() end
    local size = opts().grid
    local n = 0
    local function line(vertical, offset, center)
        n = n + 1
        local t = grid.lines[n] or grid:CreateTexture(nil, "BACKGROUND")
        grid.lines[n] = t
        t:ClearAllPoints()
        -- TOP / LEFT : milieu du bord, le decalage part donc du centre
        if vertical then
            t:SetPoint("TOP", grid, "TOP", offset, 0)
            t:SetPoint("BOTTOM", grid, "BOTTOM", offset, 0)
        else
            t:SetPoint("LEFT", grid, "LEFT", 0, offset)
            t:SetPoint("RIGHT", grid, "RIGHT", 0, offset)
        end
        pixelLine(t, vertical)
        if center then t:SetColorTexture(1, 0.2, 0.2, 0.8) else t:SetColorTexture(0, 0, 0, 0.55) end
        t:Show()
    end
    line(true, 0, true)
    line(false, 0, true)
    for i = 1, math.floor(UIParent:GetWidth() / 2 / size) do
        line(true, i * size)
        line(true, -i * size)
    end
    for i = 1, math.floor(UIParent:GetHeight() / 2 / size) do
        line(false, i * size)
        line(false, -i * size)
    end
end

-- lignes guides affichees quand un bord s aimante
local function buildGuides()
    guides = CreateFrame("Frame", nil, UIParent)
    guides:SetAllPoints(UIParent)
    guides:SetFrameStrata("FULLSCREEN_DIALOG")
    guides.x = guides:CreateTexture(nil, "OVERLAY")
    guides.x:SetColorTexture(0.2, 1, 1, 0.9)
    pixelLine(guides.x, true)
    guides.y = guides:CreateTexture(nil, "OVERLAY")
    guides.y:SetColorTexture(0.2, 1, 1, 0.9)
    pixelLine(guides.y, false)
    guides.x:Hide()
    guides.y:Hide()
end

-- x, y dans l echelle s -> lignes dans l echelle d UIParent
local function showGuides(x, y, s)
    local k = s / UIParent:GetEffectiveScale()
    guides.x:SetShown(x ~= nil)
    guides.y:SetShown(y ~= nil)
    if x then
        guides.x:ClearAllPoints()
        guides.x:SetPoint("TOPLEFT", guides, "TOPLEFT", x * k, 0)
        guides.x:SetPoint("BOTTOMLEFT", guides, "BOTTOMLEFT", x * k, 0)
    end
    if y then
        guides.y:ClearAllPoints()
        guides.y:SetPoint("BOTTOMLEFT", guides, "BOTTOMLEFT", 0, y * k)
        guides.y:SetPoint("BOTTOMRIGHT", guides, "BOTTOMRIGHT", 0, y * k)
    end
end

---------------------------------------------------------------------------
-- Aimantation
---------------------------------------------------------------------------

-- bords d un cadre exprimes dans l echelle s
local function rect(f, s)
    local ok, l, r, t, b = pcall(function() return f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom() end)
    if not ok or not l or not r or not t or not b then return end
    local k = f:GetEffectiveScale() / s
    return l * k, r * k, t * k, b * k
end

-- meilleur ecart (le plus petit sous SNAP) entre nos reperes et les leurs
local function best(mine, theirs)
    local d, at
    for _, a in ipairs(mine) do
        for _, b in ipairs(theirs) do
            local e = b - a
            if math.abs(e) <= SNAP and (not d or math.abs(e) < math.abs(d)) then d, at = e, b end
        end
    end
    return d, at
end

local function snap(m, left, top, w, h, s)
    local xs, ys = {}, {}
    local sl, sr, st, sb = rect(UIParent, s)
    if sl then
        xs = { sl, sr, (sl + sr) / 2 }
        ys = { st, sb, (st + sb) / 2 }
    end
    for _, o in ipairs(ns.movers) do
        if o ~= m and o.target and o.target:IsVisible() then  -- (la minicarte range aussi une simple note ici)
            local l, r, t, b = rect(o.target, s)
            if l and r - l > 2 then
                table.insert(xs, l) table.insert(xs, r) table.insert(xs, (l + r) / 2)
                table.insert(ys, t) table.insert(ys, b) table.insert(ys, (t + b) / 2)
            end
        end
    end
    local dx, gx = best({ left, left + w, left + w / 2 }, xs)
    local dy, gy = best({ top, top - h, top - h / 2 }, ys)
    return left + (dx or 0), top + (dy or 0), gx, gy
end

---------------------------------------------------------------------------
-- Selection, placement
---------------------------------------------------------------------------

local refreshPanel

local function place(m, left, top)
    if InCombatLockdown() then return end
    local store = m.store
    store.point, store.rel = "TOPLEFT", "BOTTOMLEFT"
    store.x, store.y = math.floor(left + 0.5), math.floor(top + 0.5)
    ns.ApplyPos(m.target, store)
    if m.target.SetUserPlaced then pcall(m.target.SetUserPlaced, m.target, false) end
end

local function selectMover(m)
    if selected then selected.tex:SetColorTexture(ns.COLORS.violet[1], ns.COLORS.violet[2], ns.COLORS.violet[3], 0.3) end
    selected = m
    if m then m.tex:SetColorTexture(1, 0.82, 0.25, 0.45) end
    if refreshPanel then refreshPanel() end
end

-- Coordonnees affichees : centre du cadre par rapport au centre de l ecran
-- (0, 0 = milieu ; X = -300 et X = 300 sont symetriques), en unites de
-- l interface (UIParent), quelle que soit l echelle du cadre.
local function centerOf(m)
    local t = m.target
    local l, r, tp, b = t:GetLeft(), t:GetRight(), t:GetTop(), t:GetBottom()
    if not l or not r or not tp or not b then return end
    local k = t:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return (l + r) / 2 * k - UIParent:GetWidth() / 2, (tp + b) / 2 * k - UIParent:GetHeight() / 2
end

local function moveCenterTo(m, cx, cy)
    if InCombatLockdown() then return end
    local t = m.target
    local k = UIParent:GetEffectiveScale() / t:GetEffectiveScale()
    local left = (cx + UIParent:GetWidth() / 2) * k - t:GetWidth() / 2
    local top = (cy + UIParent:GetHeight() / 2) * k + t:GetHeight() / 2
    place(m, left, top)
    ns.PinTop(t, m.store, true)
    if m.onMoved then m.onMoved() end
end

local function nudge(dx, dy)
    local m = selected
    if not m or InCombatLockdown() then return end
    local l, t = m.target:GetLeft(), m.target:GetTop()
    if not l then return end
    if m.store.rel == "BOTTOMLEFT" then l, t = m.store.x, m.store.y end
    place(m, l + dx, t + dy)
    ns.PinTop(m.target, m.store, true)   -- recale si l ecran a borne le cadre
    if m.onMoved then m.onMoved() end
    refreshPanel()
end

---------------------------------------------------------------------------
-- Panneau de reglage
---------------------------------------------------------------------------

local function buildPanel()
    panel = CreateFrame("Frame", "CorpUIMoverPanel", UIParent, "BackdropTemplate")
    panel:SetSize(340, 166)
    panel:SetPoint("TOP", UIParent, "TOP", 0, -220)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    ns.UI.SetBackdrop(panel, 0.95)

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOPLEFT", 10, -10)
    panel.title:SetPoint("TOPRIGHT", -10, -10)
    panel.title:SetHeight(16)
    panel.title:SetJustifyH("LEFT")

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 10, 9)
    hint:SetPoint("BOTTOMRIGHT", -10, 9)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.MOVER_PICK)

    -- X / Y
    local function coord(label, x)
        local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", x, -36)
        fs:SetText(label)
        local e = ns.UI.EditBox(panel, 52, 20)
        e:SetSize(52, 20)
        e:SetPoint("LEFT", fs, "RIGHT", 8, 0)
        e:SetAutoFocus(false)
        e:SetNumeric(false)
        e:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
            local v = tonumber(self:GetText())
            if v and selected then
                local cx, cy = centerOf(selected)
                if cx then
                    if label == "X" then cx = v else cy = v end
                    moveCenterTo(selected, cx, cy)
                end
            end
            refreshPanel()
        end)
        e:SetScript("OnEscapePressed", function(self) self:ClearFocus() refreshPanel() end)
        return e
    end
    panel.ex = coord("X", 12)
    panel.ey = coord("Y", 96)

    -- fleches : 1 px, Maj = 10
    local function arrow(text, dx, dy, x, y)
        local b = ns.UI.Button(panel, text, 24, function()
            local k = IsShiftKeyDown() and 10 or 1
            nudge(dx * k, dy * k)
        end)
        b:SetSize(24, 20)
        b:SetPoint("TOPLEFT", x, y)
    end
    arrow("<", -1, 0, 194, -46)
    arrow(">", 1, 0, 246, -46)
    arrow("^", 0, 1, 220, -30)
    arrow("v", 0, -1, 220, -62)

    panel.snap = ns.UI.Check(panel, L.MOVER_SNAP, function(v) opts().snap = v end)
    panel.snap:SetPoint("TOPLEFT", 8, -64)

    -- pas de la grille
    local gl = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    gl:SetPoint("TOPLEFT", 12, -96)
    panel.gridText = gl
    local function gridStep(d)
        local o = opts()
        o.grid = math.max(8, math.min(256, o.grid + d))
        buildGrid()
        refreshPanel()
    end
    local minus = ns.UI.Button(panel, "-", 24, function() gridStep(-8) end)
    minus:SetSize(24, 20)
    minus:SetPoint("TOPLEFT", 92, -92)
    local plus = ns.UI.Button(panel, "+", 24, function() gridStep(8) end)
    plus:SetSize(24, 20)
    plus:SetPoint("LEFT", minus, "RIGHT", 2, 0)

    local lock = ns.UI.Button(panel, L.MOVER_LOCK, 90, function() ns.SetMoversShown(false) end)
    lock:SetPoint("TOPRIGHT", -10, -92)
    -- miroir : meme place de l autre cote de l axe vertical (X -> -X)
    local mirror = ns.UI.Button(panel, L.MOVER_MIRROR, 70, function()
        if not selected then return end
        local cx, cy = centerOf(selected)
        if cx then moveCenterTo(selected, -cx, cy) end
        refreshPanel()
    end)
    mirror:SetPoint("RIGHT", lock, "LEFT", -4, 0)
    local origin = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    origin:SetPoint("TOPLEFT", 12, -120)
    origin:SetPoint("TOPRIGHT", -10, -120)
    origin:SetJustifyH("LEFT")
    origin:SetText(L.MOVER_CENTER)

    -- fleches du clavier : deplacent le cadre selectionne, le reste passe au jeu
    panel:EnableKeyboard(true)
    pcall(panel.SetPropagateKeyboardInput, panel, true)
    panel:SetScript("OnKeyDown", function(self, key)
        local d = ({ LEFT = { -1, 0 }, RIGHT = { 1, 0 }, UP = { 0, 1 }, DOWN = { 0, -1 } })[key]
        if d and selected and not InCombatLockdown() then
            pcall(self.SetPropagateKeyboardInput, self, false)
            local k = IsShiftKeyDown() and 10 or 1
            nudge(d[1] * k, d[2] * k)
        else
            pcall(self.SetPropagateKeyboardInput, self, true)
        end
    end)
    panel:Hide()
end

refreshPanel = function()
    if not panel then return end
    local o = opts()
    panel.snap:SetChecked(o.snap)
    panel.gridText:SetText(L.MOVER_GRID .. " " .. o.grid)
    if selected then
        local cx, cy = centerOf(selected)
        panel.title:SetText(selected.label)
        if not panel.ex:HasFocus() then panel.ex:SetText(cx and tostring(math.floor(cx + 0.5)) or "") end
        if not panel.ey:HasFocus() then panel.ey:SetText(cy and tostring(math.floor(cy + 0.5)) or "") end
    else
        panel.title:SetText(ns.TITLE)
        panel.ex:SetText("")
        panel.ey:SetText("")
    end
end

---------------------------------------------------------------------------
-- Poignee
---------------------------------------------------------------------------

-- target : cadre a deplacer, si ce n est pas celui que la poignee recouvre
function ns.UI.Mover(frame, store, label, target)
    target = target or frame
    local m = CreateFrame("Frame", nil, frame)
    m:SetAllPoints()
    m:SetFrameStrata("DIALOG")
    m.tex = m:CreateTexture(nil, "OVERLAY")
    m.tex:SetAllPoints()
    m.tex:SetColorTexture(ns.COLORS.violet[1], ns.COLORS.violet[2], ns.COLORS.violet[3], 0.3)
    local fs = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER")
    fs:SetText(label or "")
    m.target, m.store, m.label = target, store, label or ""
    m:EnableMouse(true)
    target:SetClampedToScreen(true)

    m:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or InCombatLockdown() then return end
        selectMover(self)
        local s = target:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        local l, t = target:GetLeft(), target:GetTop()
        if not l then return end
        self.dx, self.dy = cx / s - l, cy / s - t
        dragging = self
    end)
    m:SetScript("OnMouseUp", function(self)
        if dragging ~= self then return end
        dragging = nil
        guides.x:Hide()
        guides.y:Hide()
        if InCombatLockdown() then return end
        ns.PinTop(target, store, true)
        if self.onMoved then self.onMoved() end
        refreshPanel()
    end)
    m:SetScript("OnUpdate", function(self)
        if dragging ~= self then return end
        if InCombatLockdown() then dragging = nil return end
        local s = target:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        local left, top = cx / s - self.dx, cy / s - self.dy
        local gx, gy
        if opts().snap and not IsShiftKeyDown() then
            left, top, gx, gy = snap(self, left, top, target:GetWidth(), target:GetHeight(), s)
        end
        place(self, left, top)
        showGuides(gx, gy, s)
        refreshPanel()
    end)
    m:SetShown(ns.moversShown)
    table.insert(ns.movers, m)
    return m
end

local function setShown(v)
    ns.moversShown = v and true or false
    if not guides then buildGuides() end
    if not panel then buildPanel() end
    if ns.moversShown then buildGrid() end
    if grid then grid:SetShown(ns.moversShown) end
    dragging = nil
    guides.x:Hide()
    guides.y:Hide()
    selectMover(nil)
    panel:SetShown(ns.moversShown)
    for _, m in ipairs(ns.movers) do m:SetShown(ns.moversShown) end
    ns.Changed()
end

function ns.SetMoversShown(v)
    if InCombatLockdown() then
        ns.Say(L.COMBAT_BLOCKED)
        return
    end
    setShown(v)
end

-- entree en combat : on reverrouille (le jeu bloque deja les cadres proteges)
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:SetScript("OnEvent", function()
    if ns.moversShown then setShown(false) end
end)
