--[[--------------------------------------------------------------------------
    CorpUI - module Habillage : canaux de discussion en profondeur
    (ChannelFrame de Blizzard_Channels ; le .toc charge [Family] = Mainline
    en Camelot, les variantes Classic sont aussi reconnues par leurs champs)

    Skins.lua pose le cadre exterieur une fois la fenetre declaree dans
    Fenetres.lua (fond, lisere, bandeau, titre or, croix plate, portrait
    Battle.net a alpha 0) ; ici on reprend l interieur :
      - les deux cadres interieurs (LeftInset, RightInset) : marbre et
        bordure a alpha 0, panneau sombre a lisere pose sur la liste et sur
        la liste des membres (au-dessus de la fenetre, sous les lignes) ;
      - liste des canaux : en-tetes (Groupe, Monde, Personnalise, nom d une
        communaute) en bandeau degrade + filet d or, signe +/- en or ;
        lignes de canaux (texte, vocal, communaute) en lignes plates a
        separateur fin, survol en degrade, canal choisi en degrade d accent,
        barre et lisere d or ; canal inactif attenue (texte gris de Blizzard
        garde) ; icones vocales gardees ;
      - liste des membres : titre du canal (et nombre) en or sur un bandeau,
        lignes plates a separateur, survol en degrade + barre d or ; nom a
        la couleur de classe (ou gris hors ligne) et icone de rang gardes ;
      - boutons Ajouter / Reglages : plaque plate, lisere d or au survol (si
        Skins.lua ne l a pas deja fait) ;
      - barres de defilement minimalistes (et anciennes, variante Classic) ;
      - fenetre "Nouveau canal" (CreateChannelPopup, posee sur UIParent) :
        fond, ombre, bandeau, titre or, croix plate, champs Nom / Mot de
        passe habilles (on n y lit ni n y ecrit rien), libelles or, case
        "chat vocal", boutons OK / Annuler aplatis.
    Pas touches : bulle d aide (HelpTip) et lueur du tutoriel (variante
    Classic), boutons vocaux (casque, sourdine) dont l icone dit l etat,
    menus contextuels (systeme de menus du jeu), notifications vocales.
    La bulle (tant qu elle est posee sur la fenetre) et la lueur sont
    reclamees par ns.SkinClaimed : Skins.lua ne les parcourt pas non plus.
    Declaration conseillee dans Fenetres.lua : { "ChannelFrame", depth = 0 }
    (tout l interieur est repris ici ; Skins.lua ne fait que le cadre).

    Regles de ce client (valeurs secretes, taint) - les actions de cette
    fenetre sont sensibles (rejoindre / quitter un canal, inviter, menus de
    joueur, mot de passe) :
      - aucun crochet, aucun SetScript, aucun appel de methode de Blizzard
        (mixins) : releve periodique, fenetre ouverte ;
      - aucun champ ecrit dans les cadres de Blizzard (lignes recyclees par
        des pools) : notre etat est range dans des tables faibles a nous ;
      - aucune taille, position, strate, niveau, parent, souris ni
        visibilite de Blizzard modifiee : seulement l alpha et la couleur de
        leurs textures, la couleur de quelques titres decoratifs, et nos
        propres textures / textes ;
      - les textures dont Blizzard pilote l alpha (fond des lignes remis a
        1 a chaque mise a jour, survol verrouille du canal choisi) sont
        eteintes par la COULEUR (alpha 0 du sommet), jamais par SetAlpha ;
      - rien en combat ; toute valeur lue est verifiee (pcall, issecretvalue).
    Diagnostic : la premiere erreur de la session, avec le nom de l etape,
    est gardee dans CorpUIDB.skins.errors.Channels.
----------------------------------------------------------------------------]]

local _, ns = ...

local issecret = issecretvalue or function() return false end
local weak = { __mode = "k" }

local mine = setmetatable({}, weak)      -- nos regions (a ne jamais traiter)
local claimed = setmetatable({}, weak)   -- cadres que Skins.lua / Communs.lua laissent
local panels = setmetatable({}, weak)    -- cadre deja habille (panneau, fenetre)
local heads = setmetatable({}, weak)     -- en-tete de categorie -> etat
local chans = setmetatable({}, weak)     -- ligne de canal -> etat
local members = setmetatable({}, weak)   -- ligne de membre -> etat
local plates = setmetatable({}, weak)    -- bouton aplati -> { fill, edges, glyph }
local others = setmetatable({}, weak)    -- bouton deja aplati par un autre fichier
local bars = setmetatable({}, weak)      -- barre de defilement -> { thumb, knob }
local checks = setmetatable({}, weak)    -- case a cocher -> { edges, mark, label }
local edits = setmetatable({}, weak)     -- champ de saisie -> { edges }
local labels = setmetatable({}, weak)    -- titre decoratif passe en or
local tints = setmetatable({}, weak)     -- texture teintee en or (+/-, atlas changeant)
local titles = setmetatable({}, weak)    -- liste des membres -> bandeau du titre

