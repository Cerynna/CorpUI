--[[--------------------------------------------------------------------------
    CorpUI - module Habillage : dialogues des PNJ en profondeur
    (GossipFrame et QuestFrame de Blizzard_UIPanels_Game, famille Mainline
    sur ce client)

    Skins.lua pose deja le fond des deux fenetres, leur lisere, leur
    bandeau, le titre en or et la croix, et aplatit les boutons rouges (Au
    revoir, Accepter, Refuser, Continuer, Terminer la quete) ; ici on
    reprend l interieur, reste sur parchemin :
      - parchemin et materiaux (pierre, marbre, sceau) eteints, panneau
        sombre a lisere derriere la zone de texte, barres de defilement
        minimalistes ;
      - dialogue (GossipFrame) : options et quetes en lignes, survol en
        degrade d accent, icone sur un carre sombre, textes clairs (quete
        de bas niveau ou ignoree attenuee, comme l icone que Blizzard
        grise) ;
      - accueil d un donneur de quetes (QuestFrame) : memes lignes, titres
        "Quetes en cours" / "Quetes disponibles" en or, separateur en filet
        d or ;
      - progression : titres en or, texte clair, objets demandes en cases
        carrees ;
      - detail et recompense : textes de QuestInfo eclaircis, bandeau
        "Recompenses", cases carrees au lisere de qualite (rouge si
        inutilisable) ; choix de recompense : degrade d accent, lisere d or
        double et barre d or sur la case choisie, lisere d accent au survol
        d une case a choisir.

    Couleur des textes : Blizzard la repose a chaque mise a jour (theme du
    parchemin) ; on la reprend a chaque image tant qu une des deux fenetres
    est ouverte (avant le rendu : pas d eclair sombre), sans l ecrire si
    elle n a pas change. Les titres de quetes du dialogue portent un code
    couleur noir dans leur texte : comme le theme sombre de Blizzard, on
    leur pose la couleur fixe (SetFixedColor), que Blizzard repose avec sa
    couleur a chaque mise a jour de son theme (fausse, vraie en theme
    sombre : contraste du texte des quetes a 4). Habillage coupe (groupe
    decoche, hors combat) : couleurs, couleur fixe (celle que Blizzard y
    pose), parchemin et cadres rendus a Blizzard (couleurs seulement si
    nous sommes encore les derniers a les avoir changees), nos textures
    cachees ; l apparence complete d origine demande un /reload.

    QuestInfo (titres, textes, recompenses) est partage avec la fiche du
    journal et la fiche seule (QuestLogPopupDetailFrame, sur parchemin) :
      - ses textes ont un seul proprietaire, JournalQuetes.lua : on lui
        inscrit les deux contenus deroules du QuestFrame habille
        (ns.QuestInfoHosts) ;
      - les cases de QuestInfoRewardsFrame ne perdent leur cadre de Blizzard
        (et ne recoivent les notres, recadrage de l icone compris) que tant
        que ce cadre est dans le QuestFrame habille ; rendues hors combat
        des qu il passe ailleurs. Une case creee par Blizzard en combat n a
        pas encore nos textures : si elle est choisie, une marque de secours
        posee sur la surbrillance de Blizzard (qu il ancre a la case choisie)
        la signale jusqu a la fin du combat.

    Regles de ce client (taint, valeurs secretes) : ces fenetres appellent
    des fonctions protegees depuis leurs clics (AcceptQuest, CompleteQuest,
    GetQuestReward, SelectOptionByIndex...) ; rien de ce que ce code relit
    ne doit venir de nous :
      - aucun crochet, aucun script pose sur un cadre de Blizzard, aucune
        fonction ou methode Lua de Blizzard appelee (accesseurs du moteur
        seulement : IsVisible, GetParent, GetID, GetVertexColor...) ;
      - aucun champ ecrit dans leurs cadres ou leurs tables (lignes
        recyclees comprises) : notre etat est range dans des tables faibles
        a nous, indexees par le cadre ;
      - aucune taille, position, strate, niveau, parent, souris ni
        visibilite de Blizzard modifiee, aucun atlas, texture ni police :
        seulement l alpha de leurs textures (jamais d une texture dont ils
        pilotent l alpha), la couleur des fleches de defilement, le
        recadrage d une icone, la couleur (et la couleur fixe) de leurs
        textes, et nos propres textures posees sur leurs cadres (jamais sur
        la liste deroulee du dialogue ni sur les contenus deroules porteurs
        de QuestInfo) ;
      - en combat : seulement la couleur des textes (lignes nouvelles
        reperees par simple lecture de la liste) et l etat de NOS
        textures ; aucune creation, aucun alpha de Blizzard ; toute valeur
        lue est verifiee (pcall, issecretvalue).
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)

local issecret = issecretvalue or function() return false end
local weak = { __mode = "k" }

local mine = setmetatable({}, weak)      -- nos regions (a ne jamais traiter)
local base = setmetatable({}, weak)      -- nos textures montrees tant que l habillage est pose
local extras = setmetatable({}, weak)    -- nos textures montrees sous condition -> fonction
local shownAs = setmetatable({}, weak)   -- derniere visibilite donnee a une texture d extras
local faded = setmetatable({}, weak)     -- texture de Blizzard a alpha 0 -> son alpha d origine
local tinted = setmetatable({}, weak)    -- texture de Blizzard recoloree -> sa couleur d origine
local cropped = setmetatable({}, weak)   -- icone de Blizzard recadree
local claimed = setmetatable({}, weak)   -- lignes et cases que Skins.lua ne doit pas aplatir
local panels = setmetatable({}, weak)    -- panneau de Blizzard -> notre fond
local dressed = setmetatable({}, weak)   -- panneau dont le parchemin est eteint
local bars = setmetatable({}, weak)      -- barre de defilement -> { thumb, knob, over }
local rows = setmetatable({}, weak)      -- ligne (dialogue, accueil) -> nos textures
local lines = setmetatable({}, weak)     -- ligne -> { fs, icon } (texte a eclaircir)
local texts = setmetatable({}, weak)     -- texte fixe de la fenetre -> "gold" / "body"
local themed = setmetatable({}, weak)    -- texte dont Blizzard pose la couleur fixe (theme)
local boxes = setmetatable({}, weak)     -- case a icone -> nos textures et leur etat
local tints = setmetatable({}, weak)     -- texte -> couleurs (Blizzard, nous)

local live = false    -- habillage pose (parchemin eteint, nos textures montrees)
local rfOn = false    -- cases de QuestInfoRewardsFrame habillees (cadre dans le QuestFrame)

local DIM = 0.6       -- attenuation d une ligne grisee par Blizzard

local function db()
    local d = ns.skinsDB
    if type(d) ~= "table" or not d.enabled then return nil end
    if d.groups and d.groups.npc == false then return nil end
    return d
end

-- erreur gardee pour /dump CorpUIDB.skins.errors (jamais propagee)
local function report(where, err)
    if ns.skinsDB then
        ns.skinsDB.errors = ns.skinsDB.errors or {}
        ns.skinsDB.errors[where] = tostring(err)
    end
end

local function run(where, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then report(where, err) end
end

---------------------------------------------------------------------------
-- Outils (lectures)
---------------------------------------------------------------------------

local function objType(o)
    if type(o) ~= "table" or not o.GetObjectType then return nil end
    local ok, t = pcall(o.GetObjectType, o)
    if ok and type(t) == "string" and not issecret(t) then return t end
end

local function isButton(o)
    local t = objType(o)
    return t == "Button" or t == "CheckButton"
end

-- lectures sans fermeture creee a chaque appel (releves a chaque image)
local function get(f, k) return f[k] end
local function packRegions(f) return { f:GetRegions() } end
local function packChildren(f) return { f:GetChildren() } end

local function field(f, key)
    if type(f) ~= "table" then return nil end
    local ok, c = pcall(get, f, key)
    if ok and type(c) == "table" then return c end
end

-- valeur simple d un champ (nil si secrete)
local function value(f, key)
    if type(f) ~= "table" then return nil end
    local ok, v = pcall(get, f, key)
    if ok and not issecret(v) then return v end
end

local function num(v)
    if v == nil or issecret(v) or type(v) ~= "number" then return nil end
    return v
end

-- accesseur du moteur (premiere valeur, nil si secrete)
local function ask(f, m)
    if type(f) ~= "table" then return nil end
    local okF, fn = pcall(get, f, m)
    if not okF or type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, f)
    if ok and not issecret(v) then return v end
end

local function visible(f) return ask(f, "IsVisible") == true end
local function shown(f) return ask(f, "IsShown") == true end
local function isOver(f) return ask(f, "IsMouseOver") == true end

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

local function numKids(f) return num(ask(f, "GetNumChildren")) or -1 end

local function atlasOf(t)
    local a = ask(t, "GetAtlas")
    if type(a) == "string" then return a end
end

local function parentOf(r)
    if type(r) ~= "table" or not r.GetParent then return nil end
    local ok, p = pcall(r.GetParent, r)
    if ok and type(p) == "table" then return p end
end

-- r a "f" pour ancetre a "depth" niveaux au plus
local function below(r, f, depth)
    local p = parentOf(r)
    for _ = 1, depth do
        if not p then return false end
        if p == f then return true end
        p = parentOf(p)
    end
    return false
end

local function vertexOf(t)
    if type(t) ~= "table" or not t.GetVertexColor then return nil end
    local ok, r, g, b, a = pcall(t.GetVertexColor, t)
    if ok and num(r) and num(g) and num(b) then return r, g, b, num(a) or 1 end
end

local function near(a, b) return a ~= nil and b ~= nil and math.abs(a - b) < 0.01 end

---------------------------------------------------------------------------
-- Outils (ecritures : textures de Blizzard, toujours reversibles)
---------------------------------------------------------------------------

-- alpha 0 (jamais sur un cadre, jamais sur nos textures) ; l alpha
-- d origine est garde pour le rendre si l habillage est coupe
local function fade(t)
    if objType(t) ~= "Texture" or mine[t] then return end
    local a = num(ask(t, "GetAlpha"))
    if a == 0 then return end
    if faded[t] == nil then faded[t] = a or 1 end
    pcall(t.SetAlpha, t, 0)
end

local function unfade(t)
    local a = faded[t]
    if a == nil then return end
    faded[t] = nil
    pcall(t.SetAlpha, t, a)
end

-- couleur de sommet (fleches de defilement) ; l origine est gardee
local function tintTex(t, c, a)
    if objType(t) ~= "Texture" or mine[t] then return end
    local r, g, b, al = vertexOf(t)
    if r and near(r, c[1]) and near(g, c[2]) and near(b, c[3]) and near(al, a) then return end
    if tinted[t] == nil then tinted[t] = { r or 1, g or 1, b or 1, al or 1 } end
    pcall(t.SetVertexColor, t, c[1], c[2], c[3], a)
end

-- icone recadree (jamais sur un atlas : on casserait ses coordonnees)
local function cropIcon(icon)
    if objType(icon) ~= "Texture" or mine[icon] or atlasOf(icon) then return end
    cropped[icon] = true
    pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
end

-- recadrage rendu (SetTexture de Blizzard garde les coordonnees) ; un atlas
-- pose depuis a deja les siennes
local function uncrop(icon)
    if not cropped[icon] then return end
    cropped[icon] = nil
    if not atlasOf(icon) then pcall(icon.SetTexCoord, icon, 0, 1, 0, 1) end
end

local function fadeOwn(f)
    for _, r in ipairs(regionsOf(f)) do fade(r) end
end

local function fadeStates(b, list)
    for _, get in ipairs(list) do
        local t = ask(b, get)
        if t then fade(t) end
    end
end

---------------------------------------------------------------------------
-- Nos textures
---------------------------------------------------------------------------

local function tex(host, layer, sub, always)
    local t = host:CreateTexture(nil, layer, nil, sub)
    mine[t] = true
    if always then base[t] = true end
    ns.NoSnap(t)   -- traits fins toujours dessines (Core.lua)
    return t
end

-- quatre filets de 1 px autour de "anchor" (sur "host"), "out" px en dehors
local function ring(host, anchor, layer, sub, out, always)
    local list = {}
    local function line()
        local x = tex(host, layer, sub, always)
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

local function accent(t, a1, a2)
    local C = ns.COLORS
    ns.UI.Gradient(t, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], a1, C.violet[1], C.violet[2], C.violet[3], a2)
