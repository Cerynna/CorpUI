--[[--------------------------------------------------------------------------
    CorpUI - module Habillage : courrier en profondeur
    (MailFrame avec InboxFrame et SendMailFrame, et OpenMailFrame, de
    Blizzard_MailFrame : MailFrame.lua / MailFrame.xml, communs aux familles
    Mainline et Camelot, charges des la connexion)

    Skins.lua pose deja le fond, le lisere, le bandeau, le titre et la croix
    des deux fenetres ; ici on reprend tout l interieur :
      - titres en police de titre, or ;
      - onglets du bas (Boite de reception / Envoyer) : plaques plates,
        l actif en lisere d or, degrade d accent, filet d or et texte or,
        les inactifs plus courts, centres sur leur texte (recette de
        HotelVentes.lua) ;
      - zone de contenu (Inset de Blizzard, eteint par Skins.lua) : puits
        sombre a lisere ;
      - boite de reception : chaque lettre devient une carte (fond, lisere),
        la lettre ouverte en degrade d accent avec une barre d or, survol en
        degrade ; icone carree recadree sur fond sombre, lisere de la
        qualite de l objet joint, a defaut lisere d or si la lettre n est
        pas lue (case jaune de Blizzard, lue), du theme une fois lue ;
        expediteur, objet, delai (vert / rouge), mention C.R. et icone
        grisee d une lettre lue : ceux de Blizzard ;
      - pagination : fleches jaunes -> petites plaques a chevron d or,
        libelles Precedent / Suivant a la couleur du texte (attenues quand
        la page n existe pas) ; Tout ouvrir en plaque ;
      - envoi : champs Destinataire / Objet et champs d argent habilles
        autour (morceaux a alpha 0, fond sombre, lisere d or au focus,
        violet au survol), cases d objets joints carrees (lisere de
        qualite, attenuees vides), boutons radio Envoyer de l argent /
        Contre-remboursement en losanges a point d or, cadre d argent en bas
        a gauche, Envoyer / Annuler en plaques ;
      - lettre ouverte : objets joints, lettre et argent en cases carrees
        (la teinte rouge de Blizzard d un objet inutilisable est gardee, le
        lisere passe au rouge sombre), Repondre / Supprimer (Retourner) /
        Fermer / Signaler en plaques ;
      - barres horizontales de Blizzard -> filets d or degrades (ils
        suivent la barre, que Blizzard deplace selon le nombre d objets) ;
        barres de defilement minimalistes ; libelles (A, Objet, De, Cout,
        Montant) en or.
    Volontairement gardes : le papier a lettres (le texte du courrier est
    sombre et ni la police ni la couleur d un champ de saisie ne sont
    touchees ; il recoit seulement un cadre, une ombre et un filet d or),
    les factures de l hotel des ventes ecrites dessus, les pieces des cadres
    d argent (rouges si l envoi coute trop cher), le voile noir de l envoi
    verrouille, les messages d erreur rouges. Aucun texte visible ajoute.

    Regles de ce client (taint, valeurs secretes). Ces fenetres appellent
    des fonctions protegees ou sensibles depuis les scripts de leurs boutons
    (SendMail, TakeInboxItem, TakeInboxMoney, AutoLootMailItem,
    DeleteInboxItem, ReturnInboxItem, ClickSendMailItemButton...). Donc :
      - aucun crochet, aucun SetScript, aucun champ ecrit dans un cadre ou
        une table de Blizzard : notre etat est range dans des tables faibles
        a nous, indexees par le cadre ;
      - aucune taille, position, strate, niveau, parent, souris ni
        visibilite de Blizzard modifiee, aucune de leurs fonctions Lua
        appelee : seulement des accesseurs du moteur, l alpha de leurs
        textures decoratives, le recadrage des icones, la couleur de
        quelques libelles (jamais relue par Blizzard) et nos propres
        textures. Les couleurs que Blizzard pose a chaque mise a jour (case
        jaune d une lettre non lue, icone rouge d un objet inutilisable,
        bordure de qualite) sont LUES pour choisir notre lisere, jamais
        ecrasees ;
      - rien en combat, releve periodique (0,1 s) seulement fenetre
        ouverte ; toute valeur lue est verifiee (pcall, issecretvalue).
    Skins.lua ne descend plus dans ces fenetres (ns.SkinClaimed) : il garde
    leur fond, leur cadre, leur titre et leur croix. Groupe "trade".
----------------------------------------------------------------------------]]

local _, ns = ...

local issecret = issecretvalue or function() return false end
local weak = { __mode = "k" }

local mine = setmetatable({}, weak)      -- nos regions (a ne jamais traiter)
local claimed = setmetatable({}, weak)   -- cadres repris ici
local done = setmetatable({}, weak)      -- decor deja traite (cadre ou texture)
local ruled = setmetatable({}, weak)     -- barre horizontale de Blizzard -> notre filet d or
local plates = setmetatable({}, weak)    -- bouton aplati -> { fill, edges, hl, glyph, label }
local tabs = setmetatable({}, weak)      -- onglet du bas -> { fill, accent, edges, line, hl, text, off, act }
local rows = setmetatable({}, weak)      -- ligne de la boite -> { b, icon, slot, border, fill, edges, sel, bar, hov, box }
local slots = setmetatable({}, weak)     -- case d objet -> { kind, icon, border, box, hl }
local edits = setmetatable({}, weak)     -- champ de saisie -> { fill, edges }
local radios = setmetatable({}, weak)    -- bouton radio -> { outer, inner, mark, label }
local bars = setmetatable({}, weak)      -- barre de defilement -> { thumb, knob }
local labels = setmetatable({}, weak)    -- libelle de Blizzard teinte en or -> true
local titles = setmetatable({}, weak)    -- fenetre -> { fs, size, file } (titre)

