--[[--------------------------------------------------------------------------
    CorpUI - module Encheres : swap d essences (onglet Essences du volet et
    panneau /corp essences)

    Les essences d enchantement existent en inferieure et en superieure :
    3 inferieures se combinent en 1 superieure, 1 superieure se separe en
    3 inferieures (clic droit dans les sacs, sans perte). Quand les deux
    prix s ecartent, on achete la forme bon marche, on convertit et on
    revend l autre :
      - combiner : 3 inf achetees coutent moins que ce que rapporte 1 sup ;
      - separer : 1 sup achetee coute moins que ce que rapportent 3 inf.
    Ce que rapporte une vente : le prix de mise en vente (le plus bas de
    l HV, ou la valeur marche si elle est plus basse) moins la commission
    de 5 %. Ce que coute un achat : l echelle des prix du dernier releve
    (les moins chers d abord). On achete tant que chaque superieure (ou
    trio d inferieures) rapporte encore la marge mini (reglage, 10 % par
    defaut), au plus N superieures par coup (reglage, 20). Le depot n est
    pas compte (rendu a la vente, perdu si l enchere expire : le suivi
    compte les expirees). Prix plus vieux que le reglage : affiches, mais
    ni comptes ni annonces.
    Pour ses propres essences (dez) : la forme sous laquelle les vendre.
    Suivi (registre de la comptabilite, lu dans les courriers de l HV) :
    achats et ventes d essences sur 7, 30 ou 90 jours, par palier, en
    unites d inferieure (1 sup = 3 inf) : cout moyen, vente nette moyenne,
    benefice sur les unites achetees puis revendues, stock achete pas
    encore revendu, ventes sans achat (dez) ; encheres d essences en cours
    (onglet Mes encheres) ; dernieres operations.
    Aucun achat, aucune vente, aucune conversion par l addon (interdit sur
    ce client) : clic sur un palier = recherche des deux formes dans l HV
    (la partie commune de leurs noms), ce qui rafraichit leurs prix.
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local C = ns.COLORS
local AH = ns.AH

local issecret = issecretvalue or function() return false end
local num = AH.num

local CUT = 0.95            -- commission de l HV : 5 %
local MAX_CAP = 200         -- superieures par coup, au plus (reglage)
local ROW_H = 54
local PAD = 8
local PERIODS = { 7, 30, 90 }

local TIERS = {
    { key = "magic", name = "ESS_T_MAGIC", lesser = 10938, greater = 10939 },
    { key = "astral", name = "ESS_T_ASTRAL", lesser = 10998, greater = 11082 },
    { key = "mystic", name = "ESS_T_MYSTIC", lesser = 11134, greater = 11135 },
    { key = "nether", name = "ESS_T_NETHER", lesser = 11174, greater = 11175 },
    { key = "eternal", name = "ESS_T_ETERNAL", lesser = 16202, greater = 16203 },
}
-- itemID -> palier et unites (1 inferieure, 3 pour une superieure)
local ESS = {}
for _, t in ipairs(TIERS) do
    ESS[t.lesser] = { t = t, u = 1 }
    ESS[t.greater] = { t = t, u = 3 }
end

local function opts()
    local db = AH.DB()
    if not db then return nil end
    if type(db.essences) ~= "table" then db.essences = {} end
    local o = db.essences
    if type(o.margin) ~= "number" then o.margin = 10 end
    if type(o.max) ~= "number" then o.max = 20 end
    if type(o.fresh) ~= "number" then o.fresh = 60 end
    if o.view ~= "swap" and o.view ~= "track" then o.view = "swap" end
    if o.days ~= 7 and o.days ~= 30 and o.days ~= 90 then o.days = 7 end
    if o.announce == nil then o.announce = true end
    if o.tip == nil then o.tip = true end
    return o
end

local function tierName(t) return L[t.name] end

---------------------------------------------------------------------------
-- Calcul
---------------------------------------------------------------------------

-- prix de mise en vente : le plus bas de l HV, ou la valeur marche si elle
-- est plus basse (on vend maintenant, sans attendre une remontee)
local function sellPrice(v)
    if not v then return nil end
    local p = v.min
    if v.market and v.market < p then p = v.market end
    if p and p > 0 then return p end
end

-- achats successifs sur l echelle de buyID, par lots de `per` exemplaires
-- (3 inferieures ou 1 superieure, de quoi faire une superieure), tant que
-- chaque lot rapporte `out` (vente apres commission) avec la marge :
-- nombre de lots, cout total, gain net, cout estime (pas d echelle)
local function walk(buyID, per, out, margin, max)
    local n, cost, gain, est = 0, 0, 0, false
    if not ns.AHCost then return 0, 0, 0, false end
    while n < max do
        local c, got, _, e = ns.AHCost(buyID, (n + 1) * per)
        if not c or got < (n + 1) * per then break end
        local step = c - cost
        if step <= 0 or out < step * margin then break end
        n, cost, gain = n + 1, c, gain + out - step
        est = est or e == true
    end
    return n, cost, gain, est
end

-- un palier : { t, vl, vg (valeurs HV), sellL, sellG (prix de vente), age,
-- old, form ("greater" / "lesser" : forme a vendre), formGain (par
-- superieure), dir ("up" combiner, "down" separer, nil), n (superieures),
-- nBuy, nSell, buyID, sellID, cost, gain, income, roi, est }
local function evaluate(t, o)
    local vl = ns.AHValues and ns.AHValues(t.lesser)
    local vg = ns.AHValues and ns.AHValues(t.greater)
    local r = { t = t, vl = vl, vg = vg }
    if not (vl and vg) then return r end
    r.sellL, r.sellG = sellPrice(vl), sellPrice(vg)
    r.age = math.max(vl.age or 0, vg.age or 0)
    r.old = r.age > o.fresh * 60
    if not (r.sellL and r.sellG) then return r end
    r.form = r.sellG >= 3 * r.sellL and "greater" or "lesser"
    r.formGain = math.abs(r.sellG - 3 * r.sellL) * CUT
    local margin = 1 + math.max(0, o.margin) / 100
    local max = math.max(1, math.min(MAX_CAP, math.floor(o.max)))
    local n, cost, gain, est = walk(t.lesser, 3, r.sellG * CUT, margin, max)
    if n > 0 then
        r.dir, r.buyID, r.sellID, r.nBuy, r.nSell = "up", t.lesser, t.greater, 3 * n, n
    else
        n, cost, gain, est = walk(t.greater, 1, 3 * r.sellL * CUT, margin, max)
        if n > 0 then r.dir, r.buyID, r.sellID, r.nBuy, r.nSell = "down", t.greater, t.lesser, n, 3 * n end
    end
    if r.dir then
        r.n, r.cost, r.gain, r.est = n, cost, gain, est
        r.income = cost + gain
        r.roi = cost > 0 and gain / cost * 100 or 0
    end
    return r
end

-- les cinq paliers ; nombre de swaps rentables (prix recents) et leur gain
local function evaluateAll(o)
    local list, n, sum, best = {}, 0, 0, nil
    for i, t in ipairs(TIERS) do
        local r = evaluate(t, o)
        list[i] = r
        if r.dir and not r.old then
            n, sum = n + 1, sum + r.gain
            if not best or r.gain > best.gain then best = r end
        end
    end
    return list, n, sum, best
end

-- essences possedees, tous les persos (sacs et banque ; perso courant :
-- ses sacs en direct)
local function owned(id)
    local root = ns.InitRoot and ns.InitRoot()
    local alts = type(root) == "table" and root.alts
    local me = ns.CharKey and ns.CharKey()
    local total, seenMe = 0, false
    local function count(t, k) return (type(t) == "table" and num(t[k])) or 0 end
    if type(alts) == "table" then
        for key, a in pairs(alts) do
            if type(a) == "table" then
                if key == me then
                    seenMe = true
                    total = total + ns.ItemCount(id) + count(a.bank, id)
                else
                    total = total + count(a.bags, id) + count(a.bank, id)
                end
            end
        end
    end
    if not seenMe then total = total + ns.ItemCount(id) end
    return total
end

-- encheres d essences en cours (onglet Mes encheres : lu HV ouvert)
local function posted()
    local out = {}
    if not AH.MineGroups then return out end
    local ok, groups = pcall(AH.MineGroups)
    if not ok or type(groups) ~= "table" then return out end
    for _, g in ipairs(groups) do
        if ESS[g.id] then out[#out + 1] = g end
    end
    return out
end

local function postedCount(id)
    local n = 0
    for _, g in ipairs(posted()) do
        if g.id == id and not g.sold then n = n + g.qty end
    end
    return n
end

---------------------------------------------------------------------------
-- Suivi : registre de la comptabilite
---------------------------------------------------------------------------

-- noms des essences (les ventes ne donnent que le nom)
local function namesIndex()
    local m = {}
    for id in pairs(ESS) do
        local n = ns.ItemName(id)
        if n then m[n] = id else AH.ItemLabel(id) end
    end
    return m
end

local SUMS = { "buyU", "buyC", "saleU", "saleNet", "profit", "stockU", "stockC", "expired", "extraU", "extraNet" }

-- bilan depuis `since` : liste par palier, total, operations (recentes d abord)
local function track(since)
    local r = AH.Ledger and AH.Ledger()
    local idx = namesIndex()
    local by, ops = {}, {}
    for _, t in ipairs(TIERS) do
        by[t.key] = { t = t, buyU = 0, buyC = 0, saleU = 0, saleNet = 0, expired = 0, bq = { 0, 0 }, sq = { 0, 0 } }
    end
    for _, tx in ipairs(r and r.tx or {}) do
        if type(tx) == "table" and (num(tx.t) or 0) >= since then
            local id = (tx.id and ESS[tx.id] and tx.id) or (type(tx.item) == "string" and idx[tx.item])
            local e = id and ESS[id]
            if e then
                local s = by[e.t.key]
                local q = math.max(1, num(tx.q) or 1)
                local form = e.u == 3 and 2 or 1
                if tx.k == "buy" then
                    s.buyU, s.buyC = s.buyU + q * e.u, s.buyC + (num(tx.p) or 0)
                    s.bq[form] = s.bq[form] + q
                elseif tx.k == "sale" then
                    s.saleU, s.saleNet = s.saleU + q * e.u, s.saleNet + (num(tx.p) or 0) - (num(tx.fee) or 0)
                    s.sq[form] = s.sq[form] + q
                elseif tx.k == "expired" or tx.k == "cancel" then
                    s.expired = s.expired + 1
                end
                ops[#ops + 1] = tx
            end
        end
    end
    local list, total = {}, {}
    for _, k in ipairs(SUMS) do total[k] = 0 end
    for _, t in ipairs(TIERS) do
        local s = by[t.key]
        s.costU = s.buyU > 0 and s.buyC / s.buyU or nil
        s.saleUnit = s.saleU > 0 and s.saleNet / s.saleU or nil
        s.matched = math.min(s.buyU, s.saleU)
        s.profit = (s.costU and s.saleUnit) and s.matched * (s.saleUnit - s.costU) or 0
        s.stockU = math.max(0, s.buyU - s.saleU)
        s.stockC = s.costU and s.stockU * s.costU or 0
        s.extraU = math.max(0, s.saleU - s.buyU)
        s.extraNet = s.saleUnit and s.extraU * s.saleUnit or 0
        s.active = s.buyU > 0 or s.saleU > 0 or s.expired > 0
        for _, k in ipairs(SUMS) do total[k] = total[k] + s[k] end
        list[#list + 1] = s
    end
    table.sort(ops, function(a, b) return (num(a.t) or 0) > (num(b.t) or 0) end)
    return list, total, ops
end

---------------------------------------------------------------------------
-- Recherche dans l HV : la partie commune des deux noms ("Essence du
-- neant", "Nether Essence") ramene les deux formes d un coup
---------------------------------------------------------------------------

-- plus longue sous-chaine commune, sans mot coupe aux bords ("Lesser" et
-- "Greater" finissent tous deux par "er", "하급" et "상급" par "급") ni
-- caractere UTF-8 coupe (langues sans espaces)
local function common(a, b)
    local best = ""
    for i = 1, #a do
        local j = i + #best
        while j <= #a and b:find(a:sub(i, j), 1, true) do
            best = a:sub(i, j)
            j = j + 1
        end
    end
    if best:find(" ", 1, true) then
        local cutStart, cutEnd = false, false
        for _, s in ipairs({ a, b }) do
            local p = s:find(best, 1, true)
            if p > 1 and s:sub(p - 1, p - 1) ~= " " then cutStart = true end
            local after = s:sub(p + #best, p + #best)
            if after ~= "" and after ~= " " then cutEnd = true end
        end
        if cutStart and best:sub(1, 1) ~= " " then best = best:gsub("^[^ ]*", "") end
        if cutEnd and best:sub(-1) ~= " " then best = best:gsub("[^ ]*$", "") end
    end
    best = best:gsub("^[\128-\191]+", "")
    local i = #best
    while i > 0 and best:byte(i) >= 128 and best:byte(i) < 192 do i = i - 1 end
    if i > 0 then
        local c = best:byte(i)
        local need = c >= 240 and 4 or c >= 224 and 3 or c >= 192 and 2 or 1
        if #best - i + 1 < need then best = best:sub(1, i - 1) end
    end
    return strtrim(best)
end

local function searchTier(t)
    if not (ns.AHFrame and ns.AHFrame()) then
        ns.Say(L.ESS_OPEN_AH)
        return
    end
    local a, b = ns.ItemName(t.lesser), ns.ItemName(t.greater)
    local text = a and b and common(a, b)
    if text and #text < 4 then text = nil end
    AH.Search(t.greater, text)
end

---------------------------------------------------------------------------
-- Vue (onglet du volet et panneau /corp essences)
---------------------------------------------------------------------------

local views = {}
local version = 1           -- change avec les donnees (prix, reglages) : vues a redessiner
local function bump() version = version + 1 end

local function M(c) return AH.Money(c) end

local function signed(c)
    if c < 0 then return "|cffff6060-" .. M(-c) .. "|r" end
    if c > 0 then return "|cff6be070+" .. M(c) .. "|r" end
    return M(0)
end

local function numField(page, label, x, y, w, get, set)
    local fs = AH.Text(page, "GameFontDisableSmall", "LEFT")
    fs:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
    fs:SetText(label)
    local e = ns.UI.EditBox(page, w, 18)
    e:SetPoint("TOPLEFT", page, "TOPLEFT", x, y - 13)
    e:SetJustifyH("RIGHT")
    local function commit(self)
        set(self:GetText() or "")
        e:SetText(get())
        bump()
    end
    e:SetScript("OnEnterPressed", function(self) commit(self) self:ClearFocus() end)
    e:HookScript("OnEditFocusLost", commit)
    e.get = get
    return e
end

-- bouton a filet d or (vue choisie, periode choisie)
local function tabButton(parent, w, onClick)
    local b = ns.UI.Button(parent, "", w, onClick)
    b.line = b:CreateTexture(nil, "OVERLAY")
    b.line:SetHeight(2)
    b.line:SetPoint("BOTTOMLEFT", 1, 1)
    b.line:SetPoint("BOTTOMRIGHT", -1, 1)
    b.line:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.9)
    return b
end

local function paintTab(b, on)
    b.line:SetShown(on)
    if on then b.cuiText:SetTextColor(C.gold[1], C.gold[2], C.gold[3]) else b.cuiText:SetTextColor(0.75, 0.75, 0.75) end
end

local function repaintAll()
    bump()
    for _, v in ipairs(views) do v.paintedAt = nil end
end

-- infobulle d un palier
local function tierTip(row)
    local r = row.r
    if not r then return end
    local t = r.t
    local tip = ns.Tooltip(row, "ANCHOR_RIGHT")
    tip:AddLine(tierName(t), C.gold[1], C.gold[2], C.gold[3])
    local function itemLine(id, v)
        if v then
            tip:AddLine(string.format(L.ESS_TIP_ITEM, AH.ItemLabel(id), M(v.min), v.qty or 0, M(v.market or v.min)), 0.85, 0.85, 0.85, true)
        else
            tip:AddLine(AH.ItemLabel(id) .. " : ?", 0.6, 0.6, 0.6, true)
        end
    end
    itemLine(t.lesser, r.vl)
    itemLine(t.greater, r.vg)
    local o = opts()
    if r.sellL and r.sellG then
        tip:AddLine(string.format(L.ESS_TIP_SELL, M(r.sellL), M(r.sellG)), 0.7, 0.7, 0.7, true)
        if r.dir then
            local fmt = r.dir == "up" and L.ESS_TIP_UP or L.ESS_TIP_DOWN
            tip:AddLine(string.format(fmt, r.nBuy, M(r.cost), r.nSell, M(r.income)), 0.42, 0.88, 0.46, true)
            tip:AddLine(string.format(L.ESS_TIP_PROFIT, M(r.gain), math.floor(r.roi + 0.5), o and o.margin or 10), 0.42, 0.88, 0.46, true)
            if r.est then tip:AddLine(L.ESS_TIP_EST, 1, 0.6, 0.25, true) end
        else
            tip:AddLine(string.format(L.ESS_TIP_NONE, o and o.margin or 10), 0.7, 0.7, 0.7, true)
        end
    end
    if r.age then
        tip:AddLine(string.format(L.ESS_TIP_AGE, ns.FormatAgo(time() - r.age)), 0.6, 0.6, 0.6)
        if r.old then tip:AddLine(L.ESS_TIP_OLD, 1, 0.6, 0.25, true) end
    end
    local hl, hg = owned(t.lesser), owned(t.greater)
    if hl + hg > 0 then tip:AddLine(string.format(L.ESS_TIP_OWNED, hl, hg), 1, 0.82, 0) end
    local pl, pg = postedCount(t.lesser), postedCount(t.greater)
    if pl + pg > 0 then tip:AddLine(string.format(L.ESS_TIP_POSTED, pl, pg), 1, 0.82, 0) end
    tip:AddLine(L.ESS_TIP_CLICK, 0.7, 0.7, 0.7, true)
    tip:Show()
end

local function makeTierRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    ns.UI.Gradient(hl, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.25, C.violet[1], C.violet[2], C.violet[3], 0.02)
    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetAllPoints()
    row.stripe:SetColorTexture(1, 1, 1, 0.03)
    -- la superieure, et l inferieure posee en bas a droite
    local function icon(size, x, y, sub)
        local f = row:CreateTexture(nil, "ARTWORK", nil, sub)
        f:SetSize(size, size)
        f:SetPoint("TOPLEFT", row, "TOPLEFT", x, y)
        f:SetColorTexture(0, 0, 0, 1)
        local tex = row:CreateTexture(nil, "ARTWORK", nil, sub + 1)
        tex:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
        tex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        return tex
    end
    row.iconG = icon(28, 2, -4, 1)
    row.iconL = icon(20, 18, -26, 3)
    row.right = AH.Text(row, "GameFontHighlightSmall", "RIGHT")
    row.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, -6)
    row.name = AH.Text(row, "GameFontNormal", "LEFT")
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 46, -4)
    row.name:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
    row.prices = AH.Text(row, "GameFontHighlightSmall", "LEFT")
    row.prices:SetPoint("TOPLEFT", row, "TOPLEFT", 46, -22)
    row.prices:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.action = AH.Text(row, "GameFontDisableSmall", "LEFT")
    row.action:SetPoint("TOPLEFT", row, "TOPLEFT", 46, -37)
    row.action:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row:SetScript("OnClick", function(self) if self.r then searchTier(self.r.t) end end)
    row:SetScript("OnEnter", tierTip)
    row:SetScript("OnLeave", function() ns.HideTooltip() end)
    return row
end

local function fillTierRow(row, r, i)
    local t = r.t
    row.r = r
    row.stripe:SetShown(i % 2 == 0)
    row.iconG:SetTexture(ns.ItemIcon(t.greater))
    row.iconL:SetTexture(ns.ItemIcon(t.lesser))
    row.name:SetText(tierName(t))
    if not (r.vl and r.vg) then
        row.prices:SetText("|cff9d9d9d—|r")
        row.right:SetText("")
        row.action:SetText("|cffff9a40" .. L.ESS_NOPRICE .. "|r")
        return
    end
    local prices = string.format(L.ESS_PRICES, M(3 * r.vl.min), M(r.vg.min))
    if r.old then prices = prices .. "  |cffff9a40" .. ns.FormatAgo(time() - r.age) .. "|r" end
    row.prices:SetText(prices)
    if r.dir then
        local col = r.old and "ff9a40" or "6be070"
        row.right:SetText("|cff" .. col .. string.format(L.ESS_GAIN, M(r.gain), math.floor(r.roi + 0.5)) .. "|r")
        local fmt = r.dir == "up" and L.ESS_UP or L.ESS_DOWN
        row.action:SetText("|cff" .. col .. string.format(fmt, r.nBuy, M(r.cost), r.nSell) .. "|r")
    else
        row.right:SetText("|cff9d9d9d" .. L.ESS_NONE .. "|r")
        if r.form then
            local fmt = r.form == "greater" and L.ESS_FORM_G or L.ESS_FORM_L
            row.action:SetText(string.format(fmt, M(r.formGain)))
        else
            row.action:SetText("")
        end
    end
end

-- une ligne du tableau de suivi : palier, achats, ventes, benefice
local function trackRowTip(self)
    local s = self.s
    if not s then return end
    local tip = ns.Tooltip(self, "ANCHOR_RIGHT")
    tip:AddLine(s.t and tierName(s.t) or L.ESS_TOTAL, C.gold[1], C.gold[2], C.gold[3])
    if s.bq then
        if s.buyU > 0 then
            tip:AddLine(string.format(L.ESS_TT_BUY, s.bq[1], s.bq[2], s.buyU, M(s.buyC), M(s.costU)), 0.85, 0.85, 0.85, true)
        end
        if s.saleU > 0 then
            tip:AddLine(string.format(L.ESS_TT_SALE, s.sq[1], s.sq[2], s.saleU, M(s.saleNet), M(s.saleUnit)), 0.85, 0.85, 0.85, true)
        end
    end
    if s.buyU > 0 and s.saleU > 0 then
        tip:AddLine(string.format(L.ESS_TT_PROFIT, math.min(s.buyU, s.saleU), signed(s.profit)), 0.42, 0.88, 0.46, true)
    end
    if s.stockU > 0 then tip:AddLine(string.format(L.ESS_TT_STOCK, s.stockU, M(s.stockC)), 1, 0.82, 0, true) end
    if s.extraU > 0 then tip:AddLine(string.format(L.ESS_TT_EXTRA, s.extraU, M(s.extraNet)), 0.7, 0.7, 0.7, true) end
    if s.expired > 0 then tip:AddLine(string.format(L.ESS_TT_EXPIRED, s.expired), 1, 0.6, 0.25, true) end
    tip:AddLine(L.ESS_TT_UNIT, 0.6, 0.6, 0.6, true)
    tip:Show()
end

local KIND = { sale = { "BOOK_K_SALE", "6be070" }, buy = { "BOOK_K_BUY", "ff9060" }, expired = { "BOOK_K_EXPIRED", "9d9d9d" },
               cancel = { "BOOK_K_CANCEL", "9d9d9d" } }

local function buildView(page, w, top)
    local v = { page = page, w = w }
    -- deux vues : swaps et suivi
    local half = (w - 2 * PAD - 6) / 2
    v.tabs = {
        swap = tabButton(page, half, function() local o = opts() if o then o.view = "swap" end repaintAll() end),
        track = tabButton(page, half, function() local o = opts() if o then o.view = "track" end repaintAll() end),
    }
    v.tabs.swap:SetSize(half, 22)
    v.tabs.swap:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, top)
    v.tabs.swap:SetText(L.ESS_VIEW_SWAP)
    v.tabs.track:SetSize(half, 22)
    v.tabs.track:SetPoint("LEFT", v.tabs.swap, "RIGHT", 6, 0)
    v.tabs.track:SetText(L.ESS_VIEW_TRACK)

    -- Swaps
    local sw = CreateFrame("Frame", nil, page)
    sw:SetPoint("TOPLEFT", page, "TOPLEFT", 0, top - 28)
    sw:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
    v.sw = sw
    v.summary = AH.Text(sw, "GameFontHighlightSmall", "LEFT")
    v.summary:SetPoint("TOPLEFT", sw, "TOPLEFT", PAD, -2)
    v.summary:SetPoint("RIGHT", sw, "RIGHT", -PAD, 0)
    v.fields = {
        numField(sw, L.ESS_MARGIN, PAD, -18, 44, function() local o = opts() return tostring(o and o.margin or 10) end, function(s)
            local n, o = tonumber((s:gsub("%%", ""))), opts()
            if n and o and n >= 0 and n <= 500 then o.margin = n end
        end),
        numField(sw, L.ESS_MAX, PAD + 96, -18, 44, function() local o = opts() return tostring(o and o.max or 20) end, function(s)
            local n, o = tonumber(s), opts()
            if n and o and n >= 1 then o.max = math.min(MAX_CAP, math.floor(n)) end
        end),
        numField(sw, L.ESS_FRESH, PAD + 192, -18, 44, function() local o = opts() return tostring(o and o.fresh or 60) end, function(s)
            local n, o = tonumber(s), opts()
            if n and o and n >= 1 and n <= 2880 then o.fresh = math.floor(n) end
        end),
    }
    v.rows = {}
    for i = 1, #TIERS do
        local row = makeTierRow(sw)
        row:SetPoint("TOPLEFT", sw, "TOPLEFT", PAD - 2, -54 - (i - 1) * ROW_H)
        row:SetPoint("RIGHT", sw, "RIGHT", -PAD + 2, 0)
        v.rows[i] = row
    end
    v.hint = AH.Text(sw, "GameFontDisableSmall", "LEFT")
    v.hint:SetPoint("TOPLEFT", sw, "TOPLEFT", PAD, -58 - #TIERS * ROW_H)
    v.hint:SetPoint("RIGHT", sw, "RIGHT", -PAD, 0)
    v.hint:SetHeight(40)
    v.hint:SetWordWrap(true)
    v.hint:SetJustifyV("TOP")
    v.hint:SetText(L.ESS_HINT)

    -- Suivi
    local tr = CreateFrame("Frame", nil, page)
    tr:SetPoint("TOPLEFT", page, "TOPLEFT", 0, top - 28)
    tr:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
    v.tr = tr
    v.periods = {}
    for i, d in ipairs(PERIODS) do
        local b = tabButton(tr, 50, function()
            local o = opts()
            if o then o.days = d end
            repaintAll()
        end)
        b:SetSize(50, 20)
        b:SetPoint("TOPLEFT", tr, "TOPLEFT", PAD + (i - 1) * 54, -2)
        b:SetText(string.format(L.ESS_PERIOD, d))
        b.days = d
        v.periods[i] = b
    end
    local y = -30
    local labW = 74
    local colW = math.floor((w - PAD * 2 - labW) / 3)
    local heads = { L.ESS_COL_BUY, L.ESS_COL_SALE, L.ESS_COL_PROFIT }
    local h0 = AH.Text(tr, "GameFontNormalSmall", "LEFT")
    h0:SetPoint("TOPLEFT", tr, "TOPLEFT", PAD, y)
    h0:SetText(L.ESS_COL_TIER)
    for c = 1, 3 do
        local fs = AH.Text(tr, "GameFontNormalSmall", "RIGHT")
        fs:SetPoint("TOPLEFT", tr, "TOPLEFT", PAD + labW + (c - 1) * colW, y)
        fs:SetWidth(colW)
        fs:SetText(heads[c])
    end
    y = y - 16
    v.trows = {}
    for i = 1, #TIERS + 1 do
        local row = CreateFrame("Frame", nil, tr)
        row:SetHeight(15)
        row:SetPoint("TOPLEFT", tr, "TOPLEFT", PAD, y)
        row:SetPoint("RIGHT", tr, "RIGHT", -PAD, 0)
        row:EnableMouse(true)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.06)
        row.label = AH.Text(row, i > #TIERS and "GameFontNormalSmall" or "GameFontHighlightSmall", "LEFT")
        row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.label:SetWidth(labW)
        row.cells = {}
        for c = 1, 3 do
            local fs = AH.Text(row, "GameFontHighlightSmall", "RIGHT")
            fs:SetPoint("LEFT", row, "LEFT", labW + (c - 1) * colW, 0)
            fs:SetWidth(colW)
            row.cells[c] = fs
        end
        row:SetScript("OnEnter", trackRowTip)
        row:SetScript("OnLeave", function() ns.HideTooltip() end)
        v.trows[i] = row
        y = y - 15
        if i == #TIERS then y = y - 3 end
    end
    y = y - 4
    v.stock = AH.Text(tr, "GameFontDisableSmall", "LEFT")
    v.stock:SetPoint("TOPLEFT", tr, "TOPLEFT", PAD, y)
    v.stock:SetPoint("RIGHT", tr, "RIGHT", -PAD, 0)
    y = y - 20
    AH.Header(tr, L.ESS_SEC_POSTED, y)
    y = y - 22
    v.posted = {}
    for i = 1, 4 do
        local fs = AH.Text(tr, "GameFontHighlightSmall", "LEFT")
        fs:SetPoint("TOPLEFT", tr, "TOPLEFT", PAD, y)
        fs:SetPoint("RIGHT", tr, "RIGHT", -PAD, 0)
        v.posted[i] = fs
        y = y - 14
    end
    y = y - 6
    AH.Header(tr, L.ESS_SEC_LAST, y)
    y = y - 22
    v.list = AH.List(tr, 16, function(list)
        local row = CreateFrame("Frame", nil, list)
        row.when = AH.Text(row, "GameFontDisableSmall", "LEFT")
        row.when:SetPoint("LEFT", 0, 0)
        row.when:SetWidth(34)
        row.kind = AH.Text(row, "GameFontHighlightSmall", "LEFT")
        row.kind:SetPoint("LEFT", row.when, "RIGHT", 2, 0)
        row.kind:SetWidth(54)
        row.amount = AH.Text(row, "GameFontHighlightSmall", "RIGHT")
        row.amount:SetPoint("RIGHT", 0, 0)
        row.item = AH.Text(row, "GameFontHighlightSmall", "LEFT")
        row.item:SetPoint("LEFT", row.kind, "RIGHT", 2, 0)
        row.item:SetPoint("RIGHT", row.amount, "LEFT", -4, 0)
        return row
    end, function(row, tx)
        row.when:SetText(date and date("%d/%m", tx.t) or "")
        local k = KIND[tx.k] or { "", "ffffff" }
        row.kind:SetText("|cff" .. k[2] .. (L[k[1]] or tx.k) .. "|r")
        local item = tx.item or ""
        if tx.q and tx.q > 1 then item = item .. " x" .. tx.q end
        row.item:SetText(item)
        local a
        if tx.k == "sale" then a = (tx.p or 0) - (tx.fee or 0) elseif tx.k == "buy" then a = -(tx.p or 0) end
        row.amount:SetText(a and signed(a) or "")
    end)
    v.list:SetPoint("TOPLEFT", tr, "TOPLEFT", PAD, y)
    v.list:SetPoint("BOTTOMRIGHT", tr, "BOTTOMRIGHT", -PAD, 8)
    v.empty = AH.Text(tr, "GameFontDisableSmall", "LEFT")
    v.empty:SetPoint("TOPLEFT", tr, "TOPLEFT", PAD, y)
    v.empty:SetPoint("RIGHT", tr, "RIGHT", -PAD, 0)
    v.empty:SetHeight(44)
    v.empty:SetWordWrap(true)
    v.empty:SetJustifyV("TOP")
    v.empty:SetText(L.ESS_EMPTY)
    views[#views + 1] = v
    return v
end

local function postedLine(g)
    local st
    if g.sold then
        st = "|cffffd100" .. L.MINE_SOLD .. "|r"
    elseif g.status == "under" and g.info and g.info.low then
        st = "|cffff6060" .. string.format(L.MINE_UNDER, M(g.price - g.info.low)) .. "|r"
    elseif g.status == "maybe" and g.info and g.info.min then
        st = "|cffffa040" .. string.format(L.MINE_MAYBE, M(g.info.min)) .. "|r"
    elseif g.status == "best" then
        st = "|cff6be070" .. L.MINE_BEST .. "|r"
    elseif g.status == "alone" then
        st = "|cff6be070" .. L.MINE_ALONE .. "|r"
    else
        st = "|cff9d9d9d" .. L.MINE_UNKNOWN .. "|r"
    end
    return g.qty .. " × " .. AH.QualityHex(g.id) .. AH.ItemLabel(g.id) .. "|r " .. M(g.price) .. "  " .. st
end

local function paintSwap(v, o)
    local list, n, sum = evaluateAll(o)
    for i, r in ipairs(list) do fillTierRow(v.rows[i], r, i) end
    if n > 0 then
        v.summary:SetText(string.format(L.ESS_SUMMARY, n, M(sum)))
    else
        v.summary:SetText("|cff9d9d9d" .. L.ESS_SUMMARY_NONE .. "|r")
    end
    for _, e in ipairs(v.fields) do
        if not e:HasFocus() then e:SetText(e.get()) end
    end
end

local function paintTrack(v, o)
    for _, b in ipairs(v.periods) do paintTab(b, b.days == o.days) end
    local list, total, ops = track(time() - o.days * 86400)
    for i, s in ipairs(list) do
        local row = v.trows[i]
        row.s = s
        row.label:SetText(tierName(s.t))
        row.label:SetAlpha(s.active and 1 or 0.45)
        row.cells[1]:SetText(s.buyC > 0 and M(s.buyC) or "|cff9d9d9d—|r")
        row.cells[2]:SetText(s.saleNet > 0 and M(s.saleNet) or "|cff9d9d9d—|r")
        row.cells[3]:SetText((s.buyU > 0 and s.saleU > 0) and signed(s.profit) or "|cff9d9d9d—|r")
    end
    local trow = v.trows[#TIERS + 1]
    trow.s = total
    trow.label:SetText(L.ESS_TOTAL)
    trow.cells[1]:SetText(M(total.buyC))
    trow.cells[2]:SetText(M(total.saleNet))
    trow.cells[3]:SetText(signed(total.profit))
    v.stock:SetText(string.format(L.ESS_STOCK, M(total.stockC), total.expired))
    local p = posted()
    for i, fs in ipairs(v.posted) do
        local g = p[i]
        if g then
            fs:SetText(postedLine(g))
        elseif i == 1 then
            fs:SetText("|cff9d9d9d" .. L.ESS_POSTED_NONE .. "|r")
        else
            fs:SetText("")
        end
    end
    v.list:SetData(ops)
    v.empty:SetShown(#ops == 0)
end

local function paint(v, force)
    if not v then return end
    local now = GetTime()
    -- swaps : au plus une fois par seconde ; suivi : toutes les 3 s
    local o = opts()
    if not o then return end
    local every = o.view == "track" and 3 or 1
    if not force and v.ver == version and v.paintedAt and now - v.paintedAt < every then return end
    v.paintedAt = now
    paintTab(v.tabs.swap, o.view == "swap")
    paintTab(v.tabs.track, o.view == "track")
    v.sw:SetShown(o.view == "swap")
    v.tr:SetShown(o.view == "track")
    if o.view == "swap" then paintSwap(v, o) else paintTrack(v, o) end
    v.ver = version
end

AH.AddTab({ key = "ess", order = 4.5, label = function() return L.AHP_TAB_ESS end,
    build = function(page) page.view = buildView(page, AH.W or 340, -4) end,
    refresh = function(page) paint(page.view) end,
    show = function(page) if page.view then page.view.paintedAt = nil end end })

---------------------------------------------------------------------------
-- Panneau /corp essences (fenetre principale)
---------------------------------------------------------------------------

local panel

local function buildPanel()
    panel = ns.UI.Window("CorpUIEssencesOptions", ns.TITLE .. " - " .. L.MOD_ESS, nil, 440, 520)
    panel.view = buildView(panel, 440, -34)
    panel:HookScript("OnShow", function() paint(panel.view, true) end)
    local acc = 0
    panel:HookScript("OnUpdate", function(_, elapsed)
        acc = acc + (elapsed or 0)
        if acc < 0.5 then return end
        acc = 0
        paint(panel.view)
    end)
end

local function toggle()
    if not AH.DB() then return end
    if not panel then buildPanel() end
    ns.ShowPanel(panel)
end

ns.RegisterModule({
    command = "essences",
    alias = "swap",
    panelName = "CorpUIEssencesOptions",
    icon = "Interface\\Icons\\INV_Enchant_EssenceMagicLarge",
    title = function() return L.MOD_ESS end,
    desc = function() return L.ESS_DESC end,
    Slash = function() toggle() end,
    Open = toggle,
})

---------------------------------------------------------------------------
-- Donnees qui changent, annonce apres un scan, infobulles, reglages
---------------------------------------------------------------------------

if ns.AHListen then ns.AHListen(function() bump() end) end

ns.AHScanDoneHooks = ns.AHScanDoneHooks or {}
table.insert(ns.AHScanDoneHooks, function()
    bump()
    local o = opts()
    if not (o and o.announce) then return end
    local _, n, _, best = evaluateAll(o)
    if n > 0 and best then
        local dir = best.dir == "up" and L.ESS_DIR_UP or L.ESS_DIR_DOWN
        ns.Say(string.format(L.ESS_FOUND, n, tierName(best.t), dir, M(best.gain)))
    end
end)

-- infobulle d une essence : ce que valent 3 inferieures et 1 superieure
ns.tipItemProviders = ns.tipItemProviders or {}
table.insert(ns.tipItemProviders, function(tip, link, out)
    local o = opts()
    if not (o and o.tip) or issecret(link) or type(link) ~= "string" then return end
    local id = tonumber(link:match("item:(%d+)"))
    local e = id and ESS[id]
    if not (e and ns.AHValues) then return end
    local sl, sg = sellPrice(ns.AHValues(e.t.lesser)), sellPrice(ns.AHValues(e.t.greater))
    if not (sl and sg) then return end
    local form = sg >= 3 * sl and L.ESS_TIP_SELL_G or L.ESS_TIP_SELL_L
    out[#out + 1] = "|cffffd100" .. L.ESS_TIP_SWAP .. "|r " .. string.format(L.ESS_PRICES, M(3 * sl), M(sg))
        .. " |cff9d9d9d(" .. form .. ")|r"
end)

ns.AHPanelHooks = ns.AHPanelHooks or {}
table.insert(ns.AHPanelHooks, function(p, form)
    form:Header(L.ESS_SEC)
    form:Check(L.ESS_OPT_ANNOUNCE, function() local o = opts() return o and o.announce end, function(val)
        local o = opts()
        if o then o.announce = val end
    end)
    form:Check(L.ESS_OPT_TIP, function() local o = opts() return o and o.tip end, function(val)
        local o = opts()
        if o then o.tip = val end
    end)
end)

-- banc d essai
AH._ess = { evaluate = evaluate, evaluateAll = evaluateAll, track = track, common = common, sellPrice = sellPrice,
            opts = opts, views = function() return views end, paint = paint, search = searchTier, tiers = TIERS,
            owned = owned, toggle = toggle }
