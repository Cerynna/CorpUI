--[[--------------------------------------------------------------------------
    CorpUI - module Voyage : la carte du monde

    Calque a nous pose sur le canevas de la carte (WorldMapFrame.
    ScrollContainer.Child), comme les points de vol de la minicarte : aucun
    fournisseur ajoute a la carte de Blizzard, aucun crochet, rien d ecrit
    chez elle.
      Maj + clic gauche : destination du voyage a cet endroit ;
      Maj + clic droit  : annuler le voyage.
    Le calque ne prend la souris que Maj enfoncee : sans Maj, les clics
    vont a la carte comme d habitude (zoom, carte suivante, deplacement).
    Une etoile marque la destination quand la carte affichee la contient.
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local V = ns.Voyage
local num, call = V.num, V.call
local issecret = issecretvalue or function() return false end

local STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
local PIN = 20

local layer, pin
local lastKey

local function canvas()
    local wm = _G.WorldMapFrame
    if type(wm) ~= "table" then return nil end
    local sc = wm.ScrollContainer
    local child = type(sc) == "table" and sc.Child or nil
    if type(child) ~= "table" or not child.GetWidth then return nil end
    return wm, sc, child
end

local function mapIDOf(wm)
    if not (wm and wm.GetMapID) then return nil end
    local ok, id = pcall(wm.GetMapID, wm)
    if ok then return num(id) end
end

local function canvasScale(sc, child)
    local s
    if sc and sc.GetCanvasScale then
        local ok, v = pcall(sc.GetCanvasScale, sc)
        if ok then s = v end
    end
    s = num(s)
    if not s then
        local ok, v = pcall(child.GetScale, child)
        s = ok and num(v) or 1
    end
    if s <= 0 then s = 1 end
    return s
end

-- curseur -> point de la carte affichee (0-1)
local function cursorPoint()
    local l, t = layer:GetLeft(), layer:GetTop()
    local w, h = layer:GetWidth(), layer:GetHeight()
    local cx, cy = GetCursorPosition()
    local s = layer:GetEffectiveScale()
    if not (num(l) and num(t) and num(w) and num(h) and num(cx) and num(s)) or w <= 0 or h <= 0 then return nil end
    local x, y = (cx / s - l) / w, (t - cy / s) / h
    if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return x, y
end

local function onMouseUp(_, button)
    local db = V.DB()
    if not (db and db.mapClick and IsShiftKeyDown()) then return end
    if button == "RightButton" then
        V.Cancel()
        return
    end
    if button ~= "LeftButton" then return end
    local map = mapIDOf((canvas()))
    local x, y = cursorPoint()
    if map and x then V.GoMap(map, x, y) end
end

-- etoile de la destination sur la carte affichee
local function placePin()
    if not pin then return end
    local d = V.Dest and V.Dest()
    local wm, sc, child = canvas()
    local map = mapIDOf(wm)
    if not (d and map and child) then
        pin:Hide()
        lastKey = nil
        return
    end
    local s = canvasScale(sc, child)
    local w, h = child:GetWidth(), child:GetHeight()
    local key = table.concat({ map, d.cont, d.x, d.y, s, tostring(w), tostring(h) }, ":")
    if key == lastKey then return end
    lastKey = key
    local id, x, y = V.MapPos(d.cont, d.x, d.y, map)
    if not (id and x and x >= 0 and x <= 1 and y >= 0 and y <= 1) or issecret(w) or issecret(h) then
        pin:Hide()
        return
    end
    pin:SetScale(1 / s)
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", child, "TOPLEFT", x * w * s, -y * h * s)
    pin:Show()
end

local function onUpdate(self)
    local db = V.DB()
    local want = db and db.mapClick and IsShiftKeyDown() and true or false
    -- (relu aussi chez le jeu : un script de souris peut rallumer la souris)
    local okM, enabled = pcall(self.IsMouseEnabled, self)
    if want ~= self.mouse or (okM and enabled ~= want) then
        self.mouse = want
        self:EnableMouse(want)
    end
    placePin()
end

-- calque pose sur le canevas de la carte (une fois la carte chargee)
function V.MapSetup()
    if layer then return true end
    local _, _, child = canvas()
    if not child then return false end
    layer = CreateFrame("Frame", nil, child)
    layer:SetAllPoints(child)
    layer:SetFrameLevel((child:GetFrameLevel() or 1) + 200)
    -- scripts d abord : sur ce client, poser un script de souris (OnMouseUp)
    -- rallume la souris du cadre ; on la coupe ensuite (sinon le calque
    -- avale les clics de la carte : plus de zoom avant / arriere)
    layer:SetScript("OnMouseUp", onMouseUp)
    layer:SetScript("OnUpdate", onUpdate)
    layer:EnableMouse(false)
    layer.mouse = false
    pin = CreateFrame("Frame", nil, layer)
    pin:SetSize(PIN, PIN)
    pin:SetFrameLevel(layer:GetFrameLevel() + 5)
    pin.tex = pin:CreateTexture(nil, "OVERLAY")
    pin.tex:SetAllPoints()
    pin.tex:SetTexture(STAR)
    pin:Hide()
    return true
end

function V.MapRefresh() lastKey = nil end