local WHITE = { 1, 1, 1 }
local RED = { 0.72, 0.16, 0.16 }   -- lisere d un objet inutilisable (rouge sombre)

local function db()
    local d = ns.skinsDB
    if type(d) ~= "table" or not d.enabled then return nil end
    if d.groups and d.groups.trade == false then return nil end
    return d
end

---------------------------------------------------------------------------
-- Outils (lectures protegees, sans fermeture neuve a chaque appel)
---------------------------------------------------------------------------

local function isTrue(v)
    if issecret(v) then return false end
    return v == true
end

local function objType(o)
    if type(o) ~= "table" or not o.GetObjectType then return nil end
    local ok, t = pcall(o.GetObjectType, o)
    if ok and not issecret(t) and type(t) == "string" then return t end
end

local function get(f, key) return f[key] end
local function packRegions(f) return { f:GetRegions() } end
local function packChildren(f) return { f:GetChildren() } end

local function field(f, key)
    if type(f) ~= "table" then return nil end
    local ok, c = pcall(get, f, key)
    if ok and type(c) == "table" then return c end
end

-- globale de Blizzard (cadre ou region nommes), lue sans metatable
local function global(name)
    local v = rawget(_G, name)
    if type(v) == "table" then return v end
end

local function num(v)
    if issecret(v) or type(v) ~= "number" then return nil end
    return v
end

local function isTex(o) return objType(o) == "Texture" end

-- accesseur du moteur qui rend un objet (texture d etat d un bouton...)
local function askObj(f, m)
    if type(f) ~= "table" or type(f[m]) ~= "function" then return nil end
    local ok, v = pcall(f[m], f)
    if ok and type(v) == "table" then return v end
end

local function nameOf(f)
    if type(f) ~= "table" or not f.GetName then return nil end
    local ok, n = pcall(f.GetName, f)
    if ok and not issecret(n) and type(n) == "string" then return n end
end

local function fade(obj)
    if type(obj) == "table" and obj.SetAlpha and not mine[obj] then pcall(obj.SetAlpha, obj, 0) end
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

local function drawLayer(t)
    if type(t) ~= "table" or not t.GetDrawLayer then return nil end
    local ok, l = pcall(t.GetDrawLayer, t)
    if ok and not issecret(l) and type(l) == "string" then return l end
end

-- texture qui affiche un fichier (case d envoi remplie)
local function hasFile(t)
    if not isTex(t) or not shown(t) then return false end
    local ok, v = pcall(t.GetTexture, t)
    if not ok or issecret(v) then return false end
    return (type(v) == "string" and v ~= "") or type(v) == "number"
end

-- texte d un FontString (false si absent ou secret)
local function textOf(fs)
    if objType(fs) ~= "FontString" then return false end
    local ok, t = pcall(fs.GetText, fs)
    if not ok or issecret(t) or type(t) ~= "string" then return false end
    return t
end

-- texture posee par un autre habillage : a garder
local function owned(r)
    if mine[r] then return true end
    local fn = ns.SkinOwned
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn, r)
    return ok and v == true
end

-- icone recadree (jamais sur un atlas : on casserait ses coordonnees)
local function cropIcon(icon)
    if not isTex(icon) or atlasOf(icon) then return end
    pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
end

-- textures d un cadre (pas celles de ses enfants), sauf les notres
local function fadeOwn(f)
    for _, r in ipairs(regionsOf(f)) do
        if not owned(r) and objType(r) == "Texture" then fade(r) end
    end
end

-- textures d etat d un bouton (normale, enfoncee, survol...)
local function fadeStates(b, list)
    for _, m in ipairs(list) do fade(askObj(b, m)) end
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

-- carre sombre + lisere autour de "anchor"
local function box(host, anchor, out)
    local C = ns.COLORS
    local fill = tex(host, "BACKGROUND", -8)
    fill:SetPoint("TOPLEFT", anchor, "TOPLEFT", -out, out)
    fill:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", out, -out)
    fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.9)
    local edges = ring(host, anchor, "OVERLAY", 7, out)
    paintC(edges, C.border)
    return { fill = fill, edges = edges }
end

-- couleur de sommet d une texture de Blizzard (nil si secrete)
local function vertexOf(t)
    if type(t) ~= "table" or not t.GetVertexColor then return nil end
    local ok, r, g, b = pcall(t.GetVertexColor, t)
    if not ok then return nil end
    r, g, b = num(r), num(g), num(b)
    if r and g and b then return r, g, b end
end

