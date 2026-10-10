--[[--------------------------------------------------------------------------
    CorpUI - module Chat
    Style CorpUI pour les fenetres de discussion de Blizzard :
      - fond du theme (opacite reglable) a la place du fond de Blizzard ;
      - le fond s arrete sous les onglets (plaques detachees, l active
        soulignee a la couleur d accent) ; colonne d icones a gauche, du
        meme bord ;
      - zone de saisie au style du theme ;
      - bouton de copie : ouvre une fenetre ou le texte recent est
        selectionnable (Ctrl+C), liens et adresses compris ; les adresses
        web y sont reperees (clic droit sur le bouton : la derniere) ;
      - heure devant les messages et noms aux couleurs de classe : simples
        reglages du jeu (CVar showTimestamps, chatClassColorOverride) que le
        code de Blizzard lit lui-meme, changes seulement depuis le panneau.

    Precautions propres a ce client (valeurs secretes) :
      - aucun filtre de message, aucun crochet : notre code ne s execute
        jamais dans le traitement des messages de Blizzard ;
      - on ne change que l apparence (transparence de leurs textures, cadres
        a nous glisses dessous). Blizzard refait apparaitre son fond au
        survol : un releve leger le recoupe.
      - la position et la taille des fenetres restent celles du jeu (clic
        droit sur l onglet, ou mode Edition).
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local MAX_WINDOWS = 20      -- fenetres temporaires (chuchotements) comprises

local issecret = issecretvalue or function() return false end

local db
local skinned = {}          -- fenetre de chat -> { bg, tab, edit, copy }
local faded = {}            -- textures de Blizzard a garder transparentes

-- Efface un dessin de Blizzard. Une texture est videe (SetTexture(nil)) :
-- Blizzard ne fait ensuite que jouer sur son opacite (fondus), elle reste
-- donc invisible sans qu on ait a la recouper sans cesse (ce bras de fer
-- faisait clignoter le chat). Un texte, lui, passe simplement a 0.
local function fade(t)
    if not t or not t.SetAlpha then return end
    if t.GetObjectType and t:GetObjectType() == "Texture" then
        pcall(t.SetTexture, t, nil)
        pcall(t.SetAtlas, t, nil)
    end
    pcall(t.SetAlpha, t, 0)
end

local function fadeRegions(f)
    if not f or not f.GetRegions then return end
    local ok, regions = pcall(function() return { f:GetRegions() } end)
    if not ok then return end
    for _, r in ipairs(regions) do
        if r.GetObjectType and r:GetObjectType() == "Texture" then fade(r) end
    end
end

---------------------------------------------------------------------------
-- Fenetre de copie
---------------------------------------------------------------------------

local copyWin

-- texte lisible et copiable : sans couleurs ni icones, liens en [texte]
local function plain(s)
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    s = s:gsub("|H.-|h(.-)|h", "%1")
    -- pluriels du jeu : "2 |4jour:jours;" -> "2 jours"
    s = s:gsub("(%d+)(%s*)|4([^:;]*):([^;]*);", function(n, sp, one, many)
        return n .. sp .. (tonumber(n) == 1 and one or many)
    end)
    s = s:gsub("|4[^:;]*:([^;]*);", "%1")
    return s
end

local function buildCopy()
    local C = ns.COLORS
    copyWin = CreateFrame("Frame", "CorpUIChatCopy", UIParent, "BackdropTemplate")
    copyWin:SetSize(560, 360)
    copyWin:SetPoint("CENTER")
    copyWin:SetFrameStrata("DIALOG")
    copyWin:SetToplevel(true)
    copyWin:SetClampedToScreen(true)
    copyWin:SetMovable(true)
    copyWin:EnableMouse(true)
    copyWin:RegisterForDrag("LeftButton")
    copyWin:SetScript("OnDragStart", copyWin.StartMoving)
    copyWin:SetScript("OnDragStop", copyWin.StopMovingOrSizing)
    ns.UI.SetBackdrop(copyWin, 0.97)
    ns.UI.Shadow(copyWin, 5)

    local title = copyWin:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(title, 14)
    title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    title:SetPoint("TOPLEFT", 10, -9)
    title:SetText(L.CHAT_COPY_TITLE)
    local hint = copyWin:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", title, "RIGHT", 10, 0)
    hint:SetText(L.CHAT_COPY_HINT)

    local close = ns.UI.Button(copyWin, "×", 24, function() copyWin:Hide() end)
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -6, -6)

    local scroll = CreateFrame("ScrollFrame", nil, copyWin, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -34)
    scroll:SetPoint("BOTTOMRIGHT", -30, 10)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetWidth(510)
    edit:SetScript("OnEscapePressed", function() copyWin:Hide() end)
    scroll:SetScrollChild(edit)
    copyWin.edit, copyWin.scroll = edit, scroll

    -- ligne des adresses web : l adresse choisie, deja selectionnee, dans une
    -- zone d une ligne (Ctrl+C) ; < et > passent aux autres adresses
    local row = CreateFrame("Frame", nil, copyWin)
    row:SetPoint("BOTTOMLEFT", 10, 8)
    row:SetPoint("BOTTOMRIGHT", -10, 8)
    row:SetHeight(22)
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", 0, 0)
    label:SetText(L.CHAT_URL_LABEL)
    label:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    local nextB = ns.UI.Button(row, ">", 22, function() copyWin.ShowUrl((copyWin.urlIndex or 0) + 1) end)
    nextB:SetSize(22, 22)
    nextB:SetPoint("RIGHT", 0, 0)
    local count = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    count:SetPoint("RIGHT", nextB, "LEFT", -6, 0)
    local prevB = ns.UI.Button(row, "<", 22, function() copyWin.ShowUrl((copyWin.urlIndex or 2) - 1) end)
    prevB:SetSize(22, 22)
    prevB:SetPoint("RIGHT", count, "LEFT", -6, 0)
    local box = CreateFrame("EditBox", nil, row, "BackdropTemplate")
    box:SetPoint("LEFT", label, "RIGHT", 8, 0)
    box:SetPoint("RIGHT", prevB, "LEFT", -6, 0)
    box:SetHeight(22)
    ns.UI.SetBackdrop(box, 0.6)
    box:SetAutoFocus(false)
    box:SetFontObject("ChatFontNormal")
    box:SetTextInsets(6, 6, 0, 0)
    box:SetScript("OnEscapePressed", function() copyWin:Hide() end)
    box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    box:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    -- lecture seule : une frappe remet l adresse
    box:SetScript("OnTextChanged", function(self, user)
        if user then
            self:SetText(copyWin.urls and copyWin.urls[copyWin.urlIndex or 0] or "")
            self:HighlightText()
        end
    end)
    local none = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    none:SetPoint("LEFT", 6, 0)
    none:SetText(L.CHAT_URL_NONE)
    copyWin.urlRow, copyWin.urlBox = row, box

    function copyWin.ShowUrl(i)
        local urls = copyWin.urls or {}
        local n = #urls
        i = math.max(math.min(i or n, n), n > 0 and 1 or 0)
        copyWin.urlIndex = i
        box:SetText(urls[i] or "")
        box:SetCursorPosition(0)
        none:SetShown(n == 0)
        count:SetText(n > 0 and (i .. " / " .. n) or "")
        prevB:SetShown(n > 1)
        nextB:SetShown(n > 1)
        if box:HasFocus() then box:HighlightText() end
    end
    copyWin:Hide()
end

-- Adresses web d une ligne deja nettoyee (plain) : http://, https://, www.
-- La ponctuation collee autour (parentheses, point final...) est retiree.
local function findUrls(s, out)
    for word in s:gmatch("%S+") do
        local w = word:gsub("^[%(%[<\"']+", "")
        local lw = w:lower()
        if lw:find("^https?://[%w%[]") or lw:find("^www%.[%w%-]+%.%a") then
            w = w:gsub("[%.,;:!%?%)%]>\"']+$", "")
            out[#out + 1] = w
        end
    end
end

-- wantUrl : ouvre sur la derniere adresse web, selectionnee (clic droit)
local function openCopy(cf, wantUrl)
    if not copyWin then buildCopy() end
    local lines, found = {}, {}
    local okN, n = pcall(cf.GetNumMessages, cf)
    n = okN and type(n) == "number" and not issecret(n) and n or 0
    for i = math.max(1, n - 300), n do
        local ok, text = pcall(cf.GetMessageInfo, cf, i)
        -- message secret (combat, instance...) : illisible pour un addon, on
        -- le saute avant toute operation de chaine
        if ok and not issecret(text) and type(text) == "string" then
            local okP, p = pcall(plain, text)
            if okP and type(p) == "string" then
                lines[#lines + 1] = p
                if db and db.urls then pcall(findUrls, p, found) end
            end
        end
    end
    -- chaque adresse une fois, a sa derniere apparition, dans l ordre
    local urls, seen = {}, {}
    for i = #found, 1, -1 do
        local u = found[i]
        if not seen[u] then seen[u] = true table.insert(urls, 1, u) end
    end
    copyWin.urls = urls
    local showUrls = db and db.urls
    copyWin.urlRow:SetShown(showUrls and true or false)
    copyWin.scroll:SetPoint("BOTTOMRIGHT", -30, showUrls and 38 or 10)
    copyWin.ShowUrl(#urls)
    copyWin.edit:SetText(table.concat(lines, "\n"))
    copyWin:Show()
    if wantUrl and showUrls and #urls > 0 then
        copyWin.urlBox:SetFocus()
        copyWin.urlBox:HighlightText()
    else
        copyWin.edit:SetFocus()
        copyWin.edit:HighlightText()
    end
    -- en bas, la ou sont les messages recents
    C_Timer.After(0, function() copyWin.scroll:SetVerticalScroll(copyWin.scroll:GetVerticalScrollRange()) end)
end

---------------------------------------------------------------------------
-- Habillage d une fenetre de chat
--   un seul panneau par fenetre : bandeau d onglets (degrade d accent +
--   filigrane d or), zone des messages sur le motif runique, ombre ;
--   onglets en texte seul, l onglet actif souligne d or ;
--   zone de saisie en barre plate, liseré a la couleur du canal.
---------------------------------------------------------------------------

local MEDIA = ns.MEDIA
local EDIT = 24           -- hauteur de la zone de saisie (sous les messages)
-- (10/10, variante B choisie parmi quatre) le fond du chat s arrete au bas
-- des onglets, PANEL_TOP au-dessus des messages ; les onglets sont des
-- plaques detachees, TAB_GAP au-dessus de ce bord ; la colonne d icones
-- part du meme bord
local PANEL_TOP = 3
local TAB_GAP = 3
-- place prise a gauche par la colonne d icones (0 si aucune icone) ;
-- declaree ici : place() (zone de saisie) la lit, layoutButtons l ecrit
local colOffset = 0

-- Fenetre qui donne la place du panneau : pour les fenetres ancrees
-- ensemble (General, Journal de combat...), toujours la principale. Le
-- journal de combat est descendu par Blizzard pour loger ses filtres : s y
-- caler decalait le panneau d un onglet a l autre.
local function hostOf(cf)
    local ok, docked = pcall(function() return cf.isDocked end)
    local dock = GENERAL_CHAT_DOCK
    local primary = dock and dock.primary
    if ok and docked and primary then return primary end
    return cf
end

local function buildPanel(cf)
    local C = ns.COLORS
    local p = CreateFrame("Frame", nil, cf, "BackdropTemplate")
    -- couche LOW : sous les onglets de Blizzard (MEDIUM, niveau bas) et sous
    -- les messages ; sinon notre fond voile le texte des onglets
    p:SetFrameStrata("LOW")
    p:SetFrameLevel(1)
    ns.UI.SetBackdrop(p, db.alpha)
    ns.UI.Shadow(p, 4)

    -- bord du haut a la couleur d accent (les onglets sont au-dessus du fond)
    p.accent = p:CreateTexture(nil, "ARTWORK")
    p.accent:SetPoint("TOPLEFT", 1, -1)
    p.accent:SetPoint("TOPRIGHT", -1, -1)
    p.accent:SetHeight(1)
    ns.NoSnap(p.accent)
    p.accent:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.9)

    -- zone de saisie, integree au bas du panneau
    local edit = CreateFrame("Frame", nil, p)
    edit:SetPoint("BOTTOMLEFT", 1, 1)
    edit:SetPoint("BOTTOMRIGHT", -1, 1)
    edit:SetHeight(EDIT)
    edit.bg = edit:CreateTexture(nil, "BACKGROUND", nil, 3)
    edit.bg:SetAllPoints()
    edit.bg:SetColorTexture(0, 0, 0, 0.35)
    edit.sep = edit:CreateTexture(nil, "ARTWORK")
    edit.sep:SetPoint("BOTTOMLEFT", edit, "TOPLEFT", 0, 0)
    edit.sep:SetPoint("BOTTOMRIGHT", edit, "TOPRIGHT", 0, 0)
    edit.sep:SetHeight(1)
    ns.NoSnap(edit.sep)
    edit.sep:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
    -- liseré gauche a la couleur du canal (Dire, Groupe, Guilde...)
    edit.bar = edit:CreateTexture(nil, "ARTWORK")
    edit.bar:SetPoint("TOPLEFT", 0, 0)
    edit.bar:SetPoint("BOTTOMLEFT", 0, 0)
    edit.bar:SetWidth(3)
    p.edit = edit
    return p
end

-- place le panneau et la zone de saisie de Blizzard (qui flottait dessous)
-- champ de saisie encadre (09/10, style choisi parmi quatre) : sous le chat,
-- a la place de la barre d infos du dessous (ns.ChatBox), 3 px sous la
-- fenetre ; fond sombre et lisere a la couleur du canal portes par la zone
-- de saisie elle-meme : visibles quelle que soit la fenetre choisie (avant,
-- ils etaient sur le panneau de General, cache sous un autre onglet)
local FIELD_GAP = 3
local FIELD_H = EDIT - 4

local function place(s, cf)
    local host = hostOf(cf)
    -- le panneau ne s agrandit plus pour la saisie : elle a son propre champ
    local withEdit = false
    if s.host ~= host or s.withEdit ~= withEdit then
        s.host, s.withEdit = host, withEdit
        local p = s.panel
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", host, "TOPLEFT", -6, PANEL_TOP)
        p:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 6, withEdit and -(EDIT + 6) or -6)
        p.edit:SetShown(withEdit)
    end
    -- bouton "revenir en bas" : dans le coin bas droit des messages (Blizzard
    -- l accroche a sa poignee de redimensionnement, hors de notre panneau)
    local tb = s.toBottom
    if tb then
        local _, rel = tb:GetPoint(1)
        if rel ~= cf then
            tb:ClearAllPoints()
            tb:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 0, 2)
            -- (notre barre de defilement s arrete au-dessus de lui)
        end
    end
    local eb = s.eb
    if eb and eb:IsShown() then
        local _, rel, _, x, y = eb:GetPoint(1)
        local lx = -6 - colOffset
        if rel ~= host or x ~= lx or y ~= -(6 + FIELD_GAP) then
            eb:ClearAllPoints()
            eb:SetPoint("TOPLEFT", host, "BOTTOMLEFT", lx, -(6 + FIELD_GAP))
            eb:SetPoint("TOPRIGHT", host, "BOTTOMRIGHT", 6, -(6 + FIELD_GAP))
            eb:SetHeight(FIELD_H)
        end
    end
end

-- texte d un onglet : GetFontString, ou le champ Text selon le modele
local function tabText(tab)
    local fs = tab.GetFontString and tab:GetFontString()
    if not fs then
        local ok, t = pcall(function() return tab.Text end)
        if ok and type(t) == "table" and t.SetTextColor then fs = t end
    end
    return fs
end

-- Libelles d onglets a nous : Blizzard estompe ses onglets image par image
-- (UIFrameFade), impossible a contrer proprement. On rend ses textes
-- invisibles (les onglets restent cliquables) et on dessine nos libelles sur
-- un calque commun, juste au-dessus des onglets.
local labelHost
local function styleTab(tab)
    local C = ns.COLORS
    if not labelHost then
        labelHost = CreateFrame("Frame", nil, UIParent)
        -- meme couche que les onglets (MEDIUM), juste au-dessus d eux : le
        -- gestionnaire d ancrage de Blizzard (LOW) voilait un calque plus bas
        labelHost:SetFrameStrata("MEDIUM")
        labelHost:SetFrameLevel(math.max(tab:GetFrameLevel() + 2, 10))
        labelHost:SetAllPoints(UIParent)
    end
    fadeRegions(tab)
    local fs = tabText(tab)
    if fs then fade(fs) end
    local t = {}
    -- onglet en plaque detachee (10/10, variante B) : toute la largeur de
    -- l onglet de Blizzard, au-dessus du fond ; l actif a la couleur du chat
    -- et souligne, les autres plus pales. Calage refait par tabGeom (refresh)
    t.plate = labelHost:CreateTexture(nil, "BACKGROUND", nil, 1)
    ns.NoSnap(t.plate)
    t.edges = {}
    -- haut, gauche, droite : jamais de bord en bas (ouvert sur le chat)
    for i, pts in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local e = labelHost:CreateTexture(nil, "BACKGROUND", nil, 2)
        e:SetPoint(pts[1], t.plate, pts[1], 0, 0)
        e:SetPoint(pts[2], t.plate, pts[2], 0, 0)
        if i == 1 then e:SetHeight(1) else e:SetWidth(1) end
        ns.NoSnap(e)
        t.edges[i] = e
    end
    -- onglet actif souligne en bas de sa plaque (detachee du fond)
    t.bottom = labelHost:CreateTexture(nil, "BACKGROUND", nil, 3)
    t.bottom:SetPoint("BOTTOMLEFT", t.plate, "BOTTOMLEFT", 0, 0)
    t.bottom:SetPoint("BOTTOMRIGHT", t.plate, "BOTTOMRIGHT", 0, 0)
    t.bottom:SetHeight(2)
    ns.NoSnap(t.bottom)
    t.bottom:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 1)
    t.bottom:Hide()
    -- message non lu (onglet ferme) : voile a la couleur d accent qui pulse,
    -- a la place de la lueur de Blizzard (videe avec ses autres textures)
    t.glow = labelHost:CreateTexture(nil, "BACKGROUND", nil, 2)
    t.glow:SetAllPoints(t.plate)
    ns.NoSnap(t.glow)
    t.glow:Hide()
    t.label = labelHost:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t.label:SetPoint("CENTER", t.plate, "CENTER", 0, -1)
    t.label:SetShadowColor(0, 0, 0, 1)
    t.label:SetShadowOffset(1, -1)
    -- coupe a la largeur de l onglet (les onglets d un dock charge sont
    -- etroits : "Journal de combat" debordait sur ses voisins)
    t.label:SetWordWrap(false)
    return t
