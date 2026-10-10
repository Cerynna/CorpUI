--[[--------------------------------------------------------------------------
    CorpUI - module Habillage : fiche personnage en profondeur
    (CharacterFrame et ses volets, variante Camelot de ce client)

    Skins.lua pose deja le fond de la fenetre ; ici on reprend le detail :
      - titre en or (police des titres), recolore a chaque releve car
        Blizzard le remet a sa couleur a chaque changement de volet ;
      - cases d equipement (CharacterHeadSlot ... CharacterAmmoSlot) :
        cadre dore a alpha 0, carre sombre, liseré de la couleur de qualite,
        icone recadree, niveau d objet et barre de durabilite (options) ;
      - en-tetes de categories (stats, volets lateraux, reputation,
        competences) : degrade d accent et filet d or, titre en or ;
      - lignes de stats : la bande de Blizzard devient une alternance
        discrete ;
      - onglets a icones (CharacterFrameModeTab1-6 a droite de la fiche,
        PaperDollSidebarTab1-4 au-dessus des stats) : carre CorpUI,
        liseré d or pour l onglet actif ;
      - barres de defilement minimalistes : piste de 1 px, curseur fin ;
      - boutons du modele (zoom, rotation) et bouton du volet droit : plaque
        plate ;
      - volets reputation, competences, monnaies, PvP, statistiques, titres,
        ensembles : barres de progression (fond sombre, liseré, texture
        CorpUI, couleur de Blizzard gardee), surbrillance des lignes en
        degrade d accent, cases a cocher facon ns.UI.Check, boutons - / +
        en or, icones carrees.
    Les decors sont reconnus par leur atlas (GetAtlas), jamais detruits.

    Regles de ce client (valeurs secretes, taint) :
      - aucun crochet sur une fonction ou un script de Blizzard : tout passe
        par nos evenements et un releve periodique quand la fiche est
        ouverte ;
      - aucun champ ecrit dans les tables de Blizzard : nos textures sont
        rangees dans des tables faibles a nous, indexees par le cadre ;
      - aucune taille, position, script ou attribut de Blizzard modifie :
        seulement l alpha, la couleur, le recadrage des textures, et nos
        propres textures / textes poses dessus ;
      - rien en combat ; toute valeur lue est verifiee (pcall, issecretvalue).
----------------------------------------------------------------------------]]

local _, ns = ...

local issecret = issecretvalue or function() return false end
local weak = { __mode = "k" }

local mine = setmetatable({}, weak)      -- nos regions (a ne jamais traiter)
local done = setmetatable({}, weak)      -- textures de Blizzard deja traitees
local headers = setmetatable({}, weak)   -- cadre -> { title, fill, line }
local slots = setmetatable({}, weak)     -- case d equipement -> nos regions
local modeTabs = setmetatable({}, weak)  -- onglet a droite -> { edges, fill }
local sideTabs = setmetatable({}, weak)  -- onglet au-dessus des stats -> idem
local plates = setmetatable({}, weak)    -- bouton aplati -> { edges, ... }
local bars = setmetatable({}, weak)      -- barre de defilement -> { thumb }
local checks = setmetatable({}, weak)    -- case a cocher -> { edges, mark }
local rowHl = setmetatable({}, weak)     -- cadre de surbrillance -> { tex, ref }
local progress = setmetatable({}, weak)  -- barre de progression -> { fill, edges }
local titleRows = setmetatable({}, weak) -- ligne de titre -> { sel, ref }
local masked = setmetatable({}, weak)    -- remplissage dont le masque est retire
local toggles = setmetatable({}, weak)   -- bouton de repli (statistiques) -> notre - / +

local SLOT_NAMES = { "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist",
                     "Hands", "Waist", "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1",
                     "MainHand", "SecondaryHand", "Ranged", "Ammo" }
-- emplacements sans niveau d objet utile : chemise (4), tabard (19), munitions (0)
local NO_ILVL = { [0] = true, [4] = true, [19] = true }

