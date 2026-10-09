--[[--------------------------------------------------------------------------
    CorpUI - module Habillage : journal de quetes en profondeur
    (QuestMapFrame rattache a la carte du monde, variante Camelot de ce
    client : pas d onglets, niveau "[12+]" devant le titre)

    Skins.lua pose deja le fond de la carte, son lisere, son bandeau et la
    croix ; ici on reprend le detail :
      - cadre de la carte : titre en or (police des titres), boutons
        agrandir / reduire en glyphes plats ;
      - barre de navigation (Monde > Royaumes de l Est > ...) : bande
        sombre, chevrons d or, survol en degrade, filet d or sous le lieu
        affiche ; fleche de liste en or ;
      - boutons de la carte : volet du journal, croix de remise a zero des
        filtres, point de passage (plaques plates, icone en or, lisere d or
        quand il est actif) ; le bouton des filtres et la liste des etages
        sont des menus a fleche, repris par Communs.lua ;
      - liste : panneau sombre, bandeau de recherche (champ et compteur
        aplatis, loupe en or), en-tetes de zones en degrade d accent avec
        filet et titre en or, lignes de quetes (survol en degrade, barre
        d or pour la quete mise en avant, plus discrete pour les quetes
        suivies), cases de suivi carrees (la coche de Blizzard passee en
        or : elle reste seule juge du suivi), tirets d objectifs en or,
        separateur en filet d or, barre de defilement minimaliste ; les
        couleurs de difficulte des titres restent celles de Blizzard ;
      - fiche d une quete : fond sombre, bandeau du bouton Retour, boutons
        plats, boutons de destination et de route en or, panneau des
        recompenses (bandeau, titre en or), cases de recompenses carrees au
        lisere de qualite (rouge si inutilisable), textes de la fiche
        eclaircis (titres en or, objectifs termines en vert).
    Textes de QuestInfo (partages avec le dialogue des PNJ et la fiche
    seule) : ce fichier en est le seul proprietaire. Clairs tant qu ils sont
    sur un fond sombre (fiche de la carte, ou contenu deroule d un QuestFrame
    habille, inscrit par PNJ.lua dans ns.QuestInfoHosts), rendus a Blizzard
    partout ailleurs (fiche seule sur parchemin, fenetres fermees,
    habillage coupe).

    Regles de ce client (valeurs secretes, taint) : l ouverture de la
    carte passe par du code protege (C_ChatInfo.PerformEmote dans
    WorldMapMixin:OnShow) qui reconstruit tout le journal. Rien de ce que
    ce code relit ne doit venir de nous :
      - aucun crochet, aucun script pose sur un cadre de Blizzard ;
      - aucun champ ecrit dans leurs tables : nos textures sont rangees
        dans des tables faibles a nous ;
      - aucune taille, position, strate, visibilite, souris, atlas,
        texture ou police de Blizzard modifiee (sauf la police de textes a
        taille fixe : titre de la fenetre, en-tetes de zones, "Recompenses"),
        aucun appel a une fonction ou une methode Lua de Blizzard :
        seulement l alpha et la couleur de leurs textures, la couleur de
        quelques textes, et nos propres textures posees dessus ;
      - aucune region a nous sur la liste deroulee (QuestScrollFrame.Contents,
        relue par sa mise en page) ni sur le contenu deroule de la fiche ;
      - le suivi CorpUI (Quetes.lua) clique les vraies lignes : elles
        gardent leurs champs, leur souris et leur ordre ;
      - rien en combat, sauf la couleur des textes de la fiche (SetTextColor
        sur des textes non proteges) et l etat de NOS textures (lectures,
        puis SetShown / SetAlpha / SetHeight / couleur sur nos regions
        seulement : les lignes recyclees par Blizzard en combat suivent
        leur nouvelle quete) ; aucune creation, aucun parcours d enfants ;
        cet etat suit aussi quand l habillage est coupe sans /reload ;
        toute valeur lue est verifiee (pcall, issecretvalue).
----------------------------------------------------------------------------]]

local _, ns = ...

local issecret = issecretvalue or function() return false end
local weak = { __mode = "k" }

local mine = setmetatable({}, weak)      -- nos regions (a ne jamais traiter)
local done = setmetatable({}, weak)      -- elements de Blizzard deja traites
local claimed = setmetatable({}, weak)   -- cadres que Skins.lua ne doit pas aplatir
local plates = setmetatable({}, weak)    -- bouton -> { fill, edges, hl, glyph, ... }
local bars = setmetatable({}, weak)      -- barre de defilement -> { thumb, knob }
local edits = setmetatable({}, weak)     -- champ de saisie -> { fill, edges, glass }
local headers = setmetatable({}, weak)   -- en-tete de zone -> { font, icon, cbtn }
local rows = setmetatable({}, weak)      -- ligne de quete -> { hov, call, sel, bar }
local checks = setmetatable({}, weak)    -- case de suivi -> { edges, ref }
local boxes = setmetatable({}, weak)     -- case de recompense -> { edges, icon, border }
local navs = setmetatable({}, weak)      -- bouton de navigation -> { hl, cur, line, chev }
local bands = setmetatable({}, weak)     -- cadre deja dote de son decor -> nos textures
local labels = setmetatable({}, weak)    -- textes en or a taille fixe -> goldFont
local tints = setmetatable({}, weak)     -- texte de la fiche -> couleurs (Blizzard, nous)

local DONE_COLOR = { 0.35, 0.85, 0.35 }  -- objectif termine (comme le suivi CorpUI)

local function db()
    local d = ns.skinsDB
    if type(d) ~= "table" or not d.enabled then return nil end
    if d.groups and d.groups.map == false then return nil end
    return d
end

