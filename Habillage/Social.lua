--[[--------------------------------------------------------------------------
    CorpUI - module Habillage : contacts en profondeur
    (SocialUIFrame de Blizzard_SocialUI, famille Mainline chargee par ce
    client Camelot ; vues fournies par Blizzard_FriendsFrame,
    Blizzard_RecentAllies, Blizzard_QuickJoin, Blizzard_RecruitAFriend et
    Blizzard_RaidFrame ; dialogues de Blizzard_AddFriend)

    Skins.lua pose le cadre exterieur (fond, lisere, bandeau, titre or,
    croix plate, portrait cache) et aplatit les boutons rouges a sa portee
    une fois la fenetre declaree dans Fenetres.lua ; ici l interieur :
      - onglets lateraux (contacts, allies recents, groupes rapides,
        demandes d ami, recrutement, raid) : tuile carree sur un rail sombre
        colle a la fenetre, icone de l onglet reprise de son atlas (grisee
        si l onglet est desactive), lisere et barre d or pour l actif,
        lisere qui pulse quand Blizzard fait luire l onglet ;
      - barre Battle.net : bandeau sombre a filet d or, BattleTag dans un
        champ plat (couleurs du BattleTag gardees) pose a cote du menu de
        statut, dont le champ est a Communs.lua (pas de double cadre),
        bouton menu en plaque carree ;
      - recherche + Filtrer : champ sombre a lisere (or au focus, loupe en
        or), Filtrer en plaque plate a chevron d or (or menu ouvert) ;
      - listes : panneau sombre, filets d or a la place des separateurs,
        en-tetes repliables en degrade + filet d or (titre or, +/- or),
        cartes (amis, demandes, allies recents, recrues, groupes rapides)
        en plaques plates : bande de couleur a gauche (or : ami du jeu,
        bleu : Battle.net, gris : hors ligne, accent : groupe rapide),
        lisere or au survol, degrade d accent + lisere or pour la carte
        choisie ; icones de statut, couleurs de classe et textes gardes ;
        boutons d action (inviter, appel RAF, accepter, refuser) en plaques ;
      - raid : groupes en panneaux a bandeau (titre or), membres en lignes
        plates (couleur de classe / hors ligne / mort gardee) ;
      - fenetres de cote (ignores, infos de raid, annonce Battle.net,
        Battle.net indisponible) et dialogues annexes (ajout d ami,
        invitation BattleTag, amis d un ami) : fond, ombre, bandeau, titre
        or, croix plate, champs habilles, lignes plates a selection or.
    Les decors sont reconnus par leur atlas ou leur nom de champ, jamais
    detruits.

    Regles de ce client (valeurs secretes, taint) : ces fenetres declenchent
    des actions sensibles (ajouter / retirer un ami, inviter, bloquer, menus
    de joueur, membres de raid securises), donc habillage = textures :
      - aucun crochet, aucun SetScript, aucune fonction Lua de Blizzard
        appelee : seulement des methodes du moteur, et jamais une methode
        posee dans la table du cadre (celle d un mixin, meme si elle porte
        le nom d une methode du moteur) ;
      - aucun champ ecrit chez Blizzard (lignes recyclees, boutons) : notre
        etat est range dans des tables faibles a nous, indexees par le cadre ;
      - aucune taille, position, strate, niveau, parent, souris ni
        visibilite de Blizzard modifiee : l alpha, la couleur, la
        desaturation de LEURS textures, la couleur (jamais la police, la
        taille ni l ombre) de quelques titres decoratifs, et nos propres
        textures / textes poses dessus. Une
        texture dont Blizzard pilote l alpha (lueur d onglet, survol des
        groupes rapides) est eteinte par la couleur, jamais par l alpha ;
      - les cadres a taille calculee sur leurs regions (ResizeLayoutFrame :
        ajout d ami, annonce, Battle.net indisponible) recoivent nos
        textures sur leur bordure (cadre enfant a leur taille), jamais sur
        eux-memes : elles fausseraient leur calcul ;
      - les couleurs d information (classe, en ligne / absent / occupe /
        hors ligne, BattleTag, Battle.net en bleu, desactive) sont gardees ;
      - rien en combat ; toute valeur lue est verifiee (pcall, issecretvalue).
    Partage : ns.SkinClaimed (Skins.lua n aplatit pas nos cadres),
    ns.SkinOwned (nos textures ne sont jamais eteintes), ns.SkinCommon
    (menus a fleche et cases a cocher restent a Communs.lua).
    Diagnostic : la premiere erreur de la session, avec le nom de l etape,
    est gardee dans CorpUIDB.skins.errors.Social.
----------------------------------------------------------------------------]]

local _, ns = ...

local issecret = issecretvalue or function() return false end
local weak = { __mode = "k" }

local mine = setmetatable({}, weak)      -- nos regions (a ne jamais traiter)
local done = setmetatable({}, weak)      -- textures de Blizzard deja traitees (atlas)
local claimed = setmetatable({}, weak)   -- cadres que Skins.lua ne doit pas aplatir
local plates = setmetatable({}, weak)    -- bouton aplati -> { fill, edges, hl, glyph, chev... }
local bars = setmetatable({}, weak)      -- barre de defilement -> { thumb, knob }
local edits = setmetatable({}, weak)     -- champ de saisie -> { fill, edges, glass }
local tabs = setmetatable({}, weak)      -- onglet lateral -> { fill, accent, icon, edges, bar }
local rails = setmetatable({}, weak)     -- parent des onglets -> { fill, edges }
local cards = setmetatable({}, weak)     -- carte (ami, demande, allie, recrue, groupe, raid)
local rows = setmetatable({}, weak)      -- ligne simple (ignores, infos de raid, amis d un ami)
local heads = setmetatable({}, weak)     -- en-tete repliable -> { fill, line, text, collapse }
local bands = setmetatable({}, weak)     -- texture de Blizzard -> nos textures (suivent son affichage)
local labels = setmetatable({}, weak)    -- titre passe en or (couleur seule) -> { fs }
local panels = setmetatable({}, weak)    -- cadre deja habille (panneau, dialogue, groupe)

local WHITE = { 1, 1, 1 }
local RED = { 1, 0.3, 0.3 }
local BNET = { 0.51, 0.77, 1 }
local GREY = { 0.45, 0.45, 0.48 }

-- textures de Blizzard reconnues par leur atlas
local ATLAS = {
    ["friends-frame-infobg"] = "fade",        -- fond de la barre Battle.net
    ["friends-frame-toptexbg"] = "fade",
    ["friends-frame-bottomtexbg"] = "fade",
    ["friends-card-raidBG"] = "fade",         -- fond d un groupe de raid
    ["perks-divider-short"] = "divider",      -- separateurs des listes
    -- (la loupe du champ de recherche est teintee par son champ, selon le focus)
    ["common-searchbar-a"] = "fade",
    ["_UI-Frame-DiamondMetal-EdgeTop"] = "fade",
    ["friends-RAF-headerBG"] = "rafband",     -- en-tete du recrutement (+ son filigrane)
}
-- bordure a neuf morceaux d un champ (annonce Battle.net)
local BORDER9 = { "TopLeftBorder", "TopRightBorder", "TopBorder", "BottomLeftBorder", "BottomRightBorder",
                  "BottomBorder", "LeftBorder", "RightBorder", "MiddleBorder" }

