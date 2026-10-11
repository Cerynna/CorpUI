--[[--------------------------------------------------------------------------
    CorpUI - podometre : le classeur (fenetre a quatre onglets) et l annonce
      - Classeur : pages de 4 x 2 cartes, filtres serie / rarete, carte en
        grand a droite (fabrication avec les eclats) ; classeur d un joueur
        de la guilde en lecture seule ;
      - Boosters : boosters en attente, ouverture animee (cartes retournees
        une a une, son selon la rarete, "Nouveau !" ou eclats du doublon) ;
      - Statistiques : jour, semaine, mois, annee, total (prochain palier),
        facons de se deplacer, record, 30 derniers jours, personnages,
        equivalence reelle ;
      - Guilde : classement de la semaine des joueurs CorpUI.
    Images (Media\Podometre, Nano Banana) : cadre argente teinte selon la
    rarete, dos de carte, booster ; sans elles (jeu pas redemarre), les
    cartes gardent un liseré de couleur.
    Aucune action protegee : la fenetre s ouvre aussi en combat.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L
local C = ns.COLORS

ns.Pedo = ns.Pedo or {}
local P = ns.Pedo

local MEDIA = ns.MEDIA .. "Podometre\\"
-- mesures des images (make_pedo.js) : fractions de la carte
local RATIO = 1.3877                     -- hauteur / largeur d une carte
local ART = { l = 0.2025, r = 0.7914, t = 0.1085, b = 0.6014 }
local PLATE = { l = 0.1494, r = 0.8457, t = 0.7375, b = 0.8870 }
local TEX_FRAME, TEX_BACK, TEX_PACK = 355 / 512, 363 / 512, 392 / 512
local PACK_RATIO = 1.5325

local WIN_W, WIN_H = 780, 540
local GRID_COLS, GRID_ROWS = 4, 2
local PER_PAGE = GRID_COLS * GRID_ROWS
local SOUND_OF = { "coin", "f_ding", "f_ding", "quest", "f_carillon" }

local win, tabs, pages = nil, {}, {}
local current = "binder"

local function db() return P.db end

local function rarityRGB(r) return P.RARITY_RGB[r] or P.RARITY_RGB[1] end
local function tint(r)
    local c = rarityRGB(r)
    return 0.35 + 0.65 * c[1], 0.35 + 0.65 * c[2], 0.35 + 0.65 * c[3]
end

local function font(fs, size, flags)
    local f = (ns.FontFile and ns.FontFile("regular")) or STANDARD_TEXT_FONT
    pcall(fs.SetFont, fs, f, size, flags or "")
end

local function text(parent, template, size, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    if size then font(fs, size, flags) end
    return fs
end

local function shortName(full)
    if type(full) ~= "string" then return "?" end
    return full:match("^([^%-]+)") or full
end

-- code couleur |cff : composantes entieres
local function hex(r, g, b)
    return string.format("%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function classColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

---------------------------------------------------------------------------
-- Carte
---------------------------------------------------------------------------

local function newCard(parent, w)
    local h = math.floor(w * RATIO + 0.5)
    local c = CreateFrame("Button", nil, parent)
    c:SetSize(w, h)
    c.w, c.h = w, h
    -- lueur (epique, legendaire)
    c.glow = c:CreateTexture(nil, "BACKGROUND", nil, -8)
    c.glow:SetPoint("TOPLEFT", -5, 5)
    c.glow:SetPoint("BOTTOMRIGHT", 5, -5)
    c.glow:SetColorTexture(1, 1, 1, 0.3)
    c.glow:Hide()
    -- liseré de secours (sans l image du cadre)
    c.edge = c:CreateTexture(nil, "BACKGROUND", nil, -7)
    c.edge:SetAllPoints()
    c.edge:SetColorTexture(0.5, 0.5, 0.5, 1)
    ns.NoSnap(c.edge)
    c.bg = c:CreateTexture(nil, "BACKGROUND", nil, -6)
    c.bg:SetPoint("TOPLEFT", 2, -2)
    c.bg:SetPoint("BOTTOMRIGHT", -2, 2)
    c.bg:SetColorTexture(0.07, 0.06, 0.09, 1)
    ns.NoSnap(c.bg)
    -- image : la fenetre du cadre
    local al, at = math.floor(w * ART.l + 0.5), math.floor(h * ART.t + 0.5)
    local aw, ah = math.floor(w * (ART.r - ART.l) + 0.5), math.floor(h * (ART.b - ART.t) + 0.5)
    c.artBg = c:CreateTexture(nil, "BORDER")
    c.artBg:SetPoint("TOPLEFT", al, -at)
    c.artBg:SetSize(aw, ah)
    c.artBg:SetColorTexture(0.12, 0.1, 0.16, 1)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    local isz = math.floor(math.min(aw, ah) * 0.78 + 0.5)
    c.icon:SetSize(isz, isz)
    c.icon:SetPoint("CENTER", c.artBg, "CENTER", 0, 0)
    c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- tuiles de la carte du monde : 2 x 2, rognees sur les cotes
    c.tiles = {}
    for i = 1, 4 do
        local t = c:CreateTexture(nil, "ARTWORK")
        t:SetSize(aw / 2, ah / 2)
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        t:SetPoint("TOPLEFT", c.artBg, "TOPLEFT", col * aw / 2, -row * ah / 2)
        c.tiles[i] = t
    end
    c.dim = c:CreateTexture(nil, "ARTWORK", nil, 3)
    c.dim:SetAllPoints(c.artBg)
    c.dim:SetColorTexture(0, 0, 0, 0.6)
    -- cartouche du nom
    local pl, pt = math.floor(w * PLATE.l + 0.5), math.floor(h * PLATE.t + 0.5)
    local pw, ph = math.floor(w * (PLATE.r - PLATE.l) + 0.5), math.floor(h * (PLATE.b - PLATE.t) + 0.5)
    c.plate = c:CreateTexture(nil, "BORDER")
    c.plate:SetPoint("TOPLEFT", pl, -pt)
    c.plate:SetSize(pw, ph)
    c.plate:SetColorTexture(0.04, 0.035, 0.05, 1)
    -- cadre (image argentee, teintee)
    c.frame = c:CreateTexture(nil, "OVERLAY")
    c.frame:SetAllPoints()
    c.frame:SetTexture(MEDIA .. "cadre")
    c.frame:SetTexCoord(0, 1, 0, TEX_FRAME)
    local fsz = math.max(8, math.floor(w / 11 + 0.5))
    c.name = text(c, "GameFontHighlightSmall", fsz, "OUTLINE")
    c.name:SetPoint("TOPLEFT", c.plate, "TOPLEFT", 3, -1)
    c.name:SetPoint("BOTTOMRIGHT", c.plate, "BOTTOMRIGHT", -3, 1)
    c.name:SetJustifyH("CENTER")
    c.name:SetJustifyV("MIDDLE")
    c.num = text(c, "GameFontDisableSmall", math.max(7, fsz - 2), "OUTLINE")
    c.num:SetPoint("BOTTOM", c, "BOTTOM", 0, math.floor(h * 0.035 + 0.5))
    c.qmark = text(c, "GameFontNormalHuge", math.floor(aw * 0.45 + 0.5), "OUTLINE")
    c.qmark:SetPoint("CENTER", c.artBg, "CENTER", 0, 0)
    c.qmark:SetText("?")
    c.qmark:SetTextColor(0.7, 0.7, 0.75)
    c.new = text(c, "GameFontNormalSmall", math.max(8, fsz - 1), "OUTLINE")
    c.new:SetPoint("TOP", c.artBg, "TOP", 0, -3)
    c.new:SetText(L.PEDO_NEW)
    c.new:SetTextColor(1, 0.82, 0)
    -- dos (boosters) : un cadre au-dessus de la carte, pas une texture de
    -- la carte (le jeu dessine les textes par-dessus les textures de leur
    -- couche : le nom se voyait a travers le dos)
    c.back = CreateFrame("Frame", nil, c)
    c.back:SetAllPoints()
    c.back:SetFrameLevel(c:GetFrameLevel() + 5)
    local back = c.back:CreateTexture(nil, "ARTWORK")
    back:SetAllPoints()
    back:SetTexture(MEDIA .. "dos")
    back:SetTexCoord(0, 1, 0, TEX_BACK)
    c.back:Hide()
    return c
end

-- remplit une carte ; owned : la carte est-elle dans le classeur montre
local function paintCard(card, c, owned, isNew)
    card.card = c
    if not c then card:Hide() return end
    card:Show()
    local r1, g1, b1 = tint(c.r)
    local col = rarityRGB(c.r)
    for _, t in ipairs(card.tiles) do t:Hide() end
    card.icon:Hide()
    local tiles = c.map and P.CardTiles(c)
    if tiles then
        local cols, rows = tiles.cols, tiles.rows
        local c0 = cols >= 2 and (math.floor((cols - 2) / 2) + 1) or 1
        local r0 = rows >= 2 and (math.floor((rows - 2) / 2) + 1) or 1
        local cut = 0.139   -- rognage des cotes (fenetre plus haute que large)
        for i = 1, 4 do
            local cc, rr = c0 + (i - 1) % 2, r0 + math.floor((i - 1) / 2)
            local id = tiles.tex[(rr - 1) * cols + cc]
            local t = card.tiles[i]
            if id and cc <= cols and rr <= rows then
                t:SetTexture(id)
                if (i - 1) % 2 == 0 then t:SetTexCoord(cut, 1, 0, 1) else t:SetTexCoord(0, 1 - cut, 0, 1) end
                pcall(t.SetDesaturated, t, not owned)
                t:Show()
            end
        end
    else
        card.icon:SetTexture(P.CardIcon(c) or "Interface\\Icons\\INV_Misc_QuestionMark")
        pcall(card.icon.SetDesaturated, card.icon, not owned)
        card.icon:Show()
    end
    card.artBg:SetColorTexture(col[1] * 0.18, col[2] * 0.18, col[3] * 0.18, 1)
    card.dim:SetShown(not owned)
    card.qmark:SetShown(not owned)
    if owned then
        card.frame:SetVertexColor(r1, g1, b1)
        card.edge:SetColorTexture(col[1], col[2], col[3], 1)
        card.name:SetText(P.CardName(c))
        card.name:SetTextColor(math.min(1, col[1] + 0.25), math.min(1, col[2] + 0.25), math.min(1, col[3] + 0.25))
    else
        card.frame:SetVertexColor(0.38, 0.38, 0.4)
        card.edge:SetColorTexture(0.3, 0.3, 0.32, 1)
        card.name:SetText("???")
        card.name:SetTextColor(0.55, 0.55, 0.6)
    end
    card.num:SetText("#" .. (c.num or c.index))
    card.new:SetShown(owned and isNew and true or false)
    card.glow:SetShown(owned and c.r >= 4)
    if owned and c.r >= 4 then card.glow:SetColorTexture(col[1], col[2], col[3], 0.28) end
end

local function cardTooltip(card)
    local c = card.card
    if not c then return end
    local owned = card.owned
    local t = ns.Tooltip(card, "ANCHOR_RIGHT")
    if owned and c.item then
        pcall(t.SetItemByID, t, c.item)
    else
        local col = rarityRGB(c.r)
        t:AddLine(owned and P.CardName(c) or L.PEDO_MISSING, col[1], col[2], col[3])
    end
    t:AddLine(L["PEDO_SERIES_" .. string.upper(c.s)] .. " · " .. L["PEDO_R" .. c.r], 0.8, 0.8, 0.8)
    local hint = P.CardHint(c)
    if hint then t:AddLine(hint, 0.6, 0.8, 1, true) end
    t:Show()
end

---------------------------------------------------------------------------
-- Fenetre
---------------------------------------------------------------------------

local refreshPage

local function selectTab(key)
    current = key
    for k, f in pairs(pages) do f:SetShown(k == key) end
    for _, t in ipairs(tabs) do
        local on = t.key == key
        t:SetBackdropBorderColor((on and C.gold or C.border)[1], (on and C.gold or C.border)[2], (on and C.gold or C.border)[3], 1)
    end
    refreshPage()
end

local function tabLabel(key)
    if key == "packs" then
        local n = db() and #db().packs or 0
        return n > 0 and string.format(L.PEDO_TAB_PACKS_N, n) or L.PEDO_TAB_PACKS
    end
    return L["PEDO_TAB_" .. string.upper(key)]
end

---------------------------------------------------------------------------
-- Onglet Classeur
---------------------------------------------------------------------------

local B = { series = "all", rarity = 0, page = 1, sel = nil }
local view            -- classeur d un autre joueur : { name, set }
local shownNew = {}   -- cartes "Nouveau" montrees : vues au changement de page
local shownKey

local function ownedHere(id)
    if view then return view.set[id] == true end
    return P.Owned(id)
end

local function forgetNew()
    local d = db()
    if not d or view then return end
    for id in pairs(shownNew) do d.newCards[id] = nil end
    shownNew = {}
end

local function buildBinder(page)
    local p = page
    p.series = ns.UI.Select(p, 160, function()
        local list = { { value = "all", text = L.PEDO_ALL_SERIES } }
        for _, s in ipairs(P.SERIES) do list[#list + 1] = { value = s, text = L["PEDO_SERIES_" .. string.upper(s)] } end
        return list
    end, function() return B.series end, function(v) B.series = v B.page = 1 B.sel = nil end, function() refreshPage() end)
    p.series:SetPoint("TOPLEFT", 12, -6)
    p.rarity = ns.UI.Select(p, 140, function()
        local list = { { value = 0, text = L.PEDO_ALL_RARITIES } }
        for r = 1, 5 do list[#list + 1] = { value = r, text = L["PEDO_R" .. r] } end
        return list
    end, function() return B.rarity end, function(v) B.rarity = v B.page = 1 B.sel = nil end, function() refreshPage() end)
    p.rarity:SetPoint("LEFT", p.series, "RIGHT", 8, 0)
    p.count = text(p, "GameFontNormal")
    p.count:SetPoint("LEFT", p.rarity, "RIGHT", 14, 0)
    -- classeur d un autre joueur : bandeau
    p.viewing = text(p, "GameFontNormal")
    p.viewing:SetPoint("TOPRIGHT", p, "TOPRIGHT", -150, -10)
    p.back = ns.UI.Button(p, L.PEDO_MY_BINDER, 130, function() view = nil B.page = 1 B.sel = nil refreshPage() end)
    p.back:SetPoint("TOPRIGHT", p, "TOPRIGHT", -12, -6)
    -- grille
    p.cards = {}
    for i = 1, PER_PAGE do
        local card = newCard(p, 112)
        local col, row = (i - 1) % GRID_COLS, math.floor((i - 1) / GRID_COLS)
        card:SetPoint("TOPLEFT", p, "TOPLEFT", 12 + col * 124, -40 - row * 169)
        card:SetScript("OnEnter", cardTooltip)
        card:SetScript("OnLeave", ns.HideTooltip)
        card:SetScript("OnClick", function(self)
            B.sel = self.card and self.card.id
            refreshPage()
        end)
        p.cards[i] = card
    end
    p.prev = ns.UI.Button(p, "<", 30, function() B.page = B.page - 1 refreshPage() end)
    p.prev:SetPoint("TOPLEFT", p, "TOPLEFT", 160, -384)
    p.pageText = text(p, "GameFontHighlight")
    p.pageText:SetPoint("LEFT", p.prev, "RIGHT", 10, 0)
    p.pageText:SetWidth(110)
    p.next = ns.UI.Button(p, ">", 30, function() B.page = B.page + 1 refreshPage() end)
    p.next:SetPoint("LEFT", p.pageText, "RIGHT", 10, 0)
    -- carte en grand
    p.big = newCard(p, 168)
    p.big:SetPoint("TOPLEFT", p, "TOPLEFT", 556, -40)
    p.big:SetScript("OnEnter", cardTooltip)
    p.big:SetScript("OnLeave", ns.HideTooltip)
    p.bigName = text(p, "GameFontNormalLarge")
    p.bigName:SetPoint("TOP", p.big, "BOTTOM", 0, -8)
    p.bigName:SetWidth(240)
    p.bigInfo = text(p, "GameFontHighlightSmall")
    p.bigInfo:SetPoint("TOP", p.bigName, "BOTTOM", 0, -4)
    p.bigInfo:SetWidth(240)
    p.bigHint = text(p, "GameFontDisableSmall")
    p.bigHint:SetPoint("TOP", p.bigInfo, "BOTTOM", 0, -4)
    p.bigHint:SetWidth(240)
    p.craft = ns.UI.Button(p, "", 200, function()
        if B.sel and P.Craft(B.sel) then
            P.Sound("f_ding")
            refreshPage()
        end
    end)
    p.craft:SetPoint("TOP", p.bigHint, "BOTTOM", 0, -8)
end

local function refreshBinder(p)
    local list = P.Cards(B.series, B.rarity)
    local pagesN = math.max(1, math.ceil(#list / PER_PAGE))
    B.page = math.max(1, math.min(B.page, pagesN))
    -- autre page (ou autre filtre) : les cartes nouvelles d avant sont vues
    local key = B.series .. ":" .. B.rarity .. ":" .. B.page .. ":" .. (view and view.name or "")
    if key ~= shownKey then forgetNew() shownKey = key end
    -- listes deroulantes : le choix en cours s affiche a la demande
    p.series:Refresh()
    p.rarity:Refresh()
    local own = 0
    for _, c in ipairs(list) do if ownedHere(c.id) then own = own + 1 end end
    p.count:SetText(string.format(L.PEDO_COUNT, own, #list, #list > 0 and math.floor(own / #list * 100 + 0.5) or 0))
    p.viewing:SetShown(view ~= nil)
    p.back:SetShown(view ~= nil)
    if view then p.viewing:SetText(string.format(L.PEDO_VIEWING, shortName(view.name))) end
    local first = (B.page - 1) * PER_PAGE
    local d = db()
    for i, card in ipairs(p.cards) do
        local c = list[first + i]
        local owned = c and ownedHere(c.id) or false
        card.owned = owned
        local isNew = c and not view and d and d.newCards[c.id] or false
        if isNew then shownNew[c.id] = true end
        paintCard(card, c, owned, isNew)
    end
    p.pageText:SetText(string.format(L.PEDO_PAGE, B.page, pagesN))
    p.prev:SetEnabled(B.page > 1)
    p.next:SetEnabled(B.page < pagesN)
    -- carte en grand : la choisie, sinon la premiere de la page
    local sel = B.sel and P.byId[B.sel]
    if not sel or not P.IsValid(sel.id) then sel = list[first + 1] end
    if not sel then
        p.big:Hide() p.bigName:SetText("") p.bigInfo:SetText("") p.bigHint:SetText("") p.craft:Hide()
        return
    end
    local owned = ownedHere(sel.id)
    p.big.owned = owned
    paintCard(p.big, sel, owned, false)
    local col = rarityRGB(sel.r)
    p.bigName:SetText(owned and P.CardName(sel) or L.PEDO_MISSING)
    p.bigName:SetTextColor(col[1], col[2], col[3])
    p.bigInfo:SetText(L["PEDO_SERIES_" .. string.upper(sel.s)] .. " · " .. L["PEDO_R" .. sel.r] ..
        " · #" .. (sel.num or sel.index) .. "/" .. ((P.seriesCount and P.seriesCount[sel.s]) or "?"))
    local hint = P.CardHint(sel)
    if not hint and not owned and sel.s ~= "trophees" then hint = L.PEDO_MISSING_HINT end
    p.bigHint:SetText(hint or "")
    if not view and not owned and sel.s ~= "trophees" then
        p.craft:SetText(string.format(L.PEDO_CRAFT, P.CRAFT[sel.r]))
        p.craft:SetEnabled(P.CanCraft(sel.id))
        p.craft:Show()
    else
        p.craft:Hide()
    end
end

---------------------------------------------------------------------------
-- Onglet Boosters (ouverture animee)
---------------------------------------------------------------------------

local reveal          -- { ids, results, start, flipAt = {}, done = {} }
local FLIP_GAP, FLIP_TIME = 0.45, 0.28

local function buildPacks(page)
    local p = page
    -- liste
    p.list = CreateFrame("Frame", nil, p)
    p.list:SetAllPoints()
    p.art = p.list:CreateTexture(nil, "ARTWORK")
    p.art:SetSize(170, math.floor(170 * PACK_RATIO + 0.5))
    p.art:SetPoint("TOPLEFT", p.list, "TOPLEFT", 40, -20)
    p.art:SetTexture(MEDIA .. "booster")
    p.art:SetTexCoord(0, 1, 0, TEX_PACK)
    p.artCount = text(p.list, "GameFontNormalHuge", 28, "OUTLINE")
    p.artCount:SetPoint("BOTTOMRIGHT", p.art, "BOTTOMRIGHT", -6, 10)
    p.open = ns.UI.Button(p.list, L.PEDO_OPEN_PACK, 170, function() P.OpenNextPack() end)
    p.open:SetPoint("TOP", p.art, "BOTTOM", 0, -14)
    p.title = text(p.list, "GameFontNormalLarge")
    p.title:SetPoint("TOPLEFT", p.list, "TOPLEFT", 250, -20)
    p.rows = {}
    for i = 1, 12 do
        local fs = text(p.list, "GameFontHighlight")
        fs:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -10 - (i - 1) * 20)
        fs:SetWidth(500)
        fs:SetJustifyH("LEFT")
        p.rows[i] = fs
    end
    p.empty = text(p.list, "GameFontHighlight")
    p.empty:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -10)
    p.empty:SetWidth(500)
    p.empty:SetJustifyH("LEFT")
    -- ouverture
    p.show = CreateFrame("Frame", nil, p)
    p.show:SetAllPoints()
    p.show:Hide()
    p.showTitle = text(p.show, "GameFontNormalLarge")
    p.showTitle:SetPoint("TOP", p.show, "TOP", 0, -16)
    p.slots, p.revealCards, p.captions = {}, {}, {}
    local cw = 120
    local total = 5 * cw + 4 * 16
    for i = 1, 5 do
        local slot = CreateFrame("Frame", nil, p.show)
        slot:SetSize(cw, math.floor(cw * RATIO + 0.5))
        slot:SetPoint("TOPLEFT", p.show, "TOPLEFT", (WIN_W - total) / 2 + (i - 1) * (cw + 16), -70)
        local card = newCard(slot, cw)
        card:SetPoint("CENTER", slot, "CENTER", 0, 0)
        card:SetScript("OnEnter", function(self) if not self.back:IsShown() then cardTooltip(self) end end)
        card:SetScript("OnLeave", ns.HideTooltip)
        card:SetScript("OnClick", function()
            if reveal and not reveal.done[i] and not reveal.flipAt[i] then reveal.flipAt[i] = GetTime() end
        end)
        local cap = text(p.show, "GameFontNormal")
        cap:SetPoint("TOP", slot, "BOTTOM", 0, -10)
        cap:SetWidth(cw + 10)
        p.slots[i], p.revealCards[i], p.captions[i] = slot, card, cap
    end
    p.nextPack = ns.UI.Button(p.show, "", 200, function()
        if db() and #db().packs > 0 then P.OpenNextPack() else reveal = nil refreshPage() end
    end)
    p.nextPack:SetPoint("BOTTOM", p.show, "BOTTOM", -110, 40)
    p.toBinder = ns.UI.Button(p.show, L.PEDO_SEE_BINDER, 200, function() reveal = nil selectTab("binder") end)
    p.toBinder:SetPoint("BOTTOM", p.show, "BOTTOM", 110, 40)
    -- animation : retournement des cartes une a une
    p.show:SetScript("OnUpdate", function()
        if not reveal then return end
        local now = GetTime()
        for i = 1, #reveal.ids do
            local card = p.revealCards[i]
            if not reveal.flipAt[i] and now >= reveal.start + 0.6 + (i - 1) * FLIP_GAP then reveal.flipAt[i] = now end
            local t0 = reveal.flipAt[i]
            if t0 and not reveal.done[i] then
                local k = math.min(1, (now - t0) / FLIP_TIME)
                card.back:SetAlpha(1 - k)
                card:SetScale(1 + 0.12 * math.sin(k * math.pi))
                if k >= 1 then
                    reveal.done[i] = true
                    card.back:Hide()
                    card.name:SetAlpha(1)
                    card.num:SetAlpha(1)
                    card:SetScale(1)
                    local res = reveal.results[i]
                    local c = P.byId[reveal.ids[i]]
                    local cap = p.captions[i]
                    if res and res.what == "new" then
                        cap:SetText(L.PEDO_NEW_CARD)
                        cap:SetTextColor(1, 0.82, 0)
                    else
                        cap:SetText(string.format(L.PEDO_DUP, res and res.gain or 0))
                        cap:SetTextColor(0.7, 0.7, 0.75)
                    end
                    P.Sound(SOUND_OF[c and c.r or 1])
                end
            end
            -- lueur des grandes raretes une fois retournees
            if reveal.done[i] and card.card and card.card.r >= 4 then
                card.glow:SetAlpha(0.55 + 0.45 * math.abs(math.sin(now * 3)))
            end
        end
    end)
end

local function refreshPacks(p)
    local d = db()
    if not d then return end
    if reveal then
        p.list:Hide()
        p.show:Show()
        p.showTitle:SetText(reveal.title or "")
        local left = #d.packs
        p.nextPack:SetText(left > 0 and string.format(L.PEDO_NEXT_PACK, left) or L.PEDO_DONE)
        return
    end
    p.show:Hide()
    p.list:Show()
    local n = #d.packs
    p.artCount:SetText(n > 0 and ("x" .. n) or "")
    p.art:SetDesaturated(n == 0)
    p.open:SetEnabled(n > 0)
    p.title:SetText(n > 0 and string.format(L.PEDO_PACKS_WAITING, n) or L.PEDO_NO_PACK)
    for i, fs in ipairs(p.rows) do
        local pack = d.packs[i]
        if pack and i < #p.rows then
            local col = rarityRGB(P.PACK_MIN[pack.k] and (P.PACK_MIN[pack.k] + 1) or 2)
            if pack.k == "normal" then col = { 1, 1, 1 } end
            fs:SetText(string.format("|cff%s%s|r  %s", hex(col[1], col[2], col[3]),
                L["PEDO_PACK_" .. string.upper(pack.k)] or pack.k, P.WhyText(pack)))
        elseif i == #p.rows and n >= #p.rows then
            fs:SetText(string.format(L.PEDO_AND_MORE, n - #p.rows + 1))
        else
            fs:SetText("")
        end
    end
    p.empty:SetShown(n == 0)
    if n == 0 then
        local nk, kind, y = P.NextMilestone("day")
        p.empty:SetText(nk and string.format(L.PEDO_NEXT_DAY, P.KmValue(nk), P.Km(nk * 1000 - y), L["PEDO_PACK_" .. string.upper(kind)]) or "")
    end
end

-- ouvre le plus ancien booster : les cartes sont gagnees tout de suite,
-- l animation ne fait que les montrer
function P.OpenNextPack()
    local d = db()
    if not d or #d.packs == 0 then return end
    local pack = table.remove(d.packs, 1)
    local ids = P.RollPack(pack.k)
    local results = {}
    for i, id in ipairs(ids) do
        local what, gain = P.Grant(id)
        results[i] = { what = what, gain = gain }
    end
    d.opened = (d.opened or 0) + 1
    reveal = { ids = ids, results = results, start = GetTime(), flipAt = {}, done = {},
               title = (L["PEDO_PACK_" .. string.upper(pack.k)] or "") .. " · " .. P.WhyText(pack) }
    local p = pages.packs
    for i = 1, 5 do
        local card = p.revealCards[i]
        local c = P.byId[ids[i]]
        card.owned = true
        paintCard(card, c, true, false)
        card.new:Hide()
        -- face cachee : rien de la carte ne doit se voir
        card.name:SetAlpha(0)
        card.num:SetAlpha(0)
        card.back:Show()
        card.back:SetAlpha(1)
        card:SetScale(1)
        card.glow:SetAlpha(1)
        p.captions[i]:SetText("")
        p.slots[i]:SetShown(c ~= nil)
    end
    P.Sound("f_confirm1")
    if P.CheckTrophies then P.CheckTrophies() end
    P.Changed("open")
    if current ~= "packs" then selectTab("packs") else refreshPage() end
end

---------------------------------------------------------------------------
-- Onglet Statistiques
---------------------------------------------------------------------------

local function buildStats(page)
    local p = page
    p.boxes = {}
    for i, kind in ipairs({ "day", "week", "month", "year", "total" }) do
        local box = CreateFrame("Frame", nil, p)
        box:SetSize(142, 96)
        box:SetPoint("TOPLEFT", p, "TOPLEFT", 12 + (i - 1) * 152, -8)
        ns.UI.Skin(box, 0.6)
        box.title = text(box, "GameFontDisableSmall")
        box.title:SetPoint("TOPLEFT", 8, -7)
        box.title:SetText(L["PEDO_P_" .. string.upper(kind)])
        box.value = text(box, "GameFontHighlightLarge")
        ns.UI.HeadFont(box.value, 19)
        box.value:SetPoint("TOPLEFT", 8, -24)
        box.bar = CreateFrame("StatusBar", nil, box)
        box.bar:SetPoint("TOPLEFT", 8, -56)
        box.bar:SetPoint("TOPRIGHT", -8, -56)
        box.bar:SetHeight(6)
        box.bar:SetStatusBarTexture(ns.BAR_TEXTURE)
        box.bar:SetStatusBarColor(C.gold[1], C.gold[2], C.gold[3])
        box.bar:SetMinMaxValues(0, 1)
        local bbg = box.bar:CreateTexture(nil, "BACKGROUND")
        bbg:SetAllPoints()
        bbg:SetColorTexture(0, 0, 0, 0.5)
        box.next = text(box, "GameFontDisableSmall")
        box.next:SetPoint("TOPLEFT", 8, -68)
        box.next:SetWidth(128)
        box.next:SetJustifyH("LEFT")
        box.kind = kind
        p.boxes[i] = box
    end
    p.modesToday = text(p, "GameFontHighlightSmall")
    p.modesToday:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -118)
    p.modesTotal = text(p, "GameFontHighlightSmall")
    p.modesTotal:SetPoint("TOPLEFT", p.modesToday, "BOTTOMLEFT", 0, -4)
    p.record = text(p, "GameFontNormalSmall")
    p.record:SetPoint("TOPLEFT", p.modesTotal, "BOTTOMLEFT", 0, -4)
    -- 30 derniers jours
    p.chartTitle = text(p, "GameFontNormal")
    p.chartTitle:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -186)
    p.chartTitle:SetText(L.PEDO_LAST30)
    p.chart = CreateFrame("Frame", nil, p)
    p.chart:SetSize(30 * 16, 150)
    p.chart:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -208)
    ns.UI.Skin(p.chart, 0.45)
    p.bars = {}
    for i = 1, 30 do
        local b = CreateFrame("Frame", nil, p.chart)
        b:SetSize(12, 1)
        b:SetPoint("BOTTOMLEFT", p.chart, "BOTTOMLEFT", 2 + (i - 1) * 16, 2)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints()
        b:EnableMouse(true)
        b:SetScript("OnEnter", function(self)
            if not self.label then return end
            local t = ns.Tooltip(self, "ANCHOR_TOP")
            t:AddLine(self.label, 1, 0.82, 0)
            t:AddLine(P.Km(self.yards or 0, 2), 1, 1, 1)
            t:Show()
        end)
        b:SetScript("OnLeave", ns.HideTooltip)
        p.bars[i] = b
    end
    p.chartMax = text(p, "GameFontDisableSmall")
    p.chartMax:SetPoint("BOTTOMLEFT", p.chart, "TOPRIGHT", -80, 4)
    p.equiv = text(p, "GameFontHighlight")
    p.equiv:SetPoint("TOPLEFT", p.chart, "BOTTOMLEFT", 0, -12)
    p.equiv:SetWidth(740)
    p.equiv:SetJustifyH("LEFT")
    -- personnages
    p.charsTitle = text(p, "GameFontNormal")
    p.charsTitle:SetPoint("TOPLEFT", p, "TOPLEFT", 520, -186)
    p.charsTitle:SetText(L.PEDO_CHARS)
    p.chars = {}
    for i = 1, 8 do
        local row = text(p, "GameFontHighlightSmall")
        row:SetPoint("TOPLEFT", p.charsTitle, "BOTTOMLEFT", 0, -6 - (i - 1) * 18)
        row:SetWidth(240)
        row:SetJustifyH("LEFT")
        p.chars[i] = row
    end
end

local function modesLine(label, get)
    return string.format("%s  %s %s  ·  %s %s  ·  %s %s  ·  %s %s", label,
        L.PEDO_M_F, P.Km(get("f")), L.PEDO_M_S, P.Km(get("s")), L.PEDO_M_M, P.Km(get("m")), L.PEDO_M_G, P.Km(get("g")))
end

local function refreshStats(p)
    local d = db()
    if not d then return end
    local T = P.Totals()
    for _, box in ipairs(p.boxes) do
        local y = T[box.kind] or 0
        box.value:SetText(P.Km(y))
        local list = P.MILESTONES[box.kind]
        local prevK, nextK, nextKind = 0, nil, nil
        for _, ms in ipairs(list) do
            if y < ms[1] * 1000 then nextK, nextKind = ms[1], ms[2] break end
            prevK = ms[1]
        end
        if nextK then
            box.bar:SetValue((y - prevK * 1000) / ((nextK - prevK) * 1000))
            box.next:SetText(string.format(L.PEDO_NEXT_SHORT, P.KmValue(nextK)))
        else
            box.bar:SetValue(1)
            box.next:SetText(L.PEDO_ALL_DONE)
        end
    end
    local K = T.keys
    p.modesToday:SetText(modesLine(L.PEDO_TODAY, function(m) return P.DayYards(K.day, m) end))
    p.modesTotal:SetText(modesLine(L.PEDO_P_TOTAL, function(m) return d.total[m] or 0 end))
    if (d.best.y or 0) > 0 and d.best.k then
        local yy, mm, dd = d.best.k:match("^(%d+)%-(%d+)%-(%d+)$")
        p.record:SetText(string.format(L.PEDO_RECORD, P.Km(d.best.y), string.format(L.PEDO_DATE, dd or "?", mm or "?", yy or "?")))
    else
        p.record:SetText("")
    end
    -- 30 derniers jours
    local maxY = 1
    local vals = {}
    for i = 1, 30 do
        local t = K.noon - (30 - i) * 86400
        local dk = date("%Y-%m-%d", t)
        vals[i] = { y = P.DayYards(dk), dk = dk, t = t }
        if vals[i].y > maxY then maxY = vals[i].y end
    end
    for i, b in ipairs(p.bars) do
        local v = vals[i]
        b:SetHeight(math.max(1, math.floor(v.y / maxY * 144 + 0.5)))
        if i == 30 then b.tex:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
        else b.tex:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], v.y > 0 and 0.9 or 0.25) end
        b.yards = v.y
        b.label = date(L.PEDO_DAY_FMT, v.t)
    end
    p.chartMax:SetText(string.format(L.PEDO_MAX, P.Km(maxY)))
    -- equivalence reelle
    local tk = T.total / 1000
    local done, nextE
    for _, e in ipairs(P.EQUIV) do
        if tk >= e[1] then done = e else nextE = e break end
    end
    local s = done and string.format(L.PEDO_EQUIV_DONE, L[done[2]]) or L.PEDO_EQUIV_NONE
    if nextE then s = s .. "  " .. string.format(L.PEDO_EQUIV_NEXT, L[nextE[2]], P.Km((nextE[1] - tk) * 1000, 0)) end
    p.equiv:SetText(s)
    -- personnages
    local chars = {}
    for _, ch in pairs(d.chars) do
        if type(ch) == "table" and (tonumber(ch.total) or 0) > 0 then chars[#chars + 1] = ch end
    end
    table.sort(chars, function(a, b) return (a.total or 0) > (b.total or 0) end)
    for i, row in ipairs(p.chars) do
        local ch = chars[i]
        if ch then
            local r, g, b = classColor(ch.class)
            row:SetText(string.format("|cff%s%s|r  %s  |cff999999(%s)|r", hex(r, g, b),
                ch.name or "?", P.Km(ch.total), string.format(L.PEDO_TODAY_SHORT, P.Km(ch.days and ch.days[K.day] or 0))))
        else
            row:SetText("")
        end
    end
end

---------------------------------------------------------------------------
-- Onglet Guilde
---------------------------------------------------------------------------

local function buildGuild(page)
    local p = page
    p.title = text(p, "GameFontNormalLarge")
    p.title:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -10)
    p.title:SetText(L.PEDO_GUILD_TITLE)
    p.sub = text(p, "GameFontDisableSmall")
    p.sub:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -4)
    p.sub:SetText(L.PEDO_GUILD_SUB)
    local cols = { { "#", 12 }, { L.PEDO_COL_NAME, 48 }, { L.PEDO_COL_WEEK, 250 }, { L.PEDO_COL_TOTAL, 370 }, { L.PEDO_COL_CARDS, 490 } }
    for _, col in ipairs(cols) do
        local h = text(p, "GameFontNormalSmall")
        h:SetPoint("TOPLEFT", p, "TOPLEFT", col[2], -60)
        h:SetText(col[1])
    end
    p.rows = {}
    for i = 1, 14 do
        local row = CreateFrame("Frame", nil, p)
        row:SetSize(WIN_W - 24, 22)
        row:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -78 - (i - 1) * 24)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0.06)
        row.rank = text(row, "GameFontHighlight")
        row.rank:SetPoint("LEFT", 0, 0)
        row.name = text(row, "GameFontHighlight")
        row.name:SetPoint("LEFT", 36, 0)
        row.week = text(row, "GameFontHighlight")
        row.week:SetPoint("LEFT", 238, 0)
        row.total = text(row, "GameFontHighlight")
        row.total:SetPoint("LEFT", 358, 0)
        row.cards = text(row, "GameFontHighlight")
        row.cards:SetPoint("LEFT", 478, 0)
        row.see = ns.UI.Button(row, L.PEDO_SEE, 110, function(self)
            local e = self.entry
            if not e or not e.bits then return end
            view = { name = e.name, set = P.BitsToSet(e.bits) }
            B.page, B.sel = 1, nil
            selectTab("binder")
        end)
        row.see:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.see:SetHeight(20)
        p.rows[i] = row
    end
    p.empty = text(p, "GameFontHighlight")
    p.empty:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -110)
    p.empty:SetWidth(740)
    p.empty:SetJustifyH("LEFT")
    p.share = ns.UI.Check(p, L.PEDO_OPT_SHARE, function(v)
        if db() then db().opt.share = v end
        if v then P.Share(false) end
    end)
    p.share:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 8, 10)
