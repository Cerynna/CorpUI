--[[--------------------------------------------------------------------------
    CorpUI - module Habillage : grimoire en profondeur
    (PlayerSpellsFrame.SpellBookFrame de Blizzard_PlayerSpells, variante
    Camelot de ce client)

    Skins.lua garde le cadre commun de la fenetre (fond obsidienne, lisere,
    bandeau, croix) mais ne descend plus dans le grimoire : il est reclame
    ici. On reprend le detail :
      - titre de la fenetre en or (police des titres), boutons agrandir /
        reduire dessines a plat (carre creux, trait) ;
      - pages du livre : parchemin a alpha 0, un panneau sombre par page
        (deux en vue agrandie, un en vue reduite) ;
      - onglets de categories (general, classe, familier...) : tuile carree,
        icone recadree (masque retire), lisere d or et trait d or sous
        l onglet actif, icones des autres attenuees ;
      - champ de recherche aplati, loupe en or, apercu des resultats sombre
        (lignes en degrade, icones carrees) ; la fleche des reglages est
        celle de tous les menus (Communs.lua) ;
      - en-tetes de categories : degrade d accent, filet d or, titre en or ;
      - cases de sorts : carte sombre, icone carree recadree et lisere ;
        sorts passifs gardes ronds comme chez Blizzard (anneau teinte) ;
        sorts non appris et a apprendre distingues comme chez Blizzard
        (l icone garde sa desaturation, sa teinte et son alpha) ; survol en
        degrade et lisere d or ; halo violet qui pulse sur un sort absent de
        toutes les barres d action ; nom en couleur de texte, rang ou
        "Passif" en or ;
      - pagination : boutons < > plats, numero de page en couleur de texte.

    Regles de ce client (valeurs secretes, taint) : les cases lancent les
    sorts et se glissent vers les barres (chemins proteges), donc :
      - aucun crochet (hooksecurefunc, HookScript), aucun SetScript sur un
        cadre de Blizzard : tout passe par un releve periodique quand la
        fenetre est ouverte ;
      - aucun champ ecrit dans un cadre ou une table de Blizzard (cases,
        en-tetes et lignes recyclees compris) : nos textures sont rangees
        dans des tables faibles a nous, indexees par le cadre ;
      - aucune taille, position, strate, niveau, parent ou souris modifie
        chez Blizzard, aucune de leurs methodes Lua appelee : seulement
        l alpha, la couleur, la desaturation et le recadrage de leurs
        textures, le retrait du masque d une icone (remis pour un passif),
        et nos propres textures / textes poses sur leurs cadres, jamais sur
        un cadre a disposition automatique (TextContainer des cases, rangee
        d onglets, pagination, vues) ;
      - jamais de Show / Hide / SetAtlas / SetTexture sur leurs regions :
        leur etat (atlas, visibilite, alpha) sert a relever celui des cases ;
      - le menu volant des sorts (SpellFlyout, securise et partage avec les
        barres) peut devenir enfant d une case : on ne parcourt jamais les
        enfants des boutons de sort ;
      - rien en combat ; toute valeur lue est verifiee (pcall, issecretvalue).

    Releves : le passage leger (10 fois par seconde) reconnait aussi les
    cases et lignes de l apercu apparues sans changement de page (reglage
    "masquer les passifs", sort appris, frappe dans la recherche) ; une case
    n est redessinee en entier que si son etat change, si elle reapparait,
    ou a l ouverture / page tournee. Le bouton d aide (MainHelpPlateButton)
    n est pas traite : en Camelot il se cache a chaque OnShow
    (HelpPlateOverrides.lua).
----------------------------------------------------------------------------]]

local _, ns = ...

local issecret = issecretvalue or function() return false end
local weak = { __mode = "k" }

local mine = setmetatable({}, weak)      -- nos regions (a ne jamais traiter)
local claimed = setmetatable({}, weak)   -- cadres que Skins.lua ne doit pas aplatir
local masked = setmetatable({}, weak)    -- icone dont le masque est retire
local items = setmetatable({}, weak)     -- case de sort -> nos regions et son etat
local heads = setmetatable({}, weak)     -- en-tete -> { fill, line, font }
local tabs = setmetatable({}, weak)      -- onglet de categorie -> { edges, bar, icon }
local plates = setmetatable({}, weak)    -- bouton aplati -> { fill, edges, glyph }
local marks = setmetatable({}, weak)     -- bouton agrandir / reduire -> nos traits
local edits = setmetatable({}, weak)     -- champ de recherche -> { fill, edges, ... }
local rows = setmetatable({}, weak)      -- ligne de l apercu -> { sel, ref, ... }
local panels = setmetatable({}, weak)    -- conteneur deja habille -> true
local pages = setmetatable({}, weak)     -- grimoire -> { { view, fill, edges } }
local tinted = setmetatable({}, weak)    -- textures a teinter en or a chaque passage
local others = setmetatable({}, weak)    -- enfant des vues ni case ni en-tete (separateur...)

