--[[--------------------------------------------------------------------------
    CorpUI - module Habillage : collections en profondeur
    (CollectionsJournal de Blizzard_Collections, variante Camelot de ce
    client : onglets lateraux, journal des montures, des mascottes facon
    Classic, coffre a jouets, objets d heritage, apparences)

    Skins.lua pose deja le fond de la fenetre, efface les encarts (cadres a
    layoutType) et aplatit les boutons rouges (Monture, Invoquer...) ; ici
    on reprend le detail :
      - onglets a icones a droite (LargeSideTabButtonTemplate, comme les
        metiers) : rail sombre, tuile carree, lisere d or pour l actif ;
      - titre de la fenetre en or (police des titres) ;
      - encarts (listes, pages de jouets / heritages / apparences) :
        panneau sombre et lisere ;
      - lignes des listes (montures, mascottes, ensembles) : carte plate,
        choix en degrade d accent et barre d or, survol en degrade, icone
        carree recadree (lisere d or si la monture / mascotte est active,
        rouge si elle ne sera jamais utilisable : etat lu chez Blizzard) ;
      - jouets et heritages (boutons securises : textures seulement) :
        cadre dore a alpha 0, carre sombre, icone recadree, lisere selon
        l etat (possede, non possede, couleur de qualite heritage) ;
      - en-tetes des heritages : degrade d accent, filet d or, titre en or ;
      - panneau du modele 3D : fond de Blizzard a alpha 0, degrade sombre
        (le modele lui-meme n est pas touche) ; boutons zoom / rotation
        aplatis ; case "Joueur" facon CorpUI ;
      - apparences : cadre des modeles remplace par un lisere (gris si non
        collectee, rouge si inutilisable, or au survol) ;
      - compteurs (Total), barre de progression (texture CorpUI), champs
        de recherche (loupe en or, attenuee sans focus ni texte), bandeau
        de progression d une recherche des apparences, boutons Filtre,
        fleches de page, barres de defilement minimalistes. Les listes
        deroulantes et les onglets du haut des apparences (Objets /
        Ensembles) sont repris par Communs.lua.
    Les decors sont reconnus par leur atlas (GetAtlas) ou par leur nom de
    champ, jamais detruits.

    Regles de ce client (valeurs secretes, taint) :
      - aucun crochet sur une fonction ou un script de Blizzard : tout passe
        par un releve periodique quand la fenetre est ouverte ;
      - aucun champ ecrit dans les tables de Blizzard : nos textures sont
        rangees dans des tables faibles a nous, indexees par le cadre ;
      - aucune taille, position, script, attribut ou visibilite de Blizzard
        modifie, aucune methode de Blizzard appelee : seulement l alpha, la
        couleur, le recadrage des textures, et nos propres textures / textes
        poses dessus. Les boutons de jouets et l invocation passent par des
        boutons / API proteges : on n y pose que des textures ;
      - rien en combat ; toute valeur lue est verifiee (pcall, issecretvalue).
----------------------------------------------------------------------------]]

local _, ns = ...

local issecret = issecretvalue or function() return false end
local weak = { __mode = "k" }

local mine = setmetatable({}, weak)      -- nos regions (a ne jamais traiter)
local done = setmetatable({}, weak)      -- textures de Blizzard deja traitees
local claimed = setmetatable({}, weak)   -- cadres que Skins.lua ne doit pas aplatir
local plates = setmetatable({}, weak)    -- bouton aplati -> { fill, edges, glyph }
local bars = setmetatable({}, weak)      -- barre de defilement -> { thumb, knob }
local checks = setmetatable({}, weak)    -- case a cocher -> { edges, mark }
local edits = setmetatable({}, weak)     -- champ de saisie -> { fill, edges, glass }
local sideTabs = setmetatable({}, weak)  -- onglet de droite -> { fill, icon, ... }
local panels = setmetatable({}, weak)    -- encart -> true
local rows = setmetatable({}, weak)      -- ligne de liste -> { pick, bar, box... }
local spells = setmetatable({}, weak)    -- jouet / heritage -> { box, icon... }
local models = setmetatable({}, weak)    -- modele d apparence -> { edges, border }
local progress = setmetatable({}, weak)  -- barre de progression -> { fill, bt }
local counts = setmetatable({}, weak)    -- compteur "Total" -> panneau
local boxes = setmetatable({}, weak)     -- hote d une icone simple -> { fill, edges, icon }
local displays = setmetatable({}, weak)  -- panneau du modele 3D -> true
local headers = setmetatable({}, weak)   -- en-tete d heritages -> { font }
local collapse = setmetatable({}, weak)  -- fleche de liste deroulante -> son bouton
local loaders = setmetatable({}, weak)   -- progression de la recherche (apparences) -> true

