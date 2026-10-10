--[[--------------------------------------------------------------------------
    CorpUI - module Habillage : fenetre du marchand en profondeur
    (MerchantFrame de Blizzard_UIPanels_Game : variante Mainline, chargee
    par ce client Camelot - Mainline/MerchantFrame.xml et .lua)

    Skins.lua pose deja le fond, le lisere, le bandeau, le titre et la croix,
    et efface le cadre exterieur (portrait, NineSlice, Inset, voile blanc
    BuybackBG de la page Rachat, bas de page UI-Merchant-BotFrame) ; ici on
    reprend tout l interieur :
      - cases d objets (MerchantItem1 a 12, recyclees entre la page Marchand
        et la page Rachat, plus la case du dernier objet vendu,
        MerchantBuyBackItem) : emplacement UI-EmptySlot, etiquette
        UI-Merchant-LabelSlots, cadre UI-Quickslot2, enfoncement, survol et
        bordure de qualite de Blizzard a alpha 0 ; carte sombre a lisere,
        puits carre de l icone, icone recadree, lisere de la qualite, survol
        en degrade d accent et lisere d or ;
      - etats de Blizzard gardes mais rendus a la CorpUI : objet inutilisable
        ou non apprenable (icone teintee en rouge par Blizzard, gardee) :
        lisere rouge sombre et voile rouge en degrade sur la carte, au lieu
        du gros fond rouge ; objet indisponible (stock epuise, objet
        d heritage deja connu : icone grisee) : carte attenuee, lisere gris ;
        case vide : puits seul. Nom a la couleur de qualite, stock limite,
        quantite, point d exclamation de quete, prix (pieces de Blizzard,
        grises si trop cher) et prix en monnaie ou en objets : intouches ;
      - boutons-icones (reparer un objet, tout reparer, reparer avec la
        guilde, vendre les objets gris) : carre sombre, icone recadree,
        lisere d or au survol et en mode reparation, attenue si desactive ;
      - boutons de page (fleches jaunes Prec. / Suivant) : plaque carree et
        chevron d or ; libelles et "Page 1 de 4" a la couleur du texte ;
      - pied de la page Marchand (reparation, vente, rachat) : filet d or et
        fond discret, a la place du bas de page de Blizzard ;
      - barres d argent et de monnaies : decor a alpha 0, champ sombre a
        lisere, pieces de Blizzard gardees ;
      - onglets du bas (Marchand / Rachat) : plaques plates, l actif en or.
    Le menu de filtre (WowStyle1DropdownTemplate) reste a Communs.lua.
    Aucun texte visible n est ajoute.

    Regles de ce client (taint, valeurs secretes). Les boutons de cette
    fenetre achetent, vendent, rachetent et reparent depuis leurs propres
    scripts (BuyMerchantItem, BuybackItem, RepairAllItems,
    SellAllJunkItems...) : le moindre ecart bloquerait le marchand. Donc :
      - aucun crochet, aucun SetScript, aucun attribut, aucun champ ecrit
        dans un cadre ou une table de Blizzard (cases recyclees comprises) :
        nos textures sont rangees dans des tables faibles a nous ;
      - aucune taille, position, strate, niveau, parent, souris ni
        visibilite de Blizzard modifiee, aucune de leurs fonctions Lua
        appelee (le bouton d objet porte un SetAlpha de Blizzard,
        ItemButtonMixin : jamais appele, seules ses textures passent a
        alpha 0) : seulement des accesseurs du moteur, l alpha de leurs
        decors, le recadrage des icones et la couleur de quelques textes
        decoratifs (libelles des pages, onglets) ;
      - les couleurs que Blizzard pose a chaque mise a jour (teinte rouge ou
        grise de l icone, de l emplacement et de l etiquette, bordure de
        qualite) sont LUES pour choisir nos liseres, jamais ecrasees : ces
        decors sont eteints par l alpha, que Blizzard ne touche pas ;
      - releve periodique (0,1 s), fenetre ouverte seulement, rien en
        combat ; toute valeur lue est verifiee (pcall, issecretvalue).
    Skins.lua ne descend plus dans la fenetre (ns.SkinClaimed : enfants
    directs du marchand, sauf le menu de filtre laisse a Communs.lua). Ce
    fichier doit etre charge apres Personnage.lua (qui ne chaine pas
    ns.SkinClaimed) et avant Skins.lua.
----------------------------------------------------------------------------]]