-- marges des panneaux de page autour des vues de Blizzard. Les vues sont
-- decentrees dans le livre (View1 a 85 px du bord gauche, View2 a 50 px du
-- bord droit) : calees dessus, les cartes restent centrees dans leur page
-- et les panneaux s alignent sur la rangee d outils (onglets a x = 70,
-- reglages a 30 px du bord droit). Vue agrandie : panneaux de x = 59 a 785
-- et de 856 a 1582 (grimoire de 1612) ; vue reduite : 59 a 785 (806).
local PAGE_PAD = { left = 26, top = 30, right = 20, bottom = 6 }

-- decors des pages, par champ et par atlas (Camelot, et Mainline au cas ou)
local PAGE_KEYS = { "BookBGLeft", "BookBGRight", "BookBGHalved", "TopBar", "Bookmark", "BookCornerFlipbook" }
local PAGE_ATLAS = {
    ["spellbook-Page-Left-C60"] = true,
    ["spellbook-Page-Right-C60"] = true,
    ["spellbook-corner-flipbook-evergreen"] = true,
    ["spellbook-background-evergreen-left"] = true,
    ["spellbook-background-evergreen-right"] = true,
    ["spellbook-background-evergreen-header"] = true,
    ["spellbook-background-evergreen-ribbon"] = true,
}

-- decors des onglets de categories (mode carre et mode texte)
local TAB_DECOR = { "SquareBackground", "SquareBackgroundActive", "SquareBackgroundActiveGlow",
                    "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive",
                    "LeftHighlight", "MiddleHighlight", "RightHighlight" }

-- forme d une case de sort : masque de l icone, sinon cadre de l icone
local MASK_KIND = {
    ["spellbook-item-spellicon-mask"] = "square",
    ["talents-node-circle-mask"] = "circle",
}
local BORDER_KIND = {
    ["spellbook-item-iconframe"] = "square",
    ["spellbook-item-iconframe-inactive"] = "square",
    ["talents-node-circle-gray"] = "circle",
    ["spellbook-item-iconframe-passive-inactive"] = "circle",
}

-- texte "Disponible au niveau X" : gris violace
local MUTED = { 0.65, 0.62, 0.72 }

local function db()
    local d = ns.skinsDB
    if type(d) ~= "table" or not d.enabled then return nil end
    if d.groups and d.groups.spells == false then return nil end
    return d
end

---------------------------------------------------------------------------
-- Outils (memes recettes que Metiers.lua)
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

-- lecture d un champ simple (nombre, booleen, chaine), jamais secret
local function value(f, key)
    if type(f) ~= "table" then return nil end
    local ok, v = pcall(function() return f[key] end)
    if not ok or v == nil or issecret(v) then return nil end
    local t = type(v)
    if t == "number" or t == "boolean" or t == "string" then return v end
end

local function fade(obj)
    if type(obj) == "table" and obj.SetAlpha and not mine[obj] then pcall(obj.SetAlpha, obj, 0) end
end

-- texture dont Blizzard pilote l alpha (survol, animation) : eteinte par
-- la couleur, son alpha reste lisible
local function vfade(t)
    if objType(t) == "Texture" and not mine[t] then pcall(t.SetVertexColor, t, 1, 1, 1, 0) end
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

local function alphaOf(t)
    if type(t) ~= "table" or not t.GetAlpha then return nil end
    local ok, a = pcall(t.GetAlpha, t)
    return ok and num(a) or nil
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
                                   "GetDisabledTexture" }) do
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

local function showAll(list, on)
    for _, x in ipairs(list) do x:SetShown(on) end
end

local function textColor(fs, c, k)
    if objType(fs) ~= "FontString" then return end
    k = k or 1
    pcall(fs.SetTextColor, fs, c[1] * k, c[2] * k, c[3] * k)
end

-- panneau sombre (fond, lisere) sur "host", aux dimensions de "anchor"
local function backdrop(host, anchor, alpha)
    local C = ns.COLORS
    local fill = tex(host, "BACKGROUND", -8)
    fill:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    fill:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
    fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], alpha or 0.75)
    local edges = ring(host, anchor, "BACKGROUND", -7, 0)
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

-- halo qui pulse : une animation a nous, sur notre texture
local function pulse(t)
    local ok, ag = pcall(t.CreateAnimationGroup, t)
    if not ok or type(ag) ~= "table" then return nil end
    local ok2 = pcall(function()
        ag:SetLooping("BOUNCE")
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(0.15)
        a:SetToAlpha(0.95)
        a:SetDuration(0.6)
        a:SetSmoothing("IN_OUT")
    end)
    if ok2 then return ag end
end

---------------------------------------------------------------------------
-- Boutons plats
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

-- bouton a glyphe (pagination)
local function glyphButton(b, glyph, size, inset)
    if objType(b) == nil or (plates[b] and plates[b].glyph) then return end
    fadeStates(b)
    local p = plate(b, inset or 2)
    p.glyph = text(b, size or 12)
    p.glyph:SetPoint("CENTER", 0, 0)
    p.glyph:SetText(glyph)
    local C = ns.COLORS
    p.glyph:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
end

---------------------------------------------------------------------------
-- 1. Fenetre : titre, boutons agrandir / reduire
---------------------------------------------------------------------------

local titleFont

local function windowTitle(psf)
    local fs = field(field(psf, "TitleContainer"), "TitleText")
    if objType(fs) ~= "FontString" then return end
    if not titleFont or titleFont.fs ~= fs then titleFont = goldFont(fs, 12) else keepGold(titleFont) end
