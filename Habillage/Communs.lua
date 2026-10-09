--[[--------------------------------------------------------------------------
    CorpUI - module Habillage : elements communs a toutes les fenetres

    Quelques elements de Blizzard reviennent dans plusieurs fenetres deja
    habillees et y restaient "non CorpUI". Ils sont repris ici, une seule
    fois et avec le meme rendu partout :
      1. menus a fleche : tout bouton dont une texture porte l atlas
         common-dropdown-a-button* (WowStyle1ArrowDropdownTemplate,
         WowStyle1DropdownTemplate, UIPanelArrowDropdownButtonTemplate,
         bouton des filtres de la carte, choix d extension des metiers...).
         La fleche jaune carree passe a alpha 0 (Blizzard change son atlas a
         chaque etat, jamais son alpha : reverifiee a chaque releve), une
         plaque plate CorpUI et le chevron d or des menus de CorpUI (deux
         barres pivotees, recette de ns.UI.Select) prennent sa place ; le
         lisere passe a l or au survol ou menu ouvert (champ "menu" pose par
         DropdownButtonMixin, lu), le tout grise si desactive. Un menu a
         texte (fond common-dropdown-textholder : Duree de l hotel des
         ventes, classe des apparences, etages de la carte...) devient un
         champ sombre a lisere, le texte de Blizzard reste tel quel ;
      2. cases a cocher classiques (texture normale UI-CheckBox-Up, ou atlas
         checkbox-minimal) : leurs textures a alpha 0, carre sombre, lisere,
         coche d or selon GetChecked (lecture) ; leur libelle passe a la
         couleur du texte de CorpUI (blanc au survol, attenue si desactivee)
         au lieu du jaune de Blizzard ;
      3. onglets du haut (PanelTopTabButtonTemplate, champ isTopTab) : leurs
         textures a alpha 0, plaque plate ; l actif (LeftActive montre par
         Blizzard) en lisere et texte d or. Le clignotement "nouveau" d un
         onglet (FlashFrame des Ensembles) perd sa lueur jaune : la notre,
         posee sur ce cadre, clignote avec lui ;
      4. barres de defilement minimalistes (MinimalScrollBar : Track.Thumb,
         Back, Forward) des fenetres sans habillage en profondeur (macros,
         liste des add-ons...) : rail et curseur de Blizzard a alpha 0, un
         filet pour le rail, un curseur fin a l accent (or au survol), nos
         chevrons a la place des fleches (ns.UI.ArrowChevron) ;
      5. fleches de repli "bag-arrow" (categories de la liste des add-ons) :
         leurs textures eteintes par la couleur, notre chevron a la place,
         dans le sens que Blizzard leur donne par rotation (lue).
    Les enfants d un bouton ne sont jamais parcourus, sauf ceux de ROW_KEYS
    (case "Enabled" d une ligne d add-on, fleche "CollapseExpand" d une
    categorie).

    Fenetres parcourues : celles de Fenetres.lua, plus quelques fenetres
    annexes posees sur UIParent dont l habillage en profondeur ne traite
    plus les menus (EXTRA_ROOTS : dialogues des communautes).

    Partage avec les autres fichiers (le plus simple, sans course) :
      - les menus a fleche sont a ce fichier seul : les habillages en
        profondeur ne les traitent plus, et ns.SkinCommon(f) dit a qui le
        demande si un cadre est a nous (menu, case ou onglet du haut) ;
        Skins.lua ne touche a aucun d eux ;
      - cases et onglets du haut : les habillages en profondeur (hotel des
        ventes, collections, metiers...) gardent la main. Un element n est
        pris ici que s il est reste libre pendant GRACE secondes de releves
        continus (aucun fichier ne l a reclame par ns.SkinClaimed, ni n a
        eteint ses textures), le temps que leurs propres releves (une
        seconde au plus) passent.

    Regles de ce client (taint, valeurs secretes), comme les autres
    habillages :
      - aucun crochet, aucun SetScript sur un cadre de Blizzard, aucun champ
        ecrit dans leurs cadres ou leurs tables : notre etat est range dans
        des tables faibles a nous, indexees par le cadre ;
      - aucune taille, position, strate, niveau, parent, souris ni
        visibilite de Blizzard modifiee, aucune de leurs fonctions Lua
        appelee : seulement des accesseurs du moteur (IsVisible, GetAtlas,
        GetChecked...), l alpha de leurs textures et la couleur du texte
        des onglets du haut ; nos propres textures et textes poses dessus ;
      - releve periodique (0,25 s) des seules fenetres visibles de
        Fenetres.lua, en profondeur bornee, jamais dans un bouton, un gros
        pool ou le canevas de la carte ; rien en combat ; toute valeur lue
        est verifiee (pcall, issecretvalue). Les reglages du module
        Habillage (case generale et groupes) sont respectes.
----------------------------------------------------------------------------]]