-- erreur gardee pour /dump CorpUIDB.skins.errors (jamais propagee)
local function run(where, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and ns.skinsDB then
        ns.skinsDB.errors = ns.skinsDB.errors or {}
        ns.skinsDB.errors[where] = tostring(err)
    end
end

---------------------------------------------------------------------------
-- Outils
---------------------------------------------------------------------------

local function objType(o)
    if type(o) ~= "table" or not o.GetObjectType then return nil end
    local ok, t = pcall(o.GetObjectType, o)
    if ok and type(t) == "string" and not issecret(t) then return t end
end

local function isButton(o)
    local t = objType(o)
    return t == "Button" or t == "DropdownButton" or t == "CheckButton"
end

local function field(f, key)
    if type(f) ~= "table" then return nil end
    local ok, c = pcall(function() return f[key] end)
    if ok and type(c) == "table" then return c end
end

local function num(v)
    if v == nil or issecret(v) or type(v) ~= "number" then return nil end
    return v
end

-- alpha 0, jamais sur un cadre (des mixins redefinissent SetAlpha)
local function fade(t)
    if objType(t) == "Texture" and not mine[t] then pcall(t.SetAlpha, t, 0) end
end

-- texture dont Blizzard pilote l alpha : eteinte par la couleur
local function veil(t)
    if objType(t) == "Texture" and not mine[t] then pcall(t.SetVertexColor, t, 1, 1, 1, 0) end
end

local function goldTex(t)
    if objType(t) ~= "Texture" or mine[t] then return end
    local C = ns.COLORS
    pcall(t.SetDesaturated, t, true)
    pcall(t.SetVertexColor, t, C.gold[1], C.gold[2], C.gold[3], 1)
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

local function parentOf(r)
    if type(r) ~= "table" or not r.GetParent then return nil end
    local ok, p = pcall(r.GetParent, r)
    if ok and type(p) == "table" then return p end
end

-- icone recadree (jamais sur un atlas : on casserait ses coordonnees)
local function cropIcon(icon)
    if objType(icon) ~= "Texture" or mine[icon] or atlasOf(icon) then return end
    pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
end

-- textures d un cadre (pas celles de ses enfants), sauf les notres
local function fadeOwn(f)
    for _, r in ipairs(regionsOf(f)) do fade(r) end
end

-- textures d etat d un bouton (getters du moteur)
local function fadeStates(b, list)
    for _, get in ipairs(list or { "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
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

local function goldLine(host, sub)
    local C = ns.COLORS
    local line = tex(host, "BACKGROUND", sub)
    line:SetHeight(1)
    ns.UI.Gradient(line, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.8, C.gold[1], C.gold[2], C.gold[3], 0)
    return line
end

local function accent(t, a1, a2)
    local C = ns.COLORS
    ns.UI.Gradient(t, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], a1, C.violet[1], C.violet[2], C.violet[3], a2)
end

-- fichier et taille de la police d un texte (nil si illisible)
local function fontOf(fs)
    local ok, file, size = pcall(fs.GetFont, fs)
    if not ok then return nil, nil end
    if type(file) ~= "string" or issecret(file) then file = nil end
    return file, num(size)
end

-- police des titres + or, pour des textes a taille fixe ; la police est
-- reposee si Blizzard change d objet de police (survol d un bouton). Le
-- fichier ne suffit pas : sans variante grasse, la police des titres et
-- celle des objets de Blizzard (Polices.lua) sont le meme fichier, seule
-- la taille differe ; on garde donc aussi la taille obtenue
local function goldFont(fs, size)
    if objType(fs) ~= "FontString" then return nil end
    local C = ns.COLORS
    pcall(ns.UI.HeadFont, fs, size)
    pcall(fs.SetTextColor, fs, C.gold[1], C.gold[2], C.gold[3])
    local file, got = fontOf(fs)
    return { fs = fs, size = size, file = file, got = got }
end

-- or seul (texte dont la taille peut compter pour Blizzard)
local function goldColor(fs)
    if objType(fs) ~= "FontString" then return nil end
    local C = ns.COLORS
    pcall(fs.SetTextColor, fs, C.gold[1], C.gold[2], C.gold[3])
    return { fs = fs }
end

local function keepGold(h)
    if not h or not h.fs then return end
    if h.size then
        local file, size = fontOf(h.fs)
        if (file and h.file and file ~= h.file) or (size and h.got and math.abs(size - h.got) > 0.5) then
            pcall(ns.UI.HeadFont, h.fs, h.size)
        end
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
end

local BORDER_Q = { gray = 0, white = 1, green = 2, blue = 3, purple = 4, orange = 5, artifact = 6, account = 7 }

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

-- teinte rouge posee par Blizzard sur un objet inutilisable
local function redTinted(t)
    if type(t) ~= "table" or not t.GetVertexColor then return false end
    local ok, r, g, b = pcall(t.GetVertexColor, t)
    r, g, b = ok and num(r), ok and num(g), ok and num(b)
    return (r and g and b and r > 0.8 and g < 0.2 and b < 0.2) and true or false
end

---------------------------------------------------------------------------
-- Boutons, champs, barres de defilement
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

local function glyph(b, g, size, color)
    local p = plates[b]
    if not p or p.glyph then return end
    p.glyph = text(b, size)
    p.glyph:SetPoint("CENTER", 0, 0)
    p.glyph:SetText(g)
    p.color = color
end

-- bouton a glyphe seul, comme la croix de Skins.lua (agrandir / reduire)
local function bareGlyph(b, g, size)
    if objType(b) ~= "Button" or plates[b] then return end
    fadeStates(b)
    local fs = text(b, size)
    fs:SetPoint("CENTER", 0, 1)
    fs:SetText(g)
    plates[b] = { glyph = fs, bare = true }
    claimed[b] = true
end

-- bouton rouge classique (UIPanelButtonTemplate : Left/Middle/Right) :
-- toutes ses textures a alpha 0 (Blizzard change leur fichier au clic,
-- jamais leur alpha), une plaque plate dessous
local function flatButton(b)
    if objType(b) ~= "Button" or plates[b] then return end
    if not (field(b, "Left") and field(b, "Right") and (field(b, "Middle") or field(b, "Center"))) then return end
    plate(b, 1)
    fadeOwn(b)
end

-- champ de saisie : ses trois morceaux a alpha 0, notre fond et lisere
local function skinEdit(e, left)
    if type(e) ~= "table" or edits[e] or not e.CreateTexture then return end
    local l, m, r = field(e, "Left"), field(e, "Middle") or field(e, "Mid"), field(e, "Right")
    if not (l and m and r) then return end
    fade(l) fade(m) fade(r)
    local C = ns.COLORS
    local fill = tex(e, "BACKGROUND", -8)
    fill:SetPoint("TOPLEFT", e, "TOPLEFT", left, 0)
    fill:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT", 0, 0)
    fill:SetColorTexture(0, 0, 0, 0.55)
    local edges = ring(e, fill, "BACKGROUND", -7, 0)
    paintC(edges, C.border)
    edits[e] = { fill = fill, edges = edges, glass = field(e, "searchIcon"),
                 clear = field(field(e, "clearButton"), "Icon") }
    claimed[e] = true
    -- texte d aide sur une ligne (il passait sur deux dans le champ etroit)
    local hint = field(e, "Instructions")
    if objType(hint) == "FontString" then pcall(hint.SetWordWrap, hint, false) end
end

local function isScrollBar(f)
    local track = field(f, "Track")
    return track and field(track, "Thumb") and field(f, "Back") and field(f, "Forward") and true or false
end

-- barre de defilement (MinimalScrollBar) : alpha et couleur seulement,
-- jamais d atlas (Blizzard relit celui du curseur)
local function skinScrollBar(sb)
    if bars[sb] or not isScrollBar(sb) then return end
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
        if objType(t) == "Texture" then pcall(t.SetVertexColor, t, C.violet[1], C.violet[2], C.violet[3], 0.8) end
    end
    bars[sb] = { thumb = thumb, knob = knob }
end

-- barre de defilement d un cadre deroulant (champ, sinon enfant)
local function scrollBarOf(sf)
    local sb = field(sf, "ScrollBar")
    if isScrollBar(sb) then return sb end
    for _, c in ipairs(childrenOf(sf)) do
        if isScrollBar(c) then return c end
    end
end

---------------------------------------------------------------------------
-- Cadre de la carte
---------------------------------------------------------------------------

local mapTitle

local function mapFrame(map)
    local bf = field(map, "BorderFrame")
    local title = field(field(bf, "TitleContainer"), "TitleText")
    if objType(title) == "FontString" and (not mapTitle or mapTitle.fs ~= title) then
        mapTitle = goldFont(title, 12)
    end
    local mm = field(bf, "MaximizeMinimizeFrame")
    bareGlyph(field(mm, "MaximizeButton"), "+", 15)
    bareGlyph(field(mm, "MinimizeButton"), "-", 15)
end

-- Barre de navigation : les boutons se chevauchent (le bouton de gauche est
-- au-dessus), la fleche de Blizzard deborde a droite de chaque bouton.
-- Nos chevrons prennent sa place ; aucune police, aucune taille touchee
-- (Blizzard mesure leurs textes pour placer les boutons).
local function navButton(b, kind)
    local C = ns.COLORS
    fadeOwn(b)
    local s = { kind = kind }
    s.cur = tex(b, "BACKGROUND", -6)
    s.cur:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -2)
    s.cur:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 2)
    accent(s.cur, 0.28, 0.04)
    s.cur:Hide()
    s.line = tex(b, "ARTWORK", 7)
    s.line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 6, 3)
    s.line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", kind == "home" and -22 or -6, 3)
    s.line:SetHeight(2)
    s.line:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    s.line:Hide()
    s.hl = tex(b, "HIGHLIGHT")
    s.hl:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -2)
    s.hl:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 2)
    ns.UI.Gradient(s.hl, "VERTICAL", C.violet[1], C.violet[2], C.violet[3], 0.04, C.violet[1], C.violet[2], C.violet[3], 0.26)
    if kind == "overflow" then
        s.glyph = text(b, 12)
        s.glyph:SetPoint("CENTER", 0, 0)
        s.glyph:SetText("...")
        s.glyph:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    else
        s.chev = ns.UI.Chevron(b, 12, "RIGHT")
        mine[s.chev] = true
        -- accueil : dans sa pointe vide ; autres : par-dessus la marge du suivant
        if kind == "home" then s.chev:SetPoint("CENTER", b, "RIGHT", -11, 0)
        else s.chev:SetPoint("CENTER", b, "RIGHT", 9, 0) end
        s.chev:SetText(">")
        s.chev:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    end
    -- fleche de liste (Blizzard bascule l alpha de son fond au survol)
    local mab = field(b, "MenuArrowButton")
    if mab then
        -- leur fleche blanche eteinte (couleur) : notre chevron d or
        veil(field(mab, "Art"))
        veil(field(mab, "NormalTexture"))
        veil(field(mab, "PushedTexture"))
        fadeStates(mab, { "GetHighlightTexture" })
        if mab.CreateTexture then
            s.arrow = ns.UI.Chevron(mab, 12, "DOWN")
            mine[s.arrow] = true
            s.arrow:SetPoint("CENTER", mab, "CENTER", 0, 0)
        end
    end
    navs[b] = s
    claimed[b] = true
