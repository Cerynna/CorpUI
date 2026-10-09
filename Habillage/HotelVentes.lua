--[[--------------------------------------------------------------------------
    CorpUI - module Habillage : hotel des ventes en profondeur
    (AuctionHouseFrame de Blizzard_AuctionHouseUI, variante Camelot de ce
    client, famille Mainline)

    Skins.lua pose deja le fond, le lisere, le bandeau, le titre et la croix
    de la fenetre ; ici on reprend tout l interieur :
      - onglets du bas (Acheter / Vendre / Ventes) : plaques plates, l actif
        dans toute la bande de la barre CorpUI "Dernier scan | Scanner",
        lisere d or et filet d or ; les inactifs plus courts, centres sur
        leur texte ; onglets du haut des Ventes sur le meme principe ;
      - barre de recherche : champ habille (loupe en or), bouton Filtrer,
        etoile des favoris et bouton Rechercher en plaques plates de 22 px ;
      - categories : plaques pour les categories, plus sombres et decalees
        pour les sous-categories, choix en degrade d accent avec une barre
        d or, survol en degrade ;
      - listes de prix : panneau sombre, bandeau d en-tetes en degrade et
        filet d or, titres de colonnes et fleche de tri en or, alternance
        discrete des lignes, ligne choisie en degrade avec barre d or,
        icones carrees au lisere de la qualite, bouton rafraichir ;
      - pages d achat et de vente : cartes d objet (icone carree, lisere de
        qualite), champs de quantite et de prix, case a cocher (libelle a
        la couleur du texte de CorpUI, plus le jaune de Blizzard), boutons
        Acheter / Mettre en vente / Retour / Max en plaques (le menu de
        duree est un menu a fleche, repris par Communs.lua) ;
      - page des ventes : resume a gauche, listes, onglets du haut ;
      - cadre d argent et dialogue d achat des marchandises.
    Les couleurs de qualite et de prix de Blizzard restent (information de
    jeu). Aucun texte visible n est ajoute.

    Regles de ce client (taint, valeurs secretes). Cette fenetre appelle des
    fonctions protegees (achat, enchere, mise en vente, annulation) depuis
    les scripts de ses boutons : le moindre ecart bloquerait l hotel. Donc :
      - aucun crochet (hooksecurefunc, HookScript), aucun SetScript, aucun
        attribut, aucun champ ecrit dans un cadre ou une table de Blizzard
        (lignes de listes comprises) : nos textures sont rangees dans des
        tables faibles a nous, indexees par le cadre ;
      - aucune taille, position, strate, niveau ou parent de Blizzard
        modifie, aucun Show / Hide de leurs objets : seulement l alpha, la
        couleur, la desaturation, le recadrage d icones, le retrait d un
        masque, la couleur de quelques textes, et nos propres textures ;
      - aucune fonction Lua de Blizzard appelee : seulement des accesseurs du
        moteur (IsShown, GetAtlas, GetText...) et la lecture de champs ;
      - rien dans les champs de saisie lus par les achats et les ventes, ni
        sur les polices des boutons qui achetent, vendent ou annulent ;
      - tout passe par un releve periodique quand la fenetre est ouverte,
        rien en combat ; toute valeur lue est verifiee (pcall, issecretvalue).
    Skins.lua ne descend plus dans la fenetre (ns.SkinClaimed) : il garde
    seulement son fond, son cadre, son titre et sa croix.
----------------------------------------------------------------------------]]

local _, ns = ...

local issecret = issecretvalue or function() return false end
local weak = { __mode = "k" }

local mine = setmetatable({}, weak)      -- nos regions (a ne jamais traiter)
local done = setmetatable({}, weak)      -- textures de Blizzard deja traitees (atlas)
local claimed = setmetatable({}, weak)   -- cadres repris ici
local plates = setmetatable({}, weak)    -- bouton aplati -> { fill, edges, hl }
local tabs = setmetatable({}, weak)      -- onglet -> { fill, accent, edges, line, text }
local cats = setmetatable({}, weak)      -- bouton de categorie -> { fill, edges, sel, bar, kind }
local rows = setmetatable({}, weak)      -- ligne de liste -> { zebra, sel, bar, hov2 }
local sums = setmetatable({}, weak)      -- ligne du resume des ventes -> { sel, bar, icone }
local cells = setmetatable({}, weak)     -- cellule a icone -> { fill, edges, icon, border, text }
local boxes = setmetatable({}, weak)     -- grosse icone d objet -> { fill, edges, icon, border }
local heads = setmetatable({}, weak)     -- titre de colonne -> { text, arrow }
local bands = setmetatable({}, weak)     -- conteneur des titres -> { band, line }
local surfaces = setmetatable({}, weak)  -- panneau (liste, page, carte) -> true
local edits = setmetatable({}, weak)     -- champ de saisie ou menu -> { fill, edges }
local checks = setmetatable({}, weak)    -- case a cocher -> { edges, mark }
local bars = setmetatable({}, weak)      -- barre de defilement -> { thumb, knob }
local golds = setmetatable({}, weak)     -- textures a teinter en or (Blizzard repose l atlas)
local masked = setmetatable({}, weak)    -- icone dont le masque est retire
local sellTabs = setmetatable({}, weak)  -- page de vente -> notre onglet "Creer une enchere"
local panels = setmetatable({}, weak)    -- cadre d argent, dialogue -> true
local pools = setmetatable({}, weak)     -- conteneurs de cadres recycles (ScrollTarget, titres) -> true

-- decors reconnus par leur atlas
local ATLAS = {
    ["auctionhouse-itemheaderframe"] = "fade",
    ["auctionhouse-itemicon-empty"] = "fade",
    -- menu de duree (fond common-dropdown-textholder, fleche
    -- common-dropdown-a-button) : repris par Communs.lua
}
-- reconnus par le debut de l atlas
local PREFIX = {
    { "^auctionhouse%-background%-", "fade" },
    { "^auctionhouse%-selltab%-", "fade" },
    { "^common%-search%-border", "fade" },
    { "^common%-dropdown%-b%-button", "dropdown" },  -- bouton Filtrer (l atlas suit l etat)
}

-- bordure de qualite d un bouton d objet : couleur lue dans le nom de l atlas
local BORDER_Q = { gray = 0, white = 1, green = 2, blue = 3, purple = 4, orange = 5, artifact = 6, account = 7 }

-- sous-cadres de la fenetre laisses a Skins.lua ou repris a part
local SKIP_KEYS = { "NineSlice", "PortraitContainer", "TitleContainer", "CloseButton", "DummyMoneyDisplayFrame",
                    "MoneyFrameInset", "MoneyFrameBorder" }

-- sous-cadres dont l affichage relance un parcours complet
local PAGE_KEYS = { "CategoriesList", "BrowseResultsFrame", "CommoditiesBuyFrame", "ItemBuyFrame", "ItemSellFrame",
                    "CommoditiesSellFrame", "AuctionsFrame", "BuyDialog", "WoWTokenResults" }
local AUCTION_KEYS = { "AllAuctionsList", "BidsList", "ItemList", "CommoditiesList", "ItemDisplay" }

local function db()
    local d = ns.skinsDB
    if type(d) ~= "table" or not d.enabled then return nil end
    if d.groups and d.groups.trade == false then return nil end
    return d
end

