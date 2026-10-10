--[[--------------------------------------------------------------------------
    CorpUI - ressources (avec le module Cadres)
    A la facon d ElvUI, autour de nos cadres joueur et cible :
      - points de combo (voleur, druide en felin) : 5 cases sous / au-dessus
        du cadre joueur ou cible, ou libres (poignee)
      - tick d energie : etincelle qui balaie la barre d energie en 2 s,
        calee sur les montees d energie lues
      - regle des 5 secondes : etincelle sur la barre de mana pendant les
        5 s qui suivent une depense, puis ticks de regen toutes les 2 s
      - mana du druide en forme d ours / de felin : fine barre sous le cadre

    Valeurs secretes : UnitPower / GetComboPoints peuvent l etre. Les cases
    de combo sont des barres dont les bornes sont (i - 1, i) : on leur passe
    le nombre de points tel quel et le client les remplit ou non, sans calcul
    de notre part (meme methode que nos barres de vie). Les etincelles, elles,
    ont besoin de lire les montees : valeur secrete = pas de nouveau calage.

    Affichage seulement : rien de securise, rien de Blizzard n est touche ;
    nos cadres sont des enfants (non securises) des cadres CorpUI, comme le
    portrait du module Cadres.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local issecret = issecretvalue or function() return false end

local PT = (Enum and Enum.PowerType) or {}
local MANA = PT.Mana or 0
local ENERGY = PT.Energy or 3
local COMBO = PT.ComboPoints or 4

local SPARK = "Interface\\CastingBar\\UI-CastingBar-Spark"
local TICK = 2          -- regen d energie et de mana : toutes les 2 s
local FIVE = 5          -- regle des 5 secondes
local MAX_POINTS = 5

local POSITIONS = { "player_below", "player_above", "target_below", "target_above", "plate", "free" }
local DEFAULTS = {
    combo = true, comboAlways = true, comboPos = "target_above", comboHeight = 8, comboWidth = 160,
    energyTick = true, fiveSec = true, manaTicks = true,
    druidMana = true, druidManaHeight = 5,
}

local db
local class
local combo, druidBar
local energySpark, manaSpark, druidSpark
local pending           -- placement a refaire en sortie de combat

-- etat de la puissance du joueur (valeurs lisibles seulement)
local st = {}

---------------------------------------------------------------------------
-- Lectures protegees
---------------------------------------------------------------------------

-- valeur lisible : ni secrete, ni nil (issecret d abord : comparer une
-- valeur secrete est interdit)
local function readable(v)
    if issecret(v) then return false end
    return v ~= nil
end

local function call(fn, ...)
    if not fn then return nil end
    local ok, v = pcall(fn, ...)
    if ok then return v end
end

-- nombre lisible ou nil
local function num(v)
    if readable(v) and type(v) == "number" then return v end
end

local function flag(fn, ...)
    local v = call(fn, ...)
    return readable(v) and v and true or false
end

local function powerType()
    local ok, pt = pcall(UnitPowerType, "player")
    if ok and readable(pt) then return pt end
end

local function inCombat()
    return flag(UnitAffectingCombat, "player") or InCombatLockdown()
end

-- points de combo : GetComboPoints (sur la cible, comme le ComboFrame de
-- Blizzard), sinon UnitPower ; la valeur peut etre secrete
local function comboPoints()
    local v = call(GetComboPoints, "player", "target")
    if type(v) ~= "number" then v = call(UnitPower, "player", COMBO) end
    if type(v) ~= "number" then return nil end
    return v
end

-- forme de felin : type de ressource energie, sinon la forme elle-meme
-- (GetShapeshiftFormID : 1 = felin) si le type n est pas lisible
local function catForm()
    if st.pt ~= nil then return st.pt == ENERGY end
    local id = call(GetShapeshiftFormID)
    return readable(id) and id == 1 or false
end

local function comboRelevant()
    return class == "ROGUE" or (class == "DRUID" and catForm())
end

---------------------------------------------------------------------------
-- Cadres CorpUI d accroche (construits par Cadres.lua)
---------------------------------------------------------------------------

local function unitFrame(key)
    local fdb = ns.root and ns.root.frames
    if not fdb then return nil end
    if key == "player" then
        if fdb.showPlayer == false then return nil end
        return _G.CorpUIPlayerFrame
    end
    if fdb.showTarget == false then return nil end
    return _G.CorpUITargetFrame
end

local function frameScale()
    local fdb = ns.root and ns.root.frames
    return (fdb and fdb.scale) or 1
end

-- Sur la plaque de nom de la cible ("plate", 06/10) : nos cases sont alors
-- cachees et le module Plaques montre les siennes (ns.ComboForPlate) ;
-- plaques CorpUI coupees : repli au-dessus du cadre cible
local function plateMode()
    return db.comboPos == "plate" and ns.PlatesActive ~= nil and ns.PlatesActive()
end

local function placeMode()
    if db.comboPos == "plate" then return "target_above" end
    return db.comboPos
end

-- position libre : demandee, ou cadre d accroche absent / masque
local function comboFree()
    local key = placeMode():match("^(%a+)_")
    return not key or not unitFrame(key)
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

local function makeSpark(parent)
    local o = CreateFrame("Frame", nil, parent)
    o:SetAllPoints()
    o:SetFrameLevel((parent:GetFrameLevel() or 1) + 4)
    local t = o:CreateTexture(nil, "OVERLAY")
    t:SetTexture(SPARK)
    t:SetBlendMode("ADD")
    t:SetSize(12, 16)
    o.spark = t
    o:Hide()
    return o
end

-- etincelle a la fraction f (0..1) de la barre
local function setSpark(o, f, alpha)
    local w = o:GetWidth() or 0
    local h = o:GetHeight() or 0
    o.spark:SetHeight(math.max(8, h * 2.4))
    o.spark:ClearAllPoints()
    o.spark:SetPoint("CENTER", o, "LEFT", w * f, 0)
    o.spark:SetAlpha(alpha or 1)
    o:Show()
end

local function layoutBoxes()
    if not combo then return end
    local gap = 3
    local w = combo:GetWidth() or 0
    local h = combo:GetHeight() or 0
    local bw = math.max(2, (w - gap * (MAX_POINTS - 1)) / MAX_POINTS)
    for i, b in ipairs(combo.boxes) do
        b:ClearAllPoints()
        b:SetSize(bw, h)
        b:SetPoint("TOPLEFT", combo, "TOPLEFT", (i - 1) * (bw + gap), 0)
    end
end

local function buildCombo()
    combo = CreateFrame("Frame", "CorpUIComboPoints", UIParent)
    combo:SetSize(db.comboWidth, db.comboHeight)
    combo:SetClampedToScreen(true)
    combo.boxes = {}
    for i = 1, MAX_POINTS do
        local b = CreateFrame("StatusBar", nil, combo)
        b:SetStatusBarTexture(ns.BAR_TEXTURE)
        ns.UI.Skin(b, 0.85)
        -- case i pleine des que les points atteignent i (le client compare)
        b:SetMinMaxValues(i - 1, i)
        b:SetValue(i - 1)
        local c = (i == MAX_POINTS) and ns.COLORS.violet or ns.COLORS.gold
        b:SetStatusBarColor(c[1], c[2], c[3])
        combo.boxes[i] = b
    end
    combo:SetScript("OnSizeChanged", layoutBoxes)
    combo.mover = ns.UI.Mover(combo, db.comboFree, L.RES_COMBO)
    combo:Hide()
    layoutBoxes()
end

local function buildDruid()
    druidBar = CreateFrame("StatusBar", "CorpUIDruidMana", UIParent)
    druidBar:SetStatusBarTexture(ns.BAR_TEXTURE)
    druidBar:SetHeight(db.druidManaHeight)
    ns.UI.Skin(druidBar, 0.85)
    local c = PowerBarColor and PowerBarColor.MANA
    if c and c.r then
        druidBar:SetStatusBarColor(c.r, c.g, c.b)
    else
        druidBar:SetStatusBarColor(0, 0.44, 0.87)
    end
    druidBar:SetMinMaxValues(0, 1)
    druidBar:SetValue(1)
    druidBar:Hide()
    druidSpark = makeSpark(druidBar)
end

-- etincelles sur la barre de puissance du cadre joueur (une seule fois)
local function attachSparks()
    if energySpark then return end
    local f = _G.CorpUIPlayerFrame
    if not f or not f.pw then return end
    energySpark = makeSpark(f.pw)
    manaSpark = makeSpark(f.pw)
end

---------------------------------------------------------------------------
-- Placement (hors combat)
---------------------------------------------------------------------------

local function placeDruid()
    local f = unitFrame("player")
    druidBar:ClearAllPoints()
    druidBar:SetHeight(db.druidManaHeight)
    if f then
        druidBar:SetParent(f)
        druidBar:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -4)
        druidBar:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -4)
        druidBar.attached = true
    else
        druidBar:SetParent(UIParent)
        druidBar.attached = false
    end