end

-- agrandir : carre creux (trait du haut plus epais) ; reduire : un trait
local function markButton(b, shape)
    if objType(b) ~= "Button" or marks[b] then return end
    fadeStates(b)
    local list = {}
    if shape == "square" then
        local box = tex(b, "OVERLAY", 6)   -- simple repere, transparent
        box:SetColorTexture(0, 0, 0, 0)
        box:SetSize(10, 10)
        box:SetPoint("CENTER", b, "CENTER", 0, 0)
        list = ring(b, box, "OVERLAY", 7, 0)
        local top = tex(b, "OVERLAY", 7)
        top:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -1)
        top:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, -1)
        top:SetHeight(1)
        list[#list + 1] = top
    else
        local bar = tex(b, "OVERLAY", 7)
        bar:SetSize(10, 2)
        bar:SetPoint("CENTER", b, "CENTER", 0, -3)
        list[1] = bar
    end
    local C = ns.COLORS
    paintC(list, C.text)
    marks[b] = list
    claimed[b] = true
end

local function skinMaxMin(psf)
    local mm = field(psf, "MaximizeMinimizeButton")
    if not mm then return end
    claimed[mm] = true
    markButton(field(mm, "MaximizeButton"), "square")
    markButton(field(mm, "MinimizeButton"), "bar")
end

---------------------------------------------------------------------------
-- 2. Pages : parchemin a alpha 0, un panneau sombre par page
---------------------------------------------------------------------------

local function skinPages(sbf)
    for _, k in ipairs(PAGE_KEYS) do
        local t = field(sbf, k)
        if objType(t) == "Texture" then fade(t) end
    end
    for _, r in ipairs(regionsOf(sbf)) do
        if not mine[r] and objType(r) == "Texture" then
            local a = atlasOf(r)
            if a and PAGE_ATLAS[a] then fade(r) end
        end
    end
    if pages[sbf] or not sbf.CreateTexture then return end
    -- panneaux poses sur le grimoire, ancres sur les vues de Blizzard
    -- (View2 est cachee en vue reduite : son panneau la suit)
    local C = ns.COLORS
    local list = {}
    local paged = field(sbf, "PagedSpellsFrame")
    for _, k in ipairs({ "View1", "View2" }) do
        local v = field(paged, k)
        if objType(v) then
            local p = { view = v }
            p.fill = tex(sbf, "BACKGROUND", -8)
            p.fill:SetPoint("TOPLEFT", v, "TOPLEFT", -PAGE_PAD.left, PAGE_PAD.top)
            p.fill:SetPoint("BOTTOMRIGHT", v, "BOTTOMRIGHT", PAGE_PAD.right, -PAGE_PAD.bottom)
            p.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.45)
            p.edges = ring(sbf, p.fill, "BACKGROUND", -7, 0)
            paintC(p.edges, C.border, 0.8)
            list[#list + 1] = p
        end
    end
    pages[sbf] = list
end

local function pagesState(sbf)
    for _, p in ipairs(pages[sbf] or {}) do
        local on = shown(p.view)
        p.fill:SetShown(on)
        showAll(p.edges, on)
    end
end

---------------------------------------------------------------------------
-- 3. Onglets de categories (pool recycle de TabSystemButtonTemplate)
---------------------------------------------------------------------------

local function skinTab(t)
    if tabs[t] then return tabs[t] end
    local icon = field(t, "Icon")
    if objType(icon) ~= "Texture" or not t.CreateTexture then return nil end
    for _, k in ipairs(TAB_DECOR) do fade(field(t, k)) end
    -- masque carre de Blizzard (rogne 2 px) retire : icone recadree pleine
    local mask = field(t, "IconMask")
    if mask and not masked[icon] and icon.RemoveMaskTexture then
        masked[icon] = true
        pcall(icon.RemoveMaskTexture, icon, mask)
    end
    local C = ns.COLORS
    local s = { icon = icon }
    s.fill = tex(t, "BACKGROUND", -8)
    s.fill:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
    s.fill:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
    s.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 1)
    s.edges = ring(t, icon, "OVERLAY", 6, 1)
    paintC(s.edges, C.border)
    s.bar = tex(t, "OVERLAY", 7)
    s.bar:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", -1, -3)
    s.bar:SetPoint("TOPRIGHT", icon, "BOTTOMRIGHT", 1, -3)
    s.bar:SetHeight(2)
    s.bar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    s.bar:Hide()
    s.hl = tex(t, "HIGHLIGHT")
    s.hl:SetAllPoints(icon)
    s.hl:SetColorTexture(1, 1, 1, 0.08)
    tabs[t] = s
    claimed[t] = true
    return s
end

local function skinTabs(sbf)
    for _, t in ipairs(childrenOf(field(sbf, "CategoryTabSystem"))) do
        if objType(t) == "Button" and visible(t) then skinTab(t) end
    end
end

