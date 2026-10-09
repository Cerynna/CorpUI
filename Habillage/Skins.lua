--[[--------------------------------------------------------------------------
    CorpUI - module Habillage
    Donne le style CorpUI aux fenetres de Blizzard (personnage, sorts,
    carte, marchand, courrier, menu du jeu, popups...). La liste des
    fenetres, rangee par groupe, est dans Habillage/Fenetres.lua.

    Sur ce client, le moindre crochet sur le code de Blizzard peut casser
    l interface (valeurs secretes) : on ne touche donc qu a l apparence.
      - les textures decoratives de la fenetre (cadre, fond, coins,
        portrait) passent a alpha 0 (jamais detruites) ;
      - notre fond obsidienne, son liseré, le bandeau d accent et l ombre
        sont de NOUVELLES textures posees au plus bas de la fenetre
        (calque BACKGROUND, sous-niveaux -8 a -5) : aucun cadre ajoute,
        aucune taille, position, script ou attribut de Blizzard modifie,
        aucun champ ecrit dans les tables de Blizzard ;
      - boutons rouges et onglets : leurs textures a alpha 0 et une plaque
        plate dessous (memes regles) ; la croix devient une croix plate ;
      - menus a fleche, cases a cocher et onglets du haut : Communs.lua
        (ns.SkinCommon), jamais ici.
    Les fenetres protegees ne recoivent que le fond (pas de recherche de
    boutons dedans). Rien n est fait en combat. Un releve toutes les
    secondes repere les fenetres chargees a la demande (en plus de
    ADDON_LOADED), un autre colore survol et onglet choisi.
    Pour retrouver l apparence d origine : decocher puis recharger.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

-- sous-cadres purement decoratifs des modeles de fenetre de Blizzard
local DECOR = { "NineSlice", "PortraitContainer", "TitleContainer", "Inset", "InsetLeft", "InsetRight", "Background", "Border",
                "TopTileStreaks", "Bg", "BG" }

local db
local windows = {}    -- fenetre de Blizzard -> { spec, prot } (table a nous)
local glyphs = {}     -- croix de fermeture -> notre "x"
local buttons = {}    -- bouton de Blizzard -> notre plaque
local tabs = {}       -- onglet de Blizzard -> notre plaque
local lastWalk = {}

---------------------------------------------------------------------------
-- Outils
---------------------------------------------------------------------------

local function objType(o)
    if type(o) ~= "table" or not o.GetObjectType then return nil end
    local ok, t = pcall(o.GetObjectType, o)
    if ok then return t end
end

local function fade(obj)
    if type(obj) == "table" and obj.SetAlpha then pcall(obj.SetAlpha, obj, 0) end
end

-- texture posee par un habillage en profondeur (Metiers.lua) : a garder
local function owned(r)
    if not ns.SkinOwned then return false end
    local ok, v = pcall(ns.SkinOwned, r)
    return ok and v == true
end

-- textures posees directement sur un cadre (pas celles de ses enfants) ;
-- spare : textures a garder (ex. la carte des trajets, dessinee dans InsetBg)
local function fadeRegions(f, spare)
    if type(f) ~= "table" or not f.GetRegions then return end
    local ok, regions = pcall(function() return { f:GetRegions() } end)
    if not ok then return end
    for _, r in ipairs(regions) do
        if objType(r) == "Texture" and not owned(r) and not (spare and spare[r]) then fade(r) end
    end
end

-- texture : alpha 0 ; cadre : ses propres textures a alpha 0
local function fadeObj(o)
    local t = objType(o)
    if t == "Texture" then fade(o)
    elseif t then fadeRegions(o) end
end

local function decorChild(f, key)
    local ok, c = pcall(function() return f[key] end)
    if ok and type(c) == "table" then return c end
end

-- "A.B.C" depuis la fenetre, ou "G:Globale.B.C" depuis une globale
local function resolve(f, path)
    if type(path) ~= "string" then return nil end
    local obj = f
    if path:sub(1, 2) == "G:" then
        local first, rest = path:sub(3):match("^([^%.]+)%.?(.*)$")
        if not first then return nil end
        obj, path = _G[first], rest
    end
    for key in path:gmatch("[^%.]+") do
        if type(obj) ~= "table" then return nil end
        obj = decorChild(obj, key)
    end
    if type(obj) == "table" then return obj end
end

local function setOf(list)
    local s = {}
    for _, v in ipairs(list or {}) do s[v] = true end
    return s
end

-- quatre filets de 1 px (liseré), retrait l/t/r/b depuis les bords
local function edges(f, l, t, r, b, sub)
    local list = {}
    local function line()
        local x = f:CreateTexture(nil, "BACKGROUND", nil, sub)
        table.insert(list, x)
        return x
    end
    local top = line()
    top:SetPoint("TOPLEFT", l, -t)
    top:SetPoint("TOPRIGHT", -r, -t)
    top:SetHeight(1)
    local bottom = line()
    bottom:SetPoint("BOTTOMLEFT", l, b)
    bottom:SetPoint("BOTTOMRIGHT", -r, b)
    bottom:SetHeight(1)
    local left = line()
    left:SetPoint("TOPLEFT", l, -t)
    left:SetPoint("BOTTOMLEFT", l, b)
    left:SetWidth(1)
    local right = line()
    right:SetPoint("TOPRIGHT", -r, -t)
    right:SetPoint("BOTTOMRIGHT", -r, b)
    right:SetWidth(1)
    return list
end

local function paint(list, c, a)
    for _, x in ipairs(list) do x:SetColorTexture(c[1], c[2], c[3], a or 1) end
end

---------------------------------------------------------------------------
-- Fond des fenetres
---------------------------------------------------------------------------

local function dress(f, edgeHost, inset, noHead)
    local C = ns.COLORS
    local l, t, r, b = inset[1] or 0, inset[2] or 0, inset[3] or 0, inset[4] or 0
    -- fond obsidienne
    local fill = f:CreateTexture(nil, "BACKGROUND", nil, -7)
    fill:SetPoint("TOPLEFT", l, -t)
    fill:SetPoint("BOTTOMRIGHT", -r, b)
    fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.96)
    -- ombre douce, hors du cadre : sous la fenetre elle-meme, jamais sur
    -- edgeHost (vu en jeu : sur le BorderFrame de la carte, au-dessus du
    -- canevas, ces 5 rectangles pleins assombrissaient toute la carte)
    for i = 1, 5 do
        local s = f:CreateTexture(nil, "BACKGROUND", nil, -8)
        s:SetPoint("TOPLEFT", l - i, -t + i)
        s:SetPoint("BOTTOMRIGHT", -r + i, b - i)
        s:SetColorTexture(0, 0, 0, 0.16)
    end
    -- liseré du theme
    paint(edges(edgeHost, l, t, r, b, -5), C.border, 1)
    if noHead then return end
    -- bandeau du haut : un degrade de l accent, comme la fenetre CorpUI
    local head = edgeHost:CreateTexture(nil, "BACKGROUND", nil, -6)
    head:SetPoint("TOPLEFT", l + 1, -t - 1)
    head:SetPoint("TOPRIGHT", -r - 1, -t - 1)
    head:SetHeight(22)
    ns.UI.Gradient(head, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.35, C.violet[1], C.violet[2], C.violet[3], 0)
    local gold = edgeHost:CreateTexture(nil, "BACKGROUND", nil, -6)
    gold:SetPoint("TOPLEFT", head, "BOTTOMLEFT")
    gold:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT")
    gold:SetHeight(1)
    ns.UI.Gradient(gold, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.8, C.gold[1], C.gold[2], C.gold[3], 0)
end

local function goldTitle(f, spec)
    local name = f:GetName()
    if type(name) ~= "string" then name = "" end
    local list = { resolve(f, spec.title), resolve(f, "TitleContainer.TitleText"), decorChild(f, "TitleText"),
                   _G[name .. "TitleText"], resolve(f, "Header.Text") }
    local C = ns.COLORS
    for i = 1, 5 do
        local fs = list[i]
        if objType(fs) == "FontString" then
            pcall(fs.SetTextColor, fs, C.gold[1], C.gold[2], C.gold[3])
            return
        end
    end
end

local function skinClose(f, spec)
    local name = f:GetName()
    if type(name) ~= "string" then name = "" end
    local b = resolve(f, spec.close) or decorChild(f, "CloseButton") or _G[name .. "CloseButton"]
    if objType(b) ~= "Button" or glyphs[b] or not b.GetNormalTexture then return end
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        local ok, t = pcall(b[get], b)
        if ok then fade(t) end
    end
    local x = b:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(x, 15)
    x:SetPoint("CENTER", 0, 1)
    x:SetText("×")
    local C = ns.COLORS
    x:SetTextColor(C.text[1], C.text[2], C.text[3])
    glyphs[b] = x
end

---------------------------------------------------------------------------
-- Boutons et onglets a l interieur des fenetres
---------------------------------------------------------------------------

-- plaque plate sous un bouton : textures a nous, au fond du bouton
local function plate(b)
    local C = ns.COLORS
    local fill = b:CreateTexture(nil, "BACKGROUND", nil, -8)
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.95)
    local list = edges(b, 1, 1, 1, 1, -7)
    paint(list, C.border, 1)
    -- survol : nouvelle texture sur le calque de survol du bouton
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 2, -2)
    hl:SetPoint("BOTTOMRIGHT", -2, 2)
    ns.UI.Gradient(hl, "VERTICAL", C.violet[1], C.violet[2], C.violet[3], 0.05, C.violet[1], C.violet[2], C.violet[3], 0.28)
    return { fill = fill, edges = list }
