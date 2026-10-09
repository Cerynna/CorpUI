--[[--------------------------------------------------------------------------
    CorpUI - module Habillage : fenetre Heritage en profondeur
    (LegacySystemFrame de Blizzard_LegacySystem, propre au client Camelot,
    chargee a la demande)

    La fenetre a trois volets, choisis par trois onglets a icones a droite
    (LegacyRewardTrackTab, LegacyChallengeTab, LegacyTreeTab, modele
    LargeSideTabButtonTemplate) :
      - piste de recompenses (RewardTrackPage) : embleme et total de points,
        barre de progression, cartes de palier (RenownLevelMixin, recyclees
        par un pool) et fleches de defilement ;
      - defis (ChallengesPage) : resume des points (barre), liste des
        categories (ScrollBox recyclee, champ de recherche, bouton Filtre),
        detail : cartes de defi (recyclees), criteres (pool) et leurs barres,
        case "Suivre" ;
      - arbre (TreePage) : trois cartes de choix de l arbre, grand anneau de
        l arbre choisi, total de points depense, arbre de talents partage
        (noeuds achetes / disponibles / verrouilles, liens), boutons
        Appliquer / Annuler / Reinitialiser, recherche et ses suggestions.
    Ce qui est fait :
      - decors reconnus par leur atlas ou leur champ, passes a alpha 0 ;
      - fonds, plaques, liserés, bandeaux en degrade d accent, filets d or,
        icones carrees recadrees, barres a la texture CorpUI : textures a
        nous posees sur les cadres de Blizzard ;
      - couleurs d information de Blizzard gardees (etat des noeuds et des
        liens, palier atteint / courant / a venir, defi accompli ou non,
        defi de compte en bleu, textes grises).
    Si Habillage/Fenetres.lua ne connait pas la fenetre, ce fichier pose
    aussi le fond, le bandeau, la croix et le titre (comme Skins.lua) ; s il
    la connait, Skins.lua s en charge et on ne fait que l interieur.

    Regles de ce client (valeurs secretes, taint ; achat de noeud et
    validation passent par C_Traits, "AllowedWhenUntainted") :
      - aucun crochet, aucun SetScript, aucune fonction ni methode de
        Blizzard appelee (seulement les methodes du moteur : alpha, couleur,
        recadrage, retrait de masque, lecture d atlas / d etat) ;
      - aucun champ ecrit dans les tables de Blizzard : nos textures sont
        rangees dans des tables faibles a nous, indexees par le cadre ;
      - aucune taille, position, strate, parent, visibilite de Blizzard
        modifiee ; seuls deux titres decoratifs (titre de la fenetre, nom
        de l arbre choisi) prennent police et couleur ; le libelle des
        points ne prend que la couleur (la barre de la piste est ancree sous
        lui : une autre police changerait sa hauteur et deplacerait la piste) ;
      - releve periodique quand la fenetre est ouverte (leger a 0,2 s,
        parcours complet a 0,6 s ou au changement de volet / d arbre) ;
      - rien en combat ; toute valeur lue est verifiee (pcall, issecretvalue).
----------------------------------------------------------------------------]]

local _, ns = ...

local issecret = issecretvalue or function() return false end
local weak = { __mode = "k" }

local ROOT = "LegacySystemFrame"
local TAB_KEYS = { "LegacyRewardTrackTab", "LegacyChallengeTab", "LegacyTreeTab" }
local PAGE_KEYS = { "RewardTrackPage", "ChallengesPage", "TreePage" }

local mine = setmetatable({}, weak)      -- nos regions (a ne jamais traiter)
local done = setmetatable({}, weak)      -- textures de Blizzard deja traitees
local claimed = setmetatable({}, weak)   -- cadres que Skins.lua ne doit pas aplatir
local plates = setmetatable({}, weak)    -- bouton aplati -> { fill, edges, glyph }
local checks = setmetatable({}, weak)    -- case a cocher -> { edges, mark }
local edits = setmetatable({}, weak)     -- champ de saisie -> { fill, edges }
local bars = setmetatable({}, weak)      -- barre de defilement -> { thumb, knob }
local progress = setmetatable({}, weak)  -- barre de progression -> { bg, fill, ref }
local sideTabs = setmetatable({}, weak)  -- onglet de droite -> { fill, icon, ... }
local cats = setmetatable({}, weak)      -- ligne de categorie -> nos degrades
local cards = setmetatable({}, weak)     -- carte de defi -> nos regions
local crits = setmetatable({}, weak)     -- critere de defi -> { fill, edges, ref }
local rewards = setmetatable({}, weak)   -- carte de palier -> nos regions
local trees = setmetatable({}, weak)     -- carte de choix d arbre -> nos regions
local nodes = setmetatable({}, weak)     -- noeud de l arbre -> { inner, outer }
local tints = setmetatable({}, weak)     -- texture teintee -> genre ("gold", "edge"...)
local owned = setmetatable({}, weak)     -- texture teintee par son cadre (pas par tints)
local labels = setmetatable({}, weak)    -- titre decoratif -> { fs, size, file }
local panels = setmetatable({}, weak)    -- panneau sombre deja pose
local dividers = setmetatable({}, weak)  -- separateur -> notre filet
local rows = setmetatable({}, weak)      -- suggestion de recherche -> true
local masked = setmetatable({}, weak)    -- texture dont le masque est retire

