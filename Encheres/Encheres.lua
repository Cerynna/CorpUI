--[[--------------------------------------------------------------------------
    CorpUI - module Encheres (hotel des ventes)
    Scan complet de l hotel des ventes et memoire des prix.
      - barre "Scanner" collee sous la fenetre de l hotel des ventes, a
        droite (notre cadre, strate juste au-dessus de la leur ; rien n est
        ecrit dans AuctionHouseFrame ni dans ses scripts) ;
      - C_AuctionHouse.ReplicateItems au clic seulement : le serveur
        n accepte un scan complet qu environ toutes les 15 min ;
      - lecture des resultats par tranches de quelques millisecondes par
        image (pas de gel), seulement les ventes avec achat immediat ;
        prix unitaire = achat immediat / quantite ; minimum par objet, et
        echelle des prix (les moins chers d abord, jusqu a 1000 exemplaires) ;
      - base au niveau du compte, par royaume et faction ;
      - valeur marche de chaque releve (facon TSM) : moyenne des 15 a 30 %
        d exemplaires les moins chers, coupee au premier saut de prix de
        20 %, sans les prix a plus de 1,5 ecart-type ; gardee par jour ;
      - les recherches faites a la main dans l HV (liste des resultats,
        fiche d un objet) mettent aussi la base a jour, sans attendre le
        scan complet (lecture seule des resultats de Blizzard) ;
      - lignes de prix dans le bandeau d Infobulles (notre cadre, aucun
        crochet sur les infobulles de Blizzard) : prix mini, pile, valeur
        marche, historique, nombre possede sur tous les persos ;
      - API pour les autres modules (Metiers...) :
          ns.AHPrice(itemID ou lien) -> prix, age, moyenne, quantite, jours
                                        (prix en cuivre NON arrondi : 0.25
                                        pour une fleche ; arrondir apres la
                                        multiplication par la quantite)
          ns.AHValues(item)          -> { min, market, hist, qty, age... }
          ns.AHSource(item, cle)     -> une valeur : "min", "market", "hist"
          ns.AHCost(item, n)         -> cout reel d achat des n moins chers
                                        (echelle du dernier scan), quantite
                                        couverte (< n : pas assez en vente),
                                        age, estimation (ancien scan sans
                                        echelle : prix minimum x n)
          ns.AHScanInfo()            -> etat du scan et de la base
          ns.AHMoney(cuivre)         -> "12po 34pa"
          ns.AHListen(fn)            -> fn() apres chaque mise a jour
    Rien en combat : bouton grise, lecture en pause.
    Limites : variantes a suffixe ("de l ours") confondues sous l itemID
    (signale dans l infobulle) ; HV neutre non distingue (le diagnostic
    garde la faction du commissaire-priseur pour le verifier en jeu).
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local issecret = issecretvalue or function() return false end

local COOLDOWN = 15 * 60     -- un scan complet par quart d heure (limite du serveur)
local TIMEOUT = 90           -- sans reponse du serveur au bout de 90 s : abandon
local SETTLE = 1             -- nombre de lignes stable 1 s avant de lire
local EMPTY_WAIT = 10        -- reponse vide : on attend encore un peu
local BUDGET_MS = 8          -- temps de lecture par image
local ROWS_NO_CLOCK = 300    -- lignes par image si debugprofilestop manque
local MAX_ERRORS = 50        -- tranches en erreur avant abandon
local KEEP_DAYS = 45         -- objet absent depuis 45 j : oublie
local MAX_ITEMS = 25000      -- objets gardes par royaume au plus
local MAX_HIST = 30          -- jours d historique gardes (et au plus dans la moyenne)
local MARKET_DAYS = 14       -- valeur marche : les 14 derniers jours, les plus recents comptent plus
local REALM_DAYS = 180       -- royaume sans scan depuis 180 j : oublie
local LADDER_QTY = 1000      -- echelle des prix : jusqu a 1000 exemplaires
local LADDER_LEVELS = 12     -- au-dela de 12 niveaux : paliers
local LADDER_CHARS = 72      -- garde-fou : echelle codee de 72 caracteres au plus
local BAR_W, BAR_H = 400, 24

local db          -- CorpUIDB.auction
local opts        -- db.opts
local realmKey    -- "Royaume-Faction"
local cache = {}  -- itemID -> enregistrement decode (false : inconnu)
local version = 0 -- change a chaque mise a jour (caches des infobulles)
function ns.AHDataVersion() return version end
local listeners = {}
local scan = { state = "idle" }   -- idle, wait, settle, read
local bar

-- premier cadre du fichier : le moteur (evenements, lecture, barre)
local driver = CreateFrame("Frame")

---------------------------------------------------------------------------
-- Outils
---------------------------------------------------------------------------

local function num(v)
    if not issecret(v) and type(v) == "number" then return v end
end

local function str(v)
    if not issecret(v) and type(v) == "string" then return v end
end

local function call(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, a = pcall(fn, ...)
    if ok then return a end
end

local function visible(f)
    if type(f) ~= "table" or type(f.IsVisible) ~= "function" then return false end
    local ok, v = pcall(f.IsVisible, f)
    return ok and not issecret(v) and v == true
end

-- fenetre de l hotel des ventes, si elle est affichee
local function ahFrame()
    local f = _G.AuctionHouseFrame
    if visible(f) then return f end
end

local function today()
    return math.floor(time() / 86400)
end

local function notify()
    version = version + 1
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(err) end
    end
end

---------------------------------------------------------------------------
-- Base de prix. Un objet = une chaine en base 36 (le fichier de sauvegarde
-- de CorpUI est deja gros) :
--   "prix,quantite,jour,minute,historique"
--   prix        dernier prix unitaire le plus bas (code, voir pack)
--   quantite    exemplaires en vente a ce releve
--   jour        jour du releve (time() / 86400), minute : minute du jour
--   historique  minimum de chaque jour (code), le plus recent d abord :
--               "<ecart><prix>.<ecart><prix>" ; ecart = jour - jour du
--               minimum, sur un caractere (0 a z) ; version 4 : valeur
--               marche du jour en plus, "<ecart><prix>:<marche>" (absente
--               des jours lus par une version precedente)
--   ",echelle"  (version 3) prix du dernier releve, du moins cher au plus
--               cher : "<q1>.<d2>:<q2>.<d3>:<q3>..." ; q = exemplaires du
--               niveau, d = code du prix - code du niveau precedent (le
--               premier niveau est au prix minimum) ; vide : un seul niveau
--               (prix, quantite). Sans ce champ (scan d une version
--               precedente) : pas d echelle, ns.AHCost estime.
-- Version 2 des donnees : prix codes par pack (version 1 : cuivre entier,
-- converti au chargement). Version 3 : champ echelle (rien a convertir).
-- Version 4 : valeur marche par jour (rien a convertir).
---------------------------------------------------------------------------

local DATA_VERSION = 4

-- Prix unitaire (cuivre, avec decimales) -> entier a garder.
-- Sous 1 pa : centiemes de cuivre (200 fleches pour 50 pc = 0.25 pc l une) ;
-- a partir de 1 pa : cuivre entier + 9900 (l ecart d un demi-cuivre ne
-- compte plus, et la chaine reste courte). Continu en 1 pa : 10000.
local CENTI_MAX = 10000
local function packPrice(copper)
    local centi = math.floor(copper * 100 + 0.5)
    if centi < CENTI_MAX then return math.max(1, centi) end
    return math.floor(copper + 0.5) + (CENTI_MAX - 100)
end

local function unpackPrice(code)
    if code < CENTI_MAX then return code / 100 end
    return code - (CENTI_MAX - 100)
end

local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
local function b36(n)
    n = math.floor(n or 0)
    if n <= 0 then return "0" end
    local s = ""
    while n > 0 do
        local r = n % 36
        s = B36:sub(r + 1, r + 1) .. s
        n = math.floor(n / 36)
    end
    return s
end

-- echelle -> champ code ("" : un seul niveau egal a (p, q)). Garde-fou :
-- au-dela de LADDER_CHARS, les niveaux les plus chers partent (ns.AHCost
-- dira alors une couverture plus courte).
local function encodeLadder(r)
    local lad = r.lad
    if #lad == 1 and lad[1][2] == r.q then return "" end
    local prev = packPrice(r.p)
    local parts = { b36(lad[1][2]) }
    local len = #parts[1]
    for i = 2, #lad do
        local code = packPrice(lad[i][1])
        local part = b36(math.max(0, code - prev)) .. ":" .. b36(lad[i][2])
        if len + 1 + #part > LADDER_CHARS then break end
        parts[#parts + 1] = part
        len = len + 1 + #part
        prev = code
    end
    return table.concat(parts, ".")
end

-- r.p, hist[].min et hist[].mv : cuivre avec decimales (codes par
-- packPrice) ; r.lad : { { prix, quantite } } ou nil (pas d echelle connue)
local function encode(r)
    local h = {}
    for _, e in ipairs(r.hist) do
        local k = r.day - e.day
        if k >= 0 and k < 36 then
            local s = B36:sub(k + 1, k + 1) .. b36(packPrice(e.min))
            if e.mv then s = s .. ":" .. b36(packPrice(e.mv)) end
            h[#h + 1] = s
        end
    end
    local s = b36(packPrice(r.p)) .. "," .. b36(r.q) .. "," .. b36(r.day) .. "," .. b36(r.minute) .. "," .. table.concat(h, ".")
    if r.lad and r.lad[1] then s = s .. "," .. encodeLadder(r) end
    return s
end

local function decodeLadder(r, s)
    if s == "" then return { { r.p, r.q } } end
    local lad, code = {}, packPrice(r.p)
    for e in s:gmatch("[^%.]+") do
        local d, q
        if #lad == 0 then
            d, q = 0, tonumber(e, 36)
        else
            local a, b = e:match("^(%w+):(%w+)$")
            d, q = tonumber(a or "", 36), tonumber(b or "", 36)
        end
        if not (d and q) then return nil end
        code = code + d
        lad[#lad + 1] = { unpackPrice(code), q }
    end
    return lad[1] and lad or nil
end

-- legacy : chaine de la version 1 (prix en cuivre entier, sans code)
local function decode(s, legacy)
    if type(s) ~= "string" then return nil end
    local p, q, day, minute, hist, comma, ladder = s:match("^(%w+),(%w+),(%w+),(%w+),([%w%.:]*)(,?)([%w%.:]*)$")
    if not p or (comma == "" and ladder ~= "") then return nil end
    local conv = legacy and function(v) return v end or unpackPrice
    local r = { p = tonumber(p, 36), q = tonumber(q, 36), day = tonumber(day, 36), minute = tonumber(minute, 36), hist = {} }
    if not (r.p and r.q and r.day and r.minute) then return nil end
    r.p = conv(r.p)
    r.t = r.day * 86400 + r.minute * 60
    for e in hist:gmatch("[^%.]+") do
        local k = tonumber(e:sub(1, 1), 36)
        local a, b = e:sub(2):match("^(%w+):?(%w*)$")
        local m, mv = tonumber(a or "", 36), tonumber(b or "", 36)
        if k and m then r.hist[#r.hist + 1] = { day = r.day - k, min = conv(m), mv = mv and unpackPrice(mv) or nil } end
    end
    -- echelle abimee : l objet reste connu, sans echelle (estimation)
    if comma == "," and not legacy then r.lad = decodeLadder(r, ladder) end
    return r
end

-- echelle d un releve, a partir de { [prix unitaire] = quantite } :
-- niveaux { prix, quantite } du moins cher au plus cher (meme code de prix
-- = meme niveau), jusqu a LADDER_QTY exemplaires. Plus de LADDER_LEVELS
-- niveaux : paliers geometriques sur la quantite cumulee (le premier
-- niveau seul, puis de 1 a 2, 2 a 4, ..., 512 a 1024 exemplaires), au
-- prix moyen du palier : le cout d un palier entier reste exact.
local function buildLadder(byPrice)
    local units = {}
    for u in pairs(byPrice) do units[#units + 1] = u end
    table.sort(units)
    local levels, cum = {}, 0
    for _, u in ipairs(units) do
        if cum >= LADDER_QTY then break end
        local code, q = packPrice(u), byPrice[u]
        local last = levels[#levels]
        if last and last.code == code then
            last.q, last.cost = last.q + q, last.cost + u * q
        else
            levels[#levels + 1] = { code = code, q = q, cost = u * q, from = cum }
        end
        cum = cum + q
    end
    local out = {}
    if #levels <= LADDER_LEVELS then
        for i, lv in ipairs(levels) do out[i] = { unpackPrice(lv.code), lv.q } end
        return out
    end
    local tiers, last = {}, nil
    for _, lv in ipairs(levels) do
        local k, b = 0, 1
        while lv.from >= b do k, b = k + 1, b * 2 end
        if last and last.k == k then
            last.q, last.cost = last.q + lv.q, last.cost + lv.cost
        else
            last = { k = k, q = lv.q, cost = lv.cost }
            tiers[#tiers + 1] = last
        end
    end
    for i, t in ipairs(tiers) do out[i] = { unpackPrice(packPrice(t.cost / t.q)), t.q } end
    return out
end

-- Valeur marche d un releve, a partir de { [prix unitaire] = quantite } :
-- on prend les exemplaires du moins cher au plus cher, au moins 15 % du
-- total, au plus 30 %, et on s arrete au premier prix 20 % plus cher que
-- le precedent (passe les 15 %). Moyenne de ces exemplaires, puis moyenne
-- de ceux a moins de 1,5 ecart-type (un prix tres bas ou tres haut ne la
-- tire pas). total : exemplaires en vente (resultats partiels : seulement
-- les moins chers sont la) ; nil s ils ne couvrent pas les 30 % du total.
local function marketOf(byPrice, total)
    local units, sum = {}, 0
    for u, q in pairs(byPrice) do
        if q > 0 then
            units[#units + 1] = u
            sum = sum + q
        end
    end
    if sum <= 0 then return nil end
    total = math.max(total or sum, sum)
    local lo, cap = total * 0.15, math.max(1, math.ceil(total * 0.3))
    if sum < total and sum < cap then return nil end
    table.sort(units)
    local pts, taken, acc, prev = {}, 0, 0, nil
    for _, u in ipairs(units) do
        if taken > 0 and taken >= lo and (taken >= cap or u >= prev * 1.2) then break end
        local q = math.min(byPrice[u], cap - taken)
        if q <= 0 then break end
        pts[#pts + 1] = { u, q }
        taken, acc, prev = taken + q, acc + u * q, u
    end
    local mean = acc / taken
    local var = 0
    for _, p in ipairs(pts) do var = var + p[2] * (p[1] - mean) ^ 2 end
    local sd = math.sqrt(var / taken)
    local n, s = 0, 0
    for _, p in ipairs(pts) do
        if math.abs(p[1] - mean) <= 1.5 * sd then n, s = n + p[2], s + p[1] * p[2] end
    end
    if n == 0 then return mean end
    return s / n
end

-- jour du releve, sans tout decoder (purge)
local function dayOf(s)
    local d = type(s) == "string" and s:match("^%w+,%w+,(%w+),")
    return d and tonumber(d, 36)
end

local function currentRealmKey()
    if realmKey then return realmKey end
    local r = str(call(GetRealmName)) or "?"
    local f = str(call(UnitFactionGroup, "player"))
    if not f then return r end
    realmKey = r .. "-" .. f
    return realmKey
end

local function realm(create)
    if not db then return nil end
    local key = currentRealmKey()
    local r = db.realms[key]
    if type(r) ~= "table" then
        if not create then return nil, key end
        r = { items = {} }
        db.realms[key] = r
    end
    if type(r.items) ~= "table" then r.items = {} end
    return r, key
end

local function record(id)
    local r = realm(false)
    if not r then return nil end
    local c = cache[id]
    if c == nil then
        c = decode(r.items[id]) or false
        cache[id] = c
    end
    return c or nil
end

-- "moyenne" : mediane des minimums journaliers des `days` derniers jours
-- (cuivre, non arrondie). Un prix anormal (vente a 1 pc, prix delirant)
-- ne la deplace pas.
local function average(rec, days)
    local now = today()
    local vals = {}
    for _, e in ipairs(rec.hist) do
        if now - e.day < days then vals[#vals + 1] = e.min end
    end
    local n = #vals
    if n == 0 then return nil, 0 end
    table.sort(vals)
    local mid = math.floor((n + 1) / 2)
    local v = (n % 2 == 1) and vals[mid] or (vals[mid] + vals[mid + 1]) / 2
    return v, n
end

-- jours a prendre dans les `days` derniers : ceux qui ont une valeur
-- marche s il y en a (un jour vu seulement dans une liste de resultats n a
-- que son minimum), sinon les minimums (donnees d une version precedente)
local function dayValue(rec, days)
    local now = today()
    for _, e in ipairs(rec.hist) do
        if e.mv and now - e.day < days then return function(x) return x.mv end end
    end
    return function(x) return x.min end
end

-- valeur marche : moyenne des valeurs marche des MARKET_DAYS derniers
-- jours, ponderee (aujourd hui compte 14, il y a 13 jours : 1). Cuivre
-- non arrondi, nombre de jours ; nil si rien de recent.
local function marketValue(rec)
    local now, val = today(), dayValue(rec, MARKET_DAYS)
    local s, w, n = 0, 0, 0
    for _, e in ipairs(rec.hist) do
        local age, v = now - e.day, val(e)
        if v and age >= 0 and age < MARKET_DAYS then
            local k = MARKET_DAYS - age
            s, w, n = s + v * k, w + k, n + 1
        end
    end
    if w == 0 then return nil, 0 end
    return s / w, n
end

-- historique : mediane des valeurs marche (sinon minimums) des `days`
-- derniers jours ; nombre de jours
local function histValue(rec, days)
    local now, val = today(), dayValue(rec, days)
    local vals = {}
    for _, e in ipairs(rec.hist) do
        local v = val(e)
        if v and now - e.day < days then vals[#vals + 1] = v end
    end
    local n = #vals
    if n == 0 then return nil, 0 end
    table.sort(vals)
    local mid = math.floor((n + 1) / 2)
    return (n % 2 == 1) and vals[mid] or (vals[mid] + vals[mid + 1]) / 2, n
end

-- API publique : l argument peut venir d une API du jeu, donc etre secret
-- (type() ne le dit pas) : rien n est compare avant issecret
local function itemIDOf(item)
    if issecret(item) then return nil end
    if type(item) == "number" then
        if item ~= item or item <= 0 or item >= 2 ^ 31 then return nil end
        return math.floor(item)
    end
    if type(item) == "string" then
        return tonumber(item:match("item:(%d+)") or item:match("^%d+$"))
    end
end

-- variante a suffixe aleatoire ("de l ours") : champ suffixe du lien non nul
-- (item:id:enchant:gemme1:gemme2:gemme3:gemme4:suffixe:...)
local function hasSuffix(link)
    local s = link:match("item:%-?%d+:[^:|]*:[^:|]*:[^:|]*:[^:|]*:[^:|]*:(%-?%d+)")
    s = tonumber(s)
    return s ~= nil and s ~= 0
end

-- Plafond du nombre d objets : les plus anciens partent (rare : une fois
-- passe, chaque scan n en ajoute que quelques-uns)
local function capItems(r, count)
    if count <= MAX_ITEMS then return count end
    local list = {}
    for id, s in pairs(r.items) do list[#list + 1] = { id = id, day = dayOf(s) or 0 } end
    table.sort(list, function(a, b) return a.day < b.day end)
    for i = 1, count - MAX_ITEMS do r.items[list[i].id] = nil end
    return MAX_ITEMS
end

-- Un releve d un objet entre dans la base (scan complet ou recherche) :
-- price = prix unitaire le plus bas, qty = exemplaires en vente, byPrice =
-- { [prix unitaire] = quantite } (echelle ; nil : echelle gardee si le
-- prix n a pas bouge, sinon oubliee), mv = valeur marche du releve (nil :
-- celle du jour reste). Le minimum du jour est le plus bas des releves du
-- jour ; sa valeur marche, la moyenne de l ancienne et de la nouvelle.
-- Renvoie vrai si l objet etait inconnu.
local function store(r, id, price, qty, byPrice, mv, day, minute)
    local old = decode(r.items[id])
    local hist = {}
    if old then
        -- jours gardes : ceux que les calculs utilisent (valeur marche,
        -- moyenne choisie), pas plus
        local keep = math.max(MARKET_DAYS, math.min(MAX_HIST, (opts and opts.days) or 7))
        for _, e in ipairs(old.hist) do
            if day - e.day >= 0 and day - e.day < keep then hist[#hist + 1] = { day = e.day, min = e.min, mv = e.mv } end
        end
    end
    if hist[1] and hist[1].day == day then
        hist[1].min = math.min(hist[1].min, price)
        if mv then hist[1].mv = hist[1].mv and (hist[1].mv + mv) / 2 or mv end
    else
        table.insert(hist, 1, { day = day, min = price, mv = mv })
    end
    local lad
    if byPrice then
        lad = buildLadder(byPrice)
    elseif old and old.lad and packPrice(old.p) == packPrice(price) then
        lad = old.lad
    end
    r.items[id] = encode({ p = price, q = qty, day = day, minute = minute, hist = hist, lad = lad })
    cache[id] = nil
    return old == nil
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------

-- prix unitaire (cuivre, NON arrondi : 0.25 pour une fleche), age en
-- secondes, moyenne (cuivre non arrondi, ou nil), quantite vue, nombre de
-- jours dans la moyenne ; nil si l objet est inconnu ou l argument secret.
-- Toutes variantes a suffixe confondues (prix de l itemID).
function ns.AHPrice(item)
    local id = itemIDOf(item)
    local rec = id and record(id)
    if not rec then return nil end
    local avg, n = average(rec, (opts and opts.days) or 7)
    return rec.p, math.max(0, time() - rec.t), avg, rec.q, n
end

-- cout d achat des n exemplaires les moins chers au dernier releve (cuivre
-- NON arrondi), quantite couverte (< n : l echelle s arrete avant, pas
-- assez en vente ou au-dela de 1000), age en secondes, estimation (vrai :
-- releve d une version sans echelle, prix minimum x n, couverture n).
-- nil si l objet est inconnu, n invalide ou un argument secret.
function ns.AHCost(item, n)
    if issecret(n) or type(n) ~= "number" or n ~= n or n < 0 or n == math.huge then return nil end
    local id = itemIDOf(item)
    local rec = id and record(id)
    if not rec then return nil end
    local age = math.max(0, time() - rec.t)
    if not rec.lad then return rec.p * n, n, age, true end
    local cost, got = 0, 0
    for _, lv in ipairs(rec.lad) do
        if got >= n then break end
        local take = math.min(lv[2], n - got)
        cost, got = cost + take * lv[1], got + take
    end
    return cost, got, age, false
end

-- toutes les valeurs d un objet (cuivre NON arrondi) : min (dernier prix
-- le plus bas), qty (exemplaires vus), age (secondes), seen (horodatage),
-- market (valeur marche, 14 jours ponderes ; repli : historique, puis
-- min), marketDays, hist (mediane des valeurs marche sur opts.days
-- jours), histDays, lad (echelle des prix, a lire seulement, ou nil).
-- nil si inconnu ou argument secret. nocache : lecture sans garder l objet
-- decode (parcours de toute la base).
function ns.AHValues(item, nocache)
    local id = itemIDOf(item)
    local rec
    if id and nocache then
        rec = cache[id]
        if rec == nil then
            local r = realm(false)
            rec = r and decode(r.items[id])
        end
        rec = rec or nil
    else
        rec = id and record(id)
    end
    if not rec then return nil end
    local days = (opts and opts.days) or 7
    local m, mn = marketValue(rec)
    local h, hn = histValue(rec, days)
    return { id = id, min = rec.p, qty = rec.q, age = math.max(0, time() - rec.t), seen = rec.t,
             market = m or h or rec.p, marketDays = mn, hist = h, histDays = hn, lad = rec.lad }
end

-- echelle des prix du dernier releve (copie) : { { prix unitaire, quantite } }
-- du moins cher au plus cher, ou nil (objet inconnu, releve sans echelle)
function ns.AHLadder(item)
    local id = itemIDOf(item)
    local rec = id and record(id)
    if not (rec and rec.lad) then return nil end
    local out = {}
    for i, lv in ipairs(rec.lad) do out[i] = { lv[1], lv[2] } end
    return out
end

-- objets connus du royaume courant : itemID suivant (parcours par next,
-- lecture seule ; nil a la fin). Usage : local id = ns.AHNextItem(nil) ...
function ns.AHNextItem(prev)
    local r = realm(false)
    if not r then return nil end
    local ok, id = pcall(next, r.items, prev)
    if ok then return id end
end

-- une source de prix : "min", "market" ou "hist" (cuivre non arrondi)
function ns.AHSource(item, key)
    local v = ns.AHValues(item)
    if not v then return nil end
    if key == "min" then return v.min end
    if key == "hist" then return v.hist end
    return v.market
end

local function cooldownLeft()
    local r = realm(false)
    local last = r and num(r.lastReq)
    if not last then return 0 end
    return math.max(0, last + COOLDOWN - time())
end

-- avancement : lecture 0 a 85 %, enregistrement 85 a 98 %, menage ensuite
local function progress()
    local st = scan.state
    if st == "read" and scan.n and scan.n > 0 then
        return 0.85 * math.max(0, math.min(1, (scan.cursor - scan.base) / scan.n))
    elseif st == "save" and scan.ids then
        return 0.85 + 0.13 * (#scan.ids > 0 and scan.saved / #scan.ids or 1)
    elseif st == "purge" then
        return 0.98
    end
    return 0
end

function ns.AHScanInfo()
    local r, key = realm(false)
    return {
        realm = key or currentRealmKey(),
        state = scan.state,                -- idle, wait, settle, read, save, purge
        progress = progress(),             -- 0 a 1 pendant le scan
        paused = scan.paused and true or false,
        items = (r and r.nItems) or 0,
        auctions = (r and r.nAuctions) or 0,
        lastScan = r and r.lastScan,
        lastRequest = r and r.lastReq,
        wait = cooldownLeft(),             -- secondes avant le prochain scan
    }
end

function ns.AHListen(fn)
    table.insert(listeners, fn)
end

-- "12po 34pa" : abreviations communes de CorpUI (ns.MoneySymbols),
-- cuivre omis au-dela d une piece d or ; sous 1 pc : "0,25pc"
local function symbol(name, fallback)
    local s = _G[name]
    if type(s) == "string" and not issecret(s) and s ~= "" then return s end
    return fallback
end

function ns.AHMoney(copper)
    if issecret(copper) then return "?" end
    copper = tonumber(copper) or 0
    if copper ~= copper then copper = 0 end
    local G, S, Cu = ns.MoneySymbols()
    if copper >= 0.005 and copper < 0.995 then
        -- prix unitaire sous le cuivre (fleches, balles) : deux decimales
        local t = string.format("%.2f", copper):gsub("0+$", "")
        local sep = symbol("DECIMAL_SEPARATOR", ".")
        return t:gsub("%.", function() return sep end) .. Cu
    end
    copper = math.floor(copper + 0.5)
    if copper < 0 then copper = 0 end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    if g > 0 then
        if s > 0 then return g .. G .. " " .. s .. S end
        return g .. G
    elseif s > 0 then
        if c > 0 then return s .. S .. " " .. c .. Cu end
        return s .. S
    end
    return c .. Cu
end

---------------------------------------------------------------------------
-- Scan : repos -> attente (requete envoyee) -> reception (nombre de lignes
-- stable) -> lecture par tranches -> enregistrement par tranches -> menage
-- (objets trop anciens). Lecture, enregistrement et menage : quelques
-- millisecondes par image, en pause pendant un combat.
---------------------------------------------------------------------------

-- budget de temps d une image : fn() vrai quand il est depasse (teste
-- toutes les `every` iterations ; sans horloge, au plus `cap` iterations)
local function budget(every, cap)
    local clock = debugprofilestop
    local start = type(clock) == "function" and clock()
    local n = 0
    return function()
        n = n + 1
        if start then return n % every == 0 and clock() - start > BUDGET_MS end
        return n >= cap
    end
end

local function api()
    local ah = C_AuctionHouse
    if type(ah) == "table" then return ah end
end

local function numRows()
    local ah = api()
    return ah and num(call(ah.GetNumReplicateItems))
end

local function resetScan()
    scan.state = "idle"
    scan.mins, scan.qty, scan.lad, scan.paused = nil, nil, nil, false
    scan.ids, scan.realm, scan.pkey, scan.diag = nil, nil, nil, nil
end

-- etapes qui ont besoin de l hotel des ventes ouvert (ses donnees vivent
-- tant que la fenetre est ouverte) ; l enregistrement, lui, continue
local function needsAH()
    local st = scan.state
    return st == "wait" or st == "settle" or st == "read"
end

-- etapes travaillees a chaque image
local function busy()
    local st = scan.state
    return st == "read" or st == "save" or st == "purge"
end

local function setState(s)
    scan.state = s
    scan.since = GetTime()
end

local function abort(msg)
    local was = scan.state
    resetScan()
    if was ~= "idle" and msg then ns.Say(msg) end
    driver.acc = 1
end

-- une ligne : quantite, achat immediat (pile entiere), itemID
local function rowInfo(i)
    local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(i)
    return count, buyout, itemID
end

-- ligne brute pour le diagnostic (index de depart, sens du prix)
local function diagRow(i)
    local ok, name, _, count, _, _, _, _, minBid, _, buyout, bid, _, _, _, _, _, itemID, all = pcall(C_AuctionHouse.GetReplicateItemInfo, i)
    if not ok then return { i = i, err = true } end
    local function v(x)
        if issecret(x) then return "secret" end
        if type(x) == "number" or type(x) == "string" or type(x) == "boolean" then return x end
        return nil
    end
    return { i = i, name = v(name), count = v(count), minBid = v(minBid), buyout = v(buyout), bid = v(bid),
             itemID = v(itemID), all = v(all) }
end

local function toSettle(n)
    if scan.state ~= "settle" then setState("settle") end
    scan.n = n or 0
    scan.stable = GetTime()
end

local function startRead()
    -- index de depart : 0 (comme les autres addons), sinon 1
    local ok, _, _, id = pcall(rowInfo, 0)
    scan.base = (ok and num(id) and id > 0) and 0 or 1
    scan.cursor = scan.base
    scan.mins, scan.qty, scan.lad = {}, {}, {}
    scan.rows, scan.auctions, scan.skipped, scan.errors = 0, 0, 0, 0
    scan.paused = false
    -- diagnostic garde a part : il ne remplace celui de la base qu a la fin
    -- d un scan complet (un scan interrompu n efface pas le precedent)
    scan.diag = { at = time(), n = scan.n, base = scan.base, probe0 = ok and num(id) or "nil", npc = scan.npc,
                  rows = {}, stacks = {} }
    setState("read")
end

-- une tranche de lecture (appelee sous pcall)
local function readSlice()
    local over = budget(50, ROWS_NO_CLOCK)
    local last = scan.base + scan.n - 1
    local diag = scan.diag
    while scan.cursor <= last do
        local i = scan.cursor
        scan.cursor = i + 1
        scan.rows = scan.rows + 1
        local count, buyout, id = rowInfo(i)
        if not issecret(count) and not issecret(buyout) and not issecret(id)
           and type(count) == "number" and type(buyout) == "number" and type(id) == "number"
           and count > 0 and buyout > 0 and id > 0 then
            local unit = buyout / count
            local cur = scan.mins[id]
            if not cur or unit < cur then scan.mins[id] = unit end
            scan.qty[id] = (scan.qty[id] or 0) + count
            -- echelle : exemplaires par prix unitaire (triee a l enregistrement)
            local lad = scan.lad[id]
            if not lad then
                lad = {}
                scan.lad[id] = lad
            end
            lad[unit] = (lad[unit] or 0) + count
            scan.auctions = scan.auctions + 1
            if count > 1 and #diag.stacks < 3 then diag.stacks[#diag.stacks + 1] = diagRow(i) end
        else
            scan.skipped = scan.skipped + 1
        end
        if i - scan.base < 3 then diag.rows[#diag.rows + 1] = diagRow(i) end
        if over() then return end
    end
end

-- fin de lecture : les donnees sont a nous, la suite ne depend plus de
-- l hotel des ventes (on peut le fermer)
local function finishRead()
    local ids = {}
    for id in pairs(scan.mins) do ids[#ids + 1] = id end
    local now = time()
    scan.ids, scan.saved = ids, 0
    scan.stamp = now
    scan.day = math.floor(now / 86400)
    scan.minute = math.floor((now - scan.day * 86400) / 60)
    scan.realm, scan.key = realm(true)
    setState("save")
end

-- une tranche d enregistrement : les minimums du scan entrent dans la base
-- (prix unitaire non arrondi : encode garde les centiemes sous 1 pa)
local function saveSlice()
    local over = budget(20, 200)
    local r, day = scan.realm, scan.day
    while scan.saved < #scan.ids do
        scan.saved = scan.saved + 1
        local id = scan.ids[scan.saved]
        local lad = scan.lad[id]
        store(r, id, scan.mins[id], scan.qty[id] or 0, lad, lad and marketOf(lad), day, scan.minute)
        if over() then return false end
    end
    return true
end

-- une tranche de menage : objets absents depuis KEEP_DAYS jours oublies.
-- Parcours par next() : on ne fait qu effacer des cles existantes.
local function purgeSlice()
    local over = budget(50, 500)
    local items, day = scan.realm.items, scan.day
    while true do
        local id, s = next(items, scan.pkey)
        if id == nil then return true end
        local d = dayOf(s)
        if not d or day - d > KEEP_DAYS then items[id] = nil else scan.count = scan.count + 1 end
        scan.pkey = id
        if over() then return false end
    end
end

-- a la connexion : objets absents depuis KEEP_DAYS retires (avant :
-- seulement apres un releve complet de l HV)
function ns.AHPurgeOld()
    local r = realm(false)
    if not r then return 0 end
    local today = math.floor(time() / 86400)
    local n = 0
    for id, s in pairs(r.items) do
        local d = dayOf(s)
        if not d or today - d > KEEP_DAYS then
            r.items[id] = nil
            cache[id] = nil
            n = n + 1
        end
    end
    if n > 0 then version = version + 1 end
    return n
end

local function finishSave()
    local r, key = scan.realm, scan.key
    local items, auctions = #scan.ids, scan.auctions
    -- prix effaces entre-temps (bouton du panneau) : on n ecrit rien
    if db.realms[key] == r then
        r.nItems = capItems(r, scan.count)
        r.lastScan = scan.stamp
        r.nAuctions = auctions
        local d = scan.diag
        if d then
            d.rows_read, d.auctions, d.skipped, d.items, d.errors = scan.rows, auctions, scan.skipped, items, scan.errors
            db.diag = d
        end
        ns.Say(string.format(L.AH_DONE, items, auctions))
    end
    resetScan()
    wipe(cache)
    notify()
    -- autres modules (bonnes affaires)
    for _, fn in ipairs(ns.AHScanDoneHooks or {}) do
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(err) end
    end
end

local function step()
    if InCombatLockdown() then
        scan.paused = true
        return
    end
    scan.paused = false
    if scan.state == "read" then
        local n = numRows()
        if n and n > scan.n then scan.n = n end
        local ok = pcall(readSlice)
        if not ok then
            scan.errors = scan.errors + 1
            if scan.errors > MAX_ERRORS then
                abort(string.format(L.AH_FAILED, "GetReplicateItemInfo"))
                return
            end
        end
        if scan.cursor > scan.base + scan.n - 1 then finishRead() end
    elseif scan.state == "save" then
        local ok, done = pcall(saveSlice)
        if not ok then
            abort(string.format(L.AH_FAILED, tostring(done)))
        elseif done then
            scan.state, scan.pkey, scan.count = "purge", nil, 0
        end
    elseif scan.state == "purge" then
        local ok, done = pcall(purgeSlice)
        if not ok or done then finishSave() end
    end
end

local function canScan()
    local ah = api()
    return scan.state == "idle" and not InCombatLockdown() and cooldownLeft() <= 0
        and ah ~= nil and type(ah.ReplicateItems) == "function" and ahFrame() ~= nil
end

-- faction du commissaire-priseur, pour le diagnostic de l HV neutre :
-- "Alliance", "Horde", autre valeur ou "nil" ; "-" sans PNJ
local function npcFaction()
    local exists = call(UnitExists, "npc")
    if issecret(exists) then return "secret" end
    if not exists then return "-" end
    local ok, f = pcall(UnitFactionGroup, "npc")
    if not ok then return "?" end
    if issecret(f) then return "secret" end
    return type(f) == "string" and f or "nil"
end

-- clic sur Scanner (clic materiel : ReplicateItems n est pas protegee)
local function startScan()
    if not db then return end
    if InCombatLockdown() then ns.Say(L.COMBAT_BLOCKED) return end
    if scan.state ~= "idle" or not ahFrame() then return end
    local wait = cooldownLeft()
    if wait > 0 then
        ns.Say(string.format(L.AH_NEXT, math.ceil(wait / 60)))
        return
    end
    local ah = api()
    if not (ah and type(ah.ReplicateItems) == "function") then return end
    if type(ah.IsThrottledMessageSystemReady) == "function" then
        local ok, ready = pcall(ah.IsThrottledMessageSystemReady)
        if ok and not issecret(ready) and ready == false then ns.Say(L.AH_BUSY) return end
    end
    local r = realm(true)
    local prev = r.lastReq
    scan.before = numRows() or 0
    scan.late = nil
    scan.npc = npcFaction()
    setState("wait")
    r.lastReq = time()
    local ok, err = pcall(ah.ReplicateItems)
    if not ok then
        r.lastReq = prev
        resetScan()
        ns.Say(string.format(L.AH_FAILED, tostring(err)))
    end
    driver.acc = 1
end

---------------------------------------------------------------------------
-- Recherches faites dans l HV (liste des resultats, fiche d un objet) :
-- leurs resultats entrent dans la base, lus au pas suivant (les evenements
-- arrivent par rafales). Lecture seule des API de resultats ; rien en
-- combat ni pendant l enregistrement d un scan complet (le menage parcourt
-- la base). Variantes a suffixe et mascottes ignorees : la base range tout
-- sous l itemID (le scan complet les confond, une recherche les separe).
-- Les autres modules (Vente, Mes encheres, Achats) ecoutent aussi ces
-- resultats : ns.AHResultsListen(fn(type, itemID, itemKey)), type =
-- "commodity", "item" ou "browse".
---------------------------------------------------------------------------

local pending = { browse = false, items = {}, commodities = {} }
local resultListeners = {}

function ns.AHResultsListen(fn)
    table.insert(resultListeners, fn)
end

local function tellResults(kind, id, key)
    for _, fn in ipairs(resultListeners) do
        local ok, err = pcall(fn, kind, id, key)
        if not ok then geterrorhandler()(err) end
    end
end

-- itemID d une cle d objet ordinaire (ni suffixe ni mascotte), sinon nil
local function plainKey(key)
    if type(key) ~= "table" then return nil end
    local ok, id, suffix, pet = pcall(function() return key.itemID, key.itemSuffix, key.battlePetSpeciesID end)
    if not ok then return nil end
    id, suffix, pet = num(id), num(suffix) or 0, num(pet) or 0
    if id and id > 0 and suffix == 0 and pet == 0 then return id end
end
ns.AHPlainKey = plainKey

-- liste des resultats : prix le plus bas et quantite de chaque objet
-- (l echelle n est pas connue : gardee si le prix n a pas bouge)
local function readBrowse(r, day, minute)
    local ah = api()
    local list = ah and call(ah.GetBrowseResults)
    if type(list) ~= "table" then return false end
    local changed = false
    for _, res in ipairs(list) do
        if type(res) == "table" then
            local id = plainKey(res.itemKey)
            local qty, price = num(res.totalQuantity), num(res.minPrice)
            if id and qty and price and qty > 0 and price > 0 then
                if store(r, id, price, qty, nil, nil, day, minute) then r.nItems = (r.nItems or 0) + 1 end
                changed = true
            end
        end
    end
    return changed
end

-- fiche d une marchandise : toutes les annonces, les moins cheres d abord
-- (resultats partiels : seulement le debut de la liste)
local function readCommodity(r, id, day, minute)
    local ah = api()
    local n = ah and num(call(ah.GetNumCommoditySearchResults, id))
    if not n or n <= 0 then return false end
    local byPrice, got, low = {}, 0, nil
    for i = 1, n do
        local ok, res = pcall(ah.GetCommoditySearchResultInfo, id, i)
        if ok and type(res) == "table" then
            local u, q = num(res.unitPrice), num(res.quantity)
            if u and q and u > 0 and q > 0 then
                byPrice[u] = (byPrice[u] or 0) + q
                got = got + q
                if not low or u < low then low = u end
            end
        end
    end
    if not low then return false end
    local total = math.max(num(call(ah.GetCommoditySearchResultsQuantity, id)) or got, got)
    if store(r, id, low, total, byPrice, marketOf(byPrice, total), day, minute) then r.nItems = (r.nItems or 0) + 1 end
    return true
end

-- fiche d un objet (prix d achat immediat a l unite) : seulement une liste
-- complete (son ordre depend du tri choisi par le joueur)
local function readItems(r, key, day, minute)
    local id = plainKey(key)
    local ah = api()
    if not (id and ah) or call(ah.HasFullItemSearchResults, key) ~= true then return false end
    local n = num(call(ah.GetNumItemSearchResults, key))
    if not n or n <= 0 then return false end
    local byPrice, got, low = {}, 0, nil
    for i = 1, n do
        local ok, res = pcall(ah.GetItemSearchResultInfo, key, i)
        if ok and type(res) == "table" then
            local u, q = num(res.buyoutAmount), num(res.quantity) or 1
            if u and u > 0 and q > 0 then
                byPrice[u] = (byPrice[u] or 0) + q
                got = got + q
                if not low or u < low then low = u end
            end
        end
    end
    if not low then return false end
    if store(r, id, low, got, byPrice, marketOf(byPrice, got), day, minute) then r.nItems = (r.nItems or 0) + 1 end
    return true
end

local function capture()
    if not (pending.browse or next(pending.items) or next(pending.commodities)) then return end
    if not db or InCombatLockdown() or scan.state == "save" or scan.state == "purge" then return end
    if opts.capture == false then
        pending.browse = false
        wipe(pending.items)
        wipe(pending.commodities)
        return
    end
    local r = realm(true)
    local now = time()
    local day = math.floor(now / 86400)
    local minute = math.floor((now - day * 86400) / 60)
    local changed = false
    if pending.browse then
        pending.browse = false
        changed = readBrowse(r, day, minute) or changed
    end
    for id in pairs(pending.commodities) do changed = readCommodity(r, id, day, minute) or changed end
    wipe(pending.commodities)
    for _, key in pairs(pending.items) do changed = readItems(r, key, day, minute) or changed end
    wipe(pending.items)
    if changed then notify() end
end

local function onResults(event, a)
    if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
        pending.browse = true
        tellResults("browse")
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_ADDED" then
        local id = num(a)
        if id and id > 0 then
            pending.commodities[id] = true
            tellResults("commodity", id)
        end
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_ADDED" then
        local id = plainKey(a)
        if id then pending.items[id] = a end
        local ok, raw = pcall(function() return a.itemID end)
        tellResults("item", (ok and num(raw)) or id, a)
    end
end

---------------------------------------------------------------------------
-- Barre sous la fenetre de l hotel des ventes
---------------------------------------------------------------------------

-- strate juste au-dessus : un cadre d addon pose sur une fenetre de
-- Blizzard dans la meme strate ne s affiche pas sur son contenu
local STRATA_UP = { BACKGROUND = "LOW", LOW = "MEDIUM", MEDIUM = "HIGH", HIGH = "DIALOG",
                    DIALOG = "FULLSCREEN", FULLSCREEN = "FULLSCREEN_DIALOG" }

-- strate, niveau et echelle calques sur la fenetre de Blizzard (lus
-- seulement : on ne touche jamais a la leur)
local function follow(f, pf)
    local okS, strata = pcall(pf.GetFrameStrata, pf)
    strata = okS and str(strata)
    strata = (strata and STRATA_UP[strata]) or "HIGH"
    if f:GetFrameStrata() ~= strata then f:SetFrameStrata(strata) end
    local okL, lvl = pcall(pf.GetFrameLevel, pf)
    lvl = okL and num(lvl)
    if lvl then
        local want = math.min(9000, lvl + 10)
        if f:GetFrameLevel() ~= want then f:SetFrameLevel(want) end
    end
    local okE, s = pcall(pf.GetEffectiveScale, pf)
    s = okE and num(s)
    local u = UIParent:GetEffectiveScale()
    if s and u and u > 0 and s > 0 then
        local want = s / u
        local cur = f:GetScale()
        if type(cur) ~= "number" or math.abs(cur - want) > 0.001 then f:SetScale(want) end
    end
end
ns.AHFollow = follow
ns.AHFrame = ahFrame
-- CorpUIDB.auction (reglages et donnees des onglets du volet) ; nil avant
-- la connexion
function ns.AHDB() return db end
ns.AHRealmKey = currentRealmKey

-- etat pendant un scan (nil au repos)
local function activeText()
    local st = scan.state
    if st == "wait" then return string.format(L.AH_WAITING, math.floor(GetTime() - (scan.since or GetTime()))) end
    if st == "settle" then return L.AH_RECEIVING end
    if busy() then
        if scan.paused then return L.AH_PAUSED end
        return string.format(L.AH_SCANNING, math.floor(progress() * 100))
    end
end

-- etat au repos : combat, delai, pret
local function idleText()
    if InCombatLockdown() then return L.AH_COMBAT end
    local wait = cooldownLeft()
    if wait > 0 then return string.format(L.AH_NEXT, math.ceil(wait / 60)) end
    return L.AH_READY
end

local function statusText()
    local active = activeText()
    if active then return active end
    local r = realm(false)
    local last = r and num(r.lastScan)
    local state = idleText()
    if last then return "|cff9d9d9d" .. string.format(L.AH_LAST, ns.FormatAgo(last)) .. "|r  ·  " .. state end
    return state
end

-- infobulle du bouton, y compris grise : elle dit pourquoi
local function buttonTip(self)
    local t = ns.Tooltip(self, "ANCHOR_TOP")
    t:AddLine(L.MOD_AH)
    t:AddLine(L.AH_BTN_TIP, 1, 1, 1, true)
    t:AddLine(L.AH_BTN_TIP2, 0.7, 0.7, 0.7, true)
    local r = realm(false)
    if r and num(r.lastScan) then
        t:AddLine(string.format(L.AH_LAST, ns.FormatAgo(r.lastScan)), 1, 0.82, 0.25)
        t:AddLine(string.format(L.AH_KNOWN, r.nItems or 0), 1, 0.82, 0.25)
    end
    if canScan() then
        t:AddLine(L.AH_READY, 0.3, 1, 0.3)
    else
        t:AddLine(activeText() or idleText(), 1, 0.5, 0.3)
    end
    t:Show()
end

local function buildBar()
    local C = ns.COLORS
    bar = CreateFrame("Frame", "CorpUIAuctionBar", UIParent)
    bar:SetSize(BAR_W, BAR_H)
    -- pas de SetClampedToScreen : remontee dans la fenetre, la barre (strate
    -- au-dessus) couvrirait les boutons Acheter de Blizzard
    bar:EnableMouse(true)
    ns.UI.Skin(bar, 0.95, true)
    local b = ns.UI.Button(bar, L.AH_SCAN, 90, startScan)
    b:SetHeight(BAR_H - 4)
    b:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
    -- grise sous la souris (clic, delai) : sans cela OnLeave ne vient pas et
    -- l infobulle resterait affichee sur l HV
    b:SetMotionScriptsWhileDisabled(true)
    b:HookScript("OnEnter", function(self)
        bar.hover = true
        buttonTip(self)
    end)
    b:HookScript("OnLeave", function()
        bar.hover = false
        ns.HideTooltip()
    end)
    bar.button = b
    -- texte ancre sur deux cotes, hauteur fixe (un seul coin : parfois sans position)
    local fs = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", bar, "LEFT", 8, 0)
    fs:SetPoint("RIGHT", b, "LEFT", -8, 0)
    fs:SetHeight(BAR_H - 4)
    fs:SetJustifyH("RIGHT")
    fs:SetWordWrap(false)
    bar.status = fs
    -- avancement de la lecture : filet en bas de la barre
    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 1, 1)
    fill:SetHeight(2)
    fill:SetWidth(1)
    ns.NoSnap(fill)
    ns.UI.Gradient(fill, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 1, C.gold[1], C.gold[2], C.gold[3], 1)
    fill:Hide()
    bar.fill = fill
    bar:Hide()
    -- autres modules de l HV (bouton du volet CorpUI)
    for _, fn in ipairs(ns.AHBarHooks or {}) do
        local ok, err = pcall(fn, bar)
        if not ok then geterrorhandler()(err) end
    end
end

local function updateBar(ahf)
    if not ahf then
        if bar and bar.hover then
            bar.hover = false
            ns.HideTooltip()
        end
        if bar and bar:IsShown() then bar:Hide() end
        return
    end
    if not bar then buildBar() end
    if bar.anchoredTo ~= ahf then
        -- hors de la fenetre, dans la bande des onglets (a droite)
        bar:ClearAllPoints()
        bar:SetPoint("TOPRIGHT", ahf, "BOTTOMRIGHT", -4, -2)
        bar.anchoredTo = ahf
    end
    follow(bar, ahf)
    local text, enabled = statusText(), canScan()
    bar.status:SetText(text)
    bar.button:SetEnabled(enabled)
    -- infobulle du bouton ouverte : elle suit l etat (grise, compte a rebours)
    if bar.hover and (enabled ~= bar.lastEnabled or text ~= bar.lastText) then buttonTip(bar.button) end
    bar.lastEnabled, bar.lastText = enabled, text
    if busy() then
        bar.fill:SetWidth(math.max(1, (BAR_W - 2) * progress()))
        bar.fill:Show()
    else
        bar.fill:Hide()
    end
    if not bar:IsShown() then bar:Show() end
end

-- requete abandonnee faute de reponse : sa reponse compte encore tant que
-- le delai du serveur court et que l HV reste ouvert (memes donnees)
local function lateOpen()
    if not scan.late then return false end
    if time() - scan.late >= COOLDOWN then
        scan.late = nil
        return false
    end
    return true
end

local function lateReply(n)
    scan.late = nil
    ns.Say(L.AH_LATE)
    toSettle(n)
end

-- releve lent : attente du serveur, stabilite, barre
local function tick()
    capture()
    local ahf = ahFrame()
    if needsAH() and not ahf then
        abort(L.AH_ABORTED)
    elseif scan.state == "wait" then
        local n = numRows() or 0
        if n > 0 and scan.before == 0 then
            -- donnees arrivees sans evenement
            toSettle(n)
        elseif GetTime() - scan.since > TIMEOUT then
            abort(L.AH_NO_REPLY)
            local r = realm(false)
            scan.late = (r and num(r.lastReq)) or time()
        end
    elseif scan.state == "settle" then
        local n = numRows() or 0
        if n > 0 and GetTime() - scan.since > TIMEOUT then
            -- des morceaux arrivent sans fin : on lit (la suite sera prise en route)
            scan.n = n
            startRead()
        elseif n ~= scan.n then
            scan.n = n
            scan.stable = GetTime()
        elseif GetTime() - scan.stable >= SETTLE then
            if n > 0 then
                startRead()
            elseif GetTime() - scan.since > EMPTY_WAIT then
                abort(L.AH_EMPTY)
            end
        end
    elseif scan.state == "idle" and ahf and lateOpen() then
        local n = numRows() or 0
        if n > 0 and scan.before == 0 then lateReply(n) end
    end
    updateBar(ahf)
end

driver.acc = 0
driver:SetScript("OnUpdate", function(self, dt)
    if not db then return end
    if busy() then step() end
    self.acc = self.acc + dt
    if self.acc >= 0.2 then
        self.acc = 0
        tick()
    end
end)

---------------------------------------------------------------------------
-- Infobulles : lignes ajoutees au bandeau d Infobulles (Tooltips.lua)
---------------------------------------------------------------------------

-- quantite de la pile montree par l infobulle (sacs, banque, butin) ;
-- rien en combat, tout en lecture protegee
local function stackCount(tip)
    if InCombatLockdown() then return nil end
    -- objet possede : GUID -> emplacement -> pile
    if type(tip.GetPrimaryTooltipData) == "function" then
        local ok, data = pcall(tip.GetPrimaryTooltipData, tip)
        if ok and type(data) == "table" then
            local okG, guid = pcall(function() return data.guid end)
            if okG and str(guid) and C_Item and C_Item.GetItemLocation and C_Item.GetStackCount then
                local okL, loc = pcall(C_Item.GetItemLocation, guid)
                if okL and type(loc) == "table" and type(loc.IsValid) == "function" then
                    local okV, valid = pcall(loc.IsValid, loc)
                    if okV and not issecret(valid) and valid == true then
                        local n = num(call(C_Item.GetStackCount, loc))
                        if n then return n end
                    end
                end
            end
        end
    end
    -- sinon : ce que l infobulle a demande (sac et case, butin)
    if type(tip.GetPrimaryTooltipInfo) ~= "function" then return nil end
    local ok, info = pcall(tip.GetPrimaryTooltipInfo, tip)
    if not ok or type(info) ~= "table" then return nil end
    local okN, getter, args = pcall(function() return info.getterName, info.getterArgs end)
    getter = okN and str(getter)
    if not getter or type(args) ~= "table" then return nil end
    local okA, a1, a2 = pcall(function() return args[1], args[2] end)
    if not okA then return nil end
    a1, a2 = num(a1), num(a2)
    if getter == "GetBagItem" and a1 and a2 then
        local _, n = ns.BagItem(a1, a2)
        return num(n)
    elseif getter == "GetLootItem" and a1 and GetLootSlotInfo then
        local okS, _, _, n = pcall(GetLootSlotInfo, a1)
        return okS and num(n) or nil
    end
    return nil
end

local tipCache = setmetatable({}, { __mode = "k" })   -- infobulle -> derniere reponse

local function gold(s) return "|cffffd100" .. s .. "|r" end

local rootDB      -- CorpUIDB (persos du module Persos : CorpUIDB.alts)

-- nombre possede sur tous les persos : sacs (en direct pour celui-ci) et
-- banque (dernier releve du module Persos) ; total, puis les trois persos
-- qui en ont le plus. nil si personne n en a.
local function ownedText(id)
    local alts = rootDB and rootDB.alts
    local me = ns.CharKey()
    local list, total = {}, 0
    local function add(name, n)
        if n > 0 then
            list[#list + 1] = { name = name, n = n }
            total = total + n
        end
    end
    local function count(t, k) return (type(t) == "table" and num(t[k])) or 0 end
    local seenMe = false
    if type(alts) == "table" then
        for key, t in pairs(alts) do
            if type(t) == "table" then
                local name = str(t.name) or tostring(key)
                if key == me then
                    seenMe = true
                    add(name, ns.ItemCount(id) + count(t.bank, id))
                else
                    add(name, count(t.bags, id) + count(t.bank, id))
                end
            end
        end
    end
    if not seenMe then add(str(call(UnitName, "player")) or "?", ns.ItemCount(id)) end
    if total == 0 then return nil end
    table.sort(list, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.name < b.name
    end)
    local parts = {}
    for i = 1, math.min(3, #list) do parts[i] = list[i].name .. " " .. list[i].n end
    if #list > 3 then parts[#parts + 1] = "+" .. (#list - 3) end
    return gold(L.AH_TIP_OWNED) .. " |cffffffff" .. total .. "|r |cff9d9d9d(" .. table.concat(parts, ", ") .. ")|r"
end

-- prix de vente au marchand (cuivre, a l unite) ou nil
local function vendorPrice(link)
    local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if type(info) ~= "function" then return nil end
    local ok, v = pcall(function() return select(11, info(link)) end)
    v = ok and num(v)
    if v and v > 0 then return v end
end
ns.AHVendorPrice = vendorPrice

-- fn(infobulle, lien, lignes) : ajoute les lignes de prix
local function tipLines(tip, link, out)
    if not db or not opts.tip or issecret(link) or type(link) ~= "string" then return end
    local id = tonumber(link:match("item:(%d+)"))
    if not id then return end
    local rec = record(id)
    local count = (rec and opts.stack) and stackCount(tip) or nil
    local bags = opts.owned and ns.ItemCount(id) or 0
    -- meme objet, meme pile, meme minute, memes sacs : lignes deja pretes
    local key = link .. "|" .. (count or 0) .. "|" .. version .. "|" .. math.floor(time() / 60) .. "|" .. bags
    local c = tipCache[tip]
    if not (c and c.key == key) then
        local lines = {}
        if rec then
            local age = ns.FormatAgo(rec.t)
            -- variante a suffixe : le prix est celui de l itemID (toutes variantes)
            if hasSuffix(link) then age = age .. ", " .. L.AH_VARIANTS end
            lines[1] = gold(L.AH_TIP) .. " " .. ns.AHMoney(rec.p) .. " |cff9d9d9d(" .. age .. ")|r"
            if count and count > 1 then
                -- prix unitaire non arrondi x pile, arrondi une seule fois
                lines[#lines + 1] = gold(string.format(L.AH_TIP_STACK, count)) .. " " .. ns.AHMoney(rec.p * count)
            end
            local market = marketValue(rec)
            if opts.market and market then
                lines[#lines + 1] = gold(L.AH_TIP_MARKET) .. " " .. ns.AHMoney(market)
            end
            if opts.avg then
                local h, n = histValue(rec, opts.days or 7)
                local shown = (opts.market and market) or rec.p
                if h and n >= 2 and ns.AHMoney(h) ~= ns.AHMoney(shown) then
                    lines[#lines + 1] = gold(string.format(L.AH_TIP_AVG, n)) .. " " .. ns.AHMoney(h)
                end
            end
        end
        if opts.vendor then
            local v = vendorPrice(link)
            if v then lines[#lines + 1] = gold(L.AH_TIP_VENDOR) .. " " .. ns.AHMoney(v) end
        end
        if opts.owned then
            local o = ownedText(id)
            if o then lines[#lines + 1] = o end
        end
        c = { key = key, lines = lines }
        tipCache[tip] = c
    end
    for _, l in ipairs(c.lines) do out[#out + 1] = l end
end
ns.AHTipLines = tipLines

-- point d extension d Infobulles (independant de l ordre de chargement)
ns.tipItemProviders = ns.tipItemProviders or {}
table.insert(ns.tipItemProviders, tipLines)

---------------------------------------------------------------------------
-- Options (/corp hv)
---------------------------------------------------------------------------

local panel, statsText

local function refreshPanel()
    if not panel or not statsText then return end
    local info = ns.AHScanInfo()
    local last = info.lastScan and ns.FormatAgo(info.lastScan) or L.AH_NEVER
    local s = string.format(L.AH_STATS, info.realm, info.items, last)
    if info.lastScan then s = s .. "\n" .. string.format(L.AH_STATS2, info.auctions) end
    statsText:SetText(s)
end
ns.AHListen(function() if panel and panel:IsVisible() then refreshPanel() end end)

local function clearPrices()
    local r, key = realm(false)
    if r then db.realms[key] = { items = {}, lastReq = r.lastReq, nItems = 0 } end
    wipe(cache)
    ns.Say(string.format(L.AH_CLEARED, key or currentRealmKey()))
    notify()
end

local function buildPanel()
    panel = ns.UI.Window("CorpUIAuctionOptions", ns.TITLE .. " - " .. L.MOD_AH, nil, 440, 260)
    local form = ns.UI.Form(panel, -34, function() notify() end)
    form:Header(L.AH_SEC_TIPS)
    form:Check(L.AH_OPT_TIP, function() return opts.tip end, function(v) opts.tip = v end)
    form:Columns(2)
    form:Check(L.AH_OPT_STACK, function() return opts.stack end, function(v) opts.stack = v end)
    form:Check(L.AH_OPT_MARKET, function() return opts.market end, function(v) opts.market = v end)
    form:Check(L.AH_OPT_AVG, function() return opts.avg end, function(v) opts.avg = v end)
    form:Check(L.AH_OPT_OWNED, function() return opts.owned end, function(v) opts.owned = v end)
    form:Check(L.AH_OPT_VENDOR, function() return opts.vendor end, function(v) opts.vendor = v end)
    form:EndColumns()
    form:Number(L.AH_OPT_DAYS, function() return opts.days end, function(v) opts.days = v end, 2, MAX_HIST, 1)
    -- reglages des onglets du volet (Vente...)
    for _, fn in ipairs(ns.AHPanelHooks or {}) do
        local ok, err = pcall(fn, panel, form)
        if not ok then geterrorhandler()(err) end
    end
    form:Header(L.AH_SEC_DATA)
    form:Check(L.AH_OPT_CAPTURE, function() return opts.capture end, function(v) opts.capture = v end)
    statsText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statsText:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, form.y)
    statsText:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, form.y)
    statsText:SetHeight(30)
    statsText:SetJustifyH("LEFT")
    statsText:SetJustifyV("TOP")
    local y = form.y - 34
    local clear = ns.UI.Button(panel, L.AH_CLEAR, 130, function(self)
        if self.armed then
            self.armed = nil
            self:SetText(L.AH_CLEAR)
            clearPrices()
        else
            self.armed = true
            self:SetText(L.AH_SURE)
            C_Timer.After(3, function()
                if self.armed then self.armed = nil self:SetText(L.AH_CLEAR) end
            end)
        end
    end)
    clear:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, y)
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, y - 30)
    hint:SetWidth(420)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.AH_HINT)
    panel:SetHeight(-(y - 30) + 52)
    panel:HookScript("OnShow", function()
        form:Refresh()
        refreshPanel()
    end)
end

local function toggle()
    if not db then return end
    if not panel then buildPanel() end
    ns.ShowPanel(panel)
end

local function slash(input)
    local cmd = strlower(strtrim(input or ""))
    if not db then return end
    if cmd == "diag" then
        local d = db.diag
        if type(d) ~= "table" then ns.Say(L.AH_DIAG_NONE) return end
        ns.Say(string.format(L.AH_DIAG, num(d.rows_read) or num(d.n) or 0, num(d.base) or 0, num(d.auctions) or 0,
            num(d.skipped) or 0))
        -- lignes brutes ; prix unitaire calcule (achat immediat / quantite)
        local function show(prefix, row)
            local unit = ""
            if type(row.buyout) == "number" and type(row.count) == "number" and row.count > 0 then
                unit = "  -> " .. ns.AHMoney(row.buyout / row.count) .. " / 1"
            end
            ns.Chat(string.format("  %s#%s  id=%s  x%s  buyout=%s  minBid=%s%s", prefix, tostring(row.i),
                tostring(row.itemID), tostring(row.count), tostring(row.buyout), tostring(row.minBid), unit))
        end
        for _, row in ipairs(d.rows or {}) do show("", row) end
        for _, row in ipairs(d.stacks or {}) do show("stack ", row) end
        ns.Chat("  npc faction: " .. tostring(d.npc) .. "  errors: " .. tostring(d.errors or 0))
    else
        toggle()
    end
end

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

local function init()
    local root = ns.InitRoot()
    rootDB = root
    if type(root.auction) ~= "table" then root.auction = {} end
    db = root.auction
    if type(db.realms) ~= "table" then db.realms = {} end
    if type(db.opts) ~= "table" then db.opts = {} end
    opts = db.opts
    if opts.tip == nil then opts.tip = true end
    if opts.stack == nil then opts.stack = true end
    if opts.avg == nil then opts.avg = true end
    if opts.market == nil then opts.market = true end
    if opts.owned == nil then opts.owned = true end
    if opts.vendor == nil then opts.vendor = false end
    if opts.capture == nil then opts.capture = true end
    if type(opts.days) ~= "number" then opts.days = 7 end
    opts.days = math.max(2, math.min(MAX_HIST, math.floor(opts.days)))
    -- donnees de la version 1 (prix en cuivre entier) : converties une fois ;
    -- version 2 (sans echelle) : gardee telle quelle, ns.AHCost estime
    -- jusqu au prochain scan de l objet
    if (num(db.version) or 0) < 2 then
        for _, r in pairs(db.realms) do
            if type(r) == "table" and type(r.items) == "table" then
                for id, s in pairs(r.items) do
                    local rec = decode(s, true)
                    r.items[id] = rec and encode(rec) or nil
                end
            end
        end
    end
    db.version = DATA_VERSION
    for _, fn in ipairs(ns.AHInitHooks or {}) do
        local ok, err = pcall(fn, db)
        if not ok then geterrorhandler()(err) end
    end
    -- royaumes sans scan depuis longtemps : oublies
    local now = time()
    for key, r in pairs(db.realms) do
        if type(r) ~= "table" or (num(r.lastScan) and now - r.lastScan > REALM_DAYS * 86400) then db.realms[key] = nil end
    end
    realmKey = nil
    currentRealmKey()
end

driver:SetScript("OnEvent", function(_, event, ...)
    if ns.ModuleOff("hv", driver) then return end
    if event == "PLAYER_LOGIN" then
        init()
    elseif not db then
        return
    elseif event == "AUCTION_HOUSE_CLOSED" then
        scan.late = nil     -- les donnees de l HV partent avec la fenetre
        if needsAH() then abort(L.AH_ABORTED) end
        if bar then bar:Hide() end
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
        if scan.state == "wait" or scan.state == "settle" then
            toSettle(numRows() or 0)
        elseif scan.state == "read" then
            local n = numRows()
            if n and n > scan.n then scan.n = n end
        elseif scan.state == "idle" and ahFrame() and lateOpen() then
            lateReply(numRows() or 0)
        end
    elseif event == "AUCTION_HOUSE_SHOW" or event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED"
        or event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        driver.acc = 1      -- barre a jour a la prochaine image
    else
        onResults(event, ...)
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "REPLICATE_ITEM_LIST_UPDATE",
                     "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
                     "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
                     "COMMODITY_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_ADDED",
                     "ITEM_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_ADDED" }) do
    pcall(driver.RegisterEvent, driver, e)
end

ns.RegisterModule({
    command = "hv",
    alias = "ah",
    panelName = "CorpUIAuctionOptions",
    icon = "Interface\\Icons\\INV_Misc_Coin_01",
    title = function() return L.MOD_AH end,
    desc = function() return L.AH_DESC end,
    Slash = slash,
    Open = toggle,
})
