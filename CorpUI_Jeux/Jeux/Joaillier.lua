--[[--------------------------------------------------------------------------
    CorpUI - module Jeux : l etabli du joaillier

    Aligner les gemmes : sur une grille de 8 x 8, on echange deux gemmes
    voisines pour en aligner trois ou plus de la meme sorte, ou pour en
    former un carre de 2 x 2 ; elles partent, celles du dessus tombent, de
    nouvelles arrivent par le haut (cascades : points multiplies). Six
    sortes, une couleur chacune : malachite, oeil de tigre, ombre-gemme,
    pierre de lune inferieure, rubis etoile, saphir bleu (icones lues sur le
    client), chacune avec son lisere.
      - 4 alignees : gemme taillee (vide sa ligne, ou sa colonne, quand elle
        part) ; carre de 2 x 2 : gemme filante (fait partir ses voisines puis
        file frapper une gemme, de preference une gemme speciale) ; en L ou
        en T : gemme eclatante (explose en 3 x 3) ; 5 alignees : diamant
        (diamant azerothien), qui, echange avec une gemme, fait partir toutes
        celles de cette sorte ;
      - deux gemmes speciales echangees se combinent : deux taillees = une
        croix, taillee + eclatante = 3 lignes et 3 colonnes, deux eclatantes
        = 5 x 5, filante + speciale = la speciale emportee au loin, deux
        filantes = trois cibles, diamant + speciale = toute la sorte
        changee en cette speciale, deux diamants = toute la grille ;
      - cascades : une gemme qui tombe complete parfois un alignement (CHAIN
        pour mille), d ou des reactions en chaine plus frequentes ;
      - une partie = 30 coups ; au dernier, bouquet final : les gemmes
        speciales restantes partent toutes ; un echange sans effet revient
        en arriere sans compter ; plus aucun coup possible : melange ;
      - classement de guilde : record et record de la semaine, un par compte
        (ns.Games.Scores, Jeux.lua : un joueur et ses rerolls = une ligne) ;
      - clic puis clic sur une voisine, ou glisser une gemme ; clic droit :
        lacher la gemme choisie ; indice (halo) apres 6 s sans jouer
        (reglage) ; Echap : fermer ; la partie est gardee ;
      - en combat : clavier rendu au jeu, la souris marche toujours (jeu au
        tour par tour : pas de pause) ;
      - effets : etincelles, rayons des taillees, onde des eclatantes,
        gemme qui file, points qui montent, bandeau des cascades, secousse
        (textures du podometre : etincelle, lueur, rayons) ; sons de CorpUI.
    Les regles se jouent d un coup (etat final aussitot, sauvegardable) ;
    l animation rejoue ensuite les etapes notees (echange, conversion,
    disparition, chute, melange). Fenetre a nous, deplacable ; rien de
    Blizzard n est touche.
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local C = ns.COLORS

local SOUNDS = ns.MEDIA .. "Sons\\"
local FXDIR = ns.MEDIA .. "Podometre\\"

local N = 8
local TILE, GAP = 46, 3
local BOARD = N * TILE + (N + 1) * GAP    -- 395
local PAD, TOP, SIDE_W = 12, 38, 214
local WIN_W = PAD + BOARD + 12 + SIDE_W + PAD
local WIN_H = TOP + BOARD + 64
local MOVES = 30
local HINT_DELAY = 6
local KINDS = 6
local DIAMOND = 7                          -- sorte du diamant (ne s aligne pas)
local SP_ROW, SP_COL, SP_BOMB, SP_FLY = 1, 2, 3, 4
local SP_MAX = SP_FLY
local SWAP, CLEAR, FALL_ROW, SHUFFLE, CONVERT = 0.14, 0.22, 0.055, 0.3, 0.4
local POINTS = 10
local BONUS = { [SP_ROW] = 40, [SP_COL] = 40, [SP_BOMB] = 80, [SP_FLY] = 60 }
local BONUS_DIAMOND = 150
local BONUS_DUO = 100
local CHAIN = 250                          -- sur 1000 : gemme tombee qui complete un alignement
local MAX_WAVES = 40
local FINALE_ROUNDS = 8
local DRAG = 14                            -- pixels pour un glisser
local LB_ROWS = 8

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
local win, board, overlay, hud, selBox, hintBox, hoverBox, fxf, ban, side
local tiles, used, cellTile = {}, 0, {}
local anim                -- { steps, n, t, entered } : etapes rejouees
-- kind : sorte par case (0 = vide, 1-6, DIAMOND) ; spec : gemme speciale
local st = { kind = {}, spec = {}, score = 0, moves = MOVES, over = false, startBest = 0, ready = false, chain = 0 }
for i = 1, N * N do st.kind[i], st.spec[i] = 0, 0 end
local sel                 -- case choisie (clic puis clic)
local idle, hint = 0, nil
local msg, msgUntil = nil, 0
local rand = math.random
local chainRate = CHAIN
local refresh, drawFinal, finishAnim, refreshBoard

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
local function inside(r, c) return r >= 1 and r <= N and c >= 1 and c <= N end

local function adjacent(a, b)
    if not a or not b or a < 1 or b < 1 or a > N * N or b > N * N then return false end
    local ra, ca = rc(a)
    local rb, cb = rc(b)
    return math.abs(ra - rb) + math.abs(ca - cb) == 1
end

local function special(i) return st.spec[i] > 0 or st.kind[i] == DIAMOND end

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

-- alignements de 3 ou plus et carres de 2 x 2 : { dir = "h", "v" ou
-- "sq", k, cells }
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
    for r = 1, N - 1 do
        for c = 1, N - 1 do
            local i = idx(r, c)
            local k = K[i]
            if k >= 1 and k <= KINDS and K[i + 1] == k and K[i + N] == k and K[i + N + 1] == k then
                runs[#runs + 1] = { dir = "sq", k = k, cells = { i, i + 1, i + N, i + N + 1 } }
            end
        end
    end
    return runs
end

-- un carre de 2 x 2 de la sorte de i contient-il i ?
local function squareAt(i)
    local K = st.kind
    local k = K[i]
    if k < 1 or k > KINDS then return false end
    local r, c = rc(i)
    for r0 = r - 1, r do
        for c0 = c - 1, c do
            if r0 >= 1 and c0 >= 1 and r0 < N and c0 < N then
                local j = idx(r0, c0)
                if K[j] == k and K[j + 1] == k and K[j + N] == k and K[j + N + 1] == k then return true end
            end
        end
    end
    return false
end

-- la case i est-elle dans un alignement (ou un carre) ?
local function matchAt(i)
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
    if n >= 3 then return true end
    return squareAt(i)
end

-- echange qui compte : un alignement, un diamant ou deux gemmes speciales
local function validSwap(a, b)
    if st.kind[a] == 0 or st.kind[b] == 0 then return false end
    if st.kind[a] == DIAMOND or st.kind[b] == DIAMOND then return true end
    if special(a) and special(b) then return true end
    swapCells(a, b)
    local ok = matchAt(a) or matchAt(b)
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
    local clear, create, spent, inRun, inLine = {}, {}, {}, {}, {}
    for ri, run in ipairs(runs) do
        for _, i in ipairs(run.cells) do
            clear[i] = true
            if run.dir ~= "sq" then
                inRun[i] = inRun[i] or {}
                table.insert(inRun[i], ri)
                inLine[i] = true
            end
        end
    end
    -- 5 alignees : diamant
    for ri, run in ipairs(runs) do
        if run.dir ~= "sq" and #run.cells >= 5 then
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
        if run.dir ~= "sq" and not spent[ri] and #run.cells == 4 then
            local at = pick(run.cells, moved, create)
            if at then
                create[at] = { k = run.k, sp = run.dir == "h" and SP_ROW or SP_COL }
                spent[ri] = true
            end
        end
    end
    -- carre de 2 x 2 hors de tout alignement : filante
    local taken = {}
    for _, run in ipairs(runs) do
        if run.dir == "sq" then
            local free = true
            for _, i in ipairs(run.cells) do
                if inLine[i] or create[i] or taken[i] then free = false end
            end
            if free then
                local at = pick(run.cells, moved, create)
                if at then create[at] = { k = run.k, sp = SP_FLY } end
                for _, i in ipairs(run.cells) do taken[i] = true end
            end
        end
    end
    return clear, create
end

-- cible d une gemme filante : une gemme speciale qui ne part pas encore
-- (reaction en chaine), sinon une gemme de la sorte la plus nombreuse
local function flyTarget(clear)
    local specials, plain, any = {}, {}, {}
    local kk = commonKind()
    for j = 1, N * N do
        if not clear[j] and st.kind[j] > 0 then
            if special(j) then specials[#specials + 1] = j
            elseif st.kind[j] == kk then plain[#plain + 1] = j end
            any[#any + 1] = j
        end
    end
    local list = #specials > 0 and specials or (#plain > 0 and plain or any)
    if #list == 0 then return nil end
    return list[rand(#list)]
end

-- effets des gemmes speciales qui partent, en chaine ; fired : cases dont
-- l effet est deja joue ; fx : effets notes pour l animation
local function expand(clear, fired, fx)
    fired = fired or {}
    fx = fx or {}
    local queue = {}
    for i = 1, N * N do if clear[i] then queue[#queue + 1] = i end end
    local function add(j)
        if j and not clear[j] then
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
                fx[#fx + 1] = { t = "row", r = r, k = k }
            elseif sp == SP_COL then
                for y = 1, N do add(idx(y, c)) end
                fx[#fx + 1] = { t = "col", c = c, k = k }
            elseif sp == SP_BOMB then
                for y = r - 1, r + 1 do
                    for x = c - 1, c + 1 do
                        if inside(y, x) then add(idx(y, x)) end
                    end
                end
                fx[#fx + 1] = { t = "bomb", i = i, rad = 1, k = k }
            elseif sp == SP_FLY then
                for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
                    if inside(r + d[1], c + d[2]) then add(idx(r + d[1], c + d[2])) end
                end
                local t = flyTarget(clear)
                if t then
                    add(t)
                    fx[#fx + 1] = { t = "fly", from = i, to = t, k = k }
                end
            elseif k == DIAMOND then
                local kk = commonKind()
                for j = 1, N * N do if st.kind[j] == kk then add(j) end end
                fx[#fx + 1] = { t = "diamond", i = i, kk = kk }
            end
        end
    end
    return clear, fx
end

-- sortes qui feraient un alignement en j (case vide)
local function chainKinds(j)
    local list = {}
    for k = 1, KINDS do
        st.kind[j] = k
        if matchAt(j) then list[#list + 1] = k end
    end
    st.kind[j] = 0
    return list
end

-- chute dans chaque colonne, puis remplissage par le haut ; from[i] =
-- rangee d ou part la gemme arrivee en i (0, -1... : au-dessus de la
-- grille). Une gemme neuve sur chainRate (pour mille) complete un
-- alignement si elle le peut : des cascades plus frequentes.
local function gravity()
    local from, empty = {}, {}
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
        empty[c] = write
    end
    for c = 1, N do
        local e = empty[c]
        for r = e, 1, -1 do
            local j = idx(r, c)
            local k
            if chainRate > 0 and rand(1000) <= chainRate then
                local list = chainKinds(j)
                if #list > 0 then k = list[rand(#list)] end
            end
            st.kind[j], st.spec[j] = k or rand(KINDS), 0
            from[j] = r - e
        end
    end
    return from
end

local MADE_RANK = { cut = 1, fly = 2, bomb = 3, diamond = 4 }
local MADE_OF = { [SP_ROW] = "cut", [SP_COL] = "cut", [SP_FLY] = "fly", [SP_BOMB] = "bomb" }

-- une vague : effets, points, disparition, chute ; rend les points et la
-- plus belle gemme nee ("diamond", "bomb", "fly", "cut")
local function blast(clear, create, cascade, steps, fired, extra)
    local _, fx = expand(clear, fired)
    local n, bonus, made = 0, extra or 0, nil
    for i = 1, N * N do
        local cr = create[i]
        if cr then
            local m = cr.k == DIAMOND and "diamond" or MADE_OF[cr.sp]
            bonus = bonus + (cr.k == DIAMOND and BONUS_DIAMOND or (BONUS[cr.sp] or 0))
            if m and (not made or MADE_RANK[m] > MADE_RANK[made]) then made = m end
        elseif clear[i] then
            n = n + 1
        end
    end
    local pts = (n * POINTS + bonus) * cascade
    steps[#steps + 1] = { t = "clear", snap = snapshot(), cells = clear, create = create, cascade = cascade,
                          fx = fx, points = pts }
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
    return pts, made
end

-- alignements en chaine (cascade 1, 2, 3...) ; rend points, plus haute
-- cascade, plus belle gemme nee
local function cascades(moved, steps, cascade)
    local gained, top, best = 0, cascade - 1, nil
    for _ = 1, MAX_WAVES do
        local clear, create = analyze(moved)
        if not clear then break end
        local g, made = blast(clear, create, cascade, steps)
        local s = steps[#steps - 1]
        s.snd = made and "montee" or (cascade >= 3 and "ding" or "verre")
        s.made = made
        if cascade >= 2 then s.banner = string.format(L.JOA_COMBO, cascade) end
        gained, top = gained + g, cascade
        if made and (not best or MADE_RANK[made] > MADE_RANK[best]) then best = made end
        cascade = cascade + 1
        moved = nil
    end
    return gained, top, best
end

-- deux gemmes speciales (ou un diamant) echangees : un effet a elles deux,
-- autour de b (la ou arrive la gemme deplacee) ; rend les points
local function combo(a, b, steps)
    local clear, fired = {}, {}
    local ka, kb = st.kind[a], st.kind[b]
    local sa, sb = st.spec[a], st.spec[b]
    local da, dd = ka == DIAMOND, kb == DIAMOND
    local r, c = rc(b)
    clear[a], clear[b], fired[a], fired[b] = true, true, true, true
    local fx = {}
    local function row(y)
        if y < 1 or y > N then return end
        for x = 1, N do clear[idx(y, x)] = true end
        fx[#fx + 1] = { t = "row", r = y, k = kb }
    end
    local function col(x)
        if x < 1 or x > N then return end
        for y = 1, N do clear[idx(y, x)] = true end
        fx[#fx + 1] = { t = "col", c = x, k = kb }
    end
    local function area(rad)
        for y = r - rad, r + rad do
            for x = c - rad, c + rad do
                if inside(y, x) then clear[idx(y, x)] = true end
            end
        end
        fx[#fx + 1] = { t = "bomb", i = b, rad = rad, k = kb }
    end
    local function around()
        for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
            if inside(r + d[1], c + d[2]) then clear[idx(r + d[1], c + d[2])] = true end
        end
    end
    local function launch(carry)
        local t = flyTarget(clear)
        if not t then return end
        fx[#fx + 1] = { t = "fly", from = b, to = t, k = kb }
        if carry then st.spec[t] = carry end
        clear[t] = true
    end
    local cut = function(s) return s == SP_ROW or s == SP_COL end
    local banner = L.JOA_DUO
    if da and dd then
        for i = 1, N * N do clear[i] = true end
        fx[#fx + 1] = { t = "diamond", i = b, all = true }
    elseif da or dd then
        local d, o = da and a or b, da and b or a
        local k, s = st.kind[o], st.spec[o]
        fx[#fx + 1] = { t = "diamond", i = d, kk = k }
        if s > 0 then
            -- toute la sorte devient cette gemme speciale, puis part
            local conv = {}
            for i = 1, N * N do
                if st.kind[i] == k then
                    st.spec[i] = cut(s) and (rand(2) == 1 and SP_ROW or SP_COL) or s
                    conv[i] = true
                    clear[i] = true
                end
            end
            fired[o] = nil
            steps[#steps + 1] = { t = "convert", snap = snapshot(), cells = conv, k = k, snd = "montee" }
        else
            for i = 1, N * N do if st.kind[i] == k then clear[i] = true end end
            banner = L.JOA_DIAMOND_USE
        end
    elseif cut(sa) and cut(sb) then
        row(r) col(c)
    elseif (cut(sa) and sb == SP_BOMB) or (sa == SP_BOMB and cut(sb)) then
        for y = r - 1, r + 1 do row(y) end
        for x = c - 1, c + 1 do col(x) end
    elseif sa == SP_BOMB and sb == SP_BOMB then
        area(2)
    elseif sa == SP_FLY and sb == SP_FLY then
        around()
        launch() launch() launch()
    else
        -- filante + taillee ou eclatante : la speciale emportee au loin
        local carry = sa == SP_FLY and sb or sa
        around()
        launch(carry)
    end
    local g = blast(clear, {}, 1, steps, fired, BONUS_DUO)
    local s = steps[#steps - 1]
    for _, e in ipairs(fx) do table.insert(s.fx, 1, e) end
    s.snd, s.banner, s.duo = "bong", banner, true
    return g
end

-- bouquet final : les gemmes speciales restantes partent toutes, avec
-- leurs cascades ; rend les points
local function finale(steps, cascade)
    local gained = 0
    for round = 1, FINALE_ROUNDS do
        local clear, any = {}, false
        for i = 1, N * N do
            if special(i) then clear[i], any = true, true end
        end
        if not any then break end
        local g = blast(clear, {}, cascade, steps)
        local s = steps[#steps - 1]
        s.snd = "montee"
        if round == 1 then s.banner, s.finale = L.JOA_FINALE, true end
        local g2, t2 = cascades(nil, steps, cascade + 1)
        gained = gained + g + g2
        cascade = math.max(cascade + 1, t2 + 1)
    end
    return gained
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
                    local sq = r > 1 and c > 1 and st.kind[i - 1] == k and st.kind[i - N] == k and st.kind[i - N - 1] == k
                    if not h and not v and not sq then break end
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

---------------------------------------------------------------------------
-- Records (le classement de guilde lit ceux-ci : ns.Games.Scores)
---------------------------------------------------------------------------

local function Scores() return ns.Games and ns.Games.Scores end

local function weekKey()
    local S = Scores()
    return S and S.Week and S.Week() or date("%Y-%W")
end

local function weekBest()
    if not db or db.week ~= weekKey() then return 0 end
    return db.weekBest or 0
end

-- records de la partie en cours ; rend true si l un d eux a bouge
local function noteScore()
    local moved = false
    if st.score > (db.best or 0) then db.best, moved = st.score, true end
    local wk = weekKey()
    if db.week ~= wk then db.week, db.weekBest = wk, 0 end
    if st.score > (db.weekBest or 0) then db.weekBest, moved = st.score, true end
    return moved
end

local function save()
    if not db then return end
    db.save = { kind = copy(st.kind), spec = copy(st.spec), score = st.score, moves = st.moves,
                over = st.over, startBest = st.startBest, startWeek = st.startWeek, chain = st.chain }
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
    if type(s) ~= "table" or not validCells(s.kind, DIAMOND) or not validCells(s.spec, SP_MAX)
        or type(s.score) ~= "number" or type(s.moves) ~= "number" then return false end
    for i = 1, N * N do if s.kind[i] == 0 then return false end end
    st.kind, st.spec = copy(s.kind), copy(s.spec)
    st.score = s.score
    st.moves = math.max(0, math.min(MOVES, math.floor(s.moves)))
    st.over = (s.over and true or false) or st.moves == 0
    st.startBest = type(s.startBest) == "number" and s.startBest or (db.best or 0)
    st.startWeek = type(s.startWeek) == "number" and s.startWeek or weekBest()
    st.chain = type(s.chain) == "number" and s.chain or 0
    st.ready = true
    if hud then hud.disp = st.score end
    return true
end

local function newGame()
    fresh()
    st.score, st.moves, st.over, st.chain = 0, MOVES, false, 0
    st.startBest, st.startWeek = db.best or 0, weekBest()
    st.ready = true
    db.games = (db.games or 0) + 1
    anim, sel, hint, idle, msg = nil, nil, nil, 0, nil
    if hud then hud.disp = 0 end
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
    local duo = special(a) and special(b)
    local da, dd = st.kind[a] == DIAMOND, st.kind[b] == DIAMOND
    if not (da or dd or duo) and not validSwap(a, b) then
        -- rien d aligne : aller-retour, coup non compte
        steps[1] = { t = "swap", snap = before, a = a, b = b, back = true, snd = "refus" }
        anim = { steps = steps, n = 1, t = 0 }
        st.lastSteps = steps
        if win then refresh() end
        return false
    end
    swapCells(a, b)
    steps[1] = { t = "swap", snap = before, a = a, b = b }
    st.moves = st.moves - 1
    local gained, top, made
    if duo or da or dd then
        local g = combo(a, b, steps)
        local g2, t2, m2 = cascades(nil, steps, 2)
        gained, top, made = g + g2, math.max(1, t2), m2
        if not m2 then say(duo and L.JOA_DUO or L.JOA_DIAMOND_USE) end
    else
        gained, top, made = cascades({ [a] = true, [b] = true }, steps, 1)
    end
    st.score = st.score + gained
    if top > (st.chain or 0) then st.chain = top end
    if made == "diamond" then say(L.JOA_DIAMOND)
    elseif made == "bomb" then say(L.JOA_RADIANT)
    elseif made == "fly" then say(L.JOA_FLY)
    elseif made == "cut" then say(L.JOA_CUT)
    elseif top >= 2 then say(string.format(L.JOA_COMBO, top)) end
    if st.moves <= 0 then
        st.score = st.score + finale(steps, math.max(2, top + 1))
        st.moves, st.over = 0, true
        local record = st.score > (st.startBest or 0)
        steps[#steps + 1] = { t = "end", snd = record and "carillon" or "trombone" }
    elseif not findMove() then
        shuffle()
        steps[#steps + 1] = { t = "shuffle", snap = snapshot(), snd = "ding_grave", banner = L.JOA_SHUFFLE_SHORT }
        say(L.JOA_SHUFFLE)
    end
    local moved = noteScore()
    save()
    if st.over or moved then
        local S = Scores()
        if S and S.Changed and st.over then S.Changed("joaillier") end
    end
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
-- Dessin des gemmes
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

local function rotate(t, a)
    if t.SetRotation then pcall(t.SetRotation, t, a) end
end

local function newTile()
    local f = CreateFrame("Frame", nil, board)
    f:SetFrameLevel(board:GetFrameLevel() + 2)
    -- lueur douce de la couleur de la gemme, rayons des grosses gemmes
    f.aura = f:CreateTexture(nil, "BACKGROUND")
    f.aura:SetPoint("CENTER")
    f.aura:SetTexture(FXDIR .. "lueur")
    f.aura:SetBlendMode("ADD")
    f.rays = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.rays:SetPoint("CENTER")
    f.rays:SetTexture(FXDIR .. "rayons")
    f.rays:SetBlendMode("ADD")
    f.rays:Hide()
    -- sertissage : lisere de la couleur de la gemme, fond sombre
    f.edge = f:CreateTexture(nil, "BORDER")
    f.edge:SetPoint("TOPLEFT", 2, -2)
    f.edge:SetPoint("BOTTOMRIGHT", -2, 2)
    local inner = f:CreateTexture(nil, "BORDER", nil, 1)
    inner:SetPoint("TOPLEFT", 3, -3)
    inner:SetPoint("BOTTOMRIGHT", -3, 3)
    inner:SetColorTexture(0.05, 0.05, 0.07, 1)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("TOPLEFT", 4, -4)
    f.icon:SetPoint("BOTTOMRIGHT", -4, 4)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- halo des gemmes speciales, traits des taillees, etoile des filantes
    f.glow = f:CreateTexture(nil, "OVERLAY")
    f.glow:SetPoint("CENTER")
    f.glow:SetTexture(FXDIR .. "lueur")
    f.glow:SetBlendMode("ADD")
    f.glow:Hide()
    f.bars = {}
    for b = 1, 2 do
        local t = f:CreateTexture(nil, "OVERLAY", nil, 1)
        t:SetColorTexture(1, 1, 1, 0.85)
        t:SetBlendMode("ADD")
        t:Hide()
        f.bars[b] = t
    end
    f.orbit = f:CreateTexture(nil, "OVERLAY", nil, 2)
    f.orbit:SetTexture(FXDIR .. "etincelle")
    f.orbit:SetBlendMode("ADD")
    f.orbit:Hide()
    return f
end

local function styleTile(f, k, sp)
    local gem = GEMS[k] or GEMS[1]
    f.edge:SetColorTexture(gem.r, gem.g, gem.b, 0.9)
    f.icon:SetTexture(iconOf(k))
    f.aura:SetVertexColor(gem.r, gem.g, gem.b, 1)
    f.aura:SetAlpha(k == DIAMOND and 0.5 or 0.22)
    local lined = sp == SP_ROW or sp == SP_COL
    for b, t in ipairs(f.bars) do
        t:ClearAllPoints()
        local off = b == 1 and 8 or -8
        if sp == SP_ROW then
            t:SetPoint("LEFT", f, "LEFT", 2, off)
            t:SetPoint("RIGHT", f, "RIGHT", -2, off)
            t:SetHeight(3)
        elseif sp == SP_COL then
            t:SetPoint("TOP", f, "TOP", off, -2)
            t:SetPoint("BOTTOM", f, "BOTTOM", off, 2)
            t:SetWidth(3)
        end
        t:SetShown(lined)
    end
    local glows = sp == SP_BOMB or sp == SP_FLY or k == DIAMOND
    f.glow:SetVertexColor(gem.r, gem.g, gem.b, 1)
    f.glow:SetShown(glows)
    f.rays:SetVertexColor(gem.r, gem.g, gem.b, 1)
    f.rays:SetShown(sp == SP_BOMB or k == DIAMOND)
    f.orbit:SetVertexColor(1, 1, 1, 1)
    f.orbit:SetShown(sp == SP_FLY)
end

local function put(k, sp, x, y, s, a)
    used = used + 1
    local f = tiles[used]
    if not f then
        f = newTile()
        tiles[used] = f
    end
    local size = TILE * (s or 1)
    if f.size ~= size then
        f.size = size
        f:SetSize(size, size)
        f.aura:SetSize(size * 1.5, size * 1.5)
        f.glow:SetSize(size * 1.7, size * 1.7)
        f.rays:SetSize(size * 2, size * 2)
        f.orbit:SetSize(size * 0.45, size * 0.45)
    end
    f:ClearAllPoints()
    f:SetPoint("CENTER", board, "TOPLEFT", x, y)
    f:SetAlpha(a or 1)
    if f.k ~= k or f.sp ~= sp then
        f.k, f.sp = k, sp
        styleTile(f, k, sp)
    end
    f:Show()
    return f
end

local function hideRest()
    for j = used + 1, #tiles do tiles[j]:Hide() end
end

-- place(i, x, y) -> x, y, taille, alpha (dessin d une etape)
local function drawBoard(K, S, place)
    used = 0
    for i = 1, N * N do
        local k = K[i]
        cellTile[i] = nil
        if k > 0 then
            local x, y = posOf(i)
            local s, a = 1, 1
            if place then x, y, s, a = place(i, x, y) end
            if s > 0.02 and a > 0.02 then cellTile[i] = put(k, S[i], x, y, s, a) end
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

---------------------------------------------------------------------------
-- Effets : etincelles, rayons, ondes, gemme qui file, points, bandeau,
-- secousse. Objets tires de reserves, rendus a la fin de leur vie.
---------------------------------------------------------------------------

local live, pools = {}, {}
local shakeT, shakeAmp = 0, 0
local banT, banLife = nil, 1.3

local function take(kind, make)
    local p = pools[kind]
    if not p then p = {} pools[kind] = p end
    local o = table.remove(p)
    if not o then o = make() end
    o.poolKind = kind
    o:Show()
    return o
end

local function spawn(obj, life, fn, data)
    data = data or {}
    data.obj, data.life, data.t, data.fn = obj, life, 0, fn
    live[#live + 1] = data
    fn(data, 0)
    return data
end

local function stepFx(dt)
    local i = 1
    while i <= #live do
        local e = live[i]
        e.t = e.t + dt
        local p = e.t / e.life
        if p >= 1 then
            e.obj:Hide()
            table.insert(pools[e.obj.poolKind], e.obj)
            table.remove(live, i)
            if e.done then e.done(e) end
        else
            e.fn(e, p)
            i = i + 1
        end
    end
end

local function clearFx()
    for _, e in ipairs(live) do
        e.obj:Hide()
        table.insert(pools[e.obj.poolKind], e.obj)
    end
    live = {}
    shakeT = 0
    banT = nil
    if ban then ban:Hide() end
end

local function texMaker(file, sub, blend)
    return function()
        local t = fxf:CreateTexture(nil, "OVERLAY", nil, sub or 0)
        if file then t:SetTexture(file) end
        t:SetBlendMode(blend or "ADD")
        return t
    end
end
local mkSpark, mkGlow, mkRays, mkBeam, mkIcon
local function mkPopup()
    local fs = fxf:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(fs, 16)
    return fs
end

local function at(obj, x, y)
    obj:ClearAllPoints()
    obj:SetPoint("CENTER", fxf, "TOPLEFT", x, y)
end

-- etincelles d une gemme qui part
local function burst(x, y, gem, n)
    for _ = 1, n do
        local t = take("spark", mkSpark)
        t:SetVertexColor(gem.r * 0.7 + 0.3, gem.g * 0.7 + 0.3, gem.b * 0.7 + 0.3, 1)
        local a = math.random() * 2 * math.pi
        local v = 50 + math.random() * 110
        spawn(t, 0.4 + math.random() * 0.35, function(e, p)
            local tt = e.t
            at(e.obj, x + e.vx * tt, y + e.vy * tt - 260 * tt * tt)
            local s = e.size * (1 - 0.6 * p)
            e.obj:SetSize(s, s)
            e.obj:SetAlpha(1 - p * p)
        end, { vx = math.cos(a) * v, vy = math.sin(a) * v + 50, size = 12 + math.random() * 12 })
    end
end

-- onde (lueur qui s etend)
local function shock(x, y, size, gem, life)
    local t = take("glow", mkGlow)
    t:SetVertexColor(gem.r, gem.g, gem.b, 1)
    spawn(t, life or 0.4, function(e, p)
        at(e.obj, x, y)
        local s = size * (0.35 + 0.9 * p)
        e.obj:SetSize(s, s)
        e.obj:SetAlpha(0.9 * (1 - p))
    end)
end

-- rayons qui tournent et s effacent
local function burstRays(x, y, size, gem, life, alpha)
    local t = take("rays", mkRays)
    t:SetVertexColor(gem.r, gem.g, gem.b, 1)
    spawn(t, life or 0.7, function(e, p)
        at(e.obj, x, y)
        local s = size * (0.6 + 0.5 * p)
        e.obj:SetSize(s, s)
        rotate(e.obj, p * 1.6)
        e.obj:SetAlpha((alpha or 0.8) * (1 - p))
    end)
end

-- rayon d une taillee : toute la ligne (ou la colonne)
local function beam(horizontal, pos, gem)
    for layer = 1, 2 do
        local t = take("beam", mkBeam)
        if layer == 1 then
            t:SetColorTexture(gem.r * 0.6 + 0.4, gem.g * 0.6 + 0.4, gem.b * 0.6 + 0.4, 1)
        else
            t:SetColorTexture(1, 1, 1, 1)
        end
        local wide = layer == 1 and TILE * 0.95 or TILE * 0.3
        spawn(t, 0.38, function(e, p)
            local thick = math.max(1, wide * (1 - 0.85 * p))
            e.obj:ClearAllPoints()
            if horizontal then
                e.obj:SetPoint("LEFT", fxf, "TOPLEFT", 0, pos)
                e.obj:SetPoint("RIGHT", fxf, "TOPRIGHT", 0, pos)
                e.obj:SetHeight(thick)
            else
                e.obj:SetPoint("TOP", fxf, "TOPLEFT", pos, 0)
                e.obj:SetPoint("BOTTOM", fxf, "BOTTOMLEFT", pos, 0)
                e.obj:SetWidth(thick)
            end
            e.obj:SetAlpha((layer == 1 and 0.75 or 0.95) * (1 - p))
        end)
    end
end

-- gemme filante : de sa case a sa cible, en arc, avec une trainee
local function flyer(from, to, k)
    local ax, ay = posOf(from)
    local bx, by = posOf(to)
    local gem = GEMS[k] or GEMS[1]
    local t = take("icon", mkIcon)
    t:SetTexture(iconOf(k))
    t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local lift = 30 + math.abs(bx - ax) * 0.15
    spawn(t, CLEAR + 0.08, function(e, p)
        local q = p * p * (3 - 2 * p)
        local x = ax + (bx - ax) * q
        local y = ay + (by - ay) * q + math.sin(math.pi * p) * lift
        at(e.obj, x, y)
        local s = TILE * (0.75 - 0.2 * math.sin(math.pi * p))
        e.obj:SetSize(s, s)
        e.acc = (e.acc or 0) + 1
        if e.acc % 2 == 0 then burst(x, y, gem, 1) end
    end, { done = function() shock(bx, by, TILE * 2.2, gem, 0.35) burst(bx, by, gem, 6) end })
end

-- points gagnes, qui montent
local function popup(x, y, text, r, g, b, size)
    local fs = take("pop", mkPopup)
    ns.UI.HeadFont(fs, size or 16)
    fs:SetText(text)
    fs:SetTextColor(r, g, b)
    y = math.min(-14, math.max(-BOARD + 14, y))
    x = math.min(BOARD - 30, math.max(30, x))
    spawn(fs, 0.95, function(e, p)
        at(e.obj, x, y + 36 * p)
        e.obj:SetAlpha(p < 0.6 and 1 or (1 - (p - 0.6) / 0.4))
    end)
end

-- bandeau au milieu de la grille (cascade, combinaison, bouquet final)
local function banner(text, r, g, b)
    if not ban then return end
    ban.text:SetText(text)
    ban.text:SetTextColor(r or C.gold[1], g or C.gold[2], b or C.gold[3])
    banT = 0
    ban:SetAlpha(0)
    ban:Show()
end

local function shake(amp, dur)
    if amp > shakeAmp or shakeT <= 0 then shakeAmp = amp end
    shakeT = math.max(shakeT, dur)
end

local GOLD = { r = 1, g = 0.82, b = 0.25 }

-- effets d une etape, a son debut
local function startFx(s)
    if not fxf then return end
    if s.t == "clear" then
        local sx, sy, n = 0, 0, 0
        for i in pairs(s.cells) do
            if not s.create[i] then
                local k = s.snap.kind[i]
                local x, y = posOf(i)
                burst(x, y, GEMS[k] or GEMS[1], k == DIAMOND and 8 or 3)
                sx, sy, n = sx + x, sy + y, n + 1
            end
        end
        local big = 0
        for _, f in ipairs(s.fx or {}) do
            local gem = GEMS[f.k] or GOLD
            if f.t == "row" then
                local _, y = cellPos(f.r, 1)
                beam(true, y, gem)
                big = big + 1
            elseif f.t == "col" then
                local x = cellPos(1, f.c)
                beam(false, x, gem)
                big = big + 1
            elseif f.t == "bomb" then
                local x, y = posOf(f.i)
                shock(x, y, TILE * (3.4 + 2 * (f.rad - 1)), gem, 0.45)
                burstRays(x, y, TILE * (3 + 2 * (f.rad - 1)), gem, 0.5)
                big = big + 2 * f.rad
            elseif f.t == "fly" then
                flyer(f.from, f.to, f.k)
            elseif f.t == "diamond" then
                local x, y = posOf(f.i)
                burstRays(x, y, BOARD * 1.1, GEMS[DIAMOND], 0.9, 0.55)
                shock(x, y, TILE * 4, GEMS[DIAMOND], 0.5)
                big = big + 4
            end
        end
        for i, cr in pairs(s.create) do
            local x, y = posOf(i)
            local gem = GEMS[cr.k] or GOLD
            shock(x, y, TILE * 2.4, gem, 0.5)
            burstRays(x, y, TILE * 2.2, gem, 0.6, 0.6)
        end
        if n > 0 and (s.points or 0) > 0 then
            local size = s.cascade >= 3 and 22 or (s.cascade >= 2 and 19 or 16)
            popup(sx / n, sy / n, "+" .. s.points, 1, 0.86, 0.35, size)
        end
        if s.banner then
            if s.finale then banner(s.banner, 1, 0.55, 1)
            elseif s.duo then banner(s.banner, 0.55, 0.9, 1)
            else banner(s.banner) end
        end
        if s.cascade >= 3 or big >= 3 or s.duo or s.finale then
            shake(math.min(6, 1.5 + big * 0.6 + (s.cascade - 2)), 0.25)
        end
        if s.cascade >= 4 or s.finale or (s.duo and big >= 4) then
            burstRays(BOARD / 2, -BOARD / 2, BOARD * 1.4, GOLD, 1, 0.35)
        end
    elseif s.t == "convert" then
        for i in pairs(s.cells) do
            local x, y = posOf(i)
            shock(x, y, TILE * 1.8, GEMS[s.k] or GOLD, 0.4)
        end
        banner(L.JOA_DUO, 0.55, 0.9, 1)
    elseif s.t == "shuffle" then
        if s.banner then banner(s.banner, 0.8, 0.8, 0.85) end
    end
end

---------------------------------------------------------------------------
-- Animation des etapes
---------------------------------------------------------------------------

local function stepLen(s)
    if s.t == "swap" then return s.back and SWAP * 2 or SWAP end
    if s.t == "clear" then return CLEAR + ((s.fx and #s.fx > 0) and 0.08 or 0) end
    if s.t == "fall" then
        local d = 0
        for i, r0 in pairs(s.from) do
            local r = rc(i)
            if r - r0 > d then d = r - r0 end
        end
        return math.max(0.12, math.min(0.42, d * FALL_ROW + 0.06))
    end
    if s.t == "shuffle" then return SHUFFLE end
    if s.t == "convert" then return CONVERT end
    return 0
end

-- chute qui rebondit un peu a l arrivee
local function landing(p)
    if p < 0.8 then
        local q = p / 0.8
        return q * q
    end
    local q = (p - 0.8) / 0.2
    return 1 - 0.06 * math.sin(math.pi * q)
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
            if i == s.a then return ax + (bx - ax) * q, ay + (by - ay) * q, 1 + 0.1 * math.sin(math.pi * q), 1 end
            if i == s.b then return bx + (ax - bx) * q, by + (ay - by) * q, 1, 1 end
            return x, y, 1, 1
        end)
    elseif s.t == "clear" then
        drawBoard(snap.kind, snap.spec, function(i, x, y)
            if s.create[i] then return x, y, 1 + 0.25 * math.sin(math.pi * p), 1 end
            if s.cells[i] then return x, y, 1 + 0.25 * p - 1.1 * p * p, 1 - p end
            return x, y, 1, 1
        end)
    elseif s.t == "fall" then
        local q = landing(p)
        drawBoard(snap.kind, snap.spec, function(i, x, y)
            local r0 = s.from[i]
            local r, c = rc(i)
            if r0 and r0 ~= r then
                local _, y0 = cellPos(r0, c)
                return x, y0 + (y - y0) * q, 1, 1
            end
            return x, y, 1, 1
        end)
    elseif s.t == "convert" then
        drawBoard(snap.kind, snap.spec, function(i, x, y)
            if s.cells[i] then return x, y, 1 + 0.2 * math.sin(math.pi * p * 2), 1 end
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
            startFx(s)
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

---------------------------------------------------------------------------
-- Panneau : score, records, coups, classement de la guilde
---------------------------------------------------------------------------

local function fmt(n)
    n = math.floor(tonumber(n) or 0)
    if BreakUpLargeNumbers then
        local ok, s = pcall(BreakUpLargeNumbers, n)
        if ok and type(s) == "string" then return s end
    end
    return tostring(n)
end

local function shortName(full)
    if type(full) ~= "string" then return "?" end
    return full:match("^([^%-]+)") or full
end

local function classRGB(class)
    if class and ns.ClassColor then
        local ok, r, g, b = pcall(ns.ClassColor, class)
        if ok and r then return r, g, b end
    end
    return 0.85, 0.85, 0.85
end

local MEDAL = { { 1, 0.82, 0.25 }, { 0.78, 0.8, 0.86 }, { 0.85, 0.55, 0.3 } }

-- rang du joueur dans le classement (mode), et nombre de lignes
local function myRank(mode)
    local S = Scores()
    if not S or not S.Board then return nil end
    local list = S.Board("joaillier", mode)
    for i, e in ipairs(list) do if e.me then return i, #list end end
    return nil, #list
end

function refreshBoard()
    if not side then return end
    local S = Scores()
    local mode = db.lb == "week" and "week" or "best"
    local list = S and S.Board and S.Board("joaillier", mode) or {}
    local rows = side.rows
    -- dix lignes au plus : le joueur hors du haut du classement prend la
    -- derniere, avec son rang
    local shown, mine = {}, nil
    for i, e in ipairs(list) do
        e.rank = i
        if e.me then mine = e end
    end
    for i = 1, math.min(#rows, #list) do shown[i] = list[i] end
    if mine and mine.rank > #rows then shown[#rows] = mine end
    for i, row in ipairs(rows) do
        local e = shown[i]
        if e then
            row.rank:SetText(e.rank .. ".")
            local m = MEDAL[e.rank]
            if m then row.rank:SetTextColor(m[1], m[2], m[3]) else row.rank:SetTextColor(0.6, 0.6, 0.65) end
            row.name:SetText(shortName(e.name) .. (e.me and (" |cff999999" .. L.JOA_ME .. "|r") or ""))
            row.name:SetTextColor(classRGB(e.class))
            row.score:SetText(fmt(e.score))
            row.me:SetShown(e.me and true or false)
            row:Show()
        else
            row:Hide()
        end
    end
    local others = #list - (mine and 1 or 0)
    side.empty:SetShown(others == 0)
    if side.mode then side.mode:Refresh() end
end

local sureUntil = 0

local function showOverlay(title, lines, b1)
    overlay.title:SetText(title)
    overlay.line:SetText(lines or "")
    overlay.b1:SetText(b1.text)
    overlay.b1.fn = b1.fn
    overlay.b1:SetWidth(math.max(130, overlay.b1.cuiText and overlay.b1.cuiText:GetStringWidth() + 24 or 130))
    overlay:Show()
end

function refresh()
    if not win then return end
    hud.best:SetText(fmt(math.max(db.best or 0, st.score)))
    hud.week:SetText(fmt(math.max(weekBest(), st.score)))
    hud.chain:SetText(string.format(L.JOA_CHAIN, st.chain or 0))
    hud.moves:SetText(st.moves)
    hud.movesText:SetText(string.format(L.JOA_MOVES_BAR, st.moves))
    local frac = math.max(0, math.min(1, st.moves / MOVES))
    hud.fill:SetWidth(math.max(1, (BOARD - 2) * frac))
    if st.moves <= 5 then
        hud.fill:SetColorTexture(0.9, 0.3, 0.25, 0.9)
        hud.movesText:SetTextColor(1, 0.75, 0.7)
    else
        hud.fill:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.75)
        hud.movesText:SetTextColor(1, 1, 1)
    end
    hud.new:SetText(GetTime() < sureUntil and L.JOA_SURE or L.JOA_NEW)
    if InCombatLockdown() then
        hud.status:SetText(L.JOA_COMBAT)
    elseif msg and GetTime() < msgUntil then
        hud.status:SetText(msg)
    else
        hud.status:SetText(L.JOA_READY)
    end
    placeMarks()
    refreshBoard()
    if anim then return end
    if st.over then
        local line = string.format(L.JOA_OVER2, st.score)
        if st.score > 0 and st.score > (st.startBest or 0) then
            line = line .. "\n|cffffd100" .. L.JOA_NEW_BEST .. "|r"
        elseif st.score > 0 and st.score > (st.startWeek or 0) then
            line = line .. "\n|cffffd100" .. L.JOA_WEEK_BEST .. "|r"
        end
        local rank, total = myRank(db.lb == "week" and "week" or "best")
        if rank and total and total > 1 then line = line .. "\n" .. string.format(L.JOA_RANK, rank, total) end
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

local function card(parent, x, y, w, h)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, h)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    ns.UI.Skin(f, 0.55)
    return f
end

local function label(parent, text, x, y)
    local l = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    l:SetPoint("TOPLEFT", x, y)
    l:SetText(text)
    return l
end

-- cadre a quatre bords (case choisie, indice, survol)
local function outline(r, g, b, thick, fill, alpha)
    local f = CreateFrame("Frame", nil, board)
    f:SetFrameLevel(board:GetFrameLevel() + 10)
    for _, sd in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(r, g, b, alpha or 1)
        if sd == "TOP" or sd == "BOTTOM" then
            t:SetPoint(sd .. "LEFT")
            t:SetPoint(sd .. "RIGHT")
            t:SetHeight(thick)
        else
            t:SetPoint("TOP" .. sd)
            t:SetPoint("BOTTOM" .. sd)
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

local function buildSide()
    local x = PAD + BOARD + 12
    side = CreateFrame("Frame", nil, win)
    side:SetSize(SIDE_W, BOARD)
    side:SetPoint("TOPLEFT", win, "TOPLEFT", x, -TOP)
    -- score
    local sc = card(side, 0, 0, SIDE_W, 74)
    label(sc, L.JOA_SCORE, 10, -8)
    hud.score = sc:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(hud.score, 28)
    hud.score:SetPoint("TOPLEFT", 10, -22)
    hud.score:SetTextColor(1, 1, 1)
    hud.chain = sc:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hud.chain:SetPoint("BOTTOMLEFT", 10, 7)
    hud.moves = sc:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(hud.moves, 20)
    hud.moves:SetPoint("TOPRIGHT", -10, -22)
    local ml = sc:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ml:SetPoint("TOPRIGHT", -10, -8)
    ml:SetText(L.JOA_MOVES)
    -- records : de toujours, de la semaine
    local half = math.floor((SIDE_W - 6) / 2)
    local rb = card(side, 0, -80, half, 44)
    label(rb, L.JOA_BEST, 8, -6)
    hud.best = rb:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(hud.best, 15)
    hud.best:SetPoint("BOTTOMLEFT", 8, 6)
    local wb = card(side, SIDE_W - half, -80, half, 44)
    label(wb, L.JOA_WEEK, 8, -6)
    hud.week = wb:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(hud.week, 15)
    hud.week:SetPoint("BOTTOMLEFT", 8, 6)
    -- classement de la guilde (un par compte)
    local lbH = BOARD - 130 - 30
    local lb = card(side, 0, -130, SIDE_W, lbH)
    local t = lb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t:SetPoint("TOPLEFT", 8, -9)
    t:SetText(L.JOA_LB_TITLE)
    t:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    local function modes()
        return { { value = "best", text = L.JOA_LB_BEST }, { value = "week", text = L.JOA_LB_WEEK } }
    end
    side.mode = ns.UI.Select(lb, SIDE_W - 12, modes, function() return db.lb == "week" and "week" or "best" end,
        function(v) db.lb = v end, function() refresh() end)
    if side.mode then side.mode:SetPoint("TOPLEFT", lb, "TOPLEFT", 6, -24) end
    side.rows = {}
    for i = 1, LB_ROWS do
        local row = CreateFrame("Frame", nil, lb)
        row:SetSize(SIDE_W - 12, 20)
        row:SetPoint("TOPLEFT", lb, "TOPLEFT", 6, -52 - (i - 1) * 21)
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.025 or 0.05)
        row.me = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        row.me:SetAllPoints()
        row.me:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.22)
        row.me:Hide()
        row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.rank:SetPoint("LEFT", 4, 0)
        row.rank:SetWidth(22)
        row.rank:SetJustifyH("RIGHT")
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", 30, 0)
        row.name:SetPoint("RIGHT", -64, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.score = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.score:SetPoint("RIGHT", -6, 0)
        row.score:SetJustifyH("RIGHT")
        row:Hide()
        side.rows[i] = row
    end
    side.empty = lb:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    side.empty:SetPoint("BOTTOMLEFT", 8, 8)
    side.empty:SetPoint("BOTTOMRIGHT", -8, 8)
    side.empty:SetJustifyH("LEFT")
    side.empty:SetText(L.JOA_LB_EMPTY)
    -- nouvelle partie
    hud.new = ns.UI.Button(side, L.JOA_NEW, SIDE_W, function()
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
    hud.new:SetHeight(26)
    hud.new:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", 0, 0)
end

-- souris : clic puis clic, ou glisser une gemme vers sa voisine
local function onBoardDown(self, button)
    if button ~= "LeftButton" then return end
    local x0, y0 = cursorPoint(self)
    self.downX, self.downY, self.downCell = x0, y0, cellAt(x0, y0)
end

local function onBoardUp(self, button)
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
end

-- animation de la grille, a chaque image
local function onBoardUpdate(self, dt)
    animStep(dt)
    stepFx(dt)
    local now = GetTime()
    -- gemmes speciales vivantes : halo qui respire, rayons qui
    -- tournent, etoile qui tourne autour des filantes, traits qui
    -- scintillent
    local p = 0.35 + 0.2 * math.sin(now * 5)
    for j = 1, used do
        local f = tiles[j]
        if f.glow:IsShown() then f.glow:SetAlpha(p) end
        if f.rays:IsShown() then
            rotate(f.rays, now * 0.8)
            f.rays:SetAlpha(f.k == DIAMOND and 0.55 or 0.35)
        end
        if f.orbit:IsShown() then
            local a = now * 4 + j
            local rr = (f.size or TILE) * 0.36
            f.orbit:ClearAllPoints()
            f.orbit:SetPoint("CENTER", f, "CENTER", math.cos(a) * rr, math.sin(a) * rr)
        end
        if f.bars[1]:IsShown() then
            local ba = 0.55 + 0.4 * math.sin(now * 7 + j)
            f.bars[1]:SetAlpha(ba)
            f.bars[2]:SetAlpha(ba)
        end
    end
    -- gemme choisie qui palpite
    if sel and not anim and cellTile[sel] then
        local s = TILE * (1.04 + 0.05 * math.sin(now * 8))
        cellTile[sel]:SetSize(s, s)
        cellTile[sel].size = nil
    end
    if hint then hintBox:SetAlpha(0.5 + 0.5 * math.sin(now * 4)) end
    -- survol
    local hx, hy
    if not st.over and self:IsMouseOver() then hx, hy = cursorPoint(self) end
    local hc = hx and cellAt(hx, hy)
    if hc and hc ~= sel then
        local cx, cy = posOf(hc)
        hoverBox:ClearAllPoints()
        hoverBox:SetPoint("CENTER", self, "TOPLEFT", cx, cy)
        hoverBox:SetSize(TILE, TILE)
        hoverBox:Show()
    else
        hoverBox:Hide()
    end
    -- score qui monte jusqu au vrai
    if hud.disp ~= st.score then
        local d = st.score - (hud.disp or 0)
        if math.abs(d) < 1 or d < 0 then hud.disp = st.score
        else hud.disp = hud.disp + math.max(1, d * math.min(1, dt * 7)) end
        if hud.disp > st.score then hud.disp = st.score end
    end
    hud.score:SetText(fmt(hud.disp))
    -- bandeau
    if banT then
        banT = banT + dt
        local q = banT / banLife
        if q >= 1 then
            banT = nil
            ban:Hide()
        else
            local sc = q < 0.15 and (0.6 + 0.6 * (q / 0.15)) or (q < 0.25 and (1.2 - 0.2 * ((q - 0.15) / 0.1)) or 1)
            ban:SetScale(sc)
            ban:SetAlpha(q < 0.1 and q / 0.1 or (q > 0.75 and (1 - q) / 0.25 or 1))
        end
    end
    -- secousse
    if shakeT > 0 then
        shakeT = shakeT - dt
        local a = shakeT > 0 and shakeAmp * (shakeT / 0.25) or 0
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + (math.random() * 2 - 1) * a, -TOP + (math.random() * 2 - 1) * a)
    end
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
    if msg and now >= msgUntil then
        msg = nil
        refresh()
    end
end

-- fin de partie, clavier, ouverture et fermeture (hors de build : le Lua
-- du jeu refuse une fonction a plus de 60 variables exterieures)
local function buildOverlay()
    overlay = CreateFrame("Frame", nil, board)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(board:GetFrameLevel() + 20)
    local shade = overlay:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    shade:SetColorTexture(0, 0, 0, 0.66)
    overlay.title = overlay:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(overlay.title, 24)
    overlay.title:SetPoint("CENTER", 0, 52)
    overlay.title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    overlay.line = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    overlay.line:SetPoint("TOP", overlay.title, "BOTTOM", 0, -12)
    overlay.line:SetWidth(BOARD - 30)
    overlay.line:SetSpacing(4)
    overlay.b1 = ns.UI.Button(overlay, "", 130, function(self) if self.fn then self.fn() end end)
    overlay.b1:SetPoint("TOP", overlay.line, "BOTTOM", 0, -16)
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
        hud.disp = st.score
        drawFinal()
        refresh()
    end)
    win:SetScript("OnHide", function()
        setKeyboard(false)
        finishAnim()
        clearFx()
        if board then
            board:ClearAllPoints()
            board:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -TOP)
        end
        sel, hint = nil, nil
        save()
        local S = Scores()
        if S and S.Changed then S.Changed("joaillier") end
    end)
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
    local icon = bar:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", 8, 0)
    icon:SetTexture(iconOf(DIAMOND))
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local title = bar:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(title, 14)
    title:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    title:SetText(L.JOA_TITLE)
    local close = CreateFrame("Button", nil, bar)
    close:SetSize(22, 22)
    close:SetPoint("RIGHT", -4, 0)
    local x = close:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    x:SetPoint("CENTER")
    x:SetText("×")
    close:SetScript("OnClick", function() win:Hide() end)
    hud = { disp = st.score }
    -- grille : cadre dore fin, fond sombre, cases en damier
    local frame = CreateFrame("Frame", nil, win)
    frame:SetPoint("TOPLEFT", win, "TOPLEFT", PAD - 3, -TOP + 3)
    frame:SetSize(BOARD + 6, BOARD + 6)
    local fb = frame:CreateTexture(nil, "BACKGROUND")
    fb:SetAllPoints()
    fb:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.35)
    local fi = frame:CreateTexture(nil, "BORDER")
    fi:SetPoint("TOPLEFT", 1, -1)
    fi:SetPoint("BOTTOMRIGHT", -1, 1)
    fi:SetColorTexture(0.02, 0.02, 0.03, 1)
    board = CreateFrame("Frame", nil, win)
    board:SetSize(BOARD, BOARD)
    board:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -TOP)
    board:SetFrameLevel(frame:GetFrameLevel() + 1)
    pcall(board.SetClipsChildren, board, true)
    local back = board:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(0.04, 0.035, 0.06, 0.95)
    local amb = board:CreateTexture(nil, "BACKGROUND", nil, 1)
    amb:SetPoint("CENTER")
    amb:SetSize(BOARD * 1.3, BOARD * 1.3)
    amb:SetTexture(FXDIR .. "lueur")
    amb:SetVertexColor(C.violet[1], C.violet[2], C.violet[3], 1)
    amb:SetAlpha(0.22)
    amb:SetBlendMode("ADD")
    for r = 1, N do
        for c = 1, N do
            local slot = board:CreateTexture(nil, "BORDER")
            slot:SetSize(TILE, TILE)
            local cx, cy = cellPos(r, c)
            slot:SetPoint("CENTER", board, "TOPLEFT", cx, cy)
            slot:SetColorTexture(1, 1, 1, (r + c) % 2 == 0 and 0.06 or 0.03)
        end
    end
    selBox = outline(C.gold[1], C.gold[2], C.gold[3], 2, 0.18)
    hintBox = outline(1, 1, 1, 2, 0.12)
    hoverBox = outline(1, 1, 1, 1, 0.06, 0.25)
    -- effets, au-dessus des gemmes
    fxf = CreateFrame("Frame", nil, board)
    fxf:SetAllPoints()
    fxf:SetFrameLevel(board:GetFrameLevel() + 15)
    mkSpark = texMaker(FXDIR .. "etincelle", 3)
    mkGlow = texMaker(FXDIR .. "lueur", 1)
    mkRays = texMaker(FXDIR .. "rayons", 0)
    mkBeam = texMaker(nil, 2)
    mkIcon = texMaker(nil, 4, "BLEND")
    -- bandeau (cascade, combinaison, bouquet final)
    ban = CreateFrame("Frame", nil, board)
    ban:SetSize(BOARD, 56)
    ban:SetPoint("CENTER", board, "CENTER", 0, 0)
    ban:SetFrameLevel(board:GetFrameLevel() + 18)
    local strip = ban:CreateTexture(nil, "BACKGROUND")
    strip:SetAllPoints()
    strip:SetColorTexture(0, 0, 0, 0.5)
    for _, sd in ipairs({ "TOP", "BOTTOM" }) do
        local line = ban:CreateTexture(nil, "BORDER")
        line:SetPoint(sd .. "LEFT")
        line:SetPoint(sd .. "RIGHT")
        line:SetHeight(1)
        line:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.5)
    end
    ban.text = ban:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(ban.text, 26)
    ban.text:SetPoint("CENTER")
    ban:Hide()
    -- coups restants : barre sous la grille
    local mb = CreateFrame("Frame", nil, win)
    mb:SetSize(BOARD, 18)
    mb:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -TOP - BOARD - 8)
    ns.UI.Skin(mb, 0.7)
    hud.fill = mb:CreateTexture(nil, "ARTWORK")
    hud.fill:SetPoint("TOPLEFT", 1, -1)
    hud.fill:SetPoint("BOTTOMLEFT", 1, 1)
    hud.fill:SetWidth(BOARD - 2)
    hud.movesText = mb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hud.movesText:SetPoint("CENTER")
    hud.status = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hud.status:SetPoint("TOP", mb, "BOTTOM", 0, -7)
    hud.status:SetWidth(BOARD)
    buildSide()
    board:EnableMouse(true)
    board:SetScript("OnMouseDown", onBoardDown)
    board:SetScript("OnMouseUp", onBoardUp)
    board:SetScript("OnUpdate", onBoardUpdate)
    buildOverlay()
    win:Hide()
end

local function toggle()
    if not db then return end
    if not win then build() end
    win:SetShown(not win:IsShown())
end

-- liste des jeux : ouverture pendant un vol, ligne de la page des
-- mini-jeux (Jeux.lua), avec ses reglages
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
    ready = function() return db ~= nil end,
    play = function() toggle() end,
    icon = function() return iconOf(DIAMOND) end,
    tagline = function() return L.JOA_DESC end,
    hint = function() return L.JOA_HINT end,
    stats = function()
        return string.format(L.MURLOC_BEST, db.best or 0) .. "   ·   " .. string.format(L.JOA_STATS, db.games or 0)
    end,
    options = function(form)
        form:Check(L.MURLOC_OPT_SOUND, function() return db.sound end, function(v) db.sound = v end)
        form:Check(L.JOA_OPT_HINT, function() return db.hint end, function(v)
            db.hint = v
            if not v then
                hint = nil
                if win then placeMarks() end
            end
        end)
        form:Number(L.MURLOC_OPT_SCALE, function() return math.floor((db.scale or 1) * 100 + 0.5) end,
            function(v) db.scale = v / 100 end, 60, 150, 5)
    end,
    apply = function() if win then win:SetScale(db.scale or 1) end end,
})

-- records partages avec la guilde (Jeux.lua) ; classement a jour quand
-- arrive la fiche d un autre joueur
if ns.Games.Scores and ns.Games.Scores.Register then
    ns.Games.Scores.Register("joaillier", function()
        if not db then return 0, 0 end
        return db.best or 0, weekBest()
    end)
    ns.Games.Scores.OnChange(function() if win and win:IsShown() then refreshBoard() end end)
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
    icon = ns.ItemIcon(12800),
    title = function() return L.MOD_JOAILLIER end,
    desc = function() return L.JOA_DESC end,
    Slash = function(rest)
        rest = strlower(strtrim(rest or ""))
        if rest == "options" or rest == "config" then ns.Games.ShowOptions("joaillier") else toggle() end
    end,
})

-- banc d essai
ns._joaillier = { st = st, idx = idx, rc = rc, findRuns = findRuns, analyze = analyze, expand = expand,
                  gravity = gravity, validSwap = validSwap, findMove = findMove, doSwap = doSwap,
                  click = click, shuffle = shuffle, fresh = fresh, newGame = newGame, load = load,
                  save = save, toggle = toggle, finishAnim = finishAnim, animStep = animStep,
                  cellAt = cellAt, cellPos = cellPos, iconOf = iconOf, squareAt = squareAt,
                  matchAt = matchAt, combo = combo, finale = finale, cascades = cascades,
                  weekBest = weekBest, refreshBoard = refreshBoard,
                  setRand = function(fn) rand = fn or math.random end,
                  setChain = function(v) chainRate = v or CHAIN end,
                  live = function() return live end,
                  extra = function() return side, ban, fxf end,
                  N = N, KINDS = KINDS, DIAMOND = DIAMOND, SP_ROW = SP_ROW, SP_COL = SP_COL,
                  SP_BOMB = SP_BOMB, SP_FLY = SP_FLY, MOVES = MOVES, GEMS = GEMS,
                  ui = function() return win, board, overlay, hud, tiles, anim, sel, hint, msg end }