local function db()
    local d = ns.skinsDB
    if type(d) ~= "table" or not d.enabled then return nil end
    if d.groups and d.groups.social == false then return nil end
    return d
end

-- pcall qui garde la premiere erreur de la session (avec le nom de
-- l etape) dans CorpUIDB.skins.errors.Social (remis a zero par Skins.lua
-- a chaque connexion)
local function try(tag, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        local d = ns.skinsDB
        if type(d) == "table" then
            d.errors = d.errors or {}
            if not d.errors.Social then
                local okS, s = pcall(function() return tag .. ": " .. tostring(err) end)
                d.errors.Social = (okS and type(s) == "string" and not issecret(s)) and s or tag
            end
        end
    end
    return ok
end

---------------------------------------------------------------------------
-- Outils (lectures protegees, methodes du moteur seulement)
---------------------------------------------------------------------------

local function get(o, k) return o[k] end

-- methode du moteur (metatable du cadre) ; une methode posee dans la table
-- elle-meme vient d un mixin (Lua de Blizzard) : jamais appelee
local function engine(o, m)
    if type(o) ~= "table" then return nil end
    local okR, raw = pcall(rawget, o, m)
    if not okR or raw ~= nil then return nil end
    local ok, fn = pcall(get, o, m)
    if ok and type(fn) == "function" then return fn end
end

-- premier resultat simple d un accesseur du moteur, jamais secret
local function ask(o, m, ...)
    local fn = engine(o, m)
    if not fn then return nil end
    local ok, v = pcall(fn, o, ...)
    if not ok or v == nil or issecret(v) then return nil end
    local t = type(v)
    if t == "string" or t == "number" or t == "boolean" then return v end
end

-- objet rendu par un accesseur du moteur (GetNormalTexture...)
local function askObj(o, m)
    local fn = engine(o, m)
    if not fn then return nil end
    local ok, v = pcall(fn, o)
    if ok and type(v) == "table" then return v end
end

-- reglage d apparence sur un objet de Blizzard (alpha, couleur...)
local function set(o, m, ...)
    local fn = engine(o, m)
    if not fn then return false end
    return (pcall(fn, o, ...))
end

local function objType(o)
    local t = ask(o, "GetObjectType")
    if type(t) == "string" then return t end
end

-- champ table d un cadre de Blizzard (lecture seule)
local function field(f, key)
    if type(f) ~= "table" then return nil end
    local ok, c = pcall(get, f, key)
    if ok and type(c) == "table" then return c end
end

-- champ simple (texte, nombre, booleen), jamais secret
local function value(f, key)
    if type(f) ~= "table" then return nil end
    local ok, v = pcall(get, f, key)
    if not ok or v == nil or issecret(v) then return nil end
    local t = type(v)
    if t == "string" or t == "number" or t == "boolean" then return v end
end

local function num(v)
    if type(v) == "number" and not issecret(v) then return v end
end

local function visible(f) return ask(f, "IsVisible") == true end
local function shown(f) return ask(f, "IsShown") == true end
local function isOver(f) return ask(f, "IsMouseOver") == true end
local function enabled(f) return ask(f, "IsEnabled") ~= false end
-- carte ou ligne choisie : Blizzard verrouille son survol (SetHighlightLocked)
local function locked(f) return ask(f, "IsHighlightLocked") == true end

local function pack(fn, o) return { fn(o) } end

local function regionsOf(f)
    local fn = engine(f, "GetRegions")
    if not fn then return {} end
    local ok, list = pcall(pack, fn, f)
    return ok and list or {}
end

local function childrenOf(f)
    local fn = engine(f, "GetChildren")
    if not fn then return {} end
    local ok, list = pcall(pack, fn, f)
    return ok and list or {}
end

local function parentOf(f) return askObj(f, "GetParent") end

local function atlasOf(t)
    if objType(t) ~= "Texture" then return nil end
    local a = ask(t, "GetAtlas")
    if type(a) == "string" then return a end
end

local function layoutOf(f)
    local v = value(f, "layoutType")
    if type(v) == "string" then return v end
end

-- cadre a taille calculee sur ses regions (BaseLayoutMixin pose la
-- fonction IsLayoutFrame dans la table du cadre) : lu, jamais appele
local function layoutFrame(f)
    if type(f) ~= "table" then return false end
    local ok, v = pcall(rawget, f, "IsLayoutFrame")
    return ok and type(v) == "function"
end

-- texture de Blizzard a alpha 0 (seulement si besoin : releve frequent)
local function fade(t)
    if objType(t) ~= "Texture" or mine[t] then return end
    if ask(t, "GetAlpha") ~= 0 then set(t, "SetAlpha", 0) end
end

-- texture dont Blizzard pilote l alpha (animation, survol) : eteinte par
-- la couleur, jamais par l alpha (vu en jeu : clignotement sinon)
local function veil(t)
    if objType(t) ~= "Texture" or mine[t] then return end
    local fn = engine(t, "GetVertexColor")
    if fn then
        local ok, _, _, _, a = pcall(fn, t)
        if ok and a ~= nil and not issecret(a) and a == 0 then return end
    end
    set(t, "SetVertexColor", 1, 1, 1, 0)
end

local function tintGold(t, k)
    local C = ns.COLORS
    k = k or 1
    set(t, "SetDesaturated", true)
    set(t, "SetVertexColor", C.gold[1] * k, C.gold[2] * k, C.gold[3] * k, 1)
end

-- texture posee par un fichier de CorpUI (ce fichier ou un autre habillage)
local function owned(r)
    if mine[r] then return true end
    if not ns.SkinOwned then return false end
    local ok, v = pcall(ns.SkinOwned, r)
    return ok and v == true
end

-- textures d un cadre (pas celles de ses enfants), sauf celles de CorpUI
local function fadeOwn(f)
    for _, r in ipairs(regionsOf(f)) do
        if objType(r) == "Texture" and not owned(r) then fade(r) end
    end
end

-- textures d etat d un bouton
local STATES = { "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }
local function fadeStates(b, list)
    for _, m in ipairs(list or STATES) do fade(askObj(b, m)) end
end

local function tex(host, layer, sub)
    local fn = engine(host, "CreateTexture")
    local t = fn(host, nil, layer, nil, sub)
    mine[t] = true
    return t
end

local function text(host, size)
    local fn = engine(host, "CreateFontString")
    local fs = fn(host, nil, "OVERLAY")
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

local function paintC(list, c, a)
    for _, x in ipairs(list) do x:SetColorTexture(c[1], c[2], c[3], a or 1) end
end

local function showAll(list, on)
    for _, x in ipairs(list) do x:SetShown(on) end
end

local function grad(t, c, a1, a2, orient)
    ns.UI.Gradient(t, orient or "HORIZONTAL", c[1], c[2], c[3], a1, c[1], c[2], c[3], a2)
end

-- filet d or de 1 px, plus clair au centre, le long d un cote de "anchor"
-- (BOTTOM : sous le bord bas ; MID : sur l axe horizontal)
local function goldRule(host, anchor, where, layer, sub)
    local C = ns.COLORS
    local l, r = tex(host, layer, sub), tex(host, layer, sub)
    l:SetHeight(1)
    r:SetHeight(1)
    if where == "MID" then
        l:SetPoint("LEFT", anchor, "LEFT", 0, 0)
        l:SetPoint("RIGHT", anchor, "CENTER", 0, 0)
        r:SetPoint("LEFT", anchor, "CENTER", 0, 0)
        r:SetPoint("RIGHT", anchor, "RIGHT", 0, 0)
    else
        l:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)
        l:SetPoint("BOTTOMRIGHT", anchor, "BOTTOM", 0, 0)
        r:SetPoint("BOTTOMLEFT", anchor, "BOTTOM", 0, 0)
        r:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
    end
    grad(l, C.gold, 0, 0.75)
    grad(r, C.gold, 0.75, 0)
    return { l, r }
end

-- panneau sombre (fond, lisere) sur "host", aux dimensions de "anchor" ;
-- "sub" : sous-niveau du fond (defaut -8), le lisere juste au-dessus
local function backdrop(host, anchor, alpha, sub)
    local C = ns.COLORS
    sub = sub or -8
    local fill = tex(host, "BACKGROUND", sub)
    fill:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    fill:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
    fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], alpha or 0.75)
    local edges = ring(host, fill, "BACKGROUND", sub + 1, 0)
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
    return { band, line }
