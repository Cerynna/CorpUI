--[[--------------------------------------------------------------------------
    CorpUI - module Encheres : onglet Vente du volet (prix conseille)

    Objet pose dans l onglet Vendre de Blizzard (lu dans sa fenetre, jamais
    ecrit) : la concurrence (resultats que Blizzard vient de demander pour
    cet objet, sans nos propres annonces), la valeur marche, l historique,
    le cout de fabrication (module Metiers), le prix marchand. Prix
    conseille, facon TSM :
      - le moins cher de la concurrence moins la sous-cote ;
      - jamais sous le plancher (pourcentage de la base, au moins le cout
        de fabrication et le prix marchand apres la commission de 5 %) :
        concurrence plus basse -> prix plancher, et l alerte le dit ;
      - jamais au-dessus du plafond ;
      - personne n en vend : prix normal ;
      - ta propre annonce est deja la moins chere : son prix.
    Le prix tape dans le champ de Blizzard est relu : en rouge sous le
    plancher (tu perdrais de l argent), en orange au-dessus du plafond.
    Reglages par defaut (/corp hv) et reglages propres a un objet.

    Bouton "Appliquer" (experimental, coupe par defaut) : ecrit le prix
    dans le champ de Blizzard. C est notre code qui touche leur champ : si
    la mise en vente se bloque en jeu, couper l option.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L
local C = ns.COLORS
local AH = ns.AH

local CUT = 0.95          -- part du vendeur apres la commission de l HV
local PAD = 8

local num, field, call = AH.num, AH.field, AH.call

---------------------------------------------------------------------------
-- Reglages : db.sell (defauts), db.sell.items[id] (propres a un objet),
-- db.sell.groups (groupes de reglages, facon "operations" de TSM) :
-- { id, name, floor, normal, ceil, base, undercut, class, sub } ; un objet
-- suit un groupe choisi pour lui (db.sell.member[id] = id du groupe) ou,
-- sinon, le premier groupe de sa categorie (classe d objet, sous-classe
-- facultative). Ordre : reglages propres > groupe choisi > groupe de la
-- categorie > defauts.
---------------------------------------------------------------------------

local DEFAULTS = { floor = 80, normal = 120, ceil = 250, base = "market", undercut = 1,
                   craftFloor = true, vendorFloor = true, apply = false }
local KEYS = { "floor", "normal", "ceil", "base", "undercut" }

local function sellDB()
    local db = AH.DB()
    if not db then return nil end
    if type(db.sell) ~= "table" then db.sell = {} end
    local s = db.sell
    for k, v in pairs(DEFAULTS) do
        if s[k] == nil then s[k] = v end
    end
    if type(s.items) ~= "table" then s.items = {} end
    if type(s.groups) ~= "table" then s.groups = {} end
    if type(s.member) ~= "table" then s.member = {} end
    return s
end
AH.SellDB = sellDB

-- classe et sous-classe d un objet (infos instantanees du client)
local function itemClass(id)
    local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if type(fn) ~= "function" or not id then return nil end
    local ok, _, _, _, _, _, classID, subID = pcall(fn, id)
    if ok then return num(classID), num(subID) end
end
AH.ItemClass = itemClass

local function groupById(s, gid)
    for _, g in ipairs(s.groups) do
        if g.id == gid then return g end
    end
end
AH.SellGroup = function(gid) local s = sellDB() return s and groupById(s, gid) end

-- groupe d un objet : choisi pour lui ("member"), sinon celui de sa
-- categorie ("class"), sinon nil
local function groupOf(id)
    local s = sellDB()
    if not (s and id) then return nil end
    local gid = s.member[id]
    if gid then
        local g = groupById(s, gid)
        if g then return g, "member" end
    end
    local classID, subID = itemClass(id)
    if classID then
        for _, g in ipairs(s.groups) do
            if g.class == classID and (g.sub == nil or g.sub == subID) then return g, "class" end
        end
    end
end
AH.SellGroupOf = groupOf

-- reglages d un objet ; second resultat : "own", "group" ou "default" ;
-- troisieme : le groupe suivi
local function settingsOf(id)
    local s = sellDB()
    if not s then return DEFAULTS, "default" end
    local own = id and s.items[id]
    local src, g = "default", nil
    if type(own) == "table" then
        src = "own"
    else
        g = groupOf(id)
        if g then src = "group" end
    end
    local out = {}
    for _, k in ipairs(KEYS) do
        local v
        if src == "own" and own[k] ~= nil then v = own[k]
        elseif g and g[k] ~= nil then v = g[k] end
        if v == nil then v = s[k] end
        out[k] = v
    end
    out.craftFloor, out.vendorFloor = s.craftFloor, s.vendorFloor
    return out, src, g
end
AH.SellSettings = settingsOf

-- nouveau groupe (reglages par defaut actuels), renvoie le groupe
function AH.SellNewGroup(name)
    local s = sellDB()
    if not s then return nil end
    s.nextGroup = (tonumber(s.nextGroup) or 0) + 1
    local g = { id = "g" .. s.nextGroup, name = name or string.format(L.GRP_NEW_NAME, s.nextGroup) }
    for _, k in ipairs(KEYS) do g[k] = s[k] end
    table.insert(s.groups, g)
    return g
end

-- supprime un groupe ; ses objets reviennent a la categorie / aux defauts
function AH.SellDeleteGroup(gid)
    local s = sellDB()
    if not s then return end
    for i, g in ipairs(s.groups) do
        if g.id == gid then table.remove(s.groups, i) break end
    end
    for id, m in pairs(s.member) do
        if m == gid then s.member[id] = nil end
    end
end

-- nombre d objets choisis pour un groupe
function AH.SellGroupCount(gid)
    local s = sellDB()
    local n = 0
    for _, m in pairs(s and s.member or {}) do
        if m == gid then n = n + 1 end
    end
    return n
end

---------------------------------------------------------------------------
-- Calcul
---------------------------------------------------------------------------

-- cout de fabrication d un exemplaire (module Metiers : recette connue du
-- personnage, tous les composants avec un prix HV), sinon nil
local function craftCost(id)
    local M = ns.Craft
    if not (M and M.Producer and M.Profit) then return nil end
    local rid = call(M.Producer, id)
    if not rid then return nil end
    local pr = call(M.Profit, rid, 1, true)
    if type(pr) == "table" and (pr.missing or 0) == 0 and not pr.est and num(pr.cost) and pr.cost > 0 then
        return pr.cost / math.max(1, pr.yield or 1)
    end
end
AH.CraftCost = craftCost

local function roundUp(v, step) return math.ceil(v / step - 1e-9) * step end
local function roundDown(v, step) return math.floor(v / step + 1e-9) * step end
local function roundNear(v, step) return math.floor(v / step + 0.5) * step end

-- Plan de vente d un objet. live : concurrence lue dans les resultats de
-- Blizzard { low = prix le plus bas des autres, mine = ma moins chere,
-- full = resultats arrives } ou nil (repli : base de prix, peut contenir
-- ma propre annonce). Renvoie { rec, status, low, floor, normal, ceil,
-- floorWhy, base, live, ... } ; status : "mine", "undercut", "floor",
-- "ceil", "alone", "nodata".
function AH.SellPlan(id, live)
    local s = settingsOf(id)
    local v = ns.AHValues and ns.AHValues(id)
    local step = AH.Step()
    local plan = { id = id, step = step, values = v, settings = s }
    local base = v and ((s.base == "hist" and v.hist) or (s.base == "min" and v.min) or v.market)
    plan.base = base
    local floor, why
    if base then floor, why = base * s.floor / 100, "pct" end
    if s.vendorFloor then
        local vp = ns.AHVendorPrice and ns.AHVendorPrice("item:" .. id)
        if vp then
            plan.vendor = vp
            if not floor or vp / CUT > floor then floor, why = vp / CUT, "vendor" end
        end
    end
    if s.craftFloor then
        local cc = craftCost(id)
        if cc then
            plan.craft = cc
            if not floor or cc / CUT > floor then floor, why = cc / CUT, "craft" end
        end
    end
    if floor then floor = math.max(step, roundUp(floor, step)) end
    local normal = base and roundNear(base * s.normal / 100, step)
    local ceil = base and roundNear(base * s.ceil / 100, step)
    if normal and floor and normal < floor then normal = floor end
    if ceil and floor and ceil < floor then ceil = floor end
    plan.floor, plan.floorWhy, plan.normal, plan.ceil = floor, why, normal, ceil
    local under = math.max(step, roundDown(tonumber(s.undercut) or step, step))
    plan.undercut = under
    plan.live = live ~= nil
    local low, mine, full = live and live.low, live and live.mine, live and live.full
    if not live and v then low = v.min end
    plan.low, plan.mine = low, mine
    local rec, status
    if mine and (not low or mine <= low) then
        rec, status = mine, "mine"
        if floor and rec < floor then rec, status = floor, "floor" end
    elseif low then
        local cand = roundDown(low - under, step)
        plan.cand = cand
        if floor and cand < floor then
            rec, status = floor, "floor"
        elseif ceil and cand > ceil then
            rec, status = ceil, "ceil"
        elseif cand >= step then
            rec, status = cand, "undercut"
        else
            rec, status = step, "undercut"
        end
    elseif full and normal then
        rec, status = normal, "alone"
    elseif full and floor then
        rec, status = floor, "alone"
    else
        status = "nodata"
    end
    plan.rec, plan.status = rec, status
    return plan
end

---------------------------------------------------------------------------
-- Lecture de la fenetre de vente de Blizzard (champs lus seulement)
---------------------------------------------------------------------------

-- objet pose : { frame, commodity, id, link, key } ; frame seule si
-- l onglet Vendre est ouvert sans objet ; nil sinon
local function sellItem()
    local ahf = ns.AHFrame and ns.AHFrame()
    if not ahf then return nil end
    for _, key in ipairs({ "CommoditiesSellFrame", "ItemSellFrame" }) do
        local f = field(ahf, key)
        if AH.visible(f) then
            local out = { frame = f, commodity = key == "CommoditiesSellFrame" }
            local loc = field(f, "itemLocation")
            if type(loc) == "table" and C_Item then
                out.id = num(call(C_Item.GetItemID, loc))
                out.link = AH.str(call(C_Item.GetItemLink, loc))
                out.count = num(call(C_Item.GetStackCount, loc))
                out.key = field(f, "listDisplayedItemKey")
            end
            return out
        end
    end
end
AH.SellItem = sellItem

-- concurrence d une marchandise : resultats tries du moins cher au plus cher
local function liveCommodity(id)
    local ah = AH.api()
    if not ah then return nil end
    local n = num(call(ah.GetNumCommoditySearchResults, id)) or 0
    local low, mine, count, owner = nil, nil, 0, nil
    for i = 1, n do
        local res = call(ah.GetCommoditySearchResultInfo, id, i)
        if type(res) == "table" then
            local u, q, own = num(res.unitPrice), num(res.quantity) or 0, num(res.numOwnerItems) or 0
            if u and u > 0 then
                if own > 0 and (not mine or u < mine) then mine = u end
                if q - own > 0 then
                    if not low or u < low then low, owner = u, type(res.owners) == "table" and AH.str(res.owners[1]) or nil end
                    count = count + q - own
                end
            end
        end
    end
    local full = n > 0 or call(ah.HasFullCommoditySearchResults, id) == true
    if not full then return nil end
    return { low = low, mine = mine, count = count, owner = owner, full = true }
end
AH.LiveCommodity = liveCommodity

-- concurrence d un objet (fiche de l objet : une annonce par ligne)
local function liveItems(key)
    local ah = AH.api()
    if not (ah and type(key) == "table") then return nil end
    local n = num(call(ah.GetNumItemSearchResults, key)) or 0
    local low, mine, count, owner = nil, nil, 0, nil
    for i = 1, n do
        local res = call(ah.GetItemSearchResultInfo, key, i)
        if type(res) == "table" then
            local u, q = num(res.buyoutAmount), num(res.quantity) or 1
            local own = res.containsOwnerItem
            if u and u > 0 then
                if own == true then
                    if not mine or u < mine then mine = u end
                else
                    if not low or u < low then low, owner = u, type(res.owners) == "table" and AH.str(res.owners[1]) or nil end
                    count = count + q
                end
            end
        end
    end
    local full = n > 0 or call(ah.HasFullItemSearchResults, key) == true
    if not full then return nil end
    return { low = low, mine = mine, count = count, owner = owner, full = true }
end
AH.LiveItems = liveItems

local function liveOf(it)
    if not (it and it.id) then return nil end
    if it.commodity then return liveCommodity(it.id) end
    local key = it.key
    if type(key) ~= "table" and C_AuctionHouse and C_AuctionHouse.MakeItemKey then key = call(C_AuctionHouse.MakeItemKey, it.id) end
    return liveItems(key)
end
AH.SellLive = liveOf

-- prix tape dans le champ de Blizzard (cuivre, a l unite), ou nil
local function typedPrice(f)
    local mi = field(field(f, "PriceInput"), "MoneyInputFrame")
    if type(mi) ~= "table" then return nil end
    local total, any = 0, false
    for box, mult in pairs({ GoldBox = 10000, SilverBox = 100, CopperBox = 1 }) do
        local b = field(mi, box)
        if type(b) == "table" and b.GetNumber then
            local ok, v = pcall(b.GetNumber, b)
            v = ok and num(v)
            if v then total, any = total + v * mult, true end
        end
    end
    if any then return total end
end

---------------------------------------------------------------------------
-- Onglet
---------------------------------------------------------------------------

local ui = {}
local last = { id = nil, at = 0 }

local function line(page, y, h)
    local fs = AH.Text(page, "GameFontHighlightSmall", "LEFT")
    fs:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, y)
    fs:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
    if h then
        fs:SetHeight(h)
        fs:SetWordWrap(true)
        fs:SetJustifyV("TOP")
    end
    return fs
end

local function grey(s) return "|cff9d9d9d" .. s .. "|r" end
local function goldT(s) return "|cffffd100" .. s .. "|r" end

local STATUS_TEXT = { mine = "SELL_ST_MINE", undercut = "SELL_ST_UNDERCUT", floor = "SELL_ST_FLOOR",
                      ceil = "SELL_ST_CEIL", alone = "SELL_ST_ALONE", nodata = "SELL_ST_NODATA" }
local BASE_TEXT = { market = "AH_SRC_MARKET", hist = "AH_SRC_HIST", min = "AH_SRC_MIN" }
local WHY_TEXT = { pct = "SELL_WHY_PCT", vendor = "SELL_WHY_VENDOR", craft = "SELL_WHY_CRAFT" }

local function statusText(p)
    local M = AH.Money
    local s = p.status
    if s == "undercut" then return string.format(L.SELL_ST_UNDERCUT, M(p.undercut), M(p.low)) end
    if s == "floor" then
        if p.mine and (not p.low or p.mine <= p.low) then return string.format(L.SELL_ST_FLOOR_MINE, M(p.floor)) end
        return string.format(L.SELL_ST_FLOOR, M(p.low or 0), M(p.floor))
    end
    if s == "ceil" then return string.format(L.SELL_ST_CEIL, M(p.low or 0)) end
    if s == "alone" then return string.format(L.SELL_ST_ALONE, p.settings.normal, L[BASE_TEXT[p.settings.base]] or "") end
    return L[STATUS_TEXT[s]] or ""
end

local function statusColor(s)
    if s == "floor" then return 1, 0.5, 0.3 end
    if s == "nodata" then return 0.6, 0.6, 0.6 end
    if s == "mine" or s == "alone" then return 0.45, 0.85, 1 end
    return 0.42, 0.88, 0.46
end

-- table que modifient les champs de l onglet : les reglages propres de
-- l objet, ou son groupe ; nil : les defauts (a changer dans /corp hv)
local function editTarget(id)
    local s = sellDB()
    if not (s and id) then return nil end
    if type(s.items[id]) == "table" then return s.items[id] end
    return (groupOf(id))
end

-- choix des reglages de l objet : automatique (groupe de sa categorie ou
-- defauts), propres, ou un groupe
local function modeOf(id)
    local s = sellDB()
    if not (s and id) then return "auto" end
    if type(s.items[id]) == "table" then return "own" end
    if s.member[id] and groupById(s, s.member[id]) then return s.member[id] end
    return "auto"
end

local function modeOptions()
    local s = sellDB()
    local out = { { value = "auto", text = L.GRP_AUTO }, { value = "own", text = L.GRP_OWN } }
    for _, g in ipairs(s and s.groups or {}) do out[#out + 1] = { value = g.id, text = L.GRP_PREFIX .. g.name } end
    return out
end

local function setMode(v)
    local s = sellDB()
    local id = ui.id
    if not (s and id) then return end
    if v == "own" then
        local cur = settingsOf(id)
        s.items[id] = { floor = cur.floor, normal = cur.normal, ceil = cur.ceil, base = cur.base, undercut = cur.undercut }
        s.member[id] = nil
    elseif v == "auto" then
        s.items[id], s.member[id] = nil, nil
    else
        s.items[id], s.member[id] = nil, v
    end
end

-- champs des reglages de l objet (ou de son groupe)
local function numBox(page, label, x, y, key, suffix)
    local fs = AH.Text(page, "GameFontDisableSmall", "LEFT")
    fs:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
    fs:SetText(label)
    local e = ns.UI.EditBox(page, 54, 18)
    e:SetPoint("TOPLEFT", page, "TOPLEFT", x, y - 13)
    e:SetJustifyH("RIGHT")
    local suf = AH.Text(page, "GameFontDisableSmall", "LEFT")
    suf:SetPoint("LEFT", e, "RIGHT", 2, 0)
    suf:SetText(suffix or "")
    e.key = key
    local function commit(self)
        local t = editTarget(ui.id)
        if not t then return end
        local txt = self:GetText() or ""
        if key == "undercut" then
            local c = AH.ParseMoney(txt)
            if c and c >= 0 then t.undercut = c end
        else
            local v = tonumber((txt:gsub(",", ".")))
            if v and v > 0 and v <= 10000 then t[key] = v end
        end
        last.at = 0
        AH.Refresh("sell")
    end
    e:SetScript("OnEnterPressed", function(self) commit(self) self:ClearFocus() end)
    e:HookScript("OnEditFocusLost", commit)
    return e
end

local function build(page)
    ui.page = page
    local y = -6
    local frame = page:CreateTexture(nil, "ARTWORK")
    frame:SetSize(34, 34)
    frame:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, y)
    frame:SetColorTexture(0, 0, 0, 1)
    ui.icon = page:CreateTexture(nil, "ARTWORK", nil, 1)
    ui.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    ui.icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    ui.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ui.name = AH.Text(page, "GameFontNormal", "LEFT")
    ui.name:SetPoint("TOPLEFT", frame, "TOPRIGHT", 8, -2)
    ui.name:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
    ui.sub = AH.Text(page, "GameFontDisableSmall", "LEFT")
    ui.sub:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 8, 2)
    ui.sub:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
    ui.empty = line(page, -50, 60)
    ui.empty:SetText(L.SELL_EMPTY)

    local body = CreateFrame("Frame", nil, page)
    body:SetAllPoints()
    ui.body = body
    y = -48
    AH.Header(body, L.SELL_SEC_MARKET, y)
    y = y - 22
    ui.low = line(body, y); y = y - 15
    ui.mine = line(body, y); y = y - 15
    ui.values = line(body, y); y = y - 15
    ui.costs = line(body, y); y = y - 22

    AH.Header(body, L.SELL_SEC_PRICE, y)
    y = y - 24
    ui.rec = body:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(ui.rec, 18)
    ui.rec:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, y)
    ui.rec:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    y = y - 26
    ui.why = line(body, y, 28); y = y - 30
    ui.bounds = line(body, y); y = y - 15
    ui.typed = line(body, y); y = y - 20
    ui.apply = ns.UI.Button(body, L.SELL_APPLY, 120, function()
        local it = sellItem()
        local p = ui.plan
        if not (it and it.frame and p and p.rec) or InCombatLockdown() then return end
        local pi = field(it.frame, "PriceInput")
        if type(pi) == "table" and type(pi.SetAmount) == "function" then pcall(pi.SetAmount, pi, p.rec) end
        last.at = 0
    end)
    ui.apply:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, y)
    ui.apply:HookScript("OnEnter", function(self)
        local t = ns.Tooltip(self, "ANCHOR_TOP")
        t:AddLine(L.SELL_APPLY)
        t:AddLine(L.SELL_APPLY_TIP, 1, 0.6, 0.3, true)
        t:Show()
    end)
    ui.apply:HookScript("OnLeave", function() ns.HideTooltip() end)
    ui.applyY = y
    y = y - 30

    AH.Header(body, L.SELL_SEC_ITEM, y)
    y = y - 22
    ui.mode = ns.UI.Select(body, 210, modeOptions, function() return modeOf(ui.id) end, function(v)
        setMode(v)
        last.at = 0
        AH.Refresh("sell")
    end)
    ui.mode:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, y)
    y = y - 24
    ui.target = line(body, y)
    y = y - 18
    ui.boxes = {
        numBox(body, L.SELL_FLOOR, PAD, y, "floor", "%"),
        numBox(body, L.SELL_NORMAL, PAD + 98, y, "normal", "%"),
        numBox(body, L.SELL_CEIL, PAD + 196, y, "ceil", "%"),
    }
    y = y - 40
    ui.boxes[4] = numBox(body, L.SELL_UNDERCUT, PAD, y, "undercut", "")
    local bl = AH.Text(body, "GameFontDisableSmall", "LEFT")
    bl:SetPoint("TOPLEFT", body, "TOPLEFT", PAD + 98, y)
    bl:SetText(L.SELL_BASE)
    ui.base = ns.UI.Select(body, 150, function()
        return { { value = "market", text = L.AH_SRC_MARKET }, { value = "hist", text = L.AH_SRC_HIST },
                 { value = "min", text = L.AH_SRC_MIN } }
    end, function() return settingsOf(ui.id).base end, function(v)
        local t = editTarget(ui.id)
        if t then t.base = v end
        last.at = 0
        AH.Refresh("sell")
    end)
    ui.base:SetPoint("TOPLEFT", body, "TOPLEFT", PAD + 98, y - 13)
    y = y - 44
    ui.hint = line(body, y, 40)
    ui.hint:SetText(grey(L.SELL_HINT))