local _, ns = ...

local issecret = issecretvalue or function() return false end
local weak = { __mode = "k" }

local mine = setmetatable({}, weak)      -- nos regions (a ne jamais traiter)
local claimed = setmetatable({}, weak)   -- cadres repris ici
local cells = setmetatable({}, weak)     -- case d objet -> { btn, icon, fill, edges, ring... }
local squares = setmetatable({}, weak)   -- bouton-icone -> { icon, fill, edges }
local pagers = setmetatable({}, weak)    -- bouton de page -> { fill, edges, chev, label }
local tabs = setmetatable({}, weak)      -- onglet du bas -> { fill, accent, edges, line, text }
local bars = setmetatable({}, weak)      -- barre d argent -> { fill, edges }
local cropped = setmetatable({}, weak)   -- icone a atlas deja recadree (une fois)

local NUM_CELLS = 12
-- boutons-icones (Icon : atlas SpellIcon-256x256-*)
local SQUARES = { "MerchantRepairItemButton", "MerchantRepairAllButton", "MerchantGuildBankRepairButton",
                  "MerchantSellAllJunkButton" }
local PAGERS = { { "MerchantPrevPageButton", "LEFT" }, { "MerchantNextPageButton", "RIGHT" } }
-- barres d argent : cadre ThinGoldEdgeTemplate, cadre InsetFrameTemplate
local MONEY = { { "MerchantMoneyBg", "MerchantMoneyInset" }, { "MerchantExtraCurrencyBg", "MerchantExtraCurrencyInset" } }
-- textures d etat d un bouton (accesseurs du moteur)
local STATES = { "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }
-- regions (tout le reste est un cadre)
local REGION = { Texture = true, FontString = true, MaskTexture = true, Line = true }

local function db()
    local d = ns.skinsDB
    if type(d) ~= "table" or not d.enabled then return nil end
    if d.groups and d.groups.trade == false then return nil end
    return d
end

---------------------------------------------------------------------------
-- Outils (lectures protegees, sans fermeture neuve a chaque appel)
---------------------------------------------------------------------------

local function get(f, key) return f[key] end
local function packRegions(f) return { f:GetRegions() } end

local function objType(o)
    if type(o) ~= "table" or not o.GetObjectType then return nil end
    local ok, t = pcall(o.GetObjectType, o)
    if ok and not issecret(t) and type(t) == "string" then return t end
end

-- cadre (bouton, ItemButton intrinseque...) et non region
local function isFrame(o)
    local t = objType(o)
    if not t or REGION[t] then return false end
    local ok, fn = pcall(get, o, "CreateTexture")
    return ok and type(fn) == "function"
end

-- champ table d un cadre de Blizzard (lecture seule)
local function field(f, key)
    if type(f) ~= "table" then return nil end
    local ok, c = pcall(get, f, key)
    if ok and type(c) == "table" then return c end
end

-- champ simple (texte, booleen, nombre), jamais secret
local function value(f, key)
    if type(f) ~= "table" then return nil end
    local ok, v = pcall(get, f, key)
    if not ok or v == nil or issecret(v) then return nil end
    local t = type(v)
    if t == "string" or t == "boolean" or t == "number" then return v end
end

local function global(name)
    if type(name) ~= "string" then return nil end
    local v = rawget(_G, name)
    if type(v) == "table" then return v end
end

local function isTrue(v)
    if issecret(v) then return false end
    return v == true
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

local function nameOf(f)
    if type(f) ~= "table" or not f.GetName then return nil end
    local ok, n = pcall(f.GetName, f)
    if ok and not issecret(n) and type(n) == "string" then return n end
end

local function regionsOf(f)
    if type(f) ~= "table" or not f.GetRegions then return {} end
    local ok, list = pcall(packRegions, f)
    return ok and list or {}
end

local function atlasOf(t)
    if type(t) ~= "table" or not t.GetAtlas then return nil end
    local ok, a = pcall(t.GetAtlas, t)
    if ok and not issecret(a) and type(a) == "string" and a ~= "" then return a end
end

-- texte d un FontString (false si absent ou secret)
local function textOf(fs)
    if objType(fs) ~= "FontString" then return false end
    local ok, t = pcall(fs.GetText, fs)
    if not ok or issecret(t) then return false end
    if t == nil then return "" end
    if type(t) ~= "string" then return false end
    return t
end

local function alphaOf(t)
    if type(t) ~= "table" or not t.GetAlpha then return nil end
    local ok, a = pcall(t.GetAlpha, t)
    if ok then return num(a) end
end

-- texture de Blizzard a alpha 0, seulement si besoin (le releve repasse
-- souvent). Jamais un cadre : le bouton d objet a un SetAlpha de Blizzard.
local function fade(t)
    if objType(t) ~= "Texture" or mine[t] then return end
    if alphaOf(t) ~= 0 then pcall(t.SetAlpha, t, 0) end
end

-- textures d etat d un bouton (normale, enfoncee, survol, desactivee)
local function fadeStates(b)
    for _, m in ipairs(STATES) do
        local ok, fn = pcall(get, b, m)
        if ok and type(fn) == "function" then
            local okT, t = pcall(fn, b)
            if okT then fade(t) end
        end
    end
end

-- textures posees sur un cadre (pas celles de ses enfants), sauf les notres
-- et celles de "keep"
local function fadeOwn(f, keep)
    for _, r in ipairs(regionsOf(f)) do
        if not mine[r] and not (keep and rawequal(r, keep)) and objType(r) == "Texture" then fade(r) end
    end
end

-- couleur de sommet d une texture (lue, jamais ecrite)
local function vertex(t)
    if objType(t) ~= "Texture" then return nil end
    local ok, r, g, b = pcall(t.GetVertexColor, t)
    if not ok then return nil end
    r, g, b = num(r), num(g), num(b)
    if r and g and b then return r, g, b end
end

-- icone recadree (pas un atlas : on casserait ses coordonnees)
local function cropIcon(icon)
    if objType(icon) ~= "Texture" or atlasOf(icon) then return end
    local ok, l = pcall(icon.GetTexCoord, icon)
    l = ok and num(l)
    if l and math.abs(l - 0.08) < 0.001 then return end
    pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
end

-- icone a atlas (boutons de reparation, de vente) : recadree une fois a
-- l interieur des coordonnees de l atlas (8 % de chaque cote)
local function cropAtlas(icon)
    if cropped[icon] or objType(icon) ~= "Texture" then return end
    if not atlasOf(icon) then
        cropIcon(icon)
        return
    end
    local ok, ulx, uly, llx, lly, urx, ury, lrx, lry = pcall(icon.GetTexCoord, icon)
    if not ok then return end
    ulx, uly, lly, urx = num(ulx), num(uly), num(lly), num(urx)
    -- coordonnees droites seulement (atlas non pivote)
    if not (ulx and uly and lly and urx) or not (urx > ulx and lly > uly) then return end
    if num(llx) ~= ulx or num(ury) ~= uly or num(lrx) ~= urx or num(lry) ~= lly then return end
    cropped[icon] = true
    local dx, dy = (urx - ulx) * 0.08, (lly - uly) * 0.08
    pcall(icon.SetTexCoord, icon, ulx + dx, urx - dx, uly + dy, lly - dy)
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

local function paint(list, r, g, b, a)
    for _, x in ipairs(list) do x:SetColorTexture(r, g, b, a or 1) end
end

local function paintC(list, c, a) paint(list, c[1], c[2], c[3], a) end

-- lisere repeint seulement quand sa couleur change (releve frequent)
local function tint(s, c, a)
    a = a or 1
    if s.ec == c and s.ea == a then return end
    s.ec, s.ea = c, a
    paintC(s.edges, c, a)
end

local function showAll(list, on)
    for _, x in ipairs(list) do x:SetShown(on) end
end

-- police des titres + or ; on retient la police posee pour la reposer si
-- Blizzard change d objet de police
local function goldFont(fs, size)
    if objType(fs) ~= "FontString" then return nil end
    local C = ns.COLORS
    pcall(ns.UI.HeadFont, fs, size)
    pcall(fs.SetTextColor, fs, C.gold[1], C.gold[2], C.gold[3])
    local ok, file = pcall(fs.GetFont, fs)
    return { fs = fs, size = size, file = (ok and not issecret(file) and type(file) == "string") and file or nil }
end

local function keepGold(h)
    if not h or not h.fs then return end
    local ok, file = pcall(h.fs.GetFont, h.fs)
    if ok and not issecret(file) and type(file) == "string" and h.file and file ~= h.file then
        pcall(ns.UI.HeadFont, h.fs, h.size)
    end
    local C = ns.COLORS
    pcall(h.fs.SetTextColor, h.fs, C.gold[1], C.gold[2], C.gold[3])
end

---------------------------------------------------------------------------
-- Cases d objets (MerchantItem1 a 12, MerchantBuyBackItem)
---------------------------------------------------------------------------

-- teinte posee par Blizzard sur l icone (MerchantFrame_UpdateMerchantInfo /
-- UpdateBuybackInfo) : rouge 0,9 (inutilisable), rouge 0,5 (inutilisable et
-- indisponible), gris 0,5 (indisponible, heritage connu), blanc (normal) ;
-- l emplacement suit la meme regle (1 / 0,5 / 0,5 / 1)
local function tintOf(r, g, b)
    if not r then return "ok" end
    if r > 0.3 and g < 0.2 and b < 0.2 then return r < 0.7 and "baddim" or "bad" end
    if r < 0.75 and math.abs(r - g) < 0.1 and math.abs(g - b) < 0.1 then return "dim" end
    return "ok"
end

-- couleur de la bordure de qualite (WhiteIconFrame teinte par
-- SetItemButtonQuality, cachee par l alpha) ; blanc : lisere du theme
local function qualityOf(border)
    if not shown(border) then return nil end
    local r, g, b = vertex(border)
    if r and not (r > 0.95 and g > 0.95 and b > 0.95) then return r, g, b end
end

local function skinCell(c)
    if cells[c] then return cells[c] end
    if not isFrame(c) then return nil end
    local name = nameOf(c) or ""
    local btn = field(c, "ItemButton") or global(name .. "ItemButton")
    if not isFrame(btn) then return nil end
    local bname = nameOf(btn) or ""
    local icon = field(btn, "icon") or field(btn, "Icon") or global(bname .. "IconTexture")
    if objType(icon) ~= "Texture" then return nil end
    local C = ns.COLORS
    local s = { btn = btn, icon = icon, buyback = rawequal(c, global("MerchantBuyBackItem")) }
    s.slot = field(c, "SlotTexture") or global(name .. "SlotTexture")
    s.label = field(c, "NameFrame") or global(name .. "NameFrame")
    s.name = field(c, "Name") or global(name .. "Name")
    s.border = field(btn, "IconBorder")
    -- carte : toute la case (icone, nom, prix), 2 px de marge
    s.fill = tex(c, "BACKGROUND", -8)
    s.fill:SetPoint("TOPLEFT", c, "TOPLEFT", -2, 2)
    s.fill:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 2, -2)
    s.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.7)
    -- voile rouge (inutilisable) et survol : degrades depuis la gauche
    s.warn = tex(c, "BACKGROUND", -7)
    s.warn:SetAllPoints(s.fill)
    ns.UI.Gradient(s.warn, "HORIZONTAL", 0.85, 0.12, 0.12, 0.30, 0.85, 0.12, 0.12, 0.02)
    s.warn:Hide()
    s.glow = tex(c, "BACKGROUND", -7)
    s.glow:SetAllPoints(s.fill)
    ns.UI.Gradient(s.glow, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.24, C.violet[1], C.violet[2], C.violet[3], 0.02)
    s.glow:Hide()
    s.edges = ring(c, s.fill, "BACKGROUND", -6, 0)
    -- puits carre de l icone, sur la case (sous le bouton) : seul visible
    -- quand Blizzard cache le bouton (case vide)
    s.well = tex(c, "BACKGROUND", -5)
    s.well:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    s.well:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    s.well:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.9)
    s.wellEdges = ring(c, btn, "BORDER", 1, 0)
    paintC(s.wellEdges, C.border, 0.45)
    -- lisere de l icone (qualite, rouge, gris) au-dessus d elle, et survol
    -- sur le calque HIGHLIGHT du bouton (montre par le moteur)
    s.ring = ring(btn, btn, "OVERLAY", 7, 0)
    s.hl = tex(btn, "HIGHLIGHT")
    s.hl:SetAllPoints(btn)
    s.hl:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.2)
    cells[c] = s
    claimed[c] = true
    claimed[btn] = true
    return s
