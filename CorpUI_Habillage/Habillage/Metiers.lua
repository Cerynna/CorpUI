--[[--------------------------------------------------------------------------
    CorpUI - module Habillage : fenetre des metiers en profondeur
    (ProfessionsFrame de Blizzard_Professions, variante Camelot de ce client)

    Skins.lua pose deja le fond de la fenetre et aplatit les boutons rouges
    (Creer, Tout creer...) ; ici on reprend le detail :
      - onglets a icones a droite (ProfessionsOverviewTab, Professions1Tab
        a 7Tab, modele LargeSideTabButtonTemplate) : rail sombre, tuile
        carree, lisere d or pour l onglet actif ;
      - liste des recettes : panneau sombre, champ de recherche et bouton
        Filtre aplatis, en-tetes de categories en degrade d accent et titre
        en or, recette choisie et survol en degrade, separateurs en filet
        d or, barre de defilement minimaliste ;
      - detail de la recette : panneau sombre, icone du produit carree
        (masque rond retire) avec lisere de qualite, cases de reactifs
        carrees, titres "Reactifs" en or, cases a cocher, champ de quantite
        et ses boutons - / + aplatis ;
      - barre de rang du metier (et celles du livre) : fond sombre, lisere,
        remplissage CorpUI qui suit le masque de Blizzard ;
      - equipement de metier (outil, accessoires) : cases carrees ;
      - livre des metiers (volet BookPage) : cartes sombres a en-tete,
        boutons de sort carres, bouton "desapprendre" aplati ;
      - journal de fabrication et resultats de recherche reduits : fond,
        bandeau, titre en or, croix plate.
    Les decors sont reconnus par leur atlas (GetAtlas) ou par leur nom de
    champ, jamais detruits.

    Regles de ce client (valeurs secretes, taint) :
      - aucun crochet sur une fonction ou un script de Blizzard : tout passe
        par un releve periodique quand la fenetre est ouverte ;
      - aucun champ ecrit dans les tables de Blizzard : nos textures sont
        rangees dans des tables faibles a nous, indexees par le cadre ;
      - aucune taille, position, script ou attribut de Blizzard modifie :
        seulement l alpha, la couleur, le recadrage des textures, le retrait
        d un masque, et nos propres textures / textes poses dessus ;
      - rien en combat ; toute valeur lue est verifiee (pcall, issecretvalue).
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)

local issecret = issecretvalue or function() return false end
local weak = { __mode = "k" }

local mine = setmetatable({}, weak)      -- nos regions (a ne jamais traiter)
local done = setmetatable({}, weak)      -- textures de Blizzard deja traitees
local claimed = setmetatable({}, weak)   -- cadres que Skins.lua ne doit pas aplatir
local headers = setmetatable({}, weak)   -- cadre -> { title, fill, line, font }
local plates = setmetatable({}, weak)    -- bouton aplati -> { fill, edges, glyph }
local bars = setmetatable({}, weak)      -- barre de defilement -> { thumb, knob }
local checks = setmetatable({}, weak)    -- case a cocher -> { edges, mark }
local rows = setmetatable({}, weak)      -- ligne de recette -> { sel, line, ref }
local progress = setmetatable({}, weak)  -- barre d etat (categories) -> { bg, edges }
local rankBars = setmetatable({}, weak)  -- barre de rang -> { bg, fill, edges }
local boxes = setmetatable({}, weak)     -- case a icone -> { fill, edges, border }
local edits = setmetatable({}, weak)     -- champ de saisie -> { fill, edges }
local sideTabs = setmetatable({}, weak)  -- onglet de droite -> { fill, icon, ... }
local panels = setmetatable({}, weak)    -- panneau secondaire -> true
local cards = setmetatable({}, weak)     -- carte du livre -> true
local dividers = setmetatable({}, weak)  -- separateur -> notre filet
local collapse = setmetatable({}, weak)  -- icone +/- a teinter en or
local labels = setmetatable({}, weak)    -- titres de reactifs -> true
local masked = setmetatable({}, weak)    -- texture dont le masque est retire

-- decors de la fenetre, par atlas
local ATLAS = {
    -- fonds
    ["Profession-Background-Template2"] = "fade",
    ["Profession-Background-Overview"] = "fade",
    ["Professions-MinimizedView-Background"] = "fade",
    ["Professions-background-summarylist"] = "listbg",
    ["common-insideframe"] = "fade",
    ["common-framedivider"] = "fade",
    ["Professions-Equipment-Divider"] = "vline",
    ["Options_HorizontalDivider"] = "divider",
    -- en-tetes de categories et boutons +/-
    ["common-button-list-collapseExpand"] = "header",
    ["common-button-list-plus"] = "gold",
    ["common-button-list-minus"] = "gold",
    -- lignes de recettes
    ["Professions_Recipe_Active"] = "recipeSel",
    ["Professions_Recipe_Hover"] = "recipeHover",
    -- barres de rang (reprises par leurs champs)
    ["Professions-skillbar-bg"] = "fade",
    ["Professions-skillbar-frame"] = "fade",
    ["Profession-ProgressBar-frame"] = "fade",
    ["Profession-ProgressBar-BG"] = "fade",
    -- cases de reactifs et de sorts
    ["Professions-Slot-bg"] = "fade",
    ["Professions-ChoiceReagent-Frame"] = "fade",
    ["Profession-square-frame"] = "fade",
    -- cases a cocher minimalistes
    ["checkbox-minimal"] = "checkbox",
    ["checkmark-minimal"] = "fade",
    ["checkmark-minimal-disabled"] = "fade",
    -- bouton "desapprendre" du livre
    ["Profession-button-red-crossmark"] = "unlearn",
    ["Profession-button-red-crossmark-pressed"] = "fade",
    -- journal de fabrication : cartes d objet
    ["looting_itemcard_bg"] = "itemcard",
    ["looting_itemcard_stroke_normal"] = "fade",
    ["looting_itemcard_stroke_clickstate"] = "fade",
}
-- reconnus par le debut de l atlas
local PREFIX = {
    { "^common%-dropdown%-b%-button", "dropdown" },  -- bouton Filtre (l atlas suit l etat)
    -- fleche du choix d extension (common-dropdown-a-button) : Communs.lua
    { "^common%-button%-tertiary", "tertiary" },     -- bouton de lien
    { "^Profession%-overview%-[Cc]ard", "card" },    -- cartes du livre
    { "^common%-search%-border", "fade" },
    { "^uiframebackground%-nineslice", "fade" },
}
-- actions a refaire a chaque passage (Blizzard repose l atlas)
local AGAIN = { gold = true }

-- bordure de qualite d un bouton d objet : couleur lue dans le nom de l atlas
local BORDER_Q = { gray = 0, white = 1, green = 2, blue = 3, purple = 4, orange = 5, artifact = 6, account = 7 }

local function db()
    local d = ns.skinsDB
    if type(d) ~= "table" or not d.enabled then return nil end
    if d.groups and d.groups.prof == false then return nil end
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

-- bandeau d accent et filet d or sous le haut d un panneau
local function headBand(host, anchor, top, height)
    local C = ns.COLORS
    local band = tex(host, "BACKGROUND", -6)
    band:SetPoint("TOPLEFT", anchor, "TOPLEFT", 1, -top)
    band:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -1, -top)
    band:SetHeight(height or 22)
    ns.UI.Gradient(band, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.32, C.violet[1], C.violet[2], C.violet[3], 0.03)
    local line = tex(host, "BACKGROUND", -6)
    line:SetPoint("TOPLEFT", band, "BOTTOMLEFT")
    line:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT")
    line:SetHeight(1)
    ns.UI.Gradient(line, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.8, C.gold[1], C.gold[2], C.gold[3], 0)