-- atlas du canal choisi (ChannelButtonBaseMixin:SetIsSelectedChannel)
local SELECTED = "voicechat-channellist-row-selected"

local RED = { 1, 0.3, 0.3 }
local WHITE = { 1, 1, 1 }

local TICK = 0.1     -- etats (survol, choix, textures remises par Blizzard)
local WALK = 0.4     -- parcours de la fenetre ouverte (lignes acquises en route)
local MAXDEPTH = 8

local function db()
    local d = ns.skinsDB
    if type(d) ~= "table" or not d.enabled then return nil end
    if d.groups and d.groups.social == false then return nil end
    return d
end

-- pcall qui garde la premiere erreur de la session (avec le nom de
-- l etape) dans CorpUIDB.skins.errors.Channels (remis a zero par Skins.lua
-- a chaque connexion)
local function try(tag, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        local d = ns.skinsDB
        if type(d) == "table" then
            d.errors = d.errors or {}
            if not d.errors.Channels then
                local okS, s = pcall(function() return tag .. ": " .. tostring(err) end)
                d.errors.Channels = (okS and type(s) == "string" and not issecret(s)) and s or tag
            end
        end
    end
    return ok
end

---------------------------------------------------------------------------
-- Outils (lectures protegees, sans fermeture neuve a chaque appel)
---------------------------------------------------------------------------

local function get(f, k) return f[k] end
local function packRegions(f) return { f:GetRegions() } end
local function packChildren(f) return { f:GetChildren() } end

local function objType(o)
    if type(o) ~= "table" or not o.GetObjectType then return nil end
    local ok, t = pcall(o.GetObjectType, o)
    if ok and type(t) == "string" and not issecret(t) then return t end
end

-- champ table d un cadre de Blizzard (lecture seule)
local function field(f, key)
    if type(f) ~= "table" then return nil end
    local ok, c = pcall(get, f, key)
    if ok and type(c) == "table" then return c end
end

-- premier resultat d un accesseur du moteur, s il est simple et lisible
local function ask(f, m)
    if type(f) ~= "table" then return nil end
    local okF, fn = pcall(get, f, m)
    if not okF or type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, f)
    if not ok or v == nil or issecret(v) then return nil end
    local t = type(v)
    if t == "string" or t == "number" or t == "boolean" then return v end
end

-- objet rendu par un accesseur (GetNormalTexture...)
local function askObj(f, m)
    if type(f) ~= "table" then return nil end
    local okF, fn = pcall(get, f, m)
    if not okF or type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, f)
    if ok and type(v) == "table" then return v end
end

local function num(v)
    if type(v) == "number" and not issecret(v) then return v end
end

local function visible(f) return ask(f, "IsVisible") == true end
local function shown(f) return ask(f, "IsShown") == true end
local function isOver(f) return ask(f, "IsMouseOver") == true end
local function enabled(f) return ask(f, "IsEnabled") ~= false end

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
    if objType(t) ~= "Texture" then return nil end
    local a = ask(t, "GetAtlas")
    if type(a) == "string" then return a end
end

local function alphaOf(t) return num(ask(t, "GetAlpha")) end

-- texture decorative de Blizzard a alpha 0 (jamais une des notres)
local function fade(t)
    if objType(t) ~= "Texture" or mine[t] then return end
    if alphaOf(t) ~= 0 then pcall(t.SetAlpha, t, 0) end
end

-- texture dont Blizzard pilote l alpha (fond des lignes, survol verrouille
-- du canal choisi) : eteinte par la couleur, verifiee a chaque releve
local function veil(t)
    if objType(t) ~= "Texture" or mine[t] then return end
    local ok, _, _, _, a = pcall(t.GetVertexColor, t)
    if ok and type(a) == "number" and not issecret(a) and a == 0 then return end
    pcall(t.SetVertexColor, t, 1, 1, 1, 0)
end

-- textures d un cadre (pas celles de ses enfants), sauf les notres
local function fadeOwn(f)
    for _, r in ipairs(regionsOf(f)) do
        if not mine[r] and objType(r) == "Texture" then fade(r) end
    end
end

-- textures d etat d un bouton (accesseurs du moteur)
local function fadeStates(b, list)
    for _, m in ipairs(list) do fade(askObj(b, m)) end
end

