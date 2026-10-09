--[[--------------------------------------------------------------------------
    CorpUI - module Habillage : guilde et communautes en profondeur
    (CommunitiesFrame de Blizzard_Communities, variante Camelot de ce client)

    Skins.lua pose deja le fond de la fenetre, la croix et aplatit les
    boutons rouges proches de la fenetre (profondeur 3) ; ici on reprend le
    detail :
      - liste des communautes a gauche : decor bleu (filigranes, coins,
        barres) a alpha 0, panneau sombre ; chaque entree devient une plaque
        plate (lisere d or au survol, degrade d accent + barre d or pour la
        communaute choisie), avatar carre (masque rond retire, anneau
        remplace par un lisere), blason de guilde garde ;
      - onglets lateraux (discussion, membres, avantages, infos, recherche
        de guilde) : tuile carree, icone recadree, rail sombre, lisere d or
        et barre d or pour l onglet actif ;
      - discussion : cadre interieur sombre, zone de saisie habillee ;
      - liste des membres (et des candidats) : panneau sombre, en-tetes de
        colonnes plats au titre or et filet d or, lignes a separateur fin et
        survol en degrade, en-tetes de metiers en degrade, case "hors ligne" ;
      - infos de guilde, nouvelles, avantages : panneaux sombres, bandeaux
        d en-tete en degrade + filet d or, titres en or, barre de reputation
        de guilde a la texture CorpUI (couleur de Blizzard gardee) ;
      - boutons Filtre : plaque plate ; les menus a fleche (canaux, rangs...)
        sont repris par Communs.lua ;
      - dialogues (fiche d un membre, canal, notifications, recrutement,
        message du jour, journal, filtres des nouvelles, parametres de la
        communaute, gestion des invitations) : fond, ombre, bandeau, titre
        or, croix plate, champs et cases a cocher habilles, boutons radio
        ronds (choix exclusif garde lisible) ;
      - boutons de reduction / agrandissement : plaque et signe.
    Les decors sont reconnus par leur atlas, leur nom de champ ou leur
    layoutType, jamais detruits.

    Regles de ce client (valeurs secretes, taint) :
      - aucun crochet, aucun SetScript, aucun appel de methode de Blizzard
        (mixins) : tout passe par un releve periodique, fenetre ouverte ;
      - aucun champ ecrit dans les tables de Blizzard : nos textures sont
        rangees dans des tables faibles a nous, indexees par le cadre ;
      - aucune taille, position, strate, visibilite ou attribut de Blizzard
        modifie : seulement l alpha, la couleur, le recadrage des icones,
        le retrait d un masque, et nos propres textures / textes ;
      - les couleurs d information (classe, en ligne / hors ligne, rangs,
        guilde en vert, Battle.net en bleu, etats desactives) sont gardees ;
      - Blizzard_CommunitiesSecure (ajout / creation de communaute) et le
        choix d avatar qui en depend ne sont jamais touches ;
      - rien en combat ; toute valeur lue est verifiee (pcall, issecretvalue).
    Diagnostic : la premiere erreur de la session, avec le nom de l etape,
    est gardee dans CorpUIDB.skins.errors.Communities.
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
local edits = setmetatable({}, weak)     -- champ de saisie -> { fill, edges }
local tabs = setmetatable({}, weak)      -- onglet lateral -> { fill, edges, bar, icon }
local rails = setmetatable({}, weak)     -- parent des onglets -> { fill, edges }
local entries = setmetatable({}, weak)   -- entree de la liste des communautes
local rows = setmetatable({}, weak)      -- ligne de membre / candidat / avantage
local profHeads = setmetatable({}, weak) -- en-tete de metier (liste des membres)
local cells = setmetatable({}, weak)     -- en-tete de colonne -> { fs }
local bands = setmetatable({}, weak)     -- texture d en-tete de Blizzard -> notre bandeau
local labels = setmetatable({}, weak)    -- titre passe en or -> { fs, size, file }
local tints = setmetatable({}, weak)     -- texture a teinter en or (atlas changeant)
local panels = setmetatable({}, weak)    -- panneau deja habille
local inner = setmetatable({}, weak)     -- cadre interieur (notes, journaux)
local masked = setmetatable({}, weak)    -- texture dont le masque est retire
local progress = setmetatable({}, weak)  -- barre de reputation de guilde
local radios = setmetatable({}, weak)    -- bouton radio -> { edges, mark } ou { tinted }

-- decors de la fenetre, par atlas
local ATLAS = {
    -- menus a texte (fond common-dropdown-textholder) : Communs.lua
    ["communities-widebackground"] = "fade",
    ["guildfinder-card"] = "card",
    ["communitiesfinder-card"] = "card",
    ["communitiesfinder_card_highlight"] = "fade",
    ["checkbox-minimal"] = "checkbox",
    ["checkmark-minimal"] = "fade",
    ["checkmark-minimal-disabled"] = "fade",
    ["common-search-magnifyingglass"] = "gold",
    -- croix des sous-fenetres (la croix de la fenetre est celle de Skins.lua)
    ["RedButton-Exit"] = "close",
    ["RedButton-exit-pressed"] = "fade",
    ["RedButton-Exit-Disabled"] = "fade",
    -- reduire / agrandir
    ["RedButton-Condense"] = "minimize",
    ["RedButton-Condense-Pressed"] = "fade",
    ["RedButton-Condense-disabled"] = "fade",
    ["RedButton-Expand"] = "maximize",
    ["RedButton-Expand-Pressed"] = "fade",
    ["RedButton-Expand-Disabled"] = "fade",
    ["RedButton-Highlight"] = "fade",
}
-- reconnus par le debut de l atlas
local PREFIX = {
    -- fleche des menus (common-dropdown-a-button) : Communs.lua
    { "^common%-dropdown%-b%-button", "dropdown" },  -- bouton Filtre
    { "^common%-search%-border", "fade" },
    -- bordure et intersections du gestionnaire d invitations (macropopup-*,
    -- _macropopup-*, !macropopup-*)
    { "^[_!]?macropopup%-", "fade" },
}
-- actions a refaire a chaque passage (Blizzard repose l atlas)
local AGAIN = { gold = true }

local DIALOG_KEYS = { "BG", "Border", "Selector", "BorderBox" }
local STRETCH = { "TopLeft", "TopRight", "BottomLeft", "BottomRight", "TopMiddle", "MiddleLeft",
                  "MiddleRight", "BottomMiddle", "MiddleMiddle" }
local INPUT9 = { "TopLeftTex", "TopRightTex", "TopTex", "BottomLeftTex", "BottomRightTex", "BottomTex",
                 "LeftTex", "RightTex", "MiddleTex" }

local function db()
    local d = ns.skinsDB
    if type(d) ~= "table" or not d.enabled then return nil end
    if d.groups and d.groups.social == false then return nil end
    return d
end

-- pcall qui garde la premiere erreur de la session (avec le nom de
-- l etape) dans CorpUIDB.skins.errors.Communities (remis a zero par
-- Skins.lua a chaque connexion)
local function try(tag, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        local d = ns.skinsDB
        if type(d) == "table" then
            d.errors = d.errors or {}
            if not d.errors.Communities then
                local okS, s = pcall(function() return tag .. ": " .. tostring(err) end)
                d.errors.Communities = (okS and type(s) == "string" and not issecret(s)) and s or tag
            end
        end
    end
    return ok
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

-- champ de n importe quel type (lecture seule), nil s il est secret
local function value(f, key)
    if type(f) ~= "table" then return nil end
    local ok, v = pcall(function() return f[key] end)
    if ok and v ~= nil and not issecret(v) then return v end
end

local function layoutOf(f)
    if type(f) ~= "table" then return nil end
    local ok, v = pcall(function() return f.layoutType end)
    if ok and type(v) == "string" and not issecret(v) then return v end
end

local function fade(obj)
    if type(obj) == "table" and obj.SetAlpha and not mine[obj] then pcall(obj.SetAlpha, obj, 0) end
end

local function num(v)
    if v == nil or issecret(v) or type(v) ~= "number" then return nil end
    return v
end

-- booleen lu d un getter : faux s il echoue ou s il est secret
local function flag(f, method)
    if type(f) ~= "table" or not f[method] then return nil end
    local ok, v = pcall(f[method], f)
    if not ok or issecret(v) then return nil end
    return v
end

local function visible(f) return flag(f, "IsVisible") == true end
local function shown(f) return flag(f, "IsShown") == true end
local function isOver(f) return flag(f, "IsMouseOver") == true end
local function enabled(f)
    if type(f) ~= "table" or not f.IsEnabled then return true end
    return flag(f, "IsEnabled") ~= false
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

local function parentOf(f)
    if type(f) ~= "table" or not f.GetParent then return nil end
    local ok, p = pcall(f.GetParent, f)
    if ok and type(p) == "table" then return p end
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

local function showAll(list, on)
    for _, x in ipairs(list) do x:SetShown(on) end
end

local function grad(t, c, a1, a2, orient)
    ns.UI.Gradient(t, orient or "HORIZONTAL", c[1], c[2], c[3], a1, c[1], c[2], c[3], a2)
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
    grad(band, C.violet, 0.32, 0.03)
    local line = tex(host, "BACKGROUND", -6)
    line:SetPoint("TOPLEFT", band, "BOTTOMLEFT")
    line:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT")
    line:SetHeight(1)
    grad(line, C.gold, 0.8, 0)
end

-- police des titres + or ; on retient la police posee pour la reposer si
-- Blizzard change d objet de police
local function goldFont(fs, size)
    if objType(fs) ~= "FontString" then return nil end
    local C = ns.COLORS
    if size then pcall(ns.UI.HeadFont, fs, size) end
    pcall(fs.SetTextColor, fs, C.gold[1], C.gold[2], C.gold[3])
    local ok, file = pcall(fs.GetFont, fs)
    return { fs = fs, size = size, file = (ok and type(file) == "string" and not issecret(file)) and file or nil }
end

local function keepGold(h)
    if not h or not h.fs then return end
    if h.size then
        local ok, file = pcall(h.fs.GetFont, h.fs)
        if ok and type(file) == "string" and not issecret(file) and h.file and file ~= h.file then
            pcall(ns.UI.HeadFont, h.fs, h.size)
        end
    end
    local C = ns.COLORS
    pcall(h.fs.SetTextColor, h.fs, C.gold[1], C.gold[2], C.gold[3])
end

local function titleGold(fs, size)
    if objType(fs) ~= "FontString" or labels[fs] then return end
    local h = goldFont(fs, size)
    if h then labels[fs] = h end
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
    grad(p.hl, C.violet, 0.05, 0.28, "VERTICAL")
    plates[b] = p
    claimed[b] = true
    return p
end

-- bouton a signe (croix des sous-fenetres, reduire / agrandir)
local function glyphButton(b, glyph, size, inset, color)
    if objType(b) == nil or (plates[b] and plates[b].glyph) then return end
    fadeStates(b, { "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" })
    local p = plate(b, inset or 2)
    p.glyph = text(b, size or 12)
    p.glyph:SetPoint("CENTER", 0, 0)
    p.glyph:SetText(glyph)
    p.color = color
    p.restyle = true
    local c = color or ns.COLORS.gold
    p.glyph:SetTextColor(c[1], c[2], c[3])
end

-- bouton rouge (Left/Middle/Right) que Skins.lua n atteint pas
local function panelButton(b)
    if plates[b] then return end
    fade(field(b, "Left"))
    fade(field(b, "Middle") or field(b, "Center"))
    fade(field(b, "Right"))
    fadeStates(b, { "GetHighlightTexture" })
    plate(b, 1)
end

-- bouton a neuf morceaux (UIMenuButtonStretchTemplate)
local function stretchButton(b)
    if plates[b] then return end
    for _, k in ipairs(STRETCH) do fade(field(b, k)) end
    fadeStates(b, { "GetHighlightTexture", "GetPushedTexture" })
    plate(b, 1)
end

-- case a cocher : carre sombre, lisere, coche d or (textures a nous)
local function skinCheck(cb)
    if checks[cb] then return end
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

-- bouton radio (choix exclusif : notifications d un canal masquees /
-- affichees) : pastille ronde a nous (disque de lisere, disque sombre,
-- point d or), jamais la case carree
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local function isRadio(cb)
    -- UIRadioButtonTemplate des notifications : cle "filter" (KeyValue) et
    -- parent a nom de canal + separateur
    if value(cb, "filter") ~= nil then return true end
    local p = parentOf(cb)
    if field(p, "StreamName") and field(p, "Separator") then return true end
    -- UIRadialButtonTemplate (atlas common-dropdown-tickradial)
    local okN, n = pcall(cb.GetNormalTexture, cb)
    local a = okN and atlasOf(n) or nil
    return a ~= nil and a:find("tickradial") ~= nil
end

local function disc(cb, layer, sub, size)
    local t = tex(cb, layer, sub)
    t:SetSize(size, size)
    t:SetPoint("CENTER", cb, "CENTER", 0, 0)
    local m = cb:CreateMaskTexture()
    mine[m] = true
    m:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetAllPoints(t)
    t:AddMaskTexture(m)
    return t
end

local function skinRadio(cb)
    if radios[cb] or checks[cb] then return end
    local C = ns.COLORS
    -- les disques d abord (sans couleur ils ne dessinent rien) : si le
    -- masque manque, le rond de Blizzard reste, point teinte en or
    local ok, edge, fill, mark = false, nil, nil, nil
    if cb.CreateMaskTexture then
        ok, edge, fill, mark = pcall(function()
            return disc(cb, "BACKGROUND", -8, 14), disc(cb, "BACKGROUND", -7, 12), disc(cb, "OVERLAY", 7, 6)
        end)
    end
    if not ok then
        local okC, c = pcall(cb.GetCheckedTexture, cb)
        if okC and objType(c) == "Texture" then tints[c] = true end
        radios[cb] = { tinted = true }
        return
    end
    fadeStates(cb)
    edge:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
    fill:SetColorTexture(0, 0, 0, 0.85)
    mark:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    mark:Hide()
    radios[cb] = { edges = { edge }, mark = mark }
    -- etats suivis comme une case (coche -> point, survol -> lisere or)
    checks[cb] = radios[cb]
    claimed[cb] = true
end

-- champ de saisie (recherche, nom, saisie de la discussion) : les trois
-- morceaux de Blizzard a alpha 0, notre fond et notre lisere autour
local function skinEdit(e)
    if edits[e] then return end
    local l, r = field(e, "Left"), field(e, "Right")
    local m, chat = field(e, "Middle"), false
    if not m then
        m = field(e, "Mid")
        chat = m ~= nil
    end
    if not (l and m and r) then return end
    fade(l) fade(m) fade(r)
    local C = ns.COLORS
    local fill = tex(e, "BACKGROUND", -8)
    if chat then
        -- saisie de la discussion : cadre de 32 px, barre visible plus fine
        fill:SetPoint("TOPLEFT", e, "TOPLEFT", -6, -4)
        fill:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT", 6, 4)
    else
        fill:SetPoint("TOPLEFT", e, "TOPLEFT", -5, 0)
        fill:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT", 0, 0)
    end
    fill:SetColorTexture(0, 0, 0, 0.55)
    local edges = ring(e, fill, "BACKGROUND", -7, 0)
    paintC(edges, C.border)
    edits[e] = { fill = fill, edges = edges }
    claimed[e] = true
    local glass = field(e, "searchIcon") or field(e, "SearchIcon")
    if glass then tints[glass] = true end
end

-- multi-ligne (InputScrollFrameTemplate) : neuf morceaux a alpha 0
local function inputScroll(f)
    if inner[f] then return end
    inner[f] = true
    for _, k in ipairs(INPUT9) do fade(field(f, k)) end
    local C = ns.COLORS
    local fill = tex(f, "BACKGROUND", -8)
    fill:SetPoint("TOPLEFT", f, "TOPLEFT", -5, 5)
    fill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 5, -5)
    fill:SetColorTexture(0, 0, 0, 0.55)
    paintC(ring(f, fill, "BACKGROUND", -7, 0), C.border)
end

-- cadre interieur a fond d infobulle (notes d un membre, journaux)
local function innerBox(f)
    if inner[f] then return end
    inner[f] = true
    fadeOwn(f)
    fadeOwn(field(f, "NineSlice"))
    local C = ns.COLORS
    local fill = tex(f, "BACKGROUND", -8)
    fill:SetAllPoints(f)
    fill:SetColorTexture(0, 0, 0, 0.5)
    paintC(ring(f, fill, "BACKGROUND", -7, 0), C.border)
end

---------------------------------------------------------------------------
-- Barres
---------------------------------------------------------------------------

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
    -- fond marbre de certaines barres (membres, nouvelles)
    fade(field(sb, "Background"))
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

-- barre de reputation de guilde (CommunitiesGuildProgressBarTemplate) : le
-- remplissage de Blizzard passe a alpha 0, le notre le suit (taille par
-- ancrage, couleur relue)
local function progressBar(f)
    if progress[f] then return end
    for _, k in ipairs({ "Left", "Right", "Middle", "BG", "Shadow" }) do fade(field(f, k)) end
    local C = ns.COLORS
    local s = {}
    s.bg = tex(f, "BACKGROUND", -8)
    s.bg:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -2)
    s.bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 2)
    s.bg:SetColorTexture(0, 0, 0, 0.6)
    s.edges = ring(f, s.bg, "BACKGROUND", -7, 0)
    paintC(s.edges, C.border)
    local pr = field(f, "Progress")
    if objType(pr) == "Texture" then
        fade(pr)
        s.ref = pr
        s.fill = tex(f, "ARTWORK", -1)
        s.fill:SetPoint("TOPLEFT", pr, "TOPLEFT", 0, 0)
        s.fill:SetPoint("BOTTOMRIGHT", pr, "BOTTOMRIGHT", 0, 0)
        if ns.BAR_TEXTURE then s.fill:SetTexture(ns.BAR_TEXTURE) else s.fill:SetColorTexture(1, 1, 1, 1) end
        s.fill:SetVertexColor(C.violet[1], C.violet[2], C.violet[3], 1)
    end
    progress[f] = s