end

local function refreshGuild(p)
    local list = P.GuildBoard()
    local _, all = P.OwnedCount()
    for i, row in ipairs(p.rows) do
        local e = list[i]
        if e then
            row:Show()
            row.rank:SetText(i)
            local r, g, b = classColor(e.class)
            row.name:SetText(shortName(e.name) .. (e.me and (" |cff999999" .. L.PEDO_ME .. "|r") or ""))
            row.name:SetTextColor(r, g, b)
            row.week:SetText(P.Km(e.week))
            row.total:SetText(P.Km(e.total, 0))
            row.cards:SetText(string.format("%d / %d", e.cards or 0, all))
            row.see.entry = e
            row.see:SetShown(not e.me and e.bits ~= nil and e.bits ~= "")
        else
            row:Hide()
        end
    end
    p.empty:SetShown(#list <= 1)
    p.empty:SetText(L.PEDO_GUILD_EMPTY)
    p.share:SetChecked(db() and db().opt.share or false)
end

---------------------------------------------------------------------------
-- Construction et rafraichissement
---------------------------------------------------------------------------

refreshPage = function()
    if not win or not win:IsShown() then return end
    for _, t in ipairs(tabs) do t:SetText(tabLabel(t.key)) end
    if win.shards then win.shards:SetText(string.format(L.PEDO_SHARDS, db() and db().shards or 0)) end
    local p = pages[current]
    if current == "binder" then refreshBinder(p)
    elseif current == "packs" then refreshPacks(p)
    elseif current == "stats" then refreshStats(p)
    elseif current == "guild" then refreshGuild(p) end
end
P.RefreshBinder = function() pcall(refreshPage) end
P.OnDataLoaded = function() pcall(refreshPage) end

local function build()
    local d = db()
    d.opt.pos = d.opt.pos or { point = "CENTER", x = 0, y = 30 }
    win = CreateFrame("Frame", "CorpUIBinder", UIParent)
    win:SetSize(WIN_W, WIN_H)
    ns.ApplyPos(win, d.opt.pos)
    win:SetFrameStrata("HIGH")
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    ns.UI.Skin(win, 0.97, true)
    win:Hide()
    -- barre de titre (glisser pour deplacer)
    local bar = CreateFrame("Frame", nil, win)
    bar:SetPoint("TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", 0, 0)
    bar:SetHeight(28)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() win:StartMoving() end)
    bar:SetScript("OnDragStop", function()
        win:StopMovingOrSizing()
        local point, _, _, x, y = win:GetPoint(1)
        d.opt.pos = { point = point or "CENTER", x = x or 0, y = y or 0 }
    end)
    local title = bar:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(title, 14)
    title:SetPoint("LEFT", 10, 0)
    title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    title:SetText(L.PEDO_BINDER)
    local close = CreateFrame("Button", nil, bar)
    close:SetSize(22, 22)
    close:SetPoint("RIGHT", -4, 0)
    local x = close:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    x:SetPoint("CENTER")
    x:SetText("×")
    close:SetScript("OnClick", function() win:Hide() end)
    win.shards = text(bar, "GameFontNormal")
    win.shards:SetPoint("RIGHT", close, "LEFT", -12, 0)
    -- onglets
    for i, key in ipairs({ "binder", "packs", "stats", "guild" }) do
        local t = ns.UI.Button(win, tabLabel(key), 130, function() selectTab(key) end)
        t:SetPoint("TOPLEFT", win, "TOPLEFT", 12 + (i - 1) * 138, -32)
        t.key = key
        t:HookScript("OnLeave", function(self)
            local on = self.key == current
            self:SetBackdropBorderColor((on and C.gold or C.border)[1], (on and C.gold or C.border)[2], (on and C.gold or C.border)[3], 1)
        end)
        tabs[i] = t
        local page = CreateFrame("Frame", nil, win)
        page:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -62)
        page:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 0)
        page:Hide()
        pages[key] = page
    end
    buildBinder(pages.binder)
    buildPacks(pages.packs)
    buildStats(pages.stats)
    buildGuild(pages.guild)
    win:SetScript("OnShow", function() selectTab(current) end)
    win:SetScript("OnHide", function()
        forgetNew()
        shownKey = nil
        -- ouverture interrompue : les cartes sont deja gagnees
        reveal = nil
    end)
