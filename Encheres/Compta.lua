--[[--------------------------------------------------------------------------
    CorpUI - module Encheres : comptabilite (onglet Compta du volet et
    panneau /corp compta)

    Operations de l hotel des ventes, par royaume et faction, pour tous les
    persos du compte :
      - ventes et achats : lus dans les factures des courriers de l HV
        (GetInboxInvoiceInfo) a chaque mise a jour de la boite aux
        lettres ; un courrier deja lu n est pas compte deux fois (cle :
        type, objet, joueur, montant, quantite, heure d expiration) ;
      - encheres expirees et annulees : objet du courrier (sujets de
        Blizzard AUCTION_EXPIRED_MAIL_SUBJECT / AUCTION_REMOVED_MAIL_SUBJECT) ;
      - depots et frais d annulation : l argent qui part au moment ou une
        enchere est creee ou annulee (PLAYER_MONEY a 3 s pres) ; le depot
        rendu avec une vente vient en deduction.
    Bilan aujourd hui / 7 jours / 30 jours (ventes nettes de la commission,
    achats, frais, benefice), meilleures ventes, dernieres operations, et
    l or de tous les persos jour par jour (releve a chaque connexion et a
    chaque changement : un point par heure, un par jour apres 7 jours).
    Ligne "Derniere vente" dans les infobulles (option).
    Lecture seule du courrier : rien n est ouvert, pris ni supprime.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L
local C = ns.COLORS
local AH = ns.AH

local issecret = issecretvalue or function() return false end
local num, str, call = AH.num, AH.str, AH.call

local MAX_TX = 5000          -- operations gardees par royaume au plus
local SEEN_DAYS = 32         -- courriers deja comptes : gardes 32 jours
local MATCH = 3              -- argent parti a 3 s d une creation / annulation
local GOLD_DAYS = 400        -- historique de l or : 400 jours au plus

---------------------------------------------------------------------------
-- Donnees : db.ledger[royaume] = { tx = {...}, seen = {...} } ;
-- db.gold[perso] = { { t, argent }, ... }
---------------------------------------------------------------------------

local function ledger()
    local db = AH.DB()
    if not db then return nil end
    if type(db.ledger) ~= "table" then db.ledger = {} end
    local key = (ns.AHRealmKey and ns.AHRealmKey()) or "?"
    local r = db.ledger[key]
    if type(r) ~= "table" then
        r = {}
        db.ledger[key] = r
    end
    if type(r.tx) ~= "table" then r.tx = {} end
    if type(r.seen) ~= "table" then r.seen = {} end
    return r
end
AH.Ledger = ledger

local function bookOpts()
    local db = AH.DB()
    if not db then return {} end
    if type(db.book) ~= "table" then db.book = {} end
    if db.book.tip == nil then db.book.tip = true end
    return db.book
end

local listeners = {}
local function changed()
    for _, fn in ipairs(listeners) do pcall(fn) end
    AH.Refresh("book")
end

-- k : "sale", "buy", "expired", "cancel", "deposit", "cancelfee"
local function addTx(tx)
    local r = ledger()
    if not r then return end
    tx.t = tx.t or time()
    tx.char = tx.char or ns.CharKey()
    table.insert(r.tx, tx)
    while #r.tx > MAX_TX do table.remove(r.tx, 1) end
    changed()
end
AH.LedgerAdd = addTx

---------------------------------------------------------------------------
-- Courrier : factures de l HV, expirees, annulees
---------------------------------------------------------------------------

-- "Auction expired: %s" -> motif qui capture l objet
local function subjectPattern(fmt)
    fmt = str(fmt)
    if not fmt or not fmt:find("%s", 1, true) then return nil end
    local p = fmt:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    p = p:gsub("%%s", "(.+)")
    return "^" .. p .. "$"
end

local function mailKey(parts, expiry)
    return table.concat(parts, "|") .. "|" .. math.floor(expiry / 1800)
end

-- deja compte (a une demi-heure pres sur l heure d expiration)
local function seenMail(r, parts, expiry)
    for d = -1, 1 do
        if r.seen[mailKey(parts, expiry + d * 1800)] then return true end
    end
    return false
end

local function markMail(r, parts, expiry)
    r.seen[mailKey(parts, expiry)] = math.floor(expiry)
end

local function scanInbox()
    local r = ledger()
    if not r or type(GetInboxNumItems) ~= "function" then return 0 end
    local n = num(call(GetInboxNumItems)) or 0
    local now = time()
    local added = 0
    local expPat = subjectPattern(AUCTION_EXPIRED_MAIL_SUBJECT)
    local canPat = subjectPattern(AUCTION_REMOVED_MAIL_SUBJECT)
    for i = 1, n do
        local ok, _, _, sender, subject, money, _, daysLeft = pcall(GetInboxHeaderInfo, i)
        daysLeft = ok and num(daysLeft)
        if daysLeft then
            local expiry = now + daysLeft * 86400
            local okI, kind, itemName, player, bid, _, deposit, consignment, _, _, _, count
            if type(GetInboxInvoiceInfo) == "function" then
                okI, kind, itemName, player, bid, _, deposit, consignment, _, _, _, count = pcall(GetInboxInvoiceInfo, i)
            end
            kind, itemName, player = okI and str(kind), okI and str(itemName), okI and str(player)
            bid, deposit, consignment, count = num(bid), num(deposit) or 0, num(consignment) or 0, num(count)
            local tx
            if kind == "seller" and itemName and bid then
                tx = { k = "sale", item = itemName, q = count or 1, p = bid, fee = consignment, dep = deposit, who = player }
            elseif kind == "buyer" and itemName and bid then
                tx = { k = "buy", item = itemName, q = count or 1, p = bid, who = player }
            else
                subject = ok and str(subject)
                local item = subject and ((expPat and subject:match(expPat)) or (canPat and subject:match(canPat)))
                if item then
                    local isExp = expPat and subject:match(expPat) ~= nil
                    tx = { k = isExp and "expired" or "cancel", item = item, q = 1 }
                end
            end
            if tx then
                -- objet joint (achat, expiree, annulee) : son numero et sa quantite
                if tx.k ~= "sale" and type(GetInboxItem) == "function" then
                    local okG, _, id, _, q = pcall(GetInboxItem, i, 1)
                    if okG and num(id) then
                        tx.id = id
                        if tx.k ~= "buy" and num(q) then tx.q = q end
                    end
                end
                local parts = { tx.k, tx.item, tx.who or "", tx.p or 0, tx.q or 1, num(money) or 0 }
                if not seenMail(r, parts, expiry) then
                    markMail(r, parts, expiry)
                    tx.t = now
                    addTx(tx)
                    added = added + 1
                end
            end
        end
    end
    return added
end
AH.LedgerScanMail = scanInbox

-- menage des courriers deja comptes : un courrier expire n est plus dans
-- la boite, sa cle ne sert plus (un jour de marge)
local function purgeSeen()
    local r = ledger()
    if not r then return end
    local now = time()
    local drop = {}
    for k, exp in pairs(r.seen) do
        if type(exp) ~= "number" or exp < now - 86400 or exp > now + SEEN_DAYS * 86400 then drop[#drop + 1] = k end
    end
    for _, k in ipairs(drop) do r.seen[k] = nil end
end

---------------------------------------------------------------------------
-- Depots et frais d annulation : argent parti pres d une creation /
-- annulation d enchere
---------------------------------------------------------------------------

local lastMoney
local drops = {}         -- { t, montant } recents
local pending = {}       -- { t, k } evenements HV en attente de l argent

local function matchDrop(k)
    local now = GetTime()
    for i, d in ipairs(drops) do
        if math.abs(now - d.t) <= MATCH then
            table.remove(drops, i)
            addTx({ k = k, p = d.amount })
            return true
        end
    end
    return false
end

local function onMoney()
    local m = num(call(GetMoney))
    if not m then return end
    if lastMoney and m < lastMoney and ns.AHFrame and ns.AHFrame() then
        local d = { t = GetTime(), amount = lastMoney - m }
        -- un evenement HV attendait cet argent ?
        local used = false
        for i, p in ipairs(pending) do
            if d.t - p.t <= MATCH then
                table.remove(pending, i)
                addTx({ k = p.k, p = d.amount })
                used = true
                break
            end
        end
        if not used then
            drops[#drops + 1] = d
            while #drops > 5 do table.remove(drops, 1) end
        end
    end
    lastMoney = m
end

local function onAuctionEvent(k)
    if not matchDrop(k) then
        pending[#pending + 1] = { t = GetTime(), k = k }
        while #pending > 10 do table.remove(pending, 1) end
    end
end

---------------------------------------------------------------------------
-- Or de tous les persos
---------------------------------------------------------------------------

local function goldDB()
    local db = AH.DB()
    if not db then return nil end
    if type(db.gold) ~= "table" then db.gold = {} end
    return db.gold
end

local function recordGold()
    local g = goldDB()
    local m = num(call(GetMoney))
    if not (g and m) then return end
    local key = ns.CharKey()
    local pts = g[key]
    if type(pts) ~= "table" then
        pts = {}
        g[key] = pts
    end
    local now = time()
    local last = pts[#pts]
    if last and last[2] == m then return end
    -- un point par heure : le dernier de l heure remplace le precedent
    if last and math.floor(last[1] / 3600) == math.floor(now / 3600) then
        last[1], last[2] = now, m
    else
        pts[#pts + 1] = { now, m }
    end
end

-- au-dela de 7 jours, un point par jour (le dernier du jour)
local function compactGold()
    local g = goldDB()
    if not g then return end
    local now = time()
    for key, pts in pairs(g) do
        if type(pts) == "table" then
            local out, lastDay = {}, nil
            for _, p in ipairs(pts) do
                if type(p) == "table" and num(p[1]) and num(p[2]) and now - p[1] < GOLD_DAYS * 86400 then
                    local day = math.floor(p[1] / 86400)
                    if now - p[1] > 7 * 86400 and lastDay == day then
                        out[#out] = p
                    else
                        out[#out + 1] = p
                    end
                    lastDay = day
                end
            end
            g[key] = out
        end
    end
end

-- or total (tous les persos) a la fin de chacun des `days` derniers jours
function AH.GoldSeries(days)
    local g = goldDB() or {}
    local today = math.floor(time() / 86400)
    local out = {}
    for d = days - 1, 0, -1 do
        local dayEnd = (today - d + 1) * 86400
        local total, any = 0, false
        for _, pts in pairs(g) do
            if type(pts) == "table" then
                local v
                for _, p in ipairs(pts) do
                    if p[1] < dayEnd then v = p[2] else break end
                end
                if v then total, any = total + v, true end
            end
        end
        out[#out + 1] = { day = today - d, gold = any and total or nil }
    end
    return out
end

---------------------------------------------------------------------------
-- Bilans
---------------------------------------------------------------------------

-- bilan depuis `since` (horodatage) : sales (net), buys, fees, profit, nSales, nBuys
function AH.LedgerSummary(since)
    local r = ledger()
    local s = { sales = 0, buys = 0, fees = 0, nSales = 0, nBuys = 0, nExpired = 0 }
    for _, tx in ipairs(r and r.tx or {}) do
        if tx.t >= since then
            if tx.k == "sale" then
                s.sales = s.sales + (tx.p or 0) - (tx.fee or 0)
                s.fees = s.fees - (tx.dep or 0)
                s.nSales = s.nSales + 1
            elseif tx.k == "buy" then
                s.buys, s.nBuys = s.buys + (tx.p or 0), s.nBuys + 1
            elseif tx.k == "deposit" or tx.k == "cancelfee" then
                s.fees = s.fees + (tx.p or 0)
            elseif tx.k == "expired" or tx.k == "cancel" then
                s.nExpired = s.nExpired + 1
            end
        end
    end
    s.fees = math.max(0, s.fees)
    s.profit = s.sales - s.buys - s.fees
    return s
end

-- meilleures ventes depuis `since` : { item, q, net } par recette decroissante
function AH.LedgerTop(since, n)
    local r = ledger()
    local by, out = {}, {}
    for _, tx in ipairs(r and r.tx or {}) do
        if tx.k == "sale" and tx.t >= since then
            local e = by[tx.item]
            if not e then
                e = { item = tx.item, q = 0, net = 0 }
                by[tx.item] = e
                out[#out + 1] = e
            end
            e.q, e.net = e.q + (tx.q or 1), e.net + (tx.p or 0) - (tx.fee or 0)
        end
    end
    table.sort(out, function(a, b) return a.net > b.net end)
    while #out > (n or 5) do table.remove(out) end
    return out
end

-- derniere vente d un objet (par son nom) : prix unitaire brut, horodatage
function AH.LastSale(name)
    local r = ledger()
    if not (r and name) then return nil end
    for i = #r.tx, 1, -1 do
        local tx = r.tx[i]
        if tx.k == "sale" and tx.item == name then return (tx.p or 0) / math.max(1, tx.q or 1), tx.t end
    end
end

---------------------------------------------------------------------------
-- Vue (onglet du volet et panneau /corp compta)
---------------------------------------------------------------------------

local KIND = { sale = { "BOOK_K_SALE", "6be070" }, buy = { "BOOK_K_BUY", "ff9060" }, expired = { "BOOK_K_EXPIRED", "9d9d9d" },
               cancel = { "BOOK_K_CANCEL", "9d9d9d" }, deposit = { "BOOK_K_DEPOSIT", "ffa040" }, cancelfee = { "BOOK_K_CANCELFEE", "ffa040" } }

local function signed(c)
    if c < 0 then return "|cffff6060-" .. AH.Money(-c) .. "|r" end
    return AH.Money(c)
end

local function txAmount(tx)
    if tx.k == "sale" then return (tx.p or 0) - (tx.fee or 0) end
    if tx.k == "buy" or tx.k == "deposit" or tx.k == "cancelfee" then return -(tx.p or 0) end
end

local views = {}

local function buildView(page, w, top)
    local v = { page = page, w = w }
    local PAD = 8
    local y = top
    AH.Header(page, L.BOOK_SEC_SUMMARY, y)
    y = y - 22
    -- tableau : libelle + 3 colonnes
    local colW = math.floor((w - PAD * 2 - 70) / 3)
    v.cells = {}
    local heads = { L.BOOK_TODAY, L.BOOK_7D, L.BOOK_30D }
    for c = 1, 3 do
        local fs = AH.Text(page, "GameFontNormalSmall", "RIGHT")
        fs:SetPoint("TOPLEFT", page, "TOPLEFT", PAD + 70 + (c - 1) * colW, y)
        fs:SetWidth(colW)
        fs:SetText(heads[c])
    end
    y = y - 15
    local rows = { "sales", "buys", "fees", "profit" }
    local labels = { sales = L.BOOK_SALES, buys = L.BOOK_BUYS, fees = L.BOOK_FEES, profit = L.BOOK_PROFIT }
    for _, key in ipairs(rows) do
        local lab = AH.Text(page, "GameFontHighlightSmall", "LEFT")
        lab:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, y)
        lab:SetWidth(70)
        lab:SetText(labels[key])
        v.cells[key] = {}
        for c = 1, 3 do
            local fs = AH.Text(page, "GameFontHighlightSmall", "RIGHT")
            fs:SetPoint("TOPLEFT", page, "TOPLEFT", PAD + 70 + (c - 1) * colW, y)
            fs:SetWidth(colW)
            v.cells[key][c] = fs
        end
        y = y - 15
    end
    y = y - 8
    -- or de tous les persos : 30 barres
    AH.Header(page, L.BOOK_SEC_GOLD, y)
    y = y - 22
    v.goldNow = AH.Text(page, "GameFontHighlightSmall", "LEFT")
    v.goldNow:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, y)
    y = y - 14
    local chartH = 60
    local chart = CreateFrame("Frame", nil, page)
    chart:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, y)
    chart:SetSize(w - PAD * 2, chartH)
    local back = chart:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(0, 0, 0, 0.25)
    v.bars = {}
    local bw = (w - PAD * 2) / 30
    for i = 1, 30 do
        local b = CreateFrame("Frame", nil, chart)
        b:SetPoint("BOTTOMLEFT", chart, "BOTTOMLEFT", (i - 1) * bw, 0)
        b:SetSize(math.max(1, bw - 1), chartH)
        b:EnableMouse(true)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetPoint("BOTTOMLEFT")
        b.tex:SetPoint("BOTTOMRIGHT")
        b.tex:SetHeight(1)
        ns.NoSnap(b.tex)
        ns.UI.Gradient(b.tex, "VERTICAL", C.violet[1], C.violet[2], C.violet[3], 0.9, C.gold[1], C.gold[2], C.gold[3], 0.9)
        b:SetScript("OnEnter", function(self)
            if not self.data then return end
            local t = ns.Tooltip(self, "ANCHOR_TOP")
            t:AddLine(date and date("%d/%m", self.data.day * 86400 + 43200) or tostring(self.data.day))
            t:AddLine(self.data.gold and AH.Money(self.data.gold) or "?", 1, 1, 1)
            t:Show()
        end)
        b:SetScript("OnLeave", function() ns.HideTooltip() end)
        v.bars[i] = b
    end
    v.chartH = chartH
    y = y - chartH - 10
    -- meilleures ventes
    AH.Header(page, L.BOOK_SEC_TOP, y)
    y = y - 22
    v.top = {}
    for i = 1, 3 do
        local fs = AH.Text(page, "GameFontHighlightSmall", "LEFT")
        fs:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, y)
        fs:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
        v.top[i] = fs
        y = y - 14
    end
    y = y - 6
    -- dernieres operations
    AH.Header(page, L.BOOK_SEC_LAST, y)
    y = y - 22
    v.list = AH.List(page, 16, function(list)
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
        if tx.who and tx.who ~= "" then item = item .. " |cff9d9d9d(" .. tx.who .. ")|r" end
        row.item:SetText(item)
        local a = txAmount(tx)
        row.amount:SetText(a and signed(a) or "")
    end)
    v.list:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, y)
    v.list:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -PAD, 8)
    v.empty = AH.Text(page, "GameFontDisableSmall", "LEFT")
    v.empty:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, y)
    v.empty:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
    v.empty:SetHeight(44)
    v.empty:SetWordWrap(true)
    v.empty:SetJustifyV("TOP")
    v.empty:SetText(L.BOOK_EMPTY)
    views[#views + 1] = v
    return v
end

local function fillView(v)
    local now = time()
    local today = math.floor(now / 86400) * 86400
    local periods = { today, now - 7 * 86400, now - 30 * 86400 }
    for c, since in ipairs(periods) do
        local s = AH.LedgerSummary(since)
        v.cells.sales[c]:SetText(AH.Money(s.sales))
        v.cells.buys[c]:SetText(AH.Money(s.buys))
        v.cells.fees[c]:SetText(AH.Money(s.fees))
        v.cells.profit[c]:SetText(signed(s.profit))
    end
    local series = AH.GoldSeries(30)
    local max = 0
    for _, d in ipairs(series) do if d.gold and d.gold > max then max = d.gold end end
    for i, b in ipairs(v.bars) do
        local d = series[i]
        b.data = d
        local h = (d and d.gold and max > 0) and math.max(1, v.chartH * d.gold / max) or 1
        b.tex:SetHeight(h)
        b.tex:SetAlpha((d and d.gold) and 1 or 0.2)
    end
    local last = series[#series]
    v.goldNow:SetText(string.format(L.BOOK_GOLD_NOW, AH.Money(last and last.gold or 0)))
    local top = AH.LedgerTop(now - 30 * 86400, 3)
    for i, fs in ipairs(v.top) do
        local e = top[i]
        fs:SetText(e and string.format(L.BOOK_TOP_LINE, e.item, e.q, AH.Money(e.net)) or "")
    end
    local r = ledger()
    local list = {}
    for i = #(r and r.tx or {}), 1, -1 do list[#list + 1] = r.tx[i] end
    v.list:SetData(list)
    v.empty:SetShown(#list == 0)
end

local lastPaint = 0
listeners[#listeners + 1] = function() lastPaint = 0 end

AH.AddTab({ key = "book", order = 5, label = function() return L.AHP_TAB_BOOK end,
    build = function(page) page.view = buildView(page, AH.W or 340, -6) end,
    refresh = function(page)
        if not page.view then return end
        local now = GetTime()
        if now - lastPaint < 5 then return end
        lastPaint = now
        fillView(page.view)
    end,
    show = function() lastPaint = 0 end })

---------------------------------------------------------------------------
-- Panneau /corp compta (fenetre principale, page Hotel des ventes)
---------------------------------------------------------------------------

local panel

local function buildPanel()
    panel = ns.UI.Window("CorpUIAccountingOptions", ns.TITLE .. " - " .. L.MOD_BOOK, nil, 440, 520)
    panel.view = buildView(panel, 440, -34)
    panel:HookScript("OnShow", function() fillView(panel.view) end)
    listeners[#listeners + 1] = function() if panel:IsVisible() then fillView(panel.view) end end
end

local function toggle()
    if not AH.DB() then return end
    if not panel then buildPanel() end
    ns.ShowPanel(panel)
end

ns.RegisterModule({
    command = "compta",
    alias = "ledger",
    panelName = "CorpUIAccountingOptions",
    icon = "Interface\\Icons\\INV_Misc_Note_01",
    title = function() return L.MOD_BOOK end,
    desc = function() return L.BOOK_DESC end,
    Slash = function() toggle() end,
    Open = toggle,
})

-- reglages dans le panneau /corp hv
ns.AHPanelHooks = ns.AHPanelHooks or {}
table.insert(ns.AHPanelHooks, function(p, form)
    form:Header(L.BOOK_SEC_OPTS)
    form:Check(L.BOOK_OPT_TIP, function() return bookOpts().tip end, function(v) bookOpts().tip = v end)
end)

---------------------------------------------------------------------------
-- Infobulle : derniere vente de l objet
---------------------------------------------------------------------------

ns.tipItemProviders = ns.tipItemProviders or {}
table.insert(ns.tipItemProviders, function(tip, link, out)
    if not AH.DB() or not bookOpts().tip or issecret(link) or type(link) ~= "string" then return end
    local name = link:match("|h%[(.-)%]|h")
    if not name then return end
    local p, t = AH.LastSale(name)
    if p then
        out[#out + 1] = "|cffffd100" .. L.BOOK_TIP_LAST .. "|r " .. AH.Money(p) .. " |cff9d9d9d(" .. ns.FormatAgo(t) .. ")|r"
    end
end)

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
local scanQueued = false
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        lastMoney = num(call(GetMoney))
        C_Timer.After(5, function()
            compactGold()
            recordGold()
            purgeSeen()
        end)
    elseif event == "PLAYER_MONEY" then
        onMoney()
        recordGold()
    elseif event == "PLAYER_LOGOUT" then
        recordGold()
    elseif event == "MAIL_INBOX_UPDATE" or event == "MAIL_SHOW" then
        if not scanQueued then
            scanQueued = true
            C_Timer.After(0.5, function()
                scanQueued = false
                scanInbox()
            end)
        end
    elseif event == "AUCTION_HOUSE_AUCTION_CREATED" then
        onAuctionEvent("deposit")
    elseif event == "AUCTION_CANCELED" then
        onAuctionEvent("cancelfee")
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_MONEY", "PLAYER_LOGOUT", "MAIL_INBOX_UPDATE", "MAIL_SHOW",
                     "AUCTION_HOUSE_AUCTION_CREATED", "AUCTION_CANCELED" }) do
    pcall(ev.RegisterEvent, ev, e)
end

-- banc d essai
AH._book = { scan = scanInbox, money = onMoney, auction = onAuctionEvent, gold = recordGold, compact = compactGold,
             fill = function() for _, v in ipairs(views) do fillView(v) end end }