-- fond et survol d une ligne : par la couleur (champ ou accesseur)
local function veilRow(b)
    local n, h = field(b, "NormalTexture"), field(b, "HighlightTexture")
    veil(n)
    veil(h)
    local n2, h2 = askObj(b, "GetNormalTexture"), askObj(b, "GetHighlightTexture")
    if not rawequal(n2, n) then veil(n2) end
    if not rawequal(h2, h) then veil(h2) end
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

-- quatre filets de 1 px autour de "anchor" (sur "host")
local function ring(host, anchor, layer, sub)
    local list = {}
    local function line()
        local x = tex(host, layer, sub)
        list[#list + 1] = x
        return x
    end
    local top = line()
    top:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, 0)
    top:SetHeight(1)
    local bottom = line()
    bottom:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(1)
    local left = line()
    left:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)
    left:SetWidth(1)
    local right = line()
    right:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(1)
    return list
end

-- couleur des filets, seulement si elle change
local function paint(s, c, a)
    a = a or 1
    if s.c == c and s.ca == a then return end
    s.c, s.ca = c, a
    for _, x in ipairs(s.edges) do x:SetColorTexture(c[1], c[2], c[3], a) end
end

local function showAll(list, on)
    for _, x in ipairs(list) do x:SetShown(on) end
end

local function grad(t, c, a1, a2, orient)
    ns.UI.Gradient(t, orient or "HORIZONTAL", c[1], c[2], c[3], a1, c[1], c[2], c[3], a2)
end

-- titre decoratif passe en or (Blizzard n y pose que du texte)
local function goldLabel(fs)
    if objType(fs) ~= "FontString" or mine[fs] then return end
    labels[fs] = true
    local C = ns.COLORS
    pcall(fs.SetTextColor, fs, C.gold[1], C.gold[2], C.gold[3])
end

-- panneau sombre (fond, lisere) sur "host", aux dimensions de "anchor"
local function backdrop(host, anchor, alpha)
    local C = ns.COLORS
    local s = {}
    s.fill = tex(host, "BACKGROUND", -8)
    s.fill:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    s.fill:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
    s.fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], alpha or 0.6)
    s.edges = ring(host, s.fill, "BACKGROUND", -7)
    paint(s, C.border)
    return s
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
    p.fill:SetPoint("TOPLEFT", b, "TOPLEFT", inset, -inset)
    p.fill:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -inset, inset)
    p.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.95)
    p.edges = ring(b, p.fill, "BACKGROUND", -7)
    paint(p, C.border)
    p.hl = tex(b, "HIGHLIGHT")
    p.hl:SetAllPoints(p.fill)
    grad(p.hl, C.violet, 0.05, 0.28, "VERTICAL")
    plates[b] = p
    claimed[b] = true
    return p
end

-- bouton rouge (Left/Middle/Right : Ajouter, Reglages, OK, Annuler). Dans
-- la fenetre, Skins.lua l aplatit peut-etre deja : ses morceaux sont alors
-- a alpha 0 (Blizzard ne les y met jamais) et on le laisse.
local function isPanelButton(b)
    return objType(field(b, "Left")) == "Texture" and objType(field(b, "Right")) == "Texture"
        and (objType(field(b, "Middle")) == "Texture" or objType(field(b, "Center")) == "Texture")
end

local function panelButton(b)
    if plates[b] or others[b] then return end
    local okC, cl = pcall(ns.SkinClaimed, b)
    if (okC and cl and not claimed[b]) or alphaOf(field(b, "Left")) == 0 then
        others[b] = true
        return
    end
    fade(field(b, "Left"))
    fade(field(b, "Middle") or field(b, "Center"))
    fade(field(b, "Right"))
    fadeStates(b, { "GetHighlightTexture" })
    plate(b, 1)
end