---------------------------------------------------------------------------
-- Outils
---------------------------------------------------------------------------

local function isTrue(v)
    if issecret(v) then return false end
    return v == true
end

local function objType(o)
    if type(o) ~= "table" or not o.GetObjectType then return nil end
    local ok, t = pcall(o.GetObjectType, o)
    if ok and not issecret(t) and type(t) == "string" then return t end
end

-- lectures protegees sans fermeture neuve a chaque appel (le releve en
-- fait des milliers par seconde) : une seule fonction, passee a pcall
local function get(f, key) return f[key] end
local function packRegions(f) return { f:GetRegions() } end
local function packChildren(f) return { f:GetChildren() } end

local function field(f, key)
    if type(f) ~= "table" then return nil end
    local ok, c = pcall(get, f, key)
    if ok and type(c) == "table" then return c end
end

-- champ simple (texte, booleen, nombre), jamais secret
local function value(f, key)
    if type(f) ~= "table" then return nil end
    local ok, v = pcall(get, f, key)
    if not ok or issecret(v) then return nil end
    local t = type(v)
    if t == "string" or t == "boolean" or t == "number" then return v end
end

local function hasFn(f, key)
    if type(f) ~= "table" then return false end
    local ok, v = pcall(get, f, key)
    return ok and type(v) == "function"
end

local function isTex(o) return objType(o) == "Texture" end

local function fade(obj)
    if type(obj) == "table" and obj.SetAlpha and not mine[obj] then pcall(obj.SetAlpha, obj, 0) end
end

-- texture dont Blizzard repose l alpha : eteinte par la couleur
local function douse(t)
    if type(t) == "table" and t.SetVertexColor and not mine[t] then pcall(t.SetVertexColor, t, 0, 0, 0, 0) end
end

local function num(v)
    if issecret(v) or type(v) ~= "number" then return nil end
    return v
end

local function visible(f)
    if type(f) ~= "table" or not f.IsVisible then return false end
    local ok, v = pcall(f.IsVisible, f)
    return ok and isTrue(v)
end

local function shown(f)
    if type(f) ~= "table" or not f.IsShown then return false end
    local ok, v = pcall(f.IsShown, f)
    return ok and isTrue(v)
end

local function isOver(f)
    if type(f) ~= "table" or not f.IsMouseOver then return false end
    local ok, v = pcall(f.IsMouseOver, f)
    return ok and isTrue(v)
end

local function enabled(f)
    if type(f) ~= "table" or not f.IsEnabled then return true end
    local ok, v = pcall(f.IsEnabled, f)
    if not ok or issecret(v) then return true end
    return v ~= false
end

local function regionsOf(f)
    if type(f) ~= "table" or not f.GetRegions then return {} end
    local ok, list = pcall(packRegions, f)
    return ok and list or {}
end

local function childrenOf(f)
    if type(f) ~= "table" or not f.GetChildren then return {} end
    local ok, list = pcall(packChildren, f)
    return ok and list or {}
end

local function atlasOf(t)
    if type(t) ~= "table" or not t.GetAtlas then return nil end
    local ok, a = pcall(t.GetAtlas, t)
    if ok and not issecret(a) and type(a) == "string" then return a end
end

-- icone recadree (jamais sur un atlas : on casserait ses coordonnees)
local function cropIcon(icon)
    if objType(icon) ~= "Texture" or atlasOf(icon) then return end
    pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
end

-- textures d un cadre (pas celles de ses enfants), sauf les notres
local function fadeOwn(f)
    for _, r in ipairs(regionsOf(f)) do
        if not mine[r] and objType(r) == "Texture" then fade(r) end
    end
end

-- textures d etat d un bouton (normale, enfoncee, survol...)
local function fadeStates(b, list)
    for _, get in ipairs(list or { "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture",
                                   "GetDisabledTexture", "GetCheckedTexture", "GetDisabledCheckedTexture" }) do
        if type(b) == "table" and b[get] then
            local ok, t = pcall(b[get], b)
            if ok then fade(t) end
        end
    end
end

local function tex(host, layer, sub)
    local t = host:CreateTexture(nil, layer, nil, sub)
    mine[t] = true
    return t
end

-- quatre filets de 1 px autour de "anchor" (sur "host"), "out" px en dehors
local function ring(host, anchor, layer, sub, out)
    local list = {}
    local function line()
        local x = tex(host, layer, sub)
        list[#list + 1] = x
        return x
    end
    local top = line()
    top:SetPoint("TOPLEFT", anchor, "TOPLEFT", -out, out)
    top:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", out, out)
    top:SetHeight(1)
    local bottom = line()
    bottom:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", -out, -out)
    bottom:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", out, -out)
    bottom:SetHeight(1)
    local left = line()
    left:SetPoint("TOPLEFT", anchor, "TOPLEFT", -out, out)
    left:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", -out, -out)
    left:SetWidth(1)
    local right = line()
    right:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", out, out)
    right:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", out, -out)
    right:SetWidth(1)
    return list
end

local function paint(list, r, g, b, a)
    for _, x in ipairs(list) do x:SetColorTexture(r, g, b, a or 1) end
end

local function paintC(list, c, a) paint(list, c[1], c[2], c[3], a) end

-- lisere repeint seulement quand sa couleur change (releve frequent)
local function tint(s, c, a)
    a = a or 1
    if s.ec == c and s.ea == a then return end
    s.ec, s.ea = c, a
    paintC(s.edges, c, a)
end

local function showAll(list, on)
    for _, x in ipairs(list) do x:SetShown(on) end
end

-- carre sombre + lisere autour de "anchor"
local function box(host, anchor, out)
    local C = ns.COLORS
    local fill = tex(host, "BACKGROUND", -8)
    fill:SetPoint("TOPLEFT", anchor, "TOPLEFT", -out, out)
    fill:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", out, -out)
    fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.9)
    local edges = ring(host, anchor, "OVERLAY", 7, out)
    paintC(edges, C.border)
    return { fill = fill, edges = edges }
end

-- panneau (fond, lisere) sur "host", aux dimensions de "anchor"
local function backdrop(host, anchor, c, alpha)
    local C = ns.COLORS
    local fill = tex(host, "BACKGROUND", -8)
    fill:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    fill:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
    fill:SetColorTexture(c[1], c[2], c[3], alpha)
    local edges = ring(host, fill, "BACKGROUND", -7, 0)
    paintC(edges, C.border)
    return { fill = fill, edges = edges }
end

-- police des titres + or ; on retient la police posee pour la reposer si
-- Blizzard change d objet de police
local function goldFont(fs, size)
    if objType(fs) ~= "FontString" then return nil end
    local C = ns.COLORS
    pcall(ns.UI.HeadFont, fs, size)
    pcall(fs.SetTextColor, fs, C.gold[1], C.gold[2], C.gold[3])
    local ok, file = pcall(fs.GetFont, fs)
    return { fs = fs, size = size, file = (ok and not issecret(file) and type(file) == "string") and file or nil }
end

local function keepGold(h)
    if not h or not h.fs then return end
    local ok, file = pcall(h.fs.GetFont, h.fs)
    if ok and not issecret(file) and type(file) == "string" and h.file and file ~= h.file then
        pcall(ns.UI.HeadFont, h.fs, h.size)
    end
    local C = ns.COLORS
    pcall(h.fs.SetTextColor, h.fs, C.gold[1], C.gold[2], C.gold[3])
