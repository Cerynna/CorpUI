--[[--------------------------------------------------------------------------
    CorpUI - module Voyage : le planificateur (trajet le plus rapide)

    Donnees tirees des tables du jeu (Donnees.lua) et relevees en jeu.

    Graphe :
      points : depart, arrivee, points de vol connus de ton camp, quais des
               transports, lieu de la pierre de foyer ;
      marche : entre deux points du meme continent, en ligne droite, a ta
               vitesse de course (monture comprise) ;
      vol    : liaison du jeu entre deux points de vol connus (duree relevee
               en jeu, sinon longueur du trace / vitesse de vol) ;
      bateau : d un quai au suivant de la ligne (attente moyenne : une
               demi-rotation, puis la traversee et l arret au quai) ;
      foyer  : depuis le depart seulement, si la pierre est prete ;
      liaison: tram des profondeurs, portail de Darnassus (duree fixe, dans
               les deux sens).
    Plus court chemin : Dijkstra (une centaine de points).
    Les vols qui se suivent font une seule etape (le maitre de vol enchaine
    les escales tout seul), de meme pour les troncons d une meme ligne de
    bateau.
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local sqrt = math.sqrt

local P = {}
ns.VoyagePlan = P

P.RUN = 7              -- metres par seconde a pied
P.FLY = 32             -- vitesse de vol (estimation, avant les durees relevees)
P.FLY_EXTRA = 8        -- envol et atterrissage
P.BOAT = 30            -- vitesse des bateaux (estimation)
P.HEARTH = 15          -- incantation et chargement

---------------------------------------------------------------------------
-- Donnees (decodees une fois)
---------------------------------------------------------------------------

local data
function P.Data()
    if data then return data end
    data = { nodes = {}, flights = {}, lines = {}, links = {} }
    local src = ns.VoyageData or {}
    for id, raw in pairs(src.nodes or {}) do
        local c, x, y, side, z = raw:match("^(%-?%d+),(%-?[%d%.]+),(%-?[%d%.]+),(%d+),?(%-?[%d%.]*)$")
        if c then data.nodes[id] = { id = id, cont = tonumber(c), x = tonumber(x), y = tonumber(y), z = tonumber(z), side = tonumber(side) } end
    end
    for _, raw in ipairs(src.flights or {}) do
        local a, b, len, cost = raw:match("^(%d+),(%d+),(%d+),(%d+)$")
        if a then
            a, b = tonumber(a), tonumber(b)
            data.flights[a] = data.flights[a] or {}
            data.flights[a][#data.flights[a] + 1] = { to = b, len = tonumber(len), cost = tonumber(cost) }
        end
    end
    for id, raw in pairs(src.transports or {}) do
        local line = { id = id, docks = {} }
        for c, x, y, stop, len, z in raw:gmatch("(%-?%d+):(%-?[%d%.]+):(%-?[%d%.]+):(%d+):(%d+):?(%-?[%d%.]*)") do
            line.docks[#line.docks + 1] = { cont = tonumber(c), x = tonumber(x), y = tonumber(y), z = tonumber(z), stop = tonumber(stop),
                                             len = tonumber(len) }
        end
        local period = 0
        for _, d in ipairs(line.docks) do period = period + d.len / P.BOAT + d.stop end
        line.period = period
        data.lines[#data.lines + 1] = line
    end
    for _, raw in ipairs(src.links or {}) do
        local v = {}
        for x in raw:gmatch("[^,]+") do v[#v + 1] = x end
        if #v == 10 then
            local n = function(i) return tonumber(v[i]) end
            data.links[#data.links + 1] = { kind = v[1], time = n(10),
                a = { cont = n(2), x = n(3), y = n(4), z = n(5) }, b = { cont = n(6), x = n(7), y = n(8), z = n(9) } }
        end
    end
    return data
end

local function dist(a, b)
    if a.cont ~= b.cont then return nil end
    local dx, dy = a.x - b.x, a.y - b.y
    return sqrt(dx * dx + dy * dy)
end
P.Dist = dist

---------------------------------------------------------------------------
-- Plus court chemin
---------------------------------------------------------------------------

-- opts : side (1 Horde, 2 Alliance), known (set de points de vol connus),
-- run (vitesse a pied), fly (vitesse de vol apprise), times (durees
-- relevees : ["a:b"] = s), hearth ({ cont, x, y, wait } : wait = recharge
-- restante), noBoats, noLinks (sans tram ni portail)
-- -> etapes { kind, fc, fx, fy (debut), cont, x, y (fin), time, from, to, via,
-- line, wait, dest }, total ; nil si aucun chemin
function P.Plan(start, dest, opts)
    opts = opts or {}
    local d = P.Data()
    local run = opts.run or P.RUN
    local fly = opts.fly or P.FLY
    local pts = {}
    local function add(p) pts[#pts + 1] = p return #pts end
    local iStart = add({ kind = "start", key = "start", cont = start.cont, x = start.x, y = start.y })
    local iDest = add({ kind = "dest", key = "dest", cont = dest.cont, x = dest.x, y = dest.y })
    local nodeAt = {}
    for id, n in pairs(d.nodes) do
        if (not opts.side or n.side == 3 or n.side == opts.side) and (not opts.known or opts.known[id]) then
            nodeAt[id] = add({ kind = "node", node = id, key = "n" .. id, cont = n.cont, x = n.x, y = n.y })
        end
    end
    local dockAt = {}
    if not opts.noBoats then
        for li, line in ipairs(d.lines) do
            for k, dk in ipairs(line.docks) do
                dockAt[li .. ":" .. k] = add({ kind = "dock", line = li, k = k, key = "d" .. line.id .. "_" .. k, cont = dk.cont, x = dk.x, y = dk.y })
            end
        end
    end
    local gateAt = {}
    for li, lk in ipairs(opts.noLinks and {} or d.links) do
        gateAt[li .. ":1"] = add({ kind = "gate", link = li, side = 1, key = "g" .. li .. "_1", cont = lk.a.cont, x = lk.a.x, y = lk.a.y })
        gateAt[li .. ":2"] = add({ kind = "gate", link = li, side = 2, key = "g" .. li .. "_2", cont = lk.b.cont, x = lk.b.x, y = lk.b.y })
    end
    local iHearth
    if opts.hearth then iHearth = add({ kind = "hearth", key = "hearth", cont = opts.hearth.cont, x = opts.hearth.x, y = opts.hearth.y }) end

    -- aretes sortantes d un point
    local function edges(i)
        local p = pts[i]
        local out = {}
        for j, q in ipairs(pts) do
            if j ~= i and j ~= iStart and q.cont == p.cont then
                -- marche : chemin du terrain (opts.walk : secondes, false = pas de
                -- passage), sinon ligne droite
                local t = opts.walk and opts.walk(p, q)
                if t ~= false then out[#out + 1] = { to = j, time = t or (dist(p, q) / run), kind = "walk" } end
            end
        end
        if p.kind == "node" then
            for _, f in ipairs(d.flights[p.node] or {}) do
                local j = nodeAt[f.to]
                if j then
                    local t = opts.times and opts.times[p.node .. ":" .. f.to] or (f.len / fly + P.FLY_EXTRA)
                    out[#out + 1] = { to = j, time = t, kind = "fly" }
                end
            end
        elseif p.kind == "dock" then
            local line = d.lines[p.line]
            local dk = line.docks[p.k]
            local nk = p.k % #line.docks + 1
            local j = dockAt[p.line .. ":" .. nk]
            -- attente moyenne si on monte ici (une demi-rotation), puis traversee
            if j then out[#out + 1] = { to = j, time = dk.len / P.BOAT + dk.stop, wait = line.period / 2, kind = "boat" } end
        elseif p.kind == "gate" then
            local lk = d.links[p.link]
            local j = gateAt[p.link .. ":" .. (3 - p.side)]
            if j then out[#out + 1] = { to = j, time = lk.time, kind = lk.kind } end
        end
        if i == iStart and iHearth then out[#out + 1] = { to = iHearth, time = P.HEARTH + (opts.hearth.wait or 0), kind = "hearth" } end
        return out
    end

    -- Dijkstra ; "onBoat" : deja monte sur cette ligne (pas de nouvelle attente)
    local best, prev, via, done = { [iStart] = 0 }, {}, {}, {}
    local onBoat = {}
    while true do
        local u, bu
        for i, v in pairs(best) do
            if not done[i] and (not bu or v < bu) then u, bu = i, v end
        end
        if not u or u == iDest then break end
        done[u] = true
        for _, e in ipairs(edges(u)) do
            local t = e.time
            if e.kind == "boat" and onBoat[u] ~= pts[u].line then t = t + e.wait end
            local nt = bu + t
            if not best[e.to] or nt < best[e.to] - 1e-6 then
                best[e.to], prev[e.to], via[e.to] = nt, u, e
                onBoat[e.to] = e.kind == "boat" and pts[u].line or nil
            end
        end
    end
    if not best[iDest] then return nil end

    -- chemin, puis etapes (marches, vols, troncons d une meme ligne de bateau
    -- qui se suivent : une etape)
    local chain = {}
    local i = iDest
    while i ~= iStart do
        table.insert(chain, 1, { at = i, e = via[i], from = prev[i] })
        i = prev[i]
    end
    local steps = {}
    for _, c in ipairs(chain) do
        local p, e = pts[c.at], c.e
        local last = steps[#steps]
        local board = e.kind == "boat" and (not last or last.kind ~= "boat" or last.line ~= p.line)
        local t = e.time + (board and e.wait or 0)
        if e.time < 0.5 and e.kind == "walk" then
            -- deja sur place : rien a faire
        elseif last and last.kind == e.kind and (e.kind ~= "boat" or last.line == p.line) then
            if e.kind == "fly" then
                last.via = last.via or {}
                last.via[#last.via + 1] = last.to
            end
            last.to, last.cont, last.x, last.y, last.dest = p.node, p.cont, p.x, p.y, p.kind == "dest"
            last.time = last.time + t
        else
            local from = pts[c.from]
            steps[#steps + 1] = { kind = e.kind, fc = from.cont, fx = from.x, fy = from.y, cont = p.cont, x = p.x, y = p.y,
                                  time = t, from = from.node, to = p.node, line = p.line, wait = board and e.wait or nil,
                                  dest = p.kind == "dest" }
        end
    end
    return steps, best[iDest]
end