end

local function navBar(map)
    local nb = field(map, "NavBar")
    if type(nb) ~= "table" or not nb.CreateTexture then return end
    local C = ns.COLORS
    if not bands[nb] then
        fadeOwn(nb)
        fadeOwn(field(nb, "overlay"))
        local fill = tex(nb, "BACKGROUND", -8)
        fill:SetPoint("TOPLEFT", nb, "TOPLEFT", 0, -1)
        fill:SetPoint("BOTTOMRIGHT", nb, "BOTTOMRIGHT", 0, 1)
        fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.9)
        paintC(ring(nb, fill, "BACKGROUND", -7, 0), C.border)
        bands[nb] = { fill = fill }
    end
    local home, over = field(nb, "home"), field(nb, "overflow")
    for _, b in ipairs(childrenOf(nb)) do
        if not navs[b] and isButton(b) then
            if b == home then navButton(b, "home")
            elseif b == over then navButton(b, "overflow")
            elseif field(b, "arrowUp") and field(b, "arrowDown") then navButton(b, "nav") end
        end
    end
end

-- boutons poses sur la carte (le canevas, les punaises et les POI ne sont
-- jamais touches)
local floorScanned = false

local function mapButtons(map)
    local spt = field(map, "SidePanelToggle")
    for key, g in pairs({ OpenButton = ">", CloseButton = "<" }) do
        local b = field(spt, key)
        if objType(b) == "Button" and not plates[b] then
            fadeOwn(b)
            plate(b, 5)
            glyph(b, g, 13)
        end
    end
    -- bouton des filtres : en Camelot, sa fleche (common-dropdown-a-button)
    -- est celle de tous les menus (Communs.lua) ; sinon plaque et icone en or
    local opt = field(map, "WorldMapTrackingOptionsButton")
    if isButton(opt) and not plates[opt] and not done[opt] and opt.CreateTexture then
        done[opt] = true
        if not (ns.SkinCommon and ns.SkinCommon(opt)) then
            fadeStates(opt, { "GetHighlightTexture" })
            local p = plate(opt, 4)
            p.icon = field(opt, "Icon")
            goldTex(p.icon)
        end
        -- croix de remise a zero (montree par Blizzard si un filtre change)
        local reset = field(opt, "ResetButton")
        if isButton(reset) then
            for _, get in ipairs({ "GetNormalTexture", "GetHighlightTexture" }) do
                if reset[get] then
                    local ok, t = pcall(reset[get], reset)
                    if ok then goldTex(t) end
                end
            end
        end
    end
    -- liste des etages (cartes a plusieurs niveaux) : enfant de la carte
    -- sans champ, cree une fois pour toutes au chargement de la carte ;
    -- fond a alpha 0 (Blizzard ne change que l atlas de la fleche), aucune
    -- police touchee ; un menu a fleche de Blizzard est a Communs.lua
    if not floorScanned then
        floorScanned = true
        for _, c in ipairs(childrenOf(map)) do
            if isButton(c) and c ~= opt and not plates[c] and c.CreateTexture
               and not (ns.SkinCommon and ns.SkinCommon(c))
               and objType(field(c, "Background")) == "Texture" and objType(field(c, "Arrow")) == "Texture"
               and objType(field(c, "Text")) == "FontString" then
                fade(field(c, "Background"))
                local p = plate(c, 1)
                p.icon = field(c, "Arrow")
                goldTex(p.icon)
            end
        end
    end
    local pin = field(map, "WorldMapTrackingPinButton")
    if isButton(pin) and not plates[pin] and pin.CreateTexture then
        for _, k in ipairs({ "Background", "Border", "ActiveTexture" }) do fade(field(pin, k)) end
        fadeStates(pin, { "GetHighlightTexture" })
        for _, r in ipairs(regionsOf(pin)) do
            if atlasOf(r) == "MapCornerShadow-Right" then fade(r) end
        end
        local p = plate(pin, 4)
        p.active = field(pin, "ActiveTexture")
    end
