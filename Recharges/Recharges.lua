--[[--------------------------------------------------------------------------
    CorpUI - module Recharges (CD de raid facon MRT + barre de CD perso)

    Deux affichages :
      - suivi des CD de raid : une ligne par joueur du groupe et par sort
        coche dans le selecteur (Renaissance, Innervation, Mur protecteur...),
        avec le temps restant ou "Pret" ;
      - barre de CD perso : les sorts choisis par le joueur (cases de sa
        classe ou n importe quel sort glisse depuis le grimoire), avec le
        decompte natif du cadre Cooldown.

    Ce que le client laisse lire (SpellDocumentation, branche forever) :
      - C_Spell.GetSpellCooldown : startTime / duration SECRETS quand les
        recharges sont restreintes (combat...), mais isActive et isOnGCD ne
        le sont jamais. On sait donc toujours SI un de nos sorts est en
        recharge ; la duree vient de la lecture quand elle est lisible
        (retenue par personnage), sinon de la base (Sorts.lua) ;
      - C_Spell.GetSpellCooldownDuration : objet de duree accepte tel quel
        par le cadre Cooldown (barre perso, comme Barres.lua) ;
      - UNIT_SPELLCAST_SUCCEEDED : numero de sort secret quand les
        incantations sont restreintes : ecarte (issecretvalue) ;
      - SendAddonMessage : rien de secret ; bloque pendant les verrous de
        messages (ns.Comm attend la fin du verrou).

    Recharge "vraie" et recharge globale : un sort actif depuis plus de
    1,7 s, ou dont la duree lisible depasse 1,6 s, ou que le jeu dit hors
    recharge globale (isOnGCD == false, lu sur SPELL_UPDATE_COOLDOWN), ou
    que l on vient de voir lancer.

    Partage (ns.Comm, canal du groupe) :
      CDH "1;CLASSE;Q;cle=reste/duree,..." : nos sorts connus et leur etat
          (reste -1 = inconnu, 0 = pret). Q = "reponds-moi" : envoye en
          arrivant dans un groupe ou apres un rechargement ; les autres
          repondent par leur CDH (au plus un toutes les 10 s).
      CDU "1;cle=reste/duree" : un sort vient d etre utilise (ou remis a
          zero plus tot que prevu).
    Joueurs sans CorpUI : sorts de leur classe supposes prets (hors
    talents, d apres le niveau), mis en recharge quand on les voit lancer.

    Regles de ce client : aucune valeur secrete comparee ni envoyee, aucun
    crochet, aucune globale ; nos cadres ne sont pas proteges (affichage
    seulement), rien n est differe en combat.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local issecret = issecretvalue or function() return false end
local W8 = "Interface\\Buttons\\WHITE8X8"

local GCD_MAX = 1.6           -- au-dela, ce n est plus la recharge globale
local CONFIRM_AFTER = 1.7     -- actif depuis plus longtemps : vraie recharge
local REPLY_GAP = 10          -- une reponse CDH toutes les 10 s au plus
local SEEN_TRUST = 5          -- un CDU recent prime sur ce qu on voit lancer

local DEFAULTS = {
    raid = {
        enabled = true, vis = "group", width = 200, rowH = 16, rows = 24, title = true, tips = true, ask = true,
    },
    perso = {
        enabled = true, vis = "always", size = 34, spacing = 4, perRow = 8, hideReady = false, tips = false,
    },
}

local db, cdb                 -- CorpUIDB.cd, puis la partie du personnage
local Comm

---------------------------------------------------------------------------
-- Valeurs sures
---------------------------------------------------------------------------

local function str(v)
    if issecret(v) or type(v) ~= "string" then return nil end
    return v
end

local function num(v)
    if issecret(v) or type(v) ~= "number" then return nil end
    return v
end

-- booleen lisible (nil si secret ou erreur)
local function bool(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or issecret(v) then return nil end
    if v == nil then return false end
    return v and true or false
end

local function now() return GetTime() end

---------------------------------------------------------------------------
-- Noms : identite commune a tout CorpUI (ns.Names, Core.lua) : "Prenom Nom"
-- avec les noms uniques regionaux de ce client, sinon "Nom-Royaume"
---------------------------------------------------------------------------

local function unitFull(unit) return ns.Names.Unit(unit) end
local function me() return ns.Names.Me() end
-- lignes du suivi : prenom seul ; infobulle : nom complet
local function shortName(full) return ns.Names.Short(full) end
local function displayName(full) return ns.Names.Display(full) end

local function unitClass(unit)
    local ok, _, token = pcall(UnitClass, unit)
    return ok and str(token) or nil
end

---------------------------------------------------------------------------
-- Sorts : noms, icones, index par nom (tous rangs, toutes langues)
---------------------------------------------------------------------------

local nameCache = {}
local function spellName(id)
    if not id then return nil end
    local v = nameCache[id]
    if v ~= nil then return v or nil end
    local n
    if C_Spell and C_Spell.GetSpellName then
        local ok, r = pcall(C_Spell.GetSpellName, id)
        n = ok and str(r) or nil
    end
    nameCache[id] = n or false
    return n
end

local function spellIcon(id)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, t = pcall(C_Spell.GetSpellTexture, id)
        if ok and t and not issecret(t) then return t end
    end
    return 134400   -- point d interrogation
end

local byName       -- nom -> { entrees } (Rapidite de la nature : druide et chaman)
local function nameIndex()
    if byName then return byName end
    byName = {}
    for _, s in ipairs(ns.CD_SPELLS) do
        local ids = { s.id }
        for _, a in ipairs(s.alt or {}) do ids[#ids + 1] = a end
        for _, id in ipairs(ids) do
            local n = spellName(id)
            if n then
                byName[n] = byName[n] or {}
                table.insert(byName[n], s)
            end
        end
    end
    return byName
end

-- entree de la base pour un sort lance par un joueur de cette classe
local function entryFor(spellID, class)
    local s = ns.CD_BY_ID[spellID]
    if s and (not class or s.class == class) then return s end
    local list = nameIndex()[spellName(spellID) or ""]
    if not list then return nil end
    for _, e in ipairs(list) do
        if not class or e.class == class then return e end
    end
end

---------------------------------------------------------------------------
-- Nos sorts : rang connu, etat de recharge
---------------------------------------------------------------------------

local myClass
local function myLevel()
    local ok, v = pcall(UnitLevel, "player")
    return ok and num(v) or nil
end

local function isKnown(id)
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local v = bool(C_SpellBook.IsSpellKnown, id)
        if v ~= nil then return v end
    end
    if IsPlayerSpell then
        local v = bool(IsPlayerSpell, id)
        if v ~= nil then return v end
    end
    if IsSpellKnown then
        local v = bool(IsSpellKnown, id)
        if v ~= nil then return v end
    end
    return nil
end

-- numero de NOTRE rang d un sort de la base (nil : pas appris)
local function ownId(s)
    if s.item then
        local lv = myLevel()
        if s.class == myClass and (not lv or not s.lvl or lv >= s.lvl) then return s.id end
        return nil
    end
    local n = spellName(s.id)
    if n and C_Spell and C_Spell.GetSpellInfo then
        -- par le nom : seul un sort du grimoire repond, au rang le plus haut
        local ok, info = pcall(C_Spell.GetSpellInfo, n)
        if ok and type(info) == "table" then
            local id = num(info.spellID)
            if id and isKnown(id) ~= false then return id end
        end
    end
    if isKnown(s.id) then return s.id end
    return nil
end

-- etat de chaque sort suivi : own[numero] = { id, key, entry, active,
-- confirmed, since, castAt, start, ends, dur, unknown }
local own = {}
local ownKeys = {}            -- cle de la base -> etat (sorts de la base appris)
local scanned = false

local function learned(key)
    return cdb and cdb.learned and cdb.learned[key]
end

local function durationOf(s)
    if s.readDur then return s.readDur end
    if s.key then return learned(s.key) or (s.entry and s.entry.cd) end
    return nil
end

local function persoList()
    return cdb and cdb.list or {}
end

-- reconstruit la liste des sorts suivis (base + barre perso)
local function rebuildOwn()
    local keep = {}
    wipe(ownKeys)
    local function track(id, entry)
        if not id then return end
        local s = own[id] or { id = id }
        s.entry = entry or s.entry or entryFor(id, myClass)
        s.key = s.entry and s.entry.id or nil
        own[id] = s
        keep[id] = true
        if s.key then ownKeys[s.key] = s end
    end
    for _, e in ipairs(ns.CD_SPELLS) do
        if e.class == myClass then track(ownId(e), e) end
    end
    local list = persoList()
    for i, id in ipairs(list) do
        if not issecret(id) and type(id) == "number" then
            -- rang oublie ou remplace par un rang superieur : on suit le nom
            if isKnown(id) == false then
                local n = spellName(id)
                local ok, info = false, nil
                if n and C_Spell and C_Spell.GetSpellInfo then ok, info = pcall(C_Spell.GetSpellInfo, n) end
                local up = ok and type(info) == "table" and num(info.spellID) or nil
                if up and up ~= id and isKnown(up) ~= false then
                    list[i] = up
                    id = up
                else
                    id = nil
                end
            end
            track(id)
        end
    end
    for id in pairs(own) do
        if not keep[id] then own[id] = nil end
    end
end

---------------------------------------------------------------------------
-- Etat des autres (CorpUI ou vus)
---------------------------------------------------------------------------

-- peers["Nom-Royaume"] = { class, corpui, known = { [cle] = true }, at,
--                          cds = { [cle] = { ends, dur, unknown, src, at } } }
local peers = {}

local function peer(full)
    local p = peers[full]
    if not p then
        p = { cds = {} }
        peers[full] = p
    end
    return p
end

---------------------------------------------------------------------------
-- Partage
---------------------------------------------------------------------------

local refreshRaid, refreshPerso, layoutPerso   -- plus bas

local function encodeState(key, s)
    local rem, dur = 0, durationOf(s) or 0
    if s.active and s.confirmed then
        if s.ends then
            rem = math.max(1, math.floor(s.ends - now() + 0.5))
        else
            rem = -1
        end
    end
    return string.format("%d=%d/%d", key, rem, math.floor(dur + 0.5))
end

local function canSend()
    return Comm and Comm.Send and IsInGroup and bool(IsInGroup) == true
end

local function sendHello(query)
    if not canSend() or not myClass then return end
    local parts = {}
    for key, s in pairs(ownKeys) do parts[#parts + 1] = encodeState(key, s) end
    table.sort(parts)
    Comm.Send("CDH", "1;" .. myClass .. ";" .. (query and "Q" or "") .. ";" .. table.concat(parts, ","), "GROUP")
end

local function sendUse(s)
    if not canSend() or not s.key then return end
    Comm.Send("CDU", "1;" .. encodeState(s.key, s), "GROUP")
end

local function readEntry(p, text, src)
    local k, r, d = text:match("^(%d+)=(%-?%d+)/(%d+)$")
    k, r, d = tonumber(k), tonumber(r), tonumber(d)
    if not k or not ns.CD_BY_ID[k] then return end
    p.known = p.known or {}
    p.known[k] = true
    if r == 0 then
        p.cds[k] = nil
    elseif r < 0 then
        p.cds[k] = { unknown = true, dur = d > 0 and d or nil, src = src, at = now() }
    else
        p.cds[k] = { ends = now() + r, dur = d > 0 and d or r, src = src, at = now() }
    end
end

local lastReply = -REPLY_GAP
local replyPending = false

-- reponse a une demande : tout de suite (etalee sur 0,5-3 s), ou a la fin
-- du delai si on vient deja de repondre (un 2e arrivant ne reste pas sans)
local function reply()
    local wait = REPLY_GAP - (now() - lastReply)
    if wait <= 0 then
        lastReply = now()
        C_Timer.After(0.5 + math.random() * 2.5, function() sendHello(false) end)
    elseif not replyPending then
        replyPending = true
        C_Timer.After(wait + math.random() * 2, function()
            replyPending = false
            lastReply = now()
            sendHello(false)
        end)
    end
end

local function onHello(who, payload)
    local v, class, q, list = payload:match("^(%d+);(%u*);(%u*);(.*)$")
    if v ~= "1" then return end
    local p = peer(who)
    p.corpui, p.at = true, now()
    if class ~= "" then p.class = class end
    p.known = {}
    local fresh = {}
    for item in list:gmatch("[^,]+") do
        local k = tonumber(item:match("^(%d+)="))
        if k then fresh[k] = true end
        readEntry(p, item, "corpui")
    end
    for k in pairs(p.cds) do
        if not fresh[k] then p.cds[k] = nil end
    end
    if q == "Q" then reply() end
    if refreshRaid then refreshRaid() end
end

local function onUse(who, payload)
    local v, item = payload:match("^(%d+);(.+)$")
    if v ~= "1" then return end
    local p = peer(who)
    p.corpui, p.at = true, now()
    readEntry(p, item, "corpui")
    if refreshRaid then refreshRaid() end
end

---------------------------------------------------------------------------
-- Relevé de nos recharges
---------------------------------------------------------------------------

local function readCooldown(id)
    if not (C_Spell and C_Spell.GetSpellCooldown) then return nil end
    local ok, info = pcall(C_Spell.GetSpellCooldown, id)
    if not ok or type(info) ~= "table" then return nil end
    local act = info.isActive
    if issecret(act) then act = nil end
    local dur, start = num(info.duration), num(info.startTime)
    if act == nil then act = (dur and dur > 0) and true or false end
    local gcd = info.isOnGCD
    if issecret(gcd) then gcd = nil end
    return act and true or false, dur, start, gcd
end

local function confirm(s, t, dur, start, initial)
    s.confirmed = true
    local d = (dur and dur > GCD_MAX) and dur or nil
    if d then
        s.readDur = d
        if s.key and cdb then
            cdb.learned = cdb.learned or {}
            cdb.learned[s.key] = math.floor(d + 0.5)
        end
    end
    local st = (d and start) or s.castAt or ((not initial) and s.since) or nil
    local total = durationOf(s)
    if st and total then
        s.ends, s.unknown = st + total, false
    else
        s.ends, s.unknown = nil, true
    end
    if not initial then sendUse(s) end
end

local changedOwn = false

-- un sort : passage pret -> recharge -> pret
local function pollOne(s, t, fromEvent)
    if s.entry and s.entry.item then
        -- objet (pierre d ame) : etat tenu par l incantation vue
        if s.active and s.ends and t >= s.ends then
            s.active, s.confirmed, s.ends = false, false, nil
            changedOwn = true
        end
        return
    end
    local act, dur, start, gcd = readCooldown(s.id)
    if act == nil then return end
    if act then
        if not s.active then
            s.active, s.confirmed, s.since, s.readDur = true, false, t, nil
            s.initial = not scanned
            changedOwn = true
        end
        if not s.confirmed then
            local real
            if dur then
                -- duree lisible : elle seule fait foi
                real = dur > GCD_MAX
            else
                real = (fromEvent and gcd == false)
                    or (s.initial and gcd == false)
                    or (s.entry ~= nil and s.castAt ~= nil and t - s.castAt < 2)
                    or (t - s.since > CONFIRM_AFTER)
            end
            if real then
                confirm(s, t, dur, start, s.initial)
                changedOwn = true
            end
        elseif dur and dur > GCD_MAX and start then
            -- duree devenue lisible (fin du combat...) : on corrige
            local ends = start + dur
            if not s.ends or math.abs(ends - s.ends) > 2 then
                s.ends, s.unknown, s.readDur = ends, false, dur
                changedOwn = true
            end
        end
    elseif s.active then
        local early = s.confirmed and s.ends and (s.ends - t) > 3
        local wasUnknown = s.confirmed and s.unknown
        s.active, s.confirmed, s.ends, s.unknown, s.castAt, s.initial = false, false, nil, false, nil, nil
        changedOwn = true
        -- remise a zero (Morsure de glace...) ou fin d une duree inconnue
        if early or wasUnknown then sendUse(s) end
    end
end

local function pollOwn(fromEvent)
    local t = now()
    for _, s in pairs(own) do pollOne(s, t, fromEvent) end
    scanned = true
    if changedOwn then
        changedOwn = false
        if refreshPerso then refreshPerso() end
        if refreshRaid then refreshRaid() end
    end
end

-- incantation vue (nous ou un membre du groupe)
local function onCast(unit, spellID)
    if issecret(unit) or issecret(spellID) or type(unit) ~= "string" or type(spellID) ~= "number" then return end
    local t = now()
    if unit == "player" then
        local n = spellName(spellID)
        for _, s in pairs(own) do
            if s.id == spellID or (n and spellName(s.id) == n) then
                s.castAt = t
                if s.entry and s.entry.item then
                    s.active, s.confirmed, s.since = true, true, t
                    s.ends, s.unknown = t + (durationOf(s) or s.entry.cd), false
                    sendUse(s)
                    changedOwn = true
                end
            end
        end
        pollOwn(true)
        return
    end
    if not (unit:match("^raid%d+$") or unit:match("^party%d+$")) then return end
    -- tri rapide (40 joueurs qui lancent sans arret) : sort connu de la base ?
    if not entryFor(spellID, nil) then return end
    local full = unitFull(unit)
    if not full or full == me() then return end
    local class = unitClass(unit)
    local e = entryFor(spellID, class)
    if not e then return end
    local p = peer(full)
    p.class = p.class or class
    local cur = p.cds[e.id]
    -- un CorpUI nous dit deja tout : ce qu on voit ne sert qu a defaut
    if p.corpui and cur and cur.src == "corpui" and t - (cur.at or 0) < SEEN_TRUST then return end
    if p.corpui and p.known and p.known[e.id] and cur and cur.src == "corpui" and not cur.unknown then return end
    local dur = (cur and cur.dur) or e.cd
    p.cds[e.id] = { ends = t + dur, dur = dur, src = p.corpui and "corpui" or "seen", at = t }
    p.seen = p.seen or {}
    p.seen[e.id] = true
    if refreshRaid then refreshRaid() end
end

---------------------------------------------------------------------------
-- Groupe
---------------------------------------------------------------------------

local function members()
    local out = {}
    local function add(unit)
        local full = unitFull(unit)
        if not full then return end
        local lv
        local ok, v = pcall(UnitLevel, unit)
        lv = ok and num(v) or nil
        if lv and lv <= 0 then lv = nil end
        out[#out + 1] = {
            unit = unit, full = full, class = unitClass(unit) or (peers[full] and peers[full].class),
            level = lv, dead = bool(UnitIsDeadOrGhost, unit) == true,
            offline = bool(UnitIsConnected, unit) == false,
        }
    end
    if bool(IsInRaid) then
        local n = num(GetNumGroupMembers and GetNumGroupMembers()) or 0
        for i = 1, math.min(n, 40) do add("raid" .. i) end
    else
        add("player")
        if bool(IsInGroup) then
            for i = 1, 4 do add("party" .. i) end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Selection (selecteur de sorts)
---------------------------------------------------------------------------

local function raidSelected(key)
    local v = db and db.raid.spells[key]
    if v ~= nil then return v end
    local e = ns.CD_BY_ID[key]
    return e and ns.CD_DEFAULT_CATS[e.cat] or false
end

local catIndex = {}
for i, c in ipairs(ns.CD_CATS) do catIndex[c] = i end

local function fmtTime(sec)
    sec = math.max(0, math.floor(sec + 0.5))
    if sec >= 3600 then return string.format("%dh%02d", math.floor(sec / 3600), math.floor(sec % 3600 / 60)) end
    if sec >= 60 then return string.format("%d:%02d", math.floor(sec / 60), sec % 60) end
    return tostring(sec)
end

local function fmtCd(sec)
    if not sec then return "" end
    if sec >= 3600 then return string.format(L.CD_FMT_H, sec / 3600) end
    if sec >= 60 then return string.format(L.CD_FMT_MIN, math.floor(sec / 60 + 0.5)) end
    return string.format(L.CD_FMT_S, sec)
end

local function classColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.7, 0.7, 0.7
end

---------------------------------------------------------------------------
-- Suivi des CD de raid
---------------------------------------------------------------------------

local raidFrame
local raidDirty = false
local rowPool = {}
local lines = {}              -- lignes affichees : { m, e, state }
local inCombat = false

-- lignes : membres x sorts coches de leur classe
local function collect()
    wipe(lines)
    local mine = me()
    local t = now()
    for _, m in ipairs(members()) do
        local p = peers[m.full]
        for _, e in ipairs(ns.CD_SPELLS) do
            if e.class == m.class and raidSelected(e.id) then
                local has, st = false, nil
                if m.full == mine then
                    local s = ownKeys[e.id]
                    if s then
                        has = true
                        st = { src = "own", dur = durationOf(s) }
                        if s.active and s.confirmed then
                            st.ends, st.unknown = s.ends, s.unknown
                        end
                    end
                else
                    if p and p.corpui and p.known then
                        has = p.known[e.id] or false
                    else
                        has = (p and p.seen and p.seen[e.id]) or (not e.talent and (not m.level or not e.lvl or m.level >= e.lvl))
                    end
                    if has then
                        local c = p and p.cds[e.id]
                        if c and c.ends and c.ends <= t then
                            p.cds[e.id] = nil
                            c = nil
                        end
                        st = { src = (p and p.corpui) and "corpui" or (c and "seen" or "guess"), dur = c and c.dur or e.cd }
                        if c then st.ends, st.unknown = c.ends, c.unknown end
                    end
                end
                if has then lines[#lines + 1] = { m = m, e = e, st = st } end
            end
        end
    end
    table.sort(lines, function(a, b)
        local ca, cb = catIndex[a.e.cat] or 99, catIndex[b.e.cat] or 99
        if ca ~= cb then return ca < cb end
        if a.e.order ~= b.e.order then return a.e.order < b.e.order end
        local ra = a.st.unknown and 1e9 or (a.st.ends and (a.st.ends - t) or 0)
        local rb = b.st.unknown and 1e9 or (b.st.ends and (b.st.ends - t) or 0)
        if ra ~= rb then return ra < rb end
        return a.m.full < b.m.full
    end)
end

local function rowTooltip(row)
    if not db.raid.tips or not row.line then return end
    local ln = row.line
    local tip = ns.Tooltip(row, "ANCHOR_LEFT")
    if not pcall(tip.SetSpellByID, tip, ln.e.id) then tip:SetText(spellName(ln.e.id) or "?") end
    tip:AddLine(" ")
    local r, g, b = classColor(ln.m.class)
    tip:AddLine(displayName(ln.m.full), r, g, b)
    local src = ln.st.src
    tip:AddLine(src == "guess" and L.CD_SRC_GUESS or src == "seen" and L.CD_SRC_SEEN
        or src == "own" and L.CD_SRC_OWN or L.CD_SRC_CORPUI, 0.7, 0.7, 0.75, true)
    if ln.st.dur then tip:AddLine(string.format(L.CD_BASE, fmtCd(ln.st.dur)), 0.7, 0.7, 0.75) end
    if db.raid.ask and ln.m.full ~= me() then
        tip:AddLine(" ")
        tip:AddLine(L.CD_TIP_ASK, 0.3, 1, 0.4)
        tip:AddLine(L.CD_TIP_ASK_ON, 0.3, 1, 0.4)
    end
    tip:Show()
end

---------------------------------------------------------------------------
-- Clic sur une ligne : demander le sort au joueur en message prive.
-- C_ChatInfo.SendChatMessage est marquee HasRestrictions : refusee aux
-- addons pendant le verrou des messages (C_ChatInfo.InChatMessagingLockdown,
-- combats restreints). On le lit avant d envoyer ; un refus quand meme
-- (ADDON_ACTION_BLOCKED juste apres l appel) est signale au lieu du
-- "demande envoyee".
---------------------------------------------------------------------------

local lastAsk = {}            -- "Nom-Royaume:cle" -> GetTime() (anti-repetition)
local askBlocked = false      -- refus vu pendant notre appel
local askWatch = false

local function spellLink(id)
    if C_Spell and C_Spell.GetSpellLink then
        local ok, l = pcall(C_Spell.GetSpellLink, id)
        if ok and str(l) and l ~= "" then return l end
    end
    return spellName(id) or ("#" .. id)
end


local function chatLocked()
    return C_ChatInfo ~= nil and bool(C_ChatInfo.InChatMessagingLockdown) == true
end

local function ask(row, button)
    if button ~= "LeftButton" or not db.raid.ask or not row.line then return end
    local m, e, st = row.line.m, row.line.e, row.line.st
    if m.full == me() then return end
    local who, sname = shortName(m.full), spellName(e.id) or ("#" .. e.id)
    if m.offline or m.dead then
        ns.Say(string.format(L.CD_ASK_UNAVAILABLE, who))
        return
    end
    local rem = st.ends and (st.ends - now()) or nil
    if rem and rem > 0 then
        ns.Say(string.format(L.CD_ASK_NOT_READY, who, sname, fmtTime(rem)))
        return
    end
    local key = m.full .. ":" .. e.id
    if lastAsk[key] and now() - lastAsk[key] < 5 then return end
    if chatLocked() then
        ns.Say(L.CD_ASK_LOCKED)
        return
    end
    local msg = string.format(L.CD_ASK_MSG, spellLink(e.id))
    if IsShiftKeyDown and IsShiftKeyDown() then
        local ok, tn = pcall(UnitName, "target")
        tn = ok and str(tn) or nil
        if tn and tn ~= "" then msg = string.format(L.CD_ASK_MSG_ON, spellLink(e.id), tn) end
    end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if type(send) ~= "function" then return end
    lastAsk[key] = now()
    askBlocked, askWatch = false, true
    local ok = pcall(send, msg, "WHISPER", nil, ns.Names.Whisper(m.full))
    askWatch = false
    if not ok or askBlocked then
        ns.Say(L.CD_ASK_BLOCKED)
    else
        ns.Say(string.format(L.CD_ASK_SENT, who, sname))
    end
end

local function newRow()
    local row = CreateFrame("Frame", nil, raidFrame)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("TOPLEFT")
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetStatusBarTexture(W8)
    row.bar:SetMinMaxValues(0, 1)
    row.bg = row.bar:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, 0.06)
    row.name = row.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", 4, 0)
    row.name:SetJustifyH("LEFT")
    row.time = row.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.time:SetPoint("RIGHT", -4, 0)
    row.time:SetJustifyH("RIGHT")
    row.name:SetPoint("RIGHT", row.time, "LEFT", -4, 0)
    row:SetScript("OnEnter", rowTooltip)
    row:SetScript("OnMouseUp", ask)
    row:SetScript("OnLeave", function() ns.HideTooltip() end)
    return row
end

local function paintRow(row, t)
    local ln = row.line
    local st, m = ln.st, ln.m
    local r, g, b = classColor(m.class)
    local rem = st.ends and (st.ends - t) or nil
    if rem and rem <= 0 then rem, st.ends = nil, nil end
    if m.offline then
        row.bar:SetStatusBarColor(0.3, 0.3, 0.3, 0.5)
        row.bar:SetValue(1)
        row.time:SetText(L.CD_OFFLINE)
        row.time:SetTextColor(0.5, 0.5, 0.5)
    elseif rem then
        row.bar:SetStatusBarColor(r, g, b, 0.55)
        row.bar:SetValue((st.dur and st.dur > 0) and math.min(1, rem / st.dur) or 1)
        row.time:SetText(fmtTime(rem))
        row.time:SetTextColor(1, 1, 1)
    elseif st.unknown then
        row.bar:SetStatusBarColor(r, g, b, 0.35)
        row.bar:SetValue(1)
        row.time:SetText("?")
        row.time:SetTextColor(1, 0.75, 0.3)
    else
        row.bar:SetStatusBarColor(r, g, b, 0.18)
        row.bar:SetValue(1)
        row.time:SetText(m.dead and L.CD_DEAD or L.CD_READY)
        if m.dead then
            row.time:SetTextColor(0.85, 0.3, 0.3)
        elseif st.src == "guess" then
            row.time:SetTextColor(0.6, 0.8, 0.6)
        else
            row.time:SetTextColor(0.3, 1, 0.4)
        end
    end
    row.name:SetTextColor(r, g, b)
    row:SetAlpha((m.dead or m.offline) and 0.6 or 1)
end

local function raidVisible()
    if not db or not db.raid.enabled then return false end
    if ns.moversShown then return true end
    local v = db.raid.vis
    if v == "always" then return true end
    if v == "combat" then return inCombat end
    if v == "raid" then return bool(IsInRaid) == true end
    return bool(IsInGroup) == true
end

local function layoutRaid()
    if not raidFrame then return end
    local o = db.raid
    local head = o.title and 18 or 0
    local shown = math.min(#lines, o.rows)
    for i = 1, shown do
        local row = rowPool[i] or newRow()
        rowPool[i] = row
        row.line = lines[i]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", raidFrame, "TOPLEFT", 0, -head - (i - 1) * (o.rowH + 1))
        row:SetSize(o.width, o.rowH)
        row.icon:SetSize(o.rowH, o.rowH)
        row.icon:SetTexture(spellIcon(lines[i].e.id))
        row.bar:ClearAllPoints()
        row.bar:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 1, 0)
        row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        row.name:SetText(shortName(lines[i].m.full))
        row:EnableMouse((o.tips or o.ask) and true or false)
        row:Show()
    end
    for i = shown + 1, #rowPool do rowPool[i]:Hide(); rowPool[i].line = nil end
    raidFrame.title:SetShown(o.title and true or false)
    local extra = #lines - shown
    raidFrame.more:SetText(extra > 0 and ("+" .. extra) or "")
    local rowsH = math.max(shown, ns.moversShown and 3 or 0) * (o.rowH + 1)
    raidFrame:SetSize(o.width, math.max(head + rowsH, 16))
    raidFrame.empty:SetShown(shown == 0)
    raidFrame:SetShown(raidVisible() and (shown > 0 or ns.moversShown or o.vis == "always"))
end

refreshRaid = function()
    if not raidFrame then return end
    collect()
    layoutRaid()
    local t = now()
    for _, row in ipairs(rowPool) do
        if row:IsShown() and row.line then paintRow(row, t) end
    end
end

local function buildRaid()
    local o = db.raid
    o.pos = o.pos or { point = "LEFT", x = 30, y = 80 }
    raidFrame = CreateFrame("Frame", "CorpUIRaidCD", UIParent)
    raidFrame:SetSize(o.width, 40)
    raidFrame:SetFrameStrata("LOW")
    ns.ApplyPos(raidFrame, o.pos)
    raidFrame.title = raidFrame:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(raidFrame.title, 11)
    raidFrame.title:SetPoint("TOPLEFT", 2, -2)
    raidFrame.title:SetText(L.CD_TAB_RAID)
    local C = ns.COLORS
    raidFrame.title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    raidFrame.more = raidFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    raidFrame.more:SetPoint("TOPRIGHT", -2, -3)
    raidFrame.empty = raidFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    raidFrame.empty:SetPoint("TOPLEFT", 2, -20)
    raidFrame.empty:SetText(L.CD_EMPTY_RAID)
    ns.UI.Mover(raidFrame, o.pos, L.CD_TAB_RAID)
    local since, full = 0, 0
    raidFrame:SetScript("OnUpdate", function(_, dt)
        since, full = since + dt, full + dt
        if since < 0.2 then return end
        since = 0
        -- toutes les 2 s (ou apres un changement d etat d un membre) : liste
        -- refaite (morts, deconnectes, sorts revenus, ordre)
        if full >= 2 or raidDirty then
            full, raidDirty = 0, false
            refreshRaid()
            return
        end
        local t = now()
        for _, row in ipairs(rowPool) do
            if row:IsShown() and row.line then paintRow(row, t) end
        end
    end)
    refreshRaid()
end

---------------------------------------------------------------------------
-- Barre de CD perso
---------------------------------------------------------------------------

local persoFrame
local icons = {}

local function setCooldown(b, id)
    if C_Spell and C_Spell.GetSpellCooldownDuration and b.cd.SetCooldownFromDurationObject then
        local ok, d = pcall(C_Spell.GetSpellCooldownDuration, id, true)
        if ok and d and pcall(b.cd.SetCooldownFromDurationObject, b.cd, d) then return end
    end
    local act, dur, start = readCooldown(id)
    if act and dur and start and dur > GCD_MAX then
        if not pcall(b.cd.SetCooldown, b.cd, start, dur) then b.cd:Clear() end
    elseif act == false then
        b.cd:Clear()
    end
end

local function persoVisible()
    if not db or not db.perso.enabled then return false end
    if ns.moversShown then return true end
    local v = db.perso.vis
    if v == "combat" then return inCombat end
    if v == "group" then return bool(IsInGroup) == true end
    return true
end

local function iconTooltip(b)
    if not db.perso.tips or not b.spell then return end
    local tip = ns.Tooltip(b, "ANCHOR_TOP")
    if not pcall(tip.SetSpellByID, tip, b.spell) then tip:SetText(spellName(b.spell) or "?") end
    tip:Show()
end

local function newIcon()
    local b = CreateFrame("Frame", nil, persoFrame)
    ns.UI.Skin(b, 0.6)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints()
    pcall(b.cd.SetDrawEdge, b.cd, false)
    pcall(b.cd.SetHideCountdownNumbers, b.cd, false)
    b:SetScript("OnEnter", iconTooltip)
    b:SetScript("OnLeave", function() ns.HideTooltip() end)
    return b
end

-- sorts a montrer : liste du personnage, sorts appris seulement
local function persoSpells()
    local out = {}
    for _, id in ipairs(persoList()) do
        if own[id] then
            local s = own[id]
            if not db.perso.hideReady or (s.active and s.confirmed) or ns.moversShown then out[#out + 1] = id end
        end
    end
    return out
end

layoutPerso = function()
    if not persoFrame then return end
    local o = db.perso
    local list = persoSpells()
    local per = math.max(1, o.perRow)
    for i, id in ipairs(list) do
        local b = icons[i] or newIcon()
        icons[i] = b
        b.spell = id
        b:SetSize(o.size, o.size)
        b:ClearAllPoints()
        local col, row = (i - 1) % per, math.floor((i - 1) / per)
        b:SetPoint("TOPLEFT", persoFrame, "TOPLEFT", col * (o.size + o.spacing), -row * (o.size + o.spacing))
        b.icon:SetTexture(spellIcon(id))
        b:EnableMouse(o.tips and true or false)
        b:Show()
    end
    for i = #list + 1, #icons do icons[i]:Hide(); icons[i].spell = nil end
    local n = math.max(#list, 1)
    local cols = math.min(n, per)
    local rows = math.ceil(n / per)
    persoFrame:SetSize(cols * o.size + (cols - 1) * o.spacing, rows * o.size + (rows - 1) * o.spacing)
    persoFrame:SetShown(persoVisible() and (#list > 0 or ns.moversShown))
end

local lastPersoSig
refreshPerso = function()
    if not persoFrame then return end
    -- liste changee (sort pret masque / montre) : nouvelle disposition
    local sig = table.concat(persoSpells(), ",")
    if sig ~= lastPersoSig then
        lastPersoSig = sig
        layoutPerso()
    end
    for _, b in ipairs(icons) do
        if b:IsShown() and b.spell then
            local s = own[b.spell]
            local on = s and s.active and s.confirmed
            b.icon:SetDesaturated(on and true or false)
            b.icon:SetAlpha(on and 0.75 or 1)
            setCooldown(b, b.spell)
        end
    end
end

local function buildPerso()
    local o = db.perso
    o.pos = o.pos or { point = "CENTER", x = 0, y = -200 }
    persoFrame = CreateFrame("Frame", "CorpUICDPerso", UIParent)
    persoFrame:SetSize(o.size, o.size)
    persoFrame:SetFrameStrata("LOW")
    ns.ApplyPos(persoFrame, o.pos)
    ns.UI.Mover(persoFrame, o.pos, L.CD_TAB_PERSO)
    lastPersoSig = nil
    refreshPerso()
end

local function applyAll()
    if raidFrame then refreshRaid() end
    if persoFrame then lastPersoSig = nil; refreshPerso() end
end

---------------------------------------------------------------------------
-- Liste perso : ajout, retrait, ordre
---------------------------------------------------------------------------

local refreshWindow   -- plus bas

local function inList(id)
    for i, v in ipairs(persoList()) do
        if v == id then return i end
    end
end

local function addPerso(id)
    if not cdb or not id or inList(id) then return end
    table.insert(cdb.list, id)
    rebuildOwn()
    pollOwn()
    applyAll()
    if refreshWindow then refreshWindow() end
end

local function removePerso(id)
    local i = inList(id)
    if not i then return end
    table.remove(cdb.list, i)
    rebuildOwn()
    applyAll()
    if refreshWindow then refreshWindow() end
end

local function moveLeft(id)
    local i = inList(id)
    if not i or i <= 1 then return end
    cdb.list[i], cdb.list[i - 1] = cdb.list[i - 1], cdb.list[i]
    applyAll()
    if refreshWindow then refreshWindow() end
end

-- sort tenu par le curseur (glisse depuis le grimoire)
local function cursorSpell()
    local ok, kind, a, b, c = pcall(GetCursorInfo)
    if not ok or kind ~= "spell" then return nil end
    local id = num(c)
    if not id and C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
        local ok2, info = pcall(C_SpellBook.GetSpellBookItemInfo, a, b)
        if ok2 and type(info) == "table" then id = num(info.spellID) end
    end
    return id
end

-- premiere ouverture du personnage : les CD de sa classe qu il connait
local function seedList()
    if cdb.init then return end
    cdb.init = true
    for _, e in ipairs(ns.CD_SPELLS) do
        if e.class == myClass and not e.item and e.cat ~= "kick" and e.cd >= 30 then
            local id = ownId(e)
            if id and not inList(id) then table.insert(cdb.list, id) end
        end
    end
end

---------------------------------------------------------------------------
-- Panneau d options : selecteur
---------------------------------------------------------------------------

local win
local pages, subTabs = {}, {}
local raidForm, persoForm
local classTabs, spellRows, myIcons, myRows = {}, {}, {}, {}
local selClass
local dropZone

local function classIconTex(t, class)
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if coords then
        t:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        t:SetTexCoord(coords[1] + 0.015, coords[2] - 0.015, coords[3] + 0.015, coords[4] - 0.015)
    else
        t:SetColorTexture(classColor(class))
    end
end

local function className(class)
    local n = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]
    return str(n) or class
end

local function catName(cat)
    return L["CD_CAT_" .. cat:upper()] or cat
end

local function spellCheckRow(parent, width)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, 22)
    row.check = ns.UI.Check(row, "", function(v) if row.onToggle then row.onToggle(v) end end)
    row.check:SetPoint("LEFT", 0, 0)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetJustifyH("LEFT")
    row.info = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.info:SetPoint("RIGHT", -6, 0)
    row.info:SetJustifyH("RIGHT")
    row.name:SetPoint("RIGHT", row.info, "LEFT", -6, 0)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if not self.spell then return end
        local tip = ns.Tooltip(self, "ANCHOR_RIGHT")
        if not pcall(tip.SetSpellByID, tip, self.spell) then tip:SetText(spellName(self.spell) or "?") end
        tip:Show()
    end)
    row:SetScript("OnLeave", function() ns.HideTooltip() end)
    return row
end

local function showPage(key)
    for k, p in pairs(pages) do p:SetShown(k == key) end
    local C = ns.COLORS
    for k, b in pairs(subTabs) do
        -- filet d or sous l onglet choisi (le liseré du bouton suit le survol)
        b.sel:SetShown(k == key)
        b.sel:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    end
    if db then db.page = key end
end

local function refreshRaidSpells()
    local C = ns.COLORS
    for _, b in ipairs(classTabs) do
        local c = (b.class == selClass) and C.gold or C.border
        b.cuiBorder:SetColorTexture(c[1], c[2], c[3], 1)
    end
    local i = 0
    for _, e in ipairs(ns.CD_SPELLS) do
        if e.class == selClass then
            i = i + 1
            local row = spellRows[i]
            if row then
                row.spell = e.id
                row.icon:SetTexture(spellIcon(e.id))
                row.name:SetText((spellName(e.id) or ("#" .. e.id)) .. (e.talent and ("  |cff888888(" .. L.CD_TALENT .. ")|r") or ""))
                row.info:SetText(catName(e.cat) .. "  " .. fmtCd(e.cd))
                row.check:SetChecked(raidSelected(e.id) and true or false)
                row.onToggle = function(v)
                    db.raid.spells[e.id] = v
                    refreshRaid()
                end
                row:Show()
            end
        end
    end
    for j = i + 1, #spellRows do spellRows[j]:Hide() end
end

local function refreshPersoPage()
    local list = persoList()
    for i, b in ipairs(myIcons) do
        local id = list[i]
        b.spell = id
        if id then
            b.icon:SetTexture(spellIcon(id))
            b.icon:SetDesaturated(not own[id])
            b:Show()
        else
            b:Hide()
        end
    end
    local last = myIcons[math.min(#list, #myIcons)]
    -- consigne a cote de la case tant qu il y a la place
    dropZone.label:SetShown(#list <= 6)
    dropZone:ClearAllPoints()
    if #list > 0 and last then
        dropZone:SetPoint("LEFT", last, "RIGHT", 6, 0)
    else
        dropZone:SetPoint("TOPLEFT", pages.perso, "TOPLEFT", 8, dropZone.y)
    end
    local i = 0
    for _, e in ipairs(ns.CD_SPELLS) do
        if e.class == myClass then
            i = i + 1
            local row = myRows[i]
            if row then
                local id = ownId(e)
                row.spell = id or e.id
                row.icon:SetTexture(spellIcon(id or e.id))
                row.icon:SetDesaturated(not id)
                row.name:SetText(spellName(e.id) or ("#" .. e.id))
                row.name:SetTextColor(id and 1 or 0.5, id and 1 or 0.5, id and 1 or 0.5)
                row.info:SetText(id and (catName(e.cat) .. "  " .. fmtCd(learned(e.id) or e.cd)) or L.CD_NOT_KNOWN)
                local n = spellName(e.id)
                local on = false
                for _, v in ipairs(list) do
                    if v == id or (n and spellName(v) == n) then on = true end
                end
                row.check:SetChecked(on)
                row.check:SetEnabled(id ~= nil and not e.item)
                row.onToggle = function(v)
                    if not id then return end
                    if v then
                        addPerso(id)
                    else
                        for j = #cdb.list, 1, -1 do
                            local x = cdb.list[j]
                            if x == id or (n and spellName(x) == n) then table.remove(cdb.list, j) end
                        end
                        rebuildOwn()
                        applyAll()
                        refreshWindow()
                    end
                end
                row:Show()
            end
        end
    end
    for j = i + 1, #myRows do myRows[j]:Hide() end
end

refreshWindow = function()
    if not win or not db then return end
    if raidForm then raidForm:Refresh() end
    if persoForm then persoForm:Refresh() end
    refreshRaidSpells()
    refreshPersoPage()
end

local function hint(parent, y, text, h)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)
    fs:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, y)
    fs:SetHeight(h or 40)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetText(text)
    return fs
end

local WIN_W, WIN_H = 500, 670

local function buildRaidPage(page)
    local o = db.raid
    raidForm = ns.UI.Form(page, -4, applyAll, WIN_W)
    local function check(key, text)
        raidForm:Check(text, function() return o[key] end, function(v) o[key] = v end)
    end
    check("enabled", L.CD_OPT_RAID_ENABLE)
    raidForm:Columns(2)
    raidForm:Cycle(L.CD_OPT_VIS, { "always", "group", "raid", "combat" },
        { always = L.CD_VIS_ALWAYS, group = L.CD_VIS_GROUP, raid = L.CD_VIS_RAID, combat = L.CD_VIS_COMBAT },
        function() return o.vis end, function(v) o.vis = v end)
    raidForm:Number(L.CD_OPT_WIDTH, function() return o.width end, function(v) o.width = v end, 140, 320, 2)
    raidForm:Number(L.CD_OPT_ROWH, function() return o.rowH end, function(v) o.rowH = v end, 12, 28, 1)
    raidForm:Number(L.CD_OPT_ROWS, function() return o.rows end, function(v) o.rows = v end, 5, 40, 1)
    raidForm:EndColumns()
    raidForm:Columns(2)
    check("title", L.CD_OPT_TITLE)
    check("tips", L.CD_OPT_TIPS)
    check("ask", L.CD_OPT_ASK)
    raidForm:EndColumns()
    raidForm:Gap(4)
    raidForm:Header(L.CD_SPELLS)
    local y = raidForm.y
    for i, class in ipairs(ns.CD_CLASSES) do
        local b = CreateFrame("Button", nil, page)
        b:SetSize(26, 26)
        b:SetPoint("TOPLEFT", page, "TOPLEFT", 8 + (i - 1) * 30, y)
        ns.UI.Skin(b, 0.6)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetPoint("TOPLEFT", 1, -1)
        b.tex:SetPoint("BOTTOMRIGHT", -1, 1)
        classIconTex(b.tex, class)
        b.class = class
        b:SetScript("OnClick", function() selClass = class; refreshRaidSpells() end)
        b:SetScript("OnEnter", function(self)
            local tip = ns.Tooltip(self, "ANCHOR_TOP")
            tip:SetText(className(class), classColor(class))
            tip:Show()
        end)
        b:SetScript("OnLeave", function() ns.HideTooltip() end)
        classTabs[#classTabs + 1] = b
    end
    local def = ns.UI.Button(page, L.CD_DEFAULTS, 90, function()
        wipe(o.spells)
        refreshRaidSpells()
        refreshRaid()
    end)
    def:SetPoint("TOPRIGHT", page, "TOPRIGHT", -8, y - 2)
    y = y - 34
    for i = 1, 12 do
        local row = spellCheckRow(page, WIN_W - 16)
        row:SetPoint("TOPLEFT", page, "TOPLEFT", 4, y - (i - 1) * 22)
        spellRows[i] = row
    end
    y = y - 12 * 22 - 6
    hint(page, y, L.CD_HINT_RAID, 54)
end

local function buildPersoPage(page)
    local o = db.perso
    persoForm = ns.UI.Form(page, -4, applyAll, WIN_W)
    local function check(key, text)
        persoForm:Check(text, function() return o[key] end, function(v) o[key] = v end)
    end
    check("enabled", L.CD_OPT_PERSO_ENABLE)
    persoForm:Columns(2)
    persoForm:Cycle(L.CD_OPT_VIS, { "always", "group", "combat" },
        { always = L.CD_VIS_ALWAYS, group = L.CD_VIS_GROUP, combat = L.CD_VIS_COMBAT },
        function() return o.vis end, function(v) o.vis = v end)
    persoForm:Number(L.CD_OPT_SIZE, function() return o.size end, function(v) o.size = v end, 20, 64, 1)
    persoForm:Number(L.CD_OPT_SPACING, function() return o.spacing end, function(v) o.spacing = v end, 0, 16, 1)
    persoForm:Number(L.CD_OPT_PERROW, function() return o.perRow end, function(v) o.perRow = v end, 1, 16, 1)
    persoForm:EndColumns()
    persoForm:Columns(2)
    check("hideReady", L.CD_OPT_HIDEREADY)
    check("tips", L.CD_OPT_TIPS)
    persoForm:EndColumns()
    persoForm:Gap(4)
    persoForm:Header(L.CD_MY_SPELLS)
    local y = persoForm.y
    for i = 1, 14 do
        local b = CreateFrame("Button", nil, page)
        b:SetSize(28, 28)
        b:SetPoint("TOPLEFT", page, "TOPLEFT", 8 + (i - 1) * 32, y)
        ns.UI.Skin(b, 0.6)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(self, button)
            local id = cursorSpell()
            if id then
                addPerso(id)
                if ClearCursor then pcall(ClearCursor) end
                return
            end
            if not self.spell then return end
            if button == "RightButton" then removePerso(self.spell) else moveLeft(self.spell) end
        end)
        b:SetScript("OnReceiveDrag", function()
            local id = cursorSpell()
            if id then
                addPerso(id)
                if ClearCursor then pcall(ClearCursor) end
            end
        end)
        b:SetScript("OnEnter", function(self)
            if not self.spell then return end
            local tip = ns.Tooltip(self, "ANCHOR_TOP")
            if not pcall(tip.SetSpellByID, tip, self.spell) then tip:SetText(spellName(self.spell) or "?") end
            tip:AddLine(" ")
            tip:AddLine(L.CD_TIP_ICON, 0.7, 0.7, 0.75, true)
            tip:Show()
        end)
        b:SetScript("OnLeave", function() ns.HideTooltip() end)
        myIcons[i] = b
    end
    -- case de depot : glisser un sort du grimoire, ou cliquer avec
    dropZone = CreateFrame("Button", nil, page, "BackdropTemplate")
    dropZone:SetSize(28, 28)
    dropZone.y = y
    ns.UI.SetBackdrop(dropZone, 0.5)
    dropZone.plus = dropZone:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    dropZone.plus:SetPoint("CENTER")
    dropZone.plus:SetText("+")
    dropZone.label = dropZone:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    dropZone.label:SetPoint("LEFT", dropZone, "RIGHT", 6, 0)
    dropZone.label:SetText(L.CD_DROP)
    local function drop()
        local id = cursorSpell()
        if id then
            addPerso(id)
            if ClearCursor then pcall(ClearCursor) end
        end
    end
    dropZone:SetScript("OnReceiveDrag", drop)
    dropZone:SetScript("OnClick", drop)
    dropZone:SetScript("OnEnter", function(self)
        local tip = ns.Tooltip(self, "ANCHOR_TOP")
        tip:SetText(L.CD_DROP, 1, 1, 1, 1, true)
        tip:Show()
    end)
    dropZone:SetScript("OnLeave", function() ns.HideTooltip() end)
    y = y - 40
    local h = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h:SetPoint("TOPLEFT", page, "TOPLEFT", 8, y)
    h:SetText(string.format(L.CD_SUGGEST, className(myClass or "")))
    y = y - 22
    for i = 1, 12 do
        local row = spellCheckRow(page, WIN_W - 16)
        row:SetPoint("TOPLEFT", page, "TOPLEFT", 4, y - (i - 1) * 22)
        myRows[i] = row
    end
    y = y - 12 * 22 - 6
    hint(page, y, L.CD_HINT_PERSO, 40)
end

local function buildWindow()
    win = ns.UI.Window("CorpUICDOptions", ns.TITLE .. " - " .. L.MOD_CD, nil, WIN_W + 16, WIN_H)
    local function tab(key, text, x)
        local b = ns.UI.Button(win, text, 200, function() showPage(key) end)
        b:SetPoint("TOPLEFT", win, "TOPLEFT", x, -30)
        b.sel = b:CreateTexture(nil, "OVERLAY")
        b.sel:SetHeight(2)
        b.sel:SetPoint("BOTTOMLEFT", 1, 1)
        b.sel:SetPoint("BOTTOMRIGHT", -1, 1)
        subTabs[key] = b
    end
    tab("raid", L.CD_TAB_RAID, 8)
    tab("perso", L.CD_TAB_PERSO, 214)
    for _, key in ipairs({ "raid", "perso" }) do
        local p = CreateFrame("Frame", nil, win)
        p:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -60)
        p:SetSize(WIN_W + 16, WIN_H - 60)
        pages[key] = p
    end
    selClass = myClass or ns.CD_CLASSES[1]
    buildRaidPage(pages.raid)
    buildPersoPage(pages.perso)
    win:HookScript("OnShow", function()
        rebuildOwn()
        refreshWindow()
    end)
    showPage(db.page == "perso" and "perso" or "raid")
    refreshWindow()
end

local function toggle()
    if not db then return end
    if not win then buildWindow() end
    ns.ShowPanel(win)
end

---------------------------------------------------------------------------
-- /corp cd diag
---------------------------------------------------------------------------

local function diag()
    local out = {}
    local R = C_RestrictedActions
    if R and R.IsAddOnRestrictionActive and Enum and Enum.AddOnRestrictionType then
        local parts = {}
        for k, v in pairs(Enum.AddOnRestrictionType) do
            local on = bool(R.IsAddOnRestrictionActive, v)
            parts[#parts + 1] = k .. "=" .. tostring(on)
        end
        table.sort(parts)
        out[#out + 1] = "restrictions: " .. table.concat(parts, " ")
    end
    out[#out + 1] = "class=" .. tostring(myClass) .. " combat=" .. tostring(inCombat)
    for id, s in pairs(own) do
        local act, dur, start, gcd = readCooldown(id)
        local ok, info = pcall(C_Spell.GetSpellCooldown, id)
        local secretDur = ok and type(info) == "table" and issecret(info.duration) or false
        out[#out + 1] = string.format("%s #%d key=%s active=%s conf=%s ends=%s unknown=%s | read: act=%s dur=%s gcd=%s secret=%s",
            spellName(id) or "?", id, tostring(s.key), tostring(s.active), tostring(s.confirmed),
            s.ends and string.format("%.0f", s.ends - now()) or "-", tostring(s.unknown),
            tostring(act), tostring(dur), tostring(gcd), tostring(secretDur))
    end
    local np = 0
    for who, p in pairs(peers) do
        np = np + 1
        local n = 0
        for _ in pairs(p.cds) do n = n + 1 end
        out[#out + 1] = string.format("peer %s class=%s corpui=%s cds=%d", who, tostring(p.class), tostring(p.corpui), n)
    end
    out[#out + 1] = "peers=" .. np .. " lines=" .. #lines
    if db then db.diag = out end
    ns.Say("cd diag")
    for _, line in ipairs(out) do ns.Chat("  " .. line) end
end

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

local wasInGroup = false
local helloTimer = false

local function scheduleHello(query, delay)
    if helloTimer then return end
    helloTimer = true
    C_Timer.After(delay or 3, function()
        helloTimer = false
        sendHello(query)
    end)
end

local knownSig
local function knownChanged()
    local keys = {}
    for k in pairs(ownKeys) do keys[#keys + 1] = k end
    table.sort(keys)
    local sig = table.concat(keys, ",")
    local diff = knownSig ~= nil and sig ~= knownSig
    knownSig = sig
    return diff
end

local function onRoster()
    local inGroup = bool(IsInGroup) == true
    if inGroup and not wasInGroup then scheduleHello(true, 3) end
    if not inGroup and wasInGroup then wipe(peers) end
    wasInGroup = inGroup
    refreshRaid()
    if persoFrame then layoutPerso() end
end

local function init()
    local root = ns.InitRoot()
    root.cd = root.cd or {}
    db = root.cd
    for part, defs in pairs(DEFAULTS) do
        db[part] = db[part] or {}
        for k, v in pairs(defs) do
            if db[part][k] == nil then db[part][k] = v end
        end
    end
    db.raid.spells = db.raid.spells or {}
    db.chars = db.chars or {}
    local key = ns.CharKey and ns.CharKey() or (unitFull("player") or "?")
    db.chars[key] = db.chars[key] or {}
    cdb = db.chars[key]
    cdb.list = cdb.list or {}
    cdb.learned = cdb.learned or {}
    myClass = unitClass("player")
    Comm = ns.Comm
    if Comm and Comm.On then
        Comm.On("CDH", onHello)
        Comm.On("CDU", onUse)
    end
end

local ev = CreateFrame("Frame")
local poll = CreateFrame("Frame")
local acc = 0
poll:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.2 then return end
    acc = 0
    if db then pollOwn(false) end
end)
poll:Hide()

local spellsTimer = false
ev:SetScript("OnEvent", function(_, event, a1, a2, a3)
    if ns.ModuleOff("cd", ev) then return end
    if event == "PLAYER_LOGIN" then
        init()
        rebuildOwn()
        seedList()
        rebuildOwn()
        knownChanged()
        pollOwn(false)
        buildRaid()
        buildPerso()
        poll:Show()
        wasInGroup = bool(IsInGroup) == true
        if wasInGroup then scheduleHello(true, 8) end
        return
    end
    if not db then return end
    if event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" then
        pollOwn(true)
        if persoFrame then refreshPerso() end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        onCast(a1, a3)
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        onRoster()
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        applyAll()
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        applyAll()
    elseif event == "SPELLS_CHANGED" or event == "PLAYER_LEVEL_UP" or event == "LEARNED_SPELL_IN_TAB" then
        if spellsTimer then return end
        spellsTimer = true
        C_Timer.After(1, function()
            spellsTimer = false
            rebuildOwn()
            pollOwn(false)
            applyAll()
            if knownChanged() and bool(IsInGroup) then scheduleHello(false, 2) end
            if win and win:IsShown() then refreshWindow() end
        end)
    elseif event == "ADDON_ACTION_BLOCKED" then
        -- refus de notre message prive (voir ask)
        if askWatch and not issecret(a2) and type(a2) == "string" and a2:find("SendChatMessage", 1, true) then
            askBlocked = true
        end
    elseif event == "UNIT_CONNECTION" or event == "UNIT_FLAGS" then
        -- tres frequent en raid (plaques comprises) : membres du groupe
        -- seulement, suivi affiche seulement, traite par la mise a jour suivante
        if raidDirty or not (raidFrame and raidFrame:IsVisible()) then return end
        if issecret(a1) or type(a1) ~= "string" then return end
        if a1 == "player" or a1:find("^raid%d") or a1:find("^party%d") then raidDirty = true end
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "SPELL_UPDATE_COOLDOWN",
                     "SPELL_UPDATE_CHARGES", "UNIT_SPELLCAST_SUCCEEDED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
                     "SPELLS_CHANGED", "PLAYER_LEVEL_UP", "LEARNED_SPELL_IN_TAB", "UNIT_CONNECTION", "UNIT_FLAGS",
                     "ADDON_ACTION_BLOCKED" }) do
    pcall(ev.RegisterEvent, ev, e)
end

-- poignees de deplacement : cadres montres meme vides
local lastMovers = false
ns.Listen(function()
    if (ns.moversShown and true or false) == lastMovers then return end
    lastMovers = ns.moversShown and true or false
    applyAll()
end)

ns.RegisterModule({
    command = "cd",
    panelName = "CorpUICDOptions",
    icon = "Interface\\Icons\\Spell_Nature_TimeStop",
    title = function() return L.MOD_CD end,
    desc = function() return L.CD_DESC end,
    Slash = function(input)
        if strlower(strtrim(input or "")) == "diag" then diag() return end
        toggle()
    end,
    Open = toggle,
})
