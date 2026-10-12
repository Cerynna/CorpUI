--[[--------------------------------------------------------------------------
    CorpUI - module SpellsAhead
    Affiche les sorts a venir et le niveau auquel on les apprend.

    Regles de construction (retenues du fiasco !FixCharStats) :
      - aucun hook sur une fonction de Blizzard
      - aucune ecriture sur une globale existante
      - aucun ajout dans UISpecialFrames (le handler ESC est du code securise)
      - notre propre fenetre, notre propre code, lecture seule

    Affichage, au style CorpUI (recettes de Habillage/Grimoire.lua) :
      - un onglet a nous a droite des onglets de categorie du grimoire,
        et une page a nous posee sur leur zone de page : panneaux sombres,
        en-tete par niveau, cartes de sorts, pagination plate ;
      - le panneau "Sorts a venir" de la fenetre CorpUI (/sa).

    Trois sources de donnees, detectees a l execution :
      1. livre de sorts moderne  : C_SpellBook + Enum.SpellBookItemType.FutureSpell
      2. livre de sorts classic  : GetSpellBookItemInfo(i,"spell") == "FUTURESPELL"
      3. entraineur de classe    : scrute a l ouverture, mis en cache

    Commandes : /sa
----------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...   -- module de CorpUI depuis le 04/10/2026

local PREFIX = "|cff66ccffSpellsAhead|r: "
local ROWS   = 16
local ROW_H  = 20
local WIDTH  = 340

-- Version du cache. A incrementer quand la forme des entrees change : les
-- anciennes sont alors migrees ou jetees au lieu d etre melangees.
local CACHE_VERSION = 3

local entries      = {}   -- resultat fusionne et trie
local failedEvents = {}   -- evenements refuses par ce client
local scrollOffset = 0
local win                  -- fenetre principale
local rows   = {}

--------------------------------------------------------------------------
-- Utilitaires
--------------------------------------------------------------------------

local function chat(msg)
    local frame = DEFAULT_CHAT_FRAME or ChatFrame1
    if frame then frame:AddMessage(msg) end
end

local function say(msg)
    chat(PREFIX .. msg)
end

local function classKey()
    local _, fileName = UnitClass("player")
    return fileName or "UNKNOWN"
end

local function playerLevel()
    return UnitLevel("player") or 1
end

-- Appel protege : renvoie nil si la fonction n existe pas ou explose
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local res = { pcall(fn, ...) }
    if not res[1] then return nil end
    -- Une fonction qui ne renvoie RIEN doit quand meme nous rendre un nil,
    -- sinon tostring(call(...)) se retrouve sans argument du tout.
    return unpack(res, 2, math.max(#res, 2))
end

-- Les services d entraineur ne donnent pas de spellID. On le retrouve par le
-- nom (sans le suffixe de rang) pour obtenir un vrai tooltip de sort.
local idCache = {}

local function resolveSpellID(name)
    if type(name) ~= "string" or name == "" then return nil end
    if idCache[name] ~= nil then
        return idCache[name] or nil
    end

    local clean = (name:gsub("%s*%(.-%)%s*$", ""))
    local found

    local cs = _G.C_Spell
    if type(cs) == "table" and type(cs.GetSpellInfo) == "function" then
        local info = call(cs.GetSpellInfo, clean)
        if type(info) == "table" then
            found = info.spellID
        end
    end

    if not found and type(_G.GetSpellInfo) == "function" then
        -- signature classic : le 7e retour est le spellID
        local _, _, _, _, _, _, sid = call(_G.GetSpellInfo, clean)
        if type(sid) == "number" then found = sid end
    end

    idCache[name] = found or false
    return found
end

--------------------------------------------------------------------------
-- Detection des API disponibles
--------------------------------------------------------------------------

local function probe()
    local cs = _G.C_SpellBook
    local en = _G.Enum
    return {
        ["C_SpellBook"]                         = type(cs) == "table",
        ["C_SpellBook.GetNumSpellBookSkillLines"] = type(cs) == "table" and type(cs.GetNumSpellBookSkillLines) == "function",
        ["C_SpellBook.GetSpellBookSkillLineInfo"] = type(cs) == "table" and type(cs.GetSpellBookSkillLineInfo) == "function",
        ["C_SpellBook.GetSpellBookItemInfo"]      = type(cs) == "table" and type(cs.GetSpellBookItemInfo) == "function",
        ["C_SpellBook.GetSpellBookItemLevelLearned"] = type(cs) == "table" and type(cs.GetSpellBookItemLevelLearned) == "function",
        ["Enum.SpellBookItemType.FutureSpell"]  = type(en) == "table" and type(en.SpellBookItemType) == "table"
                                                   and en.SpellBookItemType.FutureSpell ~= nil,
        ["Enum.SpellBookSpellBank.Player"]      = type(en) == "table" and type(en.SpellBookSpellBank) == "table"
                                                   and en.SpellBookSpellBank.Player ~= nil,
        ["GetNumSpellTabs"]                     = type(_G.GetNumSpellTabs) == "function",
        ["GetSpellTabInfo"]                     = type(_G.GetSpellTabInfo) == "function",
        ["GetSpellBookItemInfo"]                = type(_G.GetSpellBookItemInfo) == "function",
        ["GetSpellAvailableLevel"]              = type(_G.GetSpellAvailableLevel) == "function",
        ["GetSpellBookItemName"]                = type(_G.GetSpellBookItemName) == "function",
        ["GetNumTrainerServices"]               = type(_G.GetNumTrainerServices) == "function",
        ["GetTrainerServiceInfo"]               = type(_G.GetTrainerServiceInfo) == "function",
        ["GetTrainerServiceLevelReq"]           = type(_G.GetTrainerServiceLevelReq) == "function",
    }
end

--------------------------------------------------------------------------
-- Collecte
--------------------------------------------------------------------------

local function addEntry(list, level, name, spellID, icon, source)
    if not name or name == "" then return end
    level = tonumber(level)
    if not level or level <= 0 then level = 0 end

    -- Deux rangs du meme sort portent le meme nom : on ne dedoublonne sur le
    -- nom que faute de spellID, sinon on perdrait les rangs intermediaires.
    for _, e in ipairs(list) do
        if spellID and e.spellID then
            if e.spellID == spellID then return nil end
        elseif e.name == name and e.level == level then
            return nil
        end
    end

    local entry = {
        level   = level,
        name    = name,
        spellID = spellID,
        icon    = icon,
        source  = source,
    }
    list[#list + 1] = entry
    return entry
end

-- Source 1 : livre de sorts moderne
local function collectModern(list)
    local cs = _G.C_SpellBook
    local en = _G.Enum
    if type(cs) ~= "table" or type(en) ~= "table" then return 0 end
    if type(cs.GetNumSpellBookSkillLines) ~= "function" then return 0 end
    if type(cs.GetSpellBookItemInfo) ~= "function" then return 0 end

    local bank = en.SpellBookSpellBank and en.SpellBookSpellBank.Player
    local futureType = en.SpellBookItemType and en.SpellBookItemType.FutureSpell
    if bank == nil or futureType == nil then return 0 end

    -- Balayage direct des index. Les skill lines ne couvrent que 17 entrees
    -- sur 26 sur ce client : metiers et secourisme sont au dela.
    -- Note : ce client ne place AUCUN FutureSpell dans le livre, donc cette
    -- source rend 0. On la garde au cas ou un patch la remplirait.
    local found = 0
    for i = 1, 500 do
        local item = call(cs.GetSpellBookItemInfo, i, bank)
        if type(item) == "table" and item.itemType == futureType then
            local lvl = item.minLevel or item.level
                    or call(cs.GetSpellBookItemLevelLearned, i, bank)
            addEntry(list, lvl, item.name, item.spellID, item.iconID, "livre")
            found = found + 1
        end
    end
    return found
end

-- Sorts deja connus + le niveau auquel ils ont ete appris.
-- GetSpellBookItemLevelLearned fonctionne sur ce client, contrairement au
-- reste. Sert a la vue /sa known.
local function collectKnown()
    local cs = _G.C_SpellBook
    local en = _G.Enum
    if type(cs) ~= "table" or type(cs.GetSpellBookItemInfo) ~= "function" then
        return {}
    end
    local bank = en and en.SpellBookSpellBank and en.SpellBookSpellBank.Player

    local out = {}
    for i = 1, 500 do
        local item = call(cs.GetSpellBookItemInfo, i, bank)
        if type(item) == "table" and item.name then
            local lvl = call(cs.GetSpellBookItemLevelLearned, i, bank) or 0
            out[#out + 1] = {
                level   = lvl,
                name    = item.name,
                spellID = item.spellID,
                passive = item.isPassive,
            }
        end
    end
    sort(out, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        return (a.name or "") < (b.name or "")
    end)
    return out
end

-- Source 2 : livre de sorts classic
local function collectClassic(list)
    if type(_G.GetNumSpellTabs) ~= "function" then return 0 end
    if type(_G.GetSpellBookItemInfo) ~= "function" then return 0 end

    local found   = 0
    local numTabs = call(_G.GetNumSpellTabs) or 0

    for tab = 1, numTabs do
        local _, _, offset, numSpells = call(_G.GetSpellTabInfo, tab)
        offset    = offset or 0
        numSpells = numSpells or 0

        for i = offset + 1, offset + numSpells do
            local itemType, id = call(_G.GetSpellBookItemInfo, i, "spell")
            if itemType == "FUTURESPELL" then
                local name = call(_G.GetSpellBookItemName, i, "spell")
                local lvl  = call(_G.GetSpellAvailableLevel, i, "spell")
                local icon = call(_G.GetSpellBookItemTexture, i, "spell")
                addEntry(list, lvl, name, id, icon, "livre")
                found = found + 1
            end
        end
    end
    return found
end

-- Source 3 : cache de l entraineur (rempli par scrapeTrainer)
local function collectTrainerCache(list)
    local db = SpellsAheadDB
    if not db or not db.trainer then return 0 end
    local cache = db.trainer[classKey()]
    if type(cache) ~= "table" then return 0 end

    local showTrade = db.showTrade
    local found = 0
    for _, e in ipairs(cache) do
        if not e.trade or showTrade then
            local entry = addEntry(list, e.level, e.name,
                e.spellID or resolveSpellID(e.name), e.icon, "entraineur")
            if entry then
                entry.desc = e.desc
                entry.rank = e.rank
            end
            found = found + 1
        end
    end
    return found
end

local function rebuild()
    wipe(entries)
    local list = {}

    local nModern  = collectModern(list)
    local nClassic = (nModern == 0) and collectClassic(list) or 0
    local nTrainer = collectTrainerCache(list)

    local lvl = playerLevel()
    for _, e in ipairs(list) do
        if e.level == 0 or e.level > lvl then
            entries[#entries + 1] = e
        end
    end

    -- niveau inconnu (0) en fin de liste
    sort(entries, function(a, b)
        local la = a.level > 0 and a.level or math.huge
        local lb = b.level > 0 and b.level or math.huge
        if la ~= lb then return la < lb end
        return (a.name or "") < (b.name or "")
    end)

    scrollOffset = 0
    return nModern, nClassic, nTrainer
end

--------------------------------------------------------------------------
-- Scrutation de l entraineur
--------------------------------------------------------------------------

local scraping = false

-- Tooltip invisible : seul moyen d obtenir le VRAI spellID d un sort pas
-- encore appris. GetSpellInfo(nom) ne resout que les sorts deja connus, donc
-- on passe par SetTrainerService puis GetSpell.
local scanTip

local function getScanTip()
    if scanTip ~= nil then
        return scanTip or nil
    end
    local ok, t = pcall(CreateFrame, "GameTooltip", "SpellsAheadScanTip",
                        UIParent, "GameTooltipTemplate")
    scanTip = (ok and t) or false
    return scanTip or nil
end

-- Pourquoi la derniere lecture a echoue. Lu par /sa api et par le dump.
local scanDiag = { reason = "jamais execute" }

-- Renvoie spellID, description pour le service d entraineur numero i
local function readService(i)
    local tip = getScanTip()
    if not tip then
        scanDiag.reason = "creation du tooltip de scan impossible"
        return nil, nil
    end
    if type(tip.SetTrainerService) ~= "function" then
        scanDiag.reason = "tooltip:SetTrainerService absent sur ce client"
        return nil, nil
    end

    tip:SetOwner(UIParent, "ANCHOR_NONE")
    if tip.ClearLines then tip:ClearLines() end

    local ok, err = pcall(tip.SetTrainerService, tip, i)
    if not ok then
        scanDiag.reason = "SetTrainerService a leve : " .. tostring(err)
        tip:Hide()
        return nil, nil
    end

    local sid
    if type(tip.GetSpell) ~= "function" then
        scanDiag.reason = "tooltip:GetSpell absent"
    else
        local _, id = call(tip.GetSpell, tip)
        if type(id) == "number" then
            sid = id
        else
            scanDiag.reason = "GetSpell n a pas rendu d id"
        end
    end

    -- Meme sans id, le texte du tooltip est celui du jeu : on le garde, il
    -- vaut mille fois mieux que du texte fabrique par moi.
    local lines = {}
    local n = (type(tip.NumLines) == "function" and call(tip.NumLines, tip)) or 0
    for li = 2, n do
        local fs  = _G["SpellsAheadScanTipTextLeft" .. li]
        local txt = fs and fs.GetText and fs:GetText()
        if type(txt) == "string" and txt ~= "" then
            lines[#lines + 1] = txt
        end
    end

    scanDiag.lines = n
    if sid then scanDiag.reason = "ok" end
    if n == 0 and ok then
        scanDiag.reason = "SetTrainerService a rendu un tooltip vide"
    end

    tip:Hide()
    return sid, (#lines > 0) and table.concat(lines, "\n") or nil
end

local SERVICE_CATEGORIES = {
    ["available"] = true, ["unavailable"] = true,
    ["used"] = true, ["header"] = true,
}

local function isServiceCategory(v)
    return type(v) == "string" and SERVICE_CATEGORIES[v] == true
end

-- Migration du cache. v2 : noms pollues par le type de service. v3 : recettes
-- de metier ramassees chez un entraineur de metier -- elles n ont pas de
-- niveau requis, c est ce qui permet de les reconnaitre apres coup.
local function migrateCache()
    local db = SpellsAheadDB
    if not db or type(db.trainer) ~= "table" then return end
    if db.cacheVersion == CACHE_VERSION then return end

    local dropped = 0
    for class, list in pairs(db.trainer) do
        local kept, seen = {}, {}
        for _, e in ipairs(list) do
            local clean = tostring(e.name or "?")
            for cat in pairs(SERVICE_CATEGORIES) do
                clean = clean:gsub("%s*%(" .. cat .. "%)$", "")
            end

            local key = e.spellID or (clean .. "#" .. tostring(e.level))
            if (tonumber(e.level) or 0) <= 0 then
                dropped = dropped + 1
            elseif not seen[key] then
                seen[key] = true
                e.name = clean
                kept[#kept + 1] = e
            end
        end
        db.trainer[class] = kept
    end

    db.cacheVersion = CACHE_VERSION
    db.cacheClean   = nil
    if dropped > 0 then
        db.migrationNote = format("%d entree(s) sans niveau retirees (metiers)", dropped)
    end
end

-- Affecte plus bas, une fois l interface construite : permet a la lecture
-- differee de rafraichir ce qui est affiche.
local onDataChanged

local savedFilters

local function widenFilters()
    if type(_G.GetTrainerServiceTypeFilter) ~= "function"
    or type(_G.SetTrainerServiceTypeFilter) ~= "function" then
        return false
    end
    savedFilters = {}
    for _, filter in ipairs({ "available", "unavailable", "used" }) do
        savedFilters[filter] = call(_G.GetTrainerServiceTypeFilter, filter)
        pcall(_G.SetTrainerServiceTypeFilter, filter, 1)
    end
    return true
end

local function restoreFilters()
    if not savedFilters then return end
    for filter, value in pairs(savedFilters) do
        pcall(_G.SetTrainerServiceTypeFilter, filter, value and 1 or 0)
    end
    savedFilters = nil
end

local function spellRank(spellID)
    if not spellID then return nil end
    local cs = _G.C_Spell
    if type(cs) == "table" and type(cs.GetSpellSubtext) == "function" then
        local s = call(cs.GetSpellSubtext, spellID)
        if type(s) == "string" and s ~= "" then return s end
    end
    if type(_G.GetSpellSubtext) == "function" then
        local s = call(_G.GetSpellSubtext, spellID)
        if type(s) == "string" and s ~= "" then return s end
    end
    return nil
end

-- Lit la liste telle qu elle est affichee, sans toucher aux filtres.
local function readAllServices()
    local db  = SpellsAheadDB
    db.trainer = db.trainer or {}
    local key = classKey()

    -- Fusion avec ce qui est deja connu : un entraineur ne montre pas
    -- forcement tout, et on visite plusieurs entraineurs au fil des niveaux.
    -- La cle est le spellID, unique PAR RANG : deduire par le nom ecrasait
    -- tous les rangs d un meme sort et ne gardait que le dernier lu.
    -- Un entraineur de metier expose ses recettes par la meme API. On les
    -- marque pour pouvoir les ecarter de la liste des sorts de classe.
    local isTrade = call(_G.IsTradeskillTrainer) and true or nil

    local merged = {}
    if db.cacheVersion == CACHE_VERSION then
        for _, e in ipairs(db.trainer[key] or {}) do
            merged[e.spellID or (e.name .. "#" .. tostring(e.level))] = e
        end
    end

    local seen = 0
    for i = 1, (call(_G.GetNumTrainerServices) or 0) do
        -- Attention : sur ce client la 2e valeur est le TYPE de service
        -- ("available" / "unavailable" / "used"), pas le rang. On identifie
        -- donc les valeurs par leur contenu et non par leur position.
        local a, b, c = call(_G.GetTrainerServiceInfo, i)
        local name, rank, category = a, nil, nil

        local function classify(v)
            if isServiceCategory(v) then
                category = category or v
            elseif type(v) == "string" and v ~= "" and not rank then
                rank = v
            end
        end
        classify(b)
        classify(c)

        if name and category ~= "header" then
            local level = call(_G.GetTrainerServiceLevelReq, i) or 0
            local icon  = call(_G.GetTrainerServiceIcon, i)
            local label = name
            if rank then
                label = name .. " (" .. rank .. ")"
            end

            -- C est ici, et seulement ici, qu on peut capturer le spellID.
            local sid, desc = readService(i)

            local spellID = sid or resolveSpellID(name)
            local mkey    = spellID or (label .. "#" .. tostring(level))

            merged[mkey] = {
                level   = level,
                name    = label,
                icon    = icon,
                desc    = desc,
                spellID = spellID,
                rank    = rank or spellRank(spellID),
                trade   = isTrade,
            }
            seen = seen + 1
        end
    end

    if seen > 0 then
        local flat = {}
        for _, e in pairs(merged) do
            flat[#flat + 1] = e
        end
        db.trainer[key]  = flat
        db.trainerStamp  = date("%d/%m %H:%M")
        db.trainerCount  = #flat
        db.cacheVersion  = CACHE_VERSION
    end
    return seen
end

-- Elargit les filtres, PUIS lit -- mais pas dans la foulee. Le client ne
-- reconstruit pas la liste immediatement apres un changement de filtre :
-- GetNumTrainerServices repond encore l ancien compte. C est ce qui faisait
-- qu on relevait 47 services sur 173, et sans aucun spellID.
local function scrapeTrainer()
    if scraping then return 0 end
    -- rien en combat (filtres de l entraineur, tooltip de scan) : la liste
    -- sera relue a la prochaine ouverture
    if InCombatLockdown() then return 0 end
    if type(_G.GetNumTrainerServices) ~= "function" then return 0 end

    scraping = true
    local widened = widenFilters()

    local function finish()
        local n = readAllServices()
        restoreFilters()
        scraping = false
        if onDataChanged then onDataChanged() end
        return n
    end

    if widened and _G.C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0.25, finish)
        return nil   -- lecture differee
    end

    return finish()
end

--------------------------------------------------------------------------
-- Style CorpUI : memes recettes que Habillage/Grimoire.lua
--   - onglet : tuile carree, icone recadree, lisere ; trait d or sous
--     l onglet actif, icone attenuee sinon, lisere violet au survol ;
--   - page : panneau sombre par page (memes marges que le grimoire),
--     en-tetes en degrade d accent + filet d or + titre or de 17,
--     cartes sombres (icone carree et lisere, nom couleur texte, rang en
--     or), survol en degrade et lisere d or ; pagination plate.
-- Tout est construit sur NOS cadres. Chez Blizzard on ne fait que lire
-- (champs, taille, visibilite, survol) et s ancrer : aucun champ ecrit,
-- aucune methode qui ecrit, aucun crochet.
--------------------------------------------------------------------------

local issecret = issecretvalue or function() return false end
local weak = { __mode = "k" }
local mine = setmetatable({}, weak)   -- nos textures et textes
local ours = setmetatable({}, weak)   -- nos cadres

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local BOOK_ICON = "Interface\\Icons\\INV_Misc_Book_09"

-- texte secondaire : gris violace (celui de "Disponible au niveau X")
local MUTED = { 0.65, 0.62, 0.72 }

-- grille du grimoire (Blizzard_SpellBookFrame.xml) : vues de 680 x 590,
-- 3 colonnes, marges 15 / 10, cases de 60, en-tetes de 51, intervalle de
-- 20 entre deux groupes
local GRID = { cols = 3, xpad = 15, ypad = 10, itemH = 60, headH = 51, spacer = 20, viewW = 680, viewH = 590 }
-- bas de vue laisse libre : la pagination y est posee (comme celle de
-- Blizzard, a 40 px du bas de la zone de page)
local FOOT_H = 52
-- marges des panneaux de page autour des vues (celles de Grimoire.lua)
local PAGE_PAD = { left = 26, top = 30, right = 20, bottom = 6 }
-- vues de Blizzard dans la zone de page (repli si elles sont illisibles)
local VIEW_POS = { { "TOPLEFT", 85, -45 }, { "TOPRIGHT", -50, -45 } }

local function field(f, key)
    if type(f) ~= "table" then return nil end
    local ok, c = pcall(function() return f[key] end)
    if ok and type(c) == "table" then return c end
end

-- lecture d un champ simple (nombre, booleen, chaine), jamais secret
local function value(f, key)
    if type(f) ~= "table" then return nil end
    local ok, v = pcall(function() return f[key] end)
    if not ok or v == nil or issecret(v) then return nil end
    local t = type(v)
    if t == "number" or t == "boolean" or t == "string" then return v end
end

local function num(v)
    if v == nil or issecret(v) or type(v) ~= "number" then return nil end
    return v
end

-- appel d une methode de lecture (taille, visibilite...), protege
local function callNum(f, method)
    if type(f) ~= "table" then return nil end
    local ok, v = pcall(function() return f[method](f) end)
    if ok then return num(v) end
end

local function callTrue(f, method)
    if type(f) ~= "table" then return false end
    local ok, v = pcall(function() return f[method](f) end)
    return ok and not issecret(v) and v == true
end

local function isOver(f) return callTrue(f, "IsMouseOver") end

local function tex(host, layer, sub)
    local t = host:CreateTexture(nil, layer, nil, sub)
    mine[t] = true
    ns.NoSnap(t)   -- traits fins toujours dessines (Core.lua)
    return t
end

local function frame(kind, parent)
    local f = CreateFrame(kind, nil, parent)
    ours[f] = true
    return f
end

-- quatre filets de 1 px autour de "anchor" (sur "host"), "out" px en dehors
local function ring(host, anchor, layer, sub, out)
    local list = {}
    local function line()
        local x = tex(host, layer, sub)
        list[#list + 1] = x
        return x
    end
    local top = line()
    top:SetPoint("TOPLEFT", anchor, "TOPLEFT", -out, out)
    top:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", out, out)
    top:SetHeight(1)
    local bottom = line()
    bottom:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", -out, -out)
    bottom:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", out, -out)
    bottom:SetHeight(1)
    local left = line()
    left:SetPoint("TOPLEFT", anchor, "TOPLEFT", -out, out)
    left:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", -out, -out)
    left:SetWidth(1)
    local right = line()
    right:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", out, out)
    right:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", out, -out)
    right:SetWidth(1)
    return list
end

local function paint(list, r, g, b, a)
    for _, x in ipairs(list) do x:SetColorTexture(r, g, b, a or 1) end
end

local function paintC(list, c, a) paint(list, c[1], c[2], c[3], a) end

local function showAll(list, on)
    for _, x in ipairs(list) do x:SetShown(on) end
end

local function setColor(fs, c, k)
    k = k or 1
    fs:SetTextColor(c[1] * k, c[2] * k, c[3] * k)
end

-- police des titres (celle des en-tetes du grimoire)
local function headText(host, size)
    local fs = host:CreateFontString(nil, "OVERLAY")
    mine[fs] = true
    pcall(ns.UI.HeadFont, fs, size)
    return fs
end

-- police du jeu par le nom de son objet (celles des cases du grimoire)
local function sysText(host, fontName, size)
    local fs = host:CreateFontString(nil, "OVERLAY")
    mine[fs] = true
    local obj = rawget(_G, fontName)
    if not (type(obj) == "table" and pcall(fs.SetFontObject, fs, obj)) then
        pcall(fs.SetFont, fs, "Fonts\\FRIZQT__.TTF", size or 12, "")
    end
    return fs
end

local function textHeight(fs, fallback)
    local ok, h = pcall(fs.GetStringHeight, fs)
    h = ok and num(h) or nil
    if h and h > 0 then return h end
    return fallback
end

local function gradient(t, orientation, c, a1, a2)
    ns.UI.Gradient(t, orientation, c[1], c[2], c[3], a1, c[1], c[2], c[3], a2)
end

-- nom sans le rang ajoute a la lecture de l entraineur ("Nom (Rang 3)")
local function shortName(e)
    local n = e.name or "?"
    if e.rank then n = (n:gsub("%s*%(.-%)%s*$", "")) end
    return n
end

local function summary()
    local L = ns.L
    local lvl = playerLevel()
    local s = format(L.SA_SUMMARY, lvl, #entries)
    for _, e in ipairs(entries) do
        if e.level > lvl then
            s = s .. "  ·  " .. format(L.SA_NEXT, e.level)
            break
        end
    end
    return s
end

--------------------------------------------------------------------------
-- Infobulle : vrai tooltip de sort si on a pu resoudre le spellID, sinon
-- le nom, la description relevee chez l entraineur et le niveau. Infobulle
-- privee de CorpUI (ns.Tooltip) : on ne touche pas au GameTooltip partage.
--------------------------------------------------------------------------

local function showTip(self)
    local e = self.entry
    if not e or not ns.Tooltip then return end
    local C, L = ns.COLORS, ns.L
    local tip = ns.Tooltip(self, "ANCHOR_RIGHT")
    local native = false
    if e.spellID then
        native = pcall(tip.SetSpellByID, tip, e.spellID)
    end
    if not native then
        tip:SetText(e.name, C.gold[1], C.gold[2], C.gold[3])
        if e.desc then
            tip:AddLine(e.desc, C.text[1], C.text[2], C.text[3], true)
        end
    end
    if e.level and e.level > 0 then
        tip:AddLine(format(L.SA_LEARN_AT, e.level), C.gold[1], C.gold[2], C.gold[3])
    end
    tip:Show()
end

local function hideTip()
    if ns.HideTooltip then ns.HideTooltip() end
end

--------------------------------------------------------------------------
-- Fenetre (panneau du module dans la fenetre CorpUI, /sa) : lignes
-- compactes a la facon de l apercu de recherche du grimoire
--------------------------------------------------------------------------

local function makeRow(parent)
    local C = ns.COLORS
    local row = frame("Frame", parent)
    row:SetHeight(ROW_H)
    row:EnableMouse(true)

    local hov = tex(row, "HIGHLIGHT")
    hov:SetAllPoints(row)
    gradient(hov, "HORIZONTAL", C.violet, 0.22, 0.02)

    local lv = headText(row, 11)
    lv:SetPoint("LEFT", 2, 0)
    lv:SetWidth(26)
    lv:SetJustifyH("RIGHT")
    row.level = lv

    local ic = tex(row, "ARTWORK")
    ic:SetSize(15, 15)
    ic:SetPoint("LEFT", lv, "RIGHT", 7, 0)
    ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon = ic
    row.edges = ring(row, ic, "OVERLAY", 7, 1)
    paintC(row.edges, C.border)

    local nm = sysText(row, "GameFontHighlightSmall", 11)
    nm:SetPoint("LEFT", ic, "RIGHT", 7, 0)
    nm:SetPoint("RIGHT", -2, 0)
    nm:SetJustifyH("LEFT")
    nm:SetWordWrap(false)
    row.name = nm

    row:SetScript("OnEnter", function(self)
        paintC(self.edges, ns.COLORS.gold)
        showTip(self)
    end)
    row:SetScript("OnLeave", function(self)
        paintC(self.edges, ns.COLORS.border)
        hideTip()
    end)
    return row
end

local function fillRow(row, e)
    row.entry = e
    if not e then
        row:Hide()
        return
    end
    local C = ns.COLORS
    row.name:SetText(e.name)
    setColor(row.name, C.text)
    if e.level > 0 then
        row.level:SetText(tostring(e.level))
        setColor(row.level, C.gold)
    else
        row.level:SetText("--")
        setColor(row.level, MUTED)
    end
    row.icon:SetTexture(e.icon or QUESTION)
    row:Show()
end

local function clampOffset(offset, total, visible)
    local maxOffset = total - visible
    if maxOffset < 0 then maxOffset = 0 end
    if offset > maxOffset then offset = maxOffset end
    if offset < 0 then offset = 0 end
    return offset
end

local function refresh()
    if not win or not win:IsShown() then return end
    local total = #entries
    win.subtitle:SetText(total == 0 and ns.L.SA_EMPTY_HINT or summary())
    setColor(win.subtitle, MUTED)
    scrollOffset = clampOffset(scrollOffset, total, ROWS)
    for i = 1, ROWS do
        fillRow(rows[i], entries[i + scrollOffset])
    end
end

local function buildWindow()
    if win then return end

    -- panneau de la fenetre principale de CorpUI
    local f = ns.NewPanel("SpellsAheadFrame", ns.L.MOD_SPELLS, WIDTH, 52 + ROWS * ROW_H + 10)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(self, delta)
        scrollOffset = scrollOffset - delta * 3
        refresh()
    end)

    local sub = sysText(f, "GameFontHighlightSmall", 11)
    sub:SetPoint("TOPLEFT", 10, -32)
    sub:SetPoint("TOPRIGHT", -10, -32)
    sub:SetJustifyH("LEFT")
    sub:SetWordWrap(false)
    f.subtitle = sub

    for i = 1, ROWS do
        local row = makeRow(f)
        row:SetPoint("TOPLEFT", 8, -(48 + (i - 1) * ROW_H))
        row:SetPoint("TOPRIGHT", -8, -(48 + (i - 1) * ROW_H))
        rows[i] = row
    end

    win = f
end

local function toggle()
    buildWindow()
    rebuild()
    ns.ShowPanel(win)
    refresh()
end

--------------------------------------------------------------------------
-- Integration dans le livre de sorts
--
-- Regle absolue : aucun hook sur du code de Blizzard. Notre onglet et notre
-- page sont de simples enfants de leur grimoire, ancres sur leurs cadres,
-- et toute la detection se fait par sondage depuis NOTRE OnUpdate (plus un
-- evenement de clic global), jamais depuis leur pile d appels.
--
-- Structure relevee sur ce client :
--   PlayerSpellsFrame.SpellBookFrame          1612x702 (806 en vue reduite)
--     .CategoryTabSystem  bande des onglets de categorie (44x32 chacun)
--     .PagedSpellsFrame   zone de page, vues View1 / View2 de 680x590
-- La bande d onglets est au-dessus de la zone de page : notre page ne
-- recouvre donc jamais leurs onglets, ils restent cliquables.
--------------------------------------------------------------------------

-- combat : vrai de PLAYER_REGEN_DISABLED (qui precede le verrouillage) a
-- PLAYER_REGEN_ENABLED ; pending : donnees changees pendant le combat
local book = { page = 1, nv = 2, dirty = true, combat = false, pending = false }

-- Rien en combat (comme Grimoire.lua) : la page se ferme a l entree en
-- combat, ne s ouvre pas et ne se redessine pas pendant ; aucun cadre cree,
-- aucune lecture de leurs cadres
local function inCombat()
    return book.combat == true or InCombatLockdown() == true
end

local function getBookFrames()
    local psf = rawget(_G, "PlayerSpellsFrame")
    local sbf = field(psf, "SpellBookFrame")
    if not sbf then return nil end
    local tabs = field(sbf, "CategoryTabSystem") or field(sbf, "tabSystem")
    local page = field(sbf, "PagedSpellsFrame")
    if not tabs or not page then return nil end
    return sbf, tabs, page, psf
end

-- nombre de pages en vue : 2 (grimoire agrandi) ou 1 (reduit)
local function viewsShown()
    local _, _, page, psf = getBookFrames()
    local v2 = field(page, "View2")
    if v2 then
        local ok, s = pcall(function() return v2:IsShown() end)
        if ok and not issecret(s) and type(s) == "boolean" then return s and 2 or 1 end
    end
    local m = value(psf, "isMinimized")
    if type(m) == "boolean" then return m and 1 or 2 end
    local w = book.panel and callNum(book.panel, "GetWidth")
    return (w and w < 1200) and 1 or 2
end

local function pageFormat()
    local g = rawget(_G, "PAGE_NUMBER_WITH_MAX")
    if type(g) == "string" and not issecret(g) and select(2, g:gsub("%%d", "")) == 2 then return g end
    return ns.L.SA_PAGE
end

---------------------------------------------------------------------------
-- Onglet
---------------------------------------------------------------------------

local function tabPaint()
    local s = book.tabSkin
    if not s then return end
    local C = ns.COLORS
    local active = book.panel ~= nil and book.panel:IsShown()
    -- en combat la page est indisponible : icone grisee, pas de survol
    local locked = not active and inCombat()
    s.bar:SetShown(active)
    if active then paintC(s.edges, C.gold)
    elseif book.tabOver and not locked then paintC(s.edges, C.violet)
    else paintC(s.edges, C.border) end
    local v = locked and 0.35 or ((active or book.tabOver) and 1 or 0.6)
    s.icon:SetVertexColor(v, v, v, 1)
    s.icon:SetDesaturated(locked)
end

local showPanel

local function buildTab(sbf, tabs)
    local C = ns.COLORS
    -- taille d un de leurs onglets (icone de 36 + 8 = 44 x 32), lue
    local w, h = 44, 32
    local okK, kids = pcall(function() return { tabs:GetChildren() } end)
    if okK then
        for _, k in ipairs(kids) do
            local kw, kh = callNum(k, "GetWidth"), callNum(k, "GetHeight")
            if kw and kh and kw >= 20 and kw <= 80 and kh >= 20 and kh <= 60 then
                w, h = kw, kh
                break
            end
        end
    end

    local tab = frame("Button", sbf)
    tab:SetSize(w, h)
    tab:SetPoint("LEFT", tabs, "RIGHT", 0, 0)

    local s = {}
    s.icon = tex(tab, "ARTWORK")
    s.icon:SetSize(36, 35)
    s.icon:SetPoint("CENTER", tab, "CENTER", 0, 0)
    s.icon:SetTexture(BOOK_ICON)
    s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    s.fill = tex(tab, "BACKGROUND", -8)
    s.fill:SetPoint("TOPLEFT", s.icon, "TOPLEFT", -1, 1)
    s.fill:SetPoint("BOTTOMRIGHT", s.icon, "BOTTOMRIGHT", 1, -1)
    s.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 1)
    s.edges = ring(tab, s.icon, "OVERLAY", 6, 1)
    s.bar = tex(tab, "OVERLAY", 7)
    s.bar:SetPoint("TOPLEFT", s.icon, "BOTTOMLEFT", -1, -3)
    s.bar:SetPoint("TOPRIGHT", s.icon, "BOTTOMRIGHT", 1, -3)
    s.bar:SetHeight(2)
    s.bar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    s.bar:Hide()
    s.hl = tex(tab, "HIGHLIGHT")
    s.hl:SetAllPoints(s.icon)
    s.hl:SetColorTexture(1, 1, 1, 0.08)

    tab:SetScript("OnEnter", function(self)
        book.tabOver = true
        tabPaint()
        if ns.Tooltip then
            local c = ns.COLORS
            local tip = ns.Tooltip(self, "ANCHOR_RIGHT")
            tip:SetText(ns.L.MOD_SPELLS, c.gold[1], c.gold[2], c.gold[3])
            local d = ns.L.SPELLS_DESC or ""
            tip:AddLine(d:sub(1, 1):upper() .. d:sub(2), c.text[1], c.text[2], c.text[3], true)
            if inCombat() then tip:AddLine(ns.L.SA_COMBAT, 1, 0.45, 0.45) end
            tip:Show()
        end
    end)
    tab:SetScript("OnLeave", function()
        book.tabOver = false
        tabPaint()
        hideTip()
    end)
    -- en combat le clic n ouvre rien (showPanel refuse) ; fermer reste permis
    tab:SetScript("OnClick", function()
        if book.panel then showPanel(not book.panel:IsShown()) end
    end)

    book.tab, book.tabSkin = tab, s
    tabPaint()
end

---------------------------------------------------------------------------
-- Page : en-tetes, cartes, pagination
---------------------------------------------------------------------------

-- en-tete : 51 de haut comme ceux du grimoire ; bandeau de 28 centre sur
-- le titre (en haut de l en-tete, ou Blizzard pose son texte)
local function newHead(slot)
    local C = ns.COLORS
    local f = frame("Frame", slot.frame)
    f:SetHeight(GRID.headH)
    local h = {}
    h.band = tex(f, "BACKGROUND", -8)
    h.band:SetPoint("TOPLEFT", f, "TOPLEFT", -14, 4)
    h.band:SetPoint("TOPRIGHT", f, "TOPRIGHT", -40, 4)
    h.band:SetHeight(28)
    gradient(h.band, "HORIZONTAL", C.violet, 0.30, 0.03)
    h.line = tex(f, "BACKGROUND", -7)
    h.line:SetPoint("TOPLEFT", h.band, "BOTTOMLEFT", 0, 0)
    h.line:SetPoint("TOPRIGHT", h.band, "BOTTOMRIGHT", 0, 0)
    h.line:SetHeight(1)
    gradient(h.line, "HORIZONTAL", C.gold, 0.8, 0)
    h.title = headText(f, 17)
    h.title:SetPoint("LEFT", h.band, "LEFT", 6, 0)
    h.title:SetJustifyH("LEFT")
    h.info = sysText(f, "SystemFont_Med1", 12)
    h.info:SetPoint("RIGHT", h.band, "RIGHT", -10, 0)
    h.info:SetJustifyH("RIGHT")
    h.note = sysText(f, "SystemFont_Med1", 12)
    h.note:SetPoint("TOPLEFT", h.line, "BOTTOMLEFT", 6, -12)
    h.note:SetJustifyH("LEFT")
    f.cui = h
    return f
end

local function fillHead(f, hd, host, w)
    local C = ns.COLORS
    local h = f.cui
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -hd.y)
    f:SetWidth(w)
    h.title:SetText(hd.title or "")
    setColor(h.title, C.gold)
    h.info:SetText(hd.info or "")
    setColor(h.info, MUTED)
    h.note:SetText(hd.note or "")
    h.note:SetWidth(math.max(40, w - 60))
    h.note:SetShown(hd.note ~= nil)
    setColor(h.note, C.text)
    f:Show()
end

local function cardPaint(c, over)
    local C = ns.COLORS
    c.glow:SetShown(over)
    if over then
        paintC(c.edges, C.gold, 1)
        paintC(c.ring, C.gold)
    else
        paintC(c.edges, C.border, 0.55)
        paintC(c.ring, C.border)
    end
end

-- carte : celle d une case du grimoire habillee (case de 60, bouton de 40
-- a gauche avec icone de 36, textes a 50 px du bord)
local function newCard(slot)
    local C = ns.COLORS
    local f = frame("Frame", slot.frame)
    f:SetSize(GRID.viewW / GRID.cols, GRID.itemH)
    f:EnableMouse(true)
    local c = {}
    c.fill = tex(f, "BACKGROUND", -8)
    c.fill:SetPoint("TOPLEFT", f, "TOPLEFT", -5, 1)
    c.fill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, -1)
    c.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.5)
    c.glow = tex(f, "BACKGROUND", -7)
    c.glow:SetAllPoints(c.fill)
    gradient(c.glow, "HORIZONTAL", C.violet, 0.22, 0.02)
    c.glow:Hide()
    c.edges = ring(f, c.fill, "BACKGROUND", -6, 0)
    c.icon = tex(f, "ARTWORK")
    c.icon:SetSize(36, 36)
    c.icon:SetPoint("LEFT", f, "LEFT", 2, 0)
    c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.ring = ring(f, c.icon, "OVERLAY", 7, 1)
    c.hl = tex(f, "HIGHLIGHT")
    c.hl:SetAllPoints(c.icon)
    c.hl:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.22)
    c.name = sysText(f, "SystemFont_Large", 16)
    c.name:SetJustifyH("LEFT")
    c.name:SetWordWrap(true)
    pcall(c.name.SetMaxLines, c.name, 2)
    c.sub = sysText(f, "SystemFont_Med1", 12)
    c.sub:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -2)
    c.sub:SetJustifyH("LEFT")
    c.sub:SetWordWrap(false)
    f.cui = c
    f:SetScript("OnEnter", function(self)
        cardPaint(c, true)
        showTip(self)
    end)
    f:SetScript("OnLeave", function()
        cardPaint(c, false)
        hideTip()
    end)
    cardPaint(c, false)
    return f
end

-- bloc nom + rang centre verticalement dans la carte (comme le
-- TextContainer de Blizzard, decale de 1 px vers le bas)
local function placeText(f, c, w)
    -- largeur posee avant la mesure : le retour a la ligne du nom (deux
    -- lignes au plus) est connu tout de suite
    local tw = math.max(20, w - 52)
    c.name:SetWidth(tw)
    c.sub:SetWidth(tw)
    local hasSub = c.sub:IsShown()
    local total = textHeight(c.name, 16) + (hasSub and (2 + textHeight(c.sub, 12)) or 0)
    local top = math.max(2, math.floor((GRID.itemH - total) / 2 + 0.5) + 1)
    c.name:ClearAllPoints()
    c.name:SetPoint("TOPLEFT", f, "TOPLEFT", 50, -top)
end

local function fillCard(f, e, host, x, y, w)
    local C = ns.COLORS
    local c = f.cui
    f.entry = e
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", host, "TOPLEFT", x, -y)
    f:SetWidth(w)
    c.icon:SetTexture(e.icon or QUESTION)
    c.name:SetText(shortName(e))
    setColor(c.name, C.text)
    local sub = e.rank or ""
    c.sub:SetText(sub)
    c.sub:SetShown(sub ~= "")
    setColor(c.sub, C.gold)
    placeText(f, c, w)
    f:Show()
end

-- groupes par niveau (niveau inconnu a la fin)
local function groupsOf(list)
    local out, unknown, cur = {}, nil, nil
    for _, e in ipairs(list) do
        if e.level <= 0 then
            unknown = unknown or { level = 0, entries = {} }
            unknown.entries[#unknown.entries + 1] = e
        else
            if not cur or cur.level ~= e.level then
                cur = { level = e.level, entries = {} }
                out[#out + 1] = cur
            end
            cur.entries[#cur.entries + 1] = e
        end
    end
    if unknown then out[#out + 1] = unknown end
    return out
end

-- repartition en vues, a la facon de la grille "condensee" du grimoire :
-- un en-tete par groupe, cartes colonne par colonne (3 colonnes, autant de
-- rangees que necessaire), suite du groupe dans la vue suivante si la
-- place manque. Chaque vue : { heads = { {y,title,info,note} }, items =
-- { {x,y,entry} } }
local function layout(groups, colW, height)
    local L = ns.L
    local lvl = playerLevel()
    local views = {}
    local view, space, y
    local function newView()
        view = { heads = {}, items = {} }
        views[#views + 1] = view
        space, y = height, 0
    end
    newView()
    if #groups == 0 then
        view.heads[1] = { y = 0, title = L.SA_EMPTY_TITLE, note = L.SA_EMPTY_HINT }
        return views
    end
    local rowNeed = GRID.itemH + GRID.ypad
    local headNeed = GRID.headH + GRID.ypad
    local spacerNeed = GRID.spacer + GRID.ypad
    for _, g in ipairs(groups) do
        if y > 0 then
            -- pas la place pour l intervalle, l en-tete et une rangee
            if space < spacerNeed + headNeed + rowNeed then
                newView()
            else
                y, space = y + spacerNeed, space - spacerNeed
            end
        end
        view.heads[#view.heads + 1] = {
            y = y,
            title = g.level > 0 and format(L.SA_LEVEL, g.level) or L.SA_LEVEL_UNKNOWN,
            info = (g.level > lvl) and format(L.SA_TOGO, g.level - lvl) or nil,
        }
        y, space = y + headNeed, space - headNeed
        local i, n = 1, #g.entries
        while i <= n do
            local fit = math.floor(space / rowNeed)
            if fit < 1 then
                newView()
                fit = math.max(1, math.floor(space / rowNeed))
            end
            local left = n - i + 1
            local rowsN = math.min(fit, math.ceil(left / GRID.cols))
            local take = math.min(left, rowsN * GRID.cols)
            for k = 0, take - 1 do
                local col, row = math.floor(k / rowsN), k % rowsN
                view.items[#view.items + 1] = {
                    x = col * (colW + GRID.xpad),
                    y = y + row * rowNeed,
                    entry = g.entries[i + k],
                }
            end
            i = i + take
            y, space = y + rowsN * rowNeed, space - rowsN * rowNeed
        end
    end
    return views
end

-- places d une vue haute de "height" (bornes de layout) : une rangee de
-- cartes par tranche de 70 ; un en-tete en haut, puis un par groupe complet
-- (intervalle + en-tete + une rangee)
local function capacity(height)
    local rowNeed = GRID.itemH + GRID.ypad
    local headNeed = GRID.headH + GRID.ypad
    local groupNeed = GRID.spacer + GRID.ypad + headNeed + rowNeed
    local cards = math.max(1, math.floor(height / rowNeed)) * GRID.cols
    local heads = 1
    if height > headNeed + rowNeed then
        heads = 1 + math.floor((height - headNeed - rowNeed) / groupNeed)
    end
    return heads, cards
end

-- reserve de cartes et d en-tetes d une page : creee a la construction, hors
-- combat, agrandie au besoin par render (jamais en combat)
local function growPool(slot, heads, cards)
    if inCombat() then return end
    while #slot.heads < heads do
        local f = newHead(slot)
        f:Hide()
        slot.heads[#slot.heads + 1] = f
    end
    while #slot.cards < cards do
        local f = newCard(slot)
        f:Hide()
        slot.cards[#slot.cards + 1] = f
    end
end

-- remplit une page avec la reserve : aucun cadre n est cree ici
local function fillSlot(slot, view)
    for _, f in ipairs(slot.cards) do
        f:Hide()
        f.entry = nil
    end
    for _, f in ipairs(slot.heads) do f:Hide() end
    if not view then return end
    for i, hd in ipairs(view.heads) do
        local f = slot.heads[i]
        if f then fillHead(f, hd, slot.frame, book.viewW) end
    end
    for i, it in ipairs(view.items) do
        local f = slot.cards[i]
        if f then fillCard(f, it.entry, slot.frame, it.x, it.y, book.colW) end
    end
end

-- pagination : boutons < > plats (plaque, lisere, glyphe or)
local function glyphButton(parent, glyph)
    local C = ns.COLORS
    local b = frame("Button", parent)
    b:SetSize(32, 32)
    local p = {}
    p.fill = tex(b, "BACKGROUND", -8)
    p.fill:SetPoint("TOPLEFT", 6, -6)
    p.fill:SetPoint("BOTTOMRIGHT", -6, 6)
    p.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.95)
    p.edges = ring(b, p.fill, "BACKGROUND", -7, 0)
    paintC(p.edges, C.border)
    p.hl = tex(b, "HIGHLIGHT")
    p.hl:SetAllPoints(p.fill)
    gradient(p.hl, "VERTICAL", C.violet, 0.05, 0.28)
    p.glyph = ns.UI.Chevron(b, 14, glyph)
    mine[p.glyph] = true
    p.glyph:SetPoint("CENTER", 0, 0)
    p.glyph:SetText(glyph)
    setColor(p.glyph, C.gold)
    b.cui = p
    b:SetScript("OnEnter", function(self)
        if self:IsEnabled() then paintC(p.edges, ns.COLORS.gold) end
    end)
    b:SetScript("OnLeave", function()
        paintC(p.edges, ns.COLORS.border)
    end)
    return b
end

local function setUsable(b, on)
    b:SetEnabled(on)
    b.cui.glyph:SetAlpha(on and 1 or 0.35)
    if not on then paintC(b.cui.edges, ns.COLORS.border) end
end

local function render()
    local p = book.panel
    if not p or not p:IsShown() then return end
    -- rien en combat (la page est fermee a l entree en combat)
    if inCombat() then return end
    local nv = viewsShown()
    if nv ~= book.nv and book.views then
        -- vue agrandie / reduite : on garde en vue la meme premiere page
        local first = (book.page - 1) * book.nv + 1
        book.page = math.floor((first - 1) / nv) + 1
    end
    if book.dirty or not book.views then
        local s1 = book.slots[1].frame
        local w, h = callNum(s1, "GetWidth"), callNum(s1, "GetHeight")
        if not (w and w >= 400 and w <= 1000) then w = GRID.viewW end
        if not (h and h >= 300 and h <= 1000) then h = GRID.viewH end
        book.viewW = w
        book.colW = (w - GRID.xpad * (GRID.cols - 1)) / GRID.cols
        book.views = layout(groupsOf(entries), book.colW, h - FOOT_H)
        book.dirty = false
        -- reserve a la mesure de la vue la plus remplie (hors combat)
        local nh, nc = 0, 0
        for _, v in ipairs(book.views) do
            nh, nc = math.max(nh, #v.heads), math.max(nc, #v.items)
        end
        for _, slot in ipairs(book.slots) do growPool(slot, nh, nc) end
    end
    book.nv = nv
    local pages = math.max(1, math.ceil(#book.views / nv))
    book.page = math.min(math.max(book.page or 1, 1), pages)
    for k, slot in ipairs(book.slots) do
        local on = k <= nv
        slot.frame:SetShown(on)
        slot.cover:SetShown(on)
        slot.fill:SetShown(on)
        showAll(slot.edges, on)
        fillSlot(slot, on and book.views[(book.page - 1) * nv + k] or nil)
    end
    -- pagination au bas de la derniere page visible
    local last = book.slots[math.max(1, math.min(nv, #book.slots))]
    if book.pagedOn ~= last then
        book.pagedOn = last
        book.next:ClearAllPoints()
        book.next:SetPoint("BOTTOMRIGHT", last.fill, "BOTTOMRIGHT", -12, 8)
    end
    local C = ns.COLORS
    book.pageText:SetText(format(pageFormat(), book.page, pages))
    setColor(book.pageText, C.text)
    setUsable(book.prev, book.page > 1)
    setUsable(book.next, book.page < pages)
    book.summary:SetText(#entries > 0 and summary() or "")
    setColor(book.summary, MUTED)
end

local function turn(d)
    if not book.views or inCombat() then return end
    book.page = (book.page or 1) + d
    render()
end

local function buildPanel(sbf, page)
    local C = ns.COLORS
    -- calque sur leur zone de page, au-dessus de leurs cases ; il ne prend
    -- pas la souris (vu en jeu : couvrant toute la zone, plus large que les
    -- pages, il cachait la bande des onglets et debordait a gauche) : seules
    -- nos pages (ci-dessous) recouvrent et bloquent leurs cases
    local panel = frame("Frame", sbf)
    panel:SetAllPoints(page)
    panel:SetFrameLevel((callNum(page, "GetFrameLevel") or 1) + 20)
    panel:EnableMouse(false)
    panel:Hide()
    book.panel = panel
    local function wheel(_, delta) turn(delta > 0 and -1 or 1) end

    -- une page par vue de Blizzard (ancree dessus, sinon a leur place)
    book.slots = {}
    for k = 1, 2 do
        local view = field(page, "View" .. k)
        local f = frame("Frame", panel)
        if view then
            f:SetPoint("TOPLEFT", view, "TOPLEFT", 0, 0)
            f:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", 0, 0)
        else
            local pos = VIEW_POS[k]
            f:SetSize(GRID.viewW, GRID.viewH)
            f:SetPoint(pos[1], panel, pos[1], pos[2], pos[3])
        end
        -- la page prend la souris (leurs cases dessous ne recoivent rien)
        f:EnableMouse(true)
        f:EnableMouseWheel(true)
        f:SetScript("OnMouseWheel", wheel)
        local slot = { frame = f, cards = {}, heads = {} }
        -- fond opaque de la page seule (celui de la fenetre habillee)
        slot.cover = tex(panel, "BACKGROUND", -8)
        slot.cover:SetPoint("TOPLEFT", f, "TOPLEFT", -PAGE_PAD.left, PAGE_PAD.top)
        slot.cover:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", PAGE_PAD.right, -PAGE_PAD.bottom)
        slot.cover:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 1)
        slot.fill = tex(panel, "BACKGROUND", -7)
        slot.fill:SetPoint("TOPLEFT", f, "TOPLEFT", -PAGE_PAD.left, PAGE_PAD.top)
        slot.fill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", PAGE_PAD.right, -PAGE_PAD.bottom)
        slot.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.45)
        slot.edges = ring(panel, slot.fill, "BACKGROUND", -6, 0)
        paintC(slot.edges, C.border, 0.8)
        book.slots[k] = slot
    end

    -- reserve creee ici, hors combat : de quoi remplir une vue entiere
    -- (hauteur de leur vue lue, sinon celle du grimoire)
    local vh = callNum(field(page, "View1"), "GetHeight")
    if not (vh and vh >= 300 and vh <= 1000) then vh = GRID.viewH end
    local nh, nc = capacity(vh - FOOT_H)
    for _, slot in ipairs(book.slots) do growPool(slot, nh, nc) end

    -- pagination a la place de la leur : [texte] [<] [>], en bas de la
    -- derniere page visible (recalee par render selon la vue)
    book.next = glyphButton(panel, ">")
    book.next:SetPoint("BOTTOMRIGHT", book.slots[2].fill, "BOTTOMRIGHT", -12, 8)
    book.next:SetScript("OnClick", function() turn(1) end)
    book.prev = glyphButton(panel, "<")
    book.prev:SetPoint("RIGHT", book.next, "LEFT", -8, 0)
    book.prev:SetScript("OnClick", function() turn(-1) end)
    book.pageText = sysText(panel, "SystemFont_Med3", 14)
    book.pageText:SetPoint("RIGHT", book.prev, "LEFT", -8, 0)
    book.pageText:SetJustifyH("RIGHT")

    -- niveau, nombre de sorts, prochain sort : en bas de la page de gauche
    book.summary = sysText(panel, "SystemFont_Med1", 12)
    book.summary:SetPoint("BOTTOMLEFT", book.slots[1].fill, "BOTTOMLEFT", 26, 16)
    book.summary:SetJustifyH("LEFT")

end

showPanel = function(show)
    local p = book.panel
    if not p then return end
    -- en combat la page ne s ouvre pas ; la fermer (cacher notre cadre)
    -- reste permis
    if show and inCombat() then show = false end
    if show then
        rebuild()
        book.page, book.dirty = 1, true
        local sbf, tabs = getBookFrames()
        book.cat = value(tabs, "selectedTabID")
        book.search = value(sbf, "isInSearchResultsMode")
        p:Show()
        render()
    else
        p:Hide()
    end
    tabPaint()
end

-- etat lisible par les autres fichiers de CorpUI : Grimoire.lua (tabState)
-- s en sert pour eteindre leur onglet actif pendant que notre page est
-- ouverte
function ns.SpellsAheadShown()
    return book.panel ~= nil and book.panel:IsShown() == true
end

-- Skins.lua : ne pas aplatir nos cadres, ne pas eteindre nos textures.
-- Chaine posee a la construction, une fois tous les fichiers charges :
-- Personnage.lua (charge apres nous) redefinit ns.SkinClaimed sans
-- enchainer, ce qui effacerait une chaine posee au chargement.
local chained = false
local function chainClaims()
    if chained then return end
    chained = true
    local prevClaimed = ns.SkinClaimed
    function ns.SkinClaimed(f)
        if type(f) == "table" and ours[f] then return true end
        if prevClaimed then return prevClaimed(f) end
        return false
    end
    local prevOwned = ns.SkinOwned
    function ns.SkinOwned(r)
        if type(r) == "table" and mine[r] then return true end
        if prevOwned then return prevOwned(r) end
        return false
    end
end

local function buildBookUI()
    if book.built or book.failed then return book.built == true end
    if inCombat() then return false end
    local sbf, tabs, page = getBookFrames()
    if not sbf then return false end
    chainClaims()
    local ok, err = pcall(function()
        buildPanel(sbf, page)
        buildTab(sbf, tabs)
    end)
    if not ok then
        -- construction ratee : rien d a moitie visible, raison dans /sa api
        book.failed = tostring(err)
        if book.tab then book.tab:Hide() end
        if book.panel then book.panel:Hide() end
        return false
    end
    book.built = true
    return true
end


-- Branche la mise a jour differee de la lecture d entraineur sur ce qui est
-- actuellement affiche.
onDataChanged = function()
    local needWin   = win and win:IsShown()
    local needPanel = book.panel and book.panel:IsShown()
    if not (needWin or needPanel) then return end
    -- en combat : remis a PLAYER_REGEN_ENABLED
    if inCombat() then
        book.pending = true
        return
    end
    rebuild()
    if needWin then refresh() end
    if needPanel then
        book.dirty = true
        render()
    end
end

-- Pilote : construit l integration des que le livre existe (il est charge a
-- la demande, jamais en combat), puis, pendant que notre page est affichee,
-- s efface quand le livre se ferme, qu une de LEURS categories est choisie
-- ou qu une recherche est lancee, et suit la vue agrandie / reduite.
local function watch()
    -- rien en combat, pas meme une lecture de leurs cadres
    if inCombat() then return end
    local panel = book.panel
    if not panel:IsVisible() then
        showPanel(false)
        return
    end
    local sbf, tabs = getBookFrames()
    local cat = value(tabs, "selectedTabID")
    if cat ~= nil and book.cat ~= nil and cat ~= book.cat then
        showPanel(false)
        return
    end
    local searching = value(sbf, "isInSearchResultsMode")
    if searching == true and book.search ~= true then
        showPanel(false)
        return
    end
    book.search = searching
    if isOver(tabs) and type(_G.IsMouseButtonDown) == "function"
       and IsMouseButtonDown("LeftButton") then
        showPanel(false)
        return
    end
    if viewsShown() ~= book.nv then render() end
end

local driver = CreateFrame("Frame")
driver.elapsed = 0
ns.Every(0.1, function(dt)
    local self = driver
    self.elapsed = self.elapsed + dt
    local open = book.panel ~= nil and book.panel:IsShown()
    if self.elapsed < (open and 0.1 or 0.25) - 0.001 then return end
    self.elapsed = 0
    -- rien en combat. Filet : une page restee ouverte (PLAYER_REGEN_DISABLED
    -- manque) est fermee, ce qui ne cache que notre cadre
    if inCombat() then
        if open then showPanel(false) end
        return
    end
    if not book.built then
        buildBookUI()
        return
    end
    if open then watch() end
end, "SpellsAhead : grimoire", "sorts")

-- clic n importe ou : sur LEUR bande d onglets, on s efface tout de suite
-- (le sondage ci-dessus rattrape le cas ou l evenement n existe pas)
local clicks = CreateFrame("Frame")
clicks:SetScript("OnEvent", function(_, event, button)
    if ns.ModuleOff("sorts", clicks) then return end
    if event ~= "GLOBAL_MOUSE_DOWN" then return end
    if button ~= nil and button ~= "LeftButton" then return end
    if inCombat() then return end
    if not (book.panel and book.panel:IsShown()) then return end
    local _, tabs = getBookFrames()
    if isOver(tabs) then showPanel(false) end
end)
pcall(clicks.RegisterEvent, clicks, "GLOBAL_MOUSE_DOWN")


--------------------------------------------------------------------------
-- Commandes
--------------------------------------------------------------------------

local function PrintChat()
    rebuild()
    if #entries == 0 then
        say("aucune donnee. Visite un entraineur de classe une fois, ou tape /sa api.")
        return
    end
    local lvl = playerLevel()
    say(format("sorts a venir (niveau actuel %d) :", lvl))
    local shown = 0
    for _, e in ipairs(entries) do
        chat(format("   |cffffd100%s|r  %s", e.level > 0 and tostring(e.level) or "--", e.name))
        shown = shown + 1
        if shown >= 30 then
            chat(format("   |cff888888... et %d de plus, utilise /sa|r", #entries - shown))
            break
        end
    end
end

local function PrintApi()
    say("API disponibles sur ce client :")
    local p = probe()
    local keys = {}
    for k in pairs(p) do keys[#keys + 1] = k end
    sort(keys)
    for _, k in ipairs(keys) do
        chat(format("   %s |cff888888%s|r", p[k] and "|cff00ff00oui|r" or "|cffff5555non|r", k))
    end
    if #failedEvents > 0 then
        say("evenements refuses par ce client :")
        for _, e in ipairs(failedEvents) do
            chat("   |cffff5555" .. e .. "|r")
        end
    else
        say("tous les evenements ont ete acceptes.")
    end

    say("onglet du livre : |cffffff00" .. (book.failed and ("echec : " .. book.failed)
        or (book.built and "style CorpUI" or "pas encore construit")) .. "|r")

    local nModern, nClassic, nTrainer = rebuild()
    say(format("collecte : livre moderne=%d, livre classic=%d, cache entraineur=%d",
        nModern, nClassic, nTrainer))

    local withID = 0
    for _, e in ipairs(entries) do
        if e.spellID then withID = withID + 1 end
    end
    say(format("%d entree(s) sur %d ont un vrai spellID (donc un vrai tooltip).",
        withID, #entries))
    say("tooltip d entraineur : |cffffff00" .. tostring(scanDiag.reason) .. "|r")
end

--------------------------------------------------------------------------
-- Dump complet vers les SavedVariables (relu depuis le disque)
--------------------------------------------------------------------------

local function buildDump()
    local d = {}
    local mfloor = math.floor

    -- Publie la table AVANT de la remplir : si une section plante, le partiel
    -- est conserve et la derniere ligne ecrite indique ou ca s est arrete.
    SpellsAheadDB = SpellsAheadDB or {}
    SpellsAheadDB.dump = d
    SpellsAheadDB.dumpStamp = date("%d/%m %H:%M:%S")

    local function add(fmt, ...)
        if select("#", ...) > 0 then
            d[#d + 1] = format(fmt, ...)
        else
            d[#d + 1] = fmt
        end
    end

    local cs = _G.C_SpellBook
    local en = _G.Enum

    add("== contexte ==")
    add("  classe=%s niveau=%d", classKey(), playerLevel())

    add("== Enum.SpellBookItemType ==")
    if type(en) == "table" and type(en.SpellBookItemType) == "table" then
        for k, v in pairs(en.SpellBookItemType) do
            add("  %s = %s", tostring(k), tostring(v))
        end
    end

    add("== Enum.SpellBookSpellBank ==")
    if type(en) == "table" and type(en.SpellBookSpellBank) == "table" then
        for k, v in pairs(en.SpellBookSpellBank) do
            add("  %s = %s", tostring(k), tostring(v))
        end
    end

    local numLines = call(cs.GetNumSpellBookSkillLines)
    add("== GetNumSpellBookSkillLines = %s ==", tostring(numLines))

    for line = 1, (tonumber(numLines) or 0) do
        local info = call(cs.GetSpellBookSkillLineInfo, line)
        add("  -- skillLine %d (%s)", line, type(info))
        if type(info) == "table" then
            for k, v in pairs(info) do
                add("      %s = %s", tostring(k), tostring(v))
            end
        end
    end

    -- Balayage brut, independant des skill lines
    local bank = (type(en) == "table" and en.SpellBookSpellBank
                  and en.SpellBookSpellBank.Player) or nil
    add("== balayage index 1..400 (bank=%s) ==", tostring(bank))

    local seen = 0
    for i = 1, 400 do
        local item = call(cs.GetSpellBookItemInfo, i, bank)
        if type(item) == "table" then
            seen = seen + 1
            if seen <= 80 then
                add("  [%d] itemType=%s name=%s spellID=%s passive=%s minLevel=%s learnedAt=%s",
                    i, tostring(item.itemType), tostring(item.name),
                    tostring(item.spellID), tostring(item.isPassive),
                    tostring(item.minLevel),
                    tostring(call(cs.GetSpellBookItemLevelLearned, i, bank)))
            end
        end
    end
    add("  total entrees lues = %d", seen)

    -- Cadres candidats pour accrocher le panneau dans le livre de sorts
    add("== noms connus ==")
    for _, n in ipairs({
        "SpellBookFrame", "PlayerSpellsFrame", "SpellBookFrameTabButton1",
        "SpellBookSpellIconsFrame", "SpellBookPage1", "ClassTrainerFrame",
        "ProfessionsBookFrame",
    }) do
        add("  %s = %s", n, type(_G[n]))
    end

    add("== frames visibles nommees (>150x150) ==")
    if type(_G.EnumerateFrames) == "function" then
        local frame, steps, shown = EnumerateFrames(), 0, 0
        while frame and steps < 6000 and shown < 60 do
            steps = steps + 1
            local ok, visible = pcall(frame.IsShown, frame)
            if ok and visible then
                local name = frame.GetName and frame:GetName()
                local w = (frame.GetWidth and frame:GetWidth()) or 0
                local h = (frame.GetHeight and frame:GetHeight()) or 0
                if name and w > 150 and h > 150 then
                    shown = shown + 1
                    local parent = frame.GetParent and frame:GetParent()
                    local pname  = parent and parent.GetName and parent:GetName()
                    add("  %s  %dx%d  parent=%s", name, mfloor(w), mfloor(h), tostring(pname))
                end
            end
            frame = EnumerateFrames(frame)
        end
        add("  (%d frames parcourues)", steps)
    else
        add("  EnumerateFrames indisponible")
    end

    -- Structure du livre de sorts : conteneur, bande d onglets, zone de page.
    -- C est ce qui permettra d ajouter un onglet a nous sans toucher au leur.
    add("== frames spellbook/playerspells et leurs enfants ==")
    if type(_G.EnumerateFrames) == "function" then
        local frame, steps, hits = EnumerateFrames(), 0, 0
        while frame and steps < 8000 and hits < 10 do
            steps = steps + 1
            local name = frame.GetName and frame:GetName()
            if type(name) ~= "string" then name = nil end
            local low  = name and name:lower() or ""
            if name and (low:find("spellbook") or low:find("playerspells")) then
                hits = hits + 1
                local ok, visible = pcall(frame.IsShown, frame)
                add("  %s  shown=%s  %dx%d  type=%s",
                    name, tostring(ok and visible),
                    mfloor((frame.GetWidth and frame:GetWidth()) or 0),
                    mfloor((frame.GetHeight and frame:GetHeight()) or 0),
                    tostring(frame.GetObjectType and frame:GetObjectType()))

                local okk, kids = pcall(function() return { frame:GetChildren() } end)
                if okk and type(kids) == "table" then
                    for ki = 1, math.min(#kids, 24) do
                        local k = kids[ki]
                        add("      [%d] %s type=%s %dx%d shown=%s",
                            ki,
                            tostring(k.GetName and k:GetName()),
                            tostring(k.GetObjectType and k:GetObjectType()),
                            mfloor((k.GetWidth and k:GetWidth()) or 0),
                            mfloor((k.GetHeight and k:GetHeight()) or 0),
                            tostring(k.IsShown and k:IsShown()))
                    end
                end
            end
            frame = EnumerateFrames(frame)
        end
        add("  (%d frames parcourues, %d correspondances)", steps, hits)
    end

    -- Les enfants de PlayerSpellsFrame sont anonymes : c est une UI a mixins,
    -- les sous-cadres sont des CHAMPS de la table parente. C est la qu on
    -- trouvera la bande d onglets et la zone de page.
    add("== champs de PlayerSpellsFrame ==")
    local psf = _G.PlayerSpellsFrame

    local function describeFrame(prefix, key, v)
        add("%s.%s  type=%s  %dx%d  shown=%s",
            prefix, key,
            tostring(call(v.GetObjectType, v)),
            mfloor(tonumber(call(v.GetWidth, v)) or 0),
            mfloor(tonumber(call(v.GetHeight, v)) or 0),
            tostring(call(v.IsShown, v)))
    end

    local function frameFields(t, limit)
        local keys = {}
        if type(t) ~= "table" then return keys end
        local ok = pcall(function()
            for k, v in pairs(t) do
                if type(k) == "string" and type(v) == "table"
                   and type(v.GetObjectType) == "function" then
                    keys[#keys + 1] = k
                end
                if #keys >= (limit or 40) then break end
            end
        end)
        if ok then sort(keys) end
        return keys
    end

    if type(psf) == "table" then
        local top = frameFields(psf, 40)
        add("  (%d champs-cadres)", #top)
        for _, k in ipairs(top) do
            local v = psf[k]
            describeFrame("  ", k, v)
            for _, k2 in ipairs(frameFields(v, 14)) do
                describeFrame("      " .. k, k2, v[k2])
            end
        end
    else
        add("  PlayerSpellsFrame absent")
    end

    -- Pourquoi on n arrive pas a recuperer le spellID des sorts a venir
    add("== tooltip d entraineur ==")
    add("  derniere raison = %s", tostring(scanDiag.reason))
    add("  lignes lues = %s", tostring(scanDiag.lines))
    add("  scanTip cree = %s", tostring(getScanTip() ~= nil))
    for _, n in ipairs({
        "GetTrainerServiceDescription", "GetTrainerServiceAbilityReq",
        "GetTrainerServiceSkillReq", "GetTrainerServiceStepIndex",
        "GetTrainerServiceTypeFilter", "C_TrainerService",
    }) do
        add("  %s = %s", n, type(_G[n]))
    end
    for _, m in ipairs({ "SetTrainerService", "GetSpell", "NumLines", "SetSpellByID" }) do
        add("  GameTooltip.%s = %s", m,
            type(_G.GameTooltip and _G.GameTooltip[m]))
    end

    -- Tout tenter sur les premiers services si un entraineur est ouvert
    local ns = tonumber(call(_G.GetNumTrainerServices)) or 0
    add("  services ouverts = %d", ns)
    for i = 1, math.min(ns, 3) do
        local sid, desc = readService(i)
        add("    service %d : spellID=%s  raison=%s", i, tostring(sid),
            tostring(scanDiag.reason))
        if desc then
            add("      texte = %s", (desc:gsub("\n", " | ")))
        end
    end

    -- Bande d onglets de categorie (notre onglet se pose a sa droite)
    add("== onglets de categorie ==")
    add("  notre onglet = %s", book.failed and ("echec : " .. book.failed)
        or (book.built and "construit" or "pas encore construit"))

    local sbf2 = _G.PlayerSpellsFrame and _G.PlayerSpellsFrame.SpellBookFrame
    local cts  = sbf2 and (sbf2.CategoryTabSystem or sbf2.tabSystem)
    if type(cts) == "table" and type(cts.GetChildren) == "function" then
        local kids = { cts:GetChildren() }
        add("  %d onglet(s) dans la bande", #kids)
        local k = kids[1]
        if type(k) == "table" then
            add("  onglet[1] : %dx%d  type=%s",
                mfloor(tonumber(call(k.GetWidth, k)) or 0),
                mfloor(tonumber(call(k.GetHeight, k)) or 0),
                tostring(call(k.GetObjectType, k)))

            if type(k.GetRegions) == "function" then
                for ri, r in ipairs({ k:GetRegions() }) do
                    add("      region %d: %s  layer=%s  atlas=%s  tex=%s  %dx%d",
                        ri,
                        tostring(call(r.GetObjectType, r)),
                        tostring(call(r.GetDrawLayer, r)),
                        tostring(r.GetAtlas and call(r.GetAtlas, r)),
                        tostring(r.GetTexture and call(r.GetTexture, r)),
                        mfloor(tonumber(call(r.GetWidth, r)) or 0),
                        mfloor(tonumber(call(r.GetHeight, r)) or 0))
                end
            end

            for _, key in ipairs(frameFields(k, 20)) do
                describeFrame("      champ ", key, k[key])
            end
        end
    else
        add("  CategoryTabSystem introuvable")
    end

    -- Entraineur, si sa fenetre est ouverte
    local numServices = call(_G.GetNumTrainerServices)
    add("== GetNumTrainerServices = %s ==", tostring(numServices))
    for i = 1, math.min(tonumber(numServices) or 0, 40) do
        local name, rank, category = call(_G.GetTrainerServiceInfo, i)
        add("  [%d] name=%s rank=%s cat=%s lvl=%s",
            i, tostring(name), tostring(rank), tostring(category),
            tostring(call(_G.GetTrainerServiceLevelReq, i)))
    end

    return d
end

local function PrintKnown()
    local known = collectKnown()
    if #known == 0 then
        say("livre de sorts vide ou illisible.")
        return
    end
    say(format("sorts connus et niveau d apprentissage (%d) :", #known))
    for _, e in ipairs(known) do
        local lvl = e.level > 0 and format("|cffffd100%d|r", e.level) or "|cff808080--|r"
        local tag = e.passive and " |cff808080(passif)|r" or ""
        chat(format("   %s  %s%s", lvl, e.name, tag))
    end
end

local function PrintHelp()
    say("commandes :")
    chat("  |cffffff00/sa|r - ouvrir / fermer la fenetre")
    chat("  |cffffff00/sa chat|r - lister dans le chat")
    chat("  |cffffff00/sa metiers|r - afficher ou masquer les recettes de metier")
    chat("  |cffffff00/sa known|r - sorts connus et niveau ou tu les as appris")
    chat("  |cffffff00/sa scan|r - scruter l entraineur actuellement ouvert")
    chat("  |cffffff00/sa api|r - ce que le client expose (utile pour le debug)")
    chat("  |cffffff00/sa dump|r - capture complete dans les SavedVariables")
    chat("  |cffffff00/sa clear|r - vider le cache entraineur")
end

SLASH_SPELLSAHEAD1 = "/sa"
SLASH_SPELLSAHEAD2 = "/spellsahead"
SlashCmdList["SPELLSAHEAD"] = function(input)
    if ns.SlashOff("sorts") then return end
    local cmd = strlower(strtrim(input or ""))

    -- filet : la base doit exister meme si ADDON_LOADED a echoue
    SpellsAheadDB = SpellsAheadDB or {}
    SpellsAheadDB.trainer = SpellsAheadDB.trainer or {}

    if cmd == "chat" or cmd == "list" then
        PrintChat()
    elseif cmd == "api" or cmd == "debug" then
        PrintApi()
    elseif cmd == "metiers" or cmd == "trade" then
        SpellsAheadDB.showTrade = not SpellsAheadDB.showTrade
        say("recettes de metier : " ..
            (SpellsAheadDB.showTrade and "|cff00ff00affichees|r" or "|cffff0000masquees|r"))
        if onDataChanged then onDataChanged() end

    elseif cmd == "known" or cmd == "connus" then
        PrintKnown()
    elseif cmd == "scan" then
        local n = scrapeTrainer()
        if InCombatLockdown() then
            say("pas en combat.")
        elseif n == nil then
            say("lecture en cours (la liste se reconstruit), retape /sa dans une seconde.")
        elseif n > 0 then
            say(format("%d service(s) releve(s) chez l entraineur.", n))
        else
            say("aucun entraineur ouvert, ou API indisponible.")
        end
    elseif cmd == "dump" then
        local ok, err = pcall(buildDump)
        local lines = SpellsAheadDB.dump and #SpellsAheadDB.dump or 0
        if not ok then
            SpellsAheadDB.dump = SpellsAheadDB.dump or {}
            tinsert(SpellsAheadDB.dump, "!! ERREUR: " .. tostring(err))
            say("capture interrompue a la ligne " .. lines .. " : |cffff5555" .. tostring(err) .. "|r")
        end
        say(format("capture : %d lignes. Tape maintenant |cffffff00/reload|r pour l ecrire sur le disque.",
            SpellsAheadDB.dump and #SpellsAheadDB.dump or 0))

    elseif cmd == "clear" then
        SpellsAheadDB.trainer = {}
        SpellsAheadDB.dump = nil
        say("cache entraineur et capture vides.")
    elseif cmd == "help" or cmd == "?" then
        PrintHelp()
    else
        toggle()
    end
end

--------------------------------------------------------------------------
-- Evenements
--------------------------------------------------------------------------

local ev = CreateFrame("Frame")

-- Le gestionnaire est branche AVANT toute inscription : un evenement inconnu
-- du client fait lever une erreur par RegisterEvent, ce qui interromprait le
-- reste du fichier. C est exactement ce qui a casse la version precedente.
ev:SetScript("OnEvent", function(self, event, arg1)
    if ns.ModuleOff("sorts", ev) then return end
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            SpellsAheadDB = SpellsAheadDB or {}
            SpellsAheadDB.trainer = SpellsAheadDB.trainer or {}
            migrateCache()
        end
        return
    end

    -- Entree en combat (juste avant le verrouillage) : notre page se ferme et
    -- l onglet passe en "indisponible". Rien d autre jusqu a la sortie.
    if event == "PLAYER_REGEN_DISABLED" then
        book.combat = true
        if book.panel then showPanel(false) else tabPaint() end
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        book.combat = false
        tabPaint()
        if not book.built then buildBookUI() end
        -- donnees changees pendant le combat : la fenetre /sa est remise a
        -- jour (la page, elle, est fermee et se reconstruit a l ouverture)
        if book.pending then
            book.pending = false
            if win and win:IsShown() then
                rebuild()
                refresh()
            end
        end
        return
    end

    if not SpellsAheadDB then return end

    if event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
        scrapeTrainer()
    end

    -- Le livre de sorts est charge a la demande : ce moment est une bonne
    -- occasion de tenter l integration.
    if not book.built then buildBookUI() end

    local needWin   = win and win:IsShown()
    local needPanel = book.panel and book.panel:IsShown()
    if needWin or needPanel then
        -- en combat : remis a PLAYER_REGEN_ENABLED
        if inCombat() then
            book.pending = true
            return
        end
        rebuild()
        if needWin then refresh() end
        if needPanel then
            book.dirty = true
            render()
        end
    end
end)

-- Inscription protegee : le nom des evenements varie selon les versions du
-- client (LEARNED_SPELL_IN_TAB est devenu LEARNED_SPELL_IN_SKILL_LINE sur les
-- clients modernes). On tente tout, on note ce qui est refuse.
for _, name in ipairs({
    "ADDON_LOADED",
    "PLAYER_LOGIN",
    "PLAYER_LEVEL_UP",
    "SPELLS_CHANGED",
    "LEARNED_SPELL_IN_TAB",
    "LEARNED_SPELL_IN_SKILL_LINE",
    "TRAINER_SHOW",
    "TRAINER_UPDATE",
    "TRAINER_CLOSED",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
}) do
    if not pcall(ev.RegisterEvent, ev, name) then
        failedEvents[#failedEvents + 1] = name
    end
end

--------------------------------------------------------------------------
-- Enregistrement dans CorpUI (menu des outils, /corp sorts)
--------------------------------------------------------------------------

ns.RegisterModule({
    command = "sorts",
    panelName = "SpellsAheadFrame",
    alias = "/sa",
    icon = "Interface\\Icons\\INV_Misc_Book_09",
    title = function() return ns.L.MOD_SPELLS end,
    desc = function() return ns.L.SPELLS_DESC end,
    Slash = function(input) SlashCmdList["SPELLSAHEAD"](input) end,
    Open = toggle,
})