-- decors de la fiche, par atlas
local ATLAS = {
    ["UI-Character-Info-Title"] = "header",
    ["common-button-list-collapseExpand"] = "header",
    ["UI-Character-Info-Line-Bounce"] = "stripe",
    ["UI-Character-Info-Line-Bounce2"] = "stripe",
    ["UI-Character-Info-GearSlot"] = "iconslot",
    ["UI-Character-Info-OutfitCard"] = "card",
    ["UI-Character-Info-OutfitCard-Hover"] = "cardHover",
    ["UI-Character-Info-OutfitCard-Selected"] = "cardSel",
    ["common-button-square-gray-up"] = "control",
    ["common-button-square-gray-down"] = "control",
    ["UI-Character-Info-ScrollLine"] = "fade",
    ["UI-Character-Info-ScrollLine-Long"] = "fade",
    ["common-insideframe"] = "fade",
    ["common-framedivider"] = "fade",
    ["UI-Character-Info-ItemLevel-Bounce"] = "fade",
    ["UI-Character-Info-StatTab"] = "fade",
    ["UI-Character-Info-StatTab-Selected"] = "fade",
    ["UI-Character-Info-General-BG"] = "fade",
    ["UI-Character-Info-Stat-BG"] = "fade",
    ["UI-Character-Info-Stat-StoneBG"] = "fade",
    ["UI-Character-Info-Stat-StoneBG2"] = "fade",
    ["UI-Character-Info-RaceBG-Overlay"] = "fade",
    ["UI-Character-Info-GearSlotSmall"] = "fade",
    ["UI-Character-Info-GearSlot-Arrow"] = "fade",
    ["UI-Character-Info-OutfitIcon-Frame"] = "fade",
    ["common-sidetab"] = "fade",
    ["common-sidetab-selected"] = "fade",
    ["common-sidetab-hover"] = "fade",
    ["UI-Character-Info-Honor-LevelBG"] = "fade",
    ["UI-Character-Info-Honor-Bar-BG-Glow"] = "fade",
    -- surbrillance des lignes (reputation, competences, monnaies, stats)
    ["charactercreate-customize-dropdown-linemouseover-side"] = "rowhl",
    ["charactercreate-customize-dropdown-linemouseover-middle"] = "rowhl",
    -- barres de progression (ColoredProgressBarTemplate)
    ["common-stat-bar-BG"] = "barbg",
    ["common-stat-bar-white"] = "fill",
    ["common-stat-bar-red"] = "fill",
    ["common-stat-bar-green"] = "fill",
    ["common-stat-bar-blue"] = "fill",
    -- cases a cocher minimalistes
    ["checkbox-minimal"] = "checkbox",
    ["checkmark-minimal"] = "fade",
    ["checkmark-minimal-disabled"] = "fade",
    -- boutons - / + de repli : teintes en or (l atlas change, jamais "fait")
    ["common-button-list-plus"] = "gold",
    ["common-button-list-minus"] = "gold",
    -- repli des sous-categories (statistiques) : carre rouge remplace
    ["campaign_headericon_closed"] = "toggle",
    ["campaign_headericon_closedpressed"] = "toggle",
    ["campaign_headericon_open"] = "toggle",
    ["campaign_headericon_openpressed"] = "toggle",
}
-- meme table en minuscules : le jeu rend "Campaign_HeaderIcon_Open"
local ATLAS_LC = {}
for k, v in pairs(ATLAS) do ATLAS_LC[k:lower()] = v end
-- actions a refaire a chaque passage (Blizzard repose l atlas)
local AGAIN = { gold = true, fill = true, toggle = true }

local function db()
    local d = ns.skinsDB
    if type(d) ~= "table" or not d.enabled then return nil end
    if d.groups and d.groups.character == false then return nil end
    return d
end

---------------------------------------------------------------------------
-- Outils
---------------------------------------------------------------------------

local function objType(o)
    if type(o) ~= "table" or not o.GetObjectType then return nil end
    local ok, t = pcall(o.GetObjectType, o)
    if ok and not issecret(t) then return t end
end

local function field(f, key)
    if type(f) ~= "table" then return nil end
    local ok, c = pcall(function() return f[key] end)
    if ok and type(c) == "table" then return c end
end

local function fade(obj)
    if type(obj) == "table" and obj.SetAlpha then pcall(obj.SetAlpha, obj, 0) end
end

local function num(v)
    if v == nil or issecret(v) or type(v) ~= "number" then return nil end
    return v
end

local function visible(f)
    if type(f) ~= "table" or not f.IsVisible then return false end
    local ok, v = pcall(f.IsVisible, f)
    return ok and v == true
end

local function regionsOf(f)
    if type(f) ~= "table" or not f.GetRegions then return {} end
    local ok, list = pcall(function() return { f:GetRegions() } end)
    return ok and list or {}
end

local function childrenOf(f)
    if type(f) ~= "table" or not f.GetChildren then return {} end
    local ok, list = pcall(function() return { f:GetChildren() } end)
    return ok and list or {}
end

local function atlasOf(t)
    if not t.GetAtlas then return nil end
    local ok, a = pcall(t.GetAtlas, t)
    if ok and type(a) == "string" and not issecret(a) then return a end
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

-- carre sombre + liseré autour de "anchor"
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
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if type(c) == "table" and num(c.r) then return c.r, c.g, c.b end
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end

-- niveau d objet de l objet equipe : lien (fonction du moteur), sinon
-- emplacement d equipement
local function itemLevel(slot)
    local link = call(GetInventoryItemLink, "player", slot)
    if type(link) == "string" and not issecret(link) then
        local detail = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
        local lvl = num(call(detail, link))
        if lvl and lvl > 1 then return math.floor(lvl + 0.5) end
    end
    if C_Item and C_Item.GetCurrentItemLevel and ItemLocation and ItemLocation.CreateFromEquipmentSlot then
        local okL, loc = pcall(ItemLocation.CreateFromEquipmentSlot, ItemLocation, slot)
        if okL and loc then
            if C_Item.DoesItemExist then
                local e = call(C_Item.DoesItemExist, loc)
                if e ~= true then return nil end
            end
            local lvl = num(call(C_Item.GetCurrentItemLevel, loc))
            if lvl and lvl > 1 then return math.floor(lvl + 0.5) end
        end
    end
end

---------------------------------------------------------------------------
-- Cases d equipement
---------------------------------------------------------------------------

local function slotIcon(b, name)
    return field(b, "icon") or field(b, "Icon") or _G[name .. "IconTexture"]
end

-- textures de cadre d une case (pas l icone) : par atlas, plus les
-- textures normale / enfoncee / bordure de qualite de l ItemButton
local function fadeSlotDecor(b, s)
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture" }) do
        if b[get] then
            local ok, t = pcall(b[get], b)
            if ok and t ~= s.icon then fade(t) end
        end
    end
    fade(field(b, "IconBorder"))
    for _, r in ipairs(regionsOf(b)) do
        if r ~= s.icon and not mine[r] and objType(r) == "Texture" and ATLAS[atlasOf(r) or ""] then fade(r) end
    end
    for _, c in ipairs(childrenOf(b)) do
        local t = objType(c)
        if t == "Frame" then
            for _, r in ipairs(regionsOf(c)) do
                if objType(r) == "Texture" and ATLAS[atlasOf(r) or ""] then fade(r) end
            end
        end
    end
    local bf = field(b, "BorderFrame")
    if bf then
        for _, r in ipairs(regionsOf(bf)) do
            if objType(r) == "Texture" then fade(r) end
        end
    end
