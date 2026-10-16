--[[--------------------------------------------------------------------------
    CorpUI - module Voyage : positions et releves en jeu

    Positions : "monde" = continent, x (nord), y (ouest), en metres du jeu,
    comme les tables du jeu (Donnees.lua). Conversions par C_Map, dans les
    deux sens.

    Releves (sauvegarde du compte, CorpUIDB.voyage) :
      names  : nom de chaque point de vol, dans ta langue
               (C_TaxiMap.GetTaxiNodesForMap sur chaque continent) ;
      known  : points de vol connus, par personnage : ceux du maitre de
               vol ouvert, et ceux ou on a vole. (Sur ce client, la carte du
               jeu marque tous les points "decouverts", meme ceux jamais
               visites : on ne s y fie pas.) ;
      times  : duree reelle de chaque vol direct pris ("a:b" = secondes),
               et flySpeed, la vitesse de vol qu on en tire ;
      binds  : lieu de la pierre de foyer, par personnage (releve en la
               liant chez l aubergiste, ou en arrivant apres l avoir
               utilisee) ;
      mount  : vitesse sur ta monture, par personnage.
    Tout passe par pcall ; les valeurs secretes sont ecartees.
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local P = ns.VoyagePlan
local issecret = issecretvalue or function() return false end
local sqrt = math.sqrt

local V = {}
ns.Voyage = V

local HEARTHSTONE = 6948          -- objet
local HEARTH_SPELL = 8690         -- sort lance par la pierre

local function num(v) if type(v) == "number" and not issecret(v) then return v end end
local function str(v) if type(v) == "string" and not issecret(v) and v ~= "" then return v end end
local function yes(v) return not issecret(v) and v == true end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end
V.num, V.str, V.yes, V.call = num, str, yes, call

function V.DB() return ns.root and ns.root.voyage end

-- table de ce personnage dans un champ de la sauvegarde
function V.Mine(field)
    local db = V.DB()
    if not db then return {} end
    local k = ns.CharKey()
    db[field] = db[field] or {}
    if type(db[field][k]) ~= "table" then db[field][k] = {} end
    return db[field][k]
end

---------------------------------------------------------------------------
-- Positions
---------------------------------------------------------------------------

local function vecXY(v)
    if type(v) ~= "table" then return nil end
    local x, y = v.x, v.y
    if (x == nil or y == nil) and v.GetXY then
        local ok, a, b = pcall(v.GetXY, v)
        if ok then x, y = a, b end
    end
    x, y = num(x), num(y)
    if x and y then return x, y end
end
V.XY = vecXY

local function vector(x, y)
    if CreateVector2D then
        local v = call(CreateVector2D, x, y)
        if v then return v end
    end
    return { x = x, y = y, GetXY = function(s) return s.x, s.y end }
end

-- point de carte (0-1) -> continent, x, y du monde
function V.World(map, x, y)
    if not (map and x and y and C_Map and C_Map.GetWorldPosFromMapPos) then return nil end
    local cont, pos = call(C_Map.GetWorldPosFromMapPos, map, vector(x, y))
    cont = num(cont)
    local wx, wy = vecXY(pos)
    if cont and wx then return cont, wx, wy end
end

-- monde -> carte (la plus precise, ou celle demandee), x, y (0-1)
function V.MapPos(cont, wx, wy, map)
    if not (cont and wx and C_Map and C_Map.GetMapPosFromWorldPos) then return nil end
    local id, pos = call(C_Map.GetMapPosFromWorldPos, cont, vector(wx, wy), map)
    id = num(id)
    local x, y = vecXY(pos)
    if id and x then return id, x, y end
end

function V.MapName(map)
    local info = map and C_Map and call(C_Map.GetMapInfo, map)
    return type(info) == "table" and str(info.name) or nil
end

-- nom de la zone d un point du monde
function V.ZoneAt(cont, wx, wy)
    local map = V.MapPos(cont, wx, wy)
    return map and V.MapName(map)
end

-- le joueur : carte, x, y (0-1), continent et position monde ; nil en instance
function V.Player()
    if not C_Map then return nil end
    local map = num(call(C_Map.GetBestMapForUnit, "player"))
    if not map then return nil end
    local me = { map = map }
    local x, y = vecXY(call(C_Map.GetPlayerMapPosition, map, "player"))
    if x then
        me.x, me.y = x, y
        me.cont, me.wx, me.wy = V.World(map, x, y)
    end
    return me
end

-- distance entre deux points du monde ({ cont, x, y } ou joueur { cont, wx, wy })
function V.Dist(a, b)
    if not (a and b and a.cont and b.cont and a.cont == b.cont) then return nil end
    local ax, ay = a.wx or a.x, a.wy or a.y
    local bx, by = b.wx or b.x, b.wy or b.y
    if not (ax and bx) then return nil end
    local dx, dy = bx - ax, by - ay
    return sqrt(dx * dx + dy * dy), dx, dy
end

---------------------------------------------------------------------------
-- Cartes des continents (pour lire les points de vol et chercher une quete)
---------------------------------------------------------------------------

local UIMAP = { World = 1, Continent = 2, Zone = 3 }
local function mapType(name)
    return (Enum and Enum.UIMapType and Enum.UIMapType[name]) or UIMAP[name]
end

local continents
function V.Continents()
    if continents and #continents > 0 then return continents end
    continents = {}
    local seen = {}
    local function add(id)
        if id and not seen[id] then
            seen[id] = true
            continents[#continents + 1] = id
        end
    end
    -- du joueur vers le haut : son continent, puis le monde et tous ses continents
    local map = num(call(C_Map and C_Map.GetBestMapForUnit, "player"))
    local guard, top = 0, nil
    while map and guard < 8 do
        local info = call(C_Map.GetMapInfo, map)
        if type(info) ~= "table" then break end
        local t = num(info.mapType)
        if t == mapType("Continent") then add(map) end
        top = map
        local parent = num(info.parentMapID)
        if not parent or parent == 0 then break end
        map = parent
        guard = guard + 1
    end
    for _, root in ipairs(top and { top } or {}) do
        local list = call(C_Map.GetMapChildrenInfo, root, mapType("Continent"), true)
        for _, c in ipairs(type(list) == "table" and list or {}) do add(num(c.mapID)) end
    end
    return continents
end

-- zones d un continent (gardees)
local zonesOf = {}
function V.Zones(cont)
    if zonesOf[cont] then return zonesOf[cont] end
    local out = {}
    local list = C_Map and call(C_Map.GetMapChildrenInfo, cont, mapType("Zone"), true)
    for _, z in ipairs(type(list) == "table" and list or {}) do
        local id = num(z.mapID)
        if id then out[#out + 1] = id end
    end
    zonesOf[cont] = out
    return out
end

---------------------------------------------------------------------------
-- Points de vol : noms et points connus
---------------------------------------------------------------------------

function V.Side()
    local f = call(UnitFactionGroup, "player")
    if str(f) == "Horde" then return 1 end
    return 2
end

function V.NodeName(id)
    local db = V.DB()
    return (id and db and db.names and db.names[id]) or (id and string.format(L.VOY_NODE_ID, id)) or "?"
end

-- carte du jeu de chaque continent : noms des points de vol (dans ta langue)
function V.ReadNodes()
    local db = V.DB()
    if not (db and C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then return 0 end
    db.names = db.names or {}
    local n = 0
    for _, map in ipairs(V.Continents()) do
        local list = call(C_TaxiMap.GetTaxiNodesForMap, map)
        for _, info in ipairs(type(list) == "table" and list or {}) do
            local id = type(info) == "table" and num(info.nodeID)
            local name = id and str(info.name)
            if name then
                if not db.names[id] then n = n + 1 end
                db.names[id] = name
            end
        end
    end
    return n
end

-- maitre de vol ouvert : ses points atteignables sont connus
function V.ReadTaxiMap()
    if not (C_TaxiMap and C_TaxiMap.GetAllTaxiNodes) then return end
    local map = num(call(GetTaxiMapID)) or num(call(C_Map and C_Map.GetBestMapForUnit, "player"))
    if not map then return end
    local db = V.DB()
    local known = V.Mine("known")
    local list = call(C_TaxiMap.GetAllTaxiNodes, map)
    local E = Enum and Enum.FlightPathState
    local unreachable = (E and E.Unreachable) or 2
    for _, info in ipairs(type(list) == "table" and list or {}) do
        local id = type(info) == "table" and num(info.nodeID)
        local state = type(info) == "table" and num(info.state)
        if id and state and state ~= unreachable then
            known[id] = true
            local name = str(info.name)
            if name and db then
                db.names = db.names or {}
                db.names[id] = name
            end
        end
    end
end

-- point de vol (de ton camp) le plus proche d une position, a moins de r metres
function V.NearestNode(me, r)
    if not (me and me.cont) then return nil end
    local d = P.Data()
    local side = V.Side()
    local best, bd
    for id, n in pairs(d.nodes) do
        if n.cont == me.cont and (n.side == 3 or n.side == side) then
            local dd = V.Dist(me, n)
            if dd and dd <= r and (not bd or dd < bd) then best, bd = id, dd end
        end
    end
    return best
end

-- liaison directe a -> b des tables du jeu
function V.Flight(a, b)
    for _, f in ipairs(P.Data().flights[a] or {}) do
        if f.to == b then return f end
    end
end

---------------------------------------------------------------------------
-- Vols chronometres
---------------------------------------------------------------------------

local flying, lastGround
function V.TrackFlight(me, onTaxi)
    local db = V.DB()
    if not db then return end
    if onTaxi then
        if not flying then
            flying = { t = GetTime(), from = V.NearestNode(lastGround, 80) }
        end
        return
    end
    if flying then
        local to = V.NearestNode(me, 150)
        local dur = GetTime() - flying.t
        local f = flying.from and to and to ~= flying.from and V.Flight(flying.from, to)
        if f and dur > 5 then
            db.times = db.times or {}
            db.times[flying.from .. ":" .. to] = math.floor(dur + 0.5)
            -- vitesse de vol (moyenne glissante, bornee)
            local s = f.len / math.max(1, dur - P.FLY_EXTRA)
            if s > 10 and s < 80 then db.flySpeed = db.flySpeed and (db.flySpeed * 0.7 + s * 0.3) or s end
            local known = V.Mine("known")
            known[flying.from], known[to] = true, true
        end
        flying = nil
    end
    if me and me.cont then lastGround = { cont = me.cont, wx = me.wx, wy = me.wy } end
end

---------------------------------------------------------------------------
-- Pierre de foyer
---------------------------------------------------------------------------

local function bindName() return str(call(GetBindLocation)) end

-- liee chez l aubergiste : l aubergiste est a cote
function V.HearthBound()
    local me = V.Player()
    if not (me and me.cont) then return end
    local h = V.Mine("binds")
    h.cont, h.x, h.y, h.name = me.cont, me.wx, me.wy, bindName()
end

-- utilisee : on note le lieu d arrivee, une fois le transport fait
local pendingHearth
function V.HearthCast(me)
    pendingHearth = { t = GetTime(), cont = me and me.cont, wx = me and me.wx, wy = me and me.wy }
end
function V.TrackHearth(me)
    if not pendingHearth then return end
    local age = GetTime() - pendingHearth.t
    if age > 90 then pendingHearth = nil return end
    if age < 2 or not (me and me.cont) then return end
    local d = V.Dist(me, pendingHearth)
    if d and d < 300 then return end         -- pas encore transporte
    local h = V.Mine("binds")
    h.cont, h.x, h.y, h.name = me.cont, me.wx, me.wy, bindName()
    pendingHearth = nil
end
V.HEARTH_SPELL = HEARTH_SPELL

-- lieu de la pierre (si elle est dans les sacs) et recharge restante
function V.Hearth()
    local h = V.Mine("binds")
    if not (h.cont and h.x and h.y) then return nil end
    local name = bindName()
    if name and h.name and name ~= h.name then return nil end    -- liee ailleurs depuis
    local count = num(call(C_Item and C_Item.GetItemCount or GetItemCount, HEARTHSTONE))
    if not count or count < 1 then return nil end
    local start, dur = call(C_Container and C_Container.GetItemCooldown or GetItemCooldown, HEARTHSTONE)
    start, dur = num(start), num(dur)
    local wait = 0
    if start and dur and start > 0 and dur > 1.5 then wait = math.max(0, start + dur - GetTime()) end
    return { cont = h.cont, x = h.x, y = h.y, wait = wait, name = h.name or name }
end

---------------------------------------------------------------------------
-- Vitesse a pied (monture comprise)
---------------------------------------------------------------------------

function V.TrackSpeed()
    if not yes(call(IsMounted)) then return end
    local _, run = call(GetUnitSpeed, "player")
    run = num(run)
    if run and run > P.RUN + 0.5 and run < 30 then
        local db = V.DB()
        if not db then return end
        db.mount = db.mount or {}
        local k = ns.CharKey()
        if not db.mount[k] or run > db.mount[k] then db.mount[k] = run end
    end
end

function V.RunSpeed()
    local db = V.DB()
    local m = db and db.mount and db.mount[ns.CharKey()]
    if m then return m end
    local _, run = call(GetUnitSpeed, "player")
    run = num(run)
    if run and run >= P.RUN then return run end
    return P.RUN
end

---------------------------------------------------------------------------
-- Position d une quete du journal
---------------------------------------------------------------------------

-- point de la quete sur les cartes du jeu (zones de tous les continents),
-- sinon l etape du Leveling, sinon le prochain repere du jeu
function V.QuestDest(id)
    if not id then return nil end
    if C_QuestLog and C_QuestLog.GetQuestsOnMap then
        local me = V.Player()
        local first = me and { me.map } or {}
        for _, c in ipairs(V.Continents()) do
            for _, z in ipairs(V.Zones(c)) do first[#first + 1] = z end
        end
        for _, map in ipairs(first) do
            local list = call(C_QuestLog.GetQuestsOnMap, map)
            for _, p in ipairs(type(list) == "table" and list or {}) do
                if num(p.questID) == id and num(p.x) and num(p.y) then return map, p.x, p.y end
            end
        end
    end
    local LV = ns.Leveling
    local st = LV and LV.Route and LV.Route.State and LV.Route.State()
    for _, t in ipairs(st and st.tasks or {}) do
        if t.id == id and t.map and t.x then return t.map, t.x, t.y end
    end
    if C_QuestLog and C_QuestLog.GetNextWaypoint then
        local map, x, y = call(C_QuestLog.GetNextWaypoint, id)
        map, x, y = num(map), num(x), num(y)
        if map and x and y then return map, x, y end
    end
end

---------------------------------------------------------------------------
-- Diagnostic
---------------------------------------------------------------------------

function V.Diag()
    local db = V.DB() or {}
    local me = V.Player()
    local known, nk = V.Mine("known"), 0
    for _ in pairs(known) do nk = nk + 1 end
    local names = 0
    for _ in pairs(db.names or {}) do names = names + 1 end
    local timed = 0
    for _ in pairs(db.times or {}) do timed = timed + 1 end
    local h = V.Hearth()
    local hs = h and string.format("%s (%.0f, %.0f, %s)", tostring(h.name), h.x, h.y,
        h.wait > 0 and ns.FormatTime(h.wait) or "ok") or L.VOY_HEARTH_UNKNOWN
    ns.Say(string.format(L.VOY_DIAG, tostring(me and me.map), tostring(me and me.cont),
        (me and me.wx) and string.format("%.0f, %.0f", me.wx, me.wy) or "?", nk, names, timed,
        db.flySpeed and string.format("%.1f", db.flySpeed) or "?", string.format("%.1f", V.RunSpeed()), hs))
    ns.Say(string.format("  continents : %s", table.concat(V.Continents(), ", ")))
    -- dernieres etapes du journal du voyage
    local tr = V.Trace and V.Trace() or {}
    for i = math.max(1, #tr - 11), #tr do ns.Say("  " .. tr[i]) end
end