-- croix de la fenetre "Nouveau canal" (UIPanelCloseButton, atlas
-- RedButton-Exit) : plaque et signe ; la croix de la fenetre est celle de
-- Skins.lua
local CLOSE_STATES = { "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }

local function closeButton(b)
    if plates[b] and plates[b].glyph then return end
    fadeStates(b, CLOSE_STATES)
    local p = plate(b, 4)
    p.glyph = text(b, 15)
    p.glyph:SetPoint("CENTER", b, "CENTER", 0, 0)
    p.glyph:SetText("×")
    p.close = true
end

local function isCloseButton(b)
    local a = atlasOf(askObj(b, "GetNormalTexture"))
    return a ~= nil and a:lower():find("redbutton%-exit") ~= nil
end

-- case a cocher (chat vocal du nouveau canal) : carre sombre, lisere,
-- coche d or ; libelle a la couleur du texte de CorpUI
local CHECK_STATES = { "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetCheckedTexture",
                       "GetDisabledCheckedTexture", "GetDisabledTexture" }

local function skinCheck(cb)
    if checks[cb] then return end
    fadeStates(cb, CHECK_STATES)
    local C = ns.COLORS
    local k = {}
    k.fill = tex(cb, "BACKGROUND", -8)
    k.fill:SetSize(14, 14)
    k.fill:SetPoint("CENTER", cb, "CENTER", 0, 0)
    k.fill:SetColorTexture(0, 0, 0, 0.6)
    k.edges = ring(cb, k.fill, "BORDER", 7)
    paint(k, C.border)
    k.mark = tex(cb, "OVERLAY", 7)
    k.mark:SetPoint("TOPLEFT", k.fill, "TOPLEFT", 3, -3)
    k.mark:SetPoint("BOTTOMRIGHT", k.fill, "BOTTOMRIGHT", -3, 3)
    ns.UI.Gradient(k.mark, "VERTICAL", C.gold[1] * 0.75, C.gold[2] * 0.75, C.gold[3] * 0.75, 1, C.gold[1], C.gold[2], C.gold[3], 1)
    k.mark:Hide()
    local label = field(cb, "Text") or field(cb, "text")
    if objType(label) == "FontString" then k.label = label end
    checks[cb] = k
    claimed[cb] = true
end

-- champ de saisie (InputBoxTemplate : Left / Middle / Right) : les trois
-- morceaux a alpha 0, notre fond et notre lisere autour ; le texte, le
-- focus et le contenu (mot de passe) ne sont jamais lus ni touches
local function skinEdit(e)
    if edits[e] then return end
    local l, m, r = field(e, "Left"), field(e, "Middle") or field(e, "Mid"), field(e, "Right")
    if not (objType(l) == "Texture" and objType(m) == "Texture" and objType(r) == "Texture") then return end
    fade(l) fade(m) fade(r)
    local C = ns.COLORS
    local fill = tex(e, "BACKGROUND", -8)
    fill:SetPoint("TOPLEFT", e, "TOPLEFT", -5, 2)
    fill:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT", 0, -2)
    fill:SetColorTexture(0, 0, 0, 0.55)
    local k = { edges = ring(e, fill, "BACKGROUND", -7) }
    paint(k, C.border)
    edits[e] = k
    claimed[e] = true
    goldLabel(field(e, "Label"))
end

---------------------------------------------------------------------------
-- Barres de defilement
---------------------------------------------------------------------------

-- MinimalScrollBar (liste des canaux, liste des membres) : alpha et
-- couleur seulement, un trait et un curseur a nous
local function isScrollBar(f)
    local track = field(f, "Track")
    return track and field(track, "Thumb") and field(f, "Back") and field(f, "Forward") and true or false
end

local function knobOn(host, anchor)
    local C = ns.COLORS
    local knob = tex(host, "ARTWORK", 2)
    knob:SetPoint("TOP", anchor, "TOP", 0, 0)
    knob:SetPoint("BOTTOM", anchor, "BOTTOM", 0, 0)
    knob:SetWidth(4)
    knob:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.6)
    return knob
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
    fade(field(sb, "Background"))
    local line = tex(track, "ARTWORK", 1)
    line:SetPoint("TOP", track, "TOP", 0, 0)
    line:SetPoint("BOTTOM", track, "BOTTOM", 0, 0)
    line:SetWidth(1)
    line:SetColorTexture(C.border[1], C.border[2], C.border[3], 0.8)
    local knob = knobOn(thumb, thumb)
    -- fleches : notre chevron (Core.lua), celles de Blizzard eteintes
    for _, k in ipairs({ "Back", "Forward" }) do
        local b = field(sb, k)
        local c = ns.UI.ArrowChevron(b, ns.UI.ScrollDir(sb, k), 10, { field(b, "Texture") })
        if c then mine[c] = true end
    end
    bars[sb] = { thumb = thumb, knob = knob }
end

-- ancienne barre (Slider : UIPanelStretchableArtScrollBarTemplate,
-- HybridScrollBarTemplate des variantes Classic) : textures de la piste a
-- alpha 0, curseur a nous pose sur celui de Blizzard, fleches teintees
local function isOldScrollBar(f)
    if objType(f) ~= "Slider" then return false end
    return (field(f, "ScrollUpButton") or field(f, "ScrollDownButton")) ~= nil
end

local ARROW_STATES = { "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture" }

