--[[--------------------------------------------------------------------------
    CorpUI - module Notes (notes de raid facon MRT)
      - Editeur (/corp note) : notes enregistrees (liste a gauche : creer,
        dupliquer, renommer, supprimer), texte multiligne, aide a la saisie
        (marqueurs, noms du groupe, couleurs), note personnelle a part
        (jamais envoyee, affichee sous la note partagee).
      - Fenetre d affichage de la note active : deplacable (poignee commune
        ou bandeau), redimensionnable, verrouillable, fond, police, taille
        et calque reglables.
      - Partage par la communication CorpUI (ns.Comm, ecrite a part) :
        "NOTE" envoie la note au groupe (chef ou assistant seulement) ; a la
        reception, la note n est acceptee que d un chef ou d un assistant du
        groupe actuel. "NOTEREQ" la redemande : son auteur la renvoie en prive.
    Codes rendus : {rt1}..{rt8}, {star}..{skull} (noms anglais, francais,
    allemands, espagnols et ceux du client), {tank} {healer} {dps},
    {spell:ID}, {p:Nom}texte{/p} (Nom seul le voit), {!p:Nom}texte{/p}
    (tous sauf Nom), couleurs |cffRRGGBB..|r. Noms du groupe en couleur de
    classe, le sien en or et sa ligne surlignee.
    Valeurs du jeu : issecretvalue d abord, sous pcall. Rien n est cree en
    combat (fenetres construites hors combat, afficher / masquer permis).
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local C = ns.COLORS

local issecret = issecretvalue or function() return false end

local M = {}
ns.Notes = M

local MAX_SEND = 12000     -- au-dela, envoi refuse (octets)
local MAX_RECV = 20000     -- au-dela, reception ignoree
local MAX_TITLE = 80
local SEND_GAP = 3         -- secondes entre deux envois
local REQ_GAP = 5          -- entre deux demandes / reponses
local POOL = 40            -- lignes d affichage creees d avance
local HEADER_H = 20
local LIST_ROWS = 14
local selCap, captureSel, wrapColor   -- selection de la zone de texte (voir captureSel)
local ME_COLOR = "|cffffd100"
local W8 = "Interface\\Buttons\\WHITE8X8"
local RT = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:0|t"
local ROLE_TEX = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:0:0:0:0:64:64:"
local ROLE_ICONS = {
    tank = ROLE_TEX .. "0:19:22:41|t",
    healer = ROLE_TEX .. "20:39:1:20|t",
    dps = ROLE_TEX .. "20:39:22:41|t",
}

local DEFAULTS = {
    autoShow = true, locked = false, showPersonal = true, onlyMine = false, highlightMe = true,
    outline = false, fontSize = 13, bgAlpha = 75, font = "ui", strata = "MEDIUM",
    w = 300, h = 240, shown = false, soloHide = true,
}

local db
local frame, scroll, child, rows = nil, nil, nil, {}
local lines = {}           -- lignes rendues a afficher
local panel                -- editeur
local previewing           -- { id, title, text } : apercu en cours
local moverForced          -- fenetre montree pour le placement
local pendingBuild, pendingLayout, openAfterCombat
local renderQueued
local lastSend, lastReq = -100, -100
local reqAnswered = {}     -- demandeur -> heure de la derniere reponse
local commReady = false

---------------------------------------------------------------------------
-- Outils
---------------------------------------------------------------------------

local function now() return GetTime() end

local function combat()
    local ok, v = pcall(InCombatLockdown)
    return ok and not issecret(v) and v and true or false
end

-- coupe sans laisser de caractere UTF-8 a moitie
local function cut(s, max)
    if #s <= max then return s end
    s = s:sub(1, max)
    return (s:gsub("[\192-\255][\128-\191]*$", ""))
end

local function shortName(full)
    full = tostring(full or "?")
    return full:match("^([^%-]+)") or full
end

local ACCENTS = {
    ["\195\160"] = "a", ["\195\161"] = "a", ["\195\162"] = "a", ["\195\164"] = "a",
    ["\195\128"] = "a", ["\195\129"] = "a", ["\195\130"] = "a", ["\195\132"] = "a",
    ["\195\167"] = "c", ["\195\135"] = "c",
    ["\195\168"] = "e", ["\195\169"] = "e", ["\195\170"] = "e", ["\195\171"] = "e",
    ["\195\136"] = "e", ["\195\137"] = "e", ["\195\138"] = "e", ["\195\139"] = "e",
    ["\195\172"] = "i", ["\195\173"] = "i", ["\195\174"] = "i", ["\195\175"] = "i",
    ["\195\140"] = "i", ["\195\141"] = "i", ["\195\142"] = "i", ["\195\143"] = "i",
    ["\195\178"] = "o", ["\195\179"] = "o", ["\195\180"] = "o", ["\195\182"] = "o",
    ["\195\146"] = "o", ["\195\147"] = "o", ["\195\148"] = "o", ["\195\150"] = "o",
    ["\195\185"] = "u", ["\195\186"] = "u", ["\195\187"] = "u", ["\195\188"] = "u",
    ["\195\153"] = "u", ["\195\154"] = "u", ["\195\155"] = "u", ["\195\156"] = "u",
    ["\195\177"] = "n", ["\195\145"] = "n", ["\195\159"] = "ss",
}

-- cle de code : minuscules, sans accents ni espaces
local function norm(s)
    s = s:gsub("\195[\128-\191]", function(c) return ACCENTS[c] end)
    return (s:lower():gsub("%s+", ""))
end

---------------------------------------------------------------------------
-- Sauvegarde : CorpUIDB.notes = { list, selected, chars[CharKey] =
-- { shared, personal }, reglages de la fenetre }
---------------------------------------------------------------------------

local function charData()
    local key = ns.CharKey()
    local c = db.chars[key]
    if type(c) ~= "table" then
        c = {}
        db.chars[key] = c
    end
    if type(c.personal) ~= "string" then c.personal = "" end
    if c.shared ~= nil and (type(c.shared) ~= "table" or type(c.shared.text) ~= "string") then c.shared = nil end
    return c
end

local function newId()
    local id = tonumber(db.nextId) or 1
    db.nextId = id + 1
    return id
end

local function initDB()
    local root = ns.InitRoot()
    if type(root.notes) ~= "table" then root.notes = {} end
    db = root.notes
    for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
    if type(db.list) ~= "table" then db.list = {} end
    if type(db.chars) ~= "table" then db.chars = {} end
    if type(db.pos) ~= "table" then db.pos = { point = "RIGHT", x = -60, y = 120 } end
    -- notes abimees (sauvegarde modifiee a la main) ecartees, numeros uniques
    local top = 0
    for i = #db.list, 1, -1 do
        local n = db.list[i]
        if type(n) ~= "table" or type(n.text) ~= "string" then
            table.remove(db.list, i)
        else
            if type(n.title) ~= "string" then n.title = "" end
            if type(n.id) == "number" then top = math.max(top, n.id) end
        end
    end
    db.nextId = math.max(tonumber(db.nextId) or 1, top + 1)
    for _, n in ipairs(db.list) do if type(n.id) ~= "number" then n.id = newId() end end
    if #db.list == 0 then
        table.insert(db.list, { id = newId(), title = string.format(L.NOTE_NEW_TITLE, 1), text = "" })
    end
    M.db = db
end

local function selectedNote()
    for i, n in ipairs(db.list) do
        if n.id == db.selected then return n, i end
    end
    local n = db.list[1]
    db.selected = n and n.id
    return n, 1
end

local function titleOf(t)
    if type(t) ~= "string" or not t:find("%S") then return L.NOTE_UNTITLED end
    return t
end

---------------------------------------------------------------------------
-- Groupe : noms, classes, chef et assistants (lus sans jamais toucher une
-- valeur secrete)
---------------------------------------------------------------------------

local function flag(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn, ...)
    if not ok or issecret(v) then return false end
    return v and true or false
end

local function safeName(unit)
    local ok, name, realm = pcall(UnitName, unit)
    if not ok or issecret(name) or type(name) ~= "string" or name == "" then return nil end
    if issecret(realm) or type(realm) ~= "string" or realm == "" then realm = nil end
    return name, realm
end

local function safeClass(unit)
    local ok, _, class = pcall(UnitClass, unit)
    if ok and not issecret(class) and type(class) == "string" then return class end
end

local function myRealm()
    local fn = GetNormalizedRealmName or GetRealmName
    if type(fn) ~= "function" then return nil end
    local ok, r = pcall(fn)
    if ok and not issecret(r) and type(r) == "string" and r ~= "" then return r end
end

local function normRealm(r) return (tostring(r or ""):gsub("[%s%-']", ""):lower()) end

local function splitFull(full)
    local name, realm = full:match("^([^%-]+)%-(.+)$")
    if name then return name, realm end
    return full, nil
end

local function inGroup() return flag(IsInGroup) end
local function inRaid() return flag(IsInRaid) end

local function groupUnits()
    local list = {}
    if inRaid() then
        local ok, n = pcall(GetNumGroupMembers)
        n = (ok and not issecret(n) and type(n) == "number") and n or 0
        for i = 1, math.min(n, 40) do list[#list + 1] = "raid" .. i end
    else
        list[1] = "player"
        if inGroup() then
            for i = 1, 4 do list[#list + 1] = "party" .. i end
        end
    end
    return list
end

local function isLeadOrAssist(unit)
    if flag(UnitIsGroupLeader, unit) then return true end
    if inRaid() and flag(UnitIsGroupAssistant, unit) then return true end
    -- repli (API absente) : rang dans le raid, 2 = chef, 1 = assistant
    if type(UnitIsGroupLeader) ~= "function" and type(GetRaidRosterInfo) == "function" then
        local idx = tonumber(unit:match("^raid(%d+)$") or "")
        if idx then
            local ok, _, rank = pcall(GetRaidRosterInfo, idx)
            if ok and not issecret(rank) and type(rank) == "number" and rank >= 1 then return true end
        end
    end
    return false
end

-- noms uniques regionaux ("Prenom Nom", voir ns.Names dans Core.lua)
local function regional() return ns.Names ~= nil and ns.Names.Regional() end

local function isMe(full)
    if regional() then return ns.Names.Sender(full) == ns.Names.Me() end
    local name, realm = splitFull(full)
    local me = safeName("player")
    if not me or name ~= me then return false end
    local mine = myRealm()
    return not realm or not mine or normRealm(realm) == normRealm(mine)
end

-- unite du groupe actuel qui correspond a "Nom-Royaume" (nil : absent)
local function unitOf(full)
    if not inGroup() then return nil end
    if regional() then
        local id = ns.Names.Sender(full)
        for _, unit in ipairs(groupUnits()) do
            if id and ns.Names.Unit(unit) == id then return unit end
        end
        return nil
    end
    local sName, sRealm = splitFull(full)
    local mine = myRealm()
    for _, unit in ipairs(groupUnits()) do
        local name, realm = safeName(unit)
        if name and name == sName then
            local r = realm or mine
            if not sRealm or not r or normRealm(r) == normRealm(sRealm) then return unit end
        end
    end
end

local function classHex(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if type(c) == "table" and type(c.r) == "number" then
        return string.format("|cff%02x%02x%02x", math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5),
            math.floor(c.b * 255 + 0.5))
    end
    return "|cffffffff"
end

-- membres connus pour le rendu : { list (plus longs d abord), byLower, me }
local function buildRoster()
    local r = { list = {}, byLower = {} }
    local myName = safeName("player")
    local function add(name, class)
        local low = name:lower()
        if r.byLower[low] then return end
        local m = { name = name, lower = low, hex = classHex(class), me = (name == myName) }
        r.byLower[low] = m
        r.list[#r.list + 1] = m
    end
    if myName then add(myName, safeClass("player")) end
    for _, unit in ipairs(groupUnits()) do
        local name = safeName(unit)
        if name then add(name, safeClass(unit)) end
    end
    table.sort(r.list, function(a, b) return #a.lower > #b.lower end)
    r.me = myName and myName:lower()
    return r
end

---------------------------------------------------------------------------
-- Rendu des codes
---------------------------------------------------------------------------

local MARKS = {
    star = 1, circle = 2, diamond = 3, triangle = 4, moon = 5, square = 6, cross = 7, x = 7, skull = 8,
    etoile = 1, cercle = 2, rond = 2, losange = 3, lune = 5, carre = 6, croix = 7, crane = 8,
    stern = 1, kreis = 2, diamant = 3, dreieck = 4, mond = 5, quadrat = 6, kreuz = 7, totenschadel = 8,
    estrella = 1, circulo = 2, diamante = 3, triangulo = 4, luna = 5, cuadrado = 6, cruz = 7, calavera = 8,
}
local ROLES = {
    tank = "tank", heal = "healer", healer = "healer", heals = "healer", soin = "healer", soigneur = "healer",
    dps = "dps", dd = "dps", damage = "dps", degats = "dps",
}

local markIndex
local function marks()
    if markIndex then return markIndex end
    markIndex = {}
    for k, v in pairs(MARKS) do markIndex[k] = v end
    -- noms du client (RAID_TARGET_1..8, dans la langue du jeu)
    for i = 1, 8 do
        markIndex["rt" .. i] = i
        local g = _G["RAID_TARGET_" .. i]
        if not issecret(g) and type(g) == "string" and g ~= "" then markIndex[norm(g)] = i end
    end
    return markIndex
end

local function spellIcon(id)
    local fn = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture
    if type(fn) ~= "function" or not id then return nil end
    local ok, tex = pcall(fn, id)
    if not ok or issecret(tex) then return nil end
    if type(tex) == "number" then return tostring(tex) end
    if type(tex) == "string" and tex ~= "" and not tex:find("[|:]") then return tex end
end

-- "{cle}" -> code d icone, nil : laisse tel quel
local function markerCode(key)
    local k = norm(key)
    local n = marks()[k]
    if n then return string.format(RT, n) end
    local role = ROLES[k]
    if role then return ROLE_ICONS[role] end
    local id = k:match("^spell:(%d+)$") or k:match("^icon:(%d+)$")
    if id then
        local tex = spellIcon(tonumber(id))
        if tex then return "|T" .. tex .. ":0|t" end
    end
    return nil
end

local function clampNum(s, lo, hi)
    local v = tonumber(s)
    if not v then return nil end
    return tostring(math.max(lo, math.min(hi, math.floor(v))))
end

-- texture |T...|t ou atlas |A...|a : chemin sur, tailles bornees (64)
local function safeTexture(kind, body)
    if body:find("|", 1, true) or #body > 300 then return nil end
    local parts = {}
    for p in (body .. ":"):gmatch("([^:]*):") do parts[#parts + 1] = p end
    local first = (kind == "A" and parts[1] == "") and 2 or 1
    local name = parts[first]
    if not name or name == "" or name:find("[^%w_\\/%.%-%s]") then return nil end
    for i = first + 1, #parts do
        local rel = i - first
        local v
        if rel <= 2 then v = clampNum(parts[i], 0, 64)
        elseif rel <= 4 then v = clampNum(parts[i], -64, 64)
        elseif tonumber(parts[i]) then v = parts[i] end
        if not v then return nil end
        parts[i] = v
    end
    return table.concat(parts, ":")
end

-- Codes d echappement : couleurs, textures de taille raisonnable et atlas
-- sont gardes ; tout autre "|" s affiche tel quel. Une saisie au clavier
-- double les "|" ("||cff...") : on les ramene comme MRT.
local function sanitize(s)
    s = s:gsub("||([cCrRTtAa])", "|%1")
    local out, i, n = {}, 1, #s
    while i <= n do
        local a = s:find("|", i, true)
        if not a then
            out[#out + 1] = s:sub(i)
            break
        end
        out[#out + 1] = s:sub(i, a - 1)
        local nx = s:sub(a + 1, a + 1)
        local hex = s:sub(a + 2, a + 9)
        if nx == "|" then
            out[#out + 1] = "||"
            i = a + 2
        elseif (nx == "c" or nx == "C") and #hex == 8 and hex:find("^%x+$") then
            out[#out + 1] = "|c" .. hex
            i = a + 10
        elseif nx == "r" or nx == "R" then
            out[#out + 1] = "|r"
            i = a + 2
        elseif nx == "H" then
            -- lien (objet, sort...) : seul son texte reste, sans le lien
            local b = s:find("|h", a + 2, true)
            local c = b and s:find("|h", b + 2, true)
            if c then
                out[#out + 1] = sanitize(s:sub(b + 2, c - 1))
                i = c + 2
            else
                out[#out + 1] = "||"
                i = a + 1
            end
        elseif nx == "T" or nx == "A" then
            local close = nx == "T" and "|t" or "|a"
            local b = s:find(close, a + 2, true)
            local body = b and safeTexture(nx, s:sub(a + 2, b - 1))
            if body then
                out[#out + 1] = "|" .. nx .. body .. close
                i = b + 2
            else
                out[#out + 1] = "||"
                i = a + 1
            end
        else
            out[#out + 1] = "||"
            i = a + 1
        end
    end
    return table.concat(out)
end
M.Sanitize = sanitize

-- ligne assainie -> morceaux : codes (couleur, fin, texture, atlas, "||")
-- et texte
local function tokens(line)
    local list, i, n = {}, 1, #line
    while i <= n do
        local a = line:find("|", i, true)
        if not a then
            list[#list + 1] = { t = line:sub(i) }
            break
        end
        if a > i then list[#list + 1] = { t = line:sub(i, a - 1) } end
        local nx = line:sub(a + 1, a + 1)
        local stop = a + 1
        if nx == "c" then
            stop = a + 9
        elseif nx == "T" or nx == "A" then
            stop = (line:find(nx == "T" and "|t" or "|a", a + 2, true) or (n - 1)) + 1
        end
        list[#list + 1] = { code = line:sub(a, stop), kind = nx }
        i = stop + 1
    end
    return list
end

local function wordByte(b)
    return b ~= nil and (b >= 128 or (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122))
end

-- noms du groupe en couleur de classe (le sien en or) dans un morceau de
-- texte ; dans une couleur choisie par l auteur, on ne recolore pas
local function colorNames(seg, roster, inColor, state)
    if seg == "" or #roster.list == 0 then return seg end
    local low = seg:lower()
    local out, last, i, n = {}, 1, 1, #seg
    while i <= n do
        local hit
        if wordByte(seg:byte(i)) and not wordByte(i > 1 and seg:byte(i - 1) or nil) then
            for _, m in ipairs(roster.list) do
                local len = #m.lower
                if low:sub(i, i + len - 1) == m.lower and not wordByte(seg:byte(i + len)) then
                    hit = m
                    break
                end
            end
        end
        if hit then
            local len = #hit.lower
            out[#out + 1] = seg:sub(last, i - 1)
            local word = seg:sub(i, i + len - 1)
            if hit.me then state.me = true end
            if inColor then
                out[#out + 1] = word
            else
                out[#out + 1] = (hit.me and ME_COLOR or hit.hex) .. word .. "|r"
            end
            i = i + len
            last = i
        else
            i = i + 1
        end
    end
    out[#out + 1] = seg:sub(last)
    return table.concat(out)
end

-- {p:Nom1, Nom2} : vrai si j y suis (royaume ignore)
local function forMe(who, me)
    if not me then return false end
    for tok in who:gmatch("[^,;%s]+") do
        local n = tok:match("^([^%-]+)") or tok
        if n:lower() == me then return true end
    end
    return false
end

-- premier mot d une ligne, codes et ponctuation de tete retires
local function leadingWord(line)
    local s = line
    for _ = 1, 20 do
        local before = s
        s = s:gsub("^%s+", ""):gsub("^{[^}]*}", ""):gsub("^|c%x%x%x%x%x%x%x%x", ""):gsub("^|r", "")
        s = s:gsub("^|T.-|t", ""):gsub("^|A.-|a", ""):gsub("^[%-%*>%.:#]+", "")
        if s == before then break end
    end
    return s:match("^([^%s:,;%.%-%(%)%[%]!%?|{]+)")
end

local function renderLine(raw, ctx)
    local line = sanitize(raw)
    if not line:find("%S") then return { text = "" } end
    local dim = false
    local function vis(neg, who, txt)
        local ok = forMe(who, ctx.meLower)
        if neg == "!" then ok = not ok end
        if ok then return txt end
        if ctx.preview then
            dim = true
            return "(" .. who .. ") " .. txt
        end
        return ""
    end
    line = line:gsub("{(!?)[pP]:([^{}]*)}(.-){/[pP]}", vis)
    line = line:gsub("{(!?)[pP]:([^{}]*)}(.*)$", vis)
    line = line:gsub("{/[pP]}", "")
    -- ligne entierement reservee a d autres : elle disparait
    if not line:find("%S") then return nil end
    if ctx.onlyMine then
        local first = leadingWord(line)
        local m = first and ctx.roster.byLower[first:lower()]
        if m and not m.me then
            if not ctx.preview then return nil end
            dim = true
        end
    end
    line = line:gsub("{([^{}]+)}", markerCode)
    local out, state = {}, { me = false }
    local inColor = ctx.carry ~= nil
    if ctx.carry then out[1] = ctx.carry end
    for _, tk in ipairs(tokens(line)) do
        if tk.code then
            out[#out + 1] = tk.code
            if tk.kind == "c" then
                inColor, ctx.carry = true, tk.code
            elseif tk.kind == "r" then
                inColor, ctx.carry = false, nil
            end
        else
            out[#out + 1] = colorNames(tk.t, ctx.roster, inColor, state)
        end
    end
    -- couleur laissee ouverte : elle continue a la ligne suivante
    if inColor then out[#out + 1] = "|r" end
    return { text = table.concat(out), me = state.me, dim = dim }
end

local function context(preview)
    local roster = buildRoster()
    return { roster = roster, meLower = roster.me, preview = preview and true or false,
             onlyMine = db and db.onlyMine and true or false }
end
M.Context = context

-- texte d une note -> lignes { text, me, dim }
function M.RenderText(text, ctx)
    ctx = ctx or context(false)
    ctx.carry = nil
    local out = {}
    text = tostring(text or ""):gsub("\r", "")
    for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
        local row = renderLine(raw, ctx)
        if row then out[#out + 1] = row end
    end
    while #out > 0 and out[#out].text == "" do out[#out] = nil end
    return out
end

-- titre : codes et marqueurs, sans couleurs de noms
local function renderInline(s)
    s = sanitize((tostring(s or ""):gsub("[\r\n]", " ")))
    return (s:gsub("{([^{}]+)}", markerCode))
end
M.RenderInline = renderInline

---------------------------------------------------------------------------
-- Fenetre d affichage
---------------------------------------------------------------------------

local function fontPath()
    local k = db.font
    if k == "game" then
        return (type(STANDARD_TEXT_FONT) == "string" and STANDARD_TEXT_FONT) or "Fonts\\FRIZQT__.TTF"
    end
    if k ~= "ui" and ns.FontList then
        for _, f in ipairs(ns.FontList()) do
            if f.key == k and f.regular then return ns.MEDIA .. "Fonts\\" .. f.regular end
        end
    end
    return (ns.FontFile and ns.FontFile("regular")) or (type(STANDARD_TEXT_FONT) == "string" and STANDARD_TEXT_FONT)
        or "Fonts\\FRIZQT__.TTF"
end

local function styleRow(r)
    local path = fontPath()
    local key = path .. "|" .. tostring(db.fontSize) .. "|" .. tostring(db.outline)
    if r.styleKey == key then return end
    r.styleKey = key
    local flags = db.outline and "OUTLINE" or ""
    if not pcall(r.fs.SetFont, r.fs, path, db.fontSize, flags) or not r.fs:GetFont() then
        pcall(r.fs.SetFont, r.fs, "Fonts\\FRIZQT__.TTF", db.fontSize, flags)
    end
    r.fs:SetShadowColor(0, 0, 0, db.outline and 0 or 0.9)
    r.fs:SetShadowOffset(1, -1)
end

local function makeRow()
    local r = {}
    -- surlignage des lignes ou figure mon nom : degrade d or, filet a gauche
    r.bg = child:CreateTexture(nil, "BACKGROUND")
    ns.UI.Gradient(r.bg, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.22, C.gold[1], C.gold[2], C.gold[3], 0.02)
    r.bar = child:CreateTexture(nil, "BORDER")
    r.bar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.9)
    r.bar:SetWidth(2)
    r.fs = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.fs:SetJustifyH("LEFT")
    r.fs:SetJustifyV("TOP")
    r.fs:SetWordWrap(true)
    pcall(r.fs.SetNonSpaceWrap, r.fs, true)
    r.bg:Hide()
    r.bar:Hide()
    r.fs:Hide()
    rows[#rows + 1] = r
    return r
end

local function scrollRange()
    if not scroll or not child then return 0 end
    return math.max(0, (child:GetHeight() or 0) - (scroll:GetHeight() or 0))
end

local function scrollTo(v)
    if not scroll then return end
    scroll:SetVerticalScroll(math.max(0, math.min(scrollRange(), v or 0)))
end

local function layout()
    if not frame then return end
    local w = math.max(40, (frame:GetWidth() or 200) - 14)
    child:SetWidth(w)
    local list = lines
    -- plus de lignes que la reserve : en combat on ne cree rien, le surplus
    -- rejoint la derniere ligne (reprise a la sortie du combat)
    if #list > #rows then
        if combat() then
            local merged = {}
            for i = 1, #rows - 1 do merged[i] = list[i] end
            local rest = {}
            for i = #rows, #list do rest[#rest + 1] = list[i].text end
            merged[#rows] = { text = table.concat(rest, "\n") }
            list = merged
            pendingLayout = true
        else
            while #rows < #list do makeRow() end
        end
    end
    local size = db.fontSize
    local y = 3
    for i, r in ipairs(rows) do
        local ln = list[i]
        if ln then
            styleRow(r)
            r.fs:SetWidth(w - 10)
            r.fs:SetText(ln.text)
            local h
            if ln.text == "" then
                h = math.floor(size * 0.6)
            else
                local ok, sh = pcall(r.fs.GetStringHeight, r.fs)
                h = (ok and not issecret(sh) and type(sh) == "number" and sh > 0) and sh or (size + 2)
            end
            h = math.ceil(h)
            r.fs:ClearAllPoints()
            r.fs:SetPoint("TOPLEFT", child, "TOPLEFT", 7, -y)
            r.fs:SetPoint("TOPRIGHT", child, "TOPRIGHT", -3, -y)
            r.fs:SetHeight(h)
            if ln.head then
                r.fs:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
            else
                r.fs:SetTextColor(1, 1, 1)
            end
            r.fs:SetAlpha(ln.dim and 0.45 or 1)
            r.fs:Show()
            local hl = ln.me and db.highlightMe and true or false
            if hl then
                r.bg:ClearAllPoints()
                r.bg:SetPoint("TOPLEFT", r.fs, "TOPLEFT", -6, 1)
                r.bg:SetPoint("BOTTOMRIGHT", r.fs, "BOTTOMRIGHT", 2, -1)
                r.bar:ClearAllPoints()
                r.bar:SetPoint("TOPLEFT", r.bg, "TOPLEFT")
                r.bar:SetPoint("BOTTOMLEFT", r.bg, "BOTTOMLEFT")
            end
            r.bg:SetShown(hl)
            r.bar:SetShown(hl)
            y = y + h + 2
        else
            r.fs:Hide()
            r.bg:Hide()
            r.bar:Hide()
        end
    end
    child:SetHeight(math.max(1, y))
    scrollTo(scroll:GetVerticalScroll() or 0)
end
M.Layout = layout

-- lignes a afficher : note partagee (ou apercu), puis la note personnelle
local function compose()
    local ctx = context(previewing ~= nil)
    local out = {}
    local c = charData()
    local note = previewing or c.shared
    if note then
        for _, r in ipairs(M.RenderText(note.text, ctx)) do out[#out + 1] = r end
    end
    if db.showPersonal and c.personal:find("%S") then
        if #out > 0 then out[#out + 1] = { text = "" } end
        out[#out + 1] = { text = L.NOTE_PERSONAL_HEAD, head = true }
        ctx.preview = false
        for _, r in ipairs(M.RenderText(c.personal, ctx)) do out[#out + 1] = r end
    end
    if #out == 0 then out[1] = { text = L.NOTE_EMPTY, dim = true } end
    return out, note
end

local function updateHeader(note)
    if previewing then
        frame.title:SetText(string.format(L.NOTE_PREVIEW_HEAD, renderInline(titleOf(previewing.title))))
        frame.sub:SetText("")
    elseif note then
        frame.title:SetText(renderInline(titleOf(note.title)))
        frame.sub:SetText(note.from and string.format(L.NOTE_FROM, shortName(note.from)) or "")
    else
        frame.title:SetText(L.MOD_NOTES)
        frame.sub:SetText("")
    end
end

local function applyLook()
    if not frame then return end
    local strata = db.strata
    if strata ~= "LOW" and strata ~= "MEDIUM" and strata ~= "HIGH" then strata = "MEDIUM" end
    frame:SetFrameStrata(strata)
    local a = math.max(0, math.min(100, tonumber(db.bgAlpha) or 75)) / 100
    frame:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], a)
    frame:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], math.min(1, a + 0.3))
    frame.headBg:SetAlpha(math.min(1, a + 0.25))
    frame.grip:SetShown(not db.locked)
    -- verrouillee : les clics traversent le corps (le bandeau et la molette restent)
    frame:EnableMouse(not db.locked)
end

local buildFrame

-- (re)dessine la fenetre ; construite hors combat seulement
function M.Render()
    if not db then return end
    if not frame then
        if combat() then
            pendingBuild = true
            return
        end
        buildFrame()
    end
    local out, note = compose()
    lines = out
    updateHeader(note)
    applyLook()
    layout()
end

local renderStale = false   -- fenetre cachee : recomposee a l affichage
local function queueRender()
    if frame and not frame:IsShown() then renderStale = true return end
    if renderQueued then return end
    renderQueued = true
    C_Timer.After(0.15, function()
        renderQueued = false
        M.Render()
    end)
end

-- fenetre voulue : ouverte par le joueur, et en groupe si "masquer hors
-- groupe" (sauf l apercu de l editeur) ; toujours avec les poignees
local function wanted()
    if ns.moversShown then return true end
    if not db.shown then return false end
    return not db.soloHide or previewing ~= nil or inGroup()
end

-- v : true / false / nil (bascule)
function M.Show(v)
    if not db then return end
    if v == nil then v = not (frame and frame:IsShown() and db.shown) end
    db.shown = v and true or false
    if not v then previewing = nil end
    if not frame and combat() then
        pendingBuild = true
        return
    end
    M.Render()
    frame:SetShown(wanted())
    if v and not frame:IsShown() then ns.Say(L.NOTE_SOLO_HIDDEN) end
    -- les textes ont leur taille au rendu suivant
    if db.shown then C_Timer.After(0, layout) end
end

-- apercu de la note de l editeur dans la fenetre (bascule)
function M.Preview(note)
    note = note or selectedNote()
    if not note then return end
    if previewing and previewing.id == note.id then
        previewing = nil
        M.Render()
        return
    end
    previewing = { id = note.id, title = note.title, text = note.text }
    M.Show(true)
end

function M.IsPreviewing() return previewing ~= nil end

local openEditor, showOptionsTab

local function frameMenu()
    return {
        { value = "lock", text = db.locked and L.NOTE_UNLOCK or L.NOTE_LOCK },
        { value = "editor", text = L.NOTE_OPEN_EDITOR },
        { value = "request", text = L.NOTE_REQUEST },
        { value = "options", text = L.NOTE_OPTIONS },
        { value = "hide", text = L.NOTE_HIDE },
        width = 180,
    }
end

local function doFrameMenu(v)
    if v == "lock" then
        db.locked = not db.locked
        applyLook()
        if panel and panel.form then panel.form:Refresh() end
    elseif v == "editor" then
        openEditor()
    elseif v == "request" then
        M.Request()
    elseif v == "options" then
        openEditor()
        if showOptionsTab then showOptionsTab(true) end
    elseif v == "hide" then
        M.Show(false)
    end
end

buildFrame = function()
    if frame then return end
    local f = CreateFrame("Frame", "CorpUINoteFrame", UIParent, "BackdropTemplate")
    frame = f
    f:SetSize(math.max(160, tonumber(db.w) or 300), math.max(80, tonumber(db.h) or 240))
    ns.ApplyPos(f, db.pos)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(160, 80, 900, 900)
    elseif f.SetMinResize then
        f:SetMinResize(160, 80)
    end
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    ns.UI.SetBackdrop(f, 0.75)
    ns.UI.Shadow(f, 3)

    -- bandeau : titre, auteur, menu, fermeture ; on le saisit pour deplacer
    local head = CreateFrame("Frame", nil, f)
    head:SetPoint("TOPLEFT", 1, -1)
    head:SetPoint("TOPRIGHT", -1, -1)
    head:SetHeight(HEADER_H)
    head:EnableMouse(true)
    f.headBg = head:CreateTexture(nil, "BACKGROUND")
    f.headBg:SetAllPoints()
    ns.UI.Gradient(f.headBg, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.35, C.violet[1], C.violet[2], C.violet[3], 0.05)
    local line = head:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    ns.NoSnap(line)
    ns.UI.Gradient(line, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.7, C.gold[1], C.gold[2], C.gold[3], 0)

    local close = CreateFrame("Button", nil, head)
    close:SetSize(16, 16)
    close:SetPoint("RIGHT", -3, 0)
    local x = close:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(x, 13)
    x:SetPoint("CENTER", 0, 1)
    x:SetText("×")
    x:SetTextColor(C.text[1], C.text[2], C.text[3])
    close:SetScript("OnEnter", function() x:SetTextColor(1, 0.3, 0.3) end)
    close:SetScript("OnLeave", function() x:SetTextColor(C.text[1], C.text[2], C.text[3]) end)
    close:SetScript("OnClick", function() M.Show(false) end)

    local gear = CreateFrame("Button", nil, head)
    gear:SetSize(13, 13)
    gear:SetPoint("RIGHT", close, "LEFT", -4, 0)
    gear.tex = gear:CreateTexture(nil, "ARTWORK")
    gear.tex:SetAllPoints()
    gear.tex:SetTexture(ns.MEDIA .. "meter_options")
    gear.tex:SetVertexColor(C.gold[1], C.gold[2], C.gold[3])
    gear:SetScript("OnEnter", function(self) self.tex:SetVertexColor(1, 1, 1) end)
    gear:SetScript("OnLeave", function(self) self.tex:SetVertexColor(C.gold[1], C.gold[2], C.gold[3]) end)
    gear:SetScript("OnClick", function(self)
        ns.UI.OpenMenu(self, frameMenu, function() return nil end, doFrameMenu)
    end)

    f.title = head:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(f.title, 11)
    f.title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    f.title:SetJustifyH("LEFT")
    f.title:SetWordWrap(false)
    f.title:SetPoint("LEFT", 6, 0)
    f.sub = head:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.sub:SetJustifyH("RIGHT")
    f.sub:SetWordWrap(false)
    f.sub:SetPoint("RIGHT", gear, "LEFT", -6, 0)
    f.title:SetPoint("RIGHT", f.sub, "LEFT", -6, 0)

    -- deplacement par le bandeau (fenetre deverrouillee)
    head:RegisterForDrag("LeftButton")
    head:SetScript("OnDragStart", function() if not db.locked then f:StartMoving() end end)
    head:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        ns.PinTop(f, db.pos, true)
    end)
    head:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then ns.UI.OpenMenu(gear, frameMenu, function() return nil end, doFrameMenu) end
    end)

    -- corps : lignes dans une feuille qui defile a la molette
    scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", 3, -HEADER_H - 3)
    scroll:SetPoint("BOTTOMRIGHT", -3, 4)
    child = CreateFrame("Frame", nil, scroll)
    child:SetSize(200, 10)
    scroll:SetScrollChild(child)
    f:SetScript("OnMouseWheel", function(_, d) scrollTo((scroll:GetVerticalScroll() or 0) - d * 30) end)

    -- poignee de taille (fenetre deverrouillee)
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(12, 12)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel(f:GetFrameLevel() + 10)
    local gt = grip:CreateTexture(nil, "OVERLAY")
    gt:SetAllPoints()
    gt:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    gt:SetVertexColor(C.gold[1], C.gold[2], C.gold[3])
    grip:SetScript("OnMouseDown", function() if not db.locked then f:StartSizing("BOTTOMRIGHT") end end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        db.w, db.h = math.floor((f:GetWidth() or 300) + 0.5), math.floor((f:GetHeight() or 240) + 0.5)
        ns.PinTop(f, db.pos, true)
        layout()
    end)
    f.grip = grip

    f:SetScript("OnSizeChanged", function() layout() end)
    f:SetScript("OnShow", function(self)
        -- position tenue par le coin haut-gauche : le haut reste fixe
        ns.PinTop(self, db.pos)
        if renderStale then
            renderStale = false
            M.Render()
        end
        layout()
    end)
    f:SetScript("OnHide", function() if not db.shown then previewing = nil end end)

    for _ = 1, POOL do makeRow() end
    -- poignee commune (Deverrouiller l interface, onglet General)
    f.mover = ns.UI.Mover(f, db.pos, L.MOD_NOTES)
    f:Hide()
end

-- placement : la fenetre se montre avec les poignees, puis reprend son etat
ns.Listen(function()
    if not frame or not db then return end
    if ns.moversShown then
        if not frame:IsShown() then
            moverForced = true
            frame:Show()
        end
    elseif moverForced then
        moverForced = false
        frame:SetShown(wanted())
    end
end)

---------------------------------------------------------------------------
-- Partage
---------------------------------------------------------------------------

function M.Encode(title, text)
    title = cut((tostring(title or ""):gsub("[\r\n]", " ")), MAX_TITLE)
    text = (tostring(text or ""):gsub("\r", ""))
    return title .. "\n" .. text
end

function M.Decode(payload)
    local title, text = payload:match("^([^\n]*)\n(.*)$")
    if not title then title, text = payload, "" end
    return cut(title, MAX_TITLE), text
end

local function comm()
    local c = ns.Comm
    if type(c) == "table" and type(c.Send) == "function" then return c end
end

local function commSend(kind, payload, channel, target)
    local c = comm()
    if not c then
        ns.Say(L.NOTE_NO_COMM)
        return false
    end
    local ok, res = pcall(c.Send, kind, payload, channel, target)
    if not ok or res == false then
        ns.Say(L.NOTE_NO_COMM)
        return false
    end
    return true
end

-- vrai si je peux envoyer ; sinon faux et la raison
function M.CanSend()
    if not inGroup() then return false, L.NOTE_NO_GROUP end
    if not isLeadOrAssist("player") then return false, L.NOTE_NOT_LEADER end
    return true
end

local refreshStatus

function M.SendNote(note)
    if not db then return false end
    note = note or selectedNote()
    if not note then return false end
    local can, why = M.CanSend()
    if not can then
        ns.Say(why)
        return false
    end
    if not comm() then
        ns.Say(L.NOTE_NO_COMM)
        return false
    end
    local payload = M.Encode(note.title, note.text)
    if #payload > MAX_SEND then
        ns.Say(string.format(L.NOTE_TOO_LONG, #payload, MAX_SEND))
        return false
    end
    if now() - lastSend < SEND_GAP then
        ns.Say(L.NOTE_WAIT)
        return false
    end
    if not commSend("NOTE", payload, "GROUP") then return false end
    lastSend = now()
    local title, text = M.Decode(payload)
    charData().shared = { title = title, text = text, from = ns.CharKey(), at = time(), mine = true }
    previewing = nil
    ns.Say(string.format(L.NOTE_SENT, renderInline(titleOf(title))))
    if db.autoShow then M.Show(true) else M.Render() end
    if refreshStatus then refreshStatus() end
    return true
end

function M.Request()
    if not db then return false end
    if not inGroup() then
        ns.Say(L.NOTE_NO_GROUP)
        return false
    end
    if now() - lastReq < REQ_GAP then
        ns.Say(L.NOTE_WAIT)
        return false
    end
    if not commSend("NOTEREQ", "1", "GROUP") then return false end
    lastReq = now()
    ns.Say(L.NOTE_REQUESTED)
    return true
end

local function validSender(sender)
    if issecret(sender) or type(sender) ~= "string" or sender == "" then return false end
    return true
end

-- reception d une note : acceptee seulement d un chef ou d un assistant du
-- groupe actuel ; elle remplace la note partagee et s affiche
function M.OnNote(sender, payload)
    if not db or not validSender(sender) then return false end
    if issecret(payload) or type(payload) ~= "string" or #payload > MAX_RECV then return false end
    if isMe(sender) then return false end
    local unit = unitOf(sender)
    if not unit or not isLeadOrAssist(unit) then return false end
    local title, text = M.Decode(payload)
    charData().shared = { title = title, text = text, from = sender, at = time() }
    previewing = nil
    ns.Say(string.format(L.NOTE_RECEIVED, shortName(sender)))
    if db.autoShow then M.Show(true) else M.Render() end
    if refreshStatus then refreshStatus() end
    return true
end

-- demande de la note : son auteur la renvoie en prive au demandeur (le
-- chef repond a la place d un auteur parti ou qui n est plus assistant)
function M.OnRequest(sender)
    if not db or not validSender(sender) or isMe(sender) then return false end
    if not unitOf(sender) or not isLeadOrAssist("player") then return false end
    local s = charData().shared
    if not s then return false end
    if not s.mine then
        local author = s.from and not isMe(s.from) and unitOf(s.from)
        if not flag(UnitIsGroupLeader, "player") or (author and isLeadOrAssist(author)) then return false end
    end
    local t = now()
    if reqAnswered[sender] and t - reqAnswered[sender] < REQ_GAP then return false end
    reqAnswered[sender] = t
    return commSend("NOTE", M.Encode(s.title, s.text), "WHISPER", sender)
end

local function hookComm()
    if commReady then return true end
    local c = ns.Comm
    if type(c) ~= "table" or type(c.On) ~= "function" then return false end
    local ok1 = pcall(c.On, "NOTE", function(sender, payload) M.OnNote(sender, payload) end)
    local ok2 = pcall(c.On, "NOTEREQ", function(sender, payload) M.OnRequest(sender, payload) end)
    commReady = ok1 and ok2
    return commReady
end
M.HookComm = hookComm

---------------------------------------------------------------------------
-- Editeur
---------------------------------------------------------------------------

local PW, PH = 690, 492
local LEFT_W = 150
local RIGHT_X = LEFT_W + 14
local RIGHT_W = PW - RIGHT_X - 6
local lastEdit
local listOffset = 0

local function noteById(id)
    for _, n in ipairs(db.list) do if n.id == id then return n end end
end

-- zone de texte multiligne qui defile (molette, curseur toujours visible)
local function scrollEdit(parent, w, h, onChange)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(w, h)
    ns.UI.Skin(box, 0.75)
    local sf = CreateFrame("ScrollFrame", nil, box)
    sf:SetPoint("TOPLEFT", 6, -5)
    sf:SetPoint("BOTTOMRIGHT", -14, 5)
    local e = CreateFrame("EditBox", nil, sf)
    e:SetMultiLine(true)
    e:SetAutoFocus(false)
    e:SetFontObject("GameFontHighlight")
    e:SetWidth(w - 22)
    e:SetHeight(h - 10)
    e:SetMaxLetters(MAX_RECV)
    sf:SetScrollChild(e)
    -- piste fine et curseur de defilement
    local track = box:CreateTexture(nil, "ARTWORK")
    track:SetPoint("TOPRIGHT", -4, -4)
    track:SetPoint("BOTTOMRIGHT", -4, 4)
    track:SetWidth(4)
    track:SetColorTexture(0, 0, 0, 0.45)
    local thumb = box:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(4)
    thumb:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.9)
    thumb:Hide()
    local function range()
        local r = sf:GetVerticalScrollRange()
        return (type(r) == "number" and r > 0) and r or 0
    end
    local function sync()
        local r = range()
        local view = sf:GetHeight() or 0
        local trackH = (box:GetHeight() or h) - 8
        if r <= 0 or view <= 0 or trackH <= 0 then thumb:Hide() return end
        local tH = math.max(16, trackH * view / (view + r))
        thumb:SetHeight(tH)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", box, "TOPRIGHT", -4, -4 - (trackH - tH) * (sf:GetVerticalScroll() or 0) / r)
        thumb:Show()
    end
    local function setScroll(v)
        sf:SetVerticalScroll(math.max(0, math.min(range(), v or 0)))
        sync()
    end
    sf:SetScript("OnScrollRangeChanged", sync)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, d) setScroll((self:GetVerticalScroll() or 0) - d * 40) end)
    -- un clic dans le vide donne la main a la saisie
    sf:EnableMouse(true)
    sf:SetScript("OnMouseDown", function() e:SetFocus() end)
    -- curseur visible : traite a l image suivante (la hauteur du texte suit)
    -- Suivi de la selection (le jeu ne la donne pas et l efface des qu on
    -- clique ailleurs) : ancre = position a l appui de la souris, ou avant
    -- Maj + fleche ; selection = de l ancre au curseur pendant un glisser
    -- ou avec Maj ; Ctrl+A = tout. Retenue dans cuiSel avec le texte du
    -- moment (une frappe l annule).
    local MODKEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true }
    local function cursorPos()
        local ok, p = pcall(e.GetCursorPosition, e)
        if ok and type(p) == "number" then return p end
    end
    e:HookScript("OnMouseDown", function(self)
        self.cuiPendingAnchor = true
        self.cuiDragging = true
    end)
    e:HookScript("OnMouseUp", function(self) self.cuiDragging = false end)
    e:HookScript("OnKeyDown", function(self, key)
        if key == "A" and IsControlKeyDown and IsControlKeyDown() then
            local t = self:GetText() or ""
            self.cuiSel = { start = 0, stop = #t, text = t }
        elseif IsShiftKeyDown and IsShiftKeyDown() then
            -- debut d une selection au clavier : ancre au curseur actuel
            if not self.cuiSel then self.cuiAnchor = cursorPos() end
        elseif not MODKEYS[key] and not (IsControlKeyDown and IsControlKeyDown()) then
            -- fleche, frappe... sans Maj : la selection est abandonnee
            self.cuiSel = nil
        end
    end)
    e:SetScript("OnCursorChanged", function(self, _, y, _, ch)
        self.cuiCursorY, self.cuiCursorH = -(y or 0), ch or 0
        self.cuiFollow = true
        if self.cuiSilent then return end
        -- zone sans le focus (clic sur Couleur...) : la selection retenue reste
        local okF, hasF = pcall(self.HasFocus, self)
        if okF and hasF == false then return end
        local p = cursorPos()
        if not p then return end
        local t = self:GetText() or ""
        local mouseHeld = IsMouseButtonDown and IsMouseButtonDown("LeftButton")
        if self.cuiPendingAnchor then
            self.cuiPendingAnchor = false
            if IsShiftKeyDown and IsShiftKeyDown() and self.cuiAnchor then
                -- Maj + clic : etend depuis l ancre
            else
                self.cuiAnchor = p
                self.cuiSel = nil
                return
            end
        end
        local a = self.cuiAnchor
        if a and ((self.cuiDragging and mouseHeld) or (IsShiftKeyDown and IsShiftKeyDown())) then
            if a ~= p then
                self.cuiSel = { start = math.min(a, p), stop = math.max(a, p), text = t }
            else
                self.cuiSel = nil
            end
        elseif not (self.cuiDragging and mouseHeld) then
            -- simple deplacement du curseur : nouvelle ancre. La selection
            -- retenue n est pas effacee ici (le jeu bouge le curseur apres un
            -- clic hors de la zone) : clic dans la zone, touche ou frappe le font.
            self.cuiAnchor = p
        end
    end)
    box:SetScript("OnUpdate", function()
        if not e.cuiFollow then return end
        e.cuiFollow = false
        local top, bottom = e.cuiCursorY or 0, (e.cuiCursorY or 0) + (e.cuiCursorH or 0)
        local cur, view = sf:GetVerticalScroll() or 0, sf:GetHeight() or 0
        if top < cur then
            setScroll(top)
        elseif view > 0 and bottom > cur + view then
            setScroll(bottom - view)
        end
    end)
    e:SetScript("OnTextChanged", function(self, user)
        if user and onChange then onChange(self:GetText() or "") end
        sync()
    end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEditFocusGained", function(self)
        lastEdit = self
        box.cuiBorder:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    end)
    e:SetScript("OnEditFocusLost", function(self)
        box.cuiBorder:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
    end)
    box:SetScript("OnSizeChanged", function(_, bw) if bw and bw > 30 then e:SetWidth(bw - 22) end end)
    e.cuiOnChange = onChange
    return box, e
end

-- Selection de la zone de texte : le jeu ne la donne pas, et un clic sur
-- un bouton (Couleur) la fait perdre. A la perte du focus, un caractere
-- temoin insere par Insert remplace la selection : sa place et la longueur
-- disparue donnent debut et fin ; le texte est aussitot remis, la
-- selection resurlignee et le curseur replace.
local MARK = string.char(1)
selCap = nil

captureSel = function(e)
    selCap = nil
    e.cuiSilent = true
    local ok = pcall(function()
    local okT, old = pcall(e.GetText, e)
    if not okT or type(old) ~= "string" or issecret(old) or old:find(MARK, 1, true) then return end
    if not pcall(e.Insert, e, MARK) then return end
    local okN, new = pcall(e.GetText, e)
    if not okN or type(new) ~= "string" or issecret(new) then return end
    local p = new:find(MARK, 1, true)
    if new ~= old then pcall(e.SetText, e, old) end
    if not p then return end
    local start = p - 1
    local stop = start + (#old - (#new - #MARK))
    if stop < start then stop = start end
    pcall(e.SetCursorPosition, e, stop)
    if stop > start then pcall(e.HighlightText, e, start, stop) end
    selCap = { e = e, start = start, stop = stop, text = old }
    end)
    e.cuiSilent = false
end

-- texte de la zone apres une insertion par bouton (Insert ne dit pas
-- toujours "saisie utilisateur")
local function saveFrom(e)
    if e and e.cuiOnChange then e.cuiOnChange(e:GetText() or "") end
end

local function insert(str, back)
    if not panel then return end
    local e = lastEdit or panel.mainEdit
    -- curseur la ou il etait avant la perte du focus
    local s = selCap
    selCap = nil
    e:SetFocus()
    if s and s.e == e and e:GetText() == s.text then pcall(e.SetCursorPosition, e, s.start) end
    e:Insert(str)
    if back and back > 0 then
        local ok, pos = pcall(e.GetCursorPosition, e)
        if ok and type(pos) == "number" and pos >= back then pcall(e.SetCursorPosition, e, pos - back) end
    end
    saveFrom(e)
end

-- couleur : entoure le texte selectionne avant le clic, sinon insere le
-- code vide au curseur
wrapColor = function(hex)
    if not panel then return end
    local e = lastEdit or panel.mainEdit
    -- selection suivie pendant la saisie (cuiSel), sinon releve
    local s
    local txt0 = e:GetText() or ""
    if e.cuiSel and e.cuiSel.text == txt0 and e.cuiSel.stop > e.cuiSel.start then
        s = { e = e, start = e.cuiSel.start, stop = e.cuiSel.stop, text = txt0 }
    else
        if not (selCap and selCap.e == e) then captureSel(e) end
        s = selCap
    end
    local txt = e:GetText() or ""
    if s and s.e == e and s.stop > s.start and txt == s.text then
        selCap = nil
        e.cuiSel = nil
        local open, close = "|cff" .. hex, "|r"
        e:SetFocus()
        e:SetText(txt:sub(1, s.start) .. open .. txt:sub(s.start + 1, s.stop) .. close .. txt:sub(s.stop + 1))
        pcall(e.SetCursorPosition, e, s.stop + #open + #close)
        saveFrom(e)
        return
    end
    insert("|cff" .. hex .. "|r", 2)
end

local function refreshList()
    if not panel then return end
    local rowsL = panel.listRows
    listOffset = math.max(0, math.min(listOffset, #db.list - LIST_ROWS))
    for i = 1, LIST_ROWS do
        local row = rowsL[i]
        local n = db.list[i + listOffset]
        if n then
            row.note = n
            row.text:SetText(renderInline(titleOf(n.title)))
            local on = n.id == db.selected
            row.sel:SetShown(on)
            row.bar:SetShown(on)
            local c = on and C.gold or C.text
            row.text:SetTextColor(c[1], c[2], c[3])
            row:Show()
        else
            row.note = nil
            row:Hide()
        end
    end
end

refreshStatus = function()
    if not panel then return end
    local s = charData().shared
    if s then
        panel.status:SetText(string.format(L.NOTE_ACTIVE, renderInline(titleOf(s.title)), shortName(s.from),
            ns.FormatAgo(s.at)))
    else
        panel.status:SetText(L.NOTE_ACTIVE_NONE)
    end
    local n = selectedNote()
    local size = n and #M.Encode(n.title, n.text) or 0
    panel.count:SetText(string.format("%s%d|r / %d", size > MAX_SEND and "|cffff4040" or "|cff9a93aa", size, MAX_SEND))
end

-- note choisie -> champs de l editeur
local function loadSelected(force)
    if not panel then return end
    local n = selectedNote()
    if not n then return end
    if force or not panel.titleBox:HasFocus() then panel.titleBox:SetText(n.title) end
    if force or not panel.mainEdit:HasFocus() then panel.mainEdit:SetText(n.text) end
    if force or not panel.personalEdit:HasFocus() then panel.personalEdit:SetText(charData().personal) end
end

function M.RefreshEditor(force)
    if not panel then return end
    refreshList()
    loadSelected(force)
    refreshStatus()
end

function M.Select(id)
    if not noteById(id) then return end
    db.selected = id
    M.RefreshEditor(true)
end

function M.NewNote()
    local n = { id = newId(), title = string.format(L.NOTE_NEW_TITLE, #db.list + 1), text = "" }
    table.insert(db.list, n)
    db.selected = n.id
    listOffset = #db.list
    M.RefreshEditor(true)
    return n
end

function M.Duplicate()
    local cur, i = selectedNote()
    if not cur then return end
    local n = { id = newId(), title = cut(cur.title .. L.NOTE_COPY_SUFFIX, MAX_TITLE), text = cur.text }
    table.insert(db.list, i + 1, n)
    db.selected = n.id
    M.RefreshEditor(true)
    return n
end

function M.Delete()
    local cur, i = selectedNote()
    if not cur then return end
    table.remove(db.list, i)
    if previewing and previewing.id == cur.id then previewing = nil queueRender() end
    if #db.list == 0 then
        table.insert(db.list, { id = newId(), title = string.format(L.NOTE_NEW_TITLE, 1), text = "" })
    end
    db.selected = db.list[math.min(i, #db.list)].id
    M.RefreshEditor(true)
end

function M.Rename(title)
    local n = selectedNote()
    if not n then return end
    n.title = cut((tostring(title or ""):gsub("[\r\n]", " ")), MAX_TITLE)
    if previewing and previewing.id == n.id then
        previewing.title = n.title
        queueRender()
    end
    refreshList()
    refreshStatus()
end

function M.SetText(text)
    local n = selectedNote()
    if not n then return end
    n.text = tostring(text or "")
    if previewing and previewing.id == n.id then
        previewing.text = n.text
        queueRender()
    end
    refreshStatus()
end

function M.SetPersonal(text)
    charData().personal = tostring(text or "")
    queueRender()
end

-- la note recue rejoint les notes enregistrees (pour la reprendre)
function M.ImportShared()
    local s = charData().shared
    if not s then
        ns.Say(L.NOTE_NOTHING_TO_IMPORT)
        return nil
    end
    local n = { id = newId(), title = cut(titleOf(s.title), MAX_TITLE), text = s.text }
    table.insert(db.list, n)
    db.selected = n.id
    listOffset = #db.list
    M.RefreshEditor(true)
    ns.Say(L.NOTE_IMPORTED)
    return n
end

-- choix d un membre du groupe : une colonne par groupe de raid
local picker
local function pickerMembers()
    local out = {}
    local raid = inRaid()
    for i, unit in ipairs(groupUnits()) do
        local name = safeName(unit)
        if name then
            local grp = 1
            if raid and type(GetRaidRosterInfo) == "function" then
                local ok, _, _, sub = pcall(GetRaidRosterInfo, i)
                if ok and not issecret(sub) and type(sub) == "number" then grp = sub end
            end
            out[#out + 1] = { name = name, class = safeClass(unit), group = grp }
        end
    end
    return out
end

local function openPicker(owner, onPick)
    if not picker then
        if combat() then
            ns.Say(L.COMBAT_BLOCKED)
            return
        end
        picker = CreateFrame("Frame", "CorpUINotePicker", UIParent, "BackdropTemplate")
        picker:SetFrameStrata("FULLSCREEN_DIALOG")
        picker:SetClampedToScreen(true)
        ns.UI.SetBackdrop(picker, 0.98)
        picker.btns = {}
        for i = 1, 40 do
            local b = CreateFrame("Button", nil, picker)
            b:SetSize(96, 18)
            b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            b.text:SetPoint("LEFT", 4, 0)
            b.text:SetPoint("RIGHT", -2, 0)
            b.text:SetJustifyH("LEFT")
            b.text:SetWordWrap(false)
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            ns.UI.Gradient(hl, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.4, C.violet[1], C.violet[2], C.violet[3], 0.05)
            b:SetScript("OnClick", function(self)
                picker:Hide()
                if picker.onPick and self.name then picker.onPick(self.name) end
            end)
            b:Hide()
            picker.btns[i] = b
        end
        pcall(picker.RegisterEvent, picker, "GLOBAL_MOUSE_DOWN")
        picker:SetScript("OnEvent", function(self)
            if ns.ModuleOff("note", picker) then return end
            if self:IsShown() and not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then
                self:Hide()
            end
        end)
        picker:Hide()
    end
    if picker:IsShown() and picker.owner == owner then
        picker:Hide()
        return
    end
    picker.owner, picker.onPick = owner, onPick
    local members = pickerMembers()
    local cols, order = {}, {}
    for _, m in ipairs(members) do
        if not cols[m.group] then
            cols[m.group] = {}
            order[#order + 1] = m.group
        end
        table.insert(cols[m.group], m)
    end
    table.sort(order)
    local used, maxRows = 0, 1
    for ci, g in ipairs(order) do
        for ri, m in ipairs(cols[g]) do
            used = used + 1
            local b = picker.btns[used]
            if b then
                b.name = m.name
                b.text:SetText(classHex(m.class) .. m.name .. "|r")
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", picker, "TOPLEFT", 4 + (ci - 1) * 98, -4 - (ri - 1) * 20)
                b:Show()
            end
            maxRows = math.max(maxRows, ri)
        end
    end
    for i = used + 1, #picker.btns do picker.btns[i]:Hide() end
    picker:SetSize(math.max(1, #order) * 98 + 6, maxRows * 20 + 8)
    picker:ClearAllPoints()
    picker:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    picker:Show()
end

local BASIC_COLORS = { "ff4040", "ff9933", "ffd100", "40ff40", "40e0ff", "4080ff", "c070ff", "ff70c0", "ffffff", "999999" }
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local function swatch(hex)
    local r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
    return string.format("|T%s:12:28:0:0:8:8:0:8:0:8:%d:%d:%d|t", W8, r, g, b)
end

local function colorOptions()
    local list = {}
    for _, hex in ipairs(BASIC_COLORS) do
        list[#list + 1] = { value = hex, text = swatch(hex) .. "  |cff" .. hex .. hex .. "|r" }
    end
    list[#list + 1] = { title = true, value = "@title", text = L.NOTE_CLASS_COLORS }
    for _, class in ipairs(CLASSES) do
        local hex = classHex(class):sub(5)
        local names = LOCALIZED_CLASS_NAMES_MALE
        local name = (type(names) == "table" and type(names[class]) == "string") and names[class] or class
        list[#list + 1] = { value = hex, text = swatch(hex) .. "  |cff" .. hex .. name .. "|r" }
    end
    list.width = 170
    return list
end

local function tip(owner, title, text)
    local t = ns.Tooltip(owner, "ANCHOR_TOP")
    t:AddLine(title)
    if text then t:AddLine(text, 1, 1, 1, true) end
    t:Show()
end

local function withTip(b, title, text)
    b:HookScript("OnEnter", function(self) tip(self, title, text) end)
    b:HookScript("OnLeave", ns.HideTooltip)
end

local function buildEditor()
    panel = ns.UI.Window("CorpUINotes", ns.TITLE .. " - " .. L.MOD_NOTES, nil, PW, PH)
    panel.titleReserve = 190

    -- deux vues : editeur et reglages de la fenetre
    local ed = CreateFrame("Frame", nil, panel)
    ed:SetPoint("TOPLEFT", 0, -36)
    ed:SetPoint("BOTTOMRIGHT", 0, 0)
    local opt = CreateFrame("Frame", nil, panel)
    opt:SetPoint("TOPLEFT", 0, -36)
    opt:SetPoint("BOTTOMRIGHT", 0, 0)
    opt:Hide()
    panel.edView, panel.optView = ed, opt

    local tabOpt, tabEd
    local function syncTabs()
        local o = opt:IsShown()
        local a, b = o and C.text or C.gold, o and C.gold or C.text
        tabEd.cuiText:SetTextColor(a[1], a[2], a[3])
        tabOpt.cuiText:SetTextColor(b[1], b[2], b[3])
    end
    showOptionsTab = function(on)
        if not panel then return end
        opt:SetShown(on and true or false)
        ed:SetShown(not on)
        if on and panel.form then panel.form:Refresh() end
        syncTabs()
    end
    tabOpt = ns.UI.Button(panel, L.NOTE_TAB_DISPLAY, 86, function() showOptionsTab(true) end)
    tabOpt:SetSize(86, 20)
    tabOpt:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -6)
    tabEd = ns.UI.Button(panel, L.NOTE_TAB_EDITOR, 86, function() showOptionsTab(false) end)
    tabEd:SetSize(86, 20)
    tabEd:SetPoint("RIGHT", tabOpt, "LEFT", -4, 0)

    -- liste des notes
    local lh = ed:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lh:SetPoint("TOPLEFT", ed, "TOPLEFT", 6, 0)
    lh:SetSize(LEFT_W, 14)
    lh:SetJustifyH("LEFT")
    lh:SetText(L.NOTE_LIST)
    local listBox = CreateFrame("Frame", nil, ed)
    listBox:SetSize(LEFT_W, LIST_ROWS * 20 + 6)
    listBox:SetPoint("TOPLEFT", ed, "TOPLEFT", 4, -16)
    ns.UI.Skin(listBox, 0.6)
    listBox:EnableMouseWheel(true)
    listBox:SetScript("OnMouseWheel", function(_, d)
        listOffset = listOffset - d * 2
        refreshList()
    end)
    panel.listRows = {}
    for i = 1, LIST_ROWS do
        local row = CreateFrame("Button", nil, listBox)
        row:SetHeight(20)
        row:SetPoint("TOPLEFT", listBox, "TOPLEFT", 3, -3 - (i - 1) * 20)
        row:SetPoint("TOPRIGHT", listBox, "TOPRIGHT", -3, -3 - (i - 1) * 20)
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints()
        ns.UI.Gradient(row.sel, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.38, C.violet[1], C.violet[2], C.violet[3], 0)
        row.bar = row:CreateTexture(nil, "ARTWORK")
        row.bar:SetPoint("TOPLEFT")
        row.bar:SetPoint("BOTTOMLEFT")
        row.bar:SetWidth(2)
        row.bar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        ns.UI.Gradient(hl, "HORIZONTAL", 1, 1, 1, 0.10, 1, 1, 1, 0)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 6, 0)
        row.text:SetPoint("RIGHT", -2, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row:SetScript("OnClick", function(self) if self.note then M.Select(self.note.id) end end)
        row:Hide()
        panel.listRows[i] = row
    end
    -- boutons en colonne, pleine largeur (les libelles longs tiennent)
    local by = -16 - (LIST_ROWS * 20 + 6) - 6
    local function listButton(text, fn, prev)
        local b = ns.UI.Button(ed, text, LEFT_W, fn)
        b:SetSize(LEFT_W, 20)
        if prev then
            b:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -2)
        else
            b:SetPoint("TOPLEFT", ed, "TOPLEFT", 4, by)
        end
        return b
    end
    local bNew = listButton(L.NOTE_NEW, function() M.NewNote() end)
    local bDup = listButton(L.NOTE_DUP, function() M.Duplicate() end, bNew)
    local bRen = listButton(L.NOTE_RENAME, function()
        panel.titleBox:SetFocus()
        panel.titleBox:HighlightText()
    end, bDup)
    -- supprimer : deux clics (le second confirme)
    local bDel
    bDel = listButton(L.NOTE_DEL, function()
        if bDel.armed and now() - bDel.armed < 4 then
            bDel.armed = nil
            bDel:SetText(L.NOTE_DEL)
            M.Delete()
        else
            bDel.armed = now()
            bDel:SetText(L.NOTE_DEL_CONFIRM)
            C_Timer.After(4, function()
                if bDel.armed and now() - bDel.armed >= 3.9 then
                    bDel.armed = nil
                    bDel:SetText(L.NOTE_DEL)
                end
            end)
        end
    end, bRen)
    panel.delButton = bDel
    local bImp = listButton(L.NOTE_IMPORT, function() M.ImportShared() end, bDel)
    withTip(bImp, L.NOTE_IMPORT, L.NOTE_IMPORT_TIP)

    -- titre
    local tl = ed:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tl:SetPoint("TOPLEFT", ed, "TOPLEFT", RIGHT_X, -3)
    tl:SetSize(62, 16)
    tl:SetJustifyH("LEFT")
    tl:SetText(L.NOTE_TITLE_LABEL)
    local titleBox = ns.UI.EditBox(ed, RIGHT_W - 66, 20)
    titleBox:SetPoint("TOPLEFT", ed, "TOPLEFT", RIGHT_X + 66, 0)
    titleBox:SetMaxLetters(MAX_TITLE)
    titleBox:SetScript("OnTextChanged", function(self, user) if user then M.Rename(self:GetText() or "") end end)
    titleBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    panel.titleBox = titleBox

    -- barre d aide : marqueurs, joueur, ligne reservee, couleur, aide
    local x = RIGHT_X
    for i = 1, 8 do
        local b = CreateFrame("Button", nil, ed)
        b:SetSize(20, 20)
        b:SetPoint("TOPLEFT", ed, "TOPLEFT", x, -26)
        ns.UI.Skin(b, 0.7)
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetPoint("TOPLEFT", 2, -2)
        t:SetPoint("BOTTOMRIGHT", -2, 2)
        t:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.15)
        b:SetScript("OnClick", function() insert("{rt" .. i .. "}") end)
        local g = _G["RAID_TARGET_" .. i]
        withTip(b, "{rt" .. i .. "}", (not issecret(g) and type(g) == "string") and g or nil)
        x = x + 22
    end
    x = x + 4
    local bPl = ns.UI.Button(ed, L.NOTE_PLAYER, 70, function(self)
        openPicker(self, function(name) insert(name) end)
    end)
    bPl:SetSize(70, 20)
    bPl:SetPoint("TOPLEFT", ed, "TOPLEFT", x, -26)
    withTip(bPl, L.NOTE_PLAYER, L.NOTE_PLAYER_TIP)
    local bFor = ns.UI.Button(ed, "{p:}", 40, function(self)
        openPicker(self, function(name) insert("{p:" .. name .. "}{/p}", 4) end)
    end)
    bFor:SetSize(40, 20)
    bFor:SetPoint("LEFT", bPl, "RIGHT", 4, 0)
    withTip(bFor, "{p:" .. L.NOTE_PLAYER .. "}", L.NOTE_FOR_TIP)
    local bCol = ns.UI.Button(ed, L.NOTE_COLOR, 70, function(self)
        ns.UI.OpenMenu(self, colorOptions, function() return nil end, function(hex)
            if type(hex) == "string" and hex:find("^%x%x%x%x%x%x$") then wrapColor(hex) end
        end)
    end)
    bCol:SetSize(70, 20)
    bCol:SetPoint("LEFT", bFor, "RIGHT", 4, 0)
    -- le jeu efface la selection au clic : on la remontre (selection suivie,
    -- voir cuiSel) pour montrer qu elle est retenue
    bCol:HookScript("OnClick", function()
        local e = lastEdit or (panel and panel.mainEdit)
        local sel = e and e.cuiSel
        if sel and sel.text == (e:GetText() or "") and sel.stop > sel.start then
            e.cuiSilent = true
            pcall(e.SetFocus, e)
            pcall(e.HighlightText, e, sel.start, sel.stop)
            e.cuiSilent = false
        end
    end)
    withTip(bCol, L.NOTE_COLOR, L.NOTE_COLOR_TIP)
    local bHelp = ns.UI.Button(ed, "?", 22)
    bHelp:SetSize(22, 20)
    bHelp:SetPoint("LEFT", bCol, "RIGHT", 4, 0)
    withTip(bHelp, L.MOD_NOTES, L.NOTE_CODES)

    -- texte de la note
    local mainBox, mainEdit = scrollEdit(ed, RIGHT_W, 232, function(text) M.SetText(text) end)
    mainBox:SetPoint("TOPLEFT", ed, "TOPLEFT", RIGHT_X, -52)
    panel.mainEdit = mainEdit
    lastEdit = mainEdit

    -- note personnelle
    local pl = ed:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    pl:SetPoint("TOPLEFT", ed, "TOPLEFT", RIGHT_X + 2, -290)
    pl:SetSize(RIGHT_W, 14)
    pl:SetJustifyH("LEFT")
    pl:SetText(L.NOTE_PERSONAL)
    local persBox, persEdit = scrollEdit(ed, RIGHT_W, 74, function(text) M.SetPersonal(text) end)
    persBox:SetPoint("TOPLEFT", ed, "TOPLEFT", RIGHT_X, -306)
    panel.personalEdit = persEdit

    -- actions
    local bSend = ns.UI.Button(ed, L.NOTE_SEND, 130, function() M.SendNote() end)
    bSend:SetPoint("TOPLEFT", ed, "TOPLEFT", RIGHT_X, -388)
    withTip(bSend, L.NOTE_SEND, L.NOTE_SEND_TIP)
    local bPrev = ns.UI.Button(ed, L.NOTE_PREVIEW, 90, function() M.Preview() end)
    bPrev:SetPoint("LEFT", bSend, "RIGHT", 4, 0)
    withTip(bPrev, L.NOTE_PREVIEW, L.NOTE_PREVIEW_TIP)
    local bReq = ns.UI.Button(ed, L.NOTE_REQUEST, 130, function() M.Request() end)
    bReq:SetPoint("LEFT", bPrev, "RIGHT", 4, 0)
    withTip(bReq, L.NOTE_REQUEST, L.NOTE_REQUEST_TIP)
    local bShow = ns.UI.Button(ed, L.NOTE_SHOWHIDE, 110, function() M.Show() end)
    bShow:SetPoint("LEFT", bReq, "RIGHT", 4, 0)

    panel.status = ed:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.status:SetPoint("TOPLEFT", ed, "TOPLEFT", RIGHT_X + 2, -418)
    panel.status:SetSize(RIGHT_W - 90, 16)
    panel.status:SetJustifyH("LEFT")
    panel.status:SetWordWrap(false)
    panel.count = ed:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.count:SetPoint("TOPRIGHT", ed, "TOPLEFT", RIGHT_X + RIGHT_W, -418)
    panel.count:SetSize(88, 16)
    panel.count:SetJustifyH("RIGHT")

    -- reglages de la fenetre d affichage
    local form = ns.UI.Form(opt, -4, function() M.Render() end, 470)
    form:Header(L.NOTE_H_WINDOW)
    local function check(key, text)
        form:Check(text, function() return db[key] end, function(v) db[key] = v end)
    end
    check("autoShow", L.NOTE_OPT_AUTO)
    check("soloHide", L.NOTE_OPT_SOLO)
    check("locked", L.NOTE_OPT_LOCK)
    check("showPersonal", L.NOTE_OPT_PERSONAL)
    check("highlightMe", L.NOTE_OPT_HIGHLIGHT)
    check("onlyMine", L.NOTE_OPT_MINE)
    check("outline", L.NOTE_OPT_OUTLINE)
    form:Gap(4)
    form:Columns(2)
    form:Number(L.NOTE_FONT_SIZE, function() return db.fontSize end, function(v) db.fontSize = v end, 8, 24, 1)
    form:Number(L.NOTE_BG, function() return db.bgAlpha end, function(v) db.bgAlpha = v end, 0, 100, 5)
    local fontKeys, fontNames = { "ui", "game" }, { ui = L.NOTE_FONT_UI, game = L.NOTE_FONT_GAME }
    for _, f in ipairs(ns.FontList and ns.FontList() or {}) do
        if f.key and f.regular and not fontNames[f.key] then
            fontKeys[#fontKeys + 1] = f.key
            fontNames[f.key] = f.name or f.key
        end
    end
    form:Cycle(L.NOTE_FONT, fontKeys, fontNames, function() return db.font end, function(v) db.font = v end)
    form:Cycle(L.NOTE_STRATA, { "LOW", "MEDIUM", "HIGH" },
        { LOW = L.NOTE_STRATA_LOW, MEDIUM = L.NOTE_STRATA_MEDIUM, HIGH = L.NOTE_STRATA_HIGH },
        function() return db.strata end, function(v) db.strata = v end)
    form:EndColumns()
    form:Gap(6)
    local bS = ns.UI.Button(opt, L.NOTE_SHOWHIDE, 140, function() M.Show() end)
    bS:SetPoint("TOPLEFT", opt, "TOPLEFT", 8, form.y)
    local bC = ns.UI.Button(opt, L.NOTE_RESET_POS, 140, function()
        for k in pairs(db.pos) do db.pos[k] = nil end
        db.pos.point, db.pos.x, db.pos.y = "CENTER", 0, 0
        if frame then ns.ApplyPos(frame, db.pos) end
    end)
    bC:SetPoint("LEFT", bS, "RIGHT", 6, 0)
    form:Gap(30)
    local hint = opt:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", opt, "TOPLEFT", 8, form.y - 4)
    hint:SetWidth(PW - 30)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.NOTE_HINT_DISPLAY .. "\n\n" .. L.NOTE_CODES)
    panel.form = form

    panel:HookScript("OnShow", function()
        M.RefreshEditor(false)
        form:Refresh()
        syncTabs()
    end)
    syncTabs()
end

openEditor = function()
    if not db then return end
    if not panel then
        if combat() then
            ns.Say(L.NOTE_COMBAT_LATER)
            openAfterCombat = true
            return
        end
        buildEditor()
    end
    ns.ShowPanel(panel)
    M.RefreshEditor(false)
end
M.OpenEditor = openEditor

---------------------------------------------------------------------------
-- Commande, evenements, module
---------------------------------------------------------------------------

local function slash(input)
    local cmd = strlower(strtrim(input or ""))
    if cmd == "" then
        openEditor()
    elseif cmd == "montrer" or cmd == "show" or cmd == "afficher" then
        M.Show(true)
    elseif cmd == "cacher" or cmd == "hide" or cmd == "masquer" then
        M.Show(false)
    elseif cmd == "envoyer" or cmd == "send" then
        M.SendNote()
    elseif cmd == "demander" or cmd == "redemander" or cmd == "request" then
        M.Request()
    else
        ns.Say(L.NOTE_USAGE)
    end
end

-- la communication est chargee avant ce fichier ; sinon, a la connexion
hookComm()

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if ns.ModuleOff("note", ev) then return end
    if event == "PLAYER_LOGIN" then
        initDB()
        hookComm()
        if combat() then
            pendingBuild = true
        else
            buildFrame()
            M.Render()
            frame:SetShown(wanted())
        end
    elseif not db then
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingBuild then
            pendingBuild = false
            buildFrame()
            M.Render()
            frame:SetShown(wanted())
        elseif pendingLayout then
            pendingLayout = false
            layout()
        end
        if openAfterCombat then
            openAfterCombat = false
            openEditor()
        end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PARTY_LEADER_CHANGED" then
        -- couleurs de classe et visibilite des lignes suivent le groupe ;
        -- la fenetre aussi ("masquer hors groupe")
        if frame and not moverForced then frame:SetShown(wanted()) end
        queueRender()
        if refreshStatus then refreshStatus() end
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)
end

ns.RegisterModule({
    command = "note",
    panelName = "CorpUINotes",
    icon = "Interface\\Icons\\INV_Scroll_03",
    title = function() return L.MOD_NOTES end,
    desc = function() return L.NOTE_DESC end,
    Slash = slash,
    Open = openEditor,
})
