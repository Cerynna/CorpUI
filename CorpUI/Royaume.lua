--[[--------------------------------------------------------------------------
    CorpUI - royaume vide du 21/11 : cles refondues (une fois)

    Le 21/11, le jeu s est mis a rendre un royaume vide (GetRealmName() ==
    ""). Les donnees par personnage ("Nom-Royaume") et par royaume
    ("Royaume-Faction") ont alors ete ecrites sous de nouvelles cles :
    "Hysterias-" a cote de "Hysterias-<royaume>", "-Alliance" a cote de
    "<royaume>-Alliance". Chaque personnage semblait nouveau : or compte
    deux fois, base de prix et compta de l HV coupees, clics de soin,
    podometre, recharges, recettes connues... en double.

    ns.RealmName (Core.lua) garde desormais le dernier royaume connu. Ici,
    une seule fois (CorpUIDB.realmFix) : les cles "Nom-" et "-Faction" de
    toute la sauvegarde sont refondues dans leurs cles d avant, et les
    valeurs "Nom-" (personnage d une operation de la compta) corrigees.
    Royaume d avant : CorpUIDB.realmName, sinon celui du personnage vu le
    plus recemment dans CorpUIDB.alts.

    Fusion quand les deux cles existent (le nouveau = depuis le 21/11) :
    - alts : le nouveau, complete par l ancien ; royaume remis ;
    - auction.gold : les deux series de releves, dans l ordre ;
    - auction.realms : par objet, le releve le plus recent ;
    - auction.ledger : operations bout a bout, factures vues reunies ;
    - pedometer.chars : pas additionnes (total et par jour) ;
    - cd.chars : sorts appris reunis ;
    - clickcast : l ancien (vos raccourcis ; le nouveau = ceux par defaut) ;
    - setupPending : l ancien (pas d assistant pour un faux nouveau perso) ;
    - notes.chars : le nouveau, sans perdre une note ancienne ;
    - le reste : le nouveau, complete par l ancien (profil compris : le
      personnage garde celui qu il a depuis le 21/11).
----------------------------------------------------------------------------]]

local _, ns = ...

local FACTIONS = { Alliance = true, Horde = true, Neutral = true }
local MAX_DEPTH = 8

local function str(v)
    if type(v) == "string" and v ~= "" then return v end
end

-- a, complete par les champs de b qu il n a pas
local function fill(a, b)
    for k, v in pairs(b) do
        if a[k] == nil then a[k] = v end
    end
    return a
end

-- le nouveau gagne ; deux tables : le nouveau complete par l ancien
local function prefer(old, new)
    if new == nil then return old end
    if type(new) == "table" and type(old) == "table" then return fill(new, old) end
    return new
end

local function both(old, new)
    return type(old) == "table" and type(new) == "table"
end

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function maxNum(a, b)
    a, b = tonumber(a), tonumber(b)
    if a and b then return math.max(a, b) end
    return a or b
end

-- jour d un releve de prix ("prix,nombre,jour36,...")
local function dayOf(s)
    local d = type(s) == "string" and s:match("^%w+,%w+,(%w+),")
    return d and tonumber(d, 36)
end

local MERGE = {}

MERGE["alts"] = function(old, new, realm)
    local r = prefer(old, new)
    if type(r) == "table" then r.realm = realm end
    return r
end