-- decors de la fenetre, par atlas
local ATLAS = {
    -- fond des pages (CollectionsBackgroundTemplate)
    ["collections-background-tile"] = "fade",
    ["collections-background-shadow-large"] = "fade",
    ["collections-background-shadow-small"] = "fade",
    ["collections-background-corner"] = "fade",
    -- lignes des listes (montures, mascottes, ensembles)
    ["PetList-ButtonBackground"] = "row",
    ["PetList-ButtonSelect"] = "fade",
    ["PetList-ButtonHighlight"] = "fade",
    -- en-tetes des heritages
    ["collections-slotheader"] = "header",
    -- apparences : cadre des modeles (l atlas suit l etat)
    ["transmog-wardrobe-border-collected"] = "model",
    ["transmog-wardrobe-border-uncollected"] = "model",
    ["transmog-wardrobe-border-unusable"] = "model",
    ["transmog-wardrobe-border-highlighted"] = "fade",
    ["transmog-set-model-cutoff-fade"] = "fade",
    ["transmog-set-iconrow-background"] = "fade",
    -- equipement de monture (journal des montures)
    ["mountequipment-background"] = "fade",
    ["mountequipment-insetshadow"] = "fade",
    ["mountequipment-slot-background"] = "fade",
    -- boutons du modele (zoom, rotation)
    ["common-button-square-gray-up"] = "control",
    ["common-button-square-gray-down"] = "control",
    -- listes deroulantes (classe, arme, variantes : fond textholder, fleche
    -- common-dropdown-a-button) : reprises par Communs.lua
    -- cases a cocher minimalistes
    ["checkbox-minimal"] = "checkbox",
    ["checkmark-minimal"] = "fade",
    ["checkmark-minimal-disabled"] = "fade",
    ["common-insideframe"] = "fade",
}
-- reconnus par le debut de l atlas
local PREFIX = {
    { "^common%-dropdown%-b%-button", "dropdown" },  -- bouton Filtre (l atlas suit l etat)
    { "^common%-search%-border", "fade" },
}
-- actions a refaire a chaque passage (Blizzard repose l atlas)
local AGAIN = { gold = true }

-- qualite "heritage" (Enum.ItemQuality.Heirloom)
local HEIRLOOM_QUALITY = 7

local function db()
    local d = ns.skinsDB
    if type(d) ~= "table" or not d.enabled then return nil end
    if d.groups and d.groups.system == false then return nil end
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

-- champ texte (layoutType...) : lu, jamais ecrit
local function stringField(f, key)
    if type(f) ~= "table" then return nil end
    local ok, v = pcall(function() return f[key] end)
    if ok and type(v) == "string" and not issecret(v) then return v end
end

local function fade(obj)
    if type(obj) == "table" and obj.SetAlpha and not mine[obj] then pcall(obj.SetAlpha, obj, 0) end
end

-- eteint une texture par sa couleur : tient meme si une animation de
-- Blizzard remet son alpha a 1 (cadre dore des jouets, lueur des onglets)
local function veil(obj)
    if type(obj) == "table" and obj.SetVertexColor and not mine[obj] then pcall(obj.SetVertexColor, obj, 1, 1, 1, 0) end
end

local function num(v)
    if v == nil or issecret(v) or type(v) ~= "number" then return nil end
    return v
end

-- texture de Blizzard deja a alpha 0 (eteinte par un autre habillage)
local function faded(t)
    if type(t) ~= "table" or not t.GetAlpha or mine[t] then return false end
    local ok, a = pcall(t.GetAlpha, t)
    return ok and num(a) == 0
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

-- carre sombre + lisere autour d une icone ; le lisere passe sur le calque
-- ARTWORK (au-dessus de l icone, sous les etoiles et marques "Nouveau")
local function box(host, anchor, out)
    local C = ns.COLORS
    local fill = tex(host, "BACKGROUND", -4)
    fill:SetPoint("TOPLEFT", anchor, "TOPLEFT", -out, out)
    fill:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", out, -out)
    fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.9)
    local edges = ring(host, anchor, "ARTWORK", 7, out)
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

