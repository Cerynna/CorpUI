--[[--------------------------------------------------------------------------
    CorpUI - module Leveling : la fenetre, les reglages, les evenements

    Guide pas a pas (16/10) : les etapes de la route (Route.lua),
    numerotees, l etape en cours en tete, les dernieres faites cochees en
    gris au-dessus, puis les suivantes (nombre au choix). Meme dessin que le suivi des quetes (module Quetes,
    demande du 16/10) : pas de fond, titre clair, filet fin, puis par
    etape le titre de la quete dans la couleur de sa difficulte, la
    distance a droite (a la place du niveau), et une ligne en retrait :
    quete a prendre (or), prete a rendre (vert), objectif (gris) ou texte
    du repere (bleu). Survol : voile violet, comme le suivi.
      clic gauche : pointer la fleche sur cette etape (encore : revenir a
                    l etape en cours) ;
      clic droit  : ignorer la quete (par personnage ; /corp leveling reset).
    Le bouton de l en-tete replie la liste sur l etape en cours.
    Cachee au niveau maximum. Deplacable avec "Deverrouiller l interface".

    Calcul (Moteur.lua) une fois par seconde, et tout de suite apres un
    evenement du journal ou un changement de zone ; la fleche (Fleche.lua)
    tourne a part, seulement quand elle est affichee.

    /corp leveling       : reglages
    /corp leveling diag  : ce que le jeu donne (carte, quetes placees...)
    /corp leveling reset : faire revenir les quetes ignorees
    /corp leveling route : recalculer la route
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local LV = ns.Leveling
local num, str, call = LV.num, LV.str, LV.call
local issecret = issecretvalue or function() return false end

local WIDTH = 230          -- largeur du suivi des quetes
local HEAD_H = 22
local MAX_ROWS = 8
local HIST_SHOWN = 2       -- etapes faites montrees au-dessus de l etape en cours
local CHECK = "Interface\\RaidFrame\\ReadyCheck-Ready"

local KINDS = {
    accept = { color = { 1, 0.82, 0 }, label = "LVL_K_ACCEPT", sub = "LVL_SUB_ACCEPT" },
    turnin = { color = { 0.3, 0.9, 0.3 }, label = "LVL_K_TURNIN", sub = "LVL_SUB_TURNIN" },
    objective = { color = { 0.85, 0.85, 0.85 }, label = "LVL_K_OBJECTIVE", sub = "LVL_SUB_OBJECTIVE" },
}

local db, frame, header, body, rows
local list = {}           -- etapes restantes de la route, dans l ordre
local hist = {}           -- dernieres etapes faites
local forceRoute = false  -- recalculer toute la route au prochain calcul
local lastFull = 0
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

local function titleOf(a)
    return a.title or LV.Title(a.id) or string.format(L.LVL_QUEST_ID, a.id)
end

-- etapes consecutives du meme type au meme endroit : une seule ligne
-- ("Faire 2 quetes ici" et leurs objectifs, "Prendre 3 quetes"...)
local GROUP_TITLE = { accept = "LVL_GROUP_ACCEPT", objective = "LVL_GROUP_OBJECTIVE", turnin = "LVL_GROUP_TURNIN" }
local function groupSteps(steps, n)
    local out, i = {}, 1
    while i <= #steps and #out < n do
        local a = steps[i]
        local g, j = { a }, i + 1
        while j <= #steps do
            local b = steps[j]
            if b.kind ~= a.kind or not (a.cont and b.cont) or LV.Route.Dist(a, b) > LV.Route.GROUP_R[a.kind] then break end
            g[#g + 1] = b
            j = j + 1
        end
        if #g == 1 then
            out[#out + 1] = a
        else
            local e = { group = g, kind = a.kind, id = a.id, key = a.key, num = a.num, dist = a.dist, map = a.map,
                        level = a.level, via = a.via, viaText = a.viaText }
            for _, t in ipairs(g) do
                if t.pinned then e.pinned = true end
            end
            out[#out + 1] = e
        end
        i = j
    end
    return out
end

local function hexOf(r, g, b)
    return string.format("%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- lignes d objectifs d une quete (faits en vert), retrait facultatif
local function objectiveLines(t, lines, indent)
    if t.objectives and #t.objectives > 0 then
        for _, o in ipairs(t.objectives) do
            lines[#lines + 1] = indent .. (o.finished and "|cff59d959- " or "- ") .. o.text .. (o.finished and "|r" or "")
        end
    elseif t.text then
        lines[#lines + 1] = indent .. "- " .. t.text
    else
        lines[#lines + 1] = indent .. "- " .. L.LVL_SUB_OBJECTIVE
    end
end

local function stepName(a)
    return string.format("%s %s", L[KINDS[a.kind].label], titleOf(a))
end

---------------------------------------------------------------------------
-- Fenetre
---------------------------------------------------------------------------

local function tooltip(self)
    local a = self.step
    if not a then return end
    if a.group then
        local t = ns.Tooltip(self, "ANCHOR_LEFT")
        t:AddLine(string.format(L[GROUP_TITLE[a.kind]], #a.group))
        for _, s in ipairs(a.group) do
            t:AddLine(titleOf(s), levelColor(s.level))
            if a.kind == "objective" then
                local lines = {}
                objectiveLines(s, lines, "   ")
                for _, l in ipairs(lines) do t:AddLine(l, 0.85, 0.85, 0.85) end
            end
        end
        t:AddLine(" ")
        t:AddLine(L.LVL_TIP_LEFT, 0.7, 0.7, 0.7)
        t:AddLine(string.format(L.LVL_TIP_RIGHT_GROUP, titleOf(a.group[1])), 0.7, 0.7, 0.7)
        t:Show()
        return
    end
    local t = ns.Tooltip(self, "ANCHOR_LEFT")
    t:AddLine(titleOf(a), levelColor(a.level))
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
    if a.minLevel then t:AddLine(string.format(L.LVL_MINLVL, a.minLevel), 0.8, 0.8, 0.8) end
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
    if not a or a.done then return end
    if a.group then a = a.group[1] end
    if button == "RightButton" then
        mine("ignored")["q:" .. a.id] = true
        if pinned and pinned:match(":(%d+)$") == tostring(a.id) then pinned = nil end
        ns.Say(string.format(L.LVL_IGNORED, titleOf(a)))
        dirty = true
    else
        pinned = (pinned ~= a.key) and a.key or nil
    end
    ns.HideTooltip()
    refresh()
end

local function row(i)
    if rows[i] then return rows[i] end
    local C = ns.COLORS
    local r = CreateFrame("Button", nil, body)
    r:SetWidth(WIDTH)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- etape en cours : voile leger ; survol : celui du suivi des quetes
    r.mark = r:CreateTexture(nil, "BACKGROUND")
    r.mark:SetPoint("TOPLEFT", 1, 1)
    r.mark:SetPoint("BOTTOMRIGHT", -1, -1)
    ns.UI.Gradient(r.mark, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.18, C.violet[1], C.violet[2], C.violet[3], 0)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 1, 1)
    hl:SetPoint("BOTTOMRIGHT", -1, -1)
    ns.UI.Gradient(hl, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.32, C.violet[1], C.violet[2], C.violet[3], 0.04)
    r.dist = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.dist:SetPoint("TOPRIGHT", 0, -1)
    r.dist:SetJustifyH("RIGHT")
    r.num = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.num:SetPoint("TOPLEFT", 2, -2)
    r.num:SetWidth(20)
    r.num:SetJustifyH("RIGHT")
    r.check = r:CreateTexture(nil, "ARTWORK")
    r.check:SetSize(12, 12)
    r.check:SetPoint("TOPRIGHT", r.num, "TOPRIGHT", 0, 1)
    r.check:SetTexture(CHECK)
    r.check:Hide()
    r.title = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.title:SetJustifyH("LEFT")
    r.title:SetWordWrap(true)
    r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.sub:SetJustifyH("LEFT")
    r.sub:SetWordWrap(true)
    r:SetScript("OnClick", onRowClick)
    r:SetScript("OnEnter", tooltip)
    r:SetScript("OnLeave", ns.HideTooltip)
    rows[i] = r
    return r
end

-- une etape : titre (et distance), ligne en retrait ; renvoie sa hauteur
local function fill(r, a, first, y)
    r.step = a
    r.mark:SetShown(first)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
    local done = a.done == true
    r:SetAlpha(done and 0.55 or 1)
    r.num:SetText(done and "" or (a.num and tostring(a.num) or ""))
    r.check:SetShown(done)
    r.dist:SetText((not done and a.dist) and string.format(L.LVL_DIST, math.floor(a.dist + 0.5))
        or ((not done and a.map) and L.LVL_ELSEWHERE or ""))
    r.title:ClearAllPoints()
    r.title:SetPoint("TOPLEFT", 26, 0)
    r.title:SetPoint("TOPRIGHT", -((r.dist:GetStringWidth() or 0) + 6), 0)
    if a.group then
        r.title:SetText(string.format(L[GROUP_TITLE[a.kind]], #a.group))
        local kc = KINDS[a.kind].color
        if a.kind == "objective" then r.title:SetTextColor(0.93, 0.93, 0.93) else r.title:SetTextColor(kc[1], kc[2], kc[3]) end
    else
        r.title:SetText(titleOf(a))
        if done then r.title:SetTextColor(0.6, 0.6, 0.6) else r.title:SetTextColor(levelColor(a.level)) end
    end
    local k = KINDS[a.kind]
    local sub, c = L[k.sub], k.color
    if a.via and a.viaText then
        sub, c = "- " .. a.viaText, { 0.6, 0.8, 1 }
    elseif a.group then
        -- chaque quete du groupe (couleur de sa difficulte), ses objectifs dessous
        local lines = {}
        for _, s in ipairs(a.group) do
            local cr, cg, cb = levelColor(s.level)
            if a.kind == "objective" then
                lines[#lines + 1] = "|cff" .. hexOf(cr, cg, cb) .. titleOf(s) .. "|r"
                objectiveLines(s, lines, "   ")
            else
                lines[#lines + 1] = "|cff" .. hexOf(cr, cg, cb) .. "- " .. titleOf(s) .. "|r"
            end
        end
        sub, c = table.concat(lines, "\n"), { 0.85, 0.85, 0.85 }
    elseif a.kind == "objective" and a.objectives and #a.objectives > 0 and not done then
        -- tous les objectifs, comme le suivi des quetes : faits en vert
        local lines = {}
        for _, o in ipairs(a.objectives) do
            lines[#lines + 1] = (o.finished and "|cff59d959- " or "- ") .. o.text .. (o.finished and "|r" or "")
        end
        sub = table.concat(lines, "\n")
    elseif a.kind == "objective" and a.text then
        sub = "- " .. a.text
    elseif a.kind == "turnin" and not a.ready and not done then
        sub, c = L.LVL_SUB_TURNIN_LATER, { 0.55, 0.75, 0.55 }
    end
    if done then c = { 0.6, 0.6, 0.6 } end
    if a.pinned then sub = (sub and (sub .. " · ") or "") .. L.LVL_PINNED end
    r.sub:ClearAllPoints()
    r.sub:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 10, -2)
    r.sub:SetPoint("RIGHT", r, "RIGHT", -2, 0)
    r.sub:SetText(sub or "")
    r.sub:SetTextColor(c[1], c[2], c[3])
    r.sub:SetShown(sub ~= nil)
    local h = math.max(12, r.title:GetStringHeight() or 0)
    if sub then h = h + 2 + math.max(10, r.sub:GetStringHeight() or 0) end
    r:SetHeight(h + 2)
    r:Show()
    return h + 2
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
    header.toggle.label:SetText(db.collapsed and "+" or "−")
    local n = db.collapsed and 1 or math.max(1, math.min(MAX_ROWS, db.rows or 5))
    local shownList = {}
    if not db.collapsed then
        for i = math.max(1, #hist - HIST_SHOWN + 1), #hist do
            local h = hist[i]
            shownList[#shownList + 1] = { key = h.key, kind = h.kind, id = h.id, title = h.title,
                                          level = h.level, num = h.num, done = true }
        end
    end
    local firstLive = #shownList + 1
    for _, e in ipairs(groupSteps(list, n)) do shownList[#shownList + 1] = e end
    local y, count = 4, 0
    for i = 1, MAX_ROWS + HIST_SHOWN do
        local a = shownList[i]
        if a then
            y = y + fill(row(i), a, i == firstLive, y) + 4
            count = i
        elseif rows[i] then
            rows[i]:Hide()
            rows[i].step = nil
        end
    end
    frame.empty:SetShown(#list == 0)
    if #list == 0 and count > 0 then y = y + 14 end
    frame.empty:ClearAllPoints()
    frame.empty:SetPoint("TOPLEFT", body, "TOPLEFT", 4, -(y - (#list == 0 and count > 0 and 14 or 0)))
    frame.empty:SetPoint("RIGHT", body, "RIGHT", -4, 0)
    if count == 0 then y = 4 + 14 + 4 end
    body:SetHeight(y)
    frame:SetHeight(HEAD_H + 2 + y)
    frame:Show()
end

local function build()
    db.pos = db.pos or { point = "TOPLEFT", x = 20, y = -300 }
    frame = CreateFrame("Frame", "CorpUILeveling", UIParent)
    frame:SetSize(WIDTH, HEAD_H + 30)
    frame:SetFrameStrata("LOW")
    ns.ApplyPos(frame, db.pos)
    rows = {}

    -- en-tete du suivi des quetes : titre, niveau et XP, bouton replier,
    -- filet fin dessous ; pas de fond, la liste est posee sur le jeu
    header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEAD_H)
    local rule = header:CreateTexture(nil, "BORDER")
    rule:SetPoint("BOTTOMLEFT", 0, 1)
    rule:SetPoint("BOTTOMRIGHT", 0, 1)
    rule:SetHeight(1)
    ns.NoSnap(rule)
    rule:SetColorTexture(1, 1, 1, 0.22)
    header.title = header:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(header.title, 12)
    header.title:SetPoint("LEFT", 2, 0)
    header.title:SetTextColor(0.93, 0.93, 0.93)
    header.title:SetText(L.MOD_LEVELING)
    header.level = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    header.level:SetPoint("LEFT", header.title, "RIGHT", 6, 0)
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

    body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    body:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -2)
    body:SetHeight(1)
    ns.NoSnap(body)

    frame.empty = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.empty:SetPoint("TOPLEFT", 4, -4)
    frame.empty:SetPoint("RIGHT", -4, 0)
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

-- full : relire le journal et mettre la route a jour (evenement, toutes
-- les 5 s) ; sinon seulement les distances (chaque seconde)
refresh = function(full)
    if not db then return end
    lastRun = GetTime()
    if not active() or maxLevel() then
        list, hist = {}, {}
        draw()
        LV.SetArrow(nil, db)
        LV.SetNative(nil, false)
        return
    end
    local me = LV.Player()
    if full or dirty or forceRoute or lastRun - lastFull >= 5 then
        dirty, lastFull = false, lastRun
        LV.Route.Update(me, { offers = db.offers, gray = db.gray, ignored = mine("ignored") }, forceRoute)
        forceRoute = false
    end
    list, hist = LV.Route.Steps()
    for i = 1, math.min(#list, MAX_ROWS * 4) do list[i].dist = LV.Distance(me, list[i]) end
    -- etape choisie a la main : la fleche y va, elle passe en tete de la liste
    local target = list[1]
    for _, a in ipairs(list) do a.pinned = nil end
    if pinned then
        local found
        for _, a in ipairs(list) do
            if a.key == pinned then found = a break end
        end
        if found then
            found.pinned = true
            found.dist = LV.Distance(me, found)
            target = found
        else
            pinned = nil        -- etape faite (ou disparue) : retour a l etape en cours
        end
    end
    current = target and target.key or nil
    draw()
    LV.SetArrow(target, db)
    LV.SetNative(target, db.native)
end

-- recalculer toute la route (commande, bouton des reglages)
local function rebuildRoute()
    forceRoute, pinned = true, nil
    refresh(true)
    ns.Say(string.format(L.LVL_ROUTE_REBUILT, #list))
end
LV.Refresh = function() if db then refresh(true) end end

-- banc d essai : etat de la fenetre
function LV._state() return { list = list, hist = hist, current = current, pinned = pinned, frame = frame, rows = rows } end

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
    -- base d AllTheThings (Donnees.lua) : quetes de ces cartes, et celles a prendre maintenant
    local inLog = {}
    for _, q in ipairs(LV.LogQuests()) do inLog[q.id] = true end
    local who = LV.WhoAmI()
    for _, map in ipairs(me and LV.MapsAround(me.map) or {}) do
        local all, ok = LV.Offers(map), 0
        for _, q in ipairs(all) do
            if LV.CanTake(q, who, inLog) then ok = ok + 1 end
        end
        lines[#lines + 1] = string.format("  base, carte %d : %d quetes, %d a prendre (niveau %s, camp %s, race %s, classe %s)",
            map, #all, ok, tostring(who.level), tostring(who.side), tostring(who.race), tostring(who.class))
    end
    local st = LV.Route.State()
    lines[#lines + 1] = string.format("  route : zone %s, %d etapes restantes, %d faites",
        tostring(st and st.zone), st and #st.tasks or 0, st and st.done or 0)
    -- premieres etapes, et la distance jusqu a la suivante (regroupements)
    for i = 1, math.min(8, st and #st.tasks or 0) do
        local t, nx = st.tasks[i], st.tasks[i + 1]
        lines[#lines + 1] = string.format("    %d. %s (%s) %s -> suivante %s m", i, t.key, titleOf(t),
            t.map and string.format("%d %.1f,%.1f", t.map, t.x * 100, t.y * 100) or "?",
            nx and string.format("%.0f", LV.Route.Dist(t, nx)) or "-")
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
    dirty = true
    refresh(true)
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
    local again = ns.UI.Button(win, L.LVL_REBUILD, 200, function() rebuildRoute() end)
    again:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
    win:SetHeight(-form.y + 120)
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
        db.route = db.route or {}
        LV.Route.Attach(mine("route"))
        build()
        -- deverrouillage : fenetre et fleche en apercu
        ns.Listen(function() if db then draw() LV.SetArrow(list[1], db) end end)
        dirty = true
        return
    end
    if not db then return end
    if event == "QUEST_TURNED_IN" then LV.ForgetCompleted() end
    if event == "QUEST_TURNED_IN" or event == "QUEST_REMOVED" then
        -- quete rendue (ou abandonnee) : ses etapes ignorees n ont plus lieu d etre
        local id = num(arg)
        if id then
            if event == "QUEST_TURNED_IN" then mine("ignored")["q:" .. id] = nil end
        end
    end
    dirty = true
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED",
                     "QUEST_TURNED_IN", "QUEST_POI_UPDATE", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
                     "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE", "QUEST_DATA_LOAD_RESULT" }) do
    pcall(ev.RegisterEvent, ev, e)
end

-- calcul : tout de suite apres un evenement (au plus 4 fois par seconde),
-- sinon une fois par seconde (les distances changent en marchant)
ns.Every(0.25, function()
    if not db then return end
    if not dirty and GetTime() - lastRun < 1 then return end
    local ok, err = pcall(refresh, dirty)
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
        if cmd == "route" then rebuildRoute() return end
        toggle()
    end,
    Open = toggle,
})