end

local function skinSlot(b, name)
    local s = { icon = slotIcon(b, name) }
    local ok, id = pcall(b.GetID, b)
    id = ok and num(id) or nil
    if not id and GetInventorySlotInfo then
        id = num(call(GetInventorySlotInfo, (name:gsub("^Character", ""))))
    end
    s.id = id
    local anchor = b
    s.box = box(b, anchor, 1)
    -- niveau d objet, en haut a droite
    s.ilvl = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    mine[s.ilvl] = true
    s.ilvl:SetPoint("TOPRIGHT", b, "TOPRIGHT", -1, -2)
    s.ilvl:SetJustifyH("RIGHT")
    s.ilvl:Hide()
    -- durabilite : fine barre en bas de la case
    s.duraBg = tex(b, "OVERLAY", 5)
    s.duraBg:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 2, 2)
    s.duraBg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    s.duraBg:SetHeight(3)
    s.duraBg:SetColorTexture(0, 0, 0, 0.75)
    s.dura = tex(b, "OVERLAY", 6)
    s.dura:SetPoint("TOPLEFT", s.duraBg, "TOPLEFT")
    s.dura:SetPoint("BOTTOMLEFT", s.duraBg, "BOTTOMLEFT")
    s.dura:SetWidth(1)
    s.duraBg:Hide()
    s.dura:Hide()
    slots[b] = s
    fadeSlotDecor(b, s)
end

local function updateSlot(b, s)
    local C = ns.COLORS
    local d = db()
    if not d then return end
    fadeSlotDecor(b, s)
    if s.icon and s.icon.SetTexCoord then pcall(s.icon.SetTexCoord, s.icon, 0.08, 0.92, 0.08, 0.92) end
    local id = s.id
    local hasItem = id and call(GetInventoryItemTexture, "player", id) ~= nil
    -- liseré : qualite de l objet (verte et plus), sinon theme
    local r, g, bl
    if hasItem then r, g, bl = qualityColor(call(GetInventoryItemQuality, "player", id)) end
    if r then paint(s.box.edges, r, g, bl, 1) else paintC(s.box.edges, C.border) end
    -- niveau d objet
    local lvl
    if hasItem and d.charIlvl ~= false and not NO_ILVL[id] then lvl = itemLevel(id) end
    if lvl then
        s.ilvl:SetText(lvl)
        s.ilvl:SetTextColor(r or C.text[1], g or C.text[2], bl or C.text[3])
        s.ilvl:Show()
    else
        s.ilvl:SetText("")
        s.ilvl:Hide()
    end
    -- durabilite, seulement si l objet est abime
    local ratio
    if hasItem and d.charDura ~= false then
        local cur, max = call(GetInventoryItemDurability, id)
        cur, max = num(cur), num(max)
        if cur and max and max > 0 and cur < max then ratio = math.max(0, cur / max) end
    end
    local okW, w = pcall(b.GetWidth, b)
    w = okW and num(w) or nil
    if ratio and w and w > 6 then
        s.dura:SetWidth(math.max(1, (w - 4) * ratio))
        s.dura:SetColorTexture(math.min(1, 2 * (1 - ratio)), math.min(1, 2 * ratio), 0.1, 1)
        s.duraBg:Show()
        s.dura:Show()
    else
        s.duraBg:Hide()
        s.dura:Hide()
    end
end

local function eachSlot(fn)
    for _, n in ipairs(SLOT_NAMES) do
        local name = "Character" .. n .. "Slot"
        local b = _G[name]
        if type(b) == "table" and b.CreateTexture then fn(b, name) end
    end
end

local function refreshSlots()
    eachSlot(function(b, name)
        if not slots[b] then pcall(skinSlot, b, name) end
        local s = slots[b]
        if s then pcall(updateSlot, b, s) end
    end)
end

---------------------------------------------------------------------------
-- En-tetes, lignes, cartes, boutons du modele (reconnus par atlas)
---------------------------------------------------------------------------

local function header(f)
    if headers[f] then return end
    local C = ns.COLORS
    local h = {}
    h.fill = tex(f, "BACKGROUND", 1)
    h.fill:SetPoint("LEFT", f, "LEFT", 4, 1)
    h.fill:SetPoint("RIGHT", f, "RIGHT", -4, 1)
    h.fill:SetHeight(22)
    ns.UI.Gradient(h.fill, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.30, C.violet[1], C.violet[2], C.violet[3], 0.03)
    h.line = tex(f, "BACKGROUND", 2)
    h.line:SetPoint("TOPLEFT", h.fill, "BOTTOMLEFT")
    h.line:SetPoint("TOPRIGHT", h.fill, "BOTTOMRIGHT")
    h.line:SetHeight(1)
    ns.UI.Gradient(h.line, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.8, C.gold[1], C.gold[2], C.gold[3], 0)
    -- survol (calque HIGHLIGHT : le moteur l affiche seul sur un bouton)
    h.hover = tex(f, "HIGHLIGHT")
    h.hover:SetAllPoints(h.fill)
    ns.UI.Gradient(h.hover, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.25, C.violet[1], C.violet[2], C.violet[3], 0.02)
    for _, key in ipairs({ "Title", "Label", "Name" }) do
        local fs = field(f, key)
        if objType(fs) == "FontString" then
            h.title = fs
            pcall(ns.UI.HeadFont, fs, 12)
            pcall(fs.SetTextColor, fs, C.gold[1], C.gold[2], C.gold[3])
            break
        end
    end
    headers[f] = h
