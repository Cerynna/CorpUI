--[[--------------------------------------------------------------------------
    CorpUI - module Habillage : page des talents
    (PlayerSpellsFrame.TalentsFrame, variante Camelot de ce client)

    Le cadre commun (titre, onglets, grimoire) est habille ailleurs ; ici
    seulement la page des talents, revendiquee aupres de Skins.lua
    (ns.SkinClaimed) pour que le parcours generique n y descende pas :
      - fond : decors de Blizzard a alpha 0, fond obsidienne, lisere,
        filets d or sur les separations, art de la classe desature et
        teinte de l accent, animations eteintes (couleur a alpha 0 : leur
        alpha est anime) ;
      - en-tetes des trois arbres : anneau efface, icone carree dans une
        case a lisere d or, nom en or, bandeau d accent, points depenses
        dans une petite case ;
      - noeuds (boutons recycles par les pools de Blizzard) : carre sombre
        et lisere selon l etat (double filet d or si complet, or attenue si
        commence et bloque, couleur "disponible" si achetable - avec un
        filet d or dedans s il est deja commence -, gris si verrouille,
        rouge si erreur), rang "2/5" a nous ; les formes rondes et les
        octogones de choix gardent leur bordure, desaturee et teintee.
        "Disponible" = l accent du theme, ou un violet fixe s il se
        confond avec l or, le rouge ou le gris ;
      - liens et paliers : teintes selon l atlas pose par Blizzard ;
      - points non depenses, onglets de double specialisation, boutons
        Appliquer / Activer / Annuler / Reinitialiser, recherche : style
        plat CorpUI.

    Regles de ce client (valeurs secretes, taint) : aucun crochet, aucun
    champ ecrit dans les tables de Blizzard (nos textures sont rangees dans
    des tables faibles a nous), aucune taille, position, strate, script ni
    alpha de cadre de Blizzard modifie (Blizzard met ses noeuds invisibles
    a alpha 0 : on n y touche pas) ; seulement l alpha, la couleur, la
    desaturation et le recadrage de leurs textures, et nos propres
    textures / textes poses dessus. Releve periodique sur notre cadre quand
    la page est visible, jamais en combat ; toute lecture sous pcall.
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)

local issecret = issecretvalue or function() return false end
local weak = { __mode = "k" }

local mine = setmetatable({}, weak)     -- nos regions (a ne jamais traiter)
local pages = setmetatable({}, weak)    -- page -> decor a nous
local heads = setmetatable({}, weak)    -- en-tete d arbre -> nos regions
local nodes = setmetatable({}, weak)    -- bouton de talent -> nos regions + etat
local edges = setmetatable({}, weak)    -- lien -> dernier atlas vu
local gates = setmetatable({}, weak)    -- palier -> true
local plates = setmetatable({}, weak)   -- bouton aplati -> { fill, edges, hl }
local tabs = setmetatable({}, weak)     -- onglet de specialisation -> plaque
local edits = setmetatable({}, weak)    -- champ de recherche -> fond
local icons = setmetatable({}, weak)    -- bouton a icone (Annuler, Reinitialiser)
local money = setmetatable({}, weak)    -- affichage des points -> nos regions

-- etats visuels de Blizzard (TalentButtonUtil.BaseVisualState)
local VS = { Normal = 1, Gated = 2, Disabled = 3, Locked = 4, Selectable = 5, Maxed = 6,
             Invisible = 7, RefundInvalid = 8, DisplayError = 9 }
local RED = { 1, 0.27, 0.27 }
local LOCKED = { 0.22, 0.21, 0.26 }

local function db()
    local d = ns.skinsDB
    if type(d) ~= "table" or not d.enabled then return nil end
    if d.groups and d.groups.spells == false then return nil end
    return d
end

---------------------------------------------------------------------------
-- Outils
---------------------------------------------------------------------------

local function objType(o)
    if type(o) ~= "table" or not o.GetObjectType then return nil end
    local ok, t = pcall(o.GetObjectType, o)
    if ok and not issecret(t) then return t end
end

local function field(f, key)
    if type(f) ~= "table" then return nil end
    local ok, c = pcall(function() return f[key] end)
    if ok and type(c) == "table" and not issecret(c) then return c end
end

local function val(f, key)
    if type(f) ~= "table" then return nil end
    local ok, v = pcall(function() return f[key] end)
    if ok and not issecret(v) then return v end
end

local function num(v)
    if v == nil or type(v) ~= "number" or issecret(v) then return nil end
    return v
end

local function isTex(t)
    local k = objType(t)
    return k == "Texture" or k == "Line"
end

local function fade(obj)
    if type(obj) == "table" and obj.SetAlpha then pcall(obj.SetAlpha, obj, 0) end
end

-- texture animee en alpha : on eteint sa couleur (l alpha est repose par
-- l animation, pas la couleur)
local function dim(t)
    if isTex(t) then pcall(t.SetVertexColor, t, 1, 1, 1, 0) end
end

local function tint(t, c, a)
    if not isTex(t) then return end
    pcall(t.SetDesaturated, t, true)
    pcall(t.SetVertexColor, t, c[1], c[2], c[3], a or 1)
end

local function visible(f)
    if type(f) ~= "table" or not f.IsVisible then return false end
    local ok, v = pcall(f.IsVisible, f)
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
    return not ok or v ~= false
end

local function childrenOf(f)
    if type(f) ~= "table" or not f.GetChildren then return {} end
    local ok, list = pcall(function() return { f:GetChildren() } end)
    return ok and list or {}
end

local function regionsOf(f)
    if type(f) ~= "table" or not f.GetRegions then return {} end
    local ok, list = pcall(function() return { f:GetRegions() } end)
    return ok and list or {}
end

local function atlasOf(t)
    if type(t) ~= "table" or not t.GetAtlas then return nil end
    local ok, a = pcall(t.GetAtlas, t)
    if ok and type(a) == "string" and not issecret(a) then return a end
end

local function textOf(fs)
    if type(fs) ~= "table" or not fs.GetText then return nil end
    local ok, t = pcall(fs.GetText, fs)
    if ok and type(t) == "string" and not issecret(t) then return t end
end

local function crop(icon)
    if objType(icon) == "Texture" then pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92) end