-- decors de la fenetre, par atlas
local ATLAS = {
    -- fonds des trois volets
    ["Legacy-Rewards-Tracker-background"] = "fade",
    ["Legacy-Challenge-BG"] = "fade",
    ["Legacy-Tree-Frame-background"] = "fade",
    -- barres de progression (le cadre et le fond ; la barre est reprise)
    ["Legacy-Progressbar-BG"] = "fade",
    ["Legacy-Progressbar-Frame"] = "fade",
    -- separateur vertical (defis, arbre)
    ["Legacy-Tree-Frame-divider-Vertical"] = "vline",
    -- arbre : pastille des points depenses, barre des points disponibles
    ["Legacy-Tree-Frame-level-circle"] = "spent",
    ["Legacy-Tree-Frame-Points-Bar"] = "pointsbar",
    -- anneaux des cartes d arbre et du grand embleme
    ["Legacy-Tree-Frame-Card-Ring"] = "ring",
    ["Legacy-Tree-Frame-Ring-big"] = "ring",
    -- lignes de categories (reprises par leurs champs)
    ["common-button-list-collapseExpand"] = "fade",
    ["Legacy-Challenge-Left-Sub-Tab"] = "fade",
    ["Legacy-Challenge-Left-Sub-Tab-selected"] = "fade",
    -- boutons + / - (categories, cartes de defi) en or
    ["common-button-list-plus"] = "gold",
    ["common-button-list-minus"] = "gold",
    ["128-redbutton-plus"] = "gold",
    ["128-redbutton-minus"] = "gold",
    -- suggestions de la recherche de l arbre
    ["_search-rowbg"] = "searchrow",
    ["talents-search-suggestion-itemborder"] = "fade",
    ["search-highlight"] = "violet",
    -- cases a cocher minimalistes (au cas ou)
    ["checkbox-minimal"] = "checkbox",
    ["checkmark-minimal"] = "fade",
    ["checkmark-minimal-disabled"] = "fade",
}
-- reconnus par le debut de l atlas
local PREFIX = {
    { "^talents%-arrow%-line%-", "edge" },       -- liens de l arbre
    { "^talents%-arrow%-head%-", "edge" },
    { "^common%-dropdown%-b%-button", "dropdown" }, -- bouton Filtre (l atlas suit l etat)
    { "^common%-search%-border", "fade" },
}

-- couleurs d etat (celles de Blizzard, en plus sobre)
local GREEN = { 0.30, 0.85, 0.40 }
local RED = { 1.00, 0.28, 0.28 }
local GRAY = { 0.36, 0.34, 0.40 }
local DARK = { 0.20, 0.18, 0.25 }
local BLUE = { 0.30, 0.55, 1.00 }

-- groupe de la fenetre dans Habillage/Fenetres.lua (absent : cle "legacy")
local listed

local function listedKey()
    if listed == nil then
        listed = false
        for _, g in ipairs(ns.SKIN_GROUPS or {}) do
            for _, w in ipairs(g.windows or {}) do
                if w[1] == ROOT then listed = g.key end
            end
        end
    end
    return listed or nil
end

local function db()
    local d = ns.skinsDB
    if type(d) ~= "table" or not d.enabled then return nil end
    local key = listedKey() or "legacy"
    if d.groups and d.groups[key] == false then return nil end
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

local function isTex(o)
    local t = objType(o)
    return t == "Texture" or t == "Line"
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
    return ok and not issecret(v) and v == true
end

local function shown(f)
    if type(f) ~= "table" or not f.IsShown then return false end
    local ok, v = pcall(f.IsShown, f)
    return ok and not issecret(v) and v == true
end

local function isOver(f)
    if type(f) ~= "table" or not f.IsMouseOver then return false end
    local ok, v = pcall(f.IsMouseOver, f)
    return ok and not issecret(v) and v == true
end

local function enabled(f)
    if type(f) ~= "table" or not f.IsEnabled then return true end
    local ok, v = pcall(f.IsEnabled, f)
    return not (ok and not issecret(v) and v == false)
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

-- texture d etat d un bouton (getter du moteur)
local function stateTex(b, get)
    if type(b) ~= "table" or not b[get] then return nil end
    local ok, t = pcall(b[get], b)
    if ok and isTex(t) then return t end
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
        fade(stateTex(b, get))
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

-- carre sombre + lisere autour de "anchor" (fond sur fillLayer)
local function box(host, anchor, out, fillLayer, fillSub)
    local C = ns.COLORS
    local fill = tex(host, fillLayer or "BACKGROUND", fillSub or -8)
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
-- elle change (seulement sur des titres decoratifs que Blizzard ne relit pas)
-- sans taille : couleur seulement (texte sur lequel un cadre est ancre)
local function goldFont(fs, size)
    if objType(fs) ~= "FontString" then return nil end
    local C = ns.COLORS
    local file
    if size then
        pcall(ns.UI.HeadFont, fs, size)
        local ok, f = pcall(fs.GetFont, fs)
        if ok and not issecret(f) and type(f) == "string" then file = f end
    end
    pcall(fs.SetTextColor, fs, C.gold[1], C.gold[2], C.gold[3])
    return { fs = fs, size = size, file = file }
end

local function keepGold(h)
    if not h or not h.fs then return end
    if h.size and h.file then
        local ok, file = pcall(h.fs.GetFont, h.fs)
        if ok and not issecret(file) and type(file) == "string" and file ~= h.file then
            pcall(ns.UI.HeadFont, h.fs, h.size)
        end
    end
    local C = ns.COLORS
    pcall(h.fs.SetTextColor, h.fs, C.gold[1], C.gold[2], C.gold[3])
end

local function label(fs, size)
    if objType(fs) ~= "FontString" or labels[fs] then return end
    local h = goldFont(fs, size)
    if h then labels[fs] = h end
end

---------------------------------------------------------------------------
-- Boutons, cases, champs, barres de defilement
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

-- bouton a glyphe (fleches de la piste)
local function glyphButton(b, glyph, size, inset, color)
    if objType(b) == nil or (plates[b] and plates[b].glyph) then return end
    fadeStates(b)
    local p = plate(b, inset or 2)
    p.glyph = text(b, size or 12)
    p.glyph:SetPoint("CENTER", 0, 0)
    p.glyph:SetText(glyph)
    p.color = color
    local c = color or ns.COLORS.gold
    p.glyph:SetTextColor(c[1], c[2], c[3])
end

-- bouton rouge (Appliquer) : trois tranches a alpha 0, plaque plate
local function panelButton(b)
    if plates[b] then return end
    local l, m, r = field(b, "Left"), field(b, "Middle") or field(b, "Center"), field(b, "Right")
    if not (isTex(l) and isTex(m) and isTex(r)) then return end
    local hl = stateTex(b, "GetHighlightTexture")
    fade(l) fade(m) fade(r) fade(hl)
    -- Blizzard change la texture des tranches (survol, clic) : alpha repris
    plate(b, 1).parts = { l, m, r, hl }
