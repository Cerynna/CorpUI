--[[--------------------------------------------------------------------------
    CorpUI - module Habillage : fenetre des maitres (de classe, de metier,
    des familiers) en profondeur : ClassTrainerFrame de Blizzard_TrainerUI.
    Ce client charge la variante Mainline de la fenetre, plus
    Blizzard_TrainerUI_Camelot.lua (categories repliables, sauf chez le
    maitre des familiers).

    Skins.lua pose deja le fond, le lisere, le bandeau, le titre et la croix
    de la fenetre, et efface son decor (dont le parchemin BG et le cadre
    d argent MoneyBg, textures posees sur la fenetre) ; ici, l interieur :
      - zones de liste (Inset, et bottomInset quand un palier de metier est
        propose au-dessus de la liste) : puits sombre a lisere ;
      - barre de rang du metier (ClassTrainerStatusBar, maitres de metier) :
        bords et fond bleu a alpha 0, fond sombre a lisere, barre de Blizzard
        desaturee et teintee de l accent (sa valeur reste a Blizzard) ;
      - bouton Filtre / Reglages (WowStyle1FilterDropdownTemplate) : plaque
        plate de 22 px, lisere d or au survol ou menu ouvert ;
      - categories repliables (TrainerUICategoryTemplate, lignes recyclees) :
        decor a alpha 0, bandeau en degrade d accent et filet d or, titre
        en or (blanc au survol, comme chez Blizzard), +/- teinte en or ;
      - competences (ClassTrainerSkillButtonTemplate, lignes recyclees, et le
        palier de metier skillStepButton) : fond, survol, choix et voile gris
        de Blizzard a alpha 0 ; carte sombre, choix en degrade avec barre
        d or, survol en degrade, icone carree recadree dans un carre sombre ;
      - bouton Apprendre (MagicButtonTemplate) : plaque plate ;
      - barre de defilement minimaliste ; carre sombre sous l argent (pieces
        et chiffres de Blizzard gardes, points de dressage aussi).
    Couleurs d information de Blizzard gardees (jamais ecrasees) : nom gris
    et icone desaturee si indisponible, conditions manquantes en rouge, prix
    en rouge si trop cher, "Deja connu". Elles sont LUES pour le lisere de
    l icone, en style CorpUI : rouge sombre (indisponible, trop cher), gris
    (deja connu), or (competence choisie), theme sinon ; une competence
    indisponible a une carte plus sombre (au lieu du voile gris de Blizzard).
    Cette version de la fenetre n a ni volet de detail ni bouton "Tout
    apprendre" : tout est dans la ligne. Aucun texte visible ajoute.

    Regles de ce client (taint, valeurs secretes). Le bouton Apprendre
    appelle BuyTrainerService (ou la confirmation de metier) depuis les
    scripts de Blizzard, la liste appelle SelectTrainerService : le moindre
    ecart bloquerait l apprentissage. Donc :
      - aucun crochet, aucun SetScript, aucun attribut, aucun champ ecrit
        dans un cadre ou une table de Blizzard (lignes recyclees comprises) :
        notre etat est range dans des tables faibles a nous ;
      - aucune taille, position, strate, niveau, parent, souris ni visibilite
        de Blizzard modifiee, aucune de leurs fonctions Lua appelee : alpha,
        couleur, desaturation et recadrage de LEURS textures, police et
        couleur des seuls titres de categories (Blizzard ne les relit pas),
        nos propres textures posees sur leurs cadres ;
      - les etats sont relus a chaque releve (texture de choix montree, voile
        gris montre, texte "Deja connu", police rouge du prix) ;
      - releve periodique (0,1 s) fenetre ouverte, rien en combat, toute
        valeur lue verifiee (pcall, issecretvalue).
    Skins.lua ne descend plus dans la fenetre (ns.SkinClaimed) : il garde
    son fond, son cadre, son titre et sa croix. Groupe du module : "prof".
----------------------------------------------------------------------------]]

local _, ns = ...

local issecret = issecretvalue or function() return false end
local weak = { __mode = "k" }

