--[[--------------------------------------------------------------------------
    CorpUI - podometre : les kilometres parcourus font gagner des cartes
      - mesure : position du personnage (UnitPosition, lisible en combat,
        contrairement a la vitesse GetUnitSpeed) relevee 2 fois par
        seconde ; l ecart entre deux releves compte en "metres" du jeu (ceux
        qu affiche le client pour ses portees) ; repli sans UnitPosition :
        position sur la carte de la zone x taille de la carte ;
      - jamais compte : taxi, transport (bateau, zeppelin : on ne bouge pas
        soi-meme), teleportation (plus de 30 m/s), changement de carte,
        absent (AFK), vehicule ;
      - compte a part : a pied, a la nage, en monture, en fantome ;
      - compte (tous les personnages) : jour, semaine (du lundi), mois,
        annee, total ; chaque personnage garde ses km par jour et son total ;
      - paliers -> boosters (Cartes.lua tire les cartes, Classeur.lua les
        montre) ; trophees selon les distances (Cartes.lua) ;
      - guilde (joueurs CorpUI) : km de la semaine et classeur partages
        (option), message "PEDO" (ns.Comm), reponse en prive a une demande.
    Rien de protege, aucun crochet : nos cadres seulement.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

ns.Pedo = ns.Pedo or {}
local P = ns.Pedo

local issecret = issecretvalue or function() return false end

local TICK = 0.5          -- releve de position (s)
local MAX_SPEED = 30      -- m/s : au-dela, teleportation (ou chute, saut de carte)
local MIN_STEP = 0.05     -- immobile en dessous
local MAX_GAP = 5         -- releves trop espaces (ecran de chargement) : on repart
local KM = 1000
local SHARE_EVERY = 600   -- partage avec la guilde : toutes les 10 min si change
local REPLY_GAP = 60
local GUILD_KEEP = 30 * 86400

-- paliers (km du jeu) et booster gagne ; un palier ne se gagne qu une fois
-- par periode (jour, semaine...) ; ceux du total, une fois pour toutes
P.MILESTONES = {
    day = { { 2, "normal" }, { 5, "normal" }, { 10, "normal" }, { 21.1, "rare" }, { 42.195, "epic" } },
    week = { { 50, "normal" }, { 100, "rare" }, { 200, "epic" } },
    month = { { 200, "rare" }, { 500, "epic" }, { 1000, "legendary" } },
    year = { { 2000, "epic" }, { 5000, "legendary" }, { 10000, "legendary" } },
    total = { { 1, "normal" }, { 10, "normal" }, { 42.195, "rare" }, { 100, "rare" }, { 500, "epic" },
              { 775, "epic" }, { 1000, "epic" }, { 3500, "legendary" }, { 10000, "legendary" }, { 40075, "legendary" } },
}
P.PERIODS = { "day", "week", "month", "year" }
P.MODES = { "f", "s", "m", "g" }     -- a pied, nage, monture, fantome

-- equivalences reelles (km) pour les statistiques
P.EQUIV = {
    { 5, "PEDO_EQ_5" }, { 21.1, "PEDO_EQ_HALF" }, { 42.195, "PEDO_EQ_MARATHON" }, { 100, "PEDO_EQ_100" },
    { 465, "PEDO_EQ_LYON" }, { 775, "PEDO_EQ_MARSEILLE" }, { 1000, "PEDO_EQ_1000" },
    { 3500, "PEDO_EQ_TDF" }, { 5837, "PEDO_EQ_NEWYORK" }, { 40075, "PEDO_EQ_EARTH" }, { 384400, "PEDO_EQ_MOON" },
}

local db             -- CorpUIDB.pedometer (compte)
local me             -- db.chars[cle du personnage]

---------------------------------------------------------------------------
-- Valeurs sures
---------------------------------------------------------------------------

local function num(v)
    if v == nil or issecret(v) or type(v) ~= "number" then return nil end
    return v
end

-- drapeau (UnitOnTaxi, IsSwimming...) : nil si absent ou illisible
local function flag(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or issecret(v) then return nil end
    return v and true or false
end

---------------------------------------------------------------------------
-- Dates : jour, semaine (lundi), mois, annee
---------------------------------------------------------------------------

local function keysAt(t)
    local d = date("*t", t)
    -- midi : un changement d heure ne decale jamais d un jour
    local noon = time({ year = d.year, month = d.month, day = d.day, hour = 12 })
    local back = (d.wday + 5) % 7          -- lundi = 0 ... dimanche = 6
    local monday = noon - back * 86400
    return {
        day = string.format("%04d-%02d-%02d", d.year, d.month, d.day),
        week = date("%Y-%m-%d", monday),
        month = string.format("%04d-%02d", d.year, d.month),
        year = string.format("%04d", d.year),
        monday = monday, noon = noon,
    }
end
P.KeysAt = keysAt

local function dayYards(dk)
    local e = db and db.days[dk]
    if type(e) ~= "table" then return 0 end
    local s = 0
    for _, m in ipairs(P.MODES) do s = s + (tonumber(e[m]) or 0) end
    return s
end

local function periodSum(kind, K)
    if kind == "day" then return dayYards(K.day) end
    if kind == "week" then
        local s = 0
        for i = 0, 6 do s = s + dayYards(date("%Y-%m-%d", K.monday + i * 86400)) end
        return s
    end
    local prefix = kind == "month" and K.month or K.year
    local s = 0
    for dk in pairs(db.days) do
        if type(dk) == "string" and dk:sub(1, #prefix) == prefix then s = s + dayYards(dk) end
    end
    return s
end

-- sommes des periodes en cours, refaites quand la periode change
local cache = {}
local function refreshCache(K)
    for _, kind in ipairs(P.PERIODS) do
        local c = cache[kind]
        if not c or c.k ~= K[kind] then cache[kind] = { k = K[kind], y = periodSum(kind, K) } end
    end
end

local function totalYards()
    local s = 0
    for _, m in ipairs(P.MODES) do s = s + (tonumber(db.total[m]) or 0) end
    return s
end

-- distances du compte (metres du jeu) : day, week, month, year, total
function P.Totals()
    if not db then return { day = 0, week = 0, month = 0, year = 0, total = 0 } end
    local K = keysAt(time())
    refreshCache(K)
    return {
        day = cache.day.y, week = cache.week.y, month = cache.month.y, year = cache.year.y,
        total = totalYards(), keys = K,
    }
end

-- etat pour les trophees
function P.Snapshot()
    local T = P.Totals()
    local ownPool, allPool = 0, 0
    if P.OwnedCount then ownPool, allPool = P.OwnedCount(true) end
    return {
        day = T.day, week = T.week, month = T.month, year = T.year, total = T.total,
        foot = db.total.f or 0, swim = db.total.s or 0, mount = db.total.m or 0, ghost = db.total.g or 0,
        ownedPool = ownPool, pool = allPool,
    }
end

-- km d un jour (compte), par mode ou en tout
function P.DayYards(dk, mode)
    if mode then
        local e = db and db.days[dk]
        return type(e) == "table" and (tonumber(e[mode]) or 0) or 0
    end
    return dayYards(dk)
end

---------------------------------------------------------------------------
-- Texte des distances
---------------------------------------------------------------------------

function P.Km(yards, decimals)
    local v = (yards or 0) / KM
    local s
    if decimals == 0 or v >= 1000 then
        s = tostring(math.floor(v + 0.5))
        -- separateur de milliers
        local sep = L.PEDO_THOUSANDS or " "
        s = s:reverse():gsub("(%d%d%d)", "%1" .. sep:reverse()):reverse()
        if s:sub(1, #sep) == sep then s = s:sub(#sep + 1) end
    else
        s = string.format("%." .. (decimals or 1) .. "f", v)
        if (L.PEDO_DECIMAL or ".") ~= "." then s = s:gsub("%.", L.PEDO_DECIMAL) end
    end
    return s .. " " .. L.PEDO_KM
end

local function kmValue(k)
    -- un palier (km) affiche : 42,195 -> "42,2" ; 1000 -> "1 000"
    return P.Km(k * KM, (k % 1 == 0) and 0 or 1)
end
P.KmValue = kmValue

---------------------------------------------------------------------------
-- Annonces (Classeur.lua pose P.Announce) et son
---------------------------------------------------------------------------

function P.Sound(key)
    if db and db.opt.sound and ns.PlaySoundKey then pcall(ns.PlaySoundKey, key) end
end

local listeners = {}
function P.Listen(fn) listeners[#listeners + 1] = fn end
function P.Changed(what)
    for _, fn in ipairs(listeners) do pcall(fn, what) end
end

---------------------------------------------------------------------------
-- Paliers et boosters
---------------------------------------------------------------------------

-- texte de la raison d un booster
function P.WhyText(pack)
    if not pack then return "" end
    if pack.p == "welcome" then return L.PEDO_WHY_WELCOME end
    local fmt = L["PEDO_WHY_" .. string.upper(pack.p or "")]
    if not fmt then return "" end
    return string.format(fmt, kmValue(pack.d or 0))
end

local function givePack(kind, period, kmv)
    local pack = { k = kind, p = period, d = kmv, t = time() }
    table.insert(db.packs, pack)
    if P.Announce then P.Announce("pack", pack) end
    P.Changed("pack")
end
P._givePack = function(...) if db then givePack(...) end end

local function checkMilestones(K)
    refreshCache(K)
    for _, kind in ipairs(P.PERIODS) do
        local per = db.per[kind]
        if type(per) ~= "table" or per.k ~= K[kind] then
            per = { k = K[kind], got = {} }
            db.per[kind] = per
        end
        if type(per.got) ~= "table" then per.got = {} end
        for i, ms in ipairs(P.MILESTONES[kind]) do
            if not per.got[i] and cache[kind].y >= ms[1] * KM then
                per.got[i] = true
                givePack(ms[2], kind, ms[1])
            end
        end
    end
    local tot = totalYards()
    for i, ms in ipairs(P.MILESTONES.total) do
        if not db.totalGot[i] and tot >= ms[1] * KM then
            db.totalGot[i] = true
            givePack(ms[2], "total", ms[1])
        end
    end
    if P.CheckTrophies then P.CheckTrophies() end
end

-- prochain palier d une periode : km, booster, ou nil
function P.NextMilestone(kind)
    local T = P.Totals()
    local y = T[kind] or 0
    for _, ms in ipairs(P.MILESTONES[kind] or {}) do
        if y < ms[1] * KM then return ms[1], ms[2], y end
    end
end

---------------------------------------------------------------------------
-- Compte des distances
---------------------------------------------------------------------------

local function round2(v) return math.floor(v * 100 + 0.5) / 100 end

local function add(mode, yd)
    local K = keysAt(time())
    refreshCache(K)
    local e = db.days[K.day]
    if type(e) ~= "table" then e = {} db.days[K.day] = e end
    e[mode] = round2((tonumber(e[mode]) or 0) + yd)
    db.total[mode] = round2((tonumber(db.total[mode]) or 0) + yd)
    if me then
        me.total = round2((tonumber(me.total) or 0) + yd)
        me.days[K.day] = round2((tonumber(me.days[K.day]) or 0) + yd)
    end
    for _, kind in ipairs(P.PERIODS) do cache[kind].y = cache[kind].y + yd end
    if cache.day.y > (tonumber(db.best.y) or 0) then
        db.best.y = round2(cache.day.y)
        db.best.k = K.day
    end
    checkMilestones(K)
end
P._add = function(mode, yd) if db then add(mode, yd) end end

---------------------------------------------------------------------------
-- Mesure
---------------------------------------------------------------------------

local last                -- dernier releve { y, x, w, t }
local skipped = {}        -- raison -> nombre (diag)
local lastSource

local function skip(why) skipped[why] = (skipped[why] or 0) + 1 end

-- position en metres du jeu, et ou (monde / carte) : on ne compare que
-- deux releves du meme endroit
local function position()
    local ok, py, px, _, inst = pcall(UnitPosition, "player")
    if ok and num(py) and num(px) then
        lastSource = "unit"
        return py, px, "w" .. tostring(num(inst) or 0)
    end
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition and C_Map.GetMapWorldSize) then return end
    local okM, map = pcall(C_Map.GetBestMapForUnit, "player")
    map = okM and num(map) or nil
    if not map then return end
    local okP, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if not okP or type(pos) ~= "table" then return end
    local okX, mx, my = pcall(pos.GetXY, pos)
    local okS, w, h = pcall(C_Map.GetMapWorldSize, map)
    mx, my, w, h = okX and num(mx), okX and num(my), okS and num(w), okS and num(h)
    if not (mx and my and w and h) or w <= 0 or h <= 0 then return end
    lastSource = "map"
    return my * h, mx * w, "m" .. map
end

-- facon de se deplacer : f, s, m, g ; nil et la raison si ca ne compte pas
local function moveMode()
    if flag(UnitOnTaxi, "player") then return nil, "taxi" end
    if flag(UnitInVehicle, "player") then return nil, "vehicle" end
    if flag(UnitIsAFK, "player") then return nil, "afk" end
    if flag(UnitIsGhost, "player") then return "g" end
    if flag(IsSwimming) then return "s" end
    if flag(IsMounted) then return "m" end
    return "f"
end

local function step(now)
    local y, x, where = position()
    if not y then
        skip("nopos")
        last = nil
        return
    end
    local prev = last
    local moving = flag(IsPlayerMoving)
    last = { y = y, x = x, w = where, t = now, mv = moving }
    if not prev then return end
    if prev.w ~= where then skip("map") return end
    local dt = now - prev.t
    if dt <= 0 or dt > MAX_GAP then skip("gap") return end
    local dx, dy = x - prev.x, y - prev.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d < MIN_STEP then return end
    if d / dt > MAX_SPEED then skip("jump") return end
    local mode, why = moveMode()
    if not mode then skip(why) return end
    -- porte par un bateau, un zeppelin, un ascenseur : on ne bouge pas soi-meme
    -- (immobile aux deux releves : l arret en cours de pas reste compte)
    if moving == false and prev.mv == false and flag(IsFalling) ~= true then skip("carried") return end
    add(mode, d)
end
P._step = step
P._reset = function() last = nil skipped = {} end

local driver = CreateFrame("Frame")
local acc, shareAcc = 0, 0
driver:SetScript("OnUpdate", function(_, dt)
    if not db then return end
    acc = acc + dt
    shareAcc = shareAcc + dt
    if acc >= TICK then
        acc = 0
        step(GetTime())
    end
    if shareAcc >= 30 then
        shareAcc = 0
        if P.MaybeShare then P.MaybeShare() end
    end
end)

---------------------------------------------------------------------------
-- Guilde : km de la semaine et classeur des joueurs CorpUI
---------------------------------------------------------------------------

local Comm
local lastShare, lastSig = -SHARE_EVERY, nil
local replied = {}

local function signature()
    local T = P.Totals()
    local own = P.OwnedCount and P.OwnedCount() or 0
    return T.keys.week .. ":" .. math.floor(T.week / 100) .. ":" .. own
end

local function payload(ask)
    local T = P.Totals()
    local own = P.OwnedCount and P.OwnedCount() or 0
    local _, class = UnitClass("player")
    return table.concat({ "1", T.keys.week, math.floor(T.week), math.floor(T.total), own,
        P.OwnedBits and P.OwnedBits() or "", class or "", ask and "1" or "0" }, ";")
end

local function inGuild()
    local ok, v = pcall(IsInGuild)
    return ok and not issecret(v) and v and true or false
end

function P.Share(ask)
    if not db or not db.opt.share or not Comm or not inGuild() then return false end
    if InCombatLockdown() then return false end
    local sent = Comm.Send("PEDO", payload(ask), "GUILD")
    if sent then
        lastShare = GetTime()
        lastSig = signature()
    end
    return sent
end

function P.MaybeShare()
    if not db or not db.opt.share then return end
    if GetTime() - lastShare < SHARE_EVERY then return end
    if signature() == lastSig then return end
    P.Share(false)
end

local function onPedo(sender, data, channel)
    if not db or type(sender) ~= "string" or type(data) ~= "string" then return end
    local f = {}
    for part in (data .. ";"):gmatch("([^;]*);") do f[#f + 1] = part end
    if f[1] ~= "1" then return end
    local week = f[2]
    if type(week) ~= "string" or not week:match("^%d%d%d%d%-%d%d%-%d%d$") then return end
    local wy, ty, own = tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
    if not (wy and ty and own) then return end
    local bits = f[6] or ""
    if #bits > 128 or not bits:match("^[0-9a-f]*$") then bits = "" end
    local class = (f[7] or ""):match("^[A-Z]+$")
    db.guild[sender] = {
        w = week, wy = math.max(0, wy), ty = math.max(0, ty), c = math.max(0, own),
        b = bits, cl = class, at = time(),
    }
    P.Changed("guild")
    -- une demande (connexion) : notre fiche en prive, une fois par minute
    if f[8] == "1" and channel ~= "WHISPER" and db.opt.share then
        local t = GetTime()
        if not replied[sender] or t - replied[sender] > REPLY_GAP then
            replied[sender] = t
            if Comm and not InCombatLockdown() then Comm.Send("PEDO", payload(false), "WHISPER", sender) end
        end
    end
end

-- fiches de la guilde : { name, week (m), total (m), cards, bits, class, me }
function P.GuildBoard()
    local list = {}
    if not db then return list end
    local T = P.Totals()
    local own = P.OwnedCount and P.OwnedCount() or 0
    local _, myClass = UnitClass("player")
    table.insert(list, { name = UnitName("player"), week = T.week, total = T.total, cards = own,
        class = myClass, me = true })
    for sender, e in pairs(db.guild) do
        if type(e) == "table" then
            table.insert(list, {
                name = sender, week = (e.w == T.keys.week) and (e.wy or 0) or 0, total = e.ty or 0,
                cards = e.c or 0, bits = e.b, class = e.cl, at = e.at,
            })
        end
    end
    table.sort(list, function(a, b)
        if a.week ~= b.week then return a.week > b.week end
        return (a.name or "") < (b.name or "")
    end)
    return list
end

---------------------------------------------------------------------------
-- Barre d infos (Infos.lua : element "pas")
---------------------------------------------------------------------------

function P.InfoText()
    if not db then return nil end
    local T = P.Totals()
    local s = "|cffffffff" .. P.Km(T.day) .. "|r"
    if #db.packs > 0 then s = s .. " |cffffd100(" .. #db.packs .. ")|r" end
    return s
end

function P.InfoTip(t)
    if not db then return end
    local T = P.Totals()
    local C = ns.COLORS
    t:AddLine(L.PEDO_TITLE, C.gold[1], C.gold[2], C.gold[3])
    for _, kind in ipairs({ "day", "week", "month", "year" }) do
        t:AddDoubleLine(L["PEDO_P_" .. string.upper(kind)], P.Km(T[kind]), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    t:AddDoubleLine(L.PEDO_P_TOTAL, P.Km(T.total), 0.8, 0.8, 0.8, 1, 1, 1)
    local nk, kind = P.NextMilestone("day")
    if nk then
        t:AddLine(" ")
        t:AddLine(string.format(L.PEDO_NEXT_DAY, kmValue(nk), P.Km(nk * KM - T.day), L["PEDO_PACK_" .. string.upper(kind)]),
            0.6, 0.8, 1, true)
    end
    if #db.packs > 0 then
        t:AddLine(string.format(L.PEDO_PACKS_WAITING, #db.packs), 1, 0.82, 0)
    end
    local own, all = P.OwnedCount()
    t:AddLine(string.format(L.PEDO_COLLECTION, own, all), 0.8, 0.8, 0.8)
end

---------------------------------------------------------------------------
-- Diagnostic : /corp podometre diag
---------------------------------------------------------------------------

local function diag()
    local say = ns.Chat
    local ok, py, px, pz, inst = pcall(UnitPosition, "player")
    say(L.PEDO_TITLE .. " - diag")
    say("  UnitPosition : " .. (ok and (tostring(issecret(py) and "secret" or py) .. ", " ..
        tostring(issecret(px) and "secret" or px) .. " (" .. tostring(inst) .. ")") or "erreur"))
    local map = C_Map and C_Map.GetBestMapForUnit and select(2, pcall(C_Map.GetBestMapForUnit, "player"))
    say("  carte : " .. tostring(map) .. "   source : " .. tostring(lastSource))
    say(string.format("  taxi %s  vehicule %s  absent %s  fantome %s  nage %s  monture %s  bouge %s",
        tostring(flag(UnitOnTaxi, "player")), tostring(flag(UnitInVehicle, "player")), tostring(flag(UnitIsAFK, "player")),
        tostring(flag(UnitIsGhost, "player")), tostring(flag(IsSwimming)), tostring(flag(IsMounted)),
        tostring(flag(IsPlayerMoving))))
    local T = P.Totals()
    local K = T.keys
    say(string.format("  jour %s  semaine %s  mois %s  annee %s  total %s",
        P.Km(T.day, 2), P.Km(T.week, 2), P.Km(T.month, 2), P.Km(T.year, 2), P.Km(T.total, 2)))
    say(string.format("  aujourd hui : pied %s  nage %s  monture %s  fantome %s",
        P.Km(P.DayYards(K.day, "f"), 2), P.Km(P.DayYards(K.day, "s"), 2), P.Km(P.DayYards(K.day, "m"), 2),
        P.Km(P.DayYards(K.day, "g"), 2)))
    local parts = {}
    for why, n in pairs(skipped) do parts[#parts + 1] = why .. "=" .. n end
    say("  ecartes : " .. (#parts > 0 and table.concat(parts, " ") or "-"))
    -- cartes ecartees (inconnues de ce client)
    if P.BuildPool then P.BuildPool() end
    local missing = {}
    for _, c in ipairs(P.CATALOG or {}) do
        if not P.IsValid(c.id) then missing[#missing + 1] = c.id end
    end
    local own, all = P.OwnedCount()
    say(string.format("  cartes : %d / %d   boosters en attente : %d   eclats : %d", own, all, #db.packs, db.shards or 0))
    say("  cartes inconnues du client : " .. (#missing > 0 and table.concat(missing, " ") or "aucune"))
end

---------------------------------------------------------------------------
-- Reglages (/corp podometre options, page Jeux)
---------------------------------------------------------------------------

local panel

local function buildPanel()
    panel = ns.UI.Window("CorpUIPedometerOptions", ns.TITLE .. " - " .. L.MOD_PEDO, nil, 440, 360)
    local icon = panel:CreateTexture(nil, "ARTWORK")
    icon:SetSize(64, 89)
    icon:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -36)
    icon:SetTexture(ns.MEDIA .. "Podometre\\booster")
    icon:SetTexCoord(0, 1, 0, 392 / 512)
    local desc = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -2)
    desc:SetWidth(350)
    desc:SetJustifyH("LEFT")
    desc:SetText(L.PEDO_HINT)
    local stats = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    stats:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -8)
    stats:SetWidth(350)
    stats:SetJustifyH("LEFT")
    local open = ns.UI.Button(panel, L.PEDO_OPEN, 140, function() if P.ToggleBinder then P.ToggleBinder(true) end end)
    open:SetPoint("TOPLEFT", stats, "BOTTOMLEFT", 0, -8)
    local form = ns.UI.Form(panel, -150, function() end)
    form:Check(L.PEDO_OPT_TOAST, function() return db.opt.toast end, function(v) db.opt.toast = v end)
    form:Check(L.PEDO_OPT_SOUND, function() return db.opt.sound end, function(v) db.opt.sound = v end)
    form:Check(L.PEDO_OPT_SHARE, function() return db.opt.share end, function(v)
        db.opt.share = v
        if v then P.Share(false) end
    end)
    ns.Games.TaxiOptions(form)
    local foot = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    foot:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, form.y - 6)
    foot:SetWidth(424)
    foot:SetJustifyH("LEFT")
    foot:SetText(L.PEDO_FOOT)
    table.insert(form.refreshers, function()
        local T = P.Totals()
        local own, all = P.OwnedCount()
        stats:SetText(string.format(L.PEDO_PANEL_STATS, P.Km(T.day), P.Km(T.total), own, all))
    end)
    panel:HookScript("OnShow", function() form:Refresh() end)
end

local function openPanel()
    if not db then return end
    if not panel then buildPanel() end
    ns.ShowPanel(panel)
end

-- bouton cache, cible du clic de la barre d infos (clic "click" securise)
local toggleBtn = CreateFrame("Button", "CorpUIPedometerToggle", UIParent)
toggleBtn:Hide()
toggleBtn:SetScript("OnClick", function() if P.ToggleBinder then P.ToggleBinder() end end)

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

local function initDB(root)
    if type(root.pedometer) ~= "table" then root.pedometer = {} end
    local d = root.pedometer
    for _, k in ipairs({ "days", "total", "chars", "per", "totalGot", "packs", "cards", "newCards", "guild", "opt" }) do
        if type(d[k]) ~= "table" then d[k] = {} end
    end
    d.shards = tonumber(d.shards) or 0
    d.opened = tonumber(d.opened) or 0
    if type(d.best) ~= "table" then d.best = { y = 0 } end
    for _, m in ipairs(P.MODES) do d.total[m] = tonumber(d.total[m]) or 0 end
    if d.opt.toast == nil then d.opt.toast = true end
    if d.opt.sound == nil then d.opt.sound = true end
    if d.opt.share == nil then d.opt.share = true end
    -- fiches de guilde trop vieilles
    local now = time()
    for k, e in pairs(d.guild) do
        if type(e) ~= "table" or not tonumber(e.at) or now - e.at > GUILD_KEEP then d.guild[k] = nil end
    end
    return d
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if ns.ModuleOff("podometre", ev) then
        driver:SetScript("OnUpdate", nil)
        return
    end
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        db = initDB(root)
        P.db = db
        local key = ns.CharKey()
        if type(db.chars[key]) ~= "table" then db.chars[key] = {} end
        me = db.chars[key]
        if type(me.days) ~= "table" then me.days = {} end
        me.name = UnitName("player")
        local _, class = UnitClass("player")
        me.class = class
        -- bienvenue : un premier booster pour decouvrir le classeur
        if not db.welcome then
            db.welcome = true
            givePack("normal", "welcome", 0)
        end
        if P.BuildPool then P.BuildPool() end
        checkMilestones(keysAt(time()))
        Comm = ns.Comm
        if Comm and Comm.On then Comm.On("PEDO", onPedo) end
        C_Timer.After(25, function() P.Share(true) end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        last = nil
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD" }) do
    pcall(ev.RegisterEvent, ev, e)
end

-- liste des jeux : le classeur peut s ouvrir pendant un vol (Jeux.lua)
if ns.Games and ns.Games.Register then
    ns.Games.Register("classeur", {
        title = function() return L.PEDO_BINDER end,
        open = function()
            if not db or not P.ToggleBinder then return false end
            P.ToggleBinder(true)
            return true
        end,
        close = function() if P.CloseBinder then P.CloseBinder() end end,
        shown = function() return P.BinderShown and P.BinderShown() or false end,
    })
end

ns.RegisterModule({
    command = "podometre",
    alias = "classeur",
    panelName = "CorpUIPedometerOptions",
    icon = ns.MEDIA .. "Podometre\\booster",
    title = function() return L.MOD_PEDO end,
    desc = function() return L.PEDO_DESC end,
    Slash = function(rest)
        rest = strlower(strtrim(rest or ""))
        if not db then return end
        if rest == "diag" then diag()
        elseif rest == "options" or rest == "config" then openPanel()
        else if P.ToggleBinder then P.ToggleBinder() end end
    end,
    Open = openPanel,
})
