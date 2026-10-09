--[[--------------------------------------------------------------------------
    CorpUI - module Persos
    Vue d ensemble de tous les personnages du compte.

    Chaque personnage connecte enregistre son etat dans CorpUIDB.alts :
    niveau, XP, or, zone, metiers, contenu des sacs et de la banque (la
    banque seulement quand elle est ouverte), raids verrouilles.
    La fenetre liste les personnages ; la recherche trouve un objet sur
    tous les personnages (sacs et banque).

    Lecture seule : aucun cadre de Blizzard n est touche.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

-- Panneau seul de sa page : largeur et hauteur de la fenetre principale
local W        = 452
local H        = 496
local LIST_TOP = 112       -- haut de la liste (sous recherche et bandeau)
local CARD_H   = 48        -- carte de personnage repliee
local RES_H    = 38        -- ligne de resultat de recherche
local GAP      = 4
local CW       = W - 22    -- largeur des cartes (place pour l ascenseur)
local W8       = "Interface\\Buttons\\WHITE8X8"

-- En-tetes des metiers dans la liste des competences, toutes langues
-- (repli si le client n a pas GetProfessions)
local PROF_HEADERS = {
    ["Professions"] = true, ["Secondary Skills"] = true,
    ["Métiers"] = true, ["Compétences secondaires"] = true,
    ["Berufe"] = true, ["Sekundäre Fertigkeiten"] = true,
    ["Profesiones"] = true, ["Habilidades secundarias"] = true,
    ["Profissões"] = true, ["Habilidades Secundárias"] = true,
    ["Professioni"] = true, ["Abilità secondarie"] = true,
    ["Профессии"] = true, ["Вторичные навыки"] = true,
    ["专业"] = true, ["辅助技能"] = true, ["專業"] = true, ["輔助技能"] = true,
    ["전문 기술"] = true, ["보조 기술"] = true,
}

local db           -- CorpUIDB.alts : cle "Nom-Royaume" -> donnees
local names        -- CorpUIDB.itemNames : itemID -> nom (cache pour la recherche)
local bankOpen = false

---------------------------------------------------------------------------
-- Collecte
---------------------------------------------------------------------------

local function current()
    local key = ns.CharKey()
    db[key] = db[key] or {}
    return db[key], key
end

-- Valeur secrete (client en combat) : on garde l ancienne, pour ne jamais
-- ecrire "nil --[[ secret value ]]" dans la sauvegarde
local issecret = issecretvalue or function() return false end
local function plain(v, old)
    if v == nil or issecret(v) then return old end
    return v
end

local function snapBasics()
    local t = current()
    local name = UnitName("player")
    local _, class = UnitClass("player")
    t.name = plain(name, t.name)
    t.realm = plain(GetRealmName and GetRealmName(), t.realm) or "?"
    t.class = plain(class, t.class)
    t.level = plain(UnitLevel("player"), t.level)
    t.race = plain(UnitRace and UnitRace("player"), t.race)
    t.faction = plain(UnitFactionGroup and UnitFactionGroup("player"), t.faction)
    t.money = plain(GetMoney and GetMoney(), t.money) or 0
    t.xp = plain(UnitXP and UnitXP("player"), t.xp) or 0
    t.xpMax = plain(UnitXPMax and UnitXPMax("player"), t.xpMax) or 0
    t.rested = plain(GetXPExhaustion and GetXPExhaustion(), nil) or 0
    t.zone = plain((GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()), t.zone) or ""
    t.lastSeen = time()
end

local function scanContainers(bags)
    local items = {}
    for _, bag in ipairs(bags) do
        for slot = 1, ns.BagSlots(bag) do
            local id, count, link = ns.BagItem(bag, slot)
            if id then
                items[id] = (items[id] or 0) + (count or 1)
                local n = ns.LinkName(link)
                if n then names[id] = n end
            end
        end
    end
    return items
end

local function bagList()
    return ns.PlayerBags()
end

-- conteneurs de la banque : onglets achetes (C_Bank ; conteneurs 6 a 14 sur
-- ce client), sinon les numeros fixes des onglets, sinon l ancienne banque
-- (-1 et ses sacs ; ici -1 est le trousseau de cles, pas la banque)
local function bankList()
    local bt = Enum and Enum.BankType and Enum.BankType.Character
    if C_Bank and C_Bank.FetchPurchasedBankTabIDs and bt ~= nil then
        local ok, ids = pcall(C_Bank.FetchPurchasedBankTabIDs, bt)
        if ok and not issecret(ids) and type(ids) == "table" then
            local list = {}
            for _, id in ipairs(ids) do
                if not issecret(id) and type(id) == "number" then list[#list + 1] = id end
            end
            if #list > 0 then return list end
        end
    end
    local E = Enum and Enum.BagIndex
    if E and E.CharacterBankTab_1 then
        local list = {}
        for i = 1, 12 do
            local id = E["CharacterBankTab_" .. i]
            if not id then break end
            list[#list + 1] = id
        end
        return list
    end
    local first = ns.FirstBankBag()
    local list = { BANK_CONTAINER or -1 }
    for bag = first, first + (NUM_BANKBAGSLOTS or 6) - 1 do table.insert(list, bag) end
    return list
end

local function snapBags()
    local t = current()
    t.bags = scanContainers(bagList())
end

local function snapBank()
    if not bankOpen then return end
    local t = current()
    t.bank = scanContainers(bankList())
    t.bankSeen = time()
end

local function snapProfs()
    local t = current()
    local profs = {}
    if GetProfessions and GetProfessionInfo then
        local ok = pcall(function()
            for _, idx in ipairs({ GetProfessions() }) do
                if idx then
                    local name, _, rank, maxRank = GetProfessionInfo(idx)
                    if name then table.insert(profs, { name = name, rank = rank, max = maxRank }) end
                end
            end
        end)
        if ok and #profs > 0 then t.profs = profs return end
        profs = {}
    end
    if GetNumSkillLines and GetSkillLineInfo then
        pcall(function()
            local inProf = false
            for i = 1, GetNumSkillLines() do
                local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
                if isHeader then
                    inProf = PROF_HEADERS[name] or false
                elseif inProf and name then
                    table.insert(profs, { name = name, rank = rank, max = maxRank })
                end
            end
        end)
    end
    t.profs = profs
end

local function snapLocks()
    local t = current()
    local locks = {}
    if GetNumSavedInstances and GetSavedInstanceInfo then
        pcall(function()
            for i = 1, GetNumSavedInstances() do
                local name, _, reset, _, locked = GetSavedInstanceInfo(i)
                if name and locked and reset and reset > 0 then
                    table.insert(locks, { name = name, expires = time() + reset })
                end
            end
        end)
    end
    t.locks = locks
end

---------------------------------------------------------------------------
-- Fenetre : recherche, tri, bandeau des totaux, cartes de personnages
---------------------------------------------------------------------------

local C = ns.COLORS
local VIEW_H = H - LIST_TOP - 24    -- hauteur visible de la liste
local LINE_H = 13
local win, search, list, child, track, thumb, sortSel
local banner = {}
local cards, results = {}, {}
local expanded = {}                 -- cle -> detail deplie (le temps de la session)
local confirmKey, confirmAt         -- "Oublier" en attente de confirmation
local scrollY, scrollMax = 0, 0
local refresh

-- Reglages d affichage : CorpUIDB.altsView (a cote de altsWin). CorpUIDB.alts
-- ne contient que des personnages (le module Infos le parcourt aussi).
local SORTS = { "level", "money", "name", "seen" }
local SORT_TEXT = { level = "ALTS_SORT_LEVEL", money = "ALTS_SORT_MONEY", name = "ALTS_SORT_NAME", seen = "ALTS_SORT_SEEN" }

local function view()
    local root = ns.root or {}
    if type(root.altsView) ~= "table" then root.altsView = {} end
    local v = root.altsView
    if not SORT_TEXT[v.sort or ""] then v.sort = "level" end
    return v
end

-- Nombre sur : 0 si absent ou secret
local function num(v)
    if v == nil or issecret(v) then return 0 end
    return tonumber(v) or 0
end

local function maxLevel()
    if GetMaxPlayerLevel then
        local ok, v = pcall(GetMaxPlayerLevel)
        if ok and type(v) == "number" and not issecret(v) and v > 0 then return v end
    end
    return 60
end

-- Or au format commun de CorpUI : 12po 34pa 56pc, pieces nulles omises
local function group(n)
    if BreakUpLargeNumbers then
        local ok, s = pcall(BreakUpLargeNumbers, n)
        if ok and type(s) == "string" and not issecret(s) then return s end
    end
    return tostring(n)
end
local function coins(copper)
    copper = math.max(0, math.floor(num(copper)))
    local G, S, Cu = ns.MoneySymbols()
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = group(g) .. G end
    if s > 0 then parts[#parts + 1] = s .. S end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. Cu end
    return table.concat(parts, " ")
end

local function hex(c)
    return string.format("%02x%02x%02x", math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end

-- objets d une table itemID -> quantite : total, sortes
local function tally(items)
    local n, k = 0, 0
    if type(items) == "table" then
        for _, count in pairs(items) do
            n = n + num(count)
            k = k + 1
        end
    end
    return n, k
end

local function sortedChars()
    local out = {}
    local me = ns.CharKey()
    for key, t in pairs(db) do
        if type(t) == "table" and t.name then table.insert(out, { key = key, t = t, me = key == me }) end
    end
    local mode = view().sort
    table.sort(out, function(a, b)
        local x, y = a.t, b.t
        if mode == "money" then
            if num(x.money) ~= num(y.money) then return num(x.money) > num(y.money) end
        elseif mode == "name" then
            local nx, ny = strlower(tostring(x.name)), strlower(tostring(y.name))
            if nx ~= ny then return nx < ny end
        elseif mode == "seen" then
            -- le personnage connecte d abord, puis le plus recent
            if a.me ~= b.me then return a.me end
            if num(x.lastSeen) ~= num(y.lastSeen) then return num(x.lastSeen) > num(y.lastSeen) end
        else
            if num(x.level) ~= num(y.level) then return num(x.level) > num(y.level) end
            if a.me ~= b.me then return a.me end
        end
        return a.key < b.key
    end)
    return out
end

-- Recherche d objet : resultats { id, name, total, parts = { "Nom x3 (sacs)" } }
local function searchItems(query)
    local out = {}
    query = strlower(query)
    local chars = sortedChars()
    for id, name in pairs(names) do
        if strlower(name):find(query, 1, true) then
            local r = { id = id, name = name, total = 0, parts = {} }
            for _, c in ipairs(chars) do
                local b = c.t.bags and num(c.t.bags[id]) or 0
                local k = c.t.bank and num(c.t.bank[id]) or 0
                if b + k > 0 then
                    r.total = r.total + b + k
                    local detail = {}
                    if b > 0 then table.insert(detail, string.format(L.ALTS_BAGS, b)) end
                    if k > 0 then table.insert(detail, string.format(L.ALTS_BANK, k)) end
                    table.insert(r.parts, ns.ClassHex(c.t.class or "PRIEST") .. c.t.name .. "|r " ..
                        table.concat(detail, ", "))
                end
            end
            if r.total > 0 then table.insert(out, r) end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

---------------------------------------------------------------------------
-- Infobulles
---------------------------------------------------------------------------

local function charTooltip(card)
    local c = card.char
    if not c then return end
    local t = ns.Tooltip(card)
    local d = c.t
    t:AddLine(ns.ClassHex(d.class or "PRIEST") .. d.name .. "|r - " .. (d.realm or ""))
    t:AddLine(string.format("%s %d %s", L.ALTS_LEVEL, num(d.level), d.race or ""), 1, 1, 1)
    if num(d.xpMax) > 0 and num(d.level) < maxLevel() then
        local pct = math.floor(num(d.xp) / num(d.xpMax) * 100)
        local rested = math.floor(num(d.rested) / num(d.xpMax) * 100)
        t:AddLine(string.format(L.ALTS_XP, pct, rested), C.violet[1], C.violet[2], C.violet[3])
    end
    t:AddLine(coins(d.money, 12), 1, 1, 1)
    t:AddLine(" ")
    t:AddLine(L.ALTS_PROFS, C.gold[1], C.gold[2], C.gold[3])
    if d.profs and #d.profs > 0 then
        for _, p in ipairs(d.profs) do
            t:AddLine(string.format("  %s %d/%d", p.name or "?", num(p.rank), num(p.max)), 0.9, 0.9, 0.9)
        end
    else
        t:AddLine("  -", 0.6, 0.6, 0.6)
    end
    t:AddLine(L.ALTS_LOCKS, C.gold[1], C.gold[2], C.gold[3])
    local any = false
    for _, lk in ipairs(d.locks or {}) do
        local left = num(lk.expires) - time()
        if left > 0 then
            any = true
            t:AddLine("  " .. (lk.name or "?") .. " - " .. string.format(L.ALTS_RESET, ns.FormatTime(left)), 0.9, 0.9, 0.9)
        end
    end
    if not any then t:AddLine("  " .. L.ALTS_NOLOCK, 0.6, 0.6, 0.6) end
    if not d.bankSeen then t:AddLine(L.ALTS_BANK_UNKNOWN, 1, 0.5, 0.3) end
    t:AddLine(" ")
    t:AddLine(L.ALTS_CLICK_HINT, 0.6, 0.6, 0.65)
    if not c.me then t:AddLine(L.ALTS_DELETE_HINT, 0.6, 0.6, 0.65) end
    t:Show()
end

local function itemTooltip(row)
    local r = row.result
    if not r then return end
    local t = ns.Tooltip(row)
    t:AddLine(r.name)
    for _, p in ipairs(r.parts) do t:AddLine(p, 1, 1, 1) end
    t:Show()
end

---------------------------------------------------------------------------
-- Defilement
---------------------------------------------------------------------------

local function setScroll(y)
    scrollY = math.max(0, math.min(y or 0, scrollMax))
    list:SetVerticalScroll(scrollY)
    if scrollMax > 0 then
        local th = math.max(24, VIEW_H * VIEW_H / (VIEW_H + scrollMax))
        thumb:SetHeight(th)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -(VIEW_H - th) * scrollY / scrollMax)
        track:Show()
        thumb:Show()
    else
        track:Hide()
        thumb:Hide()
    end
end

---------------------------------------------------------------------------
-- Cartes de personnage
---------------------------------------------------------------------------

-- texte d une ligne, ancre sur deux cotes (un seul coin ne suffit pas en jeu)
local function place(fs, parent, lp, lx, rp, rx, y, h)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", parent, lp, lx, y)
    fs:SetPoint("TOPRIGHT", parent, rp, rx, y)
    fs:SetHeight(h or LINE_H)
end

local function newText(parent, template, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function cardBorder(card)
    if not card.cuiBorder then return end
    if card.hover then
        card.cuiBorder:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    elseif card.char and card.char.me then
        card.cuiBorder:SetColorTexture(C.gold[1] * 0.55, C.gold[2] * 0.55, C.gold[3] * 0.55, 1)
    else
        ns.UI.ResetBorder(card)
    end
end

local function forget(c)
    if not c or c.me then return end
    db[c.key] = nil
    expanded[c.key] = nil
    confirmKey = nil
    ns.Say(string.format(L.ALTS_DELETED, c.t.name or c.key))
    ns.HideTooltip()
    refresh()
end

-- ligne n du detail (cree a la demande)
local function detailLine(dt, i)
    local fs = dt.lines[i]
    if not fs then
        fs = newText(dt)
        dt.lines[i] = fs
    end
    fs:Show()
    return fs
end

local function makeCard()
    local card = CreateFrame("Button", nil, child)
    card:SetSize(CW, CARD_H)
    card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    ns.UI.Skin(card, 0.55)
    -- lueur de la couleur de classe depuis la gauche, et filet de classe
    card.glow = card:CreateTexture(nil, "BACKGROUND", nil, -5)
    card.glow:SetPoint("TOPLEFT")
    card.glow:SetSize(CW * 0.6, CARD_H)
    card.stripe = card:CreateTexture(nil, "ARTWORK")
    card.stripe:SetPoint("TOPLEFT")
    card.stripe:SetPoint("BOTTOMLEFT")
    card.stripe:SetWidth(2)
    local hl = card:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT")
    hl:SetSize(CW, CARD_H)
    ns.UI.Gradient(hl, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.16, C.violet[1], C.violet[2], C.violet[3], 0)

    -- icone de classe dans un cadre noir, niveau en pastille
    local frame = card:CreateTexture(nil, "ARTWORK")
    frame:SetSize(32, 32)
    frame:SetPoint("TOPLEFT", 9, -8)
    frame:SetColorTexture(0, 0, 0, 1)
    card.icon = card:CreateTexture(nil, "ARTWORK", nil, 1)
    card.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    card.icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    local pill = card:CreateTexture(nil, "OVERLAY")
    pill:SetSize(20, 12)
    pill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 4, -4)
    pill:SetColorTexture(0, 0, 0, 0.85)
    card.level = card:CreateFontString(nil, "OVERLAY", nil, 1)
    ns.UI.HeadFont(card.level, 9)
    card.level:SetAllPoints(pill)
    card.level:SetJustifyH("CENTER")
    card.level:SetTextColor(C.gold[1], C.gold[2], C.gold[3])

    -- nom (police des titres) et or
    card.name = card:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(card.name, 12)
    card.name:SetJustifyH("LEFT")
    card.name:SetWordWrap(false)
    place(card.name, card, "TOPLEFT", 48, "TOPRIGHT", -176, -8, 16)
    card.money = newText(card, "GameFontHighlight", "RIGHT")
    place(card.money, card, "TOPRIGHT", -176, "TOPRIGHT", -10, -8, 16)
    -- race et zone, derniere connexion
    card.info = newText(card)
    card.info:SetTextColor(C.text[1] * 0.85, C.text[2] * 0.85, C.text[3] * 0.85)
    place(card.info, card, "TOPLEFT", 48, "TOPRIGHT", -116, -25)
    card.seen = newText(card, "GameFontDisableSmall", "RIGHT")
    place(card.seen, card, "TOPRIGHT", -116, "TOPRIGHT", -10, -25)

    -- barre d XP fine : degrade du theme, repos en or translucide
    card.bar = CreateFrame("StatusBar", nil, card)
    card.bar:SetPoint("TOPLEFT", 48, -40)
    card.bar:SetPoint("TOPRIGHT", -10, -40)
    card.bar:SetHeight(3)
    card.bar:SetStatusBarTexture(ns.BAR_TEXTURE)
    card.bar:SetStatusBarColor(1, 1, 1, 1)
    local fill = card.bar:GetStatusBarTexture()
    if fill then
        ns.UI.Gradient(fill, "HORIZONTAL", C.violet[1] * 0.5, C.violet[2] * 0.5, C.violet[3] * 0.5, 1, C.violet[1], C.violet[2], C.violet[3], 1)
    end
    local back = card.bar:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(0, 0, 0, 0.6)
    card.rested = card.bar:CreateTexture(nil, "OVERLAY")
    card.rested:SetHeight(3)
    card.rested:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.45)

    -- detail deplie : metiers | verrous, puis sacs et banque, puis Oublier
    local dt = CreateFrame("Frame", nil, card)
    dt:SetPoint("TOPLEFT", 48, -CARD_H)
    dt:SetPoint("TOPRIGHT", -10, -CARD_H)
    dt:SetHeight(1)
    ns.NoSnap(dt)
    dt.lines = {}
    local sep = dt:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT")
    sep:SetPoint("TOPRIGHT")
    sep:SetHeight(1)
    ns.NoSnap(sep)
    ns.UI.Gradient(sep, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.6, C.gold[1], C.gold[2], C.gold[3], 0)
    for _, k in ipairs({ "profHead", "lockHead" }) do
        local fs = dt:CreateFontString(nil, "OVERLAY")
        ns.UI.HeadFont(fs, 10)
        fs:SetJustifyH("LEFT")
        fs:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
        dt[k] = fs
    end
    place(dt.profHead, dt, "TOPLEFT", 0, "TOP", -6, -6, 14)
    place(dt.lockHead, dt, "TOP", 6, "TOPRIGHT", 0, -6, 14)
    dt.profHead:SetText(L.ALTS_PROFS)
    dt.lockHead:SetText(L.ALTS_LOCKS)
    dt.forget = ns.UI.Button(dt, L.ALTS_FORGET, 90, function()
        local c = card.char
        if not c or c.me then return end
        if confirmKey == c.key and confirmAt and time() - confirmAt <= 4 then
            forget(c)
            return
        end
        confirmKey, confirmAt = c.key, time()
        refresh()
        C_Timer.After(4.5, function()
            if confirmKey == c.key then
                confirmKey = nil
                refresh()
            end
        end)
    end)
    dt:Hide()
    card.detail = dt

    card:SetScript("OnEnter", function(self)
        self.hover = true
        cardBorder(self)
        charTooltip(self)
    end)
    card:SetScript("OnLeave", function(self)
        self.hover = false
        cardBorder(self)
        ns.HideTooltip()
    end)
    card:SetScript("OnClick", function(self, button)
        local c = self.char
        if not c then return end
        if button == "RightButton" then
            if not c.me and IsShiftKeyDown() then forget(c) end
            return
        end
        expanded[c.key] = not expanded[c.key] or nil
        refresh()
    end)
    return card
end

-- remplit le detail ; renvoie sa hauteur
local function fillDetail(card, c)
    local d, dt = c.t, card.detail
    local gold, grey = hex(C.gold), "808080"
    local left, right = {}, {}
    for _, p in ipairs(d.profs or {}) do
        left[#left + 1] = string.format("%s  |cff%s%d/%d|r", p.name or "?", gold, num(p.rank), num(p.max))
    end
    if #left == 0 then left[1] = "|cff" .. grey .. "-|r" end
    for _, lk in ipairs(d.locks or {}) do
        local t = num(lk.expires) - time()
        if t > 0 then
            right[#right + 1] = (lk.name or "?") .. "  |cff9a96a6" .. string.format(L.ALTS_RESET, ns.FormatTime(t)) .. "|r"
        end
    end
    if #right == 0 then right[1] = "|cff" .. grey .. L.ALTS_NOLOCK .. "|r" end

    local n = 0
    local y0 = -22
    for i, text in ipairs(left) do
        n = n + 1
        local fs = detailLine(dt, n)
        place(fs, dt, "TOPLEFT", 0, "TOP", -6, y0 - (i - 1) * LINE_H)
        fs:SetText(text)
    end
    for i, text in ipairs(right) do
        n = n + 1
        local fs = detailLine(dt, n)
        place(fs, dt, "TOP", 6, "TOPRIGHT", 0, y0 - (i - 1) * LINE_H)
        fs:SetText(text)
    end
    local y = y0 - math.max(#left, #right) * LINE_H - 6

    -- sacs, banque
    local bn, bk = tally(d.bags)
    n = n + 1
    local fs = detailLine(dt, n)
    place(fs, dt, "TOPLEFT", 0, "TOPRIGHT", 0, y)
    fs:SetText("|cff" .. gold .. L.ALTS_BAGS_LABEL .. "|r  " .. string.format(L.ALTS_ITEMS, bn, bk))
    y = y - LINE_H - 1
    n = n + 1
    fs = detailLine(dt, n)
    place(fs, dt, "TOPLEFT", 0, "TOPRIGHT", 0, y)
    if d.bankSeen then
        local kn, kk = tally(d.bank)
        fs:SetText("|cff" .. gold .. L.ALTS_BANK_LABEL .. "|r  " .. string.format(L.ALTS_ITEMS, kn, kk) ..
            "  |cff" .. grey .. ns.FormatAgo(d.bankSeen) .. "|r")
    else
        fs:SetText("|cffff8040" .. L.ALTS_BANK_UNKNOWN .. "|r")
    end
    y = y - LINE_H - 6
    for i = n + 1, #dt.lines do dt.lines[i]:Hide() end

    -- Oublier (pas le personnage connecte) : deux clics
    local b = dt.forget
    if c.me then
        b:Hide()
    else
        local pending = confirmKey == c.key
        b:SetText(pending and L.ALTS_FORGET_CONFIRM or L.ALTS_FORGET)
        if pending then
            b.cuiText:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
        else
            b.cuiText:SetTextColor(1, 1, 1)
        end
        b:ClearAllPoints()
        b:SetPoint("TOPRIGHT", dt, "TOPRIGHT", 0, y)
        b:Show()
        y = y - 26
    end
    dt:SetHeight(-y)
    return -y + 2
end

local function showChar(card, c)
    card.char = c
    local d = c.t
    local class = d.class or "PRIEST"
    local r, g, b = ns.ClassColor(class)
    ns.SetClassIcon(card.icon, class)
    card.stripe:SetColorTexture(r, g, b, 1)
    if card.glowClass ~= class then
        ns.UI.Gradient(card.glow, "HORIZONTAL", r, g, b, 0.14, r, g, b, 0)
        card.glowClass = class
    end
    local level = num(d.level)
    card.level:SetText(level > 0 and level or "?")
    local myRealm = GetRealmName and GetRealmName()
    local realm = ""
    if d.realm and d.realm ~= myRealm then realm = "  |cff888888" .. d.realm .. "|r" end
    card.name:SetText(ns.ClassHex(class) .. (d.name or "?") .. "|r" .. realm)
    card.money:SetText(coins(d.money, 12))
    local info = {}
    if d.race and d.race ~= "" then info[#info + 1] = d.race end
    if d.zone and d.zone ~= "" then info[#info + 1] = d.zone end
    card.info:SetText(table.concat(info, "  |cff6a6476/|r  "))
    card.seen:SetText(c.me and ("|cff4fe34f" .. L.ALTS_NOW .. "|r") or ns.FormatAgo(d.lastSeen))

    -- XP (rien au niveau maximum)
    local xpMax, xp = num(d.xpMax), num(d.xp)
    if level < maxLevel() and xpMax > 0 then
        xp = math.max(0, math.min(xp, xpMax))
        card.bar:SetMinMaxValues(0, xpMax)
        card.bar:SetValue(xp)
        local barW = CW - 58
        local rw = math.min(num(d.rested), xpMax - xp) / xpMax * barW
        if rw >= 1 then
            card.rested:ClearAllPoints()
            card.rested:SetPoint("LEFT", card.bar, "LEFT", xp / xpMax * barW, 0)
            card.rested:SetWidth(rw)
            card.rested:Show()
        else
            card.rested:Hide()
        end
        card.bar:Show()
    else
        card.bar:Hide()
    end

    local h = CARD_H
    if expanded[c.key] then
        h = h + fillDetail(card, c)
        card.detail:Show()
    else
        card.detail:Hide()
    end
    card:SetHeight(h)
    cardBorder(card)
    card:Show()
    return h
end

---------------------------------------------------------------------------
-- Resultats de recherche
---------------------------------------------------------------------------

local function makeResult()
    local row = CreateFrame("Button", nil, child)
    row:SetSize(CW, RES_H)
    ns.UI.Skin(row, 0.45)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    ns.UI.Gradient(hl, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.16, C.violet[1], C.violet[2], C.violet[3], 0)
    local frame = row:CreateTexture(nil, "ARTWORK")
    frame:SetSize(26, 26)
    frame:SetPoint("TOPLEFT", 8, -6)
    frame:SetColorTexture(0, 0, 0, 1)
    row.icon = row:CreateTexture(nil, "ARTWORK", nil, 1)
    row.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    row.icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.name = newText(row, "GameFontHighlight")
    place(row.name, row, "TOPLEFT", 42, "TOPRIGHT", -10, -5, 15)
    row.detail = newText(row)
    place(row.detail, row, "TOPLEFT", 42, "TOPRIGHT", -10, -21)
    row:SetScript("OnEnter", function(self)
        self.cuiBorder:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
        itemTooltip(self)
    end)
    row:SetScript("OnLeave", function(self)
        ns.UI.ResetBorder(self)
        ns.HideTooltip()
    end)
    return row
end

local function showResult(row, r)
    row.result = r
    row.icon:SetTexture(ns.ItemIcon(r.id))
    row.name:SetText(r.name .. "  |cff" .. hex(C.gold) .. "x" .. r.total .. "|r")
    row.detail:SetText(table.concat(r.parts, "   "))
    row:Show()
end

---------------------------------------------------------------------------
-- Mise a jour
---------------------------------------------------------------------------

local function updateBanner()
    local total, count = 0, 0
    for _, t in pairs(db) do
        if type(t) == "table" and t.name then
            total = total + num(t.money)
            count = count + 1
        end
    end
    banner.total:SetText(coins(total, 14))
    banner.count:SetText(string.format(L.ALTS_COUNT, count))
end

refresh = function()
    if not win or not win:IsShown() or not db then return end
    snapBasics()
    local query = strtrim(search:GetText() or "")
    local isSearch = #query >= 2
    local y = 0
    local entries
    if isSearch then
        entries = searchItems(query)
        for _, card in ipairs(cards) do card:Hide() card.char = nil end
        for i, r in ipairs(entries) do
            local row = results[i] or makeResult()
            results[i] = row
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
            showResult(row, r)
            y = y + RES_H + GAP
        end
        for i = #entries + 1, #results do results[i]:Hide() results[i].result = nil end
    else
        entries = sortedChars()
        for _, row in ipairs(results) do row:Hide() row.result = nil end
        for i, c in ipairs(entries) do
            local card = cards[i] or makeCard()
            cards[i] = card
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
            y = y + showChar(card, c) + GAP
        end
        for i = #entries + 1, #cards do cards[i]:Hide() cards[i].char = nil end
    end
    child:SetHeight(math.max(1, y))
    scrollMax = math.max(0, y - GAP - VIEW_H)
    setScroll(scrollY)
    win.empty:SetShown(#entries == 0)
    win.empty:SetText(isSearch and L.ALTS_NONE or "")
    updateBanner()
    if sortSel then sortSel:Refresh() end
end

---------------------------------------------------------------------------
-- Construction du panneau
---------------------------------------------------------------------------

local function buildSearch()
    search = CreateFrame("EditBox", nil, win)
    search:SetSize(220, 22)
    search:SetPoint("TOPLEFT", win, "TOPLEFT", 4, -36)
    search:SetAutoFocus(false)
    search:SetFontObject("GameFontHighlightSmall")
    search:SetTextInsets(22, 20, 0, 0)
    search:SetMaxLetters(40)
    ns.UI.Skin(search, 0.8)
    local glass = search:CreateTexture(nil, "OVERLAY")
    glass:SetSize(14, 14)
    glass:SetPoint("LEFT", 5, 0)
    glass:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    glass:SetVertexColor(C.gold[1], C.gold[2], C.gold[3])
    -- "Chercher un objet :" sans les deux-points, en indication dans la case
    local text = L.ALTS_SEARCH:gsub("：$", ""):gsub("%s*:%s*$", "")
    local hint = newText(search, "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 22, 0)
    hint:SetPoint("BOTTOMRIGHT", -20, 0)
    hint:SetText(text)
    local clear = CreateFrame("Button", nil, search)
    clear:SetSize(16, 16)
    clear:SetPoint("RIGHT", -3, 0)
    local x = clear:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    x:SetAllPoints()
    x:SetText("x")
    clear:SetScript("OnClick", function() search:SetText("") search:ClearFocus() end)
    clear:Hide()
    local function sync()
        local empty = (search:GetText() or "") == ""
        hint:SetShown(empty and not search:HasFocus())
        clear:SetShown(not empty)
    end
    search:SetScript("OnTextChanged", function()
        sync()
        scrollY = 0
        refresh()
    end)
    search:SetScript("OnEditFocusGained", sync)
    search:SetScript("OnEditFocusLost", sync)
    search:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
end

local function buildBanner()
    local f = CreateFrame("Frame", nil, win)
    f:SetPoint("TOPLEFT", win, "TOPLEFT", 4, -66)
    f:SetPoint("TOPRIGHT", win, "TOPRIGHT", -4, -66)
    f:SetHeight(38)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    ns.UI.Gradient(bg, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.32, C.violet[1], C.violet[2], C.violet[3], 0.04)
    local bar = f:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("BOTTOMLEFT")
    bar:SetWidth(2)
    bar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    ns.NoSnap(line)
    ns.UI.Gradient(line, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.7, C.gold[1], C.gold[2], C.gold[3], 0)
    local label = newText(f, "GameFontDisableSmall")
    place(label, f, "TOPLEFT", 10, "TOPRIGHT", -150, -4, 12)
    label:SetText(L.ALTS_ACCOUNT)
    banner.total = f:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(banner.total, 14)
    banner.total:SetJustifyH("LEFT")
    banner.total:SetWordWrap(false)
    place(banner.total, f, "TOPLEFT", 10, "TOPRIGHT", -150, -16, 18)
    banner.count = f:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(banner.count, 12)
    banner.count:SetJustifyH("RIGHT")
    banner.count:SetWordWrap(false)
    banner.count:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    place(banner.count, f, "TOPRIGHT", -150, "TOPRIGHT", -10, -5, 15)
    local hint = newText(f, "GameFontDisableSmall", "RIGHT")
    place(hint, f, "TOPRIGHT", -150, "TOPRIGHT", -10, -21, 12)
    hint:SetText(L.ALTS_CLICK_HINT)
    banner.frame = f
end

local function buildWindow()
    ns.root.altsWin = ns.root.altsWin or { point = "CENTER", x = 0, y = 60 }
    win = ns.UI.Window("CorpUIAlts", ns.TITLE .. " - " .. L.MOD_ALTS, ns.root.altsWin, W, H)

    buildSearch()

    -- tri : liste deroulante CorpUI
    local function options()
        local out = {}
        for _, k in ipairs(SORTS) do out[#out + 1] = { value = k, text = L[SORT_TEXT[k]] } end
        return out
    end
    sortSel = ns.UI.Select(win, 150, options,
        function() return view().sort end,
        function(v) view().sort = v end,
        function() scrollY = 0 refresh() end)
    sortSel:SetPoint("TOPRIGHT", win, "TOPRIGHT", -4, -36)

    buildBanner()

    -- liste qui defile a la molette
    list = CreateFrame("ScrollFrame", nil, win)
    list:SetPoint("TOPLEFT", win, "TOPLEFT", 4, -LIST_TOP)
    list:SetSize(CW, VIEW_H)
    child = CreateFrame("Frame", nil, list)
    child:SetSize(CW, 1)
    list:SetScrollChild(child)
    track = win:CreateTexture(nil, "ARTWORK")
    track:SetPoint("TOPLEFT", list, "TOPRIGHT", 7, 0)
    track:SetSize(3, VIEW_H)
    track:SetColorTexture(0, 0, 0, 0.55)
    thumb = win:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(3)
    thumb:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.9)
    track:Hide()
    thumb:Hide()
    local function wheel(_, delta) setScroll(scrollY - delta * 40) end
    for _, f in ipairs({ win, list }) do
        f:EnableMouseWheel(true)
        f:SetScript("OnMouseWheel", wheel)
    end

    win.empty = newText(win, "GameFontDisable", "CENTER")
    place(win.empty, win, "TOPLEFT", 0, "TOPRIGHT", 0, -(LIST_TOP + 16), 16)

    local delHint = newText(win, "GameFontDisableSmall")
    delHint:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 6, 4)
    delHint:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -6, 4)
    delHint:SetHeight(12)
    delHint:SetText(L.ALTS_DELETE_HINT)
    win:HookScript("OnShow", function() refresh() end)
end

local function toggle()
    if not win then buildWindow() end
    ns.ShowPanel(win)
end

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
local events = {}

-- reparation (une fois) : l or des persos etait remis a 0 a chaque
-- deconnexion ; celui des persos a 0 reprend la derniere valeur non nulle
-- de l historique d or de la compta (CorpUIDB.auction.gold, lecture seule)
local function repairMoney(root)
    if root.altsMoneyFix then return end
    root.altsMoneyFix = true
    local hist = type(root.auction) == "table" and root.auction.gold
    if type(hist) ~= "table" then return end
    for key, t in pairs(db) do
        local pts = hist[key]
        if type(t) == "table" and (t.money or 0) == 0 and type(pts) == "table" then
            for i = #pts, 1, -1 do
                local m = type(pts[i]) == "table" and pts[i][2]
                if type(m) == "number" and m > 0 then
                    t.money = m
                    break
                end
            end
        end
    end
end

function events.PLAYER_LOGIN()
    local root = ns.InitRoot()
    root.alts = root.alts or {}
    root.itemNames = root.itemNames or {}
    db, names = root.alts, root.itemNames
    repairMoney(root)
    snapBasics()
    snapBags()
    snapProfs()
    if RequestRaidInfo then pcall(RequestRaidInfo) end
    -- releve de nouveau une fois les donnees du personnage arrivees
    if C_Timer and C_Timer.After then C_Timer.After(5, function() if db then snapBasics() refresh() end end) end
end

local function basics() if db then snapBasics() refresh() end end
events.PLAYER_MONEY = basics
events.PLAYER_LEVEL_UP = basics
events.PLAYER_XP_UPDATE = basics
events.ZONE_CHANGED_NEW_AREA = basics
-- a la deconnexion (et a chaque rechargement), le jeu rend 0 pour l or et
-- l experience (vu dans les sauvegardes le 09/10 : tous les persos a 0) :
-- seule l heure est notee, les valeurs relevees en jeu restent
events.PLAYER_LOGOUT = function()
    if db then current().lastSeen = time() end
end

function events.BAG_UPDATE_DELAYED()
    if not db then return end
    snapBags()
    snapBank()
    if win and win:IsShown() then refresh() end
end

function events.BANKFRAME_OPENED()
    bankOpen = true
    if db then snapBank() end
end
function events.BANKFRAME_CLOSED() bankOpen = false end
function events.PLAYERBANKSLOTS_CHANGED() if db then snapBank() end end

local function profs() if db then snapProfs() end end
events.SKILL_LINES_CHANGED = profs
events.TRADE_SKILL_SHOW = profs

function events.UPDATE_INSTANCE_INFO() if db then snapLocks() end end

ev:SetScript("OnEvent", function(_, event, ...)
    local fn = events[event]
    if fn then fn(...) end
end)
for event in pairs(events) do pcall(ev.RegisterEvent, ev, event) end

---------------------------------------------------------------------------

ns.RegisterModule({
    command = "persos",
    panelName = "CorpUIAlts",
    alias = "/alts",
    icon = "Interface\\Icons\\INV_Misc_GroupNeedMore",
    title = function() return L.MOD_ALTS end,
    desc = function() return L.ALTS_DESC end,
    Slash = function() toggle() end,
    Open = toggle,
})

SLASH_CORPUIALTS1 = "/alts"
SlashCmdList["CORPUIALTS"] = function() toggle() end