end

local function goldTint(t)
    local C = ns.COLORS
    pcall(t.SetDesaturated, t, true)
    pcall(t.SetVertexColor, t, C.gold[1], C.gold[2], C.gold[3], 1)
end

local function qualityColor(q)
    q = num(q)
    if not q or q < 2 then return nil end
    local fn = C_Item and C_Item.GetItemQualityColor
    if fn then
        local ok, r, g, b = pcall(fn, q)
        if ok and num(r) and num(g) and num(b) then return r, g, b end
    end
    if GetItemQualityColor then
        local ok, r, g, b = pcall(GetItemQualityColor, q)
        if ok and num(r) and num(g) and num(b) then return r, g, b end
    end
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if type(c) == "table" and num(c.r) then return c.r, c.g, c.b end
end

-- couleur de la bordure de qualite de Blizzard (cachee par l alpha) :
-- atlas "...-border-purple", sinon sa couleur de sommet (hors blanc)
local function borderColor(ib)
    if not shown(ib) then return nil end
    local a = atlasOf(ib)
    if a then
        local q = BORDER_Q[(a:match("%-(%a+)$") or ""):lower()]
        if q then return qualityColor(q) end
    end
    if ib.GetVertexColor then
        local ok, r, g, b = pcall(ib.GetVertexColor, ib)
        r, g, b = ok and num(r), ok and num(g), ok and num(b)
        if r and g and b and not (r > 0.95 and g > 0.95 and b > 0.95) then return r, g, b end
    end
end

-- texte d un FontString (false si absent ou secret)
local function textOf(fs)
    if objType(fs) ~= "FontString" then return false end
    local ok, t = pcall(fs.GetText, fs)
    if not ok or issecret(t) or type(t) ~= "string" then return false end
    return t
end

-- couleur de qualite d un nom d objet : code "|cffRRGGBB" de Blizzard (ou
-- "|cnIQ4:") ; blanc et gris gardent le lisere du theme
local function colorIn(t)
    if not t then return nil end
    local q = t:match("|cnIQ(%d+):")
    if q then return qualityColor(tonumber(q)) end
    local r, g, b = t:match("|c%x%x(%x%x)(%x%x)(%x%x)")
    if not r then return nil end
    r, g, b = tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
    if math.max(r, g, b) - math.min(r, g, b) < 0.08 then return nil end
    return r, g, b
end

---------------------------------------------------------------------------
-- Boutons, cases, champs
---------------------------------------------------------------------------

-- plaque plate sous un bouton (textures a nous, au fond du bouton) ;
-- "vin" : retrait vertical s il differe (negatif : la plaque deborde)
local function plate(b, inset, vin)
    if plates[b] then return plates[b] end
    if type(b) ~= "table" or not b.CreateTexture then return nil end
    local C = ns.COLORS
    vin = vin or inset
    local p = {}
    p.fill = tex(b, "BACKGROUND", -8)
    p.fill:SetPoint("TOPLEFT", b, "TOPLEFT", inset, -vin)
    p.fill:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -inset, vin)
    p.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.95)
    p.edges = ring(b, p.fill, "BACKGROUND", -7, 0)
    paintC(p.edges, C.border)
    p.hl = tex(b, "HIGHLIGHT")
    p.hl:SetAllPoints(p.fill)
    ns.UI.Gradient(p.hl, "VERTICAL", C.violet[1], C.violet[2], C.violet[3], 0.05, C.violet[1], C.violet[2], C.violet[3], 0.28)
    plates[b] = p
    claimed[b] = true
    return p
end

-- bouton rouge de Blizzard (Acheter, Mettre en vente, Retour, Max...) :
-- ses trois morceaux a alpha 0, notre plaque dessous ; texte et police
-- intouches ; "vin" : retrait vertical (1 par defaut)
local function panelButton(b, vin)
    if plates[b] then return end
    for _, k in ipairs({ "Left", "Middle", "Right" }) do fade(field(b, k)) end
    fadeStates(b, { "GetHighlightTexture" })
    plate(b, 1, vin or 1)
end

-- bouton carre a icone (etoile des favoris, rafraichir) : l icone reste
local function iconButton(b)
    if plates[b] or type(b) ~= "table" or not b.CreateTexture then return end
    fadeStates(b, { "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" })
    plate(b, 5)
end

-- case a cocher : carre sombre, lisere, coche d or (textures a nous)
local function skinCheck(cb, size)
    if checks[cb] or not cb.GetChecked or not cb.CreateTexture then return end
    fadeStates(cb)
    local C = ns.COLORS
    local fill = tex(cb, "BACKGROUND", -8)
    fill:SetSize(size, size)
    fill:SetPoint("CENTER", cb, "CENTER", 0, 0)
    fill:SetColorTexture(0, 0, 0, 0.6)
    local edges = ring(cb, fill, "BORDER", 7, 0)
    paintC(edges, C.border)
    local mark = tex(cb, "OVERLAY", 7)
    mark:SetPoint("TOPLEFT", fill, "TOPLEFT", 3, -3)
    mark:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", -3, 3)
    ns.UI.Gradient(mark, "VERTICAL", C.gold[1] * 0.75, C.gold[2] * 0.75, C.gold[3] * 0.75, 1, C.gold[1], C.gold[2], C.gold[3], 1)
    mark:Hide()
    checks[cb] = { edges = edges, mark = mark }
    -- libelle de UICheckButtonTemplate (Mode achat immediat : GameFontNormal
    -- jaune pose par Blizzard) : couleur du texte de CorpUI dans checkState
    local label = field(cb, "Text") or field(cb, "text")
    if objType(label) == "FontString" then checks[cb].label = label end
    claimed[cb] = true
end

-- fond sombre et lisere d un champ, ancres sur le champ
local function fieldBox(e, l, t, r, b)
    local C = ns.COLORS
    local fill = tex(e, "BACKGROUND", -8)
    fill:SetPoint("TOPLEFT", e, "TOPLEFT", l, t)
    fill:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT", r, b)
    fill:SetColorTexture(0, 0, 0, 0.55)
    local edges = ring(e, fill, "BACKGROUND", -7, 0)
    paintC(edges, C.border)
    edits[e] = { fill = fill, edges = edges }
    claimed[e] = true
    return edits[e]
end

-- champ de recherche (SearchBoxTemplate) : bords a alpha 0, loupe en or
local function searchEdit(e)
    for _, k in ipairs({ "Left", "Middle", "Mid", "Right" }) do fade(field(e, k)) end
    fieldBox(e, -5, 0, 0, 0)
    -- Blizzard repose sa couleur a chaque prise / perte du focus : releve
    local glass = field(e, "searchIcon") or field(e, "SearchIcon")
    if glass then
        golds[glass] = true
        goldTint(glass)
    end
end

-- grand champ (LargeInputBoxTemplate : quantite, or / argent / cuivre) :
-- notre fond suit la zone de texte (le bas du champ est reserve)
local function largeEdit(e)
    for _, k in ipairs({ "Left", "Middle", "Right" }) do fade(field(e, k)) end
    local itop, ibot = 0, 5
    local ok, _, _, t, b = pcall(e.GetTextInsets, e)
    if ok and num(t) and num(b) then itop, ibot = t, b end
    local okH, h = pcall(e.GetHeight, e)
    h = okH and num(h) or 33
    local th = math.max(0, h - itop - ibot)
    local fh = math.min(th, 22)
    local m = math.floor((th - fh) / 2 + 0.5)
    fieldBox(e, 1, -(itop + m), -1, ibot + m)