end

local function placeCombo()
    local mode = placeMode()
    local key = mode:match("^(%a+)_")
    local f = key and unitFrame(key)
    combo:ClearAllPoints()
    if f then
        combo:SetParent(f)
        combo:SetScale(1)
        combo:SetHeight(db.comboHeight)
        if mode:match("_above$") then
            combo:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 4)
            combo:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 4)
        else
            -- druide : sous sa barre de mana (toujours affichee en felin) ;
            -- cible : sous sa barre de sort si elle y est accrochee
            local anchor = f
            if key == "player" and class == "DRUID" and db.druidMana and druidBar.attached then anchor = druidBar end
            if key == "target" and ns.CastBarAttached and ns.CastBarAttached("target") and _G.CorpUICastBartarget then
                anchor = _G.CorpUICastBartarget
            end
            combo:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
            combo:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
        end
    else
        combo:SetParent(UIParent)
        combo:SetScale(frameScale())
        combo:SetSize(db.comboWidth, db.comboHeight)
        ns.ApplyPos(combo, db.comboFree)
    end
    layoutBoxes()
end

---------------------------------------------------------------------------
-- Mises a jour
---------------------------------------------------------------------------

-- cases accrochees au cadre key, cote side ("above" / "below") : les
-- auras de la cible se placent au-dela
function ns.ComboOn(key, side)
    if not (db and combo and db.combo and placeMode() == key .. "_" .. side) then return nil end
    if plateMode() then return nil end
    if not (class == "ROGUE" or class == "DRUID") then return nil end
    return unitFrame(key) and combo or nil
