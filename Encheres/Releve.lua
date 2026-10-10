--[[--------------------------------------------------------------------------
    CorpUI - module Encheres : volet du courrier (recuperer l or)

    Volet colle a droite de la fenetre du courrier (onglet Boite de
    reception), de sa hauteur : or a recuperer, ventes et achats de l HV,
    objets joints, liste des courriers de l HV (vente, achat, expiree,
    annulee : objet et montant) ; bouton "Recuperer l or" qui prend l or de
    tous les courriers sans toucher aux objets (le bouton "Tout ouvrir" de
    Blizzard prend tout). Comme celui de Blizzard : jamais les
    contre-remboursements ni les courriers de MJ, une prise a la fois
    (C_Mail.IsCommandPending), arret si la fenetre se ferme, en combat ou si
    le jeu bloque l action. La comptabilite lit les factures avant chaque
    prise (le courrier disparait une fois vide).
    Notre cadre seulement : rien n est ecrit dans MailFrame ni ses scripts.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L
local C = ns.COLORS
local AH = ns.AH

local issecret = issecretvalue or function() return false end
local num, str, call = AH.num, AH.str, AH.call

local W = 240              -- largeur du volet
local PAD = 8
local ROW_H = 16
local GAP = 0.3            -- entre deux prises
local STUCK = 3            -- courrier toujours plein au bout de 3 s : on le saute
local MAX_TAKES = 100

local side
local run                  -- recuperation en cours

local function mailOpts()
    local db = AH.DB()
    if not db then return nil end
    if type(db.mail) ~= "table" then db.mail = {} end
    if db.mail.bar == nil then db.mail.bar = true end
    return db.mail
end

local function inboxShown()
    return AH.visible(_G.InboxFrame) and AH.visible(_G.MailFrame)
end

local function dirty()
    if side then side.dirty = true end
end

-- un courrier : or, contre-remboursement, objets, MJ
local function header(i)
    local ok, _, _, _, subject, money, cod, _, itemCount, _, _, _, _, isGM = pcall(GetInboxHeaderInfo, i)
    if not ok then return nil end
    return num(money) or 0, num(cod) or 0, num(itemCount) or 0, isGM == true, str(subject)
end

-- "Enchere expiree : %s" -> motif qui capture l objet
local function subjectPattern(fmt)
    fmt = str(fmt)
    if not fmt or not fmt:find("%s", 1, true) then return nil end
    local p = fmt:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    p = p:gsub("%%s", "(.+)")
    return "^" .. p .. "$"
end

-- resume de la boite : or prenable, courriers avec or, objets joints,
-- ventes et achats de l HV, et la liste des courriers de l HV
-- { k = "sale" / "buy" / "expired" / "cancel", item, amount }
local function summary()
    local n = num(call(GetInboxNumItems)) or 0
    local s = { n = n, gold = 0, nGold = 0, items = 0, sales = 0, buys = 0, list = {} }
    local expPat = subjectPattern(AUCTION_EXPIRED_MAIL_SUBJECT)
    local canPat = subjectPattern(AUCTION_REMOVED_MAIL_SUBJECT)
    for i = 1, n do
        local money, cod, count, gm, subject = header(i)
        if money then
            if cod == 0 and not gm then
                if money > 0 then s.gold, s.nGold = s.gold + money, s.nGold + 1 end
                s.items = s.items + count
            end
            local kind, item, bid
            if type(GetInboxInvoiceInfo) == "function" then
                local ok, k, it, _, b = pcall(GetInboxInvoiceInfo, i)
                if ok then kind, item, bid = str(k), str(it), num(b) end
            end
            if kind == "seller" and item then
                s.sales = s.sales + 1
                s.list[#s.list + 1] = { k = "sale", item = item, amount = money }
            elseif kind == "buyer" and item then
                s.buys = s.buys + 1
                s.list[#s.list + 1] = { k = "buy", item = item, amount = bid and -bid }
            elseif subject then
                local e = expPat and subject:match(expPat)
                local c = canPat and subject:match(canPat)
                if e or c then s.list[#s.list + 1] = { k = e and "expired" or "cancel", item = e or c } end
            end
        end
    end
    return s
end
AH.MailSummary = summary

---------------------------------------------------------------------------
-- Recuperation de l or
---------------------------------------------------------------------------

local function stop(msg)
    if run and msg then ns.Say(msg) end
    run = nil
    dirty()
end

local function finish()
    if run then ns.Say(string.format(L.MAIL_DONE, AH.Money(run.got), run.n)) end
    stop()
end

local function nextGoldMail()
    local n = num(call(GetInboxNumItems)) or 0
    local now = GetTime()
    for i = 1, n do
        local money, cod, _, gm = header(i)
        if money and money > 0 and cod == 0 and not gm then
            local tried = run.tried[i .. ":" .. money]
            if not tried or now - tried < STUCK then return i, money, tried end
        end
    end
end

local function step()
    if not run then return end
    if not inboxShown() or InCombatLockdown() then stop() return end
    if C_Mail and C_Mail.IsCommandPending and call(C_Mail.IsCommandPending) == true then return end
    local now = GetTime()
    if now < run.next then return end
    if AH.LedgerScanMail then pcall(AH.LedgerScanMail) end
    local i, money, tried = nextGoldMail()
    if not i or run.takes >= MAX_TAKES then finish() return end
    if tried then
        -- deja demande : on attend que le serveur reponde (ou on le sautera)
        run.next = now + GAP
        return
    end
    run.tried[i .. ":" .. money] = now
    local ok = pcall(TakeInboxMoney, i)
    if not ok then stop(L.MAIL_BLOCKED) return end
    run.takes = run.takes + 1
    run.got, run.n = run.got + money, run.n + 1
    run.next = now + GAP
    dirty()
end

local function start()
    if run or not inboxShown() then return end
    if InCombatLockdown() then ns.Say(L.COMBAT_BLOCKED) return end
    run = { got = 0, n = 0, takes = 0, next = 0, tried = {} }
    step()
end
AH.MailTakeGold = start

---------------------------------------------------------------------------
-- Volet
---------------------------------------------------------------------------

local KIND = { sale = { "BOOK_K_SALE", "6be070" }, buy = { "BOOK_K_BUY", "ff9060" },
               expired = { "BOOK_K_EXPIRED", "9d9d9d" }, cancel = { "BOOK_K_CANCEL", "9d9d9d" } }

local function buildSide()
    side = CreateFrame("Frame", "CorpUIMailSide", UIParent)
    side:SetSize(W, 300)
    side:EnableMouse(true)
    ns.UI.Skin(side, 0.96, true)
    side.title = side:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(side.title, 14)
    side.title:SetPoint("TOPLEFT", side, "TOPLEFT", PAD, -8)
    side.title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    side.title:SetText(L.MAIL_TITLE)
    side.gold = AH.Text(side, "GameFontHighlight", "LEFT")
    side.gold:SetPoint("TOPLEFT", side, "TOPLEFT", PAD, -32)
    side.gold:SetPoint("RIGHT", side, "RIGHT", -PAD, 0)
    side.counts = AH.Text(side, "GameFontDisableSmall", "LEFT")
    side.counts:SetPoint("TOPLEFT", side, "TOPLEFT", PAD, -50)
    side.counts:SetPoint("RIGHT", side, "RIGHT", -PAD, 0)
    side.counts:SetHeight(26)
    side.counts:SetWordWrap(true)
    side.counts:SetJustifyV("TOP")
    AH.Header(side, L.MAIL_LIST, -80)
    side.list = AH.List(side, ROW_H, function(list)
        local row = CreateFrame("Frame", nil, list)
        row.kind = AH.Text(row, "GameFontHighlightSmall", "LEFT")
        row.kind:SetPoint("LEFT", 0, 0)
        row.kind:SetWidth(54)
        row.amount = AH.Text(row, "GameFontHighlightSmall", "RIGHT")
        row.amount:SetPoint("RIGHT", 0, 0)
        row.item = AH.Text(row, "GameFontHighlightSmall", "LEFT")
        row.item:SetPoint("LEFT", row.kind, "RIGHT", 2, 0)
        row.item:SetPoint("RIGHT", row.amount, "LEFT", -4, 0)
        return row
    end, function(row, e)
        local k = KIND[e.k] or { "", "ffffff" }
        row.kind:SetText("|cff" .. k[2] .. (L[k[1]] or e.k) .. "|r")
        row.item:SetText(e.item or "")
        if e.amount and e.amount < 0 then
            row.amount:SetText("|cffff6060-" .. AH.Money(-e.amount) .. "|r")
        elseif e.amount and e.amount > 0 then
            row.amount:SetText(AH.Money(e.amount))
        else
            row.amount:SetText("")
        end
    end)
    side.list:SetPoint("TOPLEFT", side, "TOPLEFT", PAD, -102)
    side.list:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", -PAD, 58)
    side.empty = AH.Text(side, "GameFontDisableSmall", "LEFT")
    side.empty:SetPoint("TOPLEFT", side, "TOPLEFT", PAD, -104)
    side.empty:SetPoint("RIGHT", side, "RIGHT", -PAD, 0)
    side.empty:SetText(L.MAIL_NONE_AH)
    side.status = AH.Text(side, "GameFontHighlightSmall", "LEFT")
    side.status:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", PAD, 38)
    side.status:SetPoint("RIGHT", side, "RIGHT", -PAD, 0)
    local b = ns.UI.Button(side, L.MAIL_GOLD, W - PAD * 2, start)
    b:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", PAD, PAD)
    b:SetMotionScriptsWhileDisabled(true)
    b:HookScript("OnEnter", function(self)
        local t = ns.Tooltip(self, "ANCHOR_TOP")
        t:AddLine(L.MAIL_GOLD)
        t:AddLine(L.MAIL_GOLD_TIP, 1, 1, 1, true)
        t:Show()
    end)
    b:HookScript("OnLeave", function() ns.HideTooltip() end)
    side.button = b
    side:Hide()
end

local function paint()
    local s = summary()
    if s.gold > 0 then
        side.gold:SetText(string.format(L.MAIL_GOLD_LINE, AH.Money(s.gold)) .. "|cff9d9d9d  " .. string.format(L.MAIL_IN, s.nGold) .. "|r")
    elseif s.n == 0 then
        side.gold:SetText("|cff9d9d9d" .. L.MAIL_EMPTY .. "|r")
    else
        side.gold:SetText(string.format(L.MAIL_GOLD_LINE, AH.Money(0)))
    end
    side.counts:SetText(string.format(L.MAIL_COUNTS, s.sales, s.buys, s.items))
    side.list:SetData(s.list)
    side.empty:SetShown(#s.list == 0)
    if run then
        side.status:SetText(string.format(L.MAIL_TAKING, AH.Money(run.got)))
    else
        side.status:SetText("")
    end
    side.button:SetEnabled(not run and s.gold > 0)
end

local acc, sumAcc = 0, 0
local function tick(dt)
    local o = mailOpts()
    if not (o and o.bar and inboxShown()) then
        if side and side:IsShown() then side:Hide() end
        if run then stop() end
        return
    end
    if not side then buildSide() end
    -- a droite de la fenetre du courrier, de sa hauteur
    local mf = _G.MailFrame
    if side.anchoredTo ~= mf then
        side:ClearAllPoints()
        side:SetPoint("TOPLEFT", mf, "TOPRIGHT", 4, 0)
        side.anchoredTo = mf
    end
    local okH, h = pcall(mf.GetHeight, mf)
    h = okH and num(h)
    if h and h > 200 and math.abs((side:GetHeight() or 0) - h) > 0.5 then side:SetHeight(h) end
    if ns.AHFollow then ns.AHFollow(side, mf) end
    if not side:IsShown() then
        side:Show()
        side.dirty = true
    end
    step()
    sumAcc = sumAcc + dt
    if side.dirty or sumAcc > 1 then
        sumAcc, side.dirty = 0, false
        paint()
    end
end

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.1 then return end
    tick(acc)
    acc = 0
end)
driver:SetScript("OnEvent", function(_, event, who)
    if ns.ModuleOff("hv", driver) then return end
    if event == "MAIL_INBOX_UPDATE" then
        dirty()
    elseif (event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN") and run then
        if not issecret(who) and type(who) == "string" and who:find("CorpUI", 1, true) then stop(L.MAIL_BLOCKED) end
    elseif event == "MAIL_CLOSED" then
        stop()
    end
end)
for _, e in ipairs({ "MAIL_INBOX_UPDATE", "MAIL_CLOSED", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
    pcall(driver.RegisterEvent, driver, e)
end

-- case dans le panneau /corp hv (section Comptabilite)
ns.AHPanelHooks = ns.AHPanelHooks or {}
table.insert(ns.AHPanelHooks, function(panel, form)
    form:Check(L.MAIL_OPT_BAR, function() local o = mailOpts() return o and o.bar end, function(v)
        local o = mailOpts()
        if o then o.bar = v end
    end)
end)

-- banc d essai
AH._mail = { step = step, running = function() return run end, tick = tick }
