--[[--------------------------------------------------------------------------
    CorpUI - podometre : le classeur (fenetre a quatre onglets) et l annonce
      - Classeur : albums a gauche (tout, chaque serie, chaque donjon, chaque
        raid, les elites de chaque zone : avancement), pages de 6 x 3 cartes,
        filtre de rarete ; clic sur une carte : la carte en grand par-dessus
        (fabrication avec les eclats, carte precedente / suivante) ; carte
        manquante : une case vide, et la silhouette noire d une creature ;
        classeur d un joueur de la guilde en lecture seule ;
      - Boosters : boosters en attente, ouverture animee (cartes retournees
        une a une, son selon la rarete, "Nouveau !" ou eclats du doublon) ;
      - Statistiques : jour, semaine, mois, annee, total (prochain palier),
        facons de se deplacer, record, 30 derniers jours, personnages,
        equivalence reelle ;
      - Guilde : classement de la semaine des joueurs CorpUI.
    Images (Media\Podometre, Nano Banana) : cadre argente a bandeau, passe en
    gris et teinte selon la rarete, dos de carte, booster ; halo et case vide
    dessines par programme. Carte : l image sur toute la carte (creature en
    3D sur son decor), le nom sur le bandeau, rien d autre (type, rarete,
    niveau : dans la carte en grand et l infobulle). Une carte legendaire
    retournee fait son entree en grand.
    Aucune action protegee : la fenetre s ouvre aussi en combat.
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local C = ns.COLORS

ns.Pedo = ns.Pedo or {}
local P = ns.Pedo

local MEDIA = ns.MEDIA .. "Podometre\\"
-- mesures des images (make_cadre.js) : fractions de la carte. Une carte =
-- l image (la fenetre du cadre continue sous le bandeau, jusqu en bas) et
-- le nom sur le bandeau ; rien d autre
local RATIO = 1.2773                     -- hauteur / largeur d une carte (rubans compris)
local ART = { l = 0.1277, r = 0.8700, t = 0.0622, b = 0.9108 }      -- fenetre de l image
local RIBBON = { l = 0.1277, r = 0.8700, t = 0.7468, b = 0.8730 }   -- bandeau du nom
local HALO = { pad = 0.15, tex = 0.6387 }   -- marge de chaque cote, hauteur utile de l image
local TEX_FRAME, TEX_BACK, TEX_PACK = 327 / 512, 363 / 512, 392 / 512
local PACK_RATIO = 1.5325
local ART_ASPECT = (ART.r - ART.l) / ((ART.b - ART.t) * RATIO)       -- largeur / hauteur
-- ecran de chargement (4:3) dans la fenetre (plus haute que large) : sans
-- son haut (le logo du jeu), puis le milieu sur la largeur voulue
local SCENE_V0 = 0.25
local SCENE_DU = math.min(1, ART_ASPECT * (1 - SCENE_V0) * 3 / 4)
local SCENE_U = (1 - SCENE_DU) / 2
-- tuiles de zone (2 x 2, un carre) : rognees en haut et en bas (fenetre plus
-- large que haute), sinon sur les cotes
local TILE_CUT_V = ART_ASPECT >= 1 and (1 - 1 / ART_ASPECT) or 0
local TILE_CUT_U = ART_ASPECT < 1 and (1 - ART_ASPECT) or 0
-- camera des modeles 3D : recul (1 = cadrage du jeu), rotation (radians)
local MODEL_DIST, MODEL_FACING = 1.05, 0.35

local WIN_W, WIN_H = 1000, 640
local GRID_COLS, GRID_ROWS = 6, 3
local PER_PAGE = GRID_COLS * GRID_ROWS
local CARD_W, GAP_X, GAP_Y = 112, 10, 12
local CARD_H = math.floor(CARD_W * RATIO + 0.5)
local SIDE_W, ROW_H = 222, 22                     -- albums
local SIDE_ROWS = math.floor((WIN_H - 62 - 18 - 8) / ROW_H)
local SOUND_OF = { "coin", "f_ding", "f_ding", "quest", "f_carillon" }

local win, tabs, pages = nil, {}, {}
local current = "binder"

local function db() return P.db end

local function rarityRGB(r) return P.RARITY_RGB[r] or P.RARITY_RGB[1] end
local function tint(r)
    local c = rarityRGB(r)
    return 0.35 + 0.65 * c[1], 0.35 + 0.65 * c[2], 0.35 + 0.65 * c[3]
end

local function font(fs, size, flags)
    local f = (ns.FontFile and ns.FontFile("regular")) or STANDARD_TEXT_FONT
    pcall(fs.SetFont, fs, f, size, flags or "")
end

local function text(parent, template, size, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    if size then font(fs, size, flags) end
    return fs
end

local function shortName(full)
    if type(full) ~= "string" then return "?" end
    return full:match("^([^%-]+)") or full
end

-- code couleur |cff : composantes entieres
local function hex(r, g, b)
    return string.format("%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function classColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

---------------------------------------------------------------------------
-- Carte
---------------------------------------------------------------------------

local function newCard(parent, w)
    local h = math.floor(w * RATIO + 0.5)
    local c = CreateFrame("Button", nil, parent)
    c:SetSize(w, h)
    c.w, c.h = w, h
    -- zone de la carte (fractions) : gauche, haut, largeur, hauteur en pixels
    local function box(r)
        return math.floor(w * r.l + 0.5), math.floor(h * r.t + 0.5),
            math.floor(w * (r.r - r.l) + 0.5), math.floor(h * (r.b - r.t) + 0.5)
    end
    -- halo (epique, legendaire) : la silhouette floue de la carte, teintee
    local gw = w * (1 + 2 * HALO.pad)
    c.glow = c:CreateTexture(nil, "BACKGROUND", nil, -8)
    c.glow:SetSize(gw, gw * HALO.tex * 2)
    c.glow:SetPoint("CENTER")
    c.glow:SetTexture(MEDIA .. "halo")
    c.glow:SetTexCoord(0, 1, 0, HALO.tex)
    c.glow:Hide()
    -- image : la fenetre du cadre
    local al, at, aw, ah = box(ART)
    c.artBg = c:CreateTexture(nil, "BORDER")
    c.artBg:SetPoint("TOPLEFT", al, -at)
    c.artBg:SetSize(aw, ah)
    c.artBg:SetColorTexture(0.12, 0.1, 0.16, 1)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    local isz = math.floor(math.min(aw, ah) * 0.78 + 0.5)
    c.icon:SetSize(isz, isz)
    c.icon:SetPoint("CENTER", c.artBg, "CENTER", 0, 0)
    c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- tuiles de la carte du monde : 2 x 2, rognees (TILE_CUT_U / _V)
    c.tiles = {}
    for i = 1, 4 do
        local t = c:CreateTexture(nil, "ARTWORK")
        t:SetSize(aw / 2, ah / 2)
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        t:SetPoint("TOPLEFT", c.artBg, "TOPLEFT", col * aw / 2, -row * ah / 2)
        t.coords = { col == 0 and TILE_CUT_U or 0, col == 1 and 1 - TILE_CUT_U or 1,
                     row == 0 and TILE_CUT_V or 0, row == 1 and 1 - TILE_CUT_V or 1 }
        c.tiles[i] = t
    end
    -- decor d un boss : ecran de chargement de son instance
    c.scene = c:CreateTexture(nil, "ARTWORK", nil, -1)
    c.scene:SetAllPoints(c.artBg)
    c.scene:Hide()
    c.dim = c:CreateTexture(nil, "ARTWORK", nil, 3)
    c.dim:SetAllPoints(c.artBg)
    c.dim:SetColorTexture(0, 0, 0, 0.6)
    -- creature en 3D : un cadre fils se dessine au-dessus de toutes les
    -- textures de la carte ; le cadre argente, le nom et les marques passent
    -- donc dans c.over, au-dessus du modele
    c.model = CreateFrame("PlayerModel", nil, c)
    c.model:SetAllPoints(c.artBg)
    c.model:SetFrameLevel(c:GetFrameLevel() + 1)
    pcall(c.model.SetKeepModelOnHide, c.model, true)
    c.model:Hide()
    c.over = CreateFrame("Frame", nil, c)
    c.over:SetAllPoints()
    c.over:SetFrameLevel(c:GetFrameLevel() + 2)
    -- cadre (image argentee, teintee)
    c.frame = c.over:CreateTexture(nil, "OVERLAY")
    c.frame:SetAllPoints()
    c.frame:SetTexture(MEDIA .. "cadre3")
    c.frame:SetTexCoord(0, 1, 0, TEX_FRAME)
    -- nom : sur le bandeau, une ligne
    local fsz = math.max(8, math.floor(w / 11 + 0.5))
    local rl, rt, rw, rh = box(RIBBON)
    c.name = text(c.over, "GameFontHighlightSmall", fsz, "OUTLINE")
    c.name:SetPoint("TOPLEFT", c, "TOPLEFT", rl + 2, -rt)
    c.name:SetSize(rw - 4, rh)
    c.name:SetJustifyH("CENTER")
    c.name:SetJustifyV("MIDDLE")
    pcall(c.name.SetWordWrap, c.name, false)
    c.qmark = text(c.over, "GameFontNormalHuge", math.floor(aw * 0.45 + 0.5), "OUTLINE")
    c.qmark:SetPoint("CENTER", c.artBg, "CENTER", 0, 0)
    c.qmark:SetText("?")
    c.qmark:SetTextColor(0.7, 0.7, 0.75)
    c.new = text(c.over, "GameFontNormalSmall", math.max(8, fsz - 1), "OUTLINE")
    c.new:SetPoint("TOP", c.artBg, "TOP", 0, -3)
    c.new:SetText(L.PEDO_NEW)
    c.new:SetTextColor(1, 0.82, 0)
    c.nameSize, c.nameW = fsz, rw - 4
    -- ombre portee (la silhouette floue, en noir, decalee)
    c.shadow = c:CreateTexture(nil, "BACKGROUND", nil, -7)
    c.shadow:SetSize(gw, gw * HALO.tex * 2)
    c.shadow:SetPoint("CENTER", c, "CENTER", math.max(2, w / 40), -math.max(3, w / 30))
    c.shadow:SetTexture(MEDIA .. "halo")
    c.shadow:SetTexCoord(0, 1, 0, HALO.tex)
    c.shadow:SetVertexColor(0, 0, 0)
    c.shadow:SetAlpha(0.7)
    -- carte manquante : une case vide ; dans la fenetre de l image, la
    -- silhouette noire d une creature (son modele sans lumiere, dans un
    -- brouillard noir), sinon un « ? » ; dessous son numero et ou la trouver
    c.slot = c:CreateTexture(nil, "BORDER")
    c.slot:SetAllPoints()
    c.slot:SetTexture(MEDIA .. "case")
    c.slot:SetTexCoord(0, 1, 0, TEX_FRAME)
    -- (le haut de la fenetre de l image : le numero et le lieu en dessous)
    c.sil = CreateFrame("PlayerModel", nil, c)
    c.sil:SetPoint("TOPLEFT", c.artBg, "TOPLEFT")
    c.sil:SetSize(aw, math.floor(ah * 0.7 + 0.5))
    c.sil:SetFrameLevel(c:GetFrameLevel() + 1)
    pcall(c.sil.SetKeepModelOnHide, c.sil, true)
    c.sil:Hide()
    c.slotQ = text(c, "GameFontNormalHuge", math.floor(aw * 0.45 + 0.5), "OUTLINE")
    c.slotQ:SetPoint("CENTER", c.sil, "CENTER", 0, 0)
    c.slotQ:SetText("?")
    c.slotQ:SetTextColor(C.text[1], C.text[2], C.text[3], 0.35)
    c.slotNum = text(c, "GameFontNormalHuge", math.max(10, math.floor(w / 7 + 0.5)))
    c.slotNum:SetPoint("CENTER", c, "TOP", 0, -h * 0.75)
    c.slotNum:SetTextColor(C.text[1], C.text[2], C.text[3], 0.5)
    c.slotHint = text(c, "GameFontNormalSmall", math.max(7, math.floor(w / 12 + 0.5)))
    c.slotHint:SetPoint("TOP", c.slotNum, "BOTTOM", 0, -math.floor(h * 0.03 + 0.5))
    c.slotHint:SetWidth(w - 18)
    c.slotHint:SetTextColor(C.text[1], C.text[2], C.text[3], 0.6)
    c.empty = { c.slot, c.slotQ, c.slotNum, c.slotHint }
    -- face d une carte possedee
    c.face = { c.artBg, c.frame, c.name, c.shadow }
    -- dos (boosters) : un cadre au-dessus de la carte, pas une texture de
    -- la carte (le jeu dessine les textes par-dessus les textures de leur
    -- couche : le nom se voyait a travers le dos)
    c.back = CreateFrame("Frame", nil, c)
    c.back:SetAllPoints()
    c.back:SetFrameLevel(c:GetFrameLevel() + 5)
    local back = c.back:CreateTexture(nil, "ARTWORK")
    back:SetAllPoints()
    back:SetTexture(MEDIA .. "dos")
    back:SetTexCoord(0, 1, 0, TEX_BACK)
    c.back:Hide()
    return c
end

-- modele 3D d une creature : charge une fois par cadre (le jeu le garde
-- cache), en pied, tourne un peu vers la gauche
local function showModel(m, disp)
    m:Show()
    if m.disp == disp then return end
    m.disp = disp
    pcall(m.ClearModel, m)
    pcall(m.SetDisplayInfo, m, disp)
    pcall(m.SetPortraitZoom, m, 0)
    pcall(m.SetCamDistanceScale, m, MODEL_DIST)
    pcall(m.SetRotation, m, MODEL_FACING)
end

-- silhouette : le modele sans lumiere (nouvelle forme de SetLight, sinon
-- l ancienne), noye dans un brouillard noir, sans particules (le feu de
-- Ragnaros brillerait)
local function darken(m)
    pcall(m.SetParticlesEnabled, m, false)
    pcall(m.SetFogColor, m, 0, 0, 0, 1)
    pcall(m.SetFogNear, m, 0)
    pcall(m.SetFogFar, m, 0.01)
    local ok = CreateColor and CreateVector3D and pcall(m.SetLight, m, true, {
        omnidirectional = false, point = CreateVector3D(0, 0, -1),
        ambientIntensity = 0, ambientColor = CreateColor(0, 0, 0, 1),
        diffuseIntensity = 0, diffuseColor = CreateColor(0, 0, 0, 1) })
    if not ok then pcall(m.SetLight, m, true, false, 0, 0, -1, 0, 0, 0, 0, 0, 0, 0, 0) end
end

local function showSilhouette(m, disp)
    m:Show()
    if m.disp == disp then return end
    m.disp = disp
    pcall(m.ClearModel, m)
    pcall(m.SetDisplayInfo, m, disp)
    pcall(m.SetPortraitZoom, m, 0)
    pcall(m.SetCamDistanceScale, m, MODEL_DIST)
    pcall(m.SetRotation, m, MODEL_FACING)
    darken(m)
end

-- face ou case vide
local function setFace(card, on)
    for _, r in ipairs(card.face) do r:SetShown(on) end
    for _, r in ipairs(card.empty) do r:SetShown(not on) end
end

-- nom sur le bandeau : la taille baisse jusqu a ce qu il tienne (largeur du
-- texte entier : celle d un texte deja coupe par sa boite « tient » toujours)
local function nameWidth(fs)
    local ok, w = pcall(fs.GetUnboundedStringWidth, fs)
    if ok and type(w) == "number" then return w end
    return fs:GetStringWidth() or 0
end

local function fitName(card, s)
    card.name:SetText(s)
    local size = card.nameSize
    font(card.name, size, "OUTLINE")
    while size > 7 and nameWidth(card.name) > card.nameW do
        size = size - 1
        font(card.name, size, "OUTLINE")
    end
end

-- tout ce qui montre une image dans la fenetre de la carte : cache
local function clearArt(card)
    for _, t in ipairs(card.tiles) do t:Hide() end
    card.icon:Hide()
    card.scene:Hide()
    card.model:Hide()
    card.sil:Hide()
    card.glow:Hide()
    card.dim:Hide()
    card.qmark:Hide()
    card.new:Hide()
end

-- carte manquante : une case vide, la silhouette d une creature (sinon un
-- « ? »), son numero, et ou la trouver (le lieu d une creature, sinon la serie)
local function paintEmpty(card, c)
    clearArt(card)
    setFace(card, false)
    card.slotNum:SetText("#" .. (c.num or c.index))
    card.slotHint:SetText(c.disp and P.CardPlace(c) or (L["PEDO_SERIES_" .. string.upper(c.s)] or ""))
    if c.disp then
        card.slotQ:Hide()
        showSilhouette(card.sil, c.disp)
    end
end

-- remplit une carte ; owned : la carte est-elle dans le classeur montre
local function paintCard(card, c, owned, isNew)
    card.card = c
    if not c then card:Hide() return end
    card:Show()
    if not owned then paintEmpty(card, c) return end
    setFace(card, true)
    local r1, g1, b1 = tint(c.r)
    local col = rarityRGB(c.r)
    clearArt(card)
    local tiles = P.CardTiles(c)
    local scene = not tiles and P.CardScene(c)
    if scene then
        card.scene:SetTexture(scene)
        card.scene:SetTexCoord(SCENE_U, 1 - SCENE_U, SCENE_V0, 1)
        pcall(card.scene.SetDesaturated, card.scene, not owned)
        card.scene:Show()
    elseif tiles then
        local cols, rows = tiles.cols, tiles.rows
        local c0 = cols >= 2 and (math.floor((cols - 2) / 2) + 1) or 1
        local r0 = rows >= 2 and (math.floor((rows - 2) / 2) + 1) or 1
        for i = 1, 4 do
            local cc, rr = c0 + (i - 1) % 2, r0 + math.floor((i - 1) / 2)
            local id = tiles.tex[(rr - 1) * cols + cc]
            local t = card.tiles[i]
            if id and cc <= cols and rr <= rows then
                t:SetTexture(id)
                t:SetTexCoord(t.coords[1], t.coords[2], t.coords[3], t.coords[4])
                pcall(t.SetDesaturated, t, not owned)
                t:Show()
            end
        end
    elseif not c.disp then
        card.icon:SetTexture(P.CardIcon(c) or "Interface\\Icons\\INV_Misc_QuestionMark")
        pcall(card.icon.SetDesaturated, card.icon, not owned)
        card.icon:Show()
    end
    -- creature : en 3D sur son decor
    if c.disp then showModel(card.model, c.disp) end
    card.artBg:SetColorTexture(col[1] * 0.18, col[2] * 0.18, col[3] * 0.18, 1)
    card.frame:SetVertexColor(r1, g1, b1)
    fitName(card, P.CardName(c))
    card.name:SetTextColor(1, 1, 1)
    card.new:SetShown(isNew and true or false)
    if c.r >= 4 then
        card.glow:SetVertexColor(col[1], col[2], col[3])
        card.glow:SetAlpha(0.75)
        card.glow:Show()
    end
end

-- face cachee (booster) : rien ne trahit la carte autour du dos, ni le
-- halo (il depasse du dos), ni le cadre teinte (coins et rubans du dos) ;
-- la vraie face n est peinte qu au retournement
local function paintFaceDown(card, c)
    card.card = c
    if not c then card:Hide() return end
    card:Show()
    clearArt(card)
    setFace(card, true)
    card.artBg:SetColorTexture(0.12, 0.1, 0.16, 1)
    card.frame:SetVertexColor(0.38, 0.38, 0.4)
    card.name:SetText("")
end

local function cardTooltip(card)
    local c = card.card
    if not c then return end
    local owned = card.owned
    local t = ns.Tooltip(card, "ANCHOR_RIGHT")
    if owned and c.item then
        pcall(t.SetItemByID, t, c.item)
    else
        local col = rarityRGB(c.r)
        t:AddLine(owned and P.CardName(c) or L.PEDO_MISSING, col[1], col[2], col[3])
    end
    t:AddLine(L["PEDO_SERIES_" .. string.upper(c.s)] .. " · " .. L["PEDO_R" .. c.r], 0.8, 0.8, 0.8)
    if c.disp then
        t:AddLine(P.CardPlace(c), 1, 0.82, 0)
        if owned then t:AddLine(P.CardCreatureInfo(c), 0.8, 0.8, 0.8) end
    end
    local hint = P.CardHint(c)
    if hint then t:AddLine(hint, 0.6, 0.8, 1, true) end
    t:Show()
end

---------------------------------------------------------------------------
-- Fenetre
---------------------------------------------------------------------------

local refreshPage

-- onglet choisi : lisere d or (le bouton CorpUI le remet au survol)
local function paintTab(t)
    local on = t.key == current
    t:SetBackdropBorderColor((on and C.gold or C.border)[1], (on and C.gold or C.border)[2], (on and C.gold or C.border)[3], 1)
end

local function selectTab(key)
    current = key
    for k, f in pairs(pages) do f:SetShown(k == key) end
    for _, t in ipairs(tabs) do paintTab(t) end
    refreshPage()
end

local function tabLabel(key)
    if key == "packs" then
        local n = db() and #db().packs or 0
        return n > 0 and string.format(L.PEDO_TAB_PACKS_N, n) or L.PEDO_TAB_PACKS
    end
    return L["PEDO_TAB_" .. string.upper(key)]
end

---------------------------------------------------------------------------
-- Onglet Classeur : albums a gauche, 6 x 3 cartes, une carte en grand
---------------------------------------------------------------------------

local B = { album = "all", rarity = 0, page = 1, scroll = 0 }
local view            -- classeur d un autre joueur : { name, set }
local shownNew = {}   -- cartes "Nouveau" montrees : vues au changement de page
local shownKey

local function ownedHere(id)
    if view then return view.set[id] == true end
    return P.Owned(id)
end

local function forgetNew()
    local d = db()
    if not d or view then return end
    for id in pairs(shownNew) do d.newCards[id] = nil end
    shownNew = {}
end

-- albums : { key, text, head (entete de groupe), test(carte) } ; une entete
-- de serie est aussi un album (toute la serie), "Collections" non
local albums, albumByKey
local function buildAlbums()
    albums, albumByKey = {}, {}
    local function add(a) albums[#albums + 1] = a albumByKey[a.key] = a end
    add({ key = "h:col", head = true, text = L.PEDO_ALB_COLLECTIONS })
    add({ key = "all", text = L.PEDO_ALB_ALL, test = function() return true end })
    for _, s in ipairs({ "zones", "objets", "montures", "trophees" }) do
        add({ key = s, text = L["PEDO_SERIES_" .. string.upper(s)], test = function(c) return c.s == s end })
    end
    -- chaque instance, chaque zone : dans l ordre du catalogue
    for _, s in ipairs({ "donjons", "raids", "elites" }) do
        add({ key = s, head = true, text = L["PEDO_SERIES_" .. string.upper(s)], test = function(c) return c.s == s end })
        local seen = {}
        for _, c in ipairs(P.Cards(s)) do
            if c.at and not seen[c.at] then
                seen[c.at] = true
                local at = c.at
                add({ key = s .. ":" .. at, text = P.CardPlace(c), series = s,
                      test = function(x) return x.s == s and x.at == at end })
            end
        end
    end
end

-- possedees / total de chaque album (un seul passage sur les cartes)
local function albumCounts()
    local own, all = {}, {}
    for _, c in ipairs(P.Cards()) do
        local o = ownedHere(c.id)
        local keys = { "all", c.s, c.at and (c.s .. ":" .. c.at) or nil }
        for _, k in ipairs(keys) do
            all[k] = (all[k] or 0) + 1
            if o then own[k] = (own[k] or 0) + 1 end
        end
    end
    return own, all
end

-- cartes de l album choisi (filtre de rarete compris)
local function albumCards()
    local a = albumByKey[B.album] or albumByKey.all
    local out = {}
    for _, c in ipairs(P.Cards()) do
        if a.test(c) and (B.rarity == 0 or c.r == B.rarity) then out[#out + 1] = c end
    end
    return out, a
end

local function buildSide(p)
    local s = CreateFrame("Frame", nil, p)
    s:SetPoint("TOPLEFT", 10, -8)
    s:SetPoint("BOTTOMLEFT", 10, 10)
    s:SetWidth(SIDE_W)
    ns.UI.Skin(s, 0.6)
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(_, delta) B.scroll = B.scroll - delta * 3 refreshPage() end)
    s.rows = {}
    for i = 1, SIDE_ROWS do
        local r = CreateFrame("Button", nil, s)
        r:SetHeight(ROW_H)
        r:SetPoint("TOPLEFT", s, "TOPLEFT", 4, -4 - (i - 1) * ROW_H)
        r:SetPoint("RIGHT", s, "RIGHT", -8, 0)
        r.sel = r:CreateTexture(nil, "BACKGROUND")
        r.sel:SetAllPoints()
        ns.UI.Gradient(r.sel, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.3, C.violet[1], C.violet[2], C.violet[3], 0)
        r.mark = r:CreateTexture(nil, "ARTWORK")
        r.mark:SetPoint("TOPLEFT", 0, -2)
        r.mark:SetPoint("BOTTOMLEFT", 0, 2)
        r.mark:SetWidth(2)
        r.mark:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 1)
        r.label = text(r, "GameFontHighlightSmall", 11)
        r.label:SetPoint("LEFT", 8, 1)
        r.label:SetWidth(SIDE_W - 80)
        r.label:SetJustifyH("LEFT")
        pcall(r.label.SetWordWrap, r.label, false)
        r.count = text(r, "GameFontDisableSmall", 10)
        r.count:SetPoint("RIGHT", -2, 1)
        r.barBg = r:CreateTexture(nil, "ARTWORK")
        r.barBg:SetPoint("BOTTOMLEFT", 8, 1)
        r.barBg:SetPoint("BOTTOMRIGHT", -2, 1)
        r.barBg:SetHeight(1)
        r.barBg:SetColorTexture(1, 1, 1, 0.08)
        r.bar = r:CreateTexture(nil, "ARTWORK", nil, 1)
        r.bar:SetPoint("BOTTOMLEFT", 8, 1)
        r.bar:SetHeight(1)
        r.bar:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.9)
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.05)
        r:SetScript("OnClick", function(self)
            local a = self.album
            if not (a and a.test) then return end
            B.album, B.page = a.key, 1
            refreshPage()
        end)
        s.rows[i] = r
    end
    -- position dans la liste
    s.thumb = s:CreateTexture(nil, "OVERLAY")
    s.thumb:SetWidth(2)
    s.thumb:SetColorTexture(C.text[1], C.text[2], C.text[3], 0.3)
    return s
end

local function refreshSide(s, own, all)
    local n = #albums
    B.scroll = math.max(0, math.min(B.scroll, n - #s.rows))
    local barW = SIDE_W - 22
    for i, r in ipairs(s.rows) do
        local a = albums[B.scroll + i]
        r.album = a
        if a then
            r:Show()
            local o, t = own[a.key] or 0, all[a.key] or 0
            local done = t > 0 and o == t
            r.label:SetText(a.text or "?")
            if a.head then
                font(r.label, 10)
                r.label:SetTextColor(C.gold[1], C.gold[2], C.gold[3], a.test and 1 or 0.8)
            else
                font(r.label, 11)
                local col = done and C.gold or C.text
                r.label:SetTextColor(col[1], col[2], col[3])
            end
            r.count:SetText(t > 0 and string.format("%d / %d", o, t) or "")
            local on = a.key == B.album
            r.sel:SetShown(on)
            r.mark:SetShown(on)
            r.barBg:SetShown(not a.head and t > 0)
            r.bar:SetShown(not a.head and o > 0)
            if t > 0 then r.bar:SetWidth(math.max(1, barW * o / t)) end
        else
            r:Hide()
        end
    end
    local visible = #s.rows
    s.thumb:SetShown(n > visible)
    if n > visible then
        local h = s:GetHeight() - 8
        local th = math.max(16, h * visible / n)
        s.thumb:SetHeight(th)
        s.thumb:ClearAllPoints()
        s.thumb:SetPoint("TOPRIGHT", s, "TOPRIGHT", -2, -4 - (h - th) * B.scroll / (n - visible))
    end
end

-- carte en grand, par-dessus la page : la carte, son nom, son type, ou la
-- trouver, sa rarete ; fabrication si elle manque ; precedente / suivante
local openZoom, refreshZoom

local function buildZoom(p)
    local z = CreateFrame("Button", nil, p)
    z:SetAllPoints(p)
    z:SetFrameLevel(p:GetFrameLevel() + 40)
    z.bg = z:CreateTexture(nil, "BACKGROUND")
    z.bg:SetAllPoints()
    z.bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.94)
    z:SetScript("OnClick", function(self) self:Hide() end)
    z:EnableMouseWheel(true)
    z:SetScript("OnMouseWheel", function(self, delta) if self.list then openZoom(p, self.index - delta) end end)
    z.card = newCard(z, 250)
    z.card:SetPoint("TOPLEFT", z, "TOPLEFT", 90, -24)
    z.card:SetScript("OnEnter", cardTooltip)
    z.card:SetScript("OnLeave", ns.HideTooltip)
    z.name = text(z, "GameFontNormalHuge")
    ns.UI.HeadFont(z.name, 24)
    z.name:SetPoint("TOPLEFT", z.card, "TOPRIGHT", 50, -14)
    z.name:SetWidth(460)
    z.name:SetJustifyH("LEFT")
    z.sub = text(z, "GameFontNormal")
    z.sub:SetPoint("TOPLEFT", z.name, "BOTTOMLEFT", 0, -8)
    z.sub:SetWidth(460)
    z.sub:SetJustifyH("LEFT")
    z.sub:SetTextColor(C.text[1], C.text[2], C.text[3], 0.75)
    z.rar = text(z, "GameFontNormalLarge")
    z.rar:SetPoint("TOPLEFT", z.sub, "BOTTOMLEFT", 0, -14)
    z.lines = text(z, "GameFontHighlight")
    z.lines:SetPoint("TOPLEFT", z.rar, "BOTTOMLEFT", 0, -14)
    z.lines:SetWidth(460)
    z.lines:SetJustifyH("LEFT")
    pcall(z.lines.SetSpacing, z.lines, 4)
    z.hint = text(z, "GameFontDisable")
    z.hint:SetPoint("TOPLEFT", z.lines, "BOTTOMLEFT", 0, -14)
    z.hint:SetWidth(460)
    z.hint:SetJustifyH("LEFT")
    z.craft = ns.UI.Button(z, "", 220, function()
        local c = z.list and z.list[z.index]
        if c and P.Craft(c.id) then
            P.Sound("f_ding")
            refreshPage()
        end
    end)
    z.craft:SetPoint("TOPLEFT", z.hint, "BOTTOMLEFT", 0, -14)
    z.prev = ns.UI.Button(z, "<", 30, function() openZoom(p, z.index - 1) end)
    z.prev:SetPoint("TOPLEFT", z.card, "BOTTOMLEFT", 0, -14)
    z.prevName = text(z, "GameFontDisableSmall")
    z.prevName:SetPoint("LEFT", z.prev, "RIGHT", 6, 0)
    z.next = ns.UI.Button(z, ">", 30, function() openZoom(p, z.index + 1) end)
    z.next:SetPoint("TOPRIGHT", z.card, "BOTTOMRIGHT", 0, -14)
    z.nextName = text(z, "GameFontDisableSmall")
    z.nextName:SetPoint("RIGHT", z.next, "LEFT", -6, 0)
    z.close = ns.UI.Button(z, "x", 22, function() z:Hide() end)
    z.close:SetSize(22, 22)
    z.close:SetPoint("TOPRIGHT", z, "TOPRIGHT", -12, -8)
    z:Hide()
    p.zoom = z
end

local function shortCardName(c)
    if not c then return "" end
    return ownedHere(c.id) and P.CardName(c) or "???"
end

refreshZoom = function(p)
    local z = p.zoom
    local c = z.list and z.list[z.index]
    if not c then z:Hide() return end
    local owned = ownedHere(c.id)
    local col = rarityRGB(c.r)
    local series = L["PEDO_SERIES_" .. string.upper(c.s)] or ""
    z.card.owned = owned
    paintCard(z.card, c, owned, false)
    z.name:SetText(owned and P.CardName(c) or L.PEDO_MISSING)
    z.name:SetTextColor(col[1], col[2], col[3])
    if c.disp then
        z.sub:SetText(owned and (P.CardTypeName(c) .. "  ·  " .. P.CardPlace(c)) or P.CardPlace(c))
    else
        z.sub:SetText(series)
    end
    z.rar:SetText(L["PEDO_R" .. c.r] or "")
    z.rar:SetTextColor(col[1], col[2], col[3])
    local lines = {}
    if c.disp and owned then lines[#lines + 1] = string.format(L.PEDO_Z_LEVEL, (c.lvl or 0) >= 63 and "??" or tostring(c.lvl or "?")) end
    lines[#lines + 1] = string.format(L.PEDO_Z_NUM, series, c.num or c.index, (P.seriesCount and P.seriesCount[c.s]) or 0)
    z.lines:SetText(table.concat(lines, "\n"))
    local hint = P.CardHint(c)
    if not hint and not owned and c.s ~= "trophees" then hint = L.PEDO_MISSING_HINT end
    z.hint:SetText(hint or "")
    if not view and not owned and c.s ~= "trophees" then
        z.craft:SetText(string.format(L.PEDO_CRAFT, P.CRAFT[c.r]))
        z.craft:SetEnabled(P.CanCraft(c.id))
        z.craft:Show()
    else
        z.craft:Hide()
    end
    local prev, nxt = z.list[z.index - 1], z.list[z.index + 1]
    z.prev:SetEnabled(prev ~= nil)
    z.next:SetEnabled(nxt ~= nil)
    z.prevName:SetText(shortCardName(prev))
    z.nextName:SetText(shortCardName(nxt))
end

openZoom = function(p, index)
    local list = albumCards()
    if not list[index] then return end
    local z = p.zoom
    z.list, z.index = list, index
    z:Show()
    refreshZoom(p)
end

local function buildBinder(page)
    local p = page
    buildAlbums()
    p.side = buildSide(p)
    local m = CreateFrame("Frame", nil, p)
    m:SetPoint("TOPLEFT", p, "TOPLEFT", SIDE_W + 26, -8)
    m:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -12, 10)
    p.main = m
    -- l album : nom, avancement
    p.aname = text(m, "GameFontNormalLarge")
    ns.UI.HeadFont(p.aname, 18)
    p.aname:SetPoint("TOPLEFT", 2, -2)
    p.aname:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    p.ainfo = text(m, "GameFontHighlightSmall")
    p.ainfo:SetPoint("TOPLEFT", p.aname, "BOTTOMLEFT", 0, -5)
    p.ainfo:SetTextColor(C.text[1], C.text[2], C.text[3], 0.75)
    p.aprog = CreateFrame("StatusBar", nil, m)
    p.aprog:SetSize(220, 3)
    p.aprog:SetPoint("TOPLEFT", p.ainfo, "BOTTOMLEFT", 0, -6)
    p.aprog:SetStatusBarTexture(ns.BAR_TEXTURE)
    p.aprog:SetStatusBarColor(C.violet[1], C.violet[2], C.violet[3])
    p.aprog:SetMinMaxValues(0, 1)
    local pbg = p.aprog:CreateTexture(nil, "BACKGROUND")
    pbg:SetAllPoints()
    pbg:SetColorTexture(0, 0, 0, 0.6)
    -- filtre de rarete : une pastille par rarete (un 2e clic l enleve)
    p.pills = {}
    local anchor
    for r = 5, 1, -1 do
        local b = ns.UI.Button(m, "", 40, function()
            B.rarity = (B.rarity == r) and 0 or r
            B.page = 1
            refreshPage()
        end)
        b:SetHeight(20)
        b:SetText("     " .. (L["PEDO_R" .. r] or ""))
        b:SetWidth(b.cuiText:GetStringWidth() + 16)
        local dot = b:CreateTexture(nil, "OVERLAY")
        dot:SetSize(7, 7)
        dot:SetPoint("LEFT", 8, 0)
        local col = rarityRGB(r)
        dot:SetColorTexture(col[1], col[2], col[3], 1)
        b.rarity = r
        b:HookScript("OnLeave", function(self)
            if B.rarity == self.rarity then self:SetBackdropBorderColor(C.gold[1], C.gold[2], C.gold[3], 1) end
        end)
        if anchor then b:SetPoint("RIGHT", anchor, "LEFT", -4, 0) else b:SetPoint("TOPRIGHT", m, "TOPRIGHT", 0, -2) end
        anchor = b
        p.pills[r] = b
    end
    -- classeur d un autre joueur : bandeau
    p.viewing = text(m, "GameFontNormal")
    p.viewing:SetPoint("TOPRIGHT", m, "TOPRIGHT", -140, -32)
    p.back = ns.UI.Button(m, L.PEDO_MY_BINDER, 130, function() view = nil B.page = 1 refreshPage() end)
    p.back:SetPoint("TOPRIGHT", m, "TOPRIGHT", 0, -28)
    -- grille ; la molette tourne les pages
    p.cards = {}
    for i = 1, PER_PAGE do
        local card = newCard(m, CARD_W)
        local col, row = (i - 1) % GRID_COLS, math.floor((i - 1) / GRID_COLS)
        card:SetPoint("TOPLEFT", m, "TOPLEFT", col * (CARD_W + GAP_X), -62 - row * (CARD_H + GAP_Y))
        card:SetScript("OnEnter", cardTooltip)
        card:SetScript("OnLeave", ns.HideTooltip)
        card:SetScript("OnClick", function(self)
            if self.card then
                ns.HideTooltip()
                openZoom(p, self.listIndex)
            end
        end)
        p.cards[i] = card
    end
    m:EnableMouseWheel(true)
    m:SetScript("OnMouseWheel", function(_, delta) B.page = B.page - delta refreshPage() end)
    p.pageText = text(m, "GameFontHighlight")
    p.pageText:SetPoint("BOTTOM", m, "BOTTOM", 0, 6)
    p.pageText:SetWidth(110)
    p.prev = ns.UI.Button(m, "<", 30, function() B.page = B.page - 1 refreshPage() end)
    p.prev:SetPoint("RIGHT", p.pageText, "LEFT", -10, 0)
    p.next = ns.UI.Button(m, ">", 30, function() B.page = B.page + 1 refreshPage() end)
    p.next:SetPoint("LEFT", p.pageText, "RIGHT", 10, 0)
    buildZoom(p)
end

local function refreshBinder(p)
    if not albumByKey[B.album] then B.album = "all" end
    local own, all = albumCounts()
    refreshSide(p.side, own, all)
    local list, a = albumCards()
    local pagesN = math.max(1, math.ceil(#list / PER_PAGE))
    B.page = math.max(1, math.min(B.page, pagesN))
    -- autre page (ou autre album, filtre) : les cartes nouvelles d avant sont vues
    local key = B.album .. ":" .. B.rarity .. ":" .. B.page .. ":" .. (view and view.name or "")
    if key ~= shownKey then forgetNew() shownKey = key end
    -- l album
    local o, t = own[a.key] or 0, all[a.key] or 0
    p.aname:SetText(a.key == "all" and L.PEDO_ALB_ALL or a.text)
    local info = string.format(L.PEDO_ALB_INFO, o, t, t > 0 and math.floor(o / t * 100 + 0.5) or 0)
    if a.series then info = (L["PEDO_SERIES_" .. string.upper(a.series)] or "") .. "  ·  " .. info end
    p.ainfo:SetText(info)
    p.aprog:SetValue(t > 0 and o / t or 0)
    for r, b in pairs(p.pills) do
        local on = B.rarity == r
        b:SetBackdropBorderColor((on and C.gold or C.border)[1], (on and C.gold or C.border)[2], (on and C.gold or C.border)[3], 1)
    end
    p.viewing:SetShown(view ~= nil)
    p.back:SetShown(view ~= nil)
    if view then p.viewing:SetText(string.format(L.PEDO_VIEWING, shortName(view.name))) end
    -- la page
    local first = (B.page - 1) * PER_PAGE
    local d = db()
    for i, card in ipairs(p.cards) do
        local c = list[first + i]
        local owned = c and ownedHere(c.id) or false
        card.owned = owned
        card.listIndex = first + i
        local isNew = c and not view and d and d.newCards[c.id] or false
        if isNew then shownNew[c.id] = true end
        paintCard(card, c, owned, isNew)
    end
    p.pageText:SetText(string.format(L.PEDO_PAGE, B.page, pagesN))
    p.prev:SetEnabled(B.page > 1)
    p.next:SetEnabled(B.page < pagesN)
    -- carte en grand ouverte : relue (fabrication, nouvelles cartes)
    if p.zoom:IsShown() then
        p.zoom.list = list
        refreshZoom(p)
    end
end

---------------------------------------------------------------------------
-- Onglet Boosters (ouverture animee)
---------------------------------------------------------------------------

local reveal          -- { ids, results, start, flipAt = {}, done = {}, face = {} }
local FLIP_GAP, FLIP_TIME = 0.45, 0.28
local STAGE_TIME = 4.5   -- entree en scene d une legendaire (s), un clic l abrege

-- entree en scene : la carte en grand sur fond sombre, qui grandit, halo
-- battant, creature qui tourne lentement ; les retournements attendent
local function buildStage(p)
    local s = CreateFrame("Button", nil, p.show)
    s:SetAllPoints(p)
    s:SetFrameLevel(p.show:GetFrameLevel() + 30)
    s.bg = s:CreateTexture(nil, "BACKGROUND")
    s.bg:SetAllPoints()
    s.bg:SetColorTexture(0, 0, 0, 0.85)
    s.card = newCard(s, 230)
    s.card:SetPoint("CENTER", s, "CENTER", 0, 24)
    s.card:EnableMouse(false)
    s.title = text(s, "GameFontNormalHuge", 22, "OUTLINE")
    s.title:SetPoint("TOP", s.card, "BOTTOM", 0, -12)
    s.sub = text(s, "GameFontNormalLarge", 14, "OUTLINE")
    s.sub:SetPoint("TOP", s.title, "BOTTOM", 0, -4)
    s:SetScript("OnClick", function(self) self:Hide() end)
    s:SetScript("OnUpdate", function(self)
        local age = GetTime() - (self.at or 0)
        local k = math.min(1, age / 0.45)
        self:SetAlpha(math.min(1, age / 0.25))
        self.card:SetScale(0.55 + 0.45 * (1 - (1 - k) ^ 3))
        self.card.glow:SetAlpha(0.6 + 0.4 * math.abs(math.sin(age * 2.5)))
        local m = self.card.model
        if m:IsShown() then pcall(m.SetRotation, m, MODEL_FACING + age * 0.6) end
        if age > STAGE_TIME then self:Hide() end
    end)
    -- fermee : les cartes suivantes reprennent leur retournement
    s:SetScript("OnHide", function()
        if not reveal then return end
        for i = 1, #reveal.ids do
            if not reveal.flipAt[i] then
                reveal.start = GetTime() + 0.35 - 0.6 - (i - 1) * FLIP_GAP
                break
            end
        end
    end)
    s:Hide()
    p.stage = s
end

local function showStage(p, c)
    local s = p.stage
    local col = rarityRGB(c.r)
    s.card.owned = true
    paintCard(s.card, c, true, false)
    s.card.new:Hide()
    s.title:SetText(P.CardName(c))
    s.title:SetTextColor(col[1], col[2], col[3])
    s.sub:SetText((L["PEDO_R" .. c.r] or "") .. (c.disp and ("  ·  " .. P.CardPlace(c)) or ""))
    s.at = GetTime()
    s:SetAlpha(0)
    s:Show()
end

local function buildPacks(page)
    local p = page
    -- liste
    p.list = CreateFrame("Frame", nil, p)
    p.list:SetAllPoints()
    p.art = p.list:CreateTexture(nil, "ARTWORK")
    p.art:SetSize(170, math.floor(170 * PACK_RATIO + 0.5))
    p.art:SetPoint("TOPLEFT", p.list, "TOPLEFT", 40, -20)
    p.art:SetTexture(MEDIA .. "booster")
    p.art:SetTexCoord(0, 1, 0, TEX_PACK)
    p.artCount = text(p.list, "GameFontNormalHuge", 28, "OUTLINE")
    p.artCount:SetPoint("BOTTOMRIGHT", p.art, "BOTTOMRIGHT", -6, 10)
    p.open = ns.UI.Button(p.list, L.PEDO_OPEN_PACK, 170, function() P.OpenNextPack() end)
    p.open:SetPoint("TOP", p.art, "BOTTOM", 0, -14)
    p.title = text(p.list, "GameFontNormalLarge")
    p.title:SetPoint("TOPLEFT", p.list, "TOPLEFT", 250, -20)
    p.rows = {}
    for i = 1, 12 do
        local fs = text(p.list, "GameFontHighlight")
        fs:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -10 - (i - 1) * 20)
        fs:SetWidth(500)
        fs:SetJustifyH("LEFT")
        p.rows[i] = fs
    end
    p.empty = text(p.list, "GameFontHighlight")
    p.empty:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -10)
    p.empty:SetWidth(500)
    p.empty:SetJustifyH("LEFT")
    -- ouverture
    p.show = CreateFrame("Frame", nil, p)
    p.show:SetAllPoints()
    p.show:Hide()
    p.showTitle = text(p.show, "GameFontNormalLarge")
    p.showTitle:SetPoint("TOP", p.show, "TOP", 0, -16)
    p.slots, p.revealCards, p.captions = {}, {}, {}
    local cw = 120
    local total = 5 * cw + 4 * 16
    for i = 1, 5 do
        local slot = CreateFrame("Frame", nil, p.show)
        slot:SetSize(cw, math.floor(cw * RATIO + 0.5))
        slot:SetPoint("TOPLEFT", p.show, "TOPLEFT", (WIN_W - total) / 2 + (i - 1) * (cw + 16), -70)
        local card = newCard(slot, cw)
        card:SetPoint("CENTER", slot, "CENTER", 0, 0)
        card:SetScript("OnEnter", function(self) if not self.back:IsShown() then cardTooltip(self) end end)
        card:SetScript("OnLeave", ns.HideTooltip)
        card:SetScript("OnClick", function()
            if reveal and not reveal.done[i] and not reveal.flipAt[i] then reveal.flipAt[i] = GetTime() end
        end)
        local cap = text(p.show, "GameFontNormal")
        cap:SetPoint("TOP", slot, "BOTTOM", 0, -10)
        cap:SetWidth(cw + 10)
        p.slots[i], p.revealCards[i], p.captions[i] = slot, card, cap
    end
    p.nextPack = ns.UI.Button(p.show, "", 200, function()
        if db() and #db().packs > 0 then P.OpenNextPack() else reveal = nil refreshPage() end
    end)
    p.nextPack:SetPoint("BOTTOM", p.show, "BOTTOM", -110, 40)
    p.toBinder = ns.UI.Button(p.show, L.PEDO_SEE_BINDER, 200, function() reveal = nil selectTab("binder") end)
    p.toBinder:SetPoint("BOTTOM", p.show, "BOTTOM", 110, 40)
    buildStage(p)
    -- animation : retournement des cartes une a une (en pause pendant
    -- l entree en scene d une legendaire)
    p.show:SetScript("OnUpdate", function()
        if not reveal then return end
        local now = GetTime()
        for i = 1, #reveal.ids do
            local card = p.revealCards[i]
            if not reveal.flipAt[i] and not p.stage:IsShown() and now >= reveal.start + 0.6 + (i - 1) * FLIP_GAP then
                reveal.flipAt[i] = now
            end
            local t0 = reveal.flipAt[i]
            -- debut du retournement : la vraie face, sous le dos encore opaque
            if t0 and not reveal.face[i] then
                reveal.face[i] = true
                paintCard(card, P.byId[reveal.ids[i]], true, false)
                card.new:Hide()
                card.name:SetAlpha(0)
                card.glow:SetAlpha(1)
            end
            if t0 and not reveal.done[i] then
                local k = math.min(1, (now - t0) / FLIP_TIME)
                card.back:SetAlpha(1 - k)
                card:SetScale(1 + 0.12 * math.sin(k * math.pi))
                if k >= 1 then
                    reveal.done[i] = true
                    card.back:Hide()
                    card.name:SetAlpha(1)
                    card:SetScale(1)
                    local res = reveal.results[i]
                    local c = P.byId[reveal.ids[i]]
                    local cap = p.captions[i]
                    if res and res.what == "new" then
                        cap:SetText(L.PEDO_NEW_CARD)
                        cap:SetTextColor(1, 0.82, 0)
                    else
                        cap:SetText(string.format(L.PEDO_DUP, res and res.gain or 0))
                        cap:SetTextColor(0.7, 0.7, 0.75)
                    end
                    P.Sound(SOUND_OF[c and c.r or 1])
                    if c and c.r >= 5 then showStage(p, c) end
                end
            end
            -- lueur des grandes raretes une fois retournees
            if reveal.done[i] and card.card and card.card.r >= 4 then
                card.glow:SetAlpha(0.55 + 0.45 * math.abs(math.sin(now * 3)))
            end
        end
    end)
end

local function refreshPacks(p)
    local d = db()
    if not d then return end
    if reveal then
        p.list:Hide()
        p.show:Show()
        p.showTitle:SetText(reveal.title or "")
        local left = #d.packs
        p.nextPack:SetText(left > 0 and string.format(L.PEDO_NEXT_PACK, left) or L.PEDO_DONE)
        return
    end
    p.show:Hide()
    p.list:Show()
    local n = #d.packs
    p.artCount:SetText(n > 0 and ("x" .. n) or "")
    p.art:SetDesaturated(n == 0)
    p.open:SetEnabled(n > 0)
    p.title:SetText(n > 0 and string.format(L.PEDO_PACKS_WAITING, n) or L.PEDO_NO_PACK)
    for i, fs in ipairs(p.rows) do
        local pack = d.packs[i]
        if pack and i < #p.rows then
            local col = rarityRGB(P.PACK_MIN[pack.k] and (P.PACK_MIN[pack.k] + 1) or 2)
            if pack.k == "normal" then col = { 1, 1, 1 } end
            fs:SetText(string.format("|cff%s%s|r  %s", hex(col[1], col[2], col[3]),
                L["PEDO_PACK_" .. string.upper(pack.k)] or pack.k, P.WhyText(pack)))
        elseif i == #p.rows and n >= #p.rows then
            fs:SetText(string.format(L.PEDO_AND_MORE, n - #p.rows + 1))
        else
            fs:SetText("")
        end
    end
    p.empty:SetShown(n == 0)
    if n == 0 then
        local nk, kind, y = P.NextMilestone("day")
        p.empty:SetText(nk and string.format(L.PEDO_NEXT_DAY, P.KmValue(nk), P.Km(nk * 1000 - y), L["PEDO_PACK_" .. string.upper(kind)]) or "")
    end
end

-- ouvre le plus ancien booster : les cartes sont gagnees tout de suite,
-- l animation ne fait que les montrer
function P.OpenNextPack()
    local d = db()
    if not d or #d.packs == 0 then return end
    local pack = table.remove(d.packs, 1)
    local ids = P.RollPack(pack.k)
    local results = {}
    for i, id in ipairs(ids) do
        local what, gain = P.Grant(id)
        results[i] = { what = what, gain = gain }
    end
    d.opened = (d.opened or 0) + 1
    reveal = { ids = ids, results = results, start = GetTime(), flipAt = {}, done = {}, face = {},
               title = (L["PEDO_PACK_" .. string.upper(pack.k)] or "") .. " · " .. P.WhyText(pack) }
    local p = pages.packs
    p.stage:Hide()
    for i = 1, 5 do
        local card = p.revealCards[i]
        local c = P.byId[ids[i]]
        card.owned = true
        paintFaceDown(card, c)
        card.back:Show()
        card.back:SetAlpha(1)
        card:SetScale(1)
        p.captions[i]:SetText("")
        p.slots[i]:SetShown(c ~= nil)
    end
    P.Sound("f_confirm1")
    if P.CheckTrophies then P.CheckTrophies() end
    P.Changed("open")
    if current ~= "packs" then selectTab("packs") else refreshPage() end
end

---------------------------------------------------------------------------
-- Onglet Statistiques
---------------------------------------------------------------------------

local function buildStats(page)
    local p = page
    p.boxes = {}
    for i, kind in ipairs({ "day", "week", "month", "year", "total" }) do
        local box = CreateFrame("Frame", nil, p)
        box:SetSize(142, 96)
        box:SetPoint("TOPLEFT", p, "TOPLEFT", 12 + (i - 1) * 152, -8)
        ns.UI.Skin(box, 0.6)
        box.title = text(box, "GameFontDisableSmall")
        box.title:SetPoint("TOPLEFT", 8, -7)
        box.title:SetText(L["PEDO_P_" .. string.upper(kind)])
        box.value = text(box, "GameFontHighlightLarge")
        ns.UI.HeadFont(box.value, 19)
        box.value:SetPoint("TOPLEFT", 8, -24)
        box.bar = CreateFrame("StatusBar", nil, box)
        box.bar:SetPoint("TOPLEFT", 8, -56)
        box.bar:SetPoint("TOPRIGHT", -8, -56)
        box.bar:SetHeight(6)
        box.bar:SetStatusBarTexture(ns.BAR_TEXTURE)
        box.bar:SetStatusBarColor(C.gold[1], C.gold[2], C.gold[3])
        box.bar:SetMinMaxValues(0, 1)
        local bbg = box.bar:CreateTexture(nil, "BACKGROUND")
        bbg:SetAllPoints()
        bbg:SetColorTexture(0, 0, 0, 0.5)
        box.next = text(box, "GameFontDisableSmall")
        box.next:SetPoint("TOPLEFT", 8, -68)
        box.next:SetWidth(128)
        box.next:SetJustifyH("LEFT")
        box.kind = kind
        p.boxes[i] = box
    end
    p.modesToday = text(p, "GameFontHighlightSmall")
    p.modesToday:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -118)
    p.modesTotal = text(p, "GameFontHighlightSmall")
    p.modesTotal:SetPoint("TOPLEFT", p.modesToday, "BOTTOMLEFT", 0, -4)
    p.record = text(p, "GameFontNormalSmall")
    p.record:SetPoint("TOPLEFT", p.modesTotal, "BOTTOMLEFT", 0, -4)
    -- 30 derniers jours
    p.chartTitle = text(p, "GameFontNormal")
    p.chartTitle:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -186)
    p.chartTitle:SetText(L.PEDO_LAST30)
    p.chart = CreateFrame("Frame", nil, p)
    p.chart:SetSize(30 * 16, 150)
    p.chart:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -208)
    ns.UI.Skin(p.chart, 0.45)
    p.bars = {}
    for i = 1, 30 do
        local b = CreateFrame("Frame", nil, p.chart)
        b:SetSize(12, 1)
        b:SetPoint("BOTTOMLEFT", p.chart, "BOTTOMLEFT", 2 + (i - 1) * 16, 2)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints()
        b:EnableMouse(true)
        b:SetScript("OnEnter", function(self)
            if not self.label then return end
            local t = ns.Tooltip(self, "ANCHOR_TOP")
            t:AddLine(self.label, 1, 0.82, 0)
            t:AddLine(P.Km(self.yards or 0, 2), 1, 1, 1)
            t:Show()
        end)
        b:SetScript("OnLeave", ns.HideTooltip)
        p.bars[i] = b
    end
    p.chartMax = text(p, "GameFontDisableSmall")
    p.chartMax:SetPoint("BOTTOMLEFT", p.chart, "TOPRIGHT", -80, 4)
    p.equiv = text(p, "GameFontHighlight")
    p.equiv:SetPoint("TOPLEFT", p.chart, "BOTTOMLEFT", 0, -12)
    p.equiv:SetWidth(740)
    p.equiv:SetJustifyH("LEFT")
    -- personnages
    p.charsTitle = text(p, "GameFontNormal")
    p.charsTitle:SetPoint("TOPLEFT", p, "TOPLEFT", 520, -186)
    p.charsTitle:SetText(L.PEDO_CHARS)
    p.chars = {}
    for i = 1, 8 do
        local row = text(p, "GameFontHighlightSmall")
        row:SetPoint("TOPLEFT", p.charsTitle, "BOTTOMLEFT", 0, -6 - (i - 1) * 18)
        row:SetWidth(240)
        row:SetJustifyH("LEFT")
        p.chars[i] = row
    end
end

local function modesLine(label, get)
    return string.format("%s  %s %s  ·  %s %s  ·  %s %s  ·  %s %s", label,
        L.PEDO_M_F, P.Km(get("f")), L.PEDO_M_S, P.Km(get("s")), L.PEDO_M_M, P.Km(get("m")), L.PEDO_M_G, P.Km(get("g")))
end

local function refreshStats(p)
    local d = db()
    if not d then return end
    local T = P.Totals()
    for _, box in ipairs(p.boxes) do
        local y = T[box.kind] or 0
        box.value:SetText(P.Km(y))
        local list = P.MILESTONES[box.kind]
        local prevK, nextK, nextKind = 0, nil, nil
        for _, ms in ipairs(list) do
            if y < ms[1] * 1000 then nextK, nextKind = ms[1], ms[2] break end
            prevK = ms[1]
        end
        if nextK then
            box.bar:SetValue((y - prevK * 1000) / ((nextK - prevK) * 1000))
            box.next:SetText(string.format(L.PEDO_NEXT_SHORT, P.KmValue(nextK)))
        else
            box.bar:SetValue(1)
            box.next:SetText(L.PEDO_ALL_DONE)
        end
    end
    local K = T.keys
    p.modesToday:SetText(modesLine(L.PEDO_TODAY, function(m) return P.DayYards(K.day, m) end))
    p.modesTotal:SetText(modesLine(L.PEDO_P_TOTAL, function(m) return d.total[m] or 0 end))
    if (d.best.y or 0) > 0 and d.best.k then
        local yy, mm, dd = d.best.k:match("^(%d+)%-(%d+)%-(%d+)$")
        p.record:SetText(string.format(L.PEDO_RECORD, P.Km(d.best.y), string.format(L.PEDO_DATE, dd or "?", mm or "?", yy or "?")))
    else
        p.record:SetText("")
    end
    -- 30 derniers jours
    local maxY = 1
    local vals = {}
    for i = 1, 30 do
        local t = K.noon - (30 - i) * 86400
        local dk = date("%Y-%m-%d", t)
        vals[i] = { y = P.DayYards(dk), dk = dk, t = t }
        if vals[i].y > maxY then maxY = vals[i].y end
    end
    for i, b in ipairs(p.bars) do
        local v = vals[i]
        b:SetHeight(math.max(1, math.floor(v.y / maxY * 144 + 0.5)))
        if i == 30 then b.tex:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
        else b.tex:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], v.y > 0 and 0.9 or 0.25) end
        b.yards = v.y
        b.label = date(L.PEDO_DAY_FMT, v.t)
    end
    p.chartMax:SetText(string.format(L.PEDO_MAX, P.Km(maxY)))
    -- equivalence reelle
    local tk = T.total / 1000
    local done, nextE
    for _, e in ipairs(P.EQUIV) do
        if tk >= e[1] then done = e else nextE = e break end
    end
    local s = done and string.format(L.PEDO_EQUIV_DONE, L[done[2]]) or L.PEDO_EQUIV_NONE
    if nextE then s = s .. "  " .. string.format(L.PEDO_EQUIV_NEXT, L[nextE[2]], P.Km((nextE[1] - tk) * 1000, 0)) end
    p.equiv:SetText(s)
    -- personnages
    local chars = {}
    for _, ch in pairs(d.chars) do
        if type(ch) == "table" and (tonumber(ch.total) or 0) > 0 then chars[#chars + 1] = ch end
    end
    table.sort(chars, function(a, b) return (a.total or 0) > (b.total or 0) end)
    for i, row in ipairs(p.chars) do
        local ch = chars[i]
        if ch then
            local r, g, b = classColor(ch.class)
            row:SetText(string.format("|cff%s%s|r  %s  |cff999999(%s)|r", hex(r, g, b),
                ch.name or "?", P.Km(ch.total), string.format(L.PEDO_TODAY_SHORT, P.Km(ch.days and ch.days[K.day] or 0))))
        else
            row:SetText("")
        end
    end
end

---------------------------------------------------------------------------
-- Onglet Guilde
---------------------------------------------------------------------------

local function buildGuild(page)
    local p = page
    p.title = text(p, "GameFontNormalLarge")
    p.title:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -10)
    p.title:SetText(L.PEDO_GUILD_TITLE)
    p.sub = text(p, "GameFontDisableSmall")
    p.sub:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -4)
    p.sub:SetText(L.PEDO_GUILD_SUB)
    local cols = { { "#", 12 }, { L.PEDO_COL_NAME, 48 }, { L.PEDO_COL_WEEK, 250 }, { L.PEDO_COL_TOTAL, 370 }, { L.PEDO_COL_CARDS, 490 } }
    for _, col in ipairs(cols) do
        local h = text(p, "GameFontNormalSmall")
        h:SetPoint("TOPLEFT", p, "TOPLEFT", col[2], -60)
        h:SetText(col[1])
    end
    p.rows = {}
    for i = 1, 14 do
        local row = CreateFrame("Frame", nil, p)
        row:SetSize(WIN_W - 24, 22)
        row:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -78 - (i - 1) * 24)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0.06)
        row.rank = text(row, "GameFontHighlight")
        row.rank:SetPoint("LEFT", 0, 0)
        row.name = text(row, "GameFontHighlight")
        row.name:SetPoint("LEFT", 36, 0)
        row.week = text(row, "GameFontHighlight")
        row.week:SetPoint("LEFT", 238, 0)
        row.total = text(row, "GameFontHighlight")
        row.total:SetPoint("LEFT", 358, 0)
        row.cards = text(row, "GameFontHighlight")
        row.cards:SetPoint("LEFT", 478, 0)
        row.see = ns.UI.Button(row, L.PEDO_SEE, 110, function(self)
            local e = self.entry
            if not e or not e.bits then return end
            view = { name = e.name, set = P.BitsToSet(e.bits) }
            B.album, B.page = "all", 1
            selectTab("binder")
        end)
        row.see:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.see:SetHeight(20)
        p.rows[i] = row
    end
    p.empty = text(p, "GameFontHighlight")
    p.empty:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -110)
    p.empty:SetWidth(740)
    p.empty:SetJustifyH("LEFT")
    p.share = ns.UI.Check(p, L.PEDO_OPT_SHARE, function(v)
        if db() then db().opt.share = v end
        if v then P.Share(false) end
    end)
    p.share:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 8, 10)