end

---------------------------------------------------------------------------
-- Liste des quetes
---------------------------------------------------------------------------

-- panneau du journal, pose sur QuestMapFrame (jamais sur la liste deroulee)
local function logPanel(qmf)
    if bands[qmf] then return end
    local C = ns.COLORS
    local s = {}
    s.fill = tex(qmf, "BACKGROUND", -8)
    s.fill:SetAllPoints(qmf)
    s.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.55)
    s.sep = tex(qmf, "BACKGROUND", -7)
    s.sep:SetPoint("TOPLEFT", qmf, "TOPLEFT", 0, 0)
    s.sep:SetPoint("BOTTOMLEFT", qmf, "BOTTOMLEFT", 0, 0)
    s.sep:SetWidth(1)
    s.sep:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
    -- bandeau de la recherche : les 29 px au-dessus de la liste
    local qf = field(qmf, "QuestsFrame") or qmf
    s.head = tex(qmf, "BACKGROUND", -6)
    s.head:SetPoint("TOPLEFT", qf, "TOPLEFT", 1, 0)
    s.head:SetPoint("TOPRIGHT", qmf, "TOPRIGHT", -1, 0)
    s.head:SetHeight(29)
    accent(s.head, 0.30, 0.03)
    s.line = goldLine(qmf, -6)
    s.line:SetPoint("TOPLEFT", s.head, "BOTTOMLEFT")
    s.line:SetPoint("TOPRIGHT", s.head, "BOTTOMRIGHT")
    bands[qmf] = s
end

-- cadre de la liste : fond, ombre, recherche, compteur, reglages
local function listFrame(sf)
    fade(field(sf, "Background"))      -- jamais SetAtlas / SetTexCoord : relus
    local bf = field(sf, "BorderFrame")
    fadeOwn(bf)
    -- l ombre du bas recoit son alpha a chaque defilement : la couleur
    veil(field(bf, "Shadow"))
    skinScrollBar(scrollBarOf(sf))
    skinEdit(field(sf, "SearchBox"), -5)
    skinEdit(_G.QuestLogCount, 2)
    local sd = field(sf, "SettingsDropdown")
    if sd and not done[sd] then
        done[sd] = true
        goldTex(field(sd, "Icon"))
    end
end

-- case de suivi (cadre 14 x 14, pas un CheckButton) : carre sombre ; la
-- coche de Blizzard (qui ne fait que Show / Hide) reste visible, passee en
-- or : le suivi affiche est toujours le sien, meme en combat ou quand
-- l habillage est coupe
local function trackBox(cb)
    if type(cb) ~= "table" or checks[cb] or not cb.CreateTexture then return end
    local C = ns.COLORS
    local cm = field(cb, "CheckMark")
    for _, r in ipairs(regionsOf(cb)) do
        if r ~= cm then fade(r) end
    end
    goldTex(cm)
    local fill = tex(cb, "BACKGROUND", -8)
    fill:SetSize(12, 12)
    fill:SetPoint("CENTER", cb, "CENTER", 0, 0)
    fill:SetColorTexture(0, 0, 0, 0.6)
    local edges = ring(cb, fill, "BORDER", 7, 0)
    paintC(edges, C.border)
    checks[cb] = { edges = edges, ref = cm }
end

-- ligne de quete (pool des titres) : nos degrades couvrent la bande du
-- titre (pas les objectifs, qui sont des cadres voisins), dans les bornes
-- de la ligne, sans ancrage sur son texte (Blizzard le decale au clic)
local function questRow(b)
    if rows[b] then return end
    local C = ns.COLORS
    fade(field(b, "HighlightTexture"))
    local s = {}
    local function band(layer, sub)
        local t = tex(b, layer, sub)
        t:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -3)
        t:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, -3)
        t:SetHeight(22)
        return t
    end
    s.call = band("BACKGROUND", 1)
    accent(s.call, 0.30, 0.03)
    s.call:Hide()
    s.sel = band("BACKGROUND", 2)
    accent(s.sel, 0.50, 0.05)
    s.sel:Hide()
    s.bar = band("BACKGROUND", 3)
    s.bar:ClearAllPoints()
    s.bar:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -3)
    s.bar:SetWidth(2)
    s.bar:SetHeight(22)
    s.bar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    s.bar:Hide()
    s.hov = band("HIGHLIGHT")
    accent(s.hov, 0.22, 0.02)
    rows[b] = s
    claimed[b] = true
    trackBox(field(b, "Checkbox"))