end

-- pour les plaques : montrer les cases sur la plaque de la cible ? et le
-- nombre de points (peut etre secret : passe tel quel aux barres)
function ns.ComboForPlate()
    if not (db and db.combo and plateMode() and comboRelevant()) then return false end
    local cp = comboPoints()
    if db.comboAlways or issecret(cp) then return true, cp end
    local n = num(cp)
    return (n ~= nil and n > 0) or inCombat(), cp
end

local function updateComboFrame()
    if not combo then return end
    if plateMode() then
        combo:Hide()
        if combo.mover then combo.mover:SetShown(false) end
        return
    end
    local free = comboFree()
    local preview = ns.moversShown and free and db.combo
    if combo.mover then combo.mover:SetShown(preview and true or false) end
    if not db.combo or not (comboRelevant() or preview) then
        combo:Hide()
        return
    end
    local cp = comboPoints()
    local fed = true
    for _, b in ipairs(combo.boxes) do
        if not pcall(b.SetValue, b, cp or 0) then fed = false end
    end
    if preview then
        combo:Show()
        return
    end
    -- toujours visibles (voleur, felin) : cases vides sans points
    if db.comboAlways then
        combo:Show()
        return
    end
    if not fed or not flag(UnitExists, "target") then
        combo:Hide()
        return
    end
    local n = num(cp)
    -- secret : cases toujours la (le client les remplit) ; sinon seulement
    -- avec des points ou en combat
    combo:SetShown(n == nil or n > 0 or inCombat())
end

local function updateCombo()
    updateComboFrame()
    -- les plaques suivent (cases sur la plaque de la cible, ou retirees)
    if ns.PlatesComboUpdate then ns.PlatesComboUpdate() end
end

local function updateDruid()
    if not druidBar then return end
    local show = db.druidMana and class == "DRUID" and st.pt ~= nil and st.pt ~= MANA and druidBar.attached
    druidBar:SetShown(show and true or false)
    if not show then return end
    local cur = call(UnitPower, "player", MANA)
    local max = call(UnitPowerMax, "player", MANA)
    -- valeurs passees telles quelles (la barre accepte les secrets)
    if not (pcall(druidBar.SetMinMaxValues, druidBar, 0, max) and pcall(druidBar.SetValue, druidBar, cur)) then
        druidBar:Hide()
    end
end