local _, ns = ...

local issecret = issecretvalue or function() return false end
local weak = { __mode = "k" }

local mine = setmetatable({}, weak)      -- nos regions (a ne jamais traiter)
local kinds = setmetatable({}, weak)     -- cadre -> "drop", "check", "tab" ou false (forme fixe)
local drops = setmetatable({}, weak)     -- menu a fleche -> { arrows, holders, fill, edges, chev }
local checks = setmetatable({}, weak)    -- case a cocher -> { fill, edges, mark }
local tabs = setmetatable({}, weak)      -- onglet du haut -> { texs, fill, edges, text, act }
local bars = setmetatable({}, weak)      -- barre de defilement -> { thumb, knob }
local folds = setmetatable({}, weak)     -- fleche de repli -> { texs, normal, chev }
local others = setmetatable({}, weak)    -- case / onglet repris ailleurs (ou protege) : ignore
local pending = setmetatable({}, weak)   -- candidat -> { t = premier releve, last = dernier releve }
local owner = setmetatable({}, weak)     -- element habille -> groupe de sa fenetre
local shownWin = setmetatable({}, weak)  -- fenetre -> visible au releve precedent
local lastWalk = setmetatable({}, weak)  -- fenetre -> heure de son dernier parcours

local TICK = 0.25       -- releve des etats
local WALK = 0.5        -- parcours d une fenetre ouverte (tout de suite a l ouverture)
local GRACE = 1.25      -- cases et onglets : libres au moins ce temps avant d etre pris
local MAXDEPTH = 7      -- profondeur du parcours sous la fenetre
local MAXKIDS = 48      -- cadre a plus d enfants (pool, liste) : pas de descente
local BUDGET = 800      -- cadres examines au plus par fenetre et par parcours

-- fenetres dont les controles restent a Blizzard (options du jeu : des
-- centaines de controles recycles a chaque page)
local SKIP_WINDOWS = { SettingsPanel = true, KeyBindingFrame = true }
-- fenetres annexes absentes de Fenetres.lua (parent UIParent), par groupe :
-- dialogues de Blizzard_Communities habilles par Communautes.lua, dont les
-- menus (delai d expiration, nombre d utilisations, objectif, langue...)
-- sont a nous. Jamais CommunitiesAddDialog / CommunitiesCreateDialog /
-- CommunitiesAvatarPickerDialog (environnement securise).
local EXTRA_ROOTS = {
    social = { "CommunitiesSettingsDialog", "CommunitiesTicketManagerDialog", "CommunitiesGuildTextEditFrame",
               "CommunitiesGuildLogFrame", "CommunitiesGuildNewsFiltersFrame" },
    -- choix d icone d une macro (cases et champ : Macros.lua)
    system = { "MacroPopupFrame" },
}
-- sous-cadres jamais parcourus (canevas et punaises des cartes)
local SKIP_KEYS = { "ScrollContainer" }
-- enfants d un bouton tout de meme examines : case d une ligne d add-on,
-- fleche de repli d une categorie (AddonList)
local ROW_KEYS = { "Enabled", "CollapseExpand" }

-- textures d un onglet du haut (PanelTabButtonTemplate)
local TAB_KEYS = { "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive",
                   "LeftHighlight", "MiddleHighlight", "RightHighlight" }

-- textures d etat d une case a cocher (accesseurs du moteur)
local CHECK_STATES = { "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetCheckedTexture",
                       "GetDisabledCheckedTexture", "GetDisabledTexture" }