end

local function goldLine(host, layer, sub)
    local C = ns.COLORS
    local line = tex(host, layer, sub)
    line:SetHeight(1)
    ns.UI.Gradient(line, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.8, C.gold[1], C.gold[2], C.gold[3], 0)
    return line
end

-- texture montree selon une condition lue a chaque image
local function onlyIf(t, fn)
    extras[t] = fn
    return t
end

---------------------------------------------------------------------------
-- Panneaux, barres de defilement
---------------------------------------------------------------------------

local function isScrollBar(f)
    local track = field(f, "Track")
    return track and field(track, "Thumb") and field(f, "Back") and field(f, "Forward") and true or false
end

local function scrollBarOf(sf)
    local sb = field(sf, "ScrollBar")
    if isScrollBar(sb) then return sb end
    for _, c in ipairs(childrenOf(sf)) do
        if isScrollBar(c) then return c end
    end
end

-- barre minimaliste : alpha et couleur seulement, jamais d atlas (Blizzard
-- relit celui du curseur)
local function skinScrollBar(sb)
    if not isScrollBar(sb) then return end
    local C = ns.COLORS
    local track = field(sb, "Track")
    local thumb = field(track, "Thumb")
    for _, k in ipairs({ "Begin", "Middle", "End" }) do
        fade(field(track, k))
        fade(field(thumb, k))
    end
    -- fleches : notre chevron (Core.lua), celles de Blizzard eteintes
    for _, k in ipairs({ "Back", "Forward" }) do
        local b = field(sb, k)
        local c = ns.UI.ArrowChevron(b, ns.UI.ScrollDir(sb, k), 10, { field(b, "Texture") })
        if c then mine[c] = true end
    end
    if bars[sb] or not (track.CreateTexture and thumb.CreateTexture) then return end
    local line = tex(track, "ARTWORK", 1, true)
    line:SetPoint("TOP", track, "TOP", 0, 0)
    line:SetPoint("BOTTOM", track, "BOTTOM", 0, 0)
    line:SetWidth(1)
    line:SetColorTexture(C.border[1], C.border[2], C.border[3], 0.8)
    local knob = tex(thumb, "ARTWORK", 2, true)
    knob:SetPoint("TOP", thumb, "TOP", 0, 0)
    knob:SetPoint("BOTTOM", thumb, "BOTTOM", 0, 0)
    knob:SetWidth(4)
    knob:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.6)
    bars[sb] = { thumb = thumb, knob = knob, over = false }
