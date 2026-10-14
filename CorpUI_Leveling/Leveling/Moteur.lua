--[[--------------------------------------------------------------------------
    CorpUI - module Leveling : le moteur (choix de l etape suivante)

    Idee reprise de factoruide (github.com/brouznouf/factoruide, MIT) et de
    RestedXP : dire au joueur quoi faire ensuite pour monter de niveau.
    Ecrit pour CorpUI, sans leur code ni leurs donnees : ici, pas de route
    calculee d avance, le module part de ce que le client Forever sait
    deja (journal de quetes, positions des objectifs et des PNJ de rendu,
    quetes disponibles affichees sur la carte) et choisit de proche en
    proche.

    Une "etape" (action) : { key, kind, id, title, text, map, x, y, via,
    level, trivial, xp, objType, dist, score }
      kind = "turnin" (rendre), "objective" (faire), "accept" (prendre)
      via  = position donnee par le repere de Blizzard (autre carte : sortie
             de zone, maitre de vol...) et son texte
    Choix : la plus proche, avec des poids (rendre et prendre comptent moins
    que faire, une quete trop haute ou grise compte plus) ; l etape en cours
    reste en tete tant qu une autre n est pas nettement meilleure, pour que
    la fleche ne saute pas d un objectif a l autre en marchant.

    Lecture seule : aucune fonction de Blizzard modifiee, tout passe par
    pcall et les valeurs secretes sont ecartees.
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)

local LV = {}
ns.Leveling = LV

local issecret = issecretvalue or function() return false end
local sqrt, floor = math.sqrt, math.floor

local function num(v) if type(v) == "number" and not issecret(v) then return v end end
local function str(v) if type(v) == "string" and not issecret(v) and v ~= "" then return v end end
local function yes(v) return not issecret(v) and v == true end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end
LV.num, LV.str, LV.call = num, str, call

-- poids du choix (distances en metres du jeu)
LV.W = {
    turnin = 0.6,        -- rendre : rapide, et ca libere le journal
    accept = 0.85,       -- prendre : un detour court
    via = 500,           -- etape sur une autre carte
    unknown = 3000,      -- sans position
    trivialTurnin = 150, -- quete grise a rendre : peu d XP, mais elle part du journal
    trivial = 800,       -- quete grise a faire ou a prendre
    perLevel = 250,      -- par niveau au-dela de +2 (orange, rouge)
    keep = 0.8,          -- l etape en cours reste tant qu aucune n est 20 % meilleure
}

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

local function vector(x, y)
    if CreateVector2D then
        local v = call(CreateVector2D, x, y)
        if v then return v end
    end
    return { x = x, y = y, GetXY = function(s) return s.x, s.y end }
end

-- position "monde" (continent, nord, ouest) d un point de carte
local function worldRaw(map, x, y)
    if not (map and x and y and C_Map and C_Map.GetWorldPosFromMapPos) then return nil end
    local cont, pos = call(C_Map.GetWorldPosFromMapPos, map, vector(x, y))
    cont = num(cont)
    local wx, wy = vecXY(pos)
    if cont and wx then return cont, wx, wy end
end

-- les points des etapes ne bougent pas : gardes (vides de temps en temps)
local cache, cacheN = {}, 0
function LV.World(map, x, y)
    if not (map and x and y) then return nil end
    local key = map .. ":" .. floor(x * 10000) .. ":" .. floor(y * 10000)
    local c = cache[key]
    if c then return c[1], c[2], c[3] end
    local cont, wx, wy = worldRaw(map, x, y)
    if not cont then return nil end
    if cacheN > 400 then cache, cacheN = {}, 0 end
    cache[key] = { cont, wx, wy }
    cacheN = cacheN + 1
    return cont, wx, wy
end

-- le joueur : carte, x, y (0-1) et position monde ; nil en instance
function LV.Player()
    if not C_Map then return nil end
    local map = num(call(C_Map.GetBestMapForUnit, "player"))
    if not map then return nil end
    local me = { map = map }
    local x, y = vecXY(call(C_Map.GetPlayerMapPosition, map, "player"))
    if x then
        me.x, me.y = x, y
        me.cont, me.wx, me.wy = worldRaw(map, x, y)
    end
    return me
end

-- distance (metres du jeu) entre le joueur et une etape ; nil : autre continent ou inconnue
function LV.Distance(me, a)
    if not (me and me.cont and a and a.map) then return nil end
    local cont, wx, wy = LV.World(a.map, a.x, a.y)
    if not cont or cont ~= me.cont then return nil end
    local dx, dy = wx - me.wx, wy - me.wy
    return sqrt(dx * dx + dy * dy), dx, dy
end

-- cartes a interroger : celle du joueur, et sa zone si on est dans une
-- sous-carte (grotte, ville, micro-zone)
local function mapsAround(map)
    local list = { map }
    local info = C_Map and call(C_Map.GetMapInfo, map)
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    local guard = 0
    while type(info) == "table" and num(info.mapType) and info.mapType > zoneType and guard < 3 do
        local parent = num(info.parentMapID)
        if not parent or parent == 0 then break end
        list[#list + 1] = parent
        info = call(C_Map.GetMapInfo, parent)
        guard = guard + 1
    end
    return list
end
LV.MapsAround = mapsAround

---------------------------------------------------------------------------
-- Ce que le jeu donne
---------------------------------------------------------------------------

-- quetes du journal : { id, title, level, done, trivial, xp, objective, objType }
local function logQuests()
    local Q = C_QuestLog
    local out = {}
    if not Q then return out end
    local n = num(call(Q.GetNumQuestLogEntries)) or 0
    for i = 1, n do
        local info = call(Q.GetInfo, i)
        if type(info) == "table" and not yes(info.isHeader) and not yes(info.isHidden) then
            local id = num(info.questID)
            if id and id > 0 and not yes(call(Q.IsFailed, id)) then
                local q = { id = id, title = str(info.title) or str(call(Q.GetTitleForQuestID, id)) or "?",
                            level = num(info.level) }
                q.done = yes(call(Q.ReadyForTurnIn, id)) or yes(call(Q.IsComplete, id))
                q.trivial = yes(call(Q.IsQuestTrivial, id))
                q.xp = num(call(GetQuestLogRewardXP, id))
                if not q.done then
                    local objs = call(Q.GetQuestObjectives, id)
                    for _, o in ipairs(type(objs) == "table" and objs or {}) do
                        if type(o) == "table" and not yes(o.finished) then
                            q.objective, q.objType = str(o.text), str(o.type)
                            break
                        end
                    end
                end
                out[#out + 1] = q
            end
        end
    end
    return out
end
LV.LogQuests = logQuests

-- points des quetes du journal sur ces cartes : [questID] = { map, x, y }
local function questPoints(maps)
    local out = {}
    if not (C_QuestLog and C_QuestLog.GetQuestsOnMap) then return out end
    for _, map in ipairs(maps) do
        local list = call(C_QuestLog.GetQuestsOnMap, map)
        for _, p in ipairs(type(list) == "table" and list or {}) do
            local id, x, y = num(p.questID), num(p.x), num(p.y)
            if id and x and y and not out[id] then out[id] = { map = map, x = x, y = y } end
        end
    end
    return out
end

-- quetes a prendre affichees sur la carte (lignes de quetes du jeu)
local asked = {}
function LV.ResetOffers() asked = {} end
local function offers(maps, inLog)
    local out = {}
    local QL = C_QuestLine
    if not (QL and QL.GetAvailableQuestLines) then return out end
    local seen = {}
    local now = GetTime and GetTime() or 0
    for _, map in ipairs(maps) do
        -- le jeu charge ces lignes a la demande : redemande de temps en temps
        if not asked[map] or now - asked[map] > 30 then
            asked[map] = now
            call(QL.RequestQuestLinesForMap, map)
        end
        local function add(q)
            if type(q) ~= "table" then return end
            local id, x, y = num(q.questID), num(q.x), num(q.y)
            if not (id and x and y) or inLog[id] or seen[id] then return end
            if yes(call(C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted, id)) then return end
            seen[id] = true
            out[#out + 1] = { id = id, title = str(q.questName), map = map, x = x, y = y,
                              trivial = yes(q.isHidden) or yes(call(C_QuestLog and C_QuestLog.IsQuestTrivial, id)) }
        end
        local list = call(QL.GetAvailableQuestLines, map)
        for _, q in ipairs(type(list) == "table" and list or {}) do add(q) end
        local forced = QL.GetForceVisibleQuests and call(QL.GetForceVisibleQuests, map)
        for _, id in ipairs(type(forced) == "table" and forced or {}) do
            if num(id) then add(call(QL.GetQuestLineInfo, id, map)) end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Etapes, poids, choix
---------------------------------------------------------------------------

function LV.Score(a, level)
    local W = LV.W
    local s = a.dist or W.unknown
    if a.kind == "turnin" then s = s * W.turnin
    elseif a.kind == "accept" then s = s * W.accept end
    if a.via then s = s + W.via end
    if a.trivial then s = s + (a.kind == "turnin" and W.trivialTurnin or W.trivial) end
    if a.level and level then
        local diff = a.level - level
        if diff > 2 then s = s + W.perLevel * (diff - 2) end
    end
    return s
end

-- toutes les etapes possibles, avec leur distance
-- opts : offers (quetes a prendre), gray (quetes grises aussi)
function LV.Collect(me, opts)
    opts = opts or {}
    local acts, inLog = {}, {}
    local maps = me and mapsAround(me.map) or {}
    local points = questPoints(maps)
    local stats = { log = 0, onMap = 0, via = 0, offers = 0 }
    for _, q in ipairs(logQuests()) do
        inLog[q.id] = true
        stats.log = stats.log + 1
        local a = { id = q.id, title = q.title, level = q.level, trivial = q.trivial, xp = q.xp,
                    kind = q.done and "turnin" or "objective", text = q.objective, objType = q.objType }
        local p = points[q.id]
        if p then
            a.map, a.x, a.y = p.map, p.x, p.y
            stats.onMap = stats.onMap + 1
        elseif C_QuestLog and C_QuestLog.GetNextWaypoint then
            local m, x, y = call(C_QuestLog.GetNextWaypoint, q.id)
            m, x, y = num(m), num(x), num(y)
            if m and x and y then
                a.map, a.x, a.y, a.via = m, x, y, true
                a.viaText = str(call(C_QuestLog.GetNextWaypointText, q.id))
                stats.via = stats.via + 1
            end
        end
        a.key = a.kind .. ":" .. q.id
        if opts.gray or not a.trivial or a.kind == "turnin" then acts[#acts + 1] = a end
    end
    if opts.offers then
        for _, o in ipairs(offers(maps, inLog)) do
            stats.offers = stats.offers + 1
            if opts.gray or not o.trivial then
                o.kind, o.key = "accept", "accept:" .. o.id
                acts[#acts + 1] = o
            end
        end
    end
    for _, a in ipairs(acts) do
        if a.map then a.dist = LV.Distance(me, a) end
    end
    return acts, stats
end

-- etapes triees : la premiere est celle a faire
-- opts : offers, gray, ignored (set de cles), current (cle de l etape en cours)
function LV.Plan(opts)
    opts = opts or {}
    local me = LV.Player()
    local acts, stats = LV.Collect(me, opts)
    local level = num(call(UnitLevel, "player"))
    local list = {}
    for _, a in ipairs(acts) do
        if not (opts.ignored and opts.ignored[a.key]) then
            a.score = LV.Score(a, level)
            list[#list + 1] = a
        end
    end
    table.sort(list, function(p, q)
        if p.score ~= q.score then return p.score < q.score end
        return p.key < q.key
    end)
    -- l etape en cours garde la tete si elle reste presque aussi bonne
    if opts.current and list[1] and list[1].key ~= opts.current then
        for i = 2, #list do
            local a = list[i]
            if a.key == opts.current then
                if list[1].score >= a.score * LV.W.keep then
                    table.remove(list, i)
                    table.insert(list, 1, a)
                end
                break
            end
        end
    end
    return list, me, stats
end
