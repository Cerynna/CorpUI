--[[--------------------------------------------------------------------------
    CorpUI - module Jeux : ce qui est commun aux mini-jeux

      - la liste des jeux : ns.Games.Register(cle, { title, open, close,
        shown }) ; open() rend true si le jeu s est ouvert ;
      - pendant un vol (taxi) : le jeu choisi s ouvre au decollage, et se
        referme a l atterrissage s il s etait ouvert tout seul (reglage) ;
        rien en combat ; deja en vol a la connexion : rien d office ;
      - ces reglages sont partages (CorpUIDB.games.taxi) et affiches dans le
        panneau de chaque jeu : ns.Games.TaxiOptions(form) ;
      - ns.Games.OnFlight(fn) : fn(true) au decollage, fn(false) a
        l atterrissage (servait au vol du griffon, desactive le 08/10).
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local Games = { list = {}, byKey = {} }
ns.Games = Games

local tdb    -- CorpUIDB.games.taxi = { game = cle ou "none", close = bool }
local flightFns = {}

function Games.Register(key, g)
    g.key = key
    table.insert(Games.list, g)
    Games.byKey[key] = g
end

-- fn(true) au decollage, fn(false) a l atterrissage (avant l ouverture ou
-- la fermeture du jeu choisi)
function Games.OnFlight(fn)
    table.insert(flightFns, fn)
end

-- liste "pendant un vol, ouvrir" + case "fermer a l atterrissage"
function Games.TaxiOptions(form)
    form:Select(L.GAMES_TAXI, function()
        local list = { { value = "none", text = L.GAMES_NONE } }
        for _, g in ipairs(Games.list) do table.insert(list, { value = g.key, text = g.title() }) end
        return list
    end, function() return tdb and tdb.game or "none" end, function(v) if tdb then tdb.game = v end end, 220)
    form:Check(L.GAMES_TAXI_CLOSE, function() return tdb and tdb.close end, function(v) if tdb then tdb.close = v end end)
end

-- en vol (taxi) ?
local function onTaxi()
    if not UnitOnTaxi then return false end
    local ok, v = pcall(UnitOnTaxi, "player")
    return ok and not (issecretvalue and issecretvalue(v)) and v == true
end

local flying = false
local byTaxi      -- jeu ouvert tout seul par ce vol
local function checkTaxi()
    if not tdb then return end
    local now = onTaxi()
    if now == flying then return end
    flying = now
    for _, fn in ipairs(flightFns) do pcall(fn, now) end
    if now then
        local g = Games.byKey[tdb.game]
        if g and not InCombatLockdown() and not g.shown() and g.open() then byTaxi = g end
    else
        if byTaxi and tdb.close and byTaxi.shown() then byTaxi.close() end
        byTaxi = nil
    end
end
Games._checkTaxi = checkTaxi

local ev = CreateFrame("Frame")
local acc = 0
ev:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.5 then return end
    acc = 0
    checkTaxi()
end)
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        if type(root.games) ~= "table" then root.games = {} end
        if type(root.games.taxi) ~= "table" then root.games.taxi = {} end
        tdb = root.games.taxi
        if type(tdb.game) ~= "string" then tdb.game = "murloc" end
        if tdb.close == nil then tdb.close = true end
        -- 08/10 : le vol du griffon est desactive ; qui l avait recu par
        -- defaut retrouve le murloc (une seule fois)
        if tdb.v ~= 3 then
            if tdb.game == "vol" then tdb.game = "murloc" end
            tdb.v = 3
        end
        flying = onTaxi()
    else
        C_Timer.After(0.3, checkTaxi)
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