-- repli si le chemin de la texture est illisible : identifiant du fichier
-- Interface\Buttons\UI-CheckBox-Up
local CHECK_IDS = { [130755] = true }

local WHITE = { 1, 1, 1 }

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

-- champ simple (texte, nombre, booleen), jamais secret
local function value(f, key)
    if type(f) ~= "table" then return nil end
    local ok, v = pcall(get, f, key)
    if not ok or v == nil or issecret(v) then return nil end
    local t = type(v)
    if t == "string" or t == "number" or t == "boolean" then return v end
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

-- texture de Blizzard a alpha 0 (seulement si besoin : releve frequent)
local function fade(t)
    if objType(t) ~= "Texture" or mine[t] then return end
    if alphaOf(t) ~= 0 then pcall(t.SetAlpha, t, 0) end
end

-- texture dont Blizzard pilote l alpha (survol des menus de la carte, de
-- la guilde...) : eteinte par la couleur, jamais par l alpha (vu en jeu :
-- l alpha remis par Blizzard puis par nous faisait clignoter la fleche)
local function veil(t)
    if objType(t) ~= "Texture" or mine[t] then return end
    local ok, _, _, _, a = pcall(t.GetVertexColor, t)
    if ok and a ~= nil and not issecret(a) and a == 0 then return end
    pcall(t.SetVertexColor, t, 1, 1, 1, 0)
end

local function tex(host, layer, sub)
    local t = host:CreateTexture(nil, layer, nil, sub)
    mine[t] = true
    ns.NoSnap(t)   -- traits fins toujours dessines (Core.lua)
    return t
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

---------------------------------------------------------------------------
-- Reconnaissance (forme fixe pour la vie du cadre : retenue)
---------------------------------------------------------------------------

-- fleche des menus (les variantes "-settings" sont des roues dentees)
local function arrowAtlas(a)
    if not a then return false end
    if a:find("^common%-dropdown%-a%-button") then return not a:find("settings", 1, true) end
    return a:find("^common%-dropdown%-classic%-a%-button") ~= nil
end

local function holderAtlas(a)
    if not a then return false end
    return a:find("^common%-dropdown%-textholder") ~= nil or a:find("^common%-dropdown%-classic%-textholder") ~= nil
end

-- case classique : texture normale UI-CheckBox-Up, ou atlas checkbox-minimal
local function classicCheck(cb)
    local n = askObj(cb, "GetNormalTexture")
    if objType(n) ~= "Texture" then return false end
    local a = atlasOf(n)
    if a then return a == "checkbox-minimal" end
    for _, m in ipairs({ "GetTextureFilePath", "GetTexture", "GetTextureFileID" }) do
        local v = ask(n, m)
        if type(v) == "string" then
            if v:lower():find("ui%-checkbox%-up") then return true end
            local id = tonumber(v)
            if id and CHECK_IDS[id] then return true end
        elseif type(v) == "number" and CHECK_IDS[v] then
            return true
        end
    end
    return false
end

-- onglet du haut : PanelTopTabButtonMixin pose isTopTab (lu, jamais ecrit)
local function topTab(t)
    if not rawequal(value(t, "isTopTab"), true) then return false end
    return objType(field(t, "LeftActive")) == "Texture" and objType(field(t, "Left")) == "Texture"
end

local function classify(f)
    local k = kinds[f]
    if k ~= nil then return k end
    local t = objType(f)
    if not t then return false end
    k = false
    if t == "DropdownButton" or t == "Button" then
        for _, r in ipairs(regionsOf(f)) do
            if not mine[r] and arrowAtlas(atlasOf(r)) then
                k = "drop"
                break
            end
        end
        if not k and t == "Button" and topTab(f) then k = "tab" end
        if not k and t == "Button" and atlasOf(askObj(f, "GetNormalTexture")) == "bag-arrow" then k = "fold" end
    elseif t == "CheckButton" then
        if classicCheck(f) then k = "check" end
    end
    kinds[f] = k
    return k
end

---------------------------------------------------------------------------
-- 1. Menus a fleche
---------------------------------------------------------------------------

