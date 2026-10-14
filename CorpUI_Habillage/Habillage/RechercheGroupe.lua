--[[--------------------------------------------------------------------------
    CorpUI - module Habillage : recherche de groupe en profondeur
    (LFGParentFrame de Blizzard_GroupFinder_VanillaStyle, fichiers [Family]
    = Mainline charges en Camelot ; PVEFrame / Blizzard_GroupFinder est exclu
    en Camelot et n est pas habille ici)

    Skins.lua pose deja un fond sur LFGParentFrame et aplatit les boutons
    rouges (Retour, Lister, Envoyer un message, Inviter, Appel de roles) ;
    ici on reprend le detail des trois volets (LFGListingFrame,
    LFGBrowseFrame, LFGWhoListFrame, modele PortraitFrame pose sur toute la
    fenetre) :
      - chaque volet : fond obsidienne, lisere, bandeau d accent, titre en or
        (police des titres), decor de Blizzard a alpha 0 ;
      - onglets a icones a droite (ListingTab, BrowsingTab, WhoListingTab,
        modele LargeSideTabButtonTemplate) : rail sombre, tuile carree,
        lisere d or pour l onglet actif ;
      - zones "pierre" (roles, filtres) : bande d accent et filet d or ;
        cadres interieurs : panneau sombre et lisere ; traits de separation :
        filet d or ;
      - Lister : categories (donjons, raids...) encadrees, voile sombre
        derriere le titre, survol en degrade ; lignes d activites : en-tetes
        de groupes en degrade, boutons + / - en or ; cases a cocher (roles,
        activites, "nouveaux joueurs", niveaux) facon CorpUI, coche partielle
        attenuee ; menu du style de jeu et champ de description habilles ;
      - Parcourir : menus de categorie et d activites, bouton Actualiser et
        options aplatis ; resultats en cartes plates, choix et survol en
        degrade, separateurs "joueurs seuls / groupes" en en-tetes, bouton de
        retrait aplati ; infobulle des resultats au style CorpUI ;
      - Qui : champ de recherche, loupe et filtre aplatis, lignes en cartes ;
      - barres de defilement minimalistes (et celle, ancienne, du champ de
        description).
    Les couleurs d information de Blizzard sont gardees : classes, roles,
    niveaux (activite facile / difficile), annonces retirees, etats grises.
    L oeil (LFGParentFramePortrait) reste celui de Blizzard : il anime l etat
    de l annonce. Le bouton de la minicarte de cet addon
    (Blizzard_LFGVanilla_Minimap.lua) n est pas charge en Camelot.

    Regles de ce client (valeurs secretes, taint) :
      - aucun crochet sur une fonction ou un script de Blizzard : tout passe
        par un releve periodique quand la fenetre est ouverte ;
      - aucun champ ecrit dans les tables de Blizzard (elements recycles des
        ScrollBox compris) : nos textures sont rangees dans des tables
        faibles a nous, indexees par le cadre ;
      - aucune taille, position, script, attribut ou etat de Blizzard
        modifie, aucune methode de leurs mixins appelee : seulement l alpha,
        la couleur, le recadrage de leurs textures, et nos propres textures /
        textes poses dessus. Les actions protegees (C_LFGList.CreateListing,
        UpdateListing, Search, C_FriendList.SendWho) restent entierement dans
        le code de Blizzard ; on n entre jamais dans la zone de saisie
        securisee de la description (LFGListingComment) ;
      - rien en combat ; toute valeur lue est verifiee (pcall, issecretvalue).
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)

local issecret = issecretvalue or function() return false end
local weak = { __mode = "k" }

local mine = setmetatable({}, weak)      -- nos regions (a ne jamais traiter)
local done = setmetatable({}, weak)      -- textures de Blizzard deja traitees
local claimed = setmetatable({}, weak)   -- cadres que Skins.lua ne doit pas aplatir
local panels = setmetatable({}, weak)    -- volet -> { title }
local headers = setmetatable({}, weak)   -- en-tete -> { fill, line, font }
local plates = setmetatable({}, weak)    -- bouton aplati -> { fill, edges, glyph }
local bars = setmetatable({}, weak)      -- barre de defilement -> { thumb, knob }
local checks = setmetatable({}, weak)    -- case a cocher -> { edges, mark }
local rows = setmetatable({}, weak)      -- ligne de resultat -> { bg, edges, sel, bar, ref }
local actRows = setmetatable({}, weak)   -- ligne d activite -> { band, line, level, toggle }
local edits = setmetatable({}, weak)     -- champ de saisie -> { fill, edges, focus }
local sideTabs = setmetatable({}, weak)  -- onglet de droite -> { fill, icon, ... }
local cats = setmetatable({}, weak)      -- bouton de categorie -> { edges, label }
local follow = setmetatable({}, weak)    -- notre texture -> texture de Blizzard dont elle suit l affichage
local icons = setmetatable({}, weak)     -- bouton a icone -> son icone (or, grisee si inactif)
local tips = setmetatable({}, weak)      -- infobulle des resultats -> nos textures

-- decors de la fenetre, par atlas
local ATLAS = {
    -- fonds et cadres interieurs
    ["groupfinder-background"] = "inset",
    ["groupfinder-Stat-StoneBG"] = "band",
    ["groupfinder-roles-background"] = "band",
    ["common-insideframe"] = "fade",
    ["common-framedivider"] = "fade",
    ["groupfinder-ScrollLine"] = "divider",
    -- categories du volet Lister
    ["groupfinder-button-cover"] = "catcover",
    ["groupfinder-button-cover-down"] = "fade",
    ["groupfinder-button-cover-hover"] = "fade",
    -- lueurs derriere les icones de role
    ["UI-LFG-RoleIcon-Tank-Background"] = "fade",
    ["UI-LFG-RoleIcon-Healer-Background"] = "fade",
    ["UI-LFG-RoleIcon-DPS-Background"] = "fade",
    -- lignes de resultats (Parcourir) et de joueurs (Qui)
    ["groupfinder-highlightbar"] = "rowbg",
    ["groupfinder-highlightbar-yellow"] = "rowsel",
    ["groupfinder-highlightbar-blue"] = "rowhover",
    ["common-button-list-mid2"] = "rowbg",
    ["common-button-list-mid2-selected"] = "rowsel",
    ["common-button-list-mid2-hover"] = "rowhover",
    ["common-button-list-large"] = "rowbg",
    ["common-button-list-large-selected"] = "rowsel",
    ["common-button-list-large-hover"] = "rowhover",
    -- separateurs "joueurs seuls / groupes" et leurs + / -
    ["common-button-list-collapseExpand"] = "header",
    ["common-button-list-plus"] = "gold",
    ["common-button-list-minus"] = "gold",
    -- options, loupe (les menus a fleche et leur fond textholder sont a
    -- Communs.lua)
    ["OptionsIcon-Brown"] = "gold",
    ["common-icon-search"] = "gold",
}
-- reconnus par le debut de l atlas
local PREFIX = {
    { "^common%-dropdown%-b%-button", "dropdown" },  -- bouton Filtre (Qui)
    { "^common%-button%-tertiary", "tertiary" },     -- loupe et invitation (Qui)
    { "^common%-search%-border", "fade" },
}
-- actions a refaire a chaque passage (Blizzard repose l atlas)
local AGAIN = { gold = true }

local SUBFRAMES = { "LFGListingFrame", "LFGBrowseFrame", "LFGWhoListFrame" }
local TAB_KEYS = { "ListingTab", "BrowsingTab", "WhoListingTab" }
local PANEL_DECOR = { "NineSlice", "PortraitContainer", "TitleContainer", "Bg", "TopTileStreaks" }
local INPUT_TEX = { "TopLeftTex", "TopRightTex", "TopTex", "BottomLeftTex", "BottomRightTex", "BottomTex",
                    "LeftTex", "RightTex", "MiddleTex" }
local STRETCH = { "TopLeft", "TopRight", "BottomLeft", "BottomRight", "TopMiddle", "MiddleLeft", "MiddleRight",
                  "BottomMiddle", "MiddleMiddle" }

local function db()
    local d = ns.skinsDB
    if type(d) ~= "table" or not d.enabled then return nil end
    if d.groups and d.groups.social == false then return nil end
    return d
end

---------------------------------------------------------------------------
-- Outils
---------------------------------------------------------------------------

local function objType(o)
    if type(o) ~= "table" or not o.GetObjectType then return nil end
    local ok, t = pcall(o.GetObjectType, o)
    if ok and type(t) == "string" and not issecret(t) then return t end
end

local function field(f, key)
    if type(f) ~= "table" then return nil end
    local ok, c = pcall(function() return f[key] end)
    if ok and type(c) == "table" then return c end
end

local function fade(obj)
    if type(obj) == "table" and obj.SetAlpha and not mine[obj] then pcall(obj.SetAlpha, obj, 0) end
end

local function num(v)
    if v == nil or issecret(v) or type(v) ~= "number" then return nil end
    return v
end

local function visible(f)
    if type(f) ~= "table" or not f.IsVisible then return false end
    local ok, v = pcall(f.IsVisible, f)
    return ok and v == true
end

local function shown(f)
    if type(f) ~= "table" or not f.IsShown then return false end
    local ok, v = pcall(f.IsShown, f)
    return ok and v == true
end

local function isOver(f)
    if type(f) ~= "table" or not f.IsMouseOver then return false end
    local ok, v = pcall(f.IsMouseOver, f)
    return ok and v == true
end

local function enabled(f)
    if type(f) ~= "table" or not f.IsEnabled then return true end
    local ok, v = pcall(f.IsEnabled, f)
    return not (ok and v == false)
end

local function regionsOf(f)
    if type(f) ~= "table" or not f.GetRegions then return {} end
    local ok, list = pcall(function() return { f:GetRegions() } end)
    return ok and list or {}
end

local function childrenOf(f)
    if type(f) ~= "table" or not f.GetChildren then return {} end
    local ok, list = pcall(function() return { f:GetChildren() } end)
    return ok and list or {}
end

local function atlasOf(t)
    if type(t) ~= "table" or not t.GetAtlas then return nil end
    local ok, a = pcall(t.GetAtlas, t)
    if ok and type(a) == "string" and not issecret(a) then return a end
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

-- texture d etat d un bouton (lecture seule)
local function stateTex(b, get)
    if type(b) ~= "table" or not b[get] then return nil end
    local ok, t = pcall(b[get], b)
    if ok and type(t) == "table" then return t end
end

local function tint(t, c, a)
    if type(t) ~= "table" or not t.SetVertexColor then return end
    pcall(t.SetDesaturated, t, true)
    pcall(t.SetVertexColor, t, c[1], c[2], c[3], a or 1)
end

local function tex(host, layer, sub)
    local t = host:CreateTexture(nil, layer, nil, sub)
    mine[t] = true
    ns.NoSnap(t)   -- traits fins toujours dessines (Core.lua)
    return t
end

local function text(host, size)
    local fs = host:CreateFontString(nil, "OVERLAY")
    mine[fs] = true
    pcall(ns.UI.HeadFont, fs, size)
    return fs
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

local function setShown(list, on)
    for _, x in ipairs(list) do x:SetShown(on) end
end

-- sous-niveaux de nos textures du calque BACKGROUND posees sur un volet :
-- l ordre de dessin entre textures de meme calque et meme sous-niveau
-- n est pas garanti, et la pierre / l illustration (bandes, cadres
-- interieurs) sont des regions du volet lui-meme ; on etage donc comme
-- Skins.lua : ombre, fond, lisere, puis bandes et cadres interieurs, puis
-- bandeau du haut
local SUB = {
    shadow = -8,     -- ombre douce (sous le fond, ne deborde qu a l exterieur)
    fill = -7,       -- fond du volet
    edge = -6,       -- lisere du volet
    zone = -5,       -- fond des bandes "pierre" et des cadres interieurs
    zoneEdge = -4,   -- leur filet d or / lisere
    head = -3,       -- bandeau d accent et filet d or du haut
}

-- panneau sombre (fond, lisere) sur "host", aux dimensions de "anchor" ;
-- "sub" : sous-niveau du fond (lisere juste au-dessus)
local function backdrop(host, anchor, alpha, sub)
    local C = ns.COLORS
    sub = sub or -8
    local fill = tex(host, "BACKGROUND", sub)
    fill:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    fill:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
    fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], alpha or 0.75)
    local edges = ring(host, anchor, "BACKGROUND", sub + 1, 0)
    paintC(edges, C.border)
    return { fill = fill, edges = edges }