end

-- police des titres + or ; on retient la police posee pour la reposer si
-- Blizzard change d objet de police (survol d un bouton...)
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
-- atlas "...-border-purple", sinon sa couleur de sommet
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

-- bouton a glyphe (- / + du champ de quantite, croix des panneaux)
local function glyphButton(b, glyph, size, inset, color)
    if objType(b) == nil or (plates[b] and plates[b].glyph) then return end
    fadeStates(b)
    for _, k in ipairs({ "Icon", "Overlay" }) do fade(field(b, k)) end
    local p = plate(b, inset or 2)
    -- fleche en texte : notre chevron (meme usage : SetText, SetTextColor)
    if ns.UI.IsChevron(glyph) then
        p.glyph = ns.UI.Chevron(b, size or 12, glyph)
        mine[p.glyph] = true
    else
        p.glyph = text(b, size or 12)
    end
    p.glyph:SetPoint("CENTER", 0, 0)
    p.glyph:SetText(glyph)
    p.color = color
    local c = color or ns.COLORS.gold
    p.glyph:SetTextColor(c[1], c[2], c[3])
end

-- case a cocher : carre sombre, lisere, coche d or (textures a nous)
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
end

-- champ de saisie (recherche, quantite) : la boite de Blizzard reste, ses
-- trois morceaux passent a alpha 0, notre fond et notre lisere autour
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
    edits[e] = { fill = fill, edges = edges }
    claimed[e] = true
    -- loupe en or
    local glass = field(e, "searchIcon") or field(e, "SearchIcon")
    if glass and glass.SetVertexColor then pcall(glass.SetVertexColor, glass, C.gold[1], C.gold[2], C.gold[3], 1) end
    -- champ de quantite : boutons - / +
    local dec, inc = field(e, "DecrementButton"), field(e, "IncrementButton")
    if dec then pcall(glyphButton, dec, "-", 13, 3) end
    if inc then pcall(glyphButton, inc, "+", 13, 3) end
