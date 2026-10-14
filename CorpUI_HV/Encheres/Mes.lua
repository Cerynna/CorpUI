--[[--------------------------------------------------------------------------
    CorpUI - module Encheres : onglet "Mes encheres" du volet

    Tes ventes en cours (C_AuctionHouse.GetOwnedAuctions, relu a chaque
    OWNED_AUCTIONS_UPDATED ; liste demandee au serveur a l ouverture de
    l onglet si elle date), groupees par objet et par prix, avec leur etat :
      - sous-cotee : quelqu un vend moins cher (de combien, par qui) ;
      - la moins chere / seule en vente ;
      - vendue (l argent arrive par courrier) ;
      - sans verification : la base de prix (scan) dit peut-etre.
    "Verifier" lance une recherche par objet (C_AuctionHouse.SendSearchQuery,
    une a la fois, au rythme que le serveur accepte) et lit les resultats
    sans nos propres annonces. Annuler reste dans l onglet Encheres de
    Blizzard (ce client l interdit aux addons) : les lignes a annuler sont
    en tete, en rouge.
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local C = ns.COLORS
local AH = ns.AH

local num, call = AH.num, AH.call

local PAD = 8
local ROW_H = 34
local CHECK_TTL = 15 * 60     -- une verification vaut 15 min
local QUERY_GAP = 0.4         -- entre deux recherches
local QUERY_WAIT = 6          -- reponse attendue au plus 6 s

local owned = {}              -- encheres lues (une par annonce)
local ownedAt                 -- derniere lecture
local queriedAt               -- derniere demande au serveur
local checks = {}             -- itemID -> { low, owner, count, at }
local queue, running = {}, nil
local dirty = true

---------------------------------------------------------------------------
-- Lecture
---------------------------------------------------------------------------

local function sorts()
    local E = Enum and Enum.AuctionHouseSortOrder
    return { { sortOrder = (E and E.Name) or 1, reverseSort = false }, { sortOrder = (E and E.Price) or 0, reverseSort = false } }
end

local function readOwned()
    local ah = AH.api()
    if not ah then return end
    local n = num(call(ah.GetNumOwnedAuctions)) or 0
    local list = {}
    for i = 1, n do
        local a = call(ah.GetOwnedAuctionInfo, i)
        if type(a) == "table" then
            local key = a.itemKey
            local id = type(key) == "table" and num(key.itemID)
            local q = num(a.quantity) or 1
            local price = num(a.buyoutAmount) or num(a.bidAmount)
            if id and price then
                list[#list + 1] = { id = id, key = key, link = AH.str(a.itemLink), qty = q, price = price,
                                    sold = num(a.status) == 1, left = num(a.timeLeftSeconds), band = num(a.timeLeft),
                                    bid = num(a.bidAmount) and not num(a.buyoutAmount) }
            end
        end
    end
    owned = list
    ownedAt = GetTime()
    dirty = true
end

local function query()
    local ah = AH.api()
    if not (ah and ah.QueryOwnedAuctions) or InCombatLockdown() then return end
    queriedAt = GetTime()
    pcall(ah.QueryOwnedAuctions, sorts())
end

---------------------------------------------------------------------------
-- Verification : une recherche par objet, l une apres l autre
---------------------------------------------------------------------------

local function finishOne(id, live)
    if live then checks[id] = { low = live.low, owner = live.owner, count = live.count, at = time() } end
    running = nil
    dirty = true
end

local function nextQuery()
    if running or #queue == 0 then return end
    local ah = AH.api()
    if not (ah and ah.SendSearchQuery) or InCombatLockdown() or not (ns.AHFrame and ns.AHFrame()) then
        wipe(queue)
        return
    end
    if ah.IsThrottledMessageSystemReady and call(ah.IsThrottledMessageSystemReady) == false then return end
    local job = table.remove(queue, 1)
    running = { id = job.id, key = job.key, commodity = job.commodity, at = GetTime() }
    local ok = pcall(ah.SendSearchQuery, job.key, sorts(), true)
    if not ok then finishOne(job.id, nil) end
    dirty = true
end

-- resultats d une recherche : la notre ?
if ns.AHResultsListen then
    ns.AHResultsListen(function(kind, id, key)
        if not running or kind == "browse" or id ~= running.id then return end
        local live
        if kind == "commodity" then live = AH.LiveCommodity and AH.LiveCommodity(id)
        else live = AH.LiveItems and AH.LiveItems(key or running.key) end
        if live then finishOne(id, live) end
    end)
end

local total = 0
local function startCheck()
    if running or #queue > 0 then return end
    local seen = {}
    for _, a in ipairs(owned) do
        if not a.sold and not seen[a.id] then
            seen[a.id] = true
            local key = a.key
            local ok, commodity = pcall(function()
                local info = C_AuctionHouse.GetItemKeyInfo(key)
                return info and info.isCommodity
            end)
            queue[#queue + 1] = { id = a.id, key = key, commodity = ok and commodity == true }
        end
    end
    total = #queue
    dirty = true
    nextQuery()
end

local lastQuery
local function stepQueue()
    if running and GetTime() - running.at > QUERY_WAIT then
        -- reponse jamais venue (ou deja la : on lit ce qu il y a)
        local live
        if running.commodity then live = AH.LiveCommodity and AH.LiveCommodity(running.id)
        else live = AH.LiveItems and AH.LiveItems(running.key) end
        finishOne(running.id, live)
    end
    if not running and #queue > 0 and (not lastQuery or GetTime() - lastQuery >= QUERY_GAP) then
        lastQuery = GetTime()
        nextQuery()
    end
end

---------------------------------------------------------------------------
-- Etat de chaque groupe (objet, prix)
---------------------------------------------------------------------------

local RANK = { under = 1, maybe = 2, unknown = 3, best = 4, alone = 5, sold = 6 }

local function statusOf(g)
    if g.sold then return "sold" end
    local c = checks[g.id]
    if c and time() - c.at < CHECK_TTL then
        if not c.low then return "alone" end
        if g.price <= c.low then return "best" end
        return "under", c
    end
    local v = ns.AHValues and ns.AHValues(g.id)
    if v and v.min < g.price - 0.005 then return "maybe", v end
    return "unknown"
end

local function groups()
    local by, out = {}, {}
    for _, a in ipairs(owned) do
        local k = a.id .. ":" .. math.floor(a.price) .. ":" .. (a.sold and 1 or 0)
        local g = by[k]
        if not g then
            g = { id = a.id, key = a.key, link = a.link, price = a.price, qty = 0, n = 0, sold = a.sold, left = a.left, band = a.band }
            by[k] = g
            out[#out + 1] = g
        end
        g.qty, g.n = g.qty + a.qty, g.n + 1
        if a.left and (not g.left or a.left < g.left) then g.left = a.left end
        if a.band and (not g.band or a.band < g.band) then g.band = a.band end
    end
    for _, g in ipairs(out) do g.status, g.info = statusOf(g) end
    table.sort(out, function(a, b)
        if RANK[a.status] ~= RANK[b.status] then return RANK[a.status] < RANK[b.status] end
        local na, nb = ns.ItemName(a.id) or "", ns.ItemName(b.id) or ""
        if na ~= nb then return na < nb end
        return a.price < b.price
    end)
    return out
end
AH.MineGroups = groups

---------------------------------------------------------------------------
-- Onglet
---------------------------------------------------------------------------

local ui = {}

local function leftText(g)
    if g.left then
        if g.left >= 3600 then return string.format(L.MINE_LEFT_H, math.floor(g.left / 3600)) end
        return string.format(L.MINE_LEFT_M, math.max(1, math.floor(g.left / 60)))
    end
    local bands = { [0] = L.MINE_BAND_0, [1] = L.MINE_BAND_1, [2] = L.MINE_BAND_2, [3] = L.MINE_BAND_3 }
    return g.band and bands[g.band] or ""
end

local function statusLine(g)
    local M = AH.Money
    local s = g.status
    if s == "under" then
        local who = g.info and g.info.owner
        local by = g.price - g.info.low
        return "|cffff6060" .. string.format(L.MINE_UNDER, M(by)) .. (who and (" (" .. who .. ")") or "") .. "|r"
    elseif s == "maybe" then
        return "|cffffa040" .. string.format(L.MINE_MAYBE, M(g.info.min)) .. "|r"
    elseif s == "best" then
        return "|cff6be070" .. L.MINE_BEST .. "|r"
    elseif s == "alone" then
        return "|cff6be070" .. L.MINE_ALONE .. "|r"
    elseif s == "sold" then
        return "|cffffd100" .. L.MINE_SOLD .. "|r"
    end
    return "|cff9d9d9d" .. L.MINE_UNKNOWN .. "|r"
end

local function makeRow(list, i)
    local row = AH.ItemRow(list, ROW_H)
    row:SetScript("OnClick", function(self, button)
        if self.g and button == "LeftButton" then AH.Search(self.g.id) end
    end)
    row:SetScript("OnEnter", function(self)
        local g = self.g
        if not g then return end
        local extra = { { statusLine(g) }, { L.MINE_TIP_CLICK, 0.7, 0.7, 0.7 } }
        if not g.sold and g.status ~= "best" and g.status ~= "alone" then extra[#extra + 1] = { L.MINE_TIP_CANCEL, 0.7, 0.7, 0.7 } end
        AH.ItemTip(self, g.id, extra)
    end)
    return row
end

local function fillRow(row, g, i)
    row.g = g
    row.stripe:SetShown(i % 2 == 0)
    row.icon:SetTexture(ns.ItemIcon(g.id))
    row.name:SetText(AH.QualityHex(g.id) .. AH.ItemLabel(g.id) .. "|r" .. (g.qty > 1 and ("|cffffffff x" .. g.qty .. "|r") or ""))
    row.right:SetText(AH.Money(g.price))
    local tl = leftText(g)
    row.sub:SetText(statusLine(g) .. (tl ~= "" and ("|cff9d9d9d  ·  " .. tl .. "|r") or ""))
end

local function build(page)
    ui.page = page
    ui.summary = AH.Text(page, "GameFontHighlightSmall", "LEFT")
    ui.summary:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, -6)
    ui.summary:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
    ui.check = ns.UI.Button(page, L.MINE_CHECK, 110, function() startCheck() end)
    ui.check:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, -24)
    ui.check:HookScript("OnEnter", function(self)
        local t = ns.Tooltip(self, "ANCHOR_TOP")
        t:AddLine(L.MINE_CHECK)
        t:AddLine(L.MINE_CHECK_TIP, 1, 1, 1, true)
        t:Show()
    end)
    ui.check:HookScript("OnLeave", function() ns.HideTooltip() end)
    ui.reload = ns.UI.Button(page, L.MINE_RELOAD, 90, function() query() end)
    ui.reload:SetPoint("LEFT", ui.check, "RIGHT", 6, 0)
    ui.progress = AH.Text(page, "GameFontDisableSmall", "LEFT")
    ui.progress:SetPoint("LEFT", ui.reload, "RIGHT", 8, 0)
    ui.progress:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
    ui.list = AH.List(page, ROW_H, makeRow, fillRow)
    ui.list:SetPoint("TOPLEFT", page, "TOPLEFT", PAD - 2, -52)
    ui.list:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -PAD + 2, 44)
    ui.empty = AH.Text(page, "GameFontDisableSmall", "LEFT")
    ui.empty:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, -60)
    ui.empty:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
    ui.empty:SetWordWrap(true)
    ui.hint = AH.Text(page, "GameFontDisableSmall", "LEFT")
    ui.hint:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", PAD, 6)
    ui.hint:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
    ui.hint:SetHeight(34)
    ui.hint:SetWordWrap(true)
    ui.hint:SetJustifyV("BOTTOM")
    ui.hint:SetText(L.MINE_HINT)
end

local lastPaint = 0
local function refresh(page)
    if not ui.page then return end
    local now = GetTime()
    if not dirty and now - lastPaint < 2 then return end
    dirty, lastPaint = false, now
    local gs = groups()
    local nUnder, value, nActive, nSold = 0, 0, 0, 0
    for _, g in ipairs(gs) do
        if g.sold then
            nSold = nSold + g.qty
        else
            nActive = nActive + g.n
            value = value + g.price * g.qty
            if g.status == "under" then nUnder = nUnder + 1 end
        end
    end
    ui.summary:SetText(string.format(L.MINE_SUMMARY, nActive, nUnder, AH.Money(value)) .. (nSold > 0 and ("  ·  " .. string.format(L.MINE_SUMMARY_SOLD, nSold)) or ""))
    ui.list:SetData(gs)
    ui.empty:SetText((#gs == 0) and (ownedAt and L.MINE_NONE or L.MINE_LOADING) or "")
    ui.empty:SetShown(#gs == 0)
    if running or #queue > 0 then
        ui.progress:SetText(string.format(L.MINE_CHECKING, total - #queue, total))
        ui.check:SetEnabled(false)
    else
        ui.progress:SetText("")
        ui.check:SetEnabled(#gs > 0)
    end
end

local function show()
    dirty = true
    if not queriedAt or GetTime() - queriedAt > 30 then query() end
    readOwned()
end

AH.AddTab({ key = "mine", order = 2, label = function() return L.AHP_TAB_MINE end, build = build, refresh = refresh, show = show })

-- evenements : liste de Blizzard a jour, encheres creees ou annulees
local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if ns.ModuleOff("hv", ev) then return end
    if event == "OWNED_AUCTIONS_UPDATED" then
        readOwned()
        AH.Refresh("mine")
    elseif event == "AUCTION_HOUSE_CLOSED" then
        wipe(queue)
        running = nil
    elseif AH.Current() == "mine" then
        -- vente creee ou annulee : la liste de Blizzard ne se recharge
        -- que si son onglet est ouvert ; on la redemande
        C_Timer.After(1, function() if AH.Current() == "mine" then query() end end)
    end
end)
for _, e in ipairs({ "OWNED_AUCTIONS_UPDATED", "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_AUCTION_CREATED", "AUCTION_CANCELED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
-- file des verifications : avance meme si l onglet n est plus affiche
local acc = 0
ev:SetScript("OnUpdate", function(_, dt)
    if not running and #queue == 0 then return end
    acc = acc + dt
    if acc < 0.1 then return end
    acc = 0
    stepQueue()
    if not running and #queue == 0 then AH.Refresh("mine") end
end)

-- banc d essai
AH._mine = { read = readOwned, check = startCheck, step = function() stepQueue() end, checks = checks, queue = queue,
             running = function() return running end }