end

-- bouton rouge classique (Left/Middle/Right) ou a trois tranches
-- (Left/Center/Right : boutons du menu Echap, SharedButtonTemplate)
local function skinPanelButton(b)
    local l, r = decorChild(b, "Left"), decorChild(b, "Right")
    local m = decorChild(b, "Middle") or decorChild(b, "Center")
    if not (objType(l) == "Texture" and objType(m) == "Texture" and objType(r) == "Texture") then return false end
    fade(l) fade(m) fade(r)
    local ok, h = pcall(b.GetHighlightTexture, b)
    if ok then fade(h) end
    buttons[b] = plate(b)
    return true
end

-- un habillage en profondeur (Metiers.lua) evite la double plaque
function ns.SkinHasPlate(b) return type(b) == "table" and buttons[b] ~= nil end

-- bouton a textures simples (popups) : normal / enfonce / grise / survol
local function skinTextureButton(b)
    if objType(b) ~= "Button" or buttons[b] then return end
    if skinPanelButton(b) then return end
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        local ok, t = pcall(b[get], b)
        if ok then fade(t) end
    end
    buttons[b] = plate(b)
end

-- onglet du bas d une fenetre : toutes ses textures, sauf notre survol
local function skinTab(b)
    local name = b:GetName()
    if type(name) ~= "string" then name = "" end
    if not (name:find("Tab%d+$") or decorChild(b, "LeftActive")) then return false end
    fadeRegions(b)
    tabs[b] = plate(b)
    return true