end

---------------------------------------------------------------------------
-- Cases a icone (reactifs, produit, outils, sorts du livre)
---------------------------------------------------------------------------

local function iconBox(host, icon, border, out)
    if boxes[host] or objType(icon) ~= "Texture" then return end
    local bx = box(host, icon, out or 1)
    bx.icon, bx.border = icon, border
    boxes[host] = bx
    fade(border)
    cropIcon(icon)
    claimed[host] = true
end

-- case de reactif (ProfessionsButtonTemplate) : fond et cadre de Blizzard
-- a alpha 0, carre sombre et lisere de la qualite de l objet
local function reagentButton(b)
    local icon = field(b, "Icon")
    if not icon or boxes[b] then return end
    fade(field(b, "SlotBackground"))
    fade(field(b, "CropFrame"))
    fadeStates(b, { "GetNormalTexture", "GetPushedTexture" })
    iconBox(b, icon, field(b, "IconBorder"), 1)
end

-- icone du produit (CircularGiantItemButtonTemplate) : masque rond retire
local function outputButton(b)
    local icon = field(b, "Icon")
    if not icon or boxes[b] then return end
    local mask = field(b, "CircleMask")
    if mask and not masked[icon] and icon.RemoveMaskTexture then
        masked[icon] = true
        pcall(icon.RemoveMaskTexture, icon, mask)
    end
    iconBox(b, icon, field(b, "IconBorder"), 1)
end

-- case d equipement de metier (ItemButton de la fiche)
local function gearSlot(b)
    if boxes[b] or objType(b) == nil then return end
    local icon = field(b, "icon") or field(b, "Icon")
    if not icon then return end
    fadeStates(b, { "GetNormalTexture", "GetPushedTexture" })
    iconBox(b, icon, field(b, "IconBorder"), 1)
end

-- bouton de sort du livre (ProfessionButtonTemplate, securise : textures
-- seulement) : carre autour de la partie visible de l icone
local function spellButton(b)
    local icon = field(b, "IconTexture")
    if not icon or boxes[b] then return end
    fade(field(b, "IconTextureOverlay"))
    fadeStates(b, { "GetPushedTexture", "GetHighlightTexture", "GetCheckedTexture" })
    iconBox(b, icon, nil, -2)
    local C = ns.COLORS
    local hl = tex(b, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", icon, "TOPLEFT", 3, -3)
    hl:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -3, 3)
    hl:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.25)
end

---------------------------------------------------------------------------
-- Barres
---------------------------------------------------------------------------