local function refreshPowerType()
    local pt = powerType()
    if pt ~= st.pt then
        st.pt = pt
        -- autre ressource : les calages precedents ne valent plus
        st.energyLast, st.energyMax = nil, nil
    end
end

local function readPower(kind)
    local cur = num(call(UnitPower, "player", kind))
    local max = num(call(UnitPowerMax, "player", kind))
    return cur, max
end

local function onEnergy()
    local cur, max = readPower(ENERGY)
    local last = st.energyLast
    if cur and last and cur > last then
        local d = cur - last
        -- un tick rend 20 (40 sous Poussee d adrenaline) ; un tick tronque
        -- au plafond rend moins. Le reste (Coups impitoyables, the...) ne cale pas.
        if (d >= 19 and d <= 21) or (d >= 39 and d <= 41) or (max and cur >= max and d < 21) then
            st.energyTickAt = GetTime()
        end
    end
    st.energyLast, st.energyMax = cur, max
end

local function onMana()
    local cur, max = readPower(MANA)
    local last = st.manaLast
    local now = GetTime()
    if cur and last then
        if cur < last then
            st.lastDrop = now
            -- depense juste apres un sort lance : debut de la regle des 5 s
            if st.lastCast and now - st.lastCast < 0.5 then st.fiveStart = st.lastCast end
        elseif cur > last then
            -- regen (pas une potion ni une gemme : gros gain)
            if not max or (cur - last) <= max * 0.15 then st.manaTickAt = now end
        end
    end
    st.manaLast, st.manaMax = cur, max
end

-- le sort coute-t-il du mana ? (C_Spell.GetSpellPowerCost, lu sous pcall)
local function costsMana(spellID)
    if not readable(spellID) then return false end
    local fn = (C_Spell and C_Spell.GetSpellPowerCost) or GetSpellPowerCost
    local costs = call(fn, spellID)
    if type(costs) ~= "table" then return false end
    for _, c in ipairs(costs) do
        local ok, yes = pcall(function() return c.type == MANA and (c.cost or 0) > 0 end)
        if ok and not issecret(yes) and yes then return true end
    end
    return false
end

local function onCast(spellID)
    local now = GetTime()
    st.lastCast = now
    if costsMana(spellID) or (st.lastDrop and now - st.lastDrop < 0.5) then st.fiveStart = now end
end

-- etincelles, a chaque image
local function updateSparks()
    local now = GetTime()
    -- energie
    if energySpark then
        local full = st.energyLast and st.energyMax and st.energyLast >= st.energyMax
        if db.energyTick and st.pt == ENERGY and st.energyTickAt and not full then
            setSpark(energySpark, ((now - st.energyTickAt) % TICK) / TICK)
        else
            energySpark:Hide()
        end
    end
    -- mana : barre du cadre joueur, ou barre du druide en forme
    local target
    if st.pt == MANA then
        target = manaSpark
    elseif druidBar and druidBar:IsShown() then
        target = druidSpark
    end
    if manaSpark and manaSpark ~= target then manaSpark:Hide() end
    if druidSpark and druidSpark ~= target then druidSpark:Hide() end
    if not target then return end
    if db.fiveSec and st.fiveStart and now - st.fiveStart < FIVE then
        target.spark:SetVertexColor(1, 1, 1)
        setSpark(target, (now - st.fiveStart) / FIVE, 1)
        return
    end
    local full = st.manaLast and st.manaMax and st.manaLast >= st.manaMax
    if db.manaTicks and st.manaTickAt and not full then
        target.spark:SetVertexColor(0.6, 0.85, 1)
        setSpark(target, ((now - st.manaTickAt) % TICK) / TICK, 0.7)
    else
        target:Hide()
    end
end

local function updateAll()
    refreshPowerType()
    onEnergy()
    onMana()
    updateDruid()
    updateCombo()
end

local function apply()
    if not db then return end
    if InCombatLockdown() then
        pending = true
        updateAll()
        return
    end
    pending = false
    attachSparks()
    if not combo then buildCombo() end
    if not druidBar then buildDruid() end
    placeDruid()
    placeCombo()
    if ns.AurasPlaceTarget then ns.AurasPlaceTarget() end
    updateAll()
end

---------------------------------------------------------------------------
-- Options (section du panneau Cadres)
---------------------------------------------------------------------------