end

-- titre decoratif de Blizzard passe en or : la COULEUR seulement (seul
-- reglage permis sur leurs textes) ; police, taille et ombre de Blizzard
-- gardees (pas de SetFont / SetShadow* sur un texte de Blizzard)
local function goldFont(fs)
    if objType(fs) ~= "FontString" then return nil end
    local C = ns.COLORS
    set(fs, "SetTextColor", C.gold[1], C.gold[2], C.gold[3])
    return { fs = fs }
end

local function keepGold(h)
    if not h or not h.fs then return end
    local C = ns.COLORS
    set(h.fs, "SetTextColor", C.gold[1], C.gold[2], C.gold[3])
end

local function titleGold(fs)
    if objType(fs) ~= "FontString" or labels[fs] then return end
    local h = goldFont(fs)
    if h then labels[fs] = h end
end

local function common(f)
    if not ns.SkinCommon then return false end
    local ok, v = pcall(ns.SkinCommon, f)
    return ok and v and true or false
end

---------------------------------------------------------------------------
-- Boutons, champs, barres
---------------------------------------------------------------------------

-- plaque plate sous un bouton (textures a nous, au fond du bouton) ;
-- "square" : carre centre de ce cote (boutons d action des cartes)
local function plate(b, inset, square)
    if plates[b] then return plates[b] end
    local C = ns.COLORS
    local p = {}
    p.fill = tex(b, "BACKGROUND", -8)
    if square then
        p.fill:SetSize(square, square)
        p.fill:SetPoint("CENTER", b, "CENTER", 0, 0)
    else
        p.fill:SetPoint("TOPLEFT", b, "TOPLEFT", inset, -inset)
        p.fill:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -inset, inset)
    end
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

-- cote d un bouton carre : 8 px de moins que le bouton (art de Blizzard
-- de 34 px dont le carre visible fait ~26 px), 18 a 30 px
local function squareSide(b)
    local w, h = num(ask(b, "GetWidth")), num(ask(b, "GetHeight"))
    local side = 26
    if w and h then side = math.max(18, math.min(30, math.floor(math.min(w, h)) - 8)) end
    return side
end

-- bouton d action carre (inviter, appel RAF, menu Battle.net) : son art
-- (common-button-tertiary-square-*) a alpha 0, plaque carree, icone gardee
local function squareButton(b)
    if plates[b] then return end
    fadeStates(b)
    local p = plate(b, 0, squareSide(b))
    p.states = STATES
    p.drop = objType(b) == "DropdownButton"
end

-- bouton a texte sur art "tertiaire" (Accepter une demande d ami)
local function flatButton(b)
    if plates[b] then return end
    fadeStates(b)
    local p = plate(b, 4)
    p.states = STATES
end

-- bouton a signe (croix des fenetres de cote, refus d une demande, remise
-- a zero des filtres)
local function glyphButton(b, glyph, size, inset, color, isClose)
    if plates[b] and plates[b].glyph then return end
    fadeStates(b)
    local p = plate(b, inset or 2)
    p.glyph = text(b, size or 12)
    p.glyph:SetPoint("CENTER", 0, 0)
    p.glyph:SetText(glyph)
    p.color = color
    p.close = isClose
    p.states = STATES
    p.drop = objType(b) == "DropdownButton"
    local c = color or ns.COLORS.gold
    p.glyph:SetTextColor(c[1], c[2], c[3])
end

-- bouton rouge (Left/Middle/Right ou Left/Center/Right) que Skins.lua
-- n atteint pas (trop profond, dialogue annexe, sous un cadre reclame)
local function isPanelButton(b)
    return objType(field(b, "Left")) == "Texture" and objType(field(b, "Right")) == "Texture"
        and (objType(field(b, "Middle")) == "Texture" or objType(field(b, "Center")) == "Texture")
end

local function panelButton(b)
    if plates[b] then return end
    fade(field(b, "Left"))
    fade(field(b, "Middle") or field(b, "Center"))
    fade(field(b, "Right"))
    fadeStates(b, { "GetHighlightTexture" })
    plate(b, 1)
end

-- bouton a textures simples (AddFriendButtonTemplate : UI-DialogBox-Button)
local function isTexturedButton(b)
    if objType(b) ~= "Button" or field(b, "Left") or field(b, "Icon") then return false end
    local n = askObj(b, "GetNormalTexture")
    if objType(n) ~= "Texture" or atlasOf(n) then return false end
    return objType(askObj(b, "GetFontString")) == "FontString"
end

local function textureButton(b)
    if plates[b] then return end
    fadeStates(b)
    local p = plate(b, 1)
    p.states = STATES
end

-- chevron d or des menus de CorpUI (recette de ns.UI.Select et de
-- Communs.lua) : deux barres de 6 x 2 px pivotees
local function chevron(b, point, x)
    local list = {}
    for i, rot in ipairs({ -math.pi / 4, math.pi / 4 }) do
        local t = tex(b, "OVERLAY", 7)
        t:SetSize(6, 2)
        t:SetPoint("CENTER", b, point, x + (i == 1 and -2 or 2), 0)
        pcall(t.SetRotation, t, rot)
        list[i] = t
    end
    return list