local function skinOldScrollBar(sb)
    if bars[sb] then return end
    local C = ns.COLORS
    local thumb = askObj(sb, "GetThumbTexture")
    for _, r in ipairs(regionsOf(sb)) do
        if not rawequal(r, thumb) and not mine[r] and objType(r) == "Texture" then fade(r) end
    end
    if objType(thumb) ~= "Texture" then
        bars[sb] = {}
        return
    end
    fade(thumb)
    local line = tex(sb, "ARTWORK", 1)
    line:SetPoint("TOP", sb, "TOP", 0, 0)
    line:SetPoint("BOTTOM", sb, "BOTTOM", 0, 0)
    line:SetWidth(1)
    line:SetColorTexture(C.border[1], C.border[2], C.border[3], 0.8)
    local knob = knobOn(sb, thumb)
    -- fleches : notre chevron (Core.lua), leurs etats eteints par la couleur
    for _, k in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
        local b = field(sb, k)
        local hide = {}
        for _, m in ipairs(ARROW_STATES) do
            local t = askObj(b, m)
            if objType(t) == "Texture" and not mine[t] then hide[#hide + 1] = t end
        end
        local c = ns.UI.ArrowChevron(b, k == "ScrollUpButton" and "UP" or "DOWN", 10, hide)
        if c then mine[c] = true end
        fadeStates(b, { "GetHighlightTexture" })
    end
    bars[sb] = { thumb = sb, knob = knob, ref = thumb }
end

---------------------------------------------------------------------------
-- Liste des canaux (pools de ChannelButton*Template, recycles)
---------------------------------------------------------------------------

-- en-tete de categorie (ChannelButtonHeaderTemplate : Groupe, Monde,
-- Personnalise, nom d une communaute) : bandeau degrade + filet d or ; le
-- fond gris (remis a alpha 1 a chaque mise a jour) et le survol de
-- Blizzard sont eteints par la couleur ; +/- teinte en or
local function headerRow(b)
    if heads[b] then return end
    local C = ns.COLORS
    veilRow(b)
    local s = {}
    s.fill = tex(b, "BACKGROUND", -8)
    s.fill:SetAllPoints(b)
    grad(s.fill, C.violet, 0.30, 0.03)
    s.line = tex(b, "BACKGROUND", -7)
    s.line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    s.line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    s.line:SetHeight(1)
    grad(s.line, C.gold, 0.8, 0)
    s.hl = tex(b, "HIGHLIGHT")
    s.hl:SetAllPoints(b)
    grad(s.hl, C.violet, 0.22, 0.02)
    local sign = field(b, "Collapsed")
    if objType(sign) == "Texture" then
        s.sign = sign
        tints[sign] = true
    end
    heads[b] = s
    claimed[b] = true
end

local function headState(b, s)
    veilRow(b)
    -- categorie vide : Blizzard desactive l en-tete
    local a = enabled(b) and 1 or 0.5
    if s.a ~= a then
        s.a = a
        s.fill:SetAlpha(a)
        s.line:SetAlpha(a)
    end
end

-- ligne de canal (texte, vocal, communaute) : ligne plate a separateur,
-- survol en degrade, canal choisi en degrade d accent + barre et lisere d or
local function channelRow(b)
    if chans[b] then return end
    local C = ns.COLORS
    veilRow(b)
    local s = {}
    s.fill = tex(b, "BACKGROUND", -8)
    s.fill:SetAllPoints(b)
    s.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.55)
    s.line = tex(b, "BACKGROUND", -7)
    s.line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    s.line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    s.line:SetHeight(1)
    s.line:SetColorTexture(C.border[1], C.border[2], C.border[3], 0.45)
    s.on = tex(b, "BACKGROUND", -6)
    s.on:SetAllPoints(b)
    grad(s.on, C.violet, 0.5, 0.05)
    s.on:Hide()
    s.edges = ring(b, s.fill, "BACKGROUND", -5)
    paint(s, C.gold)
    showAll(s.edges, false)
    s.bar = tex(b, "BACKGROUND", -4)
    s.bar:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    s.bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    s.bar:SetWidth(2)
    s.bar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    s.bar:Hide()
    -- survol : calque HIGHLIGHT (le moteur l affiche seul ; verrouille par
    -- Blizzard sur le canal choisi)
    s.hl = tex(b, "HIGHLIGHT")
    s.hl:SetAllPoints(b)
    grad(s.hl, C.violet, 0.25, 0.02)
    chans[b] = s
    claimed[b] = true
end

-- canal choisi : atlas pose par SetIsSelectedChannel, ou bouton retenu par
-- la liste (champ selectedChannelButton, lu)
local function isSelected(b, list)
    local a = atlasOf(askObj(b, "GetHighlightTexture")) or atlasOf(field(b, "HighlightTexture"))
    if a and a:lower() == SELECTED then return true end
    if list then
        local okS, sel = pcall(get, list, "selectedChannelButton")
        if okS and rawequal(sel, b) then return true end
    end
    return false