end

local function fillSettings(own)
    local cur, src, g = settingsOf(ui.id)
    ui.mode:Refresh()
    if src == "own" then
        ui.target:SetText(grey(L.GRP_T_OWN))
    elseif src == "group" then
        local _, how = groupOf(ui.id)
        ui.target:SetText(grey(string.format(how == "class" and L.GRP_T_CLASS or L.GRP_T_GROUP, g.name)))
    else
        ui.target:SetText(grey(L.GRP_T_DEFAULT))
    end
    for _, e in ipairs(ui.boxes) do
        if not e:HasFocus() then
            if e.key == "undercut" then
                local t = AH.Money(math.max(AH.Step(), tonumber(cur.undercut) or 1))
                t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                e:SetText(t)
            else
                e:SetText(tostring(cur[e.key]))
            end
        end
        e:SetEnabled(own)
        e:SetAlpha(own and 1 or 0.5)
    end
    ui.base:Refresh()
    ui.base:SetEnabled(own)
    ui.base:SetAlpha(own and 1 or 0.5)
end

local function refresh(page)
    if not ui.page then return end
    local it = sellItem()
    local id = it and it.id
    local now = GetTime()
    -- meme objet : relu toutes les secondes (resultats, prix tape)
    if id == last.id and now - last.at < 1 then return end
    last.id, last.at = id, now
    ui.id = id
    if not id then
        ui.icon:SetTexture(nil)
        ui.name:SetText(L.AHP_TAB_SELL)
        ui.sub:SetText("")
        ui.empty:Show()
        ui.body:Hide()
        return
    end
    ui.empty:Hide()
    ui.body:Show()
    local M = AH.Money
    ui.icon:SetTexture(ns.ItemIcon(id))
    ui.name:SetText(AH.QualityHex(id) .. AH.ItemLabel(id) .. "|r")
    ui.sub:SetText((it.commodity and L.SELL_COMMODITY or L.SELL_ITEM) .. (it.count and it.count > 1 and ("  ·  x" .. it.count) or ""))
    local live = liveOf(it)
    local p = AH.SellPlan(id, live)
    ui.plan = p
    -- concurrence
    if live then
        if live.low then
            ui.low:SetText(goldT(L.SELL_LOW) .. " " .. M(live.low) .. grey("  (" .. string.format(L.SELL_COUNT, live.count) .. ")"))
        else
            ui.low:SetText(goldT(L.SELL_LOW) .. " " .. grey(L.SELL_NOBODY))
        end
    elseif p.values then
        ui.low:SetText(goldT(L.SELL_LOW) .. " " .. M(p.values.min) .. grey("  (" .. string.format(L.SELL_FROM_SCAN, ns.FormatAgo(p.values.seen)) .. ")"))
    else
        ui.low:SetText(goldT(L.SELL_LOW) .. " " .. grey(L.SELL_WAITING))
    end
    ui.mine:SetText(p.mine and (goldT(L.SELL_MINE) .. " " .. M(p.mine)) or "")
    local v = p.values
    local parts = {}
    if v and v.market then parts[#parts + 1] = goldT(L.AH_TIP_MARKET) .. " " .. M(v.market) end
    if v and v.hist then parts[#parts + 1] = goldT(L.SELL_HIST) .. " " .. M(v.hist) end
    ui.values:SetText(#parts > 0 and table.concat(parts, "   ") or grey(L.SELL_NOVALUE))
    parts = {}
    if p.craft then parts[#parts + 1] = goldT(L.SELL_CRAFT) .. " " .. M(p.craft) end
    if p.vendor then parts[#parts + 1] = goldT(L.AH_TIP_VENDOR) .. " " .. M(p.vendor) end
    ui.costs:SetText(table.concat(parts, "   "))
    -- conseil
    ui.rec:SetText(p.rec and M(p.rec) or "—")
    ui.why:SetText(statusText(p))
    ui.why:SetTextColor(statusColor(p.status))
    parts = {}
    if p.floor then parts[#parts + 1] = L.SELL_FLOOR .. " " .. M(p.floor) .. " (" .. (L[WHY_TEXT[p.floorWhy]] or "") .. ")" end
    if p.ceil then parts[#parts + 1] = L.SELL_CEIL .. " " .. M(p.ceil) end
    ui.bounds:SetText(grey(table.concat(parts, "  ·  ")))
    -- prix tape dans le champ de Blizzard
    local typed = typedPrice(it.frame)
    if typed and typed > 0 then
        local col, note = "|cff6be070", ""
        if p.floor and typed < p.floor then
            col, note = "|cffff6060", "  " .. L.SELL_TYPED_LOW
        elseif p.ceil and typed > p.ceil then
            col, note = "|cffffa040", "  " .. L.SELL_TYPED_HIGH
        end
        ui.typed:SetText(goldT(L.SELL_TYPED) .. " " .. col .. M(typed) .. note .. "|r")
    else
        ui.typed:SetText("")
    end
    local s = sellDB()
    ui.apply:SetShown(s and s.apply and p.rec ~= nil or false)
    fillSettings(editTarget(id) ~= nil)
end

AH.AddTab({ key = "sell", order = 1, label = function() return L.AHP_TAB_SELL end, build = build, refresh = refresh,
            show = function() last.at = 0 end })

-- nouveaux resultats pour l objet en vente : relecture tout de suite
if ns.AHResultsListen then
    ns.AHResultsListen(function(kind, id)
        if kind ~= "browse" and id and id == ui.id then last.at = 0 end
    end)
end

---------------------------------------------------------------------------
-- Reglages par defaut (panneau /corp hv)
---------------------------------------------------------------------------

ns.AHPanelHooks = ns.AHPanelHooks or {}
table.insert(ns.AHPanelHooks, function(panel, form)
    local function S() return sellDB() or DEFAULTS end
    form:Header(L.SELL_SEC_DEFAULTS)
    form:Columns(3)
    form:Number(L.SELL_OPT_FLOOR, function() return S().floor end, function(v) S().floor = v end, 10, 300, 5)
    form:Number(L.SELL_OPT_NORMAL, function() return S().normal end, function(v) S().normal = v end, 50, 500, 5)
    form:Number(L.SELL_OPT_CEIL, function() return S().ceil end, function(v) S().ceil = v end, 100, 1000, 10)
    form:EndColumns()
    form:Columns(2)
    form:Cycle(L.SELL_OPT_UNDERCUT, { 1, 100, 1000, 10000 }, { [1] = L.SELL_UC_1C, [100] = L.SELL_UC_1S, [1000] = L.SELL_UC_10S, [10000] = L.SELL_UC_1G },
        function() return S().undercut end, function(v) S().undercut = v end)
    form:Cycle(L.SELL_OPT_BASE, { "market", "hist", "min" }, { market = L.AH_SRC_MARKET, hist = L.AH_SRC_HIST, min = L.AH_SRC_MIN },
        function() return S().base end, function(v) S().base = v end)
    form:EndColumns()
    form:Columns(2)
    form:Check(L.SELL_OPT_CRAFT, function() return S().craftFloor end, function(v) S().craftFloor = v end)
    form:Check(L.SELL_OPT_VENDOR, function() return S().vendorFloor end, function(v) S().vendorFloor = v end)
    form:EndColumns()
    form:Check(L.SELL_OPT_APPLY, function() return S().apply end, function(v) S().apply = v end)
    form:Check(L.AHP_OPT_AUTOTAB, function()
        local db = AH.DB()
        return not (db and type(db.side) == "table" and db.side.autoTab == false)
    end, function(v)
        local db = AH.DB()
        if not db then return end
        if type(db.side) ~= "table" then db.side = {} end
        db.side.autoTab = v
    end)
end)

---------------------------------------------------------------------------
-- Groupes de vente (panneau /corp hv) : choisir, creer, nommer, supprimer ;
-- categorie suivie (classe d objet, sous-classe facultative) ; leurs
-- pourcentages, sous-cote et base. Un objet rejoint un groupe depuis
-- l onglet Vente (liste "Reglages").
---------------------------------------------------------------------------

-- classes d objets proposees (consommables, conteneurs, armes, gemmes,
-- armures, composants, artisanat, recettes, quete, divers)
local CLASSES = { 0, 1, 2, 3, 4, 5, 7, 9, 12, 15 }

local function classOptions()
    local out = { { value = "none", text = L.GRP_CLASS_NONE } }
    local info = C_Item and C_Item.GetItemClassInfo
    local subInfo = C_Item and C_Item.GetItemSubClassInfo
    local subList = C_AuctionHouse and C_AuctionHouse.GetAuctionItemSubClasses
    for _, c in ipairs(CLASSES) do
        local name = info and AH.str(call(info, c))
        if name then
            out[#out + 1] = { value = c .. ":", text = name }
            local subs = subList and call(subList, c)
            for _, sub in ipairs(type(subs) == "table" and subs or {}) do
                local sn = subInfo and AH.str(call(subInfo, c, sub))
                if sn then out[#out + 1] = { value = c .. ":" .. sub, text = name .. " › " .. sn } end
            end
        end
    end
    return out
end

AH.ClassOptions = classOptions

local function classKey(g)
    if not (g and g.class) then return "none" end
    return g.class .. ":" .. (g.sub or "")
end

table.insert(ns.AHPanelHooks, function(panel, form)
    local cur          -- id du groupe affiche
    local function G()
        local s = sellDB()
        if not s then return nil end
        local g = cur and groupById(s, cur)
        if not g then
            g = s.groups[1]
            cur = g and g.id
        end
        return g
    end
    local function V(k) local g = G() return (g and g[k]) or (sellDB() or DEFAULTS)[k] end
    local function W(k, v) local g = G() if g then g[k] = v end end
    form:Header(L.GRP_SEC)
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, form.y)
    hint:SetWidth(form.width - 16)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.GRP_HINT)
    form.y = form.y - 30
    local sel = form:Select(nil, function()
        local out = {}
        for _, g in ipairs((sellDB() or {}).groups or {}) do out[#out + 1] = { value = g.id, text = g.name } end
        if #out == 0 then out[1] = { value = "", text = L.GRP_NONE } end
        return out
    end, function() local g = G() return g and g.id or "" end, function(v) if v ~= "" then cur = v end end, 200)
    local new = ns.UI.Button(panel, L.BUY_NEW, 70, function()
        local g = AH.SellNewGroup()
        if g then cur = g.id end
        form.Changed()
    end)
    new:SetPoint("LEFT", sel, "RIGHT", 6, 0)
    local del = ns.UI.Button(panel, L.BUY_DELETE, 70, function(self)
        local g = G()
        if not g then return end
        if not self.armed then
            self.armed = true
            self:SetText(L.AH_SURE)
            C_Timer.After(3, function() if self.armed then self.armed = nil self:SetText(L.BUY_DELETE) end end)
            return
        end
        self.armed = nil
        self:SetText(L.BUY_DELETE)
        AH.SellDeleteGroup(g.id)
        cur = nil
        form.Changed()
    end)
    del:SetPoint("LEFT", new, "RIGHT", 4, 0)
    -- nom du groupe
    local nameLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, form.y)
    nameLabel:SetText(L.GRP_NAME)
    local name = ns.UI.EditBox(panel, 200, 20)
    name:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, form.y - 16)
    local function rename(self)
        local g = G()
        local t = strtrim(self:GetText() or "")
        if g and t ~= "" then g.name = t end
        form:Refresh()
    end
    name:SetScript("OnEnterPressed", function(self) rename(self) self:ClearFocus() end)
    name:HookScript("OnEditFocusLost", rename)
    local count = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    count:SetPoint("LEFT", name, "RIGHT", 8, 0)
    form.y = form.y - 44
    table.insert(form.refreshers, function()
        local g = G()
        if not name:HasFocus() then name:SetText(g and g.name or "") end
        name:SetEnabled(g ~= nil)
        del:SetEnabled(g ~= nil)
        count:SetText(g and string.format(L.GRP_COUNT, AH.SellGroupCount(g.id)) or "")
    end)
    form:Select(L.GRP_CLASS, classOptions, function() return classKey(G()) end, function(v)
        local g = G()
        if not g then return end
        if v == "none" then
            g.class, g.sub = nil, nil
        else
            local c, s = v:match("^(%d+):(%d*)$")
            g.class, g.sub = tonumber(c), tonumber(s)
        end
    end, 260)
    form:Columns(3)
    form:Number(L.SELL_OPT_FLOOR, function() return V("floor") end, function(v) W("floor", v) end, 10, 300, 5)
    form:Number(L.SELL_OPT_NORMAL, function() return V("normal") end, function(v) W("normal", v) end, 50, 500, 5)
    form:Number(L.SELL_OPT_CEIL, function() return V("ceil") end, function(v) W("ceil", v) end, 100, 1000, 10)
    form:EndColumns()
    form:Columns(2)
    form:Cycle(L.SELL_OPT_UNDERCUT, { 1, 100, 1000, 10000 }, { [1] = L.SELL_UC_1C, [100] = L.SELL_UC_1S, [1000] = L.SELL_UC_10S, [10000] = L.SELL_UC_1G },
        function() return V("undercut") end, function(v) W("undercut", v) end)
    form:Cycle(L.SELL_OPT_BASE, { "market", "hist", "min" }, { market = L.AH_SRC_MARKET, hist = L.AH_SRC_HIST, min = L.AH_SRC_MIN },
        function() return V("base") end, function(v) W("base", v) end)
    form:EndColumns()
end)