end

-- bandeau d accent et filet d or sous le haut d un panneau
local function headBand(host, anchor, top, height)
    local C = ns.COLORS
    local band = tex(host, "BACKGROUND", SUB.head)
    band:SetPoint("TOPLEFT", anchor, "TOPLEFT", 1, -top)
    band:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -1, -top)
    band:SetHeight(height or 22)
    ns.UI.Gradient(band, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.32, C.violet[1], C.violet[2], C.violet[3], 0.03)
    local line = tex(host, "BACKGROUND", SUB.head)
    line:SetPoint("TOPLEFT", band, "BOTTOMLEFT")
    line:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT")
    line:SetHeight(1)
    ns.UI.Gradient(line, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.8, C.gold[1], C.gold[2], C.gold[3], 0)
end

-- police des titres + or ; on retient la police posee pour la reposer si
-- Blizzard change d objet de police
local function goldFont(fs, size)
    if objType(fs) ~= "FontString" then return nil end
    local C = ns.COLORS
    pcall(ns.UI.HeadFont, fs, size)
    pcall(fs.SetTextColor, fs, C.gold[1], C.gold[2], C.gold[3])
    local ok, file = pcall(fs.GetFont, fs)
    return { fs = fs, size = size, file = (ok and type(file) == "string" and not issecret(file)) and file or nil }
