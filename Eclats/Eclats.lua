--[[--------------------------------------------------------------------------
    CorpUI - module Eclats : ce qui se ramasse scintille
    (idee : l addon ForeverLootSparkles ; code ecrit pour CorpUI)

    1. Objets de quete : l effet de butin du jeu (l etincelle) ne se voit
       que si le contour des objets est coupe. Les reglages graphiques le
       remettent : les variables du jeu (CVar) sont reposees a la
       connexion et une seconde apres chaque changement graphique (hors
       combat). Couper l option remet le contour ; l etincelle ne part
       qu au redemarrage du jeu.
    2. Filons et herbes (et, en option, objets de quete proches) : le
       ciblage doux du jeu choisit l objet le plus proche (unite
       "softinteract", ~15 m). Si c est un objet voulu, le jeu lui donne
       sa plaque (nom et icone de recolte) et CorpUI y accroche un petit
       nuage d eclats dores :
         - hors de portee : eclats ternes ;
         - a portee : ils s allument d un coup ;
         - recolte impossible (competence trop basse...) : gris.
       Le type de l objet se lit sur l icone de curseur qu il donnerait
       (minage, herboristerie, quete). La plaque n est ouverte que pour ces
       objets (les PNJ et boites aux lettres restent comme avant) ; en
       combat, fermee (le jeu refuse ces reglages en combat). Les reglages
       du ciblage doux d avant sont gardes et remis quand plus rien n est
       coche.
    Rien de protege, aucun crochet : des CVar et nos propres textures.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local issecret = issecretvalue or function() return false end

local DEFAULTS = { loot = true, ore = true, herb = true, quest = false }
local CATEGORY = { ore = "ore", herb = "herb", quest = "quest" }    -- option par sorte d objet

-- effet de butin des objets de quete
local LOOT_ON = {
    outlineModeShowLootEffectWhenDisabled = "1", graphicsOutlineMode = "0", OutlineEngineMode = "0",
    raidGraphicsOutlineMode = "0", RAIDOutlineEngineMode = "0",
}
local LOOT_OFF = {
    outlineModeShowLootEffectWhenDisabled = "0", graphicsOutlineMode = "2", OutlineEngineMode = "2",
    raidGraphicsOutlineMode = "2", RAIDOutlineEngineMode = "2",
}
-- changement graphique a surveiller (en minuscules)
local WATCH = { graphicsquality = true, raidgraphicsquality = true }
for k in pairs(LOOT_ON) do WATCH[k:lower()] = true end

-- ciblage doux : valeurs voulues ; les anciennes sont gardees dans db.saved
local SOFT_ON = {
    SoftTargetInteract = 3, SoftTargetInteractRange = 60, SoftTargetInteractArc = 2,
    SoftTargetInteractOnlyInRange = 0, SoftTargetIconInteract = 1, SoftTargetIconGameObject = 1,
    SoftTargetLowPriorityIcons = 1,
}
local GATE = "SoftTargetNameplateInteract"   -- plaque de l objet vise

local SOFT = "softinteract"
local STAR = "Interface\\Cooldown\\star4"
local GLINTS, SPREAD, SIZE, DROP = 7, 44, 30, -44
local GOLD, GREY = { 1, 0.86, 0.5 }, { 0.6, 0.6, 0.62 }
local POLL = 0.15

local db
local pendingLoot, pendingSoft = false, nil   -- a faire apres le combat
local gate                                     -- etat pose de la plaque (nil : a poser)

---------------------------------------------------------------------------
-- Valeurs sures et variables du jeu
---------------------------------------------------------------------------

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or issecret(v) then return nil end
    return v
end

local function getCVar(name)
    return safe(C_CVar and C_CVar.GetCVar, name)
end

local function setCVar(name, value)
    local cur = getCVar(name)
    if cur == nil then return end          -- inconnue de ce client
    value = tostring(value)
    if cur ~= value then pcall(C_CVar.SetCVar, name, value) end
end

---------------------------------------------------------------------------
-- 1. Effet de butin des objets de quete
---------------------------------------------------------------------------

local applyingLoot = false

local function applyLoot()
    if not db or not db.loot then return end
    if InCombatLockdown() then pendingLoot = true return end
    applyingLoot = true
    for k, v in pairs(LOOT_ON) do setCVar(k, v) end
    applyingLoot = false
    db.lootOn = true
end

local function removeLoot()
    if InCombatLockdown() then return end
    applyingLoot = true
    for k, v in pairs(LOOT_OFF) do setCVar(k, v) end
    applyingLoot = false
    db.lootOn = nil
end

---------------------------------------------------------------------------
-- 2. Ciblage doux : reglages
---------------------------------------------------------------------------

local function anyNode()
    return db and (db.ore or db.herb or db.quest) and true or false
end

local function setGate(open)
    if open == gate or InCombatLockdown() then return end
    gate = open
    setCVar(GATE, open and 1 or 0)
end

local function applySoft()
    if InCombatLockdown() then pendingSoft = "apply" return end
    db.saved = db.saved or {}
    for name in pairs(SOFT_ON) do
        if db.saved[name] == nil then db.saved[name] = getCVar(name) or false end
    end
    if db.saved[GATE] == nil then db.saved[GATE] = getCVar(GATE) or false end
    for name, v in pairs(SOFT_ON) do setCVar(name, v) end
    gate = nil
end

local function restoreSoft()
    if InCombatLockdown() then pendingSoft = "restore" return end
    if type(db.saved) ~= "table" then return end
    for name, v in pairs(db.saved) do
        if v ~= false then setCVar(name, v) end
    end
    db.saved = nil
    gate = nil
end

---------------------------------------------------------------------------
-- Sorte de l objet vise : icone de curseur qu il donnerait
---------------------------------------------------------------------------

local probe = UIParent:CreateTexture(nil, "BACKGROUND")
probe:Hide()

-- fichiers de curseur -> sorte ; "Unable" : impossible pour l instant
local CURSORS = { Mine = "ore", GatherHerbs = "herb", Quest = "quest", QuestRepeatable = "quest", QuestTurnIn = "quest" }
local byFile = {}
if GetFileIDFromPath then
    for file, kind in pairs(CURSORS) do
        for _, pre in ipairs({ "", "Unable" }) do
            local path = "Interface\\Cursor\\" .. pre .. file
            local id = safe(GetFileIDFromPath, path) or safe(GetFileIDFromPath, path .. ".blp")
            if id then byFile[id] = { kind, pre ~= "" } end
        end
    end
end
-- sinon par le nom : chemin ou atlas ("Cursor_Crosshair_UnableMine_64")
local function fromName(s)
    if type(s) ~= "string" then return nil, false end
    s = s:lower()
    local unable = s:find("unable", 1, true) ~= nil
    if s:find("gather", 1, true) or s:find("herb", 1, true) then return "herb", unable end
    if s:find("mine", 1, true) then return "ore", unable end
    if s:find("quest", 1, true) then return "quest", unable end
    return nil, unable
end

local QUEST_LINE = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective

local function questObject(unit)
    if C_QuestLog and safe(C_QuestLog.UnitIsRelatedToActiveQuest, unit) == true then return true end
    if QUEST_LINE and C_TooltipInfo then
        local data = safe(C_TooltipInfo.GetUnit, unit)
        if type(data) == "table" and type(data.lines) == "table" then
            for _, line in ipairs(data.lines) do
                if line.type == QUEST_LINE then return true end
            end
        end
    end
    return false
end

-- sorte ("ore", "herb", "quest" ou nil) et "impossible pour l instant"
local function classify(unit)
    local kind, unable
    if safe(SetUnitCursorTexture, probe, unit, nil, true) then
        local tex = probe:GetTexture()
        local atlas = probe.GetAtlas and probe:GetAtlas() or nil
        if issecret(tex) then tex = nil end
        if issecret(atlas) then atlas = nil end
        local known = type(tex) == "number" and byFile[tex]
        if known then
            kind, unable = known[1], known[2]
        else
            kind, unable = fromName(tex)
            if not kind then
                local k2, u2 = fromName(atlas)
                kind, unable = k2, unable or u2
            end
        end
    end
    if kind ~= "ore" and kind ~= "herb" and questObject(unit) then kind = "quest" end
    return kind, unable and true or false
end

-- "ready" a portee, "far" trop loin, "locked" a portee mais impossible
local function stateOf(unit, unable)
    local inRange = safe(UnitIsInInteractRange, unit)
    if inRange == false then return "far" end
    if unable then return inRange == true and "locked" or "far" end
    return "ready"
end

---------------------------------------------------------------------------
-- Eclats
---------------------------------------------------------------------------

local spark = { glints = {} }          -- un seul nuage : un seul objet vise

local function lerp(a, b, t) return a + (b - a) * t end
local function toward(v, target, step)
    if v < target then return math.min(v + step, target) end
    return math.max(v - step, target)
end

local function reseed(g, now)
    local a, r = math.random() * 2 * math.pi, math.sqrt(math.random())
    g.x, g.y = math.cos(a) * r * SPREAD, math.sin(a) * r * SPREAD * 0.7
    g.life = 0.6 + 0.8 * math.random()
    g.size = 0.5 + 0.7 * math.random()
    g.rot, g.spin = math.random() * 2 * math.pi, (math.random() - 0.5) * 2
    g.t = now and 0 or -0.6 * math.random()
end

local function animate(self, dt)
    dt = math.min(dt, 0.1)
    spark.fade = toward(spark.fade, 1, dt / 0.35)
    spark.lit = toward(spark.lit, spark.state == "ready" and 1 or 0, dt / 0.3)
    spark.grey = toward(spark.grey, spark.state == "locked" and 1 or 0, dt / 0.3)
    local alpha = spark.fade * lerp(0.5, 1, spark.lit) * (1 - 0.55 * spark.grey)
    local speed = lerp(0.8, 1.25, spark.lit) * (1 - 0.5 * spark.grey)
    local r, g, b = lerp(GOLD[1], GREY[1], spark.grey), lerp(GOLD[2], GREY[2], spark.grey), lerp(GOLD[3], GREY[3], spark.grey)
    for _, gl in ipairs(spark.glints) do
        gl.t = gl.t + dt * speed
        if gl.t >= gl.life then reseed(gl) end
        local shine = gl.t > 0 and math.sin(math.pi * gl.t / gl.life) or 0
        local tex = gl.tex
        tex:SetPoint("CENTER", self, "CENTER", gl.x, gl.y + 10 * math.max(gl.t, 0))
        local s = math.max(SIZE * gl.size * (0.35 + 0.65 * shine), 0.01)
        tex:SetSize(s, s)
        pcall(tex.SetRotation, tex, gl.rot + gl.spin * math.max(gl.t, 0))
        tex:SetVertexColor(r, g, b, math.min(alpha * shine, 1))
    end
end

local function buildSpark()
    local f = CreateFrame("Frame")
    f:SetSize(1, 1)
    f:Hide()
    for i = 1, GLINTS do
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetTexture(STAR)
        t:SetBlendMode("ADD")
        t:SetVertexColor(1, 1, 1, 0)
        ns.NoSnap(t)
        spark.glints[i] = { tex = t }
    end
    f:SetScript("OnUpdate", animate)
    spark.frame = f
end

local function release()
    if not spark.plate then return end
    spark.frame:Hide()
    spark.frame:ClearAllPoints()
    spark.frame:SetParent(UIParent)
    spark.plate, spark.moved = nil, nil
end

local function attach(plate, state)
    if not spark.frame then buildSpark() end
    local f = spark.frame
    f:SetParent(plate)
    local lvl = safe(plate.GetFrameLevel, plate)
    if type(lvl) == "number" then f:SetFrameLevel(math.max(lvl - 1, 0)) end
    f:ClearAllPoints()
    f:SetPoint("CENTER", plate, "CENTER", 0, DROP)
    pcall(f.SetIgnoreParentAlpha, f, true)
    spark.plate, spark.state, spark.next = plate, state, nil
    spark.fade, spark.lit, spark.grey = 0, state == "ready" and 1 or 0, state == "locked" and 1 or 0
    for _, g in ipairs(spark.glints) do reseed(g) end
    f:Show()
end

-- un nouvel etat ne se montre que s il tient (pas de clignotement au bord)
local function propose(state)
    if state == spark.state then spark.next = nil return end
    local now = GetTime()
    if spark.next ~= state then
        spark.next, spark.since = state, now
    elseif now - spark.since >= (state == "locked" and 0.6 or 0.15) then
        spark.next, spark.state = nil, state
        -- a portee : tous les eclats repartent ensemble
        if state == "ready" then for _, g in ipairs(spark.glints) do reseed(g, true) end end
    end
end

---------------------------------------------------------------------------
-- Objet vise et sa plaque
---------------------------------------------------------------------------

local platesShown = {}           -- nameplateN -> true
local directPlate = false        -- GetNamePlateForUnit("softinteract") a deja marche

local function plateOf(unit)
    local p = C_NamePlate and safe(C_NamePlate.GetNamePlateForUnit, unit)
    if p and safe(p.IsForbidden, p) then return nil end
    return p
end

-- unite a lire, sa plaque (nil si pas encore), et "on ne sait pas"
local function target()
    local isUnit, isObj = safe(UnitExists, SOFT), safe(UnitIsGameObject, SOFT)
    if isUnit == false and isObj == false then return nil end
    local plate = plateOf(SOFT)
    if plate then
        if isObj == true then directPlate = true end
        return SOFT, plate
    end
    -- ce client ne donne pas encore la plaque par "softinteract" : on la
    -- cherche parmi les plaques visibles
    if not directPlate then
        for unit in pairs(platesShown) do
            if safe(UnitIsGameObject, unit) == true or safe(UnitIsUnit, unit, SOFT) == true then
                plate = plateOf(unit)
                if plate then return unit, plate end
            end
        end
    end
    if isUnit or isObj then return SOFT, nil end
    return nil, nil, true
end

local function evaluate()
    if not anyNode() then release() return end
    local unit, plate, unknown = target()
    -- seuls les objets du monde : pas de PNJ ni de corps
    if not unit or safe(UnitIsGameObject, unit) ~= true then
        setGate(unknown == true)
        release()
        return
    end
    local kind, unable = classify(unit)
    local want = kind ~= nil and db[CATEGORY[kind]] == true
    setGate(want)
    if not want or not plate then release() return end
    local state = stateOf(unit, unable)
    if spark.plate ~= plate or spark.moved then
        release()
        attach(plate, state)
    else
        propose(state)
    end
end
ns._sparkEvaluate = evaluate

local poller = CreateFrame("Frame")
poller:Hide()
local acc = 0
poller:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < POLL then return end
    acc = 0
    evaluate()
end)

-- options changees : reglages du jeu et releve a jour
local function refresh()
    if not db then return end
    if db.loot then applyLoot() elseif db.lootOn then removeLoot() end
    if anyNode() then applySoft() else release() restoreSoft() end
    poller:SetShown(anyNode())
    evaluate()
end
ns.SparklesRefresh = refresh

---------------------------------------------------------------------------
-- Reglages (/corp eclats)
---------------------------------------------------------------------------

local panel

local function buildPanel()
    panel = ns.UI.Window("CorpUISparklesOptions", ns.TITLE .. " - " .. L.MOD_SPARKLES, nil, 440, 250)
    local form = ns.UI.Form(panel, -34, function() refresh() end)
    form:Check(L.SPARK_OPT_LOOT, function() return db.loot end, function(v) db.loot = v end)
    local note = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", panel, "TOPLEFT", 28, form.y + 2)
    note:SetWidth(400)
    note:SetJustifyH("LEFT")
    note:SetText(L.SPARK_LOOT_NOTE)
    form.y = form.y - 26
    form:Header(L.SPARK_H_NODES)
    form:Columns(3)
    form:Check(L.SPARK_OPT_ORE, function() return db.ore end, function(v) db.ore = v end)
    form:Check(L.SPARK_OPT_HERB, function() return db.herb end, function(v) db.herb = v end)
    form:Check(L.SPARK_OPT_QUEST, function() return db.quest end, function(v) db.quest = v end)
    form:EndColumns()
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, form.y - 4)
    hint:SetWidth(424)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.SPARK_HINT)
    panel:HookScript("OnShow", function() form:Refresh() end)