local function tabState(t, s)
    local C = ns.COLORS
    local icon = s.icon
    -- l icone reste visible (un ancien passage de Skins.lua l eteignait)
    if alphaOf(icon) == 0 then pcall(icon.SetAlpha, icon, 1) end
    cropIcon(icon)
    local sel = value(t, "isSelected")
    local active
    if type(sel) == "boolean" then active = sel else active = not enabled(t) end
    -- page "Sorts a venir" ouverte par-dessus (SpellsAhead) : c est son
    -- onglet qui est actif, le leur s eteint (lecture d une fonction a nous)
    if active and ns.SpellsAheadShown and ns.SpellsAheadShown() then active = false end
    local over = isOver(t)
    s.bar:SetShown(active)
    if active then paintC(s.edges, C.gold)
    elseif over then paintC(s.edges, C.violet)
    else paintC(s.edges, C.border) end
    local v = (active or over) and 1 or 0.6
    pcall(icon.SetVertexColor, icon, v, v, v, 1)
end

---------------------------------------------------------------------------
-- 4. Barre d outils : recherche, reglages, apercu des resultats
---------------------------------------------------------------------------

local function skinSearch(e)
    if edits[e] then return edits[e] end
    local l, m, r = field(e, "Left"), field(e, "Middle") or field(e, "Mid"), field(e, "Right")
    if objType(l) ~= "Texture" or objType(r) ~= "Texture" or not m or not e.CreateTexture then return nil end
    fade(l) fade(m) fade(r)
    local C = ns.COLORS
    local k = {}
    -- notre boite epouse la leur (20 px de haut, centree dans le champ)
    k.fill = tex(e, "BACKGROUND", -8)
    k.fill:SetPoint("TOPLEFT", l, "TOPLEFT", 0, 0)
    k.fill:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
    k.fill:SetColorTexture(0, 0, 0, 0.55)
    k.edges = ring(e, k.fill, "BACKGROUND", -7, 0)
    paintC(k.edges, C.border)
    k.glass = field(e, "searchIcon") or field(e, "SearchIcon")
    if objType(k.glass) == "Texture" then pcall(k.glass.SetDesaturated, k.glass, true) end
    k.clear = field(field(e, "clearButton"), "Icon")
    k.hint = field(e, "Instructions")
    edits[e] = k
    claimed[e] = true
    return k
end

-- Blizzard remet la couleur de la loupe a chaque focus / saisie : on la
-- reteint a chaque passage
local function searchState(e, k)
    local C = ns.COLORS
    local okF, focus = pcall(e.HasFocus, e)
    focus = okF and focus == true
    local okT, txt = pcall(e.GetText, e)
    local has = okT and not issecret(txt) and type(txt) == "string" and txt ~= ""
    if focus then paintC(k.edges, C.gold)
    elseif isOver(e) then paintC(k.edges, C.violet)
    else paintC(k.edges, C.border) end
    local g = (focus or has) and 1 or 0.6
    if objType(k.glass) == "Texture" then
        pcall(k.glass.SetVertexColor, k.glass, C.gold[1] * g, C.gold[2] * g, C.gold[3] * g, 1)
    end
    if objType(k.clear) == "Texture" then
        pcall(k.clear.SetVertexColor, k.clear, C.text[1], C.text[2], C.text[3], 1)
    end
    textColor(k.hint, C.text, 0.55)
end

-- fleche des reglages : en or, sur une plaque carree ; une fleche de menu
-- (common-dropdown-a-button) est reprise par Communs.lua, comme partout
local function skinDropdown(dd)
    if objType(dd) == nil or not dd.CreateTexture then return end
    if ns.SkinCommon and ns.SkinCommon(dd) then return end
    plate(dd, -4)
    local icon = field(dd, "Icon")
    if objType(icon) == "Texture" then tinted[icon] = true end
    for _, r in ipairs(regionsOf(dd)) do
        if not mine[r] and objType(r) == "Texture" then
            local a = atlasOf(r)
            if a and a:find("^common%-dropdown%-a%-button") then tinted[r] = true end
        end
    end
end

-- ligne de l apercu (resultat ou suggestion, recyclees) : fond et survol
-- de Blizzard a alpha 0, nos degrades
local function previewRow(r)
    if rows[r] or others[r] then return end
    -- forme fixe pour la vie du cadre : un refus est retenu
    if objType(r) ~= "Button" or not r.CreateTexture then others[r] = true return end
    local ref, icon = field(r, "HighlightTexture"), field(r, "Icon")
    if objType(ref) ~= "Texture" or objType(icon) ~= "Texture" then others[r] = true return end
    fadeStates(r, { "GetNormalTexture", "GetPushedTexture" })
    fade(ref)
    local C = ns.COLORS
    local s = { ref = ref, icon = icon }
    s.sel = tex(r, "BACKGROUND", -7)
    s.sel:SetAllPoints(r)
    ns.UI.Gradient(s.sel, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.45, C.violet[1], C.violet[2], C.violet[3], 0.05)
    s.sel:Hide()
    s.hov = tex(r, "HIGHLIGHT")
    s.hov:SetAllPoints(r)
    ns.UI.Gradient(s.hov, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.22, C.violet[1], C.violet[2], C.violet[3], 0.02)
    local frame = field(r, "IconFrame")
    if frame then
        -- icone de sort : carree, lisere (la desaturation de Blizzard reste)
        fade(frame)
        s.edges = ring(r, icon, "OVERLAY", 7, 1)
        paintC(s.edges, C.border)
        s.crop = true
    else
        -- loupe d une suggestion : en or
        tinted[icon] = true
    end
    s.label = field(r, "Name") or field(r, "Text")
    rows[r] = s
    claimed[r] = true