end

local function updateProgress(s)
    if not s.ref then return end
    s.fill:SetShown(shown(s.ref))
    local ok, r, g, b = pcall(s.ref.GetVertexColor, s.ref)
    r, g, b = ok and num(r), ok and num(g), ok and num(b)
    if r and g and b then s.fill:SetVertexColor(r, g, b, 1) end
end

---------------------------------------------------------------------------
-- Onglets lateraux (RightSideTabTemplate : discussion, membres, avantages,
-- infos, recherche de guilde)
---------------------------------------------------------------------------

local function railFor(parent)
    if rails[parent] then return rails[parent] end
    if type(parent) ~= "table" or not parent.CreateTexture then return nil end
    local C = ns.COLORS
    local r = {}
    r.fill = tex(parent, "BACKGROUND", -6)
    r.fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.92)
    r.edges = ring(parent, r.fill, "BACKGROUND", -5, 0)
    paintC(r.edges, C.border)
    r.fill:Hide()
    showAll(r.edges, false)
    rails[parent] = r
    return r
end

local function sideTab(t)
    if tabs[t] then return end
    local icon = field(t, "Icon")
    if objType(icon) ~= "Texture" then return end
    local overlay = field(t, "IconOverlay")
    -- cadre du grimoire, survol et coche de Blizzard (l icone et son voile
    -- "indisponible" restent)
    for _, r in ipairs(regionsOf(t)) do
        if r ~= icon and r ~= overlay and not mine[r] and objType(r) == "Texture" then fade(r) end
    end
    fadeStates(t, { "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetCheckedTexture",
                    "GetDisabledCheckedTexture" })
    pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
    local C = ns.COLORS
    local s = { icon = icon }
    s.fill = tex(t, "BACKGROUND", -6)
    s.fill:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
    s.fill:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
    s.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 1)
    s.edges = ring(t, s.fill, "OVERLAY", 6, 0)
    paintC(s.edges, C.border)
    -- barre d or du cote de la fenetre pour l onglet actif
    s.bar = tex(t, "OVERLAY", 7)
    s.bar:SetPoint("TOPLEFT", s.fill, "TOPLEFT", 0, 0)
    s.bar:SetPoint("BOTTOMLEFT", s.fill, "BOTTOMLEFT", 0, 0)
    s.bar:SetWidth(2)
    s.bar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    s.bar:Hide()
    tabs[t] = s
    claimed[t] = true
    try("rail", railFor, parentOf(t))