end

-- decors de Blizzard (au parcours) : Blizzard ne touche que leur couleur
-- et leur visibilite, jamais leur alpha
local function cellDecor(s)
    fade(s.slot)
    fade(s.label)
    fade(s.border)
    fadeStates(s.btn)
end

local function cellState(_, s)
    local C = ns.COLORS
    cropIcon(s.icon)
    -- case pleine : Blizzard cache le bouton de toute case vide (MerchantItem1
    -- a 12, deux pages) ; le nom peut manquer (objet pas encore en cache) sur
    -- une case pleine, on ne le lit donc que pour la case du dernier objet
    -- vendu, dont le bouton reste affiche meme vide
    local filled = shown(s.btn) and (not s.buyback or textOf(s.name) ~= "")
    -- teinte de Blizzard : icone, sinon emplacement
    local r, g, b = vertex(s.icon)
    if not r then r, g, b = vertex(s.slot) end
    local mode = filled and tintOf(r, g, b) or "empty"
    local over = isOver(s.btn)
    local qr, qg, qb
    if filled then qr, qg, qb = qualityOf(s.border) end
    local key = mode .. (over and "1" or "0") .. (qr and string.format("%.3f:%.3f:%.3f", qr, qg, qb) or "-")
    if key == s.key then return end
    s.key = key
    local bad = mode == "bad" or mode == "baddim"
    local dim = mode == "dim" or mode == "baddim"
    -- carte : cachee sur une case vide (sauf la case de rachat, fixe)
    local card = filled or s.buyback
    s.fill:SetShown(card)
    showAll(s.edges, card)
    s.fill:SetAlpha(dim and 0.45 or (filled and 1 or 0.5))
    s.warn:SetShown(bad)
    s.warn:SetAlpha(mode == "baddim" and 0.55 or 1)
    s.glow:SetShown(card and over)
    paintC(s.edges, (over and card) and C.gold or C.border, (card and not filled) and 0.5 or (dim and 0.6 or 1))
    -- lisere de l icone : rouge sombre (inutilisable), gris (indisponible),
    -- qualite (verte et plus), sinon theme
    if mode == "bad" then paint(s.ring, 0.62, 0.12, 0.12, 1)
    elseif mode == "baddim" then paint(s.ring, 0.42, 0.08, 0.08, 1)
    elseif mode == "dim" then paint(s.ring, 0.38, 0.38, 0.4, 1)
    elseif qr then paint(s.ring, qr, qg, qb, 1)
    else paintC(s.ring, C.border, filled and 1 or 0.5) end