end

local function skinPreview(pc)
    if not pc.CreateTexture then return end
    if not panels[pc] then
        panels[pc] = true
        fadeOwn(pc)
        backdrop(pc, pc, 0.96)
        claimed[pc] = true
    end
    local sb = field(pc, "ScrollBox")
    local target = field(sb, "ScrollTarget")
    for _, r in ipairs(childrenOf(target)) do previewRow(r) end
    for _, r in ipairs(childrenOf(pc)) do previewRow(r) end
    local C = ns.COLORS
    textColor(field(field(pc, "OverflowCount"), "Text"), C.text, 0.6)
end

local function skinToolbar(sbf)
    local e = field(sbf, "SearchBox")
    local k = objType(e) == "EditBox" and skinSearch(e) or nil
    local dd = field(sbf, "SettingsDropdown")
    skinDropdown(dd)
    -- la fleche voisine s aligne sur le milieu de notre champ (searchState)
    if k then k.drop = dd end
end

-- fleche des reglages : sa plaque (Communs.lua) centree sur son bouton,
-- un peu plus bas que le champ de recherche de Blizzard : on la recale sur
-- le milieu du champ (memes parents, meme echelle)
local function alignDrop(k)
    if not k.drop or not ns.SkinDropShift then return end
    local okF, _, fy = pcall(k.fill.GetCenter, k.fill)
    local okB, _, by = pcall(k.drop.GetCenter, k.drop)
    if not okF or not okB or type(fy) ~= "number" or type(by) ~= "number" then return end
    ns.SkinDropShift(k.drop, math.floor(fy - by + 0.5))
end

-- apercu : ses lignes sont creees a la frappe, sans autre signe lisible
-- (il s ouvre deja sur les suggestions au focus) ; parcouru a chaque
-- passage leger tant qu il est visible (lignes connues sautees)
local function scanPreview(sbf)
    local pc = field(sbf, "SearchPreviewContainer")
    if visible(pc) then skinPreview(pc) end
end

---------------------------------------------------------------------------
-- 5. En-tetes de categories (SpellBookHeaderTemplate)
---------------------------------------------------------------------------

-- le texte de Blizzard est en haut de l en-tete, pas au milieu (vu en jeu :
-- titre au-dessus du bandeau) : le bandeau suit le centre du texte, lu par
-- sa geometrie (lecture seule), recale a chaque passage leger
local function num0(v)
    if v == nil or issecret(v) or type(v) ~= "number" then return nil end
    return v
end

local function alignHead(f, h)
    local okT, tt, tb = pcall(function() return h.txt:GetTop(), h.txt:GetBottom() end)
    local okF, ft, fb = pcall(function() return f:GetTop(), f:GetBottom() end)
    tt, tb, ft, fb = okT and num0(tt), okT and num0(tb), okF and num0(ft), okF and num0(fb)
    if not (tt and tb and ft and fb) then return end
    local dy = math.floor(((tt + tb) - (ft + fb)) / 2 + 0.5)
    if dy == h.dy then return end
    h.dy = dy
    h.fill:ClearAllPoints()
    h.fill:SetPoint("LEFT", f, "LEFT", -14, dy)
    h.fill:SetPoint("RIGHT", f, "RIGHT", -40, dy)
end

local function skinHeader(f)
    if heads[f] then return heads[f] end
    local bp, line, txt = field(f, "Backplate"), field(f, "Border"), field(f, "Text")
    if objType(bp) ~= "Texture" or objType(txt) ~= "FontString" or field(f, "Button") or not f.CreateTexture then return end
    fade(bp)
    fade(line)
    local C = ns.COLORS
    local h = {}
    h.fill = tex(f, "BACKGROUND", -8)
    h.fill:SetPoint("LEFT", f, "LEFT", -14, 0)
    h.fill:SetPoint("RIGHT", f, "RIGHT", -40, 0)
    h.fill:SetHeight(28)
    ns.UI.Gradient(h.fill, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.30, C.violet[1], C.violet[2], C.violet[3], 0.03)
    h.line = tex(f, "BACKGROUND", -7)
    h.line:SetPoint("TOPLEFT", h.fill, "BOTTOMLEFT")
    h.line:SetPoint("TOPRIGHT", h.fill, "BOTTOMRIGHT")
    h.line:SetHeight(1)
    ns.UI.Gradient(h.line, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.8, C.gold[1], C.gold[2], C.gold[3], 0)
    -- le titre est ancre sur tout l en-tete : changer sa police ne deplace rien
    h.font = goldFont(txt, 17)
    h.txt = txt
    heads[f] = h
    claimed[f] = true
    return h
end

---------------------------------------------------------------------------
-- 6. Cases de sorts (SpellBookItemTemplate, recyclees de page en page)
---------------------------------------------------------------------------