end

-- en-tete de zone (ListHeaderVisualTemplate, 289 x 22)
local function zoneHeader(b)
    if headers[b] then return end
    local C = ns.COLORS
    fadeStates(b, { "GetNormalTexture", "GetHighlightTexture" })
    local h = {}
    local fill = tex(b, "BACKGROUND", 1)
    fill:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 2)
    accent(fill, 0.30, 0.03)
    local line = goldLine(b, 2)
    line:SetPoint("TOPLEFT", fill, "BOTTOMLEFT")
    line:SetPoint("TOPRIGHT", fill, "BOTTOMRIGHT")
    local hover = tex(b, "HIGHLIGHT")
    hover:SetAllPoints(fill)
    accent(hover, 0.25, 0.02)
    -- titre : taille du bouton fixe, seule l infobulle de texte tronque en depend
    h.font = goldFont(field(b, "ButtonText"), 12)
    h.cbtn = field(b, "CollapseButton")
    h.icon = field(h.cbtn, "Icon")
    goldTex(h.icon)
    headers[b] = h
    claimed[b] = true
end

-- objectif sous une ligne : tiret en or (le texte garde sa couleur)
local function objectiveLine(f)
    if done[f] then return end
    done[f] = true
    local dash = field(f, "Dash")
    if objType(dash) == "FontString" then
        local C = ns.COLORS
        pcall(dash.SetTextColor, dash, C.gold[1], C.gold[2], C.gold[3])
    end
end

-- separateur et en-tete d histoire : enfants de la liste, decor a nous
-- pose sur eux (jamais sur la liste elle-meme)
local function separator(f)
    if type(f) ~= "table" or bands[f] or not f.CreateTexture then return end
    fade(field(f, "Divider"))
    local line = goldLine(f, 1)
    line:SetPoint("LEFT", f, "LEFT", 8, 0)
    line:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    bands[f] = { line = line }
end

local function storyHeader(f)
    if type(f) ~= "table" or bands[f] or not f.CreateTexture then return end
    for _, k in ipairs({ "Background", "HighlightTexture", "Divider" }) do fade(field(f, k)) end
    local fill = tex(f, "BACKGROUND", -8)
    fill:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -6)
    fill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 4)
    accent(fill, 0.30, 0.03)
    local line = goldLine(f, -7)
    line:SetPoint("TOPLEFT", fill, "BOTTOMLEFT")
    line:SetPoint("TOPRIGHT", fill, "BOTTOMRIGHT")
    bands[f] = { fill = fill }
    local t = goldColor(field(f, "Text"))
    if t then labels[t.fs] = t end
end

-- enfants de la liste, reconnus par leurs champs ; tout le reste (boutons
-- POI de la carte, en-tetes de campagne...) est ignore
local function listWalk(sf)
    local contents = field(sf, "Contents")
    if not contents then return end
    for _, c in ipairs(childrenOf(contents)) do
        if visible(c) and not rows[c] and not headers[c] and not done[c] then
            if field(c, "Checkbox") and field(c, "Text") and field(c, "HighlightTexture") and field(c, "TagTexture") then
                if objType(c) == "Button" then questRow(c) end
            elseif field(c, "CollapseButton") and field(c, "ButtonText") then
                if objType(c) == "Button" then zoneHeader(c) end
            elseif field(c, "Dash") and field(c, "Text") then
                objectiveLine(c)
            end
        end
    end
    separator(field(contents, "Separator"))
    storyHeader(field(contents, "StoryHeader"))
end

---------------------------------------------------------------------------
-- Fiche d une quete
---------------------------------------------------------------------------

local detailsDone = false   -- fond de la fiche efface au moins une fois

-- panneau des recompenses (au-dessus du texte deroule : fond opaque)
local function rewardsPanel(rf)
    if type(rf) ~= "table" or bands[rf] or not rf.CreateTexture then return end
    local C = ns.COLORS
    for _, k in ipairs({ "Top", "Bottom", "Background" }) do fade(field(rf, k)) end
    local s = {}
    s.fill = tex(rf, "BACKGROUND", -8)
    s.fill:SetAllPoints(rf)
    s.fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.98)
    s.top = tex(rf, "BACKGROUND", -7)
    s.top:SetPoint("TOPLEFT", rf, "TOPLEFT", 0, 0)
    s.top:SetPoint("TOPRIGHT", rf, "TOPRIGHT", 0, 0)
    s.top:SetHeight(1)
    s.top:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
    s.band = tex(rf, "BACKGROUND", -6)
    s.band:SetPoint("TOPLEFT", rf, "TOPLEFT", 1, -6)
    s.band:SetPoint("TOPRIGHT", rf, "TOPRIGHT", -1, -6)
    s.band:SetHeight(38)
    accent(s.band, 0.32, 0.03)
    s.line = goldLine(rf, -6)
    s.line:SetPoint("TOPLEFT", s.band, "BOTTOMLEFT")
    s.line:SetPoint("TOPRIGHT", s.band, "BOTTOMRIGHT")
    s.label = field(rf, "Label")
    local h = goldFont(s.label, 13)
    if h then labels[h.fs] = h end
    bands[rf] = s
end

-- case de recompense (petit bouton d objet, XP, argent, sort, reputation)
local function rewardBox(b, icon, nf)
    local C = ns.COLORS
    fade(nf)
    local border = field(b, "IconBorder")
    fade(border)
    local bx = {}
    bx.fill = tex(b, "BACKGROUND", -8)
    bx.fill:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
    bx.fill:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
    bx.fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.9)
    bx.edges = ring(b, icon, "OVERLAY", 7, 1)
    paintC(bx.edges, C.border)
    -- plaque du nom, de l icone au bord droit du bouton
    bx.name = tex(b, "BACKGROUND", -7)
    bx.name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 3, 0)
    bx.name:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 3, 0)
    bx.name:SetPoint("RIGHT", b, "RIGHT", 0, 0)
    bx.name:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.85)
    paintC(ring(b, bx.name, "BACKGROUND", -6, 0), C.border, 0.7)
    bx.icon, bx.border, bx.nf = icon, border, nf
    cropIcon(icon)
    boxes[b] = bx
    claimed[b] = true