end

---------------------------------------------------------------------------
-- Boutons-icones (reparer, vendre les objets gris)
---------------------------------------------------------------------------

local function skinSquare(b)
    if squares[b] then return squares[b] end
    if not isFrame(b) then return nil end
    local icon = field(b, "Icon") or global((nameOf(b) or "") .. "Icon")
    -- sans icone reconnue, rien : on eteindrait l icone avec le decor
    if objType(icon) ~= "Texture" then return nil end
    local C = ns.COLORS
    local s = { icon = icon }
    s.fill = tex(b, "BACKGROUND", -8)
    s.fill:SetAllPoints(b)
    s.fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.9)
    s.edges = ring(b, b, "OVERLAY", 7, 0)
    -- survol (et mode reparation : LockHighlight montre ce calque)
    s.hl = tex(b, "HIGHLIGHT")
    s.hl:SetAllPoints(b)
    s.hl:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.22)
    squares[b] = s
    claimed[b] = true
    return s
end

-- emplacement UI-EmptySlot (texture sans nom), enfoncement et survol
local function squareDecor(b, s)
    fadeOwn(b, s.icon)
    fadeStates(b)
    cropAtlas(s.icon)
end

local function repairMode()
    if type(InRepairMode) ~= "function" then return false end
    local ok, v = pcall(InRepairMode)
    return ok and not issecret(v) and (v == true or v == 1)