local function skinItem(f)
    if items[f] then return items[f] end
    local b = field(f, "Button")
    local icon = field(b, "Icon")
    if objType(icon) ~= "Texture" or objType(field(f, "Backplate")) ~= "Texture" or not field(f, "TextContainer") then return nil end
    if not f.CreateTexture or not b.CreateTexture then return nil end
    local C = ns.COLORS
    -- morceaux de Blizzard lus une fois (fixes pour la vie du cadre, meme
    -- recycle) : le releve periodique ne relit que leur etat
    local tc = field(f, "TextContainer")
    local it = {
        b = b, icon = icon,
        mask = field(b, "IconMask"), frame = field(b, "Border"), glowTex = field(b, "IconHighlight"),
        tback = field(b, "TrainableBackplate"), tshadow = field(b, "TrainableShadow"),
        bshadow = field(b, "BorderShadow"), sheen = field(b, "BorderSheen"), abh = field(b, "ActionBarHighlight"),
        bp = field(f, "Backplate"),
        name = field(f, "Name") or field(tc, "Name"),
        sub = field(f, "SubName") or field(tc, "SubName"),
        req = field(f, "RequiredLevel") or field(tc, "RequiredLevel"),
    }
    -- carte : sur le cadre de la case, jamais sur TextContainer (cadre a
    -- disposition automatique : nos regions changeraient sa taille)
    it.fill = tex(f, "BACKGROUND", -8)
    it.fill:SetPoint("TOPLEFT", f, "TOPLEFT", -5, 1)
    it.fill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, -1)
    it.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.5)
    it.glow = tex(f, "BACKGROUND", -7)
    it.glow:SetAllPoints(it.fill)
    ns.UI.Gradient(it.glow, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.22, C.violet[1], C.violet[2], C.violet[3], 0.02)
    it.glow:Hide()
    it.edges = ring(f, it.fill, "BACKGROUND", -6, 0)
    paintC(it.edges, C.border, 0.55)
    -- icone : lisere carre, survol immediat (calque HIGHLIGHT), halo
    it.ring = ring(b, icon, "OVERLAY", 7, 1)
    paintC(it.ring, C.border)
    it.hl = tex(b, "HIGHLIGHT")
    it.hl:SetAllPoints(icon)
    it.hl:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.22)
    it.halo = tex(b, "BACKGROUND", -8)
    it.halo:SetPoint("TOPLEFT", icon, "TOPLEFT", -4, 4)
    it.halo:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 4, -4)
    it.halo:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.9)
    it.halo:Hide()
    it.anim = pulse(it.halo)
    items[f] = it
    claimed[f] = true
    claimed[b] = true
    return it
end

-- forme de la case : "square", "circle" (passif) ou nil (illisible)
local function itemKind(it)
    local kind = MASK_KIND[atlasOf(it.mask) or ""]
    local border = atlasOf(it.frame)
    if not kind and border then kind = BORDER_KIND[border] end
    return kind, border
end

local function setMask(icon, mask, on)
    if not mask then return end
    if on and masked[icon] and icon.AddMaskTexture then
        masked[icon] = nil
        pcall(icon.AddMaskTexture, icon, mask)
    elseif not on and not masked[icon] and icon.RemoveMaskTexture then
        masked[icon] = true
        pcall(icon.RemoveMaskTexture, icon, mask)
    end
end