-- bordure de qualite de Blizzard (WhiteIconFrame teinte, cachee par
-- l alpha) : seulement montree et vraiment coloree (le blanc d un objet
-- commun, le gris d un objet pauvre ou d une lettre lue gardent notre lisere)
local function qualityOf(ib)
    if not shown(ib) then return nil end
    local r, g, b = vertexOf(ib)
    if r and (math.max(r, g, b) - math.min(r, g, b)) >= 0.12 then return r, g, b end
end

-- teinte rouge posee par Blizzard sur l icone d un objet inutilisable
-- (SetItemButtonTextureVertexColor 1 / 0.1 / 0.1) : lue, jamais ecrasee
local function redTinted(t)
    local r, g, b = vertexOf(t)
    return (r and r > 0.8 and g < 0.3 and b < 0.3) and true or false
end

-- case d une lettre non lue : Blizzard la teint en jaune (1 / 0.82 / 0),
-- en gris (0.5) une fois lue
local function unread(slot)
    local r, g, b = vertexOf(slot)
    return (r and r > 0.9 and g > 0.6 and b < 0.35) and true or false
end

-- police des titres + or ; on retient la police posee pour la reposer si
-- Blizzard change d objet de police
local function goldFont(fs, size)
    local C = ns.COLORS
    pcall(ns.UI.HeadFont, fs, size)
    pcall(fs.SetTextColor, fs, C.gold[1], C.gold[2], C.gold[3])
    local ok, file = pcall(fs.GetFont, fs)
    return { fs = fs, size = size, file = (ok and not issecret(file) and type(file) == "string") and file or nil }
end

local function keepGold(h)
    local ok, file = pcall(h.fs.GetFont, h.fs)
    if ok and not issecret(file) and type(file) == "string" and h.file and file ~= h.file then
        pcall(ns.UI.HeadFont, h.fs, h.size)
    end
    local C = ns.COLORS
    pcall(h.fs.SetTextColor, h.fs, C.gold[1], C.gold[2], C.gold[3])
end

---------------------------------------------------------------------------
-- Boutons, champs, cases
---------------------------------------------------------------------------

-- plaque plate sous un bouton (textures a nous, au fond du bouton)
local function plate(b, inset, vin)
    if plates[b] then return plates[b] end
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

-- bouton rouge de Blizzard (UIPanelButtonTemplate : Tout ouvrir, Envoyer,
-- Annuler, Repondre, Supprimer, Fermer, Signaler) : ses trois morceaux a
-- alpha 0 (Blizzard change leur fichier au clic, jamais leur alpha), notre
-- plaque dessous ; texte et police intouches
local function panelButton(b)
    if plates[b] or objType(b) ~= "Button" or not b.CreateTexture then return end
    local l, m, r = field(b, "Left"), field(b, "Middle"), field(b, "Right")
    if not (isTex(l) and isTex(m) and isTex(r)) then return end
    fade(l) fade(m) fade(r)
    fadeStates(b, { "GetHighlightTexture" })
    plate(b, 1, 1)
end

-- fleche de page jaune (Precedent / Suivant) : ses etats a alpha 0, petite
-- plaque carree et chevron d or ; le libelle a cote reste celui de Blizzard
local function glyphButton(b, g)
    if plates[b] or objType(b) ~= "Button" or not b.CreateTexture then return end
    fadeStates(b, { "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" })
    local p = plate(b, 6)
    local fs = ns.UI.Chevron(b, 14, g)
    mine[fs] = true
    fs:SetPoint("CENTER", p.fill, "CENTER", 0, 0)
    p.glyph = fs
    for _, r in ipairs(regionsOf(b)) do
        if not mine[r] and objType(r) == "FontString" then
            p.label = r
            break
        end
    end
end

-- fond sombre et lisere d un champ, de "tl" (haut gauche) a "br" (bas droit)
local function fieldBox(e, tl, br)
    local C = ns.COLORS
    local fill = tex(e, "BACKGROUND", -8)
    fill:SetPoint("TOPLEFT", tl, "TOPLEFT", 0, 0)
    fill:SetPoint("BOTTOMRIGHT", br, "BOTTOMRIGHT", 0, 0)
    fill:SetColorTexture(0, 0, 0, 0.55)
    local edges = ring(e, fill, "BACKGROUND", -7, 0)
    paintC(edges, C.border)
    edits[e] = { fill = fill, edges = edges }
    claimed[e] = true
end

-- champ a trois morceaux nommes ($parentLeft / Middle / Right :
-- destinataire, objet) : morceaux a alpha 0, notre fond a leur place ;
-- ni le texte, ni la police, ni le focus ne sont touches
local function namedEdit(e)
    if edits[e] or objType(e) ~= "EditBox" or not e.CreateTexture then return end
    local name = nameOf(e)
    if not name then return end
    local l, m, r = global(name .. "Left"), global(name .. "Middle"), global(name .. "Right")
    if not (isTex(l) and isTex(r)) then return end
    fade(l) fade(m) fade(r)
    fieldBox(e, l, r)
end