-- barre de rang (ProfessionsRankBarTemplate) : le remplissage anime de
-- Blizzard passe a alpha 0, le notre suit la largeur de son masque
local function rankBar(f)
    if rankBars[f] then return end
    local C = ns.COLORS
    fade(field(f, "Background"))
    fade(field(f, "Border"))
    fade(field(f, "Fill"))
    -- l eclat est remis a alpha 1 par Blizzard : on l eteint par la couleur
    local flare = field(f, "Flare")
    if flare and flare.SetVertexColor then pcall(flare.SetVertexColor, flare, 1, 1, 1, 0) end
    local s = {}
    s.bg = tex(f, "BACKGROUND", -8)
    s.bg:SetPoint("LEFT", f, "LEFT", 2, -3)
    s.bg:SetPoint("RIGHT", f, "RIGHT", -2, -3)
    s.bg:SetHeight(15)
    s.bg:SetColorTexture(0, 0, 0, 0.6)
    s.edges = ring(f, s.bg, "BACKGROUND", -6, 0)
    paintC(s.edges, C.border)
    s.fill = tex(f, "BACKGROUND", -7)
    s.fill:SetPoint("TOPLEFT", s.bg, "TOPLEFT", 1, -1)
    s.fill:SetPoint("BOTTOMLEFT", s.bg, "BOTTOMLEFT", 1, 1)
    s.fill:SetWidth(1)
    if ns.BAR_TEXTURE then s.fill:SetTexture(ns.BAR_TEXTURE) else s.fill:SetColorTexture(1, 1, 1, 1) end
    s.fill:SetVertexColor(C.violet[1], C.violet[2], C.violet[3], 1)
    s.fill:Hide()
    rankBars[f] = s
    -- fleche du choix d extension en or (reprise par Communs.lua quand elle
    -- porte l atlas des menus de Blizzard)
    local dd = field(f, "ExpansionDropdownButton")
    local t = dd and field(dd, "Texture")
    if t and not (ns.SkinCommon and ns.SkinCommon(dd)) then
        pcall(t.SetDesaturated, t, true)
        pcall(t.SetVertexColor, t, C.gold[1], C.gold[2], C.gold[3], 1)
    end
end

local function rankRatio(f)
    local okW, w = pcall(f.GetWidth, f)
    w = okW and num(w) or nil
    local mask = field(f, "Mask")
    if w and w > 0 and mask and mask.GetWidth then
        local okM, mw = pcall(mask.GetWidth, mask)
        mw = okM and num(mw) or nil
        local okO, off = pcall(function() return f.overrideMaskRightOffset end)
        off = okO and num(off) or 0
        if mw then return math.max(0, math.min(1, (mw - off) / w)) end
    end
    local okR, ratio = pcall(function() return f.ratio end)
    return okR and num(ratio) or nil
end

local function updateRankBar(f, s)
    local p = rankRatio(f)
    local okW, w = pcall(s.bg.GetWidth, s.bg)
    w = okW and num(w) or nil
    if p and p > 0 and w and w > 2 then
        s.fill:SetWidth(math.max(1, (w - 2) * p))
        s.fill:Show()
    else
        s.fill:Hide()
    end
end

-- barre d etat des categories (ProfessionsStatusBarArtTemplate)
local function statusBar(f)
    if progress[f] then return end
    for _, k in ipairs({ "BorderLeft", "BorderMid", "BorderRight" }) do fade(field(f, k)) end
    local C = ns.COLORS
    local bg = tex(f, "BACKGROUND", -8)
    bg:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
    bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
    bg:SetColorTexture(0, 0, 0, 0.6)
    local edges = ring(f, bg, "BACKGROUND", -7, 0)
    paintC(edges, C.border)
    progress[f] = { bg = bg, edges = edges }
    if ns.BAR_TEXTURE and f.GetStatusBarTexture then
        local ok, t = pcall(f.GetStatusBarTexture, f)
        if ok and t and t.SetTexture then pcall(t.SetTexture, t, ns.BAR_TEXTURE) end
    end
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

---------------------------------------------------------------------------
-- Liste des recettes
---------------------------------------------------------------------------

-- en-tete de categorie (ListHeaderVisualTemplate)
local function header(f)
    if headers[f] then return end
    local C = ns.COLORS
    local h = {}
    h.fill = tex(f, "BACKGROUND", 1)
    h.fill:SetPoint("LEFT", f, "LEFT", 2, 0)
    h.fill:SetPoint("RIGHT", f, "RIGHT", -2, 0)
    h.fill:SetHeight(22)
    ns.UI.Gradient(h.fill, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.30, C.violet[1], C.violet[2], C.violet[3], 0.03)
    h.line = tex(f, "BACKGROUND", 2)
    h.line:SetPoint("TOPLEFT", h.fill, "BOTTOMLEFT")
    h.line:SetPoint("TOPRIGHT", h.fill, "BOTTOMRIGHT")
    h.line:SetHeight(1)
    ns.UI.Gradient(h.line, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.8, C.gold[1], C.gold[2], C.gold[3], 0)
    h.hover = tex(f, "HIGHLIGHT")
    h.hover:SetAllPoints(h.fill)
    ns.UI.Gradient(h.hover, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.25, C.violet[1], C.violet[2], C.violet[3], 0.02)
    for _, key in ipairs({ "ButtonText", "Title", "Label", "Name" }) do
        local fs = field(f, key)
        if objType(fs) == "FontString" then
            h.font = goldFont(fs, 12)
            break
        end
    end
    -- bouton +/- de la categorie
    local cb = field(f, "CollapseButton")
    local icon = cb and field(cb, "Icon")
    if icon then collapse[icon] = true end
    headers[f] = h