function ns.BuildResourceOptions(win, y)
    local form = ns.UI.Form(win, y, function() apply() end)
    form:Header(L.RES_HEADER)
    form:Columns(2)
    local function check(text, key)
        form:Check(text, function() return db and db[key] end, function(v) if db then db[key] = v end end)
    end
    check(L.RES_OPT_COMBO, "combo")
    check(L.RES_OPT_COMBO_ALWAYS, "comboAlways")
    check(L.RES_OPT_ENERGY, "energyTick")
    check(L.RES_OPT_FIVE, "fiveSec")
    check(L.RES_OPT_MANATICK, "manaTicks")
    check(L.RES_OPT_DRUID, "druidMana")
    form:Cycle(L.RES_COMBO_POS, POSITIONS, {
        player_below = L.RES_POS_PLAYER_BELOW, player_above = L.RES_POS_PLAYER_ABOVE,
        target_below = L.RES_POS_TARGET_BELOW, target_above = L.RES_POS_TARGET_ABOVE, plate = L.RES_POS_PLATE,
        free = L.RES_POS_FREE,
    }, function() return db and db.comboPos end, function(v) if db then db.comboPos = v end end)
    local function number(fmt, key, lo, hi, step)
        form:Number(fmt, function() return db and db[key] or lo end, function(v)
            if db then db[key] = math.max(lo, math.min(hi, math.floor(v + 0.5))) end
        end, lo, hi, step)
    end
    number(L.RES_COMBO_HEIGHT, "comboHeight", 4, 20)
    number(L.RES_COMBO_WIDTH, "comboWidth", 60, 400, 5)
    number(L.RES_DRUID_HEIGHT, "druidManaHeight", 2, 12)
    form:EndColumns()
    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", win, "TOPLEFT", 8, form.y - 6)
    hint:SetWidth(420)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.RES_HINT)
    win:HookScript("OnShow", function() form:Refresh() end)
    form:Refresh()
    -- l aide (deux lignes) est sous le dernier reglage
    return form.y - 40
end

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, unit, arg2, arg3)
    if ns.ModuleOff("cadres", ev) then return end
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        if type(root.resources) ~= "table" then root.resources = {} end
        db = root.resources
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = v end
        end
        if type(db.comboFree) ~= "table" then db.comboFree = { point = "CENTER", x = 0, y = -230 } end
        local known = false
        for _, p in ipairs(POSITIONS) do if db.comboPos == p then known = true end end
        if not known then db.comboPos = DEFAULTS.comboPos end
        -- demande du 06/10 : points de combo sur la plaque de nom de la cible (une fois)
        if not db.comboOnPlate1 then
            db.comboOnPlate1 = true
            db.comboPos = "plate"
        end
        -- demande du 05/10 : les points de combo passent sur la cible (une fois)
        if not db.comboOnTarget2 then
            db.comboOnTarget2 = true
            if db.comboPos == "player_below" or db.comboPos == "target_below" then db.comboPos = "target_above" end
        end
        local _, c = UnitClass("player")
        class = readable(c) and c or nil
        -- apres la construction des cadres joueur et cible (meme evenement)
        C_Timer.After(0, apply)
        return
    end
    if not db or not combo then return end
    if event == "UNIT_POWER_FREQUENT" or event == "UNIT_POWER_UPDATE" then
        if unit ~= "player" then return end
        if arg2 == "ENERGY" then
            onEnergy()
        elseif arg2 == "MANA" then
            onMana()
            updateDruid()
        end
        updateCombo()
    elseif event == "UNIT_MAXPOWER" then
        if unit ~= "player" then return end
        updateAll()
    elseif event == "UNIT_DISPLAYPOWER" then
        if unit ~= "player" then return end
        updateAll()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if unit ~= "player" then return end
        onCast(arg3)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending then apply() else updateCombo() end
    else
        -- cible, forme, entree en jeu, entree en combat
        updateAll()
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "UPDATE_SHAPESHIFT_FORM",
                     "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
for _, e in ipairs({ "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
                     "UNIT_SPELLCAST_SUCCEEDED" }) do
    pcall(ev.RegisterUnitEvent, ev, e, "player")
end

ev:SetScript("OnUpdate", function()
    if db and combo then updateSparks() end
end)

-- deverrouillage de l interface, profils, reglages des cadres
ns.Listen(function()
    if not db then return end
    apply()
end)
