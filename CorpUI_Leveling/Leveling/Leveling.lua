--[[--------------------------------------------------------------------------
    CorpUI - module Leveling : la fenetre, les reglages, les evenements

    Fenetre "Leveling" : l etape en cours en tete, puis les suivantes
    (nombre au choix), chacune avec son icone, la quete (couleur de sa
    difficulte), l objectif ou le texte du repere, la distance.
      clic gauche : pointer la fleche sur cette etape (encore : laisser
                    CorpUI choisir) ;
      clic droit  : ignorer l etape (par personnage ; /corp leveling reset).
    Le bouton de l en-tete replie la liste sur l etape en cours.
    Cachee au niveau maximum. Deplacable avec "Deverrouiller l interface".

    Calcul (Moteur.lua) une fois par seconde, et tout de suite apres un
    evenement du journal ou un changement de zone ; la fleche (Fleche.lua)
    tourne a part, seulement quand elle est affichee.

    /corp leveling       : reglages
    /corp leveling diag  : ce que le jeu donne (carte, quetes placees...)
    /corp leveling reset : faire revenir les etapes ignorees
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local LV = ns.Leveling
local num, str, call = LV.num, LV.str, LV.call
local issecret = issecretvalue or function() return false end

local WIDTH = 290
local HEAD_H = 22
local ROW_H = 34
local MAX_ROWS = 8

local KINDS = {
    accept = { icon = "Interface\\GossipFrame\\AvailableQuestIcon", color = { 1, 0.82, 0 }, label = "LVL_K_ACCEPT" },
    turnin = { icon = "Interface\\GossipFrame\\ActiveQuestIcon", color = { 0.35, 1, 0.35 }, label = "LVL_K_TURNIN" },
    objective = { icon = "Interface\\Icons\\INV_Misc_Note_01", color = { 1, 0.6, 0.25 }, label = "LVL_K_OBJECTIVE" },
}
-- icone d un objectif selon son type (monstre, objet a ramasser, objet du decor)
local OBJ_ICONS = {
    monster = "Interface\\Icons\\Ability_Warrior_Cleave",
    item = "Interface\\Icons\\INV_Misc_Bag_08",
    object = "Interface\\Icons\\INV_Misc_Gear_01",
}

local db, frame, header, rows
local list = {}           -- etapes du dernier calcul
local current, pinned     -- cle de l etape en tete ; cle choisie a la main
local dirty, lastRun = true, 0

local function mine(field)
    local k = ns.CharKey()
    db[field] = db[field] or {}
    if type(db[field][k]) ~= "table" then db[field][k] = {} end
    return db[field][k]
end

local function maxLevel()
    local lvl = num(call(UnitLevel, "player"))
    local max = num(call(GetMaxLevelForPlayerExpansion)) or num(call(GetMaxPlayerLevel))
    return lvl and max and lvl >= max
end

local function levelColor(level)
    if level and GetQuestDifficultyColor then
        local ok, c = pcall(GetQuestDifficultyColor, level)
        if ok and type(c) == "table" and num(c.r) then return c.r, c.g, c.b end
    end
    return 1, 0.82, 0
end

local function iconOf(a)
    if a.kind == "objective" then return OBJ_ICONS[a.objType or ""] or KINDS.objective.icon end
    return KINDS[a.kind].icon
end

local function stepName(a)
    return string.format("%s %s", L[KINDS[a.kind].label], a.title or "?")
end

---------------------------------------------------------------------------
-- Fenetre
---------------------------------------------------------------------------

local function tooltip(self)
    local a = self.step
    if not a then return end
    local t = ns.Tooltip(self, "ANCHOR_LEFT")
    t:AddLine(a.title or "?", levelColor(a.level))
    local k = KINDS[a.kind]
    t:AddLine(L[k.label], k.color[1], k.color[2], k.color[3])
    if a.kind ~= "accept" and C_QuestLog then
        local objs = call(C_QuestLog.GetQuestObjectives, a.id)
        for _, o in ipairs(type(objs) == "table" and objs or {}) do
            local txt = type(o) == "table" and str(o.text)
            if txt then
                if not issecret(o.finished) and o.finished == true then
                    t:AddLine(txt, 0.4, 0.9, 0.4)
                else
                    t:AddLine(txt, 1, 1, 1)
                end
            end
        end
    end
    if a.viaText then t:AddLine(a.viaText, 0.6, 0.8, 1, true) end
    if a.xp and a.xp > 0 then t:AddLine(string.format(L.LVL_XP, a.xp), 0.75, 0.6, 1) end
    if a.trivial then t:AddLine(L.LVL_GRAY, 0.6, 0.6, 0.6) end
    if a.pinned then t:AddLine(L.LVL_PINNED, 1, 0.82, 0) end
    t:AddLine(" ")
    t:AddLine(L.LVL_TIP_LEFT, 0.7, 0.7, 0.7)
    t:AddLine(L.LVL_TIP_RIGHT, 0.7, 0.7, 0.7)
    t:Show()
end

local refresh

local function onRowClick(self, button)
    local a = self.step
    if not a then return end
    if button == "RightButton" then
        mine("ignored")[a.key] = true
        if pinned == a.key then pinned = nil end
        ns.Say(string.format(L.LVL_IGNORED, stepName(a)))
    else
        pinned = (pinned ~= a.key) and a.key or nil
    end
    ns.HideTooltip()
    refresh()
end

local function row(i)
    if rows[i] then return rows[i] end
    local C = ns.COLORS
    local r = CreateFrame("Button", nil, frame)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -HEAD_H - 2 - (i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -HEAD_H - 2 - (i - 1) * ROW_H)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- etape en cours : voile a gauche
    r.mark = r:CreateTexture(nil, "BACKGROUND")
    r.mark:SetAllPoints()
    ns.UI.Gradient(r.mark, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.35, C.violet[1], C.violet[2], C.violet[3], 0)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    ns.UI.Gradient(hl, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.2, C.violet[1], C.violet[2], C.violet[3], 0.05)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(18, 18)
    r.icon:SetPoint("LEFT", 3, 0)
    r.dist = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.dist:SetPoint("TOPRIGHT", -3, -4)
    r.dist:SetJustifyH("RIGHT")
    r.line1 = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.line1:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, 6)
    r.line1:SetPoint("RIGHT", r.dist, "LEFT", -4, 0)
    r.line1:SetJustifyH("LEFT")
    r.line1:SetWordWrap(false)
    r.line2 = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.line2:SetPoint("TOPLEFT", r.line1, "BOTTOMLEFT", 0, -2)
    r.line2:SetPoint("RIGHT", r, "RIGHT", -3, 0)
    r.line2:SetJustifyH("LEFT")
    r.line2:SetWordWrap(false)
    r:SetScript("OnClick", onRowClick)
    r:SetScript("OnEnter", tooltip)
    r:SetScript("OnLeave", ns.HideTooltip)
    rows[i] = r
    return r
end

local function hex(r, g, b)
    return string.format("%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function fill(r, a, first)
    r.step = a
    r.mark:SetShown(first)
    r.icon:SetTexture(iconOf(a))
    local k = KINDS[a.kind]
    local tr, tg, tb = levelColor(a.level)
    local title = "|cff" .. hex(tr, tg, tb) .. (a.title or "?") .. "|r"
    r.line1:SetText("|cff" .. hex(k.color[1], k.color[2], k.color[3]) .. L[k.label] .. "|r " .. title)
    local sub = a.kind == "objective" and a.text or nil
    if a.via and a.viaText then sub = a.viaText end
    if a.pinned then sub = (sub and (sub .. " · ") or "") .. L.LVL_PINNED end
    r.line2:SetText(sub or "")
    r.dist:SetText(a.dist and string.format(L.LVL_DIST, math.floor(a.dist + 0.5)) or (a.map and L.LVL_ELSEWHERE or ""))
    r:Show()
end

local function headerText()
    local lvl = num(call(UnitLevel, "player")) or 0
    local xp, max = num(call(UnitXP, "player")), num(call(UnitXPMax, "player"))
    local pct = (xp and max and max > 0) and math.floor(xp / max * 100) or 0
    header.level:SetText(string.format(L.LVL_LEVEL, lvl, pct))
end

local function draw()
    if not frame then return end
    local shown = db.enabled and (not maxLevel() or ns.moversShown)
    if not shown then
        frame:Hide()
        return
    end
    headerText()
    header.toggle.label:SetText(db.collapsed and "+" or "-")
    local n = db.collapsed and 1 or math.max(1, math.min(MAX_ROWS, db.rows or 5))
    local count = 0
    for i = 1, MAX_ROWS do
        local a = i <= n and list[i]
        if a then
            fill(row(i), a, i == 1)
            count = i
        elseif rows[i] then
            rows[i]:Hide()
            rows[i].step = nil
        end
    end
    frame.empty:SetShown(count == 0)
    local h = HEAD_H + 4 + math.max(1, count) * ROW_H
    if count == 0 then h = HEAD_H + 4 + 22 end
    frame:SetHeight(h)
    frame:Show()
end

local function build()
    db.pos = db.pos or { point = "TOPLEFT", x = 20, y = -300 }
    local C = ns.COLORS
    frame = CreateFrame("Frame", "CorpUILeveling", UIParent)
    frame:SetSize(WIDTH, HEAD_H + 30)
    frame:SetFrameStrata("LOW")
    ns.ApplyPos(frame, db.pos)
    ns.UI.Skin(frame, 0.72, true)
    rows = {}

    header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEAD_H)
    local rule = header:CreateTexture(nil, "BORDER")
    rule:SetPoint("BOTTOMLEFT", 4, 0)
    rule:SetPoint("BOTTOMRIGHT", -4, 0)
    rule:SetHeight(1)
    ns.NoSnap(rule)
    ns.UI.Gradient(rule, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.8, C.gold[1], C.gold[2], C.gold[3], 0)
    header.title = header:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(header.title, 12)
    header.title:SetPoint("LEFT", 6, 0)
    header.title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    header.title:SetText(L.MOD_LEVELING)
    header.toggle = CreateFrame("Button", nil, header)
    header.toggle:SetSize(18, 18)
    header.toggle:SetPoint("RIGHT", -3, 0)
    header.toggle.label = header.toggle:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(header.toggle.label, 14)
    header.toggle.label:SetPoint("CENTER", 0, 1)
    header.toggle:SetScript("OnClick", function()
        db.collapsed = not db.collapsed
        draw()
    end)
    header.level = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    header.level:SetPoint("RIGHT", header.toggle, "LEFT", -4, 0)

    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.empty:SetPoint("TOPLEFT", 8, -HEAD_H - 6)
    frame.empty:SetPoint("RIGHT", -8, 0)
    frame.empty:SetJustifyH("LEFT")
    frame.empty:SetText(L.LVL_NOTHING)
    frame:Hide()
    ns.UI.Mover(frame, db.pos, L.MOD_LEVELING)
end

---------------------------------------------------------------------------
-- Calcul
---------------------------------------------------------------------------

local function active()
    return db and (db.enabled or db.arrow or db.native) and true or false
end

refresh = function()
    if not db then return end
    dirty, lastRun = false, GetTime()
    if not active() or maxLevel() then
        list = {}
        draw()
        LV.SetArrow(nil, db)
        LV.SetNative(nil, false)
        return
    end
    local plan = LV.Plan({ offers = db.offers, gray = db.gray, ignored = mine("ignored"), current = current })
    if pinned then
        local at
        for i, a in ipairs(plan) do
            if a.key == pinned then at = i break end
        end
        if at then
            local a = table.remove(plan, at)
            a.pinned = true
            table.insert(plan, 1, a)
        else
            pinned = nil        -- etape faite (ou disparue) : CorpUI reprend la main
        end
    end
    list = plan
    current = plan[1] and plan[1].key or nil
    draw()
    LV.SetArrow(plan[1], db)
    LV.SetNative(plan[1], db.native)
end
LV.Refresh = function() if db then refresh() end end

-- banc d essai : etat de la fenetre
function LV._state() return { list = list, current = current, pinned = pinned, frame = frame, rows = rows } end

---------------------------------------------------------------------------
-- Diagnostic et remise a zero
---------------------------------------------------------------------------

function LV.Diag()
    local me = LV.Player()
    local _, stats = LV.Collect(me, { offers = true, gray = true })
    local pos = (me and me.x) and string.format("%.1f, %.1f", me.x * 100, me.y * 100) or "?"
    local facing = num(call(GetPlayerFacing))
    local wp = (C_Map and C_Map.SetUserWaypoint and C_SuperTrack) and "ok" or "absent"
    local main = string.format(L.LVL_DIAG, tostring(me and me.map), pos, stats.log, stats.onMap, stats.via, stats.offers,
        facing and string.format("%.2f", facing) or "nil", wp)
    ns.Say(main)
    for i = 1, math.min(3, #list) do
        local a = list[i]
        ns.Say(string.format("  %d. %s (%s)", i, stepName(a), a.dist and string.format(L.LVL_DIST, math.floor(a.dist + 0.5)) or "?"))
    end
    -- sources de quetes a prendre de la carte de Blizzard (QuestOfferDataProvider) :
    -- lignes de quetes, quetes forcees, taches, poles de quetes ; et debuts de
    -- quete parmi les points du journal. Garde aussi dans la sauvegarde
    -- (CorpUIDB.leveling.diag), lisible sur le disque apres un /reload.
    local function count(fn, ...)
        if type(fn) ~= "function" then return "absente" end
        local ok, t = pcall(fn, ...)
        if not ok then return "erreur" end
        return type(t) == "table" and tostring(#t) or tostring(t)
    end
    local lines = { main }
    for _, map in ipairs(me and LV.MapsAround(me.map) or {}) do
        local info = C_Map and call(C_Map.GetMapInfo, map)
        local starts = 0
        local pois = C_QuestLog and call(C_QuestLog.GetQuestsOnMap, map)
        for _, p in ipairs(type(pois) == "table" and pois or {}) do
            if type(p) == "table" and not issecret(p.isQuestStart) and p.isQuestStart == true then starts = starts + 1 end
        end
        local QL, TQ, AP = C_QuestLine or {}, C_TaskQuest or {}, C_AreaPoiInfo or {}
        lines[#lines + 1] = string.format("  carte %d (%s, type %s) : lignes %s, forcees %s, taches %s, poles %s, debuts %d, poi %s",
            map, tostring(type(info) == "table" and info.name), tostring(type(info) == "table" and info.mapType),
            count(QL.GetAvailableQuestLines, map), count(QL.GetForceVisibleQuests, map),
            count(TQ.GetQuestsOnMap or TQ.GetQuestsForPlayerByMapID, map), count(AP.GetQuestHubsForMap, map), starts,
            count(AP.GetAreaPOIForMap, map))
    end
    lines[#lines + 1] = string.format("  suivi des quetes cachees (minicarte) : %s",
        tostring(C_Minimap and call(C_Minimap.IsTrackingHiddenQuests)))
    for i = 2, #lines do ns.Say(lines[i]) end
    if db then db.diag = lines end
end

local function resetIgnored()
    local t = mine("ignored")
    local n = 0
    for k in pairs(t) do
        t[k] = nil
        n = n + 1
    end
    pinned = nil
    ns.Say(string.format(L.LVL_RESET, n))
    refresh()
end

---------------------------------------------------------------------------
-- Reglages
---------------------------------------------------------------------------

local win

local function moduleLoaded(key)
    for _, m in ipairs(ns.modules) do
        if m.command == key then return ns.ModuleOn(key) end
    end
    return false
end

local function buildWindow()
    win = ns.UI.Window("CorpUILevelingOptions", ns.TITLE .. " - " .. L.MOD_LEVELING, nil, 440, 300)
    local form = ns.UI.Form(win, -34)
    form:Header(L.LVL_H_WINDOW)
    form:Check(L.LVL_OPT_SHOW, function() return db.enabled end, function(v) db.enabled = v refresh() end)
    form:Number(L.LVL_OPT_ROWS, function() return db.rows end, function(v) db.rows = v draw() end, 1, MAX_ROWS)
    form:Header(L.LVL_H_ARROW)
    form:Check(L.LVL_OPT_ARROW, function() return db.arrow end, function(v) db.arrow = v refresh() end)
    form:Check(L.LVL_OPT_NATIVE, function() return db.native end, function(v)
        db.native = v
        if not v then LV.SetNative(nil, false) end
        refresh()
    end)
    form:Number(L.LVL_OPT_ARROW_SIZE, function() return db.arrowScale end, function(v)
        db.arrowScale = v
        LV.ArrowScale()
    end, 50, 200, 10)
    form:Header(L.LVL_H_STEPS)
    form:Check(L.LVL_OPT_OFFERS, function() return db.offers end, function(v) db.offers = v refresh() end)
    form:Check(L.LVL_OPT_GRAY, function() return db.gray end, function(v) db.gray = v refresh() end)
    -- quetes acceptees / rendues seules : reglage du module Experience
    -- (CorpUIDB.xp.autoQuest), lu par lui a chaque dialogue de PNJ
    if moduleLoaded("xp") then
        form:Check(L.XP_OPT_AUTOQUEST, function()
            local xp = ns.InitRoot().xp
            return xp and xp.autoQuest
        end, function(v)
            local xp = ns.InitRoot().xp
            if xp then xp.autoQuest = v end
        end)
    end
    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", win, "TOPLEFT", 8, form.y - 6)
    hint:SetWidth(420)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.LVL_HINT)
    win:SetHeight(-form.y + 80)
    win:HookScript("OnShow", function() form:Refresh() end)
end

local function toggle()
    if not win then buildWindow() end
    ns.ShowPanel(win)
end

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, arg)
    if ns.ModuleOff("leveling", ev) then return end
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        root.leveling = root.leveling or {}
        db = root.leveling
        if db.enabled == nil then db.enabled = true end
        if db.arrow == nil then db.arrow = true end
        -- repere de Blizzard : a essayer (ses gestionnaires d evenements tournent
        -- alors depuis notre appel), coupe par defaut
        if db.native == nil then db.native = false end
        if db.offers == nil then db.offers = true end
        if db.gray == nil then db.gray = false end
        db.rows = db.rows or 5
        db.arrowScale = db.arrowScale or 100
        db.ignored = db.ignored or {}
        build()
        -- deverrouillage : fenetre et fleche en apercu
        ns.Listen(function() if db then draw() LV.SetArrow(list[1], db) end end)
        dirty = true
        return
    end
    if not db then return end
    if event == "QUEST_TURNED_IN" or event == "QUEST_REMOVED" then
        -- quete rendue (ou abandonnee) : ses etapes ignorees n ont plus lieu d etre
        local id = num(arg)
        if id then
            local t = mine("ignored")
            t["objective:" .. id], t["turnin:" .. id] = nil, nil
            if event == "QUEST_TURNED_IN" then t["accept:" .. id] = nil end
        end
    end
    dirty = true
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED",
                     "QUEST_TURNED_IN", "QUEST_POI_UPDATE", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
                     "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE" }) do
    pcall(ev.RegisterEvent, ev, e)
end

-- calcul : tout de suite apres un evenement (au plus 4 fois par seconde),
-- sinon une fois par seconde (les distances changent en marchant)
ns.Every(0.25, function()
    if not db then return end
    if not dirty and GetTime() - lastRun < 1 then return end
    local ok, err = pcall(refresh)
    if not ok then geterrorhandler()(err) end
end, "Leveling", "leveling")

ns.RegisterModule({
    command = "leveling",
    alias = "lvl",
    panelName = "CorpUILevelingOptions",
    icon = "Interface\\Icons\\INV_Misc_Map_01",
    title = function() return L.MOD_LEVELING end,
    desc = function() return L.LVL_DESC end,
    Slash = function(input)
        local cmd = strlower(strtrim(input or ""))
        if cmd == "diag" then LV.Diag() return end
        if cmd == "reset" then resetIgnored() return end
        toggle()
    end,
    Open = toggle,
})
