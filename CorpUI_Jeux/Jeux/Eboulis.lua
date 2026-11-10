--[[--------------------------------------------------------------------------
    CorpUI - module Jeux : l eboulis

    Des blocs de minerai degringolent dans un puits de 10 x 20 : on les
    deplace et on les tourne pour remplir des lignes entieres, qui
    s effacent. Sept formes de quatre blocs, une couleur de minerai chacune
    (argent, cuivre, or, thorium, sombrefer, mithril, arcanite), tirees par
    sacs de sept ; les trois suivantes sont montrees, une peut etre mise en
    reserve (une fois par piece).
      - fleches gauche / droite (Q / D, A / D en reglage) : deplacer (appui
        long : glisse) ; fleche bas (S) : descendre vite ; fleche haut ou X
        (Z / W en reglage) : tourner ; E ou Ctrl : tourner dans l autre
        sens ; Espace : lacher ; C ou Maj : reserve ; P : pause ;
        Echap : fermer ;
      - rotation avec decalages contre les murs et le sol ; ombre de la
        piece a l arrivee (reglage) ; une piece posee se fige apres 0,5 s
        (15 deplacements au plus pour la retenir) ;
      - points : 100 / 300 / 500 / 800 x niveau pour 1 a 4 lignes, x1,5
        pour deux quadruples de suite, bonus d enchainement ; descente
        rapide 1 par rangee, lacher 2 ; un niveau toutes les 10 lignes, la
        chute accelere ;
      - en combat : pause, clavier rendu au jeu ; fenetre cachee : pause ;
        la partie est gardee (fermer, /reload) et reprend en pause ;
      - sons de CorpUI : verre pour des lignes, carillon pour quatre ou un
        record, montee a chaque niveau, trombone triste a la fin.
    Blocs dessines par CorpUI (aplats et biseaux), aucune image ; fenetre a
    nous, deplacable ; rien de Blizzard n est touche.
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local C = ns.COLORS

local SOUNDS = ns.MEDIA .. "Sons\\"

local W, H = 10, 20                 -- puits visible
local HT = 24                       -- avec les rangees cachees au-dessus
local CELL, PREV = 22, 14           -- cases du puits, des apercus
local BOARD_W, BOARD_H = W * CELL, H * CELL
local SIDE = 124
local TOP = 36
local WIN_W, WIN_H = 12 + BOARD_W + 14 + SIDE + 12, TOP + BOARD_H + 34
local DAS, ARR = 0.17, 0.05         -- appui long : delai, puis cadence
local SOFT = 0.04                   -- descente rapide : une rangee par 0,04 s au plus
local LOCK, LOCK_MOVES = 0.5, 15
local CLEAR_T = 0.24                -- clignotement des lignes pleines
local TOAST_T = 1.3
local NEXT = 3
local MAX_LEVEL = 20

-- formes en position de depart : cases dans leur boite (x vers la droite,
-- y vers le bas) ; un minerai par forme
local KINDS = { "I", "O", "T", "S", "Z", "J", "L" }
local SHAPES = {
    I = { n = 4, { 0, 1 }, { 1, 1 }, { 2, 1 }, { 3, 1 } },
    O = { n = 4, { 1, 0 }, { 2, 0 }, { 1, 1 }, { 2, 1 } },
    T = { n = 3, { 1, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 } },
    S = { n = 3, { 1, 0 }, { 2, 0 }, { 0, 1 }, { 1, 1 } },
    Z = { n = 3, { 0, 0 }, { 1, 0 }, { 1, 1 }, { 2, 1 } },
    J = { n = 3, { 0, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 } },
    L = { n = 3, { 2, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 } },
}
local TINT = {
    { 0.74, 0.77, 0.82 },   -- argent
    { 0.80, 0.46, 0.24 },   -- cuivre
    { 0.93, 0.74, 0.22 },   -- or
    { 0.22, 0.66, 0.60 },   -- thorium
    { 0.72, 0.20, 0.22 },   -- sombrefer
    { 0.38, 0.54, 0.86 },   -- mithril
    { 0.62, 0.36, 0.88 },   -- arcanite
}

-- les quatre orientations de chaque forme (quart de tour horaire dans sa
-- boite ; le carre ne tourne pas)
local ROT = {}
for k, name in ipairs(KINDS) do
    local s = SHAPES[name]
    local cur = {}
    for i = 1, 4 do cur[i] = { s[i][1], s[i][2] } end
    ROT[k] = {}
    for r = 0, 3 do
        ROT[k][r] = cur
        if name ~= "O" then
            local nx = {}
            for i = 1, 4 do nx[i] = { s.n - 1 - cur[i][2], cur[i][1] } end
            cur = nx
        end
    end
end

-- decalages essayes quand une rotation cogne (x vers la droite, y vers le
-- haut), de l orientation a vers b : la table courante du genre
local KICK = {
    ["01"] = { { 0, 0 }, { -1, 0 }, { -1, 1 }, { 0, -2 }, { -1, -2 } },
    ["10"] = { { 0, 0 }, { 1, 0 }, { 1, -1 }, { 0, 2 }, { 1, 2 } },
    ["12"] = { { 0, 0 }, { 1, 0 }, { 1, -1 }, { 0, 2 }, { 1, 2 } },
    ["21"] = { { 0, 0 }, { -1, 0 }, { -1, 1 }, { 0, -2 }, { -1, -2 } },
    ["23"] = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, -2 }, { 1, -2 } },
    ["32"] = { { 0, 0 }, { -1, 0 }, { -1, -1 }, { 0, 2 }, { -1, 2 } },
    ["30"] = { { 0, 0 }, { -1, 0 }, { -1, -1 }, { 0, 2 }, { -1, 2 } },
    ["03"] = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, -2 }, { 1, -2 } },
}
local KICK_I = {
    ["01"] = { { 0, 0 }, { -2, 0 }, { 1, 0 }, { -2, -1 }, { 1, 2 } },
    ["10"] = { { 0, 0 }, { 2, 0 }, { -1, 0 }, { 2, 1 }, { -1, -2 } },
    ["12"] = { { 0, 0 }, { -1, 0 }, { 2, 0 }, { -1, 2 }, { 2, -1 } },
    ["21"] = { { 0, 0 }, { 1, 0 }, { -2, 0 }, { 1, -2 }, { -2, 1 } },
    ["23"] = { { 0, 0 }, { 2, 0 }, { -1, 0 }, { 2, 1 }, { -1, -2 } },
    ["32"] = { { 0, 0 }, { -2, 0 }, { 1, 0 }, { -2, -1 }, { 1, 2 } },
    ["30"] = { { 0, 0 }, { 1, 0 }, { -2, 0 }, { 1, -2 }, { -2, 1 } },
    ["03"] = { { 0, 0 }, { -1, 0 }, { 2, 0 }, { -1, 2 }, { 2, -1 } },
}