end

local function tabState(t, s)
    local C = ns.COLORS
    local active = flag(t, "GetChecked") == true
    local over = isOver(t)
    s.bar:SetShown(active)
    if active then
        paintC(s.edges, C.gold)
    elseif over then
        paintC(s.edges, C.violet)
    else
        paintC(s.edges, C.border)
    end
    local v = (active or over) and 1 or 0.65
    pcall(s.icon.SetVertexColor, s.icon, v, v, v, 1)
end

-- un rail par groupe d onglets (meme parent), sous les onglets visibles
local function placeRails()
    local spans = {}
    for t, s in pairs(tabs) do
        if visible(t) then
            local p = parentOf(t)
            local okT, top = pcall(t.GetTop, t)
            top = okT and num(top) or nil
            if p and top then
                local sp = spans[p]
                if not sp then
                    sp = {}
                    spans[p] = sp
                end
                if not sp.first or top > sp.first.top then sp.first = { s = s, top = top } end
                if not sp.last or top < sp.last.top then sp.last = { s = s, top = top } end
            end
        end
    end
    for p, r in pairs(rails) do
        local sp = spans[p]
        local on = sp ~= nil
        r.fill:SetShown(on)
        showAll(r.edges, on)
        if on then
            r.fill:ClearAllPoints()
            r.fill:SetPoint("TOPLEFT", sp.first.s.fill, "TOPLEFT", -4, 4)
            r.fill:SetPoint("BOTTOMRIGHT", sp.last.s.fill, "BOTTOMRIGHT", 4, -4)
        end
    end
