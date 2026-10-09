--[[--------------------------------------------------------------------------
    CorpUI - module Experience
    Reprise de ForeverXP Bar dans CorpUI :
      - habit CorpUI : cadre obsidienne, liseré, ombre, medaillon du niveau,
        graduations tous les 10 %, etincelle au bout du remplissage ;
      - degrade aux couleurs du theme (ou de classe, ou 8 palettes), segment
        ambre de l XP des quetes terminees, XP reposee en voile du degrade ;
      - sur la barre : niveau / XP / max (reste) / % (et % avec quetes) ;
      - au-dessus : temps a ce niveau / temps de session ;
      - en dessous : XP/heure, temps estime jusqu au niveau suivant,
        quetes terminees % et repos % ;
      - option : acceptation et rendu automatiques des quetes (Maj = pause) ;
      - cache la barre d XP de Blizzard.
    Le temps a ce niveau est compte ici (par personnage) et recale par
    /played a la connexion.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local BAR_FONT = "Fonts\\FRIZQT__.TTF"
local BOLD_FONT = ns.MEDIA .. "xpbold.ttf"
local BLIZZ_XP = { "StatusTrackingBarManager", "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }

local PRESET_ORDER = { "theme", "aurora", "fire", "ocean", "emerald", "royal", "crimson", "gold", "ice" }
local PRESETS = {
    aurora  = { { 0.14, 0.86, 0.80 }, { 0.52, 0.42, 0.98 } },
    fire    = { { 1.00, 0.55, 0.10 }, { 0.85, 0.10, 0.10 } },
    ocean   = { { 0.10, 0.55, 0.95 }, { 0.05, 0.20, 0.55 } },
    emerald = { { 0.20, 0.90, 0.45 }, { 0.05, 0.45, 0.30 } },
    royal   = { { 0.55, 0.35, 0.95 }, { 0.20, 0.10, 0.55 } },
    crimson = { { 0.95, 0.20, 0.35 }, { 0.45, 0.05, 0.15 } },
    gold    = { { 1.00, 0.84, 0.30 }, { 0.70, 0.45, 0.05 } },
    ice     = { { 0.80, 0.95, 1.00 }, { 0.35, 0.60, 0.85 } },
}
local QUEST_COLOR = { 1.00, 0.74, 0.28 }
local RESTED_ALPHA = 0.32
local C = ns.COLORS

-- "theme" : l accent de CorpUI, du sombre a l eclairci
local function presetColors(key)
    if key == "theme" or not PRESETS[key] then
        local a = C.violet
        -- assez sombre pour que le texte blanc reste lisible (theme sombre compris)
        return { a[1] * 0.30, a[2] * 0.30, a[3] * 0.30 }, { a[1] * 0.85, a[2] * 0.85, a[3] * 0.85 }
    end
    return PRESETS[key][1], PRESETS[key][2]
end

local function hex(c) return string.format("%02x%02x%02x", math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255)) end
local function white(t) return "|cffffffff" .. t .. "|r" end

local DEFAULTS = {
    enabled = true, hideBlizzard = true,
    width = 660, height = 20,
    quest = true, rested = true,
    tLevel = true, tXP = true, tPct = true, tLevelTime = true, tSession = true,
    tRate = true, tETA = true, tBottom = true,
    maxLevel = false, border = false, bold = false, classColor = false,
    preset = "theme", textSize = 10, autoQuest = false,
}

local db, track
local frame, bar, fill, quest, rested, divQuest, divRested, spark, badge
local ticks = {}
local texts = {}

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end

---------------------------------------------------------------------------
-- Mise en forme
---------------------------------------------------------------------------

local function fmtAmount(v)
    if v >= 1000000 then return string.format("%.2fm", v / 1000000) end
    if v >= 1000 then return string.format("%.1fk", v / 1000) end
    return tostring(math.floor(v + 0.5))
end

local function fmtETA(seconds)
    if not seconds or seconds ~= seconds or seconds == math.huge then return nil end
    if seconds < 60 then return "<1m" end
    local totalMin = math.floor(seconds / 60 + 0.5)
    local d = math.floor(totalMin / 1440)
    if d > 99 then return ">99d" end
    local h = math.floor((totalMin % 1440) / 60)
    local m = totalMin % 60
    if d > 0 then return string.format("%dd %dh", d, h) end
    if h > 0 then return string.format("%dh %02dm", h, m) end
    return string.format("%dm", m)
end

---------------------------------------------------------------------------
-- XP des quetes terminees
---------------------------------------------------------------------------

local function pendingQuestXP()
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo and GetQuestLogRewardXP) then
        return 0
    end
    local ok, total = pcall(function()
        local sum = 0
        for i = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID then
                local done
                if C_QuestLog.IsComplete then
                    local c = C_QuestLog.IsComplete(info.questID)
                    done = c and c ~= 0
                else
                    done = info.isComplete and info.isComplete ~= 0
                end
                if done then
                    local xp = GetQuestLogRewardXP(info.questID)
                    if type(xp) == "number" then sum = sum + xp end
                end
            end
        end
        return sum
    end)
    return (ok and type(total) == "number") and total or 0
end

---------------------------------------------------------------------------
-- XP/heure : temps passe a ce niveau, par personnage
---------------------------------------------------------------------------

local lastTick, playedAsked

local function ensureTrack()
    local level = safe(UnitLevel, "player") or 0
    if level <= 0 then return nil end
    local key = ns.CharKey()
    local rec = db.chars[key]
    if not rec or rec.level ~= level then
        rec = { level = level, secs = 0, baseXP = safe(UnitXP, "player") or 0, rate = rec and rec.rate }
        db.chars[key] = rec
    end
    track = rec
    return rec
end

local function tick()
    local now = GetTime()
    local dt = lastTick and (now - lastTick) or 0
    lastTick = now
    local rec = ensureTrack()
    if rec and dt > 0 and dt < 300 then rec.secs = rec.secs + dt end
    db.lastSeen = time()
end

local function xpPerHour(xp)
    local rec = track
    if not rec then return nil end
    local gained = xp - (rec.baseXP or 0)
    if rec.secs >= 60 and gained > 0 then rec.rate = gained / rec.secs * 3600 end
    return rec.rate
end

local function sessionSeconds()
    local now = time()
    return now - (db.sessionStart or now)
end

---------------------------------------------------------------------------
-- Couleurs
---------------------------------------------------------------------------

local function gradientColors()
    if db.classColor then
        local _, class = UnitClass("player")
        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then
            local function lighten(v) return v + (1 - v) * 0.45 end
            return { lighten(c.r), lighten(c.g), lighten(c.b) }, { c.r, c.g, c.b }
        end
    end
    return presetColors(db.preset)
end

local function paintGradient(tex, alpha)
    local a, b = gradientColors()
    local ok = pcall(function()
        tex:SetTexture(ns.BAR_TEXTURE)
        tex:SetGradient("HORIZONTAL", CreateColor(a[1], a[2], a[3], alpha), CreateColor(b[1], b[2], b[3], alpha))
    end)
    if not ok then tex:SetColorTexture(a[1], a[2], a[3], alpha) end
end

local function paint()
    paintGradient(fill, 1)
    paintGradient(rested, RESTED_ALPHA)
    quest:SetTexture(ns.BAR_TEXTURE)
    quest:SetVertexColor(QUEST_COLOR[1], QUEST_COLOR[2], QUEST_COLOR[3], 1)
    local _, b = gradientColors()
    spark:SetColorTexture(b[1], b[2], b[3], 1)
    -- liseré : celui du theme, ou l accent (option)
    local edge = db.border and C.violet or C.border
    frame.cuiBorder:SetColorTexture(edge[1], edge[2], edge[3], 1)
    badge.cuiBorder:SetColorTexture(edge[1], edge[2], edge[3], 1)
    local a = C.violet
    ns.UI.Gradient(badge.fill, "VERTICAL", a[1] * 0.25, a[2] * 0.25, a[3] * 0.25, 1, a[1] * 0.6, a[2] * 0.6, a[3] * 0.6, 1)
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

-- cle, point du texte, point de la barre, x, y, taille en plus
local SLOTS = {
    { "onLeft",     "LEFT",        "LEFT",        7,   0,  0 },
    { "onCenter",   "CENTER",      "CENTER",      0,   0,  4 },
    { "onRight",    "RIGHT",       "RIGHT",       -7,  0,  0 },
    { "topLeft",    "BOTTOMLEFT",  "TOPLEFT",     1,   5,  0 },
    { "topRight",   "BOTTOMRIGHT", "TOPRIGHT",    -1,  5,  0 },
    { "underLeft",  "TOPLEFT",     "BOTTOMLEFT",  1,   -6, 0 },
    { "underNext",  "LEFT",        "RIGHT",       12,  0,  0 },
    { "underRight", "TOPRIGHT",    "BOTTOMRIGHT", -1,  -6, 0 },
}

local function applyFonts()
    -- police choisie dans CorpUI (onglet General), sinon celle du jeu
    local base = (ns.FontFile and ns.FontFile("regular")) or BAR_FONT
    local font = db.bold and BOLD_FONT or base
    for _, s in ipairs(SLOTS) do
        local fs = texts[s[1]]
        local size = clamp(db.textSize + s[6], 6, 30)
        -- police grasse absente ou refusee : on garde la police du jeu
        if not pcall(fs.SetFont, fs, font, size, "OUTLINE") or not fs:GetFont() then
            fs:SetFont(BAR_FONT, size, "OUTLINE")
        end
        -- textes autour de la barre : libelles en gris du theme, valeurs en blanc
        if s[1]:find("^top") or s[1]:find("^under") then
            fs:SetTextColor(C.text[1], C.text[2], C.text[3])
        end
    end
    ns.UI.HeadFont(badge.text, math.max(11, math.floor(db.height * 0.6)))
end

local function build()
    db.pos = db.pos or { point = "TOP", x = 0, y = -150 }
    frame = CreateFrame("Frame", "CorpUIXPBar", UIParent)
    frame:SetFrameStrata("LOW")
    ns.ApplyPos(frame, db.pos)

    -- habit CorpUI : fond obsidienne, liseré de 1 px, ombre
    ns.UI.Skin(frame, 0.92, true)
    bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("BOTTOMRIGHT", -1, 1)

    fill = bar:CreateTexture(nil, "ARTWORK", nil, 1)
    fill:SetPoint("TOPLEFT")
    fill:SetPoint("BOTTOMLEFT")
    quest = bar:CreateTexture(nil, "ARTWORK", nil, 2)
    quest:SetPoint("TOPLEFT", fill, "TOPRIGHT")
    quest:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT")
    rested = bar:CreateTexture(nil, "ARTWORK", nil, 3)
    rested:SetPoint("TOPLEFT", quest, "TOPRIGHT")
    rested:SetPoint("BOTTOMLEFT", quest, "BOTTOMRIGHT")

    local function divider(after)
        local d = bar:CreateTexture(nil, "ARTWORK", nil, 4)
        d:SetPoint("TOPLEFT", after, "TOPRIGHT", -1, 0)
        d:SetPoint("BOTTOMLEFT", after, "BOTTOMRIGHT", -1, 0)
        d:SetWidth(1)
        ns.NoSnap(d)
        d:SetColorTexture(0.02, 0.03, 0.06, 0.55)
        return d
    end
    divQuest, divRested = divider(fill), divider(quest)

    -- reflet en haut, ombre en bas
    local sheen = bar:CreateTexture(nil, "ARTWORK", nil, 5)
    sheen:SetPoint("TOPLEFT")
    sheen:SetPoint("TOPRIGHT")
    sheen:SetHeight(1)
    ns.NoSnap(sheen)
    sheen:SetColorTexture(1, 1, 1, 0.10)
    local shadow = bar:CreateTexture(nil, "ARTWORK", nil, 5)
    shadow:SetPoint("BOTTOMLEFT")
    shadow:SetPoint("BOTTOMRIGHT")
    shadow:SetHeight(3)
    ns.UI.Gradient(shadow, "VERTICAL", 0, 0, 0, 0.35, 0, 0, 0, 0)

    -- graduations tous les 10 % (placees par relayout)
    for i = 1, 9 do
        local t = bar:CreateTexture(nil, "ARTWORK", nil, 6)
        t:SetWidth(1)
        ns.NoSnap(t)
        t:SetColorTexture(0, 0, 0, 0.35)
        ticks[i] = t
    end
    -- etincelle au bout du remplissage
    spark = bar:CreateTexture(nil, "ARTWORK", nil, 7)
    spark:SetWidth(2)
    spark:SetPoint("TOPLEFT", fill, "TOPRIGHT", -1, 0)
    spark:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", -1, 0)

    -- medaillon du niveau, a gauche de la barre
    badge = CreateFrame("Frame", nil, frame)
    badge:SetPoint("RIGHT", frame, "LEFT", -4, 0)
    ns.UI.Skin(badge, 0.95, true)
    badge.fill = badge:CreateTexture(nil, "BACKGROUND", nil, -5)
    badge.fill:SetPoint("TOPLEFT")
    badge.fill:SetPoint("BOTTOMRIGHT")
    badge.text = badge:CreateFontString(nil, "OVERLAY")
    badge.text:SetPoint("CENTER", 0, 0)
    badge.text:SetShadowColor(0, 0, 0, 1)
    badge.text:SetShadowOffset(1, -1)

    local textLayer = CreateFrame("Frame", nil, frame)
    textLayer:SetAllPoints()
    textLayer:SetFrameLevel(bar:GetFrameLevel() + 3)
    for _, s in ipairs(SLOTS) do
        local fs = textLayer:CreateFontString(nil, "OVERLAY")
        fs:SetFont(BAR_FONT, 11, "OUTLINE")
        fs:SetShadowColor(0, 0, 0, 0.8)
        fs:SetShadowOffset(1, -1)
        texts[s[1]] = fs
    end
    for _, s in ipairs(SLOTS) do
        local anchor = s[1] == "underNext" and texts.underLeft or frame
        texts[s[1]]:SetPoint(s[2], anchor, s[3], s[4], s[5])
    end

    ns.UI.Mover(frame, db.pos, L.MOD_XP)
end

---------------------------------------------------------------------------
-- Mise a jour
---------------------------------------------------------------------------

local function setText(key, show, text)
    texts[key]:SetText(show and text or "")
end

local function update()
    if not frame then return end
    if not db.enabled then frame:Hide() return end
    local level = safe(UnitLevel, "player") or 0
    local maxLevel = safe(GetMaxPlayerLevel) or level
    local disabled = safe(IsXPUserDisabled)
    local W = db.width - 2

    if disabled or (maxLevel > 0 and level >= maxLevel) then
        if not db.maxLevel then frame:Hide() return end
        frame:Show()
        fill:SetWidth(W)
        quest:SetWidth(0.001)
        rested:SetWidth(0.001)
        divQuest:Hide()
        divRested:Hide()
        badge.text:SetText(level)
        setText("onCenter", db.tXP, disabled and L.XP_DISABLED or L.XP_MAX)
        for _, k in ipairs({ "onRight", "topLeft", "underLeft", "underNext", "underRight" }) do texts[k]:SetText("") end
        setText("topRight", db.tSession, L.XP_SESSION:format(white(fmtETA(sessionSeconds()) or "<1m")))
        spark:Hide()
        return
    end
    frame:Show()
    badge.text:SetText(level)

    local xp = safe(UnitXP, "player") or 0
    local xpMax = safe(UnitXPMax, "player") or 0
    if xpMax <= 0 then
        for _, s in ipairs(SLOTS) do texts[s[1]]:SetText("") end
        fill:SetWidth(0.001)
        return
    end
    local restedXP = safe(GetXPExhaustion) or 0
    local questXP = db.quest and pendingQuestXP() or 0

    local fillFrac = clamp(xp / xpMax, 0, 1)
    local questFrac = db.quest and clamp(questXP / xpMax, 0, 1 - fillFrac) or 0
    local restedFrac = db.rested and clamp(restedXP / xpMax, 0, 1 - fillFrac - questFrac) or 0
    fill:SetWidth(math.max(0.001, W * fillFrac))
    quest:SetWidth(math.max(0.001, W * questFrac))
    rested:SetWidth(math.max(0.001, W * restedFrac))
    divQuest:SetShown(questFrac > 0)
    divRested:SetShown(restedFrac > 0)
    spark:SetShown(fillFrac > 0.005 and fillFrac < 0.995)

    local rate = xpPerHour(xp)
    texts.onLeft:SetText("")
    setText("onCenter", db.tXP, string.format("%d / %d (%d)", xp, xpMax, math.max(0, xpMax - xp)))
    if questFrac > 0 then
        setText("onRight", db.tPct, string.format("%.1f%% (%.1f%%)", fillFrac * 100, (fillFrac + questFrac) * 100))
    else
        setText("onRight", db.tPct, string.format("%.1f%%", fillFrac * 100))
    end
    setText("topLeft", db.tLevelTime, L.XP_LEVELTIME:format(white(fmtETA(track and track.secs or 0) or "<1m")))
    setText("topRight", db.tSession, L.XP_SESSION:format(white(fmtETA(sessionSeconds()) or "<1m")))
    setText("underLeft", db.tRate, white(rate and fmtAmount(rate) or "--") .. " " .. L.XP_PERHOUR)

    local eta = (db.tETA and rate and rate > 0) and fmtETA(math.max(0, xpMax - xp) / rate * 3600)
    texts.underNext:SetText(eta and ("|cffffd200" .. L.XP_NEXT:format(eta) .. "|r") or "")

    local parts = {}
    if db.quest then parts[#parts + 1] = string.format("|cffffbd47%s|r", L.XP_COMPLETED:format(questFrac * 100)) end
    if db.rested then parts[#parts + 1] = string.format("|cff%s%s|r", hex(C.violet), L.XP_RESTED:format(restedFrac * 100)) end
    setText("underRight", db.tBottom, table.concat(parts, "  "))
end

local function relayout()
    if not frame then return end
    frame:SetSize(db.width, db.height)
    local b = db.height + 8
    badge:SetSize(b, b)
    badge:SetShown(db.tLevel)
    for i, t in ipairs(ticks) do
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", bar, "TOPLEFT", math.floor((db.width - 2) * i / 10), 0)
        t:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", math.floor((db.width - 2) * i / 10), 0)
    end
    applyFonts()
    paint()
    ns.HideBlizzard(BLIZZ_XP, db.enabled and db.hideBlizzard)
    update()
end

---------------------------------------------------------------------------
-- Quetes automatiques (Maj enfoncee = pause, pour lire)
---------------------------------------------------------------------------

local function autoQuest(event)
    if not db.autoQuest or IsShiftKeyDown() then return end
    pcall(function()
        if event == "QUEST_GREETING" then
            for i = 1, GetNumActiveQuests() do SelectActiveQuest(i) end
            for i = 1, GetNumAvailableQuests() do SelectAvailableQuest(i) end
        elseif event == "GOSSIP_SHOW" and C_GossipInfo then
            for _, q in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
                if q.isComplete then C_GossipInfo.SelectActiveQuest(q.questID) return end
            end
            for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
                if not q.isTrivial then C_GossipInfo.SelectAvailableQuest(q.questID) return end
            end
        elseif event == "QUEST_DETAIL" then
            AcceptQuest()
        elseif event == "QUEST_ACCEPT_CONFIRM" then
            ConfirmAcceptQuest()
        elseif event == "QUEST_PROGRESS" then
            if IsQuestCompletable() then CompleteQuest() end
        elseif event == "QUEST_COMPLETE" then
            -- un choix de recompense : on laisse le joueur choisir
            if GetNumQuestChoices() <= 1 then GetQuestReward(1) end
        end
    end)
end

---------------------------------------------------------------------------
-- Fenetre d options
---------------------------------------------------------------------------

local win

local function buildWindow()
    win = ns.UI.Window("CorpUIXPOptions", ns.TITLE .. " - " .. L.MOD_XP, nil, 440, 420)
    -- chaque modification redessine la barre, puis le formulaire est relu
    local form = ns.UI.Form(win, -34, function() relayout() end)
    local function check(key, text)
        form:Check(text, function() return db[key] end, function(v)
            db[key] = v
            if key == "classColor" and v then db.preset = nil end
        end)
    end

    -- textes affiches sur la barre
    form:Header(L.XP_H_TEXTS)
    form:Columns(2)
    for _, o in ipairs({ { "tLevel", L.XP_T_LEVEL }, { "tXP", L.XP_T_XP }, { "tPct", L.XP_T_PCT },
                         { "tLevelTime", L.XP_T_LEVELTIME }, { "tSession", L.XP_T_SESSION },
                         { "tRate", L.XP_T_RATE }, { "tETA", L.XP_T_ETA }, { "tBottom", L.XP_T_BOTTOM } }) do
        check(o[1], o[2])
    end
    form:EndColumns()

    -- la barre (la case des quetes auto, db.autoQuest, est dans le panneau
    -- Suivi de quetes : Quetes.lua ; l acceptation reste ici, autoQuest())
    form:Gap(4)
    form:Header(L.XP_H_BAR)
    form:Columns(2)
    for _, o in ipairs({ { "enabled", L.XP_OPT_ENABLE }, { "quest", L.XP_OPT_QUEST }, { "rested", L.XP_OPT_RESTED },
                         { "maxLevel", L.XP_OPT_MAXLEVEL }, { "border", L.XP_OPT_BORDER }, { "bold", L.XP_OPT_BOLD },
                         { "hideBlizzard", L.XP_OPT_BLIZZ } }) do
        check(o[1], o[2])
    end
    form:EndColumns()

    -- couleurs : 8 palettes (pastilles) + couleur de classe
    form:Gap(4)
    form:Header(L.XP_COLORS)
    local y = form.y
    local swatches = {}
    for i, key in ipairs(PRESET_ORDER) do
        local s = CreateFrame("Button", nil, win)
        s:SetSize(36, 16)
        s:SetPoint("TOPLEFT", win, "TOPLEFT", 8 + (i - 1) * 42, y - 2)
        local t = s:CreateTexture(nil, "ARTWORK")
        t:SetAllPoints()
        t:SetColorTexture(1, 1, 1, 1)
        local a, b = presetColors(key)
        if not pcall(t.SetGradient, t, "HORIZONTAL", CreateColor(a[1], a[2], a[3], 1), CreateColor(b[1], b[2], b[3], 1)) then
            t:SetColorTexture(a[1], a[2], a[3], 1)
        end
        s.sel = s:CreateTexture(nil, "OVERLAY")
        s.sel:SetPoint("TOPLEFT", -2, 2)
        s.sel:SetPoint("BOTTOMRIGHT", 2, -2)
        s.sel:SetColorTexture(1, 1, 1, 0.5)
        s.sel:SetDrawLayer("BACKGROUND")
        s.key = key
        s:SetScript("OnClick", function()
            db.preset, db.classColor = key, false
            form.Changed()
        end)
        swatches[i] = s
    end
    table.insert(form.refreshers, function()
        for _, s in ipairs(swatches) do s.sel:SetShown(not db.classColor and db.preset == s.key) end
    end)
    form.y = y - 26
    check("classColor", L.XP_OPT_CLASS)

    -- tailles : curseur + saisie (Maj sur - / + : pas de 5)
    form:Gap(4)
    form:Header(L.XP_H_SIZE)
    form:Columns(2)
    form:Number(L.XP_WIDTH, function() return db.width end, function(v) db.width = v end, 60, 3000, 10)
    form:Number(L.XP_HEIGHT, function() return db.height end, function(v) db.height = v end, 8, 60, 1)
    form:Number(L.XP_TEXTSIZE, function() return db.textSize end, function(v) db.textSize = v end, 8, 24, 1)
    form:EndColumns()

    local reset = ns.UI.Button(win, L.XP_RESET, 120, function()
        db.width, db.height, db.textSize = DEFAULTS.width, DEFAULTS.height, DEFAULTS.textSize
        db.pos.point, db.pos.rel, db.pos.x, db.pos.y = "TOP", nil, 0, -150
        ns.ApplyPos(frame, db.pos)
        form.Changed()
    end)
    reset:SetPoint("TOPLEFT", win, "TOPLEFT", 8, form.y - 4)
    form:Gap(32)
    win:SetHeight(-form.y + 12)

    win:HookScript("OnShow", function() form:Refresh() end)
end

local function toggle()
    if not win then buildWindow() end
    ns.ShowPanel(win)
end

---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        root.xp = root.xp or {}
        db = root.xp
        for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
        if not db.classColor and db.preset ~= "theme" and not PRESETS[db.preset or ""] then db.preset = "theme" end
        -- nouvel habit CorpUI (une fois) : couleurs du theme, barre plus fine
        if not db.style2 then
            db.style2 = true
            db.preset, db.classColor = "theme", false
            db.height, db.textSize = DEFAULTS.height, DEFAULTS.textSize
        end
        db.chars = db.chars or {}
        build()
        relayout()
        return
    end
    if not db then return end
    if event:find("^QUEST_") or event == "GOSSIP_SHOW" then
        autoQuest(event)
        if event ~= "QUEST_LOG_UPDATE" and event ~= "QUEST_TURNED_IN" then return end
    elseif event == "TIME_PLAYED_MSG" then
        -- a2 = temps passe a ce niveau : recale notre compteur
        local rec = ensureTrack()
        if rec and type(a2) == "number" and a2 > 0 then rec.secs, rec.baseXP = a2, 0 end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- session : repart de zero a la connexion, survit au /reload
        local now = time()
        if a1 == true or not db.sessionStart or (db.lastSeen and now - db.lastSeen > 60 and not a2) then
            db.sessionStart = now
        end
        db.lastSeen = now
        ensureTrack()
        if (a1 or not playedAsked) and C_Timer then
            playedAsked = true
            C_Timer.After(2, function() safe(RequestTimePlayed) end)
        end
        relayout()
    elseif event == "PLAYER_LEVEL_UP" then
        ensureTrack()
    end
    update()
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP",
                     "UPDATE_EXHAUSTION", "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "ENABLE_XP_GAIN",
                     "DISABLE_XP_GAIN", "TIME_PLAYED_MSG", "QUEST_GREETING", "GOSSIP_SHOW", "QUEST_DETAIL",
                     "QUEST_ACCEPT_CONFIRM", "QUEST_PROGRESS", "QUEST_COMPLETE" }) do
    pcall(ev.RegisterEvent, ev, e)
end

-- horloge : temps a ce niveau et de session
local since = 0
ev:SetScript("OnUpdate", function(_, dt)
    since = since + dt
    if since < 1 or not db then return end
    since = 0
    tick()
    update()
end)

ns.RegisterModule({
    command = "xp",
    panelName = "CorpUIXPOptions",
    icon = "Interface\\Icons\\INV_Misc_Book_11",
    title = function() return L.MOD_XP end,
    desc = function() return L.XP_DESC end,
    Slash = function() toggle() end,
    Open = toggle,
})