local LINE_PTS = { 100, 300, 500, 800 }

local db
local win, well, board, overlay, fx, hud
local blocks = {}            -- cases du puits (W * H)
local nextBoxes, holdBox = {}, nil
local dirty = true

-- cells[(rangee - 1) * W + colonne] : forme figee (0 = vide), rangee 1 en bas
-- piece = { k = forme, r = orientation, x = colonne du coin haut gauche de
-- sa boite, y = rangee de ce coin }
local st = { cells = {}, state = "ready", score = 0, lines = 0, level = 1, combo = -1, b2b = false,
             queue = {}, hold = 0, canHold = true, piece = nil, fall = 0, lockT = 0, lockMoves = 0,
             lowest = 0, clearing = nil, startBest = 0, newBest = false, toast = nil,
             keys = {}, dasDir = nil, dasT = 0, arrT = 0 }
for i = 1, W * HT do st.cells[i] = 0 end

local function play(file)
    if db and db.sound then pcall(PlaySoundFile, SOUNDS .. file .. ".ogg", "Master") end
end

---------------------------------------------------------------------------
-- Regles
---------------------------------------------------------------------------

local function cellAt(c, r)
    if c < 1 or c > W or r < 1 then return 9 end
    if r > HT then return 0 end
    return st.cells[(r - 1) * W + c]
end

local function fits(k, rot, x, y)
    for _, b in ipairs(ROT[k][rot]) do
        if cellAt(x + b[1], y - b[2]) ~= 0 then return false end
    end
    return true
end

-- chute (secondes par rangee) : la courbe habituelle du genre
local function gravity(level)
    local lv = math.min(level, MAX_LEVEL) - 1
    return math.max(0.004, (0.8 - lv * 0.007) ^ lv)
end