end

local function tex(host, layer, sub)
    local t = host:CreateTexture(nil, layer, nil, sub)
    mine[t] = true
    ns.NoSnap(t)   -- traits fins toujours dessines (Core.lua)
    return t
end

local function text(host, size, layer, sub)
    local fs = host:CreateFontString(nil, layer or "OVERLAY", nil, sub)
    mine[fs] = true
    pcall(ns.UI.HeadFont, fs, size)
    return fs
end

-- quatre filets de 1 px autour de "anchor" (sur "host"), "out" px en dehors
-- trait fin toujours dessine : pose sur une demi-unite (cadre des points
-- restants, bas a 923.5), un trait de 1 unite disparaissait a l arrondi sur
-- la grille des pixels (vu en jeu le 09/10) ; sans cet arrondi il reste net
local function thin(x, horizontal)
    if horizontal then x:SetHeight(1) else x:SetWidth(1) end
    pcall(x.SetSnapToPixelGrid, x, false)
    pcall(x.SetTexelSnappingBias, x, 0)
end

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
    thin(top, true)
    local bottom = line()
    bottom:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", -out, -out)
    bottom:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", out, -out)
    thin(bottom, true)
    local left = line()
    left:SetPoint("TOPLEFT", anchor, "TOPLEFT", -out, out)
    left:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", -out, -out)
    thin(left, false)
    local right = line()
    right:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", out, out)
    right:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", out, -out)
    thin(right, false)
    return list
end

local function paint(list, c, a)
    for _, x in ipairs(list) do x:SetColorTexture(c[1], c[2], c[3], a or 1) end
end

local function showAll(list, on)
    for _, x in ipairs(list) do x:SetShown(on) end
end

-- case sombre + lisere autour de "anchor"
local function box(host, anchor, out, alpha)
    local C = ns.COLORS
    local fill = tex(host, "BACKGROUND", -8)
    fill:SetPoint("TOPLEFT", anchor, "TOPLEFT", -out, out)
    fill:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", out, -out)
    fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], alpha or 0.92)
    local edgesL = ring(host, anchor, "OVERLAY", 1, out)
    paint(edgesL, C.border)
    return { fill = fill, edges = edgesL }
end

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
    paint(p.edges, C.border)
    p.hl = tex(b, "HIGHLIGHT")
    p.hl:SetAllPoints(p.fill)
    ns.UI.Gradient(p.hl, "VERTICAL", C.violet[1], C.violet[2], C.violet[3], 0.05, C.violet[1], C.violet[2], C.violet[3], 0.28)
    plates[b] = p
    return p