end

local function walk(f, depth, maxDepth)
    if depth > maxDepth then return end
    local ok, kids = pcall(function() return { f:GetChildren() } end)
    if not ok then return end
    for _, c in ipairs(kids) do
        local t = objType(c)
        -- cadres repris en detail ailleurs (Personnage.lua, Metiers.lua)
        local okC, claimed = pcall(function() return ns.SkinClaimed and ns.SkinClaimed(c) end)
        if okC and claimed then t = nil end
        -- menus a fleche, cases a cocher, onglets du haut : Communs.lua
        local okM, common = pcall(function() return ns.SkinCommon and ns.SkinCommon(c) end)
        if okM and common then t = nil end
        if t and not buttons[c] and not tabs[c] and not glyphs[c] then
            if t == "Button" or t == "CheckButton" then
                pcall(function() return skinTab(c) or skinPanelButton(c) end)
            else
                -- bordures interieures : cadres "NineSlice" (ils portent un
                -- champ layoutType) et leurs equivalents ranges sous ce nom
                local okL, layout = pcall(function() return c.layoutType end)
                if okL and layout then fadeRegions(c) end
                local inner = decorChild(c, "NineSlice")
                if inner then fadeRegions(inner) end
            end
            if not buttons[c] and not tabs[c] then walk(c, depth + 1, maxDepth) end
        end
    end
end