end

-- bouton de repli des sous-categories (statistiques, "Richesse") : le
-- carre rouge de Blizzard eteint par la couleur, notre - / + en or a sa
-- place, qui suit son atlas (Open = deplie)
local function toggleGlyph(b, r, a)
    local C = ns.COLORS
    pcall(r.SetVertexColor, r, 1, 1, 1, 0)
    local t = toggles[b]
    if not t then
        t = tex(b, "OVERLAY", 7)
        t:SetPoint("CENTER", b, "CENTER", 0, 0)
        toggles[b] = t
        local okH, hl = pcall(b.GetHighlightTexture, b)
        if okH then fade(hl) end
    end
    local open = a:lower():find("_open", 1, true) ~= nil
    if t.cuiOpen ~= open then
        t.cuiOpen = open
        -- a la taille de l atlas (trait de 13 x 4, croix de 13 x 13)
        pcall(t.SetAtlas, t, open and "common-button-list-minus" or "common-button-list-plus", true)
        t:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 1)
    end
end

-- plaque plate sous un bouton (textures a nous, au fond du bouton)
local function plate(b, inset)
    if plates[b] then return plates[b] end
    local C = ns.COLORS
    local p = {}
    p.fill = tex(b, "BACKGROUND", -8)
    p.fill:SetPoint("TOPLEFT", inset, -inset)
    p.fill:SetPoint("BOTTOMRIGHT", -inset, inset)
    p.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.95)
    p.edges = ring(b, p.fill, "BACKGROUND", -7, 0)
    paintC(p.edges, C.border)
    plates[b] = p
    return p
end

-- Fleches des cases (gestionnaire d equipement : liste des objets de
-- rechange). Le decor de Blizzard (tirette brune) passe a alpha 0 ; a la
-- place, une petite plaque et un chevron d or dans le sens d ouverture
-- (deduit de la place de la fleche par rapport a sa case).
local popouts = setmetatable({}, weak)

local function popoutGlyph(slot, pb, open)
    local sx, sy = slot:GetCenter()
    local px, py = pb:GetCenter()
    if not (sx and px) then return ">" end
    local dx, dy = px - sx, py - sy
    if math.abs(dy) > math.abs(dx) then
        if dy < 0 then return open and "^" or "v" end
        return open and "v" or "^"
    end
    if dx > 0 then return open and "<" or ">" end
    return open and ">" or "<"
end

local function skinPopout(slot, pb)
    local p = popouts[pb]
    if not p then
        p = plate(pb, 1)
        p.glyph = ns.UI.Chevron(pb, 10, "RIGHT")
        mine[p.glyph] = true
        p.glyph:SetPoint("CENTER", 0, 0)
        popouts[pb] = p
    end
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
        local ok, t = pcall(pb[get], pb)
        if ok and t then pcall(t.SetAlpha, t, 0) end
    end
    local fly = _G.EquipmentFlyoutFrame
    local okO, open = pcall(function() return fly and fly:IsShown() and fly.button == slot end)
    p.glyph:SetText(popoutGlyph(slot, pb, okO and open == true))
    local C = ns.COLORS
    local okM, over = pcall(pb.IsMouseOver, pb)
    local c = (okM and over == true) and { 1, 1, 1 } or C.gold
    p.glyph:SetTextColor(c[1], c[2], c[3])
end

local function skinPopouts()
    for b in pairs(slots) do
        local pb = field(b, "popoutButton")
        if objType(pb) == "Button" and visible(pb) then pcall(skinPopout, b, pb) end
    end
end

-- icone dans un emplacement (lignes a icone des volets lateraux)
local function iconSlot(f)
    local icon = field(f, "Icon")
    if objType(icon) ~= "Texture" or plates[f] then return end
    plates[f] = box(f, icon, 1)
    pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
end

-- carre autour d une icone quelconque (monnaies, ensembles d equipement)
local function iconBox(f, icon)
    if objType(icon) ~= "Texture" then return end
    if not plates[f] then plates[f] = box(f, icon, 1) end
    cropIcon(icon)
end

-- surbrillance de ligne : le cadre BackgroundHighlight garde l alpha que
-- Blizzard lui donne (survol / choix / en guerre), on change son dessin
local function rowHighlight(f, r)
    fade(r)
    if rowHl[f] then return end
    local C = ns.COLORS
    local t = tex(f, "BACKGROUND", 1)
    t:SetAllPoints(f)
    ns.UI.Gradient(t, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.9, C.violet[1], C.violet[2], C.violet[3], 0.08)
    local line = tex(f, "BACKGROUND", 2)
    line:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    line:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    line:SetWidth(2)
    line:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    rowHl[f] = { tex = t, line = line, ref = r, red = false }
end

-- barre de progression : fond et liseré a nous (le remplissage reste celui
-- de Blizzard, avec sa couleur, seule sa texture change)
local function progressBox(f)
    if progress[f] then return end
    local C = ns.COLORS
    local bg = tex(f, "BACKGROUND", -8)
    bg:SetPoint("LEFT", f, "LEFT", -1, 0)
    bg:SetPoint("RIGHT", f, "RIGHT", 1, 0)
    bg:SetHeight(17)
    bg:SetColorTexture(0, 0, 0, 0.6)
    local edges = ring(f, bg, "BACKGROUND", -7, 0)
    paintC(edges, C.border)
    progress[f] = { bg = bg, edges = edges }