end

-- panneau de texte : ses textures (parchemin, materiaux, sceau) a alpha 0
-- (Blizzard ne change que leur atlas ou leur fichier, jamais leur alpha),
-- notre fond pose sur lui et ancre a sa zone deroulante
local function dressPanel(p, sf, padL, padR, sb)
    if type(p) ~= "table" or not p.CreateTexture or type(sf) ~= "table" then return end
    fadeOwn(p)
    dressed[p] = true
    if not panels[p] then
        local C = ns.COLORS
        local fill = tex(p, "BACKGROUND", -8, true)
        fill:SetPoint("TOPLEFT", sf, "TOPLEFT", -padL, 3)
        fill:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", padR, -1)
        fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.55)
        paintC(ring(p, fill, "BACKGROUND", -7, 0, true), C.border)
        panels[p] = { fill = fill }
    end
    skinScrollBar(sb or scrollBarOf(sf))
end

---------------------------------------------------------------------------
-- Lignes (options et quetes du dialogue, quetes de l accueil)
---------------------------------------------------------------------------

-- nos textures : survol en degrade (calque HIGHLIGHT du bouton), carre
-- sombre sous l icone ; la surbrillance de Blizzard a alpha 0 (le moteur
-- la montre par son calque, jamais par son alpha)
local function dressRow(b)
    fadeStates(b, { "GetHighlightTexture" })
    if rows[b] or not b.CreateTexture then return end
    local s = {}
    s.hov = tex(b, "HIGHLIGHT", nil, true)
    s.hov:SetPoint("TOPLEFT", b, "TOPLEFT", 1, 0)
    s.hov:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 0)
    accent(s.hov, 0.22, 0.02)
    local icon = field(b, "Icon")
    if objType(icon) == "Texture" then
        s.sq = tex(b, "BACKGROUND", -8, true)
        s.sq:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
        s.sq:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
        s.sq:SetColorTexture(0, 0, 0, 0.45)
    end
    rows[b] = s
    claimed[b] = true