end

local function refreshGuild(p)
    local list = P.GuildBoard()
    local _, all = P.OwnedCount()
    for i, row in ipairs(p.rows) do
        local e = list[i]
        if e then
            row:Show()
            row.rank:SetText(i)
            local r, g, b = classColor(e.class)
            row.name:SetText(shortName(e.name) .. (e.me and (" |cff999999" .. L.PEDO_ME .. "|r") or ""))
            row.name:SetTextColor(r, g, b)
            row.week:SetText(P.Km(e.week))
            row.total:SetText(P.Km(e.total, 0))
            row.cards:SetText(string.format("%d / %d", e.cards or 0, all))
            row.see.entry = e
            row.see:SetShown(not e.me and e.bits ~= nil and e.bits ~= "")
        else
            row:Hide()
        end
    end
    p.empty:SetShown(#list <= 1)
    p.empty:SetText(L.PEDO_GUILD_EMPTY)
    p.share:SetChecked(db() and db().opt.share or false)
end

---------------------------------------------------------------------------
-- Construction et rafraichissement
---------------------------------------------------------------------------

refreshPage = function()
    if not win or not win:IsShown() then return end
    for _, t in ipairs(tabs) do t:SetText(tabLabel(t.key)) end
    if win.shards then win.shards:SetText(string.format(L.PEDO_SHARDS, db() and db().shards or 0)) end
    if win.total then
        local own, all = P.OwnedCount()
        win.total:SetText(string.format(L.PEDO_ALB_INFO, own, all, all > 0 and math.floor(own / all * 100 + 0.5) or 0))
    end
    local p = pages[current]
    if current == "binder" then refreshBinder(p)
    elseif current == "packs" then refreshPacks(p)
    elseif current == "stats" then refreshStats(p)
    elseif current == "guild" then refreshGuild(p) end
end
P.RefreshBinder = function() pcall(refreshPage) end
P.OnDataLoaded = function() pcall(refreshPage) end

local function build()
    local d = db()
    d.opt.pos = d.opt.pos or { point = "CENTER", x = 0, y = 30 }
    win = CreateFrame("Frame", "CorpUIBinder", UIParent)
    win:SetSize(WIN_W, WIN_H)
    ns.ApplyPos(win, d.opt.pos)
    win:SetFrameStrata("HIGH")
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    ns.UI.Skin(win, 0.97, true)
    win:Hide()
    -- barre de titre (glisser pour deplacer)
    local bar = CreateFrame("Frame", nil, win)
    bar:SetPoint("TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", 0, 0)
    bar:SetHeight(28)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() win:StartMoving() end)
    bar:SetScript("OnDragStop", function()
        win:StopMovingOrSizing()
        local point, _, _, x, y = win:GetPoint(1)
        d.opt.pos = { point = point or "CENTER", x = x or 0, y = y or 0 }
    end)
    local title = bar:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(title, 14)
    title:SetPoint("LEFT", 10, 0)
    title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    title:SetText(L.PEDO_BINDER)
    -- avancement de tout le classeur, a cote du titre
    win.total = text(bar, "GameFontDisableSmall")
    win.total:SetPoint("LEFT", title, "RIGHT", 12, 0)
    local close = CreateFrame("Button", nil, bar)
    close:SetSize(22, 22)
    close:SetPoint("RIGHT", -4, 0)
    local x = close:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    x:SetPoint("CENTER")
    x:SetText("×")
    close:SetScript("OnClick", function() win:Hide() end)
    win.shards = text(bar, "GameFontNormal")
    win.shards:SetPoint("RIGHT", close, "LEFT", -12, 0)
    -- onglets
    for i, key in ipairs({ "binder", "packs", "stats", "guild" }) do
        local t = ns.UI.Button(win, tabLabel(key), 130, function() selectTab(key) end)
        t:SetPoint("TOPLEFT", win, "TOPLEFT", 12 + (i - 1) * 138, -32)
        t.key = key
        t:HookScript("OnLeave", paintTab)
        tabs[i] = t
        local page = CreateFrame("Frame", nil, win)
        page:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -62)
        page:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 0)
        page:Hide()
        pages[key] = page
    end
    buildBinder(pages.binder)
    buildPacks(pages.packs)
    buildStats(pages.stats)
    buildGuild(pages.guild)
    win:SetScript("OnShow", function() selectTab(current) end)
    win:SetScript("OnHide", function()
        forgetNew()
        shownKey = nil
        -- ouverture interrompue : les cartes sont deja gagnees
        reveal = nil
    end)