end

local function squareState(b, s)
    local C = ns.COLORS
    local en = enabled(b)
    local active = rawequal(b, global("MerchantRepairItemButton")) and repairMode()
    if active or (en and isOver(b)) then tint(s, C.gold, 1)
    elseif not en then tint(s, C.border, 0.5)
    else tint(s, C.border, 1) end
end

---------------------------------------------------------------------------
-- Boutons de page (fleches jaunes Prec. / Suivant)
---------------------------------------------------------------------------

-- chevron d or (recette des menus de CorpUI) : deux barres de 6 x 2 px
-- pivotees a +-45 degres, pointe a gauche ou a droite
local function chevron(b, anchor, dir)
    local t = ns.UI.Chevron(b, 14, dir)
    mine[t] = true
    t:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    return { t }
end

local function skinPager(b, dir)
    if pagers[b] then return pagers[b] end
    if not isFrame(b) then return nil end
    local C = ns.COLORS
    local s = {}
    s.fill = tex(b, "BACKGROUND", -8)
    s.fill:SetSize(22, 22)
    s.fill:SetPoint("CENTER", b, "CENTER", 0, 0)
    s.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.95)
    s.edges = ring(b, s.fill, "BACKGROUND", -7, 0)
    s.hl = tex(b, "HIGHLIGHT")
    s.hl:SetAllPoints(s.fill)
    ns.UI.Gradient(s.hl, "VERTICAL", C.violet[1], C.violet[2], C.violet[3], 0.05, C.violet[1], C.violet[2], C.violet[3], 0.28)
    s.chev = chevron(b, s.fill, dir)
    -- libelle "Prec." / "Suivant" : texte sans nom pose sur le bouton
    for _, r in ipairs(regionsOf(b)) do
        if not mine[r] and objType(r) == "FontString" then
            s.label = r
            break
        end
    end
    pagers[b] = s
    claimed[b] = true
    return s
