--[[--------------------------------------------------------------------------
    CorpUI - module Jeux : les chats de l auberge

    Casse-tete de placement : l aubergiste loge ses chats. La grille (5 x 5
    a 9 x 9) est decoupee en chambres de couleur ; il faut un chat par
    chambre, un par ligne, un par colonne, et deux chats ne se touchent
    jamais, meme en diagonale (ils se battraient). Une seule solution,
    trouvable par la logique.
      - clic : empreinte (« pas de chat ici »), puis chat, puis vide ;
        clic droit : empreinte ; glisser : empreintes sur toutes les cases
        survolees ; Retour arriere ou Ctrl+Z : annuler ; Echap : fermer ;
      - 3 vies (reglage) : un chat pose au mauvais endroit coute une vie ;
        sans vies, les chats qui se genent passent au rouge ;
      - indice : un chat de la solution se pose (+30 s au chrono) ;
      - grille du jour : la meme pour tout le monde (8 x 8, tiree du jour
        UTC), avec sa serie de jours resolus ; record par taille ;
      - les grilles sont fabriquees ici : chats places au hasard (jamais
        voisins), chambres grandies autour d eux, puis retouchees tant
        qu une autre solution existe ; le travail est etale sur plusieurs
        images (coroutine) pour ne jamais figer le jeu ;
      - la partie est gardee (fermer, /reload) ; tour par tour : en combat,
        clavier rendu au jeu, la souris marche toujours ;
      - images peintes generees avec Nano Banana (Media/Jeux/chats.tga) ;
        sons de CorpUI : verre pour un chat loge, erreur, carillon a la fin.
    Fenetre a nous, deplacable ; rien de Blizzard n est touche.
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local C = ns.COLORS

local MEDIA = ns.MEDIA .. "Jeux\\"
local SOUNDS = ns.MEDIA .. "Sons\\"
local SHEET = MEDIA .. "chats"

local BOARD = 360
local WIN_W, WIN_H = BOARD + 24, BOARD + 168
local SIZES = { 5, 6, 7, 8, 9 }
local DAILY_N = 8
local LIVES = 3
local HINT_COST = 30
local FLASH_T = 0.6
local EMPTY, MARK, CAT = 0, 1, 2
local HEART, PAW, YARN = 10, 11, 12           -- cases de la planche

-- couleurs des chambres : tons chauds d auberge, assez sombres pour le theme
local ROOMS = {
    { 0.78, 0.47, 0.52 }, { 0.82, 0.58, 0.36 }, { 0.80, 0.72, 0.40 },
    { 0.50, 0.68, 0.45 }, { 0.40, 0.66, 0.64 }, { 0.45, 0.56, 0.78 },
    { 0.62, 0.50, 0.78 }, { 0.70, 0.62, 0.52 }, { 0.55, 0.60, 0.66 },
}

local function sprite(k)
    local col, row = (k - 1) % 4, math.floor((k - 1) / 4)
    return col * 0.25, col * 0.25 + 0.25, row * 0.25, row * 0.25 + 0.25
end

---------------------------------------------------------------------------
-- Fabrication des grilles (sans etat : testable seule)
---------------------------------------------------------------------------

-- tirage reproductible (Park-Miller : exact en nombres flottants)
local function newRng(seed)
    local s = math.floor(seed) % 2147483646 + 1
    return function(n)
        s = s * 16807 % 2147483647
        return n and (s % n + 1) or s
    end
end

local function shuffle(t, R)
    for i = #t, 2, -1 do
        local j = R(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

local function neighbors(N, i)
    local r, c = math.floor((i - 1) / N) + 1, (i - 1) % N + 1
    local t = {}
    if r > 1 then t[#t + 1] = i - N end
    if r < N then t[#t + 1] = i + N end
    if c > 1 then t[#t + 1] = i - 1 end
    if c < N then t[#t + 1] = i + 1 end
    return t
end

-- un chat par ligne et par colonne, jamais voisins : col[ligne]
local function placeCats(N, R)
    local col, used = {}, {}
    local function go(r)
        if r > N then return true end
        local order = {}
        for c = 1, N do order[c] = c end
        shuffle(order, R)
        for _, c in ipairs(order) do
            if not used[c] and (r == 1 or math.abs(c - col[r - 1]) >= 2) then
                col[r], used[c] = c, true
                if go(r + 1) then return true end
                used[c] = nil
            end
        end
        return false
    end
    go(1)
    return col
end

-- chambres grandies au hasard autour de chaque chat
local function grow(N, col, R)
    local reg, front = {}, {}
    local function push(i, k)
        for _, j in ipairs(neighbors(N, i)) do front[#front + 1] = { j, k } end
    end
    for r = 1, N do
        local i = (r - 1) * N + col[r]
        reg[i] = r
        push(i, r)
    end
    local left = N * N - N
    while left > 0 do
        local j = R(#front)
        local f = front[j]
        front[j] = front[#front]
        front[#front] = nil
        if not reg[f[1]] then
            reg[f[1]] = f[2]
            left = left - 1
            push(f[1], f[2])
        end
    end
    return reg
end

-- une solution autre que col, ou nil ; tick() appele de temps en temps
local function otherSolution(N, reg, col, tick)
    local usedC, usedR, cur = {}, {}, {}
    local found, nodes = nil, 0
    local function go(r, pc)
        if r > N then
            for k = 1, N do
                if cur[k] ~= col[k] then
                    found = {}
                    for q = 1, N do found[q] = cur[q] end
                    return true
                end
            end
            return false
        end
        nodes = nodes + 1
        if tick and nodes % 1500 == 0 then tick() end
        for c = 1, N do
            local k = reg[(r - 1) * N + c]
            if not usedC[c] and not usedR[k] and (not pc or math.abs(c - pc) >= 2) then
                usedC[c], usedR[k], cur[r] = true, true, c
                local stop = go(r + 1, c)
                usedC[c], usedR[k] = nil, nil
                if stop then return true end
            end
        end
        return false
    end
    go(1, nil)
    return found
end

-- la chambre k reste d un seul tenant sans la case x ?
local function connectedWithout(N, reg, k, x)
    local start, size = nil, 0
    for i = 1, N * N do
        if reg[i] == k and i ~= x then
            size = size + 1
            start = start or i
        end
    end
    if not start then return false end
    local seen, stack, n = { [start] = true }, { start }, 1
    while #stack > 0 do
        local i = table.remove(stack)
        for _, j in ipairs(neighbors(N, i)) do
            if j ~= x and not seen[j] and reg[j] == k then
                seen[j] = true
                n = n + 1
                stack[#stack + 1] = j
            end
        end
    end
    return n == size
end

-- grille a solution unique : chambres (reg[case] = 1..N) et solution
-- (col[ligne]) ; tant qu une autre solution existe, une de ses cases (hors
-- des chats de la vraie) passe dans une chambre voisine, ce qui la casse
local function generate(N, seed, tick)
    local R = newRng(seed)
    while true do
        local col = placeCats(N, R)
        local catAt = {}
        for r = 1, N do catAt[(r - 1) * N + col[r]] = true end
        local reg = grow(N, col, R)
        for _ = 1, N * N * 3 do
            local alt = otherSolution(N, reg, col, tick)
            if not alt then return reg, col end
            local cells = {}
            for r = 1, N do
                local i = (r - 1) * N + alt[r]
                if not catAt[i] then cells[#cells + 1] = i end
            end
            shuffle(cells, R)
            local done = false
            for _, x in ipairs(cells) do
                local ks = {}
                for _, j in ipairs(neighbors(N, x)) do
                    if reg[j] ~= reg[x] then ks[#ks + 1] = reg[j] end
                end
                if #ks > 0 and connectedWithout(N, reg, reg[x], x) then
                    reg[x] = ks[R(#ks)]
                    done = true
                    break
                end
            end
            if not done then break end
            if tick then tick() end
        end
    end
end

---------------------------------------------------------------------------
-- Partie
---------------------------------------------------------------------------

local db
local win, board, overlay, hud
local cellsUI, lines = {}, {}
local cellSize = 40

-- reg / sol / cells : chambres, solution (col par ligne), contenu des cases
local st = { state = "idle", n = 7, reg = nil, sol = nil, cells = {}, time = 0, hearts = LIVES, hints = 0,
             daily = nil, undo = {}, flash = nil, job = nil, jobN = nil, jobDaily = nil }

local function play(file)
    if db and db.sound then pcall(PlaySoundFile, SOUNDS .. file .. ".ogg", "Master") end
end

local function today()
    local ok, t = pcall(GetServerTime)
    t = ok and type(t) == "number" and t or time()
    return math.floor(t / 86400), t
end

local function clock(sec)
    sec = math.floor(sec or 0)
    local h, m = math.floor(sec / 3600), math.floor(sec % 3600 / 60)
    if h > 0 then return string.format("%d:%02d:%02d", h, m, sec % 60) end
    return string.format("%02d:%02d", math.floor(sec / 60), sec % 60)
end

local function rc(i) return math.floor((i - 1) / st.n) + 1, (i - 1) % st.n + 1 end

local function solutionAt(i)
    local r, c = rc(i)
    return st.sol[r] == c
end

-- chats qui se genent (meme ligne, colonne, chambre, ou voisins)
local function conflicts()
    local bad, cats = {}, {}
    for i = 1, st.n * st.n do if st.cells[i] == CAT then cats[#cats + 1] = i end end
    for a = 1, #cats do
        for b = a + 1, #cats do
            local i, j = cats[a], cats[b]
            local r1, c1 = rc(i)
            local r2, c2 = rc(j)
            if r1 == r2 or c1 == c2 or st.reg[i] == st.reg[j] or (math.abs(r1 - r2) <= 1 and math.abs(c1 - c2) <= 1) then
                bad[i], bad[j] = true, true
            end
        end
    end
    return bad
end

-- cases interdites par les chats poses (affichage seulement)
local function blocked()
    local out = {}
    for i = 1, st.n * st.n do
        if st.cells[i] == CAT then
            local r1, c1 = rc(i)
            for j = 1, st.n * st.n do
                if j ~= i then
                    local r2, c2 = rc(j)
                    if r1 == r2 or c1 == c2 or st.reg[i] == st.reg[j] or (math.abs(r1 - r2) <= 1 and math.abs(c1 - c2) <= 1) then
                        out[j] = true
                    end
                end
            end
        end
    end
    return out
end

local function solved()
    local n = 0
    for i = 1, st.n * st.n do
        if st.cells[i] == CAT then
            if not solutionAt(i) then return false end
            n = n + 1
        end
    end
    return n == st.n
end

local function save()
    if not db then return end
    if st.state ~= "play" and st.state ~= "won" and st.state ~= "lost" then return end
    local reg, cells, sol = {}, {}, {}
    for i = 1, st.n * st.n do reg[i], cells[i] = st.reg[i], st.cells[i] end
    for r = 1, st.n do sol[r] = st.sol[r] end
    db.save = { n = st.n, reg = reg, sol = sol, cells = cells, time = st.time, hearts = st.hearts,
                hints = st.hints, daily = st.daily, state = st.state }
end

local function validSave(s)
    if type(s) ~= "table" or type(s.n) ~= "number" or s.n < 5 or s.n > 9 then return false end
    if type(s.reg) ~= "table" or type(s.sol) ~= "table" or type(s.cells) ~= "table" then return false end
    for i = 1, s.n * s.n do
        local k, v = s.reg[i], s.cells[i]
        if type(k) ~= "number" or k < 1 or k > s.n or (v ~= EMPTY and v ~= MARK and v ~= CAT) then return false end
    end
    for r = 1, s.n do
        local c = s.sol[r]
        if type(c) ~= "number" or c < 1 or c > s.n then return false end
    end
    return s.state == "play" or s.state == "won" or s.state == "lost"
end

local function load()
    local s = db and db.save
    if not validSave(s) then return false end
    st.n, st.reg, st.sol, st.cells = s.n, {}, {}, {}
    for i = 1, s.n * s.n do st.reg[i], st.cells[i] = s.reg[i], s.cells[i] end
    for r = 1, s.n do st.sol[r] = s.sol[r] end
    st.time = type(s.time) == "number" and s.time or 0
    st.hearts = type(s.hearts) == "number" and s.hearts or LIVES
    st.hints = type(s.hints) == "number" and s.hints or 0
    st.daily = type(s.daily) == "number" and s.daily or nil
    st.state = s.state
    st.undo, st.flash, st.job = {}, nil, nil
    return true
end

local refresh, buildBoard, showOverlay

local function begin(reg, sol, n, daily)
    st.n, st.reg, st.sol, st.daily = n, reg, sol, daily
    st.cells = {}
    for i = 1, n * n do st.cells[i] = EMPTY end
    st.time, st.hearts, st.hints, st.undo, st.flash = 0, LIVES, 0, {}, nil
    st.state = "play"
    st.job = nil
    save()
    if win then buildBoard() refresh() end
end

-- nouvelle grille : fabriquee par morceaux (une reprise par image)
local function newPuzzle(n, daily)
    n = n or st.n
    local seed
    if daily then
        seed = daily * 7 + n
    else
        seed = math.random(1, 2147483000)
    end
    -- la grille d avant reste dessinee (sous le voile) jusqu a la nouvelle
    st.state = "gen"
    st.job = coroutine.create(function() return generate(n, seed, coroutine.yield) end)
    st.jobN, st.jobDaily = n, daily
    if win then refresh() end
end

local function stepJob()
    if not st.job then return end
    local ok, reg, sol = coroutine.resume(st.job)
    if not ok then
        st.job = nil
        st.state = "idle"
        geterrorhandler()(reg)
        return
    end
    if coroutine.status(st.job) == "dead" then
        local n, daily = st.jobN, st.jobDaily
        st.job = nil
        if reg then begin(reg, sol, n, daily) end
    end
end

-- grille du jour : la meme pour tous (8 x 8) ; deja resolue : on la rejoue
local function dailyPuzzle()
    newPuzzle(DAILY_N, (today()))
end

local function restart()
    for i = 1, st.n * st.n do st.cells[i] = EMPTY end
    st.time, st.hearts, st.hints, st.undo, st.flash = 0, LIVES, 0, {}, nil
    st.state = "play"
    save()
    if win then refresh() end
end

local function finish()
    st.state = "won"
    local key = tostring(st.n)
    db.best = db.best or {}
    local prev = db.best[key]
    st.newBest = not prev or st.time < prev
    if st.newBest then db.best[key] = math.floor(st.time) end
    db.solved = (db.solved or 0) + 1
    if st.daily then
        db.dailyDone = db.dailyDone or {}
        if not db.dailyDone[st.daily] then
            db.dailyDone[st.daily] = math.floor(st.time)
            if db.lastDaily == st.daily - 1 then db.streak = (db.streak or 0) + 1 else db.streak = 1 end
            db.lastDaily = st.daily
            -- seulement les 30 derniers jours
            for d in pairs(db.dailyDone) do if d < st.daily - 30 then db.dailyDone[d] = nil end end
        end
    end
    play("carillon")
    save()
end

-- poser / changer une case ; group : actions annulees d un coup
local function setCell(i, v, group)
    local before = st.cells[i]
    if before == v then return false end
    st.cells[i] = v
    if group then group[#group + 1] = { i, before } end
    return true
end

local function pushUndo(group)
    if #group > 0 then
        st.undo[#st.undo + 1] = group
        if #st.undo > 200 then table.remove(st.undo, 1) end
    end
end

-- chat sur la case i (avec les vies : refuse s il n est pas a sa place)
local function putCat(i, group)
    if db.lives and not solutionAt(i) then
        st.hearts = st.hearts - 1
        st.flash = { i = i, t = 0 }
        play("erreur1")
        if st.hearts <= 0 then
            st.state = "lost"
            play("trombone")
        end
        return false
    end
    setCell(i, CAT, group)
    play("verre")
    return true
end

-- clic : vide -> empreinte -> chat -> vide
local function clickCell(i)
    if st.state ~= "play" or not st.cells[i] then return end
    local group = {}
    local v = st.cells[i]
    if v == EMPTY then
        setCell(i, MARK, group)
    elseif v == MARK then
        putCat(i, group)    -- mal place (vies) : l empreinte reste
    else
        setCell(i, EMPTY, group)
    end
    pushUndo(group)
    if st.state == "play" and solved() then finish() end
    save()
    if win then refresh() end
end

-- clic droit : empreinte posee ou retiree
local function markCell(i)
    if st.state ~= "play" or not st.cells[i] then return end
    local group = {}
    setCell(i, st.cells[i] == MARK and EMPTY or MARK, group)
    pushUndo(group)
    save()
    if win then refresh() end
end

local function undo()
    if st.state ~= "play" then return false end
    local group = table.remove(st.undo)
    if not group then return false end
    for k = #group, 1, -1 do st.cells[group[k][1]] = group[k][2] end
    save()
    if win then refresh() end
    return true
end

-- indice : un chat de la solution dans une chambre qui n a pas le sien
local function hint()
    if st.state ~= "play" then return false end
    local todo = {}
    for r = 1, st.n do
        local i = (r - 1) * st.n + st.sol[r]
        if st.cells[i] ~= CAT then todo[#todo + 1] = i end
    end
    if #todo == 0 then return false end
    local i = todo[math.random(#todo)]
    local k = st.reg[i]
    local r0, c0 = rc(i)
    -- chats mal places qui le generaient : retires
    for j = 1, st.n * st.n do
        if st.cells[j] == CAT and not solutionAt(j) then
            local r, c = rc(j)
            if r == r0 or c == c0 or st.reg[j] == k or (math.abs(r - r0) <= 1 and math.abs(c - c0) <= 1) then
                st.cells[j] = EMPTY
            end
        end
    end
    st.cells[i] = CAT
    st.hints = st.hints + 1
    st.time = st.time + HINT_COST
    st.undo = {}
    play("question")
    if solved() then finish() end
    save()
    if win then refresh() end
    return true
end

---------------------------------------------------------------------------
-- Dessin
---------------------------------------------------------------------------

local function newCell()
    local c = {}
    c.bg = board:CreateTexture(nil, "BACKGROUND", nil, 1)
    c.shade = board:CreateTexture(nil, "BACKGROUND", nil, 2)
    c.err = board:CreateTexture(nil, "BORDER")
    c.err:SetColorTexture(0.9, 0.12, 0.1, 0.45)
    c.mark = board:CreateTexture(nil, "ARTWORK")
    c.mark:SetTexture(SHEET)
    c.mark:SetTexCoord(sprite(PAW))
    c.cat = board:CreateTexture(nil, "ARTWORK", nil, 1)
    c.cat:SetTexture(SHEET)
    return c
end

local function newLine()
    local t = board:CreateTexture(nil, "BORDER", nil, 2)
    t:SetColorTexture(0.04, 0.03, 0.03, 1)
    return t
end

-- cases et murs des chambres pour la grille en cours
function buildBoard()
    if not board or not st.reg then return end
    local n = st.n
    cellSize = math.floor(BOARD / n)
    local size = cellSize * n
    board:SetSize(size, size)
    for i = 1, n * n do
        local c = cellsUI[i] or newCell()
        cellsUI[i] = c
        local r, col = rc(i)
        local x, y = (col - 1) * cellSize, -(r - 1) * cellSize
        local k = st.reg[i]
        local tint = ROOMS[k]
        c.bg:ClearAllPoints()
        c.bg:SetPoint("TOPLEFT", board, "TOPLEFT", x, y)
        c.bg:SetSize(cellSize, cellSize)
        c.bg:SetColorTexture(tint[1], tint[2], tint[3], 1)
        -- damier tres leger pour lire les lignes
        c.shade:ClearAllPoints()
        c.shade:SetPoint("TOPLEFT", board, "TOPLEFT", x + 1, y - 1)
        c.shade:SetSize(cellSize - 2, cellSize - 2)
        c.shade:SetColorTexture(1, 1, 1, ((r + col) % 2 == 0) and 0.07 or 0.0)
        c.err:ClearAllPoints()
        c.err:SetPoint("TOPLEFT", board, "TOPLEFT", x, y)
        c.err:SetSize(cellSize, cellSize)
        local m = math.floor(cellSize * 0.18)
        c.mark:ClearAllPoints()
        c.mark:SetPoint("TOPLEFT", board, "TOPLEFT", x + m, y - m)
        c.mark:SetSize(cellSize - 2 * m, cellSize - 2 * m)
        c.cat:ClearAllPoints()
        c.cat:SetPoint("TOPLEFT", board, "TOPLEFT", x + 1, y - 1)
        c.cat:SetSize(cellSize - 2, cellSize - 2)
        c.cat:SetTexCoord(sprite(k))
        c.bg:Show() c.shade:Show()
    end
    for i = n * n + 1, #cellsUI do
        local c = cellsUI[i]
        c.bg:Hide() c.shade:Hide() c.err:Hide() c.mark:Hide() c.cat:Hide()
    end
    -- murs : traits fins entre cases, epais entre chambres et autour
    local used = 0
    local function line(x, y, w, h)
        used = used + 1
        local t = lines[used] or newLine()
        lines[used] = t
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", board, "TOPLEFT", x, y)
        t:SetSize(w, h)
        t:Show()
    end
    for i = 1, n * n do
        local r, col = rc(i)
        local x, y = (col - 1) * cellSize, -(r - 1) * cellSize
        if col < n then
            if st.reg[i] ~= st.reg[i + 1] then line(x + cellSize - 1, y, 3, cellSize)
            else line(x + cellSize, y, 1, cellSize) end
        end
        if r < n then
            if st.reg[i] ~= st.reg[i + n] then line(x, y - cellSize + 1, cellSize, 3)
            else line(x, y - cellSize, cellSize, 1) end
        end
    end
    line(-2, 2, size + 4, 3)
    line(-2, -size + 1, size + 4, 3)
    line(-2, 2, 3, size + 4)
    line(size - 1, 2, 3, size + 4)
    for j = used + 1, #lines do lines[j]:Hide() end
    -- traits fins moins visibles que les murs
    for j = 1, used do
        local t = lines[j]
        local w, h = t:GetSize()
        if w == 1 or h == 1 then t:SetColorTexture(0, 0, 0, 0.28) else t:SetColorTexture(0.06, 0.04, 0.03, 1) end
    end
end

local function paintCells()
    if not board or not st.reg then return end
    local bad = (not db.lives) and conflicts() or {}
    local block = db.auto and st.state == "play" and blocked() or {}
    local f = st.flash
    for i = 1, st.n * st.n do
        local c = cellsUI[i]
        local v = st.cells[i]
        if f and f.i == i then
            c.cat:Show()
            c.cat:SetVertexColor(1, 0.35, 0.35)
            c.cat:SetAlpha(1 - f.t / FLASH_T * 0.6)
            c.err:Show()
        else
            c.cat:SetShown(v == CAT)
            c.cat:SetVertexColor(1, 1, 1)
            c.cat:SetAlpha(1)
            c.err:SetShown(v == CAT and bad[i] or false)
        end
        if v == MARK then
            c.mark:Show()
            c.mark:SetAlpha(0.75)
        elseif v == EMPTY and block[i] then
            c.mark:Show()
            c.mark:SetAlpha(0.28)
        else
            c.mark:Hide()
        end
    end
end

function showOverlay(title, line1, b1, b2)
    overlay.title:SetText(title)
    overlay.line:SetText(line1 or "")
    overlay.b1:SetShown(b1 ~= nil)
    overlay.b2:SetShown(b2 ~= nil)
    if b1 then
        overlay.b1:SetText(b1.text)
        overlay.b1.fn = b1.fn
        overlay.b1:ClearAllPoints()
        if b2 then overlay.b1:SetPoint("TOPRIGHT", overlay.line, "BOTTOM", -4, -14)
        else overlay.b1:SetPoint("TOP", overlay.line, "BOTTOM", 0, -14) end
    end
    if b2 then
        overlay.b2:SetText(b2.text)
        overlay.b2.fn = b2.fn
    end
    overlay:Show()
end

local sureUntil = 0

local function bestOf(n)
    local b = db.best and db.best[tostring(n)]
    return b and clock(b) or L.CHA_NONE
end

function refresh()
    if not win then return end
    -- vies
    for k, h in ipairs(hud.hearts) do
        h:SetShown(db.lives)
        h:SetDesaturated(k > st.hearts)
        h:SetAlpha(k > st.hearts and 0.3 or 1)
    end
    hud.size:Refresh()
    hud.new:SetText(GetTime() < sureUntil and L.CHA_SURE or L.CHA_NEW)
    local playing = st.state == "play"
    hud.hint:SetEnabled(playing)
    hud.undo:SetEnabled(playing and #st.undo > 0)
    local status
    if st.daily then
        local _, t = today()
        local done = db.dailyDone and db.dailyDone[st.daily]
        if done then status = string.format(L.CHA_DAILY_DONE, clock(done))
        else status = string.format(L.CHA_STATUS_DAILY, date("%d/%m", t), bestOf(st.n)) end
    else
        status = string.format(L.CHA_STATUS, st.n, st.n, bestOf(st.n))
    end
    if InCombatLockdown() then status = L.CHA_COMBAT end
    hud.status:SetText(status)
    hud.timer:SetText(clock(st.time))
    if st.state ~= "gen" then paintCells() end
    if st.state == "gen" then
        showOverlay(L.CHA_TITLE, L.CHA_GEN)
    elseif st.state == "idle" then
        showOverlay(L.CHA_TITLE, L.CHA_RULES_SHORT, { text = L.CHA_NEW, fn = function() newPuzzle(db.size) end },
            { text = L.CHA_DAILY, fn = function() dailyPuzzle() end })
    elseif st.state == "won" then
        local line = string.format(L.CHA_WIN2, clock(st.time))
        if st.newBest then line = line .. "\n|cffffd100" .. L.CHA_NEW_BEST .. "|r" end
        if st.daily and (db.streak or 0) > 1 then line = line .. "\n" .. string.format(L.CHA_STREAK, db.streak) end
        showOverlay(L.CHA_WIN, line, { text = L.CHA_NEW, fn = function() newPuzzle(db.size) end })
    elseif st.state == "lost" then
        showOverlay(L.CHA_LOST, L.CHA_LOST2, { text = L.CHA_RETRY, fn = function() restart() end },
            { text = L.CHA_NEW, fn = function() newPuzzle(db.size) end })
    else
        overlay:Hide()
    end
end

---------------------------------------------------------------------------
-- Fenetre
---------------------------------------------------------------------------

local function cellUnderCursor()
    if not board or not st.reg then return nil end
    local left, top = board:GetLeft(), board:GetTop()
    if not left or not top then return nil end
    local x, y = GetCursorPosition()
    local s = board:GetEffectiveScale()
    x, y = x / s - left, top - y / s
    local col, r = math.floor(x / cellSize) + 1, math.floor(y / cellSize) + 1
    if col < 1 or r < 1 or col > st.n or r > st.n then return nil end
    return (r - 1) * st.n + col
end

local function setKeyboard(on)
    if not win then return end
    pcall(win.EnableKeyboard, win, on and not InCombatLockdown())
end

-- glisser : empreintes sur les cases vides survolees (une action annulable)
local drag

local function build()
    db.pos = db.pos or { point = "CENTER", x = 0, y = 40 }
    win = CreateFrame("Frame", "CorpUIChatsGame", UIParent)
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
    title:SetText(L.CHA_TITLE)
    local close = CreateFrame("Button", nil, bar)
    close:SetSize(22, 22)
    close:SetPoint("RIGHT", -4, 0)
    local x = close:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    x:SetPoint("CENTER")
    x:SetText("×")
    close:SetScript("OnClick", function() win:Hide() end)
    -- vies, chrono, taille
    hud = { hearts = {} }
    for k = 1, LIVES do
        local h = win:CreateTexture(nil, "ARTWORK")
        h:SetSize(20, 20)
        h:SetPoint("TOPLEFT", win, "TOPLEFT", 10 + (k - 1) * 22, -36)
        h:SetTexture(SHEET)
        h:SetTexCoord(sprite(HEART))
        hud.hearts[k] = h
    end
    hud.timer = win:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(hud.timer, 16)
    hud.timer:SetPoint("TOP", win, "TOP", 0, -37)
    hud.timer:SetTextColor(1, 1, 1)
    local sizes = function()
        local list = {}
        for _, n in ipairs(SIZES) do list[#list + 1] = { value = n, text = string.format(L.CHA_SIZE, n, n) } end
        return list
    end
    hud.size = ns.UI.Select(win, 84, sizes, function() return db.size end, function(v)
        db.size = v
        newPuzzle(v)
    end)
    hud.size:SetPoint("TOPRIGHT", win, "TOPRIGHT", -12, -35)
    -- grille
    local frame = CreateFrame("Frame", nil, win)
    frame:SetSize(BOARD + 8, BOARD + 8)
    frame:SetPoint("TOP", win, "TOP", 0, -64)
    local back = frame:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(0.03, 0.025, 0.02, 0.95)
    board = CreateFrame("Frame", nil, frame)
    board:SetSize(BOARD, BOARD)
    board:SetPoint("CENTER")
    board:EnableMouse(true)
    board:SetScript("OnMouseDown", function(_, button)
        local i = cellUnderCursor()
        if not i or st.state ~= "play" then return end
        if button == "RightButton" then
            markCell(i)
        else
            drag = { start = i, last = i, moved = false, group = {} }
        end
    end)
    board:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" or not drag then return end
        local d = drag
        drag = nil
        if d.moved then
            pushUndo(d.group)
            save()
            refresh()
        else
            clickCell(d.start)
        end
    end)
    board:SetScript("OnUpdate", function(_, dt)
        if st.job then stepJob() end
        if st.state == "play" then
            st.time = st.time + dt
            hud.timer:SetText(clock(st.time))
        end
        if st.flash then
            st.flash.t = st.flash.t + dt
            if st.flash.t >= FLASH_T then st.flash = nil refresh() else paintCells() end
        end
        if drag and st.state == "play" then
            local i = cellUnderCursor()
            if i and i ~= drag.last then
                if not drag.moved then
                    drag.moved = true
                    if st.cells[drag.start] == EMPTY then setCell(drag.start, MARK, drag.group) end
                end
                drag.last = i
                if st.cells[i] == EMPTY then setCell(i, MARK, drag.group) end
                paintCells()
            end
        end
    end)
    -- fin de partie, fabrication
    overlay = CreateFrame("Frame", nil, frame)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(board:GetFrameLevel() + 20)
    local shade = overlay:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    shade:SetColorTexture(0, 0, 0, 0.66)
    local yarn = overlay:CreateTexture(nil, "ARTWORK")
    yarn:SetSize(56, 56)
    yarn:SetPoint("CENTER", 0, 80)
    yarn:SetTexture(SHEET)
    yarn:SetTexCoord(sprite(YARN))
    overlay.title = overlay:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(overlay.title, 20)
    overlay.title:SetPoint("TOP", yarn, "BOTTOM", 0, -6)
    overlay.title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    overlay.line = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    overlay.line:SetPoint("TOP", overlay.title, "BOTTOM", 0, -10)
    overlay.line:SetWidth(BOARD - 40)
    overlay.b1 = ns.UI.Button(overlay, "", 120, function(self) if self.fn then self.fn() end end)
    overlay.b2 = ns.UI.Button(overlay, "", 120, function(self) if self.fn then self.fn() end end)
    overlay.b2:SetPoint("LEFT", overlay.b1, "RIGHT", 8, 0)
    overlay:EnableMouse(true)
    overlay:Hide()
    -- boutons du bas
    local bw = math.floor((WIN_W - 24 - 3 * 6) / 4)
    hud.new = ns.UI.Button(win, L.CHA_NEW, bw, function()
        if st.state == "play" and GetTime() >= sureUntil then
            sureUntil = GetTime() + 3
            refresh()
            C_Timer.After(3.05, function() if win and win:IsShown() then refresh() end end)
            return
        end
        sureUntil = 0
        newPuzzle(db.size)
    end)
    hud.new:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -64 - BOARD - 16)
    hud.daily = ns.UI.Button(win, L.CHA_DAILY, bw, function() dailyPuzzle() end)
    hud.daily:SetPoint("LEFT", hud.new, "RIGHT", 6, 0)
    hud.hint = ns.UI.Button(win, L.CHA_HINT_BTN, bw, function() hint() end)
    hud.hint:SetPoint("LEFT", hud.daily, "RIGHT", 6, 0)
    hud.hint:HookScript("OnEnter", function(self)
        local t = ns.Tooltip(self, "ANCHOR_TOP")
        t:AddLine(string.format(L.CHA_TIP_HINT, HINT_COST), 1, 1, 1)
        t:Show()
    end)
    hud.hint:HookScript("OnLeave", ns.HideTooltip)
    hud.undo = ns.UI.Button(win, L.CHA_UNDO, bw, function() undo() end)
    hud.undo:SetPoint("LEFT", hud.hint, "RIGHT", 6, 0)
    hud.status = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hud.status:SetPoint("TOP", win, "TOP", 0, -64 - BOARD - 46)
    hud.status:SetWidth(WIN_W - 24)
    local help = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    help:SetPoint("TOP", hud.status, "BOTTOM", 0, -4)
    help:SetWidth(WIN_W - 24)
    help:SetText(L.CHA_HELP)
    -- clavier : annuler, Echap
    win:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        if key == "BACKSPACE" or (key == "Z" and IsControlKeyDown()) then
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
        if st.state == "idle" and load() then buildBoard() end
        if st.reg then buildBoard() end
        refresh()
    end)
    win:SetScript("OnHide", function()
        setKeyboard(false)
        drag = nil
        save()
    end)
    win:Hide()
end

local function toggle()
    if not db then return end
    if not win then build() end
    win:SetShown(not win:IsShown())
end

-- liste des jeux : ouverture pendant un vol, ligne de la page des
-- mini-jeux (Jeux.lua), avec ses reglages
ns.Games.Register("chats", {
    title = function() return L.MOD_CHATS end,
    open = function()
        if not db then return false end
        if not win then build() end
        win:Show()
        return true
    end,
    close = function() if win then win:Hide() end end,
    shown = function() return win and win:IsShown() or false end,
    ready = function() return db ~= nil end,
    play = function() toggle() end,
    icon = function() return MEDIA .. "chats_icone", 0, 1, 0, 1 end,
    tagline = function() return L.CHA_DESC end,
    hint = function() return L.CHA_HINT end,
    stats = function()
        return string.format(L.CHA_STATS, db.solved or 0, db.streak or 0)
            .. "   ·   " .. string.format(L.CHA_BEST_SIZE, db.size, db.size, bestOf(db.size))
    end,
    foot = function() return L.CHA_CREDITS end,
    options = function(form)
        form:Check(L.MURLOC_OPT_SOUND, function() return db.sound end, function(v) db.sound = v end)
        form:Check(L.CHA_OPT_LIVES, function() return db.lives end, function(v) db.lives = v end)
        form:Check(L.CHA_OPT_AUTO, function() return db.auto end, function(v) db.auto = v end)
        form:Number(L.MURLOC_OPT_SCALE, function() return math.floor((db.scale or 1) * 100 + 0.5) end,
            function(v) db.scale = v / 100 end, 60, 150, 5)
    end,
    apply = function()
        if win then
            win:SetScale(db.scale or 1)
            refresh()
        end
    end,
})

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if ns.ModuleOff("jeux", ev) then return end
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        if type(root.games) ~= "table" then root.games = {} end
        if type(root.games.chats) ~= "table" then root.games.chats = {} end
        db = root.games.chats
        if db.sound == nil then db.sound = true end
        if db.lives == nil then db.lives = true end
        if db.auto == nil then db.auto = false end
        if type(db.scale) ~= "number" then db.scale = 1 end
        if type(db.size) ~= "number" or db.size < 5 or db.size > 9 then db.size = 7 end
        if type(db.best) ~= "table" then db.best = {} end
        load()
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        -- combat : clavier rendu au jeu (la souris marche toujours)
        if win and win:IsShown() then
            setKeyboard(event == "PLAYER_REGEN_ENABLED")
            refresh()
        end
    elseif event == "PLAYER_LOGOUT" then
        save()
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_LOGOUT" }) do
    pcall(ev.RegisterEvent, ev, e)
end

ns.RegisterModule({
    command = "chats",
    alias = "felins",
    icon = MEDIA .. "chats_icone",
    title = function() return L.MOD_CHATS end,
    desc = function() return L.CHA_DESC end,
    Slash = function(rest)
        rest = strlower(strtrim(rest or ""))
        if rest == "options" or rest == "config" then ns.Games.ShowOptions("chats") else toggle() end
    end,
})

-- banc d essai
ns._chats = { st = st, generate = generate, otherSolution = otherSolution, newRng = newRng, placeCats = placeCats,
              newPuzzle = newPuzzle, stepJob = stepJob, dailyPuzzle = dailyPuzzle, begin = begin,
              clickCell = clickCell, markCell = markCell, undo = undo, hint = hint, restart = restart,
              solved = solved, conflicts = conflicts, blocked = blocked, save = save, load = load, toggle = toggle,
              today = today, clock = clock,
              ui = function() return win, board, overlay, hud, cellsUI, lines end,
              drag = function() return drag end }
