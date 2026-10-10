--[[--------------------------------------------------------------------------
    CorpUI - module Dissipation (page "Intendance du raid")

    - Alerte sur les cadres de groupe et de raid (Groupe.lua) : couleur du
      type de debuff que l on peut dissiper (liseré, teinte ou les deux,
      intensite reglable) et petit son quand il apparait.
      En combat seul le client lit les auras : la case "debuff a dissiper"
      de chaque cadre est un emplacement du conteneur du client (filtre
      "HARMFUL|RAID"), montre et colore par lui. Le son vient de Groupe, qui
      regarde si cette case vient d apparaitre (visibilite de notre cadre,
      aucune aura lue).
    - Repartition en raid, facon Buffs : chaque joueur qui dissipe recoit
      des groupes (1 a 8). Avec une repartition, l alerte (couleur et son)
      ne vaut que pour MES groupes. Editee par le chef ou un assistant,
      partagee aux autres CorpUI (ns.Comm) :
        DSA "1;Nom=125,Autre=34"  repartition complete (chef / assistant)
        DSQ ""                    demande de la repartition (arrivee en raid)
      Une repartition recue d un simple membre est ignoree.

    Reglages d affichage : CorpUIDB.group.heal (partages avec Groupe :
    dispel, dispelAll, dispelStyle, tintAlpha). Le reste : CorpUIDB.dispel.
    Rien de securise ici.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local issecret = issecretvalue or function() return false end

-- ce que chaque classe dissipe (vanilla)
local CAN = {
    PRIEST = { Magic = true, Disease = true },
    PALADIN = { Magic = true, Poison = true, Disease = true },
    DRUID = { Curse = true, Poison = true },
    MAGE = { Curse = true },
    SHAMAN = { Poison = true, Disease = true },
}
local TYPES = { "Magic", "Curse", "Poison", "Disease" }
local TYPE_COLOR = { Magic = { 0.2, 0.6, 1 }, Curse = { 0.6, 0, 1 }, Disease = { 0.6, 0.4, 0 }, Poison = { 0, 0.6, 0 } }

-- sons proposes : numero du jeu (SOUNDKIT si le client le connait)
-- sons du jeu (SoundKitConstants, branche forever) : nom de la constante,
-- numero de repli ; libelle DSP_SOUND_<CLE>. Le choix dans la liste joue le son.
local SOUND_LIST = {
    { "none" },
    { title = "DSP_GROUP_GAME" },
    { "soft", "TELL_MESSAGE", 3081 },
    { "ping", "MAP_PING", 3175 },
    { "invite", "IG_PLAYER_INVITE", 880 },
    { "toast", "UI_BNET_TOAST", 18019 },
    { "tuto", "TUTORIAL_POPUP", 7355 },
    { "coin", "LOOT_WINDOW_COIN_SOUND", 120 },
    { "quest", "IG_QUEST_LIST_COMPLETE", 878 },
    { "bell", "ALARM_CLOCK_WARNING_3", 12889 },
    { "alarm1", "ALARM_CLOCK_WARNING_1", 18871 },
    { "alarm2", "ALARM_CLOCK_WARNING_2", 12867 },
    { "ready", "READY_CHECK", 8960 },
    { "role", "LFG_ROLE_CHECK", 17317 },
    { "pvp", "PVP_THROUGH_QUEUE", 8459 },
    { "gm", "GM_CHAT_WARNING", 15273 },
    { "raid", "RAID_WARNING", 8959 },
    { "boss", "RAID_BOSS_EMOTE_WARNING", 12197 },
    -- fichiers de CorpUI (Media\Sons, licences libres, voir CREDITS.txt) ;
    -- un fichier ajoute n est vu par le jeu qu apres son redemarrage
    { title = "DSP_GROUP_CORPUI" },
    { "f_ding", file = "ding" },
    { "f_dinggrave", file = "ding_grave" },
    { "f_carillon", file = "carillon" },
    { "f_bong", file = "bong" },
    { "f_verre", file = "verre" },
    { "f_question", file = "question" },
    { "f_confirm1", file = "confirmation1" },
    { "f_confirm2", file = "confirmation2" },
    { "f_montee", file = "montee" },
    { "f_tambour", file = "tambour" },
    { "f_alarme", file = "alarme" },
    { "f_alarmelongue", file = "alarme_longue" },
    { "f_erreur1", file = "erreur1" },
    { "f_erreur2", file = "erreur2" },
    { "f_refus", file = "refus" },
    { title = "DSP_GROUP_FUN" },
    { "f_trombone", file = "trombone" },
    { "f_klaxon", file = "klaxon" },
    { "f_sonnette", file = "sonnette" },
    { "f_sorciere", file = "sorciere" },
    { "f_paon", file = "paon" },
    { "f_bizarre1", file = "bizarre1", weird = 1 },
    { "f_bizarre2", file = "bizarre2", weird = 2 },
    { "f_bizarre3", file = "bizarre3", weird = 3 },
    { "f_bizarre4", file = "bizarre4", weird = 4 },
    { "f_bizarre5", file = "bizarre5", weird = 5 },
    { "f_bizarre6", file = "bizarre6", weird = 6 },
    { "f_bizarre7", file = "bizarre7", weird = 7 },
    { "f_bizarre8", file = "bizarre8", weird = 8 },
}
local SOUNDS, SOUND_KIT, SOUND_FILE = {}, {}, {}
for _, s in ipairs(SOUND_LIST) do
    if s[1] then SOUNDS[#SOUNDS + 1] = s[1] end
    if s[2] then SOUND_KIT[s[1]] = { s[2], s[3] } end
    if s.file then SOUND_FILE[s[1]] = (ns.MEDIA or "Interface\\AddOns\\CorpUI\\Media\\") .. "Sons\\" .. s.file .. ".ogg" end
end

local ALERT_GAP = 2           -- un son toutes les 2 s au plus
local REPLY_GAP = 10
local MAX_ROWS = 20

local db, hs
local Comm

ns.Dispel = {}
local D = ns.Dispel

---------------------------------------------------------------------------
-- Valeurs sures
---------------------------------------------------------------------------

local function flag(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn, ...)
    if not ok or issecret(v) then return false end
    return v and true or false
end

local function num(v)
    if issecret(v) or type(v) ~= "number" then return nil end
    return v
end

local function str(v)
    if issecret(v) or type(v) ~= "string" then return nil end
    return v
end

local function unitClass(unit)
    local ok, _, c = pcall(UnitClass, unit)
    return ok and str(c) or nil
end

---------------------------------------------------------------------------
-- Groupe : membres, groupes du raid, droits
---------------------------------------------------------------------------

-- { unit, id, class, group } pour chaque membre lisible
local function roster()
    local out = {}
    if flag(IsInRaid) then
        local n = num(GetNumGroupMembers and GetNumGroupMembers()) or 0
        for i = 1, math.min(n, 40) do
            local unit = "raid" .. i
            local id = ns.Names.Unit(unit)
            if id then
                local ok, _, _, g = pcall(GetRaidRosterInfo, i)
                out[#out + 1] = { unit = unit, id = id, class = unitClass(unit), group = ok and num(g) or 1 }
            end
        end
    else
        local units = { "player" }
        if flag(IsInGroup) then for i = 1, 4 do units[#units + 1] = "party" .. i end end
        for _, unit in ipairs(units) do
            local id = ns.Names.Unit(unit)
            if id then out[#out + 1] = { unit = unit, id = id, class = unitClass(unit), group = 1 } end
        end
    end
    return out
end

local function promotedUnit(unit)
    if flag(UnitIsGroupLeader, unit) then return true end
    if flag(IsInRaid) and (flag(UnitIsGroupAssistant, unit) or flag(IsEveryoneAssistant)) then return true end
    return false
end

-- chef ou assistant (seul hors groupe : on prepare librement)
local function canEdit()
    if not flag(IsInGroup) then return true end
    return promotedUnit("player")
end

local function senderPromoted(who)
    for _, m in ipairs(roster()) do
        if m.id == who then return promotedUnit(m.unit) end
    end
    return false
end

---------------------------------------------------------------------------
-- Repartition
---------------------------------------------------------------------------

local function myGroups()
    local me = ns.Names.Me()
    local set = me and db and db.assign[me]
    if type(set) ~= "table" or next(set) == nil then return nil end
    return set
end

-- l alerte vaut-elle pour cette unite ? (repartition en raid seulement)
function D.IsMine(unit)
    if not db or not db.onlyMine or not flag(IsInRaid) then return true end
    local set = myGroups()
    if not set then return true end
    local idx = type(unit) == "string" and tonumber(unit:match("^raid(%d+)$") or "")
    if not idx then return true end
    local ok, _, _, g = pcall(GetRaidRosterInfo, idx)
    g = ok and num(g) or nil
    if not g then return true end
    return set[g] == true
end

local function encode()
    local parts = {}
    for id, set in pairs(db.assign) do
        local digits = {}
        for g = 1, 8 do if set[g] then digits[#digits + 1] = tostring(g) end end
        if #digits > 0 and not id:find("[,=;]") then parts[#parts + 1] = id .. "=" .. table.concat(digits) end
    end
    table.sort(parts)
    return "1;" .. table.concat(parts, ",")
end

local function decode(payload)
    local v, list = payload:match("^(%d+);(.*)$")
    if v ~= "1" then return nil end
    local out = {}
    for item in list:gmatch("[^,]+") do
        local id, digits = item:match("^(.-)=(%d+)$")
        if id and id ~= "" then
            local set = {}
            for d in digits:gmatch("%d") do
                local g = tonumber(d)
                if g and g >= 1 and g <= 8 then set[g] = true end
            end
            out[id] = set
        end
    end
    return out
end

local refreshWindow   -- plus bas

local function changed()
    if ns.GroupDispelRefresh then ns.GroupDispelRefresh() end
    if refreshWindow then refreshWindow() end
end

local shareTimer = false
local function share()
    if not (Comm and Comm.Send) or not flag(IsInGroup) or not canEdit() then return end
    if shareTimer then return end
    shareTimer = true
    C_Timer.After(1.5, function()
        shareTimer = false
        if canEdit() then Comm.Send("DSA", encode(), "GROUP") end
    end)
end

local lastReply, replyPending = -REPLY_GAP, false
local function reply()
    if not canEdit() or not flag(IsInGroup) then return end
    local wait = REPLY_GAP - (GetTime() - lastReply)
    if wait <= 0 then
        lastReply = GetTime()
        C_Timer.After(0.5 + math.random() * 2, function() Comm.Send("DSA", encode(), "GROUP") end)
    elseif not replyPending then
        replyPending = true
        C_Timer.After(wait + math.random() * 2, function()
            replyPending = false
            lastReply = GetTime()
            if canEdit() then Comm.Send("DSA", encode(), "GROUP") end
        end)
    end
end

local function onAssign(who, payload)
    if not db or not senderPromoted(who) then return end
    local t = decode(payload)
    if not t then return end
    db.assign = t
    changed()
end

-- groupes du raid ou il y a quelqu un
local function groupsPresent()
    local set, list = {}, {}
    for _, m in ipairs(roster()) do
        if m.group and not set[m.group] then
            set[m.group] = true
            list[#list + 1] = m.group
        end
    end
    table.sort(list)
    if #list == 0 then list = { 1 } end
    return list
end

-- dissipateurs du groupe, dans l ordre des noms
local function dispellers()
    local list = {}
    for _, m in ipairs(roster()) do
        if m.class and CAN[m.class] then list[#list + 1] = m end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

-- repartition automatique : pour chaque type, les groupes tournent entre
-- ceux qui le dissipent ; chacun garde l union de ce qu il a recu
function D.AutoAssign()
    if not canEdit() then ns.Say(L.DSP_NEED_LEAD) return end
    local groups = groupsPresent()
    local out = {}
    for _, t in ipairs(TYPES) do
        local able = {}
        for _, m in ipairs(dispellers()) do if CAN[m.class][t] then able[#able + 1] = m end end
        for i, g in ipairs(groups) do
            local m = able[#able > 0 and ((i - 1) % #able + 1) or 0]
            if m then
                out[m.id] = out[m.id] or {}
                out[m.id][g] = true
            end
        end
    end
    db.assign = out
    changed()
    share()
end

function D.Clear()
    if not canEdit() then ns.Say(L.DSP_NEED_LEAD) return end
    db.assign = {}
    changed()
    share()
end

local function toggleCell(id, g)
    if not canEdit() then ns.Say(L.DSP_NEED_LEAD) return end
    local set = db.assign[id] or {}
    set[g] = not set[g] or nil
    db.assign[id] = next(set) and set or nil
    changed()
    share()
end

local function groupsText(set)
    local list = {}
    for g = 1, 8 do if set[g] then list[#list + 1] = tostring(g) end end
    return table.concat(list, ", ")
end

-- annonce au groupe : une ou plusieurs lignes de 240 caracteres au plus
function D.Announce()
    if C_ChatInfo and flag(C_ChatInfo.InChatMessagingLockdown) then ns.Say(L.DSP_LOCKED) return end
    local entries = {}
    for _, m in ipairs(dispellers()) do
        local set = db.assign[m.id]
        if set and next(set) then
            entries[#entries + 1] = string.format(L.DSP_ANN_ENTRY, ns.Names.Short(m.id), groupsText(set))
        end
    end
    if #entries == 0 then ns.Say(L.DSP_NOTHING) return end
    local chan = flag(IsInRaid) and "RAID" or (flag(IsInGroup) and "PARTY") or nil
    local lines, cur = {}, L.DSP_ANN_HEAD
    for _, e in ipairs(entries) do
        local add = (cur == L.DSP_ANN_HEAD) and (" " .. e) or (" | " .. e)
        if #cur + #add > 240 then
            lines[#lines + 1] = cur
            cur = L.DSP_ANN_HEAD .. " " .. e
        else
            cur = cur .. add
        end
    end
    lines[#lines + 1] = cur
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    for _, line in ipairs(lines) do
        if chan and type(send) == "function" then pcall(send, line, chan) else ns.Chat(line) end
    end
end

---------------------------------------------------------------------------
-- Son
---------------------------------------------------------------------------

local function soundId(key)
    local k = SOUND_KIT[key]
    if not k then return nil end
    local v = SOUNDKIT and SOUNDKIT[k[1]]
    if type(v) == "number" then return v end
    return k[2]
end

local function playSound(key)
    local file = SOUND_FILE[key]
    if file then
        if PlaySoundFile then pcall(PlaySoundFile, file, "Master") end
        return
    end
    local id = soundId(key)
    if id and PlaySound then pcall(PlaySound, id, "Master") end
end

local lastAlert = -ALERT_GAP
-- un debuff a dissiper vient d apparaitre sur un cadre (appele par Groupe)
function D.Alert(unit)
    if not db or db.sound == "none" then return end
    if not D.IsMine(unit) then return end
    local t = GetTime()
    if t - lastAlert < ALERT_GAP then return end
    lastAlert = t
    playSound(db.sound)
end

---------------------------------------------------------------------------
-- Panneau
---------------------------------------------------------------------------

local win, form, rowsFrame, info
local rows = {}

local function typeDots(row, class)
    for i, t in ipairs(TYPES) do
        local dot = row.dots[i]
        local on = CAN[class] and CAN[class][t]
        dot:SetShown(on and true or false)
        if on then
            local c = TYPE_COLOR[t]
            dot:SetColorTexture(c[1], c[2], c[3], 1)
        end
    end
end

local function makeRow(parent, i)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(440, 20)
    r:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(i - 1) * 22)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", 4, 0)
    r.name:SetWidth(120)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.dots = {}
    for k = 1, 4 do
        local d = r:CreateTexture(nil, "ARTWORK")
        d:SetSize(6, 12)
        d:SetPoint("LEFT", r, "LEFT", 128 + (k - 1) * 8, 0)
        r.dots[k] = d
    end
    r.cells = {}
    local C = ns.COLORS
    for g = 1, 8 do
        local c = CreateFrame("Button", nil, r, "BackdropTemplate")
        c:SetSize(28, 18)
        c:SetPoint("LEFT", r, "LEFT", 168 + (g - 1) * 32, 0)
        ns.UI.SetBackdrop(c, 0.6)
        c.fill = c:CreateTexture(nil, "ARTWORK")
        c.fill:SetPoint("TOPLEFT", 1, -1)
        c.fill:SetPoint("BOTTOMRIGHT", -1, 1)
        c.fill:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.75)
        c.text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        c.text:SetPoint("CENTER")
        c.text:SetText(g)
        c:SetScript("OnClick", function() if r.id then toggleCell(r.id, g) end end)
        c:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(C.gold[1], C.gold[2], C.gold[3], 1) end)
        c:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1) end)
        r.cells[g] = c
    end
    return r
end

refreshWindow = function()
    if not win or not win:IsShown() then return end
    if form then form:Refresh() end
    local list = dispellers()
    local present = {}
    for _, g in ipairs(groupsPresent()) do present[g] = true end
    local shown = math.min(#list, MAX_ROWS)
    for i = 1, shown do
        local m = list[i]
        local r = rows[i]
        r.id = m.id
        r.name:SetText(ns.Names.Short(m.id))
        local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[m.class]
        if c then r.name:SetTextColor(c.r, c.g, c.b) else r.name:SetTextColor(1, 1, 1) end
        typeDots(r, m.class)
        local set = db.assign[m.id] or {}
        for g = 1, 8 do
            local cell = r.cells[g]
            cell.fill:SetShown(set[g] and true or false)
            cell:SetAlpha(present[g] and 1 or 0.35)
        end
        r:Show()
    end
    for i = shown + 1, MAX_ROWS do rows[i]:Hide() end
    local mine = myGroups()
    local status
    if #list == 0 then
        status = L.DSP_NONE
    elseif mine then
        status = string.format(L.DSP_MINE, groupsText(mine))
    else
        status = L.DSP_ALL
    end
    if #list > MAX_ROWS then status = status .. string.format("  (+%d)", #list - MAX_ROWS) end
    if not canEdit() then status = status .. "\n" .. L.DSP_READONLY end
    info:SetText(status)
end

local WIN_W = 440

local function buildWindow()
    win = ns.UI.Window("CorpUIDispelOptions", ns.TITLE .. " - " .. L.MOD_DISPEL, nil, WIN_W, 600)
    form = ns.UI.Form(win, -34, function() changed() end)
    local function hcheck(text, key)
        form:Check(text, function() return hs[key] end, function(v) hs[key] = v end)
    end
    form:Header(L.DSP_ALERT_HEAD)
    hcheck(L.DSP_OPT_HIGHLIGHT, "dispel")
    hcheck(L.DSP_OPT_ALL, "dispelAll")
    form:Columns(2)
    form:Cycle(L.DSP_OPT_STYLE, { "border", "tint", "both" },
        { border = L.GROUP_HEAL_BORDER, tint = L.GROUP_HEAL_TINT, both = L.GROUP_HEAL_BOTH },
        function() return hs.dispelStyle end, function(v) hs.dispelStyle = v end)
    form:Number(L.DSP_OPT_TINT, function() return hs.tintAlpha end, function(v) hs.tintAlpha = v end, 10, 90, 5)
    form:EndColumns()
    -- son : liste a intertitres (jeu, CorpUI, rigolos) ; le choix le joue
    local soundSel = form:Select(L.DSP_OPT_SOUND, function()
        local list = {}
        for _, s in ipairs(SOUND_LIST) do
            if s.title then
                list[#list + 1] = { title = true, value = "#" .. s.title, text = L[s.title] }
            else
                local text = L["DSP_SOUND_" .. s[1]:upper()]
                if s.weird then text = string.format(L.DSP_SOUND_WEIRD, s.weird) end
                list[#list + 1] = { value = s[1], text = text or s[1] }
            end
        end
        return list
    end, function() return db.sound end, function(v) db.sound = v; playSound(v) end, 200)
    local test = ns.UI.Button(win, L.DSP_TEST, 100, function() playSound(db.sound) end)
    test:SetPoint("LEFT", soundSel, "RIGHT", 8, 0)
    form:Check(L.DSP_OPT_MINE, function() return db.onlyMine end, function(v) db.onlyMine = v end)
    form:Gap(6)
    form:Header(L.DSP_ASSIGN_HEAD)
    -- en-tete des colonnes de groupes
    local y = form.y
    local headName = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    headName:SetPoint("TOPLEFT", win, "TOPLEFT", 12, y)
    headName:SetText(L.DSP_COL_PLAYER)
    for g = 1, 8 do
        local h = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        h:SetPoint("TOPLEFT", win, "TOPLEFT", 8 + 168 + (g - 1) * 32 + 2, y)
        h:SetText(string.format(L.DSP_COL_GROUP, g))
    end
    y = y - 16
    rowsFrame = CreateFrame("Frame", nil, win)
    rowsFrame:SetPoint("TOPLEFT", win, "TOPLEFT", 8, y)
    rowsFrame:SetSize(WIN_W - 16, MAX_ROWS * 22)
    for i = 1, MAX_ROWS do rows[i] = makeRow(rowsFrame, i) end
    local auto = ns.UI.Button(win, L.DSP_AUTO, 130, function() D.AutoAssign() end)
    local clear = ns.UI.Button(win, L.DSP_CLEAR, 100, function() D.Clear() end)
    local ann = ns.UI.Button(win, L.DSP_ANNOUNCE, 110, function() D.Announce() end)
    info = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    info:SetJustifyH("LEFT")
    info:SetJustifyV("TOP")
    info:SetWidth(WIN_W - 16)
    info:SetHeight(30)
    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetJustifyH("LEFT")
    hint:SetJustifyV("TOP")
    hint:SetWidth(WIN_W - 16)
    hint:SetHeight(56)
    hint:SetText(L.DSP_HINT)
    -- boutons sous la derniere ligne affichee (place recalculee a l ouverture)
    local function place()
        local n = math.max(1, math.min(#dispellers(), MAX_ROWS))
        local by = y - n * 22 - 6
        auto:ClearAllPoints()
        auto:SetPoint("TOPLEFT", win, "TOPLEFT", 8, by)
        clear:ClearAllPoints()
        clear:SetPoint("LEFT", auto, "RIGHT", 6, 0)
        ann:ClearAllPoints()
        ann:SetPoint("LEFT", clear, "RIGHT", 6, 0)
        info:ClearAllPoints()
        info:SetPoint("TOPLEFT", win, "TOPLEFT", 8, by - 30)
        hint:ClearAllPoints()
        hint:SetPoint("TOPLEFT", win, "TOPLEFT", 8, by - 62)
        win:SetHeight(math.floor(-(by - 62 - 60)))
    end
    win.placeBottom = place
    place()
    win:HookScript("OnShow", function()
        place()
        refreshWindow()
    end)
end

local function toggle()
    if not db then return end
    if not win then buildWindow() end
    ns.ShowPanel(win)
    refreshWindow()
end

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

local wasRaid = false
local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if ns.ModuleOff("dissipation", ev) then return end
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        root.dispel = root.dispel or {}
        db = root.dispel
        if type(db.assign) ~= "table" then db.assign = {} end
        if db.sound == nil then db.sound = "soft" end
        if db.onlyMine == nil then db.onlyMine = true end
        root.group = root.group or {}
        root.group.heal = root.group.heal or {}
        hs = root.group.heal
        if hs.tintAlpha == nil then hs.tintAlpha = 35 end
        Comm = ns.Comm
        if Comm and Comm.On then
            Comm.On("DSA", onAssign)
            Comm.On("DSQ", function() reply() end)
        end
        wasRaid = flag(IsInRaid)
        if wasRaid then C_Timer.After(6, function() if Comm and Comm.Send then Comm.Send("DSQ", "", "GROUP") end end) end
        return
    end
    if not db then return end
    if event == "GROUP_ROSTER_UPDATE" or event == "PARTY_LEADER_CHANGED" then
        local raid = flag(IsInRaid)
        if raid and not wasRaid and Comm and Comm.Send then
            C_Timer.After(3, function() Comm.Send("DSQ", "", "GROUP") end)
        end
        wasRaid = raid
        changed()
        if win and win:IsShown() and win.placeBottom then win.placeBottom() end
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)
end

ns.RegisterModule({
    command = "dissipation",
    panelName = "CorpUIDispelOptions",
    icon = "Interface\\Icons\\Spell_Holy_DispelMagic",
    title = function() return L.MOD_DISPEL end,
    desc = function() return L.DSP_DESC end,
    Slash = function(input)
        local cmd = strlower(strtrim(input or ""))
        if cmd == "auto" then D.AutoAssign() return end
        if cmd == "annonce" or cmd == "announce" then D.Announce() return end
        toggle()
    end,
    Open = toggle,
})
