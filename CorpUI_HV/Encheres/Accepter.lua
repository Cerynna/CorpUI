--[[--------------------------------------------------------------------------
    CorpUI - module Encheres : "Accepter" pose sur "Achat immediat"

    Option (active par defaut) : quand la confirmation d achat immediat d un
    objet s ouvre (fenetre de Blizzard StaticPopup "BUYOUT_AUCTION"), elle
    est placee de facon que son bouton Accepter tombe exactement sur le
    bouton "Achat immediat" de la fiche de l objet. On clique deux fois au
    meme endroit : Achat immediat, puis Accepter. Le prix reste affiche
    dans la fenetre, au-dessus du bouton.
    Rien n est clique a la place du joueur : chaque achat demande ses deux
    clics sur les boutons de Blizzard (ce client interdit aux addons
    d acheter, et CorpUI n y touche pas).
    Lecture seule de StaticPopup1..4 (.which, ButtonContainer.Button1) et
    du bouton de Blizzard ; seule ecriture : la position de la fenetre
    (ClearAllPoints / SetPoint), que Blizzard refait a chaque ouverture
    d une fenetre. Aucun crochet, aucun champ ecrit.
    Plus bas : acheter une marchandise malgre une hausse du devis (la
    fenetre de Blizzard refuse au-dela de 5 %).
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local AH = ns.AH

local issecret = issecretvalue or function() return false end
local num, field = AH.num, AH.field

local function buyOpts()
    local db = AH.DB()
    if not db then return nil end
    if type(db.buy) ~= "table" then db.buy = {} end
    if db.buy.atButton == nil then db.buy.atButton = true end
    return db.buy
end

-- bouton "Achat immediat" de la fiche d un objet (s il est a l ecran)
local function buyoutButton()
    local ahf = ns.AHFrame and ns.AHFrame()
    local btn = field(field(field(ahf, "ItemBuyFrame"), "BuyoutFrame"), "BuyoutButton")
    if AH.visible(btn) then return btn end
end

local function center(f)
    local ok, x, y = pcall(f.GetCenter, f)
    x, y = ok and num(x), ok and num(y)
    local okS, s = pcall(f.GetEffectiveScale, f)
    s = okS and num(s)
    if x and y and s and s > 0 then return x * s, y * s, s end
end

-- place la fenetre : son bouton Accepter au centre du bouton Achat immediat
local function place(dlg, btn)
    local b1 = field(field(dlg, "ButtonContainer"), "Button1")
    if type(b1) ~= "table" then return false end
    local dx, dy, ds = center(dlg)
    local ax, ay = center(b1)
    if not (dx and ax) then return false end
    -- ecart (en pixels d ecran) ramene a l echelle de la fenetre
    local ox, oy = (dx - ax) / ds, (dy - ay) / ds
    local ok = pcall(function()
        dlg:ClearAllPoints()
        dlg:SetPoint("CENTER", btn, "CENTER", ox, oy)
    end)
    return ok
end

-- deja posee sur le bouton ?
local function anchoredTo(dlg, btn)
    local ok, _, rel = pcall(dlg.GetPoint, dlg, 1)
    return ok and rel == btn
end

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function()
    local o = buyOpts()
    if not (o and o.atButton) then return end
    -- la confirmation d achat n existe qu a l hotel des ventes
    if not AH.visible(_G.AuctionHouseFrame) then return end
    local btn
    for i = 1, 4 do
        local dlg = _G["StaticPopup" .. i]
        if AH.visible(dlg) then
            local which = field(dlg, "which")
            if not issecret(which) and which == "BUYOUT_AUCTION" then
                btn = btn or buyoutButton()
                if btn and not anchoredTo(dlg, btn) then place(dlg, btn) end
            end
        end
    end
end)

-- case dans le panneau /corp hv
ns.AHPanelHooks = ns.AHPanelHooks or {}
table.insert(ns.AHPanelHooks, function(panel, form)
    form:Header(L.ACC_SEC)
    form:Check(L.ACC_OPT, function() local o = buyOpts() return o and o.atButton end, function(v)
        local o = buyOpts()
        if o then o.atButton = v end
    end)
end)

---------------------------------------------------------------------------
-- Marchandise : acheter malgre une hausse du devis
--   La fenetre d achat des marchandises de Blizzard (AuctionHouseFrame.
--   BuyDialog) compare le devis du serveur (COMMODITY_PRICE_UPDATED) au
--   prix affiche au clic « Acheter » : plus de 5 % au-dessus, elle dit
--   « Cet objet n est plus disponible », alors que le serveur propose bien
--   la quantite, au nouveau prix, et la garde le temps du devis
--   (GetQuoteDurationRemaining). Quand les petits lots les moins chers
--   partent en une seconde, chaque achat echoue ainsi.
--   Option (active par defaut) : dans ce cas, un cadre sous la fenetre de
--   Blizzard montre le devis (prix unitaire, hausse, secondes restantes)
--   et un bouton « Acheter quand meme : N pour X » qui confirme CE devis
--   (ConfirmCommoditiesPurchase, non restreinte ; la demande de devis,
--   StartCommoditiesPurchase, l est et reste au bouton de Blizzard). OK de
--   Blizzard : devis annule, le cadre part. Jamais d achat sans clic, rien
--   en combat. Lecture seule de la fenetre (itemID, quantity,
--   unitPricePreview, boutons), aucun crochet.
---------------------------------------------------------------------------

local function quoteOpts()
    local o = buyOpts()
    if o and o.forceQuote == nil then o.forceQuote = true end
    return o
end

local quote                     -- { item, qty, unit, total, preview } : dernier devis
local pending                   -- devis confirme par notre bouton, en attente
local holder                    -- notre cadre sous la fenetre de Blizzard

local function buyDialog()
    return field(_G.AuctionHouseFrame, "BuyDialog")
end

-- etat « prix indisponible » de Blizzard : le bouton OK seul
local function refused(dlg)
    return AH.visible(dlg) and AH.visible(field(dlg, "OkayButton")) and not AH.visible(field(dlg, "BuyNowButton"))
end

local function quoteLeft()
    local ah = AH.api()
    return ah and num(AH.call(ah.GetQuoteDurationRemaining))
end

local function hideHolder()
    if holder then holder:Hide() end
end

local function dropQuote()
    quote = nil
    hideHolder()
end

local function confirmQuote()
    local q = quote
    if not q or pending or InCombatLockdown() then return end
    local left = quoteLeft()
    if left and left <= 0 then dropQuote() return end
    local money = num(GetMoney())
    if money and q.total > money then ns.Say(L.QUOTE_MONEY) return end
    local ah = AH.api()
    if not (ah and type(ah.ConfirmCommoditiesPurchase) == "function") then return end
    pending = q
    pending.at = GetTime()
    holder.buy:Disable()
    holder.buy:SetText(L.QUOTE_WAIT)
    local ok, err = pcall(ah.ConfirmCommoditiesPurchase, q.item, q.qty)
    if not ok then
        pending = nil
        holder.buy:Enable()
        ns.Say(string.format(L.QUOTE_FAILED, tostring(err)))
    end
end

local function buildHolder()
    local C = ns.COLORS
    holder = CreateFrame("Frame", "CorpUIQuoteBuy", UIParent, "BackdropTemplate")
    holder:SetSize(340, 62)
    holder:SetFrameStrata("FULLSCREEN_DIALOG")
    holder:SetClampedToScreen(true)
    ns.UI.SetBackdrop(holder, 0.97)
    holder:Hide()
    holder.info = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    holder.info:SetPoint("TOP", 0, -8)
    holder.info:SetWidth(324)
    holder.buy = ns.UI.Button(holder, "", 324, confirmQuote)
    holder.buy:SetSize(324, 26)
    holder.buy:SetPoint("BOTTOM", 0, 8)
    holder.buy.cuiText:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
end

local function paintHolder(left)
    local q = quote
    local pct = (q.preview and q.preview > 0) and math.floor((q.unit - q.preview) / q.preview * 100 + 0.5) or nil
    local rise = pct and string.format("%s+%d %%|r", pct >= 25 and "|cffff4040" or "|cffffa040", pct) or ""
    holder.info:SetText(string.format(L.QUOTE_INFO, AH.Money(q.unit), rise, math.max(0, math.floor(left or 0))))
    if not pending then
        holder.buy:SetText(string.format(L.QUOTE_BUY, q.qty, AH.Money(q.total)))
        local money = num(GetMoney())
        holder.buy:SetEnabled(not (money and q.total > money))
    end
end

-- tant qu un devis existe : le cadre suit l etat de la fenetre de Blizzard
local watch = CreateFrame("Frame")
local acc = 0
local function onWatch(_, dt)
    acc = acc + dt
    if acc < 0.1 then return end
    acc = 0
    local o = quoteOpts()
    local dlg = buyDialog()
    local left = quoteLeft()
    if not quote or not (o and o.forceQuote) or not refused(dlg) or (left and left <= 0) then
        -- achat en cours : Blizzard repasse en attente, on patiente
        if pending and GetTime() - pending.at < 3 then return end
        pending = nil
        hideHolder()
        if not quote or not AH.visible(dlg) or (left and left <= 0) then
            quote = nil
            watch:SetScript("OnUpdate", nil)
        end
        return
    end
    if not holder then buildHolder() end
    if not holder:IsShown() then
        holder:ClearAllPoints()
        holder:SetPoint("TOP", dlg, "BOTTOM", 0, -6)
        holder:Show()
    end
    paintHolder(left)
end

watch:SetScript("OnEvent", function(_, event, a, b)
    if ns.ModuleOff("hv", watch) then return end
    if event == "COMMODITY_PRICE_UPDATED" then
        local dlg = buyDialog()
        local unit, total = num(a), num(b)
        local item, qty = num(field(dlg, "itemID")), num(field(dlg, "quantity"))
        if not (unit and total and item and qty and qty > 0) then dropQuote() return end
        quote = { item = item, qty = qty, unit = unit, total = total, preview = num(field(dlg, "unitPricePreview")) }
        pending = nil
        acc = 1
        watch:SetScript("OnUpdate", onWatch)
    elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
        if pending then
            ns.Say(string.format(L.QUOTE_BOUGHT, pending.qty, AH.ItemLabel(pending.item), AH.Money(pending.total)))
        end
        pending = nil
        dropQuote()
    elseif event == "COMMODITY_PURCHASE_FAILED" then
        if pending then ns.Say(L.QUOTE_GONE) end
        pending = nil
        dropQuote()
    elseif event == "COMMODITY_PRICE_UNAVAILABLE" or event == "AUCTION_HOUSE_CLOSED" then
        pending = nil
        dropQuote()
    elseif (event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN") and pending then
        -- le jeu refuse la confirmation venant d un addon (pas une autre action)
        local what = AH.str(b)
        if what and not what:find("Commodit", 1, true) then return end
        pending = nil
        dropQuote()
        ns.Say(L.QUOTE_BLOCKED)
    end
end)
for _, e in ipairs({ "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE", "COMMODITY_PURCHASE_SUCCEEDED",
                     "COMMODITY_PURCHASE_FAILED", "AUCTION_HOUSE_CLOSED", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
    pcall(watch.RegisterEvent, watch, e)
end

table.insert(ns.AHPanelHooks, function(panel, form)
    form:Check(L.QUOTE_OPT, function() local o = quoteOpts() return o and o.forceQuote end, function(v)
        local o = quoteOpts()
        if o then o.forceQuote = v end
    end)
end)

-- banc d essai
AH._accept = { place = place, button = buyoutButton, confirm = confirmQuote, watch = onWatch,
               quote = function() return quote end, holder = function() return holder end }