end

function P.ToggleBinder(forceOpen, tab)
    if not db() then return end
    if not win then build() end
    if tab then current = tab end
    if win:IsShown() and not forceOpen and not tab then win:Hide() return end
    win:Show()
    if tab then selectTab(tab) end
end

function P.CloseBinder() if win then win:Hide() end end
function P.BinderShown() return win and win:IsShown() or false end

P.Listen(function(what)
    if what == "guild" and current ~= "guild" then
        -- seul l onglet Guilde en depend ; le titre des onglets ne change pas
        return
    end
    if win and win:IsShown() then
        -- pendant une ouverture, ne pas repeindre les cartes retournees
        if what == "open" then return end
        pcall(refreshPage)
    end
end)

---------------------------------------------------------------------------
-- Annonce (booster gagne, trophee) : en haut de l ecran, apres le combat
---------------------------------------------------------------------------

local toast
local queue = {}
local TOAST_TIME = 6

local function buildToast()
    toast = CreateFrame("Button", "CorpUIPedometerToast", UIParent)
    toast:SetSize(330, 64)
    toast:SetPoint("TOP", UIParent, "TOP", 0, -110)
    toast:SetFrameStrata("DIALOG")
    ns.UI.Skin(toast, 0.95, true)
    toast.icon = toast:CreateTexture(nil, "ARTWORK")
    toast.icon:SetPoint("LEFT", 8, 0)
    toast.title = text(toast, "GameFontNormal")
    toast.title:SetPoint("TOPLEFT", 64, -12)
    toast.title:SetPoint("RIGHT", -10, 0)
    toast.title:SetJustifyH("LEFT")
    toast.body = text(toast, "GameFontHighlight")
    toast.body:SetPoint("TOPLEFT", toast.title, "BOTTOMLEFT", 0, -4)
    toast.body:SetPoint("RIGHT", -10, 0)
    toast.body:SetJustifyH("LEFT")
    toast:SetScript("OnClick", function(self)
        self:Hide()
        P.ToggleBinder(true, self.tab)
    end)
    toast:SetScript("OnUpdate", function(self)
        local age = GetTime() - (self.at or 0)
        if age > TOAST_TIME then
            self:Hide()
        elseif age > TOAST_TIME - 1 then
            self:SetAlpha(TOAST_TIME - age)
        end
    end)
    toast:SetScript("OnHide", function()
        C_Timer.After(0.3, function() if P.ShowNextToast then P.ShowNextToast() end end)
    end)
    toast:Hide()
