--[[--------------------------------------------------------------------------
    CorpUI - module Voyage : le voyage, la fenetre, les reglages

    Le trajet le plus rapide vers un point, a pied, en vol, en bateau ou par
    la pierre de foyer. Donnees des tables du jeu (Donnees.lua) et relevees
    en jeu (Releves.lua).

    Destination :
      Maj + clic sur la carte du monde (Carte.lua), Maj + clic droit : annuler ;
      "Y aller" dans le menu du suivi des quetes ;
      l etape du Leveling, d elle-meme, quand un trajet plus rapide que la
      marche existe (autre continent, vol, pierre de foyer).

    Fenetre a part, dessin du suivi des quetes : en-tete (Voyage, duree
    totale, croix pour annuler), destination, puis les etapes restantes :
    icone, ce qu il faut faire, duree. L etape en cours est en tete ; elle
    passe a la suivante quand on arrive au bout (rayon selon le type). La
    fleche (Fleche.lua) montre le bout de l etape a pied, ou le maitre de
    vol / le quai ou monter.

    Le trajet est recalcule toutes les 10 s tant qu on marche (on peut
    prendre un autre chemin), jamais en vol ; en attendant un bateau, pas
    avant la fin de la rotation estimee.

    /corp voyage       : reglages
    /corp voyage stop  : annuler le voyage
    /corp voyage diag  : ce que le jeu donne
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local V = ns.Voyage
local P = ns.VoyagePlan
local num, str, yes, call = V.num, V.str, V.yes, V.call

local WIDTH = 230
local HEAD_H = 22
local MAX_ROWS = 6
local ARRIVE = 15                 -- metres de la destination : arrive
local RADIUS = { walk = 25, fly = 100, boat = 150, hearth = 200, tram = 80, portal = 60 }
local LEAVE = 150                 -- parti du maitre de vol / du point de depart : recalcul
local REPLAN = 10                 -- secondes entre deux calculs en marchant
local AUTO_EVERY = 15             -- suivi du Leveling
local ICONS = {
    walk = "Interface\\Icons\\Ability_Rogue_Sprint",
    fly = "Interface\\Minimap\\Tracking\\FlightMaster",
    boat = "Interface\\Icons\\Ability_Druid_AquaticForm",
    hearth = "Interface\\Icons\\INV_Misc_Rune_01",
    tram = "Interface\\Icons\\Trade_Engineering",
    portal = "Interface\\Icons\\Spell_Arcane_PortalDarnassus",
}

local db, frame, header, body, rows
local dest           -- { cont, x, y, label, source, questID, map, mx, my }
local trip           -- { steps, cur, at, since, auto }
local onTaxi = false
local autoKey, autoAt = nil, 0
local dirty = true
local lastDraw = 0
local pendingKey, pendingSince   -- etape du Leveling nouvelle, pas encore stable

-- journal des changements du voyage (diagnostic : /corp voyage diag, et la
-- sauvegarde CorpUIDB.voyage.trace)
local trace = {}
local function note(what)
    trace[#trace + 1] = string.format("%.1f %s", GetTime(), what)
    if #trace > 30 then table.remove(trace, 1) end
    if db then db.trace = trace end
end
V.Note = note
function V.Trace() return trace end

local function copy(t)
    local o = {}
    for k, v in pairs(t) do o[k] = v end
    return o
end

local function fmt(sec) return ns.FormatTime(math.max(0, math.floor((sec or 0) + 0.5))) end

---------------------------------------------------------------------------
-- Calcul du trajet
---------------------------------------------------------------------------

local function planOpts()
    return {
        side = V.Side(),
        known = V.Mine("known"),
        run = V.RunSpeed(),
        fly = db.flySpeed,
        times = db.times,
        hearth = db.hearth and V.Hearth() or nil,
        noBoats = not db.boats,
    }
end

-- noms des etapes (gardes dans l etape : C_Map seulement au calcul)
local function label(steps)
    for i, s in ipairs(steps) do
        local nx = steps[i + 1]
        if s.kind == "walk" then
            if s.dest then
                s.title = string.format(L.VOY_GO, dest and dest.label or L.VOY_THE_DEST)
            elseif nx and nx.kind == "fly" then
                s.title = string.format(L.VOY_GO_FM, V.NodeName(s.to))
            elseif nx and nx.kind == "tram" then
                s.title = string.format(L.VOY_GO_TRAM, V.ZoneAt(s.cont, s.x, s.y) or "?")
            elseif nx and nx.kind == "portal" then
                s.title = string.format(L.VOY_GO_PORTAL, V.ZoneAt(s.cont, s.x, s.y) or "?")
            elseif nx and nx.kind == "boat" then
                s.title = string.format(L.VOY_GO_DOCK, V.ZoneAt(s.cont, s.x, s.y) or "?")
            else
                s.title = string.format(L.VOY_GO, V.ZoneAt(s.cont, s.x, s.y) or "?")
            end
        elseif s.kind == "fly" then
            s.title = string.format(L.VOY_FLY, V.NodeName(s.to))
            if s.via then
                local names = {}
                for _, id in ipairs(s.via) do names[#names + 1] = V.NodeName(id) end
                s.viaText = string.format(L.VOY_VIA, table.concat(names, ", "))
            end
        elseif s.kind == "boat" then
            s.title = string.format(L.VOY_BOAT, V.ZoneAt(s.cont, s.x, s.y) or "?")
        elseif s.kind == "tram" then
            s.title = string.format(L.VOY_TRAM, V.ZoneAt(s.cont, s.x, s.y) or "?")
        elseif s.kind == "portal" then
            s.title = string.format(L.VOY_PORTAL, V.ZoneAt(s.cont, s.x, s.y) or "?")
        elseif s.kind == "hearth" then
            local h = V.Hearth()
            s.title = string.format(L.VOY_HEARTH, (h and h.name) or V.ZoneAt(s.cont, s.x, s.y) or "?")
        end
    end
end

-- calcul en tache de fond (coroutine) : couts de marche du terrain
-- (Marche.lua), puis plan. Un seul a la fois : le dernier demande remplace
-- le precedent. Le budget de temps par image est celui de Marche.lua.
local Walk = ns.VoyageWalk
local runner = CreateFrame("Frame")
V._runner = runner        -- banc d essai : faire tourner les calculs image par image
local job, jobDone
local function stepJob()
    if not job then
        runner:SetScript("OnUpdate", nil)
        return
    end
    if Walk then Walk.deadline = Walk.clock() + Walk.budget end
    local ok, err = coroutine.resume(job)
    if Walk then Walk.deadline = nil end
    if coroutine.status(job) == "dead" then
        local done = jobDone
        job, jobDone = nil, nil
        runner:SetScript("OnUpdate", nil)
        if not ok then geterrorhandler()(err) elseif done then done() end
    end
end
local function startJob(fn, done)
    job, jobDone = coroutine.create(fn), done
    runner:SetScript("OnUpdate", stepJob)
    stepJob()
end
function V.Busy() return job ~= nil end

-- calcule le trajet du joueur a d, puis done(steps, total) (steps nil : aucun)
local function compute(me, d, done)
    if not (me and me.cont and d) then return done(nil) end
    local start = { cont = me.cont, x = me.wx, y = me.wy }
    local opts = planOpts()
    local steps, total
    startJob(function()
        if Walk and (Walk.Has(start.cont) or Walk.Has(d.cont)) then
            opts.walk = Walk.Costs(start, d, opts.hearth, opts.run)
        end
        steps, total = P.Plan(start, d, opts)
    end, function() done(steps, total) end)
end

local function setTrip(steps, auto)
    if not steps then
        trip = nil
        return
    end
    trip = { steps = steps, cur = 1, at = GetTime(), since = GetTime(), auto = auto }
    label(steps)
end

local function save()
    if not db then return end
    db.dest = db.dest or {}
    db.dest[ns.CharKey()] = (dest and dest.source ~= "leveling") and copy(dest) or nil
end

function V.SetDest(d)
    if not db then return end
    local me = V.Player()
    if not (me and me.cont) then
        ns.Say(L.VOY_NO_POS)
        return
    end
    dest = d
    autoKey = nil
    compute(me, d, function(steps, total)
        if dest ~= d then return end             -- remplacee entre-temps
        if not steps then
            ns.Say(string.format(L.VOY_NO_ROUTE, d.label or L.VOY_THE_DEST))
            dest, trip = nil, nil
            save()
            V.Refresh()
            return
        end
        setTrip(steps, false)
        save()
        ns.Say(string.format(L.VOY_DEST_SET, d.label or L.VOY_THE_DEST, fmt(total)))
        V.Refresh()
    end)
end

function V.Cancel(quiet)
    local had = dest ~= nil and dest.source ~= "leveling"
    dest, trip = nil, nil
    autoKey = nil
    job, jobDone = nil, nil
    save()
    if had and not quiet then ns.Say(L.VOY_CANCELLED) end
    V.Refresh()
end

-- point d une carte (0-1)
function V.GoMap(map, x, y)
    local cont, wx, wy = V.World(map, x, y)
    if not cont then
        ns.Say(L.VOY_ZOOM_IN)
        return
    end
    local zmap, zx, zy = V.MapPos(cont, wx, wy)
    local name = (zmap and V.MapName(zmap)) or V.MapName(map) or "?"
    local lbl = zx and string.format("%s (%.0f, %.0f)", name, zx * 100, zy * 100) or name
    V.SetDest({ cont = cont, x = wx, y = wy, label = lbl, source = "map", map = map, mx = x, my = y })
end

-- quete du journal
function V.GoQuest(id)
    local map, x, y = V.QuestDest(id)
    local cont, wx, wy
    if map then cont, wx, wy = V.World(map, x, y) end
    if not cont then
        ns.Say(L.VOY_QUEST_UNKNOWN)
        return
    end
    local title = str(call(C_QuestLog and C_QuestLog.GetTitleForQuestID, id)) or tostring(id)
    V.SetDest({ cont = cont, x = wx, y = wy, label = string.format(L.VOY_QUEST, title), source = "quest", questID = id,
                map = map, mx = x, my = y })
end

-- destination en cours (carte du monde : epingle)
function V.Dest() return dest end

-- voyage en cours avec la fleche du Voyage : celle du Leveling se cache
function V.Guiding()
    return db and db.arrow and trip ~= nil and trip.steps[trip.cur] ~= nil or false
end

---------------------------------------------------------------------------
-- Suivi : etape en cours, arrivee, recalcul
---------------------------------------------------------------------------

local function stepStart(s) return { cont = s.fc, x = s.fx, y = s.fy } end

-- bout d etape atteint : on passe aux suivantes (on peut en sauter)
local function advance(me)
    local steps = trip.steps
    for i = #steps, trip.cur, -1 do
        local s = steps[i]
        local d = V.Dist(me, s)
        if d and d <= (RADIUS[s.kind] or 25) and not (s.kind == "fly" and onTaxi) then
            if i + 1 ~= trip.cur then
                trip.cur = i + 1
                trip.since = GetTime()
            end
            return
        end
    end
end

local function needReplan(me)
    if not trip then return true end
    if onTaxi then return false end
    local now = GetTime()
    if now - trip.at < REPLAN then return false end
    local s = trip.steps[trip.cur]
    if not s then return true end
    if s.kind == "walk" then return true end
    if s.kind == "boat" or s.kind == "tram" then
        -- a bord (ou dans le tram, une autre carte), on s eloigne du quai : pas de recalcul avant la fin de la rotation estimee
        return now - trip.since > (s.time + 120) * 1.5
    end
    -- vol ou pierre : seulement si on est parti du point de depart
    local d = V.Dist(me, stepStart(s))
    return d == nil or d > LEAVE
end

-- trajet a pied seulement, sans detour : la fleche du Leveling suffit. Avec
-- un detour (montagne, col, pont), le Voyage guide par le chemin.
local function walkOnly(steps, me, shown)
    if #steps == 0 then return true end
    if #steps > 1 or steps[1].kind ~= "walk" then return false end
    local straight = V.Dist(me, steps[1])
    local path = steps[1].time * V.RunSpeed()
    -- deja affiche : on le garde tant que le detour reste net (seuils plus bas)
    local minDist, ratio = shown and 150 or 250, shown and 1.12 or 1.25
    return not (straight and straight > minDist and path > straight * ratio)
end

-- zones traversees par des points de passage ("par Les Carmines, ...")
local function zonesOf(wps)
    local names, seen = {}, {}
    for _, p in ipairs(wps) do
        local z = V.ZoneAt(p.cont, p.x, p.y)
        if z and not seen[z] then
            seen[z] = true
            names[#names + 1] = z
        end
    end
    if #names >= 2 then return string.format(L.VOY_VIA, table.concat(names, ", ")) end
end

-- distance d un point au segment [a, b] (monde, 2D)
local function segDist(me, a, b)
    local px, py = me.wx, me.wy
    local ax, ay, bx, by = a.x, a.y, b.x, b.y
    local dx, dy = bx - ax, by - ay
    local l2 = dx * dx + dy * dy
    local t = l2 > 0 and math.max(0, math.min(1, ((px - ax) * dx + (py - ay) * dy) / l2)) or 0
    local qx, qy = ax + t * dx - px, ay + t * dy - py
    return math.sqrt(qx * qx + qy * qy)
end

-- etape a pied : chemin du terrain (points de passage), suivi pas a pas
local WP_REACHED, WP_OFF = 25, 120
local function guide(me)
    local s = trip.steps[trip.cur]
    if not (s and s.kind == "walk" and Walk and Walk.Has(s.cont) and me.cont == s.cont) then return end
    if s.wps then
        while s.wpi < #s.wps do
            local d = V.Dist(me, s.wps[s.wpi])
            if not (d and d < WP_REACHED) then break end
            s.wpi = s.wpi + 1
        end
        -- ecarte du chemin : on en cherche un nouveau d ici
        local a = s.wpi > 1 and s.wps[s.wpi - 1] or s.from0
        if a and segDist(me, a, s.wps[s.wpi]) > WP_OFF then s.wps = nil end
    end
    if not s.wps and not job and GetTime() - (s.routedAt or 0) > 5 then
        s.routedAt = GetTime()
        local from = { cont = me.cont, x = me.wx, y = me.wy }
        local to = { cont = s.cont, x = s.x, y = s.y }
        local wps, len
        startJob(function() wps, len = Walk.Route(from, to) end, function()
            if not (trip and trip.steps[trip.cur] == s and wps) then return end
            s.wps, s.wpi, s.pathLen, s.from0 = wps, 1, len, from
            s.viaText = zonesOf(wps)
            V.Refresh()
        end)
    end
end

-- l etape du Leveling, suivie quand un trajet plus rapide que la marche existe
local function followLeveling(me)
    local LV = ns.Leveling
    local a = db.leveling and LV and LV.current
    if not (a and a.map and a.x) then
        if trip and trip.auto then
            note("auto : plus d etape du Leveling")
            dest, trip = nil, nil
        end
        autoKey, pendingKey = nil, nil
        return
    end
    local now = GetTime()
    if onTaxi and trip then return end          -- en vol : on garde le trajet jusqu a l arrivee
    if a.key == autoKey then
        pendingKey = nil
        if trip then return end                 -- voyage en cours : recalcule par update (needReplan)
        if now - autoAt < AUTO_EVERY then return end
    elseif autoKey and trip then
        -- l etape du Leveling a change : elle doit tenir 2 s (pas de va-et-vient)
        if pendingKey ~= a.key then
            pendingKey, pendingSince = a.key, now
            return
        end
        if now - pendingSince < 2 then return end
    end
    pendingKey = nil
    autoKey, autoAt = a.key, now
    local cont, wx, wy = V.World(a.map, a.x, a.y)
    if not cont then return end
    local title = a.title or (LV.Title and LV.Title(a.id)) or "?"
    local mine = { cont = cont, x = wx, y = wy, label = string.format(L.VOY_LEVELING, title), source = "leveling" }
    local shown = trip ~= nil and trip.auto
    note("auto : calcul vers " .. title .. " (" .. tostring(a.key) .. ")")
    -- le trajet affiche (s il y en a un) reste la jusqu au resultat
    compute(me, mine, function(steps)
        if dest and dest.source ~= "leveling" then return end      -- destination choisie entre-temps
        if steps and not walkOnly(steps, me, shown) then
            dest = mine
            setTrip(steps, true)
            note("auto : trajet, " .. #steps .. " etape(s)")
        else
            if trip then note("auto : a pied sans detour, le Leveling guide") end
            dest, trip = nil, nil
        end
        V.Refresh()
    end)
end

local function update()
    if not db then return end
    local me = V.Player()
    if not (me and me.cont) then return end
    local user = dest and dest.source ~= "leveling"
    if not user and not job then followLeveling(me) end
    if not dest then return end
    -- arrivee
    local d = V.Dist(me, dest)
    if d and d < ARRIVE then
        note("arrive : " .. tostring(dest.label))
        if user then ns.Say(string.format(L.VOY_ARRIVED, dest.label or L.VOY_THE_DEST)) end
        dest, trip = nil, nil
        if not user then autoKey = nil end
        save()
        return
    end
    if trip then advance(me) end
    if trip and trip.cur > #trip.steps then trip.at = 0 end      -- au bout sans etre arrive : recalcul
    if trip then guide(me) end
    if job or not needReplan(me) then return end
    if trip then trip.at = GetTime() end
    local mine = dest
    compute(me, mine, function(steps)
        if dest ~= mine then return end
        if steps and not user and walkOnly(steps, me, true) then
            -- etape du Leveling a portee de marche, sans detour : le Leveling reprend la main
            note("recalcul : a pied sans detour, le Leveling guide")
            dest, trip = nil, nil
            autoAt = GetTime()
            return
        end
        if steps then
            -- meme chemin a pied deja suivi : on garde ses points de passage
            local old = trip and trip.steps[trip.cur]
            setTrip(steps, not user)
            local new = trip.steps[1]
            if old and old.wps and new.kind == "walk" and old.kind == "walk" and V.Dist(old, new) and V.Dist(old, new) < 30 then
                new.wps, new.wpi, new.pathLen, new.from0, new.viaText = old.wps, old.wpi, old.pathLen, old.from0, old.viaText
            end
        elseif not trip then
            note("recalcul : aucun trajet")
            dest = nil
            save()
        end
        V.Refresh()
    end)
end

---------------------------------------------------------------------------
-- Fenetre
---------------------------------------------------------------------------

local function stepSub(s, current)
    if s.kind == "fly" then
        if current and onTaxi then return L.VOY_ON_TAXI, { 0.6, 0.8, 1 } end
        if current then return L.VOY_SUB_TALK, { 1, 0.82, 0 } end
        return s.viaText, { 0.6, 0.6, 0.6 }
    elseif s.kind == "boat" then
        return string.format(L.VOY_SUB_BOARD, fmt(s.wait or 0)), { 0.6, 0.8, 1 }
    elseif s.kind == "tram" then
        return string.format(L.VOY_SUB_TRAM, fmt(s.time)), { 0.6, 0.8, 1 }
    elseif s.kind == "hearth" then
        local h = V.Hearth()
        if h and h.wait > 0 then return string.format(L.VOY_SUB_READY_IN, fmt(h.wait)), { 1, 0.5, 0.3 } end
        return L.VOY_SUB_USE, { 1, 0.82, 0 }
    elseif s.kind == "walk" then
        return s.viaText, { 0.6, 0.6, 0.6 }
    end
end

-- duree d une etape (celle en cours a pied : selon la distance qui reste)
local function stepTime(s, current, me)
    if current and s.kind == "walk" then
        if s.wps then
            -- par le chemin : jusqu au point de passage, puis les suivants
            local d = V.Dist(me, s.wps[s.wpi])
            if d then
                for k = s.wpi, #s.wps - 1 do d = d + (V.Dist(s.wps[k], s.wps[k + 1]) or 0) end
                return d / V.RunSpeed()
            end
        end
        local d = V.Dist(me, s)
        if d then return d / V.RunSpeed() end
    end
    if current and s.kind == "hearth" then
        local h = V.Hearth()
        if h then return P.HEARTH + h.wait end
    end
    return s.time
end

local function row(i)
    if rows[i] then return rows[i] end
    local C = ns.COLORS
    local r = CreateFrame("Frame", nil, body)
    r:SetWidth(WIDTH)
    r.mark = r:CreateTexture(nil, "BACKGROUND")
    r.mark:SetPoint("TOPLEFT", 1, 1)
    r.mark:SetPoint("BOTTOMRIGHT", -1, -1)
    ns.UI.Gradient(r.mark, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.18, C.violet[1], C.violet[2], C.violet[3], 0)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(14, 14)
    r.icon:SetPoint("TOPLEFT", 4, -1)
    r.time = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.time:SetPoint("TOPRIGHT", 0, -1)
    r.time:SetJustifyH("RIGHT")
    r.title = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.title:SetJustifyH("LEFT")
    r.title:SetWordWrap(true)
    r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.sub:SetJustifyH("LEFT")
    r.sub:SetWordWrap(true)
    rows[i] = r
    return r
end

local function fill(r, s, current, y, me)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
    r.mark:SetShown(current)
    r.icon:SetTexture(ICONS[s.kind])
    if s.kind == "fly" then r.icon:SetTexCoord(0, 1, 0, 1) else r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    r.time:SetText(fmt(stepTime(s, current, me)))
    r.title:ClearAllPoints()
    r.title:SetPoint("TOPLEFT", 24, 0)
    r.title:SetPoint("TOPRIGHT", -((r.time:GetStringWidth() or 0) + 6), 0)
    r.title:SetText(s.title or "?")
    if current then r.title:SetTextColor(0.95, 0.95, 0.95) else r.title:SetTextColor(0.7, 0.7, 0.7) end
    local sub, c = stepSub(s, current)
    r.sub:ClearAllPoints()
    r.sub:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 10, -2)
    r.sub:SetPoint("RIGHT", r, "RIGHT", -2, 0)
    r.sub:SetText(sub or "")
    if c then r.sub:SetTextColor(c[1], c[2], c[3]) end
    r.sub:SetShown(sub ~= nil)
    local h = math.max(12, r.title:GetStringHeight() or 0)
    if sub then h = h + 2 + math.max(10, r.sub:GetStringHeight() or 0) end
    r:SetHeight(h + 2)
    r:Show()
    return h + 2
end

local function draw()
    if not frame then return end
    local me = V.Player()
    local live = trip and trip.steps[trip.cur]
    if not (db.enabled and (live or ns.moversShown)) then
        frame:Hide()
        return
    end
    local y, count = 4, 0
    local total = 0
    if live then
        for i = trip.cur, #trip.steps do total = total + (stepTime(trip.steps[i], i == trip.cur, me) or 0) end
        header.total:SetText(string.format(L.VOY_TOTAL, fmt(total)))
        frame.dest:SetText(dest and dest.label or "")
        frame.dest:Show()
        y = y + (frame.dest:GetStringHeight() or 12) + 4
        for i = trip.cur, math.min(#trip.steps, trip.cur + MAX_ROWS - 1) do
            count = count + 1
            y = y + fill(row(count), trip.steps[i], i == trip.cur, y, me) + 4
        end
    else
        header.total:SetText("")
        frame.dest:Hide()
    end
    for i = count + 1, #rows do rows[i]:Hide() end
    frame.empty:SetShown(count == 0)
    if count == 0 then y = 4 + (frame.empty:GetStringHeight() or 14) + 4 end
    body:SetHeight(y)
    frame:SetHeight(HEAD_H + 2 + y)
    frame:Show()
end

-- point montre par la fleche
local function arrowTarget()
    local s = trip and trip.steps[trip.cur]
    if not s then return nil end
    if s.kind == "walk" then
        -- chemin du terrain : le prochain point de passage
        local p = s.wps and s.wps[s.wpi] or s
        return { cont = p.cont, x = p.x, y = p.y, title = s.title, sub = s.viaText }
    end
    local sub = stepSub(s, true)
    if s.kind == "hearth" or onTaxi then return { noPoint = true, title = s.title, sub = sub } end
    return { cont = s.fc, x = s.fx, y = s.fy, title = s.title, sub = sub }
end

local function build()
    db.pos = db.pos or { point = "TOPLEFT", x = 20, y = -120 }
    frame = CreateFrame("Frame", "CorpUIVoyage", UIParent)
    frame:SetSize(WIDTH, HEAD_H + 30)
    frame:SetFrameStrata("LOW")
    ns.ApplyPos(frame, db.pos)
    rows = {}

    header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEAD_H)
    local rule = header:CreateTexture(nil, "BORDER")
    rule:SetPoint("BOTTOMLEFT", 0, 1)
    rule:SetPoint("BOTTOMRIGHT", 0, 1)
    rule:SetHeight(1)
    ns.NoSnap(rule)
    rule:SetColorTexture(1, 1, 1, 0.22)
    header.title = header:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(header.title, 12)
    header.title:SetPoint("LEFT", 2, 0)
    header.title:SetTextColor(0.93, 0.93, 0.93)
    header.title:SetText(L.MOD_VOYAGE)
    header.total = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    header.total:SetPoint("LEFT", header.title, "RIGHT", 6, 0)
    header.close = CreateFrame("Button", nil, header)
    header.close:SetSize(18, 18)
    header.close:SetPoint("RIGHT", -3, 0)
    header.close.label = header.close:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(header.close.label, 14)
    header.close.label:SetPoint("CENTER", 0, 1)
    header.close.label:SetText("×")
    header.close:SetScript("OnClick", function() V.Cancel() end)
    header.close:SetScript("OnEnter", function(self)
        local t = ns.Tooltip(self, "ANCHOR_LEFT")
        t:AddLine(L.VOY_CANCEL)
        t:Show()
    end)
    header.close:SetScript("OnLeave", ns.HideTooltip)

    body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    body:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -2)
    body:SetHeight(1)
    ns.NoSnap(body)

    frame.dest = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.dest:SetPoint("TOPLEFT", 4, -4)
    frame.dest:SetPoint("RIGHT", -4, 0)
    frame.dest:SetJustifyH("LEFT")
    frame.dest:SetTextColor(1, 0.82, 0)
    frame.empty = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.empty:SetPoint("TOPLEFT", 4, -4)
    frame.empty:SetPoint("RIGHT", -4, 0)
    frame.empty:SetJustifyH("LEFT")
    frame.empty:SetText(L.VOY_OPT_MAPCLICK)
    frame:Hide()
    ns.UI.Mover(frame, db.pos, L.MOD_VOYAGE)
end

function V.Refresh()
    if not db then return end
    draw()
    V.SetArrow(arrowTarget(), db)
    if V.MapRefresh then V.MapRefresh() end
end

-- banc d essai : etat
function V._state() return { dest = dest, trip = trip, frame = frame, rows = rows, onTaxi = onTaxi } end

---------------------------------------------------------------------------
-- Reglages
---------------------------------------------------------------------------

local win

local function buildWindow()
    win = ns.UI.Window("CorpUIVoyageOptions", ns.TITLE .. " - " .. L.MOD_VOYAGE, nil, 440, 300)
    local form = ns.UI.Form(win, -34)
    form:Header(L.VOY_H_WINDOW)
    form:Check(L.VOY_OPT_SHOW, function() return db.enabled end, function(v) db.enabled = v V.Refresh() end)
    form:Header(L.VOY_H_ARROW)
    form:Check(L.VOY_OPT_ARROW, function() return db.arrow end, function(v) db.arrow = v V.Refresh() end)
    form:Number(L.VOY_OPT_ARROW_SIZE, function() return db.arrowScale end, function(v)
        db.arrowScale = v
        V.ArrowScale()
    end, 50, 200, 10)
    form:Header(L.VOY_H_ROUTE)
    form:Check(L.VOY_OPT_MAPCLICK, function() return db.mapClick end, function(v) db.mapClick = v end)
    form:Check(L.VOY_OPT_LEVELING, function() return db.leveling end, function(v)
        db.leveling = v
        autoKey = nil
        if not v and dest and dest.source == "leveling" then dest, trip = nil, nil end
        V.Refresh()
    end)
    form:Check(L.VOY_OPT_HEARTH, function() return db.hearth end, function(v) db.hearth = v dirty = true end)
    form:Check(L.VOY_OPT_BOATS, function() return db.boats end, function(v) db.boats = v dirty = true end)
    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", win, "TOPLEFT", 8, form.y - 6)
    hint:SetWidth(420)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.VOY_HINT)
    local stop = ns.UI.Button(win, L.VOY_CANCEL, 200, function() V.Cancel() end)
    stop:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
    win:SetHeight(-form.y + 130)
    win:HookScript("OnShow", function() form:Refresh() end)
end

local function toggle()
    if not win then buildWindow() end
    ns.ShowPanel(win)
end

---------------------------------------------------------------------------
-- Menu du suivi des quetes : "Y aller"
---------------------------------------------------------------------------

ns.QuestMenuHooks = ns.QuestMenuHooks or {}
table.insert(ns.QuestMenuHooks, {
    value = "voyage",
    text = function() return db and L.VOY_MENU_GO or nil end,
    run = function(id) V.GoQuest(id) end,
})

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

local readNodesAt

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, a1, _, a3)
    if ns.ModuleOff("voyage", ev) then return end
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        root.voyage = root.voyage or {}
        db = root.voyage
        if db.enabled == nil then db.enabled = true end
        if db.arrow == nil then db.arrow = true end
        if db.mapClick == nil then db.mapClick = true end
        if db.leveling == nil then db.leveling = true end
        if db.hearth == nil then db.hearth = true end
        if db.boats == nil then db.boats = true end
        db.arrowScale = db.arrowScale or 100
        -- points de vol connus lus a tort sur la carte du jeu (tous "decouverts") :
        -- on repart de zero (maitre de vol ouvert, vols pris)
        if db.knownV ~= 2 then
            db.known, db.knownV = {}, 2
        end
        build()
        local saved = db.dest and db.dest[ns.CharKey()]
        if type(saved) == "table" and saved.cont and saved.x then dest = copy(saved) end
        -- deverrouillage : fenetre et fleche en apercu
        ns.Listen(function() if db then V.Refresh() end end)
        if V.MapSetup then V.MapSetup() end
        readNodesAt = GetTime() + 5
        note("connexion")
        return
    end
    if not db then return end
    if event == "PLAYER_ENTERING_WORLD" then
        readNodesAt = GetTime() + 3
    elseif event == "TAXIMAP_OPENED" then
        V.ReadTaxiMap()
        V.ReadNodes()
    elseif event == "HEARTHSTONE_BOUND" then
        V.HearthBound()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- chaque sort du joueur passe ici (inscrit pour "player" seulement) :
        -- seule la pierre de foyer compte
        if num(a3) ~= V.HEARTH_SPELL then return end
        V.HearthCast(V.Player())
    elseif event == "ADDON_LOADED" then
        if a1 == "Blizzard_WorldMap" and V.MapSetup then V.MapSetup() end
        return
    end
    dirty = true
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "TAXIMAP_OPENED", "HEARTHSTONE_BOUND", "ADDON_LOADED",
                     "ZONE_CHANGED_NEW_AREA", "PLAYER_CONTROL_GAINED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_SUCCEEDED", "player")

-- deux fois par seconde : releves (vol, pierre, monture) ; une fois par
-- seconde (ou apres un evenement) : suivi du trajet, fenetre, fleche
ns.Every(0.5, function()
    if not db then return end
    local me = V.Player()
    onTaxi = yes(call(UnitOnTaxi, "player"))
    for _, fn in ipairs({ V.TrackFlight, V.TrackHearth, V.TrackSpeed }) do
        local ok, err = pcall(fn, me, onTaxi)
        if not ok then geterrorhandler()(err) end
    end
    if readNodesAt and GetTime() >= readNodesAt then
        readNodesAt = nil
        local ok, n = pcall(V.ReadNodes)
        note(ok and ("noms des points de vol lus : " .. tostring(n) .. " nouveaux") or ("lecture des points de vol : " .. tostring(n)))
        if not ok then geterrorhandler()(n) end
    end
    local now = GetTime()
    if not dirty and now - lastDraw < 1 then return end
    if dirty and trip then trip.at = 0 end
    dirty, lastDraw = false, now
    local ok, err = pcall(update)
    if not ok then geterrorhandler()(err) end
    V.Refresh()
end, "Voyage", "voyage")

ns.RegisterModule({
    command = "voyage",
    panelName = "CorpUIVoyageOptions",
    icon = "Interface\\Icons\\Ability_Hunter_Pathfinding",
    title = function() return L.MOD_VOYAGE end,
    desc = function() return L.VOY_DESC end,
    Slash = function(input)
        local cmd = strlower(strtrim(input or ""))
        if cmd == "diag" then V.Diag() return end
        if cmd == "stop" then V.Cancel() return end
        toggle()
    end,
    Open = toggle,
})