end

-- ligne de recette : choix et survol de Blizzard -> nos degrades
local function recipeRow(f, r, kind)
    fade(r)
    local C = ns.COLORS
    local s = rows[f]
    if not s then
        s = {}
        rows[f] = s
    end
    if kind == "sel" and not s.sel then
        s.ref = r
        s.sel = tex(f, "BACKGROUND", 1)
        s.sel:SetAllPoints(f)
        ns.UI.Gradient(s.sel, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.55, C.violet[1], C.violet[2], C.violet[3], 0.05)
        s.line = tex(f, "BACKGROUND", 2)
        s.line:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        s.line:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
        s.line:SetWidth(2)
        s.line:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
        s.sel:Hide()
        s.line:Hide()
    elseif kind == "hover" and not s.hov then
        s.hov = tex(f, "HIGHLIGHT")
        s.hov:SetAllPoints(f)
        ns.UI.Gradient(s.hov, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.25, C.violet[1], C.violet[2], C.violet[3], 0.02)
    end
end

-- separateur ("Non appris") : filet d or a la place des deux traits
local function divider(f, r)
    fade(r)
    if dividers[f] then return end
    local C = ns.COLORS
    local line = tex(f, "ARTWORK", 1)
    line:SetPoint("LEFT", r, "LEFT", 0, 0)
    line:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    line:SetHeight(1)
    ns.UI.Gradient(line, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.8, C.gold[1], C.gold[2], C.gold[3], 0)
    dividers[f] = { line = line, font = goldFont(field(f, "Label"), 11) }
end

local function vline(f, r)
    fade(r)
    if dividers[f] then return end
    local C = ns.COLORS
    local line = tex(f, "ARTWORK", 1)
    line:SetPoint("TOP", r, "TOP", 0, -4)
    line:SetPoint("BOTTOM", r, "BOTTOM", 0, 4)
    line:SetWidth(1)
    line:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
    dividers[f] = { line = line }
end

---------------------------------------------------------------------------
-- Panneaux, cartes
---------------------------------------------------------------------------

-- panneau secondaire (journal de fabrication, resultats de recherche,
-- artisans de la guilde) : decor de Blizzard a alpha 0, notre fond
local PANEL_DECOR = { "NineSlice", "Bg", "BG", "Background", "TopTileStreaks", "PortraitContainer", "TitleContainer" }

local function panel(f)
    if panels[f] or type(f) ~= "table" or not f.CreateTexture then return end
    panels[f] = true
    fadeOwn(f)
    for _, k in ipairs(PANEL_DECOR) do
        local c = field(f, k)
        if objType(c) == "Texture" then fade(c) elseif c then fadeOwn(c) end
    end
    local inset = field(f, "Inset")
    if inset then
        fadeOwn(inset)
        fadeOwn(field(inset, "NineSlice"))
        fade(field(inset, "Bg"))
    end
    -- conteneur a fond de bulle (artisans de la guilde)
    local cont = field(f, "Container")
    if cont then fadeOwn(cont) fadeOwn(field(cont, "NineSlice")) end
    local C = ns.COLORS
    local bd = backdrop(f, f, 0.96)
    for i = 1, 4 do
        local s = tex(f, "BACKGROUND", -8)
        s:SetPoint("TOPLEFT", bd.fill, "TOPLEFT", -i, i)
        s:SetPoint("BOTTOMRIGHT", bd.fill, "BOTTOMRIGHT", i, -i)
        s:SetColorTexture(0, 0, 0, 0.14)
    end
    headBand(f, f, 1, 22)
    local title = field(field(f, "TitleContainer"), "TitleText") or field(f, "TitleText") or field(f, "Title")
    if objType(title) == "FontString" then
        local h = goldFont(title, 12)
        if h then labels[title] = h end
    end
    for _, k in ipairs({ "ClosePanelButton", "CloseButton" }) do
        local b = field(f, k)
        if objType(b) == "Button" then
            pcall(glyphButton, b, "×", 15, 4, C.text)
            if plates[b] then plates[b].close = true end
        end
    end
