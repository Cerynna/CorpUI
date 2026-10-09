--[[--------------------------------------------------------------------------
    CorpUI - module Talents : export et import des talents (C_Traits)

    Sur ce client (variante Camelot), le systeme de "loadouts" de Blizzard
    est cache : aucun menu Importer / Exporter n est atteignable, et le
    dialogue d import natif creerait un loadout invisible applique tout
    seul. CorpUI fait donc le travail lui-meme, au plus pres du jeu :

      - EXPORT : lecture seule. La chaine vient de C_Traits.GenerateImportString
        (verifiee par notre lecteur), sinon de notre encodeur, copie exacte
        du format de Blizzard (Blizzard_ClassTalentImportExport.lua +
        ExportUtil.lua, sans la bibliotheque bit : arithmetique pure).
        Elle s affiche selectionnee dans une boite CorpUI : Ctrl+C.
        Jamais CopyToClipboard (fonction protegee).
      - IMPORT : decodage CorpUI, puis les rangs sont MIS EN ATTENTE par
        C_Traits (PurchaseRank / SetSelection, et ResetTreeByCurrency s il
        faut retirer des points), fenetre des talents FERMEE ainsi que tout
        autre arbre de traits de Blizzard (metiers, Heritage, compagnon des
        Gouffres..., repere par EnumerateFrames en lecture seule) : les
        evenements TRAIT_* partent pendant l appel, les gestionnaires de
        Blizzard ne doivent pas tourner a ce moment-la. Si la fenetre des
        sorts est ouverte sur les talents ou le grimoire, le bouton securise
        "Preparer" la ferme d abord (clic du vrai micro-bouton qui la
        ferme) ; sur un autre onglet, il refuse avec un message. Remise a
        zero refusee ou incomplete : rien n est achete, l attente est
        defaite. Jamais CommitConfig, LoadConfig ni ImportLoadout : c est le
        joueur qui clique sur "Appliquer" dans la fenetre du jeu.
      - GUIDE : sans rien modifier, des reperes "+N" sur la page des talents
        (nos textes, poses sur leurs boutons, ranges dans une table faible).
        Mode de secours si le jeu bloque la preparation par l addon
        (ADDON_ACTION_BLOCKED / FORBIDDEN).
    Rien en combat. Toute valeur lue passe par pcall et issecretvalue.
    Barre Exporter / Importer sur la page des talents : cadre CorpUI pose
    par-dessus (strate superieure), jamais un enfant du cadre de Blizzard.
----------------------------------------------------------------------------]]

local ADDON, ns = ...
local L = ns.L

local issecret = issecretvalue or function() return false end
local weak = { __mode = "k" }

local db
local M = {}            -- fonctions exposees (diagnostic, tests)
ns.Talents = M

---------------------------------------------------------------------------
-- Lectures protegees
---------------------------------------------------------------------------

local function num(v)
    if v == nil or type(v) ~= "number" or issecret(v) then return nil end
    return v
end

local function str(v)
    if type(v) ~= "string" or issecret(v) then return nil end
    return v
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end

local function val(t, key)
    if type(t) ~= "table" then return nil end
    local ok, v = pcall(function() return t[key] end)
    if ok and not issecret(v) then return v end
end

local function tbl(t, key)
    local v = val(t, key)
    if type(v) == "table" then return v end
end

local function visible(f)
    if type(f) ~= "table" or not f.IsVisible then return false end
    local ok, v = pcall(f.IsVisible, f)
    return ok and v == true
end

local function childrenOf(f)
    if type(f) ~= "table" or not f.GetChildren then return {} end
    local ok, list = pcall(function() return { f:GetChildren() } end)
    return ok and list or {}
end

local function api(space, name)
    local t = _G[space]
    if type(t) == "table" then return t[name] end
end

local function combat()
    return InCombatLockdown and InCombatLockdown() and true or false
end

---------------------------------------------------------------------------
-- Codec : base64 de Blizzard (A-Z a-z 0-9 + /), bits remplis par le bas de
-- chaque caractere de 6 bits. En-tete : version (8), specialisation (16),
-- empreinte de l arbre (16 x 8, zero = pas de controle). Puis, pour chaque
-- noeud dans l ordre de C_Traits.GetTreeNodes : choisi (1) [achete (1)
-- [partiel (1) [rangs (6)] choix (1) [index (2), base 0]]].
---------------------------------------------------------------------------

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local CHAR, VALUE = {}, {}
for i = 1, 64 do
    local c = B64:sub(i, i)
    CHAR[i - 1] = c
    VALUE[c] = i - 1
end

local function newWriter() return { out = {}, cur = 0, used = 0 } end