end

-- ligne reperee (lecture seule, aussi en combat) ; habillee hors combat.
-- Son texte est du theme de Blizzard : couleur fixe posee a chaque mise a
-- jour (UpdateFontStrings du dialogue, accueil du QuestFrame)
local function addLine(b, create)
    if not lines[b] then
        local fs = ask(b, "GetFontString")
        if objType(fs) ~= "FontString" then return end
        lines[b] = { fs = fs, icon = field(b, "Icon") }
        themed[fs] = true
    end
    if create then dressRow(b) end
end

---------------------------------------------------------------------------
-- Cases a icone (recompenses, objets demandes)
---------------------------------------------------------------------------

local BORDER_Q = { gray = 0, white = 1, green = 2, blue = 3, purple = 4, orange = 5, artifact = 6, account = 7 }

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

-- couleur de la bordure de qualite de Blizzard (eteinte par l alpha,
-- montree ou cachee par eux) : atlas "...-border-purple", sinon sa couleur
-- de sommet (Interface\Common\WhiteIconFrame teinte a la qualite)
local function borderColor(ib)
    if not shown(ib) then return nil end
    local a = atlasOf(ib)
    if a then
        local q = BORDER_Q[(a:match("%-(%a+)$") or ""):lower()]
        if q then return qualityColor(q) end
    end
    local r, g, b = vertexOf(ib)
    if r and not (r > 0.95 and g > 0.95 and b > 0.95) then return r, g, b end
end

-- teinte rouge posee par Blizzard sur un objet inutilisable
local function redTinted(t)
    local r, g, b = vertexOf(t)
    return (r and r > 0.8 and g < 0.2 and b < 0.2) and true or false
end

-- decor de Blizzard d une case (cadre du nom, bordure, morceaux en plus)
local function fadeBox(bx)
    fade(bx.nf)
    fade(bx.border)
    for _, t in ipairs(bx.more) do fade(t) end
end

local function unfadeBox(bx)
    unfade(bx.nf)
    unfade(bx.border)
    for _, t in ipairs(bx.more) do unfade(t) end
end

-- nos textures : fond sous l icone, liseres (simple, puis double en or
-- quand la case est choisie), plaque du nom, degrade et barre du choix.
-- shared : case de QuestInfoRewardsFrame (montree selon rfOn)
local function dressBox(b, icon, nf, shared, right, more)
    if boxes[b] then return boxes[b] end
    if not b.CreateTexture then return nil end
    local C = ns.COLORS
    local bx = { icon = icon, nf = nf, border = field(b, "IconBorder"), shared = shared, more = more or {}, list = {} }
    -- bouton de sort (QuestSpellTemplate, sans compteur) : sa bordure est
    -- une texture anonyme
    if not more and not field(b, "Count") then
        for _, r in ipairs(regionsOf(b)) do
            if objType(r) == "Texture" and r ~= icon and r ~= nf then bx.more[#bx.more + 1] = r end
        end
    end
    local function own(t) bx.list[#bx.list + 1] = t return t end
    local function ownAll(list) for _, t in ipairs(list) do own(t) end return list end
    bx.fill = own(tex(b, "BACKGROUND", -8))
    bx.fill:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
    bx.fill:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
    bx.fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.9)
    bx.name = own(tex(b, "BACKGROUND", -7))
    bx.name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 3, 0)
    bx.name:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 3, 0)
    bx.name:SetPoint("RIGHT", right or b, "RIGHT", 0, 0)
    bx.name:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.85)
    bx.nameEdges = ownAll(ring(b, bx.name, "BACKGROUND", -6, 0))
    bx.sel = own(tex(b, "BACKGROUND", -5))
    bx.sel:SetAllPoints(bx.name)
    accent(bx.sel, 0.45, 0.05)
    bx.edges = ownAll(ring(b, icon, "OVERLAY", 7, 1))
    bx.outer = ownAll(ring(b, icon, "OVERLAY", 7, 2))
    bx.bar = own(tex(b, "OVERLAY", 7))
    bx.bar:SetPoint("TOPRIGHT", icon, "TOPLEFT", -4, 2)
    bx.bar:SetPoint("BOTTOMRIGHT", icon, "BOTTOMLEFT", -4, -2)
    bx.bar:SetWidth(2)
    bx.bar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    paintC(bx.nameEdges, C.border, 0.7)
    paintC(bx.outer, C.gold)
    -- case partagee : recadree seulement dans le QuestFrame habille
    if not shared or rfOn then cropIcon(icon) end
    boxes[b] = bx
    claimed[b] = true
    return bx
end

---------------------------------------------------------------------------
-- Dialogue (GossipFrame)
---------------------------------------------------------------------------