end

-- bouton Filtrer (WowStyle1FilterDropdownTemplate : Background
-- common-dropdown-b-button*, atlas change a chaque etat, alpha jamais)
local function filterDrop(b, bg)
    if plates[b] then return end
    fade(bg)
    local p = plate(b, 1)
    p.bg = bg
    p.drop = true
    p.chev = chevron(b, "RIGHT", -12)
end

-- champ de recherche (SearchBoxNineSliceTemplate)
local function searchBox(e)
    if edits[e] then return end
    fade(field(e, "Background"))
    local C = ns.COLORS
    local fill = tex(e, "BACKGROUND", -8)
    fill:SetPoint("TOPLEFT", e, "TOPLEFT", 0, 0)
    fill:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT", 0, 0)
    fill:SetColorTexture(0, 0, 0, 0.55)
    local edges = ring(e, fill, "BACKGROUND", -7, 0)
    paintC(edges, C.border)
    local glass = field(e, "searchIcon")
    edits[e] = { fill = fill, edges = edges, glass = objType(glass) == "Texture" and glass or nil }
    claimed[e] = true
end

-- champ a bordure de Blizzard : neuf morceaux (annonce Battle.net) ou
-- Left / Right / Middle (ajout d ami : Middle n a qu un nom global)
local function borderEdit(e)
    if edits[e] then return end
    local nine = false
    for _, k in ipairs(BORDER9) do
        if objType(field(e, k)) == "Texture" then nine = true end
    end
    local l, r = field(e, "Left"), field(e, "Right")
    if not nine and not (objType(l) == "Texture" and objType(r) == "Texture") then return end
    local C = ns.COLORS
    local fill = tex(e, "BACKGROUND", -8)
    if nine then
        for _, k in ipairs(BORDER9) do fade(field(e, k)) end
        fill:SetPoint("TOPLEFT", e, "TOPLEFT", -4, 4)
        fill:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT", 4, -3)
    else
        fade(l) fade(r)
        fade(field(e, "Middle"))
        fade(field(e, "Mid"))
        local name = ask(e, "GetName")
        if type(name) == "string" then fade(rawget(_G, name .. "Middle")) end
        fill:SetPoint("TOPLEFT", e, "TOPLEFT", -5, 0)
        fill:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT", -5, 0)
    end
    fill:SetColorTexture(0, 0, 0, 0.55)
    local edges = ring(e, fill, "BACKGROUND", -7, 0)
    paintC(edges, C.border)
    edits[e] = { fill = fill, edges = edges }
    claimed[e] = true
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
    if not (engine(track, "CreateTexture") and engine(thumb, "CreateTexture")) then return end
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
    local knob = tex(thumb, "ARTWORK", 2)
    knob:SetPoint("TOP", thumb, "TOP", 0, 0)
    knob:SetPoint("BOTTOM", thumb, "BOTTOM", 0, 0)
    knob:SetWidth(4)
    knob:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.6)
    for _, k in ipairs({ "Back", "Forward" }) do
        local t = field(field(sb, k), "Texture")
        if objType(t) == "Texture" then set(t, "SetVertexColor", C.violet[1], C.violet[2], C.violet[3], 0.8) end
    end
    bars[sb] = { thumb = thumb, knob = knob }
end

---------------------------------------------------------------------------
-- Onglets lateraux (SocialUITabTemplate / LargeSideTabButtonTemplate)
---------------------------------------------------------------------------

-- Recette du rail de la fiche perso (Personnage.lua) : tuile carree collee
-- a la fenetre, icone a nous reprise de l atlas de Blizzard (son icone,
-- masquee en rond et deplacee a chaque clic, passe a alpha 0). La lueur
-- d aide (animation d alpha) est eteinte par la couleur ; notre lisere
-- pulse a sa place.
local function railFor(parent)
    if rails[parent] then return rails[parent] end
    if not engine(parent, "CreateTexture") then return nil end
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
    for _, k in ipairs({ "Background", "SelectedTexture", "HighlightTexture" }) do fade(field(t, k)) end
    fadeStates(t, { "GetHighlightTexture" })
    veil(field(t, "TabGlow"))
    fade(icon)
    local C = ns.COLORS
    local h = num(ask(t, "GetHeight")) or 50
    local size = math.max(28, math.min(46, math.floor(h) - 8))
    local s = { ref = icon, size = size }
    s.fill = tex(t, "BACKGROUND", -6)
    s.fill:SetSize(size, size)
    s.fill:SetPoint("LEFT", t, "LEFT", 4, 0)
    s.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 1)
    s.accent = tex(t, "BACKGROUND", -5)
    s.accent:SetAllPoints(s.fill)
    grad(s.accent, C.violet, 0.35, 0.05)
    s.accent:Hide()
    -- sous le compteur de Blizzard (texte ARTWORK des groupes rapides)
    s.icon = tex(t, "BORDER", 1)
    s.icon:SetSize(size - 6, size - 6)
    s.icon:SetPoint("CENTER", s.fill, "CENTER", 0, 0)
    s.lift = 0
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

-- icone : l atlas actif / inactif choisi par Blizzard, grisee si l onglet
-- est desactive (raid en mode histoire) ; remontee si un compteur s affiche
local function syncTabIcon(t, s)
    local a = atlasOf(s.ref)
    if a and a ~= s.atlas then
        s.atlas = a
        s.icon:SetAtlas(a, false)
    end
    s.icon:SetDesaturated(not enabled(t))
    local lift = shown(field(t, "Count")) and 4 or 0
    if lift ~= s.lift then
        s.lift = lift
        s.icon:ClearAllPoints()
        s.icon:SetPoint("CENTER", s.fill, "CENTER", 0, lift)
    end
end

local function tabState(t, s)
    local C = ns.COLORS
    syncTabIcon(t, s)
    veil(field(t, "TabGlow"))
    local active = shown(field(t, "SelectedTexture"))
    local over = isOver(t)
    local glowing = ask(field(t, "TabGlowAnimation"), "IsPlaying") == true
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
    local v = (active or over) and 1 or 0.7
    s.icon:SetVertexColor(v, v, v, 1)
end

-- un rail par groupe d onglets (meme parent), sous les onglets visibles
local function placeRails()
    local spans = {}
    for t, s in pairs(tabs) do
        if visible(t) then
            local p = parentOf(t)
            local top = num(ask(t, "GetTop"))
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
            r.fill:SetPoint("BOTTOMLEFT", sp.last.s.fill, "BOTTOMLEFT", -4, -4)
            r.fill:SetWidth(sp.first.s.size + 8)
        end
    end
end

---------------------------------------------------------------------------
-- Barre Battle.net, listes, en-tetes, cartes
---------------------------------------------------------------------------

