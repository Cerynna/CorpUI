--[[--------------------------------------------------------------------------
    CorpUI - module Encheres : valeur de desenchantement

    Ce que rapporte le desenchantement d une piece d armure ou d une arme
    (verte, bleue, violette), d apres la table de desenchantement de Classic
    (poussiere, essence, eclat selon le niveau d objet et la qualite ; les
    armes donnent surtout de l essence, les armures surtout de la poussiere)
    et la valeur marche des composants a l HV. Tranches de niveau verifiees
    le 09/11 dans la table ItemDisenchantLoot du jeu Forever : verts et
    bleus a partir du niveau d objet 5, violets a partir de 40.
    Un desenchantement est un tirage (09/11 : la moyenne seule trompait,
    gonflee par l eclat a 5 % alors que 3 fois sur 4 on a la poussiere) :
    on garde toute la distribution, resultat par resultat, quantite
    comprise (tiree entre deux bornes).
      AH.DECan(item)   -> vrai si l objet se desenchante
      AH.DEParts(item) -> { { itemID, chance, quantite moyenne, mini, maxi,
                          qdist = { { quantite, chance } } } }, nombre de
                          desenchantements notes dans sa tranche ; ou nil
      AH.DEDist(item)  -> { mean, lo, hi, missing, seen, parts,
                          points = { { valeur, chance } } } (cuivre non
                          arrondi, valeurs croissantes) ; ou nil
      AH.DEValue(item) -> valeur moyenne, composants sans prix (nombre)
      AH.DEChance(dist, n, need) -> chance que n desenchantements
                          rapportent au moins need, et ce qu ils rapportent
                          au moins 3 fois sur 4
      AH.DELines(item) -> lignes d infobulle, une par resultat possible
    Composant sans prix : manquant s il sort au moins 1 fois sur 20, sinon
    compte pour 0 (le cristal de nexus a 0,5 % ne bloque plus l estimation).
    Apprentissage : chaque desenchantement du joueur (sort 13262) est note
    dans sa tranche (qualite, arme ou armure, niveau) avec ce que le butin
    contient vraiment ; objet vise = l objet verrouille dans les sacs pendant
    l incantation (replis : clic du module Dez, source du butin). Les
    chances et les quantites de la table sont corrigees par ces releves (la
    table compte pour 20 desenchantements, ses quantites pour 4). Base du
    compte (CorpUIDB.auction.deLearn), tous royaumes ; /corp hv l oublie.
    Chemises et tabards ne se desenchantent pas. Infos d objet du client
    absentes (pas encore en cache) : rien.
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local AH = ns.AH

local issecret = issecretvalue or function() return false end
local num, str, call = AH.num, AH.str, AH.call

local DISENCHANT = 13262
local PRIOR = 20              -- poids de la table, en desenchantements
local PRIOR_Q = 4             -- poids de la table pour les quantites
local RARE = 0.05             -- composant sans prix plus rare que ca : vaut 0
local LOOT_WINDOW = 3         -- butin attribue au desenchantement reussi dans les 3 s
local CAST_WINDOW = 8         -- ou a l incantation commencee depuis moins de 8 s
local EXACT = 8               -- au-dela de 8 desenchantements : loi normale

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

-- verts : niveau max de la tranche, poussiere { id, mini, maxi }, essence
-- { id, mini, maxi }, eclat (id, 1) ; armures 75/20/5, armes 20/75/5.
-- Premiere tranche : 80 % poussiere, 20 % essence, pas d eclat ; tranche
-- 21-25 : 75 / 15 / 10.
local GREEN = {
    { 15, { STRANGE, 1, 2 }, { LMAGIC, 1, 2 } },
    { 20, { STRANGE, 2, 3 }, { GMAGIC, 1, 2 }, SGLIM },
    { 25, { STRANGE, 4, 6 }, { LASTRAL, 1, 2 }, SGLIM, astral = true },
    { 30, { SOUL, 1, 2 }, { GASTRAL, 1, 2 }, LGLIM },
    { 35, { SOUL, 2, 5 }, { LMYSTIC, 1, 2 }, SGLOW },
    { 40, { VISION, 1, 2 }, { GMYSTIC, 1, 2 }, LGLOW },
    { 45, { VISION, 2, 5 }, { LNETHER, 1, 2 }, SRAD },
    { 50, { DREAM, 1, 2 }, { GNETHER, 1, 2 }, LRAD },
    { 55, { DREAM, 2, 5 }, { LETERNAL, 1, 2 }, SBRIL },
    { 60, { ILLUSION, 1, 2 }, { GETERNAL, 1, 2 }, LBRIL },
    { 999, { ILLUSION, 2, 5 }, { GETERNAL, 2, 3 }, LBRIL },
}

-- bleus : un eclat (56 et plus : 0,5 % de cristal de nexus)
local BLUE = {
    { 25, SGLIM }, { 30, LGLIM }, { 35, SGLOW }, { 40, LGLOW }, { 45, SRAD },
    { 50, LRAD }, { 55, SBRIL }, { 999, LBRIL, nexus = true },
}

-- violets : 2 a 4 eclats jusqu au niveau 55, puis cristal de nexus
local PURPLE = {
    { 45, SRAD, 2, 4 }, { 50, LRAD, 2, 4 }, { 55, SBRIL, 2, 4 }, { 60, NEXUS, 1, 1 }, { 999, NEXUS, 1, 2 },
}

-- niveau d objet minimal par qualite (table du jeu)
local MIN_LEVEL = { [2] = 5, [3] = 5, [4] = 40 }

local function bracket(list, lvl)
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
    return num(quality), num(level), num(classID), str(equipLoc)
end

-- tranche d un objet : cle (releves) et resultats de la table
-- { { itemID, chance, mini, maxi } } ; nil s il ne se desenchante pas
local function tierOf(item)
    local quality, lvl, classID, loc = itemInfo(item)
    if not (quality and lvl and classID) then return nil end
    if classID ~= 2 and classID ~= 4 then return nil end
    if loc == "INVTYPE_BODY" or loc == "INVTYPE_TABARD" then return nil end
    if not MIN_LEVEL[quality] or lvl < MIN_LEVEL[quality] then return nil end
    if quality == 2 then
        local t = bracket(GREEN, lvl)
        local weapon = classID == 2
        local pDust, pEss, pShard = 0.75, 0.20, 0.05
        if t[1] == 15 then pDust, pEss, pShard = 0.80, 0.20, 0 end
        if t.astral then pDust, pEss, pShard = 0.75, 0.15, 0.10 end
        if weapon then pDust, pEss = pEss, pDust end
        local out = { { t[2][1], pDust, t[2][2], t[2][3] }, { t[3][1], pEss, t[3][2], t[3][3] } }
        if t[4] and pShard > 0 then out[#out + 1] = { t[4], pShard, 1, 1 } end
        return "2" .. (weapon and "w" or "a") .. t[1], out
    elseif quality == 3 then
        local t = bracket(BLUE, lvl)
        if t.nexus then return "3x" .. t[1], { { t[2], 0.995, 1, 1 }, { NEXUS, 0.005, 1, 1 } } end
        return "3x" .. t[1], { { t[2], 1, 1, 1 } }
    end
    local t = bracket(PURPLE, lvl)
    return "4x" .. t[1], { { t[2], 1, t[3], t[4] } }
end

function AH.DECan(item)
    return tierOf(item) ~= nil
end

---------------------------------------------------------------------------
-- Table corrigee par les releves du joueur
---------------------------------------------------------------------------

local learnVer = 0            -- change a chaque releve (caches)

-- releves d une tranche : { n = desenchantements, m = { [itemID] = { k = fois,
-- q = { [quantite] = fois } } } } ; nil si aucun
local function learned(key)
    local db = AH.DB()
    local all = db and db.deLearn
    local t = type(all) == "table" and all[key]
    if type(t) == "table" and num(t.n) and t.n > 0 and type(t.m) == "table" then return t end
end

-- un resultat : chance melangee et quantites (table uniforme entre mini et
-- maxi, poids PRIOR_Q, plus les quantites vues)
local function outcome(id, p0, lo, hi, seen, n)
    local m = seen and type(seen.m[id]) == "table" and seen.m[id] or nil
    local k = m and num(m.k) or 0
    local p = (PRIOR * p0 + k) / (PRIOR + n)
    if p <= 0 then return nil end
    local w, total = {}, 0
    if lo and hi and hi >= lo then
        for q = lo, hi do w[q] = PRIOR_Q / (hi - lo + 1) end
        total = PRIOR_Q
    end
    if m and type(m.q) == "table" then
        for q, c in pairs(m.q) do
            q, c = num(q), num(c)
            if q and c and q > 0 and c > 0 then
                w[q] = (w[q] or 0) + c
                total = total + c
            end
        end
    end
    if total <= 0 then return nil end
    local qd, mean, qlo, qhi = {}, 0, nil, nil
    for q, c in pairs(w) do
        qd[#qd + 1] = { q, c / total }
        mean = mean + q * c / total
        qlo, qhi = math.min(qlo or q, q), math.max(qhi or q, q)
    end
    table.sort(qd, function(a, b) return a[1] < b[1] end)
    return { id, p, mean, qlo, qhi, qdist = qd }
end

-- composants d un desenchantement, du plus probable au moins probable
function AH.DEParts(item)
    local key, base = tierOf(item)
    if not key then return nil end
    local seen = learned(key)
    local n = seen and seen.n or 0
    local out, inTable, sum = {}, {}, 0
    local function add(o)
        if o then
            out[#out + 1] = o
            sum = sum + o[2]
        end
    end
    for _, b in ipairs(base) do
        inTable[b[1]] = true
        add(outcome(b[1], b[2], b[3], b[4], seen, n))
    end
    -- composant vu mais absent de la table
    if seen then
        for id in pairs(seen.m) do
            if num(id) and not inTable[id] then add(outcome(id, 0, nil, nil, seen, n)) end
        end
    end
    -- un desenchantement donne un seul composant : chances ramenees a 1
    if sum > 0 then
        for _, o in ipairs(out) do o[2] = o[2] / sum end
    end
    table.sort(out, function(a, b) return a[2] > b[2] end)
    return out, n
end

---------------------------------------------------------------------------
-- Valeur : distribution, moyenne, chances
---------------------------------------------------------------------------

local distCache, distVer = {}, nil
function AH.DEDist(item)
    local ver = tostring(ns.AHDataVersion and ns.AHDataVersion()) .. ":" .. learnVer
    if ver ~= distVer then distCache, distVer = {}, ver end
    local c = distCache[item]
    if c ~= nil then return c or nil end
    local d = AH.DEDistRaw(item)
    distCache[item] = d or false
    return d
end

function AH.DEDistRaw(item)
    local parts, n = AH.DEParts(item)
    if not parts then return nil end
    local d = { mean = 0, missing = 0, points = {}, parts = parts, seen = n }
    for _, p in ipairs(parts) do
        local v = ns.AHSource and ns.AHSource(p[1], "market")
        if not (v and v > 0) then
            if p[2] >= RARE then d.missing = d.missing + 1 end
            v = 0
        end
        p.value = v
        for _, qp in ipairs(p.qdist) do
            local val, pr = v * qp[1], p[2] * qp[2]
            d.points[#d.points + 1] = { val, pr }
            d.mean = d.mean + val * pr
        end
    end
    table.sort(d.points, function(a, b) return a[1] < b[1] end)
    d.lo = d.points[1] and d.points[1][1] or 0
    d.hi = d.points[#d.points] and d.points[#d.points][1] or 0
    return d
end

-- valeur moyenne (cuivre) d apres la valeur marche des composants ;
-- second resultat : nombre de composants sans prix (valeur alors partielle)
function AH.DEValue(item)
    local d = AH.DEDist(item)
    if not d then return nil end
    return d.mean, d.missing
end

-- loi normale : P(X <= z)
local function phi(z)
    local t = 1 / (1 + 0.2316419 * math.abs(z))
    local p = 0.3989422804014327 * math.exp(-z * z / 2)
        * t * (0.319381530 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))))
    return z > 0 and 1 - p or p
end

-- n desenchantements (distribution d) : chance que le total atteigne need,
-- et le total atteint au moins 3 fois sur 4. Jusqu a EXACT : toutes les
-- sommes possibles (en centiemes de cuivre, les sommes egales fondues :
-- un millier au plus pour 8 verts) ; au-dela : loi normale.
function AH.DEChance(d, n, need)
    if not d or not n or n < 1 then return 0, 0 end
    local pts = d.points
    if n > EXACT then
        local var = 0
        for _, p in ipairs(pts) do var = var + p[2] * (p[1] - d.mean) ^ 2 end
        local mu, sd = n * d.mean, math.sqrt(n * var)
        if sd <= 0 then return mu >= need and 1 or 0, mu end
        return 1 - phi((need - mu) / sd), math.max(n * d.lo, mu - 0.6745 * sd)
    end
    -- valeurs d un desenchantement (centiemes de cuivre), les egales fondues
    local byVal, steps = {}, {}
    for _, p in ipairs(pts) do
        local c = math.floor(p[1] * 100 + 0.5)
        byVal[c] = (byVal[c] or 0) + p[2]
    end
    for c, pr in pairs(byVal) do steps[#steps + 1] = { c, pr } end
    local h = { [0] = 1 }
    for _ = 1, n do
        local nh = {}
        for s, ps in pairs(h) do
            for _, st in ipairs(steps) do
                local j = s + st[1]
                nh[j] = (nh[j] or 0) + ps * st[2]
            end
        end
        h = nh
    end
    local keys = {}
    for s in pairs(h) do keys[#keys + 1] = s end
    table.sort(keys)
    local needC = need * 100 - 0.5
    local win, acc, low = 0, 0, nil
    for _, s in ipairs(keys) do
        if s >= needC then win = win + h[s] end
        acc = acc + h[s]
        if not low and acc >= 0.25 - 1e-9 then low = s / 100 end
    end
    return math.min(1, win), low or 0
end

-- pourcentage lisible : "75", "0,5", "99,5"
local function pctText(p)
    local v = p * 100
    local r = math.floor(v + 0.5)
    if math.abs(v - r) < 0.05 or (v >= 10 and v <= 99) then return tostring(r) end
    local sep = DECIMAL_SEPARATOR
    if type(sep) ~= "string" or issecret(sep) or sep == "" then sep = "." end
    return (string.format("%.1f", v):gsub("%.", function() return sep end))
end

-- lignes d infobulle : { texte, r, g, b }, une par resultat possible, puis
-- le nombre de desenchantements notes dans la tranche
function AH.DELines(item)
    local d = AH.DEDist(item)
    if not d then return {} end
    local out = {}
    for _, p in ipairs(d.parts) do
        local q = p[4] == p[5] and tostring(p[4]) or (p[4] .. "-" .. p[5])
        local name = ns.ItemName(p[1]) or AH.ItemLabel(p[1])
        local val = p.value > 0 and AH.Money(p.value * p[3]) or "?"
        out[#out + 1] = { string.format(L.DE_LINE, pctText(p[2]), q, name, val), 0.85, 0.85, 0.85 }
    end
    if d.seen > 0 then out[#out + 1] = { string.format(L.DE_SEEN, d.seen), 0.6, 0.6, 0.6 } end
    return out
end

---------------------------------------------------------------------------
-- Apprentissage : ce que donnent vraiment les desenchantements du joueur
---------------------------------------------------------------------------

local cast        -- incantation en cours { link, guid, t }
local pending     -- desenchantement reussi, butin attendu { link, t }

-- objet desenchantable verrouille dans les sacs (celui que le sort vise) ;
-- nil s il n y en a aucun ou plusieurs
local function lockedTarget()
    if not (C_Container and C_Container.GetContainerItemInfo and ns.PlayerBags) then return nil end
    local found
    for _, bag in ipairs(ns.PlayerBags()) do
        for slot = 1, ns.BagSlots(bag) do
            local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
            if ok and type(info) == "table" and not issecret(info.isLocked) and info.isLocked == true then
                local link = str(info.hyperlink)
                if link and AH.DECan(link) then
                    if found then return nil end
                    found = link
                end
            end
        end
    end
    return found
end

-- objet du dernier clic sur l icone du module Dez (10 s au plus)
local function clicked()
    local c = ns.DezClicked
    if type(c) == "table" and num(c.t) and GetTime() - c.t < 10 then return str(c.link) end
end

-- objet source du butin ("Item-..."), si le client le donne encore
local function lootSourceLink()
    if type(GetLootSourceInfo) ~= "function" or not (C_Item and C_Item.GetItemLinkByGUID) then return nil end
    local ok, g = pcall(GetLootSourceInfo, 1)
    if not ok or type(g) ~= "string" or issecret(g) or not g:match("^Item%-") then return nil end
    return str(call(C_Item.GetItemLinkByGUID, g))
end

-- butin ouvert, s il ne contient que des composants d enchantement :
-- { [itemID] = quantite } ; nil sinon
local function readLoot()
    local n = num(call(GetNumLootItems)) or 0
    if n <= 0 then return nil end
    local got = {}
    for slot = 1, n do
        local link = str(call(GetLootSlotLink, slot))
        local id = link and tonumber(link:match("item:(%d+)"))
        local ok, _, _, qty = pcall(GetLootSlotInfo, slot)
        qty = ok and num(qty) or nil
        if not (id and qty and qty > 0 and AH.DEMats[id]) then return nil end
        got[id] = (got[id] or 0) + qty
    end
    return got
end

-- un desenchantement note dans sa tranche ; vrai si note
function AH.DELearn(item, got)
    local db = AH.DB()
    local key = db and tierOf(item)
    if not key or type(got) ~= "table" or next(got) == nil then return false end
    if type(db.deLearn) ~= "table" then db.deLearn = {} end
    local t = db.deLearn[key]
    if type(t) ~= "table" or type(t.m) ~= "table" then
        t = { n = 0, m = {} }
        db.deLearn[key] = t
    end
    t.n = (num(t.n) or 0) + 1
    for id, qty in pairs(got) do
        local m = t.m[id]
        if type(m) ~= "table" then
            m = { k = 0, q = {} }
            t.m[id] = m
        end
        if type(m.q) ~= "table" then m.q = {} end
        m.k = (num(m.k) or 0) + 1
        m.q[qty] = (num(m.q[qty]) or 0) + 1
    end
    learnVer = learnVer + 1
    return true
end

-- desenchantements notes, toutes tranches
function AH.DESeen()
    local db = AH.DB()
    local n = 0
    for _, t in pairs(db and type(db.deLearn) == "table" and db.deLearn or {}) do
        if type(t) == "table" then n = n + (num(t.n) or 0) end
    end
    return n
end

function AH.DEForget()
    local db = AH.DB()
    if db then db.deLearn = nil end
    learnVer = learnVer + 1
end

local learn = CreateFrame("Frame")
learn:SetScript("OnEvent", function(_, event, unit, guid, spellID)
    if ns.ModuleOff("hv", learn) then return end
    local now = GetTime()
    if event == "LOOT_READY" or event == "LOOT_OPENED" then
        -- butin juste apres le sort (ou pendant, si la reussite arrive apres)
        local src = pending and now - pending.t <= LOOT_WINDOW and pending
            or cast and now - cast.t <= CAST_WINDOW and cast or nil
        if not src then
            pending = nil
            return
        end
        local got = readLoot()
        if not got then return end
        local link = src.link or lootSourceLink()
        pending, cast = nil, nil
        if link then AH.DELearn(link, got) end
        return
    end
    if issecret(unit) or unit ~= "player" or issecret(spellID) or spellID ~= DISENCHANT then return end
    if issecret(guid) then guid = nil end
    if event == "UNIT_SPELLCAST_START" then
        cast = { link = lockedTarget() or clicked(), guid = guid, t = now }
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local link = cast and cast.link or lockedTarget() or clicked()
        pending = { link = link, t = now }
        cast = nil
    elseif cast and (not guid or not cast.guid or guid == cast.guid) then
        -- echec ou interruption de cette incantation (pas d un second essai)
        cast = nil
    end
end)
for _, e in ipairs({ "LOOT_READY", "LOOT_OPENED" }) do pcall(learn.RegisterEvent, learn, e) end
for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
                     "UNIT_SPELLCAST_INTERRUPTED" }) do
    if not (learn.RegisterUnitEvent and pcall(learn.RegisterUnitEvent, learn, e, "player")) then
        pcall(learn.RegisterEvent, learn, e)
    end
end

---------------------------------------------------------------------------
-- Infobulle
---------------------------------------------------------------------------

ns.tipItemProviders = ns.tipItemProviders or {}
table.insert(ns.tipItemProviders, function(tip, link, out)
    local db = AH.DB()
    if not (db and db.opts and db.opts.tip and db.opts.de ~= false) or issecret(link) or type(link) ~= "string" then return end
    local d = AH.DEDist(link)
    if not d or d.mean <= 0 then return end
    local txt = "|cffffd100" .. L.DE_TIP .. "|r ≈ " .. AH.Money(d.mean)
    -- fourchette d un desenchantement (le moins et le plus rentable)
    if d.hi > d.lo then txt = txt .. " |cff9d9d9d(" .. string.format(L.DE_RANGE, AH.Money(d.lo), AH.Money(d.hi)) .. ")|r" end
    if d.missing > 0 then txt = txt .. " |cff9d9d9d(" .. L.DE_PARTIAL .. ")|r" end
    out[#out + 1] = txt
end)

-- cases dans le panneau /corp hv (section Infobulles : apres les autres)
ns.AHPanelHooks = ns.AHPanelHooks or {}
table.insert(ns.AHPanelHooks, 1, function(panel, form)
    local db = AH.DB()
    form:Check(L.DE_OPT, function() return db and db.opts and db.opts.de ~= false end, function(v)
        if db and db.opts then db.opts.de = v end
    end)
    -- releves de desenchantement : les oublier (retour a la table seule)
    local btn = ns.UI.Button(panel, "", 260, function(self)
        AH.DEForget()
        self:SetText(string.format(L.DE_FORGET, 0))
        self:SetEnabled(false)
    end)
    btn:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, form.y - 2)
    form.y = form.y - 30
    table.insert(form.refreshers, function()
        local n = AH.DESeen()
        btn:SetText(string.format(L.DE_FORGET, n))
        btn:SetEnabled(n > 0)
    end)
end)

-- banc d essai
AH._de = { tierOf = tierOf, phi = phi, pending = function() return pending end, cast = function() return cast end }