end

-- petit champ d argent (MoneyInputFrameTemplate : enchere) : morceaux en
-- minuscules (left, right et un milieu sans cle), la piece reste
local function moneyEdit(e)
    local coin = field(e, "texture")
    for _, r in ipairs(regionsOf(e)) do
        if r ~= coin and not mine[r] and objType(r) == "Texture" then fade(r) end
    end
    local l, r = field(e, "left"), field(e, "right")
    local C = ns.COLORS
    local fill = tex(e, "BACKGROUND", -8)
    fill:SetPoint("TOPLEFT", l, "TOPLEFT", 0, 0)
    fill:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
    fill:SetColorTexture(0, 0, 0, 0.55)
    local edges = ring(e, fill, "BACKGROUND", -7, 0)
    paintC(edges, C.border)
    edits[e] = { fill = fill, edges = edges }
    claimed[e] = true
end

local function editBox(e)
    if edits[e] or not e.CreateTexture then return end
    if field(e, "Left") and field(e, "Right") then
        if field(e, "searchIcon") or field(e, "SearchIcon") or field(e, "Instructions") then
            searchEdit(e)
        else
            largeEdit(e)
        end
    elseif field(e, "left") and field(e, "right") then
        moneyEdit(e)
    end
end

---------------------------------------------------------------------------
-- Onglets (bas de la fenetre, haut de la page des ventes)
---------------------------------------------------------------------------

-- PanelTabButtonTemplate : toutes ses textures a alpha 0 (jamais leurs
-- coordonnees : celles du haut sont retournees par Blizzard), notre plaque.
-- Blizzard deplace son texte selon l etat (PanelTemplates_SelectTab /
-- DeselectTab : bas +2 inactif, -3 actif ; haut -8 inactif, -4 actif, sur
-- un onglet de 32 px et un texte de 10 px) : le texte n est jamais touche,
-- ce sont nos ancres qui le suivent (placeTab, a chaque changement d etat).
--   - onglets du bas (ils se chevauchent de 15 px) : haut de la plaque
--     colle a la fenetre, a -1 comme le lisere de la barre CorpUI
--     "Dernier scan | Scanner" ; actif : toute la bande de la barre (-1 a
--     -27 sous la fenetre) ; inactif : plaque plus courte, centree sur le
--     texte (en retrait, comme chez Blizzard) ;
--   - onglets du haut (page des ventes) : actif : du texte au haut des
--     listes (2 px au-dessus du bas de l onglet), texte centre ; inactif :
--     plaque plus courte centree sur le texte, qui descend jusqu au bas de
--     l onglet (comme l art de Blizzard).
local function placeTab(t, s, active)
    local f = s.fill
    local txt = objType(s.text) == "FontString" and s.text or nil
    f:ClearAllPoints()
    if s.top then
        f:SetPoint("LEFT", t, "LEFT", 1, 0)
        f:SetPoint("RIGHT", t, "RIGHT", -1, 0)
        if not txt then
            f:SetPoint("TOP", t, "TOP", 0, active and -10 or -16)
            f:SetPoint("BOTTOM", t, "BOTTOM", 0, active and 2 or 0)
        elseif active then
            f:SetPoint("TOP", txt, "TOP", 0, 5)
            f:SetPoint("BOTTOM", t, "BOTTOM", 0, 2)
        else
            f:SetPoint("TOP", txt, "TOP", 0, 3)
            f:SetPoint("BOTTOM", txt, "BOTTOM", 0, -3)
        end
    else
        f:SetPoint("LEFT", t, "LEFT", 8, 0)
        f:SetPoint("RIGHT", t, "RIGHT", -9, 0)
        f:SetPoint("TOP", t, "TOP", 0, -5)
        if active or not txt then
            f:SetPoint("BOTTOM", t, "BOTTOM", 0, 1)
        else
            f:SetPoint("BOTTOM", txt, "BOTTOM", 0, -4)
        end
    end
end

local function skinTab(t)
    fadeOwn(t)
    if tabs[t] or not t.CreateTexture then return end
    local C = ns.COLORS
    local top = isTrue(value(t, "isTopTab"))
    local s = { top = top }
    s.fill = tex(t, "BACKGROUND", -8)
    s.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.95)
    s.accent = tex(t, "BACKGROUND", -7)
    s.accent:SetAllPoints(s.fill)
    ns.UI.Gradient(s.accent, "VERTICAL", C.violet[1], C.violet[2], C.violet[3], 0.05, C.violet[1], C.violet[2], C.violet[3], 0.38)
    s.accent:Hide()
    s.edges = ring(t, s.fill, "BACKGROUND", -6, 0)
    paintC(s.edges, C.border)
    s.line = tex(t, "BACKGROUND", -5)
    s.line:SetPoint("TOPLEFT", s.fill, "TOPLEFT", 0, 0)
    s.line:SetPoint("TOPRIGHT", s.fill, "TOPRIGHT", 0, 0)
    s.line:SetHeight(2)
    s.line:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    s.line:Hide()
    -- survol : calque HIGHLIGHT (l onglet actif est desactive, sans survol)
    s.hl = tex(t, "HIGHLIGHT")
    s.hl:SetAllPoints(s.fill)
    ns.UI.Gradient(s.hl, "VERTICAL", C.violet[1], C.violet[2], C.violet[3], 0.04, C.violet[1], C.violet[2], C.violet[3], 0.25)
    s.text = field(t, "Text")
    s.act = shown(field(t, "LeftActive"))
    placeTab(t, s, s.act)
    tabs[t] = s
    claimed[t] = true
end

-- actif : textures "Active" montrees par Blizzard (PanelTemplates_SelectTab)
local function tabState(t, s)
    local C = ns.COLORS
    local active = shown(field(t, "LeftActive"))
    if active ~= s.act then
        s.act = active
        placeTab(t, s, active)
    end
    local over = not active and isOver(t)
    s.accent:SetShown(active)
    s.line:SetShown(active)
    tint(s, active and C.gold or (over and C.violet or C.border))
    if objType(s.text) == "FontString" then
        local c = active and C.gold or (over and { 1, 1, 1 } or C.text)
        pcall(s.text.SetTextColor, s.text, c[1], c[2], c[3])
    end
end

---------------------------------------------------------------------------
-- Categories (boutons recycles de la liste de gauche)
---------------------------------------------------------------------------

-- Blizzard refait atlas, taille, ancrage et alpha de leurs textures a
-- chaque recyclage (AuctionHouseFilterButton_SetUp) mais jamais la
-- couleur : elles sont eteintes par la couleur, a chaque releve.
local CAT_X = { category = 0, subCategory = 10, subSubCategory = 18 }

local function placeCat(b, s, kind)
    local C = ns.COLORS
    s.fill:ClearAllPoints()
    s.fill:SetPoint("TOPLEFT", b, "TOPLEFT", CAT_X[kind] or 0, -1)
    s.fill:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 1)
    s.sub = kind == "subCategory"
    s.plain = kind == "subSubCategory"
    if s.sub then
        s.fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.9)
    else
        s.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.95)
    end
    s.fill:SetShown(not s.plain)
    showAll(s.edges, not s.plain)
    s.ec = nil
