--[[--------------------------------------------------------------------------
    CorpUI - module Couches : voir sa couche et en changer

    La couche se lit sur les PNJ autour de soi : le GUID d une creature
    ("Creature-0-serveur-instance-zone-PNJ-apparition") porte le numero de
    la copie de zone (5e champ). Il change d une couche a l autre, et aussi
    d une zone a l autre : il ne sert qu a comparer dans une meme zone.
      - unites vues : plaques de nom (tant qu elles sont la), cible et survol
        (20 s) ; la couche affichee est le code porte par le plus d unites
        (egalite : on garde l actuel) ;
      - remise a zero au changement de zone ; pas de couches en instance ;
      - /corp couches diag : les GUID lus (a verifier en jeu sur deux
        couches : c est bien le 5e champ qui change ?).

    Changer de couche (clic sur l affichage, /corp couches swap) : entrer
    dans le groupe d un joueur d une autre couche de la meme zone fait
    passer sur sa couche (le jeu deplace l invite vers celle du chef).
      1. la guilde (ns.Comm, type COUCHE) : "REQ zone code" en GUILD ; les
         CorpUI qui peuvent accueillir repondent "OFFER zone code" en
         WHISPER ; le premier est choisi ("PICK zone" en WHISPER ; "BUSY" :
         le suivant) ; il invite ; on accepte (AcceptGroup, reglage) ; des
         que la couche a change on quitte le groupe, sinon au bout de 60 s ;
      2. personne dans la guilde : la demande publique ("inv layer", canal
         au choix) est posee dans la zone de saisie, le joueur l envoie
         lui-meme (SendChatMessage est interdit aux addons sur ce client) ;
         une invitation dans les 2 min qui suivent est acceptee de meme.
    Accueillir (reglages) :
      - la guilde : seul, ou chef d un groupe (pas un raid) avec de la
        place, couche connue et differente de celle du demandeur ; l invite
        quitte le groupe de lui-meme (on previent au bout de 90 s) ;
      - le public (coupe par defaut) : "inv layer" et variantes dans les
        canaux de zone, dire, crier, chuchotements ; seul seulement ; on
        quitte soi-meme le groupe 30 s apres l arrivee de l invite
        (UninviteUnit est interdit aux addons) ;
      - jamais en combat ni en instance, un invite a la fois.
    C_PartyInfo.InviteUnit et LeaveParty ne sont pas restreintes. Aucun
    code de Blizzard n est touche : la fenetre d invitation reste affichee
    apres AcceptGroup (un clic dessus ne change plus rien).
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local C = ns.COLORS
local issecret = issecretvalue or function() return false end

local KIND = "COUCHE"
local OBS_TTL = 20        -- cible et survol : comptes 20 s
local OFFER_WAIT = 3      -- reponses de la guilde attendues 3 s
local PICK_WAIT = 15      -- invitation de l hote attendue 15 s (30 s une fois recue)
local MOVE_WAIT = 60      -- changement de couche attendu 60 s dans le groupe
local PUBLIC_WAIT = 120   -- demande publique : invitation acceptee pendant 2 min
local OFFER_TTL = 30      -- notre offre vaut 30 s
local HOST_KEEP = 30      -- invite public : on quitte le groupe 30 s apres son arrivee
local HOST_GIVEUP = 90    -- invite de la guilde : on previent au bout de 90 s
local ASK_GAP = 10        -- une demande a la guilde toutes les 10 s au plus
local PUBLIC_GAP = 120    -- un meme joueur public toutes les 2 min au plus
local MAX_MSG = 60
local DEFAULT_MSG = "inv layer"
local CHANNELS = { "1", "2", "3", "4", "5", "SAY", "YELL" }

local db
local frame, panel

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

local function yes(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn, ...)
    return ok and not issecret(v) and v and true or false
end

local function count(fn, ...)
    if type(fn) ~= "function" then return 0 end
    local ok, v = pcall(fn, ...)
    if not ok or issecret(v) or type(v) ~= "number" then return 0 end
    return v
end

local function inCombat()
    return yes(InCombatLockdown) or yes(UnitAffectingCombat, "player")
end

local function inInstance()
    local ok, inside = pcall(IsInInstance)
    return ok and not issecret(inside) and inside == true
end

-- zone de la carte (un quartier, une grotte : la zone au-dessus)
local function zoneMap()
    local M = C_Map
    if not (M and M.GetBestMapForUnit) then return nil end
    local ok, id = pcall(M.GetBestMapForUnit, "player")
    id = ok and num(id) or nil
    for _ = 1, 4 do
        if not id or not M.GetMapInfo then break end
        local ok2, info = pcall(M.GetMapInfo, id)
        if not ok2 or type(info) ~= "table" then break end
        local t, parent = num(info.mapType), num(info.parentMapID)
        -- Enum.UIMapType : 3 = zone ; 4 a 6 = donjon, micro, orpheline
        if not t or t <= 3 or not parent or parent == 0 then break end
        id = parent
    end
    return id
end

local function zoneName()
    local ok, z = pcall(GetRealZoneText)
    z = ok and str(z) or nil
    if z and z ~= "" then return z end
    return "?"
end

local function display(who) return ns.Names.Display(who) end

---------------------------------------------------------------------------
-- Lecture de la couche
---------------------------------------------------------------------------

-- code de couche d un GUID de creature (nil : joueur, familier, objet...)
local function codeOf(guid)
    guid = str(guid)
    if not guid then return nil end
    local kind, zone = guid:match("^(%a+)%-%d+%-%d+%-%d+%-(%d+)%-%d+%-%x+$")
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    return zone
end

local obs = {}        -- guid -> { code, at, unit (jeton de plaque) }
local current         -- code de la couche (nil : inconnue)
local zoneId          -- zone des observations (nil : instance ou inconnue)
local seen = {}       -- zone -> { [code] = GetTime() } (session)
local refreshDisplay, onLayer

local function tally()
    local n = {}
    for _, o in pairs(obs) do n[o.code] = (n[o.code] or 0) + 1 end
    return n
end

local function decide()
    local n = tally()
    local best, bn = current, current and n[current] or 0
    for code, k in pairs(n) do
        if k > bn then best, bn = code, k end
    end
    if best and zoneId then
        seen[zoneId] = seen[zoneId] or {}
        seen[zoneId][best] = GetTime()
    end
    if best == current or bn == 0 then return end
    local old = current
    current = best
    if onLayer then onLayer(old, best) end
    refreshDisplay()
end

local function observe(unit, plate)
    if not zoneId then return end
    local ok, guid = pcall(UnitGUID, unit)
    guid = ok and str(guid) or nil
    local code = guid and codeOf(guid)
    if not code then return end
    local o = obs[guid]
    if not o then
        o = {}
        obs[guid] = o
    end
    o.code, o.at = code, GetTime()
    if plate then o.unit = unit end
    decide()
end

local function plateGone(unit)
    for guid, o in pairs(obs) do
        if o.unit == unit then obs[guid] = nil end
    end
    decide()
end

local function scanPlates()
    for i = 1, 40 do
        local u = "nameplate" .. i
        if yes(UnitExists, u) then observe(u, true) end
    end
end

-- unites perimees : cible et survol au-dela de 20 s, plaque reprise par
-- une autre unite (retrait manque)
local function expire(now)
    for guid, o in pairs(obs) do
        if o.unit then
            local ok, g = pcall(UnitGUID, o.unit)
            if not ok or str(g) ~= guid then
                if now - o.at > OBS_TTL then obs[guid] = nil else o.unit = nil end
            end
        elseif now - o.at > OBS_TTL then
            obs[guid] = nil
        end
    end
    decide()
end

local function enterZone(loading)
    if loading then wipe(obs) end
    local z = (not inInstance()) and zoneMap() or nil
    if z ~= zoneId then
        wipe(obs)
        zoneId, current = z, nil
    end
    if zoneId then scanPlates() end
    refreshDisplay()
end

---------------------------------------------------------------------------
-- Groupe
---------------------------------------------------------------------------

local function grouped() return yes(IsInGroup) end

local function inMyGroup(who)
    local raid = yes(IsInRaid)
    local n = count(GetNumGroupMembers)
    local last = raid and n or math.max(0, n - 1)
    for i = 1, last do
        if ns.Names.Unit((raid and "raid" or "party") .. i) == who then return true end
    end
    return false
end

local function leave()
    local fn = (C_PartyInfo and C_PartyInfo.LeaveParty) or LeaveParty
    if type(fn) == "function" then pcall(fn) end
end

local function send(payload, channel, target)
    local Comm = ns.Comm
    if not (Comm and Comm.Send) then return false end
    return Comm.Send(KIND, payload, channel, target)
end

---------------------------------------------------------------------------
-- Changer de couche (demandeur)
---------------------------------------------------------------------------

-- nil, ou { state = "ask" | "pick" | "public" | "wait", due, offers,
--           tried, host, hostCode, before, invited }
local swap
local lastAsk = -ASK_GAP

local function setState(state, due)
    swap.state, swap.due = state, GetTime() + due
    refreshDisplay()
end

-- demande publique posee dans la zone de saisie (envoyee par le joueur)
local function prefill()
    local msg = strtrim(db.message or "")
    if msg == "" then msg = DEFAULT_MSG end
    local ch = db.channel
    local cmd = (ch == "SAY" and "/s ") or (ch == "YELL" and "/y ") or ("/" .. ch .. " ")
    local U = ChatFrameUtil
    local fn = (U and U.OpenChat) or ChatFrame_OpenChat
    if type(fn) ~= "function" then return false end
    return (pcall(fn, cmd .. msg))
end

local function goPublic(why)
    if why then ns.Say(why) end
    if not db.public then
        swap = nil
        ns.Say(L.LAYER_PUBLIC_OFF)
        refreshDisplay()
        return
    end
    if not swap then swap = { offers = {}, tried = {} } end
    swap.host, swap.hostCode, swap.invited = nil, nil, nil
    setState("public", PUBLIC_WAIT)
    if prefill() then ns.Say(L.LAYER_PUBLIC_READY) end
end

-- hote suivant : le premier a avoir repondu, d une autre couche
local function pickNext()
    local best
    for who, o in pairs(swap.offers) do
        if not swap.tried[who] and (not current or o.code ~= current)
            and (not best or o.at < swap.offers[best].at) then
            best = who
        end
    end
    if not best then
        goPublic(L.LAYER_NO_GUILD_HOST)
        return
    end
    swap.tried[best] = true
    swap.host, swap.hostCode, swap.invited = best, swap.offers[best].code, nil
    setState("pick", PICK_WAIT)
    send("PICK " .. zoneId, "WHISPER", best)
    ns.Say(string.format(L.LAYER_HOST_PICKED, display(best), swap.hostCode or "?"))
end

local function startSwap()
    if inInstance() then ns.Say(L.LAYER_IN_INSTANCE) return end
    if inCombat() then ns.Say(L.LAYER_IN_COMBAT) return end
    if grouped() then ns.Say(L.LAYER_IN_GROUP) return end
    if not zoneId then enterZone() end
    if not zoneId then ns.Say(L.LAYER_IN_INSTANCE) return end
    if not current then ns.Say(L.LAYER_UNKNOWN_WARN) end
    swap = { offers = {}, tried = {} }
    local now = GetTime()
    if yes(IsInGuild) and now - lastAsk >= ASK_GAP
        and send(string.format("REQ %d %s", zoneId, current or "-"), "GUILD") then
        lastAsk = now
        setState("ask", OFFER_WAIT)
        ns.Say(L.LAYER_ASK_GUILD)
    else
        goPublic()
    end
end

local function stopSwap(msg)
    local waiting = swap and swap.state == "wait"
    swap = nil
    if msg then ns.Say(msg) end
    if waiting and db.leave and grouped() then
        leave()
        ns.Say(L.LAYER_LEAVING)
    end
    refreshDisplay()
end

local function toggleSwap()
    if not db then return end
    if swap then stopSwap(L.LAYER_CANCELLED) else startSwap() end
end

-- entre dans un groupe pendant la demande : on attend le changement
local function enterWait()
    if not swap.host then
        -- invite par un joueur du public : le chef du groupe
        local raid = yes(IsInRaid)
        for i = 1, raid and 40 or 4 do
            local u = (raid and "raid" or "party") .. i
            if yes(UnitIsGroupLeader, u) then swap.host = ns.Names.Unit(u) break end
        end
    end
    swap.before = current
    setState("wait", MOVE_WAIT)
    ns.Say(string.format(L.LAYER_JOINED, swap.host and display(swap.host) or "?"))
end

local function onInvite(name)
    if not swap or (swap.state ~= "pick" and swap.state ~= "public") then return end
    local who = ns.Names.Sender(str(name))
    if not who then return end
    if swap.state == "pick" and who ~= swap.host then return end
    swap.host, swap.invited = who, true
    swap.due = GetTime() + 2 * PICK_WAIT
    local ok = false
    if db.accept and type(AcceptGroup) == "function" then ok = pcall(AcceptGroup) end
    if not ok then ns.Say(string.format(L.LAYER_ACCEPT, display(who))) end
    refreshDisplay()
end

local function onOffer(who, zone, code)
    if not swap or zone ~= zoneId then return end
    -- hote de notre couche (la notre a change depuis la demande) : inutile
    if swap.offers[who] or (current and code == current) then return end
    swap.offers[who] = { code = code, at = GetTime() }
    -- premier hote : choisi tout de suite (l hote a deja verifie sa couche) ;
    -- arrive apres le passage en public : prefere tant que personne n invite
    if swap.state == "ask" or (swap.state == "public" and not swap.invited) then pickNext() end
end

local function onBusy(who)
    if swap and swap.state == "pick" and swap.host == who and not swap.invited then pickNext() end
end

---------------------------------------------------------------------------
-- Accueillir (hote)
---------------------------------------------------------------------------

local hosted = {}       -- invite -> { at, joined, public, alone }
local offered = {}      -- demandeur de la guilde -> GetTime() de notre offre
local publicSeen = {}   -- joueur du public -> GetTime() de sa demande traitee

-- "alone" (seul) | "lead" (chef d un groupe avec de la place) | nil
local function hostSlot(public)
    if inCombat() or inInstance() or swap or next(hosted) then return nil end
    if not grouped() then return "alone" end
    if public or yes(IsInRaid) or not yes(UnitIsGroupLeader, "player") then return nil end
    if count(GetNumGroupMembers) >= 5 then return nil end
    return "lead"
end

local function invite(who, target, public, alone)
    local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    if type(fn) ~= "function" or not target or not pcall(fn, target) then return false end
    hosted[who] = { at = GetTime(), public = public, alone = alone }
    ns.Say(string.format(L.LAYER_HOST_INVITED, display(who)))
    refreshDisplay()
    return true
end

local function onRequest(who, zone, code)
    if not db.host or not zoneId or zone ~= zoneId then return end
    if not current or code == current or not hostSlot(false) then return end
    local now = GetTime()
    if offered[who] and now - offered[who] < ASK_GAP then return end
    offered[who] = now
    -- reponses etalees : la guilde ne repond pas dans la meme image
    C_Timer.After(0.2 + math.random() * 1.2, function()
        if not db.host or zoneId ~= zone or not current or not hostSlot(false) then return end
        send(string.format("OFFER %d %s", zone, current), "WHISPER", who)
    end)
end

local function onPick(who, zone)
    local at = offered[who]
    offered[who] = nil
    if not at or GetTime() - at > OFFER_TTL then return end
    local slot = zone == zoneId and hostSlot(false)
    if not slot or not invite(who, ns.Names.Whisper(who), false, slot == "alone") then
        send("BUSY " .. zone, "WHISPER", who)
    end
end

-- demande publique : "inv layer", "layer swap pls", "inv couche svp"...
local LAYER_WORDS = { layer = true, layers = true, layering = true, couche = true, couches = true }
local ASK_WORDS = { inv = true, invite = true, swap = true, lf = true, need = true, pls = true, plz = true,
                    please = true, svp = true, stp = true, besoin = true, change = true, changer = true }

local function isRequest(text)
    local t = strlower(text)
    if #t > 80 then return false end
    local own = strlower(strtrim(db.message or ""))
    if own ~= "" and strtrim(t) == own then return true end
    local hasLayer, hasAsk, n = false, false, 0
    for w in t:gmatch("[%w\128-\255]+") do
        n = n + 1
        if LAYER_WORDS[w] then hasLayer = true elseif ASK_WORDS[w] then hasAsk = true end
    end
    return hasLayer and hasAsk and n <= 8
end

local function onPublic(text, sender)
    if not db.hostPublic then return end
    text, sender = str(text), str(sender)
    if not text or not sender or not isRequest(text) then return end
    local who = ns.Names.Sender(sender)
    if not who or who == ns.Names.Me() then return end
    local now = GetTime()
    if publicSeen[who] and now - publicSeen[who] < PUBLIC_GAP then return end
    if hostSlot(true) ~= "alone" then return end
    publicSeen[who] = now
    invite(who, sender, true, true)
end

-- canaux d une demande publique : ceux du jeu (General, Commerce,
-- Defense locale...) et les canaux perso dont le nom parle de couches
local function publicChannel(zoneChannelID, baseName)
    zoneChannelID = num(zoneChannelID)
    if zoneChannelID and zoneChannelID > 0 then return true end
    baseName = str(baseName)
    if not baseName then return false end
    baseName = strlower(baseName)
    return baseName:find("layer", 1, true) ~= nil or baseName:find("couche", 1, true) ~= nil
end

---------------------------------------------------------------------------
-- Couche changee, groupe change, minuteries
---------------------------------------------------------------------------

-- dans le groupe de l hote : un changement de code (ou le code de l hote,
-- si la couche de depart etait inconnue) = deplace
onLayer = function(old, new)
    if swap and swap.state == "wait" then
        if old or (swap.hostCode and new == swap.hostCode) then
            local from = swap.before or old or "?"
            swap = nil
            ns.Say(string.format(L.LAYER_DONE, from, new))
            if db.leave and grouped() then
                leave()
                ns.Say(L.LAYER_LEAVING)
            end
        end
        return
    end
    if old and db.announce then ns.Say(string.format(L.LAYER_CHANGED, old, new)) end
end

local function rosterChanged()
    local inGroup = grouped()
    if swap then
        if inGroup and (swap.state == "pick" or swap.state == "public") then
            enterWait()
        elseif not inGroup and swap.state == "wait" then
            swap = nil
            ns.Say(L.LAYER_GROUP_GONE)
        end
    end
    local now = GetTime()
    for who, h in pairs(hosted) do
        local here = inGroup and inMyGroup(who)
        if here and not h.joined then
            h.joined = now
        elseif h.joined and not here then
            hosted[who] = nil
        end
    end
    refreshDisplay()
end

local function tick()
    local now = GetTime()
    expire(now)
    if swap and swap.due and now >= swap.due then
        if swap.state == "ask" then
            goPublic(L.LAYER_NO_GUILD_HOST)
        elseif swap.state == "pick" then
            pickNext()
        elseif swap.state == "public" then
            stopSwap(L.LAYER_PUBLIC_EXPIRED)
        elseif swap.state == "wait" then
            stopSwap(L.LAYER_TIMEOUT)
        end
    end
    for who, h in pairs(hosted) do
        if not h.joined then
            if now - h.at > 60 then hosted[who] = nil end
        elseif now - h.joined >= (h.public and HOST_KEEP or HOST_GIVEUP) then
            hosted[who] = nil
            if inMyGroup(who) then
                if h.alone and count(GetNumGroupMembers) <= 2 then
                    leave()
                    ns.Say(string.format(L.LAYER_HOST_LEFT, display(who)))
                else
                    ns.Say(string.format(L.LAYER_HOST_STILL, display(who)))
                end
            end
        end
    end
    for who, at in pairs(offered) do
        if now - at > OFFER_TTL then offered[who] = nil end
    end
    refreshDisplay()
end

---------------------------------------------------------------------------
-- Affichage
---------------------------------------------------------------------------

local function grey(t)
    return string.format("|cff%02x%02x%02x%s|r", math.floor(C.text[1] * 255), math.floor(C.text[2] * 255),
        math.floor(C.text[3] * 255), t)
end

local function statusText()
    if swap then
        local host = swap.host and display(swap.host) or "?"
        if swap.state == "ask" then return L.LAYER_ST_ASK end
        if swap.state == "pick" then return string.format(L.LAYER_ST_PICK, host) end
        if swap.state == "public" then return L.LAYER_ST_PUBLIC end
        if swap.state == "wait" then return string.format(L.LAYER_ST_WAIT, host) end
    end
    local who = next(hosted)
    if who then return string.format(L.LAYER_ST_HOST, display(who)) end
end

local function seenHere()
    local list = {}
    for code in pairs(zoneId and seen[zoneId] or {}) do list[#list + 1] = code end
    table.sort(list, function(a, b) return tonumber(a) < tonumber(b) end)
    return list
end

local function showTip(owner)
    local t = ns.Tooltip(owner, "ANCHOR_BOTTOMLEFT")
    t:AddLine(L.MOD_LAYER, C.gold[1], C.gold[2], C.gold[3])
    if not zoneId then
        t:AddLine(inInstance() and L.LAYER_TIP_INSTANCE or L.LAYER_TIP_UNKNOWN, 1, 1, 1, true)
    else
        t:AddDoubleLine(L.LAYER_TIP_ZONE, zoneName(), 0.7, 0.7, 0.7, 1, 1, 1)
        t:AddDoubleLine(L.LAYER_TIP_CODE, current or "?", 0.7, 0.7, 0.7, 1, 1, 1)
        local list = seenHere()
        if #list > 1 then t:AddDoubleLine(L.LAYER_TIP_SEEN, table.concat(list, ", "), 0.7, 0.7, 0.7, 1, 1, 1) end
        if not current then t:AddLine(L.LAYER_TIP_UNKNOWN, 1, 1, 1, true) end
        t:AddLine(L.LAYER_TIP_NOTE, 0.6, 0.6, 0.6, true)
    end
    local st = statusText()
    if st then
        t:AddLine(" ")
        t:AddLine(st, C.gold[1], C.gold[2], C.gold[3], true)
    end
    t:AddLine(" ")
    t:AddLine(swap and L.LAYER_TIP_CANCEL or L.LAYER_TIP_SWAP, 0.5, 0.8, 1)
    t:AddLine(L.LAYER_TIP_OPTIONS, 0.5, 0.8, 1)
    t:Show()
end

local lastText
refreshDisplay = function()
    if not frame then return end
    frame:SetShown(db.show and true or false)
    if not db.show then return end
    local v
    if not zoneId then
        v = grey(inInstance() and L.LAYER_INSTANCE or "?")
    else
        v = current and ("|cffffffff" .. current .. "|r") or grey("?")
    end
    if swap or next(hosted) then v = v .. " |cffffd100...|r" end
    local text = grey(L.LAYER_LABEL) .. " " .. v
    if text ~= lastText then
        lastText = text
        frame.text:SetText(text)
        frame:SetWidth(math.max(60, math.floor(frame.text:GetStringWidth() + 18)))
    end
    -- infobulle ouverte : a jour (etat de la demande)
    if frame:IsMouseOver() then
        local tip = rawget(_G, "CorpUITooltip")
        if tip and tip:IsShown() and tip:GetOwner() == frame then showTip(frame) end
    end
end

local openPanel

local function buildFrame()
    frame = CreateFrame("Button", "CorpUILayer", UIParent)
    frame:SetSize(90, 20)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    ns.UI.Skin(frame, 0.85)
    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.text:SetPoint("LEFT", 9, 0)
    frame.text:SetPoint("RIGHT", -9, 0)
    frame.text:SetHeight(20)
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame:SetScript("OnClick", function(_, button)
        if button == "RightButton" then openPanel() else toggleSwap() end
    end)
    frame:SetScript("OnEnter", function(self) showTip(self) end)
    frame:SetScript("OnLeave", ns.HideTooltip)
    ns.ApplyPos(frame, db.pos)
    ns.UI.Mover(frame, db.pos, L.MOD_LAYER)
end

---------------------------------------------------------------------------
-- Diagnostic (/corp couches diag)
---------------------------------------------------------------------------

local function guidLine(unit)
    local ok, g = pcall(UnitGUID, unit)
    if not ok then return nil end
    if issecret(g) then return unit .. " : GUID secret" end
    if type(g) ~= "string" then return nil end
    return string.format("%s : %s  -> %s", unit, g, codeOf(g) or "-")
end

local function diag()
    ns.Say(string.format("couches : zone %s (%s), couche %s%s", tostring(zoneId), zoneName(), current or "?",
        inInstance() and ", instance" or ""))
    for code, k in pairs(tally()) do ns.Chat(string.format("  code %s : %d unite(s)", code, k)) end
    local list = seenHere()
    if #list > 0 then ns.Chat("  vus ici : " .. table.concat(list, ", ")) end
    for _, u in ipairs({ "target", "mouseover" }) do
        local line = guidLine(u)
        if line then ns.Chat("  " .. line) end
    end
    local shown = 0
    for i = 1, 40 do
        local u = "nameplate" .. i
        if shown < 6 and yes(UnitExists, u) then
            local line = guidLine(u)
            if line then
                ns.Chat("  " .. line)
                shown = shown + 1
            end
        end
    end
    local n = 0
    for _ in pairs(hosted) do n = n + 1 end
    ns.Chat(string.format("  demande %s ; accueil guilde %s, public %s ; invites %d", swap and swap.state or "-",
        tostring(db.host), tostring(db.hostPublic), n))
end

---------------------------------------------------------------------------
-- Reglages (/corp couches)
---------------------------------------------------------------------------

local function buildPanel()
    panel = ns.UI.Window("CorpUILayerOptions", ns.TITLE .. " - " .. L.MOD_LAYER, nil, 440, 480)
    local form = ns.UI.Form(panel, -34, function() refreshDisplay() end)
    form:Check(L.LAYER_OPT_SHOW, function() return db.show end, function(v) db.show = v end)
    form:Check(L.LAYER_OPT_ANNOUNCE, function() return db.announce end, function(v) db.announce = v end)
    form:Header(L.LAYER_H_SWAP)
    form:Check(L.LAYER_OPT_ACCEPT, function() return db.accept end, function(v) db.accept = v end)
    form:Check(L.LAYER_OPT_LEAVE, function() return db.leave end, function(v) db.leave = v end)
    form:Check(L.LAYER_OPT_PUBLIC, function() return db.public end, function(v) db.public = v end)
    form:Columns(2)
    local names = { ["1"] = "/1 (" .. L.LAYER_CH_GENERAL .. ")", ["2"] = "/2", ["3"] = "/3", ["4"] = "/4",
                    ["5"] = "/5", SAY = L.LAYER_CH_SAY, YELL = L.LAYER_CH_YELL }
    form:Cycle(L.LAYER_OPT_CHANNEL, CHANNELS, names, function() return db.channel end, function(v) db.channel = v end)
    -- message de la demande publique (cellule de droite)
    local x, y = form:Cell(44)
    local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", panel, "TOPLEFT", 8 + x, y)
    label:SetText(L.LAYER_OPT_MESSAGE)
    local box = ns.UI.EditBox(panel, 190, 22)
    box:SetPoint("TOPLEFT", panel, "TOPLEFT", 8 + x, y - 16)
    box:SetMaxLetters(MAX_MSG)
    local function save()
        local t = strtrim(box:GetText() or "")
        db.message = t ~= "" and t or DEFAULT_MSG
        box:SetText(db.message)
    end
    box:SetScript("OnEnterPressed", function(self) save() self:ClearFocus() end)
    box:HookScript("OnEditFocusLost", save)
    form:EndColumns()
    form:Header(L.LAYER_H_HOST)
    form:Check(L.LAYER_OPT_HOST, function() return db.host end, function(v) db.host = v end)
    form:Check(L.LAYER_OPT_HOST_PUBLIC, function() return db.hostPublic end, function(v) db.hostPublic = v end)
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, form.y - 6)
    hint:SetWidth(424)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.LAYER_HINT)
    local btn = ns.UI.Button(panel, L.LAYER_BTN_SWAP, 180, toggleSwap)
    btn:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, form.y - 96)
    panel:HookScript("OnShow", function()
        form:Refresh()
        box:SetText(db.message or DEFAULT_MSG)
    end)
