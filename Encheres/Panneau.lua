--[[--------------------------------------------------------------------------
    CorpUI - module Encheres : volet CorpUI de l hotel des ventes

    Notre cadre, colle a droite de la fenetre de Blizzard (sa taille, sa
    strate et son echelle sont lues, jamais changees), avec des onglets :
    Vente, Mes encheres, Achats, Compta (chaque fichier ajoute le sien par
    AH.AddTab). Bouton "CorpUI" a gauche de la barre de scan pour l ouvrir
    ou le fermer (choix garde). L onglet suit l onglet de Blizzard : Vendre
    -> Vente, Encheres -> Mes encheres, Acheter -> Achats (option).

    Ce client interdit aux addons de mettre en vente, d acheter, d encherir
    et d annuler : le volet analyse, conseille et lance des recherches ; le
    clic final se fait toujours sur les boutons de Blizzard.

    Outils communs aux onglets (ns.AH) : lecture prudente des champs de
    Blizzard, liste a defilement, ligne d objet, recherche dans l HV.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L
local C = ns.COLORS

local issecret = issecretvalue or function() return false end

local AH = ns.AH or {}
ns.AH = AH
AH.tabs = AH.tabs or {}

local W = 340            -- largeur du volet
AH.W = W
local TAB_H = 22         -- bande des onglets
local PAD = 8            -- marge interieure des pages

---------------------------------------------------------------------------
-- Outils
---------------------------------------------------------------------------

function AH.num(v)
    if not issecret(v) and type(v) == "number" and v == v then return v end
end

function AH.str(v)
    if not issecret(v) and type(v) == "string" then return v end
end

function AH.call(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end

-- champ d une table de Blizzard, lu seulement (jamais ecrit)
function AH.field(t, k)
    if type(t) ~= "table" then return nil end
    local ok, v = pcall(function() return t[k] end)
    if ok then return v end
end

function AH.visible(f)
    if type(f) ~= "table" or type(f.IsVisible) ~= "function" then return false end
    local ok, v = pcall(f.IsVisible, f)
    return ok and not issecret(v) and v == true
end

function AH.api()
    if type(C_AuctionHouse) == "table" then return C_AuctionHouse end
end

-- pas des prix de l HV : 1 pc si le client les accepte, sinon 1 pa
function AH.Step()
    local ah = AH.api()
    local ok = ah and AH.call(ah.SupportsCopperValues)
    return ok == true and 1 or 100
end

function AH.Money(c) return ns.AHMoney(c) end

-- couleur d une qualite d objet ("|cffxxxxxx") ou blanc
function AH.QualityHex(id)
    local q
    if C_Item and C_Item.GetItemQualityByID then q = AH.num(AH.call(C_Item.GetItemQualityByID, id)) end
    if not q and GetItemInfo then q = AH.num(select(3, AH.call(GetItemInfo, id))) end
    local colors = ITEM_QUALITY_COLORS
    local c = q and type(colors) == "table" and colors[q]
    local hex = c and AH.str(c.hex)
    return hex or "|cffffffff"
end

function AH.ItemLabel(id)
    local name = ns.ItemName(id)
    if name then return name end
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return "item:" .. tostring(id)
end

function AH.DB()
    return ns.AHDB and ns.AHDB()
end

-- texte simple
function AH.Text(parent, font, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- filet d or sous un intertitre
function AH.Header(parent, text, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
    fs:SetText(text)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    ns.NoSnap(line)
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y - 16)
    line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PAD, y - 16)
    ns.UI.Gradient(line, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.6, C.gold[1], C.gold[2], C.gold[3], 0)
    return fs, line
end

-- Liste a defilement (molette, filet a droite) : make(liste, i) cree une
-- ligne, fill(ligne, donnee, index) la remplit. liste:SetData(t).
function AH.List(parent, rowH, make, fill)
    local l = CreateFrame("Frame", nil, parent)
    l.rows, l.data, l.offset, l.rowH = {}, {}, 0, rowH
    l:EnableMouseWheel(true)
    local track = l:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("TOPRIGHT", 0, 0)
    track:SetPoint("BOTTOMRIGHT", 0, 0)
    track:SetWidth(3)
    track:SetColorTexture(1, 1, 1, 0.05)
    local thumb = l:CreateTexture(nil, "ARTWORK")
    thumb:SetWidth(3)
    thumb:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.7)
    function l:Visible()
        return math.max(1, math.floor((self:GetHeight() or rowH) / rowH))
    end
    function l:Refresh()
        local n = self:Visible()
        local maxOff = math.max(0, #self.data - n)
        if self.offset > maxOff then self.offset = maxOff end
        for i = 1, n do
            local row = self.rows[i]
            if not row then
                row = make(self, i)
                row:SetHeight(rowH)
                row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(i - 1) * rowH)
                row:SetPoint("RIGHT", self, "RIGHT", -6, 0)
                self.rows[i] = row
            end
            local item = self.data[self.offset + i]
            if item ~= nil then
                fill(row, item, self.offset + i)
                row:Show()
            else
                row:Hide()
            end
        end
        for i = n + 1, #self.rows do self.rows[i]:Hide() end
        if #self.data > n then
            local h = self:GetHeight() or (n * rowH)
            local th = math.max(12, h * n / #self.data)
            thumb:SetHeight(th)
            thumb:ClearAllPoints()
            thumb:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -(h - th) * self.offset / maxOff)
            thumb:Show()
            track:Show()
        else
            thumb:Hide()
            track:Hide()
        end
    end
    function l:SetData(data)
        self.data = data or {}
        self:Refresh()
    end
    l:SetScript("OnMouseWheel", function(self, d)
        local n = self:Visible()
        local maxOff = math.max(0, #self.data - n)
        local step = IsShiftKeyDown and IsShiftKeyDown() and n or 1
        self.offset = math.max(0, math.min(maxOff, self.offset - d * step))
        self:Refresh()
    end)
    return l
end

-- ligne d objet : icone, nom, texte de droite, sous-texte ; fond au survol
function AH.ItemRow(parent, h)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(h)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    ns.UI.Gradient(hl, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.25, C.violet[1], C.violet[2], C.violet[3], 0.02)
    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetAllPoints()
    row.stripe:SetColorTexture(1, 1, 1, 0.03)
    local frame = row:CreateTexture(nil, "ARTWORK")
    frame:SetSize(h - 6, h - 6)
    frame:SetPoint("LEFT", 2, 0)
    frame:SetColorTexture(0, 0, 0, 1)
    row.icon = row:CreateTexture(nil, "ARTWORK", nil, 1)
    row.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    row.icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.right = AH.Text(row, "GameFontHighlightSmall", "RIGHT")
    row.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, -3)
    row.name = AH.Text(row, "GameFontHighlightSmall", "LEFT")
    row.name:SetPoint("TOPLEFT", frame, "TOPRIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
    row.sub = AH.Text(row, "GameFontDisableSmall", "LEFT")
    row.sub:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 6, 0)
    row.sub:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row:SetScript("OnLeave", function() ns.HideTooltip() end)
    return row
end

-- infobulle d objet (celle du jeu, sur notre ligne)
function AH.ItemTip(owner, id, extra)
    local t = ns.Tooltip(owner, "ANCHOR_RIGHT")
    if not pcall(t.SetItemByID, t, id) then t:AddLine(AH.ItemLabel(id)) end
    for _, l in ipairs(extra or {}) do t:AddLine(l[1], l[2] or 1, l[3] or 1, l[4] or 1, true) end
    t:Show()
end

-- Recherche d un objet dans l HV : son nom dans la barre de recherche de
-- Blizzard, et une requete de liste si la liste des resultats est a
-- l ecran (sinon le joueur clique Rechercher). Aucun achat.
function AH.Search(id)
    if InCombatLockdown() then ns.Say(L.COMBAT_BLOCKED) return end
    local ahf = ns.AHFrame and ns.AHFrame()
    if not ahf then return end
    local name = ns.ItemName(id)
    if not name then return end
    local sbar = AH.field(ahf, "SearchBar")
    if not AH.visible(sbar) then ns.Say(L.SHOP_AH_BUY_TAB) return end
    local box = AH.field(sbar, "SearchBox")
    if type(box) == "table" and box.SetText then pcall(box.SetText, box, name) end
    if not AH.visible(AH.field(ahf, "BrowseResultsFrame")) then
        ns.Say(string.format(L.SHOP_AH_TYPED, name))
        return
    end
    local ah = AH.api()
    if not (ah and ah.SendBrowseQuery) then return end
    if ah.IsThrottledMessageSystemReady and AH.call(ah.IsThrottledMessageSystemReady) == false then
        ns.Say(L.SHOP_AH_BUSY)
        return
    end
    local E = Enum and Enum.AuctionHouseSortOrder
    pcall(ah.SendBrowseQuery, {
        searchString = name,
        sorts = { { sortOrder = (E and E.Price) or 0, reverseSort = false },
                  { sortOrder = (E and E.Name) or 1, reverseSort = false } },
        filters = {}, itemClassFilters = {},
    })
end

-- Montant saisi : "12po 50pa", "12g50s", "12.5" (or), "3pa", "75pc" ;
-- nil si illisible. Pourcentage ("80%") : renvoie nil, pourcentage.
function AH.ParseMoney(text)
    text = AH.str(text)
    if not text then return nil end
    text = strtrim(text:lower()):gsub(",", ".")
    if text == "" then return nil end
    local pct = text:match("^(%d+%.?%d*)%s*%%$")
    if pct then return nil, tonumber(pct) end
    local plainNum = text:match("^(%d+%.?%d*)$")
    if plainNum then return math.floor(tonumber(plainNum) * 10000 + 0.5) end
    -- unites : celles de la langue du jeu d abord, puis g/s/c et po/pa/pc
    local units = {}
    local function add(sym, mult)
        sym = AH.str(sym)
        if sym and sym ~= "" and not units[sym:lower()] then units[sym:lower()] = mult end
    end
    add(L.MONEY_G, 10000); add(L.MONEY_S, 100); add(L.MONEY_C, 1)
    add("g", 10000); add("s", 100); add("c", 1)
    add("po", 10000); add("pa", 100); add("pc", 1)
    local total, any = 0, false
    local rest = text:gsub("(%d+%.?%d*)%s*([^%d%s%.]+)", function(n, unit)
        local mult = units[unit]
        if not mult then return nil end
        total, any = total + tonumber(n) * mult, true
        return ""
    end)
    if any and strtrim(rest) == "" then return math.floor(total + 0.5) end
end

---------------------------------------------------------------------------
-- Onglets : AH.AddTab({ key, label = fonction, order, build(page),
-- refresh(page), show(page) }) ; page = cadre de l onglet (sa taille est
-- celle du volet sous la bande des onglets).
---------------------------------------------------------------------------

local side, closeBtn
local current
local tabBtns = {}

function AH.AddTab(def)
    table.insert(AH.tabs, def)
    table.sort(AH.tabs, function(a, b) return (a.order or 99) < (b.order or 99) end)
end

local function opts()
    local db = AH.DB()
    if not db then return nil end
    if type(db.side) ~= "table" then db.side = {} end
    local o = db.side
    if o.shown == nil then o.shown = true end
    if o.autoTab == nil then o.autoTab = true end
    return o
end

local function defOf(key)
    for _, d in ipairs(AH.tabs) do if d.key == key then return d end end
end

local function pageOf(def)
    if def.page then return def.page end
    local p = CreateFrame("Frame", nil, side)
    p:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -(TAB_H + 4))
    p:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", 0, 0)
    p:Hide()
    def.page = p
    if def.build then
        local ok, err = pcall(def.build, p)
        if not ok then geterrorhandler()(err) end
    end
    return p
end

local function paintTabs()
    for _, b in ipairs(tabBtns) do
        local on = b.def.key == current
        b.sel:SetShown(on)
        b.text:SetTextColor(on and C.gold[1] or C.text[1], on and C.gold[2] or C.text[2], on and C.gold[3] or C.text[3])
    end
end

local function refreshCurrent()
    local def = current and defOf(current)
    if def and def.page and def.page:IsShown() and def.refresh then
        local ok, err = pcall(def.refresh, def.page)
        if not ok then geterrorhandler()(err) end
    end
end

function AH.SelectTab(key)
    local def = defOf(key)
    if not (def and side) then return end
    for _, d in ipairs(AH.tabs) do
        if d.page and d ~= def then d.page:Hide() end
    end
    current = key
    local o = opts()
    if o then o.tab = key end
    local p = pageOf(def)
    p:Show()
    if def.show then
        local ok, err = pcall(def.show, p)
        if not ok then geterrorhandler()(err) end
    end
    paintTabs()
    refreshCurrent()
end

function AH.Current() return current end
function AH.Side() return side end

-- l onglet affiche se redessine (apres un changement de donnees)
function AH.Refresh(key)
    if side and side:IsShown() and (key == nil or key == current) then refreshCurrent() end
end

local function layoutTabs()
    local avail = W - 26
    local widths, sum = {}, 0
    for i, b in ipairs(tabBtns) do
        b.text:SetText(b.def.label())
        widths[i] = (b.text:GetStringWidth() or 40) + 14
        sum = sum + widths[i]
    end
    local k = sum > avail and avail / sum or 1
    local x = 2
    for i, b in ipairs(tabBtns) do
        local w = math.floor(widths[i] * k)
        b:SetWidth(w)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", side, "TOPLEFT", x, -2)
        x = x + w
    end
end

local function build()
    side = CreateFrame("Frame", "CorpUIAuctionSide", UIParent)
    side:SetSize(W, 420)
    side:EnableMouse(true)
    ns.UI.Skin(side, 0.96, true)
    side:Hide()
    local band = side:CreateTexture(nil, "BACKGROUND", nil, -5)
    band:SetPoint("TOPLEFT", 0, 0)
    band:SetPoint("TOPRIGHT", 0, 0)
    band:SetHeight(TAB_H + 2)
    ns.UI.Gradient(band, "VERTICAL", C.violet[1], C.violet[2], C.violet[3], 0.10, C.violet[1], C.violet[2], C.violet[3], 0.30)
    for _, def in ipairs(AH.tabs) do
        local b = CreateFrame("Button", nil, side)
        b:SetHeight(TAB_H)
        b.def = def
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.text:SetPoint("LEFT", 4, 0)
        b.text:SetPoint("RIGHT", -4, 0)
        b.text:SetWordWrap(false)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.06)
        b.sel = b:CreateTexture(nil, "ARTWORK")
        b.sel:SetPoint("BOTTOMLEFT", 2, 0)
        b.sel:SetPoint("BOTTOMRIGHT", -2, 0)
        b.sel:SetHeight(2)
        b.sel:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
        b:SetScript("OnClick", function(self) AH.SelectTab(self.def.key) end)
        table.insert(tabBtns, b)
    end
    closeBtn = CreateFrame("Button", nil, side)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", side, "TOPRIGHT", -2, -2)
    local x = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    x:SetPoint("CENTER")
    x:SetText("×")
    closeBtn:SetScript("OnClick", function()
        local o = opts()
        if o then o.shown = false end
        side:Hide()
    end)
    closeBtn:SetScript("OnEnter", function(self)
        local t = ns.Tooltip(self, "ANCHOR_TOP")
        t:AddLine(L.AHP_CLOSE, 1, 1, 1, true)
        t:Show()
    end)
    closeBtn:SetScript("OnLeave", function() ns.HideTooltip() end)
    layoutTabs()