end

local function chanState(b, s, list)
    veilRow(b)
    local on = isSelected(b, list)
    if s.sel ~= on then
        s.sel = on
        s.on:SetShown(on)
        s.bar:SetShown(on)
        showAll(s.edges, on)
    end
    -- canal inactif ou retire : Blizzard le desactive (texte gris garde)
    local a = enabled(b) and 1 or 0.5
    if s.a ~= a then
        s.a = a
        s.fill:SetAlpha(a)
    end
end

---------------------------------------------------------------------------
-- Liste des membres (ChannelRosterButtonTemplate, recyclees par la ScrollBox)
---------------------------------------------------------------------------

local function memberRow(b)
    if members[b] then return end
    local C = ns.COLORS
    veilRow(b)
    local s = {}
    s.fill = tex(b, "BACKGROUND", -8)
    s.fill:SetAllPoints(b)
    s.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.35)
    s.line = tex(b, "BACKGROUND", -7)
    s.line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    s.line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    s.line:SetHeight(1)
    s.line:SetColorTexture(C.border[1], C.border[2], C.border[3], 0.45)
    s.hl = tex(b, "HIGHLIGHT")
    s.hl:SetAllPoints(b)
    grad(s.hl, C.violet, 0.30, 0.03)
    s.hlBar = tex(b, "HIGHLIGHT")
    s.hlBar:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    s.hlBar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    s.hlBar:SetWidth(2)
    s.hlBar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    members[b] = s
    claimed[b] = true
end

-- titre du canal au-dessus de la liste des membres (ChannelName,
-- ChannelCount : textes seuls, couleur jamais relue par Blizzard) : or,
-- sur un bandeau degrade + filet d or, montre seulement s il y a un titre
local function rosterTitle(roster)
    if titles[roster] or type(roster) ~= "table" or not roster.CreateTexture then return end
    local name = field(roster, "ChannelName")
    if objType(name) ~= "FontString" then return end
    local C = ns.COLORS
    local t = { name = name }
    t.band = tex(roster, "BACKGROUND", -6)
    t.band:SetPoint("TOPLEFT", name, "TOPLEFT", -3, 3)
    t.band:SetPoint("BOTTOMRIGHT", name, "BOTTOMRIGHT", 0, -3)
    grad(t.band, C.violet, 0.32, 0.03)
    t.line = tex(roster, "BACKGROUND", -6)
    t.line:SetPoint("TOPLEFT", t.band, "BOTTOMLEFT", 0, 0)
    t.line:SetPoint("TOPRIGHT", t.band, "BOTTOMRIGHT", 0, 0)
    t.line:SetHeight(1)
    grad(t.line, C.gold, 0.8, 0)
    goldLabel(name)
    goldLabel(field(roster, "ChannelCount"))
    titles[roster] = t
end

local function titleState(t)
    local txt = ask(t.name, "GetText")
    local on = shown(t.name) and type(txt) == "string" and txt ~= ""
    if t.on ~= on then
        t.on = on
        t.band:SetShown(on)
        t.line:SetShown(on)
    end
end

---------------------------------------------------------------------------
-- Cadres interieurs
---------------------------------------------------------------------------

-- LeftInset / RightInset (InsetFrameTemplate, au niveau de la fenetre) :
-- marbre et bordure a alpha 0 ; notre panneau va sur la liste (ScrollFrame)
-- et sur la liste des membres, un niveau au-dessus de la fenetre et sous
-- les lignes, ancre au cadre interieur (qui s elargit avec la barre)
local function insetPanel(cf, insetKey, hostKey)
    local inset = field(cf, insetKey)
    local host = field(cf, hostKey)
    if not inset or panels[inset] then return end
    panels[inset] = true
    fadeOwn(inset)
    fadeOwn(field(inset, "NineSlice"))
    if type(host) == "table" and host.CreateTexture then backdrop(host, inset, 0.6) end
end

local function insets(cf)
    insetPanel(cf, "LeftInset", "ChannelList")
    insetPanel(cf, "RightInset", "ChannelRoster")
end

---------------------------------------------------------------------------
-- Fenetre "Nouveau canal" (CreateChannelPopup, strate DIALOG, UIParent)
---------------------------------------------------------------------------

