--[[--------------------------------------------------------------------------
    CorpUI - module Guide : le moteur (guides, etapes, avancement)

    Guide pas a pas de 1 a 60 : les guides de WoW Forever Tools (ceux
    qu affiche ConquestCapped), un par race, faction et classe, avec ou
    sans donjons. Donnees privees : Donnees/Guides.lua, genere par
    .github/scripts/guide_donnees.js, ignore par git, hors paquet.

    Un guide = une suite de parties (tranches de niveaux, une zone et sa
    carte), chaque partie une suite d etapes en texte balise (voir
    guide_donnees.js) : quetes avec leur role (prendre, rendre, faire,
    abandonner), PNJ, monstres, objets, sorts, lieux, coordonnees dans la
    zone de la partie, remarque.

    Etape faite :
      - cochee a la main ;
      - ou toutes ses conditions remplies (il en faut au moins une) :
        quete prise (dans le journal, ou deja rendue), rendue, objectifs
        faits, abandonnee, sort appris, niveau atteint.
    Avancement : la position gardee avance tant que l etape en cours est
    faite ; une quete deja rendue un peu plus loin (10 etapes) fait passer
    celles d avant (faites dans le desordre, ou sautees). Etape choisie a
    la main : elle reste en cours tant qu elle n est pas cochee.
    Recaler : la position va apres la derniere quete rendue du guide.

    Lecture seule : tout passe par pcall, valeurs secretes ecartees.
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L

local GD = {}
ns.Guide = GD

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
GD.num, GD.str, GD.call = num, str, call

GD.LOOKAHEAD = 10         -- etapes regardees plus loin pour une quete deja rendue

---------------------------------------------------------------------------
-- Donnees
---------------------------------------------------------------------------

function GD.Data()
    local d = ns.GuideData
    if type(d) == "table" and type(d.G) == "table" and type(d.E) == "table" then return d end
end

local byKey
local function index()
    if byKey then return byKey end
    byKey = {}
    local d = GD.Data()
    for _, g in ipairs(d and d.G or {}) do byKey[g.k] = g end
    return byKey
end
function GD.Get(key) return key and index()[key] or nil end
function GD.ResetIndex() byKey = nil end

-- partie p d un guide : { titre, carte, zone, etapes }
function GD.Stage(g, p)
    local d = GD.Data()
    local id = g and g.e[p]
    return id and d and d.E[id] or nil
end
function GD.Parts(g) return g and #g.e or 0 end

-- numero global d une etape et total (sommes gardees par guide)
local sums = {}
local function prefix(g)
    local t = sums[g.k]
    if t then return t end
    t = { [1] = 0 }
    for p = 1, #g.e do
        local e = GD.Stage(g, p)
        t[p + 1] = t[p] + (e and #e[4] or 0)
    end
    sums[g.k] = t
    return t
end
function GD.Index(g, p, s) return prefix(g)[p] + s end
function GD.Total(g) local t = prefix(g) return t[#t] end

---------------------------------------------------------------------------
-- Joueur et choix du guide
---------------------------------------------------------------------------

-- jetons du jeu (UnitRace) -> races des guides
local RACE = { Human = "Human", Dwarf = "Dwarf", NightElf = "Night Elf", Gnome = "Gnome", Orc = "Orc",
               Scourge = "Undead", Undead = "Undead", Tauren = "Tauren", Troll = "Troll" }
local function flat(s) return s and (s:gsub("[%s_%-]", ""):lower()) or nil end

function GD.Who()
    local raceLoc, race = call(UnitRace, "player")
    local _, class = call(UnitClass, "player")
    local faction = call(UnitFactionGroup, "player")
    race, class, faction, raceLoc = str(race), str(class), str(faction), str(raceLoc)
    -- Eolides : jeton du jeu inconnu (deux variantes, une par faction) ;
    -- reconnus a leur jeton ou a leur nom ("Eolide de l Ordre supreme")
    local r = race and RACE[race]
    if not r then
        local sky = L.GUIDE_RACE_SKYBORNE
        if (race and race:lower():find("skyborne", 1, true)) or (raceLoc and raceLoc:lower():find("skyborne", 1, true))
            or (raceLoc and sky and raceLoc:find(sky, 1, true)) then
            r = "Skyborne"
        end
    end
    return {
        race = r or race, raceToken = race, raceName = raceLoc,
        class = class and (class:sub(1, 1) .. class:sub(2):lower()), classToken = class,
        faction = faction,
    }
end

-- guide conseille : meme faction, puis classe, puis race
function GD.Pick(dungeons, who)
    who = who or GD.Who()
    local d = GD.Data()
    local best, bestScore
    for _, g in ipairs(d and d.G or {}) do
        if not g.ref and g.f == who.faction and (g.d == true) == (dungeons == true) then
            local s = (g.c == who.class and 4 or 0) + (flat(g.r) == flat(who.race) and 2 or 0)
            if not bestScore or s > bestScore then best, bestScore = g, s end
        end
    end
    return best and best.k or nil
end

-- meme guide avec ou sans donjons
function GD.Variant(key, dungeons)
    if not key then return nil end
    local base = key:gsub("%-dungeons$", "")
    local want = dungeons and (base .. "-dungeons") or base
    if GD.Get(want) then return want end
    return GD.Get(base) and base or key
end

local function raceName(r)
    if not r then return "" end
    local k = "GUIDE_RACE_" .. r:gsub("%s", ""):upper()
    local v = rawget(L, k) or L[k]
    return (v and v ~= k) and v or r
end
local function className(c)
    if not c then return "" end
    local t = LOCALIZED_CLASS_NAMES_MALE
    local v = type(t) == "table" and t[c:upper()]
    return str(v) or c
end
GD.RaceName, GD.ClassName = raceName, className

function GD.Label(g)
    if not g then return "" end
    if g.ref then return string.format(L.GUIDE_REF, g.f == "Horde" and L.GUIDE_HORDE or L.GUIDE_ALLIANCE) end
    local s = raceName(g.r) .. " · " .. className(g.c)
    if g.d then s = s .. " · " .. L.GUIDE_DUNGEONS end
    return s
end

---------------------------------------------------------------------------
-- Lecture d une etape
---------------------------------------------------------------------------

local HEX = {
    qa = "ffd100", qt = "40e040", qo = "70c8ff", qx = "ff6060", q = "e0c070",
    n = "8be08b", m = "ff7a6b", i = "c69bff", s = "71d5ff", l = "ffb347",
    xy = "9fb4ff", tag = "9d9d9d", tagMine = "c8a0ff",
}
GD.HEX = HEX

local function colored(hex, s) return "|cff" .. hex .. s .. "|r" end

-- {c:Hunter/Warlock}, {c:!Warlock !Druid} : pour qui ce passage est ecrit
local function tagLabel(spec, who)
    local yes_, no_ = {}, {}
    local pos, mine, neg = false, false, false
    for tok in spec:gmatch("[^/%s]+") do
        local not_ = tok:sub(1, 1) == "!"
        local t = not_ and tok:sub(2) or tok
        local isRace = RACE[t] ~= nil or flat(t) == "skyborne" or flat(t) == "undead"
        local name = isRace and raceName(RACE[t] or t) or className(t)
        local me = who and ((isRace and flat(RACE[t] or t) == flat(who.race)) or (not isRace and flat(t) == flat(who.class)))
        if not_ then
            no_[#no_ + 1] = name
            if me then neg = true end
        else
            yes_[#yes_ + 1] = name
            pos = true
            if me then mine = true end
        end
    end
    local txt
    if #yes_ > 0 then txt = table.concat(yes_, "/") end
    if #no_ > 0 then
        local n = string.format(L.GUIDE_EXCEPT, table.concat(no_, ", "))
        txt = txt and (txt .. ", " .. n) or n
    end
    local applies = (not pos or mine) and not neg
    return colored(applies and HEX.tagMine or HEX.tag, "[" .. (txt or spec) .. "]"), applies
end

local cache, cacheN = {}, 0
function GD.ForgetParsed() cache, cacheN = {}, 0 end

-- etape -> { text, note, coords = { {x, y} }, conds = { {kind, id} } }
-- coordonnees en liens |Hcorpguide:i|h (clic : la fleche y va)
function GD.Parse(raw, who)
    local c = cache[raw]
    if c then return c end
    local d = GD.Data() or {}
    local Q, N, I, S = d.Q or {}, d.N or {}, d.I or {}, d.S or {}
    local st = { coords = {}, conds = {}, raw = raw }
    local seen = {}
    local last                -- dernier nom lu : legende des coordonnees qui suivent
    local function name(hex, txt)
        last = txt
        return colored(hex, txt)
    end
    local function cond(kind, id)
        local k = kind .. id
        if seen[k] then return end
        seen[k] = true
        st.conds[#st.conds + 1] = { kind, id }
    end
    local function render(s)
        return (s:gsub("{([^}]*)}", function(tok)
            local role, id = tok:match("^q([atox]?)(%d+)$")
            if id then
                id = tonumber(id)
                if role ~= "" then cond(role, id) end
                return name(HEX["q" .. role] or HEX.q, Q[id] or string.format(L.GUIDE_QUEST_ID, id))
            end
            local k, n = tok:match("^([nmi])(%d+)$")
            if k then
                n = tonumber(n)
                if k == "i" then return name(HEX.i, "[" .. (I[n] or "?") .. "]") end
                return name(HEX[k], N[n] or "?")
            end
            local learn, sp = tok:match("^s(l?)(%d+)$")
            if sp then
                sp = tonumber(sp)
                if learn == "l" then cond("l", sp) end
                return colored(HEX.s, "[" .. (S[sp] or "?") .. "]")
            end
            local x, y = tok:match("^@([%d.]+),([%d.]+)$")
            if x then
                st.coords[#st.coords + 1] = { tonumber(x), tonumber(y), last }
                return "|Hcorpguide:" .. #st.coords .. "|h" .. colored(HEX.xy, x .. ", " .. y) .. "|h"
            end
            local lv = tok:match("^v(%d+)$")
            if lv then
                cond("v", tonumber(lv))
                return ""
            end
            local kind, txt = tok:match("^(%a):(.*)$")
            if kind == "l" then return name(HEX.l, txt) end
            if kind == "N" then return name(HEX.n, txt) end
            if kind == "M" then return name(HEX.m, txt) end
            if kind == "I" then return name(HEX.i, "[" .. txt .. "]") end
            if kind == "S" then return colored(HEX.s, "[" .. txt .. "]") end
            if kind == "c" then
                local label, applies = tagLabel(txt, who)
                if applies == false then st.notForMe = true end
                return label
            end
            return ""
        end))
    end
    local body, note = raw:match("^(.-){!}(.*)$")
    st.text = render(body or raw)
    if note then st.note = render(note) end
    if cacheN > 600 then cache, cacheN = {}, 0 end
    cache[raw] = st
    cacheN = cacheN + 1
    return st
end

-- texte sans couleurs ni liens (infobulles, journal)
function GD.Plain(s)
    return (s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H[^|]*|h", ""):gsub("|h", "")
end

---------------------------------------------------------------------------
-- Conditions
---------------------------------------------------------------------------

local function inLog(id)
    local i = C_QuestLog and num(call(C_QuestLog.GetLogIndexForQuestID, id))
    return i ~= nil and i > 0
end
local function flagged(id)
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then return yes(call(C_QuestLog.IsQuestFlaggedCompleted, id)) end
    return yes(call(IsQuestFlaggedCompleted, id))
end
local function complete(id) return C_QuestLog and yes(call(C_QuestLog.IsComplete, id)) or false end
local function knows(id)
    if yes(call(IsPlayerSpell, id)) or yes(call(IsSpellKnown, id)) then return true end
    if C_SpellBook and C_SpellBook.IsSpellKnown and yes(call(C_SpellBook.IsSpellKnown, id)) then return true end
    -- numeros du site (Classic) differents de ceux du client : le nom
    local d = GD.Data()
    local name = d and d.S and d.S[id]
    if name and C_Spell and C_Spell.GetSpellInfo then
        local info = call(C_Spell.GetSpellInfo, name)
        if type(info) == "table" and num(info.spellID) then
            local sid = info.spellID
            return yes(call(IsPlayerSpell, sid)) or yes(call(IsSpellKnown, sid))
        end
    end
    return false
end
GD.InLog, GD.Flagged = inLog, flagged

local CHECK = {
    a = function(id) return inLog(id) or flagged(id) end,
    t = function(id) return flagged(id) end,
    o = function(id) return flagged(id) or (inLog(id) and complete(id)) end,
    x = function(id) return not inLog(id) end,
    l = function(id) return knows(id) end,
    v = function(n) local lv = num(call(UnitLevel, "player")) return lv ~= nil and lv >= n end,
}
GD.CHECK = CHECK

function GD.CondOk(c)
    local fn = CHECK[c[1]]
    return fn and fn(c[2]) or false
end

-- true : faite d apres le jeu ; false : pas encore ; nil : aucune condition
function GD.AutoDone(st)
    if #st.conds == 0 then return nil end
    for _, c in ipairs(st.conds) do
        if not GD.CondOk(c) then return false end
    end
    return true
end

-- quetes a rendre de l etape toutes rendues (il y en a au moins une)
local function turnedIn(st)
    local any = false
    for _, c in ipairs(st.conds) do
        if c[1] == "t" then
            if not GD.CondOk(c) then return false end
            any = true
        end
    end
    return any
end
GD.TurnedIn = turnedIn

---------------------------------------------------------------------------
-- Avancement
---------------------------------------------------------------------------

-- progression d un personnage dans un guide (CorpUIDB.guide.chars[perso].prog[cle])
function GD.Prog(char, key)
    char.prog = type(char.prog) == "table" and char.prog or {}
    local p = char.prog[key]
    if type(p) ~= "table" then
        p = { p = 1, s = 1, manual = {}, new = true }
        char.prog[key] = p
    end
    if type(p.manual) ~= "table" then p.manual = {} end
    p.p = math.max(1, floor(tonumber(p.p) or 1))
    p.s = math.max(1, floor(tonumber(p.s) or 1))
    return p
end

local function key(p, s) return p .. "." .. s end
GD.Key = key

function GD.StepAt(g, p, s)
    local e = GD.Stage(g, p)
    local raw = e and e[4][s]
    return raw and GD.Parse(raw, GD.who) or nil, e
end

function GD.Done(g, prog, p, s)
    if prog.manual[key(p, s)] then return true, "manual" end
    local st = GD.StepAt(g, p, s)
    if not st then return true end
    return GD.AutoDone(st) == true, "auto"
end

-- position suivante (p, s + 1), en passant a la partie suivante
local function nextPos(g, p, s)
    local e = GD.Stage(g, p)
    if e and s < #e[4] then return p, s + 1 end
    if p < #g.e then return p + 1, 1 end
    return nil
end
GD.NextPos = nextPos

local function prevPos(g, p, s)
    if s > 1 then return p, s - 1 end
    if p > 1 then
        local e = GD.Stage(g, p - 1)
        return p - 1, e and math.max(1, #e[4]) or 1
    end
    return nil
end
GD.PrevPos = prevPos

-- quetes deja rendues dans les etapes qui suivent : la plus lointaine de ces
-- etapes, et si elle est faite en entier (sinon on s y arrete : une suite a
-- prendre, par exemple)
local function turnedInAhead(g, p, s, n)
    local fp, fs, full
    local cp, cs = p, s
    for _ = 1, n do
        cp, cs = nextPos(g, cp, cs)
        if not cp then break end
        local st = GD.StepAt(g, cp, cs)
        if st and turnedIn(st) then fp, fs, full = cp, cs, GD.AutoDone(st) == true end
    end
    return fp, fs, full
end

-- avance la position tant que l etape en cours est faite ; renvoie p, s
-- (p > nombre de parties : guide fini)
function GD.Advance(g, prog)
    local p, s = prog.p, prog.s
    local guard = 0
    while guard < 6000 do
        guard = guard + 1
        local e = GD.Stage(g, p)
        if not e then break end
        if s > #e[4] then
            p, s = p + 1, 1
        elseif prog.hold == key(p, s) and not prog.manual[key(p, s)] then
            break
        elseif GD.Done(g, prog, p, s) then
            s = s + 1
        else
            local jp, js, full = turnedInAhead(g, p, s, GD.LOOKAHEAD)
            if not jp then break end
            p, s = jp, full and js + 1 or js
        end
    end
    if prog.hold and prog.hold ~= key(p, s) then prog.hold = nil end
    prog.p, prog.s = p, s
    return p, s
end

-- niveaux de chaque partie, lus dans son titre ("29 ...", "29-30 ...") ;
-- sans nombre : ceux de la partie d avant
local levels = {}
local function stageLevels(g)
    local t = levels[g.k]
    if t then return t end
    t = {}
    local lo, hi = 1, 1
    for p = 1, #g.e do
        local e = GD.Stage(g, p)
        local a, b = (e and e[1] or ""):match("^(%d+)%-?(%d*)")
        if a then
            lo = tonumber(a)
            hi = tonumber(b) or lo
        end
        t[p] = { lo, hi }
    end
    levels[g.k] = t
    return t
end
GD.StageLevels = stageLevels

-- capitales : on y passe sans y faire la partie de son niveau
local CITIES = { [1453] = true, [1454] = true, [1455] = true, [1456] = true, [1457] = true, [1458] = true }

-- cartes ou se trouve le joueur : la sienne et ses parents
function GD.PlayerZones()
    local list = {}
    local map = C_Map and num(call(C_Map.GetBestMapForUnit, "player"))
    local guard = 0
    while map and map > 0 and guard < 6 do
        list[map] = true
        local info = call(C_Map.GetMapInfo, map)
        map = type(info) == "table" and num(info.parentMapID) or nil
        guard = guard + 1
    end
    return list
end

-- Se placer dans le guide (premiere ouverture, bouton Recaler) :
--   depart : la partie de ton niveau dans la zone ou tu es (niveau - 2 a
--   niveau + 1, hors capitales), sinon la premiere partie qui commence au
--   niveau - 1 ;
--   puis, si plus loin : la derniere quete rendue des parties de ton niveau
--   ou d avant (sur son etape si elle n est pas faite en entier).
-- Renvoie le nombre d etapes passees et { quest, level, zone } (parties).
function GD.CatchUp(g, prog, level, zones)
    level = level or num(call(UnitLevel, "player")) or 1
    zones = zones or GD.PlayerZones()
    local lv = stageLevels(g)
    local qp, qs, full
    for p = 1, #g.e do
        if lv[p][1] <= level + 1 then
            local e = GD.Stage(g, p)
            for s = 1, e and #e[4] or 0 do
                local st = GD.Parse(e[4][s], GD.who)
                if turnedIn(st) then qp, qs, full = p, s, GD.AutoDone(st) == true end
            end
        end
    end
    local lp, zp
    for p = 1, #g.e do
        if not lp and lv[p][1] >= level - 1 then lp = p end
        local e = GD.Stage(g, p)
        if not zp and lv[p][1] >= level - 2 and lv[p][1] <= level + 1 and e and e[2] and zones[e[2]] and not CITIES[e[2]] then
            zp = p
        end
    end
    local sp = zp or lp or #g.e
    local before = GD.Index(g, math.min(prog.p, #g.e), math.min(prog.s, 99))
    prog.hold = nil
    prog.p, prog.s = sp, 1
    if qp and qp >= sp then
        if full then
            local np, ns_ = nextPos(g, qp, qs)
            prog.p, prog.s = np or (#g.e + 1), ns_ or 1
        else
            prog.p, prog.s = qp, qs
        end
    end
    GD.Advance(g, prog)
    return GD.Index(g, math.min(prog.p, #g.e), prog.s) - before, { quest = qp, level = lp, zone = zp }
end

-- etape en cours choisie a la main (elle reste tant qu elle n est pas cochee)
function GD.GoTo(g, prog, p, s)
    if not GD.Stage(g, p) then return end
    prog.p, prog.s = p, s
    prog.manual[key(p, s)] = nil
    prog.hold = key(p, s)
end

-- cocher l etape en cours et avancer
function GD.Validate(g, prog)
    local p, s = prog.p, prog.s
    if not GD.Stage(g, p) then return end
    prog.manual[key(p, s)] = true
    prog.hold = nil
    local np, ns_ = nextPos(g, p, s)
    prog.p, prog.s = np or (#g.e + 1), ns_ or 1
    GD.Advance(g, prog)
end

-- revenir a l etape d avant (decochee, gardee en cours)
function GD.Back(g, prog)
    local p, s = prevPos(g, math.min(prog.p, #g.e + 1), prog.s)
    if prog.p > #g.e then
        local e = GD.Stage(g, #g.e)
        p, s = #g.e, e and #e[4] or 1
    end
    if p then GD.GoTo(g, prog, p, s) end
end

-- cocher ou decocher une etape (fenetre)
function GD.Toggle(g, prog, p, s)
    local k = key(p, s)
    if prog.manual[k] then prog.manual[k] = nil else prog.manual[k] = true end
end

-- etapes faites d une partie (pour la liste)
function GD.StageDone(g, prog, p)
    local e = GD.Stage(g, p)
    local n = 0
    for s = 1, e and #e[4] or 0 do
        if (p < prog.p) or (p == prog.p and s < prog.s) or GD.Done(g, prog, p, s) then n = n + 1 end
    end
    return n, e and #e[4] or 0
end

---------------------------------------------------------------------------
-- Positions (repris du module Leveling)
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

-- position "monde" (continent, nord, ouest) d un point de carte (0-1)
local world, worldN = {}, 0
function GD.World(map, x, y)
    if not (map and x and y and C_Map and C_Map.GetWorldPosFromMapPos) then return nil end
    local k = map .. ":" .. floor(x * 10000) .. ":" .. floor(y * 10000)
    local c = world[k]
    if c then return c[1], c[2], c[3] end
    local cont, pos = call(C_Map.GetWorldPosFromMapPos, map, vector(x, y))
    cont = num(cont)
    local wx, wy = vecXY(pos)
    if not (cont and wx) then return nil end
    if worldN > 400 then world, worldN = {}, 0 end
    world[k] = { cont, wx, wy }
    worldN = worldN + 1
    return cont, wx, wy
end

-- le joueur : carte, x, y (0-1), position monde ; nil en instance
function GD.Player()
    if not C_Map then return nil end
    local map = num(call(C_Map.GetBestMapForUnit, "player"))
    if not map then return nil end
    local me = { map = map }
    local x, y = vecXY(call(C_Map.GetPlayerMapPosition, map, "player"))
    if x then
        me.x, me.y = x, y
        me.cont, me.wx, me.wy = GD.World(map, x, y)
    end
    return me
end

-- distance (metres) du joueur a un point ; nil : autre continent ou inconnu
function GD.Distance(me, a)
    if not (me and me.cont and a and a.map) then return nil end
    local cont, wx, wy = GD.World(a.map, a.x, a.y)
    if not cont or cont ~= me.cont then return nil end
    local dx, dy = wx - me.wx, wy - me.wy
    return sqrt(dx * dx + dy * dy), dx, dy
end