end

-- fond UI-PageButton-Background et fleches de Blizzard (toutes les etats)
local function pagerDecor(b)
    fadeOwn(b)
    fadeStates(b)
end

local function pagerState(b, s)
    local C = ns.COLORS
    local en = enabled(b)
    tint(s, (en and isOver(b)) and C.gold or C.border, 1)
    if s.en == en then return end
    s.en = en
    s.fill:SetAlpha(en and 1 or 0.5)
    local c = en and C.gold or C.text
    for _, t in ipairs(s.chev) do t:SetVertexColor(c[1], c[2], c[3], en and 1 or 0.4) end
    -- libelle decoratif (Blizzard ne le relit jamais) : texte de CorpUI
    if s.label then
        local m = en and 1 or 0.5
        pcall(s.label.SetTextColor, s.label, C.text[1] * m, C.text[2] * m, C.text[3] * m)
    end
end

---------------------------------------------------------------------------
-- Onglets du bas (PanelTabButtonTemplate)
---------------------------------------------------------------------------

-- toutes leurs textures a alpha 0 (jamais leurs coordonnees), notre plaque.
-- Blizzard deplace le texte selon l etat (PanelTemplates_SelectTab /
-- DeselectTab : +2 inactif, -3 actif) : le texte n est jamais touche, nos
-- ancres le suivent (placeTab, a chaque changement d etat). Actif : jusqu au
-- bas de l onglet ; inactif : plaque plus courte, centree sur le texte.
local function placeTab(t, s, active)
    local f = s.fill
    local txt = objType(s.text) == "FontString" and s.text or nil
    f:ClearAllPoints()
    f:SetPoint("LEFT", t, "LEFT", 8, 0)
    f:SetPoint("RIGHT", t, "RIGHT", -9, 0)
    f:SetPoint("TOP", t, "TOP", 0, -5)
    if active or not txt then
        f:SetPoint("BOTTOM", t, "BOTTOM", 0, 1)
    else
        f:SetPoint("BOTTOM", txt, "BOTTOM", 0, -4)
    end
end

local function skinTab(t)
    fadeOwn(t)
    if tabs[t] or not isFrame(t) then return end
    local C = ns.COLORS
    local s = {}
    s.fill = tex(t, "BACKGROUND", -8)
    s.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.95)
    s.accent = tex(t, "BACKGROUND", -7)
    s.accent:SetAllPoints(s.fill)
    ns.UI.Gradient(s.accent, "VERTICAL", C.violet[1], C.violet[2], C.violet[3], 0.05, C.violet[1], C.violet[2], C.violet[3], 0.38)
    s.accent:Hide()
    s.edges = ring(t, s.fill, "BACKGROUND", -6, 0)
    paintC(s.edges, C.border)
    s.line = tex(t, "BACKGROUND", -5)
    s.line:SetPoint("TOPLEFT", s.fill, "TOPLEFT", 0, 0)
    s.line:SetPoint("TOPRIGHT", s.fill, "TOPRIGHT", 0, 0)
    s.line:SetHeight(2)
    s.line:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    s.line:Hide()
    -- survol : calque HIGHLIGHT (l onglet actif est desactive, sans survol)
    s.hl = tex(t, "HIGHLIGHT")
    s.hl:SetAllPoints(s.fill)
    ns.UI.Gradient(s.hl, "VERTICAL", C.violet[1], C.violet[2], C.violet[3], 0.04, C.violet[1], C.violet[2], C.violet[3], 0.25)
    s.text = field(t, "Text")
    s.act = shown(field(t, "LeftActive"))
    placeTab(t, s, s.act)
    tabs[t] = s
    claimed[t] = true