local function popupDress(p)
    if panels[p] then return end
    panels[p] = true
    local C = ns.COLORS
    -- textures de la fenetre elle-meme : bordure du fond (variante
    -- Classic : BackdropTemplate), bandeau de titre, coin
    fadeOwn(p)
    -- en-tete (DialogHeaderTemplate) et bordure (DialogBorderTemplate)
    local header = field(p, "Header")
    if header then
        fadeOwn(header)
        goldLabel(field(header, "Text"))
    end
    local bg = field(p, "BG")
    if objType(bg) == "Texture" then fade(bg)
    elseif bg then
        fadeOwn(bg)
        fadeOwn(field(bg, "NineSlice"))
    end
    goldLabel(field(p, "Title"))
    -- fond, ombre, bandeau d accent et filet d or
    local bd = backdrop(p, p, 0.96)
    for i = 1, 4 do
        local s = tex(p, "BACKGROUND", -8)
        s:SetPoint("TOPLEFT", bd.fill, "TOPLEFT", -i, i)
        s:SetPoint("BOTTOMRIGHT", bd.fill, "BOTTOMRIGHT", i, -i)
        s:SetColorTexture(0, 0, 0, 0.14)
    end
    local band = tex(p, "BACKGROUND", -6)
    band:SetPoint("TOPLEFT", p, "TOPLEFT", 1, -1)
    band:SetPoint("TOPRIGHT", p, "TOPRIGHT", -1, -1)
    band:SetHeight(22)
    grad(band, C.violet, 0.32, 0.03)
    local line = tex(p, "BACKGROUND", -6)
    line:SetPoint("TOPLEFT", band, "BOTTOMLEFT", 0, 0)
    line:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT", 0, 0)
    line:SetHeight(1)
    grad(line, C.gold, 0.8, 0)
end

---------------------------------------------------------------------------
-- Parcours
---------------------------------------------------------------------------

local skipKids = setmetatable({}, weak)  -- cadres jamais parcourus (tutoriel)
local mainClose                          -- croix de la fenetre : Skins.lua

-- bulle d aide (HelpTipTemplate : OkayButton + Arrow). Blizzard la tire
-- d une reserve commune a toute l interface et la pose sur la fenetre
-- (HelpTip:Show(ChannelFrame...) -> SetParent) : rien de ce qu on y
-- poserait ne doit la suivre dans une autre fenetre
local function isHelpTip(f)
    return field(f, "OkayButton") ~= nil and field(f, "Arrow") ~= nil
end

-- bulle posee en ce moment sur la fenetre (parent relu a chaque appel :
-- rendue a la reserve, elle n est plus a nous)
local function helpTipHere(f)
    if not isHelpTip(f) then return false end
    local cf = rawget(_G, "ChannelFrame")
    return cf ~= nil and rawequal(askObj(f, "GetParent"), cf)
end

-- Communs.lua parcourt la fenetre declaree : ses cases lui reviennent
local function common(f, root)
    if not rawequal(root, rawget(_G, "ChannelFrame")) then return false end
    local ok, k = pcall(ns.SkinCommon, f)
    return ok and k and true or false
end

-- un bouton est une feuille : on ne descend jamais dedans
local function button(b, root)
    local t = objType(b)
    if t == "CheckButton" then
        if not checks[b] and not common(b, root) and askObj(b, "GetCheckedTexture") then skinCheck(b) end
        return
    end
    if field(b, "Collapsed") and field(b, "Text") then
        headerRow(b)
    elseif field(b, "Speaker") and field(b, "Text") then
        channelRow(b)
    elseif field(b, "Rank") and field(b, "Name") and field(b, "SelfMuteButton") then
        memberRow(b)
    elseif isPanelButton(b) then
        panelButton(b)
    elseif not rawequal(b, mainClose) and isCloseButton(b) then
        closeButton(b)
    end
end

local function walk(f, depth, root)
    if depth > MAXDEPTH or mine[f] or skipKids[f] or not visible(f) then return end
    -- bulles d aide (HelpTip) : cadres partages entre toutes les fenetres
    if isHelpTip(f) then return end
    if isScrollBar(f) then
        try("barre", skinScrollBar, f)
        return
    end
    if isOldScrollBar(f) then
        try("ancienne barre", skinOldScrollBar, f)
        return
    end
    local t = objType(f)
    if t == "Button" or t == "CheckButton" then
        try("bouton", button, f, root)
        return
    end
    if t == "EditBox" then
        try("champ", skinEdit, f)
        return
    end
    for _, c in ipairs(childrenOf(f)) do walk(c, depth + 1, root) end
end

local function fullMain(cf)
    mainClose = field(cf, "CloseButton")
    -- lueur du tutoriel (variante Classic : GlowBoxTemplate) : a Blizzard
    local tuto = field(cf, "Tutorial")
    if tuto then skipKids[tuto] = true end
    try("cadres", insets, cf)
    try("titre", rosterTitle, field(cf, "ChannelRoster"))
    walk(cf, 0, cf)
end