-- champ d argent (MoneyFrameEditBoxTemplate : left / right en minuscules,
-- milieu sans cle) : la piece reste
local function moneyEdit(e)
    if edits[e] or objType(e) ~= "EditBox" or not e.CreateTexture then return end
    local l, r = field(e, "left"), field(e, "right")
    if not (isTex(l) and isTex(r)) then return end
    local coin = field(e, "texture")
    for _, x in ipairs(regionsOf(e)) do
        if x ~= coin and not owned(x) and objType(x) == "Texture" then fade(x) end
    end
    fieldBox(e, l, r)
end

-- bouton radio (UIRadioButtonTemplate : Envoyer de l argent / C.R.) :
-- ses etats a alpha 0, losange sombre a lisere, point d or si choisi
local function skinRadio(cb)
    if radios[cb] or objType(cb) ~= "CheckButton" or not cb.CreateTexture then return end
    fadeStates(cb, { "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetCheckedTexture",
                     "GetDisabledCheckedTexture", "GetDisabledTexture" })
    local C = ns.COLORS
    local k = {}
    local function diamond(layer, sub, size)
        local t = tex(cb, layer, sub)
        t:SetSize(size, size)
        t:SetPoint("CENTER", cb, "CENTER", 0, 0)
        pcall(t.SetRotation, t, math.pi / 4)
        return t
    end
    k.outer = diamond("BACKGROUND", -8, 11)
    k.outer:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
    k.inner = diamond("BACKGROUND", -7, 9)
    k.inner:SetColorTexture(0, 0, 0, 0.85)
    k.mark = diamond("OVERLAY", 7, 5)
    k.mark:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    k.mark:Hide()
    local name = nameOf(cb)
    local label = field(cb, "text") or field(cb, "Text") or (name and global(name .. "Text"))
    if objType(label) == "FontString" then k.label = label end
    radios[cb] = k
    claimed[cb] = true
end

-- case d objet : fond sombre, icone recadree, lisere de la qualite (rouge
-- sombre si Blizzard a teint l icone en rouge : objet inutilisable).
--   "send" : SendMailAttachment (bouton simple : l icone est sa texture
--            normale, posee et retiree par Blizzard ; fond UI-Slot-Background
--            au calque BACKGROUND)
--   "open" : ItemButton de la lettre ouverte (icone "icon", cadre
--            UI-Quickslot2 en texture normale)
local function skinSlot(b, kind)
    if slots[b] or type(b) ~= "table" or not b.CreateTexture or not b.GetRegions then return end
    local C = ns.COLORS
    local s = { kind = kind }
    if kind == "send" then
        local nt = askObj(b, "GetNormalTexture")
        for _, r in ipairs(regionsOf(b)) do
            if r ~= nt and not owned(r) and objType(r) == "Texture" and drawLayer(r) == "BACKGROUND" then fade(r) end
        end
        fadeStates(b, { "GetHighlightTexture", "GetPushedTexture" })
        s.box = box(b, b, 1)
        s.hl = tex(b, "HIGHLIGHT")
        s.hl:SetAllPoints(b)
    else
        s.icon = field(b, "icon") or field(b, "Icon")
        if not isTex(s.icon) then return end
        fadeStates(b, { "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" })
        -- l icone de l ItemButton n a pas d ancre a elle (elle remplit le
        -- bouton) : notre carre s ancre sur le bouton, comme Personnage.lua
        s.box = box(b, b, 1)
        s.hl = tex(b, "HIGHLIGHT")
        s.hl:SetAllPoints(b)
    end
    s.hl:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.2)
    s.border = field(b, "IconBorder")
    fade(s.border)
    slots[b] = s
    claimed[b] = true
end

---------------------------------------------------------------------------
-- Onglets du bas (FriendsFrameTabTemplate -> PanelTabButtonTemplate)
---------------------------------------------------------------------------

-- Toutes leurs textures a alpha 0, notre plaque. Blizzard deplace le texte
-- selon l etat (PanelTemplates_SelectTab / DeselectTab : CENTER +2 inactif,
-- -3 actif, sur un onglet de 32 px et un texte de 10 px) : le texte n est
-- jamais touche, nos ancres le suivent (placeTab, a chaque changement).
-- Haut de la plaque colle a la fenetre (1 px sous son bord, comme
-- HotelVentes.lua) ; texte centre dans la plaque : l actif descend plus bas
-- (plaque plus longue), l inactif reste court, en retrait.
local function placeTab(t, s, active)
    local f = s.fill
    local txt = objType(s.text) == "FontString" and s.text or nil
    f:ClearAllPoints()
    f:SetPoint("LEFT", t, "LEFT", 8, 0)
    f:SetPoint("RIGHT", t, "RIGHT", -9, 0)
    f:SetPoint("TOP", t, "TOP", 0, s.off)
    if not txt then
        f:SetPoint("BOTTOM", t, "BOTTOM", 0, 1)
    elseif active then
        -- texte actif : 14 px sous le haut de l onglet
        f:SetPoint("BOTTOM", txt, "BOTTOM", 0, -math.max(2, 14 + s.off))
    else
        -- texte inactif : 9 px sous le haut de l onglet
        f:SetPoint("BOTTOM", txt, "BOTTOM", 0, -math.max(2, 9 + s.off))
    end
end