end

local function catState(b, s)
    local C = ns.COLORS
    local selTex = field(b, "SelectedTexture")
    douse(field(b, "NormalTexture"))
    douse(selTex)
    douse(field(b, "HighlightTexture"))
    local kind = value(b, "type")
    if kind ~= s.kind then
        s.kind = kind
        placeCat(b, s, kind)
    end
    local sel = shown(selTex)
    s.sel:SetShown(sel)
    s.bar:SetShown(sel)
    if not s.plain then
        if sel then tint(s, C.gold) else tint(s, C.border, s.sub and 0.7 or 1) end
    end
end

local function category(b)
    if cats[b] or not b.CreateTexture then return end
    local C = ns.COLORS
    local s = {}
    s.fill = tex(b, "BACKGROUND", -8)
    s.edges = ring(b, s.fill, "BACKGROUND", -7, 0)
    s.sel = tex(b, "BACKGROUND", -6)
    s.sel:SetAllPoints(s.fill)
    ns.UI.Gradient(s.sel, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.55, C.violet[1], C.violet[2], C.violet[3], 0.05)
    s.sel:Hide()
    s.bar = tex(b, "BACKGROUND", -5)
    s.bar:SetPoint("TOPLEFT", s.fill, "TOPLEFT", 0, 0)
    s.bar:SetPoint("BOTTOMLEFT", s.fill, "BOTTOMLEFT", 0, 0)
    s.bar:SetWidth(2)
    s.bar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    s.bar:Hide()
    s.hl = tex(b, "HIGHLIGHT")
    s.hl:SetAllPoints(s.fill)
    ns.UI.Gradient(s.hl, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.25, C.violet[1], C.violet[2], C.violet[3], 0.02)
    -- filet des sous-sous-categories : teinte du lisere
    local lines = field(b, "Lines")
    if lines then
        pcall(lines.SetDesaturated, lines, true)
        pcall(lines.SetVertexColor, lines, C.border[1], C.border[2], C.border[3], 1)
    end
    cats[b] = s
    claimed[b] = true
    catState(b, s)
end

---------------------------------------------------------------------------
-- Listes de prix
---------------------------------------------------------------------------

-- rang d une ligne dans sa liste, d apres sa position (le code de Blizzard
-- n est pas appele) : alternance des bandes
local function parity(b)
    local okP, p = pcall(b.GetParent, b)
    if not okP or type(p) ~= "table" or not p.GetTop then return nil end
    local okT, top = pcall(b.GetTop, b)
    local okR, ref = pcall(p.GetTop, p)
    local okH, h = pcall(b.GetHeight, b)
    top, ref, h = okT and num(top), okR and num(ref), okH and num(h)
    if not (top and ref and h and h > 1) then return nil end
    return math.floor((ref - top) / h + 0.5) % 2
end

-- ligne de liste (AuctionHouseItemListLineTemplate) : bande, choix et
-- survol de Blizzard -> les notres
local function lineRow(b)
    if rows[b] or not b.CreateTexture then return end
    local C = ns.COLORS
    local s = {}
    s.zebra = tex(b, "BACKGROUND", -8)
    s.zebra:SetAllPoints(b)
    s.zebra:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.05)
    s.zebra:Hide()
    s.sel = tex(b, "BACKGROUND", -7)
    s.sel:SetAllPoints(b)
    ns.UI.Gradient(s.sel, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.5, C.violet[1], C.violet[2], C.violet[3], 0.06)
    s.sel:Hide()
    s.bar = tex(b, "BACKGROUND", -6)
    s.bar:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    s.bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    s.bar:SetWidth(2)
    s.bar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    s.bar:Hide()
    s.hov = tex(b, "HIGHLIGHT")
    s.hov:SetAllPoints(b)
    ns.UI.Gradient(s.hov, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.22, C.violet[1], C.violet[2], C.violet[3], 0.02)
    -- ligne desactivee : pas de calque de survol, on suit celui de Blizzard
    s.hov2 = tex(b, "BACKGROUND", -5)
    s.hov2:SetAllPoints(b)
    ns.UI.Gradient(s.hov2, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.22, C.violet[1], C.violet[2], C.violet[3], 0.02)
    s.hov2:Hide()
    rows[b] = s
    claimed[b] = true
end

local function rowState(b, s)
    local sh = field(b, "SelectedHighlight")
    local hl = field(b, "HighlightTexture")
    douse(sh)   -- Blizzard repose son alpha (0.5 pour ses propres objets)
    fade(hl)
    local okN, nt = pcall(b.GetNormalTexture, b)
    if okN then fade(nt) end
    local on = shown(sh)
    s.sel:SetShown(on)
    s.bar:SetShown(on)
    if on then
        local okA, a = pcall(sh.GetAlpha, sh)
        a = okA and num(a) or 1
        a = math.max(0.35, math.min(1, a))
        s.sel:SetAlpha(a)
        s.bar:SetAlpha(a)
    end
    s.zebra:SetShown(parity(b) == 0)
    s.hov2:SetShown(not enabled(b) and shown(hl))
end

-- icone d une cellule (nom d objet) ou d une ligne du resume : carre au
-- lisere de la qualite lue dans le texte
local function iconState(s)
    local C = ns.COLORS
    douse(s.border)   -- Blizzard repose son alpha (ventes vendues)
    cropIcon(s.icon)
    local on = shown(s.icon)
    if on ~= s.on then
        s.on = on
        s.fill:SetShown(on)
        showAll(s.edges, on)
    end
    local t = textOf(s.text)
    if t ~= s.last then
        s.last = t
        local r, g, b = colorIn(t)
        if r then paint(s.edges, r, g, b, 1) else paintC(s.edges, C.border) end
    end
end

local function iconCell(c)
    if cells[c] or not c.CreateTexture then return end
    local icon = field(c, "Icon")
    if objType(icon) ~= "Texture" then return end
    local s = box(c, icon, 1)
    s.icon, s.border, s.text = icon, field(c, "IconBorder"), field(c, "Text")
    cells[c] = s
    claimed[c] = true
    iconState(s)
end

-- ligne du resume des ventes (AuctionHouseAuctionsSummaryLineTemplate)
local function summaryRow(b)
    if sums[b] or not b.CreateTexture then return end
    local C = ns.COLORS
    fadeStates(b, { "GetHighlightTexture" })
    local s = {}
    s.sel = tex(b, "BACKGROUND", -6)
    s.sel:SetAllPoints(b)
    ns.UI.Gradient(s.sel, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.5, C.violet[1], C.violet[2], C.violet[3], 0.06)
    s.sel:Hide()
    s.bar = tex(b, "BACKGROUND", -5)
    s.bar:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    s.bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    s.bar:SetWidth(2)
    s.bar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    s.bar:Hide()
    s.hov = tex(b, "HIGHLIGHT")
    s.hov:SetAllPoints(b)
    ns.UI.Gradient(s.hov, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.22, C.violet[1], C.violet[2], C.violet[3], 0.02)
    local icon = field(b, "Icon")
    if objType(icon) == "Texture" then
        s.box = box(b, icon, 1)
        s.box.icon, s.box.border, s.box.text = icon, field(b, "IconBorder"), field(b, "Text")
    end
    sums[b] = s
    claimed[b] = true