-- releve de l etat (lu chez Blizzard, jamais ecrit) puis rendu ; le rendu
-- n est refait que si l etat change (ou au passage complet)
local function itemState(f, it, force)
    local icon = it.icon
    local kind, border = itemKind(it)
    local unlearned
    if border then
        unlearned = border:find("%-inactive$") ~= nil
    else
        local ok, d = pcall(icon.IsDesaturated, icon)
        unlearned = ok and d == true
    end
    local trainable = shown(it.tback)
    local missing = shown(it.abh)
    -- survol de toute la case (lu par IsMouseOver), pas seulement de
    -- l icone : Blizzard ne le signale que sur l icone, et la case ne
    -- s allumait qu une fraction de seconde (vu en jeu). Sort appris seulement.
    local hover = isOver(f) and not unlearned
    local file
    local okT, fl = pcall(icon.GetTexture, icon)
    if okT and fl ~= nil and not issecret(fl) and (type(fl) == "number" or type(fl) == "string") then file = fl end
    local sig = (kind or "?") .. (unlearned and "u" or "l") .. (trainable and "t" or "-")
        .. (missing and "m" or "-") .. (hover and "h" or "-") .. tostring(file)
    if not it.anim and missing then
        it.halo:SetAlpha(0.15 + 0.8 * math.abs(math.sin(GetTime() * 2.6)))
    end
    if not force and sig == it.sig then return end
    it.sig = sig

    local C = ns.COLORS
    -- decors de Blizzard eteints (leur etat reste lisible)
    fade(it.bshadow)
    fade(it.tshadow)
    fade(it.tback)
    vfade(it.bp)
    vfade(it.sheen)
    vfade(it.abh)

    local frame, glowTex, mask = it.frame, it.glowTex, it.mask
    if kind == "square" then
        -- icone carree pleine, recadree, notre lisere
        setMask(icon, mask, false)
        cropIcon(icon)
        fade(frame)
        vfade(glowTex)
        showAll(it.ring, true)
        if hover then paintC(it.ring, C.gold)
        elseif trainable then paintC(it.ring, C.gold, 0.8)
        elseif unlearned then paint(it.ring, C.border[1] * 0.6, C.border[2] * 0.6, C.border[3] * 0.6, 1)
        else paintC(it.ring, C.border) end
        it.hl:SetAlpha(unlearned and 0 or 1)
    elseif kind == "circle" then
        -- passif : rond comme chez Blizzard (masque remis si on l avait
        -- retire sur ce cadre recycle), son anneau teinte
        setMask(icon, mask, true)
        if not atlasOf(icon) then pcall(icon.SetTexCoord, icon, 0, 1, 0, 1) end
        showAll(it.ring, false)
        it.hl:SetAlpha(0)
        local c, k = C.violet, 0.8
        if hover then c, k = C.gold, 1
        elseif trainable then c, k = C.gold, 0.8
        elseif unlearned then c, k = C.border, 1 end
        if objType(frame) == "Texture" then
            pcall(frame.SetAlpha, frame, 1)
            pcall(frame.SetDesaturated, frame, true)
            pcall(frame.SetVertexColor, frame, c[1] * k, c[2] * k, c[3] * k, 1)
        end
        if objType(glowTex) == "Texture" then
            pcall(glowTex.SetDesaturated, glowTex, true)
            pcall(glowTex.SetVertexColor, glowTex, C.gold[1], C.gold[2], C.gold[3], 1)
        end
    else
        -- forme illisible (valeur secrete) : apparence de Blizzard rendue
        setMask(icon, mask, true)
        showAll(it.ring, false)
        it.hl:SetAlpha(0)
        if objType(frame) == "Texture" then
            pcall(frame.SetAlpha, frame, 1)
            pcall(frame.SetDesaturated, frame, false)
            pcall(frame.SetVertexColor, frame, 1, 1, 1, 1)
        end
        if objType(glowTex) == "Texture" then
            pcall(glowTex.SetDesaturated, glowTex, false)
            pcall(glowTex.SetVertexColor, glowTex, 1, 1, 1, 1)
        end
    end

    -- carte : degrade et lisere d or au survol
    it.glow:SetShown(hover)
    if hover then paintC(it.edges, C.gold, 1) else paintC(it.edges, C.border, 0.55) end

    -- absent de toutes les barres : halo violet qui pulse
    it.halo:SetShown(missing)
    if it.anim then
        local okP, playing = pcall(it.anim.IsPlaying, it.anim)
        playing = okP and playing == true
        if missing and not playing then pcall(it.anim.Play, it.anim)
        elseif not missing and playing then pcall(it.anim.Stop, it.anim) end
    end

    -- textes : couleur seulement (ni police ni alpha : Blizzard a calcule
    -- leur hauteur et pilote leur alpha de sort non appris)
    textColor(it.name, C.text)
    textColor(it.sub, C.gold)
    textColor(it.req, trainable and C.gold or MUTED)
end

-- enfants des vues (passage leger) : cases et en-tetes inconnus habilles
-- des leur apparition ; un refus (separateur...) est retenu, la forme d un
-- cadre de pool ne changeant pas
local function skinViews(sbf)
    local paged = field(sbf, "PagedSpellsFrame")
    local flyout = rawget(_G, "SpellFlyout")
    for _, k in ipairs({ "View1", "View2" }) do
        local v = field(paged, k)
        if visible(v) then
            for _, f in ipairs(childrenOf(v)) do
                if not rawequal(f, flyout) and not items[f] and not heads[f] and not others[f] and visible(f) then
                    if field(f, "Button") then
                        local it = skinItem(f)
                        if it then
                            itemState(f, it, true)
                            it.vis = true
                        else
                            others[f] = true
                        end
                    elseif not skinHeader(f) then
                        others[f] = true
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- 7. Pagination
---------------------------------------------------------------------------

local movedPaging = setmetatable({}, { __mode = "k" })

local function skinPaging(sbf)
    local pc = field(field(sbf, "PagedSpellsFrame"), "PagingControls")
    if not pc then return end
    local prev, nxt = field(pc, "PrevPageButton"), field(pc, "NextPageButton")
    if objType(prev) == "Button" then glyphButton(prev, "<", 14, 6) end
    if objType(nxt) == "Button" then glyphButton(nxt, ">", 14, 6) end
    textColor(field(pc, "PageText"), ns.COLORS.text)
    -- EXCEPTION a la regle "aucune position de Blizzard" : leur pagination
    -- (XML : BOTTOMRIGHT -75, 40 de PagedSpellsFrame) touchait la derniere
    -- rangee de sorts sur notre fond sombre (vu en jeu, tous les onglets).
    -- Cadre de pagination seul (aucun chemin protege : lancer / glisser un
    -- sort ne passe pas par lui), deplace une fois, hors combat, dans la
    -- marge du bas de la page.
    if not movedPaging[pc] and not InCombatLockdown() then
        local psf = field(sbf, "PagedSpellsFrame")
        if psf and pcall(pc.ClearAllPoints, pc) then
            movedPaging[pc] = true
            pcall(pc.SetPoint, pc, "BOTTOMRIGHT", psf, "BOTTOMRIGHT", -75, 14)
        end
    end
end

---------------------------------------------------------------------------
-- Passages
---------------------------------------------------------------------------

local function report(err)
    local d = ns.skinsDB
    if type(d) == "table" then
        d.errors = d.errors or {}
        d.errors.SpellBook = tostring(err)
    end
end