end

local function keepGold(h)
    if not h or not h.fs then return end
    local ok, file = pcall(h.fs.GetFont, h.fs)
    if ok and type(file) == "string" and not issecret(file) and h.file and file ~= h.file then
        pcall(ns.UI.HeadFont, h.fs, h.size)
    end
    local C = ns.COLORS
    pcall(h.fs.SetTextColor, h.fs, C.gold[1], C.gold[2], C.gold[3])
end

-- l ombre exterieure vient de Skins.lua quand son fond couvre toute la
-- fenetre ; avec un retrait (inset de Fenetres.lua), on la pose nous-memes
local function needShadow()
    for _, g in ipairs(ns.SKIN_GROUPS or {}) do
        for _, spec in ipairs(g.windows or {}) do
            if spec[1] == "LFGParentFrame" then
                local ins = spec.inset or {}
                for i = 1, 4 do
                    if (tonumber(ins[i]) or 0) ~= 0 then return true end
                end
                return false
            end
        end
    end
    return true
end

---------------------------------------------------------------------------
-- Boutons, cases, champs
---------------------------------------------------------------------------

-- plaque plate sous un bouton (textures a nous, au fond du bouton)
local function plate(b, inset)
    if plates[b] then return plates[b] end
    local C = ns.COLORS
    local p = {}
    p.fill = tex(b, "BACKGROUND", -8)
    p.fill:SetPoint("TOPLEFT", inset, -inset)
    p.fill:SetPoint("BOTTOMRIGHT", -inset, inset)
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

-- petit bouton a glyphe (fleches de l ancienne barre de defilement)
local function glyphButton(b, glyph, size, inset)
    if objType(b) == nil or (plates[b] and plates[b].glyph) then return end
    fadeStates(b)
    local p = plate(b, inset or 2)
    -- fleche en texte : notre chevron (meme usage : SetText, SetTextColor)
    if ns.UI.IsChevron(glyph) then
        p.glyph = ns.UI.Chevron(b, size or 10, glyph)
        mine[p.glyph] = true
    else
        p.glyph = text(b, size or 10)
    end
    p.glyph:SetPoint("CENTER", 0, 0)
    p.glyph:SetText(glyph)
    local C = ns.COLORS
    p.glyph:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
end

-- bouton a icone (Actualiser) : plaque, icone de Blizzard teinte en or
local function iconButton(b, inset)
    if objType(b) == nil or icons[b] then return end
    fadeStates(b, { "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" })
    plate(b, inset or 4)
    local icon = field(b, "Icon")
    icons[b] = (objType(icon) == "Texture") and icon or false
end

-- bouton etirable a neuf morceaux (retrait de l annonce)
local function stretchButton(b)
    if plates[b] then return end
    for _, k in ipairs(STRETCH) do fade(field(b, k)) end
    fadeStates(b, { "GetHighlightTexture" })
    plate(b, 1)
end

-- case a cocher : carre sombre, lisere, coche d or (textures a nous ; les
-- textures de Blizzard passent a alpha 0, la case garde ses scripts)
local function skinCheck(cb)
    if checks[cb] or not cb.GetChecked then return end
    fadeStates(cb)
    local C = ns.COLORS
    local fill = tex(cb, "BACKGROUND", -8)
    fill:SetSize(14, 14)
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
    claimed[cb] = true
end

