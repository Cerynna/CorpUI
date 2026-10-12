--[[--------------------------------------------------------------------------
    CorpUI - module Encheres : valeur de desenchantement

    Ce que rapporte en moyenne le desenchantement d une piece d armure ou
    d une arme (verte, bleue, violette), d apres la table de desenchantement
    de Classic (poussiere, essence, eclat selon le niveau d objet et la
    qualite ; les armes donnent surtout de l essence, les armures surtout
    de la poussiere) et la valeur marche des composants a l HV. C est une
    estimation (moyenne des tirages), affichee "≈" dans les infobulles.
      AH.DEValue(item) -> cuivre (non arrondi), composants sans prix (nombre)
                          ou nil (objet qui ne se desenchante pas)
      AH.DEParts(item) -> { { itemID, probabilite, quantite moyenne } }
    Chemises et tabards ne se desenchantent pas. Infos d objet du client
    absentes (pas encore en cache) : rien.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L
local AH = ns.AH

local issecret = issecretvalue or function() return false end
local num, call = AH.num, AH.call

-- composants (itemID)
local STRANGE, SOUL, VISION, DREAM, ILLUSION = 10940, 11083, 11137, 11176, 16204
local LMAGIC, GMAGIC, LASTRAL, GASTRAL = 10938, 10939, 10998, 11082
local LMYSTIC, GMYSTIC, LNETHER, GNETHER = 11134, 11135, 11174, 11175
local LETERNAL, GETERNAL = 16202, 16203
local SGLIM, LGLIM, SGLOW, LGLOW = 10978, 11084, 11138, 11139
local SRAD, LRAD, SBRIL, LBRIL, NEXUS = 11177, 11178, 14343, 14344, 20725

-- tous les composants d enchantement de la table (courrier : routines)
AH.DEMats = {}
for _, id in ipairs({ STRANGE, SOUL, VISION, DREAM, ILLUSION, LMAGIC, GMAGIC, LASTRAL, GASTRAL, LMYSTIC, GMYSTIC,
                      LNETHER, GNETHER, LETERNAL, GETERNAL, SGLIM, LGLIM, SGLOW, LGLOW, SRAD, LRAD, SBRIL, LBRIL, NEXUS }) do
    AH.DEMats[id] = true
end

-- verts (armure) : niveau max de la tranche, poussiere {id, qte moy},
-- essence {id, qte moy}, eclat (id) ; chances 75/20/5 (armes : 20/75/5).
-- Premiere tranche : 80 % poussiere, 20 % essence, pas d eclat ; tranche
-- 21-25 : 75 / 15 / 10.
local GREEN = {
    { 15, { STRANGE, 1.5 }, { LMAGIC, 1.5 } },
    { 20, { STRANGE, 2.5 }, { GMAGIC, 1.5 }, SGLIM },
    { 25, { STRANGE, 5 }, { LASTRAL, 1.5 }, SGLIM, astral = true },
    { 30, { SOUL, 1.5 }, { GASTRAL, 1.5 }, LGLIM },
    { 35, { SOUL, 3.5 }, { LMYSTIC, 1.5 }, SGLOW },
    { 40, { VISION, 1.5 }, { GMYSTIC, 1.5 }, LGLOW },
    { 45, { VISION, 3.5 }, { LNETHER, 1.5 }, SRAD },
    { 50, { DREAM, 1.5 }, { GNETHER, 1.5 }, LRAD },
    { 55, { DREAM, 3.5 }, { LETERNAL, 1.5 }, SBRIL },
    { 60, { ILLUSION, 1.5 }, { GETERNAL, 1.5 }, LBRIL },
    { 999, { ILLUSION, 3.5 }, { GETERNAL, 2.5 }, LBRIL },
}

-- bleus : un eclat (56 et plus : 0,5 % de cristal de nexus)
local BLUE = {
    { 25, SGLIM }, { 30, LGLIM }, { 35, SGLOW }, { 40, LGLOW }, { 45, SRAD },
    { 50, LRAD }, { 55, SBRIL }, { 999, LBRIL, nexus = true },
}

-- violets : 2 a 4 eclats jusqu au niveau 55, puis cristal de nexus
local PURPLE = {
    { 45, SRAD, 3 }, { 50, LRAD, 3 }, { 55, SBRIL, 3 }, { 60, NEXUS, 1 }, { 999, NEXUS, 1.5 },
}

local function tierOf(list, lvl)
    for _, t in ipairs(list) do
        if lvl <= t[1] then return t end
    end
end

-- infos utiles d un objet : qualite, niveau, classe (2 arme, 4 armure), emplacement
local function itemInfo(item)
    local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if type(info) ~= "function" or item == nil or issecret(item) then return nil end
    local ok, name, _, quality, level, _, _, _, _, equipLoc, _, _, classID = pcall(info, item)
    if not ok or not name then return nil end
    return num(quality), num(level), num(classID), AH.str(equipLoc)
end

-- composants d un desenchantement : { { itemID, probabilite, quantite moyenne } }
function AH.DEParts(item)
    local quality, lvl, classID, loc = itemInfo(item)
    if not (quality and lvl and classID) then return nil end
    if classID ~= 2 and classID ~= 4 then return nil end
    if loc == "INVTYPE_BODY" or loc == "INVTYPE_TABARD" then return nil end
    if quality == 2 then
        local t = tierOf(GREEN, lvl)
        if not t then return nil end
        local weapon = classID == 2
        local pDust, pEss, pShard = 0.75, 0.20, 0.05
        if t[1] == 15 then pDust, pEss, pShard = 0.80, 0.20, 0 end
        if t.astral then pDust, pEss, pShard = 0.75, 0.15, 0.10 end
        if weapon then pDust, pEss = pEss, pDust end
        local out = { { t[2][1], pDust, t[2][2] }, { t[3][1], pEss, t[3][2] } }
        if t[4] and pShard > 0 then out[#out + 1] = { t[4], pShard, 1 } end
        return out
    elseif quality == 3 then
        local t = tierOf(BLUE, lvl)
        if not t then return nil end
        if t.nexus then return { { t[2], 0.995, 1 }, { NEXUS, 0.005, 1 } } end
        return { { t[2], 1, 1 } }
    elseif quality == 4 then
        local t = tierOf(PURPLE, lvl)
        if not t then return nil end
        return { { t[2], 1, t[3] } }
    end
end

-- valeur moyenne (cuivre) d apres la valeur marche des composants ;
-- second resultat : nombre de composants sans prix (valeur alors partielle)
local deCache, deCacheVer = {}, nil
function AH.DEValue(item)
    local ver = ns.AHDataVersion and ns.AHDataVersion()
    if ver ~= deCacheVer then deCache, deCacheVer = {}, ver end
    local c = deCache[item]
    if c then return c[1], c[2] end
    local total, missing = AH.DEValueRaw(item)
    deCache[item] = { total, missing }
    return total, missing
end

function AH.DEValueRaw(item)
    local parts = AH.DEParts(item)
    if not parts then return nil end
    local total, missing = 0, 0
    for _, p in ipairs(parts) do
        local v = ns.AHSource and ns.AHSource(p[1], "market")
        if v then total = total + v * p[2] * p[3] else missing = missing + 1 end
    end
    return total, missing
end

---------------------------------------------------------------------------
-- Infobulle
---------------------------------------------------------------------------

ns.tipItemProviders = ns.tipItemProviders or {}
table.insert(ns.tipItemProviders, function(tip, link, out)
    local db = AH.DB()
    if not (db and db.opts and db.opts.tip and db.opts.de ~= false) or issecret(link) or type(link) ~= "string" then return end
    local v, missing = AH.DEValue(link)
    if not v or v <= 0 then return end
    local txt = "|cffffd100" .. L.DE_TIP .. "|r ≈ " .. AH.Money(v)
    if missing > 0 then txt = txt .. " |cff9d9d9d(" .. L.DE_PARTIAL .. ")|r" end
    out[#out + 1] = txt
end)

-- case dans le panneau /corp hv (section Infobulles : apres les autres)
ns.AHPanelHooks = ns.AHPanelHooks or {}
table.insert(ns.AHPanelHooks, 1, function(panel, form)
    local db = AH.DB()
    form:Check(L.DE_OPT, function() return db and db.opts and db.opts.de ~= false end, function(v)
        if db and db.opts then db.opts.de = v end
    end)
end)