-- bandeau sous le titre (BattleTag, statut, menu) : fond de Blizzard a
-- alpha 0, bande sombre a filet d or ; la pastille du BattleTag devient
-- un champ plat qui suit son affichage (cachee sans Battle.net).
-- La pastille de Blizzard commence SOUS le menu de statut, qui a deja son
-- champ (pose par Communs.lua, 1 px en retrait du menu) : notre champ part
-- 2 px apres le menu, a sa hauteur (meme retrait de 1 px), jusqu au bout de
-- la pastille. Deux plaques cote a cote (statut | BattleTag), sans double
-- cadre ni double fond sur le statut.
local function bnetPill(cc, pill)
    local f = tex(cc, "BACKGROUND", -8)
    local dd = field(cc, "OnlineStatusDropdown")
    if dd and engine(dd, "GetRight") then
        -- haut et bas : ceux du menu ; droite : celle de la pastille
        f:SetPoint("TOPLEFT", dd, "TOPRIGHT", 2, -1)
        f:SetPoint("BOTTOMLEFT", dd, "BOTTOMRIGHT", 2, 1)
        f:SetPoint("RIGHT", pill, "RIGHT", 0, 0)
    else
        f:SetPoint("TOPLEFT", pill, "TOPLEFT", 0, -1)
        f:SetPoint("BOTTOMRIGHT", pill, "BOTTOMRIGHT", 0, 1)
    end
    return f
end