local mine = setmetatable({}, weak)      -- nos regions (a ne jamais traiter)
local claimed = setmetatable({}, weak)   -- cadres repris ici
local plates = setmetatable({}, weak)    -- bouton aplati -> { fill, edges, hl, drop, bg }
local heads = setmetatable({}, weak)     -- categorie -> { label, icons, file, over }
local rows = setmetatable({}, weak)      -- competence -> { fill, edges, pick, bar, box, ring... }
local wells = setmetatable({}, weak)     -- zone de liste -> true
local ranks = setmetatable({}, weak)     -- barre de rang -> { bg, edges, bar }
local bars = setmetatable({}, weak)      -- barre de defilement -> { thumb, knob }
local pools = setmetatable({}, weak)     -- conteneur de lignes recyclees -> true
local purses = setmetatable({}, weak)    -- fenetre -> carre de l argent pose

-- lisere de l icone selon l etat lu chez Blizzard
local DARKRED = { 0.62, 0.16, 0.16 }
local GRAY = { 0.42, 0.42, 0.46 }
local WHITE = { 1, 1, 1 }
-- titre des categories : le texte de Blizzard fait 10 px de haut (police
-- de 12 chez eux) ; un cran plus petit que nos autres en-tetes
local HEAD_SIZE = 11
-- polices rouges des pieces (SetMoneyFrameColorByFrame(..., "red"))
local RED_FONTS = { "NumberFontNormalRightRed", "UserScaledFontNumberNormalRightRed" }
-- sous-cadres dont l affichage relance un parcours complet
local PAGE_KEYS = { "bottomInset", "skillStepButton", "money", "trainingPoints", "ScrollBox" }

local function db()
    local d = ns.skinsDB
    if type(d) ~= "table" or not d.enabled then return nil end
    if d.groups and d.groups.prof == false then return nil end
    return d
end

---------------------------------------------------------------------------
-- Outils (lectures protegees, sans fermeture neuve a chaque appel)
---------------------------------------------------------------------------

local function get(f, key) return f[key] end
local function packRegions(f) return { f:GetRegions() } end
local function packChildren(f) return { f:GetChildren() } end

local function isTrue(v)
    if issecret(v) then return false end
    return v == true
end

local function objType(o)
    if type(o) ~= "table" or not o.GetObjectType then return nil end
    local ok, t = pcall(o.GetObjectType, o)
    if ok and not issecret(t) and type(t) == "string" then return t end
end

-- champ table d un cadre de Blizzard (lecture seule)
local function field(f, key)
    if type(f) ~= "table" then return nil end
    local ok, c = pcall(get, f, key)
    if ok and type(c) == "table" then return c end
end

-- accesseur du moteur present sur l objet (jamais appele s il manque)
local function method(f, key)
    if type(f) ~= "table" then return nil end
    local ok, fn = pcall(get, f, key)
    if ok and type(fn) == "function" then return fn end
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

local function parentIs(f, p)
    local fn = method(f, "GetParent")
    if not fn then return false end
    local ok, x = pcall(fn, f)
    return ok and rawequal(x, p)
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

local function alphaOf(t)
    if type(t) ~= "table" or not t.GetAlpha then return nil end
    local ok, a = pcall(t.GetAlpha, t)
    if ok then return num(a) end
end

local function fade(obj)
    if type(obj) == "table" and obj.SetAlpha and not mine[obj] then pcall(obj.SetAlpha, obj, 0) end
end

-- texture en mode ADD : noircie par la couleur (Blizzard n y touche pas)
local function douse(t)
    if objType(t) ~= "Texture" or mine[t] then return end
    pcall(t.SetVertexColor, t, 0, 0, 0, 0)
end

-- texture de Blizzard gardee a alpha 0 (Blizzard ne pilote pas leur alpha :
-- seulement si besoin, le releve est frequent)
local function keepFaded(t)
    if objType(t) ~= "Texture" or mine[t] then return end
    if alphaOf(t) ~= 0 then fade(t) end
end