-- decalage du haut de la plaque depuis le haut de l onglet : 1 px sous le
-- bas de la fenetre (XML : onglet ancre a -30 sous la fenetre, 32 px de haut
-- -> -3) ; mesure a l habillage, repli sur la valeur du XML
local function tabOffset(t, win)
    local okT, top = pcall(t.GetTop, t)
    local okB, bottom = pcall(win.GetBottom, win)
    top, bottom = okT and num(top), okB and num(bottom)
    if top and bottom then
        local off = math.floor(bottom - 1 - top + 0.5)
        if off <= 0 and off >= -12 then return off end
    end
    return -3
end

local function skinTab(t, win)
    fadeOwn(t)
    if tabs[t] or not t.CreateTexture then return end
    local C = ns.COLORS
    local s = { off = tabOffset(t, win) }
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

---------------------------------------------------------------------------
-- Boite de reception
---------------------------------------------------------------------------

-- ligne MailItemN (cadre fixe de 305 x 45, son contenu change a chaque
-- page) : carte a nous, icone dans un carre sombre a lisere
local function skinRow(row, i)
    if rows[row] or not row.CreateTexture then return end
    local C = ns.COLORS
    fadeOwn(row)   -- cadre MailItemBorder et filet brun de Blizzard
    local s = {}
    s.fill = tex(row, "BACKGROUND", -8)
    s.fill:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
    s.fill:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 2)
    s.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.6)
    s.edges = ring(row, s.fill, "BACKGROUND", -5, 0)
    paintC(s.edges, C.border, 0.7)
    s.sel = tex(row, "BACKGROUND", -7)
    s.sel:SetAllPoints(s.fill)
    ns.UI.Gradient(s.sel, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.45, C.violet[1], C.violet[2], C.violet[3], 0.04)
    s.sel:Hide()
    s.hov = tex(row, "BACKGROUND", -7)
    s.hov:SetAllPoints(s.fill)
    ns.UI.Gradient(s.hov, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.22, C.violet[1], C.violet[2], C.violet[3], 0.02)
    s.hov:Hide()
    s.bar = tex(row, "BACKGROUND", -4)
    s.bar:SetPoint("TOPLEFT", s.fill, "TOPLEFT", 0, 0)
    s.bar:SetPoint("BOTTOMLEFT", s.fill, "BOTTOMLEFT", 0, 0)
    s.bar:SetWidth(2)
    s.bar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    s.bar:Hide()
    local b = global("MailItem" .. i .. "Button") or field(row, "Button")
    if objType(b) == "CheckButton" and b.CreateTexture then
        s.b = b
        s.icon = global("MailItem" .. i .. "ButtonIcon") or field(b, "Icon")
        s.slot = global("MailItem" .. i .. "ButtonSlot")
        s.border = field(b, "IconBorder")
        -- case jaune (lue : elle donne l etat), bordure de qualite (lue),
        -- survol et coche de Blizzard : a alpha 0 ; C.R. et compteur gardes
        fade(s.slot)
        fade(s.border)
        fadeStates(b, { "GetHighlightTexture", "GetCheckedTexture" })
        if isTex(s.icon) then
            s.box = box(b, s.icon, 1)
            local hl = tex(b, "HIGHLIGHT")
            hl:SetAllPoints(s.icon)
            hl:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.2)
        end
        claimed[b] = true
    end
    rows[row] = s
    claimed[row] = true
end

local function inbox(mf)
    local ib = field(mf, "InboxFrame") or global("InboxFrame")
    if not ib then return end
    if not done[ib] then
        done[ib] = true
        fadeOwn(ib)   -- InboxFrameBg (UI-MailFrameBG)
    end
    claimed[ib] = true
    for i = 1, 20 do
        local row = global("MailItem" .. i)
        if not row then break end
        skinRow(row, i)
    end
    glyphButton(field(ib, "PrevPageButton"), "<")
    glyphButton(field(ib, "NextPageButton"), ">")
    panelButton(field(ib, "OpenAllMail") or global("OpenAllMail"))
end

---------------------------------------------------------------------------
-- Envoi et lettre ouverte : decor, papier, filets
---------------------------------------------------------------------------

-- puits sombre a la place de l Inset de Blizzard (eteint par Skins.lua) :
-- textures sur la fenetre, ancrees a l Inset (Blizzard le deplace selon
-- l onglet), au-dessus du fond de Skins.lua
local function well(win)
    local inset = field(win, "Inset")
    if not inset or done[inset] or not win.CreateTexture then return end
    done[inset] = true
    local C = ns.COLORS
    local fill = tex(win, "BACKGROUND", -4)
    fill:SetPoint("TOPLEFT", inset, "TOPLEFT", 0, 0)
    fill:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", 0, 0)
    fill:SetColorTexture(0, 0, 0, 0.28)
    paintC(ring(win, fill, "BACKGROUND", -3, 0), C.border)
end

