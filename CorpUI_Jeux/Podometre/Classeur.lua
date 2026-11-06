--[[--------------------------------------------------------------------------
    CorpUI - podometre : le classeur (fenetre a quatre onglets) et l annonce
      - Classeur : pages de 4 x 2 cartes, filtres serie / rarete, carte en
        grand a droite (fabrication avec les eclats) ; classeur d un joueur
        de la guilde en lecture seule ;
      - Boosters : boosters en attente, ouverture animee (cartes retournees
        une a une, son selon la rarete, "Nouveau !" ou eclats du doublon) ;
      - Statistiques : jour, semaine, mois, annee, total (prochain palier),
        facons de se deplacer, record, 30 derniers jours, personnages,
        equivalence reelle ;
      - Guilde : classement de la semaine des joueurs CorpUI.
    Images (Media\Podometre, Nano Banana) : cadre argente a bandeau, passe en
    gris et teinte selon la rarete, parchemin du cartouche, dos de carte,
    booster ; chaton du niveau et halo dessines par make_cadre.js. Carte :
    l image en haut (creature en 3D sur son decor), le nom sur le bandeau,
    le type et la rarete sur le parchemin, le niveau dans le chaton. Une
    carte legendaire retournee fait son entree en grand.
    Aucune action protegee : la fenetre s ouvre aussi en combat.
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local C = ns.COLORS

ns.Pedo = ns.Pedo or {}
local P = ns.Pedo

local MEDIA = ns.MEDIA .. "Podometre\\"
-- mesures des images (make_cadre.js) : fractions de la carte
local RATIO = 1.2977                     -- hauteur / largeur d une carte (rubans compris)
local ART = { l = 0.1248, r = 0.8739, t = 0.0638, b = 0.5328 }      -- fenetre de l image
local RIBBON = { l = 0.1248, r = 0.8739, t = 0.5328, b = 0.6494 }   -- bandeau du nom
local PANEL = { l = 0.1248, r = 0.8739, t = 0.6494, b = 0.9149 }    -- cartouche (parchemin)
local GEM = { x = 0.1717, y = 0.1064, d = 0.1369 }                  -- chaton du niveau
local HALO = { pad = 0.15, tex = 0.6489 }   -- marge de chaque cote, hauteur utile de l image
local TEX_FRAME, TEX_BACK, TEX_PACK, TEX_PARCH = 332 / 512, 363 / 512, 392 / 512, 191 / 256
local PACK_RATIO = 1.5325
local ART_ASPECT = (ART.r - ART.l) / ((ART.b - ART.t) * RATIO)       -- largeur / hauteur
-- ecran de chargement (4:3) dans la fenetre : le milieu, sur toute la hauteur
local SCENE_U = math.max(0, (1 - ART_ASPECT / (4 / 3)) / 2)
-- tuiles de zone (2 x 2, un carre) : rognees en haut et en bas (fenetre plus
-- large que haute), sinon sur les cotes
local TILE_CUT_V = ART_ASPECT >= 1 and (1 - 1 / ART_ASPECT) or 0
local TILE_CUT_U = ART_ASPECT < 1 and (1 - ART_ASPECT) or 0
-- parchemin (1200 x 896) dans le cartouche, bien plus large : le milieu
local PARCH_H = (1200 / 896) / ((PANEL.r - PANEL.l) / ((PANEL.b - PANEL.t) * RATIO))
local PARCH_V0, PARCH_V1 = (1 - PARCH_H) / 2 * TEX_PARCH, (1 + PARCH_H) / 2 * TEX_PARCH
local INK = { 0.25, 0.17, 0.09 }   -- encre du parchemin
-- camera des modeles 3D : recul (1 = cadrage du jeu), rotation (radians)
local MODEL_DIST, MODEL_FACING = 1.05, 0.35

local WIN_W, WIN_H = 780, 540
local GRID_COLS, GRID_ROWS = 4, 2
local PER_PAGE = GRID_COLS * GRID_ROWS
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
    -- cartouche : parchemin
    local pl, pt, pw, ph = box(PANEL)
    c.parch = c:CreateTexture(nil, "BORDER")
    c.parch:SetPoint("TOPLEFT", pl, -pt)
    c.parch:SetSize(pw, ph)
    c.parch:SetTexture(MEDIA .. "parchemin")
    c.parch:SetTexCoord(0, 1, PARCH_V0, PARCH_V1)
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
    -- cadre (image argentee, teintee) ; le chaton dessous, dans son anneau
    c.frame = c.over:CreateTexture(nil, "OVERLAY")
    c.frame:SetAllPoints()
    c.frame:SetTexture(MEDIA .. "cadre2")
    c.frame:SetTexCoord(0, 1, 0, TEX_FRAME)
    local gd = math.floor(w * GEM.d * 0.92 + 0.5)
    c.gem = c.over:CreateTexture(nil, "ARTWORK")
    c.gem:SetSize(gd, gd)
    c.gem:SetPoint("CENTER", c, "TOPLEFT", w * GEM.x, -h * GEM.y)
    c.gem:SetTexture(MEDIA .. "gemme")
    c.lvl = text(c.over, "GameFontHighlightSmall", math.max(7, math.floor(gd * 0.48 + 0.5)), "OUTLINE")
    c.lvl:SetPoint("CENTER", c.gem, "CENTER", 0, 0)
    -- nom : sur le bandeau, une ligne
    local fsz = math.max(8, math.floor(w / 11 + 0.5))
    local rl, rt, rw, rh = box(RIBBON)
    c.name = text(c.over, "GameFontHighlightSmall", fsz, "OUTLINE")
    c.name:SetPoint("TOPLEFT", c, "TOPLEFT", rl + 2, -rt)
    c.name:SetSize(rw - 4, rh)
    c.name:SetJustifyH("CENTER")
    c.name:SetJustifyV("MIDDLE")
    pcall(c.name.SetWordWrap, c.name, false)
    -- cartouche : type (ou serie), rarete, numero ; encre sur le parchemin
    local psz = math.max(7, math.floor(w / 14 + 0.5))
    c.sub = text(c.over, "GameFontNormalSmall", psz)
    c.sub:SetPoint("TOP", c, "TOPLEFT", pl + pw / 2, -(pt + math.floor(ph * 0.16 + 0.5)))
    c.sub:SetWidth(pw - 6)
    pcall(c.sub.SetWordWrap, c.sub, false)
    c.sub:SetTextColor(INK[1], INK[2], INK[3])
    c.rar = text(c.over, "GameFontNormalSmall", psz)
    c.rar:SetPoint("TOP", c.sub, "BOTTOM", 0, -2)
    c.rar:SetWidth(pw - 6)
    c.num = text(c.over, "GameFontNormalSmall", math.max(6, psz - 1))
    c.num:SetPoint("BOTTOMRIGHT", c, "TOPLEFT", pl + pw - 3, -(pt + ph - 2))
    c.num:SetTextColor(INK[1] + 0.25, INK[2] + 0.2, INK[3] + 0.15)
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
    -- carte manquante : une case vide, son numero et ou la trouver
    c.slot = c:CreateTexture(nil, "BORDER")
    c.slot:SetAllPoints()
    c.slot:SetTexture(MEDIA .. "case")
    c.slot:SetTexCoord(0, 1, 0, TEX_FRAME)
    c.slotNum = text(c, "GameFontNormalHuge", math.max(10, math.floor(w / 6 + 0.5)))
    c.slotNum:SetPoint("CENTER", c, "TOP", 0, -h * 0.38)
    c.slotNum:SetTextColor(0.62, 0.5, 0.3, 0.55)
    c.slotHint = text(c, "GameFontNormalSmall", math.max(7, math.floor(w / 12 + 0.5)))
    c.slotHint:SetPoint("TOP", c.slotNum, "BOTTOM", 0, -math.floor(h * 0.06 + 0.5))
    c.slotHint:SetWidth(w - 18)
    c.slotHint:SetTextColor(0.6, 0.53, 0.42, 0.75)
    c.empty = { c.slot, c.slotNum, c.slotHint }
    -- face d une carte possedee
    c.face = { c.artBg, c.parch, c.frame, c.gem, c.lvl, c.name, c.sub, c.rar, c.num, c.shadow }
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

-- face ou case vide
local function setFace(card, on)
    for _, r in ipairs(card.face) do r:SetShown(on) end
    for _, r in ipairs(card.empty) do r:SetShown(not on) end
end

-- nom sur le bandeau : la taille baisse jusqu a ce qu il tienne
local function fitName(card, s)
    card.name:SetText(s)
    local size = card.nameSize
    font(card.name, size, "OUTLINE")
    while size > 7 and (card.name:GetStringWidth() or 0) > card.nameW do
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
    card.glow:Hide()
    card.dim:Hide()
    card.qmark:Hide()
    card.new:Hide()
end

-- carte manquante : une case vide, son numero, et ou la trouver (le lieu
-- d une creature, sinon la serie)
local function paintEmpty(card, c)
    clearArt(card)
    setFace(card, false)
    card.slotNum:SetText("#" .. (c.num or c.index))
    card.slotHint:SetText(c.disp and P.CardPlace(c) or (L["PEDO_SERIES_" .. string.upper(c.s)] or ""))
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
        card.scene:SetTexCoord(SCENE_U, 1 - SCENE_U, 0, 1)
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
    card.gem:SetVertexColor(col[1], col[2], col[3])
    fitName(card, P.CardName(c))
    card.name:SetTextColor(1, 1, 1)
    -- cartouche : le type d une creature, sinon la serie ; puis la rarete,
    -- dans sa couleur assombrie (lisible sur le parchemin)
    card.sub:SetText(c.disp and P.CardTypeName(c) or (L["PEDO_SERIES_" .. string.upper(c.s)] or ""))
    card.rar:SetText(L["PEDO_R" .. c.r] or "")
    card.rar:SetTextColor(col[1] * 0.7, col[2] * 0.7, col[3] * 0.7)
    card.lvl:SetText(c.disp and ((c.lvl or 0) >= 63 and "??" or tostring(c.lvl or "")) or "")
    card.num:SetText("#" .. (c.num or c.index))
    card.new:SetShown(isNew and true or false)
    if c.r >= 4 then
        card.glow:SetVertexColor(col[1], col[2], col[3])
        card.glow:SetAlpha(0.75)
        card.glow:Show()
    end
end

-- face cachee (booster) : rien ne trahit la carte autour du dos, ni le
-- halo (il depasse du dos), ni le cadre et le chaton teintes (coins et
-- rubans du dos) ; la vraie face n est peinte qu au retournement
local function paintFaceDown(card, c)
    card.card = c
    if not c then card:Hide() return end
    card:Show()
    clearArt(card)
    setFace(card, true)
    card.artBg:SetColorTexture(0.12, 0.1, 0.16, 1)
    card.frame:SetVertexColor(0.38, 0.38, 0.4)
    card.gem:SetVertexColor(0.4, 0.4, 0.42)
    card.name:SetText("")
    card.lvl:SetText("")
    card.sub:SetText("")
    card.rar:SetText("")
    card.num:SetText("")
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

-- habillage propre au classeur (pas le cadre commun de CorpUI) : fond chaud,
-- filets dores a losanges, titres dans la police des quetes du jeu
local GOLD = { 0.86, 0.69, 0.38 }
local TAB_ON, TAB_OFF, TAB_HOVER = { 1, 0.84, 0.5 }, { 0.62, 0.56, 0.46 }, { 0.92, 0.85, 0.7 }
local LATIN = { enUS = true, enGB = true, frFR = true, deDE = true, esES = true, esMX = true, ptBR = true, itIT = true }

-- titre : Morpheus (police des quetes) ; elle n a que l alphabet latin
local function titleFont(fs, size)
    local ok, set = false, nil
    if LATIN[GetLocale()] then ok, set = pcall(fs.SetFont, fs, "Fonts\\MORPHEUS.TTF", size, "") end
    if not ok or set == false then ns.UI.HeadFont(fs, size - 4) end
end

local function diamond(parent, size, a)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetSize(size, size)
    t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], a or 1)
    pcall(t.SetRotation, t, math.pi / 4)
    return t