MERGE["auction.gold"] = function(old, new)
    if not both(old, new) then return prefer(old, new) end
    local all = {}
    for _, p in ipairs(old) do if type(p) == "table" then all[#all + 1] = p end end
    for _, p in ipairs(new) do if type(p) == "table" then all[#all + 1] = p end end
    table.sort(all, function(a, b) return (tonumber(a[1]) or 0) < (tonumber(b[1]) or 0) end)
    return all
end

MERGE["auction.realms"] = function(old, new)
    if not both(old, new) then return prefer(old, new) end
    local items = {}
    if type(old.items) == "table" then
        for k, v in pairs(old.items) do items[k] = v end
    end
    if type(new.items) == "table" then
        for k, v in pairs(new.items) do
            local a, b = dayOf(items[k]), dayOf(v)
            if items[k] == nil or not a or not b or b >= a then items[k] = v end
        end
    end
    local r = fill(new, old)
    r.items = items
    r.nItems = count(items)
    r.lastScan = maxNum(old.lastScan, new.lastScan)
    r.lastReq = maxNum(old.lastReq, new.lastReq)
    return r
end

MERGE["auction.ledger"] = function(old, new)
    if not both(old, new) then return prefer(old, new) end
    local seen = {}
    if type(old.seen) == "table" then for k, v in pairs(old.seen) do seen[k] = v end end
    if type(new.seen) == "table" then for k, v in pairs(new.seen) do seen[k] = v end end
    local tx = {}
    if type(old.tx) == "table" then for _, x in ipairs(old.tx) do tx[#tx + 1] = x end end
    if type(new.tx) == "table" then for _, x in ipairs(new.tx) do tx[#tx + 1] = x end end
    local r = fill(new, old)
    r.seen, r.tx = seen, tx
    return r
end

MERGE["pedometer.chars"] = function(old, new)
    if not both(old, new) then return prefer(old, new) end
    local days = {}
    if type(old.days) == "table" then for k, v in pairs(old.days) do days[k] = v end end
    if type(new.days) == "table" then
        for k, v in pairs(new.days) do days[k] = (tonumber(days[k]) or 0) + (tonumber(v) or 0) end
    end
    local total = (tonumber(old.total) or 0) + (tonumber(new.total) or 0)
    local r = fill(new, old)
    r.days, r.total = days, total
    return r
end

MERGE["cd.chars"] = function(old, new)
    if not both(old, new) then return prefer(old, new) end
    local learned = prefer(old.learned, new.learned)
    local r = fill(new, old)
    r.learned = learned
    return r
end

MERGE["clickcast"] = function(old, new)
    if old ~= nil then return old end
    return new
end

MERGE["setupPending"] = function(old)
    return old
end

MERGE["notes.chars"] = function(old, new)
    if not both(old, new) then return prefer(old, new) end
    local keep = str(old.personal)
    local r = fill(new, old)
    if not str(r.personal) and keep then r.personal = keep end
    return r
end

-- reglage d un profil range : meme regle qu a la racine
local function policy(path)
    local fn = MERGE[path]
    if fn then return fn end
    local rest = path:match("^profiles%.[^%.]+%.(.+)$")
    return rest and MERGE[rest]
end

-- nouvelle cle -> cle d avant (nil : pas concernee)
local function target(k, names, realm)
    if type(k) ~= "string" then return nil end
    local name = k:match("^(.+)%-$")
    if name and names[name] then return name .. "-" .. realm end
    local f = k:match("^%-(%a+)$")
    if f and FACTIONS[f] then return realm .. "-" .. f end
    return nil
end

local function oldRealm(db)
    local r = str(db.realmName)
    if r then return r end
    local best, bestT
    if type(db.alts) == "table" then
        for k, d in pairs(db.alts) do
            local realm = type(d) == "table" and str(d.realm)
            if realm and type(k) == "string" and k:sub(-(#realm + 1)) == "-" .. realm then
                local t = tonumber(d.lastSeen) or 0
                if not bestT or t > bestT then best, bestT = realm, t end
            end
        end
    end
    return best
end

-- personnages ecrits sous "Nom-" (vus depuis le 21/11)
local function newNames(db)
    local names, any = {}, false
    for _, t in ipairs({ db.alts, type(db.account) == "table" and db.account.chars or nil }) do
        if type(t) == "table" then
            for k in pairs(t) do
                local name = type(k) == "string" and k:match("^(.+)%-$")
                if name then names[name], any = true, true end
            end
        end
    end
    return names, any
end

function ns.FixRealmKeys(db)
    if type(db) ~= "table" or db.realmFix then return end
    local realm = oldRealm(db)
    if not realm then
        -- aucun royaume connu (installe apres le 21/11) : rien a refondre
        db.realmFix = 1
        return
    end
    db.realmName = realm
    local names = newNames(db)
    -- cles a deplacer, des plus profondes aux moins profondes
    local moves, visited = {}, {}
    local function walk(t, path, depth)
        if depth > MAX_DEPTH or visited[t] then return end
        visited[t] = true
        for k, v in pairs(t) do
            local to = target(k, names, realm)
            if to then moves[#moves + 1] = { t = t, path = path, from = k, to = to, depth = depth } end
            if type(v) == "string" then
                -- valeur "Nom-" (personnage d une operation) : corrigee
                local fixed = target(v, names, realm)
                if fixed then t[k] = fixed end
            elseif type(v) == "table" then
                walk(v, path == "" and tostring(k) or (path .. "." .. tostring(k)), depth + 1)
            end
        end
    end
    walk(db, "", 0)
    table.sort(moves, function(a, b) return a.depth > b.depth end)
    local merged = 0
    for _, m in ipairs(moves) do
        local new, old = m.t[m.from], m.t[m.to]
        local fn = policy(m.path)
        local v
        if old == nil then
            v = new
            if fn == MERGE["alts"] then v = MERGE["alts"](nil, new, realm) end
        elseif fn then
            v = fn(old, new, realm)
        else
            v = prefer(old, new)
        end
        m.t[m.to] = v
        m.t[m.from] = nil
        merged = merged + 1
    end
    db.realmFix = 1
    ns.realmFixed = merged
end

-- message a la connexion qui a refondu les donnees
ns.AddStrings({
    enUS = { REALM_FIXED = "the game no longer gives the realm name (since 11/21): your characters and auction house data had been split in two, they are merged again (%d entries)." },
    frFR = { REALM_FIXED = "le jeu ne donne plus le nom du royaume (depuis le 21/11) : vos personnages et les données de l'HV étaient coupés en deux, ils sont refondus (%d entrées)." },
    deDE = { REALM_FIXED = "das Spiel liefert den Realmnamen nicht mehr (seit 21.11.): Charaktere und Auktionshausdaten waren zweigeteilt, sie wurden wieder zusammengeführt (%d Einträge)." },
    esES = { REALM_FIXED = "el juego ya no da el nombre del reino (desde el 21/11): tus personajes y los datos de la casa de subastas estaban divididos, se han vuelto a unir (%d entradas)." },
    ptBR = { REALM_FIXED = "o jogo não informa mais o nome do reino (desde 21/11): seus personagens e os dados da casa de leilões estavam divididos, foram reunidos (%d entradas)." },
    itIT = { REALM_FIXED = "il gioco non fornisce più il nome del reame (dal 21/11): i tuoi personaggi e i dati della casa d'aste erano divisi in due, sono stati riuniti (%d voci)." },
    ruRU = { REALM_FIXED = "игра больше не сообщает название мира (с 21.11): данные персонажей и аукциона были разделены, они снова объединены (записей: %d)." },
    zhCN = { REALM_FIXED = "游戏不再提供服务器名称（自 11/21 起）：角色和拍卖行数据曾被拆分，现已合并（%d 项）。" },
    zhTW = { REALM_FIXED = "遊戲不再提供伺服器名稱（自 11/21 起）：角色與拍賣場資料曾被拆分，現已合併（%d 項）。" },
    koKR = { REALM_FIXED = "게임이 더 이상 서버 이름을 주지 않습니다(11/21부터): 캐릭터와 경매장 데이터가 둘로 나뉘어 있었으며 다시 합쳤습니다(%d개 항목)." },
})

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    local n = ns.realmFixed
    if n and n > 0 and C_Timer then
        C_Timer.After(6, function() ns.Say(string.format(ns.L.REALM_FIXED, n)) end)
    end
end)

-- banc d essai
ns._realmTest = { target = target, oldRealm = oldRealm, MERGE = MERGE }