end

-- carte du livre des metiers (Profession-overview-Card...)
local function card(f, r)
    fade(r)
    if cards[f] then return end
    cards[f] = true
    local C = ns.COLORS
    local fill = tex(f, "BACKGROUND", -8)
    fill:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -6)
    fill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 6)
    fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.6)
    paintC(ring(f, fill, "BACKGROUND", -7, 0), C.border)
    headBand(f, fill, 8, 24)
    for _, k in ipairs({ "ProfessionName", "missingHeader" }) do
        local h = goldFont(field(f, k), 12)
        if h then labels[h.fs] = h end
    end
end

-- carte du journal de fabrication (looting_itemcard_bg)
local function itemCard(f, r)
    fade(r)
    if cards[f] then return end
    cards[f] = true
    local C = ns.COLORS
    local fill = tex(f, "BACKGROUND", -8)
    fill:SetAllPoints(r)
    fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.9)
    paintC(ring(f, fill, "BACKGROUND", -7, 0), C.border)
end

-- titres des groupes de reactifs ("Reactifs :", "Optionnels")
local function reagentLabels(sf)
    for _, k in ipairs({ "Reagents", "OptionalReagents", "FinishingReagents" }) do
        local fs = field(field(sf, k), "Label")
        if objType(fs) == "FontString" and not labels[fs] then
            local h = goldFont(fs, 11)
            if h then labels[fs] = h end
        end
    end
end

---------------------------------------------------------------------------
-- Onglets de droite (LargeSideTabButtonTemplate, comme la fiche perso)
---------------------------------------------------------------------------

local TAB_KEYS = { "ProfessionsOverviewTab", "Professions1Tab", "Professions2Tab", "Professions3Tab",
                   "Professions4Tab", "Professions5Tab", "Professions6Tab", "Professions7Tab" }
local rail

local function buildRail(pf)
    if rail then return end
    local C = ns.COLORS
    rail = {}
    rail.fill = tex(pf, "BACKGROUND", -8)
    rail.fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.92)
    rail.edges = ring(pf, rail.fill, "BACKGROUND", -7, 0)
    paintC(rail.edges, C.border)
    rail.fill:Hide()
    for _, e in ipairs(rail.edges) do e:Hide() end
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

-- icone choisie par Blizzard (texture du metier, ou iconTexture du premier)
local function syncTabIcon(t, s)
    local src
    local icon = field(t, "Icon")
    if icon and icon.GetTexture then
        local okT, f = pcall(icon.GetTexture, icon)
        if okT and f ~= nil and not issecret(f) then src = f end
    end
    if src == nil then
        local okS, k = pcall(function() return t.iconTexture end)
        if okS and k ~= nil and not issecret(k) then src = k end
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