end

-- filet dore horizontal, plus vif au milieu (losange), qui s eteint aux bouts
local function fadeLine(parent, y, x0, x1)
    local half = (x1 - x0) / 2 - 7
    for side = 0, 1 do
        local l = parent:CreateTexture(nil, "BORDER")
        l:SetColorTexture(1, 1, 1, 1)
        l:SetSize(half, 1)
        l:SetPoint("TOPLEFT", parent, "TOPLEFT", side == 0 and x0 or (x1 - half), y)
        local dim, lit = CreateColor and CreateColor(GOLD[1], GOLD[2], GOLD[3], 0), CreateColor and CreateColor(GOLD[1], GOLD[2], GOLD[3], 0.75)
        if not (dim and pcall(l.SetGradient, l, "HORIZONTAL", side == 0 and dim or lit, side == 0 and lit or dim)) then
            l:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.4)
        end
    end
    diamond(parent, 6, 0.9):SetPoint("CENTER", parent, "TOPLEFT", (x0 + x1) / 2, y - 0.5)
end

-- fond et liseré de la fenetre
local function dress(f)
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetTexture(MEDIA .. "fond")
    local function edge(x0, y0, x1, y1, r, g, b, a)
        local t = f:CreateTexture(nil, "BORDER")
        t:SetColorTexture(r, g, b, a)
        t:SetPoint("TOPLEFT", f, "TOPLEFT", x0, -y0)
        t:SetPoint("BOTTOMRIGHT", f, "TOPLEFT", x1, -y1)
    end
    local w, h = f:GetWidth(), f:GetHeight()
    -- bord noir, puis filet dore en retrait
    edge(0, 0, w, 1, 0, 0, 0, 1) edge(0, h - 1, w, h, 0, 0, 0, 1)
    edge(0, 0, 1, h, 0, 0, 0, 1) edge(w - 1, 0, w, h, 0, 0, 0, 1)
    local i = 5
    edge(i, i, w - i, i + 1, GOLD[1], GOLD[2], GOLD[3], 0.7) edge(i, h - i - 1, w - i, h - i, GOLD[1], GOLD[2], GOLD[3], 0.7)
    edge(i, i, i + 1, h - i, GOLD[1], GOLD[2], GOLD[3], 0.7) edge(w - i - 1, i, w - i, h - i, GOLD[1], GOLD[2], GOLD[3], 0.7)
    for _, p in ipairs({ { i, i }, { w - i, i }, { i, h - i }, { w - i, h - i } }) do
        diamond(f, 7):SetPoint("CENTER", f, "TOPLEFT", p[1] + 0.5, -p[2] - 0.5)
    end