-- police des titres + or ; on retient la police posee pour la reposer si
-- Blizzard change d objet de police. Seulement sur des titres decoratifs
-- dont Blizzard ne relit jamais la couleur.
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

-- teinte rouge posee par Blizzard (monture / mascotte jamais utilisable)
local function isRed(t)
    if type(t) ~= "table" or not t.GetVertexColor then return false end
    local ok, r, g = pcall(t.GetVertexColor, t)
    r, g = ok and num(r), ok and num(g)
    return (r and g and r > 0.8 and g < 0.5) and true or false
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

-- bouton a glyphe (fleches de page)
local function glyphButton(b, glyph, size, inset)
    if objType(b) == nil or (plates[b] and plates[b].glyph) then return end
    fadeStates(b)
    local p = plate(b, inset or 2)
    p.glyph = text(b, size or 12)
    p.glyph:SetPoint("CENTER", 0, 0)
    p.glyph:SetText(glyph)
    local c = ns.COLORS.gold
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
    claimed[cb] = true
end

-- champ de recherche : la boite de Blizzard reste, ses trois morceaux
-- passent a alpha 0, notre fond et notre lisere autour
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
    -- loupe : Blizzard repose sa couleur (0,6 / 1) au focus et a chaque
    -- frappe (SearchBoxTemplate) : elle est reteinte en or a chaque releve
    local glass = field(e, "searchIcon") or field(e, "SearchIcon")
    if objType(glass) ~= "Texture" then glass = nil end
    edits[e] = { fill = fill, edges = edges, glass = glass }
    claimed[e] = true
end

-- etat d un champ : lisere selon le focus / survol ; loupe en or plein si
-- le champ a le focus ou du texte, en or attenue sinon (meme indice que
-- le 0,6 / 1 de Blizzard)
local function editState(e, k)
    local C = ns.COLORS
    local okF, focus = pcall(e.HasFocus, e)
    focus = okF and focus == true
    if focus then paintC(k.edges, C.gold)
    elseif isOver(e) then paintC(k.edges, C.violet)
    else paintC(k.edges, C.border) end
    if k.glass then
        local okT, txt = pcall(e.GetText, e)
        local has = okT and type(txt) == "string" and not issecret(txt) and txt ~= ""
        local g = (focus or has) and 1 or 0.6
        pcall(k.glass.SetVertexColor, k.glass, C.gold[1] * g, C.gold[2] * g, C.gold[3] * g, 1)
    end
end

-- icone simple (fiche de la monture / mascotte, equipement de monture) ;
-- le carre suit la visibilite de l icone (Blizzard la cache sur la fiche
-- mascotte quand aucune mascotte n est choisie)
local function iconBox(host, icon)
    if boxes[host] or objType(icon) ~= "Texture" then return end
    local b = box(host, icon, 1)
    b.icon = icon
    boxes[host] = b
    cropIcon(icon)
    claimed[host] = true
end

local function boxState(b)
    local on = shown(b.icon)
    b.fill:SetShown(on)
    for _, x in ipairs(b.edges) do x:SetShown(on) end
end

---------------------------------------------------------------------------
-- Encarts, panneau du modele, compteurs, barres
---------------------------------------------------------------------------

-- encart (InsetFrameTemplate, CollectionsBackgroundTemplate) : Skins.lua
-- efface deja son dessin, on pose un panneau sombre a la place
local function inset(f)
    if panels[f] then return end
    panels[f] = true
    fadeOwn(f)
    fadeOwn(field(f, "NineSlice"))
    backdrop(f, f, 0.55)
end

-- panneau du modele 3D (montures, mascottes) : fond de Blizzard a alpha 0,
-- degrade sombre vers le haut ; le modele n est pas touche
local function display(f)
    if displays[f] then return end
    displays[f] = true
    for _, k in ipairs({ "YesMountsTex", "NoMountsTex", "PetBackground" }) do fade(field(f, k)) end
    local shadow = field(f, "ShadowOverlay")
    if shadow then fadeOwn(shadow) end
    local C = ns.COLORS
    local g = tex(f, "BACKGROUND", -7)
    g:SetAllPoints(f)
    ns.UI.Gradient(g, "VERTICAL", C.bg[1], C.bg[2], C.bg[3], 0.95, C.violet[1] * 0.3, C.violet[2] * 0.3, C.violet[3] * 0.3, 0.9)
    -- icone de la fiche (nom de la monture / mascotte en haut a gauche)
    for _, k in ipairs({ "InfoButton", "PetInfo" }) do
        local b = field(f, k)
        local icon = field(b, "Icon") or field(b, "icon")
        if b and b.CreateTexture and icon then pcall(iconBox, b, icon) end
    end