end

---------------------------------------------------------------------------
-- Liste des communautes (CommunitiesListEntryTemplate, recyclees)
---------------------------------------------------------------------------

local function listPanel(cl)
    if panels[cl] then return end
    panels[cl] = true
    -- fond bleu, filigranes, coins et barres dorees
    fadeOwn(cl)
    fadeOwn(field(cl, "FilligreeOverlay"))
    local inset = field(cl, "InsetFrame")
    if inset then
        fadeOwn(inset)
        fadeOwn(field(inset, "NineSlice"))
    end
    -- le panneau est pose sur la ScrollBox (au-dessus de la fenetre, sous
    -- les entrees) ; le cadre de bord de Blizzard est au niveau 200
    local host = field(cl, "ScrollBox")
    if not (host and host.CreateTexture) then host = cl end
    backdrop(host, cl, 0.6)
end

local function listEntry(e)
    if entries[e] then return end
    local C = ns.COLORS
    local s = {}
    s.sel = field(e, "Selection")
    s.ringTex = field(e, "IconRing")
    s.icon = field(e, "Icon")
    s.mask = field(e, "CircleMask")
    fade(field(e, "Background"))
    fade(s.sel)
    fade(s.ringTex)
    fadeStates(e, { "GetHighlightTexture" })
    -- avatar carre : masque rond retire (une fois pour toutes)
    if objType(s.icon) == "Texture" and s.mask and not masked[s.icon] and s.icon.RemoveMaskTexture then
        masked[s.icon] = true
        pcall(s.icon.RemoveMaskTexture, s.icon, s.mask)
    end
    s.fill = tex(e, "BACKGROUND", -8)
    -- 1 px en haut et en bas (3 avant) : les entrees se suivent sans trou
    s.fill:SetPoint("TOPLEFT", e, "TOPLEFT", 3, -1)
    s.fill:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT", -3, 1)
    s.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.9)
    s.edges = ring(e, s.fill, "BACKGROUND", -7, 0)
    paintC(s.edges, C.border)
    s.on = tex(e, "BACKGROUND", -6)
    s.on:SetAllPoints(s.fill)
    grad(s.on, C.violet, 0.45, 0.04)
    s.on:Hide()
    s.bar = tex(e, "BACKGROUND", -5)
    s.bar:SetPoint("TOPLEFT", s.fill, "TOPLEFT", 0, 0)
    s.bar:SetPoint("BOTTOMLEFT", s.fill, "BOTTOMLEFT", 0, 0)
    s.bar:SetWidth(2)
    s.bar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    s.bar:Hide()
    s.hl = tex(e, "HIGHLIGHT")
    s.hl:SetAllPoints(s.fill)
    grad(s.hl, C.violet, 0.22, 0.02)
    if objType(s.icon) == "Texture" then
        s.avatar = ring(e, s.icon, "OVERLAY", 5, 0)
        showAll(s.avatar, false)
    end
    entries[e] = s
    claimed[e] = true
end

local BNET = { 0.51, 0.77, 1 }

local function entryState(e, s)
    local C = ns.COLORS
    local on = shown(s.sel)
    s.on:SetShown(on)
    s.bar:SetShown(on)
    local en = enabled(e)
    s.fill:SetAlpha(en and 1 or 0.5)
    paintC(s.edges, (isOver(e) and en) and C.gold or C.border)
    if s.avatar then
        -- lisere a la place de l anneau : bleu pour Battle.net (comme l anneau)
        local a = shown(s.icon) and (shown(s.ringTex) or shown(s.mask))
        showAll(s.avatar, a)
        if a then
            -- l atlas de l anneau n est fiable que s il est affiche : une
            -- entree recyclee (recherche de guilde) garde l ancien atlas
            local atlas = shown(s.ringTex) and atlasOf(s.ringTex) or ""
            paintC(s.avatar, atlas:find("blue") and BNET or C.border)
        end
    end
end