end

-- hauteur des plaques (toutes la meme)
local TAB_H = 22

-- plaque detachee, TAB_GAP au-dessus du bord du fond (lui-meme PANEL_TOP
-- au-dessus du haut du chat, comme le bas des onglets de Blizzard : 3 pour
-- General, 4 pour les onglets du cadre defilant, mesure en jeu le 09/10)
local function tabGeom(t, tab, host)
    local hb, tb = host:GetTop(), tab:GetBottom()
    if not hb or not tb then return end
    local dy = math.floor((hb + PANEL_TOP + TAB_GAP - tb) * 10 + 0.5) / 10
    local h = TAB_H
    if t.dy == dy and t.h == h and t.anchor == tab then return end
    t.dy, t.h, t.anchor = dy, h, tab
    t.plate:ClearAllPoints()
    t.plate:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 1, dy)
    t.plate:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -1, dy)
    t.plate:SetHeight(h)
end

-- Message non lu sur un onglet ferme : le jeu le signale lui-meme
-- (FCF_StartAlertFlash pose tab.alerting et fait clignoter tab.glow, que
-- styleTab a vide ; FCF_StopAlertFlash a l ouverture de l onglet). On ne
-- fait que lire ces champs, sans crochet.
local function tabAlert(tab)
    if rawget(tab, "alerting") == true then return true end
    local g = rawget(tab, "glow")
    if type(g) == "table" and g.IsShown then
        local ok, shown = pcall(g.IsShown, g)
        return ok and shown == true
    end
    return false