end

local FILL_TINT = { ["common-stat-bar-red"] = { 0.85, 0.2, 0.2 }, ["common-stat-bar-green"] = { 0.25, 0.8, 0.3 } }

local function restyleFill(f, r, a)
    progressBox(f)
    local mask = field(f, "Mask")
    if mask and not masked[r] and r.RemoveMaskTexture then
        masked[r] = true
        pcall(r.RemoveMaskTexture, r, mask)
    end
    if not ns.BAR_TEXTURE then return end
    pcall(r.SetTexture, r, ns.BAR_TEXTURE)
    local tint = FILL_TINT[a]
    if a == "common-stat-bar-blue" then tint = ns.COLORS.violet end
    if tint then pcall(r.SetVertexColor, r, tint[1], tint[2], tint[3], 1) end
end

-- case a cocher : carre sombre, liseré, coche d or (textures a nous ; les
-- textures de Blizzard passent a alpha 0, la case garde ses scripts)
local function skinCheck(cb)
    if checks[cb] or not cb.GetChecked then return end
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetCheckedTexture",
                           "GetDisabledCheckedTexture", "GetHighlightTexture" }) do
        if cb[get] then
            local ok, t = pcall(cb[get], cb)
            if ok then fade(t) end
        end
    end
    local C = ns.COLORS
    local fill = tex(cb, "BACKGROUND", -8)
    fill:SetSize(14, 14)
    fill:SetPoint("CENTER", cb, "CENTER", 0, 0)
    fill:SetColorTexture(0, 0, 0, 0.6)
    local edges = ring(cb, fill, "BORDER", 7, 0)
    paintC(edges, C.border)
    local mark = tex(cb, "OVERLAY", 7)
    mark:SetPoint("TOPLEFT", fill, "TOPLEFT", 3, -3)
    mark:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", -3, 3)
    ns.UI.Gradient(mark, "VERTICAL", C.gold[1] * 0.75, C.gold[2] * 0.75, C.gold[3] * 0.75, 1, C.gold[1], C.gold[2], C.gold[3], 1)
    mark:Hide()
    checks[cb] = { edges = edges, mark = mark }
end

-- lignes particulieres reconnues par leurs champs
local function special(f)
    -- titres : barre de choix et survol de Blizzard -> les notres
    local selBar, stripe = field(f, "SelectedBar"), field(f, "Stripe")
    if selBar and stripe and not titleRows[f] and objType(f) == "Button" then
        local C = ns.COLORS
        fade(selBar)
        local okH, hl = pcall(f.GetHighlightTexture, f)
        if okH then fade(hl) end
        local sel = tex(f, "BACKGROUND", 3)
        sel:SetAllPoints(f)
        ns.UI.Gradient(sel, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.4, C.violet[1], C.violet[2], C.violet[3], 0.04)
        sel:Hide()
        local hov = tex(f, "HIGHLIGHT")
        hov:SetAllPoints(f)
        ns.UI.Gradient(hov, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.22, C.violet[1], C.violet[2], C.violet[3], 0.02)
        titleRows[f] = { sel = sel, ref = selBar }
    end
    -- ensembles d equipement : icone carree
    if field(f, "HighlightBar") and field(f, "icon") then iconBox(f, field(f, "icon")) end
    -- monnaies : icone carree
    local cur = field(f, "CurrencyIcon")
    if cur then iconBox(f, cur) end
end

local function scanRegions(f)
    local C = ns.COLORS
    for _, r in ipairs(regionsOf(f)) do
        if not mine[r] and not done[r] and objType(r) == "Texture" then
            local a = atlasOf(r)
            local act = a and (ATLAS[a] or ATLAS_LC[a:lower()] or (a:match("^UI%-Character%-Info%-%u+%-BG$") and "fade")
                              or (a:match("^common%-button%-tertiary") and "tertiary"))
            if act then
                if not AGAIN[act] then done[r] = true end
                if act == "fade" then
                    fade(r)
                elseif act == "header" then
                    fade(r)
                    header(f)
                elseif act == "stripe" then
                    pcall(r.SetColorTexture, r, C.violet[1], C.violet[2], C.violet[3], 0.07)
                elseif act == "card" then
                    pcall(r.SetColorTexture, r, C.panel[1], C.panel[2], C.panel[3], 0.9)
                elseif act == "cardHover" then
                    pcall(r.SetColorTexture, r, C.violet[1], C.violet[2], C.violet[3], 0.15)
                elseif act == "cardSel" then
                    pcall(r.SetColorTexture, r, C.violet[1], C.violet[2], C.violet[3], 0.3)
                elseif act == "iconslot" then
                    fade(r)
                    iconSlot(f)
                elseif act == "control" then
                    fade(r)
                    if objType(f) == "Button" then plate(f, 6) end
                elseif act == "tertiary" then
                    fade(r)
                    if objType(f) == "Button" then plate(f, 2) end
                elseif act == "rowhl" then
                    rowHighlight(f, r)
                elseif act == "barbg" then
                    fade(r)
                    progressBox(f)
                elseif act == "fill" then
                    restyleFill(f, r, a)
                elseif act == "checkbox" then
                    fade(r)
                    if objType(f) == "CheckButton" then skinCheck(f) end
                elseif act == "toggle" then
                    toggleGlyph(f, r, a)
                elseif act == "gold" then
                    pcall(r.SetDesaturated, r, true)
                    pcall(r.SetVertexColor, r, C.gold[1], C.gold[2], C.gold[3], 1)
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Barres de defilement (MinimalScrollBar) : alpha et couleur seulement,
-- jamais SetAtlas / SetColorTexture sur leurs textures (le code de
-- Blizzard relit l atlas du curseur)
---------------------------------------------------------------------------