---------------------------------------------------------------------------
-- Liste des membres / candidats
---------------------------------------------------------------------------

local function listBackdrop(ml)
    if panels[ml] then return end
    panels[ml] = true
    local inset = field(ml, "InsetFrame")
    if inset then
        fadeOwn(inset)
        fadeOwn(field(inset, "NineSlice"))
    end
    -- sur la liste elle-meme : son cadre de bord est au niveau 100, au-dessus
    -- des lignes
    backdrop(ml, inset or ml, 0.6)
end

-- en-tetes de colonnes (ColumnDisplayTemplate) : fond de roche a alpha 0,
-- filet d or sous les en-tetes
local function columnDisplay(f)
    if panels[f] then return end
    panels[f] = true
    fadeOwn(f)
    local C = ns.COLORS
    local line = tex(f, "ARTWORK", 1)
    line:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 2, 0)
    line:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 0)
    line:SetHeight(1)
    grad(line, C.gold, 0.85, 0.1)
end

local function isColumnCell(b)
    return field(parentOf(b), "columnHeaders") ~= nil
end

-- en-tete de colonne : a portee de Skins.lua (profondeur 3), c est lui qui
-- pose la plaque (sinon deux plaques si son releve passe avant le notre) ;
-- plus loin, la plaque est a nous. Le titre passe en or dans tous les cas.
local function columnCell(b, ownPlate)
    if cells[b] then return end
    fade(field(b, "Left"))
    fade(field(b, "Middle"))
    fade(field(b, "Right"))
    fadeStates(b, { "GetHighlightTexture" })
    if ownPlate then plate(b, 1) end
    local ok, fs = pcall(b.GetFontString, b)
    cells[b] = { fs = (ok and objType(fs) == "FontString") and fs or nil }
end

-- en-tete de metier dans la liste des membres
local function profHeader(ph)
    if profHeads[ph] then return end
    fade(field(ph, "Left"))
    fade(field(ph, "Middle"))
    fade(field(ph, "Right"))
    local C = ns.COLORS
    local h = {}
    h.fill = tex(ph, "BACKGROUND", -8)
    h.fill:SetPoint("TOPLEFT", ph, "TOPLEFT", 1, -1)
    h.fill:SetPoint("BOTTOMRIGHT", ph, "BOTTOMRIGHT", -1, 1)
    grad(h.fill, C.violet, 0.30, 0.03)
    h.line = tex(ph, "BACKGROUND", -7)
    h.line:SetPoint("BOTTOMLEFT", h.fill, "BOTTOMLEFT")
    h.line:SetPoint("BOTTOMRIGHT", h.fill, "BOTTOMRIGHT")
    h.line:SetHeight(1)
    grad(h.line, C.gold, 0.8, 0)
    h.hover = tex(ph, "HIGHLIGHT")
    h.hover:SetAllPoints(h.fill)
    grad(h.hover, C.violet, 0.22, 0.02)
    titleGold(field(ph, "Name"), 11)
    for _, k in ipairs({ "ExpandedIcon", "CollapsedIcon" }) do
        local t = field(ph, k)
        if t then tints[t] = true end
    end
    local icon = field(ph, "Icon")
    if objType(icon) == "Texture" then paintC(ring(ph, icon, "OVERLAY", 6, 1), C.border) end
    profHeads[ph] = h
    claimed[ph] = true
end

-- ligne de membre ou de candidat : bande et survol de Blizzard a alpha 0,
-- fond leger, separateur fin, survol en degrade (calque HIGHLIGHT : le
-- moteur l affiche seul) ; textes, classe et etat gardes
local function tableRow(r)
    if rows[r] then return end
    local C = ns.COLORS
    fadeStates(r, { "GetNormalTexture", "GetHighlightTexture" })
    local s = {}
    s.fill = tex(r, "BACKGROUND", -8)
    s.fill:SetAllPoints(r)
    s.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.35)
    s.line = tex(r, "BACKGROUND", -7)
    s.line:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
    s.line:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
    s.line:SetHeight(1)
    s.line:SetColorTexture(C.border[1], C.border[2], C.border[3], 0.45)
    s.hl = tex(r, "HIGHLIGHT")
    s.hl:SetAllPoints(r)
    grad(s.hl, C.violet, 0.30, 0.03)
    s.hlBar = tex(r, "HIGHLIGHT")
    s.hlBar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
    s.hlBar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
    s.hlBar:SetWidth(2)
    s.hlBar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    rows[r] = s
    claimed[r] = true
    local ph = field(r, "ProfessionHeader")
    if ph then profHeader(ph) end
end

-- ligne d avantage / de recompense de guilde (icone + nom)
local function rewardRow(b)
    if rows[b] then return end
    local icon = field(b, "Icon")
    local keep = { [icon or 0] = true, [field(b, "Lock") or 0] = true, [field(b, "DisabledBG") or 0] = true }
    for _, r in ipairs(regionsOf(b)) do
        if not keep[r] and not mine[r] and objType(r) == "Texture" then fade(r) end
    end
    fadeOwn(field(b, "NormalBorder"))
    fadeOwn(field(b, "DisabledBorder"))
    tableRow(b)
    if objType(icon) == "Texture" then
        cropIcon(icon)
        paintC(ring(b, icon, "OVERLAY", 6, 1), ns.COLORS.border)
    end
end

-- ligne de nouvelles : survol en degrade, bandeau sur les lignes d en-tete
local function bandOn(host, ref)
    if bands[ref] or objType(ref) ~= "Texture" then return end
    local C = ns.COLORS
    -- le bandeau ne deborde pas du panneau (en-tetes de 280 px sur 270)
    local dx = 0
    local okR, rr = pcall(ref.GetRight, ref)
    local okH, hr = pcall(host.GetRight, host)
    rr, hr = okR and num(rr), okH and num(hr)
    if rr and hr and rr > hr - 1 then dx = hr - 1 - rr end
    local b = { ref = ref }
    b.fill = tex(host, "BACKGROUND", -6)
    b.fill:SetPoint("TOPLEFT", ref, "TOPLEFT", 0, 0)
    b.fill:SetPoint("BOTTOMRIGHT", ref, "BOTTOMRIGHT", dx, 0)
    grad(b.fill, C.violet, 0.30, 0.03)
    b.line = tex(host, "BACKGROUND", -6)
    b.line:SetPoint("TOPLEFT", b.fill, "BOTTOMLEFT")
    b.line:SetPoint("TOPRIGHT", b.fill, "BOTTOMRIGHT")
    b.line:SetHeight(1)
    grad(b.line, C.gold, 0.8, 0)
    bands[ref] = b