-- coche partielle (groupe d activites dont une partie seulement est
-- choisie) : Blizzard pose alors la texture "UI-MultiCheck"
local function partial(cb)
    local t = stateTex(cb, "GetCheckedTexture")
    if not t then return false end
    for _, get in ipairs({ "GetTextureFilePath", "GetTexture" }) do
        if t[get] then
            local ok, f = pcall(t[get], t)
            if ok and type(f) == "string" and not issecret(f) then
                return f:lower():find("multicheck", 1, true) ~= nil
            end
        end
    end
    return false
end

-- champ de saisie (recherche Qui) : ses trois morceaux a alpha 0, notre
-- fond et notre lisere autour
local function skinEdit(e)
    if edits[e] then return end
    local l, m, r = field(e, "Left"), field(e, "Middle") or field(e, "Mid"), field(e, "Right")
    if not (l and m and r) then return end
    fade(l) fade(m) fade(r)
    local C = ns.COLORS
    local fill = tex(e, "BACKGROUND", -8)
    fill:SetPoint("TOPLEFT", e, "TOPLEFT", -5, 0)
    fill:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT", 0, 0)
    fill:SetColorTexture(0, 0, 0, 0.55)
    local edges = ring(e, fill, "BACKGROUND", -7, 0)
    paintC(edges, C.border)
    -- loupe en or : SearchBoxTemplate repose sa couleur (gris 0,6 / blanc)
    -- a chaque focus et changement de texte ; elle est donc reteinte a
    -- chaque releve dans light() (or plein = champ actif, or attenue sinon)
    local glass = field(e, "searchIcon") or field(e, "SearchIcon")
    if objType(glass) ~= "Texture" then glass = nil end
    edits[e] = { fill = fill, edges = edges, glass = glass, clear = field(e, "clearButton") }
    claimed[e] = true
    if glass then tint(glass, C.gold, 1) end
end

-- etat "actif" de la loupe, tel que SearchBoxTemplate le calcule (focus, ou
-- texte present : il montre alors le bouton d effacement) ; lecture seule
local function glassActive(k, focused)
    return focused or (k.clear ~= nil and shown(k.clear))
end

-- champ de description (UIPanelInputScrollFrameTemplate) : les neuf
-- morceaux du cadre passent a alpha 0 ; la zone de saisie (securisee)
-- n est jamais touchee, on lit seulement si elle a le focus
local function isInputScroll(f)
    return field(f, "TopLeftTex") and field(f, "MiddleTex") and field(f, "EditBox") and true or false
end

local function inputScroll(f)
    if edits[f] then return end
    for _, k in ipairs(INPUT_TEX) do fade(field(f, k)) end
    local C = ns.COLORS
    local fill = tex(f, "BACKGROUND", -8)
    fill:SetPoint("TOPLEFT", f, "TOPLEFT", -5, 5)
    fill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 5, -5)
    fill:SetColorTexture(0, 0, 0, 0.55)
    local edges = ring(f, fill, "BACKGROUND", -7, 0)
    paintC(edges, C.border)
    edits[f] = { fill = fill, edges = edges, focus = field(f, "EditBox") }
    claimed[f] = true
end

---------------------------------------------------------------------------
-- Barres de defilement
---------------------------------------------------------------------------

-- MinimalScrollBar : alpha et couleur seulement (le code de Blizzard
-- relit l atlas du curseur)
local function isScrollBar(f)
    local track = field(f, "Track")
    return track and field(track, "Thumb") and field(f, "Back") and field(f, "Forward") and true or false
end

local function skinScrollBar(sb)
    if bars[sb] then return end
    local C = ns.COLORS
    local track = field(sb, "Track")
    local thumb = field(track, "Thumb")
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
    -- fleches : notre chevron (Core.lua), celles de Blizzard eteintes
    for _, k in ipairs({ "Back", "Forward" }) do
        local b = field(sb, k)
        local c = ns.UI.ArrowChevron(b, ns.UI.ScrollDir(sb, k), 10, { field(b, "Texture") })
        if c then mine[c] = true end
    end
    bars[sb] = { thumb = thumb, knob = knob }
end

-- ancienne barre (Slider de UIPanelScrollFrameTemplate) du champ de
-- description : curseur et fleches a alpha 0, filet, curseur fin et
-- chevrons d or a la place
local function classicBar(sb)
    if bars[sb] then return end
    local thumb = field(sb, "ThumbTexture")
    if objType(thumb) ~= "Texture" then return end
    local C = ns.COLORS
    fade(thumb)
    local line = tex(sb, "BACKGROUND", 1)
    line:SetPoint("TOP", sb, "TOP", 0, 0)
    line:SetPoint("BOTTOM", sb, "BOTTOM", 0, 0)
    line:SetWidth(1)
    line:SetColorTexture(C.border[1], C.border[2], C.border[3], 0.8)
    local knob = tex(sb, "ARTWORK", 2)
    knob:SetPoint("TOP", thumb, "TOP", 0, -2)
    knob:SetPoint("BOTTOM", thumb, "BOTTOM", 0, 2)
    knob:SetWidth(4)
    knob:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.6)
    bars[sb] = { thumb = sb, knob = knob }
    local up, down = field(sb, "ScrollUpButton"), field(sb, "ScrollDownButton")
    if up then pcall(glyphButton, up, "^", 9, 2) end
    if down then pcall(glyphButton, down, "v", 9, 2) end
end

---------------------------------------------------------------------------
-- Volets, bandes, lignes
---------------------------------------------------------------------------