end

openPanel = function()
    if not db then return end
    if not panel then buildPanel() end
    ns.ShowPanel(panel)
end

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

local rosterQueued = false
local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, a1, a2, _, _, _, _, a7, _, a9)
    if ns.ModuleOff("couches", ev) then return end
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        if type(root.layer) ~= "table" then root.layer = {} end
        db = root.layer
        local D = { show = true, announce = true, accept = true, leave = true, public = true,
                    host = true, hostPublic = false }
        for k, v in pairs(D) do if db[k] == nil then db[k] = v end end
        local okCh = false
        for _, c in ipairs(CHANNELS) do if db.channel == c then okCh = true end end
        if not okCh then db.channel = "1" end
        if type(db.message) ~= "string" or strtrim(db.message) == "" then db.message = DEFAULT_MSG end
        if type(db.pos) ~= "table" then db.pos = { point = "TOPRIGHT", x = -40, y = -236 } end
        buildFrame()
        ns.Every(1, tick, "Couches", "couches")
        enterZone(true)
        return
    end
    if not db then return end
    if event == "PLAYER_ENTERING_WORLD" then
        enterZone(true)
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        enterZone(false)
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if str(a1) then observe(a1, true) end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if str(a1) then plateGone(a1) end
    elseif event == "PLAYER_TARGET_CHANGED" then
        observe("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        observe("mouseover")
    elseif event == "PARTY_INVITE_REQUEST" then
        onInvite(a1)
    elseif event == "GROUP_JOINED" or event == "GROUP_LEFT" or event == "GROUP_ROSTER_UPDATE" then
        -- plusieurs dans la meme image : un seul passage, a la suivante
        if not rosterQueued then
            rosterQueued = true
            C_Timer.After(0, function() rosterQueued = false rosterChanged() end)
        end
    elseif event == "CHAT_MSG_CHANNEL" then
        if publicChannel(a7, a9) then onPublic(a1, a2) end
    elseif event == "CHAT_MSG_SAY" or event == "CHAT_MSG_YELL" or event == "CHAT_MSG_WHISPER" then
        onPublic(a1, a2)
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "NAME_PLATE_UNIT_ADDED",
                     "NAME_PLATE_UNIT_REMOVED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
                     "PARTY_INVITE_REQUEST", "GROUP_JOINED", "GROUP_LEFT", "GROUP_ROSTER_UPDATE",
                     "CHAT_MSG_CHANNEL", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_WHISPER" }) do
    pcall(ev.RegisterEvent, ev, e)
end

-- messages des autres CorpUI : "VERBE zone [code]"
if ns.Comm and ns.Comm.On then
    ns.Comm.On(KIND, function(who, payload, channel)
        if not db then return end
        local verb, zone, code = (str(payload) or ""):match("^(%u+)%s+(%d+)%s*(%S*)$")
        zone = tonumber(zone)
        if not verb or not zone then return end
        if not code:match("^%d+$") then code = nil end
        if verb == "REQ" and channel == "GUILD" then
            onRequest(who, zone, code)
        elseif channel == "WHISPER" then
            if verb == "OFFER" then onOffer(who, zone, code)
            elseif verb == "PICK" then onPick(who, zone)
            elseif verb == "BUSY" then onBusy(who) end
        end
    end)
end

ns.RegisterModule({
    command = "couches",
    alias = "layer",
    panelName = "CorpUILayerOptions",
    icon = "Interface\\Icons\\Spell_Nature_AstralRecal",
    title = function() return L.MOD_LAYER end,
    desc = function() return L.LAYER_DESC end,
    Slash = function(rest)
        rest = strlower(strtrim(rest or ""))
        if not db then return end
        if rest == "swap" or rest == "changer" then
            toggleSwap()
        elseif rest == "diag" then
            diag()
        else
            openPanel()
        end
    end,
    Open = openPanel,
})

-- banc d essai
ns._layer = { codeOf = codeOf, isRequest = isRequest, publicChannel = publicChannel, tick = tick,
              state = function() return db, swap, current, zoneId, hosted, obs end, toggle = toggleSwap }
