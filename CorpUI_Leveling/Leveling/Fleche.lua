--[[--------------------------------------------------------------------------
    CorpUI - module Leveling : la fleche et le repere de Blizzard

    Fleche CorpUI : tourne avec le personnage vers l etape en cours, verte
    devant, jaune de cote, rouge derriere ; distance dessous, coche a
    l arrivee, "ailleurs" sur un autre continent (avec le texte du repere
    de Blizzard quand il y en a un : "Prendre le vol vers..."). Texture a
    nous (Media/fleche.tga, dessinee par un script), teintee a l execution.
    Deplacable avec "Deverrouiller l interface".

    Calcul : angle de l etape vu du joueur dans le repere du monde
    (x vers le nord, y vers l ouest, comme l orientation du personnage,
    0 = nord, sens trigonometrique), moins l orientation (GetPlayerFacing).
    La texture pointe vers le haut : SetRotation de cet angle.

    Repere de Blizzard (option) : la quete suivie par la navigation du jeu
    (C_SuperTrack.SetSuperTrackedQuestID : le jeu sait la guider meme dans
    une autre zone), ou une epingle (C_Map.SetUserWaypoint) pour une quete
    a prendre. Change seulement quand l etape change ; l epingle posee par
    nous est retiree quand il n y a plus d etape (jamais celle du joueur).
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local LV = ns.Leveling
local num, call = LV.num, LV.call

local TEX = "Interface\\AddOns\\CorpUI_Leveling\\Media\\fleche"
local CHECK = "Interface\\RaidFrame\\ReadyCheck-Ready"
local SIZE = 52
local ARRIVED = 10            -- metres
local TICK = 0.05             -- 20 images par seconde, fleche affichee seulement
local TWO_PI = 2 * math.pi
local atan2 = math.atan2 or math.atan

local arrow, target, db

-- angle (radians, sens trigonometrique, 0 = droit devant) d un point situe
-- dn metres au nord et dw metres a l ouest, pour une orientation donnee
function LV.Angle(dn, dw, facing)
    return (atan2(dw, dn) - facing) % TWO_PI
end

-- 0 = devant, 1 = derriere -> vert, jaune, rouge
function LV.ArrowColor(angle)
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
    local me = LV.Player()
    local d, dn, dw = LV.Distance(me, a)
    if not d then
        arrow.tex:Hide()
        arrow.check:Hide()
        arrow.dist:SetText(L.LVL_ELSEWHERE)
        return
    end
    arrow.dist:SetText(string.format(L.LVL_DIST, math.floor(d + 0.5)))
    if d < ARRIVED then
        showArrowOnly(false)
        return
    end
    local facing = num(call(GetPlayerFacing))
    if not facing then
        arrow.tex:Hide()
        arrow.check:Hide()
        return
    end
    local angle = LV.Angle(dn, dw, facing)
    pcall(arrow.tex.SetRotation, arrow.tex, angle)
    arrow.tex:SetVertexColor(LV.ArrowColor(angle))
    showArrowOnly(true)
end

local function build()
    db.arrowPos = db.arrowPos or { point = "TOP", x = 0, y = -150 }
    arrow = CreateFrame("Frame", "CorpUILevelingArrow", UIParent)
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
    arrow.title:SetWidth(240)
    arrow.title:SetWordWrap(false)
    arrow.via = arrow:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    arrow.via:SetPoint("TOP", arrow.title, "BOTTOM", 0, -1)
    arrow.via:SetWidth(240)
    arrow.via:SetWordWrap(false)
    arrow:SetScript("OnUpdate", update)
    arrow:Hide()
    ns.UI.Mover(arrow, db.arrowPos, L.LVL_ARROW)
end

function LV.ArrowScale()
    if arrow then arrow:SetScale(((db and db.arrowScale) or 100) / 100) end
end

-- etape montree par la fleche (nil : cachee) ; preview : deverrouillage
function LV.SetArrow(a, options)
    db = options
    if not arrow then build() end
    LV.ArrowScale()
    target = a
    -- voyage en cours (module Voyage) : sa fleche prend le relais
    if ns.Voyage and ns.Voyage.Guiding and ns.Voyage.Guiding() then
        arrow:Hide()
        return
    end
    local preview = ns.moversShown and not a
    if not db.arrow or (not a and not preview) then
        arrow:Hide()
        return
    end
    if preview then
        pcall(arrow.tex.SetRotation, arrow.tex, 0)
        arrow.tex:SetVertexColor(LV.ArrowColor(0))
        showArrowOnly(true)
        arrow.dist:SetText(string.format(L.LVL_DIST, 120))
        arrow.title:SetText(L.LVL_ARROW)
        arrow.via:SetText("")
    else
        arrow.title:SetText(a.title or (LV.Title and LV.Title(a.id)) or "")
        arrow.via:SetText(a.via and a.viaText or "")
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

-- appele a chaque calcul : n agit que si l etape a change
function LV.SetNative(a, on)
    if not on then
        if nativeKey then clearOurPin() end
        nativeKey = nil
        return
    end
    local key = a and a.key or nil
    if key == nativeKey then return end
    nativeKey = key
    if not a then
        clearOurPin()
        return
    end
    if a.kind ~= "accept" and a.id and C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
        clearOurPin()
        call(C_SuperTrack.SetSuperTrackedQuestID, a.id)
    else
        pinAt(a)
    end
end
