--[[--------------------------------------------------------------------------
    CorpUI - centre de l ecran (avec le module Cadres)
    Entre les cadres joueur et cible, comme la maquette :
      - barre de puissance du joueur (mana, rage, energie), texte centre
        "3 060 / 4 230" (ou valeur seule, ou %) ;
      - procs : buffs courts du joueur (duree d au plus N secondes, les
        buffs permanents et longs restent en haut a droite), en ligne
        centree sous la barre.
    Coupe par defaut ; allume dans les reglages par defaut de CorpUI
    (Defauts.lua).
    Deplacable avec les autres poignees.

    Valeurs secretes : la barre recoit UnitPower / UnitPowerMax tels quels
    (le client remplit la barre) ; le texte est calcule si les valeurs sont
    lisibles, sinon abrege par le client (AbbreviateNumbers). Les procs
    passent par le conteneur d auras du client (ns.NativeAuras) : en combat,
    ce client refuse toute lecture d aura a un addon, le conteneur les lit
    et les filtre seul (filtre "HELPFUL", candidat maxDuration).
    Affichage seulement : rien de securise, rien de Blizzard n est touche.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L
local C = ns.COLORS

local issecret = issecretvalue or function() return false end

local TEXTS = { "curmax", "cur", "pct", "none" }
local DEFAULTS = {
    enabled = false,
    power = true, width = 150, height = 14, textSize = 11, text = "curmax",
    procs = true, procSize = 22, procMax = 8, procDuration = 60, procTime = true,
}
local PROC_GAP = 4

local POWER_FALLBACK = {
    MANA = { 0.18, 0.44, 0.84 }, RAGE = { 0.78, 0.15, 0.15 }, ENERGY = { 1, 0.85, 0.1 },
    FOCUS = { 1, 0.5, 0.25 },
}

local db
local holder, bar, text
local procs
local pending           -- placement a refaire en sortie de combat

---------------------------------------------------------------------------
-- Barre de puissance
---------------------------------------------------------------------------

local function powerColor()
    local ok, _, token = pcall(UnitPowerType, "player")
    if not ok or issecret(token) or type(token) ~= "string" then token = "MANA" end
    local c = PowerBarColor and PowerBarColor[token]
    if c and c.r then return c.r, c.g, c.b end
    local f = POWER_FALLBACK[token] or POWER_FALLBACK.MANA
    return f[1], f[2], f[3]
end

local function big(n)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    return tostring(n)
end

-- texte de la barre : calcule si lisible, sinon par le client
local function setText(cur, max)
    local mode = db.text
    if mode == "none" then text:SetText("") return end
    local ok, s = pcall(function()
        if mode == "pct" then
            if max <= 0 then return "" end
            return math.floor(cur / max * 100 + 0.5) .. "%"
        elseif mode == "cur" then
            return big(cur)
        end
        return big(cur) .. " / " .. big(max)
    end)
    if ok then text:SetText(s) return end
    if mode == "pct" then
        local scale = CurveConstants and CurveConstants.ScaleTo100
        if scale and UnitPowerPercent then
            local okP, p = pcall(UnitPowerPercent, "player", nil, true, scale)
            if okP and pcall(text.SetFormattedText, text, "%d%%", p) then return end
        end
        text:SetText("")
        return
    end
    local okA, a = pcall(AbbreviateNumbers or tostring, cur)
    if mode == "cur" then
        if not okA or not pcall(text.SetFormattedText, text, "%s", a) then text:SetText("") end
        return
    end
    local okB, b = pcall(AbbreviateNumbers or tostring, max)
    if not (okA and okB and pcall(text.SetFormattedText, text, "%s / %s", a, b)) then text:SetText("") end
end

local function updatePower()
    if not bar or not db or not db.enabled or not db.power then return end
    local okC, cur = pcall(UnitPower, "player")
    local okM, max = pcall(UnitPowerMax, "player")
    if not okC or not okM then return end
    pcall(bar.SetMinMaxValues, bar, 0, max)
    pcall(bar.SetValue, bar, cur)
    bar:SetStatusBarColor(powerColor())
    setText(cur, max)
end

---------------------------------------------------------------------------
-- Procs : conteneur d auras du client
---------------------------------------------------------------------------

local function procSpec()
    return {
        width = db.procSize, height = db.procSize, spacing = 3, perRow = db.procMax, max = db.procMax,
        grow = "down", time = db.procTime and "below" or "none",
        -- au milieu de l ecran : les clics passent (tourner la camera)
        noMouse = true,
        groups = { { key = "procs", filter = "HELPFUL", candidate = { maxDuration = db.procDuration } } },
    }
end

-- le conteneur prend la taille de son contenu : accroche par le haut, la
-- ligne d icones reste centree sous la barre
local function anchorProcs()
    local fr = procs.frame
    fr:ClearAllPoints()
    if db.power then
        fr:SetPoint("TOP", holder, "BOTTOM", 0, -PROC_GAP)
    else
        fr:SetPoint("TOP", holder, "TOP", 0, 0)
    end
end

---------------------------------------------------------------------------
-- Construction et placement
---------------------------------------------------------------------------

local function build()
    holder = CreateFrame("Frame", "CorpUICenter", UIParent)
    holder:SetFrameStrata("LOW")
    ns.ApplyPos(holder, db.pos)
    bar = CreateFrame("StatusBar", nil, holder)
    bar:SetAllPoints()
    bar:SetStatusBarTexture(ns.BAR_TEXTURE)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    ns.UI.Skin(bar, 0.8)
    text = bar:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER", 0, 0)
    ns.UI.Mover(holder, db.pos, L.CENTER_MOVER)
end

local function apply()
    if not holder then return end
    if InCombatLockdown() then pending = true return end
    pending = false
    local on = db.enabled
    holder:SetSize(db.width, db.power and db.height or db.procSize)
    holder:SetShown(on or ns.moversShown or false)
    bar:SetShown(on and db.power or false)
    ns.UI.HeadFont(text, db.textSize)
    if on and db.procs and not procs and ns.NativeAuras then
        procs = ns.NativeAuras(holder, "player", procSpec())
    end
    if procs then
        if on and db.procs then
            procs:Apply(procSpec())
            anchorProcs()
            procs.frame:Show()
        else
            procs.frame:Hide()
        end
    end
    updatePower()
end
ns.CenterApply = apply

-- poignees affichees : le centre se montre pour etre place
local lastMovers = false
ns.Listen(function()
    if not db or (ns.moversShown and true or false) == lastMovers then return end
    lastMovers = ns.moversShown and true or false
    apply()
end)

---------------------------------------------------------------------------
-- Options (section "Joueur" de l editeur des cadres)
---------------------------------------------------------------------------

function ns.FramesOpt.Center(parent, y)
    local form = ns.UI.Form(parent, y, function() apply() end)
    form:Header(L.CENTER_HEADER)
    local function check(textKey, key)
        form:Check(textKey, function() return db and db[key] end, function(v) if db then db[key] = v end end)
    end
    local function number(fmt, key, lo, hi, step)
        form:Number(fmt, function() return db and db[key] or lo end, function(v)
            if db then db[key] = math.max(lo, math.min(hi, math.floor(v + 0.5))) end
        end, lo, hi, step)
    end
    check(L.CENTER_OPT_ENABLE, "enabled")
    form:Columns(2)
    check(L.CENTER_OPT_POWER, "power")
    check(L.CENTER_OPT_PROCS, "procs")
    number(L.CENTER_WIDTH, "width", 80, 400, 2)
    number(L.CENTER_HEIGHT, "height", 4, 30)
    number(L.CENTER_TEXT_SIZE, "textSize", 7, 18)
    form:Cycle(L.CENTER_TEXT, TEXTS, {
        curmax = L.CENTER_TEXT_CURMAX, cur = L.CENTER_TEXT_CUR, pct = L.CENTER_TEXT_PCT, none = L.CENTER_TEXT_NONE,
    }, function() return db and db.text end, function(v) if db then db.text = v end end)
    number(L.CENTER_PROC_SIZE, "procSize", 14, 40)
    number(L.CENTER_PROC_MAX, "procMax", 1, 16)
    number(L.CENTER_PROC_DURATION, "procDuration", 5, 300, 5)
    check(L.CENTER_OPT_PROC_TIME, "procTime")
    form:EndColumns()
    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, form.y - 6)
    hint:SetWidth(420)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.CENTER_HINT)
    parent:HookScript("OnShow", function() form:Refresh() end)
    form:Refresh()
    return form.y - 40
end

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        if type(root.center) ~= "table" then root.center = {} end
        db = root.center
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = v end
        end
        local known = false
        for _, t in ipairs(TEXTS) do if db.text == t then known = true end end
        if not known then db.text = DEFAULTS.text end
        if type(db.pos) ~= "table" then db.pos = { point = "CENTER", x = 0, y = -150 } end
        build()
        apply()
    elseif not db then
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending then apply() end
    else
        updatePower()
    end
end)
pcall(ev.RegisterEvent, ev, "PLAYER_LOGIN")
pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")
pcall(ev.RegisterEvent, ev, "PLAYER_ENTERING_WORLD")
for _, e in ipairs({ "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }) do
    pcall(ev.RegisterUnitEvent, ev, e, "player")
end