end

-- bouton a icone (Annuler, Reinitialiser) : l icone reste, plaque dessous
local function iconButton(b)
    if objType(b) ~= "Button" or plates[b] then return end
    plate(b, 0)
end

-- case a cocher : carre sombre, lisere, coche d or (textures a nous)
local function skinCheck(cb)
    if checks[cb] or objType(cb) ~= "CheckButton" then return end
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

-- champ de recherche : ses trois morceaux a alpha 0, notre fond et lisere
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
    -- loupe : Blizzard la repasse en blanc (champ utilise) ou en gris (vide,
    -- sans focus) a chaque focus / texte ; reteintee en or vif / terne au
    -- releve leger (glassState)
    local glass = field(e, "searchIcon") or field(e, "SearchIcon")
    if not (isTex(glass) and glass.SetVertexColor) then glass = nil end
    edits[e] = { fill = fill, edges = edges, glass = glass }
    claimed[e] = true
    if glass then pcall(glass.SetVertexColor, glass, C.gold[1] * 0.6, C.gold[2] * 0.6, C.gold[3] * 0.6, 1) end
end

-- couleur de la loupe : meme information que Blizzard (focus ou texte saisi)
local function glassState(e, k, focus)
    if not k.glass then return end
    local active = focus
    if not active then
        local okT, txt = pcall(e.GetText, e)
        active = okT and not issecret(txt) and type(txt) == "string" and txt ~= ""
    end
    local C, m = ns.COLORS, active and 1 or 0.6
    pcall(k.glass.SetVertexColor, k.glass, C.gold[1] * m, C.gold[2] * m, C.gold[3] * m, 1)
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
end

---------------------------------------------------------------------------
-- Barres de progression (LegacyProgressBarTemplate) : le remplissage de
-- Blizzard passe a alpha 0, le notre est ancre sur lui (il suit donc la
-- largeur et l animation). Au minimum, le moteur cache sa texture sans la
-- redimensionner : la notre, ancree sur un cadre perime (critere recycle,
-- niveau 0), afficherait une fausse valeur. Elle n est donc visible que si
-- celle de Blizzard l est et que la valeur depasse le minimum.
---------------------------------------------------------------------------

local function barState(sb, s)
    if not s.fill then return end
    fade(s.ref)
    local on = shown(s.ref)
    if on then
        local okV, v = pcall(sb.GetValue, sb)
        local okM, lo = pcall(sb.GetMinMaxValues, sb)
        v = okV and num(v) or nil
        lo = okM and num(lo) or nil
        if v and lo and v <= lo then on = false end
    end
    s.fill:SetShown(on)
end

local function legacyBar(sb)
    if progress[sb] or objType(sb) ~= "StatusBar" then return end
    local C = ns.COLORS
    fade(field(sb, "ProgressBarFrame"))
    local s = {}
    s.bg = tex(sb, "BACKGROUND", -8)
    s.bg:SetPoint("TOPLEFT", sb, "TOPLEFT", -1, 1)
    s.bg:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 1, -1)
    s.bg:SetColorTexture(0, 0, 0, 0.6)
    s.edges = ring(sb, s.bg, "BACKGROUND", -7, 0)
    paintC(s.edges, C.border)
    local okT, ref = pcall(sb.GetStatusBarTexture, sb)
    if okT and objType(ref) == "Texture" then
        s.ref = ref
        fade(ref)
        s.fill = tex(sb, "ARTWORK", 1)
        s.fill:SetPoint("TOPLEFT", ref, "TOPLEFT", 0, 0)
        s.fill:SetPoint("BOTTOMRIGHT", ref, "BOTTOMRIGHT", 0, 0)
        if ns.BAR_TEXTURE then s.fill:SetTexture(ns.BAR_TEXTURE) else s.fill:SetColorTexture(1, 1, 1, 1) end
        s.fill:SetVertexColor(C.violet[1], C.violet[2], C.violet[3], 1)
    end
    progress[sb] = s
    claimed[sb] = true
    barState(sb, s)
end

---------------------------------------------------------------------------
-- Defis : lignes de categories, cartes, criteres
---------------------------------------------------------------------------

-- ligne de categorie (ListHeaderVisualTemplate recycle) : parent = en-tete
-- en degrade, feuille = ligne sombre, choisie = degrade et barre d or
local function catRow(f)
    if cats[f] then return end
    local C = ns.COLORS
    local s = {}
    s.hdr = tex(f, "BACKGROUND", 1)
    s.hdr:SetPoint("LEFT", f, "LEFT", 2, 0)
    s.hdr:SetPoint("RIGHT", f, "RIGHT", -2, 0)
    s.hdr:SetHeight(22)
    ns.UI.Gradient(s.hdr, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.30, C.violet[1], C.violet[2], C.violet[3], 0.03)
    s.line = tex(f, "BACKGROUND", 2)
    s.line:SetPoint("TOPLEFT", s.hdr, "BOTTOMLEFT")
    s.line:SetPoint("TOPRIGHT", s.hdr, "BOTTOMRIGHT")
    s.line:SetHeight(1)
    ns.UI.Gradient(s.line, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.8, C.gold[1], C.gold[2], C.gold[3], 0)
    s.leaf = tex(f, "BACKGROUND", 1)
    s.leaf:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -1)
    s.leaf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 1)
    s.leaf:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.6)
    s.sel = tex(f, "BACKGROUND", 2)
    s.sel:SetAllPoints(s.leaf)
    ns.UI.Gradient(s.sel, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.55, C.violet[1], C.violet[2], C.violet[3], 0.05)
    s.bar = tex(f, "BACKGROUND", 3)
    s.bar:SetPoint("TOPLEFT", s.leaf, "TOPLEFT", 0, 0)
    s.bar:SetPoint("BOTTOMLEFT", s.leaf, "BOTTOMLEFT", 0, 0)
    s.bar:SetWidth(2)
    s.bar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    s.hover = tex(f, "HIGHLIGHT")
    s.hover:SetAllPoints(s.leaf)
    ns.UI.Gradient(s.hover, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.25, C.violet[1], C.violet[2], C.violet[3], 0.02)
    s.sel:Hide()
    s.bar:Hide()
    s.leaf:Hide()
    cats[f] = s
    claimed[f] = true
    local icon = field(field(f, "CollapseButton"), "Icon")
    if isTex(icon) then tints[icon] = "gold" end