-- morceaux d une barre horizontale de Blizzard (UI-ClassTrainer-
-- HorizontalBar) : la barre nommee et les textures sans nom de "host"
-- ancrees sur elle (XML : Anchor LEFT relativeTo la barre). Rien d autre
-- n est touche (ni le fond de Skins.lua, ni la piece de l erreur C.R.)
local function barPieces(host, bar)
    local list = { bar }
    for _, r in ipairs(regionsOf(host)) do
        if not rawequal(r, bar) and not mine[r] and isTex(r) and r.GetPoint then
            local ok, _, rel = pcall(r.GetPoint, r, 1)
            if ok and rawequal(rel, bar) then list[#list + 1] = r end
        end
    end
    return list
end

-- filet d or a la place d une barre horizontale de Blizzard (ses morceaux a
-- alpha 0) : ancre sur elle, il la suit quand Blizzard la deplace
local function rule(host, bar)
    if not isTex(bar) or ruled[bar] or not host or not host.CreateTexture then return end
    for _, r in ipairs(barPieces(host, bar)) do fade(r) end
    local C = ns.COLORS
    local t = tex(host, "ARTWORK", 1)
    t:SetPoint("LEFT", bar, "LEFT", 8, 0)
    t:SetSize(310, 1)
    ns.UI.Gradient(t, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.75, C.gold[1], C.gold[2], C.gold[3], 0.04)
    ruled[bar] = t
end

-- papier a lettres (garde : le texte du courrier est sombre) : ombre, lisere
-- du theme et filet d or en haut, ancres sur le papier dont Blizzard change
-- la hauteur selon le nombre de rangees d objets
local function paper(sf, left, right)
    if not sf or done[sf] or not sf.CreateTexture or not isTex(left) or not isTex(right) then return end
    done[sf] = true
    local C = ns.COLORS
    local area = tex(sf, "BACKGROUND", -8)
    area:SetPoint("TOPLEFT", left, "TOPLEFT", 0, 0)
    area:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", 0, 0)
    area:SetColorTexture(0, 0, 0, 0)
    for i = 2, 4 do
        local sh = tex(sf, "BACKGROUND", -8)
        sh:SetPoint("TOPLEFT", area, "TOPLEFT", -i, i)
        sh:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", i, -i)
        sh:SetColorTexture(0, 0, 0, 0.2)
    end
    paintC(ring(sf, area, "BORDER", 6, 1), C.border)
    local line = tex(sf, "BORDER", 7)
    line:SetPoint("TOPLEFT", area, "TOPLEFT", -1, 1)
    line:SetPoint("TOPRIGHT", area, "TOPRIGHT", 1, 1)
    line:SetHeight(1)
    ns.UI.Gradient(line, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.9, C.gold[1], C.gold[2], C.gold[3], 0.15)
end

-- barres de defilement (MinimalScrollBar) : alpha et couleur seulement
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

local function skinScrollBar(sb)
    if not sb or bars[sb] then return end
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

-- libelle decoratif (A :, Objet :, De :, Cout :, Montant...) : or ; Blizzard
-- ne relit jamais sa couleur
local function goldLabel(fs)
    if objType(fs) ~= "FontString" or mine[fs] then return end
    labels[fs] = true
    local C = ns.COLORS
    pcall(fs.SetTextColor, fs, C.gold[1], C.gold[2], C.gold[3])
end

-- libelle sans nom d un cadre, reconnu a son texte (chaine de Blizzard)
local function labelByText(f, key)
    local want = rawget(_G, key)
    if type(want) ~= "string" or want == "" then return end
    for _, r in ipairs(regionsOf(f)) do
        if not mine[r] and textOf(r) == want then goldLabel(r) end
    end
end

-- cadre d argent du bas (InsetFrameTemplate + ThinGoldEdgeTemplate) :
-- decor a alpha 0, notre carre ; pieces et chiffres de Blizzard gardes
local function moneyBox(inset, bg)
    if inset and not done[inset] then
        done[inset] = true
        fadeOwn(inset)
        fadeOwn(field(inset, "NineSlice"))
        claimed[inset] = true
    end
    if bg and not done[bg] and bg.CreateTexture then
        done[bg] = true
        fadeOwn(bg)
        box(bg, bg, 0)
        claimed[bg] = true
    end
end

local function send(mf)
    local sf = field(mf, "SendMail") or global("SendMailFrame")
    if not sf then return end
    claimed[sf] = true
    -- textures de SendMailFrame : les deux barres horizontales (quatre
    -- morceaux) ; la piece et le texte de l erreur C.R. restent
    rule(sf, global("SendMailHorizontalBarLeft"))
    rule(sf, global("SendMailHorizontalBarLeft2"))
    local scroll = field(sf, "ScrollFrame") or global("SendMailScrollFrame")
    paper(scroll, global("SendStationeryBackgroundLeft"), global("SendStationeryBackgroundRight"))
    skinScrollBar(scrollBarOf(scroll))
    local nameBox = field(sf, "NameEditBox") or global("SendMailNameEditBox")
    local subjBox = field(sf, "SubjectEditBox") or global("SendMailSubjectEditBox")
    namedEdit(nameBox)
    namedEdit(subjBox)
    labelByText(nameBox, "MAIL_TO_LABEL")
    labelByText(subjBox, "MAIL_SUBJECT_LABEL")
    labelByText(global("SendMailCostMoneyFrame"), "SEND_MAIL_COST")
    goldLabel(global("SendMailMoneyText"))
    for i = 1, 16 do
        local b = global("SendMailAttachment" .. i)
        if objType(b) == "Button" then skinSlot(b, "send") end
    end
    skinRadio(global("SendMailSendMoneyButton"))
    skinRadio(global("SendMailCODButton"))
    local money = global("SendMailMoney")
    for _, k in ipairs({ "gold", "silver", "copper" }) do moneyEdit(field(money, k)) end
    moneyBox(global("SendMailMoneyInset"), global("SendMailMoneyBg"))
    panelButton(field(sf, "SendButton") or global("SendMailMailButton"))
    panelButton(field(sf, "CancelButton") or global("SendMailCancelButton"))
end

-- lettre ouverte (OpenMailFrame, keep = true dans Fenetres.lua : Skins.lua
-- y garde les textures posees sur la fenetre) : on eteint seulement les
-- deux morceaux de sa barre horizontale ; le fond de Skins.lua n est
-- jamais touche
local function openMail(om)
    rule(om, global("OpenMailHorizontalBarLeft"))
    well(om)
    local scroll = field(om, "ScrollFrame") or global("OpenMailScrollFrame")
    paper(scroll, global("OpenStationeryBackgroundLeft"), global("OpenStationeryBackgroundRight"))
    skinScrollBar(scrollBarOf(scroll))
    goldLabel(global("OpenMailSenderLabel"))
    goldLabel(global("OpenMailSubjectLabel"))
    skinSlot(global("OpenMailLetterButton"), "open")
    skinSlot(global("OpenMailMoneyButton"), "open")
    for i = 1, 16 do
        local b = global("OpenMailAttachmentButton" .. i)
        if b then skinSlot(b, "open") end
    end
    for _, k in ipairs({ "ReplyButton", "DeleteButton", "CancelButton", "ReportSpamButton" }) do
        panelButton(field(om, k))
    end
end

---------------------------------------------------------------------------
-- Releve leger (10 fois par seconde, fenetre ouverte) : etats et couleurs
---------------------------------------------------------------------------

local function plateState(b, p)
    local C = ns.COLORS
    local en = enabled(b)
    local over = en and isOver(b)
    tint(p, over and C.gold or C.border)
    local a = en and 1 or 0.5
    if a ~= p.a then
        p.a = a
        p.fill:SetAlpha(a)
    end
    if p.glyph then
        local c = en and C.gold or C.text
        p.glyph:SetTextColor(c[1], c[2], c[3], en and 1 or 0.35)
    end
    -- libelle Precedent / Suivant : texte de CorpUI, blanc au survol,
    -- attenue sans page ; reposee a chaque releve, jamais la police
    if p.label then
        local c = over and WHITE or C.text
        local m = en and 1 or 0.45
        pcall(p.label.SetTextColor, p.label, c[1] * m, c[2] * m, c[3] * m)
    end
end

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
    if objType(s.text) == "FontString" then
        local c = active and C.gold or (over and WHITE or C.text)
        pcall(s.text.SetTextColor, s.text, c[1], c[2], c[3])
    end
end

local function editState(e, k)
    local C = ns.COLORS
    local okF, focus = pcall(e.HasFocus, e)
    if okF and isTrue(focus) then tint(k, C.gold)
    elseif isOver(e) then tint(k, C.violet)
    else tint(k, C.border) end
end

local function radioState(cb, k)
    local C = ns.COLORS
    local okC, on = pcall(cb.GetChecked, cb)
    local en = enabled(cb)
    local over = en and isOver(cb)
    k.mark:SetShown(okC and isTrue(on))
    local c = over and C.gold or C.border
    if k.c ~= c then
        k.c = c
        k.outer:SetColorTexture(c[1], c[2], c[3], 1)
    end
    local a = en and 1 or 0.4
    if k.a ~= a then
        k.a = a
        k.outer:SetAlpha(a)
        k.mark:SetAlpha(a)
    end
    -- libelle : texte de CorpUI, blanc au survol, gris si desactive (le C.R.
    -- sans objet joint : Blizzard le grise aussi)
    if k.label then
        local lc = over and WHITE or C.text
        local m = en and 1 or 0.5
        pcall(k.label.SetTextColor, k.label, lc[1] * m, lc[2] * m, lc[3] * m)
    end
end

-- lettre : carte (ouverte : degrade et barre d or ; survol de l icone :
-- degrade leger), icone : qualite > non lue (or) > theme
local function rowState(row, s)
    local C = ns.COLORS
    local b = s.b
    local has = b ~= nil and shown(b)
    if has ~= s.has then
        s.has = has
        s.fill:SetShown(has)
        showAll(s.edges, has)
        if not has then
            s.sel:Hide()
            s.bar:Hide()
            s.hov:Hide()
        end
    end
    if not has then return end
    local okC, on = pcall(b.GetChecked, b)
    on = okC and isTrue(on)
    local over = isOver(b)
    s.sel:SetShown(on)
    s.bar:SetShown(on)
    s.hov:SetShown(over and not on)
    tint(s, on and C.gold or (over and C.violet or C.border), (on or over) and 1 or 0.7)
    cropIcon(s.icon)
    if not s.box then return end
    local r, g, bl = qualityOf(s.border)
    local key
    if r then key = string.format("q%.3f:%.3f:%.3f", r, g, bl)
    elseif unread(s.slot) then key = "u"
    else key = "-" end
    if key ~= s.ikey then
        s.ikey = key
        if r then paint(s.box.edges, r, g, bl, 1)
        elseif key == "u" then paintC(s.box.edges, C.gold, 1)
        else paintC(s.box.edges, C.border, 1) end
    end
end

local function slotState(b, s)
    local C = ns.COLORS
    local icon = s.icon
    if s.kind == "send" then icon = askObj(b, "GetNormalTexture") end
    cropIcon(icon)
    local full = s.kind ~= "send" or hasFile(icon)
    local key, r, g, bl
    if full and redTinted(icon) then
        key, r, g, bl = "r", RED[1], RED[2], RED[3]
    else
        r, g, bl = qualityOf(s.border)
        if r then key = string.format("q%.3f:%.3f:%.3f", r, g, bl) else key = full and "-" or "0" end
    end
    if key ~= s.key then
        s.key = key
        if r then paint(s.box.edges, r, g, bl, 1) else paintC(s.box.edges, C.border, full and 1 or 0.55) end
        s.box.fill:SetAlpha(full and 1 or 0.7)
    end
end

local function barState(_, k)
    local C = ns.COLORS
    local over = isOver(k.thumb)
    if over ~= k.over then
        k.over = over
        if over then
            k.knob:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.9)
        else
            k.knob:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.6)
        end
    end