local function isScrollBar(f)
    local track = field(f, "Track")
    return track and field(track, "Thumb") and field(f, "Back") and field(f, "Forward") and true or false
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
end

---------------------------------------------------------------------------
-- Onglets a icones
---------------------------------------------------------------------------

-- Onglets du cote droit de la fiche (CharacterFrameModeTab1-6) : un rail
-- sombre colle a la fiche, une tuile carree par onglet. L icone de Blizzard
-- (masquee en rond, remise a 50 px a chaque clic) passe a alpha 0 ; la
-- notre est centree dans la tuile (l onglet est plus large que haut).
-- La lueur d aide (animation d alpha) est eteinte par la couleur, et notre
-- liseré pulse a sa place.
local rail
local portraitDirty = true

local function buildRail(cf)
    local host = field(cf, "ModeTabs") or _G.CharacterFrameModeTabs
    if rail or type(host) ~= "table" or not host.CreateTexture then return end
    local C = ns.COLORS
    rail = {}
    rail.fill = tex(host, "BACKGROUND", -8)
    rail.fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.92)
    rail.edges = ring(host, rail.fill, "BACKGROUND", -7, 0)
    paintC(rail.edges, C.border)
    rail.fill:Hide()
    for _, e in ipairs(rail.edges) do e:Hide() end
end

local function skinModeTab(t, index)
    if modeTabs[t] then return end
    local icon = field(t, "Icon")
    if objType(icon) ~= "Texture" then return end
    for _, k in ipairs({ "Background", "SelectedTexture", "HighlightTexture" }) do fade(field(t, k)) end
    local glow = field(t, "TabGlow")
    if glow and glow.SetVertexColor then pcall(glow.SetVertexColor, glow, 1, 1, 1, 0) end
    fade(icon)
    local C = ns.COLORS
    local okH, h = pcall(t.GetHeight, t)
    h = okH and num(h) or 50
    local size = math.max(28, math.min(46, math.floor(h) - 8))
    local s = { index = index, size = size }
    s.fill = tex(t, "BACKGROUND", -6)
    s.fill:SetSize(size, size)
    s.fill:SetPoint("LEFT", t, "LEFT", 4, 0)
    s.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 1)
    s.accent = tex(t, "BACKGROUND", -5)
    s.accent:SetAllPoints(s.fill)
    ns.UI.Gradient(s.accent, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.35, C.violet[1], C.violet[2], C.violet[3], 0.05)
    s.accent:Hide()
    s.icon = tex(t, "ARTWORK", 3)
    s.icon:SetSize(size - 4, size - 4)
    s.icon:SetPoint("CENTER", s.fill, "CENTER", 0, 0)
    s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    s.edges = ring(t, s.fill, "OVERLAY", 6, 0)
    paintC(s.edges, C.border)
    -- barre d or du cote de la fiche pour l onglet actif
    s.bar = tex(t, "OVERLAY", 7)
    s.bar:SetPoint("TOPLEFT", s.fill, "TOPLEFT", 0, 0)
    s.bar:SetPoint("BOTTOMLEFT", s.fill, "BOTTOMLEFT", 0, 0)
    s.bar:SetWidth(2)
    s.bar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    s.bar:Hide()
    modeTabs[t] = s
end

-- icone de l onglet : portrait carre (carre inscrit dans le rond) pour le
-- premier, sinon l icone choisie par Blizzard
local function syncModeIcon(t, s)
    if s.index == 1 then
        if portraitDirty or not s.portrait then
            s.portrait = true
            if SetPortraitTexture then pcall(SetPortraitTexture, s.icon, "player") end
            s.icon:SetTexCoord(0.15, 0.85, 0.15, 0.85)
        end
        return
    end
    local okS, src = pcall(function() return t.iconTexture end)
    src = okS and not issecret(src) and src or nil
    if src == nil then
        local icon = field(t, "Icon")
        local okT, f = pcall(icon.GetTexture, icon)
        if okT and not issecret(f) then src = f end
    end
    if src ~= nil and src ~= s.src then
        s.src = src
        pcall(s.icon.SetTexture, s.icon, src)
        s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

local function modeTabState(t, s)
    local C = ns.COLORS
    syncModeIcon(t, s)
    local sel = field(t, "SelectedTexture")
    local okS, active = pcall(function() return sel and sel:IsShown() end)
    active = okS and active == true
    local okM, over = pcall(t.IsMouseOver, t)
    over = okM and over == true
    local okG, glowing = pcall(function() return t.TabGlowAnimation and t.TabGlowAnimation:IsPlaying() end)
    glowing = okG and glowing == true
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
    local v = (active or over) and 1 or 0.6
    s.icon:SetVertexColor(v, v, v, 1)
end