-- texte d un FontString (false si absent ou secret)
local function textOf(fs)
    if objType(fs) ~= "FontString" then return false end
    local ok, t = pcall(fs.GetText, fs)
    if not ok or issecret(t) or type(t) ~= "string" then return false end
    return t
end

local function isRedText(fs)
    if objType(fs) ~= "FontString" then return false end
    local ok, r, g, b = pcall(fs.GetTextColor, fs)
    if not ok then return false end
    r, g, b = num(r), num(g), num(b)
    return (r and g and b and r > 0.85 and g < 0.4 and b < 0.4) and true or false
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

-- textures d etat d un bouton (accesseurs du moteur)
local function stateTex(b, getter)
    local fn = method(b, getter)
    if not fn then return nil end
    local ok, t = pcall(fn, b)
    if ok and objType(t) == "Texture" then return t end
end

local function fadeStates(b, list)
    for _, g in ipairs(list) do fade(stateTex(b, g)) end
end

local function tex(host, layer, sub)
    local t = host:CreateTexture(nil, layer, nil, sub)
    mine[t] = true
    ns.NoSnap(t)   -- traits fins toujours dessines (Core.lua)
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

local function paintC(list, c, a)
    for _, x in ipairs(list) do x:SetColorTexture(c[1], c[2], c[3], a or 1) end
end

-- lisere repeint seulement quand sa couleur change (releve frequent)
local function tint(s, c, a)
    a = a or 1
    if s.ec == c and s.ea == a then return end
    s.ec, s.ea = c, a
    paintC(s.edges, c, a)
end

local function goldTint(t)
    if objType(t) ~= "Texture" then return end
    local C = ns.COLORS
    pcall(t.SetDesaturated, t, true)
    pcall(t.SetVertexColor, t, C.gold[1], C.gold[2], C.gold[3], 1)
end

---------------------------------------------------------------------------
-- Boutons
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

-- bouton Apprendre (MagicButtonTemplate = UIPanelButtonTemplate) : ses
-- trois tranches a alpha 0, notre plaque de 20 px ; texte et police
-- intouches (le bouton appelle l apprentissage)
local function panelButton(b)
    if plates[b] or type(b) ~= "table" or not b.CreateTexture then return end
    local l, m, r = field(b, "Left"), field(b, "Middle"), field(b, "Right")
    if objType(l) == "Texture" and objType(m) == "Texture" and objType(r) == "Texture" then
        fade(l) fade(m) fade(r)
        fadeStates(b, { "GetHighlightTexture" })
    else
        fadeStates(b, { "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" })
    end
    plate(b, 1, 1)
end

-- bouton Filtre / Reglages (fond common-dropdown-b-button : Blizzard en
-- change l atlas a chaque etat, jamais l alpha) : plaque de 22 px pour un
-- bouton de 18. Les menus a fleche jaune sont a Communs.lua.
local function dropdown(b)
    if plates[b] or type(b) ~= "table" or not b.CreateTexture then return end
    local okC, common = pcall(function() return ns.SkinCommon and ns.SkinCommon(b) end)
    if okC and common then return end
    local bg = field(b, "Background")
    fade(bg)
    for _, r in ipairs(regionsOf(b)) do
        local a = atlasOf(r)
        if a and a:find("^common%-dropdown%-b%-button") then fade(r) end
    end
    local p = plate(b, 0, -2)
    if p then p.drop, p.bg = true, bg end
end

-- menu ouvert : champ "menu" pose par DropdownButtonMixin (lu), ou atlas
-- "-open" du fond (WowStyle1FilterDropdownStateOpen)
local function dropOpen(b, p)
    if field(b, "menu") ~= nil then return true end
    local a = atlasOf(p.bg)
    return a ~= nil and a:find("%-open$") ~= nil
end

local function plateState(b, p)
    local C = ns.COLORS
    local en = enabled(b)
    if p.drop then keepFaded(p.bg) end
    local hot = en and (isOver(b) or (p.drop and dropOpen(b, p)))
    tint(p, hot and C.gold or C.border)
    local a = en and 1 or 0.5
    if a ~= p.a then
        p.a = a
        p.fill:SetAlpha(a)
    end