local function gossipWalk(gf, create)
    local gp = field(gf, "GreetingPanel")
    local sbox = field(gp, "ScrollBox")
    if create then
        -- parchemin : Blizzard lui repose son atlas (theme), jamais l alpha
        fade(field(gf, "Background"))
        dressPanel(gp, sbox, 3, 20, field(gp, "ScrollBar"))
    end
    -- lignes : enfants de la liste deroulee, recycles par Blizzard ; les
    -- cadres de mesure (enfants directs de GossipFrame) ne sont jamais vus
    local st = field(sbox, "ScrollTarget")
    for _, c in ipairs(childrenOf(st)) do
        if not mine[c] then
            local gt = field(c, "GreetingText")
            if objType(gt) == "FontString" then
                texts[gt] = "body"
                themed[gt] = true
            elseif isButton(c) and objType(field(c, "Icon")) == "Texture" then
                addLine(c, create)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Quetes (QuestFrame)
---------------------------------------------------------------------------

local QPANELS = {
    { "QuestFrameGreetingPanel", "QuestGreetingScrollFrame" },
    { "QuestFrameDetailPanel", "QuestDetailScrollFrame" },
    { "QuestFrameProgressPanel", "QuestProgressScrollFrame" },
    { "QuestFrameRewardPanel", "QuestRewardScrollFrame" },
}

-- textes propres au QuestFrame (QuestInfo est a JournalQuetes.lua)
local STATIC = {
    GreetingText = "body", CurrentQuestsText = "gold", AvailableQuestsText = "gold",
    QuestProgressTitleText = "gold", QuestProgressText = "body",
    QuestProgressRequiredItemsText = "gold", QuestProgressRequiredMoneyText = "body",
}

-- separateur de l accueil : filet d or a nous, pose sur le contenu deroule
-- de l accueil (cadre simple, sans mise en page ni QuestInfo)
local breakLine

local function greetingBreak()
    local brk, sc = _G.QuestGreetingFrameHorizontalBreak, _G.QuestGreetingScrollChildFrame
    if objType(brk) ~= "Texture" or type(sc) ~= "table" or not sc.CreateTexture then return end
    fade(brk)
    if breakLine then return end
    breakLine = goldLine(sc, "ARTWORK", 1)
    breakLine:SetPoint("LEFT", brk, "LEFT", 0, 0)
    breakLine:SetPoint("RIGHT", brk, "RIGHT", -16, 0)
    onlyIf(breakLine, function() return shown(brk) end)
end

-- cadre des recompenses dans le QuestFrame habille ?
local function rfOurs()
    local p = parentOf(_G.QuestInfoRewardsFrame)
    if not p then return false end
    if p == _G.QuestDetailScrollChildFrame then return dressed[_G.QuestFrameDetailPanel] == true end
    if p == _G.QuestRewardScrollChildFrame then return dressed[_G.QuestFrameRewardPanel] == true end
    return false
end

-- bandeau "Recompenses" : pose sur le cadre des recompenses lui-meme (il
-- suit l alpha que Blizzard lui donne pendant la description tapee)
local rewardBand

-- marque de secours du choix : nos textures posees sur la surbrillance de
-- Blizzard (QuestInfoItemHighlight), qu il ancre a -8, +7 du coin de la
-- case choisie et montre au clic (icone de 39 px au coin de la case,
-- LargeItemButtonTemplate) ; au-dessus des cases (niveau releve par
-- Blizzard), donc sans fond sur l icone. Montree seulement si la case
-- choisie n a pas encore nos textures (creee par Blizzard en combat)
local spare

local function spareMark(hl)
    if spare or objType(hl) ~= "Frame" or not hl.CreateTexture then return end
    local C = ns.COLORS
    local s = { list = {} }
    local function own(t) s.list[#s.list + 1] = t return t end
    local spot = own(tex(hl, "ARTWORK", 0))
    spot:SetPoint("TOPLEFT", hl, "TOPLEFT", 8, -7)
    spot:SetSize(39, 39)
    spot:SetColorTexture(0, 0, 0, 0)
    local sel = own(tex(hl, "ARTWORK", 1))
    sel:SetPoint("TOPLEFT", spot, "TOPRIGHT", 3, 0)
    sel:SetPoint("BOTTOMLEFT", spot, "BOTTOMRIGHT", 3, 0)
    sel:SetWidth(105)
    accent(sel, 0.25, 0.02)
    for _, out in ipairs({ 1, 2 }) do
        for _, t in ipairs(ring(hl, spot, "OVERLAY", 7, out)) do
            own(t):SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
        end
    end
    local bar = own(tex(hl, "OVERLAY", 7))
    bar:SetPoint("TOPRIGHT", spot, "TOPLEFT", -4, 2)
    bar:SetPoint("BOTTOMRIGHT", spot, "BOTTOMLEFT", -4, -2)
    bar:SetWidth(2)
    bar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    spare = s
end

local function rewardsWalk(rf)
    spareMark(field(rf, "ItemHighlight"))
    if not rewardBand and rf.CreateTexture then
        local header = field(rf, "Header")
        if objType(header) == "FontString" then
            local band = tex(rf, "BACKGROUND", -8)
            band:SetPoint("TOPLEFT", rf, "TOPLEFT", -4, 4)
            band:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 4, -3)
            accent(band, 0.32, 0.03)
            local line = goldLine(rf, "BACKGROUND", -7)
            line:SetPoint("TOPLEFT", band, "BOTTOMLEFT")
            line:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT")
            local function on() return rfOn and shown(header) end
            onlyIf(band, on)
            onlyIf(line, on)
            rewardBand = band
        end
    end
    -- cases : boutons d objets, d honneur, de points, de sorts (pools de
    -- Blizzard compris), cadre du titre ; creees au fil de l eau
    for _, b in ipairs(childrenOf(rf)) do
        if not boxes[b] and not mine[b] and isButton(b) then
            local icon, nf = field(b, "Icon"), field(b, "NameFrame")
            if objType(icon) == "Texture" and objType(nf) == "Texture" then
                local bx = dressBox(b, icon, nf, true)
                if bx and rfOn then fadeBox(bx) end
            end
        end
    end
    local tf = field(rf, "TitleFrame")
    if tf and not boxes[tf] then
        local icon, l, m, r = field(tf, "Icon"), field(tf, "FrameLeft"), field(tf, "FrameCenter"), field(tf, "FrameRight")
        if objType(icon) == "Texture" and objType(m) == "Texture" and objType(r) == "Texture" then
            local bx = dressBox(tf, icon, nil, true, r, { l, m, r })
            if bx and rfOn then fadeBox(bx) end
        end
    end