-- le rail couvre les onglets visibles (seuls les metiers appris en ont un)
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
    for _, e in ipairs(rail.edges) do e:SetShown(show) end
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
                elseif act == "header" then
                    fade(r)
                    if objType(f) == "Button" then header(f) end
                elseif act == "listbg" then
                    fade(r)
                    if not panels[f] then
                        panels[f] = true
                        backdrop(f, f, 0.55)
                    end
                elseif act == "recipeSel" then
                    recipeRow(f, r, "sel")
                elseif act == "recipeHover" then
                    recipeRow(f, r, "hover")
                elseif act == "divider" then
                    divider(f, r)
                elseif act == "vline" then
                    vline(f, r)
                elseif act == "checkbox" then
                    fade(r)
                    if objType(f) == "CheckButton" then skinCheck(f) end
                elseif act == "dropdown" then
                    fade(r)
                    plate(f, 0)
                elseif act == "tertiary" then
                    fade(r)
                    plate(f, 2)
                elseif act == "unlearn" then
                    fade(r)
                    pcall(glyphButton, f, "×", 14, 2, { 0.95, 0.35, 0.35 })
                elseif act == "card" then
                    card(f, r)
                elseif act == "itemcard" then
                    itemCard(f, r)
                elseif act == "gold" then
                    pcall(r.SetDesaturated, r, true)
                    pcall(r.SetVertexColor, r, C.gold[1], C.gold[2], C.gold[3], 1)
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
    if t == "Button" and not plates[f] and objType(field(f, "Left")) == "Texture"
        and objType(field(f, "Right")) == "Texture" and objType(field(f, "Center")) == "Texture" then
        -- bouton a trois morceaux de Blizzard (Creer, Tout creer :
        -- SharedButtonSmallTemplate) reconnu a sa forme : l atlas varie d un
        -- client a l autre (sombre a liseré dore ici, pas 128-RedButton que
        -- l habillage commun connait). Ses morceaux et sa surbrillance a
        -- alpha 0 (Blizzard change leur atlas, jamais leur alpha), notre plaque
        -- dessous ; texte et clic restent les siens. Deja eteint par
        -- l habillage commun : rien (pas de double plaque).
        if ns.SkinHasPlate and ns.SkinHasPlate(f) then return end
        local okA, a = pcall(field(f, "Left").GetAlpha, field(f, "Left"))
        if okA and num(a) == 0 then return end
        fade(field(f, "Left"))
        fade(field(f, "Right"))
        fade(field(f, "Center"))
        fadeStates(f, { "GetHighlightTexture" })
        plate(f, 1)
    elseif field(f, "Fill") and field(f, "Mask") and field(f, "Rank") and field(f, "Border") then
        rankBar(f)
    elseif field(f, "BorderLeft") and field(f, "BorderMid") and field(f, "BorderRight") then
        statusBar(f)
    elseif field(f, "SlotBackground") and field(f, "Icon") then
        reagentButton(f)
    elseif field(f, "CircleMask") and field(f, "Icon") then
        outputButton(f)
    elseif field(f, "IconTexture") and field(f, "IconTextureOverlay") then
        spellButton(f)
    end
end

local function walk(f, depth)
    if depth > 11 or not visible(f) then return end
    if sideTabs[f] then return end
    if isScrollBar(f) then
        pcall(skinScrollBar, f)
        return
    end
    scanRegions(f)
    pcall(special, f)
    for _, c in ipairs(childrenOf(f)) do walk(c, depth + 1) end
end

local GEAR_KEYS = { "Prof0ToolSlot", "Prof0Gear0Slot", "Prof0Gear1Slot", "Prof1ToolSlot", "Prof1Gear0Slot",
                    "Prof1Gear1Slot", "CookingToolSlot", "CookingGear0Slot", "FishingToolSlot",
                    "FishingGear0Slot", "FishingGear1Slot" }

local function titleText(pf)
    local fs = field(field(pf, "TitleContainer"), "TitleText") or field(pf, "TitleText")
    if objType(fs) == "FontString" then return fs end
end

local schematicBd

local function full(pf)
    pcall(buildRail, pf)
    for _, k in ipairs(TAB_KEYS) do
        local t = field(pf, k)
        if t and t.CreateTexture then pcall(skinSideTab, t) end
    end
    local cp = field(pf, "CraftingPage")
    if cp then
        for _, k in ipairs(GEAR_KEYS) do
            local b = field(cp, k)
            if b and b.CreateTexture then pcall(gearSlot, b) end
        end
        for _, k in ipairs({ "CraftingOutputLog", "MinimizedSearchResults", "GuildFrame" }) do
            local p = field(cp, k)
            if visible(p) then pcall(panel, p) end
        end
        -- detail de la recette : fond pose sur la page (le formulaire porte
        -- un layoutType : Skins.lua efface ses textures)
        local sf = field(cp, "SchematicForm")
        if sf then
            if not schematicBd and cp.CreateTexture then schematicBd = backdrop(cp, sf, 0.55) end
            reagentLabels(sf)
            local out = field(sf, "OutputIcon")
            if out then pcall(outputButton, out) end
        end
    end
    walk(pf, 1)
end

-- leger (5 fois par seconde, fenetre ouverte) : couleurs d etat
local titleFont