end

-- textures d etat d un bouton (normale, enfoncee, survol...)
local function fadeStates(b)
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        if type(b) == "table" and b[get] then
            local ok, t = pcall(b[get], b)
            if ok then fade(t) end
        end
    end
end

local function gradientLine(t, horizontal, a1, a2)
    local C = ns.COLORS
    ns.UI.Gradient(t, horizontal and "HORIZONTAL" or "VERTICAL",
        C.gold[1], C.gold[2], C.gold[3], a1, C.gold[1], C.gold[2], C.gold[3], a2)
end

---------------------------------------------------------------------------
-- Fond de la page
---------------------------------------------------------------------------

local FADE_KEYS = { "Background", "BackgroundBorder", "DividerHorizontalLeft", "DividerHorizontalRight",
                    "DividerVerticalLeft", "DividerVerticalRight" }
local ANIM_KEYS = { "OverlayBackgroundRight", "OverlayBackgroundMid", "Clouds1", "Clouds2", "AirParticlesClose",
                    "AirParticlesFar", "BackgroundFlash", "ActivationExpandFx", "ActivationClassFx",
                    "ActivationClassFx2", "ActivationClassFx3", "ActivationClassFx4", "ActivationTitansFX" }

-- filet vertical d or (deux moities qui s effacent vers les bouts)
local function vFilet(tf, anchor)
    local top = tex(tf, "BACKGROUND", -6)
    top:SetWidth(1)
    top:SetPoint("TOP", anchor, "TOP", 0, 0)
    top:SetPoint("BOTTOM", anchor, "CENTER", 0, 0)
    gradientLine(top, false, 0.55, 0)
    local bottom = tex(tf, "BACKGROUND", -6)
    bottom:SetWidth(1)
    bottom:SetPoint("TOP", anchor, "CENTER", 0, 0)
    bottom:SetPoint("BOTTOM", anchor, "BOTTOM", 0, 0)
    gradientLine(bottom, false, 0, 0.55)
end

local function skinPage(tf)
    local d = pages[tf]
    if not d then
        local C = ns.COLORS
        d = {}
        -- fond obsidienne sur toute la page
        d.fill = tex(tf, "BACKGROUND", -8)
        d.fill:SetAllPoints(tf)
        d.fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.96)
        local frameTex = field(tf, "BackgroundBorder")
        if isTex(frameTex) then
            -- lisere autour de la zone des arbres
            d.edges = ring(tf, frameTex, "BACKGROUND", -5, -2)
            paint(d.edges, C.border)
            -- filet d or sous la ligne des en-tetes d arbre
            local l = tex(tf, "BACKGROUND", -6)
            l:SetHeight(1)
            l:SetPoint("TOPLEFT", frameTex, "TOPLEFT", 16, -130)
            l:SetPoint("TOPRIGHT", frameTex, "TOP", 0, -130)
            gradientLine(l, true, 0, 0.5)
            local r = tex(tf, "BACKGROUND", -6)
            r:SetHeight(1)
            r:SetPoint("TOPLEFT", frameTex, "TOP", 0, -130)
            r:SetPoint("TOPRIGHT", frameTex, "TOPRIGHT", -16, -130)
            gradientLine(r, true, 0.5, 0)
        end
        for _, key in ipairs({ "DividerVerticalLeft", "DividerVerticalRight" }) do
            local div = field(tf, key)
            if isTex(div) then vFilet(tf, div) end
        end
        pages[tf] = d
    end
    for _, key in ipairs(FADE_KEYS) do
        local t = field(tf, key)
        if isTex(t) then fade(t) end
    end
    for _, key in ipairs(ANIM_KEYS) do dim(field(tf, key)) end
    local fx = field(tf, "classActivationTextures")
    if fx then for _, t in ipairs(fx) do dim(t) end end
    -- art de la classe : retire (une grande image sur toute la page : ses
    -- zones claires faisaient une bande sur le troisieme arbre)
    local art = field(tf, "ClassBackground")
    if isTex(art) then dim(art) end
end

---------------------------------------------------------------------------
-- En-tetes des arbres (pool de Blizzard : memes cadres a chaque mise a jour)
---------------------------------------------------------------------------