local function dropState(b, s)
    local C = ns.COLORS
    -- Blizzard repose l atlas de la fleche a chaque etat, jamais son alpha
    local open = false
    for _, r in ipairs(s.arrows) do
        veil(r)
        local a = atlasOf(r)
        if a and a:find("%-open") then open = true end
    end
    for _, r in ipairs(s.holders) do veil(r) end
    -- menu ouvert : DropdownButtonMixin garde le menu dans self.menu
    -- (IsMenuOpen) ; lu seulement. Les fleches seules (reglages du
    -- grimoire, filtres de la carte) n ont jamais d atlas "-open"
    if not open and field(b, "menu") ~= nil then open = true end
    local en = enabled(b)
    if s.edges then paint(s, (en and (open or isOver(b))) and C.gold or C.border) end
    local a = en and 1 or 0.5
    if s.fill and s.a ~= a then
        s.a = a
        s.fill:SetAlpha(a)
    end
    if s.en ~= en then
        s.en = en
        local c = en and C.gold or C.text
        for _, t in ipairs(s.chev) do t:SetVertexColor(c[1], c[2], c[3], en and 1 or 0.4) end
    end
end

-- chevron d or des menus de CorpUI (image de ns.UI.Chevron), centre en
-- (x, 0) de "point"
local function chevron(b, point, x)
    local t = ns.UI.Chevron(b, 14, "DOWN")
    mine[t] = true
    t:SetPoint("CENTER", b, point, x, 0)
    return { t }
end