end

-- plaques en alerte : leur voile pulse a chaque image (periode ~1,8 s)
local pulsing = {}
local function pulse()
    if not next(pulsing) then return end
    local C = ns.COLORS
    local a = 0.12 + 0.36 * (0.5 + 0.5 * math.sin(GetTime() * 3.5))
    for look in pairs(pulsing) do look.glow:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], a) end
end

-- couleurs de la plaque : "on" (onglet actif, couleur du chat), "over"
-- (survol), "alert" (message non lu : liseré d accent), sinon repos (en
-- retrait, sombre)
local function plateLook(t, state)
    -- (opacite du chat changee dans les options : la plaque suit)
    if t.state == state and t.alpha == db.alpha then return end
    t.state, t.alpha = state, db.alpha
    -- l active a la couleur du fond du chat, soulignee ; les autres plus pales
    local C = ns.COLORS
    local fa, ea
    if state == "on" then
        fa, ea = db.alpha, 0.14
    elseif state == "over" then
        fa, ea = db.alpha * 0.75, 0.12
    elseif state == "alert" then
        fa, ea = db.alpha * 0.75, 0.8
    else
        fa, ea = db.alpha * 0.5, 0.06
    end
    local fr, fg, fb = C.bg[1], C.bg[2], C.bg[3]
    t.bottom:SetShown(state == "on")
    t.plate:SetColorTexture(fr, fg, fb, fa)
    local er, eg, eb = 1, 1, 1
    if state == "alert" then er, eg, eb = C.violet[1], C.violet[2], C.violet[3] end
    for _, e in ipairs(t.edges) do e:SetColorTexture(er, eg, eb, ea) end
end

local function showLook(t, on)
    t.label:SetShown(on)
    t.plate:SetShown(on)
    for _, e in ipairs(t.edges) do e:SetShown(on) end
    if not on then
        t.bottom:Hide()
        t.glow:Hide()
        pulsing[t] = nil
    end
end