end

---------------------------------------------------------------------------
-- Zones de la fenetre
---------------------------------------------------------------------------

-- zone de liste (InsetFrameTemplate, dessinee au niveau de la fenetre :
-- nos textures au-dessus du fond de Skins.lua, sous-niveaux -4 / -3)
local function well(inset)
    if type(inset) ~= "table" or wells[inset] or not inset.CreateTexture then return end
    wells[inset] = true
    fade(field(inset, "Bg"))
    fadeOwn(inset)
    fadeOwn(field(inset, "NineSlice"))
    local C = ns.COLORS
    local fill = tex(inset, "BACKGROUND", -4)
    fill:SetAllPoints(inset)
    fill:SetColorTexture(0, 0, 0, 0.35)
    paintC(ring(inset, fill, "BACKGROUND", -3, 0), C.border, 0.9)
    claimed[inset] = true
end

-- carre sombre sous l argent (barre du bas de ButtonFrameTemplate) : de la
-- gauche du cadre d argent de Blizzard (MoneyBg, efface) au bord droit des
-- pieces, a la hauteur de la plaque du bouton Apprendre (5 a 25 px)
local function purse(f)
    if purses[f] or not f.CreateTexture then return end
    purses[f] = true
    local bg = rawget(_G, "ClassTrainerFrameMoneyBg")
    if objType(bg) == "Texture" then fade(bg) end
    local C = ns.COLORS
    local fill = tex(f, "BACKGROUND", -4)
    fill:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 7, 25)
    fill:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", 163, 5)
    fill:SetColorTexture(0, 0, 0, 0.45)
    paintC(ring(f, fill, "BACKGROUND", -3, 0), C.border)
end

-- barre de rang (StatusBar nommee, sans champs) : bords, fond bleu a
-- alpha 0 ; la barre de Blizzard reste (valeur, largeur), desaturee et
-- teintee de l accent
local function rankTex(sb)
    local fn = method(sb, "GetStatusBarTexture")
    if fn then
        local ok, t = pcall(fn, sb)
        if ok and objType(t) == "Texture" then return t end
    end
    local t = rawget(_G, "ClassTrainerStatusBarBar")
    if objType(t) == "Texture" then return t end
end

local function rankState(_, s)
    local t = s.bar
    if objType(t) ~= "Texture" then return end
    local C = ns.COLORS
    local ok, r, g, b = pcall(t.GetVertexColor, t)
    r, g, b = ok and num(r), ok and num(g), ok and num(b)
    if r and g and b and math.abs(r - C.violet[1]) < 0.01 and math.abs(g - C.violet[2]) < 0.01
        and math.abs(b - C.violet[3]) < 0.01 then return end
    pcall(t.SetDesaturated, t, true)
    pcall(t.SetVertexColor, t, C.violet[1], C.violet[2], C.violet[3], 0.9)
end

local function rankBar(sb)
    if ranks[sb] or not sb.CreateTexture then return end
    local name = "ClassTrainerStatusBar"
    local fn = method(sb, "GetName")
    if fn then
        local ok, n = pcall(fn, sb)
        if ok and type(n) == "string" and not issecret(n) then name = n end
    end
    for _, k in ipairs({ "Left", "Right", "Middle", "Background" }) do
        local t = rawget(_G, name .. k)
        if objType(t) == "Texture" then fade(t) end
    end
    local C = ns.COLORS
    local s = { bar = rankTex(sb) }
    s.bg = tex(sb, "BACKGROUND", -8)
    s.bg:SetPoint("TOPLEFT", sb, "TOPLEFT", -1, 1)
    s.bg:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 1, -1)
    s.bg:SetColorTexture(0, 0, 0, 0.6)
    s.edges = ring(sb, s.bg, "BACKGROUND", -7, 0)
    paintC(s.edges, C.border)
    ranks[sb] = s
    claimed[sb] = true
    rankState(sb, s)