end

-- compteur "Total" (CollectionsCountTemplate, bordure InsetFrameTemplate3)
local function countPlate(f)
    if counts[f] then return end
    fadeOwn(f)
    counts[f] = backdrop(f, f, 0.7)
    claimed[f] = true
end

-- barre de progression (CollectionsProgressBarTemplate) : bordure, fond et
-- remplissage de Blizzard a alpha 0 ; le notre suit la valeur de la barre
local function progressBar(f)
    if progress[f] then return end
    fadeOwn(f)
    local okT, bt = pcall(f.GetStatusBarTexture, f)
    bt = okT and type(bt) == "table" and bt or nil
    fade(bt)
    local C = ns.COLORS
    local s = { bt = bt }
    s.bg = tex(f, "BACKGROUND", -8)
    s.bg:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
    s.bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
    s.bg:SetColorTexture(0, 0, 0, 0.6)
    s.edges = ring(f, s.bg, "BACKGROUND", -7, 0)
    paintC(s.edges, C.border)
    s.fill = tex(f, "ARTWORK", 1)
    s.fill:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    s.fill:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    s.fill:SetWidth(1)
    if ns.BAR_TEXTURE then s.fill:SetTexture(ns.BAR_TEXTURE) else s.fill:SetColorTexture(1, 1, 1, 1) end
    s.fill:SetVertexColor(C.violet[1], C.violet[2], C.violet[3], 1)
    s.fill:Hide()
    progress[f] = s
    claimed[f] = true
end

local function updateProgress(f, s)
    fade(s.bt)
    local okV, v = pcall(f.GetValue, f)
    local okM, lo, hi = pcall(f.GetMinMaxValues, f)
    local okW, w = pcall(f.GetWidth, f)
    v = okV and num(v) or nil
    lo, hi = okM and num(lo) or nil, okM and num(hi) or nil
    w = okW and num(w) or nil
    if v and lo and hi and hi > lo and w and w > 0 then
        local p = math.max(0, math.min(1, (v - lo) / (hi - lo)))
        if p > 0 then
            s.fill:SetWidth(math.max(1, w * p))
            s.fill:Show()
            return
        end
    end
    s.fill:Hide()
end

-- progression d une recherche des apparences (SearchBox.ProgressFrame :
-- bandeau "Chargement" ou barre, sous le champ quand la recherche dure) :
-- fond "_search-rowbg", bords de cadre de pierre et bordure de barre de
-- hauts faits a alpha 0 ; panneau sombre, barre facon CorpUI. Le cadre
-- peut etre cache : on prepare tout d avance, textures seulement.
local function searchProgress(f)
    if loaders[f] or not f.CreateTexture then return end
    loaders[f] = true
    fadeOwn(f)
    backdrop(f, f, 0.9)
    claimed[f] = true
    local bar = field(f, "ProgressBar")
    if objType(bar) == "StatusBar" and bar.CreateTexture then pcall(progressBar, bar) end
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
    for _, k in ipairs({ "Back", "Forward" }) do
        local t = field(field(sb, k), "Texture")
        if t and t.SetVertexColor then pcall(t.SetVertexColor, t, C.violet[1], C.violet[2], C.violet[3], 0.8) end
    end
    bars[sb] = { thumb = thumb, knob = knob }
    claimed[sb] = true
end

---------------------------------------------------------------------------
-- Lignes des listes (montures, mascottes, ensembles d apparences)
---------------------------------------------------------------------------