local function dressDrop(b)
    local C = ns.COLORS
    local s = { arrows = {}, holders = {} }
    local seen = {}
    local function sort(r)
        if seen[r] or mine[r] or objType(r) ~= "Texture" then return end
        seen[r] = true
        local a = atlasOf(r)
        if arrowAtlas(a) then s.arrows[#s.arrows + 1] = r
        elseif holderAtlas(a) then s.holders[#s.holders + 1] = r end
    end
    for _, r in ipairs(regionsOf(b)) do sort(r) end
    sort(askObj(b, "GetHighlightTexture"))
    s.field = #s.holders > 0
    -- un autre fichier y a deja pose sa plaque : le chevron seul
    local okC, cl = pcall(ns.SkinClaimed, b)
    if not (okC and cl) then
        s.fill = tex(b, "BACKGROUND", -8)
        s.hl = tex(b, "HIGHLIGHT")
        if s.field then
            -- menu a texte : un champ sombre sur tout le bouton
            s.fill:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
            s.fill:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
            s.fill:SetColorTexture(0, 0, 0, 0.55)
            ns.UI.Gradient(s.hl, "VERTICAL", C.violet[1], C.violet[2], C.violet[3], 0.04, C.violet[1], C.violet[2], C.violet[3], 0.22)
        else
            -- fleche seule : plaque carree centree (15 a 32 px selon le modele)
            local w, h = num(ask(b, "GetWidth")), num(ask(b, "GetHeight"))
            local side = 20
            if w and h then side = math.max(18, math.min(22, math.floor(math.max(w, h) + 4))) end
            s.fill:SetSize(side, side)
            s.fill:SetPoint("CENTER", b, "CENTER", 0, 0)
            s.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.95)
            ns.UI.Gradient(s.hl, "VERTICAL", C.violet[1], C.violet[2], C.violet[3], 0.05, C.violet[1], C.violet[2], C.violet[3], 0.28)
        end
        s.hl:SetAllPoints(s.fill)
        s.edges = ring(b, s.fill, "BACKGROUND", -7)
    end
    -- chevron d or : au bout du champ (comme ns.UI.Select), ou au centre
    -- de la plaque
    if s.field then s.chev = chevron(b, "RIGHT", -12)
    else s.chev = chevron(b, "CENTER", 0) end
    drops[b] = s
    dropState(b, s)
end

---------------------------------------------------------------------------
-- 2. Cases a cocher
---------------------------------------------------------------------------

local function checkState(cb, k)
    local C = ns.COLORS
    for _, m in ipairs(CHECK_STATES) do fade(askObj(cb, m)) end
    local on = ask(cb, "GetChecked") == true
    if k.on ~= on then
        k.on = on
        k.mark:SetShown(on)
    end
    local en = enabled(cb)
    local a = en and 1 or 0.4
    if k.a ~= a then
        k.a = a
        k.mark:SetAlpha(a)
    end
    local over = en and isOver(cb)
    paint(k, over and C.gold or C.border)
    -- libelle (GameFontNormalSmall, NORMAL_FONT_COLOR pour Mode achat
    -- immediat) : couleur du texte de CorpUI comme ns.UI.Check, reposee a
    -- chaque releve (Blizzard peut la remettre), jamais la police
    if k.label then
        local c = over and WHITE or C.text
        local m = en and 1 or 0.5
        pcall(k.label.SetTextColor, k.label, c[1] * m, c[2] * m, c[3] * m)
    end
end

local function dressCheck(cb)
    local C = ns.COLORS
    local w, h = num(ask(cb, "GetWidth")), num(ask(cb, "GetHeight"))
    -- carre de 14 px comme les autres habillages ; 12 sur une petite case,
    -- 16 sur une grande (36 px : Mode achat immediat de l hotel des ventes)
    local side = 14
    if w and h then
        local m = math.min(w, h)
        if m <= 24 then side = 12 elseif m >= 36 then side = 16 end
    end
    local k = {}
    k.fill = tex(cb, "BACKGROUND", -8)
    k.fill:SetSize(side, side)
    k.fill:SetPoint("CENTER", cb, "CENTER", 0, 0)
    k.fill:SetColorTexture(0, 0, 0, 0.6)
    k.edges = ring(cb, k.fill, "BORDER", 7)
    k.mark = tex(cb, "OVERLAY", 7)
    k.mark:SetPoint("TOPLEFT", k.fill, "TOPLEFT", 3, -3)
    k.mark:SetPoint("BOTTOMRIGHT", k.fill, "BOTTOMRIGHT", -3, 3)
    ns.UI.Gradient(k.mark, "VERTICAL", C.gold[1] * 0.75, C.gold[2] * 0.75, C.gold[3] * 0.75, 1, C.gold[1], C.gold[2], C.gold[3], 1)
    k.mark:Hide()
    k.on = false
    -- libelle de UICheckButtonTemplate (parentKey Text, alias text)
    local label = field(cb, "Text") or field(cb, "text")
    if objType(label) == "FontString" then k.label = label end
    checks[cb] = k
    checkState(cb, k)
end

---------------------------------------------------------------------------
-- 3. Onglets du haut
---------------------------------------------------------------------------

-- l art de Blizzard occupe le bas de l onglet (75 % de 32 px) ; l inactif
-- est plus court, comme chez Blizzard (son texte est 4 px plus bas)
local function placeTab(t, s, active)
    s.fill:ClearAllPoints()
    s.fill:SetPoint("TOPLEFT", t, "TOPLEFT", 1, active and -8 or -12)
    s.fill:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -1, 0)
end

local function tabState(t, s)
    local C = ns.COLORS
    for _, r in ipairs(s.texs) do fade(r) end
    for _, r in ipairs(s.flash) do fade(r) end
    local active = shown(s.leftActive)
    if active ~= s.act then
        s.act = active
        placeTab(t, s, active)
        if active then
            local fill = ns.UI.SelectedTab()
            s.fill:SetColorTexture(fill[1], fill[2], fill[3], 0.95)
        else
            s.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.95)
        end
    end
    local en = enabled(t)
    local over = not active and en and isOver(t)
    local _, edge = ns.UI.SelectedTab()
    paint(s, active and edge or (over and C.violet or C.border))
    -- texte : Blizzard change d objet de police a chaque etat, la couleur
    -- est reposee a chaque releve (jamais la police ni la position)
    if objType(s.text) == "FontString" then
        local c = active and C.gold or (over and WHITE or C.text)
        local k = (active or en) and 1 or 0.5
        pcall(s.text.SetTextColor, s.text, c[1] * k, c[2] * k, c[3] * k)
    end
end