local function skinChildren(f, spec)
    local maxDepth = spec.depth or 6
    if maxDepth > 0 then
        local roots = {}
        if spec.walk then
            for _, p in ipairs(spec.walk) do
                local r = resolve(f, p)
                if r then table.insert(roots, r) end
            end
        else
            roots[1] = f
        end
        for _, r in ipairs(roots) do walk(r, 1, maxDepth) end
    end
    -- les onglets d une fenetre sont parfois ranges a cote : NomTab1, NomTab2...
    local name = f:GetName()
    if type(name) == "string" then
        for i = 1, 12 do
            local t = _G[name .. "Tab" .. i]
            local okC, claimed = pcall(function() return ns.SkinClaimed and ns.SkinClaimed(t) end)
            local okM, common = pcall(function() return ns.SkinCommon and ns.SkinCommon(t) end)
            if objType(t) == "Button" and not tabs[t] and not (okC and claimed) and not (okM and common) then
                pcall(skinTab, t)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Une fenetre
---------------------------------------------------------------------------

local function skin(spec, f)
    local okP, prot = pcall(f.IsProtected, f)
    prot = (okP and prot) and true or false

    -- le cadre et ses morceaux decoratifs perdent leur dessin (sauf les
    -- textures de spec.spare, ex. la carte des trajets aeriens)
    local spare
    for _, p in ipairs(spec.spare or {}) do
        local r = resolve(f, p)
        if r then spare = spare or {} spare[r] = true end
    end
    if not spec.keep then fadeRegions(f, spare) end
    local keepDecor = setOf(spec.keepDecor)
    for _, key in ipairs(DECOR) do
        if not keepDecor[key] then
            local c = decorChild(f, key)
            if c then
                fadeObj(c)
                local inner = decorChild(c, "NineSlice")
                if inner then fadeRegions(inner) end
                -- le titre reste (police du jeu), seul son fond disparait
            end
        end
    end
    -- portrait rond et son anneau, quel que soit leur nom dans ce modele
    -- (jamais un bouton : l oeil de la recherche de groupe en est un)
    local name = f:GetName()
    if type(name) ~= "string" then name = "" end
    for _, p in pairs({ decorChild(f, "portrait"), decorChild(f, "Portrait"), decorChild(f, "PortraitFrame"),
                        _G[name .. "Portrait"], _G[name .. "PortraitFrame"], _G[name .. "PortraitRing"] }) do
        local t = objType(p)
        if t == "Texture" then fade(p)
        elseif t and t ~= "Button" then fade(p) fadeRegions(p) end
    end
    for _, p in ipairs(spec.fade or {}) do fadeObj(resolve(f, p)) end

    -- notre fond, liseré, bandeau
    local edgeHost = (spec.edge and resolve(f, spec.edge)) or f
    if not edgeHost.CreateTexture then edgeHost = f end
    dress(f, edgeHost, spec.inset or {}, spec.noHead)
    goldTitle(f, spec)
    skinClose(f, spec)

    if not prot then
        for _, p in ipairs(spec.buttons or {}) do pcall(skinTextureButton, resolve(f, p)) end
    end
    windows[f] = { spec = spec, prot = prot }
end

local function groupOn(key)
    return not (db and db.groups and db.groups[key] == false)
end

local function scan()
    if not db or not db.enabled or InCombatLockdown() then return end
    local now = GetTime()
    for _, g in ipairs(ns.SKIN_GROUPS or {}) do
        if groupOn(g.key) then
            for _, spec in ipairs(g.windows) do
                local name = spec[1]
                local f = _G[name]
                if type(f) == "table" and f.GetRegions and f.CreateTexture then
                    if not windows[f] then
                        local ok, err = pcall(skin, spec, f)
                        if not ok then
                            windows[f] = { spec = spec, failed = true }
                            db.errors = db.errors or {}
                            db.errors[name] = tostring(err)
                        end
                    end
                    -- contenu cree au fil de l eau : on repasse sur les fenetres ouvertes
                    local w = windows[f]
                    if w and not w.failed and not w.prot and (now - (lastWalk[f] or 0)) > 3 then
                        local okV, vis = pcall(f.IsVisible, f)
                        if okV and vis then
                            lastWalk[f] = now
                            pcall(skinChildren, f, spec)
                        end
                    end
                end
            end
        end
    end