-- La ligne (208 x 46) laisse son icone 42 px a gauche : notre carte part
-- du bord de l icone. Les elements sont recycles par la ScrollBox : l etat
-- (choix, rouge, active) est relu a chaque releve.
local function row(f)
    if rows[f] or objType(f) ~= "Button" then return end
    local bg = field(f, "background") or field(f, "Background")
    local selRef = field(f, "selectedTexture") or field(f, "SelectedTexture")
    if not (bg and selRef) then return end
    local iconFrame = field(f, "IconFrame")
    local icon = field(f, "icon") or (iconFrame and field(iconFrame, "Icon"))
    local drag = field(f, "DragButton") or field(f, "dragButton")
    fade(bg)
    fade(selRef)
    fade(field(f, "HighlightTexture"))
    fadeStates(f, { "GetHighlightTexture" })
    fade(field(f, "iconBorder"))
    local C = ns.COLORS
    local s = { bg = bg, selRef = selRef, red = false }
    s.fill = tex(f, "BACKGROUND", -8)
    s.fill:SetPoint("TOPLEFT", f, "TOPLEFT", -44, -1)
    s.fill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 1)
    s.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.85)
    s.edges = ring(f, s.fill, "BACKGROUND", -7, 0)
    paintC(s.edges, C.border, 0.7)
    -- choix : degrade d accent et barre d or a gauche
    s.pick = tex(f, "BACKGROUND", -6)
    s.pick:SetAllPoints(s.fill)
    ns.UI.Gradient(s.pick, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.5, C.violet[1], C.violet[2], C.violet[3], 0.05)
    s.pick:Hide()
    s.bar = tex(f, "BACKGROUND", -5)
    s.bar:SetPoint("TOPLEFT", s.fill, "TOPLEFT", 0, 0)
    s.bar:SetPoint("BOTTOMLEFT", s.fill, "BOTTOMLEFT", 0, 0)
    s.bar:SetWidth(2)
    s.bar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    s.bar:Hide()
    -- survol (calque HIGHLIGHT : le moteur l affiche seul sur un bouton)
    s.hov = tex(f, "HIGHLIGHT")
    s.hov:SetAllPoints(s.fill)
    ns.UI.Gradient(s.hov, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.22, C.violet[1], C.violet[2], C.violet[3], 0.02)
    -- icone carree
    if objType(icon) == "Texture" then
        s.icon = icon
        s.box = box(f, icon, 1)
        cropIcon(icon)
    end
    -- bouton pose sur l icone (glisser, invoquer) : son survol et sa marque
    -- "active" deviennent les notres
    if drag and drag.CreateTexture then
        fadeStates(drag, { "GetHighlightTexture" })
        s.active = field(drag, "ActiveTexture")
        fade(s.active)
        if s.icon then
            local hl = tex(drag, "HIGHLIGHT")
            hl:SetAllPoints(s.icon)
            hl:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.25)
        end
        claimed[drag] = true
    end
    rows[f] = s
    claimed[f] = true
end

local function rowState(f, s)
    local C = ns.COLORS
    local on = shown(s.selRef)
    s.pick:SetShown(on)
    s.bar:SetShown(on)
    local red = isRed(s.bg)
    if red ~= s.red then
        s.red = red
        if red then
            s.fill:SetColorTexture(0.30, 0.04, 0.05, 0.85)
        else
            s.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.85)
        end
    end
    if s.icon and not atlasOf(s.icon) then pcall(s.icon.SetTexCoord, s.icon, 0.08, 0.92, 0.08, 0.92) end
    if s.box then
        if s.active and shown(s.active) then paintC(s.box.edges, C.gold)
        elseif red then paint(s.box.edges, 0.85, 0.2, 0.2, 1)
        else paintC(s.box.edges, C.border) end
    end
end

---------------------------------------------------------------------------
-- Jouets et heritages (CollectionsSpellButtonTemplate, boutons securises)
---------------------------------------------------------------------------

local SLOT_FRAMES = { "slotFrameCollected", "slotFrameUncollected", "slotFrameUncollectedInnerGlow" }

local function spellButton(b)
    if spells[b] then return end
    local icon = field(b, "iconTexture")
    if objType(icon) ~= "Texture" then return end
    local unc = field(b, "iconTextureUncollected")
    -- cadres dores : eteints par la couleur (l apparition d un nouveau
    -- jouet anime leur alpha)
    for _, k in ipairs(SLOT_FRAMES) do veil(field(b, k)) end
    fadeStates(b, { "GetHighlightTexture", "GetCheckedTexture" })
    local C = ns.COLORS
    local s = { icon = icon, unc = unc, heirloom = field(b, "levelBackground") ~= nil }
    s.box = box(b, icon, 1)
    cropIcon(icon)
    cropIcon(unc)
    local hl = tex(b, "HIGHLIGHT")
    hl:SetAllPoints(icon)
    hl:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.22)
    spells[b] = s
    claimed[b] = true
end

