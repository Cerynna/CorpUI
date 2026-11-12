--[[--------------------------------------------------------------------------
    CorpUI - module Metiers : fabriquer pour desenchanter

    Pour chaque recette apprise du metier ouvert dont l objet se
    desenchante (armes et armures vertes, bleues, violettes) : ce que coute
    une fabrication si on achete TOUS ses composants, et ce que rapporte le
    desenchantement de l objet une fois ses composants revendus a l HV.
      - cout : prix marchand pour les fournitures (fils, sel, teintures...
        Montee.lua S.VENDOR, ou prix releve chez un marchand), sinon
        l echelle des prix de l HV pour la serie (reglage, 10
        fabrications : les moins chers d abord). Ce qu on recolte compte
        aussi : on suppose qu on l achete ;
      - dez : valeur moyenne d un desenchantement (module Encheres,
        AH.DEDist : table de Classic corrigee par tes propres dez, composants
        au plus bas du marche et du jour) x objets par fabrication, moins la
        commission de 5 % ;
      - le dez est un tirage : chance que la serie rembourse ses
        composants (AH.DEChance) et ce qu elle rapporte au moins 3 fois sur
        4 ;
      - comparaison avec la vente de l objet tel quel (meme commission).
    Composant sans prix ou estime (pas assez en vente) : le gain n est
    qu une borne haute (gris, "max"), ou une perte sure (rouge).
    Affichage :
      - onglet "Dez" du volet des metiers : recettes triees par gain par
        fabrication, rentables en tete ; clic = 1 fabrication dans la file
        (Maj : la serie), les courses suivent ;
      - lignes de la liste des recettes de Blizzard : "dez +X" en vert pour
        les recettes rentables (Montee.lua S.RowExtra, option).
    Demande le module Hotel des ventes (CorpUI_HV) et des prix (scan).
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local M = ns.Craft
local S = ns.CraftSkill
local issecret = issecretvalue or function() return false end

local D = {}
ns.CraftDez = D

local CUT = 0.95            -- commission de l HV sur la revente des composants
local ROW_H = 30
local MAX_ROWS = 24
local TTL = 10              -- resultats gardes 10 s (ou jusqu au prochain changement de prix)

local function num(v) if type(v) == "number" and v == v and not issecret(v) then return v end end
local function str(v) if type(v) == "string" and not issecret(v) and v ~= "" then return v end end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end
local function TS(fn, ...)
    local f = C_TradeSkillUI and C_TradeSkillUI[fn]
    local a = call(f, ...)
    if not issecret(a) then return a end
end

local function DB() return M and M.DB and M.DB() end

local function series()
    local d = DB()
    local n = d and num(d.dezSeries)
    return n and math.max(1, math.min(100, math.floor(n))) or 10
end

function D.RowsOn()
    local d = DB()
    return d ~= nil and d.dezRows ~= false
end

local function money(c) return (ns.AHMoney or ns.FormatMoney)(c) end
local function signed(c)
    if c >= 0.5 then return "+" .. money(c) end
    if c <= -0.5 then return "-" .. money(-c) end
    return money(0)
end

-- module Encheres present, avec sa base
function D.Ready()
    local AH = ns.AH
    return type(AH) == "table" and type(AH.DEDist) == "function" and type(AH.DEChance) == "function"
        and type(ns.AHValues) == "function" and type(AH.DB) == "function" and AH.DB() ~= nil
end

---------------------------------------------------------------------------
-- Calcul
---------------------------------------------------------------------------

-- prix marchand d une fourniture (releve chez un marchand, ou connue)
local function vendorPrice(item)
    local d = DB()
    local seen = d and type(d.vendor) == "table" and num(d.vendor[item])
    if seen then return seen end
    local e = S and S.Item and S.Item(item)
    if e and e.buy > 0 and S.VENDOR and S.VENDOR[item] then return e.buy / e.stack end
end

-- composants de n fabrications, tous achetes : cout total (composants qui
-- ont un prix), nombre sans prix, estimation (borne basse), detail
-- { { objet, qte par fabrication, prix unitaire, source, estime } }
local function costOf(reagents, n)
    local total, missing, est, parts = 0, 0, false, {}
    for _, g in ipairs(reagents) do
        local item, q = g[1], g[2] * n
        local unit, src, e = vendorPrice(item), nil, false
        if unit then
            src = "vendor"
        elseif M and M.AHCost then
            local c, got, _, es = M.AHCost(item, q)
            if c and got and got > 0 then unit, src, e = c / got, "ah", es == true or got < q end
        end
        parts[#parts + 1] = { item, g[2], unit, src, e }
        if unit then
            total = total + unit * q
            est = est or e
        else
            missing = missing + 1
        end
    end
    return total, missing, est, parts
end

-- recette : objet produit, nombre par fabrication, composants, nom
local function recipeOf(id)
    local r = M and M.Recipe and M.Recipe(id)
    if type(r) == "table" and num(r.out) and type(r.reagents) == "table" and not r.special then
        return { out = r.out, count = math.max(1, r.yield or 1), reagents = r.reagents, unread = num(r.unread) or 0, name = r.name }
    end
    local s = S and S.Recipe and S.Recipe(id)
    if s and s.item and s.item > 0 then
        return { out = s.item, count = math.max(1, s.count or 1), reagents = s.reagents, unread = 0 }
    end
end

-- objet que les donnees du jeu disent desenchantable (verts a violets,
-- armes et armures) : en attente des infos du client s il n est pas en cache
local function maybeDE(item)
    local e = S and S.Item and S.Item(item)
    return e ~= nil and e.q >= 2 and e.q <= 4 and (e.cls == 2 or e.cls == 4)
end

local function requestItem(item)
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, item) end
end

-- infos de l objet deja chez le client (sinon le dez ne peut pas le juger)
local function cached(item)
    local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if type(info) ~= "function" then return false end
    local ok, name = pcall(info, item)
    return ok and name ~= nil and not issecret(name)
end

-- une recette : nil si son objet ne se desenchante pas ; { loading } si
-- l objet n est pas encore connu du client ; sinon
-- { id, out, count, parts, cost (par fabrication), missing, est, de
--   (valeur moyenne du dez par fabrication), value (apres 5 %), partial
--   (composant du dez sans prix), known (tout est connu), profit (par
--   fabrication ; borne haute si pas known), roi, n (serie), chance, low
--   (benefice de la serie 3 fois sur 4), sale (vente de l objet apres 5 %),
--   craftable }
function D.Evaluate(id, n)
    n = n or series()
    local rec = recipeOf(id)
    if not rec or not D.Ready() then return nil end
    local AH = ns.AH
    local d = AH.DEDist("item:" .. rec.out)
    if not d then
        -- objet pas encore connu du client : demande, et reponse au passage suivant
        if maybeDE(rec.out) and not cached(rec.out) then
            requestItem(rec.out)
            return { id = id, out = rec.out, loading = true }
        end
        return nil
    end
    local total, missing, est, parts = costOf(rec.reagents, n)
    local res = { id = id, out = rec.out, count = rec.count, parts = parts, n = n, est = est, name = rec.name }
    res.missing = missing + rec.unread
    res.cost = total / n
    res.de = d.mean * rec.count
    res.value = res.de * CUT
    res.partial = (d.missing or 0) > 0
    res.known = res.missing == 0 and not res.est and not res.partial
    res.profit = res.value - res.cost
    res.roi = res.cost > 0 and res.profit / res.cost * 100 or nil
    res.dist = d
    if res.known and total > 0 then
        local chance, low = AH.DEChance(d, n * rec.count, total / CUT)
        res.chance, res.low = chance, low * CUT - total
    end
    local v = ns.AHValues(rec.out)
    if v and num(v.min) then res.sale = math.min(v.min, num(v.market) or v.min) * CUT * rec.count end
    res.craftable = num(TS("GetCraftableCount", id))
    return res
end

-- resultats gardes un moment (prix, serie, releves inchanges)
local cache, cacheKey, cacheAt = {}, nil, 0
local function evaluate(id)
    local key = tostring(ns.AHDataVersion and ns.AHDataVersion()) .. ":" .. series()
    local now = GetTime()
    if key ~= cacheKey or now - cacheAt > TTL then
        cache, cacheKey, cacheAt = {}, key, now
    end
    local c = cache[id]
    if c == nil then
        c = D.Evaluate(id) or false
        -- objet encore inconnu du client : redemande au prochain passage
        if c and c.loading then return c end
        cache[id] = c
    end
    return c or nil
end
D.Cached = evaluate

-- recettes apprises du metier ouvert dont l objet se desenchante, les
-- rentables d abord (gain sur), puis les bornes, les pertes, en attente
function D.List()
    local out = {}
    local ids = TS("GetAllRecipeIDs")
    for _, id in ipairs(type(ids) == "table" and ids or {}) do
        id = num(id)
        if id and (not M.Learned or M.Learned(id)) then
            local res = evaluate(id)
            if res then out[#out + 1] = res end
        end
    end
    local function rank(e)
        if e.loading then return 4 end
        if e.known then return e.profit > 0 and 1 or 3 end
        return 2
    end
    table.sort(out, function(a, b)
        local ra, rb = rank(a), rank(b)
        if ra ~= rb then return ra < rb end
        local pa, pb = a.profit or 0, b.profit or 0
        if pa ~= pb then return pa > pb end
        return a.id < b.id
    end)
    return out
end

-- texte d une ligne de la liste de Blizzard : seulement un gain sur
function D.RowText(id)
    local res = evaluate(id)
    if res and res.known and res.profit >= 0.5 then
        return "|cff6be070" .. string.format(L.DEZ_BADGE, signed(res.profit)) .. "|r"
    end
end
if S then
    S.RowExtra = D.RowText
    S.RowExtraOn = D.RowsOn
end

---------------------------------------------------------------------------
-- Onglet "Dez" du volet des metiers
---------------------------------------------------------------------------

local view

local function nameOf(e)
    local info = TS("GetRecipeInfo", e.id)
    return (type(info) == "table" and str(info.name)) or e.name or ns.ItemName(e.out) or ("#" .. e.id)
end

local function qualityHex(item)
    local q
    if C_Item and C_Item.GetItemQualityByID then q = num(call(C_Item.GetItemQualityByID, item)) end
    local e = not q and S and S.Item and S.Item(item)
    if e then q = e.q end
    local c = q and type(ITEM_QUALITY_COLORS) == "table" and ITEM_QUALITY_COLORS[q]
    local hex = c and str(c.hex)
    return hex or "|cffffffff"
end

-- gain de la ligne : sur (vert / rouge), borne haute (gris "max"), perte sure
local function profitText(e)
    if e.loading then return "|cff9d9d9d…|r" end
    if e.known then
        return (e.profit >= 0.5 and "|cff6be070" or e.profit <= -0.5 and "|cffff6060" or "|cffffffff") .. signed(e.profit) .. "|r"
    end
    if e.profit <= -0.5 then return "|cffff6060" .. string.format(L.CRAFT_AH_LOSS, money(-e.profit)) .. "|r" end
    return "|cff9d9d9d" .. string.format(L.CRAFT_AH_MAX, signed(e.profit)) .. "|r"
end

local function subText(e)
    if e.loading then return L.DEZ_LOADING end
    local cost = money(e.cost) .. ((e.missing > 0 or e.est) and "+" or "")
    local t = string.format(L.DEZ_ROW, money(e.value), cost)
    if e.chance then
        local p = math.floor(e.chance * 100 + 0.5)
        local col = p >= 80 and "6be070" or p >= 60 and "ffd100" or "ff9a40"
        t = t .. " · |cff" .. col .. string.format(L.DEZ_ROW_CHANCE, p) .. "|r"
    end
    if e.sale and e.sale > e.value then t = t .. " · |cffffd100" .. L.DEZ_ROW_SALE .. "|r" end
    return t
end

local function rowTip(row)
    local e = row.entry
    if not e then return end
    local t = ns.Tooltip(row, "ANCHOR_LEFT")
    if not pcall(t.SetItemByID, t, e.out) then t:SetText(nameOf(e)) end
    if e.loading then
        t:AddLine(L.DEZ_LOADING, 0.6, 0.6, 0.6)
        t:Show()
        return
    end
    local G = ns.COLORS.gold
    t:AddLine(" ")
    t:AddLine(string.format(L.DEZ_TIP_DE, e.count), G[1], G[2], G[3])
    for _, l in ipairs(ns.AH.DELines("item:" .. e.out)) do t:AddLine(l[1], l[2], l[3], l[4], true) end
    t:AddLine(" ")
    t:AddLine(L.DEZ_TIP_COST, G[1], G[2], G[3])
    for _, p in ipairs(e.parts) do
        local nm = ns.ItemName(p[1]) or ("item:" .. p[1])
        local src = p[4] == "vendor" and L.DEZ_SRC_VENDOR or p[4] == "ah" and L.DEZ_SRC_AH or L.DEZ_SRC_NONE
        local right = p[3] and (money(p[3] * p[2]) .. (p[5] and "+" or "") .. " |cff909090" .. src .. "|r") or ("|cffff6666" .. src .. "|r")
        t:AddDoubleLine(p[2] .. " x " .. nm, right, 1, 1, 1, 1, 1, 1)
    end
    t:AddLine(" ")
    t:AddLine(string.format(L.DEZ_TIP_TOTAL, money(e.cost), money(e.value), signed(e.profit)), 1, 0.82, 0, true)
    if e.chance then
        local lowCol = e.low >= 0 and { 0.42, 0.88, 0.46 } or { 1, 0.38, 0.38 }
        t:AddLine(string.format(L.DEZ_TIP_CHANCE, e.n, math.floor(e.chance * 100 + 0.5), signed(e.low)),
            lowCol[1], lowCol[2], lowCol[3], true)
    end
    if e.sale then
        t:AddLine(string.format(L.DEZ_TIP_SALE, money(e.sale)), 0.85, 0.85, 0.85, true)
        if e.sale > e.value then t:AddLine(L.DEZ_TIP_SALE_BETTER, 1, 0.82, 0, true) end
    end
    if e.missing > 0 then t:AddLine(string.format(L.CRAFT_AH_MISSING, e.missing), 0.6, 0.6, 0.6, true) end
    if e.est then t:AddLine(L.DEZ_TIP_EST, 0.6, 0.6, 0.6, true) end
    if e.partial then t:AddLine(L.DEZ_TIP_PARTIAL, 0.6, 0.6, 0.6, true) end
    if e.craftable and e.craftable > 0 then t:AddLine(string.format(L.DEZ_TIP_CRAFTABLE, e.craftable), 0.85, 0.85, 0.85) end
    t:AddLine(string.format(L.DEZ_TIP_CLICK, e.n), 0.6, 0.6, 0.6, true)
    t:Show()
end

local function refreshView()
    if not (view and view.frame:IsVisible()) then return end
    local skill, prof = M.CurrentProf()
    local message
    if not skill or not (M.OwnSkill and M.OwnSkill()) then
        message = L.SKILL_OPEN
    elseif not D.Ready() then
        message = L.DEZ_NO_AH
    end
    local list = message and {} or D.List()
    if not message and #list == 0 then message = L.DEZ_NONE end
    local good = 0
    for _, e in ipairs(list) do
        if e.known and e.profit >= 0.5 then good = good + 1 end
    end
    view.head:SetText(message and "" or string.format(L.DEZ_HEAD, prof or "?", good))
    view.sub:SetText(message or string.format(L.DEZ_SUB, series()))
    local top = -40
    local avail = math.max(1, math.floor(((view.frame:GetHeight() or 300) + top) / ROW_H))
    view.offset = math.max(0, math.min(view.offset or 0, #list - avail))
    for i, row in ipairs(view.rows) do
        local e = list[i + view.offset]
        if e and i <= avail then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", view.frame, "TOPLEFT", 0, top - (i - 1) * ROW_H)
            row:SetPoint("RIGHT", view.frame, "RIGHT", 0, 0)
            row.entry = e
            row.icon:SetTexture(ns.ItemIcon(e.out))
            row.name:SetText(qualityHex(e.out) .. nameOf(e) .. "|r")
            row.right:SetText(profitText(e))
            row.sub:SetText(subText(e))
            row.stripe:SetShown((i + view.offset) % 2 == 0)
            row:SetAlpha((e.known and e.profit < 0.5) and 0.6 or 1)
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end
end
D.Refresh = refreshView

function M.BuildDezView(parent)
    view = { rows = {}, offset = 0 }
    local f = CreateFrame("Frame", nil, parent)
    view.frame = f
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, d)
        view.offset = math.max(0, (view.offset or 0) - d * 2)
        refreshView()
    end)
    view.head = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    view.head:SetPoint("TOPLEFT", 4, -4)
    view.head:SetPoint("RIGHT", -4, 0)
    view.head:SetJustifyH("LEFT")
    view.head:SetWordWrap(false)
    view.sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    view.sub:SetPoint("TOPLEFT", 4, -20)
    view.sub:SetPoint("RIGHT", -4, 0)
    view.sub:SetJustifyH("LEFT")
    view.sub:SetJustifyV("TOP")
    view.sub:SetWordWrap(true)
    view.sub:SetHeight(20)
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Button", nil, f)
        row:SetHeight(ROW_H)
        row:RegisterForClicks("LeftButtonUp")
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        row.stripe = row:CreateTexture(nil, "BACKGROUND")
        row.stripe:SetAllPoints()
        row.stripe:SetColorTexture(1, 1, 1, 0.03)
        local frame = row:CreateTexture(nil, "ARTWORK")
        frame:SetSize(ROW_H - 6, ROW_H - 6)
        frame:SetPoint("LEFT", 2, 0)
        frame:SetColorTexture(0, 0, 0, 1)
        row.icon = row:CreateTexture(nil, "ARTWORK", nil, 1)
        row.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
        row.icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.right:SetPoint("TOPRIGHT", -2, -3)
        row.right:SetJustifyH("RIGHT")
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("TOPLEFT", frame, "TOPRIGHT", 5, 0)
        row.name:SetPoint("RIGHT", row.right, "LEFT", -4, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.sub:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 5, 0)
        row.sub:SetPoint("RIGHT", -2, 0)
        row.sub:SetJustifyH("LEFT")
        row.sub:SetWordWrap(false)
        row:SetScript("OnClick", function(self)
            local e = self.entry
            if not e or e.loading or not M.AddAndSay then return end
            M.AddAndSay(e.id, (IsShiftKeyDown and IsShiftKeyDown()) and e.n or 1)
        end)
        row:SetScript("OnEnter", rowTip)
        row:SetScript("OnLeave", ns.HideTooltip)
        row:Hide()
        view.rows[i] = row
    end
    f:SetScript("OnShow", refreshView)
    f:SetScript("OnSizeChanged", refreshView)
    f:Hide()
    return view
end

---------------------------------------------------------------------------
-- Reglages (panneau des metiers) et rafraichissement
---------------------------------------------------------------------------

M.optionHooks = M.optionHooks or {}
table.insert(M.optionHooks, function(form, d)
    form:Check(L.DEZ_OPT_ROWS, function() return d.dezRows ~= false end, function(v) d.dezRows = v end)
    form:Number(L.DEZ_OPT_SERIES, function() return series() end, function(v) d.dezSeries = v end, 1, 50, 1)
end)

-- onglet ouvert : redessine toutes les 2 s (prix, objets arrives du client)
local acc = 0
ns.Every(0.5, function()
    if not (view and view.frame:IsVisible()) then return end
    acc = acc + 0.5
    if acc < 2 then return end
    acc = 0
    pcall(refreshView)
end, "Metiers : dez", "metiers")

if M and M.listeners then
    table.insert(M.listeners, function() pcall(refreshView) end)
end

-- banc d essai
D._test = { costOf = costOf, recipeOf = recipeOf, view = function() return view end,
            reset = function() cache, cacheKey = {}, nil end }