end

local function catState(f, s)
    local nt = stateTex(f, "GetNormalTexture")
    fade(nt)
    fade(stateTex(f, "GetHighlightTexture"))
    local a = atlasOf(nt) or ""
    local parent = a == "common-button-list-collapseExpand"
    local selected = (not parent) and a == "Legacy-Challenge-Left-Sub-Tab-selected"
    s.hdr:SetShown(parent)
    s.line:SetShown(parent)
    s.leaf:SetShown(not parent)
    s.sel:SetShown(selected)
    s.bar:SetShown(selected)
end

-- critere d un defi (pool) : notre ligne suit le fond de Blizzard (cache
-- quand le critere est une barre de progression)
local function criteria(f)
    if crits[f] then return end
    local ref = field(f, "Background")
    if not isTex(ref) then return end
    fade(ref)
    fade(field(f, "ProgressBarBackground"))
    local C = ns.COLORS
    local s = { ref = ref }
    s.fill = tex(f, "BACKGROUND", -8)
    s.fill:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -2)
    s.fill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 2)
    s.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.85)
    s.edges = ring(f, s.fill, "BACKGROUND", -7, 0)
    paintC(s.edges, C.border)
    crits[f] = s
    claimed[f] = true
    local pb = field(f, "ProgressBar")
    if pb then pcall(legacyBar, pb) end
end

-- carte de defi (LegacyChallengeTemplate, recyclee par la ScrollBox)
local function card(f)
    if cards[f] then return end
    local C = ns.COLORS
    for _, k in ipairs({ "Background", "BackgroundTop", "BackgroundMiddle", "BackgroundBottom", "SelectedOverlay", "TitleBar" }) do
        fade(field(f, k))
    end
    local s = {}
    s.fill = tex(f, "BACKGROUND", -8)
    s.fill:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
    s.fill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
    s.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.92)
    s.sel = tex(f, "BACKGROUND", -6)
    s.sel:SetAllPoints(s.fill)
    ns.UI.Gradient(s.sel, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.30, C.violet[1], C.violet[2], C.violet[3], 0.03)
    s.sel:Hide()
    s.bar = tex(f, "BACKGROUND", -4)
    s.bar:SetPoint("TOPLEFT", s.fill, "TOPLEFT", 0, 0)
    s.bar:SetPoint("BOTTOMLEFT", s.fill, "BOTTOMLEFT", 0, 0)
    s.bar:SetWidth(2)
    s.bar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    s.bar:Hide()
    s.edges = ring(f, s.fill, "BACKGROUND", -5, 0)
    paintC(s.edges, C.border)
    s.hover = tex(f, "HIGHLIGHT")
    s.hover:SetAllPoints(s.fill)
    ns.UI.Gradient(s.hover, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.16, C.violet[1], C.violet[2], C.violet[3], 0.02)
    -- bandeau du titre a la place du ruban (ancre sur le ruban, efface)
    local tb = field(f, "TitleBar")
    if isTex(tb) then
        s.band = tex(f, "BACKGROUND", -4)
        s.band:SetPoint("TOPLEFT", tb, "TOPLEFT", 0, -10)
        s.band:SetPoint("BOTTOMRIGHT", tb, "TOPRIGHT", 0, -38)
        s.line = tex(f, "BACKGROUND", -4)
        s.line:SetPoint("TOPLEFT", s.band, "BOTTOMLEFT")
        s.line:SetPoint("TOPRIGHT", s.band, "BOTTOMRIGHT")
        s.line:SetHeight(1)
    end
    -- icone : masque retire, carre recadre
    local ic = field(f, "Icon")
    local it = field(ic, "texture")
    if objType(it) == "Texture" and ic.CreateTexture then
        local mask = field(ic, "TextureMask")
        if mask and not masked[it] and it.RemoveMaskTexture then
            masked[it] = true
            pcall(it.RemoveMaskTexture, it, mask)
        end
        fade(field(ic, "frame"))
        cropIcon(it)
        s.icon = box(ic, it, 1)
        s.iconTex = it
    end
    -- plaque de la date d obtention (suit le fond de Blizzard)
    local sh = field(f, "Shield")
    local cbg = field(sh, "CheckBackground")
    if isTex(cbg) and sh.CreateTexture then
        fade(cbg)
        s.dateRef = cbg
        s.date = tex(sh, "BORDER", 0)
        s.date:SetAllPoints(cbg)
        s.date:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.85)
        s.dateEdges = ring(sh, s.date, "BORDER", 1, 0)
        paintC(s.dateEdges, C.border)
    end
    -- case "Suivre"
    local tr = field(f, "Tracked")
    if tr then pcall(skinCheck, tr) end
    local pm = field(f, "PlusMinus")
    if isTex(pm) then tints[pm] = "gold" end
    cards[f] = s
    claimed[f] = true
end

local function cardState(f, s)
    local C = ns.COLORS
    local bgA = atlasOf(field(f, "Background")) or ""
    local completed = bgA ~= "" and not bgA:find("%-Disable$")
    local selected = shown(field(f, "SelectedOverlay"))
    local account = (atlasOf(field(f, "TitleBar")) or ""):find("Blue") ~= nil
    local key = (completed and "c" or "-") .. (selected and "s" or "-") .. (account and "a" or "-")
    if s.key ~= key then
        s.key = key
        if completed then
            s.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.92)
        else
            s.fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.92)
        end
        s.sel:SetShown(selected)
        s.bar:SetShown(selected)
        if selected then
            paintC(s.edges, C.gold)
        elseif completed then
            paintC(s.edges, C.border)
        else
            paintC(s.edges, C.border, 0.6)
        end
        if s.band then
            -- defi de compte : bleu, comme le ruban de Blizzard
            local c = account and BLUE or C.violet
            local a = completed and 0.38 or 0.18
            ns.UI.Gradient(s.band, "HORIZONTAL", c[1], c[2], c[3], a, c[1], c[2], c[3], 0.02)
            ns.UI.Gradient(s.line, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], completed and 0.8 or 0.35, C.gold[1], C.gold[2], C.gold[3], 0)
        end
        if s.icon then
            if completed then paintC(s.icon.edges, C.gold) else paintC(s.icon.edges, C.border) end
        end
    end
    if s.iconTex then cropIcon(s.iconTex) end
    if s.date then
        local on = shown(s.dateRef)
        s.date:SetShown(on)
        showAll(s.dateEdges, on)
    end