end

local function rewardWalk()
    local mr = _G.MapQuestInfoRewardsFrame
    if not visible(mr) then return end
    for _, b in ipairs(childrenOf(mr)) do
        if not boxes[b] and isButton(b) and visible(b) and b.CreateTexture then
            local icon, nf = field(b, "Icon"), field(b, "NameFrame")
            if objType(icon) == "Texture" and objType(nf) == "Texture" then rewardBox(b, icon, nf) end
        end
    end
end

local function details(d)
    -- fonds : Blizzard relit leur atlas (AdjustBackgroundTexture), donc
    -- jamais SetAtlas ni SetTexCoord, l alpha seulement
    fade(field(d, "Bg"))
    fade(field(d, "SealMaterialBG"))
    fadeOwn(field(d, "BorderFrame"))
    detailsDone = true
    local back = field(d, "BackFrame")
    if back and not bands[back] and back.CreateTexture then
        fadeOwn(back)
        local fill = tex(back, "BACKGROUND", -8)
        fill:SetPoint("TOPLEFT", back, "TOPLEFT", 1, -1)
        fill:SetPoint("TOPRIGHT", back, "TOPRIGHT", -1, -1)
        fill:SetHeight(41)
        accent(fill, 0.30, 0.03)
        local line = goldLine(back, -7)
        line:SetPoint("TOPLEFT", fill, "BOTTOMLEFT")
        line:SetPoint("TOPRIGHT", fill, "BOTTOMRIGHT")
        bands[back] = { fill = fill }
    end
    flatButton(field(back, "BackButton"))
    for _, k in ipairs({ "AbandonButton", "ShareButton", "TrackButton" }) do flatButton(field(d, k)) end
    -- destination finale / route (QuestLogPathButtonTemplate) : icone en or
    -- (Blizzard ne fait que deplacer l icone au clic)
    for _, k in ipairs({ "DestinationMapButton", "WaypointMapButton" }) do
        local b = field(d, k)
        if b and not done[b] then
            done[b] = true
            goldTex(field(b, "Icon"))
            goldTex(field(b, "HighlightIcon"))
        end
    end
    rewardsPanel(field(field(d, "RewardsFrameContainer"), "RewardsFrame"))
    skinScrollBar(scrollBarOf(field(d, "ScrollFrame")))
end

---------------------------------------------------------------------------
-- Textes de QuestInfo : couleur claire tant qu ils sont sur un fond sombre
-- (fiche de la carte, ou hotes inscrits dans ns.QuestInfoHosts : contenus
-- deroules du QuestFrame habille par PNJ.lua), rendue a Blizzard ailleurs
-- (fiche seule, sur parchemin). Un seul proprietaire, ce fichier : aucun
-- combat entre deux releves. Blizzard ne relit jamais ces couleurs ; on ne
-- rend la sienne que si nous sommes encore les derniers a l avoir changee.
---------------------------------------------------------------------------

local GOLD_TEXT = { "QuestInfoTitleHeader", "QuestInfoDescriptionHeader", "QuestInfoObjectivesHeader" }
local BODY_TEXT = { "QuestInfoObjectivesText", "QuestInfoDescriptionText", "QuestInfoGroupSize",
                    "QuestInfoTimerText", "QuestInfoSpellObjectiveLearnLabel", "QuestInfoRequiredMoneyText",
                    "QuestInfoRewardText", "QuestInfoQuestType" }
-- cadre des recompenses du dialogue (QuestInfoRewardsFrame ; la carte a le
-- sien, MapQuestInfoRewardsFrame, jamais dans un hote) : titre en or, ces
-- textes et les en-tetes de sorts clairs, jamais les noms des objets
local REWARD_BODY = { "ItemChooseText", "ItemReceiveText", "PlayerTitleText", "QuestSessionBonusReward" }

-- fournisseurs d hotes : fonctions rendant une liste de cadres (PNJ.lua)
ns.QuestInfoHosts = ns.QuestInfoHosts or {}

local function near(a, b) return a ~= nil and b ~= nil and math.abs(a - b) < 0.01 end

local function colorOf(fs)
    local ok, r, g, b = pcall(fs.GetTextColor, fs)
    if ok and num(r) and num(g) and num(b) then return r, g, b end
end

local function vertexOf(fs)
    if not fs.GetVertexColor then return nil end
    local ok, r, g, b = pcall(fs.GetVertexColor, fs)
    if ok and num(r) and num(g) and num(b) then return r, g, b end
end

local function white(r, g, b) return r and r > 0.99 and g > 0.99 and b > 0.99 end

local function same(t, r, g, b)
    return t.set ~= nil and near(r, t.set[1]) and near(g, t.set[2]) and near(b, t.set[3])
end

-- vtx : en-tete de sort, que Blizzard teinte par SetVertexColor (couleur du
-- materiau, posee a chaque prise dans son pool) : teinte neutre le temps
-- de l habillage. La couleur n est ecrite que si elle a change.
local function tint(fs, c, vtx)
    if objType(fs) ~= "FontString" then return end
    local t = tints[fs]
    if not t then
        t = {}
        tints[fs] = t
    end
    local r, g, b = colorOf(fs)
    -- couleur posee par Blizzard depuis notre passage : nouvelle reference
    if r and not same(t, r, g, b) then t.r, t.g, t.b = r, g, b end
    local force = false
    if vtx then
        local vr, vg, vb = vertexOf(fs)
        if vr and not white(vr, vg, vb) and not (near(vr, c[1]) and near(vg, c[2]) and near(vb, c[3])) then
            t.vr, t.vg, t.vb = vr, vg, vb
            pcall(fs.SetVertexColor, fs, 1, 1, 1)
            force = true
        end
    end
    if force or not (r and near(r, c[1]) and near(g, c[2]) and near(b, c[3])) then
        pcall(fs.SetTextColor, fs, c[1], c[2], c[3])
    end
    t.set = c
