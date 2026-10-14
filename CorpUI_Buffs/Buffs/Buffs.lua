--[[--------------------------------------------------------------------------
    CorpUI - module Buffs (coeur)
    Coordination des buffs de toutes les classes qui en donnent :
      - chaque lanceur annonce ses buffs, rangs, talents et composants
      - paladins : une benediction par paladin et par classe (+ une aura)
      - pretres, mages, druides : chaque lanceur recoit des groupes du raid
        pour chacun de ses buffs de groupe
      - tout le monde : buffs individuels par joueur (Epines, etc.)
      - synchronisation par messages d addon, barre de lancement, rez

    Regles de construction (contrainte des secret values de ce client) :
      - aucun hook sur une fonction de Blizzard
      - aucune ecriture sur une globale existante (seulement les notres)
      - aucun ajout dans UISpecialFrames
      - toute lecture d aura ou de portee protegee par pcall et par
        issecretvalue : en combat, une valeur illisible devient "inconnue"
        et on garde la derniere valeur connue
----------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L

local COMM_PREFIX = "CorpUI"

local issecret = issecretvalue or function() return false end
local GetTime = GetTime
local strsplit, tonumber, pairs, ipairs, pcall = strsplit, tonumber, pairs, ipairs, pcall

-- fonctions partagees (sorts, classes, temps) : dans le noyau (Partage.lua)
local clean = ns.Clean
local knownSpell = ns.KnownSpell

---------------------------------------------------------------------------
-- Utilitaires
---------------------------------------------------------------------------


local function spellRank(id)
    if not id or not GetSpellSubtext then return 1 end
    local ok, sub = pcall(GetSpellSubtext, id)
    if ok and sub then
        local n = tonumber(sub:match("(%d+)"))
        if n then return n end
    end
    return 1
end

-- Points dans le talent qui porte le meme nom que le sort donne
local function talentRank(spellId)
    local want = ns.SpellName(spellId)
    if not want or not GetNumTalentTabs or not GetTalentInfo then return 0 end
    local ok, rank = pcall(function()
        for tab = 1, GetNumTalentTabs() or 0 do
            for i = 1, (GetNumTalents and GetNumTalents(tab)) or 0 do
                local name, _, _, _, r = GetTalentInfo(tab, i)
                if name == want then return r or 0 end
            end
        end
        return 0
    end)
    return (ok and rank) or 0
end

function ns.BuffName(key, group)
    local b = ns.BUFF_BY_KEY[key]
    if not b then return nil end
    return ns.SpellName(group and b.group or b.single)
end

function ns.BuffIcon(key, group)
    local b = ns.BUFF_BY_KEY[key]
    if not b then return nil end
    return ns.SpellIcon(group and b.group or b.single)
end

-- Nom court : "Bénédiction de puissance" -> "Puissance". Toutes langues : on
-- retire le premier mot puis un mot de liaison eventuel ("of", "de"...).
-- Sans espace (chinois, coreen), le nom reste entier.
function ns.BuffShort(key)
    local name = ns.BuffName(key) or key
    local rest = name:match("^%S+%s+(.+)$")
    if not rest then return name end
    rest = rest:gsub("^[dD]'", "")
    local word, tail = rest:match("^(%S+)%s+(.+)$")
    if word and ns.NAME_LINKS[strlower(word)] then rest = tail end
    return (rest:gsub("^%l", string.upper))
end

function ns.AuraName(akey)
    local a = ns.AURA_BY_KEY[akey]
    return a and ns.SpellName(a.id)
end

function ns.AuraIcon(akey)
    local a = ns.AURA_BY_KEY[akey]
    return a and ns.SpellIcon(a.id)
end


-- {1,2,3,4,7} -> "1-4, 7"
function ns.FormatGroups(set)
    local list = {}
    for g = 1, ns.MAX_GROUPS do if set and set[g] then table.insert(list, g) end end
    local parts, i = {}, 1
    while i <= #list do
        local j = i
        while j < #list and list[j + 1] == list[j] + 1 do j = j + 1 end
        table.insert(parts, i == j and tostring(list[i]) or (list[i] .. "-" .. list[j]))
        i = j + 1
    end
    return table.concat(parts, ", ")
end

local function shortName(name)
    if not name or issecret(name) then return nil end
    -- noms uniques regionaux ("Prenom Nom", voir ns.Names dans Core.lua)
    if ns.Names and ns.Names.Regional() then return ns.Names.Sender(name) end
    if Ambiguate then return Ambiguate(name, "none") end
    return (strsplit("-", name))
end
ns.ShortName = shortName

local function unitName(unit)
    if ns.Names and ns.Names.Regional() then return ns.Names.Unit(unit) end
    local ok, name, realm = pcall(UnitName, unit)
    if not ok or not name or issecret(name) or name == UNKNOWNOBJECT then return nil end
    if realm and not issecret(realm) and realm ~= "" then name = name .. "-" .. realm end
    return shortName(name)
end
ns.UnitNameFull = unitName

function ns.PlayerClass()
    local _, class = UnitClass("player")
    return class
end

-- Fournisseur de buffs du joueur (nil si sa classe n en donne pas)
function ns.MyProvider()
    return ns.PROVIDERS[ns.PlayerClass()]
end

---------------------------------------------------------------------------
-- Base de donnees
---------------------------------------------------------------------------

local DEFAULTS = {
    assign = {},      -- [paladin][classe] = benediction
    groups = {},      -- [lanceur][buff] = { [groupe] = true }
    indiv  = {},      -- [lanceur][joueur] = buff individuel
    aura   = {},      -- [paladin] = aura
    freeAssign = false,
    bar = { shown = true, locked = false, scale = 1, vertical = true, point = "CENTER", x = -300, y = 100 },
    win = { point = "CENTER", x = 0, y = 80 },
    showRF = true,
    showAura = true,
    hideBuffed = true,     -- masquer ce qui est deja buffe, et Auto si inutile
    showDead = true,       -- boutons de resurrection des morts
    rezAnnounce = true,    -- message au groupe quand on lance un rez
}

local function fill(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            fill(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

-- Les reglages du module vivent dans CorpUIDB.buffs
-- noms uniques regionaux : les noms enregistres en "Prenom-Nom" (anciennes
-- versions) passent a l ecriture du jeu, "Prenom Nom" (voir ns.Names)
local function rekey(t)
    if type(t) ~= "table" then return end
    local moves = {}
    for k in pairs(t) do
        if type(k) == "string" then
            local norm = shortName(k)
            if norm and norm ~= k then moves[k] = norm end
        end
    end
    for old, norm in pairs(moves) do
        if t[norm] == nil then t[norm] = t[old] end
        t[old] = nil
    end
end

local function initDB()
    local root = ns.InitRoot()
    if type(root.buffs) ~= "table" then root.buffs = {} end
    fill(root.buffs, DEFAULTS)
    ns.db = root.buffs
    if ns.Names and ns.Names.Regional() then
        rekey(ns.db.assign)
        rekey(ns.db.groups)
        rekey(ns.db.aura)
        rekey(ns.db.indiv)
        for _, list in pairs(ns.db.indiv) do rekey(list) end
    end
end

---------------------------------------------------------------------------
-- Composition du groupe
---------------------------------------------------------------------------

ns.roster = {}         -- { unit, name, class, group, key }
ns.byClass = {}        -- classe -> membres
ns.byGroup = {}        -- groupe (1..8) -> membres
ns.byUnit = {}         -- unite -> membre (UNIT_AURA)
ns.groupCasters = {}   -- classe fournisseur -> { nom = unite }
ns.casters = {}        -- nom -> infos annoncees (voir scanSelf)

-- Les familiers ne sont pas suivis : sur ce client, ils ne peuvent
-- recevoir aucun buff.
local function addMember(unit, group)
    if not UnitExists(unit) then return end
    local name = unitName(unit)
    if not name then return end
    local _, c = UnitClass(unit)
    local class = clean(c)
    if not class or not ns.CLASS_INDEX[class] then return end
    local m = { unit = unit, name = name, class = class, group = group or 1, key = name }
    table.insert(ns.roster, m)
    ns.byUnit[unit] = m
    ns.byClass[class] = ns.byClass[class] or {}
    table.insert(ns.byClass[class], m)
    ns.byGroup[m.group] = ns.byGroup[m.group] or {}
    table.insert(ns.byGroup[m.group], m)
    if ns.PROVIDERS[class] then
        ns.groupCasters[class] = ns.groupCasters[class] or {}
        ns.groupCasters[class][name] = unit
    end
end

function ns.BuildRoster()
    wipe(ns.roster)
    wipe(ns.byUnit)
    wipe(ns.byClass)
    wipe(ns.byGroup)
    wipe(ns.groupCasters)
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local _, _, subgroup = GetRaidRosterInfo(i)
            addMember("raid" .. i, clean(subgroup))
        end
    else
        -- hors raid, tout le groupe forme le groupe 1
        addMember("player", 1)
        if IsInGroup() then
            for i = 1, GetNumSubgroupMembers() do
                addMember("party" .. i, 1)
            end
        end
    end
    local byName = function(a, b) return a.name < b.name end
    for _, list in pairs(ns.byClass) do table.sort(list, byName) end
    for _, list in pairs(ns.byGroup) do table.sort(list, byName) end
end

function ns.UnitForName(name)
    for _, m in ipairs(ns.roster) do
        if m.name == name then return m.unit end
    end
end

function ns.MemberByName(name)
    for _, m in ipairs(ns.roster) do
        if m.name == name then return m end
    end
end

-- Groupes non vides, dans l ordre
function ns.GroupsPresent()
    local list = {}
    for g = 1, ns.MAX_GROUPS do
        if ns.byGroup[g] and #ns.byGroup[g] > 0 then table.insert(list, g) end
    end
    return list
end

-- Lanceurs d une classe presents dans le groupe, tries, le joueur en premier
function ns.CasterList(class)
    local list = {}
    for name in pairs(ns.groupCasters[class] or {}) do table.insert(list, name) end
    table.sort(list, function(a, b)
        if a == ns.me then return true end
        if b == ns.me then return false end
        return a < b
    end)
    return list
end

function ns.AllCasters()
    local list = {}
    for _, class in ipairs(ns.PROVIDER_ORDER) do
        for _, name in ipairs(ns.CasterList(class)) do table.insert(list, name) end
    end
    return list
end

function ns.CasterClass(name)
    for class, set in pairs(ns.groupCasters) do
        if set[name] then return class end
    end
    local c = ns.casters[name]
    return c and c.class
end

-- Profil suppose d un lanceur sans l addon
local function sk() return { rank = 1, talent = 0, group = true, reagents = 1 } end
local FALLBACK = {
    PALADIN = { skills = { wisdom = sk(), might = sk(), salvation = sk(), light = sk() },
                auras = { devotion = 1, retribution = 1, concentration = 1, shadow = 1, frost = 1, fire = 1 } },
    PRIEST  = { skills = { fortitude = sk(), shadowprot = sk() }, auras = {} },
    MAGE    = { skills = { intellect = sk(), amplify = sk(), dampen = sk() }, auras = {} },
    DRUID   = { skills = { wild = sk(), thorns = sk() }, auras = {} },
}
for class, f in pairs(FALLBACK) do
    f.addon = false
    f.class = class
end

function ns.CasterInfo(name)
    local c = ns.casters[name]
    if c then return c end
    local class = ns.CasterClass(name)
    return FALLBACK[class] or { addon = false, skills = {}, auras = {} }
end

---------------------------------------------------------------------------
-- Ce que sait faire le joueur
---------------------------------------------------------------------------

local function itemCount(ids)
    local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not fn or not ids then return 0 end
    local total = 0
    for _, id in ipairs(ids) do
        local ok, n = pcall(fn, id)
        total = total + ((ok and clean(n)) or 0)
    end
    return total
end

local function scanSelf()
    local class = ns.PlayerClass()
    local prov = ns.PROVIDERS[class]
    if not prov then return end
    local info = {
        addon = true,
        version = ns.VERSION,
        class = class,
        freeAssign = ns.db.freeAssign,
        skills = {},
        auras = {},
    }
    for _, b in ipairs(prov.buffs) do
        local known, id = knownSpell(b.single)
        if known then
            info.skills[b.key] = {
                rank = spellRank(id),
                talent = b.talent and talentRank(b.talent) or 0,
                group = b.group and (knownSpell(b.group)) or false,
                reagents = itemCount(b.reagents),
            }
        end
    end
    if class == "PALADIN" then
        for _, a in ipairs(ns.AURAS) do
            local known, id = knownSpell(a.id)
            if known then info.auras[a.key] = spellRank(id) end
        end
        info.rf = (knownSpell(ns.RIGHTEOUS_FURY))
    end
    info.rez = prov.rez and (knownSpell(prov.rez)) or false
    ns.casters[ns.me] = info
end

local function updateReagents()
    local p = ns.casters[ns.me]
    local prov = ns.MyProvider()
    if not p or not prov then return false end
    local changed = false
    for _, b in ipairs(prov.buffs) do
        local s = p.skills[b.key]
        if s then
            local n = itemCount(b.reagents)
            if n ~= s.reagents then
                s.reagents = n
                changed = true
            end
        end
    end
    return changed
end

---------------------------------------------------------------------------
-- Droits d edition
---------------------------------------------------------------------------

function ns.IsPromoted(name)
    if not IsInGroup() then return name == ns.me end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local n, rank = GetRaidRosterInfo(i)
            if n and shortName(n) == name then return (rank or 0) > 0 end
        end
        return false
    end
    local unit = ns.UnitForName(name)
    return unit and UnitIsGroupLeader(unit) or false
end

function ns.CanEdit(editor, caster)
    if not editor or not caster then return false end
    if editor == caster or not IsInGroup() then return true end
    if ns.IsPromoted(editor) then return true end
    local p = ns.casters[caster]
    if not p or not p.addon then return true end   -- lanceur sans addon
    return p.freeAssign and true or false
end

---------------------------------------------------------------------------
-- Synchronisation
--   REQ                               demande a tous de s annoncer
--   SELF;ver;classe;libre;rf;rez;buffs;auras
--          buffs = cle:rang:talent:groupe(0/1):composants,...
--   ALL;lanceur;aura;CLASSE=ben,...;buff=1234,...   assignations completes
--   ASG;paladin;classe;ben
--   GRP;lanceur;buff;1234                groupes d un buff ("-" = aucun)
--   AUR;paladin;aura
--   IND;lanceur;joueur;buff
--   INDS;lanceur;reset;joueur=buff,...   individuels par paquets
--   CLR                                  le chef efface tout
--   REZ;joueur                           je lance un rez sur ce joueur
---------------------------------------------------------------------------

local function channel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

local function send(msg)
    local chan = channel()
    if not chan then return end
    local fn = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if fn then pcall(fn, COMM_PREFIX, msg, chan) end
end

local function groupDigits(set)
    local s = ""
    for g = 1, ns.MAX_GROUPS do if set and set[g] then s = s .. g end end
    return s ~= "" and s or "-"
end

local function parseDigits(s)
    local set = {}
    for d in (s or ""):gmatch("%d") do
        local g = tonumber(d)
        if g >= 1 and g <= ns.MAX_GROUPS then set[g] = true end
    end
    return next(set) and set or nil
end

local function encodeSelf()
    local p = ns.casters[ns.me]
    local prov = ns.MyProvider()
    if not p or not prov then return nil end
    local bl, au = {}, {}
    for _, b in ipairs(prov.buffs) do
        local s = p.skills[b.key]
        if s then
            table.insert(bl, string.format("%s:%d:%d:%d:%d", b.key, s.rank or 1, s.talent or 0,
                s.group and 1 or 0, s.reagents or 0))
        end
    end
    for _, a in ipairs(ns.AURAS) do
        if p.auras[a.key] then table.insert(au, a.key .. ":" .. p.auras[a.key]) end
    end
    return string.format("SELF;%s;%s;%d;%d;%d;%s;%s", ns.VERSION, p.class, ns.db.freeAssign and 1 or 0,
        p.rf and 1 or 0, p.rez and 1 or 0, table.concat(bl, ","), table.concat(au, ","))
end

local function encodeAll(caster)
    local cls, grp = {}, {}
    local a = ns.db.assign[caster]
    if a then
        for _, class in ipairs(ns.CLASSES) do
            if a[class] then table.insert(cls, class .. "=" .. a[class]) end
        end
    end
    for key, set in pairs(ns.db.groups[caster] or {}) do
        if next(set) then table.insert(grp, key .. "=" .. groupDigits(set)) end
    end
    return string.format("ALL;%s;%s;%s;%s", caster, ns.db.aura[caster] or "-",
        table.concat(cls, ","), table.concat(grp, ","))
end

local function sendIndividuals(caster)
    local list = ns.db.indiv[caster]
    local chunk, first = {}, true
    local function flush(force)
        if #chunk == 0 and not (force and first) then return end
        send(string.format("INDS;%s;%d;%s", caster, first and 1 or 0, table.concat(chunk, ",")))
        first = false
        wipe(chunk)
    end
    if list then
        local len = 0
        for player, key in pairs(list) do
            local item = player .. "=" .. key
            if len + #item > 200 then flush(); len = 0 end
            table.insert(chunk, item)
            len = len + #item + 1
        end
    end
    flush(true)
end

-- Annonce ce que je sais : moi-meme, et les lanceurs sans addon si je suis chef
local function announce()
    if not IsInGroup() then return end
    if ns.casters[ns.me] then
        send(encodeSelf())
        send(encodeAll(ns.me))
        sendIndividuals(ns.me)
    end
    if ns.IsPromoted(ns.me) then
        for _, name in ipairs(ns.AllCasters()) do
            if name ~= ns.me and not (ns.casters[name] and ns.casters[name].addon) then
                send(encodeAll(name))
            end
        end
    end
end
ns.Announce = announce

local announcePending = false
local function announceSoon(delay)
    if announcePending then return end
    announcePending = true
    C_Timer.After(delay or (0.5 + math.random() * 1.5), function()
        announcePending = false
        announce()
    end)
end

function ns.RequestSync()
    if not IsInGroup() then return end
    send("REQ")
    announceSoon(0.5)
end

local handlers = {}

function handlers.REQ(sender)
    announceSoon()
end

function handlers.SELF(sender, ver, class, free, rf, rez, bl, au)
    if not ns.PROVIDERS[class] then return end
    local p = { addon = true, version = ver, class = class, freeAssign = free == "1",
                rf = rf == "1", rez = rez == "1", skills = {}, auras = {} }
    for item in (bl or ""):gmatch("[^,]+") do
        local key, rank, talent, group, reag = strsplit(":", item)
        if ns.BUFF_BY_KEY[key] then
            p.skills[key] = { rank = tonumber(rank) or 1, talent = tonumber(talent) or 0,
                              group = group == "1", reagents = tonumber(reag) or 0 }
        end
    end
    for item in (au or ""):gmatch("[^,]+") do
        local key, rank = strsplit(":", item)
        if ns.AURA_BY_KEY[key] then p.auras[key] = tonumber(rank) or 1 end
    end
    ns.casters[sender] = p
    ns.Changed("buffs")
end

function handlers.ALL(sender, caster, aura, cls, grp)
    if not caster or not ns.CanEdit(sender, caster) then return end
    local a = {}
    for item in (cls or ""):gmatch("[^,]+") do
        local class, key = strsplit("=", item)
        if ns.CLASS_INDEX[class] and ns.BUFF_BY_KEY[key] then a[class] = key end
    end
    local g = {}
    for item in (grp or ""):gmatch("[^,]+") do
        local key, digits = strsplit("=", item)
        if ns.BUFF_BY_KEY[key] then g[key] = parseDigits(digits) end
    end
    ns.db.assign[caster] = a
    ns.db.groups[caster] = g
    ns.db.aura[caster] = ns.AURA_BY_KEY[aura] and aura or nil
    ns.Changed("buffs")
end

function handlers.ASG(sender, caster, class, key)
    if not caster or not ns.CLASS_INDEX[class] or not ns.CanEdit(sender, caster) then return end
    ns.db.assign[caster] = ns.db.assign[caster] or {}
    ns.db.assign[caster][class] = ns.BUFF_BY_KEY[key] and key or nil
    ns.Changed("buffs")
end

function handlers.GRP(sender, caster, key, digits)
    if not caster or not ns.BUFF_BY_KEY[key] or not ns.CanEdit(sender, caster) then return end
    ns.db.groups[caster] = ns.db.groups[caster] or {}
    ns.db.groups[caster][key] = parseDigits(digits)
    ns.Changed("buffs")
end

function handlers.AUR(sender, caster, akey)
    if not caster or not ns.CanEdit(sender, caster) then return end
    ns.db.aura[caster] = ns.AURA_BY_KEY[akey] and akey or nil
    ns.Changed("buffs")
end

function handlers.IND(sender, caster, player, key)
    if not caster or not player or not ns.CanEdit(sender, caster) then return end
    ns.db.indiv[caster] = ns.db.indiv[caster] or {}
    ns.db.indiv[caster][player] = ns.BUFF_BY_KEY[key] and key or nil
    ns.Changed("buffs")
end

function handlers.INDS(sender, caster, reset, list)
    if not caster or not ns.CanEdit(sender, caster) then return end
    if reset == "1" or not ns.db.indiv[caster] then ns.db.indiv[caster] = {} end
    for item in (list or ""):gmatch("[^,]+") do
        local player, key = strsplit("=", item)
        if player and ns.BUFF_BY_KEY[key] then ns.db.indiv[caster][player] = key end
    end
    ns.Changed("buffs")
end

-- Resurrections en cours : cible -> { by = lanceur, t = debut }
ns.rezzing = {}

function handlers.REZ(sender, target)
    if not target or target == "" then return end
    ns.rezzing[target] = { by = sender, t = GetTime() }
    ns.Changed("buffs")
end

-- Rez en cours sur ce joueur ? Renvoie le nom de celui qui le releve.
function ns.RezzedBy(name)
    local r = ns.rezzing[name]
    if not r then return nil end
    if GetTime() - r.t > ns.REZ_DURATION then
        ns.rezzing[name] = nil
        return nil
    end
    return r.by
end

function handlers.CLR(sender)
    if not ns.IsPromoted(sender) then return end
    wipe(ns.db.assign)
    wipe(ns.db.groups)
    wipe(ns.db.aura)
    wipe(ns.db.indiv)
    ns.Changed("buffs")
end

local function onAddonMessage(prefix, text, _, sender)
    if prefix ~= COMM_PREFIX or not text or issecret(text) then return end
    sender = shortName(sender)
    if not sender or sender == ns.me then return end
    local fields = { strsplit(";", text) }
    local fn = handlers[fields[1]]
    if fn then fn(sender, unpack(fields, 2)) end
end

---------------------------------------------------------------------------
-- Modifications locales (verifient les droits puis diffusent)
---------------------------------------------------------------------------

function ns.SetAssign(caster, class, key)
    if not ns.CanEdit(ns.me, caster) then return false end
    ns.db.assign[caster] = ns.db.assign[caster] or {}
    ns.db.assign[caster][class] = key
    send(string.format("ASG;%s;%s;%s", caster, class, key or "-"))
    ns.Changed()
    return true
end

function ns.SetGroups(caster, key, set)
    if not ns.CanEdit(ns.me, caster) then return false end
    if set and not next(set) then set = nil end
    ns.db.groups[caster] = ns.db.groups[caster] or {}
    ns.db.groups[caster][key] = set
    send(string.format("GRP;%s;%s;%s", caster, key, groupDigits(set)))
    ns.Changed()
    return true
end

function ns.ToggleGroup(caster, key, g)
    local cur = ns.db.groups[caster] and ns.db.groups[caster][key]
    local set = {}
    for k in pairs(cur or {}) do set[k] = true end
    set[g] = not set[g] or nil
    return ns.SetGroups(caster, key, set)
end

function ns.SetAura(caster, akey)
    if not ns.CanEdit(ns.me, caster) then return false end
    ns.db.aura[caster] = akey
    send(string.format("AUR;%s;%s", caster, akey or "-"))
    ns.Changed()
    return true
end

function ns.SetIndiv(caster, player, key)
    if not ns.CanEdit(ns.me, caster) then return false end
    ns.db.indiv[caster] = ns.db.indiv[caster] or {}
    ns.db.indiv[caster][player] = key
    send(string.format("IND;%s;%s;%s", caster, player, key or "-"))
    ns.Changed()
    return true
end

function ns.ClearAll()
    if IsInGroup() and not ns.IsPromoted(ns.me) then
        -- sans droits, on n efface que ses propres assignations
        ns.db.assign[ns.me] = {}
        ns.db.groups[ns.me] = {}
        ns.db.aura[ns.me] = nil
        ns.db.indiv[ns.me] = {}
        announce()
    else
        wipe(ns.db.assign)
        wipe(ns.db.groups)
        wipe(ns.db.aura)
        wipe(ns.db.indiv)
        send("CLR")
    end
    ns.Changed()
end

function ns.SetFreeAssign(v)
    ns.db.freeAssign = v and true or false
    if ns.casters[ns.me] then ns.casters[ns.me].freeAssign = ns.db.freeAssign end
    if IsInGroup() and ns.casters[ns.me] then send(encodeSelf()) end
    ns.Changed()
end

---------------------------------------------------------------------------
-- Cycle des valeurs (clic dans une case)
---------------------------------------------------------------------------

-- Benediction suivante/precedente que ce paladin possede. Celles deja
-- donnees a cette classe par un autre paladin sont sautees : elles ne
-- s empilent pas.
function ns.CycleBlessing(pally, class, current, step)
    local skills = ns.CasterInfo(pally).skills
    local list = ns.PROVIDERS.PALADIN.buffs
    local taken = {}
    for other, a in pairs(ns.db.assign) do
        if other ~= pally and ns.groupCasters.PALADIN and ns.groupCasters.PALADIN[other] and a[class] then
            taken[a[class]] = true
        end
    end
    local n = #list
    local idx = current and ns.BUFF_BY_KEY[current] and ns.BUFF_BY_KEY[current].index or 0
    for _ = 1, n + 1 do
        idx = idx + step
        if idx > n then idx = 0 elseif idx < 0 then idx = n end
        if idx == 0 then return nil end
        local b = list[idx]
        if skills[b.key] and not taken[b.key] then return b.key end
    end
    return nil
end

function ns.CycleAura(pally, current, step)
    local auras = ns.CasterInfo(pally).auras
    local n = #ns.AURAS
    local idx = current and ns.AURA_BY_KEY[current] and ns.AURA_BY_KEY[current].index or 0
    for _ = 1, n + 1 do
        idx = idx + step
        if idx > n then idx = 0 elseif idx < 0 then idx = n end
        if idx == 0 then return nil end
        if auras[ns.AURAS[idx].key] then return ns.AURAS[idx].key end
    end
    return nil
end

-- Buff individuel suivant que je peux donner a ce joueur
function ns.CycleIndividual(player, step)
    local prov = ns.MyProvider()
    local me = ns.casters[ns.me]
    if not prov or not me then return end
    local current = ns.db.indiv[ns.me] and ns.db.indiv[ns.me][player]
    local list = prov.buffs
    local n = #list
    local idx = current and ns.BUFF_BY_KEY[current] and ns.BUFF_BY_KEY[current].index or 0
    for _ = 1, n + 1 do
        idx = idx + step
        if idx > n then idx = 0 elseif idx < 0 then idx = n end
        if idx == 0 or me.skills[list[idx].key] then break end
    end
    ns.SetIndiv(ns.me, player, idx > 0 and list[idx].key or nil)
end

---------------------------------------------------------------------------
-- Auto-assignation
---------------------------------------------------------------------------

-- Paladins : une benediction par paladin et par classe, en suivant les
-- priorites, et en gardant le detenteur d une benediction rare pour elle.
local function autoPaladins(editable, fixed)
    local result = {}
    for _, p in ipairs(editable) do result[p] = {} end

    local function score(p, key, reachable)
        local skills = ns.CasterInfo(p).skills
        local s = skills[key]
        if not s then return nil end
        local v = (s.talent or 0) * 10 + (s.rank or 1) + (s.group and 50 or 0)
        for _, b in ipairs(ns.PROVIDERS.PALADIN.buffs) do
            if b.rare and b.key ~= key and skills[b.key] and reachable[b.key] then v = v - 100 end
        end
        return v
    end

    for _, class in ipairs(ns.CLASSES) do
        local used = {}
        for _, p in ipairs(fixed) do
            local a = ns.db.assign[p]
            if a and a[class] then used[a[class]] = true end
        end
        local free = {}
        for _, p in ipairs(editable) do free[p] = true end

        local prio = ns.PRIORITY[class]
        for i, key in ipairs(prio) do
            if not used[key] then
                local slots = -1   -- paladins libres apres celui-ci
                for _ in pairs(free) do slots = slots + 1 end
                local reachable = {}
                for j = i + 1, #prio do
                    if slots <= 0 then break end
                    if not used[prio[j]] then
                        reachable[prio[j]] = true
                        slots = slots - 1
                    end
                end
                local best, bestScore
                for _, p in ipairs(editable) do
                    if free[p] then
                        local s = score(p, key, reachable)
                        if s and (not bestScore or s > bestScore) then best, bestScore = p, s end
                    end
                end
                if best then
                    result[best][class] = key
                    free[best] = nil
                    used[key] = true
                end
            end
        end
    end
    for _, p in ipairs(editable) do ns.db.assign[p] = result[p] end
end

-- Pretres, mages, druides : pour chaque buff de groupe, les groupes presents
-- sont partages en blocs contigus entre les lanceurs qui le connaissent.
local function autoGroups(class, editable, fixed)
    local present = ns.GroupsPresent()
    for _, b in ipairs(ns.PROVIDERS[class].buffs) do
        if b.group and b.auto then
            local covered = {}
            for _, p in ipairs(fixed) do
                local set = ns.db.groups[p] and ns.db.groups[p][b.key]
                for g in pairs(set or {}) do covered[g] = true end
            end
            local todo = {}
            for _, g in ipairs(present) do
                if not covered[g] then table.insert(todo, g) end
            end
            local able = {}
            for _, p in ipairs(editable) do
                if ns.CasterInfo(p).skills[b.key] then table.insert(able, p) end
            end
            for _, p in ipairs(editable) do
                ns.db.groups[p] = ns.db.groups[p] or {}
                ns.db.groups[p][b.key] = nil
            end
            if #able > 0 and #todo > 0 then
                local per = math.ceil(#todo / #able)
                for i, g in ipairs(todo) do
                    local p = able[math.floor((i - 1) / per) + 1]
                    ns.db.groups[p][b.key] = ns.db.groups[p][b.key] or {}
                    ns.db.groups[p][b.key][g] = true
                end
            end
        end
    end
end

function ns.AutoAssign()
    local total = 0
    for _, class in ipairs(ns.PROVIDER_ORDER) do
        local editable, fixed = {}, {}
        for _, p in ipairs(ns.CasterList(class)) do
            if ns.CanEdit(ns.me, p) then table.insert(editable, p) else table.insert(fixed, p) end
        end
        if #editable > 0 then
            if ns.PROVIDERS[class].mode == "class" then
                autoPaladins(editable, fixed)
            else
                autoGroups(class, editable, fixed)
            end
            for _, p in ipairs(editable) do send(encodeAll(p)) end
            total = total + #editable
        end
    end
    if total == 0 then
        ns.Say(#ns.AllCasters() == 0 and L.NO_CASTER or L.NO_RIGHTS_ANY)
        return
    end
    ns.Say(string.format(L.AUTO_DONE, total))
    ns.Changed()
end

---------------------------------------------------------------------------
-- Annonce des assignations dans le canal du groupe
---------------------------------------------------------------------------

function ns.Report()
    local lines = {}
    for _, p in ipairs(ns.AllCasters()) do
        local parts = {}
        local class = ns.CasterClass(p)
        if class == "PALADIN" then
            local a = ns.db.assign[p] or {}
            local byBless = {}
            for _, c in ipairs(ns.CLASSES) do
                local key = a[c]
                if key and ns.byClass[c] then
                    byBless[key] = byBless[key] or {}
                    table.insert(byBless[key], ns.ClassName(c))
                end
            end
            for _, b in ipairs(ns.PROVIDERS.PALADIN.buffs) do
                if byBless[b.key] then
                    table.insert(parts, ns.BuffShort(b.key) .. " : " .. table.concat(byBless[b.key], ", "))
                end
            end
            local aura = ns.db.aura[p]
            if aura then table.insert(parts, string.format(L.REPORT_AURA, ns.AuraName(aura) or aura)) end
        elseif class then
            for _, b in ipairs(ns.PROVIDERS[class].buffs) do
                local set = ns.db.groups[p] and ns.db.groups[p][b.key]
                if set and next(set) then
                    table.insert(parts, string.format(L.REPORT_GROUPS, ns.BuffShort(b.key), ns.FormatGroups(set)))
                end
            end
        end
        if #parts > 0 then table.insert(lines, p .. " - " .. table.concat(parts, " ; ")) end
    end
    if #lines == 0 then
        ns.Say(L.NOTHING_REPORT)
        return
    end
    local chan = IsInRaid() and "RAID" or (IsInGroup() and "PARTY") or nil
    for _, line in ipairs(lines) do
        if #line > 250 then line = line:sub(1, 247) .. "..." end
        if chan then
            pcall(SendChatMessage, line, chan)
        else
            ns.Chat(line)
        end
    end
end

---------------------------------------------------------------------------
-- Etat des buffs sur les membres
---------------------------------------------------------------------------

-- nom d aura -> { key, group }
local auraLookup = {}
local function buildLookup()
    wipe(auraLookup)
    for key, b in pairs(ns.BUFF_BY_KEY) do
        local n = ns.SpellName(b.single)
        local g = b.group and ns.SpellName(b.group)
        if n then auraLookup[n] = { key = key, group = false } end
        if g then auraLookup[g] = { key = key, group = true } end
    end
end

ns.buffs = {}   -- cle membre -> { [buff] = { exp = t, group = bool } }

local getAura
if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    getAura = function(unit, i)
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
        if not aura then return nil end
        return aura.name, aura.expirationTime
    end
elseif UnitBuff then
    getAura = function(unit, i)
        local name, _, _, _, _, exp = UnitBuff(unit, i)
        return name, exp
    end
end

-- Relit les buffs suivis d un membre. Si les donnees sont secretes
-- (combat), le cache precedent est conserve.
local function scanMember(m)
    if not getAura then return end
    local found = {}
    local ok = pcall(function()
        for i = 1, 40 do
            local name, exp = getAura(m.unit, i)
            if name == nil then break end
            if issecret(name) then error("secret") end
            local hit = auraLookup[name]
            if hit then
                exp = clean(exp) or 0
                found[hit.key] = { exp = exp, group = hit.group }
            end
        end
    end)
    if ok then ns.buffs[m.key] = found end
    return ok
end

function ns.ScanBuffs()
    if not next(auraLookup) then buildLookup() end
    for _, m in ipairs(ns.roster) do scanMember(m) end
end

-- unites dont les auras sont illisibles (secretes) pendant ce combat :
-- plus relues jusqu a la fin du combat (un releve complet y est prevu)
local secretInCombat = {}
function ns.ScanUnit(unit)
    if issecret(unit) or secretInCombat[unit] then return end
    local m = ns.byUnit[unit]
    if not m then return end
    if not scanMember(m) and InCombatLockdown() then secretInCombat[unit] = true end
end
function ns.ResetSecretAuras() wipe(secretInCombat) end

-- Ce que MOI je dois donner a ce membre : liste de
-- { key, indiv = bool, via = "class"|"group"|nil }
function ns.MyBuffsFor(m)
    local list = {}
    local prov = ns.MyProvider()
    if not prov then return list end
    local indiv = ns.db.indiv[ns.me] and ns.db.indiv[ns.me][m.name]
    if prov.mode == "class" then
        -- une benediction par paladin et par cible : l individuelle remplace
        if indiv then
            table.insert(list, { key = indiv, indiv = true })
        else
            local a = ns.db.assign[ns.me]
            if a and a[m.class] then table.insert(list, { key = a[m.class], via = "class" }) end
        end
        return list
    end
    local seen = {}
    local groups = ns.db.groups[ns.me] or {}
    for _, b in ipairs(prov.buffs) do
        local set = groups[b.key]
        if set and set[m.group] and not (b.manaOnly and ns.NO_MANA[m.class]) then
            table.insert(list, { key = b.key, via = "group" })
            seen[b.key] = true
        end
    end
    if indiv and not seen[indiv] then table.insert(list, { key = indiv, indiv = true }) end
    return list
end

-- Secondes restantes du buff sur ce membre, nil si absent.
-- Une aura sans duree renvoie math.huge.
function ns.Remaining(m, key)
    local b = ns.buffs[m.key]
    local e = b and b[key]
    if not e then return nil end
    if not e.exp or e.exp == 0 then return math.huge, e.group end
    local left = e.exp - GetTime()
    if left <= 0 then return nil end
    return left, e.group
end

function ns.IsDead(unit)
    local ok, dead = pcall(UnitIsDeadOrGhost, unit)
    if ok and clean(dead) ~= nil then return dead end
    return false
end

function ns.IsConnected(unit)
    local ok, c = pcall(UnitIsConnected, unit)
    if ok and clean(c) ~= nil then return c end
    return true
end

-- A portee ? nil = inconnu (en combat, souvent secret)
function ns.InRange(unit, spell)
    if UnitIsUnit(unit, "player") then return true end
    if spell and C_Spell and C_Spell.IsSpellInRange then
        local ok, r = pcall(C_Spell.IsSpellInRange, spell, unit)
        if ok and r ~= nil and not issecret(r) then return r and true or false end
    end
    if UnitInRange then
        local ok, r, checked = pcall(UnitInRange, unit)
        if ok and not issecret(r) and not issecret(checked) and checked then return r and true or false end
    end
    return nil
end

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
local rosterDirty, selfDirty, buffsDirty = true, true, true
local lastGroupSize = 0

local function onRosterChanged()
    rosterDirty = true
    local size = GetNumGroupMembers()
    if size > 0 and lastGroupSize == 0 then
        C_Timer.After(1, ns.RequestSync)
    elseif size > lastGroupSize then
        announceSoon()
    end
    lastGroupSize = size
end

local events = {}

function events.ADDON_LOADED(name)
    if name ~= ADDON_NAME then return end
    initDB()
    ns.me = unitName("player")
end

function events.PLAYER_LOGIN()
    ns.me = unitName("player") or ns.me
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(COMM_PREFIX)
    elseif RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(COMM_PREFIX)
    end
    buildLookup()
end

function events.PLAYER_ENTERING_WORLD()
    selfDirty, rosterDirty, buffsDirty = true, true, true
    lastGroupSize = GetNumGroupMembers()
    C_Timer.After(2, ns.RequestSync)
end

function events.GROUP_ROSTER_UPDATE() onRosterChanged() end

local function skillsChanged()
    selfDirty = true
    announceSoon(2)
end
events.SPELLS_CHANGED = skillsChanged
events.LEARNED_SPELL_IN_TAB = skillsChanged
events.CHARACTER_POINTS_CHANGED = skillsChanged
events.PLAYER_TALENT_UPDATE = skillsChanged

function events.BAG_UPDATE_DELAYED()
    if updateReagents() then ns.Changed("buffs") end
end

function events.UNIT_AURA(unit)
    if unit then ns.ScanUnit(unit) end
end

function events.CHAT_MSG_ADDON(...)
    onAddonMessage(...)
end

-- Le sort part vraiment : on previent les autres lanceurs et le groupe.
-- (UNIT_SPELLCAST_SENT couvre aussi un rez lance hors de la barre.)
local lastRez = {}
function events.UNIT_SPELLCAST_SENT(unit, target, _, spellID)
    if unit ~= "player" then return end
    spellID, target = clean(spellID), clean(target)
    if not spellID or not target or target == "" then return end
    local cast = ns.SpellName(spellID)
    local rezName
    for _, id in ipairs(ns.REZ_SPELLS) do
        local n = ns.SpellName(id)
        if n and n == cast then rezName = n break end
    end
    if not rezName then return end
    target = shortName(target)
    local now = GetTime()
    if lastRez[target] and now - lastRez[target] < 2 then return end
    lastRez[target] = now
    ns.rezzing[target] = { by = ns.me, t = now }
    send("REZ;" .. target)
    if ns.db.rezAnnounce then
        local chan = IsInRaid() and "RAID" or (IsInGroup() and "PARTY") or nil
        local msg = string.format(L.REZ_MSG, rezName, target)
        if chan then pcall(SendChatMessage, msg, chan) else ns.Say(msg) end
    end
    ns.Changed("buffs")
end

function events.PLAYER_REGEN_ENABLED()
    buffsDirty = true
    ns.ResetSecretAuras()
    ns.Changed("buffs")
end

ev:SetScript("OnEvent", function(_, event, ...)
    if ns.ModuleOff("buffs", ev) then return end
    local fn = events[event]
    if fn then fn(...) end
end)

for event in pairs(events) do
    pcall(ev.RegisterEvent, ev, event)
end

-- Boucle lente : recalcul groupe/competences, puis rafraichissement UI
local elapsed = 0
ev:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.5 then return end
    elapsed = 0
    if not ns.db or not ns.me then return end
    local changed = false
    if selfDirty then
        selfDirty = false
        scanSelf()
        changed = true
    end
    if rosterDirty then
        rosterDirty = false
        ns.BuildRoster()
        buffsDirty = true
        changed = true
    end
    if buffsDirty then
        buffsDirty = false
        ns.ScanBuffs()
        changed = true
    end
    if changed then ns.Changed("buffs") end
    if ns.Tick then ns.Tick() end
end)

---------------------------------------------------------------------------
-- Commandes
---------------------------------------------------------------------------

local function help()
    ns.Say(L.HELP_TITLE)
    for i, desc in ipairs(L.HELP) do
        local sub = ns.HelpCommands()[i] or ""
        ns.Chat(string.format("  |cffffff00/bf%s|r - %s", sub ~= "" and (" " .. sub) or "", desc))
    end
end

local function toggled(on, keyOn, keyOff)
    ns.Say(on and L[keyOn] or L[keyOff])
end

local function slash(input)
    if not ns.db then initDB() end
    local cmd, arg = strsplit(" ", strlower(strtrim(input or "")), 2)
    if cmd == "" then
        if ns.ToggleWindow then ns.ToggleWindow() end
    elseif cmd == "barre" or cmd == "bar" then
        ns.db.bar.shown = not ns.db.bar.shown
        toggled(ns.db.bar.shown, "BAR_SHOWN", "BAR_HIDDEN")
        ns.Changed()
    elseif cmd == "lock" or cmd == "verrou" then
        ns.db.bar.locked = not ns.db.bar.locked
        toggled(ns.db.bar.locked, "BAR_LOCKED", "BAR_UNLOCKED")
        ns.Changed()
    elseif cmd == "echelle" or cmd == "scale" then
        local v = tonumber(arg)
        if v and v >= 0.5 and v <= 2 then
            ns.db.bar.scale = v
            ns.Changed()
        else
            ns.Say(L.SCALE_RANGE)
        end
    elseif cmd == "sens" or cmd == "orient" or cmd == "dir" then
        ns.db.bar.vertical = not ns.db.bar.vertical
        ns.Changed()
    elseif cmd == "auto" then
        ns.AutoAssign()
    elseif cmd == "sync" then
        ns.RequestSync()
        ns.Say(L.SYNC_REQUESTED)
    elseif cmd == "annonce" or cmd == "report" then
        ns.Report()
    elseif cmd == "effacer" or cmd == "clear" then
        ns.ClearAll()
    elseif cmd == "libre" or cmd == "free" then
        ns.SetFreeAssign(not ns.db.freeAssign)
        toggled(ns.db.freeAssign, "FREE_ON", "FREE_OFF")
    elseif cmd == "masquer" or cmd == "hide" then
        ns.db.hideBuffed = not ns.db.hideBuffed
        toggled(ns.db.hideBuffed, "HIDE_ON", "HIDE_OFF")
        ns.Changed()
    elseif cmd == "morts" or cmd == "dead" then
        ns.db.showDead = not ns.db.showDead
        toggled(ns.db.showDead, "DEAD_ON", "DEAD_OFF")
        ns.Changed()
    elseif cmd == "rezmsg" then
        ns.db.rezAnnounce = not ns.db.rezAnnounce
        toggled(ns.db.rezAnnounce, "REZMSG_ON", "REZMSG_OFF")
    elseif cmd == "lang" or cmd == "langue" or cmd == "language" then
        ns.LangCommand(arg)
    elseif cmd == "minimap" then
        ns.ToggleMinimap()
    elseif cmd == "reset" then
        if InCombatLockdown() then ns.Say(L.COMBAT_BLOCKED) return end
        ns.db.bar.point, ns.db.bar.rel, ns.db.bar.x, ns.db.bar.y = "CENTER", nil, -300, 100
        ns.db.win.point, ns.db.win.rel, ns.db.win.x, ns.db.win.y = "CENTER", nil, 0, 80
        if ns.ResetPositions then ns.ResetPositions() end
    else
        help()
    end
end

ns.RegisterModule({
    command = "buffs",
    panelName = "CorpUIWindow",
    alias = "/bf",
    icon = "Interface\\Icons\\Spell_Holy_PrayerOfFortitude",
    title = function() return L.MOD_BUFFS end,
    desc = function() return L.HT_BUFFS end,
    Slash = slash,
    Open = function() if ns.ToggleWindow then ns.ToggleWindow() end end,
    Alt = function()
        if not ns.db then return end
        ns.db.bar.shown = not ns.db.bar.shown
        ns.Changed()
    end,
})

-- raccourci historique : /bf = /corp buffs
SLASH_CORPUIBUFFS1 = "/bf"
SlashCmdList["CORPUIBUFFS"] = function(input)
    if ns.SlashOff("buffs") then return end
    slash(input)
end
