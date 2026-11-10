--[[--------------------------------------------------------------------------
    CorpUI - module Jeux : l etabli du joaillier

    Aligner les gemmes : sur une grille de 8 x 8, on echange deux gemmes
    voisines pour en aligner trois ou plus de la meme sorte ; elles partent,
    celles du dessus tombent, de nouvelles arrivent par le haut (cascades :
    points multiplies). Six sortes, une couleur chacune : malachite, oeil de
    tigre, ombre-gemme, pierre de lune inferieure, rubis etoile, saphir bleu
    (icones lues sur le client), chacune avec son lisere.
      - 4 alignees : gemme taillee (vide sa ligne, ou sa colonne, quand elle
        part) ; en L ou en T : gemme eclatante (explose en 3 x 3) ; 5
        alignees : diamant (diamant azerothien), qui, echange avec une
        gemme, fait partir toutes celles de cette sorte (deux diamants :
        toute la grille) ;
      - une partie = 30 coups ; un echange sans alignement revient en
        arriere sans compter ; plus aucun coup possible : gemmes melangees ;
      - clic puis clic sur une voisine, ou glisser une gemme ; clic droit :
        lacher la gemme choisie ; indice (halo) apres 6 s sans jouer
        (reglage) ; Echap : fermer ;
      - la partie est gardee (fermer, /reload, vol suivant) ;
      - en combat : clavier rendu au jeu, la souris marche toujours (jeu au
        tour par tour : pas de pause) ;
      - sons de CorpUI : verre a chaque alignement, montee pour une gemme
        speciale, bong pour un diamant, ding aux grandes cascades, ding
        grave au melange, carillon au record, trombone triste a la fin.
    Les regles se jouent d un coup (etat final aussitot, sauvegardable) ;
    l animation rejoue ensuite les etapes notees (echange, disparition,
    chute, melange). Fenetre a nous, deplacable ; rien de Blizzard n est
    touche.
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local C = ns.COLORS

local SOUNDS = ns.MEDIA .. "Sons\\"

local N = 8
local TILE, GAP = 44, 3
local BOARD = N * TILE + (N + 1) * GAP    -- 379
local WIN_W, WIN_H = BOARD + 24, 500
local MOVES = 30
local HINT_DELAY = 6
local KINDS = 6
local DIAMOND = 7                          -- sorte du diamant (ne s aligne pas)
local SP_ROW, SP_COL, SP_BOMB = 1, 2, 3    -- taillee (ligne, colonne), eclatante
local SWAP, CLEAR, FALL_ROW, SHUFFLE = 0.14, 0.18, 0.06, 0.3
local POINTS = 10
local BONUS = { [SP_ROW] = 40, [SP_COL] = 40, [SP_BOMB] = 80 }
local BONUS_DIAMOND = 150
local DRAG = 14                            -- pixels pour un glisser

-- sortes : objets du jeu (icone lue sur le client, celle du fichier si
-- l objet n est pas encore connu) ; lisere propre a chaque sorte
local GEMS = {
    { id = 774,   file = "inv_misc_gem_emerald_03",  r = 0.25, g = 0.9,  b = 0.35 },  -- malachite
    { id = 818,   file = "inv_misc_gem_opal_03",     r = 1,    g = 0.6,  b = 0.15 },  -- oeil de tigre
    { id = 1210,  file = "inv_misc_gem_amethyst_01", r = 0.72, g = 0.4,  b = 1 },     -- ombre-gemme
    { id = 1705,  file = "inv_misc_gem_crystal_01",  r = 0.85, g = 0.92, b = 1 },     -- pierre de lune inferieure
    { id = 7910,  file = "inv_misc_gem_ruby_02",     r = 1,    g = 0.22, b = 0.25 },  -- rubis etoile
    { id = 12361, file = "inv_misc_gem_sapphire_02", r = 0.25, g = 0.55, b = 1 },     -- saphir bleu
    { id = 12800, file = "inv_misc_gem_diamond_01",  r = 1,    g = 1,    b = 1 },     -- diamant azerothien
}

local function clean(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) and v or nil end

local icons = {}
local function iconOf(k)
    local gem = GEMS[k] or GEMS[1]
    if icons[k] then return icons[k] end
    local tex
    if C_Item and C_Item.GetItemIconByID then
        local ok, v = pcall(C_Item.GetItemIconByID, gem.id)
        if ok then tex = clean(v) end
    end
    if not tex and GetItemIcon then
        local ok, v = pcall(GetItemIcon, gem.id)
        if ok then tex = clean(v) end
    end
    if tex then icons[k] = tex return tex end
    return "Interface\\Icons\\" .. gem.file
end

local db
local win, board, overlay, hud, selBox, hintBox
local tiles, used = {}, 0
local anim                -- { steps, n, t, entered } : etapes rejouees
-- kind : sorte par case (0 = vide, 1-6, DIAMOND) ; spec : gemme speciale
local st = { kind = {}, spec = {}, score = 0, moves = MOVES, over = false, startBest = 0, ready = false }
for i = 1, N * N do st.kind[i], st.spec[i] = 0, 0 end
local sel                 -- case choisie (clic puis clic)
local idle, hint = 0, nil
local msg, msgUntil = nil, 0
local rand = math.random
local refresh, drawFinal, finishAnim

local function play(file)
    if db and db.sound then pcall(PlaySoundFile, SOUNDS .. file .. ".ogg", "Master") end
end

local function say(text)
    msg, msgUntil = text, GetTime() + 3
end

---------------------------------------------------------------------------
-- Regles
---------------------------------------------------------------------------

local function idx(r, c) return (r - 1) * N + c end
local function rc(i) return math.floor((i - 1) / N) + 1, (i - 1) % N + 1 end

local function adjacent(a, b)
    if not a or not b or a < 1 or b < 1 or a > N * N or b > N * N then return false end
    local ra, ca = rc(a)
    local rb, cb = rc(b)
    return math.abs(ra - rb) + math.abs(ca - cb) == 1
end

local function swapCells(a, b)
    st.kind[a], st.kind[b] = st.kind[b], st.kind[a]
    st.spec[a], st.spec[b] = st.spec[b], st.spec[a]
end

local function copy(t)
    local o = {}
    for i = 1, N * N do o[i] = t[i] end
    return o
end

local function snapshot() return { kind = copy(st.kind), spec = copy(st.spec) } end

-- alignements de 3 ou plus : { dir = "h" ou "v", k, cells }
local function findRuns()
    local K, runs = st.kind, {}
    for r = 1, N do
        local c = 1
        while c <= N do
            local k, e = K[idx(r, c)], c
            while e < N and K[idx(r, e + 1)] == k do e = e + 1 end
            if k >= 1 and k <= KINDS and e - c >= 2 then
                local cells = {}
                for x = c, e do cells[#cells + 1] = idx(r, x) end
                runs[#runs + 1] = { dir = "h", k = k, cells = cells }
            end
            c = e + 1
        end
    end
    for c = 1, N do
        local r = 1
        while r <= N do
            local k, e = K[idx(r, c)], r
            while e < N and K[idx(e + 1, c)] == k do e = e + 1 end
            if k >= 1 and k <= KINDS and e - r >= 2 then
                local cells = {}
                for y = r, e do cells[#cells + 1] = idx(y, c) end
                runs[#runs + 1] = { dir = "v", k = k, cells = cells }
            end
            r = e + 1
        end
    end
    return runs
end

-- la case i est-elle dans un alignement ?
local function lineAt(i)
    local k = st.kind[i]
    if k < 1 or k > KINDS then return false end
    local r, c = rc(i)
    local n, x = 1, c - 1
    while x >= 1 and st.kind[idx(r, x)] == k do n, x = n + 1, x - 1 end
    x = c + 1
    while x <= N and st.kind[idx(r, x)] == k do n, x = n + 1, x + 1 end
    if n >= 3 then return true end
    local y
    n, y = 1, r - 1
    while y >= 1 and st.kind[idx(y, c)] == k do n, y = n + 1, y - 1 end
    y = r + 1
    while y <= N and st.kind[idx(y, c)] == k do n, y = n + 1, y + 1 end
    return n >= 3
end

-- echange qui compte : un alignement, ou un diamant dans l affaire
local function validSwap(a, b)
    if st.kind[a] == 0 or st.kind[b] == 0 then return false end
    if st.kind[a] == DIAMOND or st.kind[b] == DIAMOND then return true end
    swapCells(a, b)
    local ok = lineAt(a) or lineAt(b)
    swapCells(a, b)
    return ok
end

-- premier coup possible (rend ses deux cases), nil s il n y en a aucun
local function findMove()
    for r = 1, N do
        for c = 1, N do
            local i = idx(r, c)
            if c < N and validSwap(i, i + 1) then return i, i + 1 end
            if r < N and validSwap(i, i + N) then return i, i + N end
        end
    end
    return nil
end

-- sorte la plus nombreuse (diamant pris dans un effet)
local function commonKind()
    local count, best, bestN = {}, 1, -1
    for i = 1, N * N do
        local k = st.kind[i]
        if k >= 1 and k <= KINDS then count[k] = (count[k] or 0) + 1 end
    end
    for k = 1, KINDS do
        if (count[k] or 0) > bestN then best, bestN = k, count[k] or 0 end
    end
    return best
end

-- case qui recoit la gemme speciale : une case bougee par le joueur,
-- sinon le milieu de l alignement
local function pick(cells, moved, create)
    if moved then
        for _, i in ipairs(cells) do if moved[i] and not create[i] then return i end end
    end
    local mid = cells[math.floor((#cells + 1) / 2)]
    if not create[mid] then return mid end
    for _, i in ipairs(cells) do if not create[i] then return i end end
end

-- alignements presents : cases qui partent (clear) et gemmes speciales qui
-- naissent (create[i] = { k, sp }) ; nil s il n y a rien
local function analyze(moved)
    local runs = findRuns()
    if #runs == 0 then return nil end
    local clear, create, spent, inRun = {}, {}, {}, {}
    for ri, run in ipairs(runs) do
        for _, i in ipairs(run.cells) do
            clear[i] = true
            inRun[i] = inRun[i] or {}
            table.insert(inRun[i], ri)
        end
    end
    -- 5 alignees : diamant
    for ri, run in ipairs(runs) do
        if #run.cells >= 5 then
            local at = pick(run.cells, moved, create)
            if at then create[at], spent[ri] = { k = DIAMOND, sp = 0 }, true end
        end
    end
    -- croisement d un alignement en ligne et d un en colonne (L, T) : eclatante
    for i = 1, N * N do
        local list = inRun[i]
        if list and #list >= 2 and not create[i] and not spent[list[1]] and not spent[list[2]] then
            create[i] = { k = st.kind[i], sp = SP_BOMB }
            spent[list[1]], spent[list[2]] = true, true
        end
    end
    -- 4 alignees : taillee, dans le sens de l alignement
    for ri, run in ipairs(runs) do
        if not spent[ri] and #run.cells == 4 then
            local at = pick(run.cells, moved, create)
            if at then
                create[at] = { k = run.k, sp = run.dir == "h" and SP_ROW or SP_COL }
                spent[ri] = true
            end
        end
    end
    return clear, create
end

-- effets des gemmes speciales qui partent, en chaine ; fired : cases dont
-- l effet est deja joue (diamants echanges)
local function expand(clear, fired)
    fired = fired or {}
    local queue = {}
    for i = 1, N * N do if clear[i] then queue[#queue + 1] = i end end
    local function add(j)
        if not clear[j] then
            clear[j] = true
            queue[#queue + 1] = j
        end
    end
    local q = 1
    while q <= #queue do
        local i = queue[q]
        q = q + 1
        if not fired[i] then
            fired[i] = true
            local sp, k = st.spec[i], st.kind[i]
            local r, c = rc(i)
            if sp == SP_ROW then
                for x = 1, N do add(idx(r, x)) end
            elseif sp == SP_COL then
                for y = 1, N do add(idx(y, c)) end
            elseif sp == SP_BOMB then
                for y = r - 1, r + 1 do
                    for x = c - 1, c + 1 do
                        if y >= 1 and y <= N and x >= 1 and x <= N then add(idx(y, x)) end
                    end
                end
            elseif k == DIAMOND then
                local kk = commonKind()
                for j = 1, N * N do if st.kind[j] == kk then add(j) end end
            end
        end
    end
    return clear
end

-- chute dans chaque colonne et remplissage par le haut ; from[i] = rangee
-- d ou part la gemme arrivee en i (0, -1... : au-dessus de la grille)
local function gravity()
    local from = {}
    for c = 1, N do
        local write = N
        for r = N, 1, -1 do
            local i = idx(r, c)
            if st.kind[i] > 0 then
                local j = idx(write, c)
                if j ~= i then
                    st.kind[j], st.spec[j] = st.kind[i], st.spec[i]
                    st.kind[i], st.spec[i] = 0, 0
                end
                from[j] = r
                write = write - 1
            end
        end
        local empty = write
        for r = write, 1, -1 do
            local j = idx(r, c)
            st.kind[j], st.spec[j] = rand(KINDS), 0
            from[j] = r - empty
        end
    end
    return from
end

-- une vague : effets, points, disparition, chute ; rend les points et la
-- plus belle gemme nee ("diamond", "bomb", "cut")
local function blast(clear, create, cascade, steps, fired)
    expand(clear, fired)
    local n, bonus, made = 0, 0, nil
    for i = 1, N * N do
        local cr = create[i]
        if cr then
            if cr.k == DIAMOND then
                bonus, made = bonus + BONUS_DIAMOND, "diamond"
            else
                bonus = bonus + (BONUS[cr.sp] or 0)
                if cr.sp == SP_BOMB and made ~= "diamond" then made = "bomb"
                elseif not made then made = "cut" end
            end
        elseif clear[i] then
            n = n + 1
        end
    end
    steps[#steps + 1] = { t = "clear", snap = snapshot(), cells = clear, create = create, cascade = cascade }
    for i = 1, N * N do
        local cr = create[i]
        if cr then
            st.kind[i], st.spec[i] = cr.k, cr.sp
        elseif clear[i] then
            st.kind[i], st.spec[i] = 0, 0
        end
    end
    local from = gravity()
    steps[#steps + 1] = { t = "fall", snap = snapshot(), from = from }
    return (n * POINTS + bonus) * cascade, made
end

local MADE_RANK = { cut = 1, bomb = 2, diamond = 3 }

-- alignements en chaine (cascade 1, 2, 3...) ; rend points, plus haute
-- cascade, plus belle gemme nee
local function cascades(moved, steps, cascade)
    local gained, top, best = 0, cascade - 1, nil
    while true do
        local clear, create = analyze(moved)
        if not clear then break end
        local g, made = blast(clear, create, cascade, steps)
        steps[#steps - 1].snd = made and "montee" or (cascade >= 3 and "ding" or "verre")
        gained, top = gained + g, cascade
        if made and (not best or MADE_RANK[made] > MADE_RANK[best]) then best = made end
        cascade = cascade + 1
        moved = nil
    end
    return gained, top, best
end

-- grille neuve sans alignement, avec au moins un coup
local function fresh()
    for _ = 1, 50 do
        for r = 1, N do
            for c = 1, N do
                local i = idx(r, c)
                local k
                for _ = 1, 20 do
                    k = rand(KINDS)
                    local h = c > 2 and st.kind[i - 1] == k and st.kind[i - 2] == k
                    local v = r > 2 and st.kind[i - N] == k and st.kind[i - 2 * N] == k
                    if not h and not v then break end
                end
                st.kind[i], st.spec[i] = k, 0
            end
        end
        if #findRuns() == 0 and findMove() then return end
    end
end

-- plus de coup : les memes gemmes, melangees (grille neuve si le melange
-- ne donne rien de jouable)
local function shuffle()
    local bag = {}
    for i = 1, N * N do bag[i] = { st.kind[i], st.spec[i] } end
    for _ = 1, 100 do
        for i = #bag, 2, -1 do
            local j = rand(i)
            bag[i], bag[j] = bag[j], bag[i]
        end
        for i = 1, N * N do st.kind[i], st.spec[i] = bag[i][1], bag[i][2] end
        if #findRuns() == 0 and findMove() then return end
    end
    fresh()
end

local function save()
    if not db then return end
    db.save = { kind = copy(st.kind), spec = copy(st.spec), score = st.score, moves = st.moves,
                over = st.over, startBest = st.startBest }
end

local function validCells(t, max)
    if type(t) ~= "table" then return false end
    for i = 1, N * N do
        local v = t[i]
        if type(v) ~= "number" or v < 0 or v > max or v ~= math.floor(v) then return false end
    end
    return true
end

-- partie gardee (rend false si rien de valable)
local function load()
    local s = db and db.save
    if type(s) ~= "table" or not validCells(s.kind, DIAMOND) or not validCells(s.spec, SP_BOMB)
        or type(s.score) ~= "number" or type(s.moves) ~= "number" then return false end
    for i = 1, N * N do if s.kind[i] == 0 then return false end end
    st.kind, st.spec = copy(s.kind), copy(s.spec)
    st.score = s.score
    st.moves = math.max(0, math.min(MOVES, math.floor(s.moves)))
    st.over = (s.over and true or false) or st.moves == 0
    st.startBest = type(s.startBest) == "number" and s.startBest or (db.best or 0)
    st.ready = true
    return true
end

local function newGame()
    fresh()
    st.score, st.moves, st.over = 0, MOVES, false
    st.startBest = db.best or 0
    st.ready = true
    db.games = (db.games or 0) + 1
    anim, sel, hint, idle, msg = nil, nil, nil, 0, nil
    save()
    if win then drawFinal() refresh() end
end

-- un coup : echange de deux voisines ; rend true s il a compte
local function doSwap(a, b)
    if not db or st.over or not adjacent(a, b) then return false end
    finishAnim()
    if st.kind[a] == 0 or st.kind[b] == 0 then return false end
    idle, hint, sel = 0, nil, nil
    local steps = {}
    local before = snapshot()
    local da, dd = st.kind[a] == DIAMOND, st.kind[b] == DIAMOND
    if not (da or dd) and not validSwap(a, b) then
        -- rien d aligne : aller-retour, coup non compte
        steps[1] = { t = "swap", snap = before, a = a, b = b, back = true }
        anim = { steps = steps, n = 1, t = 0 }
        st.lastSteps = steps
        if win then refresh() end
        return false
    end
    swapCells(a, b)
    steps[1] = { t = "swap", snap = before, a = a, b = b }
    st.moves = st.moves - 1
    local gained, top, made
    if da or dd then
        local clear, fired = {}, {}
        if da and dd then
            for i = 1, N * N do clear[i] = true end
            fired[a], fired[b] = true, true
        else
            -- apres l echange, le diamant est passe de a a b (ou de b a a)
            local d, o = da and b or a, da and a or b
            local k = st.kind[o]
            clear[d], fired[d] = true, true
            for i = 1, N * N do if st.kind[i] == k then clear[i] = true end end
        end
        local g = blast(clear, {}, 1, steps, fired)
        steps[#steps - 1].snd = "bong"
        local g2, t2, m2 = cascades(nil, steps, 2)
        gained, top, made = g + g2, math.max(1, t2), m2
    else
        gained, top, made = cascades({ [a] = true, [b] = true }, steps, 1)
    end
    st.score = st.score + gained
    if st.score > (db.best or 0) then db.best = st.score end
    if made == "diamond" then say(L.JOA_DIAMOND)
    elseif made == "bomb" then say(L.JOA_RADIANT)
    elseif made == "cut" then say(L.JOA_CUT)
    elseif top >= 2 then say(string.format(L.JOA_COMBO, top)) end
    if st.moves <= 0 then
        st.moves, st.over = 0, true
        local record = st.score > (st.startBest or 0)
        steps[#steps + 1] = { t = "end", snd = record and "carillon" or "trombone" }
    elseif not findMove() then
        shuffle()
        steps[#steps + 1] = { t = "shuffle", snap = snapshot(), snd = "ding_grave" }
        say(L.JOA_SHUFFLE)
    end
    save()
    anim = { steps = steps, n = 1, t = 0 }
    st.lastSteps = steps
    if win then refresh() end
    return true
end

-- clic sur une case : choisir, echanger avec la choisie, ou lacher
local function click(i)
    if not i or st.over then return end
    idle, hint = 0, nil
    if sel and sel ~= i and adjacent(sel, i) then
        local a = sel
        sel = nil
        doSwap(a, i)
    elseif sel == i then
        sel = nil
    else
        sel = i
    end
    if win then refresh() end
end

---------------------------------------------------------------------------
-- Dessin
---------------------------------------------------------------------------

-- centre d une case, depuis le coin haut gauche de la grille
local function cellPos(r, c)
    return GAP + (c - 1) * (TILE + GAP) + TILE / 2, -(GAP + (r - 1) * (TILE + GAP) + TILE / 2)
end
local function posOf(i)
    local r, c = rc(i)
    return cellPos(r, c)
end

-- case sous un point de la grille (x vers la droite, y vers le bas)
local function cellAt(x, y)
    if not x or not y then return nil end
    local c = math.floor((x - GAP / 2) / (TILE + GAP)) + 1
    local r = math.floor((y - GAP / 2) / (TILE + GAP)) + 1
    if r < 1 or r > N or c < 1 or c > N then return nil end
    return idx(r, c)
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
    f.icon:SetPoint("TOPLEFT", 4, -4)
    f.icon:SetPoint("BOTTOMRIGHT", -4, 4)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- halo (eclatante, diamant) et traits (taillee)
    f.glow = f:CreateTexture(nil, "OVERLAY")
    f.glow:SetPoint("TOPLEFT", 2, -2)
    f.glow:SetPoint("BOTTOMRIGHT", -2, 2)
    f.glow:SetBlendMode("ADD")
    f.glow:Hide()
    f.bars = {}
    for b = 1, 2 do
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(1, 1, 1, 0.8)
        t:SetBlendMode("ADD")
        t:Hide()
        f.bars[b] = t
    end
    return f
end

local function styleTile(f, k, sp)
    local gem = GEMS[k] or GEMS[1]
    f.edge:SetColorTexture(gem.r, gem.g, gem.b, 1)
    f.icon:SetTexture(iconOf(k))
    local lined = sp == SP_ROW or sp == SP_COL
    for b, t in ipairs(f.bars) do
        t:ClearAllPoints()
        local off = b == 1 and 7 or -7
        if sp == SP_ROW then
            t:SetPoint("LEFT", f, "LEFT", 3, off)
            t:SetPoint("RIGHT", f, "RIGHT", -3, off)
            t:SetHeight(3)
        elseif sp == SP_COL then
            t:SetPoint("TOP", f, "TOP", off, -3)
            t:SetPoint("BOTTOM", f, "BOTTOM", off, 3)
            t:SetWidth(3)
        end
        t:SetShown(lined)
    end
    local glows = sp == SP_BOMB or k == DIAMOND
    if glows then f.glow:SetColorTexture(gem.r, gem.g, gem.b, 1) end
    f.glow:SetShown(glows)
end

local function put(k, sp, x, y, s, a)
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
    f:SetAlpha(a or 1)
    if f.k ~= k or f.sp ~= sp then
        f.k, f.sp = k, sp
        styleTile(f, k, sp)
    end
    f:Show()
end

local function hideRest()
    for j = used + 1, #tiles do tiles[j]:Hide() end
end

-- place(i, x, y) -> x, y, taille, alpha (dessin d une etape)
local function drawBoard(K, S, place)
    used = 0
    for i = 1, N * N do
        local k = K[i]
        if k > 0 then
            local x, y = posOf(i)
            local s, a = 1, 1
            if place then x, y, s, a = place(i, x, y) end
            if s > 0.02 and a > 0.02 then put(k, S[i], x, y, s, a) end
        end
    end
    hideRest()
end

local function placeMarks()
    if not board then return end
    if sel and not st.over then
        local x, y = posOf(sel)
        selBox:ClearAllPoints()
        selBox:SetPoint("CENTER", board, "TOPLEFT", x, y)
        selBox:SetSize(TILE + 4, TILE + 4)
        selBox:Show()
    else
        selBox:Hide()
    end
    if hint and not st.over then
        local ax, ay = posOf(hint[1])
        local bx, by = posOf(hint[2])
        hintBox:ClearAllPoints()
        hintBox:SetPoint("CENTER", board, "TOPLEFT", (ax + bx) / 2, (ay + by) / 2)
        hintBox:SetSize(math.abs(bx - ax) + TILE + 4, math.abs(by - ay) + TILE + 4)
        hintBox:Show()
    else
        hintBox:Hide()
    end
end

function drawFinal()
    if not board then return end
    drawBoard(st.kind, st.spec)
    placeMarks()
end

local function stepLen(s)
    if s.t == "swap" then return s.back and SWAP * 2 or SWAP end
    if s.t == "clear" then return CLEAR end
    if s.t == "fall" then
        local d = 0
        for i, r0 in pairs(s.from) do
            local r = rc(i)
            if r - r0 > d then d = r - r0 end
        end
        return math.max(0.1, math.min(0.4, d * FALL_ROW))
    end
    if s.t == "shuffle" then return SHUFFLE end
    return 0
end

local function drawStep(s, p)
    local snap = s.snap
    if s.t == "swap" then
        local q = p
        if s.back then q = p < 0.5 and p * 2 or (1 - p) * 2 end
        q = 1 - (1 - q) * (1 - q)
        local ax, ay = posOf(s.a)
        local bx, by = posOf(s.b)
        drawBoard(snap.kind, snap.spec, function(i, x, y)
            if i == s.a then return ax + (bx - ax) * q, ay + (by - ay) * q, 1, 1 end
            if i == s.b then return bx + (ax - bx) * q, by + (ay - by) * q, 1, 1 end
            return x, y, 1, 1
        end)
    elseif s.t == "clear" then
        drawBoard(snap.kind, snap.spec, function(i, x, y)
            if s.create[i] then return x, y, 1 + 0.2 * math.sin(math.pi * p), 1 end
            if s.cells[i] then return x, y, 1 - 0.7 * p, 1 - p end
            return x, y, 1, 1
        end)
    elseif s.t == "fall" then
        local q = p * p
        drawBoard(snap.kind, snap.spec, function(i, x, y)
            local r0 = s.from[i]
            local r, c = rc(i)
            if r0 and r0 ~= r then
                local _, y0 = cellPos(r0, c)
                return x, y0 + (y - y0) * q, 1, 1
            end
            return x, y, 1, 1
        end)
    elseif s.t == "shuffle" then
        drawBoard(snap.kind, snap.spec, function(_, x, y) return x, y, 0.5 + 0.5 * p, 0.3 + 0.7 * p end)
    end
end

local function animStep(dt)
    if not anim then return end
    anim.t = anim.t + dt
    while true do
        local s = anim.steps[anim.n]
        if not s then break end
        if not anim.entered then
            anim.entered = true
            if s.snd then play(s.snd) end
        end
        local len = stepLen(s)
        if anim.t < len then
            if board then drawStep(s, anim.t / len) end
            return
        end
        anim.t = anim.t - len
        anim.n = anim.n + 1
        anim.entered = false
    end
    anim = nil
    drawFinal()
    refresh()
end

function finishAnim()
    if anim then
        anim = nil
        drawFinal()
    end
end

local function showOverlay(title, line, b1)
    overlay.title:SetText(title)
    overlay.line:SetText(line or "")
    overlay.b1:SetText(b1.text)
    overlay.b1.fn = b1.fn
    overlay.b1:SetWidth(math.max(110, overlay.b1.cuiText and overlay.b1.cuiText:GetStringWidth() + 20 or 110))
    overlay:Show()
end

local sureUntil = 0

function refresh()
    if not win then return end
    hud.score:SetText(st.score)
    hud.best:SetText(math.max(db.best or 0, st.score))
    hud.moves:SetText(st.moves)
    if st.moves <= 5 then hud.moves:SetTextColor(1, 0.45, 0.3) else hud.moves:SetTextColor(1, 1, 1) end
    hud.new:SetText(GetTime() < sureUntil and L.JOA_SURE or L.JOA_NEW)
    if InCombatLockdown() then
        hud.status:SetText(L.JOA_COMBAT)
    elseif msg and GetTime() < msgUntil then
        hud.status:SetText(msg)
    else
        hud.status:SetText(L.JOA_READY)
    end
    placeMarks()
    if anim then return end
    if st.over then
        local line = string.format(L.JOA_OVER2, st.score)
        if st.score > 0 and st.score > (st.startBest or 0) then line = line .. "\n|cffffd100" .. L.JOA_NEW_BEST .. "|r" end
        showOverlay(L.JOA_OVER, line, { text = L.JOA_NEW, fn = function() newGame() end })
    else
        overlay:Hide()
    end
end

---------------------------------------------------------------------------
-- Fenetre
---------------------------------------------------------------------------

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

-- cadre a quatre bords (case choisie, indice)
local function outline(r, g, b, thick, fill)
    local f = CreateFrame("Frame", nil, board)
    f:SetFrameLevel(board:GetFrameLevel() + 10)
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(r, g, b, 1)
        if side == "TOP" or side == "BOTTOM" then
            t:SetPoint(side .. "LEFT")
            t:SetPoint(side .. "RIGHT")
            t:SetHeight(thick)
        else
            t:SetPoint("TOP" .. side)
            t:SetPoint("BOTTOM" .. side)
            t:SetWidth(thick)
        end
    end
    local t = f:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints()
    t:SetColorTexture(r, g, b, fill)
    t:SetBlendMode("ADD")
    f:Hide()
    return f
end

local function cursorPoint(self)
    local cx, cy = GetCursorPosition()
    local s = self:GetEffectiveScale()
    local left, top = self:GetLeft(), self:GetTop()
    if not cx or not s or not left or not top then return nil end
    return cx / s - left, top - cy / s
end

local function build()
    db.pos = db.pos or { point = "CENTER", x = 0, y = 40 }
    win = CreateFrame("Frame", "CorpUIJoaillierGame", UIParent)
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
    title:SetText(L.JOA_TITLE)
    local close = CreateFrame("Button", nil, bar)
    close:SetSize(22, 22)
    close:SetPoint("RIGHT", -4, 0)
    local x = close:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    x:SetPoint("CENTER")
    x:SetText("×")
    close:SetScript("OnClick", function() win:Hide() end)
    -- score, record, coups restants, nouvelle partie
    hud = {}
    hud.score = scoreBox(L.JOA_SCORE, 12)
    hud.best = scoreBox(L.JOA_BEST, 100)
    hud.moves = scoreBox(L.JOA_MOVES, 188)
    hud.new = ns.UI.Button(win, L.JOA_NEW, 110, function()
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
    hud.new:SetPoint("TOPRIGHT", win, "TOPRIGHT", -12, -42)
    -- grille
    board = CreateFrame("Frame", nil, win)
    board:SetSize(BOARD, BOARD)
    board:SetPoint("TOP", win, "TOP", 0, -84)
    pcall(board.SetClipsChildren, board, true)
    local back = board:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(0.03, 0.03, 0.04, 0.9)
    for r = 1, N do
        for c = 1, N do
            local slot = board:CreateTexture(nil, "BORDER")
            slot:SetSize(TILE, TILE)
            local cx, cy = cellPos(r, c)
            slot:SetPoint("CENTER", board, "TOPLEFT", cx, cy)
            slot:SetColorTexture(1, 1, 1, (r + c) % 2 == 0 and 0.07 or 0.04)
        end
    end
    selBox = outline(C.gold[1], C.gold[2], C.gold[3], 2, 0.18)
    hintBox = outline(1, 1, 1, 2, 0.12)
    -- souris : clic puis clic, ou glisser une gemme vers sa voisine
    board:EnableMouse(true)
    board:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local x0, y0 = cursorPoint(self)
        self.downX, self.downY, self.downCell = x0, y0, cellAt(x0, y0)
    end)
    board:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            sel = nil
            placeMarks()
            return
        end
        local from = self.downCell
        local x0, y0 = self.downX, self.downY
        self.downX, self.downY, self.downCell = nil, nil, nil
        if not from then return end
        local x1, y1 = cursorPoint(self)
        if not x1 then return end
        local dx, dy = x1 - x0, y1 - y0
        if math.max(math.abs(dx), math.abs(dy)) >= DRAG then
            local r, c = rc(from)
            if math.abs(dx) > math.abs(dy) then c = c + (dx > 0 and 1 or -1) else r = r + (dy > 0 and 1 or -1) end
            if r >= 1 and r <= N and c >= 1 and c <= N then
                sel = nil
                doSwap(from, idx(r, c))
            end
        elseif cellAt(x1, y1) == from then
            click(from)
        end
    end)
    board:SetScript("OnUpdate", function(_, dt)
        animStep(dt)
        -- halo des gemmes eclatantes et des diamants, indice qui respire
        local p = 0.22 + 0.16 * math.sin(GetTime() * 5)
        for j = 1, used do
            local f = tiles[j]
            if f.glow:IsShown() then f.glow:SetAlpha(p) end
        end
        if hint then hintBox:SetAlpha(0.5 + 0.5 * math.sin(GetTime() * 4)) end
        if not anim and not st.over and db.hint then
            idle = idle + dt
            if idle >= HINT_DELAY and not hint then
                local a, b = findMove()
                if a then
                    hint = { a, b }
                    placeMarks()
                end
            end
        end
        if msg and GetTime() >= msgUntil then
            msg = nil
            refresh()
        end
    end)
    hud.status = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hud.status:SetPoint("TOP", board, "BOTTOM", 0, -10)
    hud.status:SetWidth(WIN_W - 24)
    -- fin de partie
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
    overlay.b1:SetPoint("TOP", overlay.line, "BOTTOM", 0, -14)
    overlay:Hide()
    -- clavier : seulement Echap est garde
    win:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        if key == "ESCAPE" then
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
        if not st.ready and not load() then newGame() end
        idle, hint = 0, nil
        drawFinal()
        refresh()
    end)
    win:SetScript("OnHide", function()
        setKeyboard(false)
        finishAnim()
        sel, hint = nil, nil
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
ns.Games.Register("joaillier", {
    title = function() return L.MOD_JOAILLIER end,
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
-- Reglages (/corp joaillier)
---------------------------------------------------------------------------

local panel

local function buildPanel()
    panel = ns.UI.Window("CorpUIJoaillierOptions", ns.TITLE .. " - " .. L.MOD_JOAILLIER, nil, 440, 470)
    local icon = panel:CreateTexture(nil, "ARTWORK")
    icon:SetSize(64, 64)
    icon:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -40)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetTexture(iconOf(DIAMOND))
    local desc = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", panel, "TOPLEFT", 92, -40)
    desc:SetWidth(336)
    desc:SetJustifyH("LEFT")
    desc:SetText(L.JOA_HINT)
    local stats = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    stats:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -10)
    stats:SetWidth(336)
    stats:SetJustifyH("LEFT")
    local playBtn = ns.UI.Button(panel, L.MURLOC_PLAY, 120, function() toggle() end)
    playBtn:SetPoint("TOPLEFT", stats, "BOTTOMLEFT", 0, -10)
    local form = ns.UI.Form(panel, -266, function()
        if win then win:SetScale(db.scale or 1) end
    end)
    form:Check(L.MURLOC_OPT_SOUND, function() return db.sound end, function(v) db.sound = v end)
    form:Check(L.JOA_OPT_HINT, function() return db.hint end, function(v)
        db.hint = v
        if not v then
            hint = nil
            placeMarks()
        end
    end)
    form:Number(L.MURLOC_OPT_SCALE, function() return math.floor((db.scale or 1) * 100 + 0.5) end,
        function(v) db.scale = v / 100 end, 60, 150, 5)
    ns.Games.TaxiOptions(form)
    table.insert(form.refreshers, function()
        stats:SetText(string.format(L.MURLOC_BEST, db.best or 0) .. "   ·   " .. string.format(L.JOA_STATS, db.games or 0))
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
        if type(root.games.joaillier) ~= "table" then root.games.joaillier = {} end
        db = root.games.joaillier
        if db.sound == nil then db.sound = true end
        if db.hint == nil then db.hint = true end
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
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
    pcall(ev.RegisterEvent, ev, e)
end

ns.RegisterModule({
    command = "joaillier",
    alias = "gemmes",
    panelName = "CorpUIJoaillierOptions",
    icon = ns.ItemIcon(12800),
    title = function() return L.MOD_JOAILLIER end,
    desc = function() return L.JOA_DESC end,
    Slash = function(rest)
        rest = strlower(strtrim(rest or ""))
        if rest == "options" or rest == "config" then openPanel() else toggle() end
    end,
    Open = openPanel,
})

-- banc d essai
ns._joaillier = { st = st, idx = idx, rc = rc, findRuns = findRuns, analyze = analyze, expand = expand,
                  gravity = gravity, validSwap = validSwap, findMove = findMove, doSwap = doSwap,
                  click = click, shuffle = shuffle, fresh = fresh, newGame = newGame, load = load,
                  save = save, toggle = toggle, finishAnim = finishAnim, animStep = animStep,
                  cellAt = cellAt, cellPos = cellPos, iconOf = iconOf, openPanel = openPanel,
                  setRand = function(fn) rand = fn or math.random end,
                  N = N, KINDS = KINDS, DIAMOND = DIAMOND, SP_ROW = SP_ROW, SP_COL = SP_COL,
                  SP_BOMB = SP_BOMB, MOVES = MOVES, GEMS = GEMS,
                  ui = function() return win, board, overlay, hud, tiles, anim, sel, hint, msg end }