local function try(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then report(err) end
end

local function spellBook(psf)
    local sbf = field(psf, "SpellBookFrame")
    if sbf and visible(sbf) then return sbf end
end

-- etat des passages ; redraw : cases a redessiner en entier au prochain
-- passage leger (ouverture, page tournee, onglet, vue, recherche)
local st = { redraw = true }

-- complet (cle de page changee, sinon toutes les 0,6 s) : cadre, pages,
-- onglets, barre d outils, pagination. Les cases et l apercu sont
-- reconnus au passage leger ; le theme ne change qu au rechargement
local function full(psf)
    try(skinMaxMin, psf)
    local sbf = spellBook(psf)
    if not sbf then return end
    try(skinPages, sbf)
    try(skinTabs, sbf)
    try(skinToolbar, sbf)
    try(skinPaging, sbf)
end

-- leger (10 fois par seconde, fenetre ouverte) : cases et lignes nouvelles,
-- etats et couleurs
local function light(psf)
    local C = ns.COLORS
    windowTitle(psf)
    for b, list in pairs(marks) do
        if visible(b) then
            local over = isOver(b) and enabled(b)
            paintC(list, over and C.gold or C.text, enabled(b) and 1 or 0.4)
        end
    end
    local sbf = spellBook(psf)
    if not sbf then return end
    try(skinViews, sbf)
    for f, h in pairs(heads) do
        if visible(f) then pcall(alignHead, f, h) end
    end
    try(scanPreview, sbf)
    pagesState(sbf)
    for t, s in pairs(tabs) do
        if visible(t) then tabState(t, s) end
    end
    for e, k in pairs(edits) do
        if visible(e) then
            searchState(e, k)
            pcall(alignDrop, k)
        end
    end
    for t in pairs(tinted) do
        if visible(t) then
            pcall(t.SetDesaturated, t, true)
            pcall(t.SetVertexColor, t, C.gold[1], C.gold[2], C.gold[3], 1)
        end
    end
    for r, s in pairs(rows) do
        if visible(r) then
            s.sel:SetShown(shown(s.ref))
            if s.crop then cropIcon(s.icon) end
            textColor(s.label, C.text)
        end
    end
    for b, p in pairs(plates) do
        if p.edges and visible(b) then
            local over = isOver(b) and enabled(b)
            paintC(p.edges, over and C.gold or C.border)
            if p.glyph then
                p.glyph:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
                p.glyph:SetAlpha(enabled(b) and 1 or 0.35)
            end
        end
    end
    -- rendu complet d une case seulement si elle reapparait (cadre de pool
    -- remontre) ou apres un redraw ; sinon seulement si sa signature change
    local redraw = st.redraw
    st.redraw = false
    for f, it in pairs(items) do
        local v = visible(f)
        if v then
            try(itemState, f, it, redraw or not it.vis)
            -- fond de case de Blizzard (Backplate) : eteint a chaque passage
            -- (vu en jeu : un voile flou restait derriere le nom apres survol)
            vfade(it.bp)
        end
        it.vis = v
    end
    for f, h in pairs(heads) do
        if h.font and visible(f) then keepGold(h.font) end
    end
end

-- Skins.lua : ne pas aplatir le grimoire (repris ici en entier), ne pas
-- effacer nos textures. Le grimoire est reconnu a la volee : vrai avant
-- meme notre premier passage.
local function bookOf()
    local psf = rawget(_G, "PlayerSpellsFrame")
    return field(psf, "SpellBookFrame")
end

local prevClaimed = ns.SkinClaimed
function ns.SkinClaimed(f)
    if type(f) == "table" then
        if claimed[f] then return true end
        local sbf = bookOf()
        if sbf and rawequal(f, sbf) then return true end
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

local function safe(v)
    if v == nil then return "-" end
    if issecret(v) then return "?" end
    local t = type(v)
    if t == "number" or t == "boolean" or t == "string" then return tostring(v) end
    return "*"
end

-- cle de page (lue, jamais ecrite) : un changement relance tout de suite
-- un passage complet (page tournee, onglet, vue reduite, recherche)
local function pageKey(psf)
    local sbf = field(psf, "SpellBookFrame")
    local paged = field(sbf, "PagedSpellsFrame")
    local parts = {
        safe(value(field(paged, "PagingControls"), "currentPage")),
        safe(value(field(sbf, "CategoryTabSystem"), "selectedTabID")),
        safe(value(psf, "isMinimized")),
        safe(value(sbf, "isInSearchResultsMode")),
        visible(sbf) and "1" or "0",
        visible(field(sbf, "SearchPreviewContainer")) and "1" or "0",
    }
    return table.concat(parts, ":")
end

local acc, walkAcc = 0, 0

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then st.shown = false end
end)
pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")

ev:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.1 then return end
    walkAcc = walkAcc + acc
    acc = 0
    if not db() or InCombatLockdown() then
        st.shown = false
        return
    end
    local psf = rawget(_G, "PlayerSpellsFrame")
    if type(psf) ~= "table" or not psf.CreateTexture or not visible(psf) then
        st.shown = false
        return
    end
    local okK, key = pcall(pageKey, psf)
    key = okK and key or ""
    if not st.shown or key ~= st.key or walkAcc >= 0.6 then
        if not st.shown or key ~= st.key then st.redraw = true end
        st.shown, st.key, walkAcc = true, key, 0
        try(full, psf)
    end
    try(light, psf)
end)