end

local function sumState(b, s)
    local sh = field(b, "SelectedHighlight")
    douse(sh)
    local on = shown(sh)
    s.sel:SetShown(on)
    s.bar:SetShown(on)
    if s.box then iconState(s.box) end
end

-- titre de colonne (AuctionHouseTableHeaderStringTemplate) : la fleche de
-- tri garde ses coordonnees (Blizzard les retourne), seule sa couleur change
local function header(h)
    if heads[h] or not h.CreateTexture then return end
    local C = ns.COLORS
    for _, k in ipairs({ "Left", "Middle", "Right" }) do fade(field(h, k)) end
    fadeStates(h, { "GetHighlightTexture" })
    local s = {}
    s.sep = tex(h, "BORDER", 1)
    s.sep:SetPoint("TOPRIGHT", h, "TOPRIGHT", 0, -3)
    s.sep:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 3)
    s.sep:SetWidth(1)
    s.sep:SetColorTexture(C.border[1], C.border[2], C.border[3], 0.8)
    s.hl = tex(h, "HIGHLIGHT")
    s.hl:SetPoint("TOPLEFT", h, "TOPLEFT", 1, -1)
    s.hl:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -1, 1)
    ns.UI.Gradient(s.hl, "VERTICAL", C.violet[1], C.violet[2], C.violet[3], 0.02, C.violet[1], C.violet[2], C.violet[3], 0.25)
    s.text, s.arrow = field(h, "Text"), field(h, "Arrow")
    heads[h] = s
    claimed[h] = true
end

local function headState(_, s)
    local C = ns.COLORS
    if objType(s.text) == "FontString" then pcall(s.text.SetTextColor, s.text, C.gold[1], C.gold[2], C.gold[3]) end
    if s.arrow and s.arrow.SetVertexColor then goldTint(s.arrow) end
end

-- bandeau des titres de colonnes : degrade d accent et filet d or
local function headerBand(hc)
    if bands[hc] then return bands[hc] end
    if not hc.CreateTexture then return nil end
    local C = ns.COLORS
    local b = {}
    b.band = tex(hc, "BACKGROUND", -6)
    b.band:SetAllPoints(hc)
    ns.UI.Gradient(b.band, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.30, C.violet[1], C.violet[2], C.violet[3], 0.03)
    b.line = tex(hc, "BACKGROUND", -5)
    b.line:SetPoint("TOPLEFT", b.band, "BOTTOMLEFT", 0, 0)
    b.line:SetPoint("TOPRIGHT", b.band, "BOTTOMRIGHT", 0, 0)
    b.line:SetHeight(1)
    ns.UI.Gradient(b.line, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.8, C.gold[1], C.gold[2], C.gold[3], 0)
    bands[hc] = b
    return b
end

-- liste (AuctionHouseItemListTemplate) : bandeau si elle a des titres
local function list(f)
    local hc = field(f, "HeaderContainer")
    if hc then
        -- titres de colonnes : de nouveaux cadres quand le tableau change
        if hc.GetNumChildren then pools[hc] = true end
        local b = headerBand(hc)
        if b then
            local any = false
            for _, c in ipairs(childrenOf(hc)) do
                if shown(c) then
                    any = true
                    break
                end
            end
            b.band:SetShown(any)
            b.line:SetShown(any)
        end
    end
    local rb = field(field(f, "RefreshFrame"), "RefreshButton")
    if rb then iconButton(rb) end
end

-- barres de defilement (MinimalScrollBar) : alpha et couleur seulement
local function isScrollBar(f)
    local track = field(f, "Track")
    return track and field(track, "Thumb") and field(f, "Back") and field(f, "Forward") and true or false
end

local function skinScrollBar(sb)
    if bars[sb] then return end
    local C = ns.COLORS
    local track = field(sb, "Track")
    local thumb = field(track, "Thumb")
    if not (track and track.CreateTexture and thumb and thumb.CreateTexture) then return end
    for _, k in ipairs({ "Begin", "Middle", "End" }) do
        fade(field(track, k))
        fade(field(thumb, k))
    end
    local line = tex(track, "ARTWORK", 1)
    line:SetPoint("TOP", track, "TOP", 0, 0)
    line:SetPoint("BOTTOM", track, "BOTTOM", 0, 0)
    line:SetWidth(1)
    line:SetColorTexture(C.border[1], C.border[2], C.border[3], 0.8)
    local knob = tex(thumb, "ARTWORK", 2)
    knob:SetPoint("TOP", thumb, "TOP", 0, 0)
    knob:SetPoint("BOTTOM", thumb, "BOTTOM", 0, 0)
    knob:SetWidth(4)
    knob:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.6)
    for _, k in ipairs({ "Back", "Forward" }) do
        local t = field(field(sb, k), "Texture")
        if t and t.SetVertexColor then pcall(t.SetVertexColor, t, C.violet[1], C.violet[2], C.violet[3], 0.8) end
    end
    bars[sb] = { thumb = thumb, knob = knob }
end

---------------------------------------------------------------------------
-- Panneaux, cartes d objet, icones
---------------------------------------------------------------------------

-- carte d objet (AuctionHouseItemDisplayTemplate) : fond, degrade, lisere
-- et filet d or ; le nom et l etoile restent
local function card(f)
    local C = ns.COLORS
    local fill = tex(f, "BACKGROUND", -8)
    fill:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.92)
    local glow = tex(f, "BACKGROUND", -7)
    glow:SetAllPoints(fill)
    ns.UI.Gradient(glow, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.28, C.violet[1], C.violet[2], C.violet[3], 0.02)
    paintC(ring(f, fill, "BACKGROUND", -6, 0), C.border)
    local line = tex(f, "BACKGROUND", -5)
    line:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT", 1, 1)
    line:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", -1, 1)
    line:SetHeight(1)
    ns.UI.Gradient(line, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.8, C.gold[1], C.gold[2], C.gold[3], 0)
    claimed[f] = true
end

-- cadre a fond de Blizzard (AuctionHouseBackgroundTemplate : listes,
-- categories, resume, pages d achat et de vente, cartes d objet)
local function surface(f)
    fade(field(f, "Background"))
    local nine = field(f, "NineSlice")
    fadeOwn(nine)
    if surfaces[f] then return end
    surfaces[f] = true
    local C = ns.COLORS
    if field(f, "ItemButton") then
        if f.CreateTexture then card(f) end
        return
    end
    if hasFn(f, "IsLayoutFrame") then
        -- cadre de mise en page : le code de Blizzard parcourt ses regions,
        -- nos textures vont sur son NineSlice (meme niveau, enfant)
        if nine and nine.CreateTexture then backdrop(nine, nine, C.panel, 0.5) end
        return
    end
    if not f.CreateTexture then return end
    if field(f, "HeaderContainer") then
        backdrop(f, nine or f, { 0, 0, 0 }, 0.3)   -- liste : puits sombre
    else
        backdrop(f, nine or f, C.panel, 0.6)       -- categories, resume
    end
    claimed[f] = true
end