local function skinHeader(h)
    local C = ns.COLORS
    local s = heads[h]
    local icon = field(h, "Icon")
    if not s then
        s = {}
        if objType(icon) == "Texture" then
            -- le masque rond n a pas de nom : on le retire de l icone
            local okM, mask = pcall(icon.GetMaskTexture, icon, 1)
            if okM and type(mask) == "table" and not issecret(mask) then
                pcall(icon.RemoveMaskTexture, icon, mask)
            end
            s.box = box(h, icon, 2, 0.95)
            paint(s.box.edges, C.gold)
            -- liseré sous la case du nombre de points (vu en jeu : ses filets
            -- traversaient le chiffre, dessines au-dessus de la case)
            for _, e in ipairs(s.box.edges) do pcall(e.SetDrawLayer, e, "ARTWORK", 7) end
            -- bandeau d accent et filet d or, vers la droite
            s.band = tex(h, "BACKGROUND", -7)
            s.band:SetPoint("TOPLEFT", icon, "TOPRIGHT", 3, -4)
            s.band:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 3, 4)
            -- reste dans la colonne de l arbre (colonnes tous les 400, separateur
            -- vertical entre deux ; vu en jeu : 320 traversait le separateur et
            -- sortait du cadre pour le 3e arbre)
            s.band:SetWidth(235)
            ns.UI.Gradient(s.band, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.30, C.violet[1], C.violet[2], C.violet[3], 0.03)
            s.line = tex(h, "BACKGROUND", -6)
            s.line:SetPoint("TOPLEFT", s.band, "BOTTOMLEFT")
            s.line:SetPoint("TOPRIGHT", s.band, "BOTTOMRIGHT")
            s.line:SetHeight(1)
            gradientLine(s.line, true, 0.8, 0)
        end
        local back = field(h, "TextBackground")
        local spent = field(h, "Text")
        if isTex(back) and objType(spent) == "FontString" then
            s.count = tex(h, "OVERLAY", -1)
            s.count:SetSize(26, 18)
            s.count:SetPoint("CENTER", back, "CENTER", 0, 0)
            s.count:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.95)
            s.countEdges = ring(h, s.count, "OVERLAY", 0, 0)
            paint(s.countEdges, C.gold, 0.8)
        end
        heads[h] = s
    end
    for _, key in ipairs({ "MainRing", "TextBackground", "Divider" }) do
        local t = field(h, key)
        if isTex(t) then fade(t) end
    end
    crop(icon)
    local name = field(h, "Name")
    if objType(name) == "FontString" then
        pcall(ns.UI.HeadFont, name, 13)
        pcall(name.SetTextColor, name, C.gold[1], C.gold[2], C.gold[3])
    end
    local spent = field(h, "Text")
    if objType(spent) == "FontString" then pcall(spent.SetTextColor, spent, C.gold[1], C.gold[2], C.gold[3]) end
end

---------------------------------------------------------------------------
-- Noeuds
---------------------------------------------------------------------------

local function isSquare(b)
    local art = field(b, "artSet")
    local set = field(field(_G.TalentButtonArtMixin, "ArtSet"), "Square")
    if art and set and art == set then return true end
    local a = atlasOf(field(b, "StateBorder"))
    return a ~= nil and a:find("^talents%-node%-square") ~= nil
end

-- couleur "disponible" : l accent du theme, sauf s il se confond avec une
-- autre couleur d etat (or, rouge) ou s il est gris (themes sombre, argent,
-- classe pretre...) ; violet fixe dans ce cas
local VIOLET = { 0.84, 0.36, 1.00 }

local function dist(a, b)
    return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2)
end

local function selectableColor()
    local C = ns.COLORS
    local a = C.violet
    if type(a) ~= "table" then return VIOLET end
    local sat = math.max(a[1], a[2], a[3]) - math.min(a[1], a[2], a[3])
    if sat < 0.3 or dist(a, C.gold) < 0.4 or dist(a, RED) < 0.4 then return VIOLET end
    return a
end
ns.TalentSelectableColor = selectableColor

-- lisere exterieur (couleur, alpha) et filet interieur (couleur, alpha ;
-- nil = cache) selon l etat de Blizzard et les rangs achetes
local function stateColor(vs, ranks)
    local C = ns.COLORS
    if vs == VS.Maxed then return C.gold, 1, C.gold, 1 end
    if vs == VS.RefundInvalid or vs == VS.DisplayError then return RED, 1 end
    if vs == VS.Selectable then
        -- encore achetable : lisere "disponible" ; deja commence : filet
        -- d or attenue a l interieur
        if ranks and ranks > 0 then return selectableColor(), 1, C.gold, 0.6 end
        return selectableColor(), 1
    end
    if vs == VS.Normal then return C.gold, 0.75 end
    return C.border, 1