end

local WHITE = { 1, 1, 1 }

-- actif : textures "Active" montrees par Blizzard (PanelTemplates_SelectTab)
local function tabState(t, s)
    local C = ns.COLORS
    local active = shown(field(t, "LeftActive"))
    if active ~= s.act then
        s.act = active
        placeTab(t, s, active)
    end
    local over = not active and isOver(t)
    s.accent:SetShown(active)
    s.line:SetShown(active)
    tint(s, active and C.gold or (over and C.violet or C.border))
    -- texte : Blizzard change d objet de police a chaque etat, la couleur
    -- est reposee a chaque releve (jamais la police ni la position)
    if objType(s.text) == "FontString" then
        local c = active and C.gold or (over and WHITE or C.text)
        pcall(s.text.SetTextColor, s.text, c[1], c[2], c[3])
    end
end

---------------------------------------------------------------------------
-- Barres d argent, pied de page, titre
---------------------------------------------------------------------------

-- ThinGoldEdgeTemplate (Left / Middle / Right) et InsetFrameTemplate (Bg,
-- NineSlice) a alpha 0 ; notre champ sombre sur le cadre ThinGoldEdge (un
-- niveau au-dessus de la fenetre, sous les pieces)
local function skinMoney(bg, inset)
    if inset then
        fadeOwn(inset)
        fadeOwn(field(inset, "NineSlice"))
    end
    if not bg then return end
    fadeOwn(bg)
    if bars[bg] or not isFrame(bg) then return end
    local C = ns.COLORS
    local s = {}
    s.fill = tex(bg, "BACKGROUND", -8)
    s.fill:SetAllPoints(bg)
    s.fill:SetColorTexture(0, 0, 0, 0.45)
    s.edges = ring(bg, bg, "BACKGROUND", -7, 0)
    paintC(s.edges, C.border)
    bars[bg] = s
    claimed[bg] = true
end

-- pied de la page Marchand (boutons de reparation, de vente et case de
-- rachat), la ou Blizzard dessine UI-Merchant-BotFrame (26 a 87 px du bas,
-- eteint par Skins.lua) : fond discret et filet d or, sous la ligne des
-- boutons de page et du texte "Page 1 de 4"
local footer

local function makeFooter(mf)
    if footer or not mf.CreateTexture then return end
    local C = ns.COLORS
    footer = {}
    footer.fill = tex(mf, "BACKGROUND", -6)
    footer.fill:SetPoint("TOPLEFT", mf, "BOTTOMLEFT", 4, 79)
    footer.fill:SetPoint("BOTTOMRIGHT", mf, "BOTTOMRIGHT", -4, 27)
    footer.fill:SetColorTexture(0, 0, 0, 0.22)
    footer.line = tex(mf, "BACKGROUND", -5)
    footer.line:SetPoint("TOPLEFT", footer.fill, "TOPLEFT", 0, 0)
    footer.line:SetPoint("TOPRIGHT", footer.fill, "TOPRIGHT", 0, 0)
    footer.line:SetHeight(1)
    ns.UI.Gradient(footer.line, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.8, C.gold[1], C.gold[2], C.gold[3], 0)
    footer.on = true
end

-- page Marchand : Blizzard montre son bas de page (cache sur la page Rachat)
local function merchantPage(mf)
    local bot = global("MerchantFrameBottomLeftBorder")
    if objType(bot) == "Texture" then return shown(bot) end
    return value(mf, "selectedTab") == 1
end

local function footerState(mf)
    if not footer then return end
    local on = merchantPage(mf)
    if on == footer.on then return end
    footer.on = on
    footer.fill:SetShown(on)
    footer.line:SetShown(on)