end

-- cases de QuestInfoRewardsFrame : decor de Blizzard eteint, icone
-- recadree (et notre decor montre) seulement dans le QuestFrame habille ;
-- rendu ailleurs (fiche seule, sur parchemin). Hors combat seulement.
local function rfSwitch()
    local want = (live and rfOurs()) and true or false
    if want == rfOn then return false end
    for _, bx in pairs(boxes) do
        if bx.shared then
            if want then
                fadeBox(bx)
                cropIcon(bx.icon)
            else
                unfadeBox(bx)
                uncrop(bx.icon)
            end
        end
    end
    -- surbrillance du choix de Blizzard (texture anonyme en ADD)
    for _, r in ipairs(regionsOf(field(_G.QuestInfoRewardsFrame, "ItemHighlight"))) do
        if want then fade(r) else unfade(r) end
    end
    rfOn = want
    return true
end

local function questWalk(qf, create)
    if create then
        for _, p in ipairs(QPANELS) do
            local panel, sf = _G[p[1]], _G[p[2]]
            if parentOf(panel) == qf and objType(sf) then dressPanel(panel, sf, 0, 23) end
        end
        greetingBreak()
        for name, role in pairs(STATIC) do
            local fs = _G[name]
            if objType(fs) == "FontString" and below(fs, qf, 5) then texts[fs] = role end
        end
        -- objets demandes (progression)
        for i = 1, 6 do
            local b = _G["QuestProgressItem" .. i]
            if isButton(b) and below(b, qf, 5) then
                local icon, nf = field(b, "Icon"), field(b, "NameFrame")
                if objType(icon) == "Texture" and objType(nf) == "Texture" then
                    local bx = dressBox(b, icon, nf, false)
                    if bx then fadeBox(bx) end
                end
            end
        end
        local rf = _G.QuestInfoRewardsFrame
        if type(rf) == "table" and rf.GetChildren then rewardsWalk(rf) end
        -- icones changees par Blizzard : recadrees de nouveau
        for b, bx in pairs(boxes) do
            if visible(b) and (not bx.shared or rfOn) then cropIcon(bx.icon) end
        end
    end
    -- lignes de l accueil : pool de Blizzard, enfants du panneau (pas des
    -- boutons rouges, qui ont Left / Middle / Right)
    local gp = _G.QuestFrameGreetingPanel
    if parentOf(gp) == qf then
        for _, c in ipairs(childrenOf(gp)) do
            if not mine[c] and isButton(c) and objType(field(c, "Icon")) == "Texture" and not field(c, "Left") then
                addLine(c, create)
            end
        end
    end
end

-- parcours : creations et alpha de Blizzard seulement si "create" (hors
-- combat) ; sinon simple reperage des lignes nouvelles (lecture)
local function walk(create)
    local gf = _G.GossipFrame
    if type(gf) == "table" and gf.GetChildren then run("NpcGossip", gossipWalk, gf, create) end
    local qf = _G.QuestFrame
    if type(qf) == "table" and qf.GetChildren then run("NpcQuest", questWalk, qf, create) end
end

---------------------------------------------------------------------------
-- Couleur des textes propres aux deux fenetres (lignes, accueil,
-- progression). Blizzard ne relit jamais ces couleurs ; on ne rend la
-- sienne que si nous sommes encore les derniers a l avoir changee.
---------------------------------------------------------------------------

local function colorOf(fs)
    local ok, r, g, b = pcall(fs.GetTextColor, fs)
    if ok and num(r) and num(g) and num(b) then return r, g, b end
end

local function isOurs(t, r, g, b)
    return t.set ~= nil and near(r, t.set[1]) and near(g, t.set[2]) and near(b, t.set[3])
end

-- texte portant un code couleur (|cff000000 des titres de quetes)
local function hasCode(fs)
    local ok, s = pcall(fs.GetText, fs)
    if not ok or type(s) ~= "string" or issecret(s) then return false end
    return s:find("|c", 1, true) ~= nil or s:find("|C", 1, true) ~= nil
end

-- theme sombre de Blizzard (contraste du texte des quetes a 4) : il pose
-- alors lui-meme la couleur fixe a vrai sur les textes de son theme. Lu
-- par l API du moteur, jamais par QuestTextContrast
local function darkText()
    local cv = C_CVar
    local fn = type(cv) == "table" and cv.GetCVar
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn, "questTextContrast")
    if not ok or issecret(v) or (type(v) ~= "string" and type(v) ~= "number") then return false end
    return tonumber(v) == 4