end

local function paintTab(t, hover)
    local on = t.key == current
    local c = on and TAB_ON or (hover and TAB_HOVER or TAB_OFF)
    t.label:SetTextColor(c[1], c[2], c[3])
    t.line:SetShown(on)
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
-- Onglet Classeur
---------------------------------------------------------------------------

local B = { series = "all", rarity = 0, page = 1, sel = nil }
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

local function buildBinder(page)
    local p = page
    p.series = ns.UI.Select(p, 160, function()
        local list = { { value = "all", text = L.PEDO_ALL_SERIES } }
        for _, s in ipairs(P.SERIES) do list[#list + 1] = { value = s, text = L["PEDO_SERIES_" .. string.upper(s)] } end
        return list
    end, function() return B.series end, function(v) B.series = v B.page = 1 B.sel = nil end, function() refreshPage() end)
    p.series:SetPoint("TOPLEFT", 12, -6)
    p.rarity = ns.UI.Select(p, 140, function()
        local list = { { value = 0, text = L.PEDO_ALL_RARITIES } }
        for r = 1, 5 do list[#list + 1] = { value = r, text = L["PEDO_R" .. r] } end
        return list
    end, function() return B.rarity end, function(v) B.rarity = v B.page = 1 B.sel = nil end, function() refreshPage() end)
    p.rarity:SetPoint("LEFT", p.series, "RIGHT", 8, 0)
    p.count = text(p, "GameFontNormal")
    p.count:SetPoint("LEFT", p.rarity, "RIGHT", 14, 3)
    p.count:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    -- avancement de la collection (filtres en cours) : un filet dore
    p.progress = CreateFrame("StatusBar", nil, p)
    p.progress:SetSize(150, 3)
    p.progress:SetPoint("TOPLEFT", p.count, "BOTTOMLEFT", 0, -3)
    p.progress:SetStatusBarTexture(ns.BAR_TEXTURE)
    p.progress:SetStatusBarColor(GOLD[1], GOLD[2], GOLD[3])
    p.progress:SetMinMaxValues(0, 1)
    local pbg = p.progress:CreateTexture(nil, "BACKGROUND")
    pbg:SetAllPoints()
    pbg:SetColorTexture(0, 0, 0, 0.6)
    -- classeur d un autre joueur : bandeau
    p.viewing = text(p, "GameFontNormal")
    p.viewing:SetPoint("TOPRIGHT", p, "TOPRIGHT", -150, -10)
    p.back = ns.UI.Button(p, L.PEDO_MY_BINDER, 130, function() view = nil B.page = 1 B.sel = nil refreshPage() end)
    p.back:SetPoint("TOPRIGHT", p, "TOPRIGHT", -12, -6)
    -- grille
    p.cards = {}
    for i = 1, PER_PAGE do
        local card = newCard(p, 112)
        local col, row = (i - 1) % GRID_COLS, math.floor((i - 1) / GRID_COLS)
        card:SetPoint("TOPLEFT", p, "TOPLEFT", 18 + col * 128, -44 - row * 168)
        card:SetScript("OnEnter", cardTooltip)
        card:SetScript("OnLeave", ns.HideTooltip)
        card:SetScript("OnClick", function(self)
            B.sel = self.card and self.card.id
            refreshPage()
        end)
        p.cards[i] = card
    end
    p.prev = ns.UI.Button(p, "<", 30, function() B.page = B.page - 1 refreshPage() end)
    p.prev:SetPoint("TOPLEFT", p, "TOPLEFT", 160, -384)
    p.pageText = text(p, "GameFontHighlight")
    p.pageText:SetPoint("LEFT", p.prev, "RIGHT", 10, 0)
    p.pageText:SetWidth(110)
    p.pageText:SetTextColor(TAB_HOVER[1], TAB_HOVER[2], TAB_HOVER[3])
    p.next = ns.UI.Button(p, ">", 30, function() B.page = B.page + 1 refreshPage() end)
    p.next:SetPoint("LEFT", p.pageText, "RIGHT", 10, 0)
    -- carte en grand
    p.big = newCard(p, 168)
    p.big:SetPoint("TOPLEFT", p, "TOPLEFT", 556, -40)
    p.big:SetScript("OnEnter", cardTooltip)
    p.big:SetScript("OnLeave", ns.HideTooltip)
    p.bigName = text(p, "GameFontNormalLarge")
    titleFont(p.bigName, 18)
    p.bigName:SetShadowOffset(1, -1)
    p.bigName:SetPoint("TOP", p.big, "BOTTOM", 0, -10)
    p.bigName:SetWidth(240)
    p.bigInfo = text(p, "GameFontHighlightSmall")
    p.bigInfo:SetPoint("TOP", p.bigName, "BOTTOM", 0, -4)
    p.bigInfo:SetWidth(240)
    p.bigInfo:SetTextColor(TAB_HOVER[1], TAB_HOVER[2], TAB_HOVER[3])
    p.bigHint = text(p, "GameFontDisableSmall")
    p.bigHint:SetPoint("TOP", p.bigInfo, "BOTTOM", 0, -4)
    p.bigHint:SetWidth(240)
    p.craft = ns.UI.Button(p, "", 200, function()
        if B.sel and P.Craft(B.sel) then
            P.Sound("f_ding")
            refreshPage()
        end
    end)
    p.craft:SetPoint("TOP", p.bigHint, "BOTTOM", 0, -8)
end

local function refreshBinder(p)
    local list = P.Cards(B.series, B.rarity)
    local pagesN = math.max(1, math.ceil(#list / PER_PAGE))
    B.page = math.max(1, math.min(B.page, pagesN))
    -- autre page (ou autre filtre) : les cartes nouvelles d avant sont vues
    local key = B.series .. ":" .. B.rarity .. ":" .. B.page .. ":" .. (view and view.name or "")
    if key ~= shownKey then forgetNew() shownKey = key end
    -- listes deroulantes : le choix en cours s affiche a la demande
    p.series:Refresh()
    p.rarity:Refresh()
    local own = 0
    for _, c in ipairs(list) do if ownedHere(c.id) then own = own + 1 end end
    p.count:SetText(string.format(L.PEDO_COUNT, own, #list, #list > 0 and math.floor(own / #list * 100 + 0.5) or 0))
    p.progress:SetValue(#list > 0 and own / #list or 0)
    p.viewing:SetShown(view ~= nil)
    p.back:SetShown(view ~= nil)
    if view then p.viewing:SetText(string.format(L.PEDO_VIEWING, shortName(view.name))) end
    local first = (B.page - 1) * PER_PAGE
    local d = db()
    for i, card in ipairs(p.cards) do
        local c = list[first + i]
        local owned = c and ownedHere(c.id) or false
        card.owned = owned
        local isNew = c and not view and d and d.newCards[c.id] or false
        if isNew then shownNew[c.id] = true end
        paintCard(card, c, owned, isNew)
    end
    p.pageText:SetText(string.format(L.PEDO_PAGE, B.page, pagesN))
    p.prev:SetEnabled(B.page > 1)
    p.next:SetEnabled(B.page < pagesN)
    -- carte en grand : la choisie, sinon la premiere de la page
    local sel = B.sel and P.byId[B.sel]
    if not sel or not P.IsValid(sel.id) then sel = list[first + 1] end
    if not sel then
        p.big:Hide() p.bigName:SetText("") p.bigInfo:SetText("") p.bigHint:SetText("") p.craft:Hide()
        return
    end
    local owned = ownedHere(sel.id)
    p.big.owned = owned
    paintCard(p.big, sel, owned, false)
    local col = rarityRGB(sel.r)
    p.bigName:SetText(owned and P.CardName(sel) or L.PEDO_MISSING)
    p.bigName:SetTextColor(col[1], col[2], col[3])
    p.bigInfo:SetText(L["PEDO_SERIES_" .. string.upper(sel.s)] .. " · " .. L["PEDO_R" .. sel.r] ..
        " · #" .. (sel.num or sel.index) .. "/" .. ((P.seriesCount and P.seriesCount[sel.s]) or "?"))
    local hint = P.CardHint(sel)
    if not hint and not owned and sel.s ~= "trophees" then hint = L.PEDO_MISSING_HINT end
    -- creature : ou la trouver, puis (si on l a) niveau et type
    if sel.disp then
        hint = "|cffffd100" .. P.CardPlace(sel) .. "|r\n" .. (owned and P.CardCreatureInfo(sel) or hint or "")
    end
    p.bigHint:SetText(hint or "")
    if not view and not owned and sel.s ~= "trophees" then
        p.craft:SetText(string.format(L.PEDO_CRAFT, P.CRAFT[sel.r]))
        p.craft:SetEnabled(P.CanCraft(sel.id))
        p.craft:Show()
    else
        p.craft:Hide()
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
                card.num:SetAlpha(0)
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
                    card.num:SetAlpha(1)
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
            B.page, B.sel = 1, nil
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
    dress(win)
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
    titleFont(title, 21)
    title:SetPoint("LEFT", 18, -3)
    title:SetTextColor(TAB_ON[1], TAB_ON[2], TAB_ON[3])
    title:SetShadowOffset(1, -1)
    title:SetText(L.PEDO_BINDER)
    local close = CreateFrame("Button", nil, bar)
    close:SetSize(22, 22)
    close:SetPoint("RIGHT", -10, -2)
    local x = close:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    x:SetPoint("CENTER")
    x:SetText("×")
    x:SetTextColor(TAB_OFF[1], TAB_OFF[2], TAB_OFF[3])
    close:SetScript("OnEnter", function() x:SetTextColor(TAB_ON[1], TAB_ON[2], TAB_ON[3]) end)
    close:SetScript("OnLeave", function() x:SetTextColor(TAB_OFF[1], TAB_OFF[2], TAB_OFF[3]) end)
    close:SetScript("OnClick", function() win:Hide() end)
    win.shards = text(bar, "GameFontNormal")
    win.shards:SetPoint("RIGHT", close, "LEFT", -12, 0)
    win.shards:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    -- onglets : du texte souligne d or quand il est choisi ; puis un filet
    fadeLine(win, -61, 16, WIN_W - 16)
    for i, key in ipairs({ "binder", "packs", "stats", "guild" }) do
        local t = CreateFrame("Button", nil, win)
        t:SetSize(140, 26)
        t:SetPoint("TOPLEFT", win, "TOPLEFT", 16 + (i - 1) * 146, -33)
        t.label = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        font(t.label, 13)
        t.label:SetPoint("CENTER", 0, 1)
        t:SetFontString(t.label)
        t.line = t:CreateTexture(nil, "ARTWORK")
        t.line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
        t.line:SetHeight(2)
        t.line:SetPoint("BOTTOMLEFT", 24, 0)
        t.line:SetPoint("BOTTOMRIGHT", -24, 0)
        t.key = key
        t:SetText(tabLabel(key))
        t:SetScript("OnClick", function() selectTab(key) end)
        t:SetScript("OnEnter", function(self) paintTab(self, true) end)
        t:SetScript("OnLeave", function(self) paintTab(self, false) end)
        paintTab(t)
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