end

local function makeNode(b, icon)
    local C = ns.COLORS
    local s = {}
    s.box = box(b, icon, 2, 0.95)
    s.inner = ring(b, icon, "OVERLAY", 1, 1)       -- second filet : noeud complet
    showAll(s.inner, false)
    s.hl = tex(b, "HIGHLIGHT")
    s.hl:SetPoint("TOPLEFT", icon, "TOPLEFT", -2, 2)
    s.hl:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
    ns.UI.Gradient(s.hl, "VERTICAL", C.violet[1], C.violet[2], C.violet[3], 0.05, C.violet[1], C.violet[2], C.violet[3], 0.35)
    -- rang "2/5" sur une petite plaque, en bas a droite
    s.rank = text(b, 10, "OVERLAY", 7)
    s.rank:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 4, -4)
    s.rank:SetJustifyH("RIGHT")
    s.rankBg = tex(b, "OVERLAY", 6)
    s.rankBg:SetPoint("TOPLEFT", s.rank, "TOPLEFT", -2, 1)
    s.rankBg:SetPoint("BOTTOMRIGHT", s.rank, "BOTTOMRIGHT", 2, -1)
    s.rankBg:SetColorTexture(0, 0, 0, 0.85)
    s.rank:Hide()
    s.rankBg:Hide()
    nodes[b] = s
    return s
end

-- decors fixes d un noeud (a reprendre a chaque parcours : Blizzard
-- repose atlas et alpha quand le bouton est recycle)
local function nodeDecor(b, s)
    local C = ns.COLORS
    if s.square then
        fade(field(b, "StateBorder"))
        fade(field(b, "Shadow"))
        crop(field(b, "Icon"))
        -- survol : notre degrade a la place de la bordure claire de Blizzard
        dim(field(b, "StateBorderHover"))
    end
    s.hl:SetShown(s.square == true)
    dim(field(b, "BorderSheen"))
    for _, key in ipairs({ "SelectableGlow", "Glow", "Ghost" }) do tint(field(b, key), selectableColor()) end
    -- rang de Blizzard (texte et ses ombres) : remplace par le notre
    fade(field(b, "SpendText"))
    for i = 1, 4 do fade(field(b, "SpendTextShadow" .. i)) end
end

local function updateNode(b, s)
    local C = ns.COLORS
    local vs = num(val(b, "visualState"))
    local info = field(b, "nodeInfo")
    local ranks = info and num(val(info, "ranksPurchased"))
    local cur = info and num(val(info, "currentRank"))
    local max = info and num(val(info, "maxRanks"))
    local blizzText = textOf(field(b, "SpendText"))
    local key = tostring(vs) .. ":" .. tostring(ranks) .. ":" .. tostring(cur) .. ":" .. tostring(max)
        .. ":" .. tostring(blizzText) .. ":" .. tostring(s.square)
    if key == s.key then return end
    s.key = key
    local c, a, ic, ia = stateColor(vs, ranks)
    if s.square then
        showAll(s.box.edges, true)
        s.box.fill:Show()
        paint(s.box.edges, c, a)
        if ic then paint(s.inner, ic, ia) end
        showAll(s.inner, ic ~= nil)
    else
        -- forme ronde / octogone : la bordure de Blizzard reste, teintee
        showAll(s.box.edges, false)
        showAll(s.inner, false)
        s.box.fill:Hide()
        tint(field(b, "StateBorder"), c, a)
    end
    -- rang : seulement quand Blizzard en affiche un (memes regles que lui)
    if blizzText and blizzText ~= "" and cur and max then
        s.rank:SetText(string.format("%d/%d", cur, max))
        if vs == VS.Maxed then s.rank:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
        elseif vs == VS.Selectable then
            local sc = selectableColor()
            s.rank:SetTextColor(sc[1], sc[2], sc[3])
        else s.rank:SetTextColor(C.text[1], C.text[2], C.text[3]) end
        s.rank:Show()
        s.rankBg:Show()
    else
        s.rank:Hide()
        s.rankBg:Hide()
    end
end