end

function P.ToggleBinder(forceOpen, tab)
    if not db() then return end
    if not win then build() end
    if tab then current = tab end
    if win:IsShown() and not forceOpen and not tab then win:Hide() return end
    win:Show()
    if tab then selectTab(tab) end
end

function P.CloseBinder() if win then win:Hide() end end
function P.BinderShown() return win and win:IsShown() or false end

P.Listen(function(what)
    if what == "guild" and current ~= "guild" then
        -- seul l onglet Guilde en depend ; le titre des onglets ne change pas
        return
    end
    if win and win:IsShown() then
        -- pendant une ouverture, ne pas repeindre les cartes retournees
        if what == "open" then return end
        pcall(refreshPage)
    end
end)

---------------------------------------------------------------------------
-- Annonce (booster gagne, trophee) : en haut de l ecran, apres le combat
---------------------------------------------------------------------------

local toast
local queue = {}
local TOAST_TIME = 6

local function buildToast()
    toast = CreateFrame("Button", "CorpUIPedometerToast", UIParent)
    toast:SetSize(330, 64)
    toast:SetPoint("TOP", UIParent, "TOP", 0, -110)
    toast:SetFrameStrata("DIALOG")
    ns.UI.Skin(toast, 0.95, true)
    toast.icon = toast:CreateTexture(nil, "ARTWORK")
    toast.icon:SetPoint("LEFT", 8, 0)
    toast.title = text(toast, "GameFontNormal")
    toast.title:SetPoint("TOPLEFT", 64, -12)
    toast.title:SetPoint("RIGHT", -10, 0)
    toast.title:SetJustifyH("LEFT")
    toast.body = text(toast, "GameFontHighlight")
    toast.body:SetPoint("TOPLEFT", toast.title, "BOTTOMLEFT", 0, -4)
    toast.body:SetPoint("RIGHT", -10, 0)
    toast.body:SetJustifyH("LEFT")
    toast:SetScript("OnClick", function(self)
        self:Hide()
        P.ToggleBinder(true, self.tab)
    end)
    toast:SetScript("OnUpdate", function(self)
        local age = GetTime() - (self.at or 0)
        if age > TOAST_TIME then
            self:Hide()
        elseif age > TOAST_TIME - 1 then
            self:SetAlpha(TOAST_TIME - age)
        end
    end)
    toast:SetScript("OnHide", function()
        C_Timer.After(0.3, function() if P.ShowNextToast then P.ShowNextToast() end end)
    end)
    toast:Hide()