end

local function tint(fs, c)
    if objType(fs) ~= "FontString" then return end
    local t = tints[fs]
    if not t then
        t = {}
        tints[fs] = t
    end
    local r, g, b = colorOf(fs)
    local ours = r ~= nil and isOurs(t, r, g, b)
    -- couleur posee par Blizzard depuis notre passage : nouvelle reference ;
    -- texte de son theme : sa couleur fixe reposee avec (la notre oubliee)
    if r and not ours then
        t.r, t.g, t.b = r, g, b
        if themed[fs] then t.fixed = nil end
    end
    local code = hasCode(fs)
    if not (r and near(r, c[1]) and near(g, c[2]) and near(b, c[3])) then
        pcall(fs.SetTextColor, fs, c[1], c[2], c[3])
        -- Blizzard remet la couleur fixe a faux en meme temps que sa couleur
        if code then
            pcall(fs.SetFixedColor, fs, true)
            t.fixed = true
        end
    elseif code and not t.fixed then
        pcall(fs.SetFixedColor, fs, true)
        t.fixed = true
    end
    t.set = c
end

-- rendu a Blizzard : sa couleur si nous sommes encore les derniers a l avoir
-- changee ; la couleur fixe qu il y pose (texte de son theme : vraie en
-- theme sombre ; autre texte : jamais posee, donc fausse). Texte de son
-- theme recolore depuis : sa couleur fixe est deja reposee
local function untint(fs, t)
    tints[fs] = nil
    local r, g, b = colorOf(fs)
    local ours = r ~= nil and isOurs(t, r, g, b)
    if ours and t.r then pcall(fs.SetTextColor, fs, t.r, t.g, t.b) end
    if t.fixed and (ours or not themed[fs]) then
        pcall(fs.SetFixedColor, fs, (themed[fs] and darkText()) and true or false)
    end
end

-- ligne grisee par Blizzard (quete de bas niveau ou ignoree) : icone a 0.5
-- ou 0.75, texte attenue d autant
local dimRef, dimCol
local function dimColor()
    local c = ns.COLORS.text
    if c ~= dimRef then
        dimRef = c
        dimCol = { c[1] * DIM, c[2] * DIM, c[3] * DIM }
    end
    return dimCol
end

local function textPass(on)
    if not on then
        for fs, t in pairs(tints) do untint(fs, t) end
        return
    end
    local C = ns.COLORS
    for fs, role in pairs(texts) do
        if visible(fs) then tint(fs, role == "gold" and C.gold or C.text) end
    end
    for b, l in pairs(lines) do
        if visible(b) then
            local v = vertexOf(l.icon)
            tint(l.fs, (v and v < 0.9) and dimColor() or C.text)
        end
    end
end

---------------------------------------------------------------------------
-- Etat de NOS textures (choix de recompense, survol, qualite) : lectures,
-- puis nos regions seulement ; aussi en combat
---------------------------------------------------------------------------

local function choiceInfo()
    local qi = _G.QuestInfoFrame
    local choose = value(qi, "chooseItems")
    return choose and true or false, num(value(qi, "itemChoice"))
end

local function isChoice(b) return value(b, "type") == "choice" end

local function edges(bx, r, g, b, sel)
    if bx.cr == r and bx.cg == g and bx.cb == b and bx.csel == sel then return end
    bx.cr, bx.cg, bx.cb, bx.csel = r, g, b, sel
    local C = ns.COLORS
    paint(bx.edges, r, g, b, 1)
    paintC(bx.nameEdges, sel and C.gold or C.border, sel and 1 or 0.7)
    for _, t in ipairs(bx.outer) do t:SetShown(sel) end
    bx.sel:SetShown(sel)
    bx.bar:SetShown(sel)
end

local function boxState(b, bx, choose, choice)
    local C = ns.COLORS
    local sel = false
    if bx.shared and choose and choice and choice > 0 and isChoice(b) then
        sel = num(ask(b, "GetID")) == choice
    end
    if sel then
        edges(bx, C.gold[1], C.gold[2], C.gold[3], true)
    elseif bx.shared and choose and isChoice(b) and isOver(b) then
        edges(bx, C.violet[1], C.violet[2], C.violet[3], false)
    elseif redTinted(bx.nf) or redTinted(bx.icon) then
        edges(bx, 0.9, 0.15, 0.15, false)
    else
        local r, g, bl = borderColor(bx.border)
        if r then edges(bx, r, g, bl, false) else edges(bx, C.border[1], C.border[2], C.border[3], false) end
    end
    return sel
end

local function state()
    for t, fn in pairs(extras) do
        local ok, v = pcall(fn)
        v = live and ok and v == true
        if shownAs[t] ~= v then
            shownAs[t] = v
            t:SetShown(v)
        end
    end
    local choose, choice = choiceInfo()
    local picked = false
    for b, bx in pairs(boxes) do
        local v = live and (not bx.shared or rfOn)
        if bx.vis ~= v then
            bx.vis = v
            for _, t in ipairs(bx.list) do t:SetShown(v) end
            bx.cr = nil
        end
        if v and visible(b) and boxState(b, bx, choose, choice) then picked = true end
    end
    -- marque de secours : un choix fait sur une case sans nos textures
    -- (Blizzard la montre ou la cache avec sa surbrillance)
    if spare then
        local v = (live and rfOn and choose and choice ~= nil and choice > 0 and not picked) and true or false
        if spare.vis ~= v then
            spare.vis = v
            for _, t in ipairs(spare.list) do t:SetShown(v) end
        end
    end
    local C = ns.COLORS
    for sb, k in pairs(bars) do
        if visible(sb) then
            local over = isOver(k.thumb)
            if k.over ~= over then
                k.over = over
                if over then k.knob:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.9)
                else k.knob:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.6) end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Pose et retrait de l habillage