end

local function untint(fs, t)
    tints[fs] = nil
    local r, g, b = colorOf(fs)
    if t.r and r and same(t, r, g, b) then pcall(fs.SetTextColor, fs, t.r, t.g, t.b) end
    if t.vr and white(vertexOf(fs)) then pcall(fs.SetVertexColor, fs, t.vr, t.vg, t.vb) end
end

-- hotes du releve en cours (table reutilisee : releve a chaque image quand
-- un QuestFrame habille est ouvert)
local hostSet = {}

-- texte dans un hote (parent direct ou jusqu a deux cadres intermediaires :
-- objectifs, recompenses, texte de l experience)
local function inside(fs)
    local p = parentOf(fs)
    for _ = 1, 3 do
        if not p then return false end
        if hostSet[p] then return true end
        p = parentOf(p)
    end
    return false
end

local function addHost(h)
    if objType(h) == nil then return false end
    hostSet[h] = true
    return true
end

local function isDone(fs)
    local ok, s = pcall(fs.GetText, fs)
    if not ok or issecret(s) or type(s) ~= "string" then return false end
    local c = COMPLETE
    if issecret(c) or type(c) ~= "string" or c == "" then return false end
    return s:find("(" .. c .. ")", 1, true) ~= nil
end

local function rewardKnown(rf, r)
    if r == field(rf, "Header") then return true end
    for _, k in ipairs(REWARD_BODY) do
        if r == field(rf, k) then return true end
    end
    return false
end

-- on : fiche de la carte affichee (et habillee) ; les autres hotes sont
-- demandes a leurs fournisseurs
local function textPass(on)
    for h in pairs(hostSet) do hostSet[h] = nil end
    local any = false
    if on then
        local d = field(_G.QuestMapFrame, "DetailsFrame")
        if visible(d) then any = addHost(field(field(d, "ScrollFrame"), "Contents")) or any end
    end
    for _, provider in ipairs(ns.QuestInfoHosts) do
        local ok, list = pcall(provider)
        if ok and type(list) == "table" then
            for _, h in ipairs(list) do any = addHost(h) or any end
        end
    end
    for fs, t in pairs(tints) do
        if not (any and inside(fs)) then untint(fs, t) end
    end
    if not any then return end
    local C = ns.COLORS
    for _, n in ipairs(GOLD_TEXT) do
        local fs = _G[n]
        if type(fs) == "table" and inside(fs) then tint(fs, C.gold) end
    end
    for _, n in ipairs(BODY_TEXT) do
        local fs = _G[n]
        if type(fs) == "table" and inside(fs) then tint(fs, isDone(fs) and DONE_COLOR or C.text) end
    end
    for i = 1, 40 do
        local fs = _G["QuestInfoObjective" .. i]
        if type(fs) ~= "table" then break end
        if inside(fs) then tint(fs, isDone(fs) and DONE_COLOR or C.text) end
    end
    local rf = _G.QuestInfoRewardsFrame
    if type(rf) == "table" and inside(rf) then
        tint(field(rf, "Header"), C.gold)
        for _, k in ipairs(REWARD_BODY) do tint(field(rf, k), C.text) end
        tint(field(field(rf, "XPFrame"), "ReceiveText"), C.text)
        -- en-tetes de sorts : textes du pool de Blizzard poses sur le cadre
        for _, r in ipairs(regionsOf(rf)) do
            if objType(r) == "FontString" and not mine[r] and not rewardKnown(rf, r) then tint(r, C.text, true) end
        end
    end
end

local function mapOn()
    local map = _G.WorldMapFrame
    return type(map) == "table" and map.CreateTexture ~= nil and visible(map) and db() ~= nil and detailsDone
end

-- releve des textes demande par PNJ.lua (a chaque image, QuestFrame ouvert)
function ns.QuestInfoTextPass()
    run("QuestLogText", textPass, mapOn())
end

---------------------------------------------------------------------------
-- Releves
---------------------------------------------------------------------------

local function full(map)
    run("QuestLogMap", mapFrame, map)
    run("QuestLogNav", navBar, map)
    run("QuestLogButtons", mapButtons, map)
    local qmf = _G.QuestMapFrame
    if not visible(qmf) then return end
    run("QuestLogPanel", logPanel, qmf)
    local sf = field(field(qmf, "QuestsFrame"), "ScrollFrame") or _G.QuestScrollFrame
    if sf then
        run("QuestLogList", listFrame, sf)
        if visible(sf) then run("QuestLogRows", listWalk, sf) end
    end
    local d = field(qmf, "DetailsFrame")
    if visible(d) then
        run("QuestLogDetails", details, d)
        run("QuestLogRewards", rewardWalk)
    end
end

local function superTracked()
    local fn = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID
    if type(fn) ~= "function" then return nil end
    local ok, id = pcall(fn)
    if ok and not issecret(id) and type(id) == "number" and id > 0 then return id end
end

local function rowState(b, s, st)
    -- bande du titre : hauteur du texte (lecture seule)
    local okH, h = pcall(function() return b.Text:GetHeight() end)
    h = (okH and num(h)) or 13
    h = math.max(10, math.min(80, h)) + 9
    if h ~= s.h then
        s.h = h
        for _, t in ipairs({ s.call, s.sel, s.bar, s.hov }) do t:SetHeight(h) end
    end
    local okQ, q = pcall(function() return b.questID end)
    local sel = st ~= nil and okQ and not issecret(q) and type(q) == "number" and q == st
    local tracked = shown(field(field(b, "Checkbox"), "CheckMark"))
    s.sel:SetShown(sel)
    s.bar:SetShown(sel or tracked)
    s.bar:SetAlpha(sel and 1 or 0.45)
    -- survol d une punaise de la carte : Blizzard montre sa lueur
    s.call:SetShown(not sel and shown(field(b, "HighlightTexture")) and not isOver(b))
end