end

local titleFont

local function titleState(mf)
    local title = field(field(mf, "TitleContainer"), "TitleText")
    if objType(title) ~= "FontString" then return end
    if not titleFont or titleFont.fs ~= title then titleFont = goldFont(title, 12) else keepGold(titleFont) end
end

---------------------------------------------------------------------------
-- Parcours et releve
---------------------------------------------------------------------------

local function report(err)
    local d = ns.skinsDB
    if type(d) == "table" then
        d.errors = d.errors or {}
        d.errors.Merchant = tostring(err)
    end
end

local function try(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then report(err) end
    return ok and err or nil
end

-- parcours (ouverture, changement de page, puis toutes les 0,5 s) : les
-- cadres sont fixes et nommes, rien n est cree par Blizzard ensuite
local function full(mf)
    for i = 1, NUM_CELLS + 1 do
        local c = global(i <= NUM_CELLS and ("MerchantItem" .. i) or "MerchantBuyBackItem")
        if c then
            local s = try(skinCell, c)
            if s then try(cellDecor, s) end
        end
    end
    for _, n in ipairs(SQUARES) do
        local b = global(n)
        if b then
            local s = try(skinSquare, b)
            if s then try(squareDecor, b, s) end
        end
    end
    for _, p in ipairs(PAGERS) do
        local b = global(p[1])
        if b and try(skinPager, b, p[2]) then try(pagerDecor, b) end
    end
    for i = 1, 2 do
        local t = global("MerchantFrameTab" .. i)
        if t then try(skinTab, t) end
    end
    for _, m in ipairs(MONEY) do try(skinMoney, global(m[1]), global(m[2])) end
    -- "Page 1 de 4" : texte decoratif, a la couleur du texte de CorpUI
    local pt = global("MerchantPageText")
    if objType(pt) == "FontString" then
        local C = ns.COLORS
        pcall(pt.SetTextColor, pt, C.text[1], C.text[2], C.text[3])
    end
    try(makeFooter, mf)
end

local function each(list, fn)
    for f, s in pairs(list) do
        if visible(f) then try(fn, f, s) end
    end
end

-- releve leger (10 fois par seconde, fenetre ouverte) : etats et couleurs
local function light(mf)
    try(titleState, mf)
    each(cells, cellState)
    each(squares, squareState)
    each(pagers, pagerState)
    each(tabs, tabState)
    try(footerState, mf)
end

-- Skins.lua : ne pas descendre dans le marchand (tout est repris ici, sans
-- course au chargement : la parente suffit), sauf le menu de filtre, laisse
-- entier a Communs.lua (plaque comprise) ; ne pas effacer nos textures
local function common(f, mf)
    if rawequal(f, field(mf, "FilterDropdown") or false) then return true end
    if not ns.SkinCommon then return false end
    local ok, k = pcall(ns.SkinCommon, f)
    return ok and k and true or false
end

local prevClaimed = ns.SkinClaimed
function ns.SkinClaimed(f)
    if type(f) == "table" then
        if claimed[f] then return true end
        local mf = global("MerchantFrame")
        if mf and f.GetParent and db() then
            local ok, p = pcall(f.GetParent, f)
            if ok and rawequal(p, mf) and not common(f, mf) then return true end
        end
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

local state = { shown = false, key = nil }
local acc, walkAcc = 0, 0

local function pageKey(mf)
    local tab = value(mf, "selectedTab")
    local page = value(mf, "page")
    return tostring(tab) .. ":" .. tostring(page) .. ":" .. (merchantPage(mf) and "1" or "0")
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if ns.ModuleOff("habillage", ev) then return end
    -- fin du combat : parcours complet au tic suivant
    if event == "PLAYER_REGEN_ENABLED" then state.shown = false end
end)
pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")

ev:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.1 then return end
    walkAcc = walkAcc + acc
    acc = 0
    if not db() or InCombatLockdown() then return end
    local mf = global("MerchantFrame")
    if not mf or not mf.CreateTexture or not visible(mf) then
        state.shown = false
        return
    end
    local key = pageKey(mf)
    if not state.shown or key ~= state.key or walkAcc >= 0.5 then
        state.shown, state.key, walkAcc = true, key, 0
        try(full, mf)
    end
    try(light, mf)
end)
