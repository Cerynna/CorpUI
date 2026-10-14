--[[--------------------------------------------------------------------------
    CorpUI - module Jeux : le vol du griffon (jeu de competition)

    Pendant un vol de taxi, on pilote sa monture (griffon cote Alliance,
    wyverne cote Horde) : on passe dans les anneaux d or (points ; une serie
    d anneaux multiplie jusqu a x5), on ramasse les pieces, on evite nuages
    d orage, chauves-souris, dragonnets, pics rocheux, rochers flottants et
    zeppelins (choc : points perdus, serie remise a zero, monture sonnee).
      - la partie dure le vol : du decollage a l atterrissage ;
      - le parcours ne depend que du relais de depart et de la semaine : sur
        un meme trajet, tout le monde a exactement le meme ;
      - classement par trajet (relais de depart -> relais d arrivee, par
        leur numero dans le jeu : des clients de langues differentes
        partagent les memes tableaux) ; une saison par semaine (au reset
        hebdomadaire, tableau neuf et parcours neufs) ; le champion de la
        semaine d avant reste affiche ;
      - partage dans la guilde seulement (ns.Comm, canal GUILD) :
          VOLR  nouveau record perso (diffuse a la guilde) ;
          VOLQ  a la connexion : mes empreintes de tableaux, par trajet ;
          VOLB  reponse en chuchotement : les tableaux qui different ;
        chacun fusionne (meilleur score par joueur, 10 par trajet) : les
        records des absents circulent par ceux qui sont en ligne ; un score
        impossible pour la duree du vol est rejete ;
      - trajet : depart lu a l ouverture de la carte des vols
        (C_TaxiMap.GetAllTaxiNodes, etat Current), arrivee = bouton de la
        carte sous la souris quand elle se ferme (TaxiButtonN), sinon le
        relais le plus proche a l atterrissage ; rien de Blizzard n est
        touche (lecture seule) ;
      - hors vol : entrainement de 90 s, non classe.
    Espace / fleche haut / Z / W / clic maintenu : monter ; fleche bas / S :
    piquer ; Echap : fermer (la partie continue, sans pilote).
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L
local C = ns.COLORS

local MEDIA = ns.MEDIA .. "Jeux\\"
local SOUNDS = ns.MEDIA .. "Sons\\"
local issecret = issecretvalue or function() return false end

-- canevas
local W, H = 760, 300
local BG_TILE = H * 2
-- vol
local MOUNT_X, MOUNT_S = 150, 150           -- colonne de la monture, taille de sa case
local SPEED = 320                           -- defilement (px/s)
local THRUST, GRAVITY, DIVE, VMAX = 2100, 1300, 1600, 440
local LOW, HIGH = 30, H - 24                -- bornes du centre de la monture
local HIT_W, HIT_H = 0.15, 0.10             -- demi-boite de choc (fraction de la case)
local COUNTDOWN = 3
local STEP = 1 / 120                        -- pas fixe de la simulation
local RING_OPEN = 38                        -- demi-ouverture d un anneau
local RING_PTS, COIN_PTS, HIT_PTS = 10, 2, 25
local MULT_MAX, MULT_EVERY = 5, 4           -- x2 tous les 4 anneaux de suite, x5 au plus
local STUN, SHIELD = 0.8, 1.8
local MAXRATE = 60                          -- points par seconde au plus (controle)
local TRAIN_TIME = 90
local KEEP = 10                             -- scores gardes par trajet
local LOOKAHEAD = 4
local WEEK = 604800
local WEEK_REF = 1704265200                 -- mercredi 03/01/2024 07:00 UTC (repli)

-- objets (vol_objets.tga, 4 x 2 cases de 256) : case, boite du dessin dans
-- sa case (x, y, l, h), hauteur affichee, vitesse d approche (k : 1 =
-- immobile dans le ciel), marges de la boite de choc (g, d, haut, bas)
local OBJ = {
    ring  = { cell = 1, box = { 44, 6, 168, 244 }, size = 112 },
    coin  = { cell = 2, box = { 8, 6, 241, 244 }, size = 26 },
    cloud = { cell = 3, box = { 6, 43, 244, 170 }, size = 84, inset = { 0.10, 0.10, 0.18, 0.30 } },
    bat   = { cell = 4, box = { 6, 64, 244, 128 }, size = 34, k = 1.25, inset = { 0.25, 0.25, 0.15, 0.25 } },
    spire = { cell = 5, box = { 50, 6, 156, 244 }, inset = { 0.30, 0.30, 0.08, 0 } },
    rock  = { cell = 6, box = { 12, 6, 233, 244 }, size = 96, inset = { 0.12, 0.12, 0.12, 0.30 } },
    zep   = { cell = 7, box = { 6, 33, 244, 191 }, size = 110, k = 1.12, inset = { 0.08, 0.10, 0.06, 0.35 } },
    whelp = { cell = 8, box = { 10, 6, 236, 244 }, size = 62, k = 1.55, inset = { 0.22, 0.22, 0.22, 0.18 } },
}
-- montures : planche 4 x 2 (poses 1-4, plane 5, sonnee 6) ; cycle d ailes
local MOUNTS = {
    Alliance = { file = "vol_griffon", flap = { 1, 2, 3, 2 } },
    Horde = { file = "vol_wyverne", flap = { 1, 5, 3, 5 } },
}
local GLIDE, HURT = 5, 6

local db
local canvas, bg, mountTex, hud, overlay
local MOUNT               -- planche de la monture (faction)
local run                 -- partie en cours
local pool = {}           -- textures d objets libres
local route = {}          -- derniere carte des vols : relais, depart, arrivee
local lastQuery = 0
local Comm

local function str(v) if issecret(v) or type(v) ~= "string" then return nil end return v end
local function num(v) if issecret(v) or type(v) ~= "number" then return nil end return v end

local win
local function play(file)
    -- partie sans pilote (fenetre fermee) : en silence
    if db and db.sound and win and win:IsShown() then pcall(PlaySoundFile, SOUNDS .. file .. ".ogg", "Master") end
end

---------------------------------------------------------------------------
-- Hasard reproductible : meme graine -> meme parcours sur tous les clients
---------------------------------------------------------------------------

local function hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
    return h
end

-- Park-Miller (calcul exact en nombres a virgule)
local function newRng(seed)
    local s = seed % 2147483646 + 1
    return function(a, b)
        s = (s * 16807) % 2147483647
        local u = (s - 1) / 2147483646
        if a then return a + math.floor(u * (b - a + 1)) end
        return u
    end
end

---------------------------------------------------------------------------
-- Saison : la semaine, reperee par le jour du prochain reset hebdomadaire
---------------------------------------------------------------------------

local function seasonInfo()
    local now = (GetServerTime and num(GetServerTime())) or time()
    local left
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
        local ok, v = pcall(C_DateAndTime.GetSecondsUntilWeeklyReset)
        if ok then left = num(v) end
    end
    local nextReset = left and (now + left) or (WEEK_REF + (math.floor((now - WEEK_REF) / WEEK) + 1) * WEEK)
    return math.floor((nextReset + 43200) / 86400), nextReset, now
end

---------------------------------------------------------------------------
-- Parcours : des motifs tires a la suite (anneaux, pieces, obstacles) ;
-- e.te = instant ou l objet passe la colonne de la monture
---------------------------------------------------------------------------

local function clampY(y) return math.max(70, math.min(232, y)) end

local function put(c, kind, te, y, extra)
    local e = { kind = kind, te = te, y = y }
    if extra then for k, v in pairs(extra) do e[k] = v end end
    c.list[#c.list + 1] = e
    return e
end

local PAT = {}
function PAT.ring(c, gap)
    local y = clampY(c.y + c.rnd(-100, 100))
    put(c, "ring", c.t, y)
    c.y = y
    c.t = c.t + 1.5 * gap
end
function PAT.rings(c, gap)
    local dy, y = c.rnd(-50, 50), c.y
    for i = 0, 2 do
        y = clampY(y + dy)
        put(c, "ring", c.t + i * 0.6, y)
    end
    c.y = y
    c.t = c.t + 1.2 + 1.4 * gap
end
function PAT.coins(c, gap)
    local y0 = clampY(c.y + c.rnd(-60, 60))
    local up = c.rnd() < 0.5 and 1 or -1
    for i = 0, 5 do put(c, "coin", c.t + i * 0.16, y0 + up * 34 * math.sin(math.pi * i / 5)) end
    c.y = y0
    c.t = c.t + 0.8 + 1.0 * gap
end
function PAT.spire(c, gap)
    local top = c.rnd(105, 160)
    put(c, "spire", c.t, top)
    put(c, "ring", c.t, top + 70)
    c.y = top + 70
    c.t = c.t + 1.6 * gap
end
function PAT.cloud(c, gap)
    -- l anneau reste du cote ou l on est, le nuage barre l autre moitie
    local high = c.y > H / 2
    local ry = high and c.rnd(200, 232) or c.rnd(70, 100)
    put(c, "ring", c.t, ry)
    put(c, "cloud", c.t + 0.9, high and c.rnd(95, 125) or c.rnd(175, 205))
    put(c, "ring", c.t + 1.8, ry)
    c.y = ry
    c.t = c.t + 1.8 + 1.3 * gap
end
function PAT.rock(c, gap)
    local ry = c.rnd(120, 180)
    put(c, "rock", c.t + 0.5, ry)
    local py = ry < 150 and ry + 85 or ry - 85
    for i = 0, 4 do put(c, "coin", c.t + 0.1 + i * 0.2, py) end
    c.y = py
    c.t = c.t + 1.4 + 1.0 * gap
end
function PAT.bats(c, gap)
    local high = c.rnd() < 0.5
    for i = 0, 2 do
        local by = high and c.rnd(185, 235) or c.rnd(65, 115)
        put(c, "bat", c.t + i * 0.45, by, { amp = 22, freq = 4 + c.rnd(0, 2), ph = c.rnd() * 6.28 })
    end
    local ry = high and c.rnd(75, 100) or c.rnd(200, 228)
    put(c, "ring", c.t + 0.5, ry)
    c.y = ry
    c.t = c.t + 1.4 + 1.2 * gap
end
function PAT.zep(c, gap)
    put(c, "ring", c.t, c.rnd(75, 95))
    put(c, "zep", c.t + 0.8, c.rnd(180, 215))
    put(c, "ring", c.t + 1.6, c.rnd(75, 95))
    c.y = 85
    c.t = c.t + 1.6 + 1.4 * gap
end
function PAT.whelp(c, gap)
    -- un anneau, puis un dragonnet fonce sur la meme ligne : s ecarter
    put(c, "ring", c.t, c.y)
    put(c, "whelp", c.t + 0.75, c.y)
    local ny = c.y > H / 2 and clampY(c.y - c.rnd(100, 140)) or clampY(c.y + c.rnd(100, 140))
    put(c, "ring", c.t + 1.7, ny)
    c.y = ny
    c.t = c.t + 1.7 + 1.3 * gap
end

-- ordre fixe (jamais pairs : l ordre doit etre le meme partout)
local ORDER = { "ring", "rings", "coins", "spire", "cloud", "rock", "bats", "zep", "whelp" }
local function weights(d)
    return {
        ring = 3, rings = 2, coins = 2,
        spire = d > 0.05 and 2 or 0, cloud = d > 0.1 and 2 or 0, rock = d > 0.15 and 1.5 or 0,
        bats = d > 0.3 and 2 or 0, zep = d > 0.4 and 1 or 0, whelp = d > 0.5 and 1.5 or 0,
    }
end

local function genNext(c)
    local d = math.min(1, c.t / 150)
    local w = weights(d)
    local total = 0
    for _, k in ipairs(ORDER) do total = total + w[k] end
    local r, pick = c.rnd() * total, "ring"
    for _, k in ipairs(ORDER) do
        r = r - w[k]
        if r < 0 then pick = k break end
    end
    PAT[pick](c, 1 - 0.35 * d)
end

local function newCourse(seed, list)
    return { rnd = newRng(seed), t = COUNTDOWN + 1.2, y = H / 2, list = list or {} }
end

---------------------------------------------------------------------------
-- Tableaux : db.seasons[saison].routes[trajet] = { o, d, list = { { n, s, d, t } } }
---------------------------------------------------------------------------

-- nom de relais (champ entre ";") ; cle de trajet (sans separateurs)
local function clean(s) return ((s or "?"):gsub("[;|\n\r]", " ")) end
local function cleanKey(s) return ((s or "?"):gsub("[;,=>/|\n\r]", " ")) end

local function nodeName(key)
    local n = db and db.nodes[key]
    if not n then return "?" end
    return n:match("^([^,]+)") or n
end

local function routeKey(o, d) return o .. ">" .. d end

local function routeLabel(o, d)
    return string.format(L.VOL_ROUTE, o and nodeName(o) or "?", d and nodeName(d) or "?")
end

local function sortList(list)
    table.sort(list, function(a, b)
        if a.s ~= b.s then return a.s > b.s end
        if (a.t or 0) ~= (b.t or 0) then return (a.t or 0) < (b.t or 0) end
        return a.n < b.n
    end)
end

local function boardOf(season, rk, create)
    local s = db.seasons[season]
    if not s then
        if not create then return nil end
        s = { routes = {} }
        db.seasons[season] = s
    end
    local b = s.routes[rk]
    if not b and create then
        local o, d = rk:match("^(.-)>(.*)$")
        b = { o = o, d = d, list = {} }
        s.routes[rk] = b
    end
    return b
end

local function valid(score, dur)
    return type(score) == "number" and type(dur) == "number" and score >= 0 and score == math.floor(score)
        and dur >= 5 and dur <= 3600 and score <= dur * MAXRATE + 50
end

-- garde le meilleur score de chaque joueur ; rend true si le tableau change
local function upsert(b, n, s, d, t)
    for _, e in ipairs(b.list) do
        if e.n == n then
            if s <= e.s then return false end
            e.s, e.d, e.t = s, d, t
            sortList(b.list)
            return true
        end
    end
    table.insert(b.list, { n = n, s = s, d = d, t = t })
    sortList(b.list)
    while #b.list > KEEP do table.remove(b.list) end
    for _, e in ipairs(b.list) do if e.n == n then return true end end
    return false
end

local function rankOf(b, n)
    if not b then return nil, 0 end
    for i, e in ipairs(b.list) do if e.n == n then return i, #b.list end end
    return nil, #b.list
end

local function digest(b)
    local parts = {}
    for _, e in ipairs(b.list) do parts[#parts + 1] = e.n .. ":" .. e.s end
    table.sort(parts)
    return hash(table.concat(parts, ","))
end

local function me() return (ns.Names and ns.Names.Me()) or (UnitName("player")) or "?" end
local function display(n) return ns.Names and ns.Names.Display(n) or n end

local function inGuild()
    if not IsInGuild then return false end
    local ok, v = pcall(IsInGuild)
    return ok and not issecret(v) and v and true or false
end

-- garde la saison en cours et la precedente
local function prune(season)
    for k in pairs(db.seasons) do
        if type(k) ~= "number" or (k ~= season and k ~= season - 7) then db.seasons[k] = nil end
    end
    for k in pairs(db.mine) do
        if type(k) ~= "number" or (k ~= season and k ~= season - 7) then db.mine[k] = nil end
    end
end

---------------------------------------------------------------------------
-- Echanges dans la guilde
---------------------------------------------------------------------------

local refreshPanel

local function announce(b, who, score)
    if db.announce and b.list[1] and b.list[1].n == who and who ~= me() then
        ns.Say(string.format(L.VOL_ANNOUNCE, display(who), routeLabel(b.o, b.d), score))
    end
end

local function learnNode(key, name)
    name = str(name)
    if key and name and name ~= "" and name ~= "?" and not db.nodes[key] then db.nodes[key] = clean(name) end
end

local function onRecord(who, payload, channel)
    if channel ~= "GUILD" or not db then return end
    local season, o, d, on, dn, s, dur, t = payload:match("^(%d+);([^;]+);([^;]+);([^;]*);([^;]*);(%d+);(%d+);(%d+)$")
    season, s, dur, t = tonumber(season), tonumber(s), tonumber(dur), tonumber(t)
    local cur = seasonInfo()
    if not season or (season ~= cur and season ~= cur - 7) or not valid(s, dur) then return end
    learnNode(o, on)
    learnNode(d, dn)
    local b = boardOf(season, routeKey(o, d), true)
    if upsert(b, who, s, dur, t) then
        if season == cur then announce(b, who, s) end
        if refreshPanel then refreshPanel() end
    end
end

-- un tableau en une ligne : o;d;nom o;nom d;n,s,d,t/n,s,d,t...
local function packBoard(b)
    local es = {}
    for _, e in ipairs(b.list) do es[#es + 1] = string.format("%s,%d,%d,%d", e.n, e.s, e.d or 0, e.t or 0) end
    return table.concat({ b.o, b.d, clean(db.nodes[b.o]), clean(db.nodes[b.d]), table.concat(es, "/") }, ";")
end

local function onQuery(who, payload, channel)
    if channel ~= "GUILD" or not db or not Comm then return end
    local season, rest = payload:match("^(%d+);(.*)$")
    season = tonumber(season)
    if not season or season ~= seasonInfo() then return end
    local theirs = {}
    for rk, dg in (rest or ""):gmatch("([^=,]+)=(%d+)") do theirs[rk] = tonumber(dg) end
    local s = db.seasons[season]
    if not s then return end
    local lines = { tostring(season) }
    for rk, b in pairs(s.routes) do
        if #b.list > 0 and theirs[rk] ~= digest(b) then lines[#lines + 1] = packBoard(b) end
    end
    if #lines == 1 then return end
    -- reponses etalees : toute la guilde ne repond pas dans la meme seconde
    C_Timer.After(1 + math.random() * 5, function()
        Comm.Send("VOLB", table.concat(lines, "\n"), "WHISPER", who)
    end)
end

local function onBoards(who, payload, channel)
    if channel ~= "WHISPER" or not db or GetTime() - lastQuery > 120 then return end
    local cur = seasonInfo()
    local season
    local changed = false
    for line in payload:gmatch("[^\n]+") do
        if not season then
            season = tonumber(line)
            if season ~= cur then return end
        else
            local o, d, on, dn, list = line:match("^([^;]+);([^;]+);([^;]*);([^;]*);(.*)$")
            if o then
                learnNode(o, on)
                learnNode(d, dn)
                local b = boardOf(season, routeKey(o, d), true)
                for n, s, dur, t in list:gmatch("([^,/]+),(%d+),(%d+),(%d+)") do
                    s, dur, t = tonumber(s), tonumber(dur), tonumber(t)
                    if valid(s, dur) and upsert(b, n, s, dur, t) then changed = true end
                end
            end
        end
    end
    if changed and refreshPanel then refreshPanel() end
end

local function sendQuery()
    if not db or not Comm or not inGuild() then return end
    local season = seasonInfo()
    local parts = {}
    local s = db.seasons[season]
    if s then
        for rk, b in pairs(s.routes) do
            if #b.list > 0 then parts[#parts + 1] = rk .. "=" .. digest(b) end
        end
    end
    lastQuery = GetTime()
    Comm.Send("VOLQ", season .. ";" .. table.concat(parts, ","), "GUILD")
end

-- score de fin de vol : record perso -> tableau + diffusion a la guilde
local function submit(r)
    local season = r.season
    local rk = routeKey(r.origin, r.dest)
    db.mine[season] = db.mine[season] or {}
    local mine = db.mine[season][rk]
    local pb = not mine or r.score > mine.s
    local dur = math.floor(r.dur + 0.5)
    local t = time()
    local b = boardOf(season, rk, true)
    local wasTop = b.list[1] and b.list[1].s or -1
    if pb then
        db.mine[season][rk] = { s = r.score, d = dur, t = t }
        upsert(b, me(), r.score, dur, t)
        if Comm and inGuild() then
            Comm.Send("VOLR", table.concat({ season, r.origin, r.dest, clean(db.nodes[r.origin]), clean(db.nodes[r.dest]),
                r.score, dur, t }, ";"), "GUILD")
        end
    end
    local rank, total = rankOf(b, me())
    return { pb = pb, top = pb and r.score > wasTop, rank = rank, total = total, best = db.mine[season][rk].s }
end

---------------------------------------------------------------------------
-- Carte des vols : relais, depart, arrivee (lecture seule)
---------------------------------------------------------------------------

local function taxiMapID()
    if GetTaxiMapID then
        local ok, v = pcall(GetTaxiMapID)
        if ok and num(v) then return v end
    end
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local ok, m = pcall(C_Map.GetBestMapForUnit, "player")
    m = ok and num(m) or nil
    local CONTINENT = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
    for _ = 1, 8 do
        if not m then return nil end
        local okI, info = pcall(C_Map.GetMapInfo, m)
        if not okI or type(info) ~= "table" then return nil end
        if num(info.mapType) == CONTINENT then return m end
        m = num(info.parentMapID)
        if m == 0 then return nil end
    end
    return nil
end

local function readTaxiMap()
    if not db then return end
    route = { nodes = {}, slots = {}, mapID = taxiMapID() }
    local CURRENT = Enum and Enum.FlightPathState and Enum.FlightPathState.Current or 0
    local list
    if route.mapID and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes then
        local ok, v = pcall(C_TaxiMap.GetAllTaxiNodes, route.mapID)
        if ok and type(v) == "table" then list = v end
    end
    for _, n in ipairs(list or {}) do
        local id = type(n) == "table" and num(n.nodeID)
        if id then
            local key = tostring(id)
            local name = str(n.name)
            local x, y
            if type(n.position) == "table" then x, y = num(n.position.x), num(n.position.y) end
            route.nodes[key] = { x = x, y = y }
            if name then db.nodes[key] = clean(name) end
            local slot = num(n.slotIndex)
            if slot then route.slots[slot] = key end
            if num(n.state) == CURRENT then route.origin = key end
        end
    end
    -- repli : ancienne API, par les noms
    if not route.origin and NumTaxiNodes and TaxiNodeName and TaxiNodeGetType then
        local ok, count = pcall(NumTaxiNodes)
        for i = 1, (ok and num(count) or 0) do
            local okN, name = pcall(TaxiNodeName, i)
            local okT, kind = pcall(TaxiNodeGetType, i)
            name, kind = okN and str(name), okT and str(kind)
            if name then
                local key = "n:" .. cleanKey(name)
                db.nodes[key] = clean(name)
                route.slots[i] = key
                local okP, x, y = pcall(TaxiNodePosition, i)
                route.nodes[key] = { x = okP and num(x) or nil, y = okP and num(y) or nil }
                if kind == "CURRENT" then route.origin = key end
            end
        end
    end
    if route.origin then db.lastOrigin = route.origin end
end

-- bouton de la carte sous la souris (TaxiButtonN -> case N)
local function hoveredSlot()
    local f
    if GetMouseFoci then
        local ok, t = pcall(GetMouseFoci)
        if ok and type(t) == "table" then f = t[1] end
    elseif GetMouseFocus then
        local ok, v = pcall(GetMouseFocus)
        if ok then f = v end
    end
    if type(f) ~= "table" or type(f.GetName) ~= "function" then return nil end
    local ok, name = pcall(f.GetName, f)
    name = ok and str(name) or nil
    local n = name and name:match("^TaxiButton(%d+)$")
    return n and tonumber(n) or nil
end

local function onTaxiClosed()
    local slot = hoveredSlot()
    local key = slot and route.slots and route.slots[slot]
    if key and key ~= route.origin then route.dest = key end
    route.closedAt = GetTime()
end

-- relais le plus proche du joueur (arrivee non vue au depart)
local function nearestNode(r)
    if not r or not r.mapID or not (C_Map and C_Map.GetPlayerMapPosition) then return nil end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, r.mapID, "player")
    if not ok or type(pos) ~= "table" or type(pos.GetXY) ~= "function" then return nil end
    local okXY, px, py = pcall(pos.GetXY, pos)
    px, py = okXY and num(px), okXY and num(py)
    if not px or not py then return nil end
    local best, bestD = nil, 0.05 * 0.05
    for key, n in pairs(r.nodes or {}) do
        if key ~= r.origin and n.x and n.y then
            local dd = (n.x - px) ^ 2 + (n.y - py) ^ 2
            if dd < bestD then best, bestD = key, dd end
        end
    end
    return best
end

---------------------------------------------------------------------------
-- Partie
---------------------------------------------------------------------------

local function mountInfo()
    local ok, f = pcall(UnitFactionGroup, "player")
    f = ok and str(f) or nil
    return MOUNTS[f] or MOUNTS.Alliance, f == "Horde"
end

local function releaseAll()
    if not run then return end
    for _, e in ipairs(run.ents) do
        if e.tex then
            e.tex:Hide()
            pool[#pool + 1] = e.tex
            e.tex = nil
        end
    end
end

local function startRun(mode, origin, dest, r)
    releaseAll()
    local season = seasonInfo()
    local seedOrigin = origin or db.lastOrigin or "?"
    run = {
        mode = mode, origin = origin, dest = dest, r = r, season = season, start = GetTime(), t = 0,
        ents = {}, y = H / 2, vy = 0, score = 0, combo = 0, mult = 1, rings = 0, ringsAll = 0, coins = 0, hits = 0,
        stunUntil = 0, shieldUntil = 0, input = false, dive = false,
    }
    run.course = newCourse(hash(seedOrigin .. "@" .. season), run.ents)
end

local function objSize(e)
    local o = OBJ[e.kind]
    local h = o.size or (e.y + 8)
    return h * o.box[3] / o.box[4], h
end

-- centre de dessin d un objet a l instant t
local function objPos(e, t)
    local o = OBJ[e.kind]
    local x = MOUNT_X + (e.te - t) * SPEED * (o.k or 1)
    local y = e.y
    if e.amp then y = y + e.amp * math.sin(e.freq * (t - e.te) + e.ph) end
    if e.kind == "spire" then
        local _, h = objSize(e)
        y = h / 2
    end
    return x, y
end

local function touches(e, x, y)
    local o = OBJ[e.kind]
    local w, h = objSize(e)
    local i = o.inset or { 0, 0, 0, 0 }
    local l, r = x - w / 2 + i[1] * w, x + w / 2 - i[2] * w
    local top, bot = y + h / 2 - i[3] * h, y - h / 2 + i[4] * h
    local ml, mr = MOUNT_X - HIT_W * MOUNT_S, MOUNT_X + HIT_W * MOUNT_S
    local mt, mb = run.y + HIT_H * MOUNT_S, run.y - HIT_H * MOUNT_S
    return ml < r and mr > l and mb < top and mt > bot
end

local function stepOnce(t)
    local stunned = t < run.stunUntil
    local acc = (run.input and not stunned) and THRUST or -GRAVITY
    if run.dive and not stunned then acc = acc - DIVE end
    run.vy = math.max(-VMAX, math.min(VMAX, run.vy + acc * STEP))
    run.y = run.y + run.vy * STEP
    if run.y < LOW then run.y, run.vy = LOW, math.max(0, run.vy) end
    if run.y > HIGH then run.y, run.vy = HIGH, math.min(0, run.vy) end
    for i = #run.ents, 1, -1 do
        local e = run.ents[i]
        local x, y = objPos(e, t)
        if x < -260 then
            if e.tex then
                e.tex:Hide()
                pool[#pool + 1] = e.tex
            end
            table.remove(run.ents, i)
        elseif not e.done then
            if e.kind == "ring" then
                if t >= e.te then
                    e.done = true
                    run.ringsAll = run.ringsAll + 1
                    if math.abs(run.y - e.y) <= RING_OPEN and not stunned then
                        e.got = true
                        run.rings = run.rings + 1
                        run.combo = run.combo + 1
                        local m = math.min(MULT_MAX, 1 + math.floor(run.combo / MULT_EVERY))
                        if m > run.mult then play("ding") else play("verre") end
                        run.mult = m
                        run.score = run.score + RING_PTS * run.mult
                    else
                        run.combo, run.mult = 0, 1
                    end
                end
            elseif e.kind == "coin" then
                if math.abs(x - MOUNT_X) < 22 and math.abs(run.y - y) < 24 then
                    e.done = true
                    run.coins = run.coins + 1
                    run.score = run.score + COIN_PTS
                end
            elseif t >= run.shieldUntil and math.abs(x - MOUNT_X) < 220 and touches(e, x, y) then
                run.hits = run.hits + 1
                run.score = math.max(0, run.score - HIT_PTS)
                run.combo, run.mult = 0, 1
                run.stunUntil, run.shieldUntil = t + STUN, t + SHIELD
                run.vy = -220
                play("bong")
            end
        end
    end
end

-- avance la partie jusqu a l instant t (pas fixes : meme physique partout)
local function simulate(t)
    if not run or run.over then return end
    if t - run.t > 1 then run.t = t - 1 end
    local c = run.course
    while c.t < t + LOOKAHEAD do genNext(c) end
    while run.t + STEP <= t do
        run.t = run.t + STEP
        if run.t >= COUNTDOWN then stepOnce(run.t) end
    end
end

local function fmtTime(s)
    s = math.max(0, math.floor(s))
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local showResult

local function finish()
    if not run or run.over then return end
    simulate(GetTime() - run.start)
    run.over = true
    run.input, run.dive = false, false
    run.dur = run.t
    local res = {}
    if run.mode == "flight" then
        if not run.dest then run.dest = nearestNode(run.r) end
        if not run.dest then
            res.note = L.VOL_NO_DEST
        elseif run.score > 0 and valid(run.score, math.floor(run.dur + 0.5)) then
            res.sub = submit(run)
        end
    end
    run.res = res
    if res.sub and res.sub.pb then play("carillon") end
    if showResult then showResult() end
    if refreshPanel then refreshPanel() end
end

---------------------------------------------------------------------------
-- Dessin
---------------------------------------------------------------------------

local function cellCoords(k)
    local col, row = (k - 1) % 4, math.floor((k - 1) / 4)
    return col * 0.25, col * 0.25 + 0.25, row * 0.5, row * 0.5 + 0.5
end

local function boxCoords(o)
    local col, row = (o.cell - 1) % 4, math.floor((o.cell - 1) / 4)
    local x0, y0 = col * 256 + o.box[1], row * 256 + o.box[2]
    return x0 / 1024, (x0 + o.box[3]) / 1024, y0 / 512, (y0 + o.box[4]) / 512
end

local function texFor(e)
    local tex = table.remove(pool)
    if not tex then
        tex = canvas:CreateTexture(nil, "ARTWORK", nil, 2)
        tex:SetTexture(MEDIA .. "vol_objets")
    end
    local o = OBJ[e.kind]
    tex:SetTexCoord(boxCoords(o))
    tex:SetDrawLayer("ARTWORK", e.kind == "ring" and 1 or 2)
    tex:SetVertexColor(1, 1, 1, 1)
    local w, h = objSize(e)
    tex:SetSize(w, h)
    return tex
end

local function topOf(rk)
    local b = run and boardOf(run.season, rk)
    return b and b.list[1]
end

local function updateHud()
    if not run then return end
    if run.mode == "train" then
        hud.route:SetText(L.VOL_TRAIN)
        hud.top:SetText(fmtTime(TRAIN_TIME - math.max(0, run.t - COUNTDOWN)))
    elseif run.mode == "free" then
        hud.route:SetText(L.VOL_FREE)
        hud.top:SetText("")
    else
        hud.route:SetText(routeLabel(run.origin, run.dest))
        local top = run.dest and topOf(routeKey(run.origin, run.dest))
        hud.top:SetText(top and string.format(L.VOL_TOP, top.s, display(top.n)) or L.VOL_TOP_NONE)
    end
    hud.score:SetText(run.score)
    hud.mult:SetText(run.mult > 1 and string.format(L.VOL_MULT, run.mult) or "")
    hud.rings:SetText(string.format(L.VOL_RINGS, run.rings, run.ringsAll))
    hud.time:SetText(run.mode ~= "train" and fmtTime(run.t) or "")
end

local function render()
    if not run or not win or not win:IsShown() then return end
    local t = run.over and run.dur or run.t
    local off = (t * SPEED * 0.2 / BG_TILE) % 1
    bg:SetTexCoord(off, off + W / BG_TILE, 0, 1)
    -- monture
    local m = MOUNT
    local frame
    if t < run.stunUntil then
        frame = HURT
    elseif run.input then
        frame = m.flap[math.floor(t * 14) % 4 + 1]
    elseif run.vy < -150 then
        frame = GLIDE
    else
        frame = m.flap[math.floor(t * 7) % 4 + 1]
    end
    mountTex:SetTexCoord(cellCoords(frame))
    mountTex:ClearAllPoints()
    mountTex:SetPoint("CENTER", canvas, "BOTTOMLEFT", MOUNT_X, run.y)
    pcall(mountTex.SetRotation, mountTex, math.max(-0.35, math.min(0.35, run.vy / VMAX * 0.3)))
    -- clignote quand elle est intouchable
    mountTex:SetAlpha((t < run.shieldUntil and t >= run.stunUntil and math.floor(t * 12) % 2 == 0) and 0.45 or 1)
    -- objets
    for _, e in ipairs(run.ents) do
        local x, y = objPos(e, t)
        if x < W + 200 and x > -200 then
            if not e.tex then e.tex = texFor(e) end
            e.tex:ClearAllPoints()
            e.tex:SetPoint("CENTER", canvas, "BOTTOMLEFT", x, y)
            if e.kind == "ring" and e.done then
                if e.got then e.tex:SetVertexColor(1, 1, 0.6, 0.35) else e.tex:SetVertexColor(0.5, 0.5, 0.5, 0.6) end
            end
            e.tex:SetShown(not (e.kind == "coin" and e.done))
        elseif e.tex then
            e.tex:Hide()
        end
    end
    updateHud()
    -- compte a rebours
    if not run.over then
        if run.t < COUNTDOWN then
            overlay.big:SetText(math.ceil(COUNTDOWN - run.t))
            overlay.big:Show()
        elseif run.t < COUNTDOWN + 0.7 then
            overlay.big:SetText(L.VOL_GO)
            overlay.big:Show()
        else
            overlay.big:Hide()
        end
    end
end

function showResult()
    if not win or not run or not run.res then return end
    local r, res = run, run.res
    overlay.big:Hide()
    overlay.title:SetText(r.mode == "train" and L.VOL_TRAIN_DONE or L.VOL_LANDED)
    overlay.line1:SetText(string.format(L.VOL_RESULT, r.score, r.rings, r.ringsAll, r.coins, r.hits))
    local line2 = ""
    if res.note then
        line2 = res.note
    elseif res.sub then
        local s = res.sub
        if s.top then
            line2 = L.VOL_ROUTE_BEST
        elseif s.pb then
            line2 = string.format(L.VOL_PB, s.rank or 0, s.total)
        else
            line2 = string.format(L.VOL_RANKED, s.rank or 0, s.total, s.best)
        end
        if not inGuild() then line2 = line2 .. "  " .. L.VOL_SOLO end
    elseif r.mode == "free" then
        line2 = L.VOL_FREE
    end
    overlay.line2:SetText(line2)
    -- les trois premiers du trajet
    local podium = {}
    local b = r.mode == "flight" and r.dest and boardOf(r.season, routeKey(r.origin, r.dest))
    for i = 1, 3 do
        local e = b and b.list[i]
        if e then podium[#podium + 1] = string.format("%d. %s %d", i, display(e.n), e.s) end
    end
    overlay.line3:SetText(table.concat(podium, "   ·   "))
    overlay.panel:Show()
end

---------------------------------------------------------------------------
-- Fenetre
---------------------------------------------------------------------------

local UP_KEYS = { SPACE = true, UP = true, W = true, Z = true }
local DOWN_KEYS = { DOWN = true, S = true }

local function setKeyboard(on)
    if not win then return end
    pcall(win.EnableKeyboard, win, on and not InCombatLockdown())
end

-- hors vol, rien en cours : entrainement
local function pressStart()
    if run and not run.over then return false end
    if run and run.over and run.mode == "flight" and GetTime() - (run.start + run.dur) < 1.5 then return false end
    startRun("train")
    overlay.panel:Hide()
    return true
end

local function build()
    db.pos = db.pos or { point = "CENTER", x = 0, y = 140 }
    local m, horde = mountInfo()
    MOUNT = m
    win = CreateFrame("Frame", "CorpUIVolGame", UIParent)
    win:SetSize(W + 8, H + 34)
    ns.ApplyPos(win, db.pos)
    win:SetFrameStrata("HIGH")
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    ns.UI.Skin(win, 0.96, true)
    win:SetScale(db.scale or 1)
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
    title:SetText(horde and L.VOL_TITLE_H or L.VOL_TITLE_A)
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
    canvas:SetScript("OnMouseDown", function()
        if run then run.keep = true end
        if pressStart() then return end
        if run and not run.over then run.input = true end
    end)
    canvas:SetScript("OnMouseUp", function() if run then run.input = false end end)
    bg = canvas:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(MEDIA .. "vol_ciel", "REPEAT", "CLAMP")
    bg:SetTexCoord(0, W / BG_TILE, 0, 1)
    mountTex = canvas:CreateTexture(nil, "ARTWORK", nil, 3)
    mountTex:SetSize(MOUNT_S, MOUNT_S)
    mountTex:SetTexture(MEDIA .. m.file)
    mountTex:SetTexCoord(cellCoords(GLIDE))
    mountTex:SetPoint("CENTER", canvas, "BOTTOMLEFT", MOUNT_X, H / 2)
    -- affichage
    hud = CreateFrame("Frame", nil, canvas)
    hud:SetAllPoints()
    hud:SetFrameLevel(canvas:GetFrameLevel() + 5)
    local shade = hud:CreateTexture(nil, "BACKGROUND")
    shade:SetPoint("TOPLEFT")
    shade:SetPoint("TOPRIGHT")
    shade:SetHeight(46)
    ns.UI.Gradient(shade, "VERTICAL", 0, 0, 0, 0, 0, 0, 0, 0.45)
    hud.route = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    hud.route:SetPoint("TOPLEFT", 10, -7)
    hud.top = hud:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hud.top:SetPoint("TOPLEFT", hud.route, "BOTTOMLEFT", 0, -4)
    hud.score = hud:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(hud.score, 20)
    hud.score:SetPoint("TOPRIGHT", -12, -6)
    hud.score:SetTextColor(1, 1, 1)
    hud.mult = hud:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(hud.mult, 16)
    hud.mult:SetPoint("RIGHT", hud.score, "LEFT", -12, 0)
    hud.mult:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    hud.rings = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hud.rings:SetPoint("TOPRIGHT", hud.score, "BOTTOMRIGHT", 0, -3)
    hud.time = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hud.time:SetPoint("BOTTOMLEFT", 8, 6)
    -- compte a rebours, resultat
    overlay = CreateFrame("Frame", nil, canvas)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(canvas:GetFrameLevel() + 6)
    overlay.big = overlay:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(overlay.big, 46)
    overlay.big:SetPoint("CENTER", 0, 10)
    overlay.big:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    overlay.big:Hide()
    overlay.panel = CreateFrame("Frame", nil, overlay)
    overlay.panel:SetSize(520, 120)
    overlay.panel:SetPoint("CENTER", 0, 0)
    local pshade = overlay.panel:CreateTexture(nil, "BACKGROUND")
    pshade:SetAllPoints()
    pshade:SetColorTexture(0, 0, 0, 0.55)
    overlay.title = overlay.panel:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(overlay.title, 24)
    overlay.title:SetPoint("TOP", 0, -10)
    overlay.title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    overlay.line1 = overlay.panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    overlay.line1:SetPoint("TOP", overlay.title, "BOTTOM", 0, -10)
    overlay.line2 = overlay.panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    overlay.line2:SetPoint("TOP", overlay.line1, "BOTTOM", 0, -8)
    overlay.line3 = overlay.panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    overlay.line3:SetPoint("TOP", overlay.line2, "BOTTOM", 0, -8)
    overlay.panel:Hide()
    -- clavier : seulement les touches de vol (et Echap) sont gardees
    win:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        if UP_KEYS[key] then
            self:SetPropagateKeyboardInput(false)
            if run then run.keep = true end
            if not pressStart() and run and not run.over then run.input = true end
        elseif DOWN_KEYS[key] then
            self:SetPropagateKeyboardInput(false)
            if run and not run.over then run.dive = true end
        elseif key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    win:SetScript("OnKeyUp", function(self, key)
        if run then
            if UP_KEYS[key] then run.input = false end
            if DOWN_KEYS[key] then run.dive = false end
        end
        if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
    end)
    win:SetScript("OnShow", function()
        setKeyboard(true)
        if not run then
            overlay.title:SetText(L.VOL_TRAIN)
            overlay.line1:SetText(L.VOL_TRAIN_START)
            overlay.line2:SetText("")
            overlay.line3:SetText("")
            overlay.panel:Show()
        elseif run.over then
            showResult()
        else
            overlay.panel:Hide()
        end
        render()
    end)
    win:SetScript("OnHide", function()
        setKeyboard(false)
        if run then run.input, run.dive = false, false end
    end)
    win:Hide()
end

local function toggle()
    if not db then return end
    if not win then build() end
    win:SetShown(not win:IsShown())
end

-- liste des jeux (ouverture pendant un vol : Jeux.lua)
ns.Games.Register("vol", {
    title = function() return L.MOD_VOL end,
    open = function()
        if not db then return false end
        if not win then build() end
        win:Show()
        return true
    end,
    -- a l atterrissage : le resultat reste affiche un moment
    close = function()
        if not win then return end
        if run and run.over and run.res then
            C_Timer.After(12, function()
                if win and win:IsShown() and run and run.over and not run.keep then win:Hide() end
            end)
        else
            win:Hide()
        end
    end,
    shown = function() return win and win:IsShown() or false end,
})

-- decollage : partie classee si le depart est connu ; atterrissage : fin
ns.Games.OnFlight(function(on)
    if not db then return end
    if on then
        local fresh = route.closedAt and GetTime() - route.closedAt < 20
        if route.origin and fresh then
            startRun("flight", route.origin, route.dest, route)
        else
            startRun("free")
        end
        if overlay then overlay.panel:Hide() end
    else
        if run and not run.over and run.mode ~= "train" then finish() end
        route = {}
    end
end)

---------------------------------------------------------------------------
-- Reglages et tableaux (/corp vol)
---------------------------------------------------------------------------

local panel
local ROWS = 10

local function buildPanel()
    panel = ns.UI.Window("CorpUIVolOptions", ns.TITLE .. " - " .. L.MOD_VOL, nil, 440, 560)
    local icon = panel:CreateTexture(nil, "ARTWORK")
    icon:SetSize(64, 64)
    icon:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -40)
    icon:SetTexture(MEDIA .. "vol_icone")
    local desc = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", panel, "TOPLEFT", 92, -40)
    desc:SetWidth(336)
    desc:SetJustifyH("LEFT")
    desc:SetText(L.VOL_HINT)
    local season = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    season:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -150)
    season:SetWidth(416)
    season:SetJustifyH("LEFT")
    -- choix du trajet
    local sel
    local function routesNow()
        local cur = seasonInfo()
        local list = {}
        local s = db.seasons[cur]
        if s then
            for rk, b in pairs(s.routes) do
                if #b.list > 0 then list[#list + 1] = { value = rk, text = routeLabel(b.o, b.d) } end
            end
        end
        table.sort(list, function(a, b) return a.text < b.text end)
        return list
    end
    sel = ns.UI.Select(panel, 300, routesNow, function() return db.shownRoute end, function(v)
        db.shownRoute = v
        refreshPanel()
    end)
    sel:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -170)
    local rows = {}
    for i = 1, ROWS do
        local l = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        l:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -200 - (i - 1) * 16)
        l:SetWidth(260)
        l:SetJustifyH("LEFT")
        local r = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r:SetPoint("TOPRIGHT", panel, "TOPLEFT", 400, -200 - (i - 1) * 16)
        r:SetJustifyH("RIGHT")
        rows[i] = { l = l, r = r }
    end
    local foot = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    foot:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -200 - ROWS * 16 - 6)
    foot:SetWidth(410)
    foot:SetJustifyH("LEFT")
    local trainBtn = ns.UI.Button(panel, L.VOL_TRAIN, 140, function()
        if not win then build() end
        win:Show()
        pressStart()
    end)
    trainBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -200 - ROWS * 16 - 44)
    local form = ns.UI.Form(panel, -200 - ROWS * 16 - 76, function()
        if win then win:SetScale(db.scale or 1) end
    end)
    form:Check(L.MURLOC_OPT_SOUND, function() return db.sound end, function(v) db.sound = v end)
    form:Check(L.VOL_OPT_ANNOUNCE, function() return db.announce end, function(v) db.announce = v end)
    form:Number(L.MURLOC_OPT_SCALE, function() return math.floor((db.scale or 1) * 100 + 0.5) end,
        function(v) db.scale = v / 100 end, 60, 150, 5)
    ns.Games.TaxiOptions(form)

    function refreshPanel()
        if not panel or not panel:IsShown() then return end
        local cur, nextReset, now = seasonInfo()
        local left = math.max(0, nextReset - now)
        season:SetText(string.format(L.VOL_SEASON, date("%d/%m", nextReset),
            string.format(L.VOL_LEFT, math.floor(left / 86400), math.floor(left % 86400 / 3600))))
        local list = routesNow()
        local found = false
        for _, o in ipairs(list) do if o.value == db.shownRoute then found = true end end
        if not found then db.shownRoute = list[1] and list[1].value or nil end
        sel:Refresh()
        sel:SetShown(#list > 0)
        local b = db.shownRoute and boardOf(cur, db.shownRoute)
        local mine = me()
        for i = 1, ROWS do
            local e = b and b.list[i]
            local row = rows[i]
            if e then
                row.l:SetText(string.format("%d.  %s", i, display(e.n)))
                row.r:SetText(string.format("%d   (%s)", e.s, fmtTime(e.d or 0)))
                local c = e.n == mine and C.gold or { 1, 1, 1 }
                row.l:SetTextColor(c[1], c[2], c[3])
                row.r:SetTextColor(c[1], c[2], c[3])
            else
                row.l:SetText(i == 1 and #list == 0 and L.VOL_NO_ROUTES or "")
                row.r:SetText("")
            end
        end
        local lines = {}
        if db.shownRoute then
            local prev = boardOf(cur - 7, db.shownRoute)
            if prev and prev.list[1] then
                lines[#lines + 1] = string.format(L.VOL_LAST_CHAMP, display(prev.list[1].n), prev.list[1].s)
            end
            local my = db.mine[cur] and db.mine[cur][db.shownRoute]
            if my then lines[#lines + 1] = string.format(L.VOL_MINE, my.s) end
        end
        foot:SetText(table.concat(lines, "\n"))
        form:Refresh()
    end
    panel:HookScript("OnShow", function() refreshPanel() end)
end

local function openPanel()
    if not db then return end
    if not panel then buildPanel() end
    ns.ShowPanel(panel)
    refreshPanel()
end

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:SetScript("OnUpdate", function()
    if not run or run.over then
        return
    end
    simulate(GetTime() - run.start)
    if run.mode == "train" and run.t >= COUNTDOWN + TRAIN_TIME then finish() end
    render()
end)
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        if type(root.games) ~= "table" then root.games = {} end
        if type(root.games.vol) ~= "table" then root.games.vol = {} end
        db = root.games.vol
        if db.sound == nil then db.sound = true end
        if db.announce == nil then db.announce = true end
        if type(db.scale) ~= "number" then db.scale = 1 end
        if type(db.nodes) ~= "table" then db.nodes = {} end
        if type(db.seasons) ~= "table" then db.seasons = {} end
        if type(db.mine) ~= "table" then db.mine = {} end
        prune(seasonInfo())
        Comm = ns.Comm
        if Comm then
            Comm.On("VOLR", onRecord)
            Comm.On("VOLQ", onQuery)
            Comm.On("VOLB", onBoards)
        end
        C_Timer.After(20, sendQuery)
    elseif event == "TAXIMAP_OPENED" then
        readTaxiMap()
    elseif event == "TAXIMAP_CLOSED" then
        onTaxiClosed()
    elseif event == "PLAYER_REGEN_DISABLED" then
        if win and win:IsShown() then
            pcall(win.EnableKeyboard, win, false)
            if run then run.input, run.dive = false, false end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if win and win:IsShown() then setKeyboard(true) end
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "TAXIMAP_OPENED", "TAXIMAP_CLOSED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
    pcall(ev.RegisterEvent, ev, e)
end

ns.RegisterModule({
    command = "vol",
    alias = "griffon",
    panelName = "CorpUIVolOptions",
    icon = MEDIA .. "vol_icone",
    title = function() return L.MOD_VOL end,
    desc = function() return L.VOL_DESC end,
    Slash = function(rest)
        rest = strlower(strtrim(rest or ""))
        if rest == "options" or rest == "config" or rest == "classement" then openPanel() else toggle() end
    end,
    Open = openPanel,
})

-- banc d essai
ns._vol = {
    hash = hash, newRng = newRng, newCourse = newCourse, genNext = genNext, seasonInfo = seasonInfo,
    startRun = startRun, simulate = simulate, finish = finish, submit = submit, upsert = upsert, digest = digest,
    valid = valid, onRecord = onRecord, onQuery = onQuery, onBoards = onBoards, sendQuery = sendQuery,
    readTaxiMap = readTaxiMap, onTaxiClosed = onTaxiClosed, nearestNode = nearestNode, boardOf = boardOf,
    toggle = toggle, openPanel = openPanel, OBJ = OBJ,
    state = function() return run, route, db, win, overlay, hud end,
}