-- sacs de sept : chaque forme une fois, dans le desordre
local function fillQueue()
    while #st.queue <= NEXT do
        local bag = { 1, 2, 3, 4, 5, 6, 7 }
        for i = 7, 2, -1 do
            local j = math.random(i)
            bag[i], bag[j] = bag[j], bag[i]
        end
        for _, k in ipairs(bag) do st.queue[#st.queue + 1] = k end
    end
end

local function pull()
    fillQueue()
    local k = table.remove(st.queue, 1)
    fillQueue()
    return k
end

local function toast(text)
    st.toast = { text = text, t = 0 }
end

local gameOver

local function onGround()
    local p = st.piece
    return p and not fits(p.k, p.r, p.x, p.y - 1)
end

local function spawn(k)
    local p = { k = k, r = 0, x = 4, y = 22 }
    st.piece = p
    st.fall, st.lockT, st.lockMoves = 0, 0, 0
    if not fits(p.k, p.r, p.x, p.y) then
        gameOver()
        return false
    end
    -- descend tout de suite d une rangee : la piece se montre en haut du puits
    if fits(p.k, p.r, p.x, p.y - 1) then p.y = p.y - 1 end
    st.lowest = p.y
    dirty = true
    return true
end

-- deplacement ou rotation reussi au sol : delai de pose relance (15 fois)
local function moved()
    dirty = true
    if onGround() and st.lockMoves < LOCK_MOVES then
        st.lockT = 0
        st.lockMoves = st.lockMoves + 1
    end
end

local function tryMove(dx, dy)
    local p = st.piece
    if not p or not fits(p.k, p.r, p.x + dx, p.y + dy) then return false end
    p.x, p.y = p.x + dx, p.y + dy
    if p.y < st.lowest then
        st.lowest = p.y
        st.lockMoves, st.lockT = 0, 0
    end
    -- une descente ne compte pas parmi les 15 deplacements
    if dy < 0 then dirty = true else moved() end
    return true
end

local function rotate(dir)
    local p = st.piece
    if not p or KINDS[p.k] == "O" then return false end
    local to = (p.r + dir) % 4
    local list = (KINDS[p.k] == "I" and KICK_I or KICK)[p.r .. to]
    for _, kk in ipairs(list) do
        if fits(p.k, to, p.x + kk[1], p.y + kk[2]) then
            p.r, p.x, p.y = to, p.x + kk[1], p.y + kk[2]
            if p.y < st.lowest then
                st.lowest = p.y
                st.lockMoves = 0
            end
            moved()
            return true
        end
    end
    return false
end

local function dropY()
    local p = st.piece
    local y = p.y
    while fits(p.k, p.r, p.x, y - 1) do y = y - 1 end
    return y
end

local function fullRows()
    local rows = {}
    for r = 1, HT do
        local full = true
        for c = 1, W do
            if st.cells[(r - 1) * W + c] == 0 then full = false break end
        end
        if full then rows[#rows + 1] = r end
    end
    return rows
end

local save

-- lignes pleines retirees (apres le clignotement), puis piece suivante
local function finishClear()
    local cl = st.clearing
    if not cl then return end
    st.clearing = nil
    local gone = {}
    for _, r in ipairs(cl.rows) do gone[r] = true end
    local cells, out = st.cells, 1
    local keep = {}
    for r = 1, HT do
        if not gone[r] then
            for c = 1, W do keep[(out - 1) * W + c] = cells[(r - 1) * W + c] end
            out = out + 1
        end
    end
    for i = 1, W * HT do cells[i] = keep[i] or 0 end
    dirty = true
    spawn(pull())
end

local function lockPiece()
    local p = st.piece
    if not p then return end
    local above = true
    for _, b in ipairs(ROT[p.k][p.r]) do
        local c, r = p.x + b[1], p.y - b[2]
        if r <= H then above = false end
        if r >= 1 and r <= HT then st.cells[(r - 1) * W + c] = p.k end
    end
    st.piece = nil
    st.canHold = true
    dirty = true
    if above then
        gameOver()
        return
    end
    local rows = fullRows()
    local n = #rows
    if n == 0 then
        st.combo = -1
        spawn(pull())
        return
    end
    local pts = LINE_PTS[math.min(n, 4)] * st.level
    local said
    if n >= 4 then
        if st.b2b then
            pts = pts * 1.5
            said = L.EBO_B2B
        end
        st.b2b = true
    else
        st.b2b = false
    end
    st.combo = st.combo + 1
    if st.combo > 0 then
        pts = pts + 50 * st.combo * st.level
        said = said or string.format(L.EBO_COMBO, st.combo + 1)
    end
    st.score = st.score + math.floor(pts)
    st.lines = st.lines + n
    toast(said or L["EBO_CLEAR" .. math.min(n, 4)])
    local level = math.min(MAX_LEVEL, 1 + math.floor(st.lines / 10))
    if level > st.level then
        st.level = level
        toast(string.format(L.EBO_LEVELUP, level))
        play("montee")
    else
        play(n >= 4 and "carillon" or "verre")
    end
    if st.score > (db.best or 0) then db.best = st.score end
    st.clearing = { rows = rows, t = 0 }
end

local function hardDrop()
    local p = st.piece
    if not p then return end
    local y = dropY()
    st.score = st.score + 2 * (p.y - y)
    p.y = y
    lockPiece()
end

local function holdPiece()
    local p = st.piece
    if not p or not st.canHold then return false end
    local k = st.hold
    st.hold = p.k
    st.canHold = false
    spawn(k > 0 and k or pull())
    return true
end

local refresh, drawAll, showOverlay

function gameOver()
    st.state = "over"
    st.piece = nil
    st.clearing = nil
    st.keys, st.dasDir = {}, nil
    st.newBest = st.score > (st.startBest or 0)
    if st.score > (db.best or 0) then db.best = st.score end
    if st.lines > (db.bestLines or 0) then db.bestLines = st.lines end
    if st.level > (db.bestLevel or 0) then db.bestLevel = st.level end
    db.save = nil
    play(st.newBest and "carillon" or "trombone")
    dirty = true
    if win then refresh() end
end

local function newGame()
    for i = 1, W * HT do st.cells[i] = 0 end
    st.score, st.lines, st.level, st.combo, st.b2b = 0, 0, 1, -1, false
    st.queue, st.hold, st.canHold = {}, 0, true
    st.clearing, st.toast, st.newBest = nil, nil, false
    st.keys, st.dasDir = {}, nil
    st.startBest = db.best or 0
    db.games = (db.games or 0) + 1
    st.state = "run"
    spawn(pull())
    if win then refresh() end
end

local function pause(reason)
    if st.state ~= "run" then return end
    finishClear()
    if st.state ~= "run" then return end
    st.state = "pause"
    st.pauseReason = reason
    st.keys, st.dasDir = {}, nil
    save()
    if win then refresh() end
end

local function resume()
    if st.state ~= "pause" or InCombatLockdown() then return end
    st.state = "run"
    st.pauseReason = nil
    dirty = true
    if win then refresh() end
end

-- une image : touches tenues, chute, pose, clignotement des lignes
local function update(dt)
    if st.toast then
        st.toast.t = st.toast.t + dt
        if st.toast.t >= TOAST_T then st.toast = nil end
    end
    if st.state ~= "run" then return end
    if st.clearing then
        st.clearing.t = st.clearing.t + dt
        dirty = true
        if st.clearing.t >= CLEAR_T then finishClear() end
        return
    end
    local p = st.piece
    if not p then return end
    -- appui long a gauche ou a droite
    if st.dasDir then
        st.dasT = st.dasT + dt
        if st.dasT >= DAS then
            st.arrT = st.arrT + dt
            while st.arrT >= ARR do
                st.arrT = st.arrT - ARR
                if not tryMove(st.dasDir, 0) then st.arrT = 0 break end
            end
        end
    end
    -- chute
    local soft = st.keys.down
    local step = gravity(st.level)
    if soft then step = math.min(step, SOFT) end
    if onGround() then
        st.fall = 0
        st.lockT = st.lockT + dt
        if st.lockT >= LOCK or st.lockMoves >= LOCK_MOVES then lockPiece() end
        return
    end
    st.lockT = 0
    st.fall = st.fall + dt
    while st.fall >= step do
        st.fall = st.fall - step
        if not tryMove(0, -1) then st.fall = 0 break end
        if soft then st.score = st.score + 1 end
    end
end

-- touches : appui et relache (actions du jeu, voir KEYS)
local function press(action)
    if st.state == "ready" or st.state == "over" then
        if action == "drop" then newGame() end
        return
    end
    if st.state == "pause" then
        if action == "drop" or action == "pause" then resume() end
        return
    end
    if action == "left" or action == "right" then
        local d = action == "left" and -1 or 1
        st.keys[action] = true
        st.dasDir, st.dasT, st.arrT = d, 0, 0
        if not st.clearing then tryMove(d, 0) end
    elseif action == "down" then
        st.keys.down = true
        if not st.clearing and tryMove(0, -1) then
            st.score = st.score + 1
            st.fall = 0
        end
    elseif action == "pause" then
        pause()
    elseif st.clearing then
        return
    elseif action == "cw" then
        rotate(1)
    elseif action == "ccw" then
        rotate(-1)
    elseif action == "drop" then
        hardDrop()
    elseif action == "hold" then
        holdPiece()
    end
    if win then refresh() end
end

local function release(action)
    if action == "left" or action == "right" then
        st.keys[action] = nil
        local d = action == "left" and -1 or 1
        if st.dasDir == d then
            local other = action == "left" and "right" or "left"
            st.dasDir = st.keys[other] and -d or nil
            st.dasT, st.arrT = 0, 0
        end
    elseif action == "down" then
        st.keys.down = nil
    end
end

---------------------------------------------------------------------------
-- Partie gardee
---------------------------------------------------------------------------

local function validKind(k) return type(k) == "number" and k >= 1 and k <= 7 and k == math.floor(k) end

function save()
    if not db then return end
    if st.state ~= "run" and st.state ~= "pause" then return end
    local p = st.piece
    local cells = {}
    for i = 1, W * HT do cells[i] = st.cells[i] end
    local queue = {}
    for i, k in ipairs(st.queue) do queue[i] = k end
    db.save = {
        cells = cells, queue = queue, hold = st.hold, canHold = st.canHold,
        piece = p and { p.k, p.r, p.x, p.y } or nil,
        score = st.score, lines = st.lines, level = st.level, combo = st.combo, b2b = st.b2b,
        startBest = st.startBest,
    }
end

-- partie gardee : reprend en pause (rend false si rien de valable)
local function load()
    local s = db and db.save
    if type(s) ~= "table" or type(s.cells) ~= "table" or type(s.queue) ~= "table" or type(s.score) ~= "number" then
        return false
    end
    for i = 1, W * HT do
        local v = s.cells[i]
        if v ~= 0 and not validKind(v) then return false end
    end
    for _, k in ipairs(s.queue) do if not validKind(k) then return false end end
    local p = s.piece
    if type(p) ~= "table" or not validKind(p[1]) or type(p[2]) ~= "number" or type(p[3]) ~= "number"
        or type(p[4]) ~= "number" then
        return false
    end
    for i = 1, W * HT do st.cells[i] = s.cells[i] end
    if not fits(p[1], p[2] % 4, p[3], p[4]) then
        for i = 1, W * HT do st.cells[i] = 0 end
        return false
    end
    st.queue = {}
    for i, k in ipairs(s.queue) do st.queue[i] = k end
    fillQueue()
    st.hold = validKind(s.hold) and s.hold or 0
    st.canHold = s.canHold ~= false
    st.score = s.score
    st.lines = type(s.lines) == "number" and s.lines or 0
    st.level = math.max(1, math.min(MAX_LEVEL, type(s.level) == "number" and s.level or 1))
    st.combo = type(s.combo) == "number" and s.combo or -1
    st.b2b = s.b2b and true or false
    st.startBest = type(s.startBest) == "number" and s.startBest or (db.best or 0)
    st.piece = { k = p[1], r = p[2] % 4, x = p[3], y = p[4] }
    st.lowest, st.fall, st.lockT, st.lockMoves = st.piece.y, 0, 0, 0
    st.clearing, st.toast = nil, nil
    st.state = "pause"
    dirty = true
    return true
end

---------------------------------------------------------------------------
-- Dessin
---------------------------------------------------------------------------

local function light(v) return v + (1 - v) * 0.45 end

-- bloc : bord sombre, face, reflets en haut et a gauche
local function newBlock(parent, size)
    local b = { size = size }
    b.edge = parent:CreateTexture(nil, "BORDER")
    b.face = parent:CreateTexture(nil, "ARTWORK")
    b.hiTop = parent:CreateTexture(nil, "ARTWORK", nil, 1)
    b.hiLeft = parent:CreateTexture(nil, "ARTWORK", nil, 1)
    return b
end

local function placeBlock(b, x, y)
    local s = b.size
    b.edge:ClearAllPoints()
    b.edge:SetPoint("BOTTOMLEFT", b.parentFrame, "BOTTOMLEFT", x, y)
    b.edge:SetSize(s, s)
    b.face:ClearAllPoints()
    b.face:SetPoint("BOTTOMLEFT", b.parentFrame, "BOTTOMLEFT", x + 1, y + 2)
    b.face:SetSize(s - 3, s - 3)
    b.hiTop:ClearAllPoints()
    b.hiTop:SetPoint("BOTTOMLEFT", b.parentFrame, "BOTTOMLEFT", x + 1, y + s - 3)
    b.hiTop:SetSize(s - 3, 2)
    b.hiLeft:ClearAllPoints()
    b.hiLeft:SetPoint("BOTTOMLEFT", b.parentFrame, "BOTTOMLEFT", x + 1, y + 2)
    b.hiLeft:SetSize(2, s - 5)
end

-- mode : "solid", "ghost", "flash", "dim" (apercus suivants) ou nil (vide)
local function paint(b, k, mode)
    if b.k == k and b.mode == mode then return end
    b.k, b.mode = k, mode
    if not mode or k == 0 then
        b.edge:Hide() b.face:Hide() b.hiTop:Hide() b.hiLeft:Hide()
        return
    end
    local t = TINT[k]
    local r, g, bl = t[1], t[2], t[3]
    b.edge:Show() b.face:Show()
    if mode == "flash" then
        b.edge:SetColorTexture(1, 1, 1, 0.9)
        b.face:SetColorTexture(1, 0.97, 0.85, 0.95)
        b.hiTop:Hide() b.hiLeft:Hide()
    elseif mode == "ghost" then
        b.edge:SetColorTexture(r, g, bl, 0.5)
        b.face:SetColorTexture(0.03, 0.03, 0.04, 0.85)
        b.hiTop:Hide() b.hiLeft:Hide()
    else
        local a = mode == "dim" and 0.55 or 1
        b.edge:SetColorTexture(r * 0.42, g * 0.42, bl * 0.42, a)
        b.face:SetColorTexture(r, g, bl, a)
        b.hiTop:SetColorTexture(light(r), light(g), light(bl), a)
        b.hiLeft:SetColorTexture(light(r), light(g), light(bl), a * 0.8)
        b.hiTop:Show() b.hiLeft:Show()
    end
end

-- apercu : la forme centree dans sa case
local function drawPreview(box, k, mode)
    if not k or k == 0 then
        for _, b in ipairs(box.blocks) do paint(b, 0, nil) end
        box.k = nil
        return
    end
    if box.k ~= k then
        box.k = k
        local minx, maxx, miny, maxy = 9, -1, 9, -1
        for _, c in ipairs(ROT[k][0]) do
            minx, maxx = math.min(minx, c[1]), math.max(maxx, c[1])
            miny, maxy = math.min(miny, c[2]), math.max(maxy, c[2])
        end
        local bw, bh = (maxx - minx + 1) * PREV, (maxy - miny + 1) * PREV
        local ox, oy = (box.w - bw) / 2, (box.h - bh) / 2
        for i, c in ipairs(ROT[k][0]) do
            placeBlock(box.blocks[i], ox + (c[1] - minx) * PREV, oy + (maxy - c[2]) * PREV)
        end
    end
    for _, b in ipairs(box.blocks) do paint(b, k, mode) end
end

local vk, vm = {}, {}
function drawAll()
    if not board then return end
    dirty = false
    local cells = st.cells
    for i = 1, W * H do
        vk[i] = cells[i]
        vm[i] = cells[i] > 0 and "solid" or nil
    end
    local cl = st.clearing
    if cl and math.floor(cl.t / 0.06) % 2 == 0 then
        for _, r in ipairs(cl.rows) do
            if r <= H then
                for c = 1, W do vm[(r - 1) * W + c] = "flash" end
            end
        end
    end
    local p = st.piece
    if p and st.state ~= "over" then
        if db.ghost then
            local gy = dropY()
            for _, b in ipairs(ROT[p.k][p.r]) do
                local r = gy - b[2]
                local i = (r - 1) * W + p.x + b[1]
                if r <= H and vk[i] == 0 then vk[i], vm[i] = p.k, "ghost" end
            end
        end
        for _, b in ipairs(ROT[p.k][p.r]) do
            local r = p.y - b[2]
            if r <= H then
                local i = (r - 1) * W + p.x + b[1]
                vk[i], vm[i] = p.k, "solid"
            end
        end
    end
    for i = 1, W * H do paint(blocks[i], vk[i], vm[i]) end
    for i, box in ipairs(nextBoxes) do drawPreview(box, st.queue[i], i == 1 and "solid" or "dim") end
    drawPreview(holdBox, st.hold, st.canHold and "solid" or "dim")
end

function showOverlay(title, line1, line2)
    overlay.title:SetText(title)
    overlay.line1:SetText(line1 or "")
    overlay.line2:SetText(line2 or "")
    overlay:Show()
end

local sureUntil = 0

function refresh()
    if not win then return end
    dirty = true
    hud.score:SetText(st.score)
    hud.best:SetText(math.max(db.best or 0, st.score))
    hud.level:SetText(st.level)
    hud.lines:SetText(st.lines)
    hud.new:SetText(GetTime() < sureUntil and L.EBO_SURE or L.EBO_NEW)
    hud.pause:SetText(st.state == "pause" and L.EBO_RESUME_BTN or L.EBO_PAUSE_BTN)
    hud.pause:SetEnabled(st.state == "run" or st.state == "pause")
    if st.state == "ready" then
        showOverlay(L.EBO_TITLE, L.EBO_KEYS, L.EBO_START)
    elseif st.state == "pause" then
        showOverlay(L.EBO_TITLE, st.pauseReason or L.EBO_PAUSED, L.EBO_RESUME)
    elseif st.state == "over" then
        local line = string.format(L.EBO_OVER2, st.score, st.lines, st.level)
        if st.newBest then line = line .. "\n|cffffd100" .. L.EBO_NEW_BEST .. "|r" end
        showOverlay(L.EBO_OVER, line, L.EBO_RETRY)
    else
        overlay:Hide()
    end
end

---------------------------------------------------------------------------
-- Fenetre
---------------------------------------------------------------------------

local KEYS = { LEFT = "left", RIGHT = "right", DOWN = "down", UP = "cw", X = "cw", E = "ccw",
               LCTRL = "ccw", RCTRL = "ccw", SPACE = "drop", C = "hold", LSHIFT = "hold",
               RSHIFT = "hold", P = "pause" }
local LETTERS = { Q = "left", A = "left", D = "right", S = "down", Z = "cw", W = "cw" }

local function actionOf(key)
    return KEYS[key] or (db.letters and LETTERS[key]) or nil
end

local function setKeyboard(on)
    if not win then return end
    pcall(win.EnableKeyboard, win, on and not InCombatLockdown())
end

local function statBox(label, y)
    local l = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    l:SetPoint("TOPLEFT", win, "TOPLEFT", 12 + BOARD_W + 14, y)
    l:SetText(label)
    local v = win:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(v, 15)
    v:SetPoint("TOPRIGHT", win, "TOPLEFT", 12 + BOARD_W + 14 + SIDE, y - 1)
    v:SetTextColor(1, 1, 1)
    return v
end

local function previewBox(y, h)
    local box = CreateFrame("Frame", nil, win)
    box:SetSize(SIDE, h)
    box:SetPoint("TOPLEFT", win, "TOPLEFT", 12 + BOARD_W + 14, y)
    ns.UI.Skin(box, 0.6)
    box.w, box.h = SIDE, h
    box.blocks = {}
    for i = 1, 4 do
        local b = newBlock(box, PREV)
        b.parentFrame = box
        box.blocks[i] = b
    end
    return box
end

local function build()
    db.pos = db.pos or { point = "CENTER", x = 0, y = 40 }
    win = CreateFrame("Frame", "CorpUIEboulisGame", UIParent)
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
    title:SetText(L.EBO_TITLE)
    local close = CreateFrame("Button", nil, bar)
    close:SetSize(22, 22)
    close:SetPoint("RIGHT", -4, 0)
    local x = close:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    x:SetPoint("CENTER")
    x:SetText("×")
    close:SetScript("OnClick", function() win:Hide() end)
    -- puits
    well = CreateFrame("Frame", nil, win)
    well:SetSize(BOARD_W + 4, BOARD_H + 4)
    well:SetPoint("TOPLEFT", win, "TOPLEFT", 10, -TOP + 2)
    ns.UI.Skin(well, 0.9)
    board = CreateFrame("Frame", nil, well)
    board:SetSize(BOARD_W, BOARD_H)
    board:SetPoint("CENTER")
    local back = board:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(0.025, 0.025, 0.035, 0.95)
    for r = 1, H do
        for c = 1, W do
            local slot = board:CreateTexture(nil, "BACKGROUND", nil, 1)
            slot:SetSize(CELL - 2, CELL - 2)
            slot:SetPoint("BOTTOMLEFT", board, "BOTTOMLEFT", (c - 1) * CELL + 1, (r - 1) * CELL + 1)
            slot:SetColorTexture(1, 1, 1, 0.035)
            local b = newBlock(board, CELL)
            b.parentFrame = board
            placeBlock(b, (c - 1) * CELL, (r - 1) * CELL)
            paint(b, 0, nil)
            blocks[(r - 1) * W + c] = b
        end
    end
    -- clic sur le puits : jouer, reprendre
    board:EnableMouse(true)
    board:SetScript("OnMouseDown", function()
        if InCombatLockdown() then return end
        if st.state == "pause" then resume() elseif st.state ~= "run" then newGame() end
    end)
    -- colonne de droite : suivantes, reserve, compteurs, boutons
    local sx = 12 + BOARD_W + 14
    local nl = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nl:SetPoint("TOPLEFT", win, "TOPLEFT", sx, -TOP)
    nl:SetText(L.EBO_NEXT)
    for i = 1, NEXT do
        nextBoxes[i] = previewBox(-TOP - 14 - (i - 1) * 46, 42)
    end
    local hl = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hl:SetPoint("TOPLEFT", win, "TOPLEFT", sx, -TOP - 14 - NEXT * 46 - 6)
    hl:SetText(L.EBO_HOLD)
    holdBox = previewBox(-TOP - 14 - NEXT * 46 - 20, 42)
    hud = {}
    local y0 = -TOP - 14 - NEXT * 46 - 20 - 42 - 16
    hud.score = statBox(L.EBO_SCORE, y0)
    hud.best = statBox(L.EBO_BEST, y0 - 24)
    hud.level = statBox(L.EBO_LEVEL, y0 - 48)
    hud.lines = statBox(L.EBO_LINES, y0 - 72)
    hud.pause = ns.UI.Button(win, L.EBO_PAUSE_BTN, SIDE, function()
        if st.state == "pause" then resume() else pause() end
    end)
    hud.pause:SetPoint("BOTTOMLEFT", win, "TOPLEFT", sx, -TOP - BOARD_H)
    hud.new = ns.UI.Button(win, L.EBO_NEW, SIDE, function()
        -- partie en cours : un second clic confirme
        if (st.state == "run" or st.state == "pause") and st.score > 0 and GetTime() >= sureUntil then
            sureUntil = GetTime() + 3
            refresh()
            C_Timer.After(3.05, function() if win and win:IsShown() then refresh() end end)
            return
        end
        sureUntil = 0
        if InCombatLockdown() then return end
        newGame()
    end)
    hud.new:SetPoint("BOTTOMLEFT", hud.pause, "TOPLEFT", 0, 4)
    local help = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -TOP - BOARD_H - 9)
    help:SetWidth(WIN_W - 24)
    help:SetJustifyH("LEFT")
    help:SetText(L.EBO_HELP)
    -- messages sur le puits : pause, debut, fin
    overlay = CreateFrame("Frame", nil, board)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(board:GetFrameLevel() + 20)
    local shade = overlay:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    shade:SetColorTexture(0, 0, 0, 0.66)
    overlay.title = overlay:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(overlay.title, 22)
    overlay.title:SetPoint("CENTER", 0, 70)
    overlay.title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    overlay.line1 = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    overlay.line1:SetPoint("TOP", overlay.title, "BOTTOM", 0, -12)
    overlay.line1:SetWidth(BOARD_W - 20)
    overlay.line2 = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    overlay.line2:SetPoint("TOP", overlay.line1, "BOTTOM", 0, -12)
    overlay.line2:SetWidth(BOARD_W - 20)
    overlay:EnableMouse(false)
    overlay:Hide()
    -- annonces (lignes, niveau) : en haut du puits, s effacent
    fx = CreateFrame("Frame", nil, board)
    fx:SetAllPoints()
    fx:SetFrameLevel(board:GetFrameLevel() + 10)
    fx.text = fx:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(fx.text, 18)
    fx.text:SetPoint("TOP", 0, -70)
    fx.text:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    -- clavier : seulement les touches de jeu (et Echap) sont gardees
    win:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        local action = actionOf(key)
        if action then
            self:SetPropagateKeyboardInput(false)
            press(action)
        elseif key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    win:SetScript("OnKeyUp", function(self, key)
        local action = actionOf(key)
        if action then release(action) end
        if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
    end)
    win:SetScript("OnShow", function()
        setKeyboard(true)
        refresh()
        drawAll()
    end)
    win:SetScript("OnHide", function()
        setKeyboard(false)
        pause()
        save()
    end)
    board:SetScript("OnUpdate", function(_, dt)
        update(dt)
        local t = st.toast
        if t then
            if fx.text:GetText() ~= t.text then fx.text:SetText(t.text) end
            fx.text:SetAlpha(math.min(1, (TOAST_T - t.t) / 0.4))
            fx.text:Show()
        elseif fx.text:IsShown() then
            fx.text:Hide()
        end
        if dirty then
            drawAll()
            hud.score:SetText(st.score)
            hud.best:SetText(math.max(db.best or 0, st.score))
            hud.level:SetText(st.level)
            hud.lines:SetText(st.lines)
        end
    end)
    win:Hide()
end

local function toggle()
    if not db then return end
    if InCombatLockdown() then ns.Say(L.COMBAT_BLOCKED) return end
    if not win then build() end
    win:SetShown(not win:IsShown())
end

-- liste des jeux (ouverture pendant un vol : Jeux.lua)
ns.Games.Register("eboulis", {
    title = function() return L.MOD_EBOULIS end,
    open = function()
        if not db or InCombatLockdown() then return false end
        if not win then build() end
        win:Show()
        return true
    end,
    close = function() if win then win:Hide() end end,
    shown = function() return win and win:IsShown() or false end,
})

---------------------------------------------------------------------------
-- Reglages (/corp eboulis)
---------------------------------------------------------------------------

local panel

local function buildPanel()
    panel = ns.UI.Window("CorpUIEboulisOptions", ns.TITLE .. " - " .. L.MOD_EBOULIS, nil, 440, 420)
    local icon = panel:CreateTexture(nil, "ARTWORK")
    icon:SetSize(64, 64)
    icon:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -40)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetTexture(ns.ItemIcon and ns.ItemIcon(10620) or "Interface\\Icons\\INV_Ore_Thorium_02")
    local desc = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", panel, "TOPLEFT", 92, -40)
    desc:SetWidth(336)
    desc:SetJustifyH("LEFT")
    desc:SetText(L.EBO_HINT)
    local stats = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    stats:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -10)
    stats:SetWidth(336)
    stats:SetJustifyH("LEFT")
    local playBtn = ns.UI.Button(panel, L.MURLOC_PLAY, 120, function() toggle() end)
    playBtn:SetPoint("TOPLEFT", stats, "BOTTOMLEFT", 0, -10)
    local form = ns.UI.Form(panel, -230, function()
        if win then win:SetScale(db.scale or 1) end
        dirty = true
    end)
    form:Check(L.MURLOC_OPT_SOUND, function() return db.sound end, function(v) db.sound = v end)
    form:Check(L.MIN_OPT_LETTERS, function() return db.letters end, function(v) db.letters = v end)
    form:Check(L.EBO_OPT_GHOST, function() return db.ghost end, function(v) db.ghost = v dirty = true end)
    form:Number(L.MURLOC_OPT_SCALE, function() return math.floor((db.scale or 1) * 100 + 0.5) end,
        function(v) db.scale = v / 100 end, 60, 150, 5)
    ns.Games.TaxiOptions(form)
    table.insert(form.refreshers, function()
        stats:SetText(string.format(L.MURLOC_BEST, db.best or 0) .. "   ·   "
            .. string.format(L.EBO_STATS, db.games or 0, db.bestLines or 0, db.bestLevel or 0))
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
        if type(root.games.eboulis) ~= "table" then root.games.eboulis = {} end
        db = root.games.eboulis
        if db.sound == nil then db.sound = true end
        if db.letters == nil then db.letters = true end
        if db.ghost == nil then db.ghost = true end
        if type(db.scale) ~= "number" then db.scale = 1 end
        load()
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- combat : pause, clavier rendu au jeu
        if win and win:IsShown() then
            pause(L.EBO_COMBAT)
            pcall(win.EnableKeyboard, win, false)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if win and win:IsShown() then setKeyboard(true) end
    elseif event == "PLAYER_LOGOUT" then
        if st.state == "run" then finishClear() end
        save()
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_LOGOUT" }) do
    pcall(ev.RegisterEvent, ev, e)
end

ns.RegisterModule({
    command = "eboulis",
    alias = "blocs",
    panelName = "CorpUIEboulisOptions",
    icon = ns.ItemIcon and ns.ItemIcon(10620) or nil,
    title = function() return L.MOD_EBOULIS end,
    desc = function() return L.EBO_DESC end,
    Slash = function(rest)
        rest = strlower(strtrim(rest or ""))
        if rest == "options" or rest == "config" then openPanel() else toggle() end
    end,
    Open = openPanel,
})

-- banc d essai
ns._eboulis = { st = st, fits = fits, spawn = spawn, rotate = rotate, tryMove = tryMove, hardDrop = hardDrop,
                holdPiece = holdPiece, lockPiece = lockPiece, finishClear = finishClear, update = update,
                press = press, release = release, newGame = newGame, pause = pause, resume = resume,
                save = save, load = load, toggle = toggle, gravity = gravity, dropY = dropY,
                KINDS = KINDS, ROT = ROT, W = W, H = H, HT = HT,
                ui = function() return win, board, overlay, hud, blocks, nextBoxes, holdBox end,
                draw = function() drawAll() end }