-- un volet (modele PortraitFrame pose sur toute la fenetre) : decor de
-- Blizzard a alpha 0, notre fond, lisere, bandeau et titre
local function panel(f)
    if panels[f] then return end
    local p = {}
    panels[f] = p
    fadeOwn(f)
    for _, k in ipairs(PANEL_DECOR) do
        local c = field(f, k)
        if objType(c) == "Texture" then fade(c) elseif c then fadeOwn(c) end
    end
    local bd = backdrop(f, f, 0.96, SUB.fill)
    -- ombre : rectangles sous le fond opaque (sous-niveau plus bas), seul
    -- ce qui deborde du volet se voit, comme dans Skins.lua
    if needShadow() then
        for i = 1, 4 do
            local s = tex(f, "BACKGROUND", SUB.shadow)
            s:SetPoint("TOPLEFT", bd.fill, "TOPLEFT", -i, i)
            s:SetPoint("BOTTOMRIGHT", bd.fill, "BOTTOMRIGHT", i, -i)
            s:SetColorTexture(0, 0, 0, 0.14)
        end
    end
    headBand(f, f, 1, 22)
    p.title = goldFont(field(field(f, "TitleContainer"), "TitleText"), 12)
end

-- le decor du volet est repasse a alpha 0 a chaque parcours (NineSlice)
local function refadePanel(f)
    for _, k in ipairs({ "NineSlice", "PortraitContainer" }) do
        local c = field(f, k)
        if c then fadeOwn(c) end
    end
end

-- cadre interieur (fond illustre de Blizzard) : panneau sombre et lisere ;
-- au-dessus du fond du volet quand l illustration est une region du volet
-- lui-meme (LFGWhoListFrame.BackgroundArt)
local function inset(f, r)
    fade(r)
    local bd = backdrop(f, r, 0.55, SUB.zone)
    follow[bd.fill] = r
    for _, e in ipairs(bd.edges) do follow[e] = r end
end

-- zone "pierre" (roles, filtres) : bande d accent et filet d or en bas ;
-- au-dessus du fond du volet (LFGBrowseFrame.Bg et
-- LFGWhoListFrame.headerBackground sont des regions du volet lui-meme)
local function band(f, r)
    fade(r)
    local C = ns.COLORS
    local fill = tex(f, "BACKGROUND", SUB.zone)
    fill:SetAllPoints(r)
    ns.UI.Gradient(fill, "VERTICAL", C.violet[1], C.violet[2], C.violet[3], 0.03, C.violet[1], C.violet[2], C.violet[3], 0.16)
    local line = tex(f, "BACKGROUND", SUB.zoneEdge)
    line:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
    line:SetHeight(1)
    ns.UI.Gradient(line, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.8, C.gold[1], C.gold[2], C.gold[3], 0)
    follow[fill], follow[line] = r, r
end

-- trait de separation : filet d or a la place
local function divider(f, r)
    fade(r)
    local C = ns.COLORS
    local line = tex(f, "OVERLAY", 1)
    line:SetPoint("LEFT", r, "LEFT", 0, 0)
    line:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    line:SetHeight(1)
    ns.UI.Gradient(line, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.75, C.gold[1], C.gold[2], C.gold[3], 0.05)
    follow[line] = r
end

-- en-tete (separateur "joueurs seuls / groupes") : degrade d accent, filet
-- d or, titre en or
local function header(f, r)
    fade(r)
    if headers[f] then return end
    local C = ns.COLORS
    local h = {}
    h.fill = tex(f, "BACKGROUND", 1)
    h.fill:SetAllPoints(r)
    ns.UI.Gradient(h.fill, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.30, C.violet[1], C.violet[2], C.violet[3], 0.03)
    h.line = tex(f, "BACKGROUND", 2)
    h.line:SetPoint("TOPLEFT", h.fill, "BOTTOMLEFT")
    h.line:SetPoint("TOPRIGHT", h.fill, "BOTTOMRIGHT")
    h.line:SetHeight(1)
    ns.UI.Gradient(h.line, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.8, C.gold[1], C.gold[2], C.gold[3], 0)
    h.hover = tex(f, "HIGHLIGHT")
    h.hover:SetAllPoints(h.fill)
    ns.UI.Gradient(h.hover, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.25, C.violet[1], C.violet[2], C.violet[3], 0.02)
    for _, key in ipairs({ "CategoryLabel", "ButtonText", "Title", "Label" }) do
        local fs = field(f, key)
        if objType(fs) == "FontString" then
            h.font = goldFont(fs, 12)
            break
        end
    end
    headers[f] = h
    claimed[f] = true
end

-- bouton de categorie (Donjons, Raids...) : l illustration reste, le cadre
-- orne passe a alpha 0 ; lisere, voile sombre a gauche (lisibilite du
-- titre) et survol en degrade, tous ancres sur l illustration (le bouton
-- est un ResizeLayoutFrame : rien ne deborde de ce qui le mesure deja)
local function category(f, r)
    fade(r)
    if cats[f] then return end
    local C = ns.COLORS
    local icon = field(f, "Icon")
    local anchor = (objType(icon) == "Texture") and icon or f
    local s = {}
    s.shade = tex(f, "BORDER", 1)
    s.shade:SetAllPoints(anchor)
    ns.UI.Gradient(s.shade, "HORIZONTAL", 0, 0, 0, 0.75, 0, 0, 0, 0.05)
    s.edges = ring(f, anchor, "OVERLAY", 6, 0)
    paintC(s.edges, C.border)
    s.hl = tex(f, "HIGHLIGHT")
    s.hl:SetAllPoints(anchor)
    ns.UI.Gradient(s.hl, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.35, C.violet[1], C.violet[2], C.violet[3], 0.05)
    local label = field(f, "Label")
    if objType(label) == "FontString" then s.label = label end
    cats[f] = s
    claimed[f] = true
end

-- ligne de resultat (Parcourir, Qui) : carte plate, choix et survol en
-- degrade ; nos textures suivent celles de Blizzard (cachees par l alpha)
local function rowOf(f)
    local s = rows[f]
    if not s then
        s = {}
        rows[f] = s
        claimed[f] = true
    end
    return s
end