-- le rail couvre les onglets visibles (le PvP ou les monnaies peuvent manquer)
local function placeRail()
    if not rail then return end
    local first, last
    for t, s in pairs(modeTabs) do
        if visible(t) then
            local okT, top = pcall(t.GetTop, t)
            top = okT and num(top)
            if top then
                if not first or top > first.top then first = { t = t, s = s, top = top } end
                if not last or top < last.top then last = { t = t, s = s, top = top } end
            end
        end
    end
    local show = first ~= nil
    rail.fill:SetShown(show)
    for _, e in ipairs(rail.edges) do e:SetShown(show) end
    if not show then return end
    rail.fill:ClearAllPoints()
    rail.fill:SetPoint("TOPLEFT", first.s.fill, "TOPLEFT", -4, 4)
    rail.fill:SetPoint("BOTTOMLEFT", last.s.fill, "BOTTOMLEFT", -4, -4)
    rail.fill:SetWidth(first.s.size + 8)
end

-- onglets au-dessus des stats (PaperDollSidebarTab1-4) : icone gardee
local function skinSideTab(t)
    if sideTabs[t] then return end
    local icon = field(t, "Icon")
    for _, r in ipairs(regionsOf(t)) do
        if r ~= icon and objType(r) == "Texture" and not mine[r] then fade(r) end
    end
    if t.GetCheckedTexture then
        local ok, c = pcall(t.GetCheckedTexture, t)
        if ok then fade(c) end
    end
    local C = ns.COLORS
    local s = {}
    s.fill = tex(t, "BACKGROUND", -8)
    s.fill:SetPoint("TOPLEFT", 3, -3)
    s.fill:SetPoint("BOTTOMRIGHT", -3, 3)
    s.fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.9)
    s.edges = ring(t, s.fill, "OVERLAY", 7, 0)
    paintC(s.edges, C.border)
    sideTabs[t] = s
end

local function tabState(t, s, active)
    local C = ns.COLORS
    if active then
        paintC(s.edges, C.gold)
    else
        local okM, over = pcall(t.IsMouseOver, t)
        if okM and over == true then paintC(s.edges, C.violet) else paintC(s.edges, C.border) end
    end
end

---------------------------------------------------------------------------
-- Bouton du volet droit (fleche de page) : plaque et chevron
---------------------------------------------------------------------------

local toggle

local function skinToggle(cf)
    local b = field(cf, "RightPaneToggleButton")
    if objType(b) ~= "Button" or plates[b] then return end
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
        local ok, t = pcall(b[get], b)
        if ok then fade(t) end
    end
    local p = plate(b, 5)
    p.glyph = ns.UI.Chevron(b, 12, "LEFT")
    mine[p.glyph] = true
    p.glyph:SetPoint("CENTER", 0, 0)
    toggle = b
end

---------------------------------------------------------------------------
-- Releves
---------------------------------------------------------------------------

local function titleText(cf)
    local fs = field(field(cf, "TitleContainer"), "TitleText") or field(cf, "TitleText") or _G.CharacterFrameTitleText
    if objType(fs) == "FontString" then return fs end
end

local fontDone = setmetatable({}, weak)

-- leger (5 fois par seconde, fiche ouverte) : couleurs d etat
local function light(cf)
    local C = ns.COLORS
    skinPopouts()
    local title = titleText(cf)
    if title then
        if not fontDone[title] then
            fontDone[title] = true
            pcall(ns.UI.HeadFont, title, 12)
        end
        pcall(title.SetTextColor, title, C.gold[1], C.gold[2], C.gold[3])
    end
    for t, s in pairs(modeTabs) do
        if visible(t) then pcall(modeTabState, t, s) end
    end
    portraitDirty = false
    placeRail()
    for t, s in pairs(sideTabs) do
        if visible(t) then
            local okC, checked = pcall(t.GetChecked, t)
            tabState(t, s, okC and checked == true)
        end
    end
    for b, p in pairs(plates) do
        if p.edges and objType(b) == "Button" and visible(b) then
            local okM, over = pcall(b.IsMouseOver, b)
            paintC(p.edges, (okM and over == true) and C.gold or C.border)
        end
    end
    if toggle and plates[toggle] and plates[toggle].glyph then
        local okC, collapsed = pcall(function() return cf.rightPaneCollapsed end)
        plates[toggle].glyph:SetText((okC and collapsed == true) and ">" or "<")
        plates[toggle].glyph:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    end
    -- cases a cocher : coche, grisee si desactivee, liseré d or au survol
    for cb, k in pairs(checks) do
        if visible(cb) then
            local okC, on = pcall(cb.GetChecked, cb)
            local okE, en = pcall(cb.IsEnabled, cb)
            k.mark:SetShown(okC and on and true or false)
            k.mark:SetAlpha((okE and en == false) and 0.4 or 1)
            local okM, over = pcall(cb.IsMouseOver, cb)
            paintC(k.edges, (okM and over == true) and C.gold or C.border)
        end
    end
    -- surbrillance des lignes : rouge pour une faction en guerre (Blizzard
    -- teinte alors ses textures en rouge)
    for f, h in pairs(rowHl) do
        if visible(f) then
            local okV, r, g = pcall(h.ref.GetVertexColor, h.ref)
            local red = okV and num(r) and num(g) and r > 0.8 and g < 0.5 or false
            if red ~= h.red then
                h.red = red
                local c = red and { 1, 0.2, 0.2 } or C.violet
                ns.UI.Gradient(h.tex, "HORIZONTAL", c[1], c[2], c[3], 0.9, c[1], c[2], c[3], 0.08)
                if red then h.line:SetColorTexture(1, 0.2, 0.2, 1) else h.line:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1) end
            end
        end
    end
    -- titres : notre barre suit celle de Blizzard (cachee par alpha)
    for f, t in pairs(titleRows) do
        if visible(f) then
            local okS, shown = pcall(t.ref.IsShown, t.ref)
            t.sel:SetShown(okS and shown == true)
        end
    end
    for sb, b in pairs(bars) do
        if visible(sb) then
            local okM, over = pcall(b.thumb.IsMouseOver, b.thumb)
            if okM and over == true then
                b.knob:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.9)
            else
                b.knob:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.6)
            end
        end
    end