local function dressTab(t)
    local C = ns.COLORS
    local s = { texs = {} }
    for _, k in ipairs(TAB_KEYS) do
        local r = field(t, k)
        if objType(r) == "Texture" then s.texs[#s.texs + 1] = r end
    end
    for _, r in ipairs(regionsOf(t)) do
        if objType(r) == "Texture" and not mine[r] then
            local known = false
            for _, x in ipairs(s.texs) do if rawequal(x, r) then known = true break end end
            if not known then s.texs[#s.texs + 1] = r end
        end
    end
    s.leftActive = field(t, "LeftActive")
    s.fill = tex(t, "BACKGROUND", -8)
    s.edges = ring(t, s.fill, "BACKGROUND", -6)
    s.hl = tex(t, "HIGHLIGHT")
    s.hl:SetAllPoints(s.fill)
    ns.UI.Gradient(s.hl, "VERTICAL", C.violet[1], C.violet[2], C.violet[3], 0.04, C.violet[1], C.violet[2], C.violet[3], 0.25)
    s.text = field(t, "Text")
    -- clignotement "nouvel ensemble" (FlashFrame de l onglet Ensembles des
    -- apparences) : sa lueur jaune (UI-Character-Tab-Highlight-yellow, mode
    -- ADD) passe a alpha 0 ; une lueur d or a nous, posee sur ce cadre,
    -- suit l alpha que son OnUpdate de Blizzard fait varier a chaque image
    -- (le cadre lui-meme n est jamais touche)
    s.flash = {}
    local flash = field(t, "FlashFrame")
    if flash and objType(flash) and flash.CreateTexture then
        for _, r in ipairs(regionsOf(flash)) do
            if objType(r) == "Texture" and not mine[r] then s.flash[#s.flash + 1] = r end
        end
        s.glow = tex(flash, "ARTWORK", 7)
        s.glow:SetAllPoints(s.fill)
        ns.UI.Gradient(s.glow, "VERTICAL", C.gold[1], C.gold[2], C.gold[3], 0.06, C.gold[1], C.gold[2], C.gold[3], 0.4)
    end
    tabs[t] = s
    tabState(t, s)
end

---------------------------------------------------------------------------
-- 4. Barres de defilement minimalistes
---------------------------------------------------------------------------

local BAR_PARTS = { "Begin", "Middle", "End" }

local function isScrollBar(f)
    local track = field(f, "Track")
    return track ~= nil and field(track, "Thumb") ~= nil and field(f, "Back") ~= nil and field(f, "Forward") ~= nil
end

-- deja reprise ailleurs : reclamee, ou rail / curseur deja eteints (les
-- habillages en profondeur les passent a alpha 0)
local function barTaken(sb)
    local ok, cl = pcall(ns.SkinClaimed, sb)
    if ok and cl then return true end
    local track = field(sb, "Track")
    return alphaOf(field(track, "Begin")) == 0 or alphaOf(field(field(track, "Thumb"), "Begin")) == 0
end

local function dressBar(sb)
    local C = ns.COLORS
    local track = field(sb, "Track")
    local thumb = field(track, "Thumb")
    if not (track and track.CreateTexture and thumb and thumb.CreateTexture) then return end
    for _, k in ipairs(BAR_PARTS) do
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
        local b = field(sb, k)
        local c = ns.UI.ArrowChevron(b, ns.UI.ScrollDir(sb, k), 10, { field(b, "Texture") })
        if c then mine[c] = true end
    end
    bars[sb] = { thumb = thumb, knob = knob }
end

local function barState(_, s)
    local C = ns.COLORS
    local over = isOver(s.thumb)
    if over == s.over then return end
    s.over = over
    if over then
        s.knob:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.9)
    else
        s.knob:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.6)
    end
end

---------------------------------------------------------------------------
-- 5. Fleches de repli (bag-arrow)
---------------------------------------------------------------------------

-- sens de la fleche de Blizzard : sans rotation elle pointe a gauche ;
-- Blizzard la tourne (sens trigonometrique) : pi = fermee (droite),
-- pi / 2 = ouverte (bas)
local function foldDir(t)
    local r = num(ask(t, "GetRotation")) or 0
    local a = (math.pi + r) % (2 * math.pi)
    if a < math.pi / 4 or a >= 7 * math.pi / 4 then return "RIGHT" end
    if a < 3 * math.pi / 4 then return "UP" end
    if a < 5 * math.pi / 4 then return "LEFT" end
    return "DOWN"
end

local function foldState(_, s)
    for _, t in ipairs(s.texs) do veil(t) end
    if s.chev then s.chev:SetDir(foldDir(s.normal)) end
end

local function dressFold(b)
    local s = { texs = {}, normal = askObj(b, "GetNormalTexture") }
    for _, r in ipairs(regionsOf(b)) do
        if objType(r) == "Texture" and not mine[r] then s.texs[#s.texs + 1] = r end
    end
    s.chev = ns.UI.ArrowChevron(b, foldDir(s.normal), 10, s.texs)
    if s.chev then mine[s.chev] = true end
    folds[b] = s
    foldState(b, s)
end

---------------------------------------------------------------------------
-- Parcours
---------------------------------------------------------------------------

local function groupOn(key)
    local d = ns.skinsDB
    if type(d) ~= "table" or not d.enabled then return false end
    return not (key and d.groups and d.groups[key] == false)
end

-- case ou onglet deja habille par un autre fichier : reclame, ou textures
-- de Blizzard deja eteintes (Blizzard ne les met jamais a alpha 0)
local function takenByOther(c, kind)
    local ok, cl = pcall(ns.SkinClaimed, c)
    if ok and cl then return true end
    if kind == "check" then return alphaOf(askObj(c, "GetNormalTexture")) == 0 end
    if kind == "fold" then
        local n = askObj(c, "GetNormalTexture")
        if not n then return true end
        local ok, _, _, _, a = pcall(n.GetVertexColor, n)
        return alphaOf(n) == 0 or (ok and num(a) == 0)
    end
    return alphaOf(field(c, "Left")) == 0 or alphaOf(field(c, "LeftActive")) == 0
end

local function consider(c, key, now)
    if drops[c] or checks[c] or tabs[c] or folds[c] or others[c] then return end
    local kind = classify(c)
    if not kind then return end
    if ask(c, "IsProtected") == true then
        others[c] = true
        return
    end
    if kind == "drop" then
        dressDrop(c)
        owner[c] = key
        return
    end
    if takenByOther(c, kind) then
        others[c] = true
        pending[c] = nil
        return
    end
    -- delai de grace : vu libre a des releves continus pendant GRACE s
    local p = pending[c]
    if not p or now - p.last > WALK + TICK + 0.05 then
        pending[c] = { t = now, last = now }
        return
    end
    p.last = now
    if now - p.t < GRACE then return end
    pending[c] = nil
    if kind == "check" then dressCheck(c) elseif kind == "fold" then dressFold(c) else dressTab(c) end
    owner[c] = key
end

-- barre de defilement : meme delai de grace que les cases et onglets
local function considerBar(c, key, now)
    if bars[c] or others[c] then return end
    if barTaken(c) then
        others[c] = true
        pending[c] = nil
        return
    end
    local p = pending[c]
    if not p or now - p.last > WALK + TICK + 0.05 then
        pending[c] = { t = now, last = now }
        return
    end
    p.last = now
    if now - p.t < GRACE then return end
    pending[c] = nil
    dressBar(c)
    owner[c] = key
end

-- bulles d aide (HelpTip, partagees entre les fenetres) et menu volant des
-- sorts (securise, partage avec les barres) : jamais parcourus
local function skipFrame(c, skip)
    if skip[c] then return true end
    if rawequal(c, rawget(_G, "SpellFlyout")) then return true end
    return field(c, "OkayButton") ~= nil and field(c, "Arrow") ~= nil
end

local function walk(f, depth, key, now, budget, skip)
    for _, c in ipairs(childrenOf(f)) do
        if budget.n <= 0 then return end
        budget.n = budget.n - 1
        if not mine[c] and visible(c) then
            local t = objType(c)
            if t == "Button" or t == "CheckButton" or t == "DropdownButton" then
                -- jamais d enfants d un bouton (le menu volant des sorts en
                -- devient un), seulement le bouton lui-meme et ROW_KEYS
                consider(c, key, now)
                for _, rk in ipairs(ROW_KEYS) do
                    local sub = field(c, rk)
                    if sub and not mine[sub] and visible(sub) then consider(sub, key, now) end
                end
            elseif t and isScrollBar(c) then
                -- jamais de descente : ses fleches sont a la barre
                considerBar(c, key, now)
            elseif t and depth < MAXDEPTH and not skipFrame(c, skip) then
                local n = num(ask(c, "GetNumChildren"))
                if n and n > 0 and n <= MAXKIDS then walk(c, depth + 1, key, now, budget, skip) end
            end
        end
    end
end

local function report(err)
    local d = ns.skinsDB
    if type(d) == "table" then
        d.errors = d.errors or {}
        d.errors.Communs = tostring(err)
    end
end

local function each(list, fn)
    for f, s in pairs(list) do
        if groupOn(owner[f]) and visible(f) then
            local ok, err = pcall(fn, f, s)
            if not ok then report(err) end
        end
    end
end

-- une fenetre : parcourue tout de suite a l ouverture, puis toutes les
-- WALK secondes tant qu elle reste ouverte
local function visit(name, key, now)
    local f = not SKIP_WINDOWS[name] and rawget(_G, name)
    if type(f) ~= "table" or not f.GetChildren then return end
    if not visible(f) then
        shownWin[f] = nil
        return
    end
    if shownWin[f] and now - (lastWalk[f] or 0) < WALK then return end
    shownWin[f], lastWalk[f] = true, now
    local skip = {}
    for _, k in ipairs(SKIP_KEYS) do
        local c = field(f, k)
        if c then skip[c] = true end
    end
    local ok, err = pcall(walk, f, 1, key, now, { n = BUDGET }, skip)
    if not ok then report(err) end
end

local function pass(now)
    for _, g in ipairs(ns.SKIN_GROUPS or {}) do
        if groupOn(g.key) then
            for _, spec in ipairs(g.windows) do visit(spec[1], g.key, now) end
            for _, name in ipairs(EXTRA_ROOTS[g.key] or {}) do visit(name, g.key, now) end
        end
    end
    each(drops, dropState)
    each(checks, checkState)
    each(tabs, tabState)
    each(bars, barState)
    each(folds, foldState)
end

---------------------------------------------------------------------------
-- Partage
---------------------------------------------------------------------------

-- "drop", "check" ou "tab" si le cadre est (ou sera) habille ici, sinon
-- false. Lecture seule, sans effet : les autres fichiers s en servent pour
-- laisser ces elements a Communs.lua.
-- decale la plaque et le chevron d un menu a fleche (alignement sur un
-- champ voisin : la recherche du grimoire) ; dy en unites du bouton.
-- Textures a nous seulement : le bouton de Blizzard ne bouge pas.
function ns.SkinDropShift(b, dy)
    local s = drops[b]
    if not s or s.dy == dy then return end
    s.dy = dy
    if s.fill and not s.field then
        s.fill:ClearAllPoints()
        s.fill:SetPoint("CENTER", b, "CENTER", 0, dy)
    end
    for _, t in ipairs(s.chev or {}) do
        t:ClearAllPoints()
        t:SetPoint("CENTER", b, s.field and "RIGHT" or "CENTER", s.field and -12 or 0, dy)
    end
end

function ns.SkinCommon(f)
    if type(f) ~= "table" then return false end
    return classify(f) or false
end

-- Skins.lua : nos textures ne sont jamais eteintes
local prevOwned = ns.SkinOwned
function ns.SkinOwned(r)
    if type(r) == "table" and mine[r] then return true end
    if prevOwned then return prevOwned(r) end
    return false
end

---------------------------------------------------------------------------

local acc = 0
local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function()
    -- fin du combat : les fenetres ouvertes sont reparcourues tout de suite,
    -- les delais de grace repartent de zero
    for f in pairs(shownWin) do shownWin[f] = nil end
    for c in pairs(pending) do pending[c] = nil end
end)
pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")

ev:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < TICK then return end
    acc = 0
    if InCombatLockdown() then return end
    local d = ns.skinsDB
    if type(d) ~= "table" or not d.enabled then return end
    local ok, err = pcall(pass, GetTime())
    if not ok then report(err) end
end)
