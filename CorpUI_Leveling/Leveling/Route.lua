--[[--------------------------------------------------------------------------
    CorpUI - module Leveling : la route (guide pas a pas)

    Demande du 16/10 : un guide a suivre pas a pas qui optimise la montee
    de niveau, facon RestedXP. Les etapes de la zone (prendre, faire,
    rendre) sont mises dans l ordre d une tournee :
      - au pole de donneurs, tout prendre (distance nulle entre eux) ;
      - objectifs et rendus dans l ordre du plus proche voisin, puis
        ameliore : chaque etape est deplacee la ou elle raccourcit le plus
        le trajet, dans le respect de l ordre de chaque quete (prendre,
        faire, rendre) et des chaines (rendre la premiere avant de prendre
        la suite, prevue d avance dans la route).
    La route est stable : une etape faite en sort (historique coche), une
    nouvelle s insere la ou elle coute le moins. Elle n est recalculee
    qu au changement de zone (apres 20 s dans la nouvelle) ou a la demande
    (/corp leveling route), et elle est gardee par personnage.

    Positions :
      prendre : le donneur (base AllTheThings) ;
      faire   : le point du jeu une fois la quete prise (GetQuestsOnMap,
                sinon GetNextWaypoint) ; avant : le premier objectif de la
                base, sinon le donneur ;
      rendre  : le point du jeu quand la quete est prete ; avant : le
                donneur de la suite de la chaine (on rend souvent a celui
                qui donne la suite), sinon le donneur.
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local LV = ns.Leveling
local num, str, call, yes = LV.num, LV.str, LV.call, LV.yes
local sqrt = math.sqrt

local R = {}
LV.Route = R

local FAR = 5000          -- autre continent : tres loin
local MAX_QUESTS = 30     -- quetes a prendre gardees dans la route (les plus proches)
local PASSES = 2          -- passes d amelioration
local MOVED = 150         -- etape dont la position change de plus (m) : reinseree
local ZONE_DELAY = 20     -- secondes dans une nouvelle zone avant de recalculer
local HISTORY = 3         -- etapes faites gardees a l affichage
local KIND = { accept = 1, turnin = 2, objective = 3 }
local HUB = 40            -- donneurs a moins de 40 m : un meme pole

local function dist(a, b)
    if not (a and b and a.cont and b.cont) then return 0 end
    if a.cont ~= b.cont then return FAR end
    local dx, dy = a.wx - b.wx, a.wy - b.wy
    return sqrt(dx * dx + dy * dy)
end
R.Dist = dist

local function locate(t)
    t.cont, t.wx, t.wy = nil, nil, nil
    if t.map and t.x and t.y then t.cont, t.wx, t.wy = LV.World(t.map, t.x, t.y) end
end

local function copy(src)
    local t = {}
    for k, v in pairs(src) do t[k] = v end
    return t
end

-- carte de la zone (type "zone", la plus haute de mapsAround)
local function zoneOf(me)
    if not (me and me.map) then return nil end
    local maps = LV.MapsAround(me.map)
    local z = maps[#maps]
    local info = C_Map and call(C_Map.GetMapInfo, z)
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    if type(info) == "table" and num(info.mapType) and info.mapType < zoneType then return nil end
    return z
end
R.ZoneOf = zoneOf

---------------------------------------------------------------------------
-- Etapes de la zone
---------------------------------------------------------------------------

-- toutes les etapes possibles : [cle] = etape, et l etat des quetes
-- opts : offers, gray, ignored (cles "q:<id>")
function R.Gather(me, zone, opts)
    opts = opts or {}
    local ignored = opts.ignored or {}
    local tasks = {}
    local function add(kind, id, base)
        local t = copy(base)
        t.kind, t.id, t.key, t.after = kind, id, kind .. ":" .. id, {}
        tasks[t.key] = t
        return t
    end
    local maps = {}
    if zone then maps[1] = zone end
    for _, m in ipairs(me and LV.MapsAround(me.map) or {}) do
        if m ~= zone then maps[#maps + 1] = m end
    end
    local offerMaps = zone and { zone } or maps

    -- base de la zone : donneurs, suites des chaines
    local byId, succ = {}, {}
    for _, map in ipairs(offerMaps) do
        for _, q in ipairs(LV.Offers(map)) do
            if not byId[q.id] then
                byId[q.id] = { q = q, map = map }
                for _, p in ipairs(q.pre or {}) do
                    succ[p] = succ[p] or {}
                    succ[p][#succ[p] + 1] = q.id
                end
            end
        end
    end
    local function giver(id)
        local e = byId[id]
        if e then return e.map, e.q.x, e.q.y end
    end
    local function turninGuess(id)
        for _, s in ipairs(succ[id] or {}) do
            local m, x, y = giver(s)
            if m then return m, x, y end
        end
        return giver(id)
    end
    local function objGuess(id)
        local e = byId[id]
        local o = e and e.q.obj and e.q.obj[1]
        if o then return o[1], o[2], o[3] end
        return giver(id)
    end

    -- journal
    local ctx = { inLog = {}, ready = {} }
    local log = LV.LogQuests()
    for _, q in ipairs(log) do
        ctx.inLog[q.id] = true
        if q.done then ctx.ready[q.id] = true end
    end
    local pts = LV.QuestPoints(maps)
    local function gamePos(id)
        local p = pts[id]
        if p then return p.map, p.x, p.y end
        if C_QuestLog and C_QuestLog.GetNextWaypoint then
            local m, x, y = call(C_QuestLog.GetNextWaypoint, id)
            m, x, y = num(m), num(x), num(y)
            if m and x and y then return m, x, y, true, str(call(C_QuestLog.GetNextWaypointText, id)) end
        end
    end
    for _, q in ipairs(log) do
        if not ignored["q:" .. q.id] and (opts.gray or not q.trivial or q.done) then
            local base = { title = q.title, level = q.level, trivial = q.trivial, xp = q.xp, inLog = true }
            local m, x, y, via, viaText = gamePos(q.id)
            if not q.done then
                local o = add("objective", q.id, base)
                o.text, o.objType, o.objectives = q.objective, q.objType, q.objectives
                if m then
                    o.map, o.x, o.y, o.via, o.viaText, o.exact = m, x, y, via, viaText, true
                else
                    o.map, o.x, o.y = objGuess(q.id)
                end
                local t = add("turnin", q.id, base)
                t.map, t.x, t.y = turninGuess(q.id)
                t.after = { o.key }
            else
                local t = add("turnin", q.id, base)
                t.ready = true
                if m then
                    t.map, t.x, t.y, t.via, t.viaText, t.exact = m, x, y, via, viaText, true
                else
                    t.map, t.x, t.y = turninGuess(q.id)
                end
            end
        end
    end

    -- quetes a prendre (les plus proches d abord), puis suites des chaines
    if opts.offers ~= false then
        local who = LV.WhoAmI()
        local function offer(q, map, after)
            if ignored["q:" .. q.id] or tasks["accept:" .. q.id] then return false end
            local trivial = yes(call(C_QuestLog and C_QuestLog.IsQuestTrivial, q.id))
                or (q.lvl ~= nil and who.level - q.lvl >= 10)
            if trivial and not opts.gray then return false end
            local base = { trivial = trivial, minLevel = q.lvl, chain = after ~= nil }
            local a = add("accept", q.id, base)
            a.map, a.x, a.y = map, q.x, q.y
            a.after = after or {}
            local o = add("objective", q.id, base)
            o.map, o.x, o.y = objGuess(q.id)
            o.after = { a.key }
            local t = add("turnin", q.id, base)
            t.map, t.x, t.y = turninGuess(q.id)
            t.after = { o.key }
            return true
        end
        local cand = {}
        for _, map in ipairs(offerMaps) do
            for _, q in ipairs(LV.Offers(map)) do
                if LV.CanTake(q, who, ctx.inLog) then
                    local p = { map = map, x = q.x, y = q.y }
                    locate(p)
                    cand[#cand + 1] = { q = q, map = map, d = me and me.cont and dist(me, p) or 0 }
                end
            end
        end
        table.sort(cand, function(a, b)
            if a.d ~= b.d then return a.d < b.d end
            return a.q.id < b.q.id
        end)
        local n = 0
        for _, c in ipairs(cand) do
            if n >= MAX_QUESTS then break end
            if offer(c.q, c.map) then n = n + 1 end
        end
        -- suites : prises apres le rendu de toutes leurs quetes prealables prevues
        local assumed = {}
        for _, t in pairs(tasks) do
            if t.kind == "turnin" then assumed[t.id] = true end
        end
        local wave = {}
        for id in pairs(assumed) do
            for _, s in ipairs(succ[id] or {}) do
                local e = byId[s]
                if e and not tasks["accept:" .. s] and not ctx.inLog[s] and LV.CanTake(e.q, who, ctx.inLog, assumed) then
                    wave[s] = e
                end
            end
        end
        for s, e in pairs(wave) do
            local after = {}
            for _, p in ipairs(e.q.pre or {}) do
                if tasks["turnin:" .. p] then after[#after + 1] = "turnin:" .. p end
            end
            offer(e.q, e.map, after)
        end
    end

    for _, t in pairs(tasks) do locate(t) end
    -- etape sans position (quete du journal hors de la base, sans point du
    -- jeu) : celle de l etape qui la precede dans sa quete, pour la tournee
    for _ = 1, 2 do
        for _, t in pairs(tasks) do
            local p = not t.cont and t.after[1] and tasks[t.after[1]]
            if p and p.cont then t.cont, t.wx, t.wy = p.cont, p.wx, p.wy end
        end
    end
    return tasks, ctx
end

---------------------------------------------------------------------------
-- Tournee
---------------------------------------------------------------------------

-- longueur du trajet (etapes sans position : sans cout)
local function cost(order, start)
    local c, prev = 0, start
    for i = 1, #order do
        local t = order[i]
        if t.cont then
            if prev and prev.cont then c = c + dist(prev, t) end
            prev = t
        end
    end
    return c
end
R.Cost = cost

-- places permises pour t dans order (t retiree) : apres ses prealables,
-- avant les etapes qui en dependent, jamais avant "from"
local function bounds(order, t, deps, from)
    local lo, hi = from or 1, #order + 1
    for idx, u in ipairs(order) do
        for _, k in ipairs(t.after) do
            if u.key == k and idx + 1 > lo then lo = idx + 1 end
        end
        if deps[t.key] and deps[t.key][u.key] and idx < hi then hi = idx end
    end
    return lo, hi
end

local function depsOf(list)
    local deps = {}
    for _, t in ipairs(list) do
        for _, k in ipairs(t.after) do
            deps[k] = deps[k] or {}
            deps[k][t.key] = true
        end
    end
    return deps
end

-- cout d une etape posee entre a et b (b nil : en fin de route)
local function between(a, t, b)
    if not b then return dist(a, t) end
    return dist(a, t) + dist(t, b) - dist(a, b)
end

-- insere t a la place la moins couteuse (a partir de "from")
local function insert(order, t, start, deps, from)
    local lo, hi = bounds(order, t, deps, from)
    if hi < lo then hi = lo end
    local bestJ, bestAdd = hi, nil
    for j = lo, hi do
        local add = between(order[j - 1] or start, t, order[j])
        if not bestAdd or add < bestAdd - 0.5 then bestAdd, bestJ = add, j end
    end
    table.insert(order, bestJ, t)
    return bestJ
end
R.Insert = insert

-- amelioration : chaque etape deplacee la ou elle raccourcit le trajet
-- (calcul par difference : ce que l etape coute a sa place, ce qu elle
-- couterait ailleurs ; n x n par passe)
function R.Improve(order, start)
    local n = #order
    if n < 3 then return end
    local deps = depsOf(order)
    for _ = 1, PASSES do
        local improved = false
        for i = 1, n do
            local t = order[i]
            local here = between(order[i - 1] or start, t, order[i + 1])
            table.remove(order, i)
            local lo, hi = bounds(order, t, deps)
            local bestJ, bestAdd = i, here
            for j = lo, hi do
                local add = between(order[j - 1] or start, t, order[j])
                if add < bestAdd - 0.5 then bestAdd, bestJ = add, j end
            end
            if bestJ ~= i then improved = true end
            table.insert(order, bestJ, t)
        end
        if not improved then break end
    end
end

-- Meme endroit, a la suite (comme RestedXP) : au pole, tout prendre d un
-- coup ; les objectifs proches les uns des autres (quetes differentes au
-- meme endroit, a moins de 150 m : ours, tete du nomme, griffes...) faits ensemble ; les
-- rendus au meme PNJ a la suite. Une etape proche d une autre est ramenee
-- juste apres elle, meme si le trajet n y gagne rien, si ses prealables
-- sont deja passes (ses suites, plus loin, restent apres elle).
local GROUP_R = { accept = HUB, turnin = HUB, objective = 150 }
R.GROUP_R = GROUP_R

-- b (a la place k) peut-il remonter a la place j (< k) ?
local function canMoveTo(order, b, k, j)
    for _, key in ipairs(b.after) do
        for idx = j, k - 1 do
            if order[idx].key == key then return false end
        end
    end
    return true
end

local function batch(order, kind)
    local radius = GROUP_R[kind]
    local i = 1
    while i <= #order do
        local a = order[i]
        if a.kind == kind and a.cont then
            local j, k = i + 1, i + 1
            while k <= #order do
                local b = order[k]
                if b.kind == kind and b.cont and dist(a, b) <= radius and canMoveTo(order, b, k, j) then
                    table.remove(order, k)
                    table.insert(order, j, b)
                    j = j + 1
                end
                k = k + 1
            end
            i = j
        else
            i = i + 1
        end
    end
end
R.Batch = batch

-- route complete depuis "start" : plus proche voisin, amelioration, poles
function R.Build(tasks, start)
    local list = {}
    for _, t in pairs(tasks) do list[#list + 1] = t end
    table.sort(list, function(a, b) return a.key < b.key end)
    local placed, order = {}, {}
    local function ready(t)
        for _, k in ipairs(t.after) do
            if tasks[k] and not placed[k] then return false end
        end
        return true
    end
    local cur = start
    for _ = 1, #list do
        local best, bd
        for _, t in ipairs(list) do
            if not placed[t.key] and ready(t) then
                local d = (t.cont and cur and cur.cont) and dist(cur, t) or 0
                if not best or d < bd - 0.01 or (math.abs(d - bd) <= 0.01 and KIND[t.kind] < KIND[best.kind]) then
                    best, bd = t, d
                end
            end
        end
        if not best then break end
        placed[best.key] = true
        order[#order + 1] = best
        if best.cont then cur = best end
    end
    R.Improve(order, start)
    batch(order, "accept")
    batch(order, "objective")
    batch(order, "turnin")
    return order
end

---------------------------------------------------------------------------
-- Route suivie (par personnage)
---------------------------------------------------------------------------

local state      -- { zone, tasks = { etapes dans l ordre }, done, history, pendingZone, since }
local store      -- sauvegarde du personnage : { zone, keys, done, history }

function R.Attach(saved)
    store = saved
    state = nil
end

function R.State() return state end

local function isDone(t, ctx)
    local completed = LV.Done(t.id)
    if t.kind == "accept" then return ctx.inLog[t.id] or completed end
    if t.kind == "objective" then return (ctx.inLog[t.id] and ctx.ready[t.id]) or completed end
    return completed
end

local function save()
    if not (store and state) then return end
    local keys = {}
    for i, t in ipairs(state.tasks) do keys[i] = t.key end
    store.zone, store.keys, store.done, store.history = state.zone, keys, state.done, state.history
end

local function fresh(tasks, me, zone)
    state = state or { done = 0, history = {} }
    state.zone, state.pendingZone, state.since = zone, nil, nil
    state.tasks = R.Build(tasks, me)
    save()
end

-- ordre garde par la sauvegarde : etapes connues dans cet ordre, les
-- autres inserees
-- profondeur d une etape dans ses prealables (prendre 0, faire 1, rendre 2,
-- suite d une chaine 3...) : les nouvelles etapes s inserent dans cet ordre,
-- sinon un rendu pouvait passer avant son objectif (vu en jeu le 16/10)
local function depthOf(tasks)
    local memo = {}
    local function depth(t, guard)
        if memo[t.key] then return memo[t.key] end
        local d = 0
        if guard < 20 then
            for _, k in ipairs(t.after) do
                local p = tasks[k]
                if p then d = math.max(d, depth(p, guard + 1) + 1) end
            end
        end
        memo[t.key] = d
        return d
    end
    return function(t) return depth(t, 0) end
end

local function insertAll(order, list, tasks, start)
    local depth = depthOf(tasks)
    table.sort(list, function(a, b)
        local da, db = depth(a), depth(b)
        if da ~= db then return da < db end
        return a.key < b.key
    end)
    local deps = depsOf(order)
    for _, t in ipairs(list) do
        for _, k in ipairs(t.after) do
            deps[k] = deps[k] or {}
            deps[k][t.key] = true
        end
    end
    for _, t in ipairs(list) do insert(order, t, start, deps) end
end

-- remet chaque etape apres ses prealables (route abimee, ancienne sauvegarde)
local function repair(order)
    local guard = 0
    local moved = true
    while moved and guard < #order * 3 do
        moved = false
        guard = guard + 1
        local pos = {}
        for i, t in ipairs(order) do pos[t.key] = i end
        for i, t in ipairs(order) do
            local need = 0
            for _, k in ipairs(t.after) do
                if pos[k] and pos[k] > i and pos[k] > need then need = pos[k] end
            end
            if need > 0 then
                -- retiree, son prealable descend en need - 1 : elle se pose juste apres
                table.remove(order, i)
                table.insert(order, need, t)
                moved = true
                break
            end
        end
    end
end
R.Repair = repair

local function restore(tasks, me)
    state = { zone = store.zone, done = store.done or 0, history = store.history or {}, tasks = {} }
    local seen = {}
    for _, key in ipairs(store.keys or {}) do
        local t = tasks[key]
        if t and not seen[key] then
            state.tasks[#state.tasks + 1] = t
            seen[key] = true
        end
    end
    local new = {}
    for key, t in pairs(tasks) do
        if not seen[key] then new[#new + 1] = t end
    end
    insertAll(state.tasks, new, tasks, me)
end

-- force : recalculer toute la route
function R.Update(me, opts, force)
    local zone = zoneOf(me) or (state and state.zone) or (store and store.zone)
    -- changement de zone : apres ZONE_DELAY secondes dans la nouvelle
    local now = GetTime and GetTime() or 0
    if state and zone and state.zone and zone ~= state.zone and not force then
        if state.pendingZone ~= zone then
            state.pendingZone, state.since = zone, now
        elseif now - state.since >= ZONE_DELAY then
            force = true
        end
    elseif state then
        state.pendingZone, state.since = nil, nil
    end
    local planZone = (force and zone) or (state and state.zone) or (store and store.zone) or zone
    local tasks, ctx = R.Gather(me, planZone, opts)
    if force or (not state and not (store and store.keys and store.zone == planZone)) then
        fresh(tasks, me, zone)
        return state, ctx
    end
    if not state then restore(tasks, me) end
    -- etapes faites (historique) ou disparues
    local keep, from = {}, 1
    for _, old in ipairs(state.tasks) do
        local t = tasks[old.key]
        if t then
            -- position nettement changee (quete prise : point du jeu) : reinseree plus bas
            if old.cont and t.cont and dist(old, t) > MOVED then t.moved = true end
            keep[#keep + 1] = t
        elseif isDone(old, ctx) then
            state.done = state.done + 1
            table.insert(state.history, { key = old.key, kind = old.kind, id = old.id, title = old.title,
                                          level = old.level, num = state.done })
            while #state.history > HISTORY do table.remove(state.history, 1) end
        end
    end
    state.tasks = keep
    local deps = depsOf(keep)
    local moved = {}
    for i = #keep, 1, -1 do
        if keep[i].moved then
            moved[#moved + 1] = table.remove(keep, i)
        end
    end
    for _, t in ipairs(moved) do
        t.moved = nil
        insert(keep, t, me, deps, from)
    end
    -- nouvelles etapes : dans l ordre de leurs prealables
    local inOrder = {}
    for _, t in ipairs(keep) do inOrder[t.key] = true end
    local new = {}
    for key, t in pairs(tasks) do
        if not inOrder[key] then new[#new + 1] = t end
    end
    insertAll(keep, new, tasks, me)
    -- toujours dans l ordre des prealables, et le meme endroit a la suite
    repair(keep)
    batch(keep, "accept")
    batch(keep, "objective")
    batch(keep, "turnin")
    save()
    return state, ctx
end

-- etapes restantes, numerotees a la suite des etapes faites
function R.Steps()
    if not state then return {}, {} end
    for i, t in ipairs(state.tasks) do t.num = state.done + i end
    return state.tasks, state.history
end