local function bnetBar(bar, root)
    if panels[bar] or not engine(bar, "CreateTexture") then return end
    panels[bar] = true
    fade(field(bar, "Background"))
    local C = ns.COLORS
    local strip = tex(bar, "BACKGROUND", -8)
    strip:SetPoint("TOPLEFT", root, "TOPLEFT", 2, -24)
    strip:SetPoint("RIGHT", root, "RIGHT", -2, 0)
    strip:SetPoint("BOTTOM", bar, "BOTTOM", 0, 6)
    strip:SetColorTexture(0, 0, 0, 0.28)
    goldRule(bar, strip, "BOTTOM", "BACKGROUND", -7)
    local cc = field(bar, "ControlsContainer")
    local pill = field(cc, "BattleNetBackground")
    if objType(pill) == "Texture" and engine(cc, "CreateTexture") then
        fade(pill)
        local f = bnetPill(cc, pill)
        f:SetColorTexture(0, 0, 0, 0.5)
        local parts = { f }
        local edges = ring(cc, f, "BACKGROUND", -7, 0)
        paintC(edges, C.border)
        for _, x in ipairs(edges) do parts[#parts + 1] = x end
        bands[pill] = { parts = parts }
    end
end

-- separateur (perks-divider-short) : filet d or plus clair au centre
local function divider(t, host)
    if bands[t] or not engine(host, "CreateTexture") then return end
    fade(t)
    bands[t] = { parts = goldRule(host, t, "MID", "BORDER", 2) }
end

-- en-tete du recrutement (friends-RAF-headerBG, atlas fixe) : panneau
-- sombre a filet. Son filigrane (champ Watermark) est reconnu par son champ,
-- pas par son atlas : RewardClaimingMixin:UpdateNextReward le remplace
-- (recruitafriend_V2/V3_watermark_medium) des que les infos de recrutement
-- arrivent ; Blizzard ne fait que Show / Hide dessus, l alpha 0 tient.
local function rafBand(t, host)
    if bands[t] or not engine(host, "CreateTexture") then return end
    fade(t)
    fade(field(host, "Watermark"))
    local C = ns.COLORS
    local fill = tex(host, "BACKGROUND", -8)
    fill:SetPoint("TOPLEFT", t, "TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -2, 2)
    grad(fill, C.violet, 0.22, 0.03)
    local parts = { fill }
    for _, x in ipairs(goldRule(host, fill, "BOTTOM", "BACKGROUND", -7)) do parts[#parts + 1] = x end
    bands[t] = { parts = parts }
end

-- bandeau d en-tete pose sur une texture de Blizzard (colonnes des infos
-- de raid) : degrade + filet d or, suit son affichage
local function bandOn(host, ref)
    if bands[ref] or objType(ref) ~= "Texture" then return end
    local C = ns.COLORS
    fade(ref)
    local fill = tex(host, "BACKGROUND", -6)
    fill:SetPoint("TOPLEFT", ref, "TOPLEFT", 0, 0)
    fill:SetPoint("BOTTOMRIGHT", ref, "BOTTOMRIGHT", 0, 0)
    grad(fill, C.violet, 0.30, 0.03)
    local line = tex(host, "BACKGROUND", -6)
    line:SetPoint("TOPLEFT", fill, "BOTTOMLEFT")
    line:SetPoint("TOPRIGHT", fill, "BOTTOMRIGHT")
    line:SetHeight(1)
    grad(line, C.gold, 0.8, 0)
    bands[ref] = { parts = { fill, line } }
end

-- vue a liste (SocialUIContactsFrameTemplate : contacts, demandes, allies
-- recents, groupes rapides, recrutement) : panneau sombre sous la liste
local function contactsPanel(cf)
    if panels[cf] then return end
    local sb = field(cf, "ScrollBox")
    if not sb or not engine(cf, "CreateTexture") then return end
    panels[cf] = true
    local C = ns.COLORS
    local fill = tex(cf, "BACKGROUND", -8)
    fill:SetPoint("TOPLEFT", sb, "TOPLEFT", 4, -1)
    fill:SetPoint("BOTTOMLEFT", sb, "BOTTOMLEFT", 4, 1)
    fill:SetPoint("RIGHT", cf, "RIGHT", -4, 0)
    fill:SetColorTexture(0, 0, 0, 0.32)
    paintC(ring(cf, fill, "BACKGROUND", -7, 0), C.border)
end

-- en-tete repliable (SocialUIScrollableHeaderTemplate : "Liste de
-- contacts : 0/1"...) : barre grise a alpha 0, degrade + filet d or, titre
-- or (blanc au survol, Blizzard ne relit pas sa couleur), +/- en or
local function header(h)
    if heads[h] then return end
    fadeStates(h, { "GetNormalTexture", "GetHighlightTexture", "GetPushedTexture" })
    local C = ns.COLORS
    local s = {}
    s.fill = tex(h, "BACKGROUND", -8)
    s.fill:SetPoint("TOPLEFT", h, "TOPLEFT", 0, -1)
    s.fill:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 1)
    grad(s.fill, C.violet, 0.32, 0.04)
    s.line = tex(h, "BACKGROUND", -7)
    s.line:SetPoint("BOTTOMLEFT", s.fill, "BOTTOMLEFT")
    s.line:SetPoint("BOTTOMRIGHT", s.fill, "BOTTOMRIGHT")
    s.line:SetHeight(1)
    grad(s.line, C.gold, 0.8, 0)
    s.hl = tex(h, "HIGHLIGHT")
    s.hl:SetAllPoints(s.fill)
    grad(s.hl, C.violet, 0.22, 0.02)
    local fs = field(h, "ButtonText")
    s.text = objType(fs) == "FontString" and fs or nil
    s.collapse = field(h, "CollapseButton")
    heads[h] = s
    claimed[h] = true
end

local function headState(h, s)
    local C = ns.COLORS
    if s.text then
        local c = isOver(h) and WHITE or C.gold
        set(s.text, "SetTextColor", c[1], c[2], c[3])
    end
    -- +/- : CollapseButtonMixin repose l atlas de l icone et du survol
    if s.collapse then
        tintGold(field(s.collapse, "Icon"))
        tintGold(askObj(s.collapse, "GetHighlightTexture"))
    end
end

-- en-tete simple (liste des ignores : cadre a texte seul)
local function listHeader(f)
    if panels[f] or not engine(f, "CreateTexture") then return end
    panels[f] = true
    local C = ns.COLORS
    local fill = tex(f, "BACKGROUND", -8)
    fill:SetAllPoints(f)
    grad(fill, C.violet, 0.30, 0.03)
    local line = tex(f, "BACKGROUND", -7)
    line:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT")
    line:SetHeight(1)
    grad(line, C.gold, 0.8, 0)
    titleGold(field(f, "Text"))
end

-- type de carte d apres l atlas de son fond
local function cardKind(a)
    if a:find("^friends%-card%-raid") and not a:find("raidBG", 1, true) then return "raid" end
    if a:find("quickJoin", 1, true) then return "quick" end
    return "card"
end

-- carte : fond friends-card-* et survol friends-card-selected a alpha 0
-- (Blizzard change l atlas, jamais l alpha) ; plaque plate a bande de
-- couleur. Membre de raid (bouton securise) : ligne plate, rien d autre.
local function card(b, bg, kind)
    if cards[b] then return end
    local C = ns.COLORS
    fade(bg)
    fadeStates(b, { "GetHighlightTexture" })
    local s = { bg = bg, kind = kind }
    if kind == "raid" then
        fade(field(b, "DragBackground"))
        s.fill = tex(b, "BACKGROUND", -8)
        s.fill:SetAllPoints(b)
        s.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.45)
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
    else
        s.fill = tex(b, "BACKGROUND", -8)
        s.fill:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
        s.fill:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
        s.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.92)
        s.sel = tex(b, "BACKGROUND", -7)
        s.sel:SetAllPoints(s.fill)
        grad(s.sel, C.violet, 0.42, 0.05)
        s.sel:Hide()
        s.stripe = tex(b, "BACKGROUND", -6)
        s.stripe:SetPoint("TOPLEFT", s.fill, "TOPLEFT", 0, 0)
        s.stripe:SetPoint("BOTTOMLEFT", s.fill, "BOTTOMLEFT", 0, 0)
        -- 2 px : l icone de statut commence a 3 px du bord
        s.stripe:SetWidth(2)
        s.edges = ring(b, s.fill, "BACKGROUND", -5, 0)
        paintC(s.edges, C.border)
        s.hl = tex(b, "HIGHLIGHT")
        s.hl:SetAllPoints(s.fill)
        grad(s.hl, C.violet, 0.20, 0.02)
        if kind == "quick" then
            -- survol / selection des groupes rapides : textures BORDER dont
            -- Blizzard pilote l alpha (SetAlpha selon la selection)
            s.qsel, s.qhl = field(b, "Selected"), field(b, "Highlight")
            veil(s.qsel)
            veil(s.qhl)
        end
    end
    cards[b] = s
    claimed[b] = true
end

local function cardState(b, s)
    local C = ns.COLORS
    if s.kind == "raid" then
        fade(s.bg)
        fade(field(b, "DragBackground"))
        return
    end
    -- carte de separation du recrutement : Blizzard cache son fond
    local on = shown(s.bg)
    s.fill:SetShown(on)
    s.stripe:SetShown(on)
    s.hl:SetShown(on)
    showAll(s.edges, on)
    if not on then
        s.sel:Hide()
        return
    end
    local a = atlasOf(s.bg) or ""
    local off = a:find("disabled", 1, true) ~= nil
    local sel
    if s.kind == "quick" then
        veil(s.qsel)
        veil(s.qhl)
        sel = shown(s.qsel)
    else
        sel = locked(b)
    end
    s.sel:SetShown(sel)
    local c
    if s.kind == "quick" then c = C.violet
    elseif off then c = GREY
    elseif a:find("battleNet", 1, true) then c = BNET
    else c = C.gold end
    s.stripe:SetColorTexture(c[1], c[2], c[3], off and 0.7 or 1)
    s.fill:SetAlpha(off and 0.6 or 1)
    paintC(s.edges, (sel or isOver(b)) and C.gold or C.border)
end

-- ligne simple (ignores, infos de raid, amis d un ami) : survol de
-- Blizzard a alpha 0, fond leger, separateur fin, survol en degrade ;
-- la ligne choisie (survol verrouille par Blizzard) en accent + barre d or
local function listRow(r)
    if rows[r] or not engine(r, "CreateTexture") then return end
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
    s.sel = tex(r, "BACKGROUND", -6)
    s.sel:SetAllPoints(r)
    grad(s.sel, C.violet, 0.42, 0.05)
    s.sel:Hide()
    s.bar = tex(r, "BACKGROUND", -5)
    s.bar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
    s.bar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
    s.bar:SetWidth(2)
    s.bar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    s.bar:Hide()
    s.hl = tex(r, "HIGHLIGHT")
    s.hl:SetAllPoints(r)
    grad(s.hl, C.violet, 0.26, 0.03)
    rows[r] = s
    claimed[r] = true
end

local function rowState(r, s)
    local sel = locked(r)
    s.sel:SetShown(sel)
    s.bar:SetShown(sel)
end

-- lignes d une liste a defilement (ScrollBox.ScrollTarget)
local function listRows(sb)
    local target = field(sb, "ScrollTarget") or sb
    for _, c in ipairs(childrenOf(target)) do
        if visible(c) and not mine[c] then
            local t = objType(c)
            if t == "Button" then
                try("ligne", listRow, c)
            elseif t == "Frame" and objType(field(c, "Text")) == "FontString" then
                try("en-tete", listHeader, c)
            end
        end
    end
end

-- groupe de raid (RaidFrameSocialGroupTemplate) : fond a alpha 0,
-- panneau sombre, bandeau d en-tete, titre or
local function raidGroup(g)
    if panels[g] or not engine(g, "CreateTexture") then return end
    panels[g] = true
    fadeOwn(g)
    backdrop(g, g, 0.5)
    headBand(g, g, 1, 24)
    titleGold(field(g, "GroupNumberText"))
end

-- cadre interieur a fond d infobulle (liste des amis d un ami)
local function innerBox(f)
    if panels[f] or not engine(f, "CreateTexture") then return end
    panels[f] = true
    fadeOwn(f)
    fadeOwn(field(f, "NineSlice"))
    local C = ns.COLORS
    local fill = tex(f, "BACKGROUND", -8)
    fill:SetAllPoints(f)
    fill:SetColorTexture(0, 0, 0, 0.5)
    paintC(ring(f, fill, "BACKGROUND", -7, 0), C.border)
end

---------------------------------------------------------------------------
-- Fenetres de cote et dialogues
---------------------------------------------------------------------------

-- fond, ombre, bandeau (sauf noHead), titre or, croix plate ; "host" porte
-- nos textures (la bordure pour un cadre a taille calculee)
local function windowDress(f, host, title, noHead)
    local C = ns.COLORS
    local bd = backdrop(host, f, 0.96)
    for i = 1, 4 do
        local s = tex(host, "BACKGROUND", -8)
        s:SetPoint("TOPLEFT", bd.fill, "TOPLEFT", -i, i)
        s:SetPoint("BOTTOMRIGHT", bd.fill, "BOTTOMRIGHT", i, -i)
        s:SetColorTexture(0, 0, 0, 0.14)
    end
    if not noHead then headBand(host, f, 1, 22) end
    if objType(title) == "FontString" then titleGold(title) end
    -- croix rouge seulement (le CloseButton des amis d un ami est un
    -- bouton rouge a texte "Fermer" : plaque, par le parcours)
    local close = field(f, "CloseButton")
    local a = atlasOf(askObj(close, "GetNormalTexture"))
    if objType(close) == "Button" and a and a:find("^RedButton%-Exit") then
        try("croix", glyphButton, close, "×", 15, 4, C.text, true)
    end
end

-- hote de nos textures : la bordure de dialogue (cadre enfant a la taille
-- du dialogue) si le dialogue calcule sa taille sur ses regions
local function hostOf(f)
    if not layoutFrame(f) then return f end
    local border = field(f, "Border")
    if border and objType(border) == "Frame" and engine(border, "CreateTexture") then return border end
end

-- bordure de dialogue (DialogBorderTemplate : NineSlice + Bg)
local function fadeBorder(f)
    local border = field(f, "Border")
    if border and objType(border) ~= "Texture" then
        fadeOwn(border)
        fadeOwn(field(border, "NineSlice"))
    end
end

-- liste des ignores (ButtonFrameTemplate)
local function ignoreList(f)
    if not panels[f] then
        panels[f] = true
        fadeOwn(f)
        fadeOwn(field(f, "NineSlice"))
        fadeOwn(field(f, "PortraitContainer"))
        local inset = field(f, "Inset")
        if inset then
            fadeOwn(inset)
            fadeOwn(field(inset, "NineSlice"))
        end
        windowDress(f, f, field(field(f, "TitleContainer"), "TitleText"))
        -- au-dessus du fond de la fenetre (-8) : sous-niveaux -6 / -5
        if inset then backdrop(f, inset, 0.45, -6) end
    end
    listRows(field(f, "ScrollBox"))
end

-- infos de raid (verrous d instance) : roche, bords en diamant et fond
-- noir a alpha 0 ; bandeau sous les titres de colonnes
local function raidInfo(f)
    if not panels[f] then
        panels[f] = true
        local topInset, bottomInset = field(f, "TopInset"), field(f, "BottomInset")
        fadeOwn(f)
        fadeOwn(field(f, "Border"))
        windowDress(f, f, nil, true)
        if objType(topInset) == "Texture" then bandOn(f, topInset) end
        if objType(bottomInset) == "Texture" then bandOn(f, bottomInset) end
        for _, r in ipairs(regionsOf(f)) do
            if objType(r) == "FontString" and not mine[r] then titleGold(r) end
        end
    end
    listRows(field(f, "ScrollBox"))
end

-- annonce Battle.net, Battle.net indisponible (ResizeLayoutFrame)
local function sideDialog(f)
    if panels[f] then return end
    local host = hostOf(f)
    if not host then return end
    panels[f] = true
    fadeBorder(f)
    local title = field(f, "Title") or field(field(f, "Header"), "HeaderText")
    windowDress(f, host, title, true)
end

-- dialogues annexes (parent UIParent) : ajout d ami, invitation BattleTag,
-- amis d un ami
local function annexDialog(f)
    if not panels[f] then
        local host = hostOf(f)
        if not host then return end
        panels[f] = true
        fadeBorder(f)
        windowDress(f, host, field(f, "Title"), true)
        -- titre de la saisie d ajout d ami
        titleGold(field(field(field(f, "EntryFrame"), "TitleContainer"), "Title"))
    end
    local sb = field(f, "ScrollBox")
    if sb then listRows(sb) end
end

---------------------------------------------------------------------------
-- Parcours
---------------------------------------------------------------------------

-- profondeur de recherche de Skins.lua dans la fenetre (Fenetres.lua) ;
-- fenetre non declaree : Skins.lua n aplatit rien, tout est pour nous
local skinsDepth
local function getSkinsDepth()
    if skinsDepth then return skinsDepth end
    local found
    for _, g in ipairs(ns.SKIN_GROUPS or {}) do
        for _, spec in ipairs(g.windows or {}) do
            if spec[1] == "SocialUIFrame" then found = spec.depth or 6 end
        end
    end
    skinsDepth = found or 0
    return skinsDepth
end

-- Skins.lua ne descend pas dans un cadre reclame : ce qui est dessous est
-- pour nous
local function claimedAncestor(f, root)
    local p = parentOf(f)
    for _ = 1, 14 do
        if not p or p == root then return false end
        if claimed[p] then return true end
        p = parentOf(p)
    end
    return false
end

local function scanRegions(f)
    for _, r in ipairs(regionsOf(f)) do
        if not mine[r] and not done[r] and objType(r) == "Texture" then
            local a = atlasOf(r)
            local act = a and ATLAS[a]
            if act then
                done[r] = true
                if act == "fade" then
                    fade(r)
                elseif act == "divider" then
                    divider(r, f)
                elseif act == "rafband" then
                    rafBand(r, f)
                end
            end
        end
    end
end

-- elements reconnus par leurs champs ou l atlas de leur texture normale
local function special(f, depth, ctx)
    local t = objType(f)
    if not t then return end
    if t == "EditBox" then
        if field(f, "searchIcon") and field(f, "Instructions") then searchBox(f) else borderEdit(f) end
        return
    end
    -- cases a cocher (Tous assistants...) : Communs.lua
    if t == "CheckButton" then return end
    if t == "Button" or t == "DropdownButton" then
        -- menus a fleche (statut Battle.net...) : Communs.lua
        if common(f) or plates[f] or cards[f] or heads[f] or tabs[f] or rows[f] then return end
        -- onglet lateral
        if field(f, "SelectedTexture") and field(f, "TabGlow") and objType(field(f, "Icon")) == "Texture" then
            sideTab(f)
            return
        end
        -- en-tete repliable
        if objType(field(f, "CollapseButton")) == "Button" and objType(field(f, "ButtonText")) == "FontString" then
            header(f)
            return
        end
        -- carte (fond friends-card-*)
        local bg = field(f, "Background")
        local a = atlasOf(bg)
        if a and a:find("^friends%-card%-") then
            card(f, bg, cardKind(a))
            return
        end
        if a and a:find("^common%-dropdown%-b%-button") then
            filterDrop(f, bg)
            return
        end
        local na = atlasOf(askObj(f, "GetNormalTexture"))
        if na then
            if na:find("^common%-button%-tertiary%-square") then
                squareButton(f)
                return
            end
            if na:find("^common%-button%-tertiary") then
                flatButton(f)
                return
            end
            -- refus d une demande d ami, remise a zero des filtres
            if na == "auctionhouse-ui-filter-redx" then
                glyphButton(f, "×", 14, 3, ns.COLORS.text, true)
                return
            end
            -- croix des fenetres de cote (celle de la fenetre est a Skins.lua)
            if na:find("^RedButton%-Exit") then
                if f ~= ctx.mainClose then glyphButton(f, "×", 15, 4, ns.COLORS.text, true) end
                return
            end
        end
        if isPanelButton(f) then
            local ours = not ctx.main or depth > getSkinsDepth() or claimedAncestor(f, ctx.root)
            if ours then panelButton(f) end
            return
        end
        if ctx.annex and isTexturedButton(f) then textureButton(f) end
        return
    end
    -- cadres
    if field(f, "GroupNumberText") and field(f, "PlayersFrame") then raidGroup(f) end
    if field(f, "FilterBar") and field(f, "ScrollBox") and field(f, "ActionButton") then contactsPanel(f) end
    if layoutOf(f) == "TooltipDefaultLayout" then innerBox(f) end
end

local function walk(f, depth, ctx)
    if depth > 14 or mine[f] or not visible(f) then return end
    -- bulles d aide (HelpTip) : cadres partages entre toutes les fenetres
    if field(f, "OkayButton") and field(f, "Arrow") then return end
    if isScrollBar(f) then
        try("barre", skinScrollBar, f)
        return
    end
    scanRegions(f)
    try("element", special, f, depth, ctx)
    for _, c in ipairs(childrenOf(f)) do walk(c, depth + 1, ctx) end
end

local function titleText(f)
    local fs = field(field(f, "TitleContainer"), "TitleText") or field(f, "TitleText")
    if objType(fs) == "FontString" then return fs end
end

-- fenetres de cote de la fenetre (enfants de SocialUIFrame)
local SIDES = {
    { "IgnoreListFrame", ignoreList },
    { "RaidInfoFrame", raidInfo },
    { "BattleNetBroadcastFrame", sideDialog },
    { "BattleNetUnavailableNoticeFrame", sideDialog },
}

local function fullMain(root)
    local ctx = { root = root, main = true, mainClose = field(root, "CloseButton") }
    local bar = field(root, "BattleNetBar")
    if bar and visible(bar) then try("battle.net", bnetBar, bar, root) end
    for _, s in ipairs(SIDES) do
        local w = field(root, s[1])
        if w and visible(w) then try(s[1], s[2], w) end
    end
    walk(root, 0, ctx)
end

local function fullAnnex(f)
    try("dialogue", annexDialog, f)
    walk(f, 0, { root = f, annex = true })
end

-- leger (5 fois par seconde, fenetre ouverte) : couleurs d etat
local mainTitle

local function light(main)
    local C = ns.COLORS
    if main then
        local title = titleText(main)
        if title then
            if not mainTitle or mainTitle.fs ~= title then mainTitle = goldFont(title) else keepGold(mainTitle) end
        end
    end
    for t, s in pairs(tabs) do
        if visible(t) then try("etat onglet", tabState, t, s) end
    end
    placeRails()
    for b, s in pairs(cards) do
        if visible(b) then try("etat carte", cardState, b, s) end
    end
    for r, s in pairs(rows) do
        if visible(r) then try("etat ligne", rowState, r, s) end
    end
    for h, s in pairs(heads) do
        if visible(h) then try("etat en-tete", headState, h, s) end
    end
    for b, p in pairs(plates) do
        if p.edges and visible(b) then
            local en = enabled(b)
            local over = en and isOver(b)
            -- menu ouvert : DropdownButtonMixin garde le menu dans self.menu (lu)
            local open = p.drop and field(b, "menu") ~= nil
            local c = C.border
            if p.close and over then c = RED elseif over or open then c = C.gold end
            paintC(p.edges, c)
            p.fill:SetAlpha(en and 1 or 0.5)
            -- Blizzard repose l atlas d etat (alpha jamais) : verifie
            if p.bg then fade(p.bg) end
            if p.states then fadeStates(b, p.states) end
            if p.glyph then
                local g = p.color or C.gold
                if p.close and over then g = RED end
                p.glyph:SetTextColor(g[1], g[2], g[3])
                p.glyph:SetAlpha(en and 1 or 0.35)
            end
            if p.chev then
                local g = en and C.gold or C.text
                for _, x in ipairs(p.chev) do x:SetColorTexture(g[1], g[2], g[3], en and 1 or 0.4) end
            end
        end
    end
    for e, k in pairs(edits) do
        if visible(e) then
            local focus = ask(e, "HasFocus") == true
            if focus then paintC(k.edges, C.gold)
            elseif isOver(e) then paintC(k.edges, C.violet)
            else paintC(k.edges, C.border) end
            -- loupe : Blizzard la grise hors focus ; or plein au focus
            if k.glass then tintGold(k.glass, focus and 1 or 0.75) end
        end
    end
    for ref, b in pairs(bands) do showAll(b.parts, shown(ref)) end
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

-- fenetres reprises : la fenetre des contacts et ses dialogues annexes
-- (Blizzard_AddFriend, Blizzard_FriendsFrame), poses sur UIParent
local ROOTS = {
    { "SocialUIFrame", "main" },
    { "AddFriendFrame", "annex" },
    { "BattleNetInviteFrame", "annex" },
    { "FriendsFriendsFrame", "annex" },
}
local state = {}     -- nom -> { shown, key }
local acc, walkAcc = 0, 0

-- volet affiche (onglet choisi, fenetre de cote) : un changement relance
-- tout de suite le parcours
local function pageKey(f, kind)
    if kind ~= "main" then return "" end
    local a, b = value(f, "selectedTab"), value(f, "activeSideWindowType")
    return tostring(a) .. "|" .. tostring(b)
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
        local f = rawget(_G, name)
        local st = state[name]
        if not st then
            st = {}
            state[name] = st
        end
        if type(f) == "table" and engine(f, "CreateTexture") and visible(f) then
            any = true
            if kind == "main" then main = f end
            local key = pageKey(f, kind)
            if not st.shown or key ~= st.key or walkAcc >= 0.6 then
                st.shown, st.key, walked = true, key, true
                if kind == "main" then
                    try(name, fullMain, f)
                else
                    try(name, fullAnnex, f)
                end
            end
        else
            st.shown = false
        end
    end
    if walked then walkAcc = 0 end
    if any then try("releve", light, main) end
end)
