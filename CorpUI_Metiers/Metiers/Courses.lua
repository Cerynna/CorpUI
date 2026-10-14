--[[--------------------------------------------------------------------------
    CorpUI - module Metiers : liste de courses

    Composants consommes par toute la file (schemas des recettes,
    emplacements ordinaires seulement) : total, dont ce que la file fabrique
    elle-meme ; le reste vient de ce qu on a : sacs (ns.ItemCount) et
    banque (releve si ouverte, sinon GetItemCount avec la banque). Pour
    chaque manque : les autres persos qui en ont (sacs et banque notes par
    le module Persos, CorpUIDB.alts).

    Affichee dans l onglet "Courses" du volet des metiers, et seule dans une
    petite fenetre a l ouverture d un marchand, de la banque ou de l hotel
    des ventes (option), quand il faut aller chercher quelque chose. Rendu
    en tableau : en-tete de colonnes, sections (a acheter, en banque,
    disponible, repliable), pastille d etat par ligne.
      - banque : "Retirer ce qu il faut" deplace vers les sacs, une pile a
        la fois (UseContainerItem pour une pile entiere, sinon
        SplitContainerItem + PickupContainerItem sur une case libre d un
        sac qui accepte l objet : pas de carquois ni de sac d ames pour de
        l etoffe), arret si les sacs sont pleins ; chaque deplacement est
        compte d apres les sacs au pas suivant, pas d apres l appel ;
      - marchand : achat des manques qu il vend (ns.MerchantBuy, commun
        avec Reactifs), automatique en option ; jamais ce qui se paie en
        jetons, objets ou monnaie (Blizzard le fait confirmer) ;
      - hotel des ventes : loupe = le nom dans la barre de recherche de
        Blizzard, et C_AuctionHouse.SendBrowseQuery seulement si la liste
        des resultats est a l ecran (sinon le joueur clique Rechercher) ;
        aucun achat ;
      - cout HV estime de chaque ligne a acheter et leur total (echelle
        des prix du module Encheres, option ahProfit).
    Rien en combat.
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local C = ns.COLORS
local M = ns.Craft

local issecret = issecretvalue or function() return false end
local num, field, yes = M.num, M.field, M.yes

M.bankOpen, M.merchantOpen, M.ahOpen = false, false, false

local function visible(f)
    if type(f) ~= "table" or not f.IsVisible then return false end
    local ok, v = pcall(f.IsVisible, f)
    return ok and yes(v)
end

local function itemLabel(id)
    local name = ns.ItemName(id)
    if name then return name end
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return "item:" .. id
end

---------------------------------------------------------------------------
-- Calcul
---------------------------------------------------------------------------

-- autres persos qui ont cet objet : { { name, class, n } }, le plus fourni d abord
local function altsWith(id)
    local out = {}
    local alts = ns.root and ns.root.alts
    if type(alts) ~= "table" then return out end
    local me = ns.CharKey()
    for key, t in pairs(alts) do
        if key ~= me and type(t) == "table" and t.name then
            local n = (type(t.bags) == "table" and num(t.bags[id]) or 0)
                    + (type(t.bank) == "table" and num(t.bank[id]) or 0)
            if n > 0 then out[#out + 1] = { name = t.name, class = t.class, n = n } end
        end
    end
    table.sort(out, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return tostring(a.name) < tostring(b.name)
    end)
    return out
end
M.AltsWith = altsWith

-- ordre des etats : manque, chez un reroll, en banque, disponible
local RANK = { buy = 1, alt = 2, bank = 3, ok = 4 }

-- { { id, total, made, req, bags, bank, missing, pull, alts, altN, state,
--     cost, costLow, costN, costSeen, costEst } }
-- total = consomme par la file ; made = dont fabrique par elle ; req = le
-- reste, a tirer des sacs, de la banque ou a acheter. state : "buy"
-- (manque), "alt" (manque que les rerolls couvrent), "bank" (a prendre en
-- banque), "ok". Manques d abord. A acheter ("buy") avec un prix HV
-- (option ahProfit) : cost = cout des "missing" moins chers de l echelle
-- (au-dela de l echelle, au moins le prix de son dernier niveau), costLow
-- = c est une borne basse, costN = exemplaires couverts par l echelle,
-- costSeen = exemplaires en vente au dernier scan, costEst = scan sans
-- echelle (prix minimum x quantite).
function M.ShoppingList()
    local list = {}
    if not M.DB() then return list end
    local need, made = M.Totals()
    local priced = M.ProfitOn()
    for id, n in pairs(need) do
        local bags, bank = M.Have(id)
        local it = { id = id, total = n, made = math.min(n, made[id] or 0), bags = bags, bank = bank, altN = 0 }
        it.req = n - it.made
        it.missing = math.max(0, it.req - bags - bank)
        it.pull = math.max(0, math.min(bank, it.req - bags))
        if it.missing > 0 then
            it.alts = altsWith(id)
            for _, a in ipairs(it.alts) do it.altN = it.altN + a.n end
            it.state = (it.altN >= it.missing) and "alt" or "buy"
        else
            it.state = (it.pull > 0) and "bank" or "ok"
        end
        if priced and it.state == "buy" then
            local c, low = M.AHMarginal(id, 0, it.missing)
            local _, got, _, est = M.AHCost(id, it.missing)
            if c and got and got > 0 then
                it.cost, it.costLow, it.costN, it.costSeen, it.costEst = c, low, got, M.AHSeen(id), est
            end
        end
        list[#list + 1] = it
    end
    table.sort(list, function(a, b)
        if a.state ~= b.state then return RANK[a.state] < RANK[b.state] end
        local na, nb = ns.ItemName(a.id) or "", ns.ItemName(b.id) or ""
        if na ~= nb then return na < nb end
        return a.id < b.id
    end)
    return list
end

-- il faut aller chercher quelque chose (achat, banque, autre perso)
local function needsSomething(list)
    for _, it in ipairs(list) do
        if it.req > it.bags then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Banque : retirer ce qu il faut
---------------------------------------------------------------------------

local pulling

local function locked(bag, slot)
    if not (C_Container and C_Container.GetContainerItemInfo) then return false end
    local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
    if not ok or type(info) ~= "table" then return false end
    local v = info.isLocked
    if issecret(v) then return true end
    return v == true
end

-- famille d un sac : 0 ordinaire ; carquois, giberne, sac d ames, d herbes,
-- d enchanteur : un masque (GetContainerNumFreeSlots, 2e retour) ; nil si
-- illisible
local function bagFamily(bag)
    if not (C_Container and C_Container.GetContainerNumFreeSlots) then return 0 end
    local ok, _, fam = pcall(C_Container.GetContainerNumFreeSlots, bag)
    if not ok then return nil end
    if fam == nil then return 0 end
    return num(fam)
end

local band = bit and bit.band

local function itemFamily(id)
    local fn = (C_Item and C_Item.GetItemFamily) or GetItemFamily
    if not fn then return nil end
    local ok, v = pcall(fn, id)
    return ok and num(v) or nil
end

-- composant d artisanat (peut aller dans le sac de composants)
local function isReagent(id)
    local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not fn then return false end
    local ok, v = pcall(function() return select(17, fn(id)) end)
    return ok and yes(v)
end

-- sacs du joueur qui acceptent cet objet : les ordinaires et les speciaux
-- de sa famille, puis le sac de composants s il en est un
local function destBags(id)
    local list = {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local fam = bagFamily(bag)
        local it = fam and fam ~= 0 and band and itemFamily(id)
        if fam == 0 or (it and band(it, fam) ~= 0) then list[#list + 1] = bag end
    end
    local rb = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
    if rb and rb > (NUM_BAG_SLOTS or 4) and isReagent(id) then list[#list + 1] = rb end
    return list
end

-- case vide ou mettre cet objet
local function freeBagSlot(id, taken)
    for _, bag in ipairs(destBags(id)) do
        for slot = 1, ns.BagSlots(bag) do
            if not taken[bag .. ":" .. slot] and not ns.BagItem(bag, slot) then return bag, slot end
        end
    end
end

local function maxStack(id)
    local fn = C_Item and C_Item.GetItemMaxStackSizeByID
    if not fn then return nil end
    local ok, v = pcall(fn, id)
    return ok and num(v) or nil
end

-- piles entamees de cet objet dans les sacs : place totale, et une case
-- qui peut prendre "want" d un coup
local function stackRoom(id, want)
    local max = maxStack(id)
    if not max or max < 2 then return 0 end
    local room, fit, fitSlot = 0, nil, nil
    for _, bag in ipairs(destBags(id)) do
        for slot = 1, ns.BagSlots(bag) do
            local sid, n = ns.BagItem(bag, slot)
            n = num(n)
            if num(sid) == id and n and not locked(bag, slot) then
                local r = math.max(0, max - n)
                room = room + r
                if want and r >= want and not fit then fit, fitSlot = bag, slot end
            end
        end
    end
    return room, fit, fitSlot
end

local function cursorBusy()
    if not CursorHasItem then return false end
    local ok, v = pcall(CursorHasItem)
    return ok and yes(v)
end

local function finishPull(reason)
    local p = pulling
    pulling = nil
    if not p then return end
    local parts = {}
    for _, it in ipairs(p.items) do
        local n = p.moved[it.id]
        if n and n > 0 then parts[#parts + 1] = n .. " x " .. itemLabel(it.id) end
    end
    if #parts > 0 then ns.Say(string.format(L.SHOP_WITHDRAWN, table.concat(parts, ", "))) end
    if reason == "full" then ns.Say(L.SHOP_BAGS_FULL)
    elseif reason == "stop" then ns.Say(L.SHOP_PULL_STOPPED) end
    M.DirtyBank()
    C_Timer.After(0.6, M.Changed)
    M.Changed()
end

local function pullStep()
    local p = pulling
    if not p then return end
    if not M.bankOpen or InCombatLockdown() then return finishPull("stop") end
    -- le deplacement precedent compte d apres les sacs, pas d apres l appel
    local pd = p.pending
    if pd then
        local got = math.max(0, ns.ItemCount(pd.id) - pd.before)
        if got < pd.n and pd.tries < 8 and not cursorBusy() and (pd.tries < 1 or locked(pd.bag, pd.slot)) then
            -- le serveur n a pas encore suivi : on attend un peu
            pd.tries = pd.tries + 1
            C_Timer.After(0.25, pullStep)
            return
        end
        p.pending = nil
        got = math.min(got, pd.n)
        if got > 0 then p.moved[pd.id] = (p.moved[pd.id] or 0) + got end
        if got == 0 then
            -- refuse (plus de place, sac incompatible) : on repose et on arrete
            if cursorBusy() and ClearCursor then pcall(ClearCursor) end
            return finishPull(pd.whole and "full" or "stop")
        end
    end
    -- un objet reste sur le curseur : on le repose et on arrete
    if cursorBusy() then
        if ClearCursor then pcall(ClearCursor) end
        return finishPull("stop")
    end
    for _, it in ipairs(p.items) do
        local want = it.want - (p.moved[it.id] or 0)
        if want > 0 then
            for _, bag in ipairs(M.BankBags()) do
                for slot = 1, ns.BagSlots(bag) do
                    local key = bag .. ":" .. slot
                    local id, count = ns.BagItem(bag, slot)
                    id, count = num(id), num(count) or 1
                    if id == it.id and not p.used[key] and not locked(bag, slot) then
                        local nextMove = { id = id, before = ns.ItemCount(id), bag = bag, slot = slot, tries = 0 }
                        if count <= want then
                            -- pile entiere : le jeu la range lui-meme (piles
                            -- entamees comprises) ; il faut une case ou la place
                            if not freeBagSlot(id, p.dest) and stackRoom(id) < count then
                                return finishPull("full")
                            end
                            pcall(C_Container.UseContainerItem, bag, slot)
                            nextMove.n, nextMove.whole = count, true
                        else
                            -- partie d une pile : une case libre d un sac qui
                            -- l accepte, sinon une pile entamee qui la prend
                            local fb, fs = freeBagSlot(id, p.dest)
                            if not fb then
                                local _
                                _, fb, fs = stackRoom(id, want)
                            end
                            if not fb then return finishPull("full") end
                            pcall(C_Container.SplitContainerItem, bag, slot, want)
                            pcall(C_Container.PickupContainerItem, fb, fs)
                            p.dest[fb .. ":" .. fs] = true
                            nextMove.n = want
                        end
                        p.used[key] = true
                        p.pending = nextMove
                        C_Timer.After(0.35, pullStep)
                        return
                    end
                end
            end
        end
    end
    finishPull()
end

function M.Withdraw()
    if pulling or not M.bankOpen then return end
    if InCombatLockdown() then ns.Say(L.CRAFT_COMBAT) return end
    if not (C_Container and C_Container.UseContainerItem and C_Container.SplitContainerItem) then return end
    if cursorBusy() then return end
    M.DirtyBank()
    local items = {}
    for _, it in ipairs(M.ShoppingList()) do
        if it.pull > 0 then items[#items + 1] = { id = it.id, want = it.pull } end
    end
    if #items == 0 then ns.Say(L.SHOP_NOTHING_BANK) return end
    pulling = { items = items, moved = {}, used = {}, dest = {} }
    M.Changed()
    pullStep()
end

function M.Pulling() return pulling ~= nil end

---------------------------------------------------------------------------
-- Marchand et hotel des ventes
---------------------------------------------------------------------------

local lastBuy = 0
function M.BuyMissing(manual)
    if InCombatLockdown() or not M.merchantOpen then return end
    if GetTime() - lastBuy < 2 then return end      -- les sacs n ont pas encore suivi
    local want = {}
    for _, it in ipairs(M.ShoppingList()) do
        if it.missing > 0 then want[it.id] = it.missing end
    end
    if not next(want) then
        if manual then ns.Say(L.SHOP_NONE) end
        return
    end
    -- ns.MerchantBuy laisse ce que Blizzard ferait confirmer (jetons,
    -- objets, monnaie) et ce qui est epuise ou non achetable : on le dit
    local got, spent, skipped = ns.MerchantBuy(function(id) return want[id] end)
    local left = {}
    for _, id in ipairs(skipped or {}) do left[#left + 1] = itemLabel(id) end
    if #got == 0 then
        if #left > 0 then ns.Say(string.format(L.SHOP_SKIPPED, table.concat(left, ", ")))
        elseif manual then ns.Say(L.SHOP_NOT_SOLD) end
        return
    end
    lastBuy = GetTime()
    local parts = {}
    for _, g in ipairs(got) do parts[#parts + 1] = g.n .. " x " .. itemLabel(g.id) end
    ns.Say(string.format(L.SHOP_BOUGHT, table.concat(parts, ", "), ns.FormatMoney(spent)))
    if #left > 0 then ns.Say(string.format(L.SHOP_SKIPPED, table.concat(left, ", "))) end
    C_Timer.After(1, M.Changed)
end

function M.SearchAH(id)
    if InCombatLockdown() or not M.ahOpen then return end
    local name = ns.ItemName(id)
    if not name then return end
    local ahf = _G.AuctionHouseFrame
    local sbar = field(ahf, "SearchBar")
    if not visible(sbar) then ns.Say(L.SHOP_AH_BUY_TAB) return end
    local box = field(sbar, "SearchBox")
    if type(box) == "table" and box.SetText then pcall(box.SetText, box, name) end
    -- la barre de recherche est aussi la sur la fiche d un objet (modes
    -- CommoditiesBuy, ItemBuy), ou la liste des resultats est cachee ; une
    -- requete directe ne change pas le mode d affichage de Blizzard (rien a
    -- l ecran). Dans ce cas, le nom est dans le champ et le bouton
    -- Rechercher de Blizzard fait le reste par son propre chemin.
    if not visible(field(ahf, "BrowseResultsFrame")) then
        ns.Say(string.format(L.SHOP_AH_TYPED, name))
        return
    end
    local ah = C_AuctionHouse
    if not (ah and ah.SendBrowseQuery) then return end
    if ah.IsThrottledMessageSystemReady then
        local ok, ready = pcall(ah.IsThrottledMessageSystemReady)
        if ok and not issecret(ready) and ready == false then ns.Say(L.SHOP_AH_BUSY) return end
    end
    local E = Enum and Enum.AuctionHouseSortOrder
    local query = {
        searchString = name,
        sorts = { { sortOrder = (E and E.Price) or 0, reverseSort = false },
                  { sortOrder = (E and E.Name) or 1, reverseSort = false } },
        filters = {}, itemClassFilters = {},
    }
    pcall(ah.SendBrowseQuery, query)
end

---------------------------------------------------------------------------
-- Vue de la liste (volet des metiers et fenetre a part)
---------------------------------------------------------------------------

-- Mise en page (largeur utile : 248 dans le volet, 278 dans la fenetre).
-- En-tete de colonnes fixe ; sections (bandeau degrade de l accent, filet
-- d or) ; lignes de 34 (comme la file) sur deux etages :
--   [icone] nom sur une ligne ("..." et infobulle)        [pastille]
--           dont N fabriques             Il faut   Sacs   Banque
-- Trois colonnes de chiffres de 36, alignees a droite, fixes (en-tete
-- compris). La loupe HV (HV ouvert, lignes en manque) se pose en haut a
-- droite : seule la pastille de sa ligne se decale. Une gouttiere de 4 a
-- droite porte le curseur de defilement.
local ROW_H, SEC_H, HEAD_H, COL_W, ICON, GUTTER = 34, 20, 16, 36, 26, 4
local RP, FIND = 2, 14          -- marge de droite, cote de la loupe
local TEXT_X = ICON + 10        -- debut des textes, apres l icone et son liseré

local SECTIONS = {
    { key = "buy", label = "SHOP_SEC_BUY" },
    { key = "bank", label = "SHOP_SEC_BANK" },
    { key = "ok", label = "SHOP_SEC_OK", fold = true },
}

-- couleur d un etat (pastille, resume)
local function tone(state)
    if state == "buy" then return 1, 0.38, 0.38 end
    if state == "alt" then return 0.42, 0.68, 1 end
    if state == "bank" then return C.gold[1], C.gold[2], C.gold[3] end
    return 0.42, 0.88, 0.46
end

local function hex(r, g, b)
    return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- cout HV d une ligne a acheter : "~1po 42pa", "+" si c est une borne
-- basse (pas assez en vente ou echelle trop courte, scan sans echelle)
local function costText(it)
    return "~" .. (ns.AHMoney or ns.FormatMoney)(it.cost) .. (it.costLow and "+" or "")
end

local function pillText(it)
    if it.state == "buy" then return string.format(L.SHOP_MISSING, it.missing) end
    if it.state == "alt" then return L.SHOP_ALT end
    if it.state == "bank" then return string.format(L.SHOP_IN_BANK, it.pull) end
    return L.SHOP_OK
end

-- qualite d un objet (nil si inconnue)
local function quality(id)
    local fn = C_Item and C_Item.GetItemQualityByID
    if fn then
        local ok, q = pcall(fn, id)
        q = ok and num(q)
        if q then return q end
    end
    local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if info then
        local ok, q = pcall(function() return select(3, info(id)) end)
        return ok and num(q) or nil
    end
end

-- couleur de qualite a partir de "peu commun" (en dessous : liseré du theme)
local function qualityRGB(q)
    if not q or q < 2 then return nil end
    local c = field(ITEM_QUALITY_COLORS, q)
    local r, g, b = num(field(c, "r")), num(field(c, "g")), num(field(c, "b"))
    if r and g and b then return r, g, b end
    local fn = (C_Item and C_Item.GetItemQualityColor) or GetItemQualityColor
    if fn then
        local ok, r2, g2, b2 = pcall(fn, q)
        if ok and num(r2) and num(g2) and num(b2) then return r2, g2, b2 end
    end
end

-- texte secondaire en 9 (on garde la police choisie)
local function smaller(fs)
    local ok, file = pcall(fs.GetFont, fs)
    if ok and type(file) == "string" then pcall(fs.SetFont, fs, file, 9, "") end
end

local function rowTooltip(row)
    local it = row.item
    if not it then return end
    local t = ns.Tooltip(row, "ANCHOR_LEFT")
    if not pcall(t.SetItemByID, t, it.id) then t:SetText(itemLabel(it.id)) end
    t:AddLine(" ")
    t:AddDoubleLine(L.SHOP_REQ_LABEL, it.total, 1, 1, 1, 1, 1, 1)
    if it.made > 0 then t:AddDoubleLine(L.SHOP_MADE_LABEL, it.made, 0.7, 0.7, 0.75, 0.7, 0.7, 0.75) end
    t:AddDoubleLine(L.SHOP_BAGS_LABEL, it.bags, 1, 1, 1, 1, 1, 1)
    t:AddDoubleLine(L.SHOP_BANK_LABEL, it.bank, 1, 1, 1, 1, 1, 1)
    local r, g, b = tone(it.state)
    t:AddLine(pillText(it), r, g, b)
    if it.cost then
        t:AddDoubleLine(L.SHOP_COST_LABEL, costText(it), 1, 1, 1, C.gold[1], C.gold[2], C.gold[3])
        -- pas assez en vente, ou assez mais echelle gardee plus courte
        if it.costSeen and it.costSeen < it.missing then
            t:AddLine(string.format(L.SHOP_COST_SHORT, it.costSeen, it.missing), 0.6, 0.6, 0.6, true)
        elseif it.costN < it.missing then
            t:AddLine(string.format(L.SHOP_COST_CAP, it.costN), 0.6, 0.6, 0.6, true)
        end
        if it.costEst then t:AddLine(L.SHOP_COST_OLD, 0.6, 0.6, 0.6, true) end
    end
    if it.alts and #it.alts > 0 then
        t:AddLine(" ")
        t:AddLine(L.SHOP_ALT_TIP, C.gold[1], C.gold[2], C.gold[3])
        for _, a in ipairs(it.alts) do
            local h = ns.ClassHex and ns.ClassHex(a.class or "PRIEST") or "|cffffffff"
            t:AddDoubleLine(h .. tostring(a.name) .. "|r", a.n, 1, 1, 1, 1, 1, 1)
        end
    end
    t:Show()
end

-- bord droit de la colonne c (1 a 3), compte depuis la droite de la ligne
local function colRight(c) return RP + (3 - c) * COL_W end

-- pastille : en haut a droite, ou a gauche de la loupe HV (seulement quand
-- la loupe change)
local function placePill(row, find)
    if row.findOn == find then return end
    row.findOn = find
    row.state:ClearAllPoints()
    row.state:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(RP + (find and FIND + 2 or 0)), -3)
end

local function makeRow(v, i)
    local row = CreateFrame("Button", nil, v.list)
    row:SetHeight(ROW_H - 2)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    ns.UI.Gradient(hl, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.22, C.violet[1], C.violet[2], C.violet[3], 0.02)
    -- icone carree sur son liseré (qualite, sinon theme)
    row.edge = row:CreateTexture(nil, "BORDER")
    row.edge:SetSize(ICON + 2, ICON + 2)
    row.edge:SetPoint("LEFT", 3, 0)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON, ICON)
    row.icon:SetPoint("CENTER", row.edge, "CENTER")
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- pastille d etat : fond teinte sous le texte
    row.state = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.state:SetJustifyH("CENTER")
    row.state:SetWordWrap(false)
    row.pill = row:CreateTexture(nil, "ARTWORK")
    row.pill:SetPoint("TOPLEFT", row.state, "TOPLEFT")
    row.pill:SetPoint("BOTTOMRIGHT", row.state, "BOTTOMRIGHT")
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.cols = {}
    for c = 1, 3 do
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetJustifyH("RIGHT")
        fs:SetWordWrap(false)
        row.cols[c] = fs
    end
    -- ligne secondaire : fabriques par la file, sinon rerolls
    row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    smaller(row.sub)
    row.sub:SetJustifyH("LEFT")
    row.sub:SetWordWrap(false)
    -- loupe HV, en haut a droite (a la hauteur de la pastille)
    row.find = ns.UI.Button(row, "", FIND, function(self)
        local it = self:GetParent().item
        if it then M.SearchAH(it.id) end
    end)
    row.find:SetSize(FIND, FIND)
    row.find:SetPoint("TOPRIGHT", row, "TOPRIGHT", -RP, -3)
    local glass = row.find:CreateTexture(nil, "ARTWORK")
    glass:SetSize(10, 10)
    glass:SetPoint("CENTER")
    glass:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    glass:SetVertexColor(C.gold[1], C.gold[2], C.gold[3])
    row.find:HookScript("OnEnter", function(self)
        local t = ns.Tooltip(self, "ANCHOR_TOP")
        t:SetText(L.SHOP_SEARCH_AH)
        t:Show()
    end)
    row.find:HookScript("OnLeave", ns.HideTooltip)
    row.find:Hide()
    -- colonnes, nom (jusqu a la pastille), ligne secondaire (jusqu aux
    -- colonnes) : ancrages fixes
    for c, fs in ipairs(row.cols) do
        fs:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -colRight(c), 4)
        fs:SetSize(COL_W - 4, 12)
    end
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", TEXT_X, -4)
    row.name:SetPoint("RIGHT", row.state, "LEFT", -6, 0)
    row.name:SetHeight(14)
    row.sub:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", TEXT_X, 4)
    row.sub:SetPoint("RIGHT", row.cols[1], "LEFT", -4, 0)
    row.sub:SetHeight(12)
    row:SetScript("OnEnter", rowTooltip)
    row:SetScript("OnLeave", ns.HideTooltip)
    placePill(row, false)
    v.rows[i] = row
    return row
end

local function fillRow(row, it, odd)
    row.item = it
    row.bg:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], odd and 0.65 or 0.3)
    row.icon:SetTexture(ns.ItemIcon(it.id))
    local qr, qg, qb = qualityRGB(quality(it.id))
    if qr then
        row.edge:SetColorTexture(qr, qg, qb, 1)
        row.name:SetTextColor(qr, qg, qb)
    else
        row.edge:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
        row.name:SetTextColor(1, 1, 1)
    end
    row.name:SetText(itemLabel(it.id))
    -- chiffres : zero en gris, banque utile en or
    local vals = { it.total, it.bags, it.bank }
    for c, fs in ipairs(row.cols) do
        fs:SetText(tostring(vals[c]))
        if vals[c] == 0 then fs:SetTextColor(0.45, 0.45, 0.5)
        else fs:SetTextColor(C.text[1], C.text[2], C.text[3]) end
    end
    if it.pull > 0 then row.cols[3]:SetTextColor(C.gold[1], C.gold[2], C.gold[3]) end
    local sub = ""
    if it.made > 0 then
        sub = string.format(L.SHOP_MADE, it.made)
    elseif it.alts and #it.alts > 0 then
        local names = {}
        for i, a in ipairs(it.alts) do
            if i > 2 then break end
            local h = ns.ClassHex and ns.ClassHex(a.class or "PRIEST") or "|cffffffff"
            names[#names + 1] = h .. tostring(a.name) .. "|r " .. a.n
        end
        sub = string.format(L.SHOP_ALTS, table.concat(names, ", "))
    end
    -- a acheter : cout HV en tete de la ligne secondaire
    if it.cost then
        local c = "|cffffd100" .. costText(it) .. "|r"
        sub = (sub == "") and c or (c .. "  " .. sub)
    end
    row.sub:SetText(sub)
    local find = (M.ahOpen and it.missing > 0) and true or false
    row.find:SetShown(find)
    placePill(row, find)
    local r, g, b = tone(it.state)
    row.state:SetText(pillText(it))
    row.state:SetTextColor(r, g, b)
    row.pill:SetColorTexture(r, g, b, 0.18)
    -- mesure sans borne : la ligne reutilisee garde la largeur de sa
    -- pastille precedente
    local w = math.ceil((M.TextWidth(row.state) or 40) + 12)
    row.state:SetSize(math.max(30, math.min(84, w)), 14)
    row:Show()
end

local function makeSection(v, i)
    local s = CreateFrame("Button", nil, v.list)
    s:SetHeight(SEC_H - 2)
    local bg = s:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    ns.UI.Gradient(bg, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.35, C.violet[1], C.violet[2], C.violet[3], 0.05)
    local line = s:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    ns.NoSnap(line)
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    ns.UI.Gradient(line, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.7, C.gold[1], C.gold[2], C.gold[3], 0)
    s.fold = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.fold:SetPoint("RIGHT", -6, 0)
    s.fold:SetSize(12, 14)
    s.fold:SetJustifyH("CENTER")
    s.fold:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    s.title = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    s.title:SetPoint("LEFT", 6, 0)
    s.title:SetPoint("RIGHT", s.fold, "LEFT", -4, 0)
    s.title:SetHeight(14)
    s.title:SetJustifyH("LEFT")
    s.title:SetWordWrap(false)
    s.title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    -- section "Disponible" : clic pour replier / deplier (commun aux vues)
    s:SetScript("OnClick", function(self)
        if not self.foldable then return end
        local db = M.DB()
        db.shopFoldOK = not db.shopFoldOK
        M.Changed()
    end)
    s:SetScript("OnEnter", function(self)
        if not self.foldable then return end
        local t = ns.Tooltip(self, "ANCHOR_TOP")
        t:SetText(L.SHOP_FOLD_TIP)
        t:Show()
    end)
    s:SetScript("OnLeave", ns.HideTooltip)
    v.secs[i] = s
    return s
end

local function fillSection(s, e)
    s.foldable = e.sec.fold or false
    s.key = e.sec.key
    s.title:SetText(L[e.sec.label] .. "  |cff8f8f9f(" .. e.n .. ")|r")
    s.fold:SetText(e.closed and "+" or "-")
    s.fold:SetShown(s.foldable)
end

-- liste a plat : { sec = , n = , closed = } puis { item = , odd = }
local function buildEntries(list, folded)
    local groups = { buy = {}, bank = {}, ok = {} }
    for _, it in ipairs(list) do
        local g = groups[it.state == "alt" and "buy" or it.state]
        g[#g + 1] = it
    end
    local out = {}
    for _, s in ipairs(SECTIONS) do
        local g = groups[s.key]
        if #g > 0 then
            local closed = (s.fold and folded) and true or false
            out[#out + 1] = { sec = s, n = #g, closed = closed }
            if not closed then
                for k, it in ipairs(g) do out[#out + 1] = { item = it, odd = (k % 2 == 1) } end
            end
        end
    end
    return out
end

-- en-tete de colonnes, aligne sur les chiffres des lignes
local function placeHead(v)
    local h = v.head
    for c, fs in ipairs(h.cols) do
        fs:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -colRight(c), 3)
        fs:SetSize(COL_W - 2, 12)
    end
    h.item:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", TEXT_X, 3)
    h.item:SetPoint("RIGHT", h.cols[1], "LEFT", -4, 0)
    h.item:SetHeight(12)
end

-- pied : resume au-dessus des boutons (montres chez le banquier ou le
-- marchand ; seul, un bouton prend toute la largeur)
local function placeFoot(v)
    local p, b = M.bankOpen and true or false, M.merchantOpen and true or false
    v.pull:SetShown(p)
    v.buy:SetShown(b)
    local key = (p and 1 or 0) + (b and 2 or 0)
    if v.footKey == key then return end
    v.footKey = key
    v.pull:ClearAllPoints()
    v.buy:ClearAllPoints()
    if p then
        v.pull:SetPoint("BOTTOMLEFT")
        v.pull:SetPoint("BOTTOMRIGHT", v.frame, b and "BOTTOM" or "BOTTOMRIGHT", b and -2 or 0, 0)
    end
    if b then
        v.buy:SetPoint("BOTTOMRIGHT")
        v.buy:SetPoint("BOTTOMLEFT", v.frame, p and "BOTTOM" or "BOTTOMLEFT", p and 2 or 0, 0)
    end
    local foot = (p or b) and 26 or 0
    v.summary:ClearAllPoints()
    v.summary:SetPoint("BOTTOMLEFT", v.frame, "BOTTOMLEFT", 2, foot)
    v.summary:SetPoint("BOTTOMRIGHT", v.frame, "BOTTOMRIGHT", -2, foot)
    v.footLine:ClearAllPoints()
    v.footLine:SetPoint("BOTTOMLEFT", v.frame, "BOTTOMLEFT", 0, foot + 19)
    v.footLine:SetPoint("BOTTOMRIGHT", v.frame, "BOTTOMRIGHT", 0, foot + 19)
    v.list:ClearAllPoints()
    v.list:SetPoint("TOPLEFT", v.frame, "TOPLEFT", 0, -HEAD_H - 2)
    v.list:SetPoint("BOTTOMRIGHT", v.frame, "BOTTOMRIGHT", 0, foot + 23)
end

function M.BuildShopView(parent)
    local v = { rows = {}, secs = {}, offset = 0 }
    local f = CreateFrame("Frame", nil, parent)
    v.frame = f

    -- en-tete de colonnes (fixe, discret)
    v.head = CreateFrame("Frame", nil, f)
    v.head:SetPoint("TOPLEFT")
    v.head:SetPoint("TOPRIGHT", -GUTTER, 0)
    v.head:SetHeight(HEAD_H)
    local function label(text, justify)
        local fs = v.head:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        smaller(fs)
        fs:SetJustifyH(justify)
        fs:SetWordWrap(false)
        fs:SetText(text)
        return fs
    end
    v.head.item = label(L.SHOP_COL_ITEM, "LEFT")
    v.head.cols = { label(L.SHOP_COL_NEED, "RIGHT"), label(L.SHOP_COL_BAGS, "RIGHT"), label(L.SHOP_COL_BANK, "RIGHT") }
    placeHead(v)
    local hline = v.head:CreateTexture(nil, "ARTWORK")
    hline:SetHeight(1)
    ns.NoSnap(hline)
    hline:SetPoint("BOTTOMLEFT")
    hline:SetPoint("BOTTOMRIGHT")
    hline:SetColorTexture(C.border[1], C.border[2], C.border[3], 0.8)

    -- liste (placee par placeFoot) et curseur de defilement dans la gouttiere
    v.list = CreateFrame("Frame", nil, f)
    v.thumb = v.list:CreateTexture(nil, "ARTWORK")
    v.thumb:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.6)
    v.thumb:Hide()
    v.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    v.empty:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -8)
    v.empty:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -8)
    v.empty:SetHeight(28)
    v.empty:SetJustifyH("LEFT")
    v.empty:SetJustifyV("TOP")

    -- pied
    v.footLine = f:CreateTexture(nil, "ARTWORK")
    v.footLine:SetHeight(1)
    ns.NoSnap(v.footLine)
    v.footLine:SetColorTexture(C.border[1], C.border[2], C.border[3], 0.8)
    v.summary = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    v.summary:SetHeight(16)
    v.summary:SetJustifyH("LEFT")
    v.summary:SetWordWrap(false)
    v.pull = ns.UI.Button(f, L.SHOP_WITHDRAW, 120, function() M.Withdraw() end)
    v.buy = ns.UI.Button(f, L.SHOP_BUY, 80, function() M.BuyMissing(true) end)

    function v.Refresh()
        local db = M.DB()
        if not db then return end
        -- en combat : ni construction ni placement, on reprend a la sortie
        if InCombatLockdown() then M.shopStale = true return end
        local list = M.ShoppingList()
        placeFoot(v)

        -- resume (une couleur par etat) et boutons ; la part banque compte
        -- les objets que Retirer prendra (pull > 0), a acheter compris
        -- total HV de ce qui est a acheter : "+" si une ligne n a pas de
        -- prix ou n a qu une borne basse
        local n = { buy = 0, alt = 0, bank = 0 }
        local spend, low, priced = 0, false, false
        for _, it in ipairs(list) do
            if it.state == "buy" or it.state == "alt" then n[it.state] = n[it.state] + 1 end
            if it.pull > 0 then n.bank = n.bank + 1 end
            if it.state == "buy" then
                if it.cost then
                    spend, priced = spend + it.cost, true
                    if it.costLow then low = true end
                else
                    low = true
                end
            end
        end
        local parts = {}
        for _, k in ipairs({ "buy", "alt", "bank" }) do
            if n[k] > 0 then
                local text
                if k == "buy" and priced then
                    text = string.format(L.SHOP_SUM_BUY_COST, n.buy, (ns.AHMoney or ns.FormatMoney)(spend) .. (low and "+" or ""))
                else
                    text = string.format(L["SHOP_SUM_" .. k:upper()], n[k])
                end
                parts[#parts + 1] = hex(tone(k)) .. text .. "|r"
            end
        end
        if #list == 0 then v.summary:SetText("")
        elseif #parts == 0 then v.summary:SetText(hex(tone("ok")) .. L.SHOP_NONE .. "|r")
        else v.summary:SetText(table.concat(parts, "  ·  ")) end
        v.pull:SetEnabled(n.bank > 0 and not M.Pulling())
        v.buy:SetEnabled(n.buy + n.alt > 0)
        v.head:SetShown(#list > 0)
        v.empty:SetText(#M.Queue() == 0 and L.CRAFT_EMPTY or L.SHOP_NONE)
        v.empty:SetShown(#list == 0)

        -- entrees visibles a partir de v.offset (une section ou un objet)
        local entries = buildEntries(list, db.shopFoldOK)
        local h = v.list:GetHeight() or 0
        local function hOf(e) return e.sec and SEC_H or ROW_H end
        local maxOff, acc = math.max(0, #entries - 1), 0
        for i = #entries, 1, -1 do
            acc = acc + hOf(entries[i])
            if acc > h then break end
            maxOff = i - 1
        end
        v.offset = math.max(0, math.min(v.offset, maxOff))
        local y, nr, nsec, last = 0, 0, 0, v.offset
        for i = v.offset + 1, #entries do
            local e = entries[i]
            local eh = hOf(e)
            if y + eh > h then break end
            local fr
            if e.sec then
                nsec = nsec + 1
                fr = v.secs[nsec] or makeSection(v, nsec)
                fillSection(fr, e)
            else
                nr = nr + 1
                fr = v.rows[nr] or makeRow(v, nr)
                fillRow(fr, e.item, e.odd)
            end
            fr:ClearAllPoints()
            fr:SetPoint("TOPLEFT", v.list, "TOPLEFT", 0, -y)
            fr:SetPoint("TOPRIGHT", v.list, "TOPRIGHT", -GUTTER, -y)
            fr:Show()
            y = y + eh
            last = i
        end
        for i = nr + 1, #v.rows do
            v.rows[i]:Hide()
            v.rows[i].item = nil
        end
        for i = nsec + 1, #v.secs do v.secs[i]:Hide() end
        -- curseur : seulement si tout ne tient pas
        if maxOff > 0 then
            local th = math.max(12, h * (last - v.offset) / #entries)
            v.thumb:ClearAllPoints()
            v.thumb:SetPoint("TOPRIGHT", v.list, "TOPRIGHT", -1, -(h - th) * v.offset / maxOff)
            v.thumb:SetSize(2, th)
            v.thumb:Show()
        else
            v.thumb:Hide()
        end
        v.maxOffset = maxOff
    end

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, d)
        v.offset = math.max(0, v.offset - d)
        v.Refresh()
    end)
    v.list:SetScript("OnSizeChanged", function() if f:IsVisible() then v.Refresh() end end)
    f:SetScript("OnShow", function() v.Refresh() end)
    table.insert(M.listeners, function() if f:IsVisible() then v.Refresh() end end)
    return v
end

---------------------------------------------------------------------------
-- Fenetre a part (marchand, banque, hotel des ventes)
---------------------------------------------------------------------------

local win
local autoShown = false

local function buildWindow()
    local db = M.DB()
    win = CreateFrame("Frame", "CorpUIShopping", UIParent)
    win:SetSize(290, 400)
    win:SetFrameStrata("HIGH")
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) self:StartMoving() end)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        ns.PinTop(self, db.shopWin, true)
    end)
    ns.UI.Skin(win, 0.95, true)
    local title = win:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(title, 13)
    title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    title:SetPoint("TOPLEFT", 8, -9)
    title:SetText(L.SHOP_TITLE)
    local line = win:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    ns.NoSnap(line)
    line:SetPoint("TOPLEFT", 6, -28)
    line:SetPoint("TOPRIGHT", -6, -28)
    ns.UI.Gradient(line, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.8, C.violet[1], C.violet[2], C.violet[3], 0)
    local close = ns.UI.Button(win, "×", 20, function() win:Hide() end)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -5, -5)
    win.view = M.BuildShopView(win)
    win.view.frame:SetPoint("TOPLEFT", 6, -34)
    win.view.frame:SetPoint("BOTTOMRIGHT", -6, 6)
    if db.shopWin.x then
        ns.ApplyPos(win, db.shopWin)
    else
        win:SetPoint("TOPLEFT", UIParent, "CENTER", 120, 200)
    end
    win:Hide()
end

local function shown(f)
    if type(f) ~= "table" or not f.IsVisible then return false end
    local ok, v = pcall(f.IsVisible, f)
    return ok and v == true
end

-- place par defaut (jamais deplacee) : contre la fenetre ouverte, a droite
-- (hotel des ventes, ou son volet CorpUI s il est ouvert ; marchand,
-- banque CorpUI ou de Blizzard)
local function placeAuto()
    local db = M.DB()
    if db.shopWin.x then return end
    local ahHost = shown(_G.CorpUIAuctionSide) and _G.CorpUIAuctionSide or _G.AuctionHouseFrame
    local host = (M.ahOpen and ahHost) or (M.merchantOpen and _G.MerchantFrame)
        or (M.bankOpen and ((shown(_G.CorpUIBank) and _G.CorpUIBank) or _G.BankFrame))
    if not shown(host) then return end
    win:ClearAllPoints()
    win:SetPoint("TOPLEFT", host, "TOPRIGHT", 8, 0)
end

-- a l ouverture d un marchand, de la banque, de l hotel des ventes ; pas si
-- la fenetre des metiers est ouverte (son volet montre deja les courses)
local function autoShow()
    local db = M.DB()
    if not db or not db.shopWindow or InCombatLockdown() then return end
    if not (M.merchantOpen or M.bankOpen or M.ahOpen) then return end
    if shown(_G.ProfessionsFrame) then return end
    if not needsSomething(M.ShoppingList()) then return end
    if not win then buildWindow() end
    if not win:IsShown() then
        autoShown = true
        placeAuto()
        win:Show()
    end
    win.view.Refresh()
end

-- la fenetre des metiers s ouvre : la fenetre ouverte d office se range
function M.ProfOpened()
    if win and autoShown and win:IsShown() then
        autoShown = false
        win:Hide()
    end
end

local function autoHide()
    if win and autoShown and not (M.merchantOpen or M.bankOpen or M.ahOpen) then
        autoShown = false
        win:Hide()
    end
end

function M.ToggleShopping()
    if not M.DB() then return end
    -- en combat : fermer oui ; ni construire ni ouvrir (la vue n y est
    -- pas remplie)
    if InCombatLockdown() and not (win and win:IsShown()) then ns.Say(L.CRAFT_COMBAT) return end
    if not win then buildWindow() end
    autoShown = false
    win:SetShown(not win:IsShown())
end

---------------------------------------------------------------------------
-- Reglages (/corp metiers)
---------------------------------------------------------------------------

local panel, countText
local DEPTH_W = 280             -- liste de la profondeur (texte : 252)

local function refreshPanel()
    if countText then countText:SetText(string.format(L.CRAFT_COUNT, #M.Queue())) end
end
table.insert(M.listeners, function() if panel and panel:IsVisible() then refreshPanel() end end)

local function buildPanel()
    local db = M.DB()
    panel = ns.UI.Window("CorpUICrafting", ns.TITLE .. " - " .. L.MOD_CRAFT, {}, 440, 260)
    local form = ns.UI.Form(panel, -34, function() M.Changed() end)
    local depth = form:Cycle(L.CRAFT_OPT_DEPTH, { "none", "one", "all" },
        { none = L.CRAFT_DEPTH_NONE, one = L.CRAFT_DEPTH_ONE, all = L.CRAFT_DEPTH_ALL },
        function() return db.subDepth end, function(v) db.subDepth = v end)
    -- liste plus large que les 200 du formulaire : "Un niveau (composants
    -- directs)" tient en entier dans toutes les langues
    depth:SetSize(DEPTH_W, 22)
    form:Check(L.CRAFT_OPT_BUY, function() return db.autoBuy end, function(v) db.autoBuy = v end)
    form:Check(L.CRAFT_OPT_WIN, function() return db.shopWindow end, function(v) db.shopWindow = v end)
    form:Check(L.CRAFT_OPT_PANE, function() return db.showPane end, function(v)
        db.showPane = v
        if v then db.pane.collapsed = false end
    end)
    -- benefice HV dans la file : seulement si le module Encheres est la
    if type(ns.AHPrice) == "function" then
        form:Check(L.CRAFT_OPT_AH, function() return db.ahProfit end, function(v) db.ahProfit = v end)
    end
    -- acheter ou fabriquer selon l echelle des prix (module Encheres)
    if type(ns.AHCost) == "function" then
        form:Check(L.CRAFT_OPT_CHOICE, function() return db.ahChoice end, function(v) db.ahChoice = v end)
    end
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, form.y - 6)
    hint:SetWidth(420)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.CRAFT_HINT)
    local y = form.y - 12 - math.max(28, hint:GetStringHeight() or 28)
    countText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countText:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, y)
    local shop = ns.UI.Button(panel, L.CRAFT_SHOW_SHOP, 150, function() M.ToggleShopping() end)
    shop:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, y - 18)
    local clear = ns.UI.Button(panel, L.CRAFT_CLEAR, 80, function(self)
        if self.armed then
            self.armed = nil
            self:SetText(L.CRAFT_CLEAR)
            M.Clear()
            ns.Say(L.CRAFT_CLEARED)
        else
            self.armed = true
            self:SetText(L.CRAFT_SURE)
            C_Timer.After(3, function()
                if self.armed then self.armed = nil self:SetText(L.CRAFT_CLEAR) end
            end)
        end
    end)
    clear:SetPoint("LEFT", shop, "RIGHT", 6, 0)
    panel:SetHeight(-(y - 18) + 34)
    panel:HookScript("OnShow", function()
        form:Refresh()
        refreshPanel()
    end)
end

local function toggle()
    if not M.DB() then return end
    if not panel then buildPanel() end
    ns.ShowPanel(panel)
end

local function slash(input)
    local cmd = strlower(strtrim(input or ""))
    if not M.DB() then return end
    if cmd == "courses" or cmd == "shop" or cmd == "shopping" then
        M.ToggleShopping()
    elseif cmd == "vider" or cmd == "clear" then
        M.Clear()
        ns.Say(L.CRAFT_CLEARED)
    elseif cmd == "file" or cmd == "queue" or cmd == "list" then
        local q = M.Queue()
        if #q == 0 then ns.Say(L.CRAFT_EMPTY) return end
        ns.Say(string.format(L.CRAFT_COUNT, #q))
        for i, e in ipairs(q) do
            ns.Chat(string.format("  %d. %d x %s  |cff8f8f9f%s|r", i, e.n, M.RecipeName(e.id), e.prof or ""))
        end
    else
        toggle()
    end
end

ns.RegisterModule({
    command = "metiers",
    panelName = "CorpUICrafting",
    icon = "Interface\\Icons\\Trade_Engineering",
    title = function() return L.MOD_CRAFT end,
    desc = function() return L.CRAFT_DESC end,
    Slash = slash,
    Open = toggle,
})

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

local namesPending = false
local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if ns.ModuleOff("metiers", ev) then return end
    if event == "PLAYER_LOGIN" then
        M.Init()
        return
    end
    if not M.DB() then return end
    if event == "MERCHANT_SHOW" then
        M.merchantOpen = true
        -- la liste du marchand peut arriver juste apres l ouverture
        C_Timer.After(0.3, function()
            if M.DB().autoBuy then
                local ok, err = pcall(M.BuyMissing, false)
                if not ok then ns.Say("|cffff4040" .. tostring(err) .. "|r") end
            end
        end)
        C_Timer.After(1.2, autoShow)
        M.Changed()
    elseif event == "MERCHANT_CLOSED" then
        M.merchantOpen = false
        autoHide()
        M.Changed()
    elseif event == "BANKFRAME_OPENED" then
        M.bankOpen = true
        M.DirtyBank()
        C_Timer.After(0.3, autoShow)
        M.Changed()
    elseif event == "BANKFRAME_CLOSED" then
        M.bankOpen = false
        if pulling then finishPull("stop") end
        autoHide()
        M.Changed()
    elseif event == "AUCTION_HOUSE_SHOW" then
        M.ahOpen = true
        C_Timer.After(0.3, autoShow)
        M.Changed()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        M.ahOpen = false
        autoHide()
        M.Changed()
    elseif event == "PLAYER_REGEN_DISABLED" then
        if pulling then finishPull("stop") end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- une vue a ete laissee telle quelle pendant le combat
        if M.shopStale then
            M.shopStale = nil
            M.Changed()
        end
    elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYERBANKSLOTS_CHANGED" then
        M.DirtyBank()
        if win and win:IsShown() then M.Changed() end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- noms arrives : fenetre a part ou onglet Courses du volet
        local paneShop = M.shopView and M.shopView.frame:IsVisible()
        if namesPending or not ((win and win:IsShown()) or paneShop) then return end
        namesPending = true
        C_Timer.After(0.5, function()
            namesPending = false
            M.Changed()
        end)
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "MERCHANT_SHOW", "MERCHANT_CLOSED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
                     "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "BAG_UPDATE_DELAYED",
                     "PLAYERBANKSLOTS_CHANGED", "GET_ITEM_INFO_RECEIVED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