end

---------------------------------------------------------------------------
-- Piste de recompenses : cartes de palier, fleches
---------------------------------------------------------------------------

local function rewardCard(f)
    if rewards[f] then return end
    local C = ns.COLORS
    local bgT, sq, ib, icon = field(f, "RewardCardBG"), field(f, "LevelSquare"), field(f, "IconBorder"), field(f, "Icon")
    if not (isTex(bgT) and isTex(sq)) then return end
    fade(bgT) fade(sq) fade(ib)
    local s = { ref = bgT }
    s.fill = tex(f, "BACKGROUND", -8)
    s.fill:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -6)
    s.fill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
    s.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.9)
    s.top = tex(f, "BACKGROUND", -7)
    s.top:SetPoint("TOPLEFT", s.fill, "TOPLEFT", 1, -1)
    s.top:SetPoint("TOPRIGHT", s.fill, "TOPRIGHT", -1, -1)
    s.top:SetHeight(56)
    s.edges = ring(f, s.fill, "BACKGROUND", -6, 0)
    paintC(s.edges, C.border)
    if objType(icon) == "Texture" then
        cropIcon(icon)
        s.icon = box(f, icon, 1, "BORDER", 0)
        s.iconTex = icon
    end
    -- pastille du niveau (losange de Blizzard efface, le chiffre reste)
    s.lvl = tex(f, "ARTWORK", 6)
    s.lvl:SetSize(26, 26)
    s.lvl:SetPoint("CENTER", sq, "CENTER", 0, 0)
    s.lvl:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.95)
    s.lvlEdges = ring(f, s.lvl, "ARTWORK", 7, 0)
    paintC(s.lvlEdges, C.border)
    rewards[f] = s
    claimed[f] = true
end

-- palier courant (fond vert chez Blizzard), atteint, a venir (grise)
local function rewardState(f, s)
    local C = ns.COLORS
    local a = atlasOf(s.ref) or ""
    local state = a:find("%-Green$") and "cur" or (a:find("%-Disable$") and "off") or "on"
    if s.state ~= state then
        s.state = state
        local c = state == "cur" and GREEN or (state == "on" and C.gold) or GRAY
        paintC(s.edges, state == "off" and C.border or c, state == "off" and 0.7 or 1)
        paintC(s.lvlEdges, c)
        local top = state == "off" and 0.12 or 0.30
        local tc = state == "cur" and GREEN or C.violet
        ns.UI.Gradient(s.top, "VERTICAL", tc[1], tc[2], tc[3], 0, tc[1], tc[2], tc[3], top)
        if s.icon then paintC(s.icon.edges, state == "off" and C.border or C.gold) end
        if state == "off" then
            s.fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.9)
        else
            s.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.9)
        end
    end
    if s.iconTex then cropIcon(s.iconTex) end
end

-- fleches de defilement de la piste (affichees par Blizzard si elle defile)
local ARROWS = { LeftButton = "<", RightButton = ">", JumpLeftButton = "«", JumpRightButton = "»" }

local function trackArrows(f)
    for k, g in pairs(ARROWS) do
        local b = field(f, k)
        if objType(b) == "Button" then pcall(glyphButton, b, g, 14, 2) end
    end
end

---------------------------------------------------------------------------
-- Arbre : cartes de choix, noeuds, liens
---------------------------------------------------------------------------

-- carte de choix d arbre (LegacyTreeButtonTemplate, pool) : la carte de
-- Blizzard passe a alpha 0, la notre est ancree sur elle ; l arbre choisi
-- (lueur de Blizzard affichee) prend le lisere d or
local function treeButton(b)
    if trees[b] then return end
    local C = ns.COLORS
    local bgT, glow = field(b, "Background"), field(b, "SelectedGlow")
    if not (isTex(bgT) and isTex(glow)) then return end
    fade(bgT) fade(glow)
    local s = { ref = glow, ring = field(b, "Ring") }
    s.fill = tex(b, "BACKGROUND", -8)
    s.fill:SetPoint("TOPLEFT", bgT, "TOPLEFT", 6, -8)
    s.fill:SetPoint("BOTTOMRIGHT", bgT, "BOTTOMRIGHT", -6, 8)
    s.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.9)
    s.sel = tex(b, "BACKGROUND", -7)
    s.sel:SetAllPoints(s.fill)
    ns.UI.Gradient(s.sel, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.03, C.violet[1], C.violet[2], C.violet[3], 0.45)
    s.sel:Hide()
    s.bar = tex(b, "BACKGROUND", -5)
    s.bar:SetPoint("TOPRIGHT", s.fill, "TOPRIGHT", 0, 0)
    s.bar:SetPoint("BOTTOMRIGHT", s.fill, "BOTTOMRIGHT", 0, 0)
    s.bar:SetWidth(2)
    s.bar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    s.bar:Hide()
    s.edges = ring(b, s.fill, "BACKGROUND", -6, 0)
    paintC(s.edges, C.border)
    s.hover = tex(b, "HIGHLIGHT")
    s.hover:SetAllPoints(s.fill)
    ns.UI.Gradient(s.hover, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.02, C.violet[1], C.violet[2], C.violet[3], 0.2)
    if s.ring then owned[s.ring] = true end
    trees[b] = s
    claimed[b] = true
end

local function treeState(b, s)
    local C = ns.COLORS
    local on = shown(s.ref)
    s.sel:SetShown(on)
    s.bar:SetShown(on)
    if on then paintC(s.edges, C.gold) elseif isOver(b) then paintC(s.edges, C.violet) else paintC(s.edges, C.border) end
    if s.ring then
        local c = on and C.gold or C.violet
        pcall(s.ring.SetDesaturated, s.ring, true)
        pcall(s.ring.SetVertexColor, s.ring, c[1], c[2], c[3], on and 1 or 0.7)
    end