end

-- complet : parcours de la fiche (elements de listes crees au fil de l eau)
local function walk(f, depth)
    if depth > 10 or slots[f] or not visible(f) then return end
    if isScrollBar(f) then
        pcall(skinScrollBar, f)
        return
    end
    scanRegions(f)
    pcall(special, f)
    for _, c in ipairs(childrenOf(f)) do walk(c, depth + 1) end
end

local function full(cf)
    skinToggle(cf)
    pcall(buildRail, cf)
    for i = 1, 8 do
        local t = _G["CharacterFrameModeTab" .. i]
        if type(t) == "table" and t.CreateTexture then pcall(skinModeTab, t, i) end
        local s = _G["PaperDollSidebarTab" .. i]
        if type(s) == "table" and s.CreateTexture then pcall(skinSideTab, s) end
    end
    walk(cf, 1)
    -- plus de bandeau sous "Pretresse de niveau 8" (ni fond
    -- ni filet du bas, demande du 09/10) ; textures de Blizzard : eteintes
    -- par la couleur (alpha 0), le texte du niveau reste
    do
        local host = field(_G.PaperDollFrame, "TopBackgroundStripHost")
        if host and host.GetRegions then
            for _, r in ipairs({ host:GetRegions() }) do
                if objType(r) == "Texture" then pcall(r.SetVertexColor, r, 1, 1, 1, 0) end
            end
        end
    end
    -- titres d en-tetes : Blizzard peut remettre leur couleur
    local C = ns.COLORS
    for f, h in pairs(headers) do
        if h.title and visible(f) then pcall(h.title.SetTextColor, h.title, C.gold[1], C.gold[2], C.gold[3]) end
    end
end

-- Skins.lua ne doit pas aplatir ces cadres (ils sont repris ici)
function ns.SkinClaimed(f)
    if type(f) ~= "table" or not f.GetName then return false end
    local ok, name = pcall(f.GetName, f)
    if not ok or type(name) ~= "string" or issecret(name) then return false end
    return name:find("^PaperDollSidebarTab%d") ~= nil or name:find("^CharacterFrameModeTab%d") ~= nil
        or (name:find("^Character.+Slot$") ~= nil)
end

---------------------------------------------------------------------------
-- Options (dans le panneau du module Habillage)
---------------------------------------------------------------------------

local dirty = true

function ns.CharSheetOptions(form)
    local L = ns.L
    form:Header(L.SKINS_CHAR_HEADER)
    form:Columns(2)
    form:Check(L.SKINS_CHAR_ILVL, function() return ns.skinsDB and ns.skinsDB.charIlvl ~= false end, function(v)
        if ns.skinsDB then ns.skinsDB.charIlvl = v and true or false end
        dirty = true
    end)
    form:Check(L.SKINS_CHAR_DURA, function() return ns.skinsDB and ns.skinsDB.charDura ~= false end, function(v)
        if ns.skinsDB then ns.skinsDB.charDura = v and true or false end
        dirty = true
    end)
    form:EndColumns()
end

---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
local wasShown, lastKey = false, nil
local acc, walkAcc = 0, 0

ev:SetScript("OnEvent", function(_, event, unit)
    if ns.ModuleOff("habillage", ev) then return end
    if event == "UNIT_PORTRAIT_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        if event == "PLAYER_ENTERING_WORLD" or unit == "player" then portraitDirty = true end
        return
    end
    dirty = true
    if event == "PLAYER_REGEN_ENABLED" then wasShown = false end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_EQUIPMENT_CHANGED", "UPDATE_INVENTORY_DURABILITY",
                     "PLAYER_REGEN_ENABLED", "GET_ITEM_INFO_RECEIVED", "UNIT_INVENTORY_CHANGED",
                     "UNIT_PORTRAIT_UPDATE", "PLAYER_ENTERING_WORLD" }) do
    pcall(ev.RegisterEvent, ev, e)
end

ev:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.2 then return end
    walkAcc = walkAcc + acc
    acc = 0
    if not db() or InCombatLockdown() then return end
    local cf = _G.CharacterFrame
    if type(cf) ~= "table" or not cf.CreateTexture then return end
    if not visible(cf) then
        wasShown = false
        return
    end
    -- volet affiche : un changement relance tout de suite le parcours
    local okK, key = pcall(function()
        local side = _G.PaperDollFrame and _G.PaperDollFrame.currentSideBar
        return tostring(cf.activeSubframe) .. tostring(side)
    end)
    key = okK and not issecret(key) and key or ""
    local needWalk = not wasShown or key ~= lastKey or walkAcc >= 0.6
    if not wasShown then dirty = true end
    -- cases d abord : le parcours les saute ensuite
    if dirty then
        dirty = false
        refreshSlots()
    end
    if needWalk then
        wasShown, lastKey, walkAcc = true, key, 0
        local ok, err = pcall(full, cf)
        if not ok and ns.skinsDB then
            ns.skinsDB.errors = ns.skinsDB.errors or {}
            ns.skinsDB.errors.CharacterSheet = tostring(err)
        end
    end
    pcall(light, cf)
end)