local function styleEdit(eb)
    fadeRegions(eb)
    local ebName = eb:GetName()
    if type(ebName) == "string" then
        for _, part in ipairs({ "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }) do
            fade(_G[ebName .. part])
        end
    end
end

---------------------------------------------------------------------------
-- Barre de boutons : copie + boutons de Blizzard (menu, canaux, voix,
-- social) en petites icones carrees, dans le bandeau des onglets
---------------------------------------------------------------------------

local BLIZZ_BUTTONS = { "ChatFrameMenuButton", "ChatFrameChannelButton", "ChatFrameToggleVoiceDeafenButton",
                        "ChatFrameToggleVoiceMuteButton", "TextToSpeechButton", "QuickJoinToastButton" }
local ICON = 20
-- icones dessinees pour CorpUI (Nano Banana) : Media/chat_*.tga
local ICONS = {
    ChatFrameMenuButton = "chat_menu", ChatFrameChannelButton = "chat_channels",
    QuickJoinToastButton = "chat_social",
}

-- toutes les textures d un bouton de Blizzard (et de ses enfants) deviennent
-- transparentes : notre icone, dessous, se voit ; le bouton reste cliquable
local function fadeButtonArt(b, depth)
    depth = depth or 0
    fadeRegions(b)
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        if b[get] then
            local ok, t = pcall(b[get], b)
            if ok and t then fade(t) end
        end
    end
    -- bouton social : son dessin est dans FriendsButton ; ses notifications
    -- (groupe rapide) restent intactes
    if depth == 0 then
        local ok, fb = pcall(function() return b.FriendsButton end)
        if ok and type(fb) == "table" and fb.GetRegions then fadeButtonArt(fb, 1) end
    end
end

local function slotIcon(slot, file)
    local icon = slot:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexture(MEDIA .. file)
    return icon
end
local buttonBar, slots = nil, {}
local combatAsIcon
-- colonne d icones accolee a gauche du chat (09/10, a la place de la rangee
-- dans le bandeau des onglets) : largeur, ecart avec le panneau ; colOffset :
-- place qu elle prend a gauche (0 si aucune icone), lue par placeCorner,
-- place (zone de saisie) et ns.ChatBox (bandeau d infos sous le chat)
local COL_W, COL_GAP = ICON + 8, 2
local column
-- ordre de haut en bas
local RANK = { QuickJoinToastButton = 2, ChatFrameChannelButton = 3, ChatFrameMenuButton = 4,
               ChatFrameToggleVoiceDeafenButton = 5, ChatFrameToggleVoiceMuteButton = 6, TextToSpeechButton = 7 }
local function rankOf(e)
    if e.combat then return 1 end
    if e.own then return 9 end
    return RANK[e.name] or 8
end
local dockInset             -- recul du bord droit des onglets (largeur des icones)

local function makeSlot()
    local slot = CreateFrame("Frame", nil, buttonBar)
    slot:SetSize(ICON, ICON)
    ns.UI.Skin(slot, 0.95)
    return slot
end

local function buildButtonBar()
    if buttonBar then return end
    local C = ns.COLORS
    buttonBar = CreateFrame("Frame", "CorpUIChatButtons", UIParent)
    buttonBar:SetFrameStrata("MEDIUM")
    buttonBar:SetFrameLevel(20)
    buttonBar:SetSize(ICON, ICON)
    -- fond de la colonne : celui du panneau du chat (meme couche, meme opacite)
    column = CreateFrame("Frame", "CorpUIChatColumn", UIParent, "BackdropTemplate")
    column:SetFrameStrata("LOW")
    column:SetFrameLevel(1)
    column:SetWidth(COL_W)
    ns.UI.SetBackdrop(column, db.alpha)
    ns.UI.Shadow(column, 4)
    column:Hide()

    -- copie : la fenetre de chat choisie
    local copySlot = makeSlot()
    local copy = CreateFrame("Button", nil, copySlot)
    copy:SetAllPoints(copySlot)
    slotIcon(copySlot, "chat_copy")
    copy:SetScript("OnEnter", function(self)
        local t = ns.Tooltip(self, "ANCHOR_TOP")
        t:AddLine(L.CHAT_COPY_TITLE)
        t:AddLine(L.CHAT_COPY_HINT, 1, 1, 1)
        if db.urls then t:AddLine(L.CHAT_URL_TIP, 1, 1, 1) end
        t:Show()
    end)
    copy:SetScript("OnLeave", ns.HideTooltip)
    copy:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    copy:SetScript("OnClick", function(_, button)
        openCopy(SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME, button == "RightButton")
    end)
    slots[1] = { slot = copySlot, button = copy, own = true }

    -- journal de combat (option) : icone a gauche de la rangee. Le clic passe
    -- par un bouton securise qui "clique" l onglet de Blizzard (type
    -- "click") : leur propre code choisit la fenetre, sans taint. Bouton
    -- pose sur UIParent et ancre sur la case : la barre et ses cases restent
    -- des cadres ordinaires (deplaces et caches librement)
    local tab2 = _G.ChatFrame2Tab
    if type(tab2) == "table" and tab2.Click then
        local combatSlot = makeSlot()
        slotIcon(combatSlot, "chat_combat")
        local cb = CreateFrame("Button", "CorpUIChatCombatButton", UIParent, "SecureActionButtonTemplate")
        cb:SetFrameStrata("MEDIUM")
        cb:SetFrameLevel(25)
        cb:SetAllPoints(combatSlot)
        cb:RegisterForClicks("AnyUp", "AnyDown")
        cb:SetAttribute("type", "click")
        cb:SetAttribute("clickbutton", tab2)
        cb:SetScript("OnEnter", function(self)
            local t = ns.Tooltip(self, "ANCHOR_TOP")
            t:AddLine(L.CHAT_COMBAT_TIP)
            t:Show()
        end)
        cb:SetScript("OnLeave", ns.HideTooltip)
        table.insert(slots, { slot = combatSlot, button = cb, combat = true })
    end

    -- boutons de Blizzard : ranges dans nos cases (taille ramenee par echelle)
    for _, name in ipairs(BLIZZ_BUTTONS) do
        local b = _G[name]
        if type(b) == "table" and b.SetParent then
            local slot = makeSlot()
            pcall(b.SetParent, b, slot)
            local w = b:GetWidth()
            if w and w > 0 then b:SetScale((ICON - 2) / w) end
            b:ClearAllPoints()
            b:SetPoint("CENTER", slot, "CENTER", 0, 0)
            -- notre icone a la place du dessin de Blizzard (voix : on garde
            -- le leur, il change selon l etat micro / sourdine)
            if ICONS[name] then
                slotIcon(slot, ICONS[name])
                fadeButtonArt(b)
            end
            table.insert(slots, { slot = slot, button = b, name = name })
        end
    end
end

-- journal de combat en icone : option, fenetre ancree dans le dock
combatAsIcon = function()
    if not (db and db.combatIcon) then return false end
    local cf = _G.ChatFrame2
    local ok, docked = pcall(function() return cf and cf.isDocked end)
    return ok and docked and true or false
end

-- range les cases visibles de droite a gauche, dans le bandeau des onglets
local function layoutButtons()
    if not buttonBar then return end
    local host = DEFAULT_CHAT_FRAME and hostOf(DEFAULT_CHAT_FRAME)
    if not host then return end
    local C = ns.COLORS
    if column.host ~= host then
        column.host = host
        column:ClearAllPoints()
        column:SetPoint("TOPRIGHT", host, "TOPLEFT", -6 - COL_GAP, PANEL_TOP)
        column:SetPoint("BOTTOMRIGHT", host, "BOTTOMLEFT", -6 - COL_GAP, -6)
        buttonBar:ClearAllPoints()
        buttonBar:SetPoint("TOP", column, "TOP", 0, -4)
    end
    column:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], db.alpha)
    local order = {}
    for _, e in ipairs(slots) do order[#order + 1] = e end
    table.sort(order, function(a, b) return rankOf(a) < rankOf(b) end)
    local y = 0
    for _, e in ipairs(order) do
        local slot = e.slot
        local shown
        if e.own then shown = db.copy
        elseif e.combat then shown = combatAsIcon()
        else shown = e.button:IsShown() end
        -- bouton securise : visibilite changee hors combat seulement
        if e.combat and not InCombatLockdown() and e.button:IsShown() ~= shown then e.button:SetShown(shown) end
        if slot then
            slot:SetShown(shown)
            if shown then
                if e.y ~= y then
                    e.y = y
                    slot:ClearAllPoints()
                    slot:SetPoint("TOP", buttonBar, "TOP", 0, -y)
                end
                y = y + ICON + 4
                -- Blizzard re-ancre parfois ses boutons : on les remet en place
                if not e.own and not e.combat then
                    local _, rel = e.button:GetPoint(1)
                    if rel ~= slot then
                        e.button:ClearAllPoints()
                        e.button:SetPoint("CENTER", slot, "CENTER", 0, 0)
                    end
                    if e.button:GetParent() ~= slot then pcall(e.button.SetParent, e.button, slot) end
                end
                -- liseré dore au survol ; journal de combat affiche : accent
                local c = e.button:IsMouseOver() and C.gold or C.border
                if e.combat and not e.button:IsMouseOver() and SELECTED_CHAT_FRAME == _G.ChatFrame2 then c = C.violet end
                if slot.cuiBorder then slot.cuiBorder:SetColorTexture(c[1], c[2], c[3], 1) end
            end
        end
    end
    column:SetShown(y > 0)
    colOffset = y > 0 and (COL_W + COL_GAP) or 0
    -- bord droit du gestionnaire d onglets de Blizzard (ancre une fois par
    -- FCFDock_SetPrimary, jamais repris) : les icones ne sont plus dans le
    -- bandeau, les onglets ont toute sa largeur ; la largeur des onglets suit
    -- a la mise a jour suivante du dock (choix d un onglet...)
    local x = 0
    local dock = GENERAL_CHAT_DOCK
    local bg = dock and dock.primary and dock.primary.Background
    -- onglet fixe du journal cache : Blizzard calcule la largeur des onglets
    -- depuis son bord droit (environ 20 px perdus) ; le dock s etend d autant
    -- pour qu ils gardent la vraie place (recolles contre General ensuite)
    local inset = x
    local tab2 = _G.ChatFrame2Tab
    if dock and tab2 and combatAsIcon() and tab2:IsShown() and tab2:GetParent() == dock then
        inset = x - math.floor((tab2:GetWidth() or 0) + 1.5)
    end
    if bg and dock.SetPoint and dockInset ~= inset then
        dockInset = inset
        pcall(dock.SetPoint, dock, "BOTTOMRIGHT", bg, "TOPRIGHT", -(inset + 2), 0)
    end
end

-- Notre barre de defilement : fine, au bord droit des messages. Position
-- lue sur la fenetre (decalage depuis le bas / plage maximale), curseur
-- deplacable a la souris ; la molette reste celle du jeu.
local function buildScroll(cf, panel)
    local C = ns.COLORS
    local bar = CreateFrame("Frame", nil, panel)
    bar:SetPoint("TOPRIGHT", cf, "TOPRIGHT", 5, -2)
    bar:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 5, 22)
    bar:SetWidth(4)
    bar:SetFrameLevel(panel:GetFrameLevel() + 3)
    bar.track = bar:CreateTexture(nil, "BACKGROUND")
    bar.track:SetAllPoints()
    bar.track:SetColorTexture(0, 0, 0, 0.45)
    bar.thumb = CreateFrame("Frame", nil, bar)
    bar.thumb:SetWidth(4)
    bar.thumb:EnableMouse(true)
    bar.thumb.tex = bar.thumb:CreateTexture(nil, "ARTWORK")
    bar.thumb.tex:SetAllPoints()
    bar.thumb.tex:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.9)
    -- glisser le curseur
    bar.thumb:SetScript("OnMouseDown", function(self) self.drag = true end)
    bar.thumb:SetScript("OnMouseUp", function(self) self.drag = false end)
    bar.thumb:SetScript("OnUpdate", function(self)
        local over = self:IsMouseOver() or self.drag
        if over then self.tex:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
        else self.tex:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.9) end
        if not self.drag then return end
        if not IsMouseButtonDown("LeftButton") then self.drag = false return end
        local maxRange = cf:GetMaxScrollRange() or 0
        local top, bottom = bar:GetTop(), bar:GetBottom()
        if maxRange <= 0 or not top then return end
        local _, y = GetCursorPosition()
        y = y / bar:GetEffectiveScale()
        local h = self:GetHeight()
        -- haut de la piste = messages les plus anciens
        local frac = (y - bottom - h / 2) / math.max(1, (top - bottom - h))
        frac = math.max(0, math.min(1, frac))
        cf:SetScrollOffset(math.floor(frac * maxRange + 0.5))
    end)
    return bar
end

local function updateScroll(cf, bar)
    local ok, maxRange = pcall(cf.GetMaxScrollRange, cf)
    maxRange = ok and maxRange or 0
    if maxRange <= 0 then bar:Hide() return end
    bar:Show()
    local offset = cf:GetScrollOffset() or 0
    local trackH = bar:GetHeight()
    local _, fontH = cf:GetFont()
    local visible = math.max(1, math.floor(cf:GetHeight() / math.max(8, (fontH or 14) + 2)))
    local h = math.max(14, trackH * visible / (visible + maxRange))
    bar.thumb:SetHeight(h)
    -- decalage 0 = en bas ; le curseur monte quand on remonte l historique
    local y = (trackH - h) * (offset / maxRange)
    bar.thumb:ClearAllPoints()
    bar.thumb:SetPoint("BOTTOM", bar, "BOTTOM", 0, y)
end

