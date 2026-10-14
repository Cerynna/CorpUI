--[[--------------------------------------------------------------------------
    CorpUI - module Jeux : la course du murloc

    Mini-jeu facon "dinosaure de Google" : un murloc court sur la plage, on
    saute par-dessus crabes, oursins, rochers, caisses et coraux, on passe
    sous les mouettes qui volent haut (les basses se sautent). La vitesse
    monte peu a peu ; le score suit la distance ; record garde par compte.
      - Espace, fleche haut, Z / W ou clic dans le jeu : sauter (appui
        long = saut plus haut) ; Echap : fermer ;
      - en combat : pause, clavier rendu au jeu ;
      - images peintes generees avec Nano Banana (Media/Jeux), detourees
        (fond vert) ; fond et sol defilent en boucle (textures a raccord,
        mode REPEAT) ;
      - sons de CorpUI (Media/Sons) : ding tous les 100 points, carillon au
        record, trombone triste a la chute.
    Fenetre a nous, deplacable ; rien de Blizzard n est touche.
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local C = ns.COLORS

local MEDIA = ns.MEDIA .. "Jeux\\"
local SOUNDS = ns.MEDIA .. "Sons\\"

-- canevas
local W, H = 760, 260
local GROUND_H = 78               -- bande de sable (affichee)
local FLOOR = GROUND_H - 9        -- ligne des pieds
local BG_TILE = H * 2             -- fond 2:1 a la hauteur du canevas
local GROUND_TILE = GROUND_H * 4  -- sol 4:1

-- physique (pixels du canevas)
local GRAVITY, JUMP_V, CUT_V = 2600, 830, 330
local SPEED0, SPEED_MAX, ACCEL = 360, 790, 9
local MURLOC_X, MURLOC_SIZE = 96, 90
local CELL = 256

-- cases des planches (4 x 2), et boite du sprite dans sa case (x, y, w, h,
-- origine en haut a gauche ; releve par l outil de decoupe)
local MURLOC_BOX = { 37, 30, 183, 218 }
local OBST = {
    { key = "crab",   cell = 1, size = 72, box = { 8, 48, 240, 200 },  inset = { 0.16, 0.16, 0.06, 0.32 }, walk = 55 },
    { key = "urchin", cell = 2, size = 74, box = { 20, 8, 216, 240 },  inset = { 0.22, 0.22, 0.04, 0.20 } },
    { key = "rocks",  cell = 3, size = 92, box = { 8, 85, 240, 163 },  inset = { 0.12, 0.12, 0.05, 0.18 } },
    { key = "crate",  cell = 4, size = 84, box = { 8, 75, 240, 173 },  inset = { 0.12, 0.12, 0.05, 0.16 } },
    { key = "coral",  cell = 5, size = 92, box = { 31, 8, 195, 240 },  inset = { 0.20, 0.20, 0.04, 0.12 } },
    { key = "gull",   cell = 6, size = 78, box = { 8, 59, 240, 189 },  inset = { 0.18, 0.18, 0.28, 0.30 }, fly = true },
}

local db
local win, canvas, bg, ground, murloc, hud, overlay
local pool = {}                   -- textures des obstacles
local obstacles = {}
local st = { state = "ready" }    -- ready, run, over, pause

local function cellCoords(k)
    local col, row = (k - 1) % 4, math.floor((k - 1) / 4)
    return col * 0.25, col * 0.25 + 0.25, row * 0.5, row * 0.5 + 0.5
end

local function play(file)
    if db and db.sound then pcall(PlaySoundFile, SOUNDS .. file .. ".ogg", "Master") end
end

-- boite de collision (pixels du canevas) d un sprite pose en bas a gauche
-- (x, y) avec une case affichee de taille s
local function hitbox(x, y, s, box, inset)
    local k = s / CELL
    local l = x + box[1] * k
    local r = l + box[3] * k
    local t = y + (CELL - box[2]) * k
    local b = t - box[4] * k
    local w, h = r - l, t - b
    return l + w * inset[1], r - w * inset[2], b + h * inset[3], t - h * inset[4]
end

local function overlaps(a, b)
    return a[1] < b[2] and b[1] < a[2] and a[3] < b[4] and b[3] < a[4]
end

---------------------------------------------------------------------------
-- Partie
---------------------------------------------------------------------------

local function setMurlocFrame(k)
    local u0, u1, v0, v1 = cellCoords(k)
    murloc:SetTexCoord(u0, u1, v0, v1)
end

local function scoreText(n) return string.format("%05d", math.max(0, math.floor(n))) end

local function updateHud()
    hud.score:SetText(scoreText(st.score or 0))
    hud.best:SetText(L.MURLOC_HI .. " " .. scoreText(db.best or 0))
end

local function showOverlay(title, line1, line2)
    overlay.title:SetText(title)
    overlay.line1:SetText(line1 or "")
    overlay.line2:SetText(line2 or "")
    overlay:Show()
end

local function clearObstacles()
    for _, o in ipairs(obstacles) do
        o.tex:Hide()
        table.insert(pool, o.tex)
    end
    wipe(obstacles)
end

local function nextGap()
    -- au moins ~0,6 s entre deux obstacles, plus d espace a grande vitesse
    return st.speed * (0.62 + math.random() * 0.55) + 130
end

local function spawn(xExtra)
    local s = st.score
    local list = {}
    for i = 1, 5 do list[#list + 1] = OBST[i] end
    local def
    if s >= 150 and math.random() < 0.22 then def = OBST[6] else def = list[math.random(#list)] end
    local tex = table.remove(pool) or canvas:CreateTexture(nil, "ARTWORK", nil, 1)
    tex:SetTexture(MEDIA .. "obstacles")
    local u0, u1, v0, v1 = cellCoords(def.cell)
    tex:SetTexCoord(u0, u1, v0, v1)
    tex:SetSize(def.size, def.size)
    local y = FLOOR - 3
    if def.fly then
        -- basse : a sauter ; haute : on passe dessous
        y = (math.random() < 0.5) and (FLOOR + 22) or (FLOOR + 86)
    end
    local o = { def = def, tex = tex, x = W + (xExtra or 0), y = y, t = 0 }
    tex:Show()
    table.insert(obstacles, o)
    return o
end

local function start()
    if InCombatLockdown() then return end
    clearObstacles()
    st.state = "run"
    st.speed, st.dist, st.score, st.vy, st.y = SPEED0, 0, 0, 0, 0
    st.onGround, st.holding, st.next = true, false, 260
    st.milestone = 100
    st.newBest = false
    overlay:Hide()
    setMurlocFrame(1)
    pcall(murloc.SetRotation, murloc, 0)
    db.games = (db.games or 0) + 1
    updateHud()
end

local function gameOver()
    st.state = "over"
    setMurlocFrame(6)
    pcall(murloc.SetRotation, murloc, 0.25)
    local s = math.floor(st.score)
    local best = db.best or 0
    if s > best then
        db.best = s
        st.newBest = true
        play("carillon")
    else
        play("trombone")
    end
    updateHud()
    showOverlay(L.MURLOC_OVER, string.format(L.MURLOC_SCORE, s) .. "   " .. (st.newBest and ("|cffffd100" .. L.MURLOC_NEW_BEST .. "|r") or string.format(L.MURLOC_BEST, db.best or 0)),
        L.MURLOC_RETRY)
end

local function pause(reason)
    if st.state ~= "run" then return end
    st.state = "pause"
    showOverlay(L.MURLOC_TITLE, reason or L.MURLOC_PAUSED, L.MURLOC_START2)
end

-- appui : partir, sauter ; relache : saut coupe (appui court = petit saut)
local function press()
    if st.state == "ready" or st.state == "over" then
        start()
    elseif st.state == "pause" then
        if InCombatLockdown() then return end
        st.state = "run"
        overlay:Hide()
    elseif st.state == "run" and st.onGround then
        st.vy, st.onGround, st.holding = JUMP_V, false, true
        play("verre")
    end
end

local function release()
    st.holding = false
    if st.state == "run" and not st.onGround and st.vy > CUT_V then st.vy = CUT_V end
end

local function step(dt)
    if st.state ~= "run" then return end
    dt = math.min(dt, 0.05)
    st.speed = math.min(SPEED_MAX, st.speed + ACCEL * dt)
    local move = st.speed * dt
    st.dist = st.dist + move
    st.score = st.dist / 14
    -- murloc
    if not st.onGround then
        st.vy = st.vy - GRAVITY * dt
        st.y = st.y + st.vy * dt
        if st.y <= 0 then st.y, st.vy, st.onGround = 0, 0, true end
    end
    local bob = 0
    if st.onGround then
        local phase = st.dist / 30
        setMurlocFrame(math.floor(phase) % 4 + 1)
        bob = math.abs(math.sin(phase * math.pi)) * 3
        pcall(murloc.SetRotation, murloc, 0)
    else
        setMurlocFrame(5)
        pcall(murloc.SetRotation, murloc, math.max(-0.25, math.min(0.25, st.vy / 3600)))
    end
    murloc:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", MURLOC_X, FLOOR - 3 + st.y + bob)
    -- defilement : fond lent, sol a la vitesse du jeu
    st.bgU = ((st.bgU or 0) + move * 0.12 / BG_TILE) % 1
    st.gU = ((st.gU or 0) + move / GROUND_TILE) % 1
    bg:SetTexCoord(st.bgU, st.bgU + W / BG_TILE, 0, 1)
    ground:SetTexCoord(st.gU, st.gU + W / GROUND_TILE, 0, 1)
    -- obstacles
    local me = { hitbox(MURLOC_X, FLOOR - 3 + st.y, MURLOC_SIZE, MURLOC_BOX, { 0.24, 0.24, 0.06, 0.16 }) }
    for i = #obstacles, 1, -1 do
        local o = obstacles[i]
        o.t = o.t + dt
        o.x = o.x - move - (o.def.walk or 0) * dt
        local yy = o.y
        if o.def.fly then yy = yy + math.sin(o.t * 6) * 4 end
        if o.def.walk then yy = yy + math.abs(math.sin(o.t * 12)) * 2 end
        o.tex:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", o.x, yy)
        if o.x + o.def.size < -20 then
            o.tex:Hide()
            table.insert(pool, o.tex)
            table.remove(obstacles, i)
        else
            local hb = { hitbox(o.x, yy, o.def.size, o.def.box, o.def.inset) }
            if overlaps(me, hb) then gameOver() return end
        end
    end
    st.next = st.next - move
    if st.next <= 0 then
        local o = spawn()
        st.next = nextGap()
        -- plus loin : parfois deux obstacles colles
        if st.score >= 300 and not o.def.fly and math.random() < 0.18 then
            local o2 = spawn(o.def.size * 0.7)
            if o2.def.fly then o2.y = FLOOR - 3 + 90 end
        end
    end
    -- paliers
    if st.score >= st.milestone then
        st.milestone = st.milestone + 100
        play("ding")
        hud.flash = 0.6
    end
    if hud.flash and hud.flash > 0 then
        hud.flash = hud.flash - dt
        hud.score:SetAlpha((math.floor(hud.flash * 10) % 2 == 0) and 1 or 0.25)
    else
        hud.score:SetAlpha(1)
    end
    hud.score:SetText(scoreText(st.score))
end

---------------------------------------------------------------------------
-- Fenetre
---------------------------------------------------------------------------

local JUMP_KEYS = { SPACE = true, UP = true, W = true, Z = true }

local function setKeyboard(on)
    if not win then return end
    pcall(win.EnableKeyboard, win, on and not InCombatLockdown())
end

local function build()
    db.pos = db.pos or { point = "CENTER", x = 0, y = 120 }
    win = CreateFrame("Frame", "CorpUIMurlocGame", UIParent)
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
    title:SetText(L.MURLOC_TITLE)
    local close = CreateFrame("Button", nil, bar)
    close:SetSize(22, 22)
    close:SetPoint("RIGHT", -4, 0)
    local x = close:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    x:SetPoint("CENTER")
    x:SetText("×")
    close:SetScript("OnClick", function() win:Hide() end)
    -- canevas
    canvas = CreateFrame("Frame", nil, win)
    canvas:SetSize(W, H)
    canvas:SetPoint("BOTTOM", win, "BOTTOM", 0, 4)
    canvas:SetClipsChildren(true)
    canvas:EnableMouse(true)
    canvas:SetScript("OnMouseDown", function() press() end)
    canvas:SetScript("OnMouseUp", function() release() end)
    bg = canvas:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(MEDIA .. "bg", "REPEAT", "CLAMP")
    bg:SetTexCoord(0, W / BG_TILE, 0, 1)
    ground = canvas:CreateTexture(nil, "BORDER")
    ground:SetPoint("BOTTOMLEFT")
    ground:SetPoint("BOTTOMRIGHT")
    ground:SetHeight(GROUND_H)
    ground:SetTexture(MEDIA .. "ground", "REPEAT", "CLAMP")
    ground:SetTexCoord(0, W / GROUND_TILE, 0, 1)
    murloc = canvas:CreateTexture(nil, "ARTWORK", nil, 3)
    murloc:SetSize(MURLOC_SIZE, MURLOC_SIZE)
    murloc:SetTexture(MEDIA .. "murloc")
    murloc:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", MURLOC_X, FLOOR - 3)
    setMurlocFrame(1)
    -- score
    hud = CreateFrame("Frame", nil, canvas)
    hud:SetAllPoints()
    hud:SetFrameLevel(canvas:GetFrameLevel() + 5)
    hud.score = hud:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(hud.score, 18)
    hud.score:SetPoint("TOPRIGHT", -12, -8)
    hud.score:SetTextColor(1, 1, 1)
    hud.best = hud:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(hud.best, 14)
    hud.best:SetPoint("RIGHT", hud.score, "LEFT", -14, 0)
    hud.best:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    -- panneau d accueil / fin
    overlay = CreateFrame("Frame", nil, canvas)
    overlay:SetSize(420, 110)
    overlay:SetPoint("CENTER", 0, 26)
    overlay:SetFrameLevel(canvas:GetFrameLevel() + 6)
    local shade = overlay:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    shade:SetColorTexture(0, 0, 0, 0.45)
    overlay.title = overlay:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(overlay.title, 24)
    overlay.title:SetPoint("TOP", 0, -10)
    overlay.title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    overlay.line1 = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    overlay.line1:SetPoint("TOP", overlay.title, "BOTTOM", 0, -10)
    overlay.line2 = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    overlay.line2:SetPoint("TOP", overlay.line1, "BOTTOM", 0, -8)
    overlay:EnableMouse(false)
    -- clavier : seulement les touches de saut (et Echap) sont gardees
    win:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        if JUMP_KEYS[key] then
            press()
            self:SetPropagateKeyboardInput(false)
        elseif key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    win:SetScript("OnKeyUp", function(self, key)
        if JUMP_KEYS[key] then release() end
        if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
    end)
    win:SetScript("OnShow", function()
        setKeyboard(true)
        updateHud()
        if st.state == "ready" then showOverlay(L.MURLOC_TITLE, L.MURLOC_START, L.MURLOC_START2) end
    end)
    win:SetScript("OnHide", function()
        setKeyboard(false)
        pause()
        release()
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
ns.MurlocToggle = toggle

-- liste des jeux (ouverture pendant un vol : Jeux.lua)
ns.Games.Register("murloc", {
    title = function() return L.MOD_MURLOC end,
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
-- Reglages (/corp murloc)
---------------------------------------------------------------------------

local panel

local function buildPanel()
    panel = ns.UI.Window("CorpUIMurlocOptions", ns.TITLE .. " - " .. L.MOD_MURLOC, nil, 440, 380)
    local icon = panel:CreateTexture(nil, "ARTWORK")
    icon:SetSize(96, 96)
    icon:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -36)
    icon:SetTexture(MEDIA .. "murloc")
    icon:SetTexCoord(cellCoords(5))
    local desc = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -6)
    desc:SetWidth(320)
    desc:SetJustifyH("LEFT")
    desc:SetText(L.MURLOC_HINT)
    local stats = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    stats:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -10)
    local playBtn = ns.UI.Button(panel, L.MURLOC_PLAY, 120, function() toggle() end)
    playBtn:SetPoint("TOPLEFT", stats, "BOTTOMLEFT", 0, -10)
    local form = ns.UI.Form(panel, -146, function()
        if win then win:SetScale(db.scale or 1) end
    end)
    form:Check(L.MURLOC_OPT_SOUND, function() return db.sound end, function(v) db.sound = v end)
    form:Number(L.MURLOC_OPT_SCALE, function() return math.floor((db.scale or 1) * 100 + 0.5) end,
        function(v) db.scale = v / 100 end, 60, 150, 5)
    ns.Games.TaxiOptions(form)
    local credits = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    credits:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, form.y - 6)
    credits:SetWidth(424)
    credits:SetJustifyH("LEFT")
    credits:SetText(L.MURLOC_CREDITS)
    table.insert(form.refreshers, function()
        stats:SetText(string.format(L.MURLOC_BEST, db.best or 0) .. "   ·   " .. string.format(L.MURLOC_GAMES, db.games or 0))
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
        if type(root.games.murloc) ~= "table" then root.games.murloc = {} end
        db = root.games.murloc
        if db.sound == nil then db.sound = true end
        if type(db.scale) ~= "number" then db.scale = 1 end
        db.taxiOpen, db.taxiClose = nil, nil
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- combat : pause, clavier rendu au jeu
        if win and win:IsShown() then
            pause(L.MURLOC_COMBAT)
            pcall(win.EnableKeyboard, win, false)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if win and win:IsShown() then setKeyboard(true) end
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
    pcall(ev.RegisterEvent, ev, e)
end

ns.RegisterModule({
    command = "murloc",
    alias = "jeu",
    panelName = "CorpUIMurlocOptions",
    icon = MEDIA .. "icon",
    title = function() return L.MOD_MURLOC end,
    desc = function() return L.MURLOC_DESC end,
    Slash = function(rest)
        rest = strlower(strtrim(rest or ""))
        if rest == "options" or rest == "config" then openPanel() else toggle() end
    end,
    Open = openPanel,
})

-- banc d essai
ns._murloc = { st = st, press = press, release = release, step = step, start = start, spawn = spawn,
               obstacles = obstacles, hitbox = hitbox, toggle = toggle }