local function rowBg(f, r)
    fade(r)
    local s = rowOf(f)
    if s.bg then return end
    local C = ns.COLORS
    s.bg = tex(f, "BACKGROUND", -8)
    s.bg:SetAllPoints(r)
    s.bg:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.7)
    s.edges = ring(f, s.bg, "BACKGROUND", -7, 0)
    paintC(s.edges, C.border, 0.8)
end

local function rowSel(f, r)
    fade(r)
    local s = rowOf(f)
    if s.sel then return end
    local C = ns.COLORS
    s.ref = r
    s.sel = tex(f, "BACKGROUND", -6)
    s.sel:SetAllPoints(r)
    ns.UI.Gradient(s.sel, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.5, C.violet[1], C.violet[2], C.violet[3], 0.05)
    s.bar = tex(f, "BACKGROUND", -5)
    s.bar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
    s.bar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
    s.bar:SetWidth(2)
    s.bar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    s.sel:Hide()
    s.bar:Hide()
end

local function rowHover(f, r)
    fade(r)
    local s = rowOf(f)
    if s.hov then return end
    local C = ns.COLORS
    s.hov = tex(f, "HIGHLIGHT")
    s.hov:SetAllPoints(r)
    ns.UI.Gradient(s.hov, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.25, C.violet[1], C.violet[2], C.violet[3], 0.02)
end

-- ligne d activite du volet Lister (recyclee) : les en-tetes de groupes
-- (niveau cache) recoivent la bande d accent ; + / - en or
local function activityRow(f)
    if actRows[f] then return end
    local C = ns.COLORS
    local s = {}
    s.band = tex(f, "BACKGROUND", -8)
    s.band:SetAllPoints(f)
    ns.UI.Gradient(s.band, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.28, C.violet[1], C.violet[2], C.violet[3], 0.02)
    s.line = tex(f, "BACKGROUND", -7)
    s.line:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    s.line:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    s.line:SetHeight(1)
    ns.UI.Gradient(s.line, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.6, C.gold[1], C.gold[2], C.gold[3], 0)
    s.band:Hide()
    s.line:Hide()
    s.level = field(f, "Level")
    s.toggle = field(f, "ExpandOrCollapseButton")
    actRows[f] = s
end

-- infobulle des resultats (LFGBrowseSearchEntryTooltip) : bordure de
-- Blizzard a alpha 0, fond et lisere CorpUI, bande d accent en haut
local function skinTip(tip)
    if not tips[tip] then
        local C = ns.COLORS
        local s = {}
        s.fill = tex(tip, "BACKGROUND", -8)
        s.fill:SetAllPoints(tip)
        s.fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.94)
        s.edges = ring(tip, s.fill, "BACKGROUND", -7, 0)
        paintC(s.edges, C.border)
        s.top = tex(tip, "BACKGROUND", -6)
        s.top:SetPoint("TOPLEFT", tip, "TOPLEFT", 1, -1)
        s.top:SetPoint("TOPRIGHT", tip, "TOPRIGHT", -1, -1)
        s.top:SetHeight(18)
        ns.UI.Gradient(s.top, "VERTICAL", C.violet[1], C.violet[2], C.violet[3], 0, C.violet[1], C.violet[2], C.violet[3], 0.22)
        tips[tip] = s
    end
    local nine = field(tip, "NineSlice")
    if nine then fadeOwn(nine) end
end

---------------------------------------------------------------------------
-- Onglets de droite (LargeSideTabButtonTemplate, comme les metiers)
---------------------------------------------------------------------------

local rail

local function buildRail(root)
    if rail or type(root) ~= "table" or not root.CreateTexture then return end
    local C = ns.COLORS
    rail = {}
    -- au-dessus de l ombre de Skins.lua (-8 sur la fenetre), hors de son fond
    rail.fill = tex(root, "BACKGROUND", -7)
    rail.fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.92)
    rail.edges = ring(root, rail.fill, "BACKGROUND", -6, 0)
    paintC(rail.edges, C.border)
    rail.fill:Hide()
    setShown(rail.edges, false)
end

local function skinSideTab(t)
    if sideTabs[t] then return end
    local icon = field(t, "Icon")
    if objType(icon) ~= "Texture" then return end
    for _, k in ipairs({ "Background", "SelectedTexture", "HighlightTexture" }) do fade(field(t, k)) end
    local glow = field(t, "TabGlow")
    if glow and glow.SetVertexColor then pcall(glow.SetVertexColor, glow, 1, 1, 1, 0) end
    fade(icon)
    local C = ns.COLORS
    local okH, h = pcall(t.GetHeight, t)
    h = okH and num(h) or 50
    local size = math.max(28, math.min(46, math.floor(h) - 8))
    local s = { size = size }
    s.fill = tex(t, "BACKGROUND", -6)
    s.fill:SetSize(size, size)
    s.fill:SetPoint("LEFT", t, "LEFT", 4, 0)
    s.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 1)
    s.accent = tex(t, "BACKGROUND", -5)
    s.accent:SetAllPoints(s.fill)
    ns.UI.Gradient(s.accent, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.35, C.violet[1], C.violet[2], C.violet[3], 0.05)
    s.accent:Hide()
    s.icon = tex(t, "ARTWORK", 3)
    s.icon:SetSize(size - 4, size - 4)
    s.icon:SetPoint("CENTER", s.fill, "CENTER", 0, 0)
    s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    s.edges = ring(t, s.fill, "OVERLAY", 6, 0)
    paintC(s.edges, C.border)
    s.bar = tex(t, "OVERLAY", 7)
    s.bar:SetPoint("TOPLEFT", s.fill, "TOPLEFT", 0, 0)
    s.bar:SetPoint("BOTTOMLEFT", s.fill, "BOTTOMLEFT", 0, 0)
    s.bar:SetWidth(2)
    s.bar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    s.bar:Hide()
    sideTabs[t] = s
    claimed[t] = true