end

local function newsRow(b)
    if rows[b] then return end
    local C = ns.COLORS
    fadeStates(b, { "GetHighlightTexture" })
    local hdr = field(b, "header")
    if hdr then
        fade(hdr)
        bandOn(b, hdr)
    end
    local s = {}
    s.hl = tex(b, "HIGHLIGHT")
    s.hl:SetAllPoints(b)
    grad(s.hl, C.violet, 0.28, 0.03)
    rows[b] = s
    claimed[b] = true
end

---------------------------------------------------------------------------
-- Panneaux : infos de guilde, nouvelles, avantages, dialogues
---------------------------------------------------------------------------

-- titres poses sur un bandeau (ancres a la texture d en-tete)
local function goldLabels(f)
    for _, r in ipairs(regionsOf(f)) do
        if objType(r) == "FontString" and not mine[r] and not labels[r] then
            local ok, _, rel = pcall(r.GetPoint, r, 1)
            if ok and type(rel) == "table" and bands[rel] then titleGold(r, 12) end
        end
    end
end

-- infos de guilde (message du jour, informations, defis)
local function infoPanel(f)
    if panels[f] then return end
    panels[f] = true
    fadeOwn(f)
    backdrop(f, f, 0.55)
    local hdrs = {}
    for _, k in ipairs({ "Header1", "Header2" }) do
        local h = field(f, k)
        if h then hdrs[#hdrs + 1] = h end
    end
    local okN, name = pcall(f.GetName, f)
    if okN and type(name) == "string" and not issecret(name) then
        local h3 = _G[name .. "Header3"]
        if objType(h3) == "Texture" then hdrs[#hdrs + 1] = h3 end
    end
    for _, h in ipairs(hdrs) do bandOn(f, h) end
    goldLabels(f)
    titleGold(field(f, "TitleText"), 13)
end

-- panneau a titre et liste (nouvelles, avantages, recompenses)
local function titledPanel(f)
    if panels[f] then return end
    panels[f] = true
    fadeOwn(f)
    backdrop(f, f, 0.55)
    local hdr = field(f, "Header")
    if objType(hdr) == "Texture" then
        bandOn(f, hdr)
        goldLabels(f)
    end
    titleGold(field(f, "TitleText"), 13)
end

-- cadre commun a un dialogue : fond, ombre, bandeau, titre or
local function windowDress(f)
    local C = ns.COLORS
    local bd = backdrop(f, f, 0.96)
    for i = 1, 4 do
        local s = tex(f, "BACKGROUND", -8)
        s:SetPoint("TOPLEFT", bd.fill, "TOPLEFT", -i, i)
        s:SetPoint("BOTTOMRIGHT", bd.fill, "BOTTOMRIGHT", i, -i)
        s:SetColorTexture(0, 0, 0, 0.14)
    end
    headBand(f, f, 1, 22)
    local title = field(f, "TitleLabel") or field(f, "DialogLabel") or field(f, "Title")
    if objType(title) ~= "FontString" then
        local okN, name = pcall(f.GetName, f)
        if okN and type(name) == "string" and not issecret(name) then title = _G[name .. "Title"] end
    end
    if objType(title) == "FontString" then titleGold(title, 12) end
    local close = field(f, "CloseButton")
    if objType(close) == "Button" then
        try("croix", glyphButton, close, "×", 15, 4, C.text)
        if plates[close] then plates[close].close = true end
    end
end

-- bordure de dialogue : DialogBorder*Template ("Dialog") ou
-- SelectionFrameTemplate (cadre a boutons OK / Annuler : seules ses
-- textures a lui passent a alpha 0, les boutons restent)
local function dialogLayout(c)
    local lt = layoutOf(c)
    return lt ~= nil and (lt:find("Dialog") ~= nil or lt == "SelectionFrameTemplate")
end

local function isDialog(f)
    for _, k in ipairs(DIALOG_KEYS) do
        local c = field(f, k)
        if c and objType(c) ~= "Texture" and dialogLayout(c) then return true end
    end
    return false
end

-- dialogue (fiche d un membre, canal, notifications, recrutement...) :
-- seuls ses morceaux de bordure perdent leur dessin (l avatar des
-- parametres de communaute, par exemple, reste)
local function dialogPanel(f)
    if panels[f] or type(f) ~= "table" or not f.CreateTexture then return end
    panels[f] = true
    for _, k in ipairs(DIALOG_KEYS) do
        local c = field(f, k)
        local t = objType(c)
        if t == "Texture" then
            fade(c)
        elseif t and dialogLayout(c) then
            fadeOwn(c)
            fadeOwn(field(c, "NineSlice"))
        end
    end
    windowDress(f)
end

-- fenetre translucide (message du jour, journal, filtres des nouvelles) :
-- ses textures a elle sont toutes decoratives
local function popupPanel(f)
    if panels[f] or type(f) ~= "table" or not f.CreateTexture then return end
    panels[f] = true
    fadeOwn(f)
    for _, k in ipairs({ "NineSlice", "Bg", "BG", "Border" }) do
        local c = field(f, k)
        if objType(c) == "Texture" then fade(c) elseif c then fadeOwn(c) end
    end
    for _, c in ipairs(childrenOf(f)) do
        local lt = layoutOf(c)
        if lt and lt ~= "TooltipDefaultLayout" and objType(c) == "Frame" then
            fadeOwn(c)
            fadeOwn(field(c, "NineSlice"))
        end
    end
    windowDress(f)
end

-- cadre de la discussion
local function chatPanel(chat)
    local inset = field(chat, "InsetFrame")
    if not inset or panels[inset] or not inset.CreateTexture then return end
    panels[inset] = true
    fadeOwn(inset)
    fadeOwn(field(inset, "NineSlice"))
    backdrop(inset, inset, 0.55)
end

-- carte de la recherche de guilde / communaute
local function card(f, r)
    fade(r)
    if objType(f) == "Button" or objType(f) == "Frame" then plate(f, 2) end
end

-- gestionnaire d invitations (CommunitiesTicketManagerDialog) : pas de
-- bordure "Dialog" ; sa bordure macropopup-* passe par PREFIX, son fond
-- noir (au-dessus de notre fond et de notre bandeau) passe a alpha 0
local function isTicketDialog(f)
    -- cle propre a ce dialogue dans Blizzard_Communities
    return field(f, "InviteManager") ~= nil
end

local function ticketDialog(f)
    fade(field(f, "Background"))
end

-- liste des invitations (CommunitiesTicketManagerScrollFrameTemplate) :
-- marbre de la ScrollBox a alpha 0, panneau sombre sous en-tetes et lignes
-- (les intersections macropopup de l ArtOverlay passent par PREFIX)
local function ticketList(im)
    if panels[im] then return end
    panels[im] = true
    fade(field(field(im, "ScrollBox"), "Background"))
    local C = ns.COLORS
    local fill = tex(im, "BACKGROUND", -8)
    fill:SetPoint("TOPLEFT", im, "TOPLEFT", 12, -6)
    fill:SetPoint("BOTTOMRIGHT", im, "BOTTOMRIGHT", -12, 0)
    fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.6)
    paintC(ring(im, fill, "BACKGROUND", -7, 0), C.border)
end

-- ligne d invitation (CommunitiesTicketEntryTemplate) : bande de Blizzard a
-- alpha 0, ligne de tableau ; le bouton "copier" (cache hors survol) et
-- la croix de revocation sont aplatis tout de suite
local function ticketRow(b)
    if rows[b] then return end
    fade(field(b, "Stripe"))
    tableRow(b)
    for _, k in ipairs({ "CopyLinkButton", "RevokeButton" }) do
        local s = field(b, k)
        if s and field(s, "TopLeft") and field(s, "MiddleMiddle") then stretchButton(s) end
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

local mainClose  -- croix de la fenetre : c est celle de Skins.lua

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
                elseif act == "dropdown" then
                    fade(r)
                    plate(f, 1)
                elseif act == "card" then
                    card(f, r)
                elseif act == "checkbox" then
                    fade(r)
                    if objType(f) == "CheckButton" then skinCheck(f) end
                elseif act == "close" then
                    if f ~= mainClose and objType(f) == "Button" then
                        try("croix", glyphButton, f, "×", 15, 4, C.text)
                        if plates[f] then plates[f].close = true end
                    end
                elseif act == "minimize" then
                    if objType(f) == "Button" then try("reduire", glyphButton, f, "-", 14, 3) end
                elseif act == "maximize" then
                    if objType(f) == "Button" then try("agrandir", glyphButton, f, "+", 13, 3) end
                elseif act == "gold" then
                    tints[r] = true
                    pcall(r.SetDesaturated, r, true)
                    pcall(r.SetVertexColor, r, C.gold[1], C.gold[2], C.gold[3], 1)
                end
            end
        end
    end
end

local function isPanelButton(b)
    return objType(field(b, "Left")) == "Texture" and objType(field(b, "Right")) == "Texture"
        and (objType(field(b, "Middle")) == "Texture" or objType(field(b, "Center")) == "Texture")
end

-- profondeur de recherche de Skins.lua dans la fenetre (Fenetres.lua)
local skinsDepth
local function getSkinsDepth()
    if skinsDepth then return skinsDepth end
    skinsDepth = 3
    for _, g in ipairs(ns.SKIN_GROUPS or {}) do
        for _, spec in ipairs(g.windows or {}) do
            if spec[1] == "CommunitiesFrame" then skinsDepth = spec.depth or 6 end
        end
    end
    return skinsDepth
end

-- Skins.lua ne descend pas dans un cadre reclame : ce qui est dessous est
-- pour nous
local function claimedAncestor(f, root)
    local p = parentOf(f)
    for _ = 1, 12 do
        if not p or p == root then return false end
        if claimed[p] then return true end
        p = parentOf(p)
    end
    return false
end

-- elements reconnus par leurs champs
local function special(f, depth, root)
    local t = objType(f)
    if not t then return end
    if t == "EditBox" then
        skinEdit(f)
        return
    end
    if t == "CheckButton" then
        if field(f, "Icon") and field(f, "IconOverlay") then
            sideTab(f)
        elseif not (checks[f] or radios[f]) then
            local okN, n = pcall(f.GetNormalTexture, f)
            local okC, c = pcall(f.GetCheckedTexture, f)
            if okN and n and okC and c then
                if isRadio(f) then skinRadio(f) else skinCheck(f) end
            end
        end
        return
    end
    if t == "Button" then
        if field(f, "Selection") and field(f, "IconRing") and field(f, "GuildTabardBackground") then
            listEntry(f)
        elseif field(f, "Level") and field(f, "Class") and field(f, "Note") then
            tableRow(f)
        elseif field(f, "Creator") and field(f, "Link") and field(f, "Expires") and field(f, "Uses") then
            ticketRow(f)
        elseif field(f, "header") and field(f, "icon") and field(f, "dash") then
            newsRow(f)
        elseif field(f, "TopLeft") and field(f, "TopMiddle") and field(f, "MiddleMiddle") then
            stretchButton(f)
        elseif isPanelButton(f) then
            -- hors de portee de Skins.lua : plus profond, autre fenetre, ou
            -- sous un cadre que nous reclamons
            local ours = depth > getSkinsDepth() or root ~= _G.CommunitiesFrame or claimedAncestor(f, root)
            if isColumnCell(f) then
                columnCell(f, ours)
            elseif ours then
                panelButton(f)
            end
        elseif field(f, "Icon") and field(f, "Name") and (field(f, "Lock") or field(f, "NormalBorder")) then
            rewardRow(f)
        end
        return
    end
    -- cadres
    local lt = layoutOf(f)
    if lt == "InsetFrameTemplate" then
        fadeOwn(f)
        fadeOwn(field(f, "NineSlice"))
    elseif lt == "TooltipDefaultLayout" then
        innerBox(f)
    end
    if field(f, "columnHeaders") then columnDisplay(f) end
    -- coins interieurs des volets infos / avantages
    if field(f, "InsetBorderTopLeft") and field(f, "InsetBorderLeft2") then fadeOwn(f) end
    if field(f, "Header1") and field(f, "MOTDScrollFrame") then
        infoPanel(f)
    elseif objType(field(f, "TitleText")) == "FontString" and field(f, "ScrollBox") and field(f, "ScrollBar") then
        titledPanel(f)
    end
    -- ArtOverlay n existe que dans la liste des invitations
    if field(f, "ArtOverlay") and field(f, "ScrollBox") then ticketList(f) end
    if field(f, "TopLeftTex") and field(f, "MiddleTex") then inputScroll(f) end
    if field(f, "Progress") and field(f, "Shadow") and field(f, "BG") then progressBar(f) end
    if not panels[f] and isDialog(f) then dialogPanel(f) end
end

local function walk(f, depth, root)
    if depth > 12 or not visible(f) then return end
    -- bulles d aide (HelpTip) : cadres partages entre toutes les fenetres
    if field(f, "OkayButton") and field(f, "Arrow") then return end
    if isScrollBar(f) then
        try("barre", skinScrollBar, f)
        return
    end
    scanRegions(f)
    try("element", special, f, depth, root)
    for _, c in ipairs(childrenOf(f)) do walk(c, depth + 1, root) end
end

local function titleText(f)
    local fs = field(field(f, "TitleContainer"), "TitleText") or field(f, "TitleText")
    if objType(fs) == "FontString" then return fs end
end

-- dialogues de la fenetre, habilles meme s ils n ont pas de bordure "Dialog"
local DIALOGS = { "GuildMemberDetailFrame", "EditStreamDialog", "NotificationSettingsDialog", "RecruitmentDialog" }

-- zones de la fenetre principale
local function fullMain(cf)
    mainClose = field(cf, "CloseButton")
    -- portrait rond et blason qui debordent en haut a gauche
    fadeOwn(field(cf, "PortraitOverlay"))
    local cl = field(cf, "CommunitiesList")
    if cl and visible(cl) then try("liste", listPanel, cl) end
    for _, k in ipairs({ "MemberList", "ApplicantList" }) do
        local ml = field(cf, k)
        if ml and visible(ml) then try("membres", listBackdrop, ml) end
    end
    local chat = field(cf, "Chat")
    if chat and visible(chat) then try("discussion", chatPanel, chat) end
    for _, k in ipairs(DIALOGS) do
        local d = field(cf, k)
        if d and visible(d) then try("dialogue", dialogPanel, d) end
    end
    walk(cf, 0, cf)
end

local function fullPopup(f, kind)
    if kind == "popup" then
        try("fenetre annexe", popupPanel, f)
    else
        try("dialogue", dialogPanel, f)
        if isTicketDialog(f) then try("invitations", ticketDialog, f) end
    end
    walk(f, 0, f)
end

-- leger (5 fois par seconde, fenetre ouverte) : couleurs d etat
local mainTitle

local function light(main)
    local C = ns.COLORS
    if main then
        local title = titleText(main)
        if title then
            if not mainTitle or mainTitle.fs ~= title then mainTitle = goldFont(title, 12) else keepGold(mainTitle) end
        end
    end
    for t, s in pairs(tabs) do
        if visible(t) then try("etat onglet", tabState, t, s) end
    end
    placeRails()
    for e, s in pairs(entries) do
        if visible(e) then try("etat entree", entryState, e, s) end
    end
    for b, p in pairs(plates) do
        if p.edges and visible(b) then
            local en = enabled(b)
            local over = isOver(b) and en
            paintC(p.edges, over and (p.close and { 1, 0.3, 0.3 } or C.gold) or C.border)
            if p.glyph then
                -- Blizzard peut reposer la texture d etat (atlas des boutons rouges)
                if p.restyle then
                    fadeStates(b, { "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" })
                end
                local c = p.color or C.gold
                if p.close and over then c = { 1, 0.3, 0.3 } end
                p.glyph:SetTextColor(c[1], c[2], c[3])
                p.glyph:SetAlpha(en and 1 or 0.35)
            end
        end
    end
    for cb, k in pairs(checks) do
        if visible(cb) then
            k.mark:SetShown(flag(cb, "GetChecked") == true)
            k.mark:SetAlpha(enabled(cb) and 1 or 0.4)
            paintC(k.edges, isOver(cb) and C.gold or C.border)
        end
    end
    for e, k in pairs(edits) do
        if visible(e) then
            if flag(e, "HasFocus") == true then paintC(k.edges, C.gold)
            elseif isOver(e) then paintC(k.edges, C.violet)
            else paintC(k.edges, C.border) end
        end
    end
    for ref, b in pairs(bands) do
        local on = shown(ref)
        b.fill:SetShown(on)
        b.line:SetShown(on)
    end
    for _, s in pairs(progress) do try("reputation", updateProgress, s) end
    for t in pairs(tints) do
        if visible(t) then
            pcall(t.SetDesaturated, t, true)
            pcall(t.SetVertexColor, t, C.gold[1], C.gold[2], C.gold[3], 1)
        end
    end
    for b, c in pairs(cells) do
        if c.fs and visible(b) then pcall(c.fs.SetTextColor, c.fs, C.gold[1], C.gold[2], C.gold[3]) end
    end
    for fs, h in pairs(labels) do
        if visible(fs) then keepGold(h) end
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

-- fenetres reprises : la fenetre (chargee a la demande avec
-- Blizzard_Communities) et ses fenetres annexes posees sur UIParent.
-- Jamais CommunitiesAddDialog / CommunitiesCreateDialog (environnement
-- securise) ni CommunitiesAvatarPickerDialog (flux de creation securise).
local ROOTS = {
    { "CommunitiesFrame", "main" },
    { "CommunitiesGuildTextEditFrame", "popup" },
    { "CommunitiesGuildLogFrame", "popup" },
    { "CommunitiesGuildNewsFiltersFrame", "popup" },
    { "CommunitiesSettingsDialog", "dialog" },
    { "CommunitiesTicketManagerDialog", "dialog" },
}
local state = {}     -- nom -> { shown, key }
local acc, walkAcc = 0, 0

-- volet affiche : un changement relance tout de suite le parcours
local function pageKey(f, kind)
    if kind ~= "main" then return "" end
    local ok, key = pcall(function()
        local s = tostring(f.displayMode) .. "|" .. tostring(f.selectedClubId)
        local ml = f.MemberList
        if type(ml) == "table" then s = s .. "|" .. tostring(ml.expandedDisplay) end
        return s
    end)
    if ok and type(key) == "string" and not issecret(key) then return key end
    return ""
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        for _, st in pairs(state) do st.shown = false end
    end
end)
pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")

ev:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.2 then return end
    walkAcc = walkAcc + acc
    acc = 0
    if not db() or InCombatLockdown() then return end
    local walked, any, main = false, false, nil
    for _, spec in ipairs(ROOTS) do
        local name, kind = spec[1], spec[2]
        local f = _G[name]
        local st = state[name]
        if not st then
            st = {}
            state[name] = st
        end
        if type(f) == "table" and f.CreateTexture and visible(f) then
            any = true
            if kind == "main" then main = f end
            local key = pageKey(f, kind)
            if not st.shown or key ~= st.key or walkAcc >= 0.6 then
                st.shown, st.key, walked = true, key, true
                if kind == "main" then
                    try(name, fullMain, f)
                else
                    try(name, fullPopup, f, kind)
                end
            end
        else
            st.shown = false
        end
    end
    if walked then walkAcc = 0 end
    if any then try("releve", light, main) end
end)
