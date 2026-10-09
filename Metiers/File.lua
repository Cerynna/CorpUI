--[[--------------------------------------------------------------------------
    CorpUI - module Metiers : file de fabrication (facon Skillet)

    Fenetre des metiers de Blizzard (ProfessionsFrame, Blizzard_Professions
    charge a la demande, variante Camelot) :
      - sous la recette choisie, NOTRE barre : +1 / +10 / +20 (ajout
        direct), quantite libre + "Ajouter a la file" (la recette courante
        est lue par SchematicForm:GetRecipeInfo, qui renvoie seulement son
        champ currentRecipeInfo) ;
      - a droite du rail d onglets, NOTRE volet : onglets "File" et
        "Courses" (Courses.lua), repliable.
    File : par personnage (CorpUIDB.crafting.queues["Nom-Royaume"]), entrees
    { id = recette, n = fabrications, skill = metier, prof = nom }. A l ajout,
    les composants manquants que le personnage sait fabriquer (index de ses
    recettes apprises, rempli a l ouverture de chaque metier) passent avant,
    selon le reglage subDepth : "none" (rien), "one" (composants directs
    seulement, par defaut), "all" (recursif) ; avec une garde anti-boucle
    (une sous-recette qui aurait besoin de ce que fabrique la chaine en
    cours n est pas mise : son composant reste dans les courses). Une
    recette deja en file y gagne des fabrications (une ligne par recette).
    Acheter ou fabriquer (option ahChoice, module Encheres) : un composant
    manquant fabricable n est fabrique que si c est moins cher que de
    l acheter, d apres l echelle des prix HV (ns.AHCost) : achat direct du
    manque contre achat des composants qui manqueraient a la fabrication
    (apres sacs, banque et file), chacun pour les exemplaires en plus de
    ce que la file achete deja. Une borne basse (echelle courte, scan sans
    echelle) ne decide que si elle suffit a conclure. Fabrique aussi si
    l achat est impossible (pas de prix, pas assez en vente) ou sans
    conclusion (comportement d avant) ; meme choix a chaque niveau en "all".
    "Fabriquer" (clic) : C_TradeSkillUI.CraftRecipe(recette, nombre), sans
    restriction dans la doc forever, sur la premiere entree du metier
    ouvert qui a ses composants ET que Blizzard laisserait faire (apprise,
    active, pas en recharge, exigences comme l enclume remplies). Decompte
    par UNIT_SPELLCAST_SUCCEEDED (sort = recette) ; si le sort est secret,
    par TRADE_SKILL_ITEM_CRAFTED_RESULT (objet produit). Le suivi continue
    fenetre fermee ou en combat (la serie de Blizzard continue aussi) ; il
    s arrete sur interruption, echec (meme pendant l appel : ces evenements
    sont synchrones), UPDATE_TRADESKILL_CAST_STOPPED, ou faute d activite
    (GetRemainingRecasts a 0).
    Benefice HV (module Encheres, option ahProfit) : dans chaque ligne de la
    file, valeur de vente du produit (prix x yield) moins le cout des
    composants, pour N fabrications ; gris et borne ("max") si un composant
    n a pas de prix ou est illisible (rouge "perte X+" si la borne est deja
    negative), le cout seul si le produit n en a pas. Brut : la commission
    de l HV n est pas deduite (dit dans l infobulle). Cout des composants :
    les N x quantite moins chers de l echelle des prix ; une estimation
    (pas assez en vente, scan sans echelle) est une borne basse du cout :
    meme traitement qu un composant sans prix ("max", "+").

    Regles de ce client : nos cadres sont enfants d UIParent et seulement
    ancres sur ceux de Blizzard ; aucun crochet, aucun champ ecrit chez
    Blizzard ; toute valeur lue passe par pcall / issecretvalue ; en
    combat, aucune action (fabrication, achat, banque) ni construction ou
    placement : des lectures, cacher nos propres cadres, compter les
    fabrications.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L
local C = ns.COLORS

local issecret = issecretvalue or function() return false end

local M = {}
ns.Craft = M
M.listeners = {}

local db            -- CorpUIDB.crafting

---------------------------------------------------------------------------
-- Valeurs lues dans le jeu
---------------------------------------------------------------------------

local function plain(v)
    if issecret(v) then return nil end
    return v
end
local function num(v)
    v = plain(v)
    if type(v) == "number" then return v end
end
local function str(v)
    v = plain(v)
    if type(v) == "string" and v ~= "" then return v end
end
local function yes(v)
    if issecret(v) then return false end
    return v == true
end
-- champ d une table de Blizzard, en lecture seule
local function field(t, key)
    if type(t) ~= "table" then return nil end
    local ok, v = pcall(function() return t[key] end)
    if ok and not issecret(v) then return v end
end
-- appel protege a C_TradeSkillUI (premier retour)
local function TS(fn, ...)
    local f = C_TradeSkillUI and C_TradeSkillUI[fn]
    if not f then return nil end
    local ok, a = pcall(f, ...)
    if ok and not issecret(a) then return a end
end
local function visible(f)
    if type(f) ~= "table" or not f.IsVisible then return false end
    local ok, v = pcall(f.IsVisible, f)
    return ok and yes(v)
end
-- largeur du texte entier d une de nos chaines : GetStringWidth rend la
-- largeur affichee, bornee des qu une largeur est posee ; on prend la
-- mesure sans borne quand le client l a (nil si illisible)
local function textWidth(fs)
    for _, k in ipairs({ "GetUnboundedStringWidth", "GetStringWidth" }) do
        local fn = fs[k]
        if fn then
            local ok, w = pcall(fn, fs)
            if ok and not issecret(w) and type(w) == "number" then return w end
        end
    end
end
M.plain, M.num, M.str, M.yes, M.field, M.TS, M.TextWidth = plain, num, str, yes, field, TS, textWidth

---------------------------------------------------------------------------
-- Sauvegarde
---------------------------------------------------------------------------

-- valeurs par defaut d une sauvegarde (aussi pour une ancienne : la case
-- autoSub devient la profondeur subDepth, decochee -> "none", sinon "one")
local DEPTH = { none = 0, one = 1, all = 8 }
function M.Defaults(d)
    for _, k in ipairs({ "queues", "recipes", "known", "pane", "shopWin" }) do
        if type(d[k]) ~= "table" then d[k] = {} end
    end
    if not DEPTH[d.subDepth] then d.subDepth = (d.autoSub == false) and "none" or "one" end
    d.autoSub = nil
    if d.autoBuy == nil then d.autoBuy = true end
    if d.shopWindow == nil then d.shopWindow = true end
    if d.showPane == nil then d.showPane = true end
    if d.ahProfit == nil then d.ahProfit = true end
    if d.ahChoice == nil then d.ahChoice = true end
    return d
end

function M.Init()
    if db then return db end
    local root = ns.InitRoot()
    if type(root.crafting) ~= "table" then root.crafting = {} end
    db = M.Defaults(root.crafting)
    return db
end

function M.DB() return db end

-- niveaux de sous-composants mis en file : 0, 1, ou 8 (garde de recursion)
function M.SubDepth() return DEPTH[db and db.subDepth] or 1 end

function M.Queue()
    local k = ns.CharKey()
    if type(db.queues[k]) ~= "table" then db.queues[k] = {} end
    return db.queues[k]
end

local function known()
    local k = ns.CharKey()
    if type(db.known[k]) ~= "table" then db.known[k] = {} end
    return db.known[k]
end

function M.Recipe(id) return db and db.recipes[id] end

-- la file ou les quantites ont change : volet, liste de courses
function M.Changed()
    for _, fn in ipairs(M.listeners) do pcall(fn) end
end

---------------------------------------------------------------------------
-- Metier ouvert et recettes
---------------------------------------------------------------------------

-- metier ouvert : identifiant (le parent s il y en a un) et nom
function M.CurrentProf()
    local info = TS("GetChildProfessionInfo")
    local id = type(info) == "table" and num(info.professionID)
    if not id or id == 0 then
        info = TS("GetBaseProfessionInfo")
        id = type(info) == "table" and num(info.professionID)
    end
    if type(info) ~= "table" then return nil end
    local parent = num(info.parentProfessionID)
    if parent and parent > 0 then id = parent end
    if not id or id == 0 then return nil end
    return id, str(info.parentProfessionName) or str(info.professionName) or "?"
end

-- un metier a nous (pas un lien, ni la guilde, ni un PNJ)
function M.OwnSkill()
    return not (yes(TS("IsTradeSkillLinked")) or yes(TS("IsTradeSkillGuild")) or yes(TS("IsNPCCrafting"))
        or yes(TS("IsRuneforging")))
end

-- emplacement de composant ordinaire (pas optionnel ni modifiant)
local function basicSlot(s)
    local t = num(s.reagentType)
    local E = Enum and Enum.CraftingReagentType
    local basic = E and num(E.Basic)
    if t and basic then return t == basic end
    return plain(s.required) ~= false
end

-- schema d une recette, garde dans db.recipes (commun au compte) :
-- { name, icon, out = objet produit, yield = produits par fabrication,
--   reagents = { { objet, quantite } }, skill, prof, special }
function M.ReadRecipe(id, skill, prof)
    local old = db.recipes[id]
    local sch = TS("GetRecipeSchematic", id, false)
    if type(sch) ~= "table" then return old end
    local r = { reagents = {} }
    r.name = str(sch.name)
    r.icon = num(sch.icon)
    r.out = num(sch.outputItemID)
    r.yield = math.max(1, num(sch.quantityMin) or 1)
    -- composants illisibles (liste, emplacement, objet ou quantite secrets) :
    -- comptes dans unread, le cout HV de la recette est alors incomplet
    local unread = 0
    local slots = sch.reagentSlotSchematics
    if issecret(slots) then
        unread = 1
    elseif type(slots) == "table" then
        for _, s in ipairs(slots) do
            if issecret(s) then
                unread = unread + 1
            elseif type(s) == "table" and basicSlot(s) then
                local list = plain(s.reagents)
                local first = type(list) == "table" and plain(list[1])
                local item = type(first) == "table" and num(first.itemID)
                local n = num(s.quantityRequired)
                if item and n then
                    if n > 0 then table.insert(r.reagents, { item, n }) end
                else
                    unread = unread + 1
                end
            end
        end
    end
    if unread > 0 then r.unread = unread end
    local info = TS("GetRecipeInfo", id)
    if type(info) == "table" then
        r.name = r.name or str(info.name)
        r.icon = r.icon or num(info.icon)
        -- enchantement (cible), recyclage, recolte : hors file
        if yes(info.isEnchantingRecipe) or yes(info.isSalvageRecipe) or yes(info.isGatheringRecipe)
            or yes(info.isDummyRecipe) or yes(info.isRecraft) then
            r.special = true
        end
    end
    if not r.name then return old end
    r.skill = skill or (old and old.skill)
    r.prof = prof or (old and old.prof)
    db.recipes[id] = r
    return r
end

-- index des recettes apprises du metier ouvert : objet produit -> recette
-- (une fois par metier et par session, a nouveau apres un apprentissage)
local indexed = {}
function M.Index(force)
    if not db or InCombatLockdown() then return end
    local skill, prof = M.CurrentProf()
    if not skill or not M.OwnSkill() then return end
    if indexed[skill] and not force then return end
    local ids = TS("GetAllRecipeIDs") or TS("GetFilteredRecipeIDs")
    if type(ids) ~= "table" or #ids == 0 then return end
    indexed[skill] = true
    local k = known()
    for _, id in ipairs(ids) do
        id = num(id)
        local info = id and TS("GetRecipeInfo", id)
        if type(info) == "table" and yes(info.learned) then
            local r = M.ReadRecipe(id, skill, prof)
            if r and r.out and not r.special then k[r.out] = id end
        end
    end
end
function M.ForgetIndex() wipe(indexed) end

-- recette du personnage qui produit cet objet
function M.Producer(item)
    local id = known()[item]
    local r = id and db.recipes[id]
    if r and r.out == item and not r.special then return id, r end
end

-- recette apprise ? (faux seulement si le jeu le dit clairement : la liste
-- de Blizzard montre aussi les recettes non apprises)
function M.Learned(id)
    local info = TS("GetRecipeInfo", id)
    return not (type(info) == "table" and plain(info.learned) == false)
end

-- ce qui empeche Blizzard de lancer la recette, composants mis a part
-- (comme ProfessionsCraftingPageMixin:ValidateCraftRequirements) : non
-- apprise, desactivee, en recharge, exigence non remplie (enclume, forge,
-- feu...). Renvoie la raison, ou nil. Toutes les lectures sont protegees.
function M.Blocked(id)
    local info = TS("GetRecipeInfo", id)
    if type(info) == "table" then
        if plain(info.learned) == false then return L.CRAFT_WHY_UNLEARNED end
        if plain(info.craftable) == false or yes(info.disabled) then
            return str(info.disabledReason) or L.CRAFT_WHY_OFF
        end
    end
    local cdf = C_TradeSkillUI and C_TradeSkillUI.GetRecipeCooldown
    if cdf then
        -- comme Professions.IsRecipeOnCooldown : une recharge sans charge libre
        local ok, cd, _, charges = pcall(cdf, id)
        cd, charges = ok and num(cd), ok and num(charges)
        if cd and cd > 0 and not (charges and charges > 0) then return L.CRAFT_WHY_CD end
    end
    local reqs = TS("GetRecipeRequirements", id)
    if type(reqs) == "table" then
        for _, r in ipairs(reqs) do
            r = plain(r)
            if type(r) == "table" and plain(r.met) == false then
                return string.format(L.CRAFT_WHY_REQ, str(r.name) or "?")
            end
        end
    end
end

---------------------------------------------------------------------------
-- Ce qu on a : sacs, banque
---------------------------------------------------------------------------

-- conteneurs de la banque du personnage : onglets achetes (C_Bank), sinon
-- les numeros fixes des onglets, sinon l ancienne banque
function M.BankBags()
    local list = {}
    local bt = Enum and Enum.BankType and Enum.BankType.Character
    if C_Bank and C_Bank.FetchPurchasedBankTabIDs and bt ~= nil then
        local ok, ids = pcall(C_Bank.FetchPurchasedBankTabIDs, bt)
        if ok and type(ids) == "table" and not issecret(ids) then
            for _, id in ipairs(ids) do
                id = num(id)
                if id then list[#list + 1] = id end
            end
            if #list > 0 then return list end
        end
    end
    local E = Enum and Enum.BagIndex
    if E and E.CharacterBankTab_1 then
        for i = 1, 12 do
            local id = E["CharacterBankTab_" .. i]
            if not id then break end
            list[#list + 1] = id
        end
        return list
    end
    list[1] = BANK_CONTAINER or -1
    local first = ns.FirstBankBag()
    for i = 0, (NUM_BANKBAGSLOTS or 6) - 1 do list[#list + 1] = first + i end
    return list
end

-- banque ouverte : releve exact de ses conteneurs (garde un instant)
local tally, tallyAt
function M.BankTally()
    if tally and tallyAt == GetTime() then return tally end
    tally, tallyAt = {}, GetTime()
    for _, bag in ipairs(M.BankBags()) do
        for slot = 1, ns.BagSlots(bag) do
            local item, count = ns.BagItem(bag, slot)
            item = num(item)
            if item then tally[item] = (tally[item] or 0) + (num(count) or 1) end
        end
    end
    return tally
end
function M.DirtyBank() tally = nil end

-- nombre en banque : releve si elle est ouverte, sinon le compte du
-- client (GetItemCount avec la banque), sinon la note du module Persos
function M.BankCount(id)
    if M.bankOpen then return M.BankTally()[id] or 0 end
    local fn = C_Item and C_Item.GetItemCount
    if fn then
        local ok, all = pcall(fn, id, true)
        all = ok and num(all)
        if all then return math.max(0, all - ns.ItemCount(id)) end
    end
    local alts = ns.root and ns.root.alts
    local me = type(alts) == "table" and alts[ns.CharKey()]
    return (type(me) == "table" and type(me.bank) == "table" and num(me.bank[id])) or 0
end

function M.Have(id)
    return ns.ItemCount(id), M.BankCount(id)
end

---------------------------------------------------------------------------
-- Prix HV (module Encheres, charge apres nous : lus a l appel)
---------------------------------------------------------------------------

-- nombre utilisable : ni secret, ni NaN, ni negatif, ni infini
local function amount(v)
    if issecret(v) or type(v) ~= "number" or v ~= v or v < 0 or v == math.huge then return nil end
    return v
end

-- prix HV d un objet (cuivre, NON arrondi) et son age en secondes ; nil si
-- inconnu, secret, ou module Encheres absent
local function ahPrice(item)
    local fn = ns.AHPrice
    if type(fn) ~= "function" then return nil end
    local ok, p, age = pcall(fn, item)
    if not ok then return nil end
    p = amount(p)
    if not p then return nil end
    return p, amount(age)
end

-- cout HV des n exemplaires les moins chers (cuivre NON arrondi), nombre
-- couvert (< n : pas assez en vente au dernier scan), age, estimation
-- (scan sans echelle : prix minimum x n). Sans ns.AHCost : prix minimum
-- x n, estimation. nil si inconnu, secret ou module absent.
local function ahCost(item, n)
    local fn = ns.AHCost
    if type(fn) ~= "function" then
        local p, age = ahPrice(item)
        if not p then return nil end
        return p * n, n, age, true
    end
    local ok, c, got, age, est = pcall(fn, item, n)
    if not ok then return nil end
    c, got = amount(c), amount(got)
    if not (c and got) then return nil end
    return c, math.min(got, n), amount(age), (not issecret(est)) and est == true
end
M.AHCost = ahCost

-- exemplaires en vente (achat immediat) au dernier scan ; nil si inconnu
local function ahSeen(item)
    local fn = ns.AHPrice
    if type(fn) ~= "function" then return nil end
    local ok, _, _, _, q = pcall(fn, item)
    return ok and amount(q) or nil
end
M.AHSeen = ahSeen

-- cout HV des exemplaires base+1 a base+n quand la file en achete deja
-- "base" (cuivre NON arrondi) : cout, borne (vrai : borne basse), assez
-- (faux : moins de base+n en vente au dernier scan). Echelle trop courte
-- (bornee aux ~1000 moins chers) : le reste de ce qui etait en vente au
-- moins au prix du dernier niveau, et au-dela (autre source) rien ; scan
-- sans echelle : prix minimum x n. nil sans prix.
local function marginal(item, base, n)
    local top = base + n
    local c1, g1, _, est = ahCost(item, top)
    if not c1 then return nil end
    local seen = ahSeen(item)
    if not est and g1 >= top then
        return c1 - (base > 0 and ahCost(item, base) or 0), false, true
    end
    local enough = seen ~= nil and seen >= top
    if est then return c1 - (base > 0 and ahCost(item, base) or 0), true, enough end
    local a = math.min(base, g1)
    local cost = c1 - (a > 0 and ahCost(item, a) or 0)
    local last = g1 > 0 and (c1 - (g1 > 1 and ahCost(item, g1 - 1) or 0)) or 0
    local beyond = math.max(0, math.min(top, seen or g1) - math.max(base, g1))
    return cost + beyond * last, true, enough
end
M.AHMarginal = marginal

-- montant au format HV (arrondi par ns.AHMoney)
local function money(c) return ns.AHMoney(c) end

-- montant avec son cuivre (ns.AHMoney l omet au-dela d une piece d or) :
-- "1po 60pc" et non "1po", pour que "qte x prix = total" se lise
local function exact(c)
    local r = math.floor(c + 0.5)
    if r >= 10000 and r % 100 > 0 then return money(r - r % 100) .. " " .. money(r % 100) end
    return money(c)
end

-- choix acheter ou fabriquer : option cochee et echelle des prix presente
function M.ChoiceOn()
    return db ~= nil and db.ahChoice ~= false and type(ns.AHCost) == "function" and type(ns.AHMoney) == "function"
end

---------------------------------------------------------------------------
-- File
---------------------------------------------------------------------------

-- besoins de toute la file : composants requis et objets produits. Une
-- production ne compte pas si sa recette a besoin, directement ou par les
-- recettes de la file, de ce qu elle produit (boucle A <-> B, transmutations
-- reciproques) : elle ne peut pas payer son propre composant, qui reste
-- donc dans les courses.
function M.Totals()
    local need, made, producers = {}, {}, {}
    local q = M.Queue()
    for _, e in ipairs(q) do
        local r = db.recipes[e.id]
        if r then
            for _, g in ipairs(r.reagents or {}) do need[g[1]] = (need[g[1]] or 0) + g[2] * e.n end
            if r.out then
                producers[r.out] = producers[r.out] or {}
                table.insert(producers[r.out], r)
            end
        end
    end
    local function dependsOn(r, item, seen)
        for _, g in ipairs(r.reagents or {}) do
            if g[1] == item then return true end
            if not seen[g[1]] then
                seen[g[1]] = true
                for _, p in ipairs(producers[g[1]] or {}) do
                    if dependsOn(p, item, seen) then return true end
                end
            end
        end
        return false
    end
    local loops = {}
    for _, e in ipairs(q) do
        local r = db.recipes[e.id]
        if r and r.out then
            if loops[e.id] == nil then loops[e.id] = dependsOn(r, r.out, {}) end
            if not loops[e.id] then made[r.out] = (made[r.out] or 0) + (r.yield or 1) * e.n end
        end
    end
    return need, made
end

-- rang d une entree (par reference : les insertions decalent les rangs)
local function indexOf(e)
    for i, x in ipairs(M.Queue()) do if x == e then return i end end
end

-- entree existante ou ajouter une recette, placee avant "anchor" (avant
-- tout sans anchor) : pour un sous-composant la premiere (prete au plus
-- tot), pour la recette ajoutee sa derniere ; nil s il n y en a pas
local function entryFor(id, anchor, first)
    local q = M.Queue()
    local stop = (anchor and indexOf(anchor) or (#q + 1)) - 1
    local a, b, step = stop, 1, -1
    if first then a, b, step = 1, stop, 1 end
    for i = a, b, step do
        if q[i].id == id then return q[i] end
    end
end

-- n fabrications sur l entree e, sinon une nouvelle entree juste avant
-- "anchor" (en fin de file sans anchor)
local function push(e, id, n, r, anchor)
    if e then e.n = e.n + n return end
    local q = M.Queue()
    table.insert(q, anchor and indexOf(anchor) or (#q + 1), { id = id, n = n, skill = r.skill, prof = r.prof })
end

-- combien il manque de cet objet pour en prendre "want" une fois servi le
-- reste de la file
local function missingOf(item, want)
    local need, made = M.Totals()
    local bags, bank = M.Have(item)
    local free = math.max(0, bags + bank + (made[item] or 0) - (need[item] or 0))
    return want - free
end

-- Acheter ou fabriquer "missing" exemplaires de item (recette sr) : vrai =
-- fabriquer. pend = composants des recettes en cours d ajout (pas encore
-- dans la file). Chaque cout est celui des exemplaires EN PLUS de ce que
-- la file achete deja (marginal : un ajout ne revoit pas les lots les
-- moins chers deja pris). Achat : les "missing" suivants de l echelle.
-- Fabrication : ce qui manquerait en plus de chaque composant de sr pour
-- ceil(missing / yield) fabrications, achete a l HV. On achete si l achat
-- est exact et ne coute pas plus que la fabrication (meme bornee par le
-- bas : echelle courte, scan sans echelle) ; on fabrique si la fabrication
-- est exacte et moins chere que l achat (meme borne basse). Sinon (option
-- coupee, achat impossible : pas de prix ou pas assez en vente, composant
-- sans prix, ou deux bornes sans conclusion) : fabriquer, comme avant,
-- sans rien dire. Renvoie fabriquer, achat, fabrication, et si chacun est
-- une borne basse.
local function craftOrBuy(item, missing, sr, pend)
    if not M.ChoiceOn() then return true end
    if (tonumber(sr.unread) or 0) > 0 then return true end
    local need, made = M.Totals()
    -- ce que la file achetera de it (recettes en cours comprises), plus extra
    local function bought(it, extra)
        local bags, bank = M.Have(it)
        return math.max(0, (need[it] or 0) + (pend[it] or 0) + (extra or 0) - (made[it] or 0) - bags - bank)
    end
    local buy, buyLow, enough = marginal(item, math.max(0, bought(item) - missing), missing)
    if not buy or not enough then return true end
    local crafts = math.ceil(missing / math.max(1, sr.yield or 1))
    local craft, craftLow = 0, false
    for _, rg in ipairs(sr.reagents or {}) do
        local it = rg[1]
        local before = bought(it)
        local short = bought(it, rg[2] * crafts) - before
        if short > 0 then
            local c, low, ok = marginal(it, before, short)
            if not c then return true end
            craft = craft + c
            if low or not ok then craftLow = true end
        end
    end
    if not buyLow and craft >= buy then return false, buy, craft, false, craftLow end
    if not craftLow and craft < buy then return true, buy, craft, buyLow, false end
    return true
end

-- ajoute n fabrications de la recette (et avant elle les sous-composants
-- manquants que l on sait fabriquer, jusqu a la profondeur reglee : "one"
-- = seulement ceux de la recette ajoutee ; s ils sont moins chers a
-- fabriquer qu a acheter, voir craftOrBuy) ; une recette deja dans la file
-- y gagne des fabrications (une ligne par recette, sous-composants
-- avant ce qui les consomme) ; renvoie { { id, n, sub } } et les choix
-- acheter / fabriquer faits sur prix : { { item, craft, buy, cost, buyLow,
-- costLow } } (montants cumules par objet, *Low : borne basse)
function M.Add(recipeID, n, skill, prof)
    if not db or not recipeID or not n or n < 1 then return {}, {} end
    if not M.Learned(recipeID) then return {}, {} end
    local added, guard, choices, pend = {}, {}, {}, {}
    local maxDepth = M.SubDepth()
    local function note(id, count, sub)
        for _, a in ipairs(added) do
            if a.id == id and a.sub == sub then a.n = a.n + count return end
        end
        added[#added + 1] = { id = id, n = count, sub = sub }
    end
    -- composants d une recette en cours d ajout (sign = 1), puis rendus
    -- (sign = -1) quand elle entre dans la file
    local function hold(r, count, sign)
        for _, g in ipairs(r.reagents or {}) do pend[g[1]] = (pend[g[1]] or 0) + sign * g[2] * count end
    end
    -- un choix par objet : une fabrication l emporte sur un achat (c est
    -- elle qui change la file, le reste achete se lit dans les courses),
    -- deux choix pareils cumulent leurs montants ; renvoie de quoi
    -- l annuler (nil : rien change)
    local function chose(item, craft, buy, cost, buyLow, costLow)
        for _, c in ipairs(choices) do
            if c.item == item then
                if c.craft and not craft then return nil end
                local undo = { c = c, old = { c.craft, c.buy, c.cost, c.buyLow, c.costLow } }
                if c.craft == craft then
                    c.buy, c.cost = c.buy + buy, c.cost + cost
                    c.buyLow, c.costLow = c.buyLow or buyLow, c.costLow or costLow
                else
                    c.craft, c.buy, c.cost, c.buyLow, c.costLow = craft, buy, cost, buyLow, costLow
                end
                return undo
            end
        end
        local c = { item = item, craft = craft, buy = buy, cost = cost, buyLow = buyLow, costLow = costLow }
        choices[#choices + 1] = c
        return { c = c }
    end
    local function unchose(undo)
        local c, o = undo.c, undo.old
        if o then
            c.craft, c.buy, c.cost, c.buyLow, c.costLow = o[1], o[2], o[3], o[4], o[5]
        else
            for i, x in ipairs(choices) do if x == c then table.remove(choices, i) break end end
        end
    end
    -- renvoie vrai si la recette est mise dans la file (avant "anchor")
    local function add(id, count, depth, anchor)
        if depth > maxDepth or guard[id] then return false end
        local r = db.recipes[id]
        if depth == 0 or not r then r = M.ReadRecipe(id, depth == 0 and skill or nil, depth == 0 and prof or nil) end
        if not r or r.special then return false end
        if depth > 0 then
            -- boucle : il lui manque un objet que seule une recette de la
            -- chaine en cours fabrique (elle passerait apres) ; on ne la met
            -- pas, le parent garde son composant en manque (courses)
            for _, g in ipairs(r.reagents or {}) do
                if missingOf(g[1], g[2] * count) > 0 then
                    local sub = M.Producer(g[1])
                    if sub and guard[sub] then return false end
                end
            end
        end
        guard[id] = true
        -- entree visee : ses sous-composants passent avant elle (ou avant
        -- "anchor" si elle n existe pas encore)
        local e = entryFor(id, anchor, depth > 0)
        if depth < maxDepth then
            -- manque pour "want" : ce qui etait libre au depart, moins ce
            -- que les sous-recettes ajoutees ici consomment, plus ce
            -- qu elles produisent (un manque d avant reste aux courses)
            local need0, made0 = M.Totals()
            local function deficit(item, want)
                local need, made = M.Totals()
                local bags, bank = M.Have(item)
                local free0 = math.max(0, bags + bank + (made0[item] or 0) - (need0[item] or 0))
                return want - free0 + ((need[item] or 0) - (need0[item] or 0)) - ((made[item] or 0) - (made0[item] or 0))
            end
            -- passages repetes tant qu une sous-recette est ajoutee : elle
            -- peut consommer un composant deja vu (le resultat ne depend
            -- plus de l ordre des emplacements) ; un composant qu un ajout
            -- ne fait pas baisser n est plus repris
            local stuck = {}
            hold(r, count, 1)
            for _ = 1, 6 do
                local more = false
                for _, g in ipairs(r.reagents or {}) do
                    local item, want = g[1], g[2] * count
                    local missing = stuck[item] and 0 or deficit(item, want)
                    if missing > 0 then
                        local sub, sr = M.Producer(item)
                        local craft, buy, cost, buyLow, costLow = true, nil, nil, false, false
                        if sub and not guard[sub] then craft, buy, cost, buyLow, costLow = craftOrBuy(item, missing, sr, pend) end
                        -- fabrication choisie sur prix : dite avant celles
                        -- des niveaux en dessous, retiree si rien n est mis
                        -- (rien a dire si tout est deja la : cout 0)
                        local undo = craft and buy and cost > 0 and chose(item, true, buy, cost, buyLow, costLow)
                        if sub and not guard[sub] and craft and add(sub, math.ceil(missing / (sr.yield or 1)), depth + 1, e or anchor)
                            and deficit(item, want) < missing then
                            more = true
                        else
                            stuck[item] = true
                            if undo then unchose(undo) end
                            -- achat direct choisi : l objet reste aux courses
                            if buy and not craft then chose(item, false, buy, cost, buyLow, costLow) end
                        end
                    end
                end
                if not more then break end
            end
            hold(r, count, -1)
        end
        push(e, id, count, r, anchor)
        note(id, count, depth > 0)
        guard[id] = nil
        return true
    end
    add(recipeID, math.floor(n), 0)
    M.Changed()
    return added, choices
end

-- phrases des choix acheter / fabriquer (message de l ajout) : montants
-- au cuivre pres, "+" sur une borne basse ; rien a dire si les deux
-- montants affiches sont egaux
function M.ChoiceText(choices)
    local out = {}
    for _, c in ipairs(choices or {}) do
        local name = ns.ItemName(c.item) or ("item:" .. tostring(c.item))
        local b, f = exact(c.buy), exact(c.cost)
        if b ~= f then
            b, f = b .. (c.buyLow and "+" or ""), f .. (c.costLow and "+" or "")
            if c.craft then
                out[#out + 1] = string.format(L.CRAFT_CHOICE_CRAFT, name, f, b)
            else
                out[#out + 1] = string.format(L.CRAFT_CHOICE_BUY, name, b, f)
            end
        end
    end
    return table.concat(out, " ")
end

function M.Move(i, d)
    local q = M.Queue()
    local j = i + d
    if q[i] and q[j] then q[i], q[j] = q[j], q[i] end
    M.Changed()
end

function M.Remove(i)
    table.remove(M.Queue(), i)
    M.Changed()
end

function M.Clear()
    wipe(M.Queue())
    M.run = nil
    M.Changed()
end

function M.RecipeName(id)
    local r = db.recipes[id]
    return (r and r.name) or ("#" .. tostring(id))
end

---------------------------------------------------------------------------
-- Benefice a l hotel des ventes (prix du module Encheres)
---------------------------------------------------------------------------

-- option cochee et module Encheres charge (prix et format des montants)
function M.ProfitOn()
    return db ~= nil and db.ahProfit ~= false and type(ns.AHPrice) == "function" and type(ns.AHMoney) == "function"
end

-- autre recette de la file qui fabrique l objet item, et son nombre de
-- fabrications (nil sinon)
local function queuedMaker(item, id)
    for _, e in ipairs(M.Queue()) do
        local r = db.recipes[e.id]
        if e.id ~= id and type(r) == "table" and r.out == item then return e.id, e.n end
    end
end

-- bilan HV de n fabrications (1 par defaut), ramene a UNE fabrication
-- (cuivre non arrondi, on arrondit a l affichage ; x n = total exact) :
-- parts = { { objet, qte, prix moyen ou nil, prix = cout de fabrication,
-- estimation } }, cost = cout des composants qui ont un prix, missing =
-- nombre de composants sans prix ou illisibles, unit = prix du produit,
-- value = unit x yield (produit consomme par la file : cette part au cout
-- de son achat a l HV, rebuy), profit = value - cost (seulement si tout est
-- connu, sans estimation), est = un cout estime, age = plus vieux prix
-- pris, known = au moins un prix, sub = un composant est fabrique par la
-- file. Cout d un composant : ses qte x n exemplaires les moins chers de
-- l echelle des prix ; pas assez en vente : le reste au prix moyen deja
-- pris, et scan sans echelle : prix minimum x quantite ; ces estimations
-- sont des bornes basses (est). Un composant fabrique par la file compte a
-- son prix HV (sa ligne a son propre bilan : la somme des lignes est la
-- marge de la chaine) ; sans prix HV, a son cout de fabrication s il est
-- complet (un seul niveau : flat coupe cette recherche, pas de boucle).
-- nil si l option est coupee, le module absent ou la recette inconnue.
function M.Profit(id, n, flat)
    if not M.ProfitOn() then return nil end
    local r = db.recipes[id]
    if type(r) ~= "table" then return nil end
    n = (type(n) == "number" and n >= 1) and math.floor(n) or 1
    local res = { parts = {}, cost = 0, missing = tonumber(r.unread) or 0, yield = math.max(1, r.yield or 1), n = n }
    local function took(age)
        res.known = true
        if age and (not res.age or age > res.age) then res.age = age end
    end
    for _, g in ipairs(r.reagents or {}) do
        local qty = g[2] * n
        local p, age, est
        local total, got, a, e = ahCost(g[1], qty)
        if total and got > 0 then
            p, age, est = total / got, a, e or got < qty
        end
        local maker, makerN
        if not flat then maker, makerN = queuedMaker(g[1], id) end
        local craft
        if maker then
            res.sub = true
            if not p then
                local sp = M.Profit(maker, makerN, true)
                if sp and sp.missing == 0 and #sp.parts > 0 then
                    p, age, est, craft = sp.cost / sp.yield, sp.age, sp.est, true
                end
            end
        end
        res.parts[#res.parts + 1] = { g[1], g[2], p, craft, est }
        if p then
            res.cost = res.cost + p * g[2]
            if est then res.est = true end
            took(age)
        else
            res.missing = res.missing + 1
        end
    end
    if r.out then
        local p, age = ahPrice(r.out)
        if p then
            -- produit consomme par la file : cette part vaut ce que couterait
            -- son achat (echelle des prix, si elle la couvre), le reste le
            -- prix minimum (vente)
            res.unit, res.value = p, p * res.yield
            local qty = res.yield * n
            local k = math.min(qty, (M.Totals())[r.out] or 0)
            if k > 0 then
                local c, got, _, est = ahCost(r.out, k)
                if c and got >= k and not est then
                    local value = c + p * (qty - k)
                    res.unit, res.value, res.rebuy = value / qty, value / n, true
                end
            end
            took(age)
        end
    end
    if res.value and res.missing == 0 and not res.est then res.profit = res.value - res.cost end
    return res
end

-- montant au format HV, avec son signe
local function signed(c)
    if c >= 0.005 then return "+" .. money(c) end
    if c <= -0.005 then return "-" .. money(-c) end
    return money(0)
end
local GREEN, RED, GREY = { 0.42, 0.88, 0.46 }, { 1, 0.38, 0.38 }, { 0.6, 0.6, 0.6 }
local function tone(c)
    if c >= 0.005 then return GREEN end
    if c <= -0.005 then return RED end
    return C.text
end

-- texte court et couleur pour la ligne de la file (n fabrications) ; ""
-- s il n y a rien de sur a dire. Cout incomplet ou estime (borne basse) :
-- le benefice n est qu une borne haute ("max", gris), sauf si elle est
-- deja negative : la perte est alors sure ("perte X+", rouge) ; produit
-- sans prix : le cout seul.
function M.ProfitText(id, n)
    n = n or 1
    local pr = M.Profit(id, n)
    if not pr or not pr.known then return "", GREY end
    if pr.profit then
        return signed(pr.profit * n), tone(pr.profit * n)
    elseif pr.value then
        local b = (pr.value - pr.cost) * n
        if b <= -0.005 then return string.format(L.CRAFT_AH_LOSS, money(-b)), RED end
        return string.format(L.CRAFT_AH_MAX, signed(b)), GREY
    end
    local fmt = (pr.missing > 0 or pr.est) and L.CRAFT_AH_COST_MIN or L.CRAFT_AH_COST
    return string.format(fmt, money(pr.cost * n)), GREY
end

-- detail dans l infobulle d une ligne de la file (prix moyens sur les
-- quantites de toute la ligne)
local function profitTooltip(t, e)
    local pr = M.Profit(e.id, e.n)
    if not pr or not pr.known then return end
    local G, T = C.gold, C.text
    t:AddLine(" ")
    t:AddLine(L.CRAFT_AH_HEAD, G[1], G[2], G[3])
    for _, part in ipairs(pr.parts) do
        local item, q, p = part[1], part[2], part[3]
        -- "*" : cout de fabrication dans la file (pas de prix HV) ;
        -- "+" : estimation, au moins ce montant
        local right = p and (q .. " x " .. exact(p) .. (part[4] and "*" or "") .. " = " .. money(p * q) .. (part[5] and "+" or ""))
            or (q .. " x ?")
        t:AddDoubleLine(ns.ItemName(item) or ("item:" .. item), right, T[1], T[2], T[3], 1, 1, 1)
    end
    local cost = money(pr.cost)
    if pr.missing > 0 or pr.est then cost = string.format(L.CRAFT_AH_ATLEAST, cost) end
    t:AddDoubleLine(L.CRAFT_AH_COST_L, cost, G[1], G[2], G[3], 1, 1, 1)
    local value = "?"
    if pr.value then
        value = money(pr.value)
        if pr.yield > 1 then value = pr.yield .. " x " .. exact(pr.unit) .. " = " .. value end
    end
    t:AddDoubleLine(pr.rebuy and L.CRAFT_AH_VALUE_REBUY or L.CRAFT_AH_VALUE, value, G[1], G[2], G[3], 1, 1, 1)
    if pr.value then
        local one = pr.value - pr.cost
        local function line(label, c)
            if pr.profit then
                local k = tone(c)
                t:AddDoubleLine(label, signed(c), G[1], G[2], G[3], k[1], k[2], k[3])
            elseif c <= -0.005 then
                -- cout incomplet mais deja au-dessus de la vente : perte sure
                t:AddDoubleLine(label, string.format(L.CRAFT_AH_LOSS, money(-c)), G[1], G[2], G[3], RED[1], RED[2], RED[3])
            else
                t:AddDoubleLine(label, string.format(L.CRAFT_AH_UPTO, signed(c)), G[1], G[2], G[3], GREY[1], GREY[2], GREY[3])
            end
        end
        line(L.CRAFT_AH_PROFIT, one)
        if e.n > 1 then line(string.format(L.CRAFT_AH_PROFIT_N, e.n), one * e.n) end
    end
    if pr.missing > 0 then t:AddLine(string.format(L.CRAFT_AH_MISSING, pr.missing), GREY[1], GREY[2], GREY[3], true) end
    if pr.est then t:AddLine(L.CRAFT_AH_ESTNOTE, GREY[1], GREY[2], GREY[3], true) end
    if pr.sub then t:AddLine(L.CRAFT_AH_SUBNOTE, GREY[1], GREY[2], GREY[3], true) end
    if not pr.value then t:AddLine(L.CRAFT_AH_NOVALUE, GREY[1], GREY[2], GREY[3], true) end
    if pr.age then t:AddLine(string.format(L.CRAFT_AH_AGE, ns.FormatAgo(time() - pr.age)), GREY[1], GREY[2], GREY[3]) end
end

---------------------------------------------------------------------------
-- Fabrication
---------------------------------------------------------------------------

-- M.run = { id = recette, count = lancees, left = restantes, entry =,
--           at = heure du lancement, started = un sort a demarre,
--           casting = sort en cours, last = derniere activite }

-- premiere entree d un autre metier que celui ouvert
function M.NextOther(skill)
    for _, e in ipairs(M.Queue()) do
        if e.skill ~= skill then return e end
    end
end

-- premiere entree realisable du metier ouvert, et combien. Une entree qui
-- a ses composants mais que Blizzard refuserait (recharge, enclume...) est
-- passee, pour ne pas bloquer les suivantes ; sinon nil, nil, la raison
-- de la premiere entree ainsi passee.
function M.NextHere(skill)
    local why
    for _, e in ipairs(M.Queue()) do
        if e.skill == skill then
            local can = num(TS("GetCraftableCount", e.id)) or 0
            if can > 0 then
                local block = M.Blocked(e.id)
                if not block then return e, math.min(e.n, can) end
                why = why or string.format(L.CRAFT_BLOCKED, M.RecipeName(e.id), block)
            end
        end
    end
    return nil, nil, why
end

local function stop(say)
    if not M.run then return end
    M.run = nil
    if say then ns.Say(L.CRAFT_STOPPED) end
    M.Changed()
end
M.Stop = stop

-- un sort de la serie a vraiment demarre (ou reussi, s il est instantane)
local function started(run)
    run.last = GetTime()
    if run.started then return end
    run.started = true
    ns.Say(string.format(L.CRAFT_START, run.count, M.RecipeName(run.id)))
end

-- clic sur "Fabriquer"
function M.CraftNext()
    if InCombatLockdown() then ns.Say(L.CRAFT_COMBAT) return end
    if M.run then ns.Say(L.CRAFT_BUSY) return end
    local q = M.Queue()
    if #q == 0 then ns.Say(L.CRAFT_EMPTY) return end
    local skill = M.CurrentProf()
    if not skill or not M.OwnSkill() then ns.Say(L.CRAFT_NOT_OWN) return end
    local e, count, why = M.NextHere(skill)
    if not e then
        local other = M.NextOther(skill)
        local mine = false
        for _, x in ipairs(q) do if x.skill == skill then mine = true end end
        if mine or not other then
            ns.Say(why or L.CRAFT_NOTHING)
        else
            ns.Say(string.format(L.CRAFT_NEXT_PROF, M.RecipeName(other.id), other.prof or "?"))
        end
        M.Changed()
        return
    end
    if not (C_TradeSkillUI and C_TradeSkillUI.CraftRecipe) then return end
    -- le suivi existe AVANT l appel : un refus du client (UNIT_SPELLCAST_FAILED,
    -- evenement synchrone) arrive pendant CraftRecipe et doit le trouver
    local run = { id = e.id, count = count, left = count, entry = e, at = GetTime() }
    M.run = run
    local ok = pcall(C_TradeSkillUI.CraftRecipe, e.id, count)
    if not ok then
        if M.run == run then M.run = nil end
        ns.Say(L.CRAFT_STOPPED)
    end
    -- l annonce vient au premier sort demarre (started)
    M.Changed()
end

-- surveillance (toutes les 0,2 s, combat compris : lectures seulement) :
-- refus sans evenement, ou serie finie sans UPDATE_TRADESKILL_CAST_STOPPED
local function watch()
    local run = M.run
    if not run or run.casting then return end
    local now = GetTime()
    local recasts = num(TS("GetRemainingRecasts"))
    if not run.started then
        -- rien n a demarre : refuse (recharge, enclume, mouvement...)
        if (now - run.at > 3 and (recasts or 0) <= 0) or now - run.at > 10 then stop(true) end
        return
    end
    local idle = now - (run.last or run.at)
    if (idle > 2 and recasts == 0) or idle > 15 then stop(false) end
end

-- une fabrication de la recette en cours vient de reussir
local function crafted()
    local run = M.run
    if not run then return end
    started(run)
    run.casting = false
    local e = run.entry
    run.left = run.left - 1
    local i = indexOf(e)
    if i then
        e.n = e.n - 1
        if e.n <= 0 then
            table.remove(M.Queue(), i)
            ns.Say(string.format(L.CRAFT_DONE, M.RecipeName(e.id)))
        end
    end
    if run.left <= 0 or not i or e.n <= 0 then
        M.run = nil
        -- la suite : autre metier ? on le dit (pas d ouverture automatique)
        local skill = M.CurrentProf()
        local q = M.Queue()
        if #q > 0 and skill and not M.NextHere(skill) then
            local other = M.NextOther(skill)
            if other then ns.Say(string.format(L.CRAFT_NEXT_PROF, M.RecipeName(other.id), other.prof or "?")) end
        end
    end
    M.Changed()
end

-- ouvrir le metier d une entree (clic) : C_TradeSkillUI.OpenTradeSkill,
-- sans restriction dans la doc ; sinon on laisse faire le joueur
function M.OpenProf(e)
    if InCombatLockdown() or not e then return end
    local opened = e.skill and TS("OpenTradeSkill", e.skill)
    if not yes(opened) then ns.Say(string.format(L.CRAFT_OPEN_FAIL, e.prof or "?")) end
end

---------------------------------------------------------------------------
-- Barre sous la recette et volet a droite de la fenetre des metiers
---------------------------------------------------------------------------

local PANE_W, ROW_H, HEAD, FOOT = 260, 34, 32, 74
local bar, pane, expander, queueView, status, craftBtn, clearBtn, openBtn
local profitBox          -- benefice de la recette choisie (sous son nom)
local tabs = {}
local rows, offset = {}, 0

local function professionsFrame()
    local pf = _G.ProfessionsFrame
    if type(pf) == "table" and pf.IsVisible then return pf end
end

local function schematicForm(pf)
    return field(field(pf, "CraftingPage"), "SchematicForm")
end

-- recette affichee par Blizzard (lecture de currentRecipeInfo)
function M.SelectedRecipe()
    local sf = schematicForm(professionsFrame())
    if not visible(sf) then return nil end
    local get = field(sf, "GetRecipeInfo")
    if type(get) ~= "function" then return nil end
    local ok, info = pcall(get, sf)
    if not ok or type(info) ~= "table" or issecret(info) then return nil end
    return num(info.recipeID)
end

local function tip(owner, text)
    local t = ns.Tooltip(owner, "ANCHOR_TOP")
    t:SetText(text)
    t:Show()
end

local function iconButton(parent, texture, text, onClick)
    local b = ns.UI.Button(parent, texture and "" or text, 18, onClick)
    b:SetSize(18, 18)
    if texture then
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetPoint("CENTER")
        t:SetSize(14, 14)
        t:SetTexture(texture)
        t:SetTexCoord(0.22, 0.78, 0.22, 0.78)
        b.icon = t
    end
    b:HookScript("OnEnter", function(self) tip(self, text) end)
    b:HookScript("OnLeave", ns.HideTooltip)
    return b
end

-- ajoute n fabrications de la recette affichee (meme chemin pour les
-- boutons +N et le champ) ; vrai si quelque chose est entre dans la file
local function addSelected(n)
    if InCombatLockdown() then ns.Say(L.CRAFT_COMBAT) return false end
    local id = M.SelectedRecipe()
    if not id then ns.Say(L.CRAFT_NO_RECIPE) return false end
    local skill, prof = M.CurrentProf()
    if not skill or not M.OwnSkill() then ns.Say(L.CRAFT_NOT_OWN) return false end
    if not M.Learned(id) then ns.Say(L.CRAFT_NOT_LEARNED) return false end
    M.Index()
    n = math.max(1, math.min(999, math.floor(n)))
    local added, choices = M.Add(id, n, skill, prof)
    if #added == 0 then ns.Say(L.CRAFT_CANT) return false end
    local parts, subs = {}, {}
    for _, a in ipairs(added) do
        local t = a.n .. " x " .. M.RecipeName(a.id)
        if a.sub then subs[#subs + 1] = t else parts[#parts + 1] = t end
    end
    local msg = string.format(L.CRAFT_ADDED, table.concat(parts, ", "))
    if #subs > 0 then msg = msg .. " " .. string.format(L.CRAFT_SUB, table.concat(subs, ", ")) end
    -- choix acheter / fabriquer faits sur les prix HV
    local why = M.ChoiceText(choices)
    if why ~= "" then msg = msg .. " " .. why end
    ns.Say(msg)
    return true
end

-- champ de quantite : vide = 1 (texte d aide grise, cache pendant la
-- saisie), vide a nouveau apres chaque ajout fait par lui
local function syncHint()
    bar.hint:SetShown((bar.box:GetText() or "") == "" and not bar.box:HasFocus())
end

-- Entree rend toujours le clavier (en combat aussi : sinon les touches du
-- joueur iraient dans le champ) ; le texte n est vide qu apres un ajout
local function addFromBox()
    local ok = addSelected(tonumber(bar.box:GetText() or "") or 1)
    bar.box:ClearFocus()
    if ok then bar.box:SetText("") end
    syncHint()
end

-- Barre : [+1] [+10] [+20]  [champ] [Ajouter a la file], alignee a droite
-- du bas du formulaire. Largeurs mesurees sur le texte (police et langue
-- choisies) ; si la ligne ne tient pas a droite de "Suivre la recette",
-- les +N passent au-dessus du champ.
local STEPS, BAR_H, BOX_W = { 1, 10, 20 }, 20, 34
local GAP_STEP, GAP_BOX, GAP_ADD, GAP_ROW = 2, 6, 3, 3

local function smallButton(text, w, onClick, tipText)
    local b = ns.UI.Button(bar, text, w, onClick)
    b:SetNormalFontObject("GameFontHighlightSmall")
    b:SetHighlightFontObject("GameFontHighlightSmall")
    b:SetDisabledFontObject("GameFontDisableSmall")
    b.cuiText:SetFontObject("GameFontHighlightSmall")
    b:HookScript("OnEnter", function(self) tip(self, tipText) end)
    b:HookScript("OnLeave", ns.HideTooltip)
    return b
end

-- largeur au texte, bornee
local function fitWidth(b, pad, min)
    local w = math.max(min, math.ceil((textWidth(b.cuiText) or 0) + pad))
    b:SetSize(w, BAR_H)
    return w
end

-- place les elements ; "free" = largeur libre a droite de la case de suivi
local function layoutBar(free)
    local steps = 0
    for i, b in ipairs(bar.steps) do steps = steps + fitWidth(b, 10, 22) + (i > 1 and GAP_STEP or 0) end
    local tail = BOX_W + GAP_ADD + fitWidth(bar.add, 16, 60)
    local one = steps + GAP_BOX + tail
    local rows = (one <= free) and 1 or 2
    if bar.rows == rows and bar.oneW == one then return end
    bar.rows, bar.oneW = rows, one
    bar.add:ClearAllPoints()
    bar.add:SetPoint("BOTTOMRIGHT")
    bar.box:ClearAllPoints()
    bar.box:SetPoint("RIGHT", bar.add, "LEFT", -GAP_ADD, 0)
    local last = bar.steps[#bar.steps]
    last:ClearAllPoints()
    if rows == 1 then
        last:SetPoint("RIGHT", bar.box, "LEFT", -GAP_BOX, 0)
        bar:SetSize(one, BAR_H)
    else
        last:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, BAR_H + GAP_ROW)
        bar:SetSize(math.max(steps, tail), BAR_H * 2 + GAP_ROW)
    end
    for i = #bar.steps - 1, 1, -1 do
        local b = bar.steps[i]
        b:ClearAllPoints()
        b:SetPoint("RIGHT", bar.steps[i + 1], "LEFT", -GAP_STEP, 0)
    end
end

-- bord droit d une region de Blizzard (lecture protegee)
local function rightOf(r)
    if type(r) ~= "table" then return nil end
    local ok, x = pcall(function() return r:GetRight() end)
    return ok and num(x) or nil
end

-- largeur libre dans le bas du formulaire : de la case "Suivre la recette"
-- (Camelot : en bas a gauche, son texte a droite) a notre marge de droite
-- (12) ; 8 d ecart. Formulaire illisible : 210 (360 - case et marges).
local function freeWidth(sf)
    local ok, left = pcall(function() return sf:GetLeft() end)
    left = ok and num(left) or nil
    local right = rightOf(sf)
    if not (left and right) or right - left < 100 then return 210 end
    local used = left
    local cb = field(sf, "TrackRecipeCheckbox")
    if visible(cb) then
        local x = rightOf(field(cb, "Text")) or rightOf(cb)
        used = (x and x > left and x < right) and x or (left + 140)
    end
    return right - 12 - (used + 8)
end

local function buildBar()
    bar = CreateFrame("Frame", "CorpUICraftBar", UIParent)
    bar:SetSize(200, BAR_H)
    bar:Hide()
    bar.steps = {}
    for i, n in ipairs(STEPS) do
        local b = smallButton("+" .. n, 22, function() addSelected(n) end, string.format(L.CRAFT_ADD_N, n))
        b.n = n
        bar.steps[i] = b
    end
    bar.box = ns.UI.EditBox(bar, BOX_W, BAR_H)
    bar.box:SetNumeric(true)
    bar.box:SetMaxLetters(3)
    bar.box:SetJustifyH("CENTER")
    bar.box:SetTextInsets(4, 4, 0, 0)
    bar.box:SetText("")
    bar.hint = bar.box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    bar.hint:SetPoint("TOPLEFT", 2, 0)
    bar.hint:SetPoint("BOTTOMRIGHT", -2, 0)
    bar.hint:SetJustifyH("CENTER")
    bar.hint:SetText("1")
    bar.box:SetScript("OnEnterPressed", addFromBox)
    bar.box:SetScript("OnTextChanged", syncHint)
    bar.box:HookScript("OnEditFocusGained", syncHint)
    bar.box:HookScript("OnEditFocusLost", syncHint)
    bar.box:SetScript("OnEnter", function(self) tip(self, L.CRAFT_QTY_TIP) end)
    bar.box:SetScript("OnLeave", ns.HideTooltip)
    bar.add = smallButton(L.CRAFT_ADD, 60, addFromBox, L.CRAFT_ADD_TIP)
    syncHint()
    layoutBar(210)
end

local function showTab(key)
    db.pane.tab = key
    for k, t in pairs(tabs) do
        t.line:SetShown(k == key)
        local c = (k == key) and C.gold or C.text
        t.cuiText:SetTextColor(c[1], c[2], c[3])
    end
    queueView:SetShown(key ~= "shop")
    if M.shopView then M.shopView.frame:SetShown(key == "shop") end
    M.Changed()
end

local function rowCount()
    local h = queueView:GetHeight() or 0
    return math.max(1, math.floor(h / ROW_H))
end

local function rowTooltip(row)
    local e = M.Queue()[row.index or 0]
    if not e then return end
    local r = db.recipes[e.id] or {}
    local t = ns.Tooltip(row, "ANCHOR_LEFT")
    if r.out then pcall(t.SetItemByID, t, r.out) else t:SetText(M.RecipeName(e.id)) end
    t:AddLine(" ")
    t:AddLine(string.format("%d x %s", e.n, M.RecipeName(e.id)), C.gold[1], C.gold[2], C.gold[3])
    for _, g in ipairs(r.reagents or {}) do
        local bags, bank = M.Have(g[1])
        local want = g[2] * e.n
        local ok = bags >= want
        t:AddDoubleLine(ns.ItemName(g[1]) or ("item:" .. g[1]), (bags + bank) .. " / " .. want,
            1, 1, 1, ok and 0.5 or 1, ok and 1 or 0.4, ok and 0.5 or 0.4)
    end
    pcall(profitTooltip, t, e)
    t:Show()
end

local function makeRow(i)
    local row = CreateFrame("Button", nil, queueView)
    row:SetHeight(ROW_H - 2)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.6)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_H - 6, ROW_H - 6)
    row.icon:SetPoint("LEFT", 2, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.remove = iconButton(row, nil, L.CRAFT_REMOVE, function(self) M.Remove(self:GetParent().index) end)
    row.remove:SetText("×")
    row.remove:SetPoint("RIGHT", -2, 0)
    row.down = iconButton(row, "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up", L.CRAFT_DOWN,
        function(self) M.Move(self:GetParent().index, 1) end)
    row.down:SetPoint("RIGHT", row.remove, "LEFT", -2, 0)
    row.up = iconButton(row, "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up", L.CRAFT_UP,
        function(self) M.Move(self:GetParent().index, -1) end)
    row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 5, -1)
    row.name:SetPoint("RIGHT", row.up, "LEFT", -4, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    -- bilan HV : 2e etage, a droite, juste avant les boutons (meme ligne de
    -- base que row.sub : bas de l icone + 1 = bas des boutons - 4) ; sa
    -- largeur suit son texte, vide il ne prend rien
    row.profit = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.profit:SetPoint("BOTTOMRIGHT", row.up, "BOTTOMLEFT", -4, -4)
    row.profit:SetJustifyH("RIGHT")
    row.profit:SetWordWrap(false)
    row.profit:SetText("")
    -- "xN   metier" s arrete a sa gauche (coupe si besoin)
    row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 5, 1)
    row.sub:SetPoint("RIGHT", row.profit, "LEFT", -4, 0)
    row.sub:SetJustifyH("LEFT")
    row.sub:SetWordWrap(false)
    row:SetScript("OnEnter", rowTooltip)
    row:SetScript("OnLeave", ns.HideTooltip)
    rows[i] = row
    return row
end

local function refreshQueue()
    if not pane or not pane:IsShown() then return end
    local q = M.Queue()
    local skill = M.CurrentProf()
    tabs.queue:SetText(string.format(L.CRAFT_TAB_QUEUE, #q))
    local n = rowCount()
    offset = math.max(0, math.min(offset, #q - n))
    for i = 1, n do
        local row = rows[i] or makeRow(i)
        local e = q[i + offset]
        if e then
            local r = db.recipes[e.id] or {}
            row.index = i + offset
            row.icon:SetTexture(r.icon or (r.out and ns.ItemIcon(r.out)) or "Interface\\Icons\\INV_Misc_QuestionMark")
            local running = M.run and M.run.entry == e
            local name = M.RecipeName(e.id)
            row.name:SetText(running and ("|cffffd100" .. name .. "|r") or name)
            row.sub:SetText("x" .. e.n .. "   " .. (e.prof or r.prof or ""))
            local okP, ptext, pcol = pcall(M.ProfitText, e.id, e.n)
            if not okP or type(ptext) ~= "string" then ptext, pcol = "", GREY end
            row.profit:SetText(ptext)
            row.profit:SetTextColor(pcol[1], pcol[2], pcol[3])
            row:SetAlpha((skill and e.skill ~= skill) and 0.55 or 1)
            row.up:SetEnabled(row.index > 1)
            row.down:SetEnabled(row.index < #q)
            row:Show()
        else
            row:Hide()
        end
    end
    for i = n + 1, #rows do rows[i]:Hide() end
    queueView.empty:SetShown(#q == 0)

    -- etat et bouton d ouverture d un autre metier
    local text, other = "", nil
    if M.run then
        text = string.format(L.CRAFT_LEFT, M.RecipeName(M.run.id), M.run.left)
    elseif #q > 0 and skill then
        local e, count, why = M.NextHere(skill)
        if e then
            text = string.format(L.CRAFT_READY, count, M.RecipeName(e.id))
        else
            other = M.NextOther(skill)
            local mine = false
            for _, x in ipairs(q) do if x.skill == skill then mine = true end end
            if mine or not other then
                text = why or L.CRAFT_NOTHING
                other = nil
            else
                text = string.format(L.CRAFT_NEXT_PROF, M.RecipeName(other.id), other.prof or "?")
            end
        end
    end
    status:SetText(text)
    openBtn.entry = other
    if other then openBtn:SetText(string.format(L.CRAFT_OPEN_PROF, other.prof or "?")) end
    openBtn:SetShown(other ~= nil)
    craftBtn:SetEnabled(#q > 0 and not M.run)
end

local function buildPane()
    pane = CreateFrame("Frame", "CorpUICraftPane", UIParent)
    pane:SetWidth(PANE_W)
    pane:Hide()
    ns.UI.Skin(pane, 0.95, true)
    pane:EnableMouse(true)

    -- onglets File / Courses et bouton pour replier
    local function tabButton(key, label, x)
        local b = ns.UI.Button(pane, label, 90, function() showTab(key) end)
        b:SetPoint("TOPLEFT", x, -6)
        b.line = b:CreateTexture(nil, "OVERLAY")
        b.line:SetHeight(2)
        b.line:SetPoint("BOTTOMLEFT", 1, 1)
        b.line:SetPoint("BOTTOMRIGHT", -1, 1)
        ns.UI.Gradient(b.line, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.9, C.gold[1], C.gold[2], C.gold[3], 0.9)
        tabs[key] = b
        return b
    end
    local tq = tabButton("queue", string.format(L.CRAFT_TAB_QUEUE, 0), 6)
    tq:SetWidth(100)
    local ts = tabButton("shop", L.CRAFT_TAB_SHOP, 110)
    ts:SetWidth(100)
    local fold = iconButton(pane, nil, L.CRAFT_HIDE, function()
        db.pane.collapsed = true
        pane:Hide()
    end)
    fold:SetText("«")
    fold:SetSize(22, 22)
    fold:SetPoint("TOPRIGHT", -6, -6)

    -- file
    queueView = CreateFrame("Frame", nil, pane)
    queueView:SetPoint("TOPLEFT", 6, -HEAD - 4)
    queueView:SetPoint("BOTTOMRIGHT", -6, FOOT)
    queueView:EnableMouseWheel(true)
    queueView:SetScript("OnMouseWheel", function(_, d)
        offset = offset - d * 2
        refreshQueue()
    end)
    queueView:SetScript("OnSizeChanged", function() refreshQueue() end)
    queueView.empty = queueView:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    queueView.empty:SetPoint("TOPLEFT", 4, -6)
    queueView.empty:SetPoint("RIGHT", -4, 0)
    queueView.empty:SetJustifyH("LEFT")
    queueView.empty:SetText(L.CRAFT_EMPTY_HINT)

    status = queueView:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 8, 34)
    status:SetPoint("RIGHT", pane, "RIGHT", -8, 0)
    status:SetJustifyH("LEFT")
    status:SetHeight(28)
    status:SetWordWrap(true)

    craftBtn = ns.UI.Button(queueView, L.CRAFT_CRAFT, 120, function() M.CraftNext() end)
    craftBtn:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 8, 8)
    clearBtn = ns.UI.Button(queueView, L.CRAFT_CLEAR, 60, function(self)
        -- deux clics : le premier demande confirmation
        if self.armed then
            self.armed = nil
            self:SetText(L.CRAFT_CLEAR)
            M.Clear()
            ns.Say(L.CRAFT_CLEARED)
        else
            self.armed = true
            self:SetText(L.CRAFT_SURE)
            C_Timer.After(3, function()
                if self.armed then self.armed = nil self:SetText(L.CRAFT_CLEAR) end
            end)
        end
    end)
    clearBtn:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -8, 8)
    openBtn = ns.UI.Button(queueView, "", 100, function(self) M.OpenProf(self.entry) end)
    openBtn:SetPoint("LEFT", craftBtn, "RIGHT", 4, 0)
    openBtn:SetPoint("RIGHT", clearBtn, "LEFT", -4, 0)
    openBtn:Hide()

    -- courses (Courses.lua)
    if M.BuildShopView then
        M.shopView = M.BuildShopView(pane)
        M.shopView.frame:SetPoint("TOPLEFT", 6, -HEAD - 4)
        M.shopView.frame:SetPoint("BOTTOMRIGHT", -6, 8)
    end

    pane:SetScript("OnShow", function() M.Changed() end)

    -- volet replie : petit bouton pour le rouvrir
    expander = iconButton(UIParent, nil, L.CRAFT_SHOW, function()
        db.pane.collapsed = false
        expander:Hide()
    end)
    expander:SetText("»")
    expander:SetSize(22, 22)
    expander:Hide()

    showTab(db.pane.tab == "shop" and "shop" or "queue")
end

table.insert(M.listeners, refreshQueue)

-- largeur du rail d onglets de Blizzard a droite de la fenetre
-- (le rail CorpUI de Habillage/Metiers.lua : tuile = hauteur de l onglet
-- - 8, bornee a 28..46, plus 4 px de marge de chaque cote), plus 6 px d ecart
local function railWidth(pf)
    local t = field(pf, "ProfessionsOverviewTab")
    if type(t) ~= "table" or not t.GetHeight then return 56 end
    local okH, h = pcall(t.GetHeight, t)
    h = okH and num(h)
    if not h or h <= 0 then return 56 end
    local size = math.max(28, math.min(46, math.floor(h) - 8))
    -- decalage de l onglet par rapport au bord droit de la fenetre
    local okL, left = pcall(t.GetLeft, t)
    local okR, right = pcall(pf.GetRight, pf)
    left, right = okL and num(left), okR and num(right)
    local off = (left and right) and math.floor(left - right + 0.5) or 0
    return off + size + 8 + 6
end

-- nos cadres suivent la fenetre : strate et echelle de pf, niveau de
-- "base" (pf par defaut) + extra. Lectures seulement chez Blizzard.
-- plus haut niveau parmi un cadre et ses descendants affiches (lecture seule)
local function topLevelOf(f, depth)
    local okL, best = pcall(f.GetFrameLevel, f)
    best = okL and num(best) or 0
    if depth <= 0 then return best end
    local ok, kids = pcall(function() return { f:GetChildren() } end)
    if not ok then return best end
    for _, c in ipairs(kids) do
        if visible(c) then
            local l = topLevelOf(c, depth - 1)
            if l > best then best = l end
        end
    end
    return best
end

-- strate juste au-dessus (la barre posee SUR la fenetre des metiers)
local STRATA_UP = { BACKGROUND = "LOW", LOW = "MEDIUM", MEDIUM = "HIGH", HIGH = "DIALOG",
                    DIALOG = "FULLSCREEN", FULLSCREEN = "FULLSCREEN_DIALOG" }

local anchoredTo
local function follow(f, pf, extra, base, raise)
    base = base or pf
    local okS, strata = pcall(pf.GetFrameStrata, pf)
    strata = okS and str(strata)
    if strata and raise then strata = STRATA_UP[strata] or strata end
    if strata and f:GetFrameStrata() ~= strata then f:SetFrameStrata(strata) end
    local lvl
    if type(base) == "number" then
        lvl = base
    else
        local okL, l = pcall(base.GetFrameLevel, base)
        lvl = okL and num(l)
    end
    if lvl then f:SetFrameLevel(math.min(9000, lvl + extra)) end
    local okE, s = pcall(pf.GetEffectiveScale, pf)
    s = okE and num(s)
    local u = UIParent:GetEffectiveScale()
    if s and u and u > 0 and s > 0 then f:SetScale(s / u) end
end

-- fenetre des metiers fermee : nos cadres (enfants d UIParent) partent
-- aussi. Permis en combat : ce sont des cadres a nous, non proteges.
local function hideAll()
    if bar then bar:Hide() end
    if profitBox then profitBox:Hide() end
    if pane then pane:Hide() end
    if expander then expander:Hide() end
    if M.wasOpen then
        M.wasOpen = false
        M.Changed()
    end
end
---------------------------------------------------------------------------
-- Benefice de la recette choisie, sous son nom (demande du 07/10) : le
-- meme bilan HV que la ligne de la file (M.Profit, une fabrication), et au
-- survol l infobulle detaillee de la file.
---------------------------------------------------------------------------

local function buildProfitBox()
    profitBox = CreateFrame("Frame", "CorpUICraftProfit", UIParent)
    profitBox:SetSize(240, 30)
    profitBox:Hide()
    profitBox.main = profitBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    profitBox.main:SetPoint("TOPLEFT", 0, 0)
    profitBox.main:SetJustifyH("LEFT")
    profitBox.detail = profitBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    profitBox.detail:SetPoint("TOPLEFT", profitBox.main, "BOTTOMLEFT", 0, -2)
    profitBox.detail:SetJustifyH("LEFT")
    profitBox:EnableMouse(true)
    profitBox:SetScript("OnEnter", function(self)
        if not self.recipe then return end
        local t = ns.Tooltip(self, "ANCHOR_BOTTOMRIGHT")
        t:SetText(M.RecipeName(self.recipe))
        profitTooltip(t, { id = self.recipe, n = 1 })
        t:Show()
    end)
    profitBox:SetScript("OnLeave", ns.HideTooltip)
end

-- deux lignes : bilan (colore) et detail vente / composants
local function profitLines(id)
    local pr = M.Profit(id, 1)
    if not pr then return nil end
    if not pr.known then return L.CRAFT_PV_NODATA, GREY, "" end
    local main, col
    if pr.profit then
        if pr.profit <= -0.005 then
            main, col = string.format(L.CRAFT_PV_LOSS, money(-pr.profit)), RED
        else
            main, col = string.format(L.CRAFT_PV_PROFIT, signed(pr.profit)), tone(pr.profit)
        end
    elseif pr.value then
        local b = pr.value - pr.cost
        if b <= -0.005 then
            main, col = string.format(L.CRAFT_PV_LOSS, money(-b) .. "+"), RED
        else
            main, col = string.format(L.CRAFT_PV_PROFIT, string.format(L.CRAFT_AH_UPTO, signed(b))), GREY
        end
    else
        main, col = L.CRAFT_PV_NOVALUE, GREY
    end
    local cost = money(pr.cost)
    if pr.missing > 0 or pr.est then cost = cost .. "+" end
    local detail = string.format(L.CRAFT_PV_DETAIL, pr.value and money(pr.value) or "?", cost)
    return main, col, detail
end

-- Place sous le nom. Blizzard empile sous le nom (organiseur du formulaire)
-- sous-titre, "Requiert", recharge, puis la description, et les composants
-- 20 px sous la description (50 px avec "Recette non apprise" ou
-- "Premiere fabrication", poses dans cet ecart). D ou :
--   bouton "non apprise" / "premiere fabrication" : a sa droite, une ligne ;
--   description : juste dessous, une ligne (le detail passe a l infobulle) ;
--   sinon : sous le plus bas des textes du nom, deux lignes.
-- Lecture seule des regions de Blizzard (aucune ecriture, aucun crochet).
local UNDER_NAME = { "OutputText", "OutputSubText", "RequiredTools", "Cooldown" }

local function textShown(r)
    if type(r) ~= "table" or type(r.GetText) ~= "function" then return false end
    local okS, shown = pcall(r.IsShown, r)
    if not okS or issecret(shown) or not shown then return false end
    local okT, t = pcall(r.GetText, r)
    return okT and type(t) == "string" and not issecret(t) and t ~= ""
end

local function frameShown(r)
    if type(r) ~= "table" or type(r.IsShown) ~= "function" then return false end
    local ok, shown = pcall(r.IsShown, r)
    return ok and not issecret(shown) and shown and true or false
end

-- renvoie : region d accroche, point d accroche ("below" / "right"), cle, compact
local function profitAnchor(sf)
    for _, key in ipairs({ "RecipeSourceButton", "FirstCraftBonus" }) do
        local b = field(sf, key)
        if frameShown(b) then
            local txt = field(b, "Text")
            return (textShown(txt) and txt) or b, "right", key, true
        end
    end
    local desc = field(sf, "Description")
    if textShown(desc) then return desc, "below", "Description", true end
    local best, low, bestKey
    for _, key in ipairs(UNDER_NAME) do
        local r = field(sf, key)
        if textShown(r) then
            local ok, b = pcall(r.GetBottom, r)
            b = ok and num(b) or nil
            if b and (not low or b < low) then best, low, bestKey = r, b, key end
        end
    end
    if best then return best, "below", bestKey, false end
    local icon = field(sf, "OutputIcon")
    if type(icon) == "table" and icon.GetRight then return icon, "icon", "OutputIcon", false end
    return sf, "form", "form", false
end

-- sous le nom de la recette, une strate au-dessus de la fenetre comme la
-- barre d ajout ; place et texte relus toutes les secondes
local function placeProfit(pf, sf, id)
    local r = id and db.recipes[id]
    if id and (not r or not r.reagents) then r = M.ReadRecipe(id, nil, M.CurrentProf and M.CurrentProf() or nil) end
    if not (id and r and not r.special and M.ProfitOn()) then
        if profitBox and profitBox:IsShown() then profitBox:Hide() end
        return
    end
    if not profitBox then buildProfitBox() end
    local now = GetTime()
    if profitBox.recipe ~= id or not profitBox.at or now - profitBox.at > 1 then
        profitBox.recipe, profitBox.at = id, now
        profitBox.top = topLevelOf(sf, 3)
        -- accroche : relue a chaque fois (l organiseur de Blizzard change
        -- la pile sous le nom d une recette a l autre)
        local anchor, how, key, compact = profitAnchor(sf)
        if profitBox.anchor ~= anchor or profitBox.how ~= how then
            profitBox.anchor, profitBox.how = anchor, how
            profitBox:ClearAllPoints()
            if how == "right" then
                profitBox:SetPoint("LEFT", anchor, "RIGHT", 16, 0)
            elseif how == "below" then
                profitBox:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, compact and -3 or -6)
            elseif how == "icon" then
                profitBox:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 14, -26)
            else
                profitBox:SetPoint("TOPLEFT", anchor, "TOPLEFT", 90, -50)
            end
        end
        profitBox.anchorKey, profitBox.compact = key, compact
        local main, col, detail = profitLines(id)
        if not main then profitBox:Hide() return end
        profitBox.main:SetText(main)
        profitBox.main:SetTextColor(col[1], col[2], col[3])
        profitBox.detail:SetText(detail or "")
        profitBox.detail:SetShown(not compact)
        local w = profitBox.main:GetStringWidth() or 0
        if not compact then w = math.max(w, profitBox.detail:GetStringWidth() or 0) end
        profitBox:SetSize(math.max(60, w + 4), compact and 14 or 30)
    end
    follow(profitBox, pf, 10, profitBox.top or sf, true)
    if not profitBox:IsShown() then profitBox:Show() end
end

local function hideIfClosed()
    local pf = professionsFrame()
    if not (pf and visible(pf)) then hideAll() end
end

local function update()
    local pf = professionsFrame()
    local open = pf and visible(pf)
    if not open then return hideAll() end
    if not bar then buildBar() end
    if not pane then buildPane() end
    local x = railWidth(pf)
    if anchoredTo ~= pf or pane.railX ~= x then
        anchoredTo = pf
        pane.railX = x
        pane:ClearAllPoints()
        pane:SetPoint("TOPLEFT", pf, "TOPRIGHT", x, 0)
        pane:SetPoint("BOTTOMLEFT", pf, "BOTTOMRIGHT", x, 0)
        expander:ClearAllPoints()
        expander:SetPoint("TOPLEFT", pf, "TOPRIGHT", x, -8)
    end
    if not M.wasOpen then
        M.wasOpen = true
        M.Index()
        if M.ProfOpened then M.ProfOpened() end
    end
    follow(pane, pf, 5)
    follow(expander, pf, 5)
    local wantPane = (db.showPane and not db.pane.collapsed) and true or false
    if wantPane ~= pane:IsShown() then pane:SetShown(wantPane) end
    expander:SetShown(db.showPane and db.pane.collapsed and true or false)

    -- barre : sous la recette choisie (apprise), dans un metier a nous
    local sf = schematicForm(pf)
    local id = M.SelectedRecipe()
    local r = id and db.recipes[id]
    local ok = id and M.OwnSkill() and not (r and r.special) and M.Learned(id)
    if ok then
        if bar.sf ~= sf then
            bar.sf = sf
            bar:ClearAllPoints()
            bar:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", -12, 8)
        end
        -- une strate AU-DESSUS de la fenetre : vu en jeu, rien de la strate
        -- de la fenetre ne s affiche sur le formulaire, meme au niveau 5000
        -- (la bordure SchematicForm.NineSlice est au niveau 598) ; niveau
        -- garde au-dessus de ses descendants au cas ou ; la place libre
        -- (case "Suivre la recette" montree ou non) relue au meme rythme
        local now = GetTime()
        if not bar.topAt or now - bar.topAt > 1 or bar.topOf ~= sf or bar.recipe ~= id then
            bar.topAt, bar.topOf, bar.recipe = now, sf, id
            bar.top = topLevelOf(sf, 3)
            layoutBar(freeWidth(sf))
        end
        follow(bar, pf, 10, bar.top or sf, true)
        if not bar:IsShown() then bar:Show() end
    elseif bar:IsShown() then
        bar:Hide()
    end
    -- benefice HV de la recette choisie, sous son nom
    placeProfit(pf, sf, visible(sf) and id or nil)
end

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
local acc = 0
ev:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.2 then return end
    acc = 0
    if not db then return end
    pcall(watch)
    if InCombatLockdown() then
        -- en combat on ne place ni ne construit rien ; on cache seulement
        pcall(hideIfClosed)
        return
    end
    local ok, err = pcall(update)
    if not ok and not M.errShown then
        M.errShown = true
        ns.Say("|cffff4040" .. tostring(err) .. "|r")
    end
end)

local listPending = false
ev:SetScript("OnEvent", function(_, event, a1, a2, a3)
    if event == "PLAYER_LOGIN" then
        M.Init()
        -- prix HV mis a jour (module Encheres, charge apres nous) : bilans
        -- de la file refaits, hors combat (le prochain changement suffit)
        if type(ns.AHListen) == "function" then
            pcall(ns.AHListen, function()
                if not InCombatLockdown() then refreshQueue() end
            end)
        end
        return
    end
    if not db then return end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local run = M.run
        if not run or issecret(a1) or a1 ~= "player" then return end
        if issecret(a3) then
            run.byResult = true       -- sort illisible : on compte les objets produits
            started(run)
            run.casting = false
        elseif a3 == run.id then
            crafted()
        end
    elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_STOP" then
        local run = M.run
        if not run or issecret(a1) or a1 ~= "player" then return end
        if issecret(a3) or a3 == run.id then
            run.casting = (event == "UNIT_SPELLCAST_START")
            if run.casting then started(run) else run.last = GetTime() end
        end
    elseif event == "TRADE_SKILL_ITEM_CRAFTED_RESULT" then
        local run = M.run
        if not run or not run.byResult or type(a1) ~= "table" or issecret(a1) then return end
        local r = db.recipes[run.id]
        if r and r.out and num(a1.itemID) == r.out then crafted() end
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
        local run = M.run
        if not run or issecret(a1) or a1 ~= "player" then return end
        if issecret(a3) or a3 == run.id then stop(true) end
    elseif event == "UPDATE_TRADESKILL_CAST_STOPPED" then
        -- la derniere reussite peut arriver juste apres : on laisse un instant
        local run = M.run
        if run then C_Timer.After(0.6, function() if M.run == run then stop(false) end end) end
    elseif event == "TRADE_SKILL_CLOSE" then
        -- la serie de Blizzard continue fenetre fermee : le suivi aussi
        -- (UNIT_SPELLCAST_SUCCEEDED n a pas besoin de la fenetre) ; nos
        -- cadres partent avec elle, combat compris
        C_Timer.After(0, function() pcall(hideIfClosed) end)
        M.Changed()
    elseif event == "NEW_RECIPE_LEARNED" then
        M.ForgetIndex()
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
        -- la liste arrive par morceaux : un seul passage, un peu apres
        if listPending then return end
        listPending = true
        C_Timer.After(0.5, function()
            listPending = false
            if InCombatLockdown() then return end
            pcall(M.Index)
            M.Changed()
        end)
    elseif event == "BAG_UPDATE_DELAYED" then
        M.DirtyBank()
        if M.wasOpen then M.Changed() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- debut de combat : notre champ de quantite rend le clavier
        if bar and yes(bar.box:HasFocus()) then bar.box:ClearFocus() end
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_CLOSE",
                     "TRADE_SKILL_DATA_SOURCE_CHANGED", "NEW_RECIPE_LEARNED", "UPDATE_TRADESKILL_CAST_STOPPED",
                     "TRADE_SKILL_ITEM_CRAFTED_RESULT", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_DISABLED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
for _, e in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED",
                     "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP" }) do
    if not (ev.RegisterUnitEvent and pcall(ev.RegisterUnitEvent, ev, e, "player")) then
        pcall(ev.RegisterEvent, ev, e)
    end
end