---------------------------------------------------------------------------

-- habillage pose (hors combat) : parcours complet, fenetres cachees
-- comprises (elles existent des le chargement), puis nos textures montrees
local function dressAll()
    walk(true)
    if not live then
        for t in pairs(base) do t:Show() end
        live = true
    end
end

-- habillage coupe (hors combat) : tout est rendu a Blizzard
local function restore()
    for t in pairs(faded) do unfade(t) end
    for t, c in pairs(tinted) do
        tinted[t] = nil
        pcall(t.SetVertexColor, t, c[1], c[2], c[3], c[4])
    end
    for t in pairs(cropped) do uncrop(t) end
    for p in pairs(dressed) do dressed[p] = nil end
    for t in pairs(mine) do t:Hide() end
    for t in pairs(shownAs) do shownAs[t] = nil end
    for _, bx in pairs(boxes) do bx.vis, bx.cr = false, nil end
    if spare then spare.vis = false end
    for _, k in pairs(bars) do k.over = nil end
    live, rfOn = false, false
end

-- hotes de QuestInfo eclaircis par JournalQuetes.lua : les contenus
-- deroules du detail et de la recompense, tant que le QuestFrame habille
-- est ouvert
local hostList = {}
local function questInfoHosts()
    for i = #hostList, 1, -1 do hostList[i] = nil end
    if not live or not visible(_G.QuestFrame) then return hostList end
    if dressed[_G.QuestFrameDetailPanel] then hostList[#hostList + 1] = _G.QuestDetailScrollChildFrame end
    if dressed[_G.QuestFrameRewardPanel] then hostList[#hostList + 1] = _G.QuestRewardScrollChildFrame end
    return hostList
end
ns.QuestInfoHosts = ns.QuestInfoHosts or {}
table.insert(ns.QuestInfoHosts, questInfoHosts)

local function questInfoText()
    if ns.QuestInfoTextPass then ns.QuestInfoTextPass() end
end

-- Skins.lua : ne pas aplatir nos lignes et cases, ne pas effacer nos textures
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
-- Releves
---------------------------------------------------------------------------

-- cle d affichage (sans allocation) : un changement relance le parcours
-- dans la meme image (lignes nouvelles, autre panneau, cases nouvelles)
local last, cur = {}, {}
local function keyChanged()
    local gf, rf = _G.GossipFrame, _G.QuestInfoRewardsFrame
    cur[1] = visible(gf)
    cur[2] = numKids(field(field(field(gf, "GreetingPanel"), "ScrollBox"), "ScrollTarget"))
    for i, p in ipairs(QPANELS) do cur[2 + i] = visible(_G[p[1]]) end
    cur[7] = numKids(_G.QuestFrameGreetingPanel)
    cur[8] = numKids(rf)
    cur[9] = parentOf(rf) or false
    local changed = false
    for i = 1, 9 do
        if last[i] ~= cur[i] then
            changed = true
            last[i] = cur[i]
        end
    end
    return changed
end

local ev = CreateFrame("Frame")
local acc, wasOpen = 0, false

-- fin du combat : parcours complet tout de suite
ev:SetScript("OnEvent", function() for k in pairs(last) do last[k] = nil end end)
pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")

-- bascule des cases partagees (hors combat) : etat de nos textures suivi
-- dans la meme image
local function switchRewards()
    local ok, switched = pcall(rfSwitch)
    if not ok then
        report("NpcRewards", switched)
    elseif switched then
        run("NpcState", state)
    end
end

ev:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    local combat = InCombatLockdown()
    local on = db() ~= nil
    if not combat then
        if on and not live then
            run("NpcDress", dressAll)
            for k in pairs(last) do last[k] = nil end
            -- nos textures naissent montrees : etat applique tout de suite,
            -- fenetres des PNJ fermees comprises (cases partagees et bandeau
            -- caches tant que le cadre des recompenses n est pas chez nous :
            -- la fiche seule peut s ouvrir la premiere)
            run("NpcState", state)
        elseif not on and live then
            run("NpcRestore", restore)
            run("NpcText", textPass, false)
            questInfoText()
            run("NpcState", state)
        end
        -- le cadre des recompenses peut passer dans la fiche seule, fenetres
        -- des PNJ fermees
        switchRewards()
    end
    local open = visible(_G.GossipFrame) or visible(_G.QuestFrame)
    if not open then
        if wasOpen then
            -- passe finale : textes de QuestInfo rendus hors du QuestFrame
            wasOpen = false
            questInfoText()
            run("NpcState", state)
        end
        return
    end
    wasOpen = true
    if live then
        if keyChanged() or acc >= 0.25 then
            acc = 0
            run("NpcWalk", walk, not combat)
            if not combat then switchRewards() end
        end
        -- a chaque image : textes (avant le rendu) et etat de nos textures
        run("NpcText", textPass, true)
        if visible(_G.QuestFrame) then questInfoText() end
    end
    run("NpcState", state)
end)
