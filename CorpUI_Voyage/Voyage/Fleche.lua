--[[--------------------------------------------------------------------------
    CorpUI - module Voyage : la fleche

    Meme dessin que la fleche du Leveling (texture a nous, teintee : verte
    devant, jaune de cote, rouge derriere ; distance et titre dessous).
    Pendant un voyage, elle remplace celle du Leveling (qui se cache tant
    que V.Guiding() est vrai). Deplacable avec "Deverrouiller l interface".

    Angle : direction du point vu du joueur dans le repere du monde (x vers
    le nord, y vers l ouest ; 0 = nord, sens trigonometrique, comme
    GetPlayerFacing), moins l orientation du personnage.
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local V = ns.Voyage
local num, call = V.num, V.call

local TEX = "Interface\\AddOns\\CorpUI_Voyage\\Media\\fleche"
local CHECK = "Interface\\RaidFrame\\ReadyCheck-Ready"
local SIZE = 52
local ARRIVED = 10
local TICK = 0.05
local TWO_PI = 2 * math.pi
local atan2 = math.atan2 or math.atan

local arrow, target, db

function V.Angle(dn, dw, facing)
    return (atan2(dw, dn) - facing) % TWO_PI
end

function V.ArrowColor(angle)
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
    if a.noPoint then
        arrow.tex:Hide()
        arrow.check:Hide()
        arrow.dist:SetText("")
        return
    end
    local me = V.Player()
    local d, dn, dw = V.Dist(me, a)
    if not d then
        arrow.tex:Hide()
        arrow.check:Hide()
        arrow.dist:SetText(L.VOY_ELSEWHERE)
        return
    end
    arrow.dist:SetText(string.format(L.VOY_DIST, math.floor(d + 0.5)))
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
    local angle = V.Angle(dn, dw, facing)
    pcall(arrow.tex.SetRotation, arrow.tex, angle)
    arrow.tex:SetVertexColor(V.ArrowColor(angle))
    showArrowOnly(true)
end

local function build()
    db.arrowPos = db.arrowPos or { point = "TOP", x = 0, y = -230 }
    arrow = CreateFrame("Frame", "CorpUIVoyageArrow", UIParent)
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
    arrow.sub = arrow:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    arrow.sub:SetPoint("TOP", arrow.title, "BOTTOM", 0, -1)
    arrow.sub:SetWidth(260)
    arrow.sub:SetWordWrap(false)
    arrow:SetScript("OnUpdate", update)
    arrow:Hide()
    ns.UI.Mover(arrow, db.arrowPos, L.VOY_ARROW)
end

function V.ArrowScale()
    if arrow then arrow:SetScale(((db and db.arrowScale) or 100) / 100) end
end

-- point montre par la fleche : { cont, x, y, title, sub, noPoint } ; nil : cachee
function V.SetArrow(a, options)
    db = options
    if not arrow then build() end
    V.ArrowScale()
    target = a
    local preview = ns.moversShown and not a
    if not db.arrow or (not a and not preview) then
        arrow:Hide()
        return
    end
    if preview then
        pcall(arrow.tex.SetRotation, arrow.tex, 0)
        arrow.tex:SetVertexColor(V.ArrowColor(0))
        showArrowOnly(true)
        arrow.dist:SetText(string.format(L.VOY_DIST, 340))
        arrow.title:SetText(L.VOY_ARROW)
        arrow.sub:SetText("")
    else
        arrow.title:SetText(a.title or "")
        arrow.sub:SetText(a.sub or "")
    end
    arrow.wait = 0
    arrow:Show()
end