local function skin(cf)
    local name = cf:GetName()
    if type(name) ~= "string" then return end
    local s = {}

    -- fond de Blizzard efface, notre panneau dessous
    fadeRegions(cf)
    fadeRegions(_G[name .. "Background"])
    local okB, bgKey = pcall(function() return cf.Background end)
    if okB and type(bgKey) == "table" then fadeRegions(bgKey) fade(bgKey) end
    local bf = _G[name .. "ButtonFrame"]
    if bf then
        fadeRegions(bf)
        local bfName = bf:GetName()
        if type(bfName) == "string" then fadeRegions(_G[bfName .. "Background"]) end
    end
    s.panel = buildPanel(cf)
    local okS, sb = pcall(function() return cf.ScrollBar end)
    if okS and type(sb) == "table" and sb.SetParent then
        -- rangee dans notre cadre cache : ni ses fondus ni ses apparitions ne
        -- se voient plus ; les ancrages qui s y referent restent valables
        pcall(sb.SetParent, sb, ns.hiddenParent)
    end
    -- bouton "revenir en bas" : case CorpUI, fleche doree (voir place())
    local okT, toBottom = pcall(function() return cf.ScrollToBottomButton end)
    if okT and type(toBottom) == "table" and toBottom.SetPoint then
        s.toBottom = toBottom
        local sq = CreateFrame("Frame", nil, toBottom)
        sq:SetPoint("TOPLEFT", -2, 2)
        sq:SetPoint("BOTTOMRIGHT", 2, -2)
        sq:SetFrameLevel(math.max(0, toBottom:GetFrameLevel() - 1))
        ns.UI.Skin(sq, 0.95)
        -- leur fleche eteinte (couleur), notre chevron (Core.lua)
        local hide = {}
        for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture" }) do
            local ok, t = pcall(toBottom[get], toBottom)
            if ok and t then hide[#hide + 1] = t end
        end
        ns.UI.ArrowChevron(toBottom, "DOWN", 12, hide)
    end
    -- journal de combat : le fond noir de sa barre de filtres
    if name == "ChatFrame2" then fade(_G.CombatLogQuickButtonFrame_CustomTexture) end

    local tab = _G[name .. "Tab"]
    if tab then
        s.tab = tab
        s.tabLook = styleTab(tab)
    end
    local eb = _G[name .. "EditBox"]
    if eb then
        s.eb = eb
        styleEdit(eb)
        local fd = { edges = {} }
        fd.fill = eb:CreateTexture(nil, "BACKGROUND", nil, -8)
        fd.fill:SetAllPoints(eb)
        ns.NoSnap(fd.fill)
        for i, pts in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
            local e = eb:CreateTexture(nil, "BACKGROUND", nil, -7)
            e:SetPoint(pts[1], eb, pts[1], 0, 0)
            e:SetPoint(pts[2], eb, pts[2], 0, 0)
            if i <= 2 then e:SetHeight(1) else e:SetWidth(1) end
            ns.NoSnap(e)
            fd.edges[i] = e
        end
        s.field = fd
    end
    s.scroll = buildScroll(cf, s.panel)
    skinned[cf] = s
    place(s, cf)
end

local function scan()
    if not db or not db.enabled then return end
    for i = 1, MAX_WINDOWS do
        local cf = _G["ChatFrame" .. i]
        if type(cf) == "table" and cf.GetName and not skinned[cf] then
            local ok, err = pcall(skin, cf)
            if not ok then
                skinned[cf] = {}
                db.errors = db.errors or {}
                db.errors["ChatFrame" .. i] = tostring(err)
            end
        end
    end
    if not buttonBar then
        local ok, err = pcall(buildButtonBar)
        if not ok then
            db.errors = db.errors or {}
            db.errors.buttons = tostring(err)
        end
    end
end

-- Fenetre de chat principale dans le coin en bas a gauche (option). Le mode
-- Edition de Blizzard la gere aussi : on ne force rien pendant qu il est
-- ouvert, pour pouvoir la placer a la main si l option est decochee.
local function placeCorner()
    if not db.corner then return end
    local cf = DEFAULT_CHAT_FRAME or ChatFrame1
    if not cf or (EditModeManagerFrame and EditModeManagerFrame:IsShown()) then return end
    -- le mode Edition retient la fenetre a l ecran avec une marge calculee sur
    -- son cadre de selection (ancienne colonne de boutons, ~35 px a gauche) :
    -- c est notre panneau qui borde le chat maintenant, on leve cette retenue
    if cf:IsClampedToScreen() then cf:SetClampedToScreen(false) end
    -- marges : celles de notre panneau (6 px) et de la zone de saisie ;
    -- lift : place laissee dessous (un bandeau d infos, par exemple)
    local x, y = 8 + colOffset, EDIT + 8 + (tonumber(db.lift) or 0)
    local point, rel, relPoint, px, py = cf:GetPoint(1)
    if point ~= "BOTTOMLEFT" or rel ~= UIParent or relPoint ~= "BOTTOMLEFT"
        or math.abs((px or 0) - x) > 0.5 or math.abs((py or 0) - y) > 0.5 or cf:GetNumPoints() > 1 then
        -- le mode Edition remplace SetPoint/ClearAllPoints de cette fenetre par
        -- ses versions (aimantation + notification) : on appelle les methodes
        -- d origine qu il garde de cote, sans executer son code
        local clear = cf.ClearAllPointsBase or cf.ClearAllPoints
        local setPoint = cf.SetPointBase or cf.SetPoint
        clear(cf)
        setPoint(cf, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
    end
end

-- Bandeau pose a la place de la zone de saisie (module Infos) : bord
-- gauche et largeur du panneau CorpUI de la fenetre principale, bas et
-- hauteur de la zone de saisie (sous les messages, voir place), en unites
-- d UIParent ; nil si ce panneau n existe pas (chat de CorpUI coupe)
function ns.ChatBox()
    local cf = DEFAULT_CHAT_FRAME or ChatFrame1
    local s = cf and skinned[cf]
    local p = s and s.panel
    if not p then return nil end
    local host = hostOf(cf)
    local k = p:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local kh = host:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local l, r, b = p:GetLeft(), p:GetRight(), host:GetBottom()
    if not l or not r or not b then return nil end
    -- colonne d icones a gauche comprise
    l = l - colOffset
    return { left = l * k, width = (r - l) * k, bottom = (b - 5 - EDIT) * kh, height = EDIT * kh }
end

-- remonte le chat de v (place sous lui), si le coin est tenu par CorpUI
function ns.ChatSetLift(v)
    if not db then return end
    db.lift = math.max(0, math.floor((tonumber(v) or 0) + 0.5))
    if not InCombatLockdown() then pcall(placeCorner) end
end

-- couleur du canal choisi dans la zone de saisie
local function channelColor(eb)
    local ok, r, g, b = pcall(function()
        local t = eb:GetAttribute("chatType")
        if t == "CHANNEL" then t = "CHANNEL" .. (eb:GetAttribute("channelTarget") or "") end
        local info = ChatTypeInfo and ChatTypeInfo[t]
        if info then return info.r, info.g, info.b end
    end)
    if ok and r then return r, g, b end
    return 1, 1, 1
end

-- Blizzard refait apparaitre fonds et onglets au survol : on recoupe ;
-- onglet actif souligne, saisie a la couleur du canal, tout reste en place
-- onglets du cadre defilant recolles contre General (onglet fixe du journal
-- cache) : verifie a chaque image (09/10 : au changement d onglet, Blizzard
-- les rancrait sur le journal et le releve de 0,2 s laissait voir un
-- sursaut vers la droite) ; vrai si l onglet du journal est cache
local function holdDock()
    local tab2 = _G.ChatFrame2Tab
    if not (combatAsIcon() and tab2 and tab2:IsShown()) then return false end
    local dock = GENERAL_CHAT_DOCK
    local sf = dock and dock.scrollFrame
    local t1 = _G.ChatFrame1Tab
    if sf and t1 and tab2:GetParent() == dock then
        local l, r = sf:GetLeft(), t1:GetRight()
        if l and r and math.abs(l - (r + 1)) > 0.5 then
            pcall(sf.SetPoint, sf, "LEFT", t1, "RIGHT", 1, 0)
        end
    end
    return true
end

local function refresh()
    local C = ns.COLORS
    local selected = SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
    -- onglet du journal de combat cache (icone a la place) ; c est un onglet
    -- fixe du dock, juste apres General : le cadre defilant des autres
    -- onglets est recolle contre General (Blizzard le rancre sur l onglet du
    -- journal a chaque mise a jour du dock : repose ici)
    local tab2 = _G.ChatFrame2Tab
    local hideCombat = holdDock()
    for cf, s in pairs(skinned) do
        if s.scroll and cf:IsVisible() then pcall(updateScroll, cf, s.scroll) end
        if s.panel then
            pcall(place, s, cf)
            s.panel:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], db.alpha)
            -- bord du haut : suit la couleur d accent du theme
            s.panel.accent:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.9)
        end
        local look = s.tabLook
        if look then
            -- un onglet affiche (meme estompe par Blizzard) garde un libelle net
            local shown = s.tab:IsShown() and s.tab:IsVisible()
            if hideCombat and s.tab == tab2 then shown = false end
            showLook(look, shown)
            if shown then
                local on = (cf == selected)
                local fs = tabText(s.tab)
                local text = fs and fs:GetText() or ""
                if look.label:GetText() ~= text then look.label:SetText(text) end
                local w = s.tab:GetWidth()
                if w and w > 12 and look.w ~= w then
                    look.w = w
                    look.label:SetWidth(w - 10)
                end
                tabGeom(look, s.tab, hostOf(cf))
                local alert = not on and tabAlert(s.tab)
                pulsing[look] = alert or nil
                look.glow:SetShown(alert)
                plateLook(look, on and "on" or (s.tab:IsMouseOver() and "over" or (alert and "alert" or "rest")))
                if on or alert or s.tab:IsMouseOver() then look.label:SetTextColor(1, 1, 1)
                else look.label:SetTextColor(C.text[1] * 0.75, C.text[2] * 0.75, C.text[3] * 0.75) end
            end
        end
        if s.eb and s.field and s.eb:IsVisible() then
            local r, g, b = channelColor(s.eb)
            local fd = s.field
            local focus = s.eb:HasFocus() and true or false
            if fd.r ~= r or fd.g ~= g or fd.b ~= b or fd.focus ~= focus then
                fd.r, fd.g, fd.b, fd.focus = r, g, b, focus
                local a = focus and 0.95 or 0.45
                for _, e in ipairs(fd.edges) do e:SetColorTexture(r, g, b, a) end
                fd.fill:SetColorTexture(0.035 + r * 0.03, 0.038 + g * 0.03, 0.047 + b * 0.03, 0.94)
            end
        end
    end
    local okC, errC = pcall(placeCorner)
    if not okC then db.cornerError = tostring(errC) end
    pcall(layoutButtons)
