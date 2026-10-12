--[[--------------------------------------------------------------------------
    CorpUI - module Habillage : fenetre des macros (MacroFrame de
    Blizzard_MacroUI) et choix d icone d une macro (MacroPopupFrame).

    Skins.lua pose deja le fond, le lisere, le bandeau, le titre, la croix
    et les boutons plats de la fenetre ; Communs.lua ses onglets du haut,
    son menu "Toutes les icones" et ses barres de defilement. Ici :
      - cases d icone (grille des macros, grille du choix d icone, macro
        choisie, icone choisie) : case en pierre de Blizzard, choix et
        survol a alpha 0 ; carre sombre a lisere, icone recadree, lisere
        d or pour la case choisie, d accent au survol ;
      - zone de saisie des commandes (MacroFrameTextBackground, dont le
        cadre NineSlice est deja efface) : puits sombre a lisere ;
      - champ du nom (choix d icone) : ses textures a alpha 0, champ sombre
        a lisere.
    Aucun texte visible ajoute.

    Regles de ce client (taint, valeurs secretes) : la fenetre enregistre et
    lance les macros. Donc aucun crochet, aucun SetScript, aucun champ
    ecrit dans un cadre ou une table de Blizzard (cases recyclees
    comprises : notre etat est range dans des tables faibles a nous) ;
    seulement l alpha et le recadrage de LEURS textures, et nos propres
    textures posees sur leurs cadres. Le corps de la macro (MacroFrameText)
    n est jamais touche. Releve periodique (0,1 s) fenetre ouverte, rien en
    combat. Groupe du module : "system".
----------------------------------------------------------------------------]]

local _, ns = ...

local issecret = issecretvalue or function() return false end
local weak = { __mode = "k" }

local mine = setmetatable({}, weak)      -- nos regions (a ne jamais traiter)
local claimed = setmetatable({}, weak)   -- cadres repris ici
local slots = setmetatable({}, weak)     -- case d icone -> { icon, sel, fill, edges }
local wells = setmetatable({}, weak)     -- zone de saisie / champ -> true

local ROOTS = { "MacroFrame", "MacroPopupFrame" }
local MAXDEPTH = 7

local function db()
    local d = ns.skinsDB
    if type(d) ~= "table" or not d.enabled then return nil end
    if d.groups and d.groups.system == false then return nil end
    return d
end

---------------------------------------------------------------------------
-- Outils (lectures protegees, sans fermeture neuve a chaque appel)
---------------------------------------------------------------------------

local function get(f, key) return f[key] end
local function packRegions(f) return { f:GetRegions() } end
local function packChildren(f) return { f:GetChildren() } end

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

local function isTrue(f, m)
    if type(f) ~= "table" then return false end
    local okF, fn = pcall(get, f, m)
    if not okF or type(fn) ~= "function" then return false end
    local ok, v = pcall(fn, f)
    return ok and not issecret(v) and v == true
end

local function visible(f) return isTrue(f, "IsVisible") end
local function shown(f) return isTrue(f, "IsShown") end
local function isOver(f) return isTrue(f, "IsMouseOver") end

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
    local ok, a = pcall(t.GetAtlas, t)
    if ok and not issecret(a) and type(a) == "string" then return a end
end

local function fade(t)
    if objType(t) == "Texture" and not mine[t] then pcall(t.SetAlpha, t, 0) end
end

-- textures d un cadre (pas celles de ses enfants), sauf les notres
local function fadeOwn(f, keep)
    for _, r in ipairs(regionsOf(f)) do
        if not (keep and keep[r]) then fade(r) end
    end
end

-- icone recadree (jamais sur un atlas : on casserait ses coordonnees)
local function cropIcon(icon)
    if objType(icon) ~= "Texture" or atlasOf(icon) then return end
    pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
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

-- couleur des filets, seulement si elle change (releve frequent)
local function tint(s, c, a)
    a = a or 1
    if s.c == c and s.ca == a then return end
    s.c, s.ca = c, a
    for _, x in ipairs(s.edges) do x:SetColorTexture(c[1], c[2], c[3], a) end
end

---------------------------------------------------------------------------
-- Cases d icone (SelectorButtonTemplate et voisins)
---------------------------------------------------------------------------

local function isSlot(b)
    local t = objType(b)
    if t ~= "Button" and t ~= "CheckButton" then return false end
    return objType(field(b, "Icon")) == "Texture"
end