local function spellState(b, s)
    local C = ns.COLORS
    for _, k in ipairs(SLOT_FRAMES) do veil(field(b, k)) end
    if shown(s.icon) then
        local r, g, bl
        if s.heirloom then r, g, bl = qualityColor(HEIRLOOM_QUALITY) end
        if r then paint(s.box.edges, r, g, bl, 1) else paintC(s.box.edges, C.gold, 0.8) end
        s.box.fill:SetAlpha(1)
    elseif shown(s.unc) then
        paintC(s.box.edges, C.border, 0.6)
        s.box.fill:SetAlpha(1)
    else
        -- surprise (modele du cadeau) ou case vide
        paintC(s.box.edges, C.border, 0.4)
        s.box.fill:SetAlpha(0.5)
    end
end

-- en-tete de section des heritages (HeirloomHeaderTemplate)
local function header(f)
    if headers[f] then return end
    local C = ns.COLORS
    local h = {}
    h.fill = tex(f, "BACKGROUND", 1)
    h.fill:SetPoint("LEFT", f, "LEFT", 4, 0)
    h.fill:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    h.fill:SetHeight(22)
    ns.UI.Gradient(h.fill, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.30, C.violet[1], C.violet[2], C.violet[3], 0.03)
    h.line = tex(f, "BACKGROUND", 2)
    h.line:SetPoint("TOPLEFT", h.fill, "BOTTOMLEFT")
    h.line:SetPoint("TOPRIGHT", h.fill, "BOTTOMRIGHT")
    h.line:SetHeight(1)
    ns.UI.Gradient(h.line, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.8, C.gold[1], C.gold[2], C.gold[3], 0)
    -- titre : couleur posee une fois par le XML, jamais relue par Blizzard
    h.font = goldFont(field(f, "text") or field(f, "Text"), 13)
    headers[f] = h
    claimed[f] = true
end

-- modele d une apparence (WardrobeItemsModelTemplate) : cadre a alpha 0,
-- lisere a nous dont la couleur suit l atlas pose par Blizzard
local function wardrobeModel(m, r)
    fade(r)
    if models[m] or not m.CreateTexture then return end
    models[m] = { border = r, edges = ring(m, m, "OVERLAY", 6, 1) }
    paintC(models[m].edges, ns.COLORS.border)
    claimed[m] = true
end

local function modelState(m, s)
    local C = ns.COLORS
    fade(s.border)
    local a = atlasOf(s.border) or ""
    if isOver(m) then paintC(s.edges, C.gold)
    elseif a:find("uncollected", 1, true) then paint(s.edges, 0.42, 0.42, 0.45, 0.8)
    elseif a:find("unusable", 1, true) then paint(s.edges, 0.85, 0.2, 0.2, 1)
    else paintC(s.edges, C.border) end
end

---------------------------------------------------------------------------
-- Onglets de droite (LargeSideTabButtonTemplate, comme les metiers)
---------------------------------------------------------------------------

local TAB_KEYS = { "MountsTab", "PetsTab", "ToysTab", "HeirloomsTab", "WardrobeTab", "WarbandScenesTab" }
local rail

local function buildRail(cj)
    if rail then return end
    local C = ns.COLORS
    rail = {}
    rail.fill = tex(cj, "BACKGROUND", -8)
    rail.fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.92)
    rail.edges = ring(cj, rail.fill, "BACKGROUND", -7, 0)
    paintC(rail.edges, C.border)
    rail.fill:Hide()
    for _, e in ipairs(rail.edges) do e:Hide() end
end

local function skinSideTab(t)
    if sideTabs[t] then return end
    local icon = field(t, "Icon")
    if objType(icon) ~= "Texture" then return end
    for _, k in ipairs({ "Background", "SelectedTexture", "HighlightTexture" }) do fade(field(t, k)) end
    veil(field(t, "TabGlow"))
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

-- icone posee par Blizzard (TABS_DATA, lue sur sa texture)
local function syncTabIcon(t, s)
    local icon = field(t, "Icon")
    if not (icon and icon.GetTexture) then return end
    local ok, src = pcall(icon.GetTexture, icon)
    if ok and src ~= nil and not issecret(src) and src ~= s.src then
        s.src = src
        pcall(s.icon.SetTexture, s.icon, src)
        s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

local function sideTabState(t, s)
    local C = ns.COLORS
    syncTabIcon(t, s)
    veil(field(t, "TabGlow"))
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

-- le rail couvre les onglets visibles (heritages absents selon le compte)
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