end

-- barre de defilement (MinimalScrollBar) : alpha et couleur seulement
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
    -- fleches : notre chevron (Core.lua), celles de Blizzard eteintes
    for _, k in ipairs({ "Back", "Forward" }) do
        local b = field(sb, k)
        local c = ns.UI.ArrowChevron(b, ns.UI.ScrollDir(sb, k), 10, { field(b, "Texture") })
        if c then mine[c] = true end
    end
    bars[sb] = { thumb = thumb, knob = knob }
    claimed[sb] = true
end

local function barState(_, b)
    local C = ns.COLORS
    local over = isOver(b.thumb)
    if over == b.over then return end
    b.over = over
    if over then
        b.knob:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.9)
    else
        b.knob:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.6)
    end
end

---------------------------------------------------------------------------
-- Categories (TrainerUICategoryTemplate, recyclees)
---------------------------------------------------------------------------

local function isHeader(f)
    return objType(field(f, "Label")) == "FontString" and objType(field(f, "CollapseIcon")) == "Texture"
        and objType(field(f, "CenterPiece")) == "Texture"
end

-- decor Professions-recipe-header-* a alpha 0 (pose une fois par le XML,
-- jamais retouche), bandeau d accent, filet d or, survol en degrade
local function header(h)
    if heads[h] or not h.CreateTexture then return end
    for _, k in ipairs({ "LeftPiece", "RightPiece", "CenterPiece" }) do fade(field(h, k)) end
    local C = ns.COLORS
    local s = { label = field(h, "Label"), icons = { field(h, "CollapseIcon"), field(h, "CollapseIconAlphaAdd") } }
    -- le decor et le titre de Blizzard sont 2 px au-dessus du centre
    s.band = tex(h, "BACKGROUND", 1)
    s.band:SetPoint("TOPLEFT", h, "TOPLEFT", 1, -1)
    s.band:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -1, 3)
    ns.UI.Gradient(s.band, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.30, C.violet[1], C.violet[2], C.violet[3], 0.03)
    s.line = tex(h, "BACKGROUND", 2)
    s.line:SetPoint("TOPLEFT", s.band, "BOTTOMLEFT", 0, 0)
    s.line:SetPoint("TOPRIGHT", s.band, "BOTTOMRIGHT", 0, 0)
    s.line:SetHeight(1)
    ns.UI.Gradient(s.line, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.8, C.gold[1], C.gold[2], C.gold[3], 0)
    s.hov = tex(h, "HIGHLIGHT")
    s.hov:SetAllPoints(s.band)
    ns.UI.Gradient(s.hov, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.25, C.violet[1], C.violet[2], C.violet[3], 0.02)
    heads[h] = s
    claimed[h] = true
end

-- titre : Blizzard change d objet de police au survol (SetFontObject dans
-- ses OnEnter / OnLeave) : notre police est reposee si elle a change, la
-- couleur suit le survol (or, blanc au survol) ; +/- en or (atlas repose
-- par Blizzard a chaque recyclage)
local function headState(h, s)
    local fs = s.label
    if objType(fs) == "FontString" then
        local ok, file = pcall(fs.GetFont, fs)
        file = (ok and type(file) == "string" and not issecret(file)) and file or nil
        if not s.set or (s.file and file ~= s.file) then
            s.set = true
            pcall(ns.UI.HeadFont, fs, HEAD_SIZE)
            local ok2, f2 = pcall(fs.GetFont, fs)
            s.file = (ok2 and type(f2) == "string" and not issecret(f2)) and f2 or nil
        end
        local c = isOver(h) and WHITE or ns.COLORS.gold
        pcall(fs.SetTextColor, fs, c[1], c[2], c[3])
    end
    for _, t in ipairs(s.icons) do goldTint(t) end
end

---------------------------------------------------------------------------
-- Competences (ClassTrainerSkillButtonTemplate, recyclees)
---------------------------------------------------------------------------

local function isSkill(f)
    return objType(field(f, "icon")) == "Texture" and objType(field(f, "selectedTex")) == "Texture"
        and objType(field(f, "disabledBG")) == "Texture"