-- grosse icone d objet (CircularGiantItemButtonTemplate des pages d achat,
-- GiantItemButtonTemplate de la page de vente) : masque retire, icone
-- carree, lisere de la qualite lu dans la bordure de Blizzard
local function giantButton(b)
    if boxes[b] or not b.CreateTexture then return end
    local icon = field(b, "Icon")
    if objType(icon) ~= "Texture" then return end
    if not masked[icon] and icon.RemoveMaskTexture then
        masked[icon] = true
        for _, k in ipairs({ "CircleMask", "IconMask" }) do
            local m = field(b, k)
            if m then pcall(icon.RemoveMaskTexture, icon, m) end
        end
    end
    fade(field(b, "EmptyBackground"))
    fadeStates(b, { "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" })
    local bx = box(b, icon, 1)
    bx.icon, bx.border = icon, field(b, "IconBorder")
    local C = ns.COLORS
    local hl = tex(b, "HIGHLIGHT")
    hl:SetAllPoints(icon)
    hl:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.2)
    fade(bx.border)
    cropIcon(icon)
    boxes[b] = bx
    claimed[b] = true
end

local function boxState(_, s)
    local C = ns.COLORS
    fade(s.border)
    cropIcon(s.icon)
    local r, g, bl = borderColor(s.border)
    local key = r and string.format("%.3f:%.3f:%.3f", r, g, bl) or "-"
    if key ~= s.key then
        s.key = key
        if r then paint(s.edges, r, g, bl, 1) else paintC(s.edges, C.border) end
    end
end

-- onglet "Creer une enchere" au-dessus des pages de vente : textures a
-- nous sur la fenetre (dessous de la page, qui est un cadre de mise en
-- page), montrees avec la page
local function sellTab(ahf, sf)
    for _, k in ipairs({ "CreateAuctionTabLeft", "CreateAuctionTabMiddle", "CreateAuctionTabRight" }) do fade(field(sf, k)) end
    local label = field(sf, "CreateAuctionLabel")
    if sellTabs[sf] or objType(label) ~= "FontString" or not ahf.CreateTexture then return end
    local C = ns.COLORS
    local s = {}
    s.fill = tex(ahf, "BACKGROUND", -4)
    s.fill:SetPoint("TOPLEFT", label, "TOPLEFT", -10, 6)
    s.fill:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 10, -6)
    s.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.95)
    s.edges = ring(ahf, s.fill, "BACKGROUND", -3, 0)
    paintC(s.edges, C.border)
    s.line = tex(ahf, "BACKGROUND", -2)
    s.line:SetPoint("TOPLEFT", s.fill, "TOPLEFT", 0, 0)
    s.line:SetPoint("TOPRIGHT", s.fill, "TOPRIGHT", 0, 0)
    s.line:SetHeight(2)
    s.line:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    s.all = { s.fill, s.line }
    for _, e in ipairs(s.edges) do s.all[#s.all + 1] = e end
    showAll(s.all, false)
    s.on = false
    sellTabs[sf] = s
end

local function sellTabState(sf, s)
    local on = visible(sf)
    if on ~= s.on then
        s.on = on
        showAll(s.all, on)
    end
end

-- cadre d argent en bas a gauche : decor de Blizzard a alpha 0, notre
-- carre (pieces et chiffres de Blizzard gardes)
local function money(ahf)
    local b = field(ahf, "MoneyFrameBorder")
    if b then
        fadeOwn(b)
        if not panels[b] and b.CreateTexture then
            panels[b] = true
            box(b, b, 1)
        end
    end
    local i = field(ahf, "MoneyFrameInset")
    if i then
        fadeOwn(i)
        fade(field(i, "Bg"))
        fadeOwn(field(i, "NineSlice"))
    end
end

-- dialogue d achat des marchandises : cadre de Blizzard a alpha 0, panneau
-- sombre, ombre, lisere et filet degrade violet -> or
local function dialog(bd)
    fadeOwn(field(bd, "Border"))
    if panels[bd] or not bd.CreateTexture then return end
    panels[bd] = true
    local C = ns.COLORS
    local fill = tex(bd, "BACKGROUND", -7)
    fill:SetPoint("TOPLEFT", bd, "TOPLEFT", 6, -6)
    fill:SetPoint("BOTTOMRIGHT", bd, "BOTTOMRIGHT", -6, 6)
    fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.97)
    for i = 1, 4 do
        local sh = tex(bd, "BACKGROUND", -8)
        sh:SetPoint("TOPLEFT", fill, "TOPLEFT", -i, i)
        sh:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", i, -i)
        sh:SetColorTexture(0, 0, 0, 0.16)
    end
    paintC(ring(bd, fill, "BACKGROUND", -6, 0), C.border)
    local line = tex(bd, "BACKGROUND", -5)
    line:SetPoint("TOPLEFT", fill, "TOPLEFT", 1, -1)
    line:SetPoint("TOPRIGHT", fill, "TOPRIGHT", -1, -1)
    line:SetHeight(2)
    ns.UI.Gradient(line, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 1, C.gold[1], C.gold[2], C.gold[3], 1)
    claimed[bd] = true
end

---------------------------------------------------------------------------
-- Parcours
---------------------------------------------------------------------------

local function actionFor(a)
    local act = ATLAS[a]
    if act then return act end
    for _, p in ipairs(PREFIX) do
        if a:find(p[1]) then return p[2] end
    end
end

local function scanRegions(f)
    for _, r in ipairs(regionsOf(f)) do
        if not mine[r] and not done[r] and objType(r) == "Texture" then
            local a = atlasOf(r)
            local act = a and actionFor(a)
            if act then
                done[r] = true
                if act == "fade" then
                    fade(r)
                elseif act == "dropdown" then
                    -- bouton Filtrer (18 px ; l art de Blizzard debordait de
                    -- 4 px) : plaque de 22 px, comme le champ de recherche,
                    -- l etoile des favoris et le bouton Rechercher
                    fade(r)
                    plate(f, 0, -2)
                elseif act == "gold" then
                    golds[r] = true
                    goldTint(r)
                end
            end
        end
    end
end

-- elements reconnus par leurs champs ; vrai : ne pas descendre plus bas
local function special(f)
    local t = objType(f)
    if t == "EditBox" then
        editBox(f)
        return true
    end
    if t == "CheckButton" then
        skinCheck(f, 16)
        return true
    end
    if field(f, "GoldDisplay") then return true end   -- montant d argent : intouche
    if field(f, "LeftActive") then
        skinTab(f)
        return true
    end
    if field(f, "Lines") and field(f, "SelectedTexture") then
        category(f)
        return true
    end
    if field(f, "SelectedHighlight") then
        if field(f, "Icon") and field(f, "IconBorder") then summaryRow(f) else lineRow(f) end
        return false
    end
    if t == "Button" and isTex(field(f, "Left")) then
        if field(f, "Arrow") then
            header(f)
            return true
        end
        if isTex(field(f, "Middle")) and isTex(field(f, "Right")) then
            panelButton(f)
            return true
        end
    end
    if field(f, "CircleMask") or field(f, "IconMask") then
        giantButton(f)
        return true
    end
    if field(f, "Icon") and field(f, "IconBorder") and objType(field(f, "Text")) == "FontString" then
        iconCell(f)
        return true
    end
    if isTex(field(f, "Background")) and field(f, "NineSlice") then surface(f) end
    local sbx = field(f, "ScrollBox")
    if sbx then
        -- lignes et boutons recycles : un pool qui grandit relance le
        -- parcours (voir poolCount)
        local st = field(sbx, "ScrollTarget")
        if st and st.GetNumChildren then pools[st] = true end
        if field(f, "HeaderContainer") then list(f) end
    end
    return false