end

function P.ShowNextToast()
    if #queue == 0 or InCombatLockdown() then return end
    if not toast then buildToast() end
    if toast:IsShown() then return end
    local m = table.remove(queue, 1)
    toast.title:SetText(m.title)
    toast.body:SetText(m.body)
    if m.pack then
        toast.icon:SetSize(34, 52)
        toast.icon:SetTexture(MEDIA .. "booster")
        toast.icon:SetTexCoord(0, 1, 0, TEX_PACK)
    else
        toast.icon:SetSize(44, 44)
        toast.icon:SetTexture(m.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        toast.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    toast.tab = m.tab
    toast.at = GetTime()
    toast:SetAlpha(1)
    toast:Show()
    P.Sound(m.sound or "f_carillon")
end

function P.Announce(kind, data)
    local d = db()
    if not d then return end
    if kind == "pack" then
        if not d.opt.toast then return end
        queue[#queue + 1] = {
            pack = true, tab = "packs", sound = "f_carillon",
            title = string.format(L.PEDO_TOAST_PACK, L["PEDO_PACK_" .. string.upper(data.k)] or ""),
            body = P.WhyText(data),
        }
    elseif kind == "trophy" then
        if not d.opt.toast then return end
        queue[#queue + 1] = {
            tab = "binder", sound = "quest", icon = P.CardIcon(data),
            title = L.PEDO_TOAST_TROPHY, body = P.CardName(data),
        }
    end
    P.ShowNextToast()
end

local tev = CreateFrame("Frame")
tev:RegisterEvent("PLAYER_REGEN_ENABLED")
tev:SetScript("OnEvent", function() P.ShowNextToast() end)