end

-- prix trop cher : Blizzard passe les pieces a sa police rouge ; on lit
-- l objet de police, sinon la couleur du texte
local function redFont(o)
    if type(o) ~= "table" then return false end
    for _, k in ipairs(RED_FONTS) do
        local f = rawget(_G, k)
        if f ~= nil and rawequal(o, f) then return true end
    end
    return false
end

local function moneyRed(m)
    if not shown(m) then return false end
    for _, k in ipairs({ "GoldButton", "SilverButton", "CopperButton" }) do
        local b = field(m, k)
        if b and shown(b) then
            local fn = method(b, "GetNormalFontObject")
            if fn then
                local ok, fo = pcall(fn, b)
                if ok and redFont(fo) then return true end
            end
            if isRedText(field(b, "Text")) then return true end
        end
    end
    return false
end

-- "Deja connu" : texte pose par Blizzard sous le nom (ITEM_SPELL_KNOWN)
local function known(sub)
    local t = textOf(sub)
    local k = rawget(_G, "ITEM_SPELL_KNOWN")
    return (t and type(k) == "string" and not issecret(k) and t == k) and true or false
end

local function skillRow(b)
    if type(b) ~= "table" or rows[b] or not b.CreateTexture then return end
    local icon = field(b, "icon")
    if objType(icon) ~= "Texture" then return end
    local C = ns.COLORS
    local s = {
        icon = icon, sel = field(b, "selectedTex"), dis = field(b, "disabledBG"), sub = field(b, "subText"),
        money = field(b, "money"), alt = field(b, "alternateCost"),
        normal = stateTex(b, "GetNormalTexture"), light = stateTex(b, "GetHighlightTexture"),
    }
    -- fond de ligne, survol (ADD), choix (ADD) et voile gris (MOD) de
    -- Blizzard : alpha 0 (montres / caches par Blizzard, jamais leur alpha) ;
    -- les deux textures ADD sont en plus noircies (un ajout noir ne dessine
    -- rien, quel que soit l alpha) ; nos fonds sont dessines apres le voile
    -- gris (sous-niveaux 1 a 4) : s il assombrit encore, ce n est que le
    -- fond obsidienne dessous
    fade(s.normal) fade(s.light) fade(s.sel) fade(s.dis)
    douse(s.light) douse(s.sel)
    fadeStates(b, { "GetPushedTexture" })
    -- carte
    s.fill = tex(b, "BACKGROUND", 1)
    s.fill:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    s.fill:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    s.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.75)
    s.edges = ring(b, s.fill, "BACKGROUND", 2, 0)
    paintC(s.edges, C.border, 0.55)
    -- choix : degrade d accent et barre d or a gauche
    s.pick = tex(b, "BACKGROUND", 3)
    s.pick:SetAllPoints(s.fill)
    ns.UI.Gradient(s.pick, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.5, C.violet[1], C.violet[2], C.violet[3], 0.05)
    s.pick:Hide()
    s.bar = tex(b, "BACKGROUND", 4)
    s.bar:SetPoint("TOPLEFT", s.fill, "TOPLEFT", 0, 0)
    s.bar:SetPoint("BOTTOMLEFT", s.fill, "BOTTOMLEFT", 0, 0)
    s.bar:SetWidth(2)
    s.bar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    s.bar:Hide()
    -- survol (calque HIGHLIGHT : le moteur l affiche seul sur un bouton)
    s.hov = tex(b, "HIGHLIGHT")
    s.hov:SetAllPoints(s.fill)
    ns.UI.Gradient(s.hov, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.22, C.violet[1], C.violet[2], C.violet[3], 0.02)
    -- icone carree : fond sombre dessous, lisere d etat autour
    s.box = tex(b, "BORDER", -8)
    s.box:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
    s.box:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
    s.box:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.9)
    s.ring = { edges = ring(b, icon, "OVERLAY", 7, 1) }
    tint(s.ring, C.border)
    cropIcon(icon)
    rows[b] = s
    claimed[b] = true