-- fleche de liste deroulante : or, sauf quand Blizzard la montre
-- desactivee (atlas "...-disabled" ou bouton desactive) : elle reprend
-- alors son dessin grise d origine
local function arrowTint(icon, owner)
    local a = atlasOf(icon)
    if (a and a:find("disabled", 1, true)) or not enabled(owner) then
        pcall(icon.SetDesaturated, icon, false)
        pcall(icon.SetVertexColor, icon, 1, 1, 1, 1)
    else
        local C = ns.COLORS
        pcall(icon.SetDesaturated, icon, true)
        pcall(icon.SetVertexColor, icon, C.gold[1], C.gold[2], C.gold[3], 1)
    end
end

local function scanRegions(f)
    for _, r in ipairs(regionsOf(f)) do
        if not mine[r] and not done[r] and objType(r) == "Texture" then
            local a = atlasOf(r)
            local act = a and actionFor(a)
            if act then
                if not AGAIN[act] then done[r] = true end
                if act == "fade" then
                    fade(r)
                elseif act == "row" then
                    fade(r)
                    row(f)
                elseif act == "header" then
                    fade(r)
                    header(f)
                elseif act == "model" then
                    wardrobeModel(f, r)
                elseif act == "control" then
                    fade(r)
                    if objType(f) == "Button" then plate(f, 6) end
                elseif act == "dropdown" then
                    fade(r)
                    plate(f, 0)
                elseif act == "checkbox" then
                    fade(r)
                    if objType(f) == "CheckButton" then skinCheck(f) end
                elseif act == "gold" then
                    collapse[r] = f
                    arrowTint(r, f)
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
        -- progression de la recherche (apparences), preparee meme cachee
        local pf = field(f, "ProgressFrame")
        if pf and field(pf, "LoadingFrame") and field(pf, "ProgressBar") then searchProgress(pf) end
        return
    end
    if field(f, "LoadingFrame") and field(f, "ProgressBar") then
        searchProgress(f)
        return
    end
    if field(f, "Count") and field(f, "Label") and field(f, "BorderTopLeft") then
        countPlate(f)
        return
    end
    if t == "StatusBar" and field(f, "border") and field(f, "text") then
        progressBar(f)
        return
    end
    if field(f, "iconTexture") and field(f, "slotFrameCollected") then
        spellButton(f)
        return
    end
    if field(f, "PrevPageButton") and field(f, "NextPageButton") then
        pcall(glyphButton, field(f, "PrevPageButton"), "<", 13, 6)
        pcall(glyphButton, field(f, "NextPageButton"), ">", 13, 6)
        return
    end
    -- bouton rouge classique (Left/Middle/Right : Invoquer / Renvoi des
    -- mascottes, montures...) : Skins.lua ne le voit plus (page revendiquee).
    -- Pas un onglet (LeftActive : Objets / Ensembles des apparences, repris
    -- par Communs.lua avec ses textures d onglet actif)
    if t == "Button" and not plates[f] and not field(f, "LeftActive") and objType(field(f, "Left")) == "Texture"
        and objType(field(f, "Right")) == "Texture"
        and objType(field(f, "Middle") or field(f, "Center")) == "Texture" then
        -- deja aplati par Skins.lua (passe avant nous : Monter, a deux
        -- niveaux de la fenetre) : Blizzard ne met jamais ces textures a
        -- alpha 0, la plaque de Skins.lua reste seule
        if faded(field(f, "Left")) then return end
        fade(field(f, "Left"))
        fade(field(f, "Right"))
        fade(field(f, "Middle") or field(f, "Center"))
        local okH, hl = pcall(f.GetHighlightTexture, f)
        if okH then fade(hl) end
        plate(f, 1)
        return
    end
    if t == "Button" and (field(f, "icon") or field(f, "IconFrame"))
        and (field(f, "background") or field(f, "Background"))
        and (field(f, "selectedTexture") or field(f, "SelectedTexture")) then
        row(f)
        return
    end
    if field(f, "YesMountsTex") or field(f, "PetBackground") then display(f) end
    if field(f, "ItemIcon") and field(f, "SlotBorder") then iconBox(f, field(f, "ItemIcon")) end
    if t == "CheckButton" and field(f, "TogglePlayerText") then skinCheck(f) end
    if stringField(f, "layoutType") == "InsetFrameTemplate" then inset(f) end
end

local function walk(f, depth)
    if depth > 12 or not visible(f) then return end
    if sideTabs[f] then return end
    if isScrollBar(f) then
        pcall(skinScrollBar, f)
        return
    end
    scanRegions(f)
    pcall(special, f)
    -- elements termines : rien a chercher dedans
    if rows[f] or spells[f] or models[f] or counts[f] or progress[f] or headers[f] then return end
    for _, c in ipairs(childrenOf(f)) do walk(c, depth + 1) end