end

function P.ShowNextToast()
    if #queue == 0 or InCombatLockdown() then return end
    if not toast then buildToast() end
    if toast:IsShown() then return end
    local m = table.remove(queue, 1)
    toast.title:SetText(m.title)
    toast.body:SetText(m.body)
    if m.pack then
        toast.icon:SetSize(34, 52)
        toast.icon:SetTexture(MEDIA .. "booster")
        toast.icon:SetTexCoord(0, 1, 0, TEX_PACK)
    else
        toast.icon:SetSize(44, 44)
        toast.icon:SetTexture(m.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        toast.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    toast.tab = m.tab
    toast.at = GetTime()
    toast:SetAlpha(1)
    toast:Show()
    P.Sound(m.sound or "f_carillon")
end

function P.Announce(kind, data)
    local d = db()
    if not d then return end
    if kind == "pack" then
        if not d.opt.toast then return end
        queue[#queue + 1] = {
            pack = true, tab = "packs", sound = "f_carillon",
            title = string.format(L.PEDO_TOAST_PACK, L["PEDO_PACK_" .. string.upper(data.k)] or ""),
            body = P.WhyText(data),
        }
    elseif kind == "trophy" then
        if not d.opt.toast then return end
        queue[#queue + 1] = {
            tab = "binder", sound = "quest", icon = P.CardIcon(data),
            title = L.PEDO_TOAST_TROPHY, body = P.CardName(data),
        }
    end
    P.ShowNextToast()
end

local tev = CreateFrame("Frame")
tev:RegisterEvent("PLAYER_REGEN_ENABLED")
tev:SetScript("OnEvent", function() P.ShowNextToast() end)