end

-- etat relu a chaque releve (la ligne est recyclee et reinitialisee par
-- Blizzard) ; seules nos textures changent
local function rowState(_, s)
    local C = ns.COLORS
    keepFaded(s.normal) keepFaded(s.light) keepFaded(s.sel) keepFaded(s.dis)
    cropIcon(s.icon)
    local sel = shown(s.sel)
    local unav = shown(s.dis)
    local used = not unav and known(s.sub)
    local poor = not unav and not used and (moneyRed(s.money) or (shown(s.alt) and isRedText(s.alt)))
    local kind = unav and "U" or (used and "K" or (poor and "P" or "A"))
    if sel ~= s.selOn then
        s.selOn = sel
        s.pick:SetShown(sel)
        s.bar:SetShown(sel)
    end
    if kind ~= s.kind then
        s.kind = kind
        if kind == "U" then
            s.fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.92)
        elseif kind == "K" then
            s.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.45)
        else
            s.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.75)
        end
    end
    -- lisere de l icone : l information rouge / grise passe avant le choix
    local c = C.border
    if kind == "U" or kind == "P" then c = DARKRED
    elseif kind == "K" then c = GRAY
    elseif sel then c = C.gold end
    tint(s.ring, c)
end

---------------------------------------------------------------------------
-- Parcours
---------------------------------------------------------------------------

local function full(f)
    pcall(well, field(f, "Inset"))
    pcall(well, field(f, "bottomInset"))
    pcall(purse, f)
    local sb = rawget(_G, "ClassTrainerStatusBar")
    if type(sb) == "table" and parentIs(sb, f) then pcall(rankBar, sb) end
    pcall(dropdown, field(f, "FilterDropdown"))
    pcall(panelButton, field(f, "TrainButton"))
    -- palier de metier (meme modele que les lignes, pose sur la fenetre)
    local step = field(f, "skillStepButton")
    if step and isSkill(step) then pcall(skillRow, step) end
    local bar = field(f, "ScrollBar")
    if bar and isScrollBar(bar) then pcall(skinScrollBar, bar) end
    local target = field(field(f, "ScrollBox"), "ScrollTarget")
    if target then
        if method(target, "GetNumChildren") then pools[target] = true end
        for _, c in ipairs(childrenOf(target)) do
            if not mine[c] and not rows[c] and not heads[c] then
                if isHeader(c) then pcall(header, c)
                elseif isSkill(c) then pcall(skillRow, c) end
            end
        end
    end
end

local function each(t, fn)
    for k, s in pairs(t) do
        if visible(k) then pcall(fn, k, s) end
    end
end

-- leger (10 fois par seconde, fenetre ouverte) : etats et couleurs
local function light()
    each(plates, plateState)
    each(heads, headState)
    each(rows, rowState)
    each(ranks, rankState)
    each(bars, barState)
end

-- Skins.lua : ne pas descendre dans la fenetre des maitres (tout est repris
-- ici ; la parente suffit, sans course au chargement), ne pas effacer nos
-- textures
local prevClaimed = ns.SkinClaimed
function ns.SkinClaimed(f)
    if type(f) == "table" then
        if claimed[f] then return true end
        local ctf = rawget(_G, "ClassTrainerFrame")
        if type(ctf) == "table" and db() and parentIs(f, ctf) then return true end
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
    return s .. (shown(rawget(_G, "ClassTrainerStatusBar")) and "1" or "0")
end

-- nombre de cadres des pools connus (accesseur du moteur) : un cadre n est
-- jamais detruit, le total ne fait que croitre ; s il change, une ligne
-- neuve attend son habillage (categorie depliee, filtre change) : parcours
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
        ns.skinsDB.errors.Trainer = tostring(err)
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
    local f = rawget(_G, "ClassTrainerFrame")
    if type(f) ~= "table" or not f.CreateTexture or not visible(f) then
        state.shown = false
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
    local ok, err = pcall(light)
    if not ok then report(err) end
end)
