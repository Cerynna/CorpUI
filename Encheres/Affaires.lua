--[[--------------------------------------------------------------------------
    CorpUI - module Encheres : onglet Affaires du volet (bonnes affaires)

    Dans les prix recents de la base (scan complet ou recherches de moins
    de N minutes), les objets en vente nettement sous ce qu ils valent, en
    deux listes separees (08/10 : les affaires de desenchantement etaient
    noyees sous les reventes quand le marche bouge) :
      - Bons plans (revente) :
          sous X % de leur valeur marche (au moins 2 jours de valeurs) :
          profit = revente a la valeur marche apres la commission de 5 % ;
          sous leur prix marchand (option) : revente au PNJ, profit sur ;
      - Bons plans dez : sous Y % de leur valeur de desenchantement
        (armures et armes, composants tous avec un prix) : profit estime.
    Chaque liste a son seuil, ses objets ignores et ses 150 places. Pour
    chaque objet : les exemplaires a acheter (echelle des prix du dernier
    releve), le profit et la rentabilite (profit net / depense, 12/10 :
    43 po pour en gagner 8 valent moins que 3 po pour en gagner 2).
    Listes triees par rentabilite ou par profit (bouton). Clic : l objet est
    cherche dans l HV (achat chez Blizzard, interdit aux addons) ; clic
    droit : l objet est ignore dans cette liste.
    Recherche par tranches (quelques centaines d objets par image) a
    l ouverture de l onglet, apres un scan complet (annonce dans le chat,
    option) et au bouton Actualiser.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L
local C = ns.COLORS
local AH = ns.AH

local num = AH.num

local PAD = 8
local ROW_H = 34
local SLICE = 300           -- objets examines par image
local MAX_DEALS = 150       -- par liste
local CUT = 0.95
local CATS = { "resale", "de" }

local function opts()
    local db = AH.DB()
    if not db then return nil end
    if type(db.deals) ~= "table" then db.deals = {} end
    local o = db.deals
    if type(o.pct) ~= "number" then o.pct = 70 end
    if type(o.dePct) ~= "number" then o.dePct = 90 end
    if type(o.minProfit) ~= "number" then o.minProfit = 10000 end
    if type(o.fresh) ~= "number" then o.fresh = 60 end
    if o.vendor == nil then o.vendor = true end
    if o.announce == nil then o.announce = true end
    if type(o.ignore) ~= "table" then o.ignore = {} end
    if type(o.ignoreDE) ~= "table" then o.ignoreDE = {} end
    if o.cat ~= "resale" and o.cat ~= "de" then o.cat = "resale" end
    if o.sort ~= "profit" and o.sort ~= "roi" then o.sort = "roi" end
    o.de = nil   -- ancienne case "Desenchantement" (remplacee par la liste dez)
    return o
end
AH.DealOpts = opts

---------------------------------------------------------------------------
-- Calcul
---------------------------------------------------------------------------

-- meilleures affaires d un objet : revente (marche / marchand) et
-- desenchantement, chacune nil ou { id, kind, q, cost, profit, ref, ... }
local function evaluate(id, o)
    local wantResale, wantDE = not o.ignore[id], not o.ignoreDE[id] and AH.DEValue
    if not wantResale and not wantDE then return nil, nil end
    local v = ns.AHValues and ns.AHValues(id, true)
    if not v or v.age > o.fresh * 60 then return nil, nil end
    local lad = v.lad or { { v.min, v.qty } }
    local function under(limit, value, kind, best)
        local q, cost, profit = 0, 0, 0
        for _, lv in ipairs(lad) do
            if lv[1] > limit then break end
            q, cost, profit = q + lv[2], cost + lv[1] * lv[2], profit + (value - lv[1]) * lv[2]
        end
        if q > 0 and profit > 0 and profit >= o.minProfit and (not best or profit > best.profit) then
            return { id = id, kind = kind, q = q, cost = cost, profit = profit, ref = value, min = v.min, market = v.market,
                     roi = cost > 0 and profit / cost * 100 or 0 }
        end
        return best
    end
    local resale, de
    if wantResale then
        if v.market and (v.marketDays or 0) >= 2 then
            resale = under(v.market * o.pct / 100, v.market * CUT, "market", resale)
        end
        if o.vendor and ns.AHVendorPrice then
            local vp = ns.AHVendorPrice("item:" .. id)
            if vp then resale = under(vp - 0.5, vp, "vendor", resale) end
        end
    end
    if wantDE then
        local dv, missing = AH.DEValue("item:" .. id)
        if dv and missing == 0 and dv > 0 then de = under(dv * o.dePct / 100, dv, "de", nil) end
    end
    return resale, de
end
AH.DealOf = evaluate

local deals = { resale = {}, de = {} }   -- resultat de la derniere recherche
local job                     -- recherche en cours { prev, found = { resale, de }, seen }
local builtAt                 -- fin de la derniere recherche (GetTime)
local dirty = true            -- base changee depuis
local announceNext = false

local total = 0
local function countItems()
    local n, id = 0, ns.AHNextItem and ns.AHNextItem(nil)
    while id do
        n = n + 1
        id = ns.AHNextItem(id)
    end
    return n
end

local function startSearch(announce)
    local o = opts()
    if not o or not ns.AHNextItem then return end
    job = { prev = nil, found = { resale = {}, de = {} }, seen = 0 }
    total = countItems()
    announceNext = announce or false
end
AH.DealSearch = startSearch

-- ordre d une liste : rentabilite (defaut) ou profit
local function sortDeals(list, o)
    if o and o.sort == "profit" then
        table.sort(list, function(a, b)
            if a.profit ~= b.profit then return a.profit > b.profit end
            return (a.roi or 0) > (b.roi or 0)
        end)
    else
        table.sort(list, function(a, b)
            if (a.roi or 0) ~= (b.roi or 0) then return (a.roi or 0) > (b.roi or 0) end
            return a.profit > b.profit
        end)
    end
end

local function finish()
    for _, cat in ipairs(CATS) do
        local found = job.found[cat]
        -- les 150 meilleures au profit, puis l ordre choisi
        table.sort(found, function(a, b) return a.profit > b.profit end)
        while #found > MAX_DEALS do table.remove(found) end
        sortDeals(found, opts())
        deals[cat] = found
    end
    job = nil
    builtAt = GetTime()
    dirty = false
    local o = opts()
    if announceNext and o and o.announce then
        local r, d = deals.resale, deals.de
        if #r > 0 then ns.Say(string.format(L.DEAL_FOUND, #r, AH.ItemLabel(r[1].id), AH.Money(r[1].profit))) end
        if #d > 0 then ns.Say(string.format(L.DEAL_FOUND_DE, #d, AH.ItemLabel(d[1].id), AH.Money(d[1].profit))) end
    end
    announceNext = false
    AH.Refresh("deals")
end

local function stepSearch()
    if not job then return end
    local o = opts()
    if not o then job = nil return end
    for _ = 1, SLICE do
        local id = ns.AHNextItem(job.prev)
        if id == nil then finish() return end
        job.prev = id
        job.seen = job.seen + 1
        local r, d = evaluate(id, o)
        if r then job.found.resale[#job.found.resale + 1] = r end
        if d then job.found.de[#job.found.de + 1] = d end
    end
end

---------------------------------------------------------------------------
-- Onglet
---------------------------------------------------------------------------

local ui = {}
local lastPaint = 0         -- dernier dessin de la liste (au plus 1 par seconde)

local function cat()
    local o = opts()
    return o and o.cat or "resale"
end

local function kindText(d)
    local M = AH.Money
    if d.kind == "vendor" then return "|cff6be070" .. string.format(L.DEAL_K_VENDOR, M(d.ref)) .. "|r" end
    if d.kind == "de" then return "|cffc080ff" .. string.format(L.DEAL_K_DE, M(d.ref)) .. "|r" end
    local pct = d.market and d.market > 0 and math.floor((1 - d.min / d.market) * 100 + 0.5) or 0
    return "|cffffd100" .. string.format(L.DEAL_K_MARKET, pct, M(d.market or 0)) .. "|r"
end

-- rentabilite : vert vif au-dela de 50 %, jaune de 25 a 50, orange en dessous
local function roiText(d)
    local p = math.floor((d.roi or 0) + 0.5)
    local col = p >= 100 and "40ff80" or p >= 50 and "6be070" or p >= 25 and "ffd100" or "ff9a40"
    return "|cff" .. col .. string.format(L.DEAL_ROI, p) .. "|r"
end

local function makeRow(list, i)
    local row = AH.ItemRow(list, ROW_H)
    -- rentabilite en bas a droite ; la ligne du detail s arrete avant
    row.roi = AH.Text(row, "GameFontNormal", "RIGHT")
    row.roi:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -2, 2)
    row.sub:SetPoint("RIGHT", row.roi, "LEFT", -6, 0)
    row:SetScript("OnClick", function(self, button)
        local d = self.d
        if not d then return end
        if button == "RightButton" then
            local o = opts()
            local c = d.kind == "de" and "de" or "resale"
            if o then (c == "de" and o.ignoreDE or o.ignore)[d.id] = true end
            for k, x in ipairs(deals[c]) do
                if x == d then table.remove(deals[c], k) break end
            end
            ns.Say(string.format(L.DEAL_IGNORED, AH.ItemLabel(d.id)))
            AH.Refresh("deals")
        else
            AH.Search(d.id)
        end
    end)
    row:SetScript("OnEnter", function(self)
        local d = self.d
        if not d then return end
        AH.ItemTip(self, d.id, { { kindText(d) },
            { string.format(L.DEAL_TIP_ROI, math.floor((d.roi or 0) + 0.5), AH.Money(d.profit), AH.Money(d.cost)), 0.42, 0.88, 0.46 },
            { L.DEAL_TIP_CLICK, 0.7, 0.7, 0.7 } })
    end)
    return row
end

local function fillRow(row, d, i)
    row.d = d
    row.stripe:SetShown(i % 2 == 0)
    row.icon:SetTexture(ns.ItemIcon(d.id))
    row.name:SetText(AH.QualityHex(d.id) .. AH.ItemLabel(d.id) .. "|r")
    row.right:SetText("|cff6be070+" .. AH.Money(d.profit) .. "|r")
    row.sub:SetText(kindText(d) .. "|cff9d9d9d  ·  " .. string.format(L.DEAL_BUY, d.q, AH.Money(d.cost)) .. "|r")
    row.roi:SetText(roiText(d))
end

-- petit champ numerique avec libelle
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
    end
    e:SetScript("OnEnterPressed", function(self) commit(self) self:ClearFocus() end)
    e:HookScript("OnEditFocusLost", commit)
    e.get = get
    e.label = fs
    return e
end

local function plainMoney(c)
    local t = AH.Money(c)
    t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return t
end

-- bouton de liste (Bons plans / Bons plans dez) : texte or + filet si choisi
local function catButton(page, key)
    local b = ns.UI.Button(page, "", 100, function()
        local o = opts()
        if not o or o.cat == key then return end
        o.cat = key
        ui.list.offset = 0
        lastPaint = 0
        AH.Refresh("deals")
    end)
    b.line = b:CreateTexture(nil, "OVERLAY")
    b.line:SetHeight(2)
    b.line:SetPoint("BOTTOMLEFT", 1, 1)
    b.line:SetPoint("BOTTOMRIGHT", -1, 1)
    b.line:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.9)
    b.key = key
    return b
end

local function build(page)
    ui.page = page
    -- les deux listes, cote a cote
    local half = (AH.W - 2 * PAD - 6) / 2
    ui.cats = { resale = catButton(page, "resale"), de = catButton(page, "de") }
    ui.cats.resale:SetSize(half, 22)
    ui.cats.resale:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, -4)
    ui.cats.de:SetSize(half, 22)
    ui.cats.de:SetPoint("LEFT", ui.cats.resale, "RIGHT", 6, 0)
    ui.summary = AH.Text(page, "GameFontHighlightSmall", "LEFT")
    ui.summary:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, -36)
    ui.summary:SetPoint("RIGHT", page, "RIGHT", -PAD - 90, 0)
    ui.refresh = ns.UI.Button(page, L.DEAL_REFRESH, 84, function() startSearch(false) end)
    ui.refresh:SetPoint("TOPRIGHT", page, "TOPRIGHT", -PAD, -31)
    local y = -56
    ui.fields = {
        -- seuil : % du marche (revente) ou % de la valeur de dez
        numField(page, L.DEAL_PCT, PAD, y, 50, function()
            local o = opts()
            if not o then return "" end
            return tostring(o.cat == "de" and o.dePct or o.pct)
        end, function(t)
            local v, o = tonumber((t:gsub("%%", ""))), opts()
            if not (v and o and v > 0 and v < 100) then return end
            if o.cat == "de" then o.dePct = v else o.pct = v end
        end),
        numField(page, L.DEAL_MIN, PAD + 100, y, 80, function() local o = opts() return plainMoney(o and o.minProfit or 0) end, function(t)
            local c, o = AH.ParseMoney(t), opts()
            if c and o and c >= 0 then o.minProfit = c end
        end),
        numField(page, L.DEAL_FRESH, PAD + 210, y, 50, function() local o = opts() return tostring(o and o.fresh or 60) end, function(t)
            local v, o = tonumber(t), opts()
            if v and o and v >= 1 and v <= 2880 then o.fresh = math.floor(v) end
        end),
    }
    y = y - 36
    ui.vendor = ns.UI.Check(page, L.DEAL_VENDOR, function(v) local o = opts() if o then o.vendor = v end end)
    ui.vendor:SetPoint("TOPLEFT", page, "TOPLEFT", PAD - 4, y)
    ui.sort = ns.UI.Button(page, "", 120, function()
        local o = opts()
        if not o then return end
        o.sort = o.sort == "roi" and "profit" or "roi"
        for _, key in ipairs(CATS) do sortDeals(deals[key], o) end
        ui.list.offset = 0
        lastPaint = 0
        AH.Refresh("deals")
    end)
    ui.sort:SetHeight(20)
    ui.sort:SetPoint("TOPRIGHT", page, "TOPRIGHT", -PAD, y - 2)
    y = y - 26
    ui.list = AH.List(page, ROW_H, makeRow, fillRow)
    ui.list:SetPoint("TOPLEFT", page, "TOPLEFT", PAD - 2, y)
    ui.list:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -PAD + 2, 50)
    ui.empty = AH.Text(page, "GameFontDisableSmall", "LEFT")
    ui.empty:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, y - 6)
    ui.empty:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
    ui.empty:SetHeight(44)
    ui.empty:SetWordWrap(true)
    ui.empty:SetJustifyV("TOP")
    ui.hint = AH.Text(page, "GameFontDisableSmall", "LEFT")
    ui.hint:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", PAD, 6)
    ui.hint:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
    ui.hint:SetHeight(40)
    ui.hint:SetWordWrap(true)
    ui.hint:SetJustifyV("BOTTOM")