local function fullPopup(p)
    try("nouveau canal", popupDress, p)
    walk(p, 0, p)
end

-- releve leger (fenetre ouverte) : textures remises par Blizzard, choix,
-- survol, couleurs
local function light()
    local C = ns.COLORS
    local cf = rawget(_G, "ChannelFrame")
    local list = field(cf, "ChannelList")
    for b, s in pairs(heads) do
        if visible(b) then try("etat en-tete", headState, b, s) end
    end
    for b, s in pairs(chans) do
        if visible(b) then try("etat canal", chanState, b, s, list) end
    end
    for b in pairs(members) do
        if visible(b) then veilRow(b) end
    end
    for _, t in pairs(titles) do try("etat titre", titleState, t) end
    for b, p in pairs(plates) do
        if visible(b) then
            local en = enabled(b)
            local over = en and isOver(b)
            local hot = p.close and RED or C.gold
            paint(p, over and hot or C.border)
            if p.glyph then
                -- Blizzard peut reposer la texture d etat (atlas rouges)
                fadeStates(b, CLOSE_STATES)
                local c = over and hot or C.text
                p.glyph:SetTextColor(c[1], c[2], c[3])
                p.glyph:SetAlpha(en and 1 or 0.35)
            end
        end
    end
    for cb, k in pairs(checks) do
        if visible(cb) then
            fadeStates(cb, CHECK_STATES)
            local en = enabled(cb)
            k.mark:SetShown(ask(cb, "GetChecked") == true)
            k.mark:SetAlpha(en and 1 or 0.4)
            local over = en and isOver(cb)
            paint(k, over and C.gold or C.border)
            if k.label then
                local c = over and WHITE or C.text
                local m = en and 1 or 0.5
                pcall(k.label.SetTextColor, k.label, c[1] * m, c[2] * m, c[3] * m)
            end
        end
    end
    for e, k in pairs(edits) do
        if visible(e) then
            if ask(e, "HasFocus") == true then paint(k, C.gold)
            elseif isOver(e) then paint(k, C.violet)
            else paint(k, C.border) end
        end
    end
    for t in pairs(tints) do
        if visible(t) then
            pcall(t.SetDesaturated, t, true)
            pcall(t.SetVertexColor, t, C.gold[1], C.gold[2], C.gold[3], 1)
        end
    end
    for fs in pairs(labels) do
        if visible(fs) then pcall(fs.SetTextColor, fs, C.gold[1], C.gold[2], C.gold[3]) end
    end
    for sb, b in pairs(bars) do
        if b.knob and visible(sb) then
            if b.ref then b.knob:SetShown(shown(b.ref)) end
            if isOver(b.thumb) then
                b.knob:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.9)
            else
                b.knob:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.6)
            end
        end
    end
end

-- Skins.lua / Communs.lua : ne pas aplatir nos cadres, ne pas effacer nos
-- textures. La bulle d aide posee sur la fenetre et la lueur du tutoriel
-- (variante Classic) sont aussi reclamees pour que Skins.lua n y descende
-- pas, quelle que soit la profondeur declaree : sinon il aplatit le bouton
-- OK de la bulle (UIPanelButtonTemplate), et la plaque resterait sur ce
-- cadre recycle par la reserve dans une autre fenetre
local prevClaimed = ns.SkinClaimed
function ns.SkinClaimed(f)
    if type(f) == "table" and (claimed[f] or skipKids[f] or helpTipHere(f)) then return true end
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

-- fenetres reprises : la fenetre (Blizzard_Channels, chargee a la demande)
-- et la fenetre "Nouveau canal", posee sur UIParent
local ROOTS = {
    { "ChannelFrame", fullMain },
    { "CreateChannelPopup", fullPopup },
}
local state = {}     -- nom -> { shown, last }
local acc = 0

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if ns.ModuleOff("habillage", ev) then return end
    -- fin du combat : les fenetres ouvertes sont reparcourues tout de suite
    if event == "PLAYER_REGEN_ENABLED" then
        for _, st in pairs(state) do st.shown = false end
    end
end)
pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")

ev:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < TICK then return end
    acc = 0
    if not db() or InCombatLockdown() then return end
    local now = GetTime()
    local any = false
    for _, spec in ipairs(ROOTS) do
        local name, full = spec[1], spec[2]
        local f = rawget(_G, name)
        local st = state[name]
        if not st then
            st = {}
            state[name] = st
        end
        if type(f) == "table" and f.CreateTexture and visible(f) then
            any = true
            if not st.shown or now - (st.last or 0) >= WALK then
                st.shown, st.last = true, now
                try(name, full, f)
            end
        else
            st.shown = false
        end
    end
    if any then try("releve", light) end
end)