end

-- noeud de l arbre (TalentButtonLegacySquareTemplate, pool) : cadre
-- d etat de Blizzard a alpha 0, double lisere de la couleur de l etat
local function isLegacyNode(b)
    local okA, maxed = pcall(function() return b.artSet and b.artSet.maxed end)
    if okA and type(maxed) == "string" and not issecret(maxed) then
        return maxed:find("^Legacy%-") ~= nil
    end
    local a = atlasOf(field(b, "StateBorder"))
    return a ~= nil and a:find("^Legacy%-Tree%-Frame%-icon%-frame") ~= nil
end

local function node(b)
    if nodes[b] then return end
    local sb, icon = field(b, "StateBorder"), field(b, "Icon")
    if objType(sb) ~= "Texture" or objType(icon) ~= "Texture" or not isLegacyNode(b) then return end
    fade(sb)
    fade(field(b, "Shadow"))
    -- le survol de Blizzard recoit son alpha a chaque etat : on l eteint par la couleur
    local hov = field(b, "StateBorderHover")
    if hov and hov.SetVertexColor then pcall(hov.SetVertexColor, hov, 1, 1, 1, 0) end
    local s = { sb = sb, icon = icon }
    s.fill = tex(b, "BACKGROUND", -8)
    s.fill:SetPoint("TOPLEFT", icon, "TOPLEFT", -2, 2)
    s.fill:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
    s.fill:SetColorTexture(0, 0, 0, 0.75)
    s.inner = ring(b, icon, "OVERLAY", 6, 1)
    s.outer = ring(b, icon, "OVERLAY", 5, 2)
    cropIcon(icon)
    nodes[b] = s
    claimed[b] = true
end

-- achete (cadre or), disponible (vert), verrouille (gris), invalide (rouge)
local function nodeColor(a)
    if a == "Legacy-Tree-Frame-icon-frame" then return ns.COLORS.gold end
    if a:find("%-Green$") then return GREEN end
    if a:find("%-disable$") then return GRAY end
    if a:find("red") then return RED end
    return ns.COLORS.border
end

local function nodeState(b, s)
    fade(s.sb)
    local c = nodeColor(atlasOf(s.sb) or "")
    local over = isOver(b)
    if s.c ~= c or s.over ~= over then
        s.c, s.over = c, over
        paintC(s.inner, c, 1)
        paintC(s.outer, c, over and 0.9 or 0.3)
    end
    cropIcon(s.icon)
end

-- teintes reprises a chaque releve (Blizzard repose l atlas selon l etat)
local function edgeColor(a)
    if a:find("yellow$") then return ns.COLORS.gold end
    if a:find("gray$") then return { 0.52, 0.48, 0.60 } end
    if a:find("locked$") then return DARK end
    if a:find("red$") then return RED end
end

local function applyTint(r, kind)
    local C = ns.COLORS
    local c
    if kind == "gold" or kind == "ring" then
        c = C.gold
    elseif kind == "violet" then
        c = C.violet
    elseif kind == "edge" then
        c = edgeColor(atlasOf(r) or "")
    end
    if not c then return end
    pcall(r.SetDesaturated, r, true)
    pcall(r.SetVertexColor, r, c[1], c[2], c[3], 1)
end

---------------------------------------------------------------------------
-- Petits decors reconnus par atlas
---------------------------------------------------------------------------

local function vline(f, r)
    fade(r)
    if dividers[f] then return end
    local C = ns.COLORS
    local line = tex(f, "ARTWORK", 1)
    line:SetPoint("TOP", r, "TOP", 0, -4)
    line:SetPoint("BOTTOM", r, "BOTTOM", 0, 4)
    line:SetWidth(1)
    ns.UI.Gradient(line, "VERTICAL", C.gold[1], C.gold[2], C.gold[3], 0, C.gold[1], C.gold[2], C.gold[3], 0.6)
    dividers[f] = { line = line }
end

-- pastille des points depenses dans l arbre
local function spent(f, r)
    fade(r)
    if panels[f] then return end
    panels[f] = true
    local C = ns.COLORS
    local fill = tex(f, "BACKGROUND", 2)
    fill:SetSize(30, 30)
    fill:SetPoint("CENTER", r, "CENTER", 0, 0)
    fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.95)
    paintC(ring(f, fill, "BACKGROUND", 3, 0), C.gold)
end

-- barre des points disponibles (arbre)
local function pointsBar(f, r)
    fade(r)
    if panels[f] then return end
    panels[f] = true
    local C = ns.COLORS
    local fill = tex(f, "BACKGROUND", -8)
    fill:SetPoint("TOPLEFT", r, "TOPLEFT", 4, -6)
    fill:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -4, 6)
    fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.92)
    local band = tex(f, "BACKGROUND", -7)
    band:SetAllPoints(fill)
    ns.UI.Gradient(band, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.30, C.violet[1], C.violet[2], C.violet[3], 0.03)
    paintC(ring(f, fill, "BACKGROUND", -6, 0), C.border)
end

-- suggestions de la recherche : panneau et lignes sombres
local PREVIEW_DECOR = { "BorderAnchor", "BotRightCorner", "BottomBorder", "LeftBorder", "RightBorder" }

local function searchRow(f, r)
    fade(r)
    if objType(f) == "Button" then
        fade(stateTex(f, "GetPushedTexture"))
        if rows[f] then return end
        rows[f] = true
        claimed[f] = true
        local C = ns.COLORS
        local fill = tex(f, "BACKGROUND", -8)
        fill:SetAllPoints(f)
        fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.96)
        local icon = field(f, "Icon")
        if objType(icon) == "Texture" and not atlasOf(icon) then
            cropIcon(icon)
            box(f, icon, 1, "BORDER", 0)
        end
        return
    end
    for _, k in ipairs(PREVIEW_DECOR) do fade(field(f, k)) end
    if panels[f] then return end
    panels[f] = true
    backdrop(f, f, 0.96)
end