end

local function report(err)
    local d = ns.skinsDB
    if type(d) == "table" then
        d.errors = d.errors or {}
        d.errors.Mail = tostring(err)
    end
end

local function each(list, fn)
    for k, s in pairs(list) do
        if visible(k) then
            local ok, err = pcall(fn, k, s)
            if not ok then report(err) end
        end
    end
end

local function keepTitle(win)
    local fs = field(field(win, "TitleContainer"), "TitleText")
    if objType(fs) ~= "FontString" then return end
    local h = titles[win]
    if not h or h.fs ~= fs then titles[win] = goldFont(fs, 12) else keepGold(h) end
end

local function light(mf, om, mv, ov)
    if mv then pcall(keepTitle, mf) end
    if ov then pcall(keepTitle, om) end
    each(tabs, tabState)
    each(plates, plateState)
    each(edits, editState)
    each(radios, radioState)
    each(rows, rowState)
    each(slots, slotState)
    each(bars, barState)
    local C = ns.COLORS
    for fs in pairs(labels) do
        if visible(fs) then pcall(fs.SetTextColor, fs, C.gold[1], C.gold[2], C.gold[3]) end
    end
end

local function try(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then report(err) end
end

-- passage complet (ouverture, onglet change, sinon toutes les 0,6 s) :
-- tout est fixe dans ces fenetres (aucun pool), chaque element n est
-- habille qu une fois
local function full(mf, om, mv, ov)
    if mv then
        for i = 1, 4 do
            local t = global("MailFrameTab" .. i)
            if objType(t) == "Button" then try(skinTab, t, mf) end
        end
        try(well, mf)
        try(inbox, mf)
        try(send, mf)
    end
    if ov then try(openMail, om) end
end

---------------------------------------------------------------------------
-- Partage avec Skins.lua
---------------------------------------------------------------------------

-- Skins.lua ne descend pas dans le courrier (tout est repris ici, sans
-- course au chargement : la parente suffit) ; nos textures ne sont jamais
-- eteintes
local prevClaimed = ns.SkinClaimed
function ns.SkinClaimed(f)
    if type(f) == "table" and db() then
        if claimed[f] then return true end
        if f.GetParent then
            local ok, p = pcall(f.GetParent, f)
            if ok and type(p) == "table" then
                local mf, om = global("MailFrame"), global("OpenMailFrame")
                if (mf and rawequal(p, mf)) or (om and rawequal(p, om)) then return true end
            end
        end
    end
    return (prevClaimed and prevClaimed(f)) or false
end

local prevOwned = ns.SkinOwned
function ns.SkinOwned(r)
    if type(r) == "table" and mine[r] then return true end
    return (prevOwned and prevOwned(r)) or false
end

---------------------------------------------------------------------------

local state = { shown = false, key = nil }
local acc, walkAcc = 0, 0

local function pageKey(mf, om)
    return (visible(field(mf, "InboxFrame")) and "i" or "-") .. (visible(field(mf, "SendMail")) and "s" or "-")
        .. (visible(om) and "o" or "-")
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if ns.ModuleOff("habillage", ev) then return end
    if event == "PLAYER_REGEN_ENABLED" then state.shown = false end
end)
pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")

ns.Every(0.1, function(dt)
    walkAcc = walkAcc + dt
    if not db() or InCombatLockdown() then return end
    local mf, om = global("MailFrame"), global("OpenMailFrame")
    local mv = mf ~= nil and mf.CreateTexture ~= nil and visible(mf)
    local ov = om ~= nil and om.CreateTexture ~= nil and visible(om)
    if not mv and not ov then
        state.shown = false
        return
    end
    local key = pageKey(mf, om)
    if not state.shown or key ~= state.key or walkAcc >= 0.6 then
        state.shown, state.key, walkAcc = true, key, 0
        try(full, mf, om, mv, ov)
    end
    try(light, mf, om, mv, ov)
end, "Habillage : Courrier", "habillage")
