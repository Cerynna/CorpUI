--[[--------------------------------------------------------------------------
    CorpUI - module Jeux : ce qui est commun aux mini-jeux

      - la liste des jeux : ns.Games.Register(cle, { title, open, close,
        shown, ... }) ; open() rend true si le jeu s est ouvert ;
      - la page des mini-jeux (/corp jeux) : une seule carte pour tous les
        jeux (voir plus bas), le reglage des vols n y est qu une fois ;
      - pendant un vol (taxi) : le jeu choisi s ouvre au decollage, et se
        referme a l atterrissage s il s etait ouvert tout seul (reglage) ;
        rien en combat ; deja en vol a la connexion : rien d office ;
      - ces reglages sont partages (CorpUIDB.games.taxi) ;
      - ns.Games.OnFlight(fn) : fn(true) au decollage, fn(false) a
        l atterrissage (servait au vol du griffon, desactive le 08/10) ;
      - ns.Games.Account : le compte et son personnage principal (un
        joueur et ses rerolls = une ligne aux classements de guilde) ;
      - ns.Games.Scores : records des jeux partages avec la guilde (message
        "JSCO"), classement par compte.
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local C = ns.COLORS

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

local function taxiList()
    local list = { { value = "none", text = L.GAMES_NONE } }
    for _, g in ipairs(Games.list) do table.insert(list, { value = g.key, text = g.title() }) end
    return list
end

-- liste "pendant un vol, ouvrir" + case "fermer a l atterrissage", pour un
-- panneau a soi (la page des mini-jeux a les siens)
function Games.TaxiOptions(form)
    form:Select(L.GAMES_TAXI, taxiList, function() return tdb and tdb.game or "none" end,
        function(v) if tdb then tdb.game = v end end, 220)
    form:Check(L.GAMES_TAXI_CLOSE, function() return tdb and tdb.close end, function(v) if tdb then tdb.close = v end end)
end

---------------------------------------------------------------------------
-- Compte (classements de guilde) : un joueur et ses rerolls ne font
-- qu une ligne. Identifiant tire une fois (CorpUIDB.account.id, repris du
-- podometre) ; personnage principal : celui choisi (page des mini-jeux,
-- onglet Guilde du podometre), sinon le plus haut niveau du royaume et de
-- la faction, puis le plus de km. Les personnages viennent de la
-- connexion (Account.Note), du module Persos et du podometre.
---------------------------------------------------------------------------

local Account = {}
Games.Account = Account
local accountFns = {}
local issecret = issecretvalue or function() return false end

local function plain(v)
    if v == nil or issecret(v) then return nil end
    return v
end

local function rootOf()
    local root = ns.root or (ns.InitRoot and ns.InitRoot())
    return type(root) == "table" and root or nil
end

local function adb()
    local root = rootOf()
    if not root then return nil end
    local a = root.account
    if type(a) ~= "table" then
        a = {}
        root.account = a
        -- reprise du podometre (13/11)
        local p = root.pedometer
        if type(p) == "table" then
            if type(p.id) == "string" then a.id = p.id end
            if type(p.opt) == "table" and type(p.opt.main) == "string" then a.main = p.opt.main end
        end
    end
    if type(a.chars) ~= "table" then a.chars = {} end
    return a, root
end

local ID_CHARS = "0123456789abcdefghijklmnopqrstuvwxyz"

function Account.Id()
    local a = adb()
    if not a then return nil end
    if type(a.id) ~= "string" or not a.id:match("^[0-9a-z]+$") or #a.id ~= 10 then
        local t = {}
        for i = 1, 10 do
            local n = math.random(1, #ID_CHARS)
            t[i] = ID_CHARS:sub(n, n)
        end
        a.id = table.concat(t)
    end
    return a.id
end

-- le personnage connecte : nom, identite (forme des messages), classe,
-- niveau, faction
function Account.Note()
    local a = adb()
    if not a or not ns.CharKey then return end
    local key = ns.CharKey()
    local c = a.chars[key]
    if type(c) ~= "table" then
        c = {}
        a.chars[key] = c
    end
    c.name = plain(UnitName("player")) or c.name
    local _, class = UnitClass("player")
    c.class = plain(class) or c.class
    local lv = plain(UnitLevel("player"))
    if type(lv) == "number" then c.level = lv end
    local okF, f = pcall(UnitFactionGroup, "player")
    f = okF and plain(f) or nil
    if type(f) == "string" then c.faction = f end
    local id = ns.Names and ns.Names.Me and ns.Names.Me()
    if type(id) == "string" and not issecret(id) then c.id = id end
end

local function keyRealm(key)
    return type(key) == "string" and key:match("^[^%-]+%-(.+)$") or nil
end

-- personnages qui peuvent etre le main : ce royaume, cette faction ;
-- tries par niveau puis par km
function Account.Characters()
    local list = {}
    local a, root = adb()
    if not a then return list end
    local realm = keyRealm(ns.CharKey())
    local okF, faction = pcall(UnitFactionGroup, "player")
    faction = okF and plain(faction) or nil
    local alts = type(root.alts) == "table" and root.alts or {}
    local pedo = type(root.pedometer) == "table" and type(root.pedometer.chars) == "table" and root.pedometer.chars or {}
    local keys = {}
    for k in pairs(a.chars) do keys[k] = true end
    for k in pairs(pedo) do keys[k] = true end
    for k in pairs(alts) do keys[k] = true end
    for key in pairs(keys) do
        if keyRealm(key) == realm then
            local c = type(a.chars[key]) == "table" and a.chars[key] or {}
            local p = type(pedo[key]) == "table" and pedo[key] or {}
            local s = type(alts[key]) == "table" and alts[key] or {}
            local fac = c.faction or s.faction
            if not faction or type(fac) ~= "string" or fac == faction then
                local lv = math.max(tonumber(c.level) or 0, tonumber(p.level) or 0, tonumber(s.level) or 0)
                list[#list + 1] = {
                    key = key, name = c.name or p.name or s.name or key:match("^[^%-]+") or key,
                    id = c.id or p.id, class = c.class or p.class or s.class, level = lv,
                    km = tonumber(p.total) or 0,
                }
            end
        end
    end
    table.sort(list, function(x, y)
        if x.level ~= y.level then return x.level > y.level end
        if x.km ~= y.km then return x.km > y.km end
        return x.key < y.key
    end)
    return list
end

function Account.Main()
    local list = Account.Characters()
    local a = adb()
    local pick = a and a.main
    for _, c in ipairs(list) do
        if c.key == pick then return c end
    end
    if list[1] then return list[1] end
    local _, class = UnitClass("player")
    return { key = ns.CharKey and ns.CharKey() or "?", name = UnitName("player"),
             id = ns.Names and ns.Names.Me and ns.Names.Me() or nil, class = class }
end

-- nom du main, tel que les autres le liront ("Prenom Nom" ou "Nom-Royaume")
function Account.Name(m)
    m = m or Account.Main()
    return m.id or m.name or "?"
end

-- liste deroulante du main : Auto + personnages du compte
function Account.Options()
    local list = Account.Characters()
    local out = { { value = "auto", text = string.format(L.GAMES_MAIN_AUTO, list[1] and list[1].name or "?") } }
    for _, c in ipairs(list) do
        local lv = (c.level or 0) > 0 and (" |cff999999" .. c.level .. "|r") or ""
        out[#out + 1] = { value = c.key, text = (c.name or c.key) .. lv }
    end
    return out
end

-- choix montre par la liste ("auto" si le perso choisi n est plus la)
function Account.Choice()
    local a = adb()
    local pick = a and a.main
    for _, c in ipairs(Account.Characters()) do
        if c.key == pick then return pick end
    end
    return "auto"
end

function Account.SetChoice(v)
    local a = adb()
    if not a then return end
    a.main = (v ~= "auto") and v or nil
    for _, fn in ipairs(accountFns) do pcall(fn) end
end

function Account.OnChange(fn) table.insert(accountFns, fn) end

---------------------------------------------------------------------------
-- Records de guilde des mini-jeux (message "JSCO", ns.Comm) : chaque
-- compte envoie ses records (de toujours, de la semaine) a la connexion et
-- apres un nouveau record ; une demande (connexion) recoit les fiches en
-- prive. Fiches gardees 60 jours, rangees par compte : une ligne par
-- joueur, au nom de son main.
--   Scores.Register(jeu, fn)   fn() -> record, record de la semaine
--   Scores.Board(jeu, mode)    { name, class, score, me } ; "best" | "week"
--   Scores.Changed()           un record a bouge (envoi groupe, 3 s apres)
--   Scores.OnChange(fn)        fiche recue ou record a nous
---------------------------------------------------------------------------

local Scores = {}
Games.Scores = Scores
local SCORE_KEEP = 60 * 86400
local MAX_GAMES = 20
local providers, scoreFns = {}, {}
local Comm
local lastSig, pending = nil, false
local repliedTo = {}

local function gdb()
    local root = rootOf()
    if not root then return nil end
    if type(root.games) ~= "table" then root.games = {} end
    local g = root.games
    if type(g.scores) ~= "table" then g.scores = {} end
    if g.share == nil then g.share = true end
    return g
end

-- semaine (du lundi), comme le podometre
function Scores.Week(t)
    local d = date("*t", t or time())
    local noon = time({ year = d.year, month = d.month, day = d.day, hour = 12 })
    local back = (d.wday + 5) % 7
    return date("%Y-%m-%d", noon - back * 86400)
end

function Scores.Register(game, fn) providers[game] = fn end
function Scores.OnChange(fn) table.insert(scoreFns, fn) end
local function notify() for _, fn in ipairs(scoreFns) do pcall(fn) end end

local function own(game)
    local fn = providers[game]
    if not fn then return 0, 0 end
    local ok, b, w = pcall(fn)
    if not ok then return 0, 0 end
    return math.max(0, math.floor(tonumber(b) or 0)), math.max(0, math.floor(tonumber(w) or 0))
end

local function payload(ask)
    local m = Account.Main()
    local wk = Scores.Week()
    local parts = {}
    for game in pairs(providers) do
        local b, w = own(game)
        if b > 0 then parts[#parts + 1] = game .. ":" .. b .. ":" .. wk .. ":" .. w end
    end
    table.sort(parts)
    local name = (Account.Name(m):gsub("[;:,]", ""))
    return table.concat({ "1", Account.Id() or "", name, m.class or "", ask and "1" or "0",
        table.concat(parts, ",") }, ";"), #parts
end
Scores._payload = payload

local function inGuild()
    local ok, v = pcall(IsInGuild)
    return ok and not issecret(v) and v and true or false
end

function Scores.Share(ask)
    local g = gdb()
    if not g or not g.share or not Comm or not inGuild() or InCombatLockdown() then return false end
    local p, n = payload(ask)
    if n == 0 and not ask then return false end
    local sent = Comm.Send("JSCO", p, "GUILD")
    if sent then lastSig = (payload(false)) end
    return sent
end

function Scores.Changed()
    notify()
    if pending then return end
    pending = true
    C_Timer.After(3, function()
        pending = false
        if (payload(false)) ~= lastSig then Scores.Share(false) end
    end)
end

local function onScore(sender, data, channel)
    local g = gdb()
    if not g or type(sender) ~= "string" or type(data) ~= "string" then return end
    local f = {}
    for part in (data .. ";"):gmatch("([^;]*);") do f[#f + 1] = part end
    if f[1] ~= "1" then return end
    local id = (f[2] or ""):match("^[0-9a-z]+$")
    if not id or #id < 6 or #id > 16 or id == Account.Id() then return end
    local main = f[3]
    if type(main) ~= "string" or main == "" or #main > 64 then main = sender end
    local games, n = {}, 0
    for entry in (f[6] or ""):gmatch("[^,]+") do
        local game, b, w, wb = entry:match("^([%w_]+):(%d+):(%d%d%d%d%-%d%d%-%d%d):(%d+)$")
        if game and #game <= 24 and n < MAX_GAMES then
            games[game] = { b = tonumber(b), w = w, wb = tonumber(wb) }
            n = n + 1
        end
    end
    g.scores["@" .. id] = { n = main, cl = (f[4] or ""):match("^[A-Z]+$"), at = time(), g = games }
    notify()
    -- une demande (connexion) : nos records en prive, une fois par minute
    if f[5] == "1" and channel ~= "WHISPER" and g.share then
        local t = GetTime()
        if not repliedTo[sender] or t - repliedTo[sender] > 60 then
            repliedTo[sender] = t
            if Comm and not InCombatLockdown() then Comm.Send("JSCO", (payload(false)), "WHISPER", sender) end
        end
    end
end
Scores._receive = onScore

-- classement d un jeu : nous (au nom du main) et un par compte ; deux
-- comptes qui annoncent le meme main : la fiche la plus recente
function Scores.Board(game, mode)
    local list = {}
    local week = mode == "week"
    local m = Account.Main()
    local myName = Account.Name(m)
    local b, w = own(game)
    local mine = week and w or b
    if mine > 0 then list[1] = { name = myName, class = m.class, score = mine, me = true } end
    local g = gdb()
    if not g then return list end
    local wk = Scores.Week()
    local byName = {}
    for _, e in pairs(g.scores) do
        local s = type(e) == "table" and type(e.g) == "table" and e.g[game]
        if type(s) == "table" and type(e.n) == "string" and e.n ~= myName then
            local v = week and (s.w == wk and s.wb or 0) or (s.b or 0)
            v = tonumber(v) or 0
            if v > 0 then
                local prev = byName[e.n]
                if not prev or (tonumber(e.at) or 0) > (tonumber(prev.at) or 0) then
                    byName[e.n] = { name = e.n, class = e.cl, score = v, at = e.at }
                end
            end
        end
    end
    for _, r in pairs(byName) do list[#list + 1] = r end
    table.sort(list, function(x, y)
        if x.score ~= y.score then return x.score > y.score end
        if (x.me and true or false) ~= (y.me and true or false) then return x.me and true or false end
        return (x.name or "") < (y.name or "")
    end)
    return list
end

local function shareOn() local g = gdb() return g and g.share and true or false end
local function setShare(v)
    local g = gdb()
    if not g then return end
    g.share = v and true or false
    if v then Scores.Share(false) end
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

---------------------------------------------------------------------------
-- Page des mini-jeux (/corp jeux) : une carte pour tous les jeux.
-- En haut, le jeu a ouvrir pendant les vols (une fois pour tous) ; puis
-- une ligne par jeu : icone, nom, a quoi il sert, record, bouton Jouer.
-- Un clic sur la ligne deplie ses regles et ses reglages (un seul jeu
-- deplie a la fois). Chaque jeu decrit sa ligne dans Games.Register :
--   icon()             texture, puis coordonnees eventuelles (l, r, t, b)
--   tagline()          a quoi il sert (description du module ; le
--                      "mini-jeu :" du debut est retire)
--   hint()             regles ; stats() : record, parties...
--   options(form, f)   ses reglages (form de ns.UI.Form, sur le cadre f)
--   apply()            apres un reglage (taille de la fenetre...)
--   name()             nom sur la ligne, si autre que title()
--   foot()             credits (petit texte gris) ; playText() : libelle
--                      du bouton (Jouer par defaut) ; play() : ouvrir /
--                      fermer ; ready() : ligne montree si vrai
---------------------------------------------------------------------------

local HUB_W, ROW_H, ROW_GAP = 460, 56, 6
local AREA_X, FORM_W = 58, 380
local hub, rows, openKey, listTop = nil, {}, nil, 0

local function text(fn)
    if type(fn) ~= "function" then return "" end
    local ok, v = pcall(fn)
    return ok and type(v) == "string" and v or ""
end

-- "mini-jeu : fais courir un murloc..." -> "Fais courir un murloc..."
local function short(s)
    local head, rest = s:match("^(.-):%s*(.+)$")
    if not head or #head > 18 then head, rest = s:match("^(.-)：%s*(.+)$") end
    if head and #head <= 18 then s = rest end
    local first = s:sub(1, 1)
    if first:match("%l") then s = first:upper() .. s:sub(2) end
    return s
end

local function ready(g)
    if type(g.ready) ~= "function" then return true end
    local ok, v = pcall(g.ready)
    return ok and v and true or false
end

local function paintRow(row)
    local open = openKey == row.game.key
    row.bar:SetShown(open)
    row.hl:SetShown(open or row.head:IsMouseOver())
    row.bg:SetColorTexture(1, 1, 1, open and 0.05 or 0.025)
    row.chev:SetDir(open and "DOWN" or "RIGHT")
end

local function refreshRow(row, keepForm)
    local g = row.game
    local name = text(g.name)
    row.title:SetText(name ~= "" and name or g.title())
    row.tag:SetText(short(text(g.tagline)))
    row.stats:SetText(text(g.stats))
    local label = text(g.playText)
    row.play:SetText(label ~= "" and label or L.MURLOC_PLAY)
    if type(g.icon) == "function" then
        local ok, tex, l, r, t, b = pcall(g.icon)
        if ok and tex then
            row.icon:SetTexture(tex)
            if l then row.icon:SetTexCoord(l, r, t, b) else row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        end
    end
    if row.area.form and not keepForm then row.area.form:Refresh() end
    paintRow(row)
end

local function refreshHub()
    if not hub then return end
    if hub.taxi then hub.taxi:Refresh() end
    if hub.close then hub.close:SetChecked(tdb and tdb.close and true or false) end
    if hub.main then hub.main:Refresh() end
    if hub.share then hub.share:SetChecked(shareOn()) end
    for _, row in ipairs(rows) do refreshRow(row) end
end

-- reglages d un jeu : regles, formulaire, credits (a la premiere ouverture)
local function buildArea(row)
    local a, g = row.area, row.game
    a.built = true
    a.hint = a:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    a.hint:SetPoint("TOPLEFT", a, "TOPLEFT", 0, -2)
    a.hint:SetPoint("TOPRIGHT", a, "TOPRIGHT", 0, -2)
    a.hint:SetJustifyH("LEFT")
    a.hint:SetTextColor(C.text[1] * 0.85, C.text[2] * 0.85, C.text[3] * 0.85)
    a.hint:SetText(text(g.hint))
    a.box = CreateFrame("Frame", nil, a)
    a.box:SetPoint("TOPLEFT", a.hint, "BOTTOMLEFT", -4, -8)
    a.box:SetSize(FORM_W, 1)
    local form = ns.UI.Form(a.box, 0, function()
        if g.apply then pcall(g.apply) end
        refreshRow(row, true)
    end, FORM_W)
    if type(g.options) == "function" then
        local ok, err = pcall(g.options, form, a.box)
        if not ok then geterrorhandler()(err) end
    end
    form:EndColumns()
    a.form = form
    a.formH = math.max(0, -form.y)
    a.box:SetHeight(math.max(1, a.formH))
    local foot = text(g.foot)
    if foot ~= "" then
        a.foot = a:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        a.foot:SetPoint("TOPLEFT", a.box, "BOTTOMLEFT", 4, -2)
        a.foot:SetJustifyH("LEFT")
        a.foot:SetText(foot)
    end
    form:Refresh()
end

local function layout()
    if not hub then return end
    local y = listTop
    for _, row in ipairs(rows) do
        local show = ready(row.game)
        row:SetShown(show)
        if show then
            local h = ROW_H
            local a = row.area
            if openKey == row.game.key and a.built then
                local w = a:GetWidth()
                if a.foot and w and w > 10 then a.foot:SetWidth(w - 4) end
                local ah = (a.hint:GetStringHeight() or 0) + 8 + a.formH
                    + (a.foot and ((a.foot:GetStringHeight() or 0) + 4) or 0) + 10
                a:SetHeight(ah)
                a:Show()
                h = h + ah
            else
                a:Hide()
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", hub, "TOPLEFT", 4, y)
            row:SetPoint("TOPRIGHT", hub, "TOPRIGHT", -4, y)
            row:SetHeight(h)
            y = y - h - ROW_GAP
        end
    end
    hub:SetHeight(math.floor(-y + 4))
end

-- deplier / replier les reglages d un jeu (un seul a la fois)
local function toggleRow(key)
    openKey = openKey ~= key and key or nil
    for _, row in ipairs(rows) do
        if row.game.key == openKey and not row.area.built then buildArea(row) end
        paintRow(row)
    end
    layout()
    -- hauteur des textes connue au rendu suivant
    C_Timer.After(0, layout)
end

local function buildRow(g)
    local row = CreateFrame("Frame", nil, hub)
    row.game = g
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.hl = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.hl:SetPoint("TOPLEFT")
    row.hl:SetPoint("TOPRIGHT")
    row.hl:SetHeight(ROW_H)
    ns.UI.Gradient(row.hl, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.24, C.violet[1], C.violet[2], C.violet[3], 0)
    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetPoint("TOPLEFT")
    row.bar:SetPoint("BOTTOMLEFT")
    row.bar:SetWidth(2)
    row.bar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.9)
    -- en-tete cliquable : deplie les reglages
    row.head = CreateFrame("Button", nil, row)
    row.head:SetPoint("TOPLEFT")
    row.head:SetPoint("TOPRIGHT")
    row.head:SetHeight(ROW_H)
    row.head:RegisterForClicks("LeftButtonUp")
    row.head:SetScript("OnClick", function() toggleRow(g.key) end)
    row.head:SetScript("OnEnter", function(self)
        paintRow(row)
        local t = ns.Tooltip(self, "ANCHOR_TOPLEFT")
        t:AddLine(row.title:GetText() or g.title())
        t:AddLine(L.GAMES_TIP_ROW, 1, 1, 1)
        t:Show()
    end)
    row.head:SetScript("OnLeave", function()
        ns.HideTooltip()
        paintRow(row)
    end)
    local frame = CreateFrame("Frame", nil, row.head)
    frame:SetSize(42, 42)
    frame:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -7)
    ns.UI.Skin(frame, 0.6)
    row.icon = frame:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("TOPLEFT", 1, -1)
    row.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    row.title = row.head:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(row.title, 14)
    row.title:SetPoint("TOPLEFT", row, "TOPLEFT", AREA_X, -7)
    row.title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    row.tag = row.head:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.tag:SetPoint("TOPLEFT", row, "TOPLEFT", AREA_X, -25)
    row.tag:SetPoint("TOPRIGHT", row, "TOPRIGHT", -136, -25)
    row.tag:SetJustifyH("LEFT")
    row.tag:SetWordWrap(false)
    row.tag:SetTextColor(C.text[1] * 0.8, C.text[2] * 0.8, C.text[3] * 0.8)
    row.stats = row.head:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.stats:SetPoint("TOPLEFT", row, "TOPLEFT", AREA_X, -39)
    row.stats:SetPoint("TOPRIGHT", row, "TOPRIGHT", -136, -39)
    row.stats:SetJustifyH("LEFT")
    row.stats:SetWordWrap(false)
    row.chev = ns.UI.Chevron(row.head, 14, "RIGHT")
    row.chev:SetPoint("CENTER", row, "TOPRIGHT", -16, -ROW_H / 2)
    row.play = ns.UI.Button(row.head, L.MURLOC_PLAY, 96, function()
        if type(g.play) == "function" then pcall(g.play) end
        C_Timer.After(0.2, function() refreshRow(row) end)
    end)
    row.play:SetPoint("RIGHT", row, "TOPRIGHT", -32, -ROW_H / 2)
    -- reglages : sous l en-tete, alignes sur le nom
    row.area = CreateFrame("Frame", nil, row)
    row.area:SetPoint("TOPLEFT", row, "TOPLEFT", AREA_X, -ROW_H)
    row.area:SetPoint("TOPRIGHT", row, "TOPRIGHT", -16, -ROW_H)
    row.area:SetHeight(1)
    row.area:Hide()
    rows[#rows + 1] = row
    return row
end

local function buildHub()
    hub = ns.UI.Window("CorpUIGamesOptions", ns.TITLE .. " - " .. L.PAGE_GAMES, nil, HUB_W, 400)
    -- pendant un vol : un seul reglage pour tous les jeux
    local label = hub:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", hub, "TOPLEFT", 10, -44)
    label:SetText(L.GAMES_TAXI)
    hub.taxi = ns.UI.Select(hub, 200, taxiList, function() return tdb and tdb.game or "none" end,
        function(v) if tdb then tdb.game = v end end, refreshHub)
    hub.taxi:SetPoint("LEFT", label, "RIGHT", 10, 0)
    hub.close = ns.UI.Check(hub, L.GAMES_TAXI_CLOSE, function(v) if tdb then tdb.close = v end end)
    hub.close:SetPoint("TOPLEFT", hub, "TOPLEFT", 4, -60)
    -- classements de guilde : le main du compte, le partage
    local mainLabel = hub:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mainLabel:SetPoint("TOPLEFT", hub, "TOPLEFT", 10, -96)
    mainLabel:SetText(L.GAMES_MAIN)
    hub.main = ns.UI.Select(hub, 160, Account.Options, Account.Choice, Account.SetChoice, refreshHub)
    hub.main:SetPoint("LEFT", mainLabel, "RIGHT", 10, 0)
    hub.share = ns.UI.Check(hub, L.GAMES_SHARE, function(v) setShare(v) end)
    hub.share:SetPoint("TOPLEFT", hub, "TOPLEFT", 4, -112)
    local rule = hub:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", hub, "TOPLEFT", 4, -144)
    rule:SetPoint("TOPRIGHT", hub, "TOPRIGHT", -4, -144)
    rule:SetColorTexture(1, 1, 1, 0.08)
    listTop = -152
    for _, g in ipairs(Games.list) do buildRow(g) end
    hub:HookScript("OnShow", function()
        refreshHub()
        layout()
        C_Timer.After(0, layout)
    end)
    -- records a jour pendant que la page est ouverte
    local acc = 0
    hub:HookScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 1 then return end
        acc = 0
        for _, row in ipairs(rows) do
            row.stats:SetText(text(row.game.stats))
            local label2 = text(row.game.playText)
            row.play:SetText(label2 ~= "" and label2 or L.MURLOC_PLAY)
        end
    end)
    layout()
end

local function openHub()
    if not hub then buildHub() end
    ns.ShowPanel(hub)
end

-- reglages d un jeu : la page des mini-jeux, ce jeu deplie
function Games.ShowOptions(key)
    if not hub then buildHub() end
    if openKey ~= key then toggleRow(key) end
    ns.ShowPanel(hub)
end

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
local acc = 0
ev:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.5 then return end
    acc = 0
    checkTaxi()
end)
ev:SetScript("OnEvent", function(_, event)
    -- le compte sert aussi au podometre : note meme sans les mini-jeux
    if event == "PLAYER_LOGIN" then
        pcall(Account.Note)
    elseif event == "PLAYER_LEVEL_UP" then
        C_Timer.After(1, function() pcall(Account.Note) end)
        return
    end
    if ns.ModuleOff("jeux", ev) then return end
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
        -- records de guilde : vieilles fiches effacees, envoi et demande
        local g = gdb()
        local now = time()
        for k, e in pairs(g.scores) do
            if type(e) ~= "table" or not tonumber(e.at) or now - e.at > SCORE_KEEP then g.scores[k] = nil end
        end
        Comm = ns.Comm
        if Comm and Comm.On then Comm.On("JSCO", onScore) end
        Account.OnChange(function() Scores.Changed() end)
        C_Timer.After(35, function() Scores.Share(true) end)
    else
        C_Timer.After(0.3, checkTaxi)
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "PLAYER_LEVEL_UP" }) do
    pcall(ev.RegisterEvent, ev, e)
end

ns.RegisterModule({
    command = "jeux",
    panelName = "CorpUIGamesOptions",
    icon = ns.MEDIA .. "Jeux\\icon",
    title = function() return L.PAGE_GAMES end,
    desc = function() return L.GAMES_DESC end,
    Slash = function() openHub() end,
    Open = openHub,
})

-- banc d essai
Games._hub = { rows = rows, layout = layout, toggleRow = toggleRow, refresh = refreshHub, short = short,
               ui = function() return hub, openKey end }
