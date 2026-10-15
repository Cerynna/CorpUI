--[[--------------------------------------------------------------------------
    CorpUI - communication entre les CorpUI (prefixe "CorpUI")

    API (ns.Comm) :
      Send(kind, payload, channel, target)
          kind    : chaine courte ("NOTE", "HELLO"...), lettres/chiffres/_
          payload : chaine de n importe quelle taille (decoupee en morceaux
                    de 250 octets au plus, en-tete compris)
          channel : "GUILD" | "PARTY" | "RAID" | "INSTANCE_CHAT" |
                    "WHISPER" (target obligatoire) | "GROUP" (RAID en raid,
                    INSTANCE_CHAT en groupe d instance, sinon PARTY ; rien
                    si seul). Renvoie true si le message part en file.
      On(kind, fn [, withSelf])
          fn(sender, payload, channel) a la reception complete ; sender =
          "Nom-Royaume" ; nos propres messages ignores sauf withSelf.
      Version()            -> version de CorpUI (toc, sinon ns.VERSION)
      Users()              -> { ["Nom-Royaume"] = { version, seen, guild, group } }
      HasCorpUI(nom)       -> version ou nil ("Nom" ou "Nom-Royaume")
      Listen(fn)           -> fn() quand la liste change
      (en plus : Lookup(nom) -> version, seen ; PrintWho() ; Stats())

    Format d un morceau : "KIND:id:i:n:" + donnees. Les donnees sont
    echappees ("~" sert d echappement : \0, |, \n, \r) et jamais coupees au
    milieu d un caractere UTF-8 ni d un echappement. Le format ne ressemble
    pas a celui de la synchro des buffs (champs separes par ";"), qui
    partage le prefixe : chacun ignore les messages de l autre.

    File d envoi : jetons (6 d avance, 1 par seconde, moitie en combat),
    tour de role entre les messages (un HELLO ne reste pas coince derriere
    une longue note), code de retour de SendAddonMessage verifie (frein du
    serveur : on attend et on renvoie le meme morceau ; verrou des messages :
    on attend ; autre refus : message abandonne).

    Protocole HELLO : a la connexion (8 s apres) et a l entree dans un
    groupe, "HELLO <version>" en GUILD et en GROUP. A la reception d un
    HELLO diffuse, reponse "HELLO <version> G|P" en WHISPER a l emetteur
    (au plus une par joueur et par minute, jamais de rediffusion ; une
    reponse ne se repond pas). Pas de HELLO en combat : differe.

    Regles de ce client : aucune valeur secrete passee a SendAddonMessage,
    chaque argument recu verifie par issecretvalue avant toute comparaison,
    aucune globale, aucun crochet.
----------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...
local L = ns.L

local issecret = issecretvalue or function() return false end

local PREFIX = "CorpUI"
local MAX_LEN = 250           -- longueur d un morceau, en-tete compris
local MAX_PARTS = 400         -- au-dela (100 Ko) le message est refuse
local MAX_PENDING = 200       -- messages en cours de reassemblage
local STALE = 30              -- morceaux perimes apres 30 s sans suite
local REPLY_GAP = 60          -- une reponse HELLO par joueur et par minute
local HELLO_GAP = 15          -- pas deux HELLO de suite sur un canal
local KEEP_DAYS = 30          -- joueurs oublies apres 30 jours
local MAX_USERS = 500
local BURST, RATE = 6, 1.0    -- jetons d envoi : 6 d avance, 1 par seconde

local Comm = {}
ns.Comm = Comm

local handlers = {}           -- kind -> { { fn =, self = } }
local listeners = {}
local users = {}              -- "Nom-Royaume" -> { v = version, t = time(), gk = guilde }
local shortIndex = nil        -- "Nom" -> "Nom-Royaume" (false : plusieurs)
local sessionGuild = {}       -- vus par le canal de guilde pendant la session
local sessionGroup = {}       -- vus par un canal de groupe pendant la session
local groupSet = {}           -- membres actuels du groupe (noms complets)
local replied = {}            -- "Nom-Royaume" -> GetTime() de notre derniere reponse
local stats = { sent = 0, dropped = 0, throttled = 0, received = 0, delivered = 0 }

---------------------------------------------------------------------------
-- Valeurs sures
---------------------------------------------------------------------------

-- chaine lisible, sinon nil (secret verifie avant tout)
local function str(v)
    if issecret(v) then return nil end
    if type(v) ~= "string" then return nil end
    return v
end

local function num(v)
    if issecret(v) then return nil end
    if type(v) ~= "number" then return nil end
    return v
end

-- appel protege dont le resultat est un booleen lisible
local function yes(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn, ...)
    if not ok or issecret(v) then return false end
    return v == true
end

-- version propre : chiffres, lettres, points, tirets ; 16 caracteres
local function cleanVersion(v)
    v = str(v)
    if not v then return nil end
    v = v:match("^%s*(.-)%s*$")
    if v == "" or #v > 16 or not v:match("^[%w%.%-_]+$") then return nil end
    return v
end

---------------------------------------------------------------------------
-- Noms : "Nom-Royaume" partout (royaume sans espace, comme le serveur)
---------------------------------------------------------------------------

local realmCache
local function myRealm()
    if realmCache then return realmCache end
    local r
    if GetNormalizedRealmName then
        local ok, v = pcall(GetNormalizedRealmName)
        r = ok and str(v) or nil
    end
    if not r or r == "" then
        local ok, v = pcall(GetRealmName)
        v = ok and str(v) or nil
        r = v and (v:gsub("[%s%-]", "")) or nil
    end
    if r and r ~= "" then
        realmCache = r
        return r
    end
    return "?"
end

local function fullName(name)
    name = str(name)
    if not name then return nil end
    -- noms uniques regionaux ("Prenom Nom") : voir ns.Names (Core.lua)
    if ns.Names and ns.Names.Regional() then return ns.Names.Sender(name) end
    name = name:match("^%s*(.-)%s*$")
    if name == "" then return nil end
    local n, r = name:match("^([^%-]+)%-(.+)$")
    if n then
        r = r:gsub("%s", "")
        if r == "" then return n .. "-" .. myRealm() end
        return n .. "-" .. r
    end
    return name .. "-" .. myRealm()
end

local meCache
local function me()
    if meCache then return meCache end
    if ns.Names and ns.Names.Regional() then
        meCache = ns.Names.Me()
        return meCache
    end
    local ok, n = pcall(UnitName, "player")
    local full = ok and fullName(n) or nil
    if full and myRealm() ~= "?" then meCache = full end
    return full
end

-- nom affiche : sans le royaume s il est le notre
local function shortName(full)
    if ns.Names and ns.Names.Regional() then return full end
    local n, r = full:match("^([^%-]+)%-(.+)$")
    if n and r == myRealm() then return n end
    return full
end

---------------------------------------------------------------------------
-- Guilde et groupe
---------------------------------------------------------------------------

local function inGuild()
    return yes(IsInGuild)
end

local function guildName()
    if not GetGuildInfo then return nil end
    local ok, g = pcall(GetGuildInfo, "player")
    g = ok and str(g) or nil
    if g == "" then return nil end
    return g
end

-- canal de groupe : RAID en raid, INSTANCE_CHAT en groupe d instance,
-- sinon PARTY ; nil si seul
local function groupChannel()
    local home, inst = LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE
    if yes(IsInRaid, home) then return "RAID" end
    if inst ~= nil and yes(IsInGroup, inst) then return "INSTANCE_CHAT" end
    if yes(IsInGroup, home) then return "PARTY" end
    return nil
end

local GROUP_CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true }

-- membres actuels du groupe (noms complets) ; les valeurs secretes sont sautees
local function readGroup()
    local set = {}
    local raid = yes(IsInRaid)
    local unitPrefix, count = "party", 4
    if raid then unitPrefix, count = "raid", 40 end
    local regional = ns.Names and ns.Names.Regional()
    for i = 1, count do
        if regional then
            local full = ns.Names.Unit(unitPrefix .. i)
            if full then set[full] = true end
        else
            local ok, name, realm = pcall(UnitName, unitPrefix .. i)
            name = ok and str(name) or nil
            if name and name ~= "" then
                realm = str(realm)
                if realm == "" then realm = nil end
                local full = fullName(realm and (name .. "-" .. realm) or name)
                if full then set[full] = true end
            end
        end
    end
    return set
end

local function isGuild(who, u)
    if sessionGuild[who] then return true end
    local g = u and u.gk
    return g ~= nil and g == guildName()
end

local function isGroup(who)
    return groupSet[who] == true or sessionGroup[who] == true
end

---------------------------------------------------------------------------
-- Notifications
---------------------------------------------------------------------------

local notifyPending = false
local function changed()
    shortIndex = nil
    if notifyPending then return end
    notifyPending = true
    C_Timer.After(0, function()
        notifyPending = false
        for _, fn in ipairs(listeners) do
            local ok, err = pcall(fn)
            if not ok then geterrorhandler()(err) end
        end
    end)
end

---------------------------------------------------------------------------
-- Version
---------------------------------------------------------------------------

local versionCache
function Comm.Version()
    if versionCache then return versionCache end
    local v
    local fn = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if fn then
        local ok, r = pcall(fn, ADDON_NAME, "Version")
        if ok then v = cleanVersion(r) end
    end
    versionCache = v or cleanVersion(ns.VERSION) or "?"
    return versionCache
end

-- a plus recente que b ? (comparaison des nombres, "1.10" > "1.9")
local function digits(v)
    local t = {}
    for d in tostring(v):gmatch("%d+") do t[#t + 1] = tonumber(d) end
    return t
end

local function isNewer(a, b)
    if not a or not b then return false end
    local pa, pb = digits(a), digits(b)
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x > y end
    end
    return false
end
Comm.IsNewer = isNewer

-- version la plus recente vue, et un joueur qui l a
local function newestKnown()
    local best, by
    local mine = Comm.Version()
    for who, u in pairs(users) do
        if isNewer(u.v, mine) and (not best or isNewer(u.v, best)) then best, by = u.v, who end
    end
    return best, by
end

-- Notre version est depassee : avertissement bien visible dans le chat
-- (en orange, avec le joueur qui a la nouvelle version et le lien de
-- telechargement). Une fois par session et par version : une version
-- encore plus recente vue plus tard previent de nouveau. Aussi a la
-- connexion, d apres les joueurs vus les 30 derniers jours.
local RELEASES = "https://github.com/Cerynna/CorpUI/releases/latest"
local warnedVersion
local function warnOutdated(version, who)
    local mine = Comm.Version()
    if not version or not isNewer(version, mine) then return end
    if warnedVersion and not isNewer(version, warnedVersion) then return end
    warnedVersion = version
    ns.Say(string.format(L.COMM_OUTDATED, version, who and shortName(who) or "?", mine))
    ns.Chat("    " .. string.format(L.COMM_UPDATE_HINT, RELEASES))
end
Comm.WarnOutdated = warnOutdated

---------------------------------------------------------------------------
-- Joueurs connus
---------------------------------------------------------------------------

-- un CorpUI s est annonce (HELLO ou reponse)
local function note(who, version, channel, ctx)
    local u = users[who]
    local fresh = u == nil
    if not u then
        u = {}
        users[who] = u
    end
    local before = u.v
    u.v, u.t = version, time()
    ctx = ctx or ""
    local g = channel == "GUILD" or ctx:find("G", 1, true) ~= nil
    local p = GROUP_CHANNELS[channel] == true or ctx:find("P", 1, true) ~= nil
    if g then
        sessionGuild[who] = true
        u.gk = guildName() or u.gk
    end
    if p and groupChannel() then sessionGroup[who] = true end
    if fresh or before ~= version or g or p then changed() end
    warnOutdated(version, who)
end

function Comm.Users()
    local out = {}
    for who, u in pairs(users) do
        out[who] = { version = u.v, seen = u.t, guild = isGuild(who, u), group = isGroup(who) }
    end
    return out
end

local function buildShortIndex()
    shortIndex = {}
    for who in pairs(users) do
        -- "Nom-Royaume" ou "Prenom Nom" : index par le premier mot
        local n = who:match("^([^%-%s]+)[%-%s]")
        if n then
            if shortIndex[n] == nil then shortIndex[n] = who else shortIndex[n] = false end
        end
    end
end

-- version et date de derniere annonce d un joueur ("Nom" ou "Nom-Royaume")
function Comm.Lookup(name)
    local raw = str(name)
    local full = fullName(raw)
    if not full then return nil end
    if full == me() then return Comm.Version(), nil end
    local u = users[full]
    if not u and not raw:find("-", 1, true) then
        -- nom sans royaume absent de notre royaume : un seul joueur de ce nom ?
        if not shortIndex then buildShortIndex() end
        local alt = shortIndex[raw]
        if alt then u = users[alt] end
    end
    if u then return u.v, u.t end
    return nil
end

function Comm.HasCorpUI(name)
    local v = Comm.Lookup(name)
    return v
end

function Comm.Listen(fn)
    if type(fn) == "function" then listeners[#listeners + 1] = fn end
end

function Comm.On(kind, fn, withSelf)
    if type(kind) ~= "string" or type(fn) ~= "function" then return end
    handlers[kind] = handlers[kind] or {}
    table.insert(handlers[kind], { fn = fn, self = withSelf and true or false })
end

function Comm.Stats()
    local out = {}
    for k, v in pairs(stats) do out[k] = v end
    out.queued = Comm._queue and #Comm._queue or 0
    return out
end

---------------------------------------------------------------------------
-- Echappement et decoupage
---------------------------------------------------------------------------

local ESC = { ["~"] = "~~", ["|"] = "~p", ["\n"] = "~n", ["\r"] = "~r", ["\0"] = "~0" }
local UNESC = { ["~"] = "~", p = "|", n = "\n", r = "\r", ["0"] = "\0" }

local function decode(s)
    return (s:gsub("~(.)", function(c) return UNESC[c] or "" end))
end

-- morceaux de "room" octets au plus, une fois echappes ; jamais coupes au
-- milieu d un caractere UTF-8 ni d un echappement
local function split(payload, room)
    local parts, cur, size = {}, {}, 0
    local i, n = 1, #payload
    while i <= n do
        local b = payload:byte(i)
        local j = i
        if b >= 0xC0 then
            while j < n and j - i < 3 do
                local c = payload:byte(j + 1)
                if c < 0x80 or c > 0xBF then break end
                j = j + 1
            end
        end
        local ch = payload:sub(i, j)
        ch = ESC[ch] or ch
        if size + #ch > room and size > 0 then
            parts[#parts + 1] = table.concat(cur)
            cur, size = {}, 0
        end
        cur[#cur + 1] = ch
        size = size + #ch
        i = j + 1
    end
    if size > 0 or #parts == 0 then parts[#parts + 1] = table.concat(cur) end
    return parts
end

-- numero de message : base 36, depart au hasard (un /reload ne reprend pas
-- les memes numeros)
local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
local seq = math.random(0, 36 * 36 * 36)
local function nextId()
    seq = (seq + 1) % (36 * 36 * 36 * 36)
    local n, s = seq, ""
    repeat
        local d = n % 36
        s = B36:sub(d + 1, d + 1) .. s
        n = math.floor(n / 36)
    until n == 0
    return s
end

local function pack(kind, payload)
    local id = nextId()
    local nd = 1
    local parts
    for _ = 1, 4 do
        local room = MAX_LEN - (#kind + #id + 4 + 2 * nd)
        parts = split(payload, room)
        if #tostring(#parts) <= nd then break end
        nd = #tostring(#parts)
    end
    if #parts > MAX_PARTS then return nil end
    local n = #parts
    for i = 1, n do
        parts[i] = kind .. ":" .. id .. ":" .. i .. ":" .. n .. ":" .. parts[i]
    end
    return parts
end

---------------------------------------------------------------------------
-- File d envoi (jetons, tour de role, code de retour)
---------------------------------------------------------------------------

local R = (Enum and Enum.SendAddonMessageResult) or {}
local RES_OK = R.Success or 0
local RES_THROTTLE = { [R.AddonMessageThrottle or 3] = true, [R.ChannelThrottle or 8] = true }
local RES_LOCKDOWN = R.AddOnMessageLockdown or 11
local RES_GENERAL = R.GeneralError or 9

local queue = {}             -- { kind, parts, pos, channel, target, tries }
Comm._queue = queue
local tokens, lastFill = BURST, nil
local pauseUntil = 0

local function lockedDown()
    return C_ChatInfo ~= nil and yes(C_ChatInfo.InChatMessagingLockdown)
end

local pump = CreateFrame("Frame")
pump:Hide()

local function sendOne(m)
    local text = m.parts[m.pos]
    local fn = C_ChatInfo and C_ChatInfo.SendAddonMessage
    if not fn then return "drop" end
    local ok, res
    if m.target then
        ok, res = pcall(fn, PREFIX, text, m.channel, m.target)
    else
        ok, res = pcall(fn, PREFIX, text, m.channel)
    end
    if not ok then return "drop" end
    if issecret(res) or res == nil or res == true then return "ok" end
    if res == false then return "drop" end
    if type(res) ~= "number" then return "ok" end
    if res == RES_OK then return "ok" end
    if RES_THROTTLE[res] then return "wait" end
    if res == RES_LOCKDOWN then return "lock" end
    if res == RES_GENERAL and m.tries < 3 then
        m.tries = m.tries + 1
        return "retry"
    end
    return "drop"
end

local function pumpStep()
    local now = GetTime()
    if not lastFill then lastFill = now end
    local rate = (InCombatLockdown and InCombatLockdown()) and RATE / 2 or RATE
    tokens = math.min(BURST, tokens + (now - lastFill) * rate)
    lastFill = now
    if #queue == 0 then
        pump:Hide()
        return
    end
    if now < pauseUntil or lockedDown() then return end
    local budget = 3   -- au plus trois morceaux par image
    while budget > 0 and tokens >= 1 and #queue > 0 do
        budget = budget - 1
        local m = table.remove(queue, 1)
        local r = sendOne(m)
        if r == "ok" then
            tokens = tokens - 1
            stats.sent = stats.sent + 1
            m.pos = m.pos + 1
            if m.pos <= #m.parts then queue[#queue + 1] = m end
        elseif r == "wait" then
            -- frein du serveur : on attend, puis le meme morceau repart
            stats.throttled = stats.throttled + 1
            tokens = 0
            pauseUntil = now + 1.5
            table.insert(queue, 1, m)
            return
        elseif r == "lock" then
            pauseUntil = now + 5
            table.insert(queue, 1, m)
            return
        elseif r == "retry" then
            pauseUntil = now + 1
            table.insert(queue, 1, m)
            return
        else
            stats.dropped = stats.dropped + 1
        end
    end
end

pump:SetScript("OnUpdate", function()
    local ok, err = pcall(pumpStep)
    if not ok then
        geterrorhandler()(err)
        pump:Hide()
    end
end)

local CHANNELS = { GUILD = true, PARTY = true, RAID = true, INSTANCE_CHAT = true, WHISPER = true, GROUP = true }

function Comm.Send(kind, payload, channel, target)
    if issecret(kind) or issecret(payload) or issecret(channel) or issecret(target) then return false end
    if type(kind) ~= "string" or #kind == 0 or #kind > 16 or not kind:match("^[%w_]+$") then return false end
    if payload == nil then payload = "" end
    if type(payload) == "number" then payload = tostring(payload) end
    if type(payload) ~= "string" or type(channel) ~= "string" then return false end
    channel = channel:upper()
    if not CHANNELS[channel] then return false end
    if channel == "GROUP" then
        channel = groupChannel()
        if not channel then return false end
    elseif channel == "GUILD" then
        if not inGuild() then return false end
    elseif channel == "WHISPER" then
        target = str(target)
        if target and ns.Names then target = ns.Names.Whisper(fullName(target) or target) end
        if not target or target == "" then return false end
    end
    if channel ~= "WHISPER" then target = nil end
    local parts = pack(kind, payload)
    if not parts then return false end
    queue[#queue + 1] = { kind = kind, parts = parts, pos = 1, channel = channel, target = target, tries = 0 }
    pump:Show()
    return true
end

---------------------------------------------------------------------------
-- Reception et reassemblage
---------------------------------------------------------------------------

local pending = {}           -- cle -> { n, got, parts, at, channel }
local pendingCount = 0
local done = {}              -- cle -> GetTime() : message complet (doublons tardifs ignores)

local function sweep(now)
    for key, p in pairs(pending) do
        if now - p.at > STALE then
            pending[key] = nil
            pendingCount = pendingCount - 1
        end
    end
    for key, t in pairs(done) do
        if now - t > STALE then done[key] = nil end
    end
end

local function wantsSelf(kind)
    for _, h in ipairs(handlers[kind] or {}) do
        if h.self then return true end
    end
    return false
end

local function deliver(kind, who, payload, channel, own)
    stats.delivered = stats.delivered + 1
    if not own then
        local u = users[who]
        if u then u.t = time() end
    end
    for _, h in ipairs(handlers[kind] or {}) do
        if not own or h.self then
            local ok, err = pcall(h.fn, who, payload, channel)
            if not ok then geterrorhandler()(err) end
        end
    end
end

local function onAddon(prefix, text, channel, sender)
    -- tout argument secret : message ignore (aucune comparaison avant)
    if issecret(prefix) or issecret(text) or issecret(channel) or issecret(sender) then return end
    if type(prefix) ~= "string" or prefix ~= PREFIX then return end
    if type(text) ~= "string" or type(channel) ~= "string" or type(sender) ~= "string" then return end
    local kind, id, i, n, data = text:match("^([%w_]+):(%w+):(%d+):(%d+):(.*)$")
    if not kind then return end   -- autre format (synchro des buffs)
    i, n = tonumber(i), tonumber(n)
    if not i or not n or n < 1 or n > MAX_PARTS or i < 1 or i > n then return end
    local who = fullName(sender)
    if not who then return end
    stats.received = stats.received + 1
    local own = who == me()
    if own and not wantsSelf(kind) then return end
    if not handlers[kind] then return end
    if n == 1 then
        deliver(kind, who, decode(data), channel, own)
        return
    end
    local now = GetTime()
    sweep(now)
    local key = who .. "\001" .. kind .. "\001" .. id
    if done[key] then return end
    local p = pending[key]
    if p and p.n ~= n then
        pending[key] = nil
        pendingCount = pendingCount - 1
        p = nil
    end
    if not p then
        if pendingCount >= MAX_PENDING then return end
        p = { n = n, got = 0, parts = {}, channel = channel }
        pending[key] = p
        pendingCount = pendingCount + 1
    end
    p.at = now
    if not p.parts[i] then
        p.parts[i] = data
        p.got = p.got + 1
    end
    if p.got >= n then
        pending[key] = nil
        pendingCount = pendingCount - 1
        done[key] = now
        deliver(kind, who, decode(table.concat(p.parts, "", 1, n)), p.channel, own)
    end
end
Comm._onAddon = onAddon

---------------------------------------------------------------------------
-- HELLO
---------------------------------------------------------------------------

local loggedIn = false
local helloScope = nil        -- "all" | "group" en attente
local helloTimer = false
local helloAfterCombat = nil
local lastHello = {}          -- "GUILD" / "GROUP" -> GetTime()
local replyPending = {}       -- "Nom-Royaume" -> lettres G/P (reponse a envoyer)
local replyAfterCombat = {}

local function inCombat()
    return InCombatLockdown ~= nil and InCombatLockdown() == true
end

local function mergeScope(a, b)
    if a == "all" or b == "all" then return "all" end
    return a or b
end

local function sendHello(scope)
    if inCombat() then
        helloAfterCombat = mergeScope(helloAfterCombat, scope)
        return
    end
    local v = Comm.Version()
    local now = GetTime()
    if scope == "all" and inGuild() and (not lastHello.GUILD or now - lastHello.GUILD >= HELLO_GAP) then
        if Comm.Send("HELLO", v, "GUILD") then lastHello.GUILD = now end
    end
    if groupChannel() and (not lastHello.GROUP or now - lastHello.GROUP >= HELLO_GAP) then
        if Comm.Send("HELLO", v, "GROUP") then lastHello.GROUP = now end
    end
end

local function scheduleHello(scope, delay)
    helloScope = mergeScope(helloScope, scope)
    if helloTimer then return end
    helloTimer = true
    C_Timer.After(delay, function()
        helloTimer = false
        local s = helloScope
        helloScope = nil
        if s then sendHello(s) end
    end)
end
Comm._hello = sendHello

local function sendReply(who)
    local tag = replyPending[who]
    replyPending[who] = nil
    if not tag then return end
    if inCombat() then
        replyAfterCombat[who] = tag
        return
    end
    Comm.Send("HELLO", Comm.Version() .. " " .. tag, "WHISPER", who)
end

Comm.On("HELLO", function(who, payload, channel)
    local v, ctx = (str(payload) or ""):match("^%s*(%S+)%s*(%a*)")
    v = cleanVersion(v)
    if not v then return end
    note(who, v, channel, ctx)
    -- une reponse ne se repond pas ; jamais de rediffusion
    if channel == "WHISPER" then return end
    local tag = channel == "GUILD" and "G" or "P"
    if replyPending[who] then
        if not replyPending[who]:find(tag, 1, true) then replyPending[who] = replyPending[who] .. tag end
        return
    end
    local now = GetTime()
    if replied[who] and now - replied[who] < REPLY_GAP then return end
    replied[who] = now
    replyPending[who] = tag
    -- reponses etalees : quand un joueur se connecte, toute la guilde ne
    -- repond pas dans la meme seconde
    C_Timer.After(1 + math.random() * 3, function() sendReply(who) end)
end)

---------------------------------------------------------------------------
-- /corp qui
---------------------------------------------------------------------------

function Comm.PrintWho()
    local mine = Comm.Version()
    ns.Say(string.format(L.COMM_WHO_HEAD, mine))
    local list = {}
    for who, u in pairs(users) do
        local g, p = isGuild(who, u), isGroup(who)
        if g or p then list[#list + 1] = { who = who, u = u, g = g, p = p } end
    end
    table.sort(list, function(a, b) return a.who < b.who end)
    if #list == 0 then ns.Chat("  " .. L.COMM_WHO_NONE) end
    for _, e in ipairs(list) do
        local where = {}
        if e.g then where[#where + 1] = L.COMM_WHO_GUILD end
        if e.p then where[#where + 1] = L.COMM_WHO_GROUP end
        local color = "|cffffffff"
        if isNewer(e.u.v, mine) then color = "|cff40ff40" elseif isNewer(mine, e.u.v) then color = "|cffa0a0a0" end
        ns.Chat(string.format("  |cffffd100%s|r  %sv%s|r  (%s)  |cff808080%s|r", shortName(e.who), color,
            e.u.v, table.concat(where, ", "), ns.FormatAgo(e.u.t)))
    end
    local best = newestKnown()
    if best then ns.Chat("  |cff40ff40" .. string.format(L.COMM_NEWER, best) .. "|r") end
end

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

local wasGrouped = false

local function rosterChanged()
    local grouped = groupChannel() ~= nil
    groupSet = grouped and readGroup() or {}
    if not grouped then
        -- les joueurs quittent le groupe ; ceux de la guilde restent connus
        for k in pairs(sessionGroup) do sessionGroup[k] = nil end
    end
    if loggedIn and grouped and not wasGrouped then scheduleHello("group", 3) end
    wasGrouped = grouped
    changed()
end

local function afterCombat()
    if helloAfterCombat then
        local s = helloAfterCombat
        helloAfterCombat = nil
        scheduleHello(s, 2)
    end
    local k = 0
    for who, tag in pairs(replyAfterCombat) do
        replyAfterCombat[who] = nil
        replyPending[who] = tag
        k = k + 1
        C_Timer.After(1 + k * 0.5, function() sendReply(who) end)
    end
end

-- guilde connue apres coup (GetGuildInfo vide a la connexion) : on la note
-- pour les joueurs vus par le canal de guilde
local function guildKnown()
    local g = guildName()
    if not g then return end
    for who in pairs(sessionGuild) do
        local u = users[who]
        if u and not u.gk then u.gk = g end
    end
end

local ev = CreateFrame("Frame")
local rosterQueued = false
ev:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        onAddon(...)
    elseif event == "GROUP_ROSTER_UPDATE" or event == "GROUP_JOINED" or event == "GROUP_LEFT" then
        -- plusieurs dans la meme image : un seul passage, a la suivante
        if not rosterQueued then
            rosterQueued = true
            C_Timer.After(0, function() rosterQueued = false rosterChanged() end)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        afterCombat()
    elseif event == "PLAYER_GUILD_UPDATE" or event == "GUILD_ROSTER_UPDATE" then
        guildKnown()
    end
end)
for _, e in ipairs({ "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE", "GROUP_JOINED", "GROUP_LEFT",
                     "PLAYER_REGEN_ENABLED", "PLAYER_GUILD_UPDATE", "GUILD_ROSTER_UPDATE" }) do
    pcall(ev.RegisterEvent, ev, e)
end

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
end

-- sauvegarde : CorpUIDB.comm.users (au compte, hors profils), purge des
-- joueurs muets depuis 30 jours
local function attachStore()
    local root = ns.InitRoot()
    root.comm = type(root.comm) == "table" and root.comm or {}
    local saved = type(root.comm.users) == "table" and root.comm.users or {}
    -- noms enregistres sous une autre ecriture ("Prenom Nom-Royaume" des
    -- premieres versions) : ramenes a l identite actuelle
    local moves = {}
    for who in pairs(saved) do
        local norm = type(who) == "string" and fullName(who) or nil
        if norm and norm ~= who then moves[who] = norm end
    end
    for who, norm in pairs(moves) do
        local u = saved[who]
        saved[who] = nil
        if not saved[norm] or (type(u) == "table" and type(saved[norm]) == "table"
            and (u.t or 0) > (saved[norm].t or 0)) then
            saved[norm] = u
        end
    end
    for who, u in pairs(users) do saved[who] = u end
    local limit = time() - KEEP_DAYS * 86400
    local list = {}
    for who, u in pairs(saved) do
        if type(u) ~= "table" or type(u.t) ~= "number" or u.t < limit or not cleanVersion(u.v) then
            saved[who] = nil
        else
            list[#list + 1] = who
        end
    end
    if #list > MAX_USERS then
        table.sort(list, function(a, b) return saved[a].t > saved[b].t end)
        for i = MAX_USERS + 1, #list do saved[list[i]] = nil end
    end
    root.comm.users = saved
    users = saved
    shortIndex = nil
end

table.insert(ns.inits, function()
    attachStore()
    loggedIn = true
    groupSet = groupChannel() and readGroup() or {}
    wasGrouped = groupChannel() ~= nil
    scheduleHello("all", 8)
    -- version depassee d apres les joueurs deja vus (apres les premieres reponses)
    C_Timer.After(15, function() warnOutdated(newestKnown()) end)
    -- inscrit a la connexion : le module Buffs reste le premier de la liste
    -- (clic droit de la minicarte)
    ns.RegisterModule({
        command = "qui",
        desc = function() return L.COMM_DESC end,
        Slash = function() Comm.PrintWho() end,
    })
    changed()
end)
