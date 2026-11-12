--[[--------------------------------------------------------------------------
    CorpUI - module Encheres : affaires "fabrication -> marchand"
    (troisieme liste de l onglet Affaires, Affaires.lua)

    12/11 : les recettes dont les composants, achetes a l HV (echelle des
    prix du dernier releve) ou chez un marchand (fils, sel, fioles...),
    coutent moins que ce que paie un marchand pour l objet fabrique.
      - prix marchand de l objet : celui du jeu (GetItemInfo), donc avec
        les correctifs de Blizzard (la Grenade en fer vaut 5 pa dans les
        tables du jeu, 1 pa 25 en jeu) ; objet pas encore connu du client :
        demande, et Affaires relance la recherche une fois ;
      - fabrications successives, composants les moins chers d abord :
        arret quand une fabrication coute autant qu elle rapporte, quand
        l HV n en a plus (au dernier releve), ou a 200 ; une seule pour
        les recettes a temps de recharge (transmutations : fer en or,
        1 h sur Forever ; etoffe lunaire...) ;
      - toutes les recettes du jeu (Donnees.lua du module Metiers),
        apprises ou non : la ligne dit qui la connait, sinon le metier
        (option de l onglet : mes metiers seulement) ;
      - composants : prix de l HV de moins de N minutes (reglage de
        l onglet), sinon pas d affaire ; ceux du marchand sont illimites.
    Clic : liste d achats des composants (onglet Achats : quantites et
    prix max) ; clic droit : recette ignoree (Affaires.lua).
    Demande le module Metiers (CorpUI_Metiers) pour les recettes.
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local AH = ns.AH
local issecret = issecretvalue or function() return false end

local num, str = AH.num, AH.str

local MAX_CRAFTS = 200      -- fabrications par affaire, au plus
local HUGE = 1e9            -- quantite d un marchand

-- recettes a temps de recharge (secondes ; table SpellCooldowns du jeu
-- Forever, build 70888) : une seule fabrication par affaire
-- (transmutations, etoffe lunaire, ecaille d Onyxia raffinee)
local RECHARGE = {
    [11479] = 3600, [11480] = 3600, [17187] = 169200, [17559] = 82800, [17560] = 82800, [17561] = 82800,
    [17562] = 82800, [17563] = 82800, [17564] = 82800, [17565] = 82800, [17566] = 82800, [18560] = 342000,
    [22430] = 7200, [25146] = 600, [1317279] = 169200,
}

local F = {}
AH.Fab = F

-- noms anglais de secours des metiers (sinon le nom donne par le jeu)
local PROF_EN = {
    [40] = "Poisons", [129] = "First Aid", [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy",
    [182] = "Herbalism", [185] = "Cooking", [186] = "Mining", [197] = "Tailoring", [202] = "Engineering",
    [333] = "Enchanting", [356] = "Fishing", [393] = "Skinning",
}

-- recettes du module Metiers presentes
function F.Ready()
    local S = ns.CraftSkill
    return type(S) == "table" and type(S.Recipe) == "function" and type(ns.CraftData) == "table"
        and type(ns.CraftData.recipes) == "table"
end

local profNames = {}
function F.ProfName(skill)
    if not skill then return "?" end
    local n = profNames[skill]
    if n then return n end
    local fn = C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName
    n = str(AH.call(fn, skill))
    if n == "" then n = nil end
    n = n or PROF_EN[skill] or ("#" .. skill)
    profNames[skill] = n
    return n
end

-- recettes du jeu : identifiant suivant (parcours par next), et leur nombre
function F.Next(prev)
    local ok, id = pcall(next, ns.CraftData.recipes, prev)
    if ok then return id end
end

function F.Count()
    local n = 0
    for _ in pairs(ns.CraftData.recipes) do n = n + 1 end
    return n
end

local function shortName(key)
    return tostring(key):match("^([^%-]+)") or tostring(key)
end

-- contexte d une recherche : qui connait quelle recette (releves du module
-- Metiers, tous les personnages du compte), metiers et rangs des
-- personnages (module Persos), paliers d achat des composants deja lus
function F.Context()
    local ctx = { known = {}, ranks = {}, mine = {}, reag = {}, loading = 0 }
    local M = ns.Craft
    local d = M and M.DB and M.DB()
    if type(d) == "table" and type(d.known) == "table" then
        for char, k in pairs(d.known) do
            if type(k) == "table" then
                for _, rid in pairs(k) do
                    rid = num(rid)
                    if rid then
                        local t = ctx.known[rid] or {}
                        t[#t + 1] = shortName(char)
                        ctx.known[rid] = t
                    end
                end
            end
        end
    end
    local root = ns.InitRoot and ns.InitRoot()
    local alts = root and root.alts
    if type(alts) == "table" then
        for char, a in pairs(alts) do
            if type(a) == "table" and type(a.profs) == "table" then
                for _, p in ipairs(a.profs) do
                    if type(p) == "table" and type(p.name) == "string" then
                        local t = ctx.ranks[p.name] or {}
                        t[#t + 1] = { shortName(char), num(p.rank) or 0 }
                        ctx.ranks[p.name] = t
                        ctx.mine[p.name] = true
                    end
                end
            end
        end
    end
    return ctx
end

-- prix d une fourniture chez un marchand (releve par le module Metiers a
-- chaque visite, ou fourniture connue : fils, sel, fioles...) ; nil sinon
local function vendorCost(item)
    local M = ns.Craft
    local d = M and M.DB and M.DB()
    local seen = d and type(d.vendor) == "table" and num(d.vendor[item])
    if seen and seen > 0 then return seen end
    local S = ns.CraftSkill
    local e = S and S.Item and S.Item(item)
    if e and e.buy > 0 and S.VENDOR and S.VENDOR[item] then return e.buy / e.stack end
end

-- paliers d achat d un composant { { prix unitaire, quantite, marchand } },
-- du moins cher au plus cher : HV (prix de moins de N minutes) puis
-- marchand (illimite, les paliers HV plus chers ne servent plus) ; nil si
-- aucun prix. Lecture seule pendant la recherche (partages entre recettes).
local function tiersOf(item, o, ctx)
    local c = ctx.reag[item]
    if c ~= nil then return c or nil end
    local tiers = {}
    local v = ns.AHValues and ns.AHValues(item, true)
    if v and num(v.age) and v.age <= o.fresh * 60 then
        for _, lv in ipairs(v.lad or { { v.min, v.qty } }) do
            local p, q = num(lv[1]), num(lv[2])
            if p and q and q > 0 then tiers[#tiers + 1] = { p, q } end
        end
    end
    local vp = vendorCost(item)
    if vp then
        local cut = {}
        for _, t in ipairs(tiers) do
            if t[1] < vp then cut[#cut + 1] = t end
        end
        cut[#cut + 1] = { vp, HUGE, true }
        tiers = cut
    end
    ctx.reag[item] = #tiers > 0 and tiers or false
    return #tiers > 0 and tiers or nil
end

-- n exemplaires de plus d un composant, apres ceux deja pris (x.pos,
-- x.used) : cout, ou nil si l HV n en a plus ; position suivante gardee
-- dans x.n* (prise validee par commit)
local function take(x, n)
    local pos, used, cost, ah, top = x.pos, x.used, 0, 0, x.top
    while n > 0 do
        local t = x.tiers[pos]
        if not t then return nil end
        local avail = t[2] - used
        if avail <= 0 then
            pos, used = pos + 1, 0
        else
            local u = math.min(n, avail)
            cost = cost + u * t[1]
            if not t[3] then
                ah = ah + u
                if t[1] > top then top = t[1] end
            end
            n, used = n - u, used + u
        end
    end
    x.npos, x.nused, x.nah, x.ntop = pos, used, ah, top
    return cost
end

local function commit(x)
    x.pos, x.used, x.top = x.npos, x.nused, x.ntop
    x.ah = x.ah + x.nah
    x.total = x.total + x.n
end

local function cached(item)
    local fn = C_Item and C_Item.IsItemDataCachedByID
    if fn then
        local ok, v = pcall(fn, item)
        if ok and not issecret(v) and v ~= nil then return v == true end
    end
    local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local ok, name = pcall(info, item)
    return ok and name ~= nil
end

-- une recette : nil si pas d affaire ; sinon { id (objet fabrique), spell,
-- kind = "craft", q (fabrications), cost (composants de la serie), profit,
-- ref (prix marchand par fabrication), count, unit (cout de la 1re), last
-- (cout de la derniere), roi, parts = { { item, n, ah, top, vendor, vp } },
-- skill, yellow, gray, who (qui la connait), ranks, mine, stop }
function F.Of(id, o, ctx)
    if o.ignoreCraft[id] then return nil end
    local S = ns.CraftSkill
    local r = S.Recipe(id)
    if not r or not r.item or r.item <= 0 or #r.reagents == 0 then return nil end
    local need = {}
    for i, g in ipairs(r.reagents) do
        local tiers = tiersOf(g[1], o, ctx)
        if not tiers then return nil end
        local x = { item = g[1], n = g[2], tiers = tiers, pos = 1, used = 0, ah = 0, top = 0, total = 0 }
        for _, t in ipairs(tiers) do
            if t[3] then x.vp = t[1] end
        end
        need[i] = x
    end
    local vp = ns.AHVendorPrice and ns.AHVendorPrice("item:" .. r.item)
    if not vp then
        -- objet pas encore connu du client : demande (Affaires relance une fois)
        if not cached(r.item) then
            if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, r.item) end
            ctx.loading = ctx.loading + 1
        end
        return nil
    end
    local count = math.max(1, r.count or 1)
    local value = vp * count
    local cd = RECHARGE[id]
    local crafts, cost, profit, first, last, stop = 0, 0, 0, nil, nil, cd and "cd" or "cap"
    while crafts < (cd and 1 or MAX_CRAFTS) do
        local c = 0
        for _, x in ipairs(need) do
            local cc = take(x, x.n)
            if not cc then c = nil break end
            c = c + cc
        end
        if not c then stop = "stock" break end
        if c >= value then stop = "price" break end
        for _, x in ipairs(need) do commit(x) end
        crafts, cost, profit = crafts + 1, cost + c, profit + value - c
        first, last = first or c, c
    end
    if crafts == 0 or profit < o.minProfit then return nil end
    local parts = {}
    for _, x in ipairs(need) do
        parts[#parts + 1] = { item = x.item, n = x.n, ah = x.ah, top = x.top, vendor = x.total - x.ah, vp = x.vp }
    end
    local prof = F.ProfName(r.skill)
    local who = ctx.known[id]
    return { id = r.item, spell = id, kind = "craft", q = crafts, cost = cost, profit = profit, ref = value, count = count,
             unit = first, last = last, roi = cost > 0 and profit / cost * 100 or 0, parts = parts, skill = r.skill,
             yellow = r.yellow, gray = r.gray, who = who, ranks = ctx.ranks[prof], mine = who ~= nil or ctx.mine[prof] == true,
             stop = stop, cd = cd }
end

-- duree d une recharge : texte du jeu (SecondsToTime), sinon heures ou minutes
local function duration(s)
    local t = str(AH.call(SecondsToTime, s))
    if t and t ~= "" then return t end
    if s >= 3600 then return math.floor(s / 3600 + 0.5) .. " h" end
    return math.floor(s / 60 + 0.5) .. " min"
end

---------------------------------------------------------------------------
-- Affichage (lignes, infobulle, liste d achats)
---------------------------------------------------------------------------

-- ligne courte : qui la connait (ou le metier), prix marchand, cout, serie
function F.RowText(d)
    local M = AH.Money
    local who
    if d.who then
        who = "|cff6be070" .. table.concat(d.who, ", ") .. "|r"
    else
        who = "|cff9d9d9d" .. F.ProfName(d.skill) .. "|r"
    end
    return who .. "|cff9d9d9d · |r|cff6be070" .. string.format(L.FAB_ROW_PNJ, M(d.ref)) .. "|r|cff9d9d9d · "
        .. string.format(L.FAB_ROW_COST, M(d.unit), d.q) .. "|r"
end

-- lignes de l infobulle (format de AH.ItemTip : { texte, r, g, b })
function F.TipLines(d)
    local M = AH.Money
    local out = {}
    out[#out + 1] = { string.format(L.FAB_TIP_HEAD, M(d.ref), F.ProfName(d.skill)), 0.42, 0.88, 0.46 }
    if d.who then
        out[#out + 1] = { string.format(L.FAB_TIP_KNOWN, table.concat(d.who, ", ")), 0.42, 0.88, 0.46 }
    else
        out[#out + 1] = { string.format(L.FAB_TIP_UNKNOWN, d.yellow or 0, d.gray or 0), 1, 0.6, 0.25 }
        local ranks = {}
        for _, rk in ipairs(d.ranks or {}) do ranks[#ranks + 1] = rk[1] .. " " .. rk[2] end
        if #ranks > 0 then out[#out + 1] = { string.format(L.FAB_TIP_RANKS, table.concat(ranks, ", ")), 0.8, 0.8, 0.8 } end
    end
    out[#out + 1] = { string.format(L.FAB_TIP_PARTS, d.q), 1, 0.82, 0 }
    for _, p in ipairs(d.parts) do
        local src = {}
        if p.ah > 0 then src[#src + 1] = string.format(L.FAB_TIP_AH, p.ah, M(p.top)) end
        if p.vendor > 0 then src[#src + 1] = string.format(L.FAB_TIP_VENDOR, p.vendor, M(p.vp or 0)) end
        out[#out + 1] = { string.format(L.FAB_TIP_PART, p.n * d.q, AH.ItemLabel(p.item), table.concat(src, ", ")), 1, 1, 1 }
    end
    out[#out + 1] = { string.format(L.FAB_TIP_FIRST, M(d.unit), M(d.ref - d.unit), M(d.ref - d.last)), 0.8, 0.8, 0.8 }
    if d.cd then
        out[#out + 1] = { string.format(L.FAB_STOP_CD, duration(d.cd)), 1, 0.6, 0.25 }
    else
        out[#out + 1] = { L["FAB_STOP_" .. string.upper(d.stop)] or "", 0.6, 0.6, 0.6 }
    end
    return out
end

-- clic : liste d achats "-> marchand : objet" (onglet Achats) avec ce qu il
-- faut prendre a l HV (quantite de la serie, prix max = le plus cher
-- compte) ; ce qui vient d un marchand est annonce dans le chat
function F.Shop(d)
    local s = AH.ShopDB and AH.ShopDB()
    if not s then return end
    local name = string.format(L.FAB_LIST, AH.ItemLabel(d.id))
    local idx
    for i, l in ipairs(s.lists) do
        if l.name == name then idx = i break end
    end
    if not idx then
        s.lists[#s.lists + 1] = { name = name, items = {} }
        idx = #s.lists
    end
    local items, fromVendor = {}, {}
    for _, p in ipairs(d.parts) do
        if p.ah > 0 then items[#items + 1] = { id = p.item, qty = p.ah, max = math.ceil(p.top) } end
        if p.vendor > 0 then fromVendor[#fromVendor + 1] = p.vendor .. " " .. AH.ItemLabel(p.item) end
    end
    s.lists[idx].items = items
    s.sel = idx
    local msg = string.format(L.FAB_LIST_DONE, name, d.q)
    if #fromVendor > 0 then msg = msg .. " " .. string.format(L.FAB_LIST_VENDOR, table.concat(fromVendor, ", ")) end
    ns.Say(msg)
    if AH.SelectTab then AH.SelectTab("buy") end
end