-- toutes les textures de la case a alpha 0 (pierre, cadre, choix, survol),
-- sauf l icone ; le choix de Blizzard reste lu (IsShown) pour notre lisere
local function slot(b)
    if slots[b] or not b.CreateTexture then return end
    local icon = field(b, "Icon")
    local keep = { [icon] = true }
    fadeOwn(b, keep)
    for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetCheckedTexture" }) do
        local okF, fn = pcall(get, b, g)
        if okF and type(fn) == "function" then
            local ok, t = pcall(fn, b)
            if ok and not rawequal(t, icon) then fade(t) end
        end
    end
    cropIcon(icon)
    local C = ns.COLORS
    local s = { icon = icon, sel = field(b, "SelectedTexture") }
    s.fill = tex(b, "BACKGROUND", -8)
    s.fill:SetAllPoints(b)
    s.fill:SetColorTexture(0, 0, 0, 0.45)
    -- lisere au-dessus de l icone (elle couvre toute la case)
    s.edges = ring(b, s.fill, "OVERLAY", 7)
    s.hov = tex(b, "HIGHLIGHT")
    s.hov:SetAllPoints(b)
    s.hov:SetColorTexture(1, 1, 1, 0.12)
    tint(s, C.border)
    slots[b] = s
    claimed[b] = true
end

local function slotState(b, s)
    local C = ns.COLORS
    local c = C.border
    if shown(s.sel) or isTrue(b, "GetChecked") then c = C.gold
    elseif isOver(b) then c = C.violet end
    tint(s, c)
end

---------------------------------------------------------------------------
-- Zones de saisie
---------------------------------------------------------------------------

-- puits sombre a lisere sur "f" ; "inset" : { gauche, haut, droite, bas }
-- (positif : vers l exterieur)
local function well(f, alpha, inset)
    if wells[f] or type(f) ~= "table" or not f.CreateTexture then return end
    wells[f] = true
    inset = inset or { 0, 0, 0, 0 }
    local C = ns.COLORS
    local fill = tex(f, "BACKGROUND", -8)
    fill:SetPoint("TOPLEFT", f, "TOPLEFT", -inset[1], inset[2])
    fill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", inset[3], -inset[4])
    fill:SetColorTexture(0, 0, 0, alpha)
    tint({ edges = ring(f, fill, "BACKGROUND", -7) }, C.border, 0.9)
    claimed[f] = true
end

-- commandes de la macro : le cadre (BackdropTemplate) n a plus que son
-- NineSlice, deja efface par Skins.lua ; efface ici aussi s il revient
local function textBox()
    local bg = rawget(_G, "MacroFrameTextBackground")
    if type(bg) ~= "table" then return end
    fadeOwn(bg)
    fadeOwn(field(bg, "NineSlice"))
    well(bg, 0.35)
end

-- nom de la macro (choix d icone) : textures du champ a alpha 0
local function nameBox(popup)
    local e = field(field(popup, "BorderBox"), "IconSelectorEditBox")
    if objType(e) ~= "EditBox" then return end
    fadeOwn(e)
    well(e, 0.45, { 4, 2, 2, 2 })
end

---------------------------------------------------------------------------
-- Parcours
---------------------------------------------------------------------------

local function common(c)
    local ok, k = pcall(function() return ns.SkinCommon and ns.SkinCommon(c) end)
    return ok and k
end

local function walk(f, depth)
    for _, c in ipairs(childrenOf(f)) do
        if not mine[c] and visible(c) then
            if isSlot(c) then
                if not common(c) then pcall(slot, c) end
            elseif depth < MAXDEPTH and not field(c, "Track") then
                walk(c, depth + 1)
            end
        end
    end
end

local function full(f)
    walk(f, 1)
    if rawequal(f, rawget(_G, "MacroFrame")) then
        pcall(textBox)
    else
        pcall(nameBox, f)
    end
end

local function light()
    for b, s in pairs(slots) do
        if visible(b) then pcall(slotState, b, s) end
    end
end

-- Skins.lua : ne pas aplatir nos cases ni effacer nos textures
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

local seen = setmetatable({}, weak)   -- fenetre -> visible au releve precedent
local acc, walkAcc = 0, 0

local function report(err)
    if ns.skinsDB then
        ns.skinsDB.errors = ns.skinsDB.errors or {}
        ns.skinsDB.errors.Macros = tostring(err)
    end
end

local ev = CreateFrame("Frame")
ns.Every(0.1, function(dt)
    walkAcc = walkAcc + dt
    if not db() or InCombatLockdown() then return end
    -- cases recyclees au defilement : parcours a l ouverture puis toutes
    -- les 0,4 s
    local again = walkAcc >= 0.4
    if again then walkAcc = 0 end
    local any = false
    for _, name in ipairs(ROOTS) do
        local f = rawget(_G, name)
        if type(f) == "table" and f.GetChildren and visible(f) then
            any = true
            if again or not seen[f] then
                seen[f] = true
                local ok, err = pcall(full, f)
                if not ok then report(err) end
            end
        elseif type(f) == "table" then
            seen[f] = nil
        end
    end
    if any then
        local ok, err = pcall(light)
        if not ok then report(err) end
    end
end, "Habillage : Macros", "habillage")