end

local function sumOf(list)
    local sum, cost = 0, 0
    for _, d in ipairs(list) do
        sum = sum + d.profit
        cost = cost + (d.cost or 0)
    end
    return sum, cost
end

local function refresh(page)
    if not ui.page then return end
    local now = GetTime()
    if not job and now - lastPaint < 1 then return end
    lastPaint = now
    local o = opts()
    if not o then return end
    local c = o.cat
    local list = deals[c]
    for _, key in ipairs(CATS) do
        local b = ui.cats[key]
        local n = #deals[key]
        b:SetText(string.format("%s (%d)", key == "de" and L.DEAL_CAT_DE or L.DEAL_CAT_RESALE, n))
        local on = key == c
        b.line:SetShown(on)
        if on then b.cuiText:SetTextColor(C.gold[1], C.gold[2], C.gold[3]) else b.cuiText:SetTextColor(0.75, 0.75, 0.75) end
    end
    ui.fields[1].label:SetText(c == "de" and L.DEAL_DE_PCT or L.DEAL_PCT)
    for _, e in ipairs(ui.fields) do
        if not e:HasFocus() then e:SetText(e.get()) end
    end
    ui.vendor:SetChecked(o.vendor)
    ui.sort:SetText(o.sort == "profit" and L.DEAL_SORT_PROFIT or L.DEAL_SORT_ROI)
    ui.vendor:SetShown(c == "resale")
    if job then
        ui.summary:SetText(string.format(L.DEAL_SCANNING, total > 0 and math.floor(job.seen * 100 / total) or 0))
        ui.refresh:SetEnabled(false)
    else
        local sum, cost = sumOf(list)
        local text = string.format(L.DEAL_SUMMARY, #list, AH.Money(sum))
        if cost > 0 then text = text .. string.format(L.DEAL_SUM_ROI, math.floor(sum / cost * 100 + 0.5)) end
        ui.summary:SetText(text)
        ui.refresh:SetEnabled(true)
    end
    ui.list:SetData(list)
    ui.empty:SetText(c == "de" and L.DEAL_EMPTY_DE or L.DEAL_EMPTY)
    ui.empty:SetShown(#list == 0 and not job)
    ui.hint:SetText(c == "de" and L.DEAL_HINT_DE or L.DEAL_HINT_RES)
end

AH.AddTab({ key = "deals", order = 4, label = function() return L.AHP_TAB_DEALS end, build = build, refresh = refresh,
            show = function()
                lastPaint = 0
                if not job and (dirty or not builtAt or GetTime() - builtAt > 60) then startSearch(false) end
            end })

-- la base change (scan, recherches) : la liste sera refaite a l ouverture
if ns.AHListen then ns.AHListen(function() dirty = true end) end

-- apres un scan complet : recherche et annonce
ns.AHScanDoneHooks = ns.AHScanDoneHooks or {}
table.insert(ns.AHScanDoneHooks, function() startSearch(true) end)

-- recherche par tranches, meme onglet ferme
local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function()
    if job and not InCombatLockdown() then stepSearch() end
end)

-- case dans le panneau /corp hv
ns.AHPanelHooks = ns.AHPanelHooks or {}
table.insert(ns.AHPanelHooks, function(panel, form)
    form:Header(L.DEAL_SEC)
    form:Check(L.DEAL_OPT_ANNOUNCE, function() local o = opts() return o and o.announce end, function(v)
        local o = opts()
        if o then o.announce = v end
    end)
    local btn = ns.UI.Button(panel, "", 200, function(self)
        local o = opts()
        if o then
            wipe(o.ignore)
            wipe(o.ignoreDE)
        end
        self:SetText(string.format(L.DEAL_RESET_IGNORE, 0))
    end)
    btn:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, form.y - 2)
    form.y = form.y - 30
    table.insert(form.refreshers, function()
        local o = opts()
        local n = 0
        for _ in pairs(o and o.ignore or {}) do n = n + 1 end
        for _ in pairs(o and o.ignoreDE or {}) do n = n + 1 end
        btn:SetText(string.format(L.DEAL_RESET_IGNORE, n))
        btn:SetEnabled(n > 0)
    end)
end)

-- banc d essai
AH._deals = { step = stepSearch, list = function(c) return deals[c or "resale"] end, job = function() return job end,
              ui = function() return ui end }