end

-- mode d affichage de Blizzard, d apres ses sous-fenetres visibles
local function blizzMode(ahf)
    if AH.visible(AH.field(ahf, "CommoditiesSellFrame")) or AH.visible(AH.field(ahf, "ItemSellFrame")) then return "sell" end
    if AH.visible(AH.field(ahf, "AuctionsFrame")) then return "mine" end
    return "buy"
end

local lastMode
local acc = 0

local function place(ahf)
    if side.anchoredTo ~= ahf then
        side:ClearAllPoints()
        side:SetPoint("TOPLEFT", ahf, "TOPRIGHT", 4, 0)
        side.anchoredTo = ahf
    end
    local ok, h = pcall(ahf.GetHeight, ahf)
    h = ok and AH.num(h)
    if h and h > 200 and math.abs((side:GetHeight() or 0) - h) > 0.5 then side:SetHeight(h) end
    if ns.AHFollow then ns.AHFollow(side, ahf) end
end

local function tick()
    local ahf = ns.AHFrame and ns.AHFrame()
    local o = opts()
    if not (ahf and o) then
        if side and side:IsShown() then side:Hide() end
        lastMode = nil
        return
    end
    if not o.shown then return end
    if not side then build() end
    place(ahf)
    if not side:IsShown() then
        side:Show()
        lastMode = nil
    end
    -- onglet de Blizzard change : Vendre -> Vente, Encheres -> Mes
    -- encheres, retour a Acheter -> Achats (option) ; a l ouverture sans
    -- l option : le dernier onglet
    local mode = blizzMode(ahf)
    if mode ~= lastMode then
        local first = lastMode == nil
        lastMode = mode
        local want
        if o.autoTab then
            if mode == "sell" or mode == "mine" then
                want = mode
            elseif first or current == "sell" or current == "mine" then
                want = "buy"
            end
        end
        if first and not want then want = (o.tab and defOf(o.tab)) and o.tab or "buy" end
        if want and (want ~= current or first) then AH.SelectTab(want) return end
    end
    refreshCurrent()
end

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.25 then return end
    acc = 0
    tick()
end)

-- bouton "CorpUI" a gauche de la barre de scan
ns.AHBarHooks = ns.AHBarHooks or {}
table.insert(ns.AHBarHooks, function(bar)
    local b = ns.UI.Button(bar, ns.TITLE or "CorpUI", 70, function()
        local o = opts()
        if not o then return end
        o.shown = not (side and side:IsShown())
        if not o.shown and side then side:Hide() end
        acc = 0
        tick()
    end)
    b:SetHeight(20)
    b:SetPoint("RIGHT", bar, "LEFT", -4, 0)
    b:HookScript("OnEnter", function(self)
        local t = ns.Tooltip(self, "ANCHOR_TOP")
        t:AddLine(ns.TITLE or "CorpUI")
        t:AddLine(L.AHP_TOGGLE_TIP, 1, 1, 1, true)
        t:Show()
    end)
    b:HookScript("OnLeave", function() ns.HideTooltip() end)
    bar.sideButton = b
end)

-- tableau de bord de test (bancs hors jeu)
AH._tick = tick
