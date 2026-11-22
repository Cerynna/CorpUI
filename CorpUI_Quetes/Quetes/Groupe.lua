--[[--------------------------------------------------------------------------
    CorpUI - module Suivi de quetes : les quetes du groupe (22/11)
    Qui, dans le groupe, a la meme quete, et ou il en est.

    Deux sources :
    - le serveur : C_QuestLog.IsUnitOnQuest (comme QuestUtils de Blizzard),
      et la progression qu il donne a l infobulle du journal
      (C_TooltipInfo.GetQuestPartyProgress, lue par Quetes.lua) ;
    - les autres CorpUI du groupe (ns.Comm, sorte "QST") : chacun envoie son
      journal. Charge utile, premier caractere :
        F  journal complet
        R  journal complet, et chacun renvoie le sien (arrivee dans un
           groupe, connexion en groupe) : une reponse par 10 s au plus
        D  changements seulement (2 s apres le dernier QUEST_LOG_UPDATE)
        Q  (en message prive) "renvoie-moi ton journal" : on a recu un D
           d un joueur dont on n a pas le journal
      Entrees separees par ";" : "numero[!]:f/r[*],f/r[*]" (! = prete a
      rendre ; f/r = fait / demande par objectif, * = objectif termine) ;
      "-numero" dans un D = quete partie du journal.
      On ne garde que les joueurs encore dans le groupe ; tout s efface quand
      on le quitte.

    API (ns.QuestParty) :
      Members(questID) -> { { id, name, class, unit, entry, server } } dans
                          l ordre du groupe, nous exclus. entry = ce que son
                          CorpUI a envoye ({ done, obj = { { f, r, fin } } })
                          ou nil ; server = le serveur dit qu il l a
      OnChange(fn)     -> fn() quand ce que l on sait du groupe change
      Start()          -> a la connexion, module actif (Quetes.lua)

    Regles de ce client : rien de secret envoye, chaque valeur lue
    verifiee par issecretvalue avant toute comparaison, aucune globale.
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)

local issecret = issecretvalue or function() return false end

local KIND = "QST"
local MAX_QUESTS, MAX_OBJ = 60, 12
local DELTA_WAIT, REPLY_GAP, ASK_GAP = 2, 10, 30

local QP = {}
ns.QuestParty = QP

local data = {}        -- "Nom-Royaume" -> { [questID] = { done, obj } }
local sent = {}        -- questID -> chaine : ce que le groupe a de nous
local group = {}       -- membres actuels : identite -> unite, nous exclus
local order = {}       -- les memes dans l ordre du groupe : { id, unit }
local listeners = {}
local started = false
local deltaPending, replyPending, lastReply = false, false, -REPLY_GAP
local asked = {}       -- identite -> GetTime() de notre derniere demande "Q"

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end

local function num(v)
    if issecret(v) or type(v) ~= "number" then return nil end
    return v
end

local function yes(fn, ...)
    local v = safe(fn, ...)
    if issecret(v) then return false end
    return v == true
end

local function field(t, k)
    if issecret(t) or type(t) ~= "table" then return nil end
    local v = t[k]
    if issecret(v) then return nil end
    return v
end

local function changed()
    for _, fn in ipairs(listeners) do pcall(fn) end
end

function QP.OnChange(fn)
    if type(fn) == "function" then listeners[#listeners + 1] = fn end
end

---------------------------------------------------------------------------
-- Groupe
---------------------------------------------------------------------------

local function me()
    return ns.Names and ns.Names.Me()
end

-- unites du groupe dans l ordre : partyN, ou raidN en raid
local function units()
    if yes(IsInRaid) then
        local list = {}
        for i = 1, 40 do list[i] = "raid" .. i end
        return list
    end
    return { "party1", "party2", "party3", "party4" }
end

local function readGroup()
    local set, list = {}, {}
    local self = me()
    if ns.Names and yes(IsInGroup) then
        for _, u in ipairs(units()) do
            local id = ns.Names.Unit(u)
            if id and id ~= self and not set[id] then
                set[id] = u
                list[#list + 1] = { id = id, unit = u }
            end
        end
    end
    group, order = set, list
    -- joueurs partis : leurs quetes s en vont
    for who in pairs(data) do
        if not set[who] then data[who] = nil end
    end
end

---------------------------------------------------------------------------
-- Notre journal
---------------------------------------------------------------------------

local function snapshot()
    local out, count = {}, 0
    local Q = C_QuestLog
    if not Q then return out end
    for i = 1, num((safe(Q.GetNumQuestLogEntries))) or 0 do
        local info = safe(Q.GetInfo, i)
        local id = num(field(info, "questID"))
        if id and id > 0 and not field(info, "isHeader") and not field(info, "isHidden") then
            local objs = {}
            local list = safe(Q.GetQuestObjectives, id)
            if not issecret(list) and type(list) == "table" then
                for k, o in ipairs(list) do
                    if k > MAX_OBJ then break end
                    local f = math.floor(num(field(o, "numFulfilled")) or 0)
                    local r = math.floor(num(field(o, "numRequired")) or 0)
                    objs[#objs + 1] = f .. "/" .. r .. ((field(o, "finished") == true) and "*" or "")
                end
            end
            local done = safe(Q.IsComplete, id)
            done = not issecret(done) and done == true
            out[id] = id .. (done and "!" or "") .. ":" .. table.concat(objs, ",")
            count = count + 1
            if count >= MAX_QUESTS then break end
        end
    end
    return out
end

local function inGroup()
    return yes(IsInGroup)
end

local function comm()
    return ns.Comm and ns.Comm.Send and ns.Comm
end

-- journal complet ; au groupe, il devient la base des changements suivants
-- (en prive non : les autres n ont pas recu celui-la)
local function full(mark, channel, target)
    local C = comm()
    if not C or not inGroup() then return end
    local snap = snapshot()
    local list = {}
    for _, s in pairs(snap) do list[#list + 1] = s end
    if not target then sent = snap end
    C.Send(KIND, mark .. table.concat(list, ";"), target and "WHISPER" or "GROUP", target)
end

local function delta()
    local C = comm()
    if not C or not inGroup() then return end
    local snap = snapshot()
    local list = {}
    for id, s in pairs(snap) do
        if sent[id] ~= s then list[#list + 1] = s end
    end
    for id in pairs(sent) do
        if not snap[id] then list[#list + 1] = "-" .. id end
    end
    sent = snap
    if #list > 0 then C.Send(KIND, "D" .. table.concat(list, ";"), "GROUP") end
end

local function scheduleDelta()
    if deltaPending or not inGroup() then return end
    deltaPending = true
    C_Timer.After(DELTA_WAIT, function()
        deltaPending = false
        delta()
    end)
end

-- quelqu un veut tous les journaux : le notre part une fois (10 s au plus)
local function reply()
    if replyPending then return end
    replyPending = true
    local wait = math.max(0, REPLY_GAP - (GetTime() - lastReply)) + 0.5 + math.random() * 2
    C_Timer.After(wait, function()
        replyPending = false
        lastReply = GetTime()
        full("F")
    end)
end

---------------------------------------------------------------------------
-- Reception
---------------------------------------------------------------------------

-- "26000!:3/10*,1/1" -> id, { done, obj }
local function parseEntry(s)
    local id, bang, rest = s:match("^(%d+)(!?):(.*)$")
    id = tonumber(id)
    if not id then return nil end
    local e = { done = bang == "!", obj = {} }
    for f, r, star in rest:gmatch("(%d+)/(%d+)(%*?)") do
        if #e.obj >= MAX_OBJ then break end
        e.obj[#e.obj + 1] = { f = tonumber(f), r = tonumber(r), fin = star == "*" }
    end
    return id, e
end

local function onMessage(who, payload, channel)
    if type(who) ~= "string" or type(payload) ~= "string" then return end
    local mark, body = payload:sub(1, 1), payload:sub(2)
    if mark == "Q" then
        if not group[who] then readGroup() end
        if group[who] then full("F", nil, who) end
        return
    end
    -- arrive a l instant (liste du groupe pas encore relue)
    if not group[who] then readGroup() end
    if not group[who] then return end
    if mark == "F" or mark == "R" then
        local q, count = {}, 0
        for s in body:gmatch("[^;]+") do
            local id, e = parseEntry(s)
            if id then
                q[id] = e
                count = count + 1
                if count >= MAX_QUESTS then break end
            end
        end
        data[who] = q
        if mark == "R" then reply() end
        changed()
    elseif mark == "D" then
        local q = data[who]
        if not q then
            -- son journal nous manque (rechargement) : on le lui demande
            local now = GetTime()
            if not asked[who] or now - asked[who] > ASK_GAP then
                asked[who] = now
                local C = comm()
                if C then C.Send(KIND, "Q", "WHISPER", who) end
            end
            return
        end
        for s in body:gmatch("[^;]+") do
            local gone = tonumber(s:match("^%-(%d+)$") or "")
            if gone then
                q[gone] = nil
            else
                local id, e = parseEntry(s)
                if id then q[id] = e end
            end
        end
        changed()
    end
end

---------------------------------------------------------------------------
-- Lecture
---------------------------------------------------------------------------

-- dans notre sous-groupe (ceux que couvrent les lignes du serveur)
local function inSubgroup(u)
    if u:find("^party") then return true end
    for k = 1, 4 do
        if yes(UnitIsUnit, u, "party" .. k) then return true end
    end
    return false
end

function QP.Members(questID)
    local list = {}
    if not inGroup() or not num(questID) then return list end
    for _, m in ipairs(order) do
        local id, u = m.id, m.unit
        local q = data[id]
        local entry = q and q[questID]
        local server = yes(C_QuestLog and C_QuestLog.IsUnitOnQuest, u, questID)
        if entry or server then
            local _, class = safe(UnitClass, u)
            if issecret(class) or type(class) ~= "string" then class = nil end
            list[#list + 1] = {
                id = id, unit = u, class = class, entry = entry, server = server,
                party = inSubgroup(u), name = ns.Names.Short(id),
            }
        end
    end
    return list
end

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
local rosterPending = false

ev:SetScript("OnEvent", function(_, event, unit)
    if not started then return end
    if event == "QUEST_LOG_UPDATE" then
        scheduleDelta()
    elseif event == "UNIT_QUEST_LOG_CHANGED" then
        if issecret(unit) or unit == "player" then return end
        changed()
    elseif event == "GROUP_LEFT" then
        data, sent, group, order = {}, {}, {}, {}
        changed()
    elseif event == "GROUP_JOINED" then
        readGroup()
        C_Timer.After(3 + math.random() * 2, function() full("R") end)
        changed()
    elseif event == "GROUP_ROSTER_UPDATE" then
        -- rafale (invitations, connexions) : un passage
        if rosterPending then return end
        rosterPending = true
        C_Timer.After(0.5, function()
            rosterPending = false
            if not inGroup() then
                data, sent, group, order = {}, {}, {}, {}
            else
                readGroup()
            end
            changed()
        end)
    end
end)

function QP.Start()
    if started then return end
    started = true
    for _, e in ipairs({ "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "GROUP_JOINED", "GROUP_LEFT",
                         "GROUP_ROSTER_UPDATE" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    if ns.Comm and ns.Comm.On then ns.Comm.On(KIND, onMessage) end
    readGroup()
    -- connexion (ou rechargement) deja en groupe : journaux de tous
    if inGroup() then
        C_Timer.After(6 + math.random() * 2, function()
            readGroup()
            full("R")
        end)
    end
end

-- banc d essai
QP._test = { snapshot = snapshot, parseEntry = parseEntry, onMessage = onMessage, data = function() return data end,
             readGroup = readGroup, delta = delta, full = full }