end

local function walk(f, depth)
    if depth > 10 or mine[f] or not visible(f) then return end
    if isScrollBar(f) then
        pcall(skinScrollBar, f)
        return
    end
    scanRegions(f)
    local ok, stop = pcall(special, f)
    if ok and stop then return end
    for _, c in ipairs(childrenOf(f)) do walk(c, depth + 1) end
end

local function full(ahf)
    local skip = {}
    for _, k in ipairs(SKIP_KEYS) do
        local c = field(ahf, k)
        if c then skip[c] = true end
    end
    pcall(money, ahf)
    local bar = field(ahf, "SearchBar")
    local fav = field(bar, "FavoritesSearchButton")
    if fav then pcall(iconButton, fav) end
    -- bouton Rechercher : plaque de toute sa hauteur (22 px), alignee sur la
    -- ligne de recherche (le parcours ne le reprend pas ensuite)
    local go = field(bar, "SearchButton")
    if go and visible(go) and isTex(field(go, "Left")) and isTex(field(go, "Middle")) and isTex(field(go, "Right")) then
        pcall(panelButton, go, 0)
    end
    local bd = field(ahf, "BuyDialog")
    if visible(bd) then pcall(dialog, bd) end
    for _, k in ipairs({ "ItemSellFrame", "CommoditiesSellFrame" }) do
        local sf = field(ahf, k)
        if sf then pcall(sellTab, ahf, sf) end
    end
    for _, c in ipairs(childrenOf(ahf)) do
        if not skip[c] then walk(c, 1) end
    end
end

---------------------------------------------------------------------------
-- Releve leger (10 fois par seconde, fenetre ouverte) : etats et couleurs
---------------------------------------------------------------------------

local titleFont

local function plateState(b, p)
    local C = ns.COLORS
    local en = enabled(b)
    tint(p, (en and isOver(b)) and C.gold or C.border)
    local a = en and 1 or 0.5
    if a ~= p.a then
        p.a = a
        p.fill:SetAlpha(a)
    end
end

local function editState(e, k)
    local C = ns.COLORS
    local okF, focus = pcall(e.HasFocus, e)
    if okF and isTrue(focus) then tint(k, C.gold)
    elseif isOver(e) then tint(k, C.violet)
    else tint(k, C.border) end
end

local WHITE = { 1, 1, 1 }

local function checkState(cb, k)
    local C = ns.COLORS
    local okC, on = pcall(cb.GetChecked, cb)
    local en = enabled(cb)
    local over = isOver(cb)
    k.mark:SetShown(okC and isTrue(on))
    k.mark:SetAlpha(en and 1 or 0.4)
    tint(k, over and C.gold or C.border)
    -- libelle : couleur du texte de CorpUI (comme ns.UI.Check), blanc au
    -- survol, attenue si desactivee ; reposee a chaque releve, jamais la police
    if k.label then
        local c = (over and en) and WHITE or C.text
        local m = en and 1 or 0.5
        pcall(k.label.SetTextColor, k.label, c[1] * m, c[2] * m, c[3] * m)
    end
end

local function barState(b)
    local C = ns.COLORS
    local over = isOver(b.thumb)
    if over ~= b.over then
        b.over = over
        if over then
            b.knob:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.9)
        else
            b.knob:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.6)
        end
    end
end

local function cellState(_, s) iconState(s) end
local function barStateOf(_, b) barState(b) end

local function each(t, fn)
    for k, s in pairs(t) do
        if visible(k) then pcall(fn, k, s) end
    end
end

local function light(ahf)
    local title = field(field(ahf, "TitleContainer"), "TitleText")
    if objType(title) == "FontString" then
        if not titleFont or titleFont.fs ~= title then titleFont = goldFont(title, 12) else keepGold(titleFont) end
    end
    each(tabs, tabState)
    each(plates, plateState)
    each(edits, editState)
    each(checks, checkState)
    each(cats, catState)
    each(rows, rowState)
    each(sums, sumState)
    each(cells, cellState)
    each(boxes, boxState)
    each(heads, headState)
    each(golds, goldTint)
    each(bars, barStateOf)
    for sf, s in pairs(sellTabs) do pcall(sellTabState, sf, s) end
end

local function hideSellTabs()
    for _, s in pairs(sellTabs) do
        s.on = false
        showAll(s.all, false)
    end
end

-- Skins.lua : ne pas descendre dans l hotel des ventes (tout est repris
-- ici, sans course au chargement : la parente suffit), ne pas effacer nos
-- textures
local prevClaimed = ns.SkinClaimed
function ns.SkinClaimed(f)
    if type(f) == "table" then
        if claimed[f] then return true end
        local ahf = _G.AuctionHouseFrame
        if type(ahf) == "table" and f.GetParent and db() then
            local ok, p = pcall(f.GetParent, f)
            if ok and rawequal(p, ahf) then return true end
        end
    end
    if prevClaimed then return prevClaimed(f) end
    return false
end

local prevOwned = ns.SkinOwned
function ns.SkinOwned(r)
    if type(r) == "table" and mine[r] then return true end
    if prevOwned then return prevOwned(r) end
    return false
end

---------------------------------------------------------------------------

local state = { shown = false, key = nil, count = nil }
local acc, walkAcc = 0, 0

local function pageKey(f)
    local s = ""
    for _, k in ipairs(PAGE_KEYS) do s = s .. (shown(field(f, k)) and "1" or "0") end
    local af = field(f, "AuctionsFrame")
    for _, k in ipairs(AUCTION_KEYS) do s = s .. (shown(field(af, k)) and "1" or "0") end
    return s
end

-- nombre de cadres des pools connus (accesseur du moteur, aucune fonction
-- Lua de Blizzard) : un cadre n est jamais detruit, le total ne fait que
-- croitre ; s il change, un cadre neuf attend son habillage (premiere
-- ouverture d une grande categorie, resultats arrives apres coup, tableau
-- aux colonnes nouvelles) : parcours au tic suivant
local function poolCount()
    local n = 0
    for f in pairs(pools) do
        local ok, c = pcall(f.GetNumChildren, f)
        c = ok and num(c)
        if c then n = n + c end
    end
    return n
end

local function report(err)
    if ns.skinsDB then
        ns.skinsDB.errors = ns.skinsDB.errors or {}
        ns.skinsDB.errors.AuctionHouse = tostring(err)
    end
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then state.shown = false end
end)
pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")

ev:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.1 then return end
    walkAcc = walkAcc + acc
    acc = 0
    if not db() or InCombatLockdown() then return end
    local f = _G.AuctionHouseFrame
    if type(f) ~= "table" or not f.CreateTexture or not visible(f) then
        if state.shown then
            state.shown = false
            pcall(hideSellTabs)
        end
        return
    end
    local key = pageKey(f)
    if not state.shown or key ~= state.key or walkAcc >= 0.6 or poolCount() ~= state.count then
        state.shown, state.key, walkAcc = true, key, 0
        local ok, err = pcall(full, f)
        if not ok then report(err) end
        -- releve apres le parcours : les pools qu il vient de decouvrir ne
        -- relancent pas un second parcours
        state.count = poolCount()
    end
    local ok, err = pcall(light, f)
    if not ok then report(err) end
end)