local function put(w, bits, value)
    value = math.floor(value)
    if value < 0 or value >= 2 ^ bits then error("value out of range") end
    while bits > 0 do
        local take = math.min(6 - w.used, bits)
        local p = 2 ^ take
        local part = value % p
        value = (value - part) / p
        w.cur = w.cur + part * 2 ^ w.used
        w.used = w.used + take
        bits = bits - take
        if w.used == 6 then
            w.out[#w.out + 1] = CHAR[w.cur]
            w.cur, w.used = 0, 0
        end
    end
end

local function finish(w)
    if w.used > 0 then
        w.out[#w.out + 1] = CHAR[w.cur]
        w.cur, w.used = 0, 0
    end
    return table.concat(w.out)
end

local function newReader(s)
    local vals = {}
    for i = 1, #s do
        local v = VALUE[s:sub(i, i)]
        if not v then return nil end
        vals[i] = v
    end
    return { vals = vals, idx = 1, used = 0, rest = vals[1] }
end

-- nil si la chaine est epuisee
local function get(r, bits)
    local value, shift = 0, 0
    while bits > 0 do
        if r.idx > #r.vals then return nil end
        local take = math.min(6 - r.used, bits)
        local p = 2 ^ take
        local part = r.rest % p
        r.rest = (r.rest - part) / p
        value = value + part * 2 ^ shift
        shift = shift + take
        bits = bits - take
        r.used = r.used + take
        if r.used == 6 then
            r.idx = r.idx + 1
            r.used = 0
            r.rest = r.vals[r.idx]
        end
    end
    return math.floor(value)
end

local HEADER_BITS = 8 + 16 + 128

local function readHeader(r)
    if #r.vals * 6 < HEADER_BITS then return nil end
    local version = get(r, 8)
    local spec = get(r, 16)
    local hash = {}
    for i = 1, 16 do hash[i] = get(r, 8) end
    if not (version and spec and hash[16]) then return nil end
    return version, spec, hash
end

-- contenu : une entree par noeud. Comme chez Blizzard, une chaine qui
-- s arrete entre deux noeuds laisse les suivants non choisis ; une chaine
-- coupee au milieu d un noeud est illisible.
local function readContent(r, count)
    local list = {}
    for i = 1, count do
        local e = { selected = false, granted = false, partial = false, ranks = 0, choice = false, index = 1 }
        local sel = get(r, 1)
        if sel == 1 then
            e.selected = true
            local bought = get(r, 1)
            if bought == nil then return nil end
            if bought == 1 then
                local partial = get(r, 1)
                if partial == nil then return nil end
                if partial == 1 then
                    e.partial = true
                    e.ranks = get(r, 6)
                    if e.ranks == nil then return nil end
                end
                local choice = get(r, 1)
                if choice == nil then return nil end
                if choice == 1 then
                    e.choice = true
                    local idx = get(r, 2)
                    if idx == nil then return nil end
                    e.index = idx + 1
                end
            else
                e.granted = true
            end
        end
        list[i] = e
    end
    return list
end

-- "|Htalentbuild:spec:niveau:CHAINE|h[...]|h" ou chaine brute (espaces retires)
local function clean(s)
    s = str(s) or ""
    local inLink = s:match("talentbuild:%d+:%d+:([%w%+/]+)")
    if inLink then return inLink end
    return (s:gsub("[%s]", ""))
end

M.newWriter, M.put, M.finish, M.newReader, M.get = newWriter, put, finish, newReader, get
M.readHeader, M.readContent, M.clean = readHeader, readContent, clean

---------------------------------------------------------------------------
-- Etat du jeu (lecture seule)
---------------------------------------------------------------------------

local TYPE_SELECTION, TYPE_SUBTREE = 2, 3

local function enumValue(group, key, default)
    local e = type(Enum) == "table" and Enum[group]
    local v = type(e) == "table" and num(e[key])
    return v or default
end

local function isChoiceType(t)
    t = num(t)
    return t ~= nil and (t == enumValue("TraitNodeType", "Selection", TYPE_SELECTION)
        or t == enumValue("TraitNodeType", "SubTreeSelection", TYPE_SUBTREE))
end

local function currentSpecID()
    local pu = _G.PlayerUtil
    local id = num(call(type(pu) == "table" and pu.GetCurrentSpecID))
    if id then return id end
    local idx = num(call(api("C_SpecializationInfo", "GetSpecialization")))
    if idx then return num(call(api("C_SpecializationInfo", "GetSpecializationInfo"), idx)) end
end

local function serialVersion()
    return num(call(api("C_Traits", "GetLoadoutSerializationVersion")))
end

local function numGroups()
    local fn = _G.GetNumSpecGroups or api("C_SpecializationInfo", "GetNumSpecGroups")
    return num(call(fn)) or 1
end

local function activeGroup()
    return num(call(api("C_SpecializationInfo", "GetActiveSpecGroup"))) or 1
end

local function configFor(group)
    local id = num(call(api("C_SpecializationInfo", "GetCombatConfigIDForSpecGroup"), group))
    if not id and group == activeGroup() then id = num(call(api("C_ClassTalents", "GetActiveConfigID"))) end
    return id
end

local function activeConfig()
    return configFor(activeGroup())
end

local function treeOf(cfg)
    if cfg then
        local info = call(api("C_Traits", "GetConfigInfo"), cfg)
        local ids = tbl(info, "treeIDs")
        local t = ids and num(val(ids, 1))
        if t then return t end
    end
    local spec = currentSpecID()
    if spec then return num(call(api("C_ClassTalents", "GetTraitTreeForSpec"), spec)) end
end

local function treeNodes(tree)
    local list = call(api("C_Traits", "GetTreeNodes"), tree)
    if type(list) ~= "table" then return nil end
    local out = {}
    for i = 1, #list do
        local id = num(list[i])
        if not id then return nil end
        out[i] = id
    end
    return out
end

local function nodeInfo(cfg, id)
    local info = call(api("C_Traits", "GetNodeInfo"), cfg, id)
    if type(info) == "table" then return info end
end

local function ranksOf(info) return num(val(info, "ranksPurchased")) or 0 end

local function activeEntryOf(info)
    local e = tbl(info, "activeEntry")
    return e and num(val(e, "entryID"))
end

local function entriesOf(info) return tbl(info, "entryIDs") or {} end

local function treeHash(tree)
    local h = call(api("C_Traits", "GetTreeHash"), tree)
    if type(h) ~= "table" then return nil end
    local out = {}
    for i = 1, 16 do
        out[i] = num(h[i])
        if not out[i] then return nil end
    end
    return out
end

local function zeroHash(h)
    for i = 1, 16 do if (h[i] or 0) ~= 0 then return false end end
    return true
end

local function sameHash(a, b)
    for i = 1, 16 do if a[i] ~= b[i] then return false end end
    return true
end

-- groupes affiches (les arbres de la classe) : { { id, name } }
local function groupsOf(tree)
    local list = call(api("C_Traits", "GetGroupDisplayInfoByTreeID"), tree)
    local out = {}
    if type(list) ~= "table" then return out end
    for _, g in ipairs(list) do
        local id, name = num(val(g, "groupID")), str(val(g, "displayName"))
        if id then out[#out + 1] = { id = id, name = name or "?" } end
    end
    return out
end

local function groupOfNode(info, groups)
    local ids = tbl(info, "groupIDs")
    if not ids then return nil end
    for _, gid in ipairs(ids) do
        gid = num(gid)
        for _, g in ipairs(groups) do if g.id == gid then return gid end end
    end
end

local function unspent(cfg, tree)
    local list = call(api("C_Traits", "GetTreeCurrencyInfo"), cfg, tree, false)
    local first = type(list) == "table" and list[1]
    return first and num(val(first, "quantity")) or nil
end

local function currencyIDs(cfg, tree)
    local list = call(api("C_Traits", "GetTreeCurrencyInfo"), cfg, tree, false)
    local out = {}
    if type(list) == "table" then
        for _, c in ipairs(list) do
            local id = num(val(c, "traitCurrencyID"))
            if id then out[#out + 1] = id end
        end
    end
    return out
end

local function hasStaged(cfg)
    return call(api("C_Traits", "ConfigHasStagedChanges"), cfg) == true
end

local function spellNameOf(cfg, entry)
    if not entry then return nil end
    local e = call(api("C_Traits", "GetEntryInfo"), cfg, entry)
    local def = e and num(val(e, "definitionID"))
    local d = def and call(api("C_Traits", "GetDefinitionInfo"), def)
    if not d then return nil end
    local name = str(val(d, "overrideName"))
    if name and name ~= "" then return name end
    local spell = num(val(d, "spellID"))
    if spell then
        name = str(call(api("C_Spell", "GetSpellName"), spell))
        if not name and _G.GetSpellInfo then name = str(call(_G.GetSpellInfo, spell)) end
    end
    return name
end

-- les fenetres de Blizzard qui ecoutent les evenements TRAIT_* quand elles
-- sont ouvertes (hors fenetre des sorts) : arbres de traits derives de
-- TalentFrameBaseTemplate (metiers, traits generiques, Heritage propre a
-- Camelot, compagnon des Gouffres...) et collections (montures)
local TRAIT_WINDOWS = { "ProfessionsFrame", "GenericTraitFrame", "CollectionsJournal", "LegacySystemFrame",
                        "DelvesCompanionAbilityListFrame", "DelvesDifficultyPickerFrame" }

local function isUnder(f, root)
    for _ = 1, 10 do
        if f == root then return true end
        if type(f) ~= "table" or not f.GetParent then return false end
        local ok, p = pcall(f.GetParent, f)
        if not ok or type(p) ~= "table" then return false end
        f = p
    end
    return false
end

-- un cadre d arbre de traits ouvert : il porte la methode de
-- TalentFrameBaseMixin qui marque un noeud a rafraichir (lecture seule)
local function isTraitFrame(f)
    return type(f) == "table" and type(rawget(f, "MarkNodeInfoCacheDirty")) == "function" and visible(f)
end

-- parcours de tous les cadres (au clic seulement) : tout arbre de traits
-- visible hors de la fenetre des sorts, nomme ou non
local function anyTraitFrameOpen()
    local enum = _G.EnumerateFrames
    if type(enum) ~= "function" then return nil end
    local psf = _G.PlayerSpellsFrame
    local okE, f = pcall(enum)
    local n = 0
    while okE and f and n < 200000 do
        n = n + 1
        local okT, hit = pcall(isTraitFrame, f)
        if okT and hit and not (psf and isUnder(f, psf)) then return f end
        okE, f = pcall(enum, f)
    end
end

local function otherTraitWindowOpen()
    for _, n in ipairs(TRAIT_WINDOWS) do
        local f = rawget(_G, n)
        if visible(f) then return f end
    end
    return anyTraitFrameOpen()
end

-- titre affiche d une fenetre (ou de son cadre parent), sinon nil
local function textOf(fs)
    if type(fs) ~= "table" or not fs.GetText then return nil end
    local ok, t = pcall(fs.GetText, fs)
    t = ok and str(t) or nil
    if t and t ~= "" then return t end
end

local function titleOf(f)
    for _ = 1, 6 do
        if type(f) ~= "table" then return nil end
        local t = textOf(tbl(tbl(f, "TitleContainer"), "TitleText")) or textOf(tbl(f, "TitleText"))
        if t then return t end
        if not f.GetParent then return nil end
        local ok, p = pcall(f.GetParent, f)
        f = ok and p or nil
    end
end

local function windowsMessage(f)
    local t = titleOf(f)
    if t then return string.format(L.TAL_ERR_WINDOW, t) end
    return L.TAL_ERR_WINDOWS
end

local function talentsPage()
    return tbl(_G.PlayerSpellsFrame, "TalentsFrame")
end

local function spellsOpen() return visible(_G.PlayerSpellsFrame) end

local function inspecting()
    local psf = _G.PlayerSpellsFrame
    if type(psf) ~= "table" then return false end
    return val(psf, "inspectUnit") ~= nil or val(psf, "inspectString") ~= nil
end

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------

local function encode(cfg, tree, spec)
    local nodes = treeNodes(tree)
    if not nodes or not spec then return nil end
    local version = serialVersion() or 1
    local hash = treeHash(tree)
    if not hash then
        hash = {}
        for i = 1, 16 do hash[i] = 0 end
    end
    local w = newWriter()
    put(w, 8, version)
    put(w, 16, spec)
    for i = 1, 16 do put(w, 8, hash[i]) end
    for _, id in ipairs(nodes) do
        local info = nodeInfo(cfg, id)
        local bought = info and ranksOf(info) or 0
        local active = info and num(val(info, "activeRank")) or 0
        local granted = active - bought > 0
        local selected = granted or bought > 0
        put(w, 1, selected and 1 or 0)
        if selected then
            put(w, 1, bought > 0 and 1 or 0)
            if bought > 0 then
                local max = num(val(info, "maxRanks")) or bought
                local partial = bought ~= max
                put(w, 1, partial and 1 or 0)
                if partial then put(w, 6, math.min(63, bought)) end
                local choice = isChoiceType(val(info, "type"))
                put(w, 1, choice and 1 or 0)
                if choice then
                    local idx, cur = 1, activeEntryOf(info)
                    for k, e in ipairs(entriesOf(info)) do if num(e) == cur then idx = k end end
                    put(w, 2, math.max(0, math.min(3, idx - 1)))
                end
            end
        end
    end
    return finish(w)
end
M.encode = encode

-- specialisations acceptees a l import : celle du joueur, et celle que le
-- jeu ecrit lui-meme dans ses chaines (si elle differe)
local gameSpec

local function headerOf(s)
    local r = newReader(s)
    if not r then return nil end
    local ok, v, spec = pcall(readHeader, r)
    if ok and v then return v, spec end
end

-- chaine du jeu si elle est lisible et coherente, sinon la notre
local function generate(cfg, tree)
    local spec = currentSpecID()
    local s = str(call(api("C_Traits", "GenerateImportString"), cfg))
    if s and s ~= "" then
        local v, sp = headerOf(s)
        local cur = serialVersion()
        if v and (not cur or v == cur) and sp and sp > 0 then
            if sp ~= spec then gameSpec = sp end
            return s, "game"
        end
    end
    local ok, mine = pcall(encode, cfg, tree, spec)
    if ok and mine then return mine, "corpui" end
end
M.generate = generate

local function specAccepted(spec)
    if not spec then return false end
    local cur = currentSpecID()
    if cur and spec == cur then return true end
    if gameSpec and spec == gameSpec then return true end
    -- premiere fois : on demande au jeu quelle specialisation il ecrit
    if not gameSpec then
        local cfg = activeConfig()
        local s = cfg and str(call(api("C_Traits", "GenerateImportString"), cfg))
        local _, sp = s and headerOf(s)
        if sp and sp ~= cur then gameSpec = sp end
        return sp ~= nil and spec == sp
    end
    return false
end

-- "Arcanes 31 · Feu 20 · Givre 0" (ranks : groupe -> rangs)
local function summaryText(tree, ranks, total)
    local groups = groupsOf(tree)
    if #groups == 0 then return string.format(L.TAL_RANKS, total or 0) end
    local parts = {}
    for _, g in ipairs(groups) do parts[#parts + 1] = g.name .. " " .. (ranks[g.id] or 0) end
    return table.concat(parts, "  \194\183  ")
end

local function configSummary(cfg, tree)
    local groups = groupsOf(tree)
    local ranks, total = {}, 0
    for _, id in ipairs(treeNodes(tree) or {}) do
        local info = nodeInfo(cfg, id)
        local r = info and ranksOf(info) or 0
        if r > 0 then
            total = total + r
            local g = groupOfNode(info, groups)
            if g then ranks[g] = (ranks[g] or 0) + r end
        end
    end
    return summaryText(tree, ranks, total)
end
M.configSummary = configSummary

---------------------------------------------------------------------------
-- Import : lecture et controle d une chaine
---------------------------------------------------------------------------

-- renvoie dec = { str, spec, cfg, tree, targets[nodeID], list (ordre de
-- l arbre), summary } ou nil, message d erreur (nil, nil : chaine vide)
local function analyse(input)
    local s = clean(input)
    if s == "" then return nil, nil end
    local r = newReader(s)
    if not r then return nil, L.TAL_ERR_BAD end
    local ok, version, spec, hash = pcall(readHeader, r)
    if not ok or not version then return nil, L.TAL_ERR_BAD end
    local cur = serialVersion()
    if cur and version ~= cur then return nil, L.TAL_ERR_VERSION end
    if not specAccepted(spec) then return nil, L.TAL_ERR_SPEC end
    local cfg = activeConfig()
    local tree = treeOf(cfg)
    if not (cfg and tree) then return nil, L.TAL_ERR_NOTREE end
    if not zeroHash(hash) then
        local th = treeHash(tree)
        if th and not sameHash(hash, th) then return nil, L.TAL_ERR_TREE end
    end
    local nodes = treeNodes(tree)
    if not nodes then return nil, L.TAL_ERR_NOTREE end
    local okC, content = pcall(readContent, r, #nodes)
    if not okC or not content then return nil, L.TAL_ERR_BAD end
    local groups = groupsOf(tree)
    local dec = { str = s, spec = spec, cfg = cfg, tree = tree, targets = {}, list = {}, nodes = nodes }
    local ranks, total = {}, 0
    for i, id in ipairs(nodes) do
        local e = content[i]
        if e and e.selected and not e.granted then
            local info = nodeInfo(cfg, id)
            if info then
                local max = num(val(info, "maxRanks")) or 1
                local want = e.partial and e.ranks or max
                local entries = entriesOf(info)
                local choice = e.choice or isChoiceType(val(info, "type"))
                local entry
                if e.choice then entry = num(entries[e.index]) end
                if not entry then entry = activeEntryOf(info) or num(entries[1]) end
                if want > 0 then
                    local t = { id = id, ranks = want, entry = entry, isChoice = choice and e.choice,
                                index = e.index, x = num(val(info, "posX")) or 0, y = num(val(info, "posY")) or 0 }
                    dec.targets[id] = t
                    dec.list[#dec.list + 1] = t
                    total = total + want
                    local g = groupOfNode(info, groups)
                    if g then ranks[g] = (ranks[g] or 0) + want end
                end
            end
        end
    end
    dec.total = total
    dec.summary = summaryText(tree, ranks, total)
    return dec
end
M.analyse = analyse

-- ecart avec l etat actuel : faut-il retirer des points, combien en acheter
local function compare(dec, cfg)
    local refund, toBuy = false, 0
    for _, id in ipairs(dec.nodes) do
        local info = nodeInfo(cfg, id)
        if info then
            local cur = ranksOf(info)
            local t = dec.targets[id]
            local want = t and t.ranks or 0
            if cur > want then refund = true end
            if t and t.isChoice and cur > 0 and t.entry and activeEntryOf(info) ~= t.entry then refund = true end
            if want > cur then toBuy = toBuy + want - cur end
        end
    end
    return refund, toBuy
end

-- rangs encore a acheter dans la config affichee (guide)
local function remaining(dec, cfg)
    local left = 0
    for _, t in ipairs(dec.list) do
        local info = nodeInfo(cfg, t.id)
        local cur = info and ranksOf(info) or 0
        if t.isChoice and cur > 0 and activeEntryOf(info) ~= t.entry then
            left = left + t.ranks
        elseif t.ranks > cur then
            left = left + t.ranks - cur
        end
    end
    return left
end
M.remaining = remaining

---------------------------------------------------------------------------
-- Import : mise en attente (jamais d application)
---------------------------------------------------------------------------

local staging = false        -- un appel C_Traits est en cours
local blockedNow = false     -- le jeu a bloque un de ces appels

local function looksBlocked(err)
    err = str(err) or ""
    err = err:lower()
    return err:find("forbidden") or err:find("blocked") or err:find("protected") or err:find("interdit") or err:find("bloqu")
end

-- appel en ecriture : pcall, et reperage d un blocage
local function write(name, ...)
    local fn = api("C_Traits", name)
    if type(fn) ~= "function" then return false end
    local ok, res = pcall(fn, ...)
    if not ok then
        if looksBlocked(res) then blockedNow = true end
        return false
    end
    return res and true or false
end

-- controles communs ; renvoie le message d erreur ou nil
local function precheck(dec)
    if combat() then return L.TAL_ERR_COMBAT end
    if not dec then return L.TAL_ERR_BAD end
    local cfg = activeConfig()
    if not cfg or cfg ~= dec.cfg then return L.TAL_ERR_NOTREE end
    local other = otherTraitWindowOpen()
    if other then return windowsMessage(other) end
    if hasStaged(cfg) then return L.TAL_ERR_STAGED end
    local canChange, canAdd, why = call(api("C_ClassTalents", "CanChangeTalents"))
    if canChange ~= true and canAdd ~= true then
        why = str(why)
        return L.TAL_ERR_CHANGE .. ((why and why ~= "") and (" " .. why) or "")
    end
    local refund, toBuy = compare(dec, cfg)
    if refund then
        local info = call(api("C_Traits", "GetTreeInfo"), cfg, dec.tree)
        if canChange ~= true or val(info, "cannotRefund") == true then return L.TAL_ERR_REFUND end
    elseif toBuy == 0 then
        return L.TAL_NOTHING
    end
    return nil
end
M.precheck = precheck

local function setGuide(dec)
    if not db then return end
    db.guide = db.guide or {}
    db.guide[ns.CharKey()] = dec and dec.str or nil
    M.guideCache = nil
end

local function readBefore(dec, cfg)
    local before = {}
    for _, t in ipairs(dec.list) do
        local info = nodeInfo(cfg, t.id)
        before[t.id] = info and ranksOf(info) or 0
    end
    return before
end

local function blocked(dec)
    staging = false
    if db then db.stageBlocked = true end
    setGuide(dec)
    return false, L.TAL_BLOCKED
end

local function stage(dec)
    local err = precheck(dec)
    if err then return false, err end
    if spellsOpen() then return false, L.TAL_ERR_SPELLS end
    local cfg, tree = dec.cfg, dec.tree
    local before = readBefore(dec, cfg)
    staging, blockedNow = true, false
    local lines = {}
    local refund = compare(dec, cfg)
    if refund then
        -- comme le bouton "Reinitialiser" de Blizzard : par monnaie
        local ids = currencyIDs(cfg, tree)
        local done = false
        for _, cur in ipairs(ids) do
            if write("ResetTreeByCurrency", cfg, tree, cur) then done = true end
        end
        if not done and #ids == 0 then done = write("ResetTree", cfg, tree) end
        if blockedNow then return blocked(dec) end
        -- le resultat compte, pas le seul retour : plus aucun point a retirer
        if compare(dec, cfg) then
            -- remise a zero refusee ou incomplete : on defait ce qui a pu
            -- etre mis en attente (rien ne l etait avant, cf. precheck)
            if hasStaged(cfg) then write("RollbackConfig", cfg) end
            staging = false
            if blockedNow then return blocked(dec) end
            return false, L.TAL_ERR_RESET
        end
        before = readBefore(dec, cfg)
        lines[#lines + 1] = L.TAL_RESET_DONE
    end
    -- du haut vers le bas de l arbre, en plusieurs passes (paliers, liens)
    local list = {}
    for _, t in ipairs(dec.list) do list[#list + 1] = t end
    table.sort(list, function(a, b)
        if a.y ~= b.y then return a.y < b.y end
        if a.x ~= b.x then return a.x < b.x end
        return a.id < b.id
    end)
    for _ = 1, 12 do
        local progress = false
        for _, t in ipairs(list) do
            if blockedNow then break end
            local info = nodeInfo(cfg, t.id)
            local cur = info and ranksOf(info) or 0
            if info and t.isChoice and t.entry and cur == 0 and activeEntryOf(info) ~= t.entry then
                if call(api("C_Traits", "CanPurchaseRank"), cfg, t.id, t.entry) == true then
                    write("SetSelection", cfg, t.id, t.entry)
                    info = nodeInfo(cfg, t.id)
                    local now = info and ranksOf(info) or 0
                    if now > cur or (info and activeEntryOf(info) == t.entry) then progress = true end
                    cur = now
                end
            end
            local guard = 0
            while info and cur < t.ranks and guard < 64 and not blockedNow do
                guard = guard + 1
                local entry = activeEntryOf(info) or t.entry or num(entriesOf(info)[1])
                if not entry or call(api("C_Traits", "CanPurchaseRank"), cfg, t.id, entry) ~= true then break end
                write("PurchaseRank", cfg, t.id)
                local after = nodeInfo(cfg, t.id)
                local now = after and ranksOf(after) or cur
                if now <= cur then break end
                info, cur, progress = after, now, true
            end
        end
        if not progress or blockedNow then break end
    end
    staging = false
    if blockedNow then return blocked(dec) end
    -- bilan
    local placed, missing, names = 0, 0, {}
    for _, t in ipairs(dec.list) do
        local info = nodeInfo(cfg, t.id)
        local cur = info and ranksOf(info) or 0
        placed = placed + math.max(0, math.min(cur, t.ranks) - (before[t.id] or 0))
        if cur < t.ranks then
            missing = missing + t.ranks - cur
            if #names < 4 then names[#names + 1] = spellNameOf(cfg, t.entry) or ("#" .. t.id) end
        end
    end
    lines[#lines + 1] = string.format(L.TAL_STAGED, placed)
    if missing > 0 then
        lines[#lines + 1] = string.format(L.TAL_PARTIAL, missing, table.concat(names, ", "))
        setGuide(dec)
    end
    return placed > 0 or refund, table.concat(lines, "\n")
end
M.stage = stage

local function rollback()
    if combat() then return L.TAL_ERR_COMBAT end
    if visible(talentsPage()) then return L.TAL_ROLLBACK_OPEN end
    if spellsOpen() then return L.TAL_ERR_SPELLS end
    local other = otherTraitWindowOpen()
    if other then return windowsMessage(other) end
    local cfg = activeConfig()
    if not cfg or not hasStaged(cfg) then return L.TAL_NONE_PENDING end
    staging = true
    write("RollbackConfig", cfg)
    staging = false
    return L.TAL_ROLLBACK_DONE
end
M.rollback = rollback

---------------------------------------------------------------------------
-- Guide
---------------------------------------------------------------------------

local guideMine = setmetatable({}, weak)   -- nos textes sur leurs boutons
local guideText = setmetatable({}, weak)   -- bouton de talent -> notre texte

-- couleur "disponible" de l habillage (l accent, sauf s il se confond avec
-- l or ou le rouge des etats)
local function selColor()
    local f = ns.TalentSelectableColor
    if type(f) == "function" then
        local ok, c = pcall(f)
        if ok and type(c) == "table" then return c end
    end
    return ns.COLORS.violet
end

local function guideData()
    if not db or db.guideOn == false then return nil end
    local s = db.guide and db.guide[ns.CharKey()]
    if not s then return nil end
    local cfg = activeConfig()
    local c = M.guideCache
    if c and c.str == s and c.cfg == cfg then return c.dec end
    local dec = analyse(s)
    M.guideCache = { str = s, cfg = cfg, dec = dec }
    return dec
end
M.guideData = guideData

local function clearGuide()
    setGuide(nil)
end
M.clearGuide = clearGuide

local function guideFont(b)
    local fs = guideText[b]
    if fs then return fs end
    local ok, made = pcall(b.CreateFontString, b, nil, "OVERLAY")
    if not ok or not made then return nil end
    fs = made
    pcall(ns.UI.HeadFont, fs, 12)
    fs:SetPoint("BOTTOMLEFT", b, "TOPLEFT", -2, -10)
    guideMine[fs] = true
    guideText[b] = fs
    return fs
end

local function updateGuide(tf, dec)
    local shown = dec ~= nil
    if shown then
        local cfgInfo = tbl(tf, "configurationInfo")
        shown = cfgInfo ~= nil and num(val(cfgInfo, "ID")) == dec.cfg and not inspecting()
    end
    local sel = selColor()
    for _, b in ipairs(childrenOf(tbl(tf, "ButtonsParent"))) do
        local info = tbl(b, "nodeInfo")
        local text
        if shown and info then
            local id = num(val(info, "ID"))
            local t = id and dec.targets[id]
            if t then
                local cur = ranksOf(info)
                if t.isChoice and cur > 0 and activeEntryOf(info) ~= t.entry then
                    text = "#" .. t.index
                elseif t.ranks > cur then
                    text = "+" .. (t.ranks - cur) .. (t.isChoice and (" #" .. t.index) or "")
                end
            end
        end
        local fs = guideText[b]
        if text then
            fs = fs or guideFont(b)
            if fs then
                fs:SetText(text)
                fs:SetTextColor(sel[1], sel[2], sel[3])
                fs:Show()
            end
        elseif fs then
            fs:Hide()
        end
    end
end

-- nos textes ne sont pas a effacer par l habillage
local prevOwned = ns.SkinOwned
function ns.SkinOwned(r)
    if type(r) == "table" and guideMine[r] then return true end
    if prevOwned then return prevOwned(r) end
    return false
end

---------------------------------------------------------------------------
-- Fenetre d export / import (CorpUI, strate DIALOG)
---------------------------------------------------------------------------

local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }

local function above(f, min)
    local ok, s = pcall(f.GetFrameStrata, f)
    local idx, low = 3, 1
    for i, n in ipairs(STRATA) do
        if ok and n == s then idx = i end
        if n == min then low = i end
    end
    return STRATA[math.max(low, math.min(#STRATA - 1, idx + 1))]
end

local dlg
local view = { mode = "export", group = 1 }

local function setStatus(text, r, g, b)
    if not dlg then return end
    dlg.status:SetText(text or "")
    local C = ns.COLORS
    dlg.status:SetTextColor(r or C.text[1], g or C.text[2], b or C.text[3])
end

local function statusError(text) setStatus(text, 1, 0.4, 0.4) end

local function tip(b, text)
    b:HookScript("OnEnter", function(self)
        local t = ns.Tooltip(self, "ANCHOR_TOP")
        local s = type(text) == "function" and text() or text
        if not s then return end
        t:AddLine(s, 1, 1, 1, true)
        t:Show()
    end)
    b:HookScript("OnLeave", ns.HideTooltip)
end

-- source affichee a l export : groupe de specialisation ou inspection
local function exportString()
    if view.inspect then
        local psf = _G.PlayerSpellsFrame
        local unit = psf and str(val(psf, "inspectUnit"))
        local s = unit and str(call(api("C_Traits", "GenerateInspectImportString"), unit))
        s = s or (psf and str(val(psf, "inspectString")))
        if s and s ~= "" then return s, L.TAL_INSPECT_SRC end
        return nil, L.TAL_ERR_INSPECT
    end
    local cfg = configFor(view.group)
    local tree = treeOf(cfg)
    if not (cfg and tree) then return nil, L.TAL_ERR_NOTREE end
    local s = generate(cfg, tree)
    if not s then return nil, L.TAL_ERR_NOTREE end
    local sum = configSummary(cfg, tree)
    local points = unspent(cfg, tree)
    if points and points > 0 then sum = sum .. "   |cff999999" .. string.format(L.TAL_UNSPENT, points) .. "|r" end
    return s, sum, hasStaged(cfg)
end

local refreshDialog

local function selectAll()
    if not dlg then return end
    dlg.edit:SetFocus()
    dlg.edit:HighlightText()
end

local function refreshImport(user)
    local dec, err = analyse(dlg.edit:GetText())
    dlg.dec = dec
    if dec then
        dlg.summary:SetText(dec.summary)
        setStatus(L.TAL_PASTE_HINT)
    elseif err then
        dlg.summary:SetText("")
        statusError(err)
    else
        dlg.summary:SetText("")
        setStatus(L.TAL_PASTE_HINT)
    end
    if not combat() then
        dlg.stageBtn:SetEnabled(dec ~= nil and not (db and db.stageBlocked))
    end
    dlg.guideBtn:SetEnabled(dec ~= nil)
end

refreshDialog = function()
    if not dlg then return end
    local C = ns.COLORS
    local export = view.mode == "export"
    dlg.title:SetText(export and L.TAL_EXPORT_TITLE or L.TAL_IMPORT_TITLE)
    -- choix de la specialisation (export, double specialisation)
    local n = numGroups()
    local act = activeGroup()
    for i, b in ipairs(dlg.specBtns) do
        local show = export and not view.inspect and n > 1 and i <= n
        b:SetShown(show)
        local sel = view.group == i
        b.cuiText:SetText(string.format(L.TAL_SPEC, i) .. (i == act and " *" or ""))
        b.cuiText:SetTextColor(sel and C.gold[1] or C.text[1], sel and C.gold[2] or C.text[2], sel and C.gold[3] or C.text[3])
    end
    if export then
        dlg.specLbl:SetText(view.inspect and L.TAL_INSPECT_SRC or (n > 1 and "" or string.format(L.TAL_SPEC, view.group)))
    else
        dlg.specLbl:SetText(string.format(L.TAL_ACTIVE, act))
    end
    dlg.hint:SetText(export and L.TAL_COPY_HINT or L.TAL_PASTE_HINT)
    dlg.stageBtn:SetShown(not export)
    dlg.guideBtn:SetShown(not export)
    dlg.openBtn:SetShown(not export)
    if export then
        local s, sum, pending = exportString()
        dlg.text = s or ""
        dlg.edit:SetText(dlg.text)
        dlg.summary:SetText(s and sum or "")
        if not s then statusError(sum) elseif pending then setStatus(L.TAL_WARN_PENDING, 1, 0.82, 0.25) else setStatus("") end
        selectAll()
    else
        refreshImport(false)
    end
end

-- la fenetre porte des boutons securises (elle devient protegee) : jamais
-- de Hide en combat, elle est fermee juste avant (PLAYER_REGEN_DISABLED)
local function hideDialog()
    if dlg and dlg:IsShown() then
        dlg.edit:ClearFocus()
        if not combat() then dlg:Hide() end
    end
end

-- bouton de Blizzard qui FERME la fenetre des sorts / talents, sinon nil.
-- Son clic bascule la fenetre seulement si l onglet qu il vise est deja
-- affiche (PlayerSpellsUtil.TogglePlayerSpellsFrame) : sur l onglet
-- Specialisation, aucun ne la ferme. Une alerte du grimoire en cours
-- (jumpToSpellID) ouvrirait le grimoire sur un sort au lieu de fermer.
local function usable(b)
    if type(b) ~= "table" or val(b, "jumpToSpellID") ~= nil then return nil end
    if b.IsEnabled then
        local ok, on = pcall(b.IsEnabled, b)
        if ok and on == false then return nil end
    end
    return b
end

local function closerButton()
    if not spellsOpen() then return nil end
    local psf = _G.PlayerSpellsFrame
    if visible(talentsPage()) then return usable(rawget(_G, "TalentMicroButton")) end
    if visible(tbl(psf, "SpellBookFrame")) then
        local b = usable(rawget(_G, "SpellbookMicroButton"))
        if b then return b end
        -- bouton unique (sans onglet vise) : il ferme la fenetre ouverte
        local p = rawget(_G, "PlayerSpellsMicroButton")
        if type(p) == "table" and val(p, "suggestedTab") == nil and val(p, "talentsOnly") == nil then return usable(p) end
    end
    return nil
end

local function runStage(self)
    local dec = self.cuiDec
    self.cuiDec = nil
    if self.cuiErr then
        statusError(self.cuiErr)
        self.cuiErr = nil
        return
    end
    if not dec then return end
    if spellsOpen() then statusError(L.TAL_ERR_SPELLS) return end
    local ok, msg = stage(dec)
    if ok then
        setStatus(msg, 0.55, 1, 0.55)
        ns.Say((msg:gsub("\n", " ")))
    else
        statusError(msg)
        if db and db.stageBlocked and not combat() then dlg.stageBtn:SetEnabled(false) end
    end
end

local function buildDialog()
    local C = ns.COLORS
    dlg = CreateFrame("Frame", "CorpUITalentsDialog", UIParent, "BackdropTemplate")
    dlg:SetSize(500, 300)
    dlg:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    dlg:SetFrameStrata("DIALOG")
    dlg:SetToplevel(true)
    dlg:SetClampedToScreen(true)
    dlg:EnableMouse(true)
    dlg:SetMovable(true)
    dlg:RegisterForDrag("LeftButton")
    dlg:SetScript("OnDragStart", function(self) if not combat() then self:StartMoving() end end)
    dlg:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    ns.UI.SetBackdrop(dlg, 0.97)
    ns.UI.Shadow(dlg, 4)
    dlg:Hide()

    local head = dlg:CreateTexture(nil, "ARTWORK")
    head:SetPoint("TOPLEFT", 1, -1)
    head:SetPoint("TOPRIGHT", -1, -1)
    head:SetHeight(26)
    ns.UI.Gradient(head, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.35, C.violet[1], C.violet[2], C.violet[3], 0)
    local line = dlg:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", head, "BOTTOMLEFT")
    line:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT")
    line:SetHeight(1)
    ns.UI.Gradient(line, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.8, C.gold[1], C.gold[2], C.gold[3], 0)
    dlg.title = dlg:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(dlg.title, 14)
    dlg.title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    dlg.title:SetPoint("TOPLEFT", 12, -7)
    local x = ns.UI.Button(dlg, "\195\151", 22, hideDialog)
    x:SetSize(22, 20)
    x:SetPoint("TOPRIGHT", -4, -4)

    -- ligne de specialisation
    dlg.specLbl = dlg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dlg.specLbl:SetPoint("TOPLEFT", 12, -38)
    dlg.specBtns = {}
    for i = 1, 2 do
        local b = ns.UI.Button(dlg, string.format(L.TAL_SPEC, i), 80, function()
            view.group = i
            refreshDialog()
        end)
        b:SetPoint("TOPLEFT", dlg, "TOPLEFT", 12 + (i - 1) * 86, -34)
        dlg.specBtns[i] = b
    end

    dlg.summary = dlg:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    dlg.summary:SetPoint("TOPLEFT", 12, -64)
    dlg.summary:SetPoint("TOPRIGHT", -12, -64)
    dlg.summary:SetHeight(18)
    dlg.summary:SetJustifyH("LEFT")
    dlg.summary:SetWordWrap(false)

    -- boite de texte (selectionnable ; non modifiable a l export)
    local box = CreateFrame("Frame", nil, dlg)
    box:SetPoint("TOPLEFT", 12, -86)
    box:SetPoint("TOPRIGHT", -12, -86)
    box:SetHeight(82)
    ns.UI.Skin(box, 0.7)
    local sf = CreateFrame("ScrollFrame", nil, box)
    sf:SetPoint("TOPLEFT", 6, -5)
    sf:SetPoint("BOTTOMRIGHT", -6, 5)
    local edit = CreateFrame("EditBox", nil, sf)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("GameFontHighlightSmall")
    edit:SetWidth(460)
    sf:SetScrollChild(edit)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, d)
        local max = math.max(0, edit:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(max, (self:GetVerticalScroll() or 0) - d * 20)))
    end)
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() edit:SetFocus() end)
    edit:SetScript("OnEscapePressed", function() hideDialog() end)
    edit:SetScript("OnEditFocusGained", function(self) if view.mode == "export" then self:HighlightText() end end)
    edit:SetScript("OnTextChanged", function(self, user)
        if view.mode == "export" then
            -- lecture seule : on remet la chaine et on la reselectionne
            if user and self:GetText() ~= (dlg.text or "") then
                self:SetText(dlg.text or "")
                self:HighlightText()
            end
        elseif user then
            refreshImport(true)
        end
    end)
    dlg.edit = edit

    dlg.hint = dlg:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    dlg.hint:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -4)
    dlg.hint:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -4)
    dlg.hint:SetJustifyH("LEFT")
    dlg.status = dlg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dlg.status:SetPoint("TOPLEFT", dlg.hint, "BOTTOMLEFT", 0, -6)
    dlg.status:SetPoint("TOPRIGHT", dlg.hint, "BOTTOMRIGHT", 0, -6)
    dlg.status:SetHeight(48)
    dlg.status:SetJustifyH("LEFT")
    dlg.status:SetJustifyV("TOP")

    -- Preparer : bouton securise. Si la fenetre des sorts / talents est
    -- ouverte, son clic passe d abord par le vrai bouton du jeu qui la
    -- ferme ; nos appels C_Traits partent ensuite (PostClick), fenetre fermee.
    local stageBtn = ns.UI.Button(dlg, L.TAL_STAGE, 110, nil, "SecureActionButtonTemplate")
    stageBtn:RegisterForClicks("AnyUp")
    stageBtn:SetAttribute("useOnKeyDown", false)
    stageBtn:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 12, 10)
    stageBtn:SetScript("PreClick", function(self)
        if combat() then return end
        self:SetAttribute("type", nil)
        self.cuiDec, self.cuiErr = nil, nil
        local dec = dlg.dec
        local err = precheck(dec)
        if err then
            self.cuiErr = err
            return
        end
        local closer = closerButton()
        if closer then
            self:SetAttribute("type", "click")
            self:SetAttribute("clickbutton", closer)
        elseif spellsOpen() then
            -- aucun bouton du jeu ne la fermerait (onglet Specialisation...)
            self.cuiErr = L.TAL_ERR_SPELLS
            return
        end
        self.cuiDec = dec
    end)
    stageBtn:SetScript("PostClick", function(self)
        if combat() then return end
        self:SetAttribute("type", nil)
        runStage(self)
    end)
    tip(stageBtn, function()
        if db and db.stageBlocked then return L.TAL_BLOCKED end
        return L.TAL_TIP_STAGE
    end)
    dlg.stageBtn = stageBtn

    local guideBtn = ns.UI.Button(dlg, L.TAL_GUIDE, 90, function()
        if not dlg.dec then return end
        db.guideOn = true
        setGuide(dlg.dec)
        setStatus(L.TAL_GUIDE_ON, 0.55, 1, 0.55)
    end)
    guideBtn:SetPoint("LEFT", stageBtn, "RIGHT", 4, 0)
    tip(guideBtn, L.TAL_TIP_GUIDE)
    dlg.guideBtn = guideBtn

    -- Ouvrir les talents : clic du vrai bouton du jeu (securise)
    local openBtn = ns.UI.Button(dlg, L.TAL_OPEN, 130, nil, "SecureActionButtonTemplate")
    openBtn:RegisterForClicks("AnyUp")
    openBtn:SetAttribute("useOnKeyDown", false)
    openBtn:SetPoint("LEFT", guideBtn, "RIGHT", 4, 0)
    openBtn:SetScript("PreClick", function(self)
        if combat() then return end
        local mb = _G.TalentMicroButton
        if type(mb) == "table" and not visible(talentsPage()) then
            self:SetAttribute("type", "click")
            self:SetAttribute("clickbutton", mb)
        else
            self:SetAttribute("type", nil)
        end
    end)
    openBtn:SetScript("PostClick", function(self)
        if combat() then return end
        self:SetAttribute("type", nil)
    end)
    dlg.openBtn = openBtn

    local close = ns.UI.Button(dlg, L.TAL_CLOSE, 80, hideDialog)
    close:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -12, 10)
end

local function openDialog(mode, opts)
    if combat() then ns.Say(L.TAL_ERR_COMBAT) return end
    if not dlg then buildDialog() end
    opts = opts or {}
    view.mode = mode
    view.inspect = opts.inspect or false
    view.group = opts.group or activeGroup()
    if mode == "import" then dlg.edit:SetText("") end
    -- au-dessus de la fenetre des talents si elle est ouverte
    local tf = talentsPage()
    dlg:SetFrameStrata(visible(tf) and above(tf, "DIALOG") or "DIALOG")
    dlg:Show()
    dlg:Raise()
    refreshDialog()
    if mode == "import" then dlg.edit:SetFocus() end
end
M.openDialog = openDialog
M.dialog = function() return dlg end

---------------------------------------------------------------------------
-- Barre Exporter / Importer sur la page des talents
---------------------------------------------------------------------------

local bar

local function displayedGroup(tf)
    local cfgInfo = tbl(tf, "configurationInfo")
    local cfg = cfgInfo and num(val(cfgInfo, "ID"))
    for g = 1, numGroups() do
        if cfg and configFor(g) == cfg then return g end
    end
    return activeGroup()
end

local function buildBar()
    bar = CreateFrame("Frame", "CorpUITalentsBar", UIParent)
    bar:SetSize(420, 24)
    bar:Hide()
    local exp = ns.UI.Button(bar, L.TAL_EXPORT, 86, function()
        local tf = talentsPage()
        openDialog("export", { inspect = inspecting(), group = displayedGroup(tf) })
    end)
    exp:SetPoint("LEFT", bar, "LEFT", 0, 0)
    local imp = ns.UI.Button(bar, L.TAL_IMPORT, 86, function()
        if inspecting() then ns.Say(L.TAL_ERR_INSPECT) return end
        openDialog("import")
    end)
    imp:SetPoint("LEFT", exp, "RIGHT", 4, 0)
    tip(imp, function() return inspecting() and L.TAL_ERR_INSPECT or L.TAL_TIP_IMPORT end)
    bar.imp = imp
    bar.guide = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.guide:SetPoint("LEFT", imp, "RIGHT", 10, 0)
    bar.clear = ns.UI.Button(bar, "\195\151", 20, function() clearGuide() end)
    bar.clear:SetSize(20, 20)
    bar.clear:SetPoint("LEFT", bar.guide, "RIGHT", 6, 0)
    tip(bar.clear, L.TAL_GUIDE_CLEAR)
end

local placedFor     -- page sur laquelle la barre est posee

local function updateBar(tf, dec)
    if not bar then buildBar() end
    if placedFor ~= tf then
        placedFor = tf
        bar:ClearAllPoints()
        bar:SetPoint("BOTTOMLEFT", tf, "BOTTOMLEFT", 48, 4)
    end
    local okS, es = pcall(tf.GetEffectiveScale, tf)
    local ui = UIParent:GetEffectiveScale()
    if okS and num(es) and ui and ui > 0 then bar:SetScale(es / ui) end
    bar:SetFrameStrata(above(tf, "HIGH"))
    bar:SetFrameLevel(50)
    local insp = inspecting()
    bar.imp:SetEnabled(not insp)
    -- le guide porte sur la config active : rien a dire en inspection ni
    -- sur l onglet de l autre specialisation (les reperes y sont masques)
    local shown = dec ~= nil and not insp
    if shown then
        local cfgInfo = tbl(tf, "configurationInfo")
        local cfg = cfgInfo and num(val(cfgInfo, "ID"))
        shown = cfg == nil or cfg == dec.cfg
    end
    if shown then
        local left = remaining(dec, dec.cfg)
        bar.guide:SetText(left > 0 and string.format(L.TAL_LEFT, left) or L.TAL_GUIDE_DONE)
        local sel = selColor()
        if left > 0 then bar.guide:SetTextColor(sel[1], sel[2], sel[3])
        else bar.guide:SetTextColor(0.55, 1, 0.55) end
        bar.guide:Show()
        bar.clear:Show()
    else
        bar.guide:Hide()
        bar.clear:Hide()
    end
    bar:Show()
end

---------------------------------------------------------------------------
-- Panneau /corp talents
---------------------------------------------------------------------------

local panel

local function refreshPanel()
    if not panel then return end
    local cfg = activeConfig()
    local tree = treeOf(cfg)
    local lines = {}
    if cfg and tree then
        lines[#lines + 1] = string.format(L.TAL_ACTIVE, activeGroup())
        lines[#lines + 1] = string.format(L.TAL_BUILD, configSummary(cfg, tree))
        local points = unspent(cfg, tree)
        if points then lines[#lines + 1] = string.format(L.TAL_UNSPENT, points) end
        if hasStaged(cfg) then lines[#lines + 1] = "|cffffd140" .. L.TAL_PENDING .. "|r" end
    else
        lines[#lines + 1] = L.TAL_ERR_NOTREE
    end
    local dec = guideData()
    if dec and cfg then
        local left = remaining(dec, cfg)
        lines[#lines + 1] = left > 0 and string.format(L.TAL_LEFT, left) or L.TAL_GUIDE_DONE
    end
    panel.info:SetText(table.concat(lines, "\n"))
    if panel.form then panel.form:Refresh() end
end

local function buildPanel()
    panel = ns.UI.Window("CorpUITalentsPanel", ns.TITLE .. " - " .. L.MOD_TALENTS, nil, 440, 330)
    local form = ns.UI.Form(panel, -34)
    panel.form = form
    panel.info = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.info:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, form.y)
    panel.info:SetWidth(424)
    panel.info:SetJustifyH("LEFT")
    panel.info:SetSpacing(3)
    form:Gap(78)
    local exp = ns.UI.Button(panel, L.TAL_EXPORT, 100, function() openDialog("export") end)
    exp:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, form.y)
    local imp = ns.UI.Button(panel, L.TAL_IMPORT, 100, function() openDialog("import") end)
    imp:SetPoint("LEFT", exp, "RIGHT", 4, 0)
    -- deuxieme ligne : libelles longs dans certaines langues (deDE, ruRU)
    form:Gap(26)
    local rb = ns.UI.Button(panel, L.TAL_ROLLBACK, 100, function()
        ns.Say(rollback())
        refreshPanel()
    end)
    rb:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, form.y)
    local cg = ns.UI.Button(panel, L.TAL_GUIDE_CLEAR, 100, function()
        clearGuide()
        ns.Say(L.TAL_GUIDE_CLEARED)
        refreshPanel()
    end)
    cg:SetPoint("LEFT", rb, "RIGHT", 4, 0)
    panel.buttons = { exp, imp, rb, cg }
    form:Gap(32)
    form:Header(L.TAL_OPTIONS)
    form:Check(L.TAL_OPT_BAR, function() return db.toolbar ~= false end, function(v) db.toolbar = v end)
    form:Check(L.TAL_OPT_GUIDE, function() return db.guideOn ~= false end, function(v) db.guideOn = v end)
    form:Check(L.TAL_OPT_STAGE, function() return not db.stageBlocked end, function(v) db.stageBlocked = not v end)
    form:Gap(6)
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, form.y)
    hint:SetWidth(424)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.TAL_HINT)
    panel:SetHeight(math.floor(80 - form.y))
    panel:HookScript("OnShow", refreshPanel)
end

local function toggle()
    if not panel then buildPanel() end
    ns.ShowPanel(panel)
    refreshPanel()
end

---------------------------------------------------------------------------
-- Diagnostic (/corp talents diag) : valeurs brutes, en lecture seule
---------------------------------------------------------------------------

local function diag()
    local cfg = activeConfig()
    local tree = treeOf(cfg)
    ns.Say(L.TAL_DIAG)
    local function line(k, v) ns.Chat("  " .. k .. " = " .. tostring(v)) end
    line("specID", currentSpecID())
    line("version", serialVersion())
    line("groups", numGroups() .. " (active " .. activeGroup() .. ")")
    line("activeConfigID", num(call(api("C_ClassTalents", "GetActiveConfigID"))))
    for g = 1, numGroups() do line("combatConfig" .. g, configFor(g)) end
    line("treeID", tree)
    local other = otherTraitWindowOpen()
    line("traitWindowOpen", other and (titleOf(other) or "?") or false)
    if cfg and tree then
        local info = call(api("C_Traits", "GetTreeInfo"), cfg, tree)
        line("cannotRefund", val(info, "cannotRefund"))
        line("nodes", #(treeNodes(tree) or {}))
        line("staged", hasStaged(cfg))
        local canChange, canAdd = call(api("C_ClassTalents", "CanChangeTalents"))
        line("canChange/canAdd", tostring(canChange) .. "/" .. tostring(canAdd))
        local game = str(call(api("C_Traits", "GenerateImportString"), cfg))
        local ok, mine = pcall(encode, cfg, tree, currentSpecID())
        line("game", game)
        line("corpui", ok and mine or "?")
        line("same", game ~= nil and ok and game == mine)
    end
    line("stageBlocked", db and db.stageBlocked or false)
end
M.diag = diag

---------------------------------------------------------------------------
-- Evenements, releve
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        root.talents = root.talents or {}
        db = root.talents
        if db.toolbar == nil then db.toolbar = true end
        if db.guideOn == nil then db.guideOn = true end
        db.guide = db.guide or {}
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- la fenetre porte des boutons securises : on la ferme avant le combat
        hideDialog()
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        local who, what = str(a1), str(a2) or ""
        if who == ADDON and (staging or what:find("Trait") or what:find("Purchase") or what:find("Selection")
                or what:find("Reset") or what:find("Rollback")) then
            blockedNow = true
            if db then db.stageBlocked = true end
        end
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_DISABLED", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
    pcall(ev.RegisterEvent, ev, e)
end

-- releve sur NOTRE cadre (aucun crochet) : barre et guide suivent la page
local acc = 0
ev:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.3 then return end
    acc = 0
    if not db then return end
    local tf = talentsPage()
    local shown = visible(tf)
    if (not shown or db.toolbar == false) and bar and bar:IsShown() then bar:Hide() end
    if not shown or combat() then return end
    local dec = guideData()
    if dec or next(guideText) then
        local ok, err = pcall(updateGuide, tf, dec)
        if not ok then M.lastError = tostring(err) end
    end
    if db.toolbar ~= false then
        local ok, err = pcall(updateBar, tf, dec)
        if not ok then M.lastError = tostring(err) end
    end
end)

---------------------------------------------------------------------------

ns.RegisterModule({
    command = "talents",
    panelName = "CorpUITalentsPanel",
    icon = ns.MEDIA .. "menu_talents",
    title = function() return L.MOD_TALENTS end,
    desc = function() return L.TAL_DESC end,
    Slash = function(arg)
        arg = strlower(strtrim(arg or ""))
        if arg == "export" then
            openDialog("export")
        elseif arg == "import" then
            openDialog("import")
        elseif arg == "diag" then
            diag()
        elseif arg == "guide off" or arg == "guide" then
            clearGuide()
            ns.Say(L.TAL_GUIDE_CLEARED)
        elseif arg == "rollback" then
            ns.Say(rollback())
        else
            toggle()
        end
    end,
    Open = toggle,
})