end

-- icone de l onglet : celle de Blizzard (iconTexture du modele)
local function syncTabIcon(t, s)
    local src
    local okS, k = pcall(function() return t.iconTexture end)
    if okS and k ~= nil and not issecret(k) and (type(k) == "string" or type(k) == "number") then src = k end
    if src == nil then
        local icon = field(t, "Icon")
        if icon and icon.GetTexture then
            local okT, f = pcall(icon.GetTexture, icon)
            if okT and f ~= nil and not issecret(f) then src = f end
        end
    end
    if src ~= nil and src ~= s.src then
        s.src = src
        pcall(s.icon.SetTexture, s.icon, src)
        s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

local function sideTabState(t, s)
    local C = ns.COLORS
    syncTabIcon(t, s)
    local active = shown(field(t, "SelectedTexture"))
    local over = isOver(t)
    local okG, glowing = pcall(function() return t.TabGlowAnimation and t.TabGlowAnimation:IsPlaying() end)
    glowing = okG and glowing == true
    s.accent:SetShown(active)
    s.bar:SetShown(active)
    if active then
        paintC(s.edges, C.gold)
    elseif glowing then
        paintC(s.edges, C.gold, 0.35 + 0.65 * math.abs(math.sin(GetTime() * 3)))
    elseif over then
        paintC(s.edges, C.violet)
    else
        paintC(s.edges, C.border)
    end
    local v = (active or over) and 1 or 0.6
    s.icon:SetVertexColor(v, v, v, 1)
end

-- le rail couvre les onglets visibles
local function placeRail()
    if not rail then return end
    local first, last
    for t, s in pairs(sideTabs) do
        if visible(t) then
            local okT, top = pcall(t.GetTop, t)
            top = okT and num(top)
            if top then
                if not first or top > first.top then first = { s = s, top = top } end
                if not last or top < last.top then last = { s = s, top = top } end
            end
        end
    end
    local show = first ~= nil
    rail.fill:SetShown(show)
    setShown(rail.edges, show)
    if not show then return end
    rail.fill:ClearAllPoints()
    rail.fill:SetPoint("TOPLEFT", first.s.fill, "TOPLEFT", -4, 4)
    rail.fill:SetPoint("BOTTOMLEFT", last.s.fill, "BOTTOMLEFT", -4, -4)
    rail.fill:SetWidth(first.s.size + 8)
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
    local C = ns.COLORS
    for _, r in ipairs(regionsOf(f)) do
        if not mine[r] and not done[r] and objType(r) == "Texture" then
            local a = atlasOf(r)
            local act = a and actionFor(a)
            if act then
                if not AGAIN[act] then done[r] = true end
                if act == "fade" then
                    fade(r)
                elseif act == "inset" then
                    inset(f, r)
                elseif act == "band" then
                    band(f, r)
                elseif act == "divider" then
                    divider(f, r)
                elseif act == "catcover" then
                    category(f, r)
                elseif act == "rowbg" then
                    rowBg(f, r)
                elseif act == "rowsel" then
                    rowSel(f, r)
                elseif act == "rowhover" then
                    rowHover(f, r)
                elseif act == "header" then
                    header(f, r)
                elseif act == "ddbox" or act == "dropdown" then
                    fade(r)
                    plate(f, 0)
                elseif act == "tertiary" then
                    fade(r)
                    plate(f, 2)
                elseif act == "gold" then
                    tint(r, C.gold)
                end
            end
        end
    end
end

-- elements reconnus par leurs champs
local function special(f)
    local t = objType(f)
    if t == "EditBox" then
        skinEdit(f)
        return
    end
    if t == "CheckButton" then
        skinCheck(f)
        return
    end
    if field(f, "TopLeft") and field(f, "MiddleMiddle") and field(f, "BottomRight") then
        stretchButton(f)
    elseif field(f, "ExpandOrCollapseButton") and field(f, "NameButton") then
        activityRow(f)
    elseif t == "Button" and field(f, "Background") and field(f, "cover") then
        -- bouton de role : la lueur de fond disparait, l icone reste
        fade(field(f, "Background"))
    end
end

local function walk(f, depth)
    if depth > 12 or not visible(f) or sideTabs[f] then return end
    if isScrollBar(f) then
        pcall(skinScrollBar, f)
        return
    end
    if isInputScroll(f) then
        pcall(inputScroll, f)
        local sb = field(f, "ScrollBar")
        if sb and visible(sb) then pcall(classicBar, sb) end
        -- jamais dans la zone de saisie securisee
        return
    end
    scanRegions(f)
    pcall(special, f)
    for _, c in ipairs(childrenOf(f)) do walk(c, depth + 1) end
end

local function full(root)
    pcall(buildRail, root)
    for _, k in ipairs(TAB_KEYS) do
        local t = field(root, k)
        if t and t.CreateTexture then pcall(skinSideTab, t) end
    end
    for _, name in ipairs(SUBFRAMES) do
        local sub = _G[name]
        if type(sub) == "table" and sub.CreateTexture and visible(sub) then
            pcall(panel, sub)
            pcall(refadePanel, sub)
            walk(sub, 1)
        end
    end
    local refresh = field(_G.LFGBrowseFrame, "RefreshButton")
    if refresh and visible(refresh) then pcall(iconButton, refresh, 4) end
end