---------------------------------------------------------------------------
-- Onglets de droite (LargeSideTabButtonTemplate, comme les metiers)
---------------------------------------------------------------------------

local rail

local function buildRail(f)
    if rail then return end
    local C = ns.COLORS
    rail = {}
    rail.fill = tex(f, "BACKGROUND", -8)
    rail.fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.92)
    rail.edges = ring(f, rail.fill, "BACKGROUND", -7, 0)
    paintC(rail.edges, C.border)
    rail.fill:Hide()
    showAll(rail.edges, false)
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

-- icone choisie par Blizzard (champ iconTexture du modele, sinon la texture)
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
    fade(field(t, "Icon"))
    local active = shown(field(t, "SelectedTexture"))
    local over = isOver(t)
    local okG, glowing = pcall(function() return t.TabGlowAnimation and t.TabGlowAnimation:IsPlaying() end)
    glowing = okG and not issecret(glowing) and glowing == true
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
    local on = first ~= nil
    rail.fill:SetShown(on)
    showAll(rail.edges, on)
    if not on then return end
    rail.fill:ClearAllPoints()
    rail.fill:SetPoint("TOPLEFT", first.s.fill, "TOPLEFT", -4, 4)
    rail.fill:SetPoint("BOTTOMLEFT", last.s.fill, "BOTTOMLEFT", -4, -4)
    rail.fill:SetWidth(first.s.size + 8)
end

---------------------------------------------------------------------------
-- Cadre exterieur (seulement si Fenetres.lua ne le connait pas : sinon
-- Skins.lua le fait deja)
---------------------------------------------------------------------------

local outer
local closeGlyph

local function dressOuter(f)
    if outer or listedKey() then return end
    outer = true
    local C = ns.COLORS
    fadeOwn(f)
    for _, k in ipairs({ "NineSlice", "PortraitContainer", "TitleContainer", "Bg", "TopTileStreaks" }) do
        local c = field(f, k)
        if objType(c) == "Texture" then fade(c) elseif c then fadeOwn(c) end
    end
    fade(field(field(f, "PortraitContainer"), "portrait"))
    -- fond obsidienne, ombre douce, lisere, bandeau d accent
    local fill = tex(f, "BACKGROUND", -7)
    fill:SetAllPoints(f)
    fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.96)
    for i = 1, 5 do
        local s = tex(f, "BACKGROUND", -8)
        s:SetPoint("TOPLEFT", f, "TOPLEFT", -i, i)
        s:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", i, -i)
        s:SetColorTexture(0, 0, 0, 0.16)
    end
    paintC(ring(f, f, "BACKGROUND", -5, 0), C.border)
    headBand(f, f, 1, 22)
    -- croix plate (ses textures a alpha 0, notre "x" dessus)
    local b = field(f, "CloseButton")
    if objType(b) == "Button" and b.CreateFontString then
        fadeStates(b, { "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" })
        local x = b:CreateFontString(nil, "OVERLAY")
        mine[x] = true
        pcall(ns.UI.HeadFont, x, 15)
        x:SetPoint("CENTER", 0, 1)
        x:SetText("×")
        x:SetTextColor(C.text[1], C.text[2], C.text[3])
        closeGlyph = { b = b, fs = x }
        claimed[b] = true
    end
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

local TINTS = { gold = true, ring = true, violet = true, edge = true }

-- atlas vu au dernier passage de teinte (vide a chaque parcours complet)
local tinted = setmetatable({}, weak)

local function retint(r, kind)
    local a = atlasOf(r) or ""
    if tinted[r] == a then return end
    tinted[r] = a
    applyTint(r, kind)
end

local function scanRegions(f)
    for _, r in ipairs(regionsOf(f)) do
        if not mine[r] and not done[r] and isTex(r) then
            local a = atlasOf(r)
            local act = a and actionFor(a)
            if act then
                done[r] = true
                if TINTS[act] then
                    tints[r] = act
                    if not owned[r] then applyTint(r, act) end
                elseif act == "fade" then
                    fade(r)
                elseif act == "vline" then
                    vline(f, r)
                elseif act == "spent" then
                    spent(f, r)
                elseif act == "pointsbar" then
                    pointsBar(f, r)
                elseif act == "searchrow" then
                    searchRow(f, r)
                elseif act == "dropdown" then
                    fade(r)
                    plate(f, 0).parts = { r }
                elseif act == "checkbox" then
                    fade(r)
                    if objType(f) == "CheckButton" then skinCheck(f) end
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
    if t == "StatusBar" then
        if field(f, "ProgressBarFrame") then legacyBar(f) end
        return
    end
    if field(f, "TitleBar") and field(f, "SelectedOverlay") and field(f, "Shield") then
        card(f)
    elseif field(f, "RewardCardBG") and field(f, "LevelSquare") then
        rewardCard(f)
    elseif field(f, "SelectedGlow") and field(f, "Ring") and field(f, "Background") then
        treeButton(f)
    elseif field(f, "StateBorder") and field(f, "Icon") then
        node(f)
    elseif t == "Button" and field(f, "CollapseButton") and field(f, "NotificationIcon") then
        catRow(f)
    elseif field(f, "ProgressBar") and field(f, "ProgressBarBackground") and field(f, "Check") and field(f, "Background") then
        criteria(f)
    elseif t == "Button" and field(f, "Left") and field(f, "Right") then
        panelButton(f)
    elseif field(f, "LeftButton") and field(f, "RightButton") and field(f, "ClipFrame") then
        trackArrows(f)
    elseif field(f, "FilterDropdown") and field(f, "SearchBox") and field(f, "ScrollBox") then
        -- liste des categories : panneau sombre
        if not panels[f] then
            panels[f] = true
            backdrop(f, f, 0.5)
        end
    elseif field(f, "ApplyButton") and field(f, "ResetButton") then
        iconButton(field(f, "ResetButton"))
        iconButton(field(f, "UndoButton"))
        label(field(field(f, "SelectedTreeIcon"), "SelectedTreeLabel"), 18)
    elseif field(f, "PointsLabel") and field(f, "LegacyRewardProgressBar") then
        -- couleur seulement : ProgressBarBackground est ancre sous ce texte
        label(field(f, "PointsLabel"), nil)
    end
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
    for _, c in ipairs(childrenOf(f)) do walk(c, depth + 1) end