-- etat de NOS textures (survol, lieu affiche, mise en avant, suivi,
-- liseres de qualite) : lectures, puis nos regions seulement. Tourne aussi
-- en combat et quand l habillage est coupe sans /reload : Blizzard recycle
-- les lignes (repli, recherche, suivi automatique) a tout moment
local function state()
    local C = ns.COLORS
    for b, p in pairs(plates) do
        if visible(b) then
            local en = enabled(b)
            local over = isOver(b) and en
            if p.edges then
                local c = C.border
                if over or (p.active and shown(p.active)) then c = C.gold end
                paintC(p.edges, c)
            end
            if p.glyph then
                local c = p.color or C.gold
                if p.bare then c = over and C.gold or C.text end
                p.glyph:SetTextColor(c[1], c[2], c[3])
                p.glyph:SetAlpha(en and 1 or 0.35)
            end
        end
    end
    -- barre de navigation : lieu affiche (dernier bouton, marque par Blizzard)
    local anyNav = false
    for b, s in pairs(navs) do
        if s.kind == "nav" and visible(b) then anyNav = true end
    end
    for b, s in pairs(navs) do
        if visible(b) then
            local cur
            if s.kind == "nav" then cur = shown(field(b, "selected"))
            else cur = s.kind == "home" and not anyNav end
            s.cur:SetShown(cur)
            s.line:SetShown(cur)
            if s.chev then s.chev:SetShown(not cur) end
            local c = isOver(b) and { 1, 1, 1 } or C.gold
            local g = s.chev or s.glyph
            if g then g:SetTextColor(c[1], c[2], c[3]) end
        end
    end
    -- bandeaux qui suivent l affichage de Blizzard
    local qmf = _G.QuestMapFrame
    local lp = qmf and bands[qmf]
    if lp and lp.head then
        local sf = field(field(qmf, "QuestsFrame"), "ScrollFrame")
        local on = visible(sf)
        lp.head:SetShown(on)
        lp.line:SetShown(on)
    end
    for _, s in pairs(bands) do
        if s.label and s.band then
            local on = shown(s.label)
            s.band:SetShown(on)
            s.line:SetShown(on)
        end
    end
    -- champs de saisie : lisere d or au focus
    for e, k in pairs(edits) do
        if visible(e) then
            local okF, focus = pcall(e.HasFocus, e)
            if okF and focus == true then paintC(k.edges, C.gold)
            elseif isOver(e) then paintC(k.edges, C.violet)
            else paintC(k.edges, C.border) end
        end
    end
    -- lignes de quetes et cases de suivi
    local st = superTracked()
    for b, s in pairs(rows) do
        if visible(b) then pcall(rowState, b, s, st) end
    end
    for cb, k in pairs(checks) do
        if visible(cb) then paintC(k.edges, isOver(cb) and C.gold or C.border) end
    end
    -- recompenses : lisere de qualite, rouge si inutilisable
    for b, bx in pairs(boxes) do
        if visible(b) then
            if redTinted(bx.nf) or redTinted(bx.icon) then
                paint(bx.edges, 0.9, 0.15, 0.15, 1)
            else
                local r, g, bl = borderColor(bx.border)
                if r then paint(bx.edges, r, g, bl, 1) else paintC(bx.edges, C.border) end
            end
        end
    end
    for sb, k in pairs(bars) do
        if visible(sb) then
            if isOver(k.thumb) then
                k.knob:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.9)
            else
                k.knob:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.6)
            end
        end
    end
end

-- textures et textes de Blizzard que l on garde (alpha, couleur, police) :
-- hors combat, habillage actif
local function touch()
    keepGold(mapTitle)
    for b, p in pairs(plates) do
        if p.icon and visible(b) then goldTex(p.icon) end
    end
    for _, h in pairs(labels) do keepGold(h) end
    -- loupe en or (Blizzard la grise a la perte du focus)
    for e, k in pairs(edits) do
        if visible(e) then
            goldTex(k.glass)
            goldTex(k.clear)
        end
    end
    -- en-tetes de zones
    for b, h in pairs(headers) do
        if visible(b) then
            keepGold(h.font)
            goldTex(h.icon)
            fadeStates(h.cbtn, { "GetHighlightTexture" })
        end
    end
    for b, bx in pairs(boxes) do
        if visible(b) then
            fade(bx.border)
            cropIcon(bx.icon)
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

-- cle d affichage : un changement relance tout de suite le parcours
local function pageKey(map)
    local ok, key = pcall(function()
        local qmf = _G.QuestMapFrame
        local d = qmf and qmf.DetailsFrame
        local q = d and d.questID
        if issecret(q) then q = "s" end
        local sf = qmf and qmf.QuestsFrame and qmf.QuestsFrame.ScrollFrame
        local contents = sf and sf.Contents
        local mr = _G.MapQuestInfoRewardsFrame
        local nb = map.NavBar
        local maxi = map.isMaximized
        if issecret(maxi) then maxi = nil end
        return table.concat({
            visible(qmf) and "1" or "0", visible(d) and "1" or "0", visible(sf) and "1" or "0",
            tostring(q), #childrenOf(contents), #childrenOf(mr), #childrenOf(nb), tostring(maxi == true),
        }, ":")
    end)
    if ok and type(key) == "string" and not issecret(key) then return key end
    return ""
end

local ev = CreateFrame("Frame")
local acc, walkAcc = 0, 0
local wasShown, lastKey = false, nil

ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then wasShown = false end
end)
pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")

ev:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.2 then return end
    walkAcc = walkAcc + acc
    acc = 0
    local map = _G.WorldMapFrame
    local vis = type(map) == "table" and map.CreateTexture ~= nil and visible(map)
    local open = vis and db() ~= nil
    -- textes de QuestInfo (fiche, dialogue des PNJ) : suivis aussi en
    -- combat (SetTextColor seul)
    run("QuestLogText", textPass, mapOn())
    if not vis then
        wasShown = false
        return
    end
    if not open then
        wasShown = false
    elseif not InCombatLockdown() then
        -- creations, parcours et textures de Blizzard : hors combat
        local key = pageKey(map)
        if not wasShown or key ~= lastKey or walkAcc >= 0.6 then
            wasShown, lastKey, walkAcc = true, key, 0
            run("QuestLog", full, map)
            -- fiche affichee pour la premiere fois : textes tout de suite
            run("QuestLogText", textPass, detailsDone)
        end
        run("QuestLogTouch", touch)
    end
    -- etat de nos textures : toujours (combat, habillage coupe compris)
    run("QuestLogState", state)
end)