end

---------------------------------------------------------------------------
-- Historique des messages envoyes
--   fleches haut / bas sans Alt (SetAltArrowKeyMode : propriete de la zone
--   de saisie, aucune fonction de Blizzard remplacee) ;
--   historique garde d une session a l autre, par personnage : la derniere
--   ligne tapee est notee (OnTextChanged) et rangee a l envoi (OnEnterPressed,
--   apres le code du jeu), au format de l historique du jeu ("/g texte").
---------------------------------------------------------------------------

local HISTORY_MAX = 50
local historyBoxes = {}

local function historyStore()
    local key = ns.CharKey()
    db.history = db.history or {}
    db.history[key] = db.history[key] or {}
    return db.history[key]
end

-- meme forme que ChatFrameEditBoxMixin:AddHistory : la commande du canal
-- puis le texte (les commandes "/..." sont gardees telles quelles)
local function historyLine(eb, text)
    if text:sub(1, 1) == "/" then return text end
    local t = eb:GetAttribute("chatType") or "SAY"
    local line = _G["SLASH_" .. t .. "1"] or ""
    if t == "WHISPER" then
        line = line .. " " .. (eb:GetAttribute("tellTarget") or "")
    elseif t == "CHANNEL" then
        line = "/" .. (eb:GetAttribute("channelTarget") or "")
    end
    return line ~= "" and (line .. " " .. text) or text
end

-- Fleches seules : la zone de saisie du jeu ignore les fleches (attribut
-- ignoreArrows, sans fonction pour le changer) et ne les passe pas non plus
-- aux raccourcis (verifie en jeu). Elle recoit quand meme l appui de touche
-- (OnKeyDown) : haut / bas y parcourent notre historique.
local active, cursor, draft

