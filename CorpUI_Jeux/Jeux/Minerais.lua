--[[--------------------------------------------------------------------------
    CorpUI - module Jeux : la fusion des minerais

    Le 2048 facon mineur : sur une grille de 4 x 4, tout glisse d un cote ;
    deux minerais pareils qui se rencontrent fusionnent en celui du dessus :
    cuivre, etain, argent, fer, or, mithril, vrai-argent, sombrefer, thorium,
    arcanite, elementium (le "2048" : victoire), puis Sulfuras et
    Thunderfury (noms lus sur le client). Une case nouvelle (cuivre,
    parfois etain) a chaque coup.
      - fleches, ZQSD / WASD (reglage) ou glisser la souris sur la grille ;
        Retour arriere : annuler (3 fois par partie) ; Echap : fermer ;
      - la partie est gardee (fermer, /reload, vol suivant) ;
      - icones et noms : ceux des objets du jeu (aucune image a nous) ;
      - en combat : clavier rendu au jeu, la souris marche toujours (jeu au
        tour par tour : pas de pause) ;
      - sons de CorpUI : ding a chaque nouveau minerai (des l or), carillon a
        la victoire ou au record, trombone triste a la fin.
    Fenetre a nous, deplacable ; rien de Blizzard n est touche.
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local C = ns.COLORS

local SOUNDS = ns.MEDIA .. "Sons\\"

local N = 4
local TILE, GAP = 64, 8
local BOARD = N * TILE + (N + 1) * GAP    -- 296
local WIN_W, WIN_H = BOARD + 24, 440
local SLIDE, POP = 0.10, 0.14             -- duree du glissement, du gonflement
local UNDOS = 3
local WIN_TIER = 11                       -- l elementium : le "2048"
local STRIP = 20                          -- icones de la progression

-- paliers : objets du jeu (icone et nom lus sur le client)
local TIERS = {
    2770,   -- minerai de cuivre
    2771,   -- minerai d etain
    2775,   -- minerai d argent
    2772,   -- minerai de fer
    2776,   -- minerai d or
    3858,   -- minerai de mithril
    7911,   -- minerai de vrai-argent
    11370,  -- minerai de sombrefer
    10620,  -- minerai de thorium
    12360,  -- lingot d arcanite
    18562,  -- minerai d elementium (victoire)
    17182,  -- Sulfuras, main de Ragnaros
    19019,  -- Tonnerre-fury, lame benie du Cherchevent
}
local VALUE = {}
do local v = 1; for k = 1, 30 do v = v * 2; VALUE[k] = v end end

-- liseré par palier : les qualites du jeu, de gris a artefact
local function tierColor(k)
    if k <= 1 then return 0.62, 0.62, 0.62 end
    if k == 2 then return 1, 1, 1 end
    if k <= 4 then return 0.12, 1, 0 end
    if k <= 6 then return 0, 0.44, 0.87 end
    if k <= 9 then return 0.64, 0.21, 0.93 end
    if k <= WIN_TIER then return 1, 0.5, 0 end
    return 0.9, 0.8, 0.5
end

local function itemOf(k) return TIERS[math.max(1, math.min(k, #TIERS))] end

local function clean(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) and v or nil end

local icons = {}
local function iconOf(k)
    local id = itemOf(k)
    if icons[id] then return icons[id] end
    local tex
    if C_Item and C_Item.GetItemIconByID then
        local ok, v = pcall(C_Item.GetItemIconByID, id)
        if ok then tex = clean(v) end
    end
    if not tex and GetItemIcon then
        local ok, v = pcall(GetItemIcon, id)
        if ok then tex = clean(v) end
    end
    if tex then icons[id] = tex return tex end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- nom colore ; pas encore en cache : "#k" et demande au serveur
local function nameOf(k)
    local id = itemOf(k)
    local name
    if C_Item and C_Item.GetItemNameByID then
        local ok, v = pcall(C_Item.GetItemNameByID, id)
        if ok then name = clean(v) end
    end
    if not name and GetItemInfo then
        local ok, v = pcall(GetItemInfo, id)
        if ok then name = clean(v) end
    end
    if type(name) ~= "string" or name == "" then
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
        name = "#" .. k
    end
    local r, g, b = tierColor(k)
    return string.format("|cff%02x%02x%02x%s|r", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), name)
end

local db
local win, board, overlay, hud, strip
local tiles, used = {}, 0
local anim
-- cells : N*N paliers (0 = vide) ; top : meilleur palier de la partie
local st = { cells = {}, score = 0, undos = UNDOS, won = false, cont = false, over = false, top = 0, startBest = 0 }
for i = 1, N * N do st.cells[i] = 0 end

local function play(file)
    if db and db.sound then pcall(PlaySoundFile, SOUNDS .. file .. ".ogg", "Master") end
end

---------------------------------------------------------------------------
-- Regles
---------------------------------------------------------------------------

local function idx(r, c) return (r - 1) * N + c end
local function inside(r, c) return r >= 1 and r <= N and c >= 1 and c <= N end

local function topTier()
    local t = 0
    for i = 1, N * N do t = math.max(t, st.cells[i]) end
    return t
end

local function addRandom()
    local free = {}
    for i = 1, N * N do if st.cells[i] == 0 then free[#free + 1] = i end end
    if #free == 0 then return nil end
    local i = free[math.random(#free)]
    st.cells[i] = math.random() < 0.9 and 1 or 2
    return i
end

local function canMove()
    for r = 1, N do
        for c = 1, N do
            local k = st.cells[idx(r, c)]
            if k == 0 then return true end
            if c < N and st.cells[idx(r, c + 1)] == k then return true end
            if r < N and st.cells[idx(r + 1, c)] == k then return true end
        end
    end
    return false
end

-- glissement : on part du bord vise ; une case ne fusionne qu une fois par
-- coup. Rend : bouge ?, glissements { palier, r, c, r2, c2 }, fusions
-- (index des cases nees d une fusion), points gagnes
local VEC = { left = { 0, -1 }, right = { 0, 1 }, up = { -1, 0 }, down = { 1, 0 } }
local function slide(dir)
    local dr, dc = VEC[dir][1], VEC[dir][2]
    local cells = st.cells
    local merged, slides, pops = {}, {}, {}
    local gained, moved = 0, false
    local r1, r2, rs = 1, N, 1
    if dr == 1 then r1, r2, rs = N, 1, -1 end
    local c1, c2, cs = 1, N, 1
    if dc == 1 then c1, c2, cs = N, 1, -1 end
    for r = r1, r2, rs do
        for c = c1, c2, cs do
            local k = cells[idx(r, c)]
            if k > 0 then
                local pr, pc = r, c
                while inside(pr + dr, pc + dc) and cells[idx(pr + dr, pc + dc)] == 0 do
                    pr, pc = pr + dr, pc + dc
                end
                local nr, nc = pr + dr, pc + dc
                local j = inside(nr, nc) and idx(nr, nc)
                if j and cells[j] == k and not merged[j] then
                    cells[idx(r, c)] = 0
                    cells[j] = k + 1
                    merged[j] = true
                    pops[#pops + 1] = j
                    gained = gained + VALUE[k + 1]
                    slides[#slides + 1] = { k, r, c, nr, nc }
                    moved = true
                else
                    if pr ~= r or pc ~= c then
                        cells[idx(r, c)] = 0
                        cells[idx(pr, pc)] = k
                        moved = true
                    end
                    slides[#slides + 1] = { k, r, c, pr, pc }
                end
            end
        end
    end
    return moved, slides, pops, gained
end

local function copyCells(src)
    local t = {}
    for i = 1, N * N do t[i] = src[i] end
    return t
end

local function save()
    if not db then return end
    db.save = {
        cells = copyCells(st.cells), score = st.score, undos = st.undos, won = st.won, cont = st.cont,
        over = st.over, startBest = st.startBest,
        prev = st.prev and { cells = copyCells(st.prev.cells), score = st.prev.score } or nil,
    }
end

local function validCells(t)
    if type(t) ~= "table" then return false end
    for i = 1, N * N do
        if type(t[i]) ~= "number" or t[i] < 0 or t[i] > 30 then return false end
    end
    return true
end

-- partie gardee (rend false si rien de valable)
local function load()
    local s = db and db.save
    if type(s) ~= "table" or not validCells(s.cells) or type(s.score) ~= "number" then return false end
    st.cells = copyCells(s.cells)
    st.score = s.score
    st.undos = type(s.undos) == "number" and s.undos or 0
    st.won, st.cont, st.over = s.won and true or false, s.cont and true or false, s.over and true or false
    st.startBest = type(s.startBest) == "number" and s.startBest or (db.best or 0)
    st.prev = type(s.prev) == "table" and validCells(s.prev.cells) and { cells = copyCells(s.prev.cells), score = s.prev.score or 0 } or nil
    st.top = topTier()
    return st.top > 0
end

local refresh, drawFinal

local function newGame()
    for i = 1, N * N do st.cells[i] = 0 end
    st.score, st.undos, st.won, st.cont, st.over, st.prev = 0, UNDOS, false, false, false, nil
    st.startBest = db.best or 0
    addRandom()
    addRandom()
    st.top = topTier()
    db.games = (db.games or 0) + 1
    anim = nil
    save()
    if win then drawFinal() refresh() end
end

local function finishAnim()
    if anim then
        anim = nil
        drawFinal()
    end
end

-- un coup ; rend true s il a fait bouger quelque chose
local function doMove(dir)
    if not db or not VEC[dir] or st.over or (st.won and not st.cont) then return false end
    finishAnim()
    local before = { cells = copyCells(st.cells), score = st.score }
    local moved, slides, pops, gained = slide(dir)
    if not moved then return false end
    st.prev = before
    st.score = st.score + gained
    local spawn = addRandom()
    local popSet = {}
    for _, j in ipairs(pops) do popSet[j] = true end
    anim = { t = 0, slides = slides, popSet = popSet, spawn = spawn }
    if st.score > (db.best or 0) then db.best = st.score end
    local top = topTier()
    if top > st.top then
        st.top = top
        if top > (db.bestTier or 0) then db.bestTier = top end
        if top >= WIN_TIER and not st.won then
            st.won = true
            db.wins = (db.wins or 0) + 1
            play("carillon")
        elseif top >= 5 then
            play("ding")
        end
    end
    if not canMove() then
        st.over = true
        if not (st.won and not st.cont) then
            play(st.score > (st.startBest or 0) and "carillon" or "trombone")
        end
    end
    save()
    if win then refresh() end
    return true
end

local function undo()
    if not st.prev or st.undos <= 0 then return false end
    finishAnim()
    st.cells = copyCells(st.prev.cells)
    st.score = st.prev.score
    st.prev = nil
    st.undos = st.undos - 1
    st.over = false
    if st.won then st.cont = true end
    st.top = topTier()
    save()
    if win then drawFinal() refresh() end
    return true
end

---------------------------------------------------------------------------
-- Dessin
---------------------------------------------------------------------------

-- centre d une case, depuis le coin haut gauche de la grille
local function cellPos(r, c)
    return GAP + (c - 1) * (TILE + GAP) + TILE / 2, -(GAP + (r - 1) * (TILE + GAP) + TILE / 2)
end

local function newTile()
    local f = CreateFrame("Frame", nil, board)
    f.edge = f:CreateTexture(nil, "BACKGROUND")
    f.edge:SetAllPoints()
    local inner = f:CreateTexture(nil, "BORDER")
    inner:SetPoint("TOPLEFT", 2, -2)
    inner:SetPoint("BOTTOMRIGHT", -2, 2)
    inner:SetColorTexture(0.07, 0.07, 0.09, 1)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("TOPLEFT", 5, -5)
    f.icon:SetPoint("BOTTOMRIGHT", -5, 5)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.val = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    f.val:SetPoint("BOTTOMRIGHT", -4, 4)
    return f
end

local function put(k, x, y, s)
    used = used + 1
    local f = tiles[used]
    if not f then
        f = newTile()
        tiles[used] = f
    end
    local size = TILE * (s or 1)
    f:SetSize(size, size)
    f:ClearAllPoints()
    f:SetPoint("CENTER", board, "TOPLEFT", x, y)
    if f.tier ~= k then
        f.tier = k
        local r, g, b = tierColor(k)
        f.edge:SetColorTexture(r, g, b, 1)
        f.icon:SetTexture(iconOf(k))
        f.val:SetText(VALUE[k] or "")
    end
    f:Show()
end

local function hideRest()
    for j = used + 1, #tiles do tiles[j]:Hide() end
end

function drawFinal(popScale, spawnScale)
    if not board then return end
    used = 0
    for r = 1, N do
        for c = 1, N do
            local i = idx(r, c)
            local k = st.cells[i]
            if k > 0 then
                local x, y = cellPos(r, c)
                local s = 1
                if anim and popScale then
                    if anim.popSet[i] then s = popScale elseif i == anim.spawn then s = spawnScale end
                end
                put(k, x, y, s)
            end
        end
    end
    hideRest()
end

local function animStep(dt)
    if not anim then return end
    anim.t = anim.t + dt
    if anim.t < SLIDE then
        local p = anim.t / SLIDE
        p = 1 - (1 - p) * (1 - p)
        used = 0
        for _, s in ipairs(anim.slides) do
            local x1, y1 = cellPos(s[2], s[3])
            local x2, y2 = cellPos(s[4], s[5])
            put(s[1], x1 + (x2 - x1) * p, y1 + (y2 - y1) * p, 1)
        end
        hideRest()
    elseif anim.t < SLIDE + POP then
        local q = (anim.t - SLIDE) / POP
        drawFinal(1 + 0.18 * math.sin(math.pi * q), 0.3 + 0.7 * q)
    else
        anim = nil
        drawFinal()
        refresh()
    end
end

local function showOverlay(title, line, b1, b2)
    overlay.title:SetText(title)
    overlay.line:SetText(line or "")
    overlay.b1:SetText(b1.text)
    overlay.b1.fn = b1.fn
    overlay.b1:SetWidth(math.max(110, overlay.b1.cuiText:GetStringWidth() + 20))
    if b2 then
        overlay.b2:SetText(b2.text)
        overlay.b2.fn = b2.fn
        overlay.b2:SetWidth(math.max(110, overlay.b2.cuiText:GetStringWidth() + 20))
        overlay.b1:ClearAllPoints()
        overlay.b1:SetPoint("TOPRIGHT", overlay.line, "BOTTOM", -4, -14)
        overlay.b2:Show()
    else
        overlay.b1:ClearAllPoints()
        overlay.b1:SetPoint("TOP", overlay.line, "BOTTOM", 0, -14)
        overlay.b2:Hide()
    end
    overlay:Show()
end

local sureUntil = 0

function refresh()
    if not win then return end
    hud.score:SetText(st.score)
    hud.best:SetText(math.max(db.best or 0, st.score))
    hud.undo:SetText(string.format(L.MIN_UNDO, st.undos))
    hud.undo:SetEnabled(st.prev ~= nil and st.undos > 0)
    hud.new:SetText(GetTime() < sureUntil and L.MIN_SURE or L.MIN_NEW)
    for k, b in ipairs(strip) do
        local got = k <= st.top
        b.icon:SetDesaturated(not got)
        b.icon:SetAlpha(got and 1 or (k <= (db.bestTier or 0) and 0.55 or 0.25))
    end
    if InCombatLockdown() then
        hud.status:SetText(L.MIN_COMBAT)
    else
        hud.status:SetText(string.format(L.MIN_TOP, nameOf(st.top)))
    end
    if anim then return end
    if st.won and not st.cont then
        showOverlay(L.MIN_WIN, string.format(L.MIN_WIN2, nameOf(WIN_TIER)),
            { text = L.MIN_CONTINUE, fn = function() st.cont = true save() refresh() end },
            { text = L.MIN_NEW, fn = function() newGame() end })
    elseif st.over then
        showOverlay(L.MIN_OVER, string.format(L.MIN_OVER2, st.score),
            { text = L.MIN_NEW, fn = function() newGame() end })
    else
        overlay:Hide()
    end
end

---------------------------------------------------------------------------
-- Fenetre
---------------------------------------------------------------------------

local MOVE_KEYS = { UP = "up", DOWN = "down", LEFT = "left", RIGHT = "right" }
local LETTER_KEYS = { Z = "up", W = "up", S = "down", Q = "left", A = "left", D = "right" }

local function setKeyboard(on)
    if not win then return end
    pcall(win.EnableKeyboard, win, on and not InCombatLockdown())
end

local function scoreBox(label, x)
    local f = CreateFrame("Frame", nil, win)
    f:SetSize(84, 44)
    f:SetPoint("TOPLEFT", win, "TOPLEFT", x, -32)
    ns.UI.Skin(f, 0.9)
    local l = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    l:SetPoint("TOP", 0, -5)
    l:SetText(label)
    local v = f:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(v, 16)
    v:SetPoint("BOTTOM", 0, 6)
    v:SetTextColor(1, 1, 1)
    return v
end

local function build()
    db.pos = db.pos or { point = "CENTER", x = 0, y = 40 }
    win = CreateFrame("Frame", "CorpUIMineraisGame", UIParent)
    win:SetSize(WIN_W, WIN_H)
    ns.ApplyPos(win, db.pos)
    win:SetFrameStrata("HIGH")
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    ns.UI.Skin(win, 0.96, true)
    win:SetScale(db.scale or 1)
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
        db.pos = { point = point or "CENTER", x = x or 0, y = y or 0 }
    end)
    local title = bar:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(title, 14)
    title:SetPoint("LEFT", 10, 0)
    title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    title:SetText(L.MIN_TITLE)
    local close = CreateFrame("Button", nil, bar)
    close:SetSize(22, 22)
    close:SetPoint("RIGHT", -4, 0)
    local x = close:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    x:SetPoint("CENTER")
    x:SetText("×")
    close:SetScript("OnClick", function() win:Hide() end)
    -- score, record, boutons
    hud = {}
    hud.score = scoreBox(L.MIN_SCORE, 12)
    hud.best = scoreBox(L.MIN_BEST, 102)
    hud.new = ns.UI.Button(win, L.MIN_NEW, 110, function()
        -- partie en cours : un second clic confirme
        if st.score > 0 and not st.over and GetTime() >= sureUntil then
            sureUntil = GetTime() + 3
            refresh()
            C_Timer.After(3.05, function() if win and win:IsShown() then refresh() end end)
            return
        end
        sureUntil = 0
        newGame()
    end)
    hud.new:SetPoint("TOPRIGHT", win, "TOPRIGHT", -12, -32)
    hud.undo = ns.UI.Button(win, string.format(L.MIN_UNDO, UNDOS), 110, function() undo() end)
    hud.undo:SetPoint("TOPRIGHT", hud.new, "BOTTOMRIGHT", 0, -2)
    -- grille
    board = CreateFrame("Frame", nil, win)
    board:SetSize(BOARD, BOARD)
    board:SetPoint("TOP", win, "TOP", 0, -84)
    local back = board:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(0.03, 0.03, 0.04, 0.9)
    for r = 1, N do
        for c = 1, N do
            local slot = board:CreateTexture(nil, "BORDER")
            slot:SetSize(TILE, TILE)
            local cx, cy = cellPos(r, c)
            slot:SetPoint("CENTER", board, "TOPLEFT", cx, cy)
            slot:SetColorTexture(1, 1, 1, 0.06)
        end
    end
    -- glisser a la souris
    board:EnableMouse(true)
    board:SetScript("OnMouseDown", function(self)
        local cx, cy = GetCursorPosition()
        local s = self:GetEffectiveScale()
        self.downX, self.downY = cx / s, cy / s
    end)
    board:SetScript("OnMouseUp", function(self)
        if not self.downX then return end
        local cx, cy = GetCursorPosition()
        local s = self:GetEffectiveScale()
        local dx, dy = cx / s - self.downX, cy / s - self.downY
        self.downX, self.downY = nil, nil
        if math.max(math.abs(dx), math.abs(dy)) < 20 then return end
        if math.abs(dx) > math.abs(dy) then
            doMove(dx > 0 and "right" or "left")
        else
            doMove(dy > 0 and "up" or "down")
        end
    end)
    board:SetScript("OnUpdate", function(_, dt) animStep(dt) end)
    -- progression : tous les paliers, gris tant qu ils ne sont pas atteints
    strip = {}
    local stripW = #TIERS * STRIP + (#TIERS - 1) * 2
    for k = 1, #TIERS do
        local b = CreateFrame("Button", nil, win)
        b:SetSize(STRIP, STRIP)
        b:SetPoint("TOPLEFT", win, "TOP", -stripW / 2 + (k - 1) * (STRIP + 2), -84 - BOARD - 8)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.icon:SetTexture(iconOf(k))
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            pcall(GameTooltip.SetItemByID, GameTooltip, TIERS[k])
            GameTooltip:AddLine(string.format(L.MIN_TIP, k, VALUE[k]), 1, 0.82, 0)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        strip[k] = b
    end
    hud.status = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hud.status:SetPoint("TOP", win, "TOP", 0, -84 - BOARD - 8 - STRIP - 8)
    hud.status:SetWidth(WIN_W - 24)
    -- fin de partie, victoire
    overlay = CreateFrame("Frame", nil, board)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(board:GetFrameLevel() + 20)
    local shade = overlay:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    shade:SetColorTexture(0, 0, 0, 0.62)
    overlay.title = overlay:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(overlay.title, 22)
    overlay.title:SetPoint("CENTER", 0, 40)
    overlay.title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    overlay.line = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    overlay.line:SetPoint("TOP", overlay.title, "BOTTOM", 0, -10)
    overlay.line:SetWidth(BOARD - 20)
    overlay.b1 = ns.UI.Button(overlay, "", 110, function(self) if self.fn then self.fn() end end)
    overlay.b2 = ns.UI.Button(overlay, "", 110, function(self) if self.fn then self.fn() end end)
    overlay.b2:SetPoint("LEFT", overlay.b1, "RIGHT", 8, 0)
    overlay:Hide()
    -- clavier : seulement les touches de jeu (et Echap) sont gardees
    win:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        local dir = MOVE_KEYS[key] or (db.letters and LETTER_KEYS[key])
        if dir then
            self:SetPropagateKeyboardInput(false)
            doMove(dir)
        elseif key == "BACKSPACE" then
            self:SetPropagateKeyboardInput(false)
            undo()
        elseif key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    win:SetScript("OnKeyUp", function(self)
        if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
    end)
    win:SetScript("OnShow", function()
        setKeyboard(true)
        if st.top == 0 and not load() then newGame() end
        drawFinal()
        refresh()
    end)
    win:SetScript("OnHide", function()
        setKeyboard(false)
        finishAnim()
        save()
    end)
    win:Hide()
end

local function toggle()
    if not db then return end
    if not win then build() end
    win:SetShown(not win:IsShown())
end

-- liste des jeux (ouverture pendant un vol : Jeux.lua)
ns.Games.Register("minerais", {
    title = function() return L.MOD_MINERAIS end,
    open = function()
        if not db then return false end
        if not win then build() end
        win:Show()
        return true
    end,
    close = function() if win then win:Hide() end end,
    shown = function() return win and win:IsShown() or false end,
})

---------------------------------------------------------------------------
-- Reglages (/corp minerais)
---------------------------------------------------------------------------

local panel

local function buildPanel()
    panel = ns.UI.Window("CorpUIMineraisOptions", ns.TITLE .. " - " .. L.MOD_MINERAIS, nil, 440, 400)
    local icon = panel:CreateTexture(nil, "ARTWORK")
    icon:SetSize(64, 64)
    icon:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -40)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetTexture(iconOf(WIN_TIER))
    local desc = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", panel, "TOPLEFT", 92, -40)
    desc:SetWidth(336)
    desc:SetJustifyH("LEFT")
    desc:SetText(L.MIN_HINT)
    local stats = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    stats:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -10)
    stats:SetWidth(336)
    stats:SetJustifyH("LEFT")
    local playBtn = ns.UI.Button(panel, L.MURLOC_PLAY, 120, function() toggle() end)
    playBtn:SetPoint("TOPLEFT", stats, "BOTTOMLEFT", 0, -10)
    local form = ns.UI.Form(panel, -196, function()
        if win then win:SetScale(db.scale or 1) end
    end)
    form:Check(L.MURLOC_OPT_SOUND, function() return db.sound end, function(v) db.sound = v end)
    form:Check(L.MIN_OPT_LETTERS, function() return db.letters end, function(v) db.letters = v end)
    form:Number(L.MURLOC_OPT_SCALE, function() return math.floor((db.scale or 1) * 100 + 0.5) end,
        function(v) db.scale = v / 100 end, 60, 150, 5)
    ns.Games.TaxiOptions(form)
    table.insert(form.refreshers, function()
        stats:SetText(string.format(L.MURLOC_BEST, db.best or 0) .. "   ·   "
            .. string.format(L.MIN_STATS, db.games or 0, db.wins or 0)
            .. ((db.bestTier or 0) > 0 and ("\n" .. string.format(L.MIN_BEST_TIER, nameOf(db.bestTier))) or ""))
    end)
    panel:HookScript("OnShow", function() form:Refresh() end)
end

local function openPanel()
    if not db then return end
    if not panel then buildPanel() end
    ns.ShowPanel(panel)
end

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if ns.ModuleOff("jeux", ev) then return end
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        if type(root.games) ~= "table" then root.games = {} end
        if type(root.games.minerais) ~= "table" then root.games.minerais = {} end
        db = root.games.minerais
        if db.sound == nil then db.sound = true end
        if db.letters == nil then db.letters = true end
        if type(db.scale) ~= "number" then db.scale = 1 end
        load()
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- combat : clavier rendu au jeu (la souris marche toujours)
        if win and win:IsShown() then
            pcall(win.EnableKeyboard, win, false)
            refresh()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if win and win:IsShown() then
            setKeyboard(true)
            refresh()
        end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if win and win:IsShown() then refresh() end
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "GET_ITEM_INFO_RECEIVED" }) do
    pcall(ev.RegisterEvent, ev, e)
end

ns.RegisterModule({
    command = "minerais",
    alias = "2048",
    panelName = "CorpUIMineraisOptions",
    icon = ns.ItemIcon(18562),
    title = function() return L.MOD_MINERAIS end,
    desc = function() return L.MIN_DESC end,
    Slash = function(rest)
        rest = strlower(strtrim(rest or ""))
        if rest == "options" or rest == "config" then openPanel() else toggle() end
    end,
    Open = openPanel,
})

-- banc d essai
ns._minerais = { st = st, slide = slide, doMove = doMove, undo = undo, newGame = newGame, canMove = canMove,
                 load = load, save = save, toggle = toggle, finishAnim = finishAnim, animStep = animStep,
                 TIERS = TIERS, WIN_TIER = WIN_TIER, nameOf = nameOf, iconOf = iconOf,
                 ui = function() return win, board, overlay, hud, tiles, anim end }