end

local function openPanel()
    if not db then return end
    if not panel then buildPanel() end
    ns.ShowPanel(panel)
end

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

local lootAt
local timer = CreateFrame("Frame")
timer:Hide()
timer:SetScript("OnUpdate", function(self)
    if GetTime() >= lootAt then self:Hide() applyLoot() end
end)
local function lootLater(delay)
    lootAt = GetTime() + delay
    timer:Show()
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, a, b)
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        if type(root.sparkles) ~= "table" then root.sparkles = {} end
        db = root.sparkles
        for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
        if ns.ModuleOff("eclats", ev) then
            -- module coupe : les reglages du jeu reviennent
            if db.lootOn then removeLoot() end
            restoreSoft()
            db = nil
            return
        end
        refresh()
        lootLater(5)            -- reglages du compte arrives apres la connexion
        return
    end
    if not db then return end
    if event == "PLAYER_ENTERING_WORLD" or event == "VARIABLES_LOADED" then
        if anyNode() then applySoft() end
        evaluate()
    elseif event == "CVAR_UPDATE" then
        if not applyingLoot and db.loot and type(a) == "string" and not issecret(a) and WATCH[a:lower()] then lootLater(1) end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- les reglages sont refuses en combat : plaque fermee avant
        if anyNode() then setGate(false) release() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingLoot then pendingLoot = false applyLoot() end
        if pendingSoft == "apply" then applySoft() elseif pendingSoft == "restore" then restoreSoft() end
        pendingSoft = nil
        evaluate()
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if type(a) == "string" and not issecret(a) then platesShown[a] = true end
        evaluate()
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if type(a) == "string" and not issecret(a) then
            platesShown[a] = nil
            local p = plateOf(a)
            if p and p == spark.plate then release() end
        end
    elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
        -- plaque recyclee d un objet au suivant : on repart de zero
        if not issecret(a) and not issecret(b) and a and b and a ~= b then spark.moved = spark.plate ~= nil end
        evaluate()
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "VARIABLES_LOADED", "CVAR_UPDATE", "PLAYER_REGEN_DISABLED",
                     "PLAYER_REGEN_ENABLED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
                     "PLAYER_SOFT_INTERACT_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)
end

ns.RegisterModule({
    command = "eclats",
    alias = "sparkles",
    panelName = "CorpUISparklesOptions",
    icon = "Interface\\Icons\\INV_Misc_Gem_Variety_01",
    title = function() return L.MOD_SPARKLES end,
    desc = function() return L.SPARK_DESC end,
    Slash = function() openPanel() end,
    Open = openPanel,
})

-- banc d essai
ns._sparkles = { evaluate = evaluate, classify = classify, spark = spark, gate = function() return gate end,
                 refresh = refresh }
