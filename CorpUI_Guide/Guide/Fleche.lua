--[[--------------------------------------------------------------------------
    CorpUI - module Guide : la fleche et le repere de Blizzard
    (reprise de la fleche du module Leveling)

    Fleche CorpUI : tourne avec le personnage vers le point de l etape en
    cours, verte devant, jaune de cote, rouge derriere ; distance dessous,
    puis la partie du guide ; coche a l arrivee ; "ailleurs" sur un autre
    continent. Texture a nous (Media/fleche.tga), teintee a l execution.
    Deplacable avec "Deverrouiller l interface".

    Calcul : angle du point vu du joueur dans le repere du monde (x vers
    le nord, y vers l ouest, 0 = nord, sens trigonometrique), moins
    l orientation (GetPlayerFacing). La texture pointe vers le haut.

    Repere de Blizzard (option, coupee par defaut) : une epingle
    (C_Map.SetUserWaypoint) sur le meme point, suivie par la navigation du
    jeu ; changee seulement quand le point change ; retiree quand il n y a
    plus de point (jamais celle posee par le joueur).
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local GD = ns.Guide
local num, call = GD.num, GD.call

local TEX = "Interface\\AddOns\\CorpUI_Guide\\Media\\fleche"
local CHECK = "Interface\\RaidFrame\\ReadyCheck-Ready"
local SIZE = 52
GD.ARRIVED = 12               -- metres
local TICK = 0.05             -- 20 images par seconde, fleche affichee seulement
local TWO_PI = 2 * math.pi
local atan2 = math.atan2 or math.atan

local arrow, target, db

-- angle (radians, sens trigonometrique, 0 = droit devant) d un point situe
-- dn metres au nord et dw metres a l ouest, pour une orientation donnee
function GD.Angle(dn, dw, facing)
    return (atan2(dw, dn) - facing) % TWO_PI
end

-- 0 = devant, 1 = derriere -> vert, jaune, rouge
function GD.ArrowColor(angle)
    local off = math.abs(((angle + math.pi) % TWO_PI) - math.pi) / math.pi
    if off < 0.5 then return off * 2, 1, 0.1 end
    return 1, 2 - off * 2, 0.1
end

local function showArrowOnly(on)
    arrow.tex:SetShown(on)
    arrow.check:SetShown(not on)
end

local function update(self, elapsed)
    self.wait = (self.wait or 0) - elapsed
    if self.wait > 0 then return end
    self.wait = TICK
    local a = target
    if not a then
        if ns.moversShown then return end
        self:Hide()
        return
    end
    local d, dn, dw = GD.Distance(GD.Player(), a)
    if not d then
        arrow.tex:Hide()
        arrow.check:Hide()
        arrow.dist:SetText(L.GUIDE_ELSEWHERE)
        return
    end
    arrow.dist:SetText(string.format(L.GUIDE_DIST, math.floor(d + 0.5)))
    if d < GD.ARRIVED then
        showArrowOnly(false)
        return
    end
    local facing = num(call(GetPlayerFacing))
    if not facing then
        arrow.tex:Hide()
        arrow.check:Hide()
        return
    end
    local angle = GD.Angle(dn, dw, facing)
    pcall(arrow.tex.SetRotation, arrow.tex, angle)
    arrow.tex:SetVertexColor(GD.ArrowColor(angle))
    showArrowOnly(true)
end

local function build()
    db.arrowPos = db.arrowPos or { point = "TOP", x = 0, y = -150 }
    arrow = CreateFrame("Frame", "CorpUIGuideArrow", UIParent)
    arrow:SetSize(SIZE, SIZE)
    arrow:SetFrameStrata("LOW")
    ns.ApplyPos(arrow, db.arrowPos)
    arrow.tex = arrow:CreateTexture(nil, "ARTWORK")
    arrow.tex:SetAllPoints()
    arrow.tex:SetTexture(TEX)
    arrow.check = arrow:CreateTexture(nil, "ARTWORK")
    arrow.check:SetSize(SIZE * 0.7, SIZE * 0.7)
    arrow.check:SetPoint("CENTER")
    arrow.check:SetTexture(CHECK)
    arrow.check:Hide()
    arrow.dist = arrow:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(arrow.dist, 12)
    arrow.dist:SetPoint("TOP", arrow, "BOTTOM", 0, -2)
    arrow.title = arrow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    arrow.title:SetPoint("TOP", arrow.dist, "BOTTOM", 0, -1)
    arrow.title:SetWidth(260)
    arrow.title:SetWordWrap(false)
    arrow:SetScript("OnUpdate", update)
    arrow:Hide()
    ns.UI.Mover(arrow, db.arrowPos, L.GUIDE_ARROW)
end

function GD.ArrowScale()
    if arrow then arrow:SetScale(((db and db.arrowScale) or 100) / 100) end
end

-- point montre par la fleche { map, x, y (0-1), title } (nil : cachee)
function GD.SetArrow(a, options)
    db = options
    if not arrow then build() end
    GD.ArrowScale()
    target = a
    local preview = ns.moversShown and not a
    if not db.arrow or (not a and not preview) then
        arrow:Hide()
        return
    end
    if preview then
        pcall(arrow.tex.SetRotation, arrow.tex, 0)
        arrow.tex:SetVertexColor(GD.ArrowColor(0))
        showArrowOnly(true)
        arrow.dist:SetText(string.format(L.GUIDE_DIST, 120))
        arrow.title:SetText(L.GUIDE_ARROW)
    else
        arrow.title:SetText(a.title or "")
    end
    arrow.wait = 0
    arrow:Show()
end

---------------------------------------------------------------------------
-- Repere de Blizzard
---------------------------------------------------------------------------

local nativeKey, ourPin

local function samePin(p)
    if not (ourPin and C_Map and C_Map.GetUserWaypoint) then return false end
    local cur = call(C_Map.GetUserWaypoint)
    if type(cur) ~= "table" then return false end
    local x, y
    if type(cur.position) == "table" then x, y = num(cur.position.x), num(cur.position.y) end
    return num(cur.uiMapID) == p[1] and x and y and math.abs(x - p[2]) < 0.0005 and math.abs(y - p[3]) < 0.0005
end

local function clearOurPin()
    if ourPin and samePin(ourPin) then call(C_Map.ClearUserWaypoint) end
    ourPin = nil
end

local function pinAt(a)
    if not (C_Map and C_Map.SetUserWaypoint and a.map and a.x and a.y) then return end
    if C_Map.CanSetUserWaypointOnMap and call(C_Map.CanSetUserWaypointOnMap, a.map) == false then return end
    local point = UiMapPoint and UiMapPoint.CreateFromCoordinates and call(UiMapPoint.CreateFromCoordinates, a.map, a.x, a.y)
    if not point then return end
    clearOurPin()
    call(C_Map.SetUserWaypoint, point)
    ourPin = { a.map, a.x, a.y }
    if C_SuperTrack then call(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
end

-- appele a chaque calcul : n agit que si le point a change
function GD.SetNative(a, on)
    if not on then
        if nativeKey then clearOurPin() end
        nativeKey = nil
        return
    end
    local k = a and string.format("%d:%.4f:%.4f", a.map, a.x, a.y) or nil
    if k == nativeKey then return end
    nativeKey = k
    if not a then
        clearOurPin()
        return
    end
    pinAt(a)
end