-- leger (5 fois par seconde, fenetre ouverte) : couleurs d etat
local function light(root)
    local C = ns.COLORS
    for f, p in pairs(panels) do
        if p.title and visible(f) then keepGold(p.title) end
    end
    for t, s in pairs(sideTabs) do
        if visible(t) then pcall(sideTabState, t, s) end
    end
    placeRail()
    for b, p in pairs(plates) do
        if p.edges and visible(b) then
            local on = enabled(b)
            paintC(p.edges, (on and isOver(b)) and C.gold or C.border)
            if p.glyph then p.glyph:SetAlpha(on and 1 or 0.35) end
        end
    end
    for b, icon in pairs(icons) do
        if icon and visible(b) then
            if enabled(b) then
                tint(icon, C.gold)
            else
                tint(icon, { 0.5, 0.5, 0.5 }, 0.6)
            end
        end
    end
    -- cases a cocher : coche (attenuee si partielle), grisee si desactivee,
    -- lisere d or au survol ; les textures de Blizzard reposees sont
    -- repassees a alpha 0
    for cb, k in pairs(checks) do
        if visible(cb) then
            fadeStates(cb, { "GetCheckedTexture", "GetDisabledCheckedTexture", "GetNormalTexture" })
            local okC, on = pcall(cb.GetChecked, cb)
            on = okC and on == true
            k.mark:SetShown(on)
            local a = enabled(cb) and 1 or 0.4
            if on and partial(cb) then a = a * 0.45 end
            k.mark:SetAlpha(a)
            paintC(k.edges, isOver(cb) and C.gold or C.border)
        end
    end
    for f, s in pairs(rows) do
        if visible(f) then
            local on = s.ref and shown(s.ref) or false
            if s.sel then
                s.sel:SetShown(on)
                s.bar:SetShown(on)
            end
            if s.edges then paintC(s.edges, on and C.gold or C.border, on and 1 or 0.8) end
        end
    end
    for f, s in pairs(actRows) do
        if visible(f) then
            local group = s.level ~= nil and not shown(s.level)
            s.band:SetShown(group)
            s.line:SetShown(group)
            local tg = s.toggle
            if tg and visible(tg) then
                tint(stateTex(tg, "GetNormalTexture"), C.gold)
                fade(stateTex(tg, "GetHighlightTexture"))
            end
        end
    end
    for t, ref in pairs(follow) do t:SetShown(shown(ref)) end
    for e, k in pairs(edits) do
        if visible(e) then
            local focus = k.focus or e
            local okF, has = pcall(focus.HasFocus, focus)
            local focused = okF and has == true
            if focused then paintC(k.edges, C.gold)
            elseif isOver(e) then paintC(k.edges, C.violet)
            else paintC(k.edges, C.border) end
            if k.glass then
                if glassActive(k, focused) then
                    tint(k.glass, C.gold, 1)
                else
                    tint(k.glass, { C.gold[1] * 0.6, C.gold[2] * 0.6, C.gold[3] * 0.6 }, 1)
                end
            end
        end
    end
    for f, s in pairs(cats) do
        if visible(f) then
            paintC(s.edges, isOver(f) and C.gold or C.border)
            if s.label then pcall(s.label.SetTextColor, s.label, C.gold[1], C.gold[2], C.gold[3]) end
        end
    end
    for f, h in pairs(headers) do
        if h.font and visible(f) then keepGold(h.font) end
    end
    for sb, b in pairs(bars) do
        if visible(sb) then
            if isOver(b.thumb) then
                b.knob:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.9)
            else
                b.knob:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.6)
            end
        end
    end
    local tip = _G.LFGBrowseSearchEntryTooltip
    if type(tip) == "table" and tip.CreateTexture and visible(tip) then pcall(skinTip, tip) end
end

-- Skins.lua : ne pas aplatir nos cadres, ne pas effacer nos textures
local prevClaimed = ns.SkinClaimed
function ns.SkinClaimed(f)
    return (type(f) == "table" and claimed[f] == true) or (prevClaimed and prevClaimed(f)) or false
end

local prevOwned = ns.SkinOwned
function ns.SkinOwned(r)
    return (type(r) == "table" and mine[r] == true) or (prevOwned and prevOwned(r)) or false
end

---------------------------------------------------------------------------

local state = { shown = false, key = "" }
local acc, walkAcc = 0, 0
local reserved = false

-- la description (zone de saisie securisee) est reservee des que l addon
-- de Blizzard est charge, meme fenetre fermee : Skins.lua ne descend
-- jamais dedans (il parcourt aussi les volets caches)
local function reserve()
    local comment = field(field(_G.LFGListingFrame, "ActivityView"), "Comment")
    if comment then
        claimed[comment] = true
        reserved = true
    end
end

-- volet et vue affiches : un changement relance tout de suite le parcours
local function pageKey()
    local ok, key = pcall(function()
        local lf = _G.LFGListingFrame
        local s = ""
        for _, p in ipairs({ lf, _G.LFGBrowseFrame, _G.LFGWhoListFrame, field(lf, "CategoryView"),
                             field(lf, "ActivityView"), field(lf, "LockedView"), field(lf, "GroupRoleButtons") }) do
            s = s .. (shown(p) and "1" or "0")
        end
        return s
    end)
    if ok and type(key) == "string" and not issecret(key) then return key end
    return ""
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if ns.ModuleOff("habillage", ev) then return end
    if event == "PLAYER_REGEN_ENABLED" then state.shown = false end
end)
pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")

ns.Every(0.2, function(dt)
    walkAcc = walkAcc + dt
    if not db() or InCombatLockdown() then return end
    local root = _G.LFGParentFrame
    if not reserved and type(root) == "table" then pcall(reserve) end
    if type(root) ~= "table" or not root.CreateTexture or not visible(root) then
        state.shown = false
        return
    end
    local key = pageKey()
    if not state.shown or key ~= state.key or walkAcc >= 0.6 then
        state.shown, state.key, walkAcc = true, key, 0
        local ok, err = pcall(full, root)
        if not ok and ns.skinsDB then
            ns.skinsDB.errors = ns.skinsDB.errors or {}
            ns.skinsDB.errors.GroupFinder = tostring(err)
        end
    end
    pcall(light, root)
end, "Habillage : RechercheGroupe", "habillage")