local function browse(d)
    local eb = active
    if not eb then return end
    local h = historyStore()
    if cursor == nil then
        cursor = #h + 1
        local ok, t = pcall(eb.GetText, eb)
        draft = ok and t or ""
    end
    cursor = math.max(1, math.min(#h + 1, cursor + d))
    local text = cursor > #h and draft or h[cursor]
    eb:SetText(text or "")
    pcall(eb.SetCursorPosition, eb, #(text or ""))
end

-- releve pour /corp chat diag
local diag = { gained = 0, lost = 0, keys = 0, arrows = 0 }

local function grabArrows(eb)
    diag.gained = diag.gained + 1
    active, cursor, draft = eb, nil, nil
end

local function releaseArrows()
    diag.lost = diag.lost + 1
    active, cursor, draft = nil, nil, nil
end

local function onKey(eb, key)
    diag.keys = diag.keys + 1
    if not db.arrows or IsAltKeyDown() then return end   -- Alt + fleche : historique du jeu
    if key == "UP" or key == "DOWN" then
        diag.arrows = diag.arrows + 1
        active = eb
        browse(key == "UP" and -1 or 1)
    end
end

local function hookHistory(eb)
    if historyBoxes[eb] then return end
    local state = {}
    historyBoxes[eb] = state
    pcall(eb.SetAltArrowKeyMode, eb, not db.arrows)
    eb:HookScript("OnEditFocusGained", function(self) grabArrows(self) end)
    eb:HookScript("OnEditFocusLost", function() releaseArrows() end)
    eb:HookScript("OnKeyDown", onKey)
    if db.keepHistory then
        for _, line in ipairs(historyStore()) do pcall(eb.AddHistoryLine, eb, line) end
    end
    eb:HookScript("OnTextChanged", function(self)
        local ok, t = pcall(self.GetText, self)
        if ok and type(t) == "string" and t ~= "" then state.last = historyLine(self, t) end
    end)
    eb:HookScript("OnEscapePressed", function() state.last = nil end)
    eb:HookScript("OnEnterPressed", function(self)
        local line = state.last
        state.last = nil
        if not line then return end
        local h = historyStore()
        if h[#h] ~= line then table.insert(h, line) end
        while #h > HISTORY_MAX do table.remove(h, 1) end
        cursor, draft = nil, nil
        -- les autres fenetres de saisie le retrouvent aussi
        for other in pairs(historyBoxes) do
            if other ~= self then pcall(other.AddHistoryLine, other, line) end
        end
    end)
end

local function scanHistory()
    for i = 1, MAX_WINDOWS do
        local eb = _G["ChatFrame" .. i .. "EditBox"]
        if type(eb) == "table" and eb.HookScript and not historyBoxes[eb] then pcall(hookHistory, eb) end
    end
end

local function applyArrows()
    for eb in pairs(historyBoxes) do pcall(eb.SetAltArrowKeyMode, eb, not db.arrows) end
end

---------------------------------------------------------------------------
-- Reglages du jeu : heure devant les messages, noms aux couleurs de classe
--   Ce sont des CVar que le code de Blizzard lit lui-meme a chaque message
--   (ChatFrameUtil.GetTimestampFormat / ShouldColorChatByClass) : aucune
--   fonction remplacee, aucun message touche. Rien n est change au
--   chargement, seulement quand on choisit dans le panneau.
---------------------------------------------------------------------------

local function getCVar(name)
    if not GetCVar then return nil end
    local ok, v = pcall(GetCVar, name)
    if ok and not issecret(v) and type(v) == "string" then return v end
end

local function setCVar(name, value)
    if not SetCVar then return end
    pcall(SetCVar, name, value)
end

-- Zone de saisie seulement pendant la frappe : style "classique" du jeu
-- (CVar chatStyle, Options > Social) ; "im" : toujours affichee
local STYLE_CVAR = "chatStyle"
local function editOnTyping()
    local ok, v = pcall(GetCVar, STYLE_CVAR)
    return ok and v == "classic"
end
function ns.ChatEditOnTyping(on)
    if on == nil then return editOnTyping() end
    setCVar(STYLE_CVAR, on and "classic" or "im")
end

-- une zone de saisie est ouverte (un bandeau pose a sa place s efface) :
-- en style classique, des qu elle est affichee ; sinon pendant la frappe
function ns.ChatEditShown()
    local classic = editOnTyping()
    -- zone de saisie visible, quelle que soit la fenetre choisie (09/10 : un
    -- autre onglet que General cache ChatFrame1, pas sa zone de saisie)
    for _, s in pairs(skinned) do
        local eb = s.eb
        if eb and eb:IsVisible() then
            if classic then return true end
            local ok, focus = pcall(eb.HasFocus, eb)
            if ok and focus then return true end
        end
    end
    return false
end

-- Heure : la CVar showTimestamps contient le format de date ("none" = sans).
-- Le jeu accepte tout format de date ; les siens (Options > Social) sont
-- repris tels quels pour que sa liste les reconnaisse.
local TS_CVAR = "showTimestamps"
local TS_EXAMPLE = { year = 2010, month = 12, day = 15, hour = 14, min = 5, sec = 33 }
local tsValues, tsNames = {}, {}

local function gameFormat(v, fallback)
    return type(v) == "string" and v ~= "" and v or fallback
end

local function tsLabel(fmt)
    if fmt == "none" then return L.CHAT_TS_NONE end
    local fn = (TimeUtil and TimeUtil.BetterDate) or date
    local ok, s = pcall(fn, fmt, time(TS_EXAMPLE))
    if ok and type(s) == "string" then return (s:gsub("%s+$", "")) end
    return fmt
end

-- liste des choix (et le format actuel du jeu s il n y figure pas)
local function tsRefresh()
    for k in pairs(tsValues) do tsValues[k] = nil end
    for k in pairs(tsNames) do tsNames[k] = nil end
    local list = {
        "none",
        gameFormat(TIMESTAMP_FORMAT_HHMM_24HR, "%H:%M "),
        gameFormat(TIMESTAMP_FORMAT_HHMMSS_24HR, "%H:%M:%S "),
        "[%H:%M] ",
        "[%H:%M:%S] ",
        gameFormat(TIMESTAMP_FORMAT_HHMM_AMPM, "%I:%M %p "),
        gameFormat(TIMESTAMP_FORMAT_HHMMSS_AMPM, "%I:%M:%S %p "),
    }
    local cur = getCVar(TS_CVAR)
    if cur and cur ~= "" then table.insert(list, cur) end
    for _, v in ipairs(list) do
        if not tsNames[v] then
            table.insert(tsValues, v)
            tsNames[v] = tsLabel(v)
        end
    end
end

local function tsGet()
    tsRefresh()
    local cur = getCVar(TS_CVAR)
    return (cur and cur ~= "") and cur or "none"
end

-- Couleurs de classe : chatClassColorOverride vaut "0" pour colorer tous
-- les canaux, "1" pour aucun, autre chose pour suivre le reglage de chaque
-- canal (clic droit sur un onglet > Parametres). Decoche : on rend la main
-- aux canaux (valeur par defaut du jeu, ou "2" si celle-ci force deja).
local CC_CVAR = "chatClassColorOverride"

local function ccGet() return getCVar(CC_CVAR) == "0" end

local function ccSet(v)
    if v then setCVar(CC_CVAR, "0") return end
    local def
    if C_CVar and C_CVar.GetCVarDefault then
        local ok, d = pcall(C_CVar.GetCVarDefault, CC_CVAR)
        if ok and not issecret(d) and type(d) == "string" then def = d end
    end
    if not def or def == "0" or def == "" then def = "2" end
    setCVar(CC_CVAR, def)
end

---------------------------------------------------------------------------
-- Onglets par defaut (09/10) : General (canaux generaux, commerce, ville),
-- Journal de combat et Voix (fenetres 2 et 3 de Blizzard, intouchees),
-- GGR (guilde, groupe, raid, officiers),
-- Loot&Trade (butin, argent, artisanat), Whisper (messages prives) ; les
-- autres fenetres sont fermees. Seulement par les fonctions du moteur qui
-- enregistrent la configuration des fenetres (AddChatWindowMessages,
-- SetChatWindowName...), jamais par le code de Blizzard (FCF_*, AddMessage-
-- Group des fenetres) : rien ne s execute chez eux, pas de taint. Le jeu
-- relit cette configuration au chargement suivant : le bouton du panneau
-- recharge l interface ; pour un nouveau personnage, au prochain /reload.
---------------------------------------------------------------------------

local combatName
local SETUP = {
    { id = 1, dock = 1, name = function() return GENERAL end, keepChannels = true, groups = {
        "SAY", "EMOTE", "YELL", "SYSTEM", "ERRORS", "CHANNEL", "MONSTER_SAY", "MONSTER_EMOTE", "MONSTER_YELL",
        "MONSTER_WHISPER", "MONSTER_BOSS_EMOTE", "MONSTER_BOSS_WHISPER", "ACHIEVEMENT", "BG_HORDE", "BG_ALLIANCE",
        "BG_NEUTRAL", "COMBAT_XP_GAIN", "COMBAT_HONOR_GAIN", "COMBAT_FACTION_CHANGE", "SKILL", "PET_INFO",
        "TARGETICONS", "BN_INLINE_TOAST_ALERT", "PING" } },
    { id = 4, dock = 2, name = "GGR", groups = {
        "GUILD", "OFFICER", "GUILD_ACHIEVEMENT", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING",
        "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER" } },
    { id = 5, dock = 3, name = "Loot&Trade", groups = { "LOOT", "MONEY", "CURRENCY", "TRADESKILLS", "OPENING" } },
    { id = 6, dock = 4, name = "Whisper", groups = { "WHISPER", "BN_WHISPER", "AFK", "DND", "IGNORED" } },
}
-- fenetres propres a Blizzard (IsBuiltinChatWindow) : journal de combat,
-- transcription vocale
local BUILTIN = { [2] = true, [3] = true }
local COMBAT_LOG_ID = 2

local function packCall(fn, id) return { fn(id) } end

-- liste rendue par le moteur (groupes, ou paires nom / zone des canaux)
local function engineList(fn, id)
    if type(fn) ~= "function" then return {} end
    local ok, list = pcall(packCall, fn, id)
    return ok and list or {}
end

local function engine(fn, ...)
    if type(fn) == "function" then pcall(fn, ...) end
end

-- vrai si la configuration est posee (fonctions du moteur presentes)
function ns.ChatSetupWindows()
    if type(SetChatWindowName) ~= "function" or type(AddChatWindowMessages) ~= "function"
        or type(RemoveChatWindowMessages) ~= "function" then return false end
    local CC = Constants and Constants.ChatFrameConstants
    local maxW = (CC and CC.MaxChatWindows) or NUM_CHAT_WINDOWS or 10
    -- police, couleur et opacite de la fenetre generale reprises
    local okI, _, size, r, g, b, a = pcall(GetChatWindowInfo, 1)
    local wanted = {}
    for _, w in ipairs(SETUP) do wanted[w.id] = w end
    for id = 1, maxW do
        if not BUILTIN[id] then
            local w = wanted[id]
            for _, grp in ipairs(engineList(GetChatWindowMessages, id)) do
                if type(grp) == "string" and not issecret(grp) then engine(RemoveChatWindowMessages, id, grp) end
            end
            if not (w and w.keepChannels) then
                local ch = engineList(GetChatWindowChannels, id)
                for i = 1, #ch, 2 do
                    if type(ch[i]) == "string" and not issecret(ch[i]) then engine(RemoveChatWindowChannel, id, ch[i]) end
                end
            end
            if w then
                for _, grp in ipairs(w.groups) do engine(AddChatWindowMessages, id, grp) end
                local name = w.name
                if type(name) == "function" then name = name() end
                engine(SetChatWindowName, id, name)
                engine(SetChatWindowShown, id, true)
                -- place dans le dock (2 : journal de combat)
                engine(SetChatWindowDocked, id, w.dock)
                if id ~= 1 and okI then
                    if type(size) == "number" and not issecret(size) and size > 0 then engine(SetChatWindowSize, id, size) end
                    if type(r) == "number" and not issecret(r) then engine(SetChatWindowColor, id, r, g, b) end
                    if type(a) == "number" and not issecret(a) then engine(SetChatWindowAlpha, id, a) end
                end
            else
                engine(SetChatWindowName, id, "")
                engine(SetChatWindowShown, id, false)
                engine(SetChatWindowDocked, id, nil)
            end
        end
    end
    return true
end

-- journal de combat ancre dans le dock mais pas en dernier : passe en
-- dernier (configuration du jeu, effet au prochain chargement de l interface)
-- Dans ce client, le journal de combat est un onglet FIXE du dock, comme
-- General (vu en jeu le 09/10 : parent GeneralDockManager) : toujours juste
-- apres General, quel que soit l ordre enregistre. En icone, son onglet est
-- cache et les onglets suivants sont recolles contre General (refresh) ;
-- son nom passe a une espace : un onglet d une vingtaine de pixels, que
-- Blizzard deduit de la place des autres. Le nom du jeu revient si l option
-- est decochee (seulement s il porte encore notre espace). Effet au
-- prochain chargement de l interface.
local COMBAT_ICON_NAME = " "
combatName = function()
    if type(GetChatWindowInfo) ~= "function" or type(SetChatWindowName) ~= "function" then return end
    local ok, name = pcall(GetChatWindowInfo, COMBAT_LOG_ID)
    if not ok or type(name) ~= "string" or issecret(name) then return end
    if db and db.combatIcon then
        if name ~= COMBAT_ICON_NAME then engine(SetChatWindowName, COMBAT_LOG_ID, COMBAT_ICON_NAME) end
    elseif name == COMBAT_ICON_NAME and type(COMBAT_LOG) == "string" and COMBAT_LOG ~= "" then
        engine(SetChatWindowName, COMBAT_LOG_ID, COMBAT_LOG)
    end
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------

local win

local function buildWindow()
    win = ns.UI.Window("CorpUIChatOptions", ns.TITLE .. " - " .. L.MOD_CHAT, nil, 440, 412)
    -- chaque reglage applique lui-meme son effet : pas d onChange commun
    local form = ns.UI.Form(win, -34)
    form:Check(L.CHAT_OPT_ENABLE, function() return db.enabled end, function(v)
        db.enabled = v
        if v then scan() end
    end)
    form:Check(L.CHAT_OPT_COPY, function() return db.copy end, function(v) db.copy = v end)
    form:Check(L.CHAT_OPT_URLS, function() return db.urls end, function(v) db.urls = v end)
    form:Check(L.CHAT_OPT_CORNER, function() return db.corner end, function(v) db.corner = v end)
    form:Check(L.CHAT_OPT_ARROWS, function() return db.arrows end, function(v) db.arrows = v applyArrows() end)
    form:Check(L.CHAT_OPT_HISTORY, function() return db.keepHistory end, function(v) db.keepHistory = v end)
    -- reglage du jeu (CVar chatStyle) : saisie cachee hors frappe
    form:Check(L.CHAT_OPT_EDIT_TYPING, editOnTyping, function(v) ns.ChatEditOnTyping(v) end)
    -- reglage du jeu (CVar), change seulement au clic
    form:Check(L.CHAT_OPT_CLASSCOLOR, ccGet, ccSet)
    -- journal de combat en icone (nom de l onglet au prochain chargement)
    form:Check(L.CHAT_OPT_COMBAT_ICON, function() return db.combatIcon end, function(v)
        db.combatIcon = v
        combatName()
    end)
    form:Gap(4)
    -- opacite du fond : enregistree de 0 a 1, reglee en % ; heure : CVar du jeu
    form:Columns(2)
    form:Number(L.CHAT_ALPHA, function() return math.floor((db.alpha or 0) * 100 + 0.5) end, function(v)
        db.alpha = math.max(0, math.min(1, v / 100))
        refresh()
    end, 0, 100, 5)
    tsRefresh()
    form:Cycle(L.CHAT_TIMESTAMP, tsValues, tsNames, tsGet, function(v) setCVar(TS_CVAR, v) end)
    -- place laissee sous le chat (coin en bas a gauche)
    form:Number(L.CHAT_LIFT, function() return db.lift or 0 end, function(v) ns.ChatSetLift(v) end, 0, 200, 1)
    form:EndColumns()
    -- onglets par defaut : deux clics (le premier demande confirmation), puis
    -- l interface se recharge (le jeu relit la configuration des fenetres).
    -- Bouton securise : ancre sur la fenetre seulement
    local setup
    setup = ns.UI.ReloadButton(win, L.CHAT_SETUP, 150, function()
        if not setup.armed then
            setup.armed = true
            setup:SetText(L.CHAT_SETUP_SURE)
            C_Timer.After(3, function()
                if setup.armed then setup.armed = false setup:SetText(L.CHAT_SETUP) end
            end)
            return false
        end
        setup.armed = false
        setup:SetText(L.CHAT_SETUP)
        if not ns.ChatSetupWindows() then return false end
    end)
    setup:SetPoint("TOPLEFT", win, "TOPLEFT", 8, form.y - 8)
    local setupHint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    setupHint:SetPoint("TOPLEFT", win, "TOPLEFT", 166, form.y - 6)
    setupHint:SetWidth(262)
    setupHint:SetJustifyH("LEFT")
    setupHint:SetText(L.CHAT_SETUP_HINT)
    form.y = form.y - 62
    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", win, "TOPLEFT", 8, form.y - 6)
    hint:SetWidth(420)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.CHAT_HINT)
    win:HookScript("OnShow", function() form:Refresh() end)
end

local function toggle()
    if not win then buildWindow() end
    ns.ShowPanel(win)
end

---------------------------------------------------------------------------

local newCharDone = false
local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if ns.ModuleOff("chat", ev) then return end
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        root.chat = root.chat or {}
        db = root.chat
        for k, v in pairs({ enabled = true, copy = true, alpha = 0.6, corner = true, arrows = true, keepHistory = true, urls = true, lift = 0,
                            combatIcon = true }) do
            if db[k] == nil then db[k] = v end
        end
        db.errors = nil
        -- historique non garde : on repart d une liste vide (elle sert quand
        -- meme pendant la session, pour les fleches)
        if not db.keepHistory and db.history then db.history[ns.CharKey()] = nil end
        C_Timer.After(4, combatName)
        -- personnage jamais vu par CorpUI (Profils.lua) : onglets par defaut,
        -- une fois la configuration du jeu chargee ; visibles au prochain
        -- chargement de l interface
        if ns.NEW_CHAR and db.enabled and not newCharDone then
            newCharDone = true
            C_Timer.After(4, function()
                if ns.ChatSetupWindows() then ns.Say(L.CHAT_SETUP_DONE) end
            end)
        end
    end
    if db then scanHistory() end
    scan()
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "UPDATE_CHAT_WINDOWS", "UPDATE_FLOATING_CHAT_WINDOWS" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local since, tick = 0, 0
local lastSelected
ev:SetScript("OnUpdate", function(_, dt)
    if not db or not db.enabled then return end
    -- a chaque image : ancrage des onglets ; changement d onglet : releve
    -- complet tout de suite (plaques, trait du bas) plutot qu au suivant
    pcall(holdDock)
    pulse()
    since = since + dt
    local sel = SELECTED_CHAT_FRAME
    if since < 0.2 and sel == lastSelected then return end
    lastSelected = sel
    since = 0
    refresh()
    -- nouvelles fenetres (chuchotements detaches) : toutes les 2 s
    tick = tick + 1
    if tick >= 10 then tick = 0 scan() scanHistory() end
end)

---------------------------------------------------------------------------
-- Diagnostic des alertes d onglets (/corp chat alerte) : apres le prochain
-- message de guilde, de groupe, de raid ou chuchote, releve l etat de chaque
-- onglet (champs a vrai ou parlant d alerte, morceaux visibles) dans
-- db.alertDiag, lu dans la sauvegarde apres un rechargement. Lecture seule :
-- les arguments des messages ne sont jamais lus.
---------------------------------------------------------------------------

local function fieldsOf(t)
    local flags, named = {}, {}
    local ok = pcall(function()
        for k, v in pairs(t) do
            if type(k) == "string" and not issecret(k) and not issecret(v) then
                local lk = k:lower()
                if v == true then table.insert(flags, k) end
                if lk:find("alert") or lk:find("flash") or lk:find("glow") then
                    local tv = type(v)
                    if tv == "table" and v.GetObjectType then
                        local okS, shown = pcall(v.IsShown, v)
                        local okA, a = pcall(v.GetAlpha, v)
                        table.insert(named, k .. "=" .. tostring(okS and shown) .. "/" .. tostring(okA and a))
                    else
                        table.insert(named, k .. "=" .. tostring(v))
                    end
                end
            end
        end
    end)
    if not ok then table.insert(named, "(lecture interrompue)") end
    table.sort(flags)
    table.sort(named)
    return table.concat(flags, ","), table.concat(named, " ")
end

local function tabState(i)
    local cf, tab = _G["ChatFrame" .. i], _G["ChatFrame" .. i .. "Tab"]
    if not cf or not tab then return nil end
    local okN, name = pcall(GetChatWindowInfo, i)
    local r = { i = i, name = okN and not issecret(name) and name or "?",
                frameShown = cf:IsShown() and true or false, tabShown = tab:IsShown() and true or false }
    r.tabTrue, r.tabNamed = fieldsOf(tab)
    r.cfTrue, r.cfNamed = fieldsOf(cf)
    local g = _G["ChatFrame" .. i .. "TabGlow"]
    if g then
        local okS, shown = pcall(g.IsShown, g)
        r.globalGlow = tostring(okS and shown)
    end
    return r
end

local alertProbe
local function armAlertProbe()
    if not alertProbe then
        alertProbe = CreateFrame("Frame")
        alertProbe:SetScript("OnEvent", function(_, event)
            alertProbe:UnregisterAllEvents()
            -- apres le traitement du message par le jeu
            C_Timer.After(0.5, function()
                local sel = SELECTED_CHAT_FRAME
                local out = { event = event, at = date("%H:%M:%S"),
                              selected = sel and sel.GetName and sel:GetName() or "?", tabs = {} }
                for i = 1, MAX_WINDOWS do
                    local r = tabState(i)
                    if r then table.insert(out.tabs, r) end
                end
                db.alertDiag = out
                local n = 0
                for _, r in ipairs(out.tabs) do if r.tabNamed:find("alerting=true") then n = n + 1 end end
                ns.Say(string.format("chat alerte : releve fait (%s, onglets en alerte : %d). Recharge pour l enregistrer.", event, n))
            end)
        end)
    end
    for _, e in ipairs({ "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
                         "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER" }) do
        pcall(alertProbe.RegisterEvent, alertProbe, e)
    end
    ns.Say("chat alerte : en attente du prochain message de guilde, groupe, raid ou chuchote (garde un autre onglet ouvert).")
end

ns.RegisterModule({
    command = "chat",
    panelName = "CorpUIChatOptions",
    icon = "Interface\\Icons\\INV_Letter_15",
    title = function() return L.MOD_CHAT end,
    desc = function() return L.CHAT_DESC end,
    Slash = function(input)
        local cmd = strlower(strtrim(input or ""))
        if cmd == "url" then
            -- derniere adresse web vue, prete a copier
            local cf = SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
            if cf then openCopy(cf, true) end
        elseif cmd == "alerte" or cmd == "alert" then
            armAlertProbe()
        elseif cmd == "diag" then
            -- historique et fleches : etat utile pour comprendre un souci
            local eb = _G.ChatFrame1EditBox
            local okA, alt = pcall(eb.GetAltArrowKeyMode, eb)
            ns.Say(string.format("chat diag : focus +%d / -%d, touches %d, fleches %d, actif %s, alt %s, histo %d",
                diag.gained, diag.lost, diag.keys, diag.arrows, active and active:GetName() or "-",
                tostring(okA and alt), #historyStore()))
        else
            toggle()
        end
    end,
    Open = toggle,
})
