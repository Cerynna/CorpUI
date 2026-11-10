--[[--------------------------------------------------------------------------
    CorpUI - module Jeux : le siege

    Casse-briques a nous : on renvoie un boulet avec son bouclier contre la
    muraille d une forteresse. Chaque pierre cassee rapporte des points ;
    les pierres renforcees demandent 2 ou 3 coups (elles se fendent et
    s assombrissent), les plaques de fer ne cassent jamais. Douze murailles
    dessinees a la main, puis on recommence, plus vite (points multiplies).
    3 vies ; record, meilleure muraille et parties gardes par compte.
      - souris (le bouclier suit le curseur sur le jeu), fleches, Q / D ou
        A / D (reglage) : deplacer ; Espace, fleche haut ou clic : lancer le
        boulet ; P : pause ; Echap : fermer ;
      - bonus qui tombent des pierres (environ 1 sur 8), icones des sorts du
        jeu : Mur protecteur (bouclier large), Fleches multiples (trois
        boulets), Eclair de givre (boulet lent), Boule de feu (le boulet
        traverse la pierre), Imposition des mains (une vie) ; un piege :
        Malediction de faiblesse (bouclier retreci) ;
      - physique a pas fixe (1/240 s) : le boulet ne traverse jamais une
        pierre ; l angle du rebond suit l endroit touche sur le bouclier ;
        la vitesse monte un peu a chaque pierre touchee ;
      - en combat : pause, clavier rendu au jeu ; fenetre cachee : pause ;
      - la partie est gardee (fermer, /reload, vol suivant) : on reprend la
        muraille en cours, pierres deja cassees comprises, boulet sur le
        bouclier ;
      - pierres, bouclier et boulet dessines (aucune image a nous) ; sons de
        CorpUI : verre a chaque pierre, tambour sur le fer, ding au bonus,
        montee a la breche, carillon au record, trombone triste a la fin.
    Fenetre a nous, deplacable ; rien de Blizzard n est touche.
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local C = ns.COLORS

local SOUNDS = ns.MEDIA .. "Sons\\"
local ICON = "Interface\\Icons\\Ability_Warrior_ShieldWall"
local DISC = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

-- canevas (origine en bas a gauche, y vers le haut)
local W, H = 480, 540
local HUD_H = 26                  -- bandeau du haut (muraille, vies, score)
local TOP = H - HUD_H             -- plafond du jeu
-- muraille : 12 colonnes, 14 lignes au plus, d un mur a l autre (le
-- passage le long d un mur, 7 px, est plus etroit que le boulet)
local COLS, ROWS = 12, 14
local MARGIN = 6
local CW, CH = 39, 18             -- case (pierre + joint)
local BW, BH = CW - 2, CH - 2     -- pierre dessinee
local GRID_TOP = TOP - 34         -- haut de la premiere ligne (place derriere)
-- bouclier et boulet
local PADDLE_Y, PADDLE_H = 34, 12 -- centre, epaisseur
local PADDLE_W = { normal = 88, wide = 132, small = 58 }
local R = 6                       -- rayon du boulet
local KEY_SPEED = 560             -- bouclier au clavier (px/s)
local MAX_ANGLE = 1.05            -- rebond le plus ouvert (rad depuis la verticale)
local MIN_DY = 0.22               -- jamais presque a plat
-- vitesse du boulet (px/s) : base par muraille, +un peu a chaque pierre
local SPEED0, SPEED_STEP, SPEED_LOOP = 280, 8, 50
local SPEED_RAMP, SPEED_GAIN, SPEED_CAP = 1.2, 110, 620
local SLOW = 0.65
-- partie
local DT = 1 / 240                -- pas fixe de la physique
local MAX_BALLS = 6
local LIVES, MAX_LIVES = 3, 6
local DROP_CHANCE, DROP_SPEED, DROP_SIZE = 0.12, 140, 22
local BETWEEN = 1.8               -- pause entre deux murailles (s)
local HIT_PTS, BONUS_PTS, CLEAR_PTS = 5, 25, 250
local BREAK_PTS = { 10, 25, 50 }  -- selon le nombre de coups qu il fallait

-- murailles : ligne du haut d abord, 12 caracteres ; "." vide, "1" pierre,
-- "2" / "3" pierre renforcee (2 ou 3 coups), "#" fer (ne casse pas)
local LEVELS = {
    {   -- les remparts
        "............",
        ".1111111111.",
        ".1111111111.",
        ".1111111111.",
        ".1111111111.",
        ".1111111111.",
    },
    {   -- les creneaux
        "2.22.22.22.2",
        "222222222222",
        "111111111111",
        "111111111111",
        "1..........1",
        "111111111111",
    },
    {   -- les tours
        "22........22",
        "22..2222..22",
        "11..1111..11",
        "11..1111..11",
        "11..1111..11",
        "11........11",
        "111111111111",
    },
    {   -- la porte
        "222222222222",
        "2..........2",
        "2.11111111.2",
        "2.1######1.2",
        "2..........2",
        "2.11111111.2",
        "............",
        "111......111",
    },
    {   -- le donjon
        ".....33.....",
        "....2222....",
        "...111111...",
        "..11111111..",
        ".1111111111.",
        "..11111111..",
        "...111111...",
        "....2222....",
        ".....##.....",
    },
    {   -- le damier
        "1.1.1.1.1.1.",
        ".2.2.2.2.2.2",
        "1.1.1.1.1.1.",
        ".2.2.2.2.2.2",
        "1.1.1.1.1.1.",
        ".2.2.2.2.2.2",
        "1.1.1.1.1.1.",
    },
    {   -- la herse
        "333333333333",
        "222222222222",
        "#.##.##.##.#",
        "111111111111",
        "111111111111",
        "............",
        "#..#....#..#",
    },
    {   -- les meurtrieres
        "2222....2222",
        "2#22....22#2",
        "2222....2222",
        "............",
        "111111111111",
        "1#1#1..1#1#1",
        "111111111111",
    },
    {   -- la citadelle
        "3..333333..3",
        "3..3####3..3",
        "3..3....3..3",
        "2..2....2..2",
        "2..222222..2",
        "1..........1",
        "111111111111",
    },
    {   -- la banniere
        "..33333333..",
        "..3######3..",
        "..32222223..",
        "..32111123..",
        "..32111123..",
        "..32222223..",
        "..33333333..",
        "....3..3....",
    },
    {   -- le chemin de ronde
        "############",
        "............",
        "222222222222",
        "1.1.1.1.1.1.",
        ".1.1.1.1.1.1",
        "222222222222",
        "............",
        "##........##",
    },
    {   -- le grand assaut
        "333333333333",
        "322222222223",
        "321111111123",
        "321#1111#123",
        "321111111123",
        "322222222223",
        "333333333333",
    },
}

-- bonus : sort du jeu (icone lue sur le client, repli : chemin connu),
-- poids du tirage, duree (s) pour ceux qui durent
local BONUS = {
    { key = "wide",  spell = 871,  w = 22, time = 15, text = "SIE_BONUS_WIDE",  icon = "Ability_Warrior_ShieldWall" },   -- Mur protecteur
    { key = "multi", spell = 2643, w = 20,            text = "SIE_BONUS_MULTI", icon = "Ability_UpgradeMoonGlaive" },    -- Fleches multiples
    { key = "slow",  spell = 116,  w = 18, time = 10, text = "SIE_BONUS_SLOW",  icon = "Spell_Frost_FrostBolt02" },      -- Eclair de givre
    { key = "fire",  spell = 133,  w = 14, time = 7,  text = "SIE_BONUS_FIRE",  icon = "Spell_Fire_FlameBolt" },         -- Boule de feu
    { key = "life",  spell = 633,  w = 8,             text = "SIE_BONUS_LIFE",  icon = "Spell_Holy_LayOnHands" },        -- Imposition des mains
    { key = "small", spell = 702,  w = 18, time = 12, text = "SIE_BONUS_SMALL", icon = "Spell_Shadow_CurseOfMannoroth", trap = true },   -- Malediction de faiblesse
}
local BONUS_BY = {}
for _, b in ipairs(BONUS) do BONUS_BY[b.key] = b end
local FX_ORDER = { "wide", "small", "slow", "fire" }

-- couleur des pierres selon la ligne (du haut vers le bas)
local ROW_COLORS = {
    { 0.78, 0.20, 0.20 }, { 0.86, 0.46, 0.14 }, { 0.84, 0.70, 0.22 }, { 0.32, 0.66, 0.28 },
    { 0.18, 0.60, 0.62 }, { 0.26, 0.44, 0.82 }, { 0.56, 0.34, 0.80 },
}
local IRON = { 0.40, 0.42, 0.47 }

local db
local win, canvas, hud, overlay, paddle
local cells = {}                  -- textures des cases (par index)
local ballTex, dropTex, lifeTex, fxIcons = {}, {}, {}, {}
-- etat : ready, serve (boulet sur le bouclier), run, pause, between, over
local st = { state = "ready", level = 1, loop = 0, score = 0, lives = LIVES, grid = {}, left = 0,
             balls = {}, drops = {}, fx = {}, keys = {}, px = W / 2, speed = SPEED0, speedBase = SPEED0 }
local acc = 0                     -- temps pas encore simule

local function clean(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) and v or nil end

local icons = {}
local function spellIcon(def)
    local id = def.spell
    if icons[id] then return icons[id] end
    local tex
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, v = pcall(C_Spell.GetSpellTexture, id)
        if ok then tex = clean(v) end
    end
    if not tex and GetSpellTexture then
        local ok, v = pcall(GetSpellTexture, id)
        if ok then tex = clean(v) end
    end
    if tex then icons[id] = tex return tex end
    return def.icon and ("Interface\\Icons\\" .. def.icon) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local lastSound = -1
local function play(file)
    if not (db and db.sound) then return end
    local now = GetTime()
    if now - lastSound < 0.05 then return end
    lastSound = now
    pcall(PlaySoundFile, SOUNDS .. file .. ".ogg", "Master")
end

local function scoreText(n) return string.format("%06d", math.max(0, math.floor(n))) end

---------------------------------------------------------------------------
-- Muraille
---------------------------------------------------------------------------

local function idx(r, c) return (r - 1) * COLS + c end

-- rectangle d une pierre : gauche, bas, droite, haut (pixels du canevas)
local function brickRect(r, c)
    local x0 = MARGIN + (c - 1) * CW + 1
    local y1 = GRID_TOP - (r - 1) * CH - 1
    return x0, y1 - BH, x0 + BW, y1
end

-- plan et tour (0 au premier passage) d une muraille
local function planOf(n)
    return LEVELS[(n - 1) % #LEVELS + 1], math.floor((n - 1) / #LEVELS)
end

local function countLeft()
    local n = 0
    for i = 1, COLS * ROWS do
        local b = st.grid[i]
        if b and not b.iron then n = n + 1 end
    end
    st.left = n
    return n
end

local function loadLevel(n)
    local plan, loop = planOf(n)
    st.level, st.loop = n, loop
    st.grid = {}
    for r = 1, ROWS do
        local line = plan[r]
        for c = 1, COLS do
            local ch = line and line:sub(c, c) or "."
            if ch == "#" then
                st.grid[idx(r, c)] = { iron = true }
            elseif ch == "1" or ch == "2" or ch == "3" then
                local m = tonumber(ch)
                st.grid[idx(r, c)] = { hp = m, max = m }
            end
        end
    end
    countLeft()
    st.speedBase = math.min(SPEED_CAP, SPEED0 + SPEED_STEP * ((n - 1) % #LEVELS) + SPEED_LOOP * loop)
    st.speed = st.speedBase
end

---------------------------------------------------------------------------
-- Partie
---------------------------------------------------------------------------

local hitBrick, levelClear, loseLife, gameOver
local drawCell, drawAll, render, updateHud, showOverlay, showToast, save

local function paddleW()
    if (st.fx.wide or 0) > 0 then return PADDLE_W.wide end
    if (st.fx.small or 0) > 0 then return PADDLE_W.small end
    return PADDLE_W.normal
end

local function clampPaddle()
    local half = paddleW() / 2
    st.px = math.max(half, math.min(W - half, st.px or W / 2))
end

local function norm(dx, dy)
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 1e-6 then return 0, 1 end
    return dx / d, dy / d
end

-- jamais presque a l horizontale (le boulet tournerait sans fin)
local function fixAngle(b)
    if math.abs(b.dy) < MIN_DY then
        local sy = b.dy < 0 and -1 or 1
        local sx = b.dx < 0 and -1 or 1
        b.dy = sy * MIN_DY
        b.dx = sx * math.sqrt(1 - MIN_DY * MIN_DY)
    end
end

local function newBall(x, y, dx, dy)
    local b = { x = x, y = y, dx = dx, dy = dy }
    table.insert(st.balls, b)
    return b
end

local function addScore(n) st.score = (st.score or 0) + n end

-- boulet pose sur le bouclier, en attente du lancer
local function serve()
    st.state = "serve"
    st.balls, st.drops, st.fx = {}, {}, {}
    clampPaddle()
    newBall(st.px, PADDLE_Y + PADDLE_H / 2 + R + 1, 0, 1)
end

local function launch()
    if st.state ~= "serve" then return end
    local b = st.balls[1]
    if not b then serve() b = st.balls[1] end
    local a = (math.random() - 0.5) * 0.6
    b.dx, b.dy = math.sin(a), math.cos(a)
    st.state = "run"
    acc = 0
end

local function pickBonus()
    local total = 0
    for _, b in ipairs(BONUS) do total = total + b.w end
    local x = math.random() * total
    for _, b in ipairs(BONUS) do
        x = x - b.w
        if x < 0 then return b end
    end
    return BONUS[#BONUS]
end

local function spawnDrop(x, y, key)
    local def = key and BONUS_BY[key] or pickBonus()
    local d = { x = x, y = y, def = def }
    table.insert(st.drops, d)
    return d
end

local function applyBonus(def)
    local k = def.key
    if k == "wide" then
        st.fx.small, st.fx.wide = nil, def.time
    elseif k == "small" then
        st.fx.wide, st.fx.small = nil, def.time
    elseif k == "slow" then
        st.fx.slow = def.time
    elseif k == "fire" then
        st.fx.fire = def.time
    elseif k == "life" then
        st.lives = math.min(MAX_LIVES, st.lives + 1)
    elseif k == "multi" then
        local src = st.balls[1]
        if src then
            for _, a in ipairs({ -0.45, 0.45 }) do
                if #st.balls >= MAX_BALLS then break end
                local cs, sn = math.cos(a), math.sin(a)
                local nb = newBall(src.x, src.y, src.dx * cs - src.dy * sn, src.dx * sn + src.dy * cs)
                nb.dx, nb.dy = norm(nb.dx, nb.dy)
                fixAngle(nb)
            end
        end
    end
    clampPaddle()
    addScore(BONUS_PTS * (1 + st.loop))
    play(def.trap and "ding_grave" or "ding")
    if showToast then showToast(L[def.text], def.trap) end
end

-- une pierre touchee (fire : le boulet de feu la casse d un coup)
function hitBrick(r, c, fire)
    local i = idx(r, c)
    local b = st.grid[i]
    if not b then return end
    if b.iron then
        play("tambour")
        return
    end
    local mult = 1 + st.loop
    st.speed = math.min(SPEED_CAP, st.speedBase + SPEED_GAIN, st.speed + SPEED_RAMP)
    b.hp = fire and 0 or (b.hp - 1)
    addScore(HIT_PTS * mult)
    if b.hp > 0 then
        play("tambour")
        drawCell(i)
        return
    end
    st.grid[i] = nil
    st.left = st.left - 1
    addScore((BREAK_PTS[b.max] or 10) * mult)
    db.stones = (db.stones or 0) + 1
    drawCell(i)
    play("verre")
    if math.random() < DROP_CHANCE then
        local x0, y0, x1, y1 = brickRect(r, c)
        spawnDrop((x0 + x1) / 2, (y0 + y1) / 2)
    end
    if st.left <= 0 then levelClear() end
end

-- pierres touchees apres un deplacement le long d un axe (le boulet ne
-- chevauche jamais une pierre en fin de pas) : rebond sur la premiere dans
-- le sens du mouvement, le boulet est repousse contre sa face ; boulet de
-- feu : toutes celles qu il touche cassent, il ne rebondit que sur le fer.
-- Deplacement par pas (2,6 px a pleine vitesse) bien plus court qu une
-- pierre + le boulet (28 px) : aucune traversee.
local burnt = {}
local function collideAxis(b, axis)
    local c1 = math.max(1, math.floor((b.x - R - MARGIN) / CW) + 1)
    local c2 = math.min(COLS, math.floor((b.x + R - MARGIN) / CW) + 1)
    local r1 = math.max(1, math.floor((GRID_TOP - (b.y + R)) / CH) + 1)
    local r2 = math.min(ROWS, math.floor((GRID_TOP - (b.y - R)) / CH) + 1)
    if c1 > c2 or r1 > r2 then return end
    local fire = (st.fx.fire or 0) > 0
    local n = 0
    local hr, hc, hkey, hother, hx0, hy0, hx1, hy1
    for r = r1, r2 do
        for c = c1, c2 do
            local brick = st.grid[idx(r, c)]
            if brick then
                local x0, y0, x1, y1 = brickRect(r, c)
                local qx = math.max(x0, math.min(b.x, x1))
                local qy = math.max(y0, math.min(b.y, y1))
                local ddx, ddy = b.x - qx, b.y - qy
                if ddx * ddx + ddy * ddy < R * R then
                    if fire and not brick.iron then
                        n = n + 1
                        burnt[n] = idx(r, c)
                    else
                        -- la premiere face rencontree, puis la plus en face
                        local key, other
                        if axis == "x" then
                            key = b.dx > 0 and x0 or -x1
                            other = math.abs(b.y - (y0 + y1) / 2)
                        else
                            key = b.dy > 0 and y0 or -y1
                            other = math.abs(b.x - (x0 + x1) / 2)
                        end
                        if not hkey or key < hkey or (key == hkey and other < hother) then
                            hr, hc, hkey, hother, hx0, hy0, hx1, hy1 = r, c, key, other, x0, y0, x1, y1
                        end
                    end
                end
            end
        end
    end
    for k = 1, n do
        local i = burnt[k]
        burnt[k] = nil
        if st.state == "run" then hitBrick(math.floor((i - 1) / COLS) + 1, (i - 1) % COLS + 1, true) end
    end
    if not hkey or st.state ~= "run" then return end
    if axis == "x" then
        b.x = b.dx > 0 and (hx0 - R - 0.01) or (hx1 + R + 0.01)
        b.dx = -b.dx
    else
        b.y = b.dy > 0 and (hy0 - R - 0.01) or (hy1 + R + 0.01)
        b.dy = -b.dy
    end
    hitBrick(hr, hc, false)
end

-- un pas fixe : boulets, pierres (axe x puis axe y), murs, bouclier
local function physics(h)
    local spd = st.speed * (((st.fx.slow or 0) > 0) and SLOW or 1)
    local half = paddleW() / 2
    local ptop = PADDLE_Y + PADDLE_H / 2
    for i = #st.balls, 1, -1 do
        local b = st.balls[i]
        if b.dx ~= 0 then
            b.x = b.x + b.dx * spd * h
            collideAxis(b, "x")
            if st.state ~= "run" then return end
        end
        if b.x < R then b.x, b.dx = R, math.abs(b.dx) end
        if b.x > W - R then b.x, b.dx = W - R, -math.abs(b.dx) end
        b.y = b.y + b.dy * spd * h
        collideAxis(b, "y")
        if st.state ~= "run" then return end
        if b.y > TOP - R then b.y, b.dy = TOP - R, -math.abs(b.dy) end
        -- bouclier : l angle suit l endroit touche (bord = rebond ouvert)
        if b.dy < 0 and b.y - R <= ptop and b.y >= PADDLE_Y - PADDLE_H / 2
            and math.abs(b.x - st.px) <= half + R then
            local off = math.max(-1, math.min(1, (b.x - st.px) / half))
            local a = off * MAX_ANGLE
            b.dx, b.dy = math.sin(a), math.cos(a)
            b.y = ptop + R
        end
        if b.y < -R then table.remove(st.balls, i) end
    end
    if #st.balls == 0 then loseLife() end
end

local function moveDrops(dt)
    local half = paddleW() / 2
    local ptop, pbot = PADDLE_Y + PADDLE_H / 2, PADDLE_Y - PADDLE_H / 2
    for i = #st.drops, 1, -1 do
        local d = st.drops[i]
        d.y = d.y - DROP_SPEED * dt
        local s = DROP_SIZE / 2
        if d.y - s <= ptop and d.y + s >= pbot and math.abs(d.x - st.px) <= half + s then
            table.remove(st.drops, i)
            applyBonus(d.def)
        elseif d.y < -DROP_SIZE then
            table.remove(st.drops, i)
        end
    end
end

-- position de la souris sur le canevas (nil : pas dessus)
local function cursorX()
    if not canvas or not canvas:IsMouseOver() then return nil end
    local ok, cx = pcall(GetCursorPosition)
    if not ok or type(cx) ~= "number" then return nil end
    local left, s = canvas:GetLeft(), canvas:GetEffectiveScale()
    if type(left) ~= "number" or type(s) ~= "number" or s == 0 then return nil end
    return cx / s - left
end

-- clavier d abord ; la souris ne reprend la main que si elle bouge
local function movePaddle(dt)
    local dir = (st.keys.right and 1 or 0) - (st.keys.left and 1 or 0)
    if dir ~= 0 then
        st.px = (st.px or W / 2) + dir * KEY_SPEED * dt
    else
        local mx = cursorX()
        if mx and mx ~= st.lastMouse then st.px = mx end
        st.lastMouse = mx
    end
    clampPaddle()
    if st.state == "serve" and st.balls[1] then st.balls[1].x = st.px end
end

local function step(dt)
    dt = math.min(dt or 0, 0.05)
    if st.toastT and st.toastT > 0 then st.toastT = st.toastT - dt end
    if st.state == "between" then
        st.wait = (st.wait or 0) - dt
        if st.wait <= 0 then
            serve()
            if overlay then overlay:Hide() end
            save()
        end
        if render then render() end
        return
    end
    if st.state ~= "run" and st.state ~= "serve" then return end
    movePaddle(dt)
    if st.state == "run" then
        for k, t in pairs(st.fx) do
            t = t - dt
            st.fx[k] = t > 0 and t or nil
        end
        clampPaddle()
        acc = acc + dt
        while acc >= DT and st.state == "run" do
            acc = acc - DT
            physics(DT)
        end
        if st.state == "run" then moveDrops(dt) end
    end
    if render then render() end
end

function loseLife()
    st.lives = st.lives - 1
    if st.lives <= 0 then gameOver() return end
    play("ding_grave")
    serve()
    save()
end

-- breche : bonus, muraille suivante affichee derriere le message
function levelClear()
    addScore((CLEAR_PTS + 100 * st.level) * (1 + st.loop))
    loadLevel(st.level + 1)
    if st.level > (db.bestLevel or 0) then db.bestLevel = st.level end
    st.state = "between"
    st.wait = BETWEEN
    st.balls, st.drops, st.fx = {}, {}, {}
    play("montee")
    if drawAll then drawAll() end
    if showOverlay then showOverlay(L.SIE_CLEAR, string.format(L.SIE_CLEAR2, st.level), "") end
    save()
end

function gameOver()
    st.state = "over"
    st.lives = 0
    st.balls, st.drops, st.fx = {}, {}, {}
    local s = math.floor(st.score)
    st.newBest = s > (db.best or 0)
    if st.newBest then
        db.best = s
        play("carillon")
    else
        play("trombone")
    end
    if st.level > (db.bestLevel or 0) then db.bestLevel = st.level end
    db.save = nil
    if updateHud then updateHud() end
    if showOverlay then
        showOverlay(L.SIE_OVER,
            string.format(L.SIE_SCORE, s) .. "   " .. (st.newBest and ("|cffffd100" .. L.SIE_NEW_BEST .. "|r") or string.format(L.SIE_BEST, db.best or 0)),
            string.format(L.SIE_OVER2, st.level) .. "   ·   " .. L.SIE_RETRY)
    end
end

local function start()
    if InCombatLockdown() then return end
    st.score, st.lives, st.newBest = 0, LIVES, false
    st.px = W / 2
    loadLevel(1)
    serve()
    if overlay then overlay:Hide() end
    if drawAll then drawAll() end
    db.games = (db.games or 0) + 1
    if (db.bestLevel or 0) < 1 then db.bestLevel = 1 end
    save()
end

local function pause(reason)
    if st.state ~= "run" and st.state ~= "serve" then return end
    st.resumeTo = st.state
    st.state = "pause"
    st.keys = {}
    save()
    if showOverlay then showOverlay(L.SIE_TITLE, reason or L.SIE_PAUSED, L.SIE_RESUME) end
end

local function resume()
    if st.state ~= "pause" or InCombatLockdown() then return end
    st.state = st.resumeTo or "serve"
    acc = 0
    if overlay then overlay:Hide() end
end

-- Espace, clic : commencer, reprendre, lancer
local function press()
    if st.state == "ready" or st.state == "over" then
        start()
    elseif st.state == "pause" then
        resume()
    elseif st.state == "serve" then
        launch()
    end
end

-- partie gardee : muraille, score, vies et pierres (boulet sur le bouclier)
function save()
    if not db then return end
    if st.state == "ready" or st.state == "over" then db.save = nil return end
    local list = {}
    for i = 1, COLS * ROWS do
        local b = st.grid[i]
        list[i] = b and (b.iron and -1 or (b.max * 10 + b.hp)) or 0
    end
    db.save = { level = st.level, score = st.score, lives = st.lives, cells = list }
end

local function load()
    local s = db and db.save
    if type(s) ~= "table" or type(s.level) ~= "number" or type(s.score) ~= "number"
        or type(s.lives) ~= "number" or type(s.cells) ~= "table" or s.level < 1 or s.lives < 1 then
        return false
    end
    loadLevel(math.floor(s.level))
    st.grid = {}
    for i = 1, COLS * ROWS do
        local v = s.cells[i]
        if v == -1 then
            st.grid[i] = { iron = true }
        elseif type(v) == "number" and v > 0 then
            local m, hp = math.floor(v / 10), v % 10
            if m >= 1 and m <= 3 and hp >= 1 and hp <= m then st.grid[i] = { max = m, hp = hp } end
        end
    end
    if countLeft() == 0 then return false end
    st.score = s.score
    st.lives = math.min(MAX_LIVES, math.floor(s.lives))
    serve()
    st.state, st.resumeTo = "pause", "serve"
    return true
end

---------------------------------------------------------------------------
-- Dessin
---------------------------------------------------------------------------

-- disque : carre colore passe au masque rond (repli : carre)
local function disc(parent, layer, sub, size)
    local t = parent:CreateTexture(nil, layer, nil, sub)
    t:SetSize(size, size)
    t:SetColorTexture(1, 1, 1, 1)
    local ok, m = pcall(parent.CreateMaskTexture, parent)
    if ok and m then
        pcall(m.SetTexture, m, DISC, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(t)
        pcall(t.AddMaskTexture, t, m)
    end
    return t
end

local function cellTex(i)
    local t = cells[i]
    if t then return t end
    local r, c = math.floor((i - 1) / COLS) + 1, (i - 1) % COLS + 1
    local x0, y0 = brickRect(r, c)
    t = {}
    t.base = canvas:CreateTexture(nil, "ARTWORK", nil, 0)
    t.base:SetSize(BW, BH)
    t.base:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", x0, y0)
    -- taille de la pierre : arete claire en haut, ombre en bas
    t.hi = canvas:CreateTexture(nil, "ARTWORK", nil, 1)
    t.hi:SetHeight(3)
    t.hi:SetPoint("TOPLEFT", t.base, "TOPLEFT", 0, 0)
    t.hi:SetPoint("TOPRIGHT", t.base, "TOPRIGHT", 0, 0)
    t.sh = canvas:CreateTexture(nil, "ARTWORK", nil, 1)
    t.sh:SetHeight(3)
    t.sh:SetPoint("BOTTOMLEFT", t.base, "BOTTOMLEFT", 0, 0)
    t.sh:SetPoint("BOTTOMRIGHT", t.base, "BOTTOMRIGHT", 0, 0)
    -- marques : joints (pierre renforcee) ou rivets (fer)
    t.m1 = canvas:CreateTexture(nil, "ARTWORK", nil, 2)
    t.m2 = canvas:CreateTexture(nil, "ARTWORK", nil, 2)
    -- fissures : un trait par coup recu
    t.k1 = canvas:CreateTexture(nil, "ARTWORK", nil, 3)
    t.k1:SetSize(2, 13)
    t.k1:SetPoint("CENTER", t.base, "CENTER", -6, 0)
    t.k1:SetColorTexture(0.05, 0.04, 0.04, 0.85)
    pcall(t.k1.SetRotation, t.k1, 0.55)
    t.k2 = canvas:CreateTexture(nil, "ARTWORK", nil, 3)
    t.k2:SetSize(2, 11)
    t.k2:SetPoint("CENTER", t.base, "CENTER", 8, 1)
    t.k2:SetColorTexture(0.05, 0.04, 0.04, 0.85)
    pcall(t.k2.SetRotation, t.k2, -0.7)
    cells[i] = t
    return t
end

local function hideCell(t)
    for _, x in pairs(t) do x:Hide() end
end

function drawCell(i)
    if not canvas then return end
    local b = st.grid[i]
    if not b then
        if cells[i] then hideCell(cells[i]) end
        return
    end
    local t = cellTex(i)
    local row = math.floor((i - 1) / COLS) + 1
    local cr, cg, cb
    if b.iron then
        cr, cg, cb = IRON[1], IRON[2], IRON[3]
    else
        local col = ROW_COLORS[(row - 1) % #ROW_COLORS + 1]
        local k = 1 - 0.24 * (b.max - b.hp)     -- plus sombre a chaque coup
        cr, cg, cb = col[1] * k, col[2] * k, col[3] * k
    end
    t.base:SetColorTexture(cr, cg, cb, 1)
    t.hi:SetColorTexture(math.min(1, cr * 1.3 + 0.1), math.min(1, cg * 1.3 + 0.1), math.min(1, cb * 1.3 + 0.1), 1)
    t.sh:SetColorTexture(cr * 0.5, cg * 0.5, cb * 0.5, 1)
    t.base:Show() t.hi:Show() t.sh:Show()
    t.m1:ClearAllPoints()
    t.m2:ClearAllPoints()
    if b.iron then
        for k, m in ipairs({ t.m1, t.m2 }) do
            m:SetSize(3, 3)
            m:SetPoint("CENTER", t.base, "LEFT", k == 1 and 6 or BW - 6, 0)
            m:SetColorTexture(0.16, 0.17, 0.2, 1)
            m:Show()
        end
    elseif b.max >= 2 then
        for k, m in ipairs({ t.m1, t.m2 }) do
            if k < b.max then
                m:SetSize(1, BH - 6)
                m:SetPoint("CENTER", t.base, "LEFT", BW * k / b.max, 0)
                m:SetColorTexture(cr * 0.45, cg * 0.45, cb * 0.45, 1)
                m:Show()
            else
                m:Hide()
            end
        end
    else
        t.m1:Hide() t.m2:Hide()
    end
    local dmg = b.iron and 0 or (b.max - b.hp)
    t.k1:SetShown(dmg >= 1)
    t.k2:SetShown(dmg >= 2)
end

function drawAll()
    if not canvas then return end
    for i = 1, COLS * ROWS do drawCell(i) end
end

local function ballTexture(i)
    local t = ballTex[i]
    if t then return t end
    t = disc(canvas, "OVERLAY", 1, R * 2)
    t.glint = disc(canvas, "OVERLAY", 2, 4)
    t.glint:SetPoint("CENTER", t, "CENTER", -2, 2)
    t.glint:SetColorTexture(1, 1, 1, 0.6)
    ballTex[i] = t
    return t
end

local function dropTexture(i)
    local t = dropTex[i]
    if t then return t end
    t = canvas:CreateTexture(nil, "OVERLAY", nil, 3)
    t:SetSize(DROP_SIZE + 2, DROP_SIZE + 2)
    t.icon = canvas:CreateTexture(nil, "OVERLAY", nil, 4)
    t.icon:SetPoint("TOPLEFT", t, "TOPLEFT", 1, -1)
    t.icon:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -1, 1)
    t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    dropTex[i] = t
    return t
end

local last = {}
function updateHud()
    if not hud then return end
    local best = math.max(db.best or 0, math.floor(st.score or 0))
    if last.level ~= st.level then last.level = st.level hud.level:SetText(string.format(L.SIE_LEVEL, st.level)) end
    if last.score ~= st.score then last.score = st.score hud.score:SetText(scoreText(st.score or 0)) end
    if last.best ~= best then last.best = best hud.best:SetText(L.SIE_HI .. " " .. scoreText(best)) end
    for k, t in ipairs(lifeTex) do t:SetShown(k <= (st.lives or 0)) end
end

function showToast(text, bad)
    if not hud then return end
    hud.toast:SetText(text or "")
    if bad then hud.toast:SetTextColor(1, 0.35, 0.3) else hud.toast:SetTextColor(C.gold[1], C.gold[2], C.gold[3]) end
    st.toastT = 1.6
end

function render()
    if not canvas then return end
    -- bouclier
    local w = paddleW()
    paddle.base:SetWidth(w)
    paddle.base:SetPoint("CENTER", canvas, "BOTTOMLEFT", st.px or W / 2, PADDLE_Y)
    local tint = (st.fx.wide and "wide") or (st.fx.small and "small") or "normal"
    if paddle.tint ~= tint then
        paddle.tint = tint
        if tint == "wide" then paddle.base:SetColorTexture(0.36, 0.52, 0.42, 1)
        elseif tint == "small" then paddle.base:SetColorTexture(0.55, 0.30, 0.34, 1)
        else paddle.base:SetColorTexture(0.42, 0.44, 0.50, 1) end
    end
    -- boulets (rouge orange en boulet de feu)
    local fire = (st.fx.fire or 0) > 0
    for i, b in ipairs(st.balls) do
        local t = ballTexture(i)
        t:SetPoint("CENTER", canvas, "BOTTOMLEFT", b.x, b.y)
        if t.fire ~= fire then
            t.fire = fire
            if fire then t:SetColorTexture(1, 0.45, 0.1, 1) else t:SetColorTexture(0.64, 0.64, 0.68, 1) end
        end
        t:Show() t.glint:Show()
    end
    for i = #st.balls + 1, #ballTex do ballTex[i]:Hide() ballTex[i].glint:Hide() end
    -- bonus qui tombent
    for i, d in ipairs(st.drops) do
        local t = dropTexture(i)
        t:SetPoint("CENTER", canvas, "BOTTOMLEFT", d.x, d.y)
        if t.def ~= d.def then
            t.def = d.def
            t.icon:SetTexture(spellIcon(d.def))
            if d.def.trap then t:SetColorTexture(0.9, 0.2, 0.2, 1) else t:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1) end
        end
        t:Show() t.icon:Show()
    end
    for i = #st.drops + 1, #dropTex do dropTex[i]:Hide() dropTex[i].icon:Hide() end
    -- effets en cours (icone et secondes)
    local n = 0
    for _, k in ipairs(FX_ORDER) do
        local t = st.fx[k]
        if t and t > 0 then
            n = n + 1
            local f = fxIcons[n]
            if f then
                f.icon:SetTexture(spellIcon(BONUS_BY[k]))
                f.secs:SetText(math.ceil(t))
                f:Show()
            end
        end
    end
    for i = n + 1, #fxIcons do fxIcons[i]:Hide() end
    -- message de bonus, aide au lancer
    if st.toastT and st.toastT > 0 then
        hud.toast:SetAlpha(math.min(1, st.toastT / 0.4))
        hud.toast:Show()
    else
        hud.toast:Hide()
    end
    hud.hint:SetShown(st.state == "serve")
    updateHud()
end

function showOverlay(title, line1, line2)
    if not overlay then return end
    overlay.title:SetText(title)
    overlay.line1:SetText(line1 or "")
    overlay.line2:SetText(line2 or "")
    overlay:Show()
end

---------------------------------------------------------------------------
-- Fenetre
---------------------------------------------------------------------------

local MOVE_KEYS = { LEFT = "left", RIGHT = "right" }
local LETTER_KEYS = { Q = "left", A = "left", D = "right" }
local LAUNCH_KEYS = { SPACE = true, UP = true }

local function setKeyboard(on)
    if not win then return end
    pcall(win.EnableKeyboard, win, on and not InCombatLockdown())
end

local function build()
    db.pos = db.pos or { point = "CENTER", x = 0, y = 40 }
    win = CreateFrame("Frame", "CorpUISiegeGame", UIParent)
    win:SetSize(W + 8, H + 34)
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
    title:SetText(L.SIE_TITLE)
    local close = CreateFrame("Button", nil, bar)
    close:SetSize(22, 22)
    close:SetPoint("RIGHT", -4, 0)
    local x = close:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    x:SetPoint("CENTER")
    x:SetText("×")
    close:SetScript("OnClick", function() win:Hide() end)
    -- canevas : nuit sur la forteresse
    canvas = CreateFrame("Frame", nil, win)
    canvas:SetSize(W, H)
    canvas:SetPoint("BOTTOM", win, "BOTTOM", 0, 4)
    canvas:SetClipsChildren(true)
    canvas:EnableMouse(true)
    canvas:SetScript("OnMouseDown", function() press() end)
    local sky = canvas:CreateTexture(nil, "BACKGROUND")
    sky:SetAllPoints()
    sky:SetColorTexture(1, 1, 1, 1)
    if not (CreateColor and pcall(sky.SetGradient, sky, "VERTICAL", CreateColor(0.035, 0.035, 0.05, 1), CreateColor(0.10, 0.11, 0.16, 1))) then
        sky:SetColorTexture(0.06, 0.065, 0.09, 1)
    end
    -- ligne du sol sous le bouclier
    local ground = canvas:CreateTexture(nil, "BORDER")
    ground:SetPoint("BOTTOMLEFT", 0, 0)
    ground:SetPoint("BOTTOMRIGHT", 0, 0)
    ground:SetHeight(4)
    ground:SetColorTexture(0.55, 0.12, 0.12, 0.5)
    -- bouclier : acier, liseré d or, umbo au centre
    paddle = {}
    paddle.base = canvas:CreateTexture(nil, "ARTWORK", nil, 4)
    paddle.base:SetSize(PADDLE_W.normal, PADDLE_H)
    paddle.base:SetColorTexture(0.42, 0.44, 0.50, 1)
    paddle.rim = canvas:CreateTexture(nil, "ARTWORK", nil, 5)
    paddle.rim:SetHeight(3)
    paddle.rim:SetPoint("TOPLEFT", paddle.base, "TOPLEFT", 0, 0)
    paddle.rim:SetPoint("TOPRIGHT", paddle.base, "TOPRIGHT", 0, 0)
    paddle.rim:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    paddle.foot = canvas:CreateTexture(nil, "ARTWORK", nil, 5)
    paddle.foot:SetHeight(2)
    paddle.foot:SetPoint("BOTTOMLEFT", paddle.base, "BOTTOMLEFT", 0, 0)
    paddle.foot:SetPoint("BOTTOMRIGHT", paddle.base, "BOTTOMRIGHT", 0, 0)
    paddle.foot:SetColorTexture(0.15, 0.15, 0.18, 1)
    paddle.boss = canvas:CreateTexture(nil, "ARTWORK", nil, 6)
    paddle.boss:SetSize(12, 6)
    paddle.boss:SetPoint("CENTER", paddle.base, "CENTER", 0, -1)
    paddle.boss:SetColorTexture(C.gold[1] * 0.85, C.gold[2] * 0.85, C.gold[3] * 0.85, 1)
    -- bandeau : muraille, vies, score, record
    hud = CreateFrame("Frame", nil, canvas)
    hud:SetAllPoints()
    hud:SetFrameLevel(canvas:GetFrameLevel() + 5)
    local band = hud:CreateTexture(nil, "BACKGROUND")
    band:SetPoint("TOPLEFT", 0, 0)
    band:SetPoint("TOPRIGHT", 0, 0)
    band:SetHeight(HUD_H)
    band:SetColorTexture(0, 0, 0, 0.55)
    local rule = hud:CreateTexture(nil, "BORDER")
    rule:SetPoint("TOPLEFT", band, "BOTTOMLEFT", 0, 0)
    rule:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT", 0, 0)
    rule:SetHeight(1)
    rule:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.35)
    hud.level = hud:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(hud.level, 13)
    hud.level:SetPoint("TOPLEFT", 10, -6)
    hud.level:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    for k = 1, MAX_LIVES do
        local t = disc(hud, "OVERLAY", 1, 9)
        t:SetPoint("TOPLEFT", hud, "TOPLEFT", 112 + (k - 1) * 13, -9)
        t:SetColorTexture(0.64, 0.64, 0.68, 1)
        lifeTex[k] = t
    end
    hud.score = hud:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(hud.score, 16)
    hud.score:SetPoint("TOP", 20, -5)
    hud.score:SetTextColor(1, 1, 1)
    hud.best = hud:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(hud.best, 12)
    hud.best:SetPoint("TOPRIGHT", -10, -7)
    hud.best:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    -- effets en cours : sous le bandeau, a droite
    for k = 1, #FX_ORDER do
        local f = CreateFrame("Frame", nil, hud)
        f:SetSize(18, 18)
        f:SetPoint("TOPRIGHT", hud, "TOPRIGHT", -6 - (k - 1) * 22, -HUD_H - 4)
        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetAllPoints()
        f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f.secs = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        f.secs:SetPoint("BOTTOMRIGHT", 2, -2)
        f:Hide()
        fxIcons[k] = f
    end
    hud.toast = hud:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(hud.toast, 16)
    hud.toast:SetPoint("CENTER", hud, "BOTTOM", 0, 150)
    hud.toast:Hide()
    hud.hint = hud:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hud.hint:SetPoint("BOTTOM", hud, "BOTTOM", 0, 8)
    hud.hint:SetText(L.SIE_SERVE)
    hud.hint:Hide()
    -- panneau d accueil, pause, breche, fin
    overlay = CreateFrame("Frame", nil, canvas)
    overlay:SetSize(420, 112)
    overlay:SetPoint("CENTER", 0, -20)
    overlay:SetFrameLevel(canvas:GetFrameLevel() + 8)
    local shade = overlay:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    shade:SetColorTexture(0, 0, 0, 0.62)
    overlay.title = overlay:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(overlay.title, 24)
    overlay.title:SetPoint("TOP", 0, -12)
    overlay.title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    overlay.line1 = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    overlay.line1:SetPoint("TOP", overlay.title, "BOTTOM", 0, -10)
    overlay.line1:SetWidth(400)
    overlay.line2 = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    overlay.line2:SetPoint("TOP", overlay.line1, "BOTTOM", 0, -8)
    overlay.line2:SetWidth(400)
    overlay:EnableMouse(false)
    overlay:Hide()
    -- clavier : seulement les touches du jeu (et Echap) sont gardees
    win:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        local dir = MOVE_KEYS[key] or (db.letters and LETTER_KEYS[key])
        if dir then
            st.keys[dir] = true
            self:SetPropagateKeyboardInput(false)
        elseif LAUNCH_KEYS[key] then
            self:SetPropagateKeyboardInput(false)
            press()
        elseif key == "P" then
            self:SetPropagateKeyboardInput(false)
            if st.state == "pause" then resume() else pause() end
        elseif key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    win:SetScript("OnKeyUp", function(self, key)
        local dir = MOVE_KEYS[key] or LETTER_KEYS[key]
        if dir then st.keys[dir] = nil end
        if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
    end)
    win:SetScript("OnShow", function()
        setKeyboard(true)
        st.lastMouse = cursorX()
        drawAll()
        if st.state == "ready" then
            showOverlay(L.SIE_TITLE, L.SIE_START, L.SIE_START2)
        elseif st.state == "pause" then
            showOverlay(L.SIE_TITLE, string.format(L.SIE_SAVED, st.level), L.SIE_RESUME)
        end
        render()
    end)
    win:SetScript("OnHide", function()
        setKeyboard(false)
        pause()
        st.keys = {}
        save()
    end)
    canvas:SetScript("OnUpdate", function(_, dt) step(dt) end)
    win:Hide()
end

local function toggle()
    if not db then return end
    if InCombatLockdown() then ns.Say(L.COMBAT_BLOCKED) return end
    if not win then build() end
    win:SetShown(not win:IsShown())
end

-- liste des jeux : ouverture pendant un vol, ligne de la page des
-- mini-jeux (Jeux.lua), avec ses reglages
ns.Games.Register("siege", {
    title = function() return L.MOD_SIEGE end,
    open = function()
        if not db or InCombatLockdown() then return false end
        if not win then build() end
        win:Show()
        return true
    end,
    close = function() if win then win:Hide() end end,
    shown = function() return win and win:IsShown() or false end,
    ready = function() return db ~= nil end,
    play = function() toggle() end,
    icon = function() return ICON end,
    tagline = function() return L.SIE_DESC end,
    hint = function() return L.SIE_HINT end,
    stats = function()
        return string.format(L.SIE_BEST, db.best or 0) .. "   ·   " .. string.format(L.SIE_STATS, db.bestLevel or 0, db.games or 0)
    end,
    options = function(form, box)
        -- ce qui tombe des pierres : icones des sorts et leur effet
        local head = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        head:SetPoint("TOPLEFT", box, "TOPLEFT", 4, form.y)
        head:SetText(L.SIE_BONUSES)
        form:Gap(16)
        form:Columns(2)
        for _, def in ipairs(BONUS) do
            local x, y, w = form:Cell(22)
            local t = box:CreateTexture(nil, "ARTWORK")
            t:SetSize(18, 18)
            t:SetPoint("TOPLEFT", box, "TOPLEFT", 6 + x, y - 2)
            t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            t:SetTexture(spellIcon(def))
            local fs = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", t, "RIGHT", 6, 0)
            fs:SetWidth(w - 32)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            fs:SetText(L[def.text])
            if def.trap then fs:SetTextColor(1, 0.45, 0.4) end
        end
        form:Gap(6)
        form:Check(L.SIE_OPT_SOUND, function() return db.sound end, function(v) db.sound = v end)
        form:Check(L.SIE_OPT_LETTERS, function() return db.letters end, function(v) db.letters = v end)
        form:Number(L.SIE_OPT_SCALE, function() return math.floor((db.scale or 1) * 100 + 0.5) end,
            function(v) db.scale = v / 100 end, 60, 150, 5)
    end,
    apply = function() if win then win:SetScale(db.scale or 1) end end,
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
        if type(root.games.siege) ~= "table" then root.games.siege = {} end
        db = root.games.siege
        if db.sound == nil then db.sound = true end
        if db.letters == nil then db.letters = true end
        if type(db.scale) ~= "number" then db.scale = 1 end
        load()
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- combat : pause, clavier rendu au jeu
        if win and win:IsShown() then
            pause(L.SIE_COMBAT)
            pcall(win.EnableKeyboard, win, false)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if win and win:IsShown() then setKeyboard(true) end
    elseif event == "PLAYER_LOGOUT" then
        if st.state ~= "ready" and st.state ~= "over" then save() end
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_LOGOUT" }) do
    pcall(ev.RegisterEvent, ev, e)
end

ns.RegisterModule({
    command = "siege",
    alias = "briques",
    icon = ICON,
    title = function() return L.MOD_SIEGE end,
    desc = function() return L.SIE_DESC end,
    Slash = function(rest)
        rest = strlower(strtrim(rest or ""))
        if rest == "options" or rest == "config" then ns.Games.ShowOptions("siege") else toggle() end
    end,
})

-- banc d essai
ns._siege = {
    st = st, start = start, press = press, pause = pause, resume = resume, step = step, physics = physics,
    serve = serve, launch = launch, loadLevel = loadLevel, countLeft = countLeft, spawnDrop = spawnDrop,
    applyBonus = applyBonus, hitBrick = hitBrick, paddleW = paddleW, save = save, load = load, toggle = toggle,
    brickRect = brickRect, idx = idx, LEVELS = LEVELS, BONUS = BONUS, BONUS_BY = BONUS_BY,
    K = { W = W, H = H, TOP = TOP, R = R, PADDLE_Y = PADDLE_Y, PADDLE_H = PADDLE_H, PADDLE_W = PADDLE_W,
          GRID_TOP = GRID_TOP, COLS = COLS, ROWS = ROWS, DT = DT, BETWEEN = BETWEEN, MAX_ANGLE = MAX_ANGLE,
          SPEED0 = SPEED0, SPEED_GAIN = SPEED_GAIN, LIVES = LIVES, MAX_LIVES = MAX_LIVES },
    ui = function() return win, canvas, overlay, hud, paddle end,
}
