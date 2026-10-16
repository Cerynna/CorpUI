--[[--------------------------------------------------------------------------
    CorpUI - module Voyage : la marche (chemins du terrain)

    Donnees : Chemins.lua (genere depuis le terrain et les batiments du
    client, .github/scripts/terrain) : par continent, des "pieces" (zones
    praticables d un bloc de terrain, reliees entre elles) et les distances
    a pied deja calculees entre points de vol, quais et entrees du tram ou
    du portail.

    Ici :
      M.Graph(cont)        : decode les donnees d un continent (une fois) ;
      M.Snap(g, n, w)      : piece la plus proche d un point ;
      M.Dijkstra(...)      : distances depuis une piece (ou vers elle, en sens
                             inverse) jusqu a un ensemble de pieces cibles ;
      M.Path(g, a, b)      : plus court chemin (A*) -> points de passage.
    Les calculs longs rendent la main (coroutine) quand leur budget de temps
    par image est depense : le jeu ne fige pas.

    Cout d un lien : distance (le haut compte pour moitie), x 1,5 a la nage.
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)

local M = {}
ns.VoyageWalk = M

local B64 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz+/"
local VAL = {}
for i = 1, 64 do VAL[B64:byte(i)] = i - 1 end
local MID = 32 * 1600 / 3
local SWIM = 1.5
local SNAP_MAX = 200          -- metres : au-dela, pas de piece (on marche en ligne droite)
local sqrt, floor, byte = math.sqrt, math.floor, string.byte
local clock = debugprofilestop or function() return os.clock() * 1000 end

M.budget = 6                  -- ms de calcul par image (coroutine)
M.deadline = nil              -- fixe par celui qui fait tourner la coroutine
M.clock = clock

-- rend la main quand le budget de l image est depense (hors coroutine : jamais)
local function tick()
    if not (M.deadline and clock() > M.deadline) then return end
    local co, main = coroutine.running()
    if co and not main then coroutine.yield() end
end

---------------------------------------------------------------------------
-- Donnees
---------------------------------------------------------------------------

local graphs = {}

function M.Has(cont) return ns.VoyageWalkData and ns.VoyageWalkData[cont] ~= nil end

local function num(s, at, n)
    local v = 0
    for k = 0, n - 1 do v = v * 64 + VAL[byte(s, at + k)] end
    return v
end

function M.Graph(cont)
    if graphs[cont] ~= nil then return graphs[cont] or nil end
    local src = ns.VoyageWalkData and ns.VoyageWalkData[cont]
    if not src then
        graphs[cont] = false
        return nil
    end
    local B = src.block
    local g = { cont = cont, block = B, count = src.count, N = {}, W = {}, Z = {}, F = {},
                first = {}, to = {}, blocks = {}, pois = src.pois or {}, pdRaw = src.pd }
    local s, e = src.nodes, src.edges
    local deg = {}
    local p = 1
    for i = 1, src.count do
        local n, w = num(s, p, 3) - 131072, num(s, p + 3, 3) - 131072
        g.N[i], g.W[i], g.Z[i] = n, w, num(s, p + 6, 2) - 2048
        g.F[i] = VAL[byte(s, p + 8)]
        deg[i] = VAL[byte(s, p + 9)]
        p = p + 10
        local key = floor((MID - n) / B) * 1024 + floor((MID - w) / B)
        if not g.blocks[key] then g.blocks[key] = i end
        if i % 2000 == 0 then tick() end
    end
    local q, t = 1, 1
    for i = 1, src.count do
        g.first[i] = t
        local bx, by = floor((MID - g.W[i]) / B), floor((MID - g.N[i]) / B)
        for _ = 1, deg[i] do
            local dir, rk = VAL[byte(e, q)], VAL[byte(e, q + 1)]
            q = q + 2
            local dy, dx = floor(dir / 3) - 1, dir % 3 - 1
            local base = g.blocks[(by + dy) * 1024 + bx + dx]
            if base then
                g.to[t] = base + rk
                t = t + 1
            end
        end
        if i % 2000 == 0 then tick() end
    end
    g.first[src.count + 1] = t
    graphs[cont] = g
    return g
end

-- liens entrants (pour les distances "vers" une piece), construits a la demande
local function reverse(g)
    if g.rfirst then return end
    local cnt = {}
    for i = 1, g.count do cnt[i] = 0 end
    for i = 1, g.count do
        for k = g.first[i], g.first[i + 1] - 1 do
            local j = g.to[k]
            cnt[j] = cnt[j] + 1
        end
    end
    local rfirst, fill = {}, {}
    local t = 1
    for i = 1, g.count do
        rfirst[i], fill[i] = t, t
        t = t + cnt[i]
    end
    rfirst[g.count + 1] = t
    local rto = {}
    for i = 1, g.count do
        for k = g.first[i], g.first[i + 1] - 1 do
            local j = g.to[k]
            rto[fill[j]] = i
            fill[j] = fill[j] + 1
        end
        if i % 4000 == 0 then tick() end
    end
    g.rfirst, g.rto = rfirst, rto
end

-- distances deja calculees entre points (cle "n2:d11616_1") -> metres
function M.PoiDist(g, a, b)
    if not g.pd then
        g.pd = {}
        for ka, kb, d in (g.pdRaw or ""):gmatch("([^:;]+):([^:;]+):(%d+)") do g.pd[ka .. ":" .. kb] = tonumber(d) end
    end
    return g.pd[a .. ":" .. b]
end

local function cost(g, a, b)
    local dn, dw, dz = g.N[a] - g.N[b], g.W[a] - g.W[b], (g.Z[a] - g.Z[b]) * 0.5
    local d = sqrt(dn * dn + dw * dw + dz * dz)
    if (g.F[a] % 2 == 1) or (g.F[b] % 2 == 1) then d = d * SWIM end
    return d
end
M.Cost = cost

---------------------------------------------------------------------------
-- Piece la plus proche
---------------------------------------------------------------------------

-- z facultatif ; renvoie piece, distance (nil au-dela de SNAP_MAX)
function M.Snap(g, n, w, z)
    if not (g and n and w) then return nil end
    local B = g.block
    local bx, by = floor((MID - w) / B), floor((MID - n) / B)
    local best, bd, bdist
    for ring = 0, 3 do
        for dy = -ring, ring do
            for dx = -ring, ring do
                if math.max(math.abs(dx), math.abs(dy)) == ring then
                    local key = (by + dy) * 1024 + bx + dx
                    local i = g.blocks[key]
                    local stop = (by + dy) * 1024 + bx + dx
                    while i and i <= g.count and floor((MID - g.N[i]) / B) * 1024 + floor((MID - g.W[i]) / B) == stop do
                        local dn, dw = g.N[i] - n, g.W[i] - w
                        local d = sqrt(dn * dn + dw * dw)
                        local score = d + (z and math.abs(g.Z[i] - z) * 2 or 0)
                        if not bd or score < bd then best, bd, bdist = i, score, d end
                        i = i + 1
                    end
                end
            end
        end
        if best and bdist < ring * B then break end
    end
    if best and bdist <= SNAP_MAX then return best, bdist end
end

---------------------------------------------------------------------------
-- Plus courts chemins
---------------------------------------------------------------------------

-- tas binaire minimal : cles (distances) et valeurs (pieces)
local function heap()
    local hk, hv, n = {}, {}, 0
    local H = {}
    function H.push(k, v)
        n = n + 1
        local i = n
        while i > 1 do
            local p = floor(i / 2)
            if hk[p] <= k then break end
            hk[i], hv[i] = hk[p], hv[p]
            i = p
        end
        hk[i], hv[i] = k, v
    end
    function H.pop()
        if n == 0 then return nil end
        local k, v = hk[1], hv[1]
        local lk, lv = hk[n], hv[n]
        hk[n], hv[n] = nil, nil
        n = n - 1
        if n > 0 then
            local i = 1
            while true do
                local c = i * 2
                if c > n then break end
                if c < n and hk[c + 1] < hk[c] then c = c + 1 end
                if lk <= hk[c] then break end
                hk[i], hv[i] = hk[c], hv[c]
                i = c
            end
            hk[i], hv[i] = lk, lv
        end
        return k, v
    end
    function H.size() return n end
    return H
end

-- distances depuis src (ou vers src si back) ; s arrete quand toutes les
-- cibles (set de pieces) sont atteintes. -> dist, prev (tables creuses)
function M.Dijkstra(g, src, targets, back)
    if back then reverse(g) end
    local first, to = back and g.rfirst or g.first, back and g.rto or g.to
    local dist, prev, done = { [src] = 0 }, {}, {}
    local left = 0
    for _ in pairs(targets or {}) do left = left + 1 end
    local h = heap()
    h.push(0, src)
    local steps = 0
    while h.size() > 0 do
        local d, u = h.pop()
        if not done[u] then
            done[u] = true
            if targets and targets[u] then
                left = left - 1
                if left <= 0 then break end
            end
            for k = first[u], first[u + 1] - 1 do
                local v = to[k]
                if not done[v] then
                    local nd = d + cost(g, u, v)
                    if not dist[v] or nd < dist[v] then
                        dist[v], prev[v] = nd, u
                        h.push(nd, v)
                    end
                end
            end
            steps = steps + 1
            if steps % 300 == 0 then tick() end
        end
    end
    return dist, prev
end

-- chemin de a a b (A*) : liste de pieces, longueur ; nil si aucun
function M.Path(g, a, b)
    if a == b then return { a }, 0 end
    local gs, prev, done = { [a] = 0 }, {}, {}
    local bn, bw = g.N[b], g.W[b]
    local function hval(i)
        local dn, dw = g.N[i] - bn, g.W[i] - bw
        return sqrt(dn * dn + dw * dw)
    end
    local h = heap()
    h.push(hval(a), a)
    local steps = 0
    while h.size() > 0 do
        local _, u = h.pop()
        if u == b then break end
        if not done[u] then
            done[u] = true
            for k = g.first[u], g.first[u + 1] - 1 do
                local v = g.to[k]
                if not done[v] then
                    local nd = gs[u] + cost(g, u, v)
                    if not gs[v] or nd < gs[v] then
                        gs[v], prev[v] = nd, u
                        h.push(nd + hval(v), v)
                    end
                end
            end
            steps = steps + 1
            if steps % 300 == 0 then tick() end
        end
    end
    if not gs[b] then return nil end
    local path = {}
    local i = b
    while i do
        table.insert(path, 1, i)
        i = prev[i]
    end
    return path, gs[b]
end

-- chemin (pieces) -> points de passage { cont, x (nord), y (ouest) } : on
-- garde les tournants (plus de 20 degres) et au moins un point tous les 400 m
function M.Waypoints(g, path)
    local out = {}
    local function keep(i) out[#out + 1] = { cont = g.cont, x = g.N[i], y = g.W[i], z = g.Z[i] } end
    if not path or #path == 0 then return out end
    local last = path[1]
    for k = 2, #path - 1 do
        local a, b, c = path[k - 1], path[k], path[k + 1]
        local x1, y1 = g.N[b] - g.N[a], g.W[b] - g.W[a]
        local x2, y2 = g.N[c] - g.N[b], g.W[c] - g.W[b]
        local l1, l2 = sqrt(x1 * x1 + y1 * y1), sqrt(x2 * x2 + y2 * y2)
        local turn = (l1 > 0 and l2 > 0) and (x1 * x2 + y1 * y2) / (l1 * l2) < 0.94 or false
        local dn, dw = g.N[b] - g.N[last], g.W[b] - g.W[last]
        if turn or sqrt(dn * dn + dw * dw) > 400 then
            keep(b)
            last = b
        end
    end
    keep(path[#path])
    return out
end

---------------------------------------------------------------------------
-- Couts de marche pour le planificateur
---------------------------------------------------------------------------

-- depart, arrivee, pierre ({ cont, x, y }), vitesse (m/s) -> fonction
-- walk(p, q) du planificateur : secondes, false (pas de passage a pied) ou
-- nil (pas de donnees : ligne droite). Trois recherches : depuis le depart,
-- vers l arrivee, depuis le lieu de la pierre ; entre deux points fixes
-- (vols, quais, liaisons), les distances deja calculees.
function M.Costs(start, dest, hearth, run)
    local spots = { start = start, dest = dest, hearth = hearth }
    local snap = {}
    for k, p in pairs(spots) do
        local g = p and M.Graph(p.cont)
        if g then
            local i, d = M.Snap(g, p.x, p.y, p.z)
            if i then snap[k] = { g = g, i = i, d = d } end
        end
    end
    -- piece d un point du planificateur sur un graphe
    local function nodeOf(g, p)
        local s = snap[p.key]
        if s then return s.g == g and s.i or nil, s.d end
        local i = g.pois[p.key]
        if i then return i, 0 end
    end
    local function targetsOn(g)
        local t = {}
        for _, i in pairs(g.pois) do t[i] = true end
        for _, s in pairs(snap) do if s.g == g then t[s.i] = true end end
        return t
    end
    -- recherches (une piece isolee : moins de 30 pieces atteintes -> on n y croit pas)
    local res = {}
    local function search(k, back)
        local s = snap[k]
        if not s then return end
        local dist = M.Dijkstra(s.g, s.i, targetsOn(s.g), back)
        local n = 0
        for _ in pairs(dist) do
            n = n + 1
            if n >= 30 then break end
        end
        if n >= 30 then res[k] = dist end
    end
    search("start", false)
    search("dest", true)
    search("hearth", false)
    local function walk(p, q)
        local g = (snap[p.key] and snap[p.key].g) or (snap[q.key] and snap[q.key].g) or M.Graph(p.cont)
        if not g then return nil end
        local a, da = nodeOf(g, p)
        local b, db = nodeOf(g, q)
        if not (a and b) then return nil end
        local d
        if res[p.key] then
            d = res[p.key][b]
        elseif res[q.key] and q.key == "dest" then
            d = res[q.key][a]
        elseif not snap[p.key] and not snap[q.key] then
            d = M.PoiDist(g, p.key, q.key)
            if not d and a == b then d = 0 end
        else
            return nil
        end
        if not d then return false end
        return (d + (da or 0) + (db or 0)) / run
    end
    return walk, snap
end

-- chemin a pied entre deux points du monde -> points de passage, longueur ;
-- nil sans donnees ou sans passage
function M.Route(from, to)
    local g = from and to and from.cont == to.cont and M.Graph(from.cont)
    if not g then return nil end
    local a = M.Snap(g, from.x, from.y, from.z)
    local b = M.Snap(g, to.x, to.y, to.z)
    if not (a and b) then return nil end
    local path, len = M.Path(g, a, b)
    if not path then return nil end
    return M.Waypoints(g, path), len
end