local function skinNode(b)
    local icon = field(b, "Icon")
    if objType(icon) ~= "Texture" then return end
    local s = nodes[b] or makeNode(b, icon)
    local square = isSquare(b)
    if s.square ~= nil and s.square ~= square and not square then
        -- forme changee (ne devrait pas arriver) : on rend la bordure
        local sb, sh = field(b, "StateBorder"), field(b, "Shadow")
        if sb then pcall(sb.SetAlpha, sb, 1) end
        if sh then pcall(sh.SetAlpha, sh, 1) end
    end
    s.square = square
    nodeDecor(b, s)
    s.key = nil
    updateNode(b, s)
end

---------------------------------------------------------------------------
-- Liens et paliers
---------------------------------------------------------------------------

local function edgeColor(atlas)
    if not atlas then return nil end
    local C = ns.COLORS
    if atlas:find("ghost") then return selectableColor(), 0.5 end
    if atlas:find("yellow") then return C.gold, 1 end
    if atlas:find("red") then return RED, 1 end
    if atlas:find("locked") then return LOCKED, 0.6 end
    if atlas:find("gray") then
        local b = C.border
        return { b[1] + (1 - b[1]) * 0.3, b[2] + (1 - b[2]) * 0.3, b[3] + (1 - b[3]) * 0.3 }, 0.8
    end
end

local function updateEdge(e)
    local line, head = field(e, "Line"), field(e, "ArrowHead")
    local a1, a2 = atlasOf(line), atlasOf(head)
    local key = tostring(a1) .. ":" .. tostring(a2)
    if edges[e] == key then return end
    edges[e] = key
    local c, a = edgeColor(a1)
    if c then tint(line, c, a) end
    c, a = edgeColor(a2 or a1)
    if c then tint(head, c, a) end
    tint(field(e, "GhostLine"), selectableColor(), 0.5)
    tint(field(e, "GhostArrowHead"), selectableColor(), 0.5)
end

local function skinGate(g)
    local C = ns.COLORS
    tint(field(g, "LockIcon"), C.gold)
    local t = field(g, "GateText")
    if objType(t) == "FontString" then pcall(t.SetTextColor, t, C.gold[1], C.gold[2], C.gold[3]) end
    gates[g] = true
end

---------------------------------------------------------------------------
-- Points non depenses, onglets, boutons, recherche
---------------------------------------------------------------------------

local function skinCurrency(cd)
    local C = ns.COLORS
    local amount = field(cd, "CurrentAmountContainer")
    if not money[cd] and type(amount) == "table" and amount.CreateTexture then
        -- nos textures sur le conteneur du chiffre (cadre simple, taille
        -- fixe) : rien ne change pour la disposition de Blizzard
        local fill = tex(amount, "BACKGROUND", -8)
        fill:SetAllPoints(amount)
        fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.95)
        local e = ring(amount, fill, "BACKGROUND", -7, 0)
        paint(e, C.gold, 0.8)
        money[cd] = { fill = fill, edges = e }
    end
    fade(field(cd, "Border"))
    local label = field(cd, "UnspentLabel")
    if objType(label) == "FontString" then pcall(label.SetTextColor, label, C.text[1], C.text[2], C.text[3]) end
    local fs = field(amount, "CurrencyAmount")
    if objType(fs) == "FontString" then pcall(ns.UI.HeadFont, fs, 22) end
end

-- chiffre : or s il reste des points, gris sinon (Blizzard le recolore)
local function colorCurrency(cd)
    local C = ns.COLORS
    local fs = field(field(cd, "CurrentAmountContainer"), "CurrencyAmount")
    if objType(fs) ~= "FontString" then return end
    local n = tonumber(textOf(fs) or "")
    if n and n > 0 then pcall(fs.SetTextColor, fs, C.gold[1], C.gold[2], C.gold[3])
    else pcall(fs.SetTextColor, fs, 0.55, 0.55, 0.6) end
end

local TAB_TEX = { "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive",
                  "LeftHighlight", "MiddleHighlight", "RightHighlight" }

local function skinTab(t)
    for _, k in ipairs(TAB_TEX) do fade(field(t, k)) end
    for _, r in ipairs(regionsOf(t)) do
        if not mine[r] and objType(r) == "Texture" then fade(r) end
    end
    if not tabs[t] then tabs[t] = plate(t, 2) end
end

local function updateTab(t, p)
    local C = ns.COLORS
    local sel = val(t, "isSelected") == true
    if sel then
        local fill, edge = ns.UI.SelectedTab()
        paint(p.edges, edge)
        p.fill:SetColorTexture(fill[1], fill[2], fill[3], 0.95)
    elseif not enabled(t) then
        paint(p.edges, C.border, 0.5)
        p.fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.95)
    else
        paint(p.edges, isOver(t) and C.violet or C.border)
        p.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.95)
    end