local function light(pf)
    local C = ns.COLORS
    local title = titleText(pf)
    if title then
        if not titleFont or titleFont.fs ~= title then titleFont = goldFont(title, 12) else keepGold(titleFont) end
    end
    for t, s in pairs(sideTabs) do
        if visible(t) then pcall(sideTabState, t, s) end
    end
    placeRail()
    for b, p in pairs(plates) do
        if p.edges and visible(b) then
            local over = isOver(b) and enabled(b)
            paintC(p.edges, over and (p.close and { 1, 0.3, 0.3 } or C.gold) or C.border)
            if p.glyph then
                local c = p.color or C.gold
                if p.close and over then c = { 1, 0.3, 0.3 } end
                p.glyph:SetTextColor(c[1], c[2], c[3])
                p.glyph:SetAlpha(enabled(b) and 1 or 0.35)
            end
        end
    end
    for cb, k in pairs(checks) do
        if visible(cb) then
            local okC, on = pcall(cb.GetChecked, cb)
            k.mark:SetShown(okC and on == true)
            k.mark:SetAlpha(enabled(cb) and 1 or 0.4)
            paintC(k.edges, isOver(cb) and C.gold or C.border)
        end
    end
    for f, s in pairs(rows) do
        if s.sel and visible(f) then
            local on = shown(s.ref)
            s.sel:SetShown(on)
            s.line:SetShown(on)
        end
    end
    for e, k in pairs(edits) do
        if visible(e) then
            local okF, focus = pcall(e.HasFocus, e)
            if okF and focus == true then paintC(k.edges, C.gold)
            elseif isOver(e) then paintC(k.edges, C.violet)
            else paintC(k.edges, C.border) end
        end
    end
    for f, s in pairs(rankBars) do
        if visible(f) then pcall(updateRankBar, f, s) end
    end
    for b, bx in pairs(boxes) do
        if visible(b) then
            fade(bx.border)
            local r, g, bl = borderColor(bx.border)
            if r then paint(bx.edges, r, g, bl, 1) else paintC(bx.edges, C.border) end
        end
    end
    for icon in pairs(collapse) do
        if visible(icon) then
            pcall(icon.SetDesaturated, icon, true)
            pcall(icon.SetVertexColor, icon, C.gold[1], C.gold[2], C.gold[3], 1)
        end
    end
    for f, h in pairs(headers) do
        if h.font and visible(f) then keepGold(h.font) end
    end
    for _, h in pairs(labels) do keepGold(h) end
    for sb, b in pairs(bars) do
        if visible(sb) then
            if isOver(b.thumb) then
                b.knob:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.9)
            else
                b.knob:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.6)
            end
        end
    end
end

-- Skins.lua : ne pas aplatir nos cadres, ne pas effacer nos textures
local prevClaimed = ns.SkinClaimed
function ns.SkinClaimed(f)
    if type(f) == "table" and claimed[f] then return true end
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

-- fenetres reprises : la fenetre des metiers (chargee a la demande) et
-- l ancien livre des metiers s il existe sur ce client
local ROOTS = { "ProfessionsFrame", "ProfessionsBookFrame" }
local state = {}     -- nom -> { shown, key }
local acc, walkAcc = 0, 0

local function pageKey(f)
    local ok, key = pcall(function()
        local cp = f.CraftingPage
        local s = ""
        for _, p in ipairs({ cp, f.BookPage, cp and cp.CraftingOutputLog, cp and cp.MinimizedSearchResults,
                             cp and cp.RecipeList }) do
            s = s .. ((type(p) == "table" and p.IsShown and p:IsShown() == true) and "1" or "0")
        end
        return s
    end)
    if ok and type(key) == "string" and not issecret(key) then return key end
    return ""
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if ns.ModuleOff("habillage", ev) then return end
    if event == "PLAYER_REGEN_ENABLED" then
        for _, st in pairs(state) do st.shown = false end
    end
end)
pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")

ns.Every(0.2, function(dt)
    walkAcc = walkAcc + dt
    if not db() or InCombatLockdown() then return end
    local walked = false
    for _, name in ipairs(ROOTS) do
        local f = _G[name]
        local st = state[name]
        if not st then
            st = {}
            state[name] = st
        end
        if type(f) == "table" and f.CreateTexture and visible(f) then
            local key = pageKey(f)
            if not st.shown or key ~= st.key or walkAcc >= 0.6 then
                st.shown, st.key, walked = true, key, true
                local ok, err = pcall(full, f)
                if not ok and ns.skinsDB then
                    ns.skinsDB.errors = ns.skinsDB.errors or {}
                    ns.skinsDB.errors.Professions = tostring(err)
                end
            end
            pcall(light, f)
        else
            st.shown = false
        end
    end
    if walked then walkAcc = 0 end
end, "Habillage : Metiers", "habillage")
