--[[--------------------------------------------------------------------------
    CorpUI - podometre : les cartes (catalogue, noms, images, tirage)
      - series prises dans les donnees du jeu : le client donne le nom dans
        la langue du joueur et l image (tuiles de la carte du monde pour une
        zone, icone pour un objet ou une monture) ; trophees : nos textes ;
      - une carte inconnue du client (zone ou objet absent de ce jeu) est
        ecartee au chargement : ni tiree, ni comptee, ni montree ;
      - raretes 1 a 5 : commune, peu commune, rare, epique, legendaire ;
      - booster : 5 cartes, la 5e d une rarete minimale selon le booster ;
        un doublon se change en eclats, les eclats fabriquent une carte
        manquante ;
      - trophees : jamais tires, gagnes par les distances (P.CheckTrophies).
    L identifiant (id) de chaque carte est garde dans la sauvegarde, et sa
    place dans CATALOG sert au classeur partage avec la guilde (bits) :
    ajouter les nouvelles cartes A LA FIN, ne jamais en retirer.
    Donnees des objets pas encore chargees : demandees une seule fois
    (rappel immediat du client si deja chargees : redessin repousse, cf.
    le "C stack overflow" des clics du 11/10).
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L

ns.Pedo = ns.Pedo or {}
local P = ns.Pedo

local issecret = issecretvalue or function() return false end

P.RARITY_RGB = {
    { 0.82, 0.82, 0.82 },   -- commune
    { 0.12, 1.00, 0.00 },   -- peu commune
    { 0.00, 0.44, 0.87 },   -- rare
    { 0.64, 0.21, 0.93 },   -- epique
    { 1.00, 0.50, 0.00 },   -- legendaire
}
P.SHARDS = { 5, 10, 25, 100, 400 }        -- un doublon rapporte
P.CRAFT = { 40, 100, 250, 1000, 4000 }    -- une carte manquante coute
P.WEIGHTS = { 70, 22, 6, 1.6, 0.4 }       -- chances d une case de booster
P.PACK_MIN = { normal = 2, rare = 3, epic = 4, legendary = 5 }
P.PACK_SIZE = 5
P.SERIES = { "zones", "objets", "montures", "trophees" }

local Z, O, M, T = "zones", "objets", "montures", "trophees"
local ICON = "Interface\\Icons\\"

-- conditions des trophees : s = P.Snapshot() (metres du jeu, cartes)
local function km(n) return n * 1000 end

local CATALOG = {
    -- Royaumes de l Est (uiMapID de Classic)
    { id = "z_elwynn", s = Z, map = 1429, r = 1 },
    { id = "z_dunmorogh", s = Z, map = 1426, r = 1 },
    { id = "z_tirisfal", s = Z, map = 1420, r = 1 },
    { id = "z_westfall", s = Z, map = 1436, r = 1 },
    { id = "z_lochmodan", s = Z, map = 1432, r = 1 },
    { id = "z_silverpine", s = Z, map = 1421, r = 1 },
    { id = "z_redridge", s = Z, map = 1433, r = 2 },
    { id = "z_duskwood", s = Z, map = 1431, r = 2 },
    { id = "z_wetlands", s = Z, map = 1437, r = 2 },
    { id = "z_hillsbrad", s = Z, map = 1424, r = 2 },
    { id = "z_alterac", s = Z, map = 1416, r = 2 },
    { id = "z_arathi", s = Z, map = 1417, r = 2 },
    { id = "z_stranglethorn", s = Z, map = 1434, r = 2 },
    { id = "z_swamp", s = Z, map = 1435, r = 2 },
    { id = "z_badlands", s = Z, map = 1418, r = 3 },
    { id = "z_hinterlands", s = Z, map = 1425, r = 3 },
    { id = "z_searing", s = Z, map = 1427, r = 3 },
    { id = "z_burning", s = Z, map = 1428, r = 3 },
    { id = "z_blasted", s = Z, map = 1419, r = 3 },
    { id = "z_wpl", s = Z, map = 1422, r = 3 },
    { id = "z_epl", s = Z, map = 1423, r = 4 },
    { id = "z_deadwind", s = Z, map = 1430, r = 4 },
    -- Kalimdor
    { id = "z_durotar", s = Z, map = 1411, r = 1 },
    { id = "z_mulgore", s = Z, map = 1412, r = 1 },
    { id = "z_teldrassil", s = Z, map = 1438, r = 1 },
    { id = "z_barrens", s = Z, map = 1413, r = 1 },
    { id = "z_darkshore", s = Z, map = 1439, r = 1 },
    { id = "z_ashenvale", s = Z, map = 1440, r = 2 },
    { id = "z_stonetalon", s = Z, map = 1442, r = 2 },
    { id = "z_needles", s = Z, map = 1441, r = 2 },
    { id = "z_desolace", s = Z, map = 1443, r = 2 },
    { id = "z_dustwallow", s = Z, map = 1445, r = 2 },
    { id = "z_feralas", s = Z, map = 1444, r = 3 },
    { id = "z_tanaris", s = Z, map = 1446, r = 3 },
    { id = "z_azshara", s = Z, map = 1447, r = 3 },
    { id = "z_felwood", s = Z, map = 1448, r = 3 },
    { id = "z_ungoro", s = Z, map = 1449, r = 3 },
    { id = "z_winterspring", s = Z, map = 1452, r = 4 },
    { id = "z_silithus", s = Z, map = 1451, r = 4 },
    { id = "z_moonglade", s = Z, map = 1450, r = 4 },
    -- capitales
    { id = "z_stormwind", s = Z, map = 1453, r = 2 },
    { id = "z_ironforge", s = Z, map = 1455, r = 2 },
    { id = "z_darnassus", s = Z, map = 1457, r = 2 },
    { id = "z_orgrimmar", s = Z, map = 1454, r = 2 },
    { id = "z_thunderbluff", s = Z, map = 1456, r = 2 },
    { id = "z_undercity", s = Z, map = 1458, r = 2 },

    -- objets : ressources
    { id = "o_linen", s = O, item = 2589, r = 1 },
    { id = "o_wool", s = O, item = 2592, r = 1 },
    { id = "o_silk", s = O, item = 4306, r = 1 },
    { id = "o_mageweave", s = O, item = 4338, r = 1 },
    { id = "o_runecloth", s = O, item = 14047, r = 2 },
    { id = "o_copper", s = O, item = 2770, r = 1 },
    { id = "o_tin", s = O, item = 2771, r = 1 },
    { id = "o_iron", s = O, item = 2772, r = 1 },
    { id = "o_mithril", s = O, item = 3858, r = 2 },
    { id = "o_thorium", s = O, item = 10620, r = 2 },
    { id = "o_peacebloom", s = O, item = 2447, r = 1 },
    { id = "o_silverleaf", s = O, item = 765, r = 1 },
    { id = "o_hearthstone", s = O, item = 6948, r = 1 },
    { id = "o_truesilver", s = O, item = 7911, r = 2 },
    { id = "o_starruby", s = O, item = 7910, r = 2 },
    { id = "o_arcanecrystal", s = O, item = 12363, r = 3 },
    { id = "o_mooncloth", s = O, item = 14342, r = 3 },
    { id = "o_felcloth", s = O, item = 14256, r = 3 },
    { id = "o_blacklotus", s = O, item = 13468, r = 4 },
    { id = "o_arcanite", s = O, item = 12360, r = 3 },
    { id = "o_brilliantshard", s = O, item = 14344, r = 3 },
    { id = "o_nexus", s = O, item = 20725, r = 4 },
    { id = "o_lavacore", s = O, item = 17011, r = 4 },
    { id = "o_elementium", s = O, item = 18562, r = 4 },
    -- objets : armes et reliques celebres
    { id = "o_arcanitereaper", s = O, item = 12784, r = 3 },
    { id = "o_lionheart", s = O, item = 12640, r = 3 },
    { id = "o_truesilverchampion", s = O, item = 7960, r = 2 },
    { id = "o_handofjustice", s = O, item = 11815, r = 3 },
    { id = "o_blackhand", s = O, item = 13965, r = 3 },
    { id = "o_onyxiatooth", s = O, item = 18404, r = 4 },
    { id = "o_onyxiahead", s = O, item = 18423, r = 4 },
    { id = "o_bonereaver", s = O, item = 17076, r = 4 },
    { id = "o_perdition", s = O, item = 18816, r = 4 },
    { id = "o_ashkandi", s = O, item = 19364, r = 4 },
    { id = "o_maladath", s = O, item = 19351, r = 4 },
    { id = "o_benediction", s = O, item = 18608, r = 4 },
    { id = "o_anathema", s = O, item = 18609, r = 4 },
    { id = "o_eyesulfuras", s = O, item = 17204, r = 5 },
    { id = "o_thunderfury", s = O, item = 19019, r = 5 },
    { id = "o_sulfuras", s = O, item = 17182, r = 5 },
    { id = "o_atiesh", s = O, item = 22589, r = 5 },
    { id = "o_windseeker", s = O, item = 18563, r = 5 },

    -- montures
    { id = "m_blackstallion", s = M, item = 2411, r = 3 },
    { id = "m_pinto", s = M, item = 2414, r = 3 },
    { id = "m_chestnut", s = M, item = 5655, r = 3 },
    { id = "m_brownhorse", s = M, item = 5656, r = 3 },
    { id = "m_whiteram", s = M, item = 5873, r = 3 },
    { id = "m_grayram", s = M, item = 5864, r = 3 },
    { id = "m_brownram", s = M, item = 5872, r = 3 },
    { id = "m_stripedfrost", s = M, item = 8631, r = 3 },
    { id = "m_stripednight", s = M, item = 8629, r = 3 },
    { id = "m_spottedfrost", s = M, item = 8632, r = 3 },
    { id = "m_redmecha", s = M, item = 8563, r = 3 },
    { id = "m_bluemecha", s = M, item = 8595, r = 3 },
    { id = "m_brownwolf", s = M, item = 5668, r = 3 },
    { id = "m_direwolf", s = M, item = 5665, r = 3 },
    { id = "m_timberwolf", s = M, item = 1132, r = 3 },
    { id = "m_emeraldraptor", s = M, item = 8588, r = 3 },
    { id = "m_turquoiseraptor", s = M, item = 8591, r = 3 },
    { id = "m_violetraptor", s = M, item = 8592, r = 3 },
    { id = "m_graykodo", s = M, item = 15277, r = 3 },
    { id = "m_brownkodo", s = M, item = 15290, r = 3 },
    { id = "m_redskeletal", s = M, item = 13331, r = 3 },
    { id = "m_blueskeletal", s = M, item = 13332, r = 3 },
    { id = "m_brownskeletal", s = M, item = 13333, r = 3 },
    { id = "m_swiftwhitesteed", s = M, item = 18778, r = 4 },
    { id = "m_swiftpalomino", s = M, item = 18776, r = 4 },
    { id = "m_swiftwhiteram", s = M, item = 18785, r = 4 },
    { id = "m_swiftgraywolf", s = M, item = 18798, r = 4 },
    { id = "m_swiftblueraptor", s = M, item = 18788, r = 4 },
    { id = "m_greatwhitekodo", s = M, item = 18793, r = 4 },
    { id = "m_purplewarhorse", s = M, item = 18791, r = 4 },
    { id = "m_swiftgreenmecha", s = M, item = 18772, r = 4 },
    { id = "m_swiftfrostsaber", s = M, item = 18766, r = 4 },
    { id = "m_frostwolfhowler", s = M, item = 19029, r = 4 },
    { id = "m_stormpikecharger", s = M, item = 19030, r = 4 },
    { id = "m_zuliantiger", s = M, item = 19902, r = 5 },
    { id = "m_razzashiraptor", s = M, item = 19872, r = 5 },
    { id = "m_deathcharger", s = M, item = 13335, r = 5 },
    { id = "m_blackqiraji", s = M, item = 21176, r = 5 },

    -- trophees de marche (jamais tires : gagnes par les distances)
    { id = "t_firstkm", s = T, icon = "INV_Boots_02", r = 1, cond = function(s) return s.total >= km(1) end },
    { id = "t_ten", s = T, icon = "Ability_Hunter_Pathfinding", r = 2, cond = function(s) return s.total >= km(10) end },
    { id = "t_half", s = T, icon = "Spell_Nature_Swiftness", r = 3, cond = function(s) return s.day >= km(21.1) end },
    { id = "t_marathon", s = T, icon = "Ability_Rogue_Sprint", r = 4, cond = function(s) return s.day >= km(42.195) end },
    { id = "t_hundred", s = T, icon = "INV_Misc_Spyglass_03", r = 3, cond = function(s) return s.total >= km(100) end },
    { id = "t_week", s = T, icon = "INV_Misc_PocketWatch_01", r = 4, cond = function(s) return s.week >= km(200) end },
    { id = "t_swimmer", s = T, icon = "Spell_Frost_SummonWaterElemental", r = 3, cond = function(s) return s.swim >= km(10) end },
    { id = "t_ghost", s = T, icon = "Spell_Holy_Resurrection", r = 3, cond = function(s) return s.ghost >= km(5) end },
    { id = "t_rider", s = T, icon = "Ability_Mount_RidingHorse", r = 4, cond = function(s) return s.mount >= km(500) end },
    { id = "t_marseille", s = T, icon = "INV_Misc_Map_01", r = 4, cond = function(s) return s.total >= km(775) end },
    { id = "t_thousand", s = T, icon = "Spell_Arcane_TeleportStormWind", r = 4, cond = function(s) return s.total >= km(1000) end },
    { id = "t_collector", s = T, icon = "INV_Misc_Bag_10", r = 4, cond = function(s) return s.pool > 0 and s.ownedPool * 2 >= s.pool end },
    { id = "t_tourdefrance", s = T, icon = "Spell_Nature_Earthquake", r = 5, cond = function(s) return s.total >= km(3500) end },
    { id = "t_earth", s = T, icon = "Spell_Nature_EarthBindTotem", r = 5, cond = function(s) return s.total >= km(40075) end },
}
P.CATALOG = CATALOG

local byId = {}
for i, c in ipairs(CATALOG) do
    c.index = i
    byId[c.id] = c
end
P.byId = byId

---------------------------------------------------------------------------
-- Valeurs sures
---------------------------------------------------------------------------

-- appel protege ; rien si une valeur rendue est secrete
local function pass(ok, ...)
    if not ok then return end
    for i = 1, select("#", ...) do
        if issecret((select(i, ...))) then return end
    end
    return ...
end
local function call(fn, ...)
    if type(fn) ~= "function" then return end
    return pass(pcall(fn, ...))
end
P.Call = call

---------------------------------------------------------------------------
-- Redessin quand des donnees arrivent (repousse, jamais dans le rappel)
---------------------------------------------------------------------------

local refreshQueued = false
function P.QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        if P.OnDataLoaded then pcall(P.OnDataLoaded) end
    end)
end

---------------------------------------------------------------------------
-- Validite, noms, images
---------------------------------------------------------------------------

local valid = {}         -- id -> true / false (ecartee)

local function itemExists(id)
    local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not fn then return true end
    return call(fn, id) ~= nil
end

local function mapInfo(map)
    if not (C_Map and C_Map.GetMapInfo) then return nil end
    local info = call(C_Map.GetMapInfo, map)
    if type(info) == "table" and type(info.name) == "string" and info.name ~= "" then return info end
end

local function check(c)
    if c.s == T then return true end
    if c.map then return mapInfo(c.map) ~= nil end
    if c.item then return itemExists(c.item) end
    return false
end

-- (re)lit la validite de chaque carte et range les cartes a tirer par rarete
local pool
function P.BuildPool()
    pool = { {}, {}, {}, {}, {} }
    for _, c in ipairs(CATALOG) do
        valid[c.id] = check(c) and true or false
        if valid[c.id] and c.s ~= T then table.insert(pool[c.r], c.id) end
    end
    -- numero dans sa serie (cartes valides seulement)
    local n = {}
    for _, c in ipairs(CATALOG) do
        if valid[c.id] then
            n[c.s] = (n[c.s] or 0) + 1
            c.num = n[c.s]
        end
    end
    P.seriesCount = n
end

function P.IsValid(id)
    if valid[id] == nil then P.BuildPool() end
    return valid[id] == true
end

-- cartes valides, dans l ordre du catalogue (serie et rarete en option)
function P.Cards(series, rarity)
    if not pool then P.BuildPool() end
    local out = {}
    for _, c in ipairs(CATALOG) do
        if valid[c.id] and (not series or series == "all" or c.s == series)
            and (not rarity or rarity == 0 or c.r == rarity) then
            out[#out + 1] = c
        end
    end
    return out
end

local itemLoading = {}
local function itemName(id)
    local n = call(C_Item and C_Item.GetItemNameByID, id)
    if type(n) == "string" and n ~= "" then return n end
    n = call(GetItemInfo, id)
    if type(n) == "string" and n ~= "" then return n end
    -- pas encore en cache : demande unique, redessin a l arrivee
    if itemLoading[id] == nil and Item and Item.CreateFromItemID then
        itemLoading[id] = true
        pcall(function()
            Item:CreateFromItemID(id):ContinueOnItemLoad(function()
                itemLoading[id] = false
                P.QueueRefresh()
            end)
        end)
    end
end

function P.CardName(c)
    if not c then return "?" end
    if c.s == T then return L["PEDO_T_" .. string.upper(c.id:sub(3))] or c.id end
    if c.map then
        local info = mapInfo(c.map)
        return info and info.name or "?"
    end
    if c.item then return itemName(c.item) or L.PEDO_LOADING end
    return "?"
end

-- texte du trophee (comment l obtenir)
function P.CardHint(c)
    if c and c.s == T then return L["PEDO_TH_" .. string.upper(c.id:sub(3))] end
end

function P.CardIcon(c)
    if not c then return nil end
    if c.icon then return ICON .. c.icon end
    if c.item then
        local ic = call(C_Item and C_Item.GetItemIconByID, c.item)
        if ic then return ic end
        local _, _, _, _, icon = call((C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant, c.item)
        return icon
    end
end

-- tuiles de la carte du monde d une zone : { tex = {fileID...}, cols, rows }
local tilesCache = {}
function P.CardTiles(c)
    if not c or not c.map then return nil end
    if tilesCache[c.map] ~= nil then return tilesCache[c.map] or nil end
    local res = false
    local layers = call(C_Map and C_Map.GetMapArtLayers, c.map)
    local tex = call(C_Map and C_Map.GetMapArtLayerTextures, c.map, 1)
    local L1 = type(layers) == "table" and layers[1]
    if type(L1) == "table" and type(tex) == "table" and #tex > 0
        and (L1.tileWidth or 0) > 0 and (L1.tileHeight or 0) > 0 then
        res = {
            tex = tex,
            cols = math.max(1, math.ceil((L1.layerWidth or 0) / L1.tileWidth)),
            rows = math.max(1, math.ceil((L1.layerHeight or 0) / L1.tileHeight)),
        }
    end
    tilesCache[c.map] = res
    return res or nil
end

---------------------------------------------------------------------------
-- Collection (P.db : CorpUIDB.pedometer, pose par Podometre.lua)
---------------------------------------------------------------------------

function P.Owned(id)
    return P.db and P.db.cards[id] == true or false
end

-- cartes valides possedees / total (series a tirer seulement si pool)
function P.OwnedCount(onlyPool)
    if not pool then P.BuildPool() end
    local own, all = 0, 0
    for _, c in ipairs(CATALOG) do
        if valid[c.id] and (not onlyPool or c.s ~= T) then
            all = all + 1
            if P.Owned(c.id) then own = own + 1 end
        end
    end
    return own, all
end

-- ajoute une carte : "new", ou "dup" et les eclats gagnes
function P.Grant(id)
    local c = byId[id]
    if not c or not P.db then return nil end
    if P.db.cards[id] then
        local gain = P.SHARDS[c.r] or 0
        P.db.shards = (P.db.shards or 0) + gain
        return "dup", gain
    end
    P.db.cards[id] = true
    P.db.newCards[id] = true
    return "new", 0
end

function P.CanCraft(id)
    local c = byId[id]
    return c and c.s ~= T and P.db and valid[id] and not P.db.cards[id]
        and (P.db.shards or 0) >= (P.CRAFT[c.r] or math.huge) or false
end

function P.Craft(id)
    if not P.CanCraft(id) then return false end
    local c = byId[id]
    P.db.shards = P.db.shards - P.CRAFT[c.r]
    P.db.cards[id] = true
    P.db.newCards[id] = true
    if P.Changed then P.Changed("craft") end
    return true
end

---------------------------------------------------------------------------
-- Tirage
---------------------------------------------------------------------------

local function pickRarity(min)
    local total = 0
    for r = min, 5 do total = total + P.WEIGHTS[r] end
    local x = math.random() * total
    for r = min, 5 do
        x = x - P.WEIGHTS[r]
        if x <= 0 then return r end
    end
    return 5
end

-- cinq cartes ; la derniere d une rarete au moins egale au minimum du booster
function P.RollPack(kind)
    if not pool then P.BuildPool() end
    local out = {}
    for i = 1, P.PACK_SIZE do
        local min = (i == P.PACK_SIZE) and (P.PACK_MIN[kind] or 2) or 1
        local r = pickRarity(min)
        -- rarete vide (cartes ecartees) : la plus proche en dessous, puis au-dessus
        local rr = r
        while rr > 1 and #pool[rr] == 0 do rr = rr - 1 end
        if #pool[rr] == 0 then
            rr = r
            while rr < 5 and #pool[rr] == 0 do rr = rr + 1 end
        end
        local list = pool[rr]
        if #list > 0 then out[#out + 1] = list[math.random(#list)] end
    end
    return out
end

---------------------------------------------------------------------------
-- Trophees
---------------------------------------------------------------------------

function P.CheckTrophies()
    if not P.db or not P.Snapshot then return end
    local s = P.Snapshot()
    for _, c in ipairs(CATALOG) do
        if c.cond and not P.db.cards[c.id] then
            local ok, yes = pcall(c.cond, s)
            if ok and yes then
                P.db.cards[c.id] = true
                P.db.newCards[c.id] = true
                if P.Announce then P.Announce("trophy", c) end
                if P.Changed then P.Changed("trophy") end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Classeur partage (guilde) : une suite de bits en hexadecimal, dans
-- l ordre du catalogue
---------------------------------------------------------------------------

function P.OwnedBits()
    local hex, n = {}, 0
    local v = 0
    for i, c in ipairs(CATALOG) do
        local bit = (i - 1) % 4
        if P.Owned(c.id) then v = v + 2 ^ bit end
        if bit == 3 or i == #CATALOG then
            n = n + 1
            hex[n] = string.format("%x", v)
            v = 0
        end
    end
    return table.concat(hex)
end

function P.BitsToSet(hex)
    local set = {}
    if type(hex) ~= "string" then return set end
    for i, c in ipairs(CATALOG) do
        local d = tonumber(hex:sub(math.floor((i - 1) / 4) + 1, math.floor((i - 1) / 4) + 1), 16)
        if d then
            local bit = (i - 1) % 4
            if math.floor(d / 2 ^ bit) % 2 == 1 then set[c.id] = true end
        end
    end
    return set
end