end

-- bouton rouge (Left / Middle / Right) : plaque plate ; sa lueur "changements
-- en attente" est gardee, en or
local function skinPanelButton(b)
    if type(b) ~= "table" then return end
    for _, k in ipairs({ "Left", "Middle", "Right" }) do fade(field(b, k)) end
    local ok, h = pcall(b.GetHighlightTexture, b)
    if ok then fade(h) end
    plate(b, 1)
    local glow = field(b, "YellowGlow")
    if glow then
        local C = ns.COLORS
        for _, k in ipairs({ "Left", "Middle", "Right" }) do tint(field(glow, k), C.gold) end
    end
end

-- bouton a icone (Annuler, Reinitialiser) : petite plaque, icone en or
local function skinIconButton(b)
    if type(b) ~= "table" then return end
    plate(b, 0)
    icons[b] = true
end

local function updateIconButton(b)
    local C = ns.COLORS
    local c = enabled(b) and C.gold or C.border
    tint(field(b, "Icon"), c)
    local ok, h = pcall(b.GetHighlightTexture, b)
    if ok then tint(h, C.gold, 0.6) end
end

-- champ de recherche : ses trois morceaux a alpha 0, notre fond et lisere
local function skinEdit(e)
    if type(e) ~= "table" or edits[e] then return end
    local l, m, r = field(e, "Left"), field(e, "Middle") or field(e, "Mid"), field(e, "Right")
    if not (l and m and r) then return end
    fade(l) fade(m) fade(r)
    local C = ns.COLORS
    -- notre boite epouse les morceaux de Blizzard (20 px, centree dans le
    -- champ), comme au grimoire : meme hauteur que la plaque de la fleche
    local fill = tex(e, "BACKGROUND", -8)
    fill:SetPoint("TOPLEFT", l, "TOPLEFT", -5, 0)
    fill:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
    fill:SetColorTexture(0, 0, 0, 0.55)
    local ed = ring(e, fill, "BACKGROUND", -7, 0)
    paint(ed, C.border)
    edits[e] = { fill = fill, edges = ed }
    local glass = field(e, "searchIcon") or field(e, "SearchIcon")
    if glass then pcall(glass.SetVertexColor, glass, C.gold[1], C.gold[2], C.gold[3], 1) end
end

-- liste d apercu de la recherche : son cadre a alpha 0, notre fond
local PREVIEW = { "Background", "BorderAnchor", "BotRightCorner", "BottomBorder", "LeftBorder", "RightBorder" }
local function skinPreview(pc)
    if type(pc) ~= "table" then return end
    for _, k in ipairs(PREVIEW) do
        local t = field(pc, k)
        if isTex(t) then fade(t) end
    end
    if not plates[pc] and pc.CreateTexture then
        local C = ns.COLORS
        local p = {}
        p.fill = tex(pc, "BACKGROUND", -8)
        p.fill:SetAllPoints(pc)
        p.fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.97)
        p.edges = ring(pc, p.fill, "BACKGROUND", -7, 0)
        paint(p.edges, C.border)
        plates[pc] = p
    end
end

-- options de recherche : une fleche de menu (common-dropdown-a-button) est
-- reprise par Communs.lua, comme partout
local function skinDropdown(dd)
    if type(dd) ~= "table" then return end
    if ns.SkinCommon and ns.SkinCommon(dd) then return end
    local arrow = field(dd, "Arrow")
    if not arrow then return end
    fade(field(dd, "Background"))
    plate(dd, 2)
    tint(arrow, ns.COLORS.gold)
end

---------------------------------------------------------------------------
-- Parcours complet et releve leger
---------------------------------------------------------------------------

local function scanButtons(tf)
    for _, c in ipairs(childrenOf(field(tf, "ButtonsParent"))) do
        if field(c, "StateBorder") and field(c, "Icon") then
            pcall(skinNode, c)
        elseif field(c, "Line") and field(c, "ArrowHead") then
            edges[c] = nil
            pcall(updateEdge, c)
        elseif field(c, "LockIcon") and field(c, "GateText") then
            pcall(skinGate, c)
        end
    end
end