end

local function titleText(f)
    local fs = field(field(f, "TitleContainer"), "TitleText") or field(f, "TitleText")
    if objType(fs) == "FontString" then return fs end
end

-- les volets et onglets sont a nous des que la fenetre existe (Skins.lua
-- ne doit pas y entrer, meme avant notre premier parcours)
local claimedRoot

local function claimRoot(f)
    if claimedRoot == f then return end
    claimedRoot = f
    for _, k in ipairs(PAGE_KEYS) do
        local p = field(f, k)
        if p then claimed[p] = true end
    end
    for _, k in ipairs(TAB_KEYS) do
        local t = field(f, k)
        if t then claimed[t] = true end
    end
end

local function full(f)
    tinted = setmetatable({}, weak)
    dressOuter(f)
    pcall(buildRail, f)
    for _, k in ipairs(TAB_KEYS) do
        local t = field(f, k)
        if t and t.CreateTexture then pcall(skinSideTab, t) end
    end
    walk(f, 1)
end

-- leger (5 fois par seconde, fenetre ouverte) : couleurs d etat
local titleFont

local function light(f)
    local C = ns.COLORS
    local title = titleText(f)
    if title then
        if not titleFont or titleFont.fs ~= title then titleFont = goldFont(title, 12) else keepGold(titleFont) end
    end
    if closeGlyph and visible(closeGlyph.b) then
        if isOver(closeGlyph.b) then closeGlyph.fs:SetTextColor(1, 0.3, 0.3)
        else closeGlyph.fs:SetTextColor(C.text[1], C.text[2], C.text[3]) end
    end
    for t, s in pairs(sideTabs) do
        if visible(t) then pcall(sideTabState, t, s) end
    end
    placeRail()
    for b, p in pairs(plates) do
        if p.edges and visible(b) then
            if p.parts then for _, x in ipairs(p.parts) do fade(x) end end
            local over = isOver(b) and enabled(b)
            paintC(p.edges, over and C.gold or C.border)
            if p.glyph then
                local c = p.color or C.gold
                p.glyph:SetTextColor(c[1], c[2], c[3])
                p.glyph:SetAlpha(enabled(b) and 1 or 0.35)
            end
        end
    end
    for cb, k in pairs(checks) do
        if visible(cb) then
            local okC, on = pcall(cb.GetChecked, cb)
            k.mark:SetShown(okC and not issecret(on) and on == true)
            k.mark:SetAlpha(enabled(cb) and 1 or 0.4)
            paintC(k.edges, isOver(cb) and C.gold or C.border)
        end
    end
    for e, k in pairs(edits) do
        if visible(e) then
            local okF, focus = pcall(e.HasFocus, e)
            focus = okF and not issecret(focus) and focus == true
            if focus then paintC(k.edges, C.gold)
            elseif isOver(e) then paintC(k.edges, C.violet)
            else paintC(k.edges, C.border) end
            pcall(glassState, e, k, focus)
        end
    end
    for sb, s in pairs(progress) do
        if s.ref and visible(sb) then pcall(barState, sb, s) end
    end
    for f2, s in pairs(cats) do
        if visible(f2) then pcall(catState, f2, s) end
    end
    for f2, s in pairs(cards) do
        if visible(f2) then pcall(cardState, f2, s) end
    end
    for f2, s in pairs(crits) do
        if visible(f2) then
            local on = shown(s.ref)
            s.fill:SetShown(on)
            showAll(s.edges, on)
        end
    end
    for f2, s in pairs(rewards) do
        if visible(f2) then pcall(rewardState, f2, s) end
    end
    for b, s in pairs(trees) do
        if visible(b) then pcall(treeState, b, s) end
    end
    for b, s in pairs(nodes) do
        if visible(b) then pcall(nodeState, b, s) end
    end
    for r, kind in pairs(tints) do
        if not owned[r] and visible(r) then retint(r, kind) end
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

-- Skins.lua : ne pas aplatir nos cadres, ne pas effacer nos textures.
-- Les volets et onglets sont reclames ici meme, des la premiere question de
-- Skins.lua : il peut parcourir la fenetre avant notre premier releve
-- (premier chargement en combat puis PLAYER_REGEN_ENABLED, ou son releve
-- tombe avant le notre) et poserait sinon une seconde plaque (Appliquer).
-- Lecture de champs et table a nous : rien chez Blizzard, meme en combat.
local prevClaimed = ns.SkinClaimed
function ns.SkinClaimed(f)
    if type(f) == "table" then
        local r = _G[ROOT]
        if type(r) == "table" and claimedRoot ~= r and db() then pcall(claimRoot, r) end
        if claimed[f] then return true end
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

-- volet affiche et arbre choisi : un changement relance le parcours
local function pageKey(f)
    local ok, key = pcall(function()
        local tp = f.TreePage
        local panel = tp and tp.LegacyTreeTraitPanel
        return tostring(f.currentPage) .. ":" .. tostring(panel and panel.selectedTreeIdx)
    end)
    if ok and type(key) == "string" and not issecret(key) then return key end
    return ""
end

local wasShown, lastKey = false, nil
local acc, walkAcc = 0, 0

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then wasShown = false end
end)
pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")

ev:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.2 then return end
    walkAcc = walkAcc + acc
    acc = 0
    if not db() then return end
    local f = _G[ROOT]
    if type(f) ~= "table" or not f.CreateTexture then return end
    -- reclamation (lecture seule) avant le test de combat
    claimRoot(f)
    if InCombatLockdown() then return end
    if not visible(f) then
        wasShown = false
        return
    end
    local key = pageKey(f)
    if not wasShown or key ~= lastKey or walkAcc >= 0.6 then
        wasShown, lastKey, walkAcc = true, key, 0
        local ok, err = pcall(full, f)
        if not ok and ns.skinsDB then
            ns.skinsDB.errors = ns.skinsDB.errors or {}
            ns.skinsDB.errors.Legacy = tostring(err)
        end
    end
    pcall(light, f)
end)