end

local function titleText(cj)
    local fs = field(field(cj, "TitleContainer"), "TitleText") or field(cj, "TitleText")
    if objType(fs) == "FontString" then return fs end
end

local titleFont

local function full(cj)
    local tc = field(cj, "TabContainer")
    if tc then
        pcall(buildRail, cj)
        for _, k in ipairs(TAB_KEYS) do
            local t = field(tc, k)
            if t and t.CreateTexture then pcall(skinSideTab, t) end
        end
    end
    walk(cj, 1)
end

-- leger (5 fois par seconde, fenetre ouverte) : couleurs d etat
local function light(cj)
    local C = ns.COLORS
    local title = cj and titleText(cj)
    if title then
        if not titleFont or titleFont.fs ~= title then titleFont = goldFont(title, 12) else keepGold(titleFont) end
    end
    for t, s in pairs(sideTabs) do
        if visible(t) then pcall(sideTabState, t, s) end
    end
    placeRail()
    for b, p in pairs(plates) do
        if p.edges and visible(b) then
            local en = enabled(b)
            paintC(p.edges, (isOver(b) and en) and C.gold or C.border)
            if p.glyph then p.glyph:SetAlpha(en and 1 or 0.35) end
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
    for e, k in pairs(edits) do
        if visible(e) then pcall(editState, e, k) end
    end
    for host, b in pairs(boxes) do
        if visible(host) then pcall(boxState, b) end
    end
    for f, s in pairs(rows) do
        if visible(f) then pcall(rowState, f, s) end
    end
    for b, s in pairs(spells) do
        if visible(b) then pcall(spellState, b, s) end
    end
    for m, s in pairs(models) do
        if visible(m) then pcall(modelState, m, s) end
    end
    for f, s in pairs(progress) do
        if visible(f) then pcall(updateProgress, f, s) end
    end
    for icon, owner in pairs(collapse) do
        if visible(icon) then pcall(arrowTint, icon, owner) end
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
end

-- Skins.lua : ne pas aplatir nos cadres, ne pas effacer nos textures
-- (chaine : ce fichier doit etre charge apres Personnage.lua)
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

-- volet affiche : un changement relance tout de suite le parcours
local PAGES = { "MountJournal", "PetJournal", "ToyBox", "HeirloomsJournal", "WardrobeCollectionFrame" }

local function pageKey()
    local ok, key = pcall(function()
        local s = ""
        for _, n in ipairs(PAGES) do
            local p = _G[n]
            s = s .. ((type(p) == "table" and p.IsShown and p:IsShown() == true) and "1" or "0")
        end
        local w = _G.WardrobeCollectionFrame
        for _, k in ipairs({ "ItemsCollectionFrame", "SetsCollectionFrame" }) do
            local p = type(w) == "table" and w[k]
            s = s .. ((type(p) == "table" and p.IsShown and p:IsShown() == true) and "1" or "0")
        end
        return s
    end)
    if ok and type(key) == "string" and not issecret(key) then return key end
    return ""
end

local ev = CreateFrame("Frame")
local wasShown, lastKey = false, nil
local acc, walkAcc = 0, 0

ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then wasShown = false end
end)
pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")

ev:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.2 then return end
    walkAcc = walkAcc + acc
    acc = 0
    if not db() or InCombatLockdown() then return end
    -- la fenetre des collections, ou l armoire seule (transmogrification)
    local cj = _G.CollectionsJournal
    local root
    if type(cj) == "table" and cj.CreateTexture and visible(cj) then
        root = cj
    else
        cj = nil
        local w = _G.WardrobeCollectionFrame
        if type(w) == "table" and w.CreateTexture and visible(w) then root = w end
    end
    if not root then
        wasShown = false
        return
    end
    local key = pageKey()
    if not wasShown or key ~= lastKey or walkAcc >= 0.8 then
        wasShown, lastKey, walkAcc = true, key, 0
        local ok, err
        if cj then ok, err = pcall(full, cj) else ok, err = pcall(walk, root, 1) end
        if not ok and ns.skinsDB then
            ns.skinsDB.errors = ns.skinsDB.errors or {}
            ns.skinsDB.errors.Collections = tostring(err)
        end
    end
    pcall(light, cj)
end)