end

-- survol des croix et des boutons, onglet choisi (releve leger, sans crochet)
local function hover()
    local C = ns.COLORS
    for b, x in pairs(glyphs) do
        local ok, vis = pcall(b.IsVisible, b)
        if ok and vis then
            if b:IsMouseOver() then x:SetTextColor(1, 0.3, 0.3) else x:SetTextColor(C.text[1], C.text[2], C.text[3]) end
        end
    end
    -- onglet choisi : Blizzard le desactive ou le marque ; liseré d or et fond d accent
    for t, p in pairs(tabs) do
        local ok, vis = pcall(t.IsVisible, t)
        if ok and vis then
            local okS, sel = pcall(function() return t.isSelected or not t:IsEnabled() end)
            if okS and sel then
                paint(p.edges, C.gold, 1)
                p.fill:SetColorTexture(C.violet[1] * 0.35, C.violet[2] * 0.35, C.violet[3] * 0.35, 0.95)
            else
                paint(p.edges, C.border, 1)
                p.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.95)
            end
        end
    end
    -- boutons : liseré d or au survol
    for b, p in pairs(buttons) do
        local ok, vis = pcall(b.IsVisible, b)
        if ok and vis then
            local okM, over = pcall(function() return b:IsMouseOver() and b:IsEnabled() end)
            paint(p.edges, (okM and over) and C.gold or C.border, 1)
        end
    end
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------

local win

local function buildWindow()
    win = ns.UI.Window("CorpUISkinsOptions", ns.TITLE .. " - " .. L.MOD_SKINS, nil, 440, 400)
    local form = ns.UI.Form(win, -34)
    form:Check(L.SKINS_OPT_ENABLE, function() return db.enabled end, function(v)
        db.enabled = v
        if v then scan() end
    end)
    form:Header(L.SKINS_GROUPS)
    form:Columns(2)
    for _, g in ipairs(ns.SKIN_GROUPS or {}) do
        form:Check(L[g.label] or g.key, function() return groupOn(g.key) end, function(v)
            db.groups = db.groups or {}
            db.groups[g.key] = v and true or false
            if v then scan() end
        end)
    end
    form:EndColumns()
    form:Gap(4)
    if ns.CharSheetOptions then ns.CharSheetOptions(form) end
    form:Gap(6)
    -- bouton securise : ancre sur le panneau, jamais sur un texte
    local reload = ns.UI.ReloadButton(win, L.GEN_RELOAD, 160)
    reload:SetPoint("TOPLEFT", win, "TOPLEFT", 8, form.y)
    form:Gap(30)
    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", win, "TOPLEFT", 8, form.y - 2)
    hint:SetWidth(420)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.SKINS_HINT)
    win:HookScript("OnShow", function() form:Refresh() end)
end

local function toggle()
    if not win then buildWindow() end
    ns.ShowPanel(win)
end

---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        root.skins = root.skins or {}
        db = root.skins
        if db.enabled == nil then db.enabled = true end
        db.groups = db.groups or {}
        db.errors = nil
        -- partage avec Personnage.lua (fiche personnage en detail)
        ns.skinsDB = db
    end
    -- ADDON_LOADED : les fenetres chargees a la demande (grimoire, metiers,
    -- hotel des ventes, calendrier...) existent des cet instant
    scan()
end)
for _, e in ipairs({ "PLAYER_LOGIN", "ADDON_LOADED", "PLAYER_REGEN_ENABLED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local since = 0
ev:SetScript("OnUpdate", function(_, dt)
    since = since + dt
    if since < 0.1 then return end
    since = 0
    pcall(hover)
    -- nouvelles fenetres : une fois par seconde
    ev.tick = (ev.tick or 0) + 1
    if ev.tick >= 10 then
        ev.tick = 0
        scan()
    end
end)

ns.RegisterModule({
    command = "habillage",
    alias = "skins",
    panelName = "CorpUISkinsOptions",
    icon = "Interface\\Icons\\INV_Misc_Note_02",
    title = function() return L.MOD_SKINS end,
    desc = function() return L.SKINS_DESC end,
    Slash = function() toggle() end,
    Open = toggle,
})