local function full(tf)
    skinPage(tf)
    for _, c in ipairs(childrenOf(tf)) do
        if field(c, "MainRing") and field(c, "Icon") then pcall(skinHeader, c) end
    end
    local cd = field(tf, "ClassCurrencyDisplay")
    if cd then pcall(skinCurrency, cd) end
    for _, t in ipairs(childrenOf(field(tf, "TabSystem"))) do
        if objType(t) == "Button" then pcall(skinTab, t) end
    end
    pcall(skinPanelButton, field(tf, "ApplyButton"))
    local active = field(tf, "ActiveSpec")
    pcall(skinPanelButton, field(active, "ActivateButton"))
    local label = field(active, "ActiveLabel")
    if objType(label) == "FontString" then
        local C = ns.COLORS
        pcall(label.SetTextColor, label, C.gold[1], C.gold[2], C.gold[3])
    end
    pcall(skinIconButton, field(tf, "ResetButton"))
    pcall(skinIconButton, field(tf, "UndoButton"))
    pcall(skinDropdown, field(tf, "SearchOptionsDropdown"))
    pcall(skinEdit, field(tf, "SearchBox"))
    local se = edits[field(tf, "SearchBox")]
    if se then se.drop = field(tf, "SearchOptionsDropdown") end
    local pc = field(tf, "SearchPreviewContainer")
    if visible(pc) then pcall(skinPreview, pc) end
    scanButtons(tf)
end

local function light(tf)
    local C = ns.COLORS
    for b, s in pairs(nodes) do
        if visible(b) then pcall(updateNode, b, s) end
    end
    for e in pairs(edges) do
        if visible(e) then pcall(updateEdge, e) end
    end
    local cd = field(tf, "ClassCurrencyDisplay")
    if cd then pcall(colorCurrency, cd) end
    for t, p in pairs(tabs) do
        if visible(t) then pcall(updateTab, t, p) end
    end
    for b, p in pairs(plates) do
        if not tabs[b] and visible(b) and b.IsEnabled then
            local over = isOver(b) and enabled(b)
            paint(p.edges, over and C.gold or C.border)
        end
    end
    for b in pairs(icons) do
        if visible(b) then pcall(updateIconButton, b) end
    end
    -- fleche des options de recherche : plaque recalee sur le milieu du
    -- champ (Communs.lua dessine la plaque, centree sur son bouton)
    for e, k in pairs(edits) do
        if k.drop and visible(e) and ns.SkinDropShift then
            local okF, _, fy = pcall(k.fill.GetCenter, k.fill)
            local okB, _, by = pcall(k.drop.GetCenter, k.drop)
            if okF and okB and type(fy) == "number" and type(by) == "number" then
                ns.SkinDropShift(k.drop, math.floor(fy - by + 0.5))
            end
        end
    end
end

-- Skins.lua ne descend pas dans la page des talents (reprise ici)
local function talentsPage()
    return field(_G.PlayerSpellsFrame, "TalentsFrame")
end

local prevClaimed = ns.SkinClaimed
function ns.SkinClaimed(f)
    if type(f) == "table" then
        local tf = talentsPage()
        if tf and f == tf then return true end
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

local ev = CreateFrame("Frame")
local wasShown, lastKey = false, nil
local acc, walkAcc = 0, 0

ev:SetScript("OnEvent", function()
    if ns.ModuleOff("habillage", ev) then return end
    wasShown = false
end)
pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")

local function pageKey(tf)
    local ok, key = pcall(function()
        local cfg = tf.configurationInfo
        local n = select("#", tf.ButtonsParent:GetChildren())
        return tostring(tf.talentTreeID) .. ":" .. tostring(cfg and cfg.ID) .. ":" .. n .. ":" .. select("#", tf:GetChildren())
    end)
    if ok and type(key) == "string" and not issecret(key) then return key end
    return ""
end

ns.Every(0.2, function(dt)
    walkAcc = walkAcc + dt
    if not db() or InCombatLockdown() then return end
    local tf = talentsPage()
    if not visible(tf) then
        wasShown = false
        return
    end
    local key = pageKey(tf)
    if not wasShown or key ~= lastKey or walkAcc >= 1 then
        wasShown, lastKey, walkAcc = true, key, 0
        local ok, err = pcall(full, tf)
        if not ok and ns.skinsDB then
            ns.skinsDB.errors = ns.skinsDB.errors or {}
            ns.skinsDB.errors.Talents = tostring(err)
        end
    end
    pcall(light, tf)
end, "Habillage : Talents", "habillage")
