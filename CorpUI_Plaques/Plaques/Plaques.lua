--[[--------------------------------------------------------------------------
    CorpUI - module Barres de vie (plaques au-dessus des unites)
    Nos propres barres sur les plaques du jeu : nom, vie (couleur de classe,
    de reaction ou du theme), pourcentage, sort en cours, debuffs sur l unite,
    cible actuelle mise en avant.

    Les plaques restent celles du moteur (position, clic, empilement) : on
    pose notre cadre dessus et on rend transparent le cadre d unite de
    Blizzard qu elles contiennent (SetAlpha, pas de crochet, pas d ecriture
    dans ses tables). Plaques interdites aux addons (IsForbidden) : ignorees.
    L echelle de la cible s applique a NOTRE cadre, jamais a la plaque.

    Valeurs secretes : la vie va telle quelle dans la barre, le texte passe
    par UnitHealthPercent ; la menace par plaque est secrete sur ce client
    (verifie le 20/09) : la couleur de menace ne s applique que si la valeur
    lue est lisible (en pratique via "target", donc sur la cible seulement).
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local UF = ns.UF

local issecret = issecretvalue or function() return false end

local MAX_DEBUFFS = 10   -- icones creees par plaque (le reglage en montre moins)
local COMBO_H = 5        -- points de combo sur la plaque de la cible

local db
local active = {}     -- unite ("nameplate3") -> notre cadre
local pool = {}

-- etat de la menace vue par le client : nil (pas encore lue), "ok", "secret"
local threatSeen = { plate = nil, target = nil }

local THREAT_COLORS = {
    [1] = { 1, 0.85, 0.1 },    -- bientot l aggro
    [2] = { 1, 0.5, 0 },       -- aggro, mais un autre te depasse
    [3] = { 1, 0.25, 0.65 },   -- tu as l aggro
}

local function isNil(v)
    local ok, r = pcall(function() return v == nil end)
    return ok and r
end

local function setFont(fs, size, flags)
    local ok, file, _, fl = pcall(fs.GetFont, fs)
    if not ok or not file then return end
    pcall(fs.SetFont, fs, file, size, flags or fl)
end

---------------------------------------------------------------------------
-- Sort non interruptible et interruption prete (meme principe que le
-- module Incantations) : notInterruptible peut etre secret, il passe tel
-- quel a SetVertexColorFromBoolean / SetAlphaFromBoolean, jamais teste.
---------------------------------------------------------------------------

-- interruptions de classe (rang 1 : reste connu quand un rang plus haut l est)
local INTERRUPTS = {
    ROGUE = { 1766 },          -- Coup de pied
    WARRIOR = { 6552, 72 },    -- Volee de coups, Coup de bouclier
    SHAMAN = { 8042 },         -- Horion de terre
    MAGE = { 2139 },           -- Contresort
    PRIEST = { 15487 },        -- Silence (talent)
    DRUID = { 16979 },         -- Charge farouche (talent)
}
local RINGS = 2
local known = {}

local function scanInterrupts()
    for i = #known, 1, -1 do known[i] = nil end
    local ok, _, class = pcall(UnitClass, "player")
    if not ok or issecret(class) or not INTERRUPTS[class] then return end
    for _, id in ipairs(INTERRUPTS[class]) do
        local okK, k = pcall(IsPlayerSpell or IsSpellKnown, id)
        if okK and not issecret(k) and k and #known < RINGS then table.insert(known, id) end
    end
end

-- "prete" par interruption connue (booleen, secret possible) : recharge
-- sans le temps global, IsZero = prete ; repli sur la recharge lisible
local function readyStates()
    local out = {}
    for i, id in ipairs(known) do
        local v = false
        local okD, d = false, nil
        if C_Spell and C_Spell.GetSpellCooldownDuration then okD, d = pcall(C_Spell.GetSpellCooldownDuration, id, true) end
        if okD and isNil(d) then
            v = true
        elseif okD then
            local okZ, z = pcall(d.IsZero, d)
            if okZ then v = z end
        elseif C_Spell and C_Spell.GetSpellCooldown then
            local okC, r = pcall(function()
                local c = C_Spell.GetSpellCooldown(id)
                return c.startTime == 0 or c.duration <= 1.5
            end)
            if okC then v = r end
        end
        out[i] = v
    end
    return out
end

local function alphaFrom(r, v, a1, a0)
    if issecret(v) then
        if not (r.SetAlphaFromBoolean and pcall(r.SetAlphaFromBoolean, r, v, a1, a0)) then r:SetAlpha(0) end
    else
        r:SetAlpha(v and a1 or a0)
    end
end

local STEEL = { 0.45, 0.5, 0.58 }
local CAST_COLOR = { 1, 0.7, 0.1 }
local CHANNEL_COLOR = { 0.3, 0.85, 0.3 }
local colorObj = {}
local function cobj(c)
    if not CreateColor then return nil end
    colorObj[c] = colorObj[c] or CreateColor(c[1], c[2], c[3], 1)
    return colorObj[c]
end

-- couleur normale, ou gris acier + bouclier si le sort est non interruptible
local function paintLock(sb, shield, notInt, c, enabled)
    sb:SetStatusBarColor(c[1], c[2], c[3])
    local tex = sb.GetStatusBarTexture and sb:GetStatusBarTexture()
    if tex then pcall(tex.SetVertexColor, tex, c[1], c[2], c[3], 1) end
    if not enabled or isNil(notInt) then shield:SetAlpha(0) return end
    if issecret(notInt) then
        local a, b = cobj(STEEL), cobj(c)
        if not (tex and a and b and tex.SetVertexColorFromBoolean and pcall(tex.SetVertexColorFromBoolean, tex, notInt, a, b)) then
            shield:SetAlpha(0) return
        end
    elseif notInt then
        sb:SetStatusBarColor(STEEL[1], STEEL[2], STEEL[3])
        if tex then pcall(tex.SetVertexColor, tex, STEEL[1], STEEL[2], STEEL[3], 1) end
    end
    alphaFrom(shield, notInt, 1, 0)
end

-- liseré vert de 2 px autour de target
local function makeRing(parent, target)
    local e = CreateFrame("Frame", nil, parent)
    e:SetAllPoints(target)
    local function side(p1, r1, x1, y1, p2, r2, x2, y2)
        local t = e:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(0.2, 1, 0.3, 1)
        t:SetPoint(p1, e, r1, x1, y1)
        t:SetPoint(p2, e, r2, x2, y2)
        return t
    end
    side("BOTTOMLEFT", "TOPLEFT", -2, 0, "BOTTOMRIGHT", "TOPRIGHT", 2, 0):SetHeight(2)
    side("TOPLEFT", "BOTTOMLEFT", -2, 0, "TOPRIGHT", "BOTTOMRIGHT", 2, 0):SetHeight(2)
    side("TOPRIGHT", "TOPLEFT", 0, 0, "BOTTOMRIGHT", "BOTTOMLEFT", 0, 0):SetWidth(2)
    side("TOPLEFT", "TOPRIGHT", 0, 0, "BOTTOMLEFT", "BOTTOMRIGHT", 0, 0):SetWidth(2)
    return e
end

-- cadre "interruptible" (alpha 0 si non interruptible) et un liseré par
-- interruption (alpha 1 si prete) : alphas multiplies, liserés superposes
local function makeReady(host, target)
    local intr = CreateFrame("Frame", nil, host)
    intr:SetAllPoints(target)
    intr:SetFrameLevel(host:GetFrameLevel() + 4)
    intr.rings = {}
    for i = 1, RINGS do intr.rings[i] = makeRing(intr, target) end
    intr:SetAlpha(0)
    return intr
end

local function applyReady(intr, notInt, states)
    if not states or #known == 0 then intr:SetAlpha(0) return end
    if isNil(notInt) then intr:SetAlpha(1) else alphaFrom(intr, notInt, 0, 1) end
    for i, ring in ipairs(intr.rings) do
        if i > #states then ring:SetAlpha(0) else alphaFrom(ring, states[i], 1, 0) end
    end
end

---------------------------------------------------------------------------
-- Construction d une barre
---------------------------------------------------------------------------

-- reglage du conteneur de debuffs d une plaque
local function plateSpec(f)
    local size = db.debuffSize
    local up = (not db.textInside and (db.showName or db.showLevel)) and (db.nameSize + 6) or 3
    return {
        width = size, height = math.floor(size * 0.78 + 0.5), spacing = 2,
        perRow = db.debuffMax, max = db.debuffMax, grow = "up", fromRight = false,
        time = db.debuffTimer and "native" or "none",
        countSize = math.max(7, math.floor(size * 0.5 + 0.5)),
        anchor = { f, "TOPLEFT", 0, up },
        groups = {
            { key = "debuffs", filter = "HARMFUL",
              candidate = db.debuffMine and { isFromPlayerOrPlayerPet = true } or {} },
        },
    }
end

local function makePlate()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(db.width, db.height)
    f:EnableMouse(false)

    f.hp = UF.Bar(f, db.height)
    f.hp:SetAllPoints()
    ns.UI.Skin(f.hp, 0.9)
    f.border = f.hp.cuiBorder

    -- nom au-dessus a gauche, niveau au-dessus a droite
    f.level = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.level:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 2)
    f.name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.name:SetJustifyH("LEFT")
    f.name:SetWordWrap(false)

    f.pct = f.hp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.pct:SetPoint("CENTER", 0, 0)
    f.pct:SetFont(f.pct:GetFont(), 8, "OUTLINE")

    -- cible actuelle : fleches dorees de part et d autre
    local C = ns.COLORS
    f.arrowL = f:CreateTexture(nil, "OVERLAY")
    f.arrowL:SetPoint("RIGHT", f, "LEFT", -3, 0)
    f.arrowL:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    f.arrowR = f:CreateTexture(nil, "OVERLAY")
    f.arrowR:SetPoint("LEFT", f, "RIGHT", 3, 0)
    f.arrowR:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)

    -- sort en cours, sous la vie
    f.cast = UF.Bar(f, 7)
    f.cast:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -3)
    f.cast:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -3)
    ns.UI.Skin(f.cast, 0.9)
    f.castText = f.cast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.castText:SetPoint("TOP", f.cast, "BOTTOM", 0, -1)
    f.castText:SetFont(f.castText:GetFont(), 8, "OUTLINE")
    f.castIcon = f.cast:CreateTexture(nil, "ARTWORK")
    f.castIcon:SetPoint("BOTTOMRIGHT", f.cast, "BOTTOMLEFT", -3, 0)
    f.castIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- non interruptible : bouclier ; interruption prete : liseré vert
    f.castShield = f.cast:CreateTexture(nil, "OVERLAY", nil, 2)
    if not pcall(f.castShield.SetAtlas, f.castShield, "nameplates-InterruptShield") then
        f.castShield:SetTexture("Interface\\Icons\\INV_Shield_06")
    end
    f.castShield:SetAlpha(0)
    f.castReady = makeReady(f.cast, f.cast)
    f.cast:Hide()

    -- points de combo (plaque de la cible, position "plaque" du module
    -- Ressources) : 5 cases sous la vie, la barre de sort passe dessous.
    -- Bornes (i - 1, i) : le nombre de points, meme secret, va tel quel
    f.combo = CreateFrame("Frame", nil, f)
    f.combo:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -2)
    f.combo:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -2)
    f.combo:SetHeight(COMBO_H)
    f.combo.boxes = {}
    for i = 1, 5 do
        local b = CreateFrame("StatusBar", nil, f.combo)
        b:SetStatusBarTexture(ns.BAR_TEXTURE)
        ns.UI.Skin(b, 0.85)
        b:SetMinMaxValues(i - 1, i)
        b:SetValue(i - 1)
        local c = (i == 5) and C.violet or C.gold
        b:SetStatusBarColor(c[1], c[2], c[3])
        f.combo.boxes[i] = b
    end
    f.combo:SetScript("OnSizeChanged", function(self)
        local w = self:GetWidth() or 0
        local bw = math.max(2, (w - 2 * 4) / 5)
        for i, b in ipairs(self.boxes) do
            b:ClearAllPoints()
            b:SetSize(bw, COMBO_H)
            b:SetPoint("TOPLEFT", self, "TOPLEFT", (i - 1) * (bw + 2), 0)
        end
    end)
    f.combo:Hide()

    -- debuffs sur l unite, au-dessus du nom
    f.debuffs = {}
    for i = 1, MAX_DEBUFFS do
        local b = CreateFrame("Frame", nil, f)
        ns.UI.Skin(b, 1)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b.icon:SetTexCoord(0.08, 0.92, 0.2, 0.8)
        b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
        b.cd:SetAllPoints()
        b.cd:SetReverse(true)
        b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        b.count:SetPoint("BOTTOMRIGHT", 2, -2)
        b:Hide()
        f.debuffs[i] = b
    end
    -- debuffs par le conteneur du client (lisibles en combat), unite posee
    -- a l accroche ; nos icones ne servent que s il n existe pas
    if ns.NativeAuras then f.native = ns.NativeAuras(f, "none", plateSpec(f)) end
    f:Hide()
    return f
end

-- tailles et elements visibles selon les reglages : refaits seulement si
-- un reglage a change depuis (layoutVer : scanAll, changements generaux)
local layoutVer = 1
local function layout(f)
    if f.layoutVer == layoutVer then return end
    f.layoutVer = layoutVer
    if f.native then
        local sig = table.concat({ db.debuffSize, db.debuffMax, tostring(db.debuffMine), tostring(db.debuffTimer),
            tostring(db.showName), tostring(db.showLevel), db.nameSize }, ":")
        if f.nativeSig ~= sig then
            f.nativeSig = sig
            f.native:Apply(plateSpec(f))
        end
    end
    local h = db.height
    f:SetSize(db.width, h)
    f.hp:SetHeight(h)
    f.arrowL:SetSize(4, h + 6)
    f.arrowR:SetSize(4, h + 6)

    -- nom et niveau : au-dessus de la barre, ou dedans (niveau et nom a
    -- gauche, pourcentage a droite ; textes portes par la barre pour
    -- passer devant son remplissage)
    f.name:SetShown(db.showName)
    f.level:SetShown(db.showLevel)
    f.name:ClearAllPoints()
    f.level:ClearAllPoints()
    f.pct:ClearAllPoints()
    if db.textInside then
        f.name:SetParent(f.hp)
        f.level:SetParent(f.hp)
        setFont(f.name, db.nameSize, "OUTLINE")
        setFont(f.level, db.nameSize, "OUTLINE")
        setFont(f.pct, db.nameSize, "OUTLINE")
        f.pct:SetPoint("RIGHT", f.hp, "RIGHT", -3, 0)
        f.level:SetPoint("LEFT", f.hp, "LEFT", 3, 0)
        if db.showLevel then
            f.name:SetPoint("LEFT", f.level, "RIGHT", 3, 0)
        else
            f.name:SetPoint("LEFT", f.hp, "LEFT", 3, 0)
        end
        f.name:SetPoint("RIGHT", f.pct, "LEFT", -3, 0)
    else
        f.name:SetParent(f)
        f.level:SetParent(f)
        setFont(f.name, db.nameSize, "")
        setFont(f.level, db.nameSize, "")
        setFont(f.pct, 8, "OUTLINE")
        f.pct:SetPoint("CENTER", 0, 0)
        f.level:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 2)
        f.name:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 2)
        if db.showLevel then
            f.name:SetPoint("RIGHT", f.level, "LEFT", -3, 0)
        else
            f.name:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 2)
        end
    end

    -- barre de sort
    f.cast:SetHeight(db.castHeight)
    setFont(f.castText, db.castTextSize, "OUTLINE")
    local icon = h + db.castHeight + 3
    f.castIcon:SetSize(icon, icon)
    f.castIcon:SetShown(db.castIcon)
    -- bouclier sur l icone du sort, sinon a gauche de la barre de sort
    local sh = db.castHeight + 6
    f.castShield:SetSize(math.floor(sh * 0.8 + 0.5), sh)
    f.castShield:ClearAllPoints()
    if db.castIcon then f.castShield:SetPoint("CENTER", f.castIcon, "CENTER")
    else f.castShield:SetPoint("RIGHT", f.cast, "LEFT", -2, 0) end

    -- debuffs : rangee au-dessus du nom (ou de la barre si pas de texte)
    local size = db.debuffSize
    local bh = math.floor(size * 0.78 + 0.5)
    local up = (not db.textInside and (db.showName or db.showLevel)) and (db.nameSize + 6) or 3
    for i, b in ipairs(f.debuffs) do
        b:SetSize(size, bh)
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", f, "TOPLEFT", (i - 1) * (size + 2), up)
        -- decompte natif du client (chiffres sur l icone)
        pcall(b.cd.SetHideCountdownNumbers, b.cd, not db.debuffTimer)
        local okF, fs = pcall(b.cd.GetCountdownFontString, b.cd)
        if okF and type(fs) == "table" then setFont(fs, math.max(7, math.floor(size * 0.45 + 0.5)), "OUTLINE") end
        setFont(b.count, math.max(7, math.floor(size * 0.5 + 0.5)), "OUTLINE")
    end
end

---------------------------------------------------------------------------
-- Couleurs et menace
---------------------------------------------------------------------------

-- menace du joueur sur une unite, seulement si le client la rend lisible
local function readThreat(u, slot)
    if not UnitThreatSituation then return nil end
    local ok, s = pcall(UnitThreatSituation, "player", u)
    if not ok then return nil end
    if issecret(s) then
        threatSeen[slot] = "secret"
        return nil
    end
    if type(s) == "number" then
        threatSeen[slot] = "ok"
        return s
    end
end

local function threatOf(f)
    local s = readThreat(f.unit, "plate")
    if s == nil and f.isTarget then s = readThreat("target", "target") end
    return s
end

-- etat affiche dans le panneau
local function threatState()
    if not UnitThreatSituation then return "none" end
    if threatSeen.plate == "ok" then return "all" end
    if threatSeen.target == "ok" then return "target" end
    if threatSeen.plate == "secret" and threatSeen.target == "secret" then return "none" end
    return "unknown"
end

local function reactionColor(u)
    local ok, r = pcall(UnitReaction, u, "player")
    if ok and not issecret(r) and type(r) == "number" then
        if r <= 3 then return 0.8, 0.15, 0.15 end
        if r == 4 then return 0.9, 0.8, 0.1 end
    end
    return 0.2, 0.75, 0.25
end

local function healthColor(f)
    local u = f.unit
    if db.tapped and UF.Flag(UnitIsTapDenied, u) then return 0.5, 0.5, 0.5 end
    if db.threat then
        local s = threatOf(f)
        local c = s and THREAT_COLORS[s]
        if c then return c[1], c[2], c[3] end
    end
    if db.colorMode == "theme" then
        local c = ns.COLORS.violet
        return c[1], c[2], c[3]
    end
    if db.colorMode == "class" and UF.Flag(UnitIsPlayer, u) then
        local ok, _, class = pcall(UnitClass, u)
        if ok and not issecret(class) and type(class) == "string" and ns.ClassColor then return ns.ClassColor(class) end
    end
    return reactionColor(u)
end

---------------------------------------------------------------------------
-- Mises a jour
---------------------------------------------------------------------------

local function updateColor(f)
    f.hp:SetStatusBarColor(healthColor(f))
end

local function updateHealth(f)
    local u = f.unit
    local okC, cur = pcall(UnitHealth, u)
    local okM, max = pcall(UnitHealthMax, u)
    if okC and okM then UF.SetBar(f.hp, cur, max) end
    if db.percent then UF.SetText(f.pct, u, "health", cur, max, "pct") else f.pct:SetText("") end
    updateColor(f)
end

local function updateName(f)
    local u = f.unit
    if db.showName then
        local ok, name = pcall(UnitName, u)
        if not ok or not pcall(f.name.SetText, f.name, name or "") then f.name:SetText("") end
    else
        f.name:SetText("")
    end
    local okL, lv = pcall(UnitLevel, u)
    if db.showLevel and okL and not issecret(lv) and type(lv) == "number" then
        f.level:SetText(lv > 0 and tostring(lv) or "??")
        local c = GetCreatureDifficultyColor and lv > 0 and GetCreatureDifficultyColor(lv)
        if c then f.level:SetTextColor(c.r, c.g, c.b) else f.level:SetTextColor(1, 0.3, 0.3) end
    else
        f.level:SetText("")
    end
end

-- points de combo sur la plaque de la cible ; la barre de sort se place dessous
local function updateCombo(f)
    local show, cp = false, nil
    if f.isTarget and ns.ComboForPlate then show, cp = ns.ComboForPlate() end
    if show then
        for _, b in ipairs(f.combo.boxes) do pcall(b.SetValue, b, cp or 0) end
    end
    if f.comboShown ~= (show and true or false) then
        f.comboShown = show and true or false
        f.combo:SetShown(f.comboShown)
        local anchor = f.comboShown and f.combo or f
        local gap = f.comboShown and -2 or -3
        f.cast:ClearAllPoints()
        f.cast:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, gap)
        f.cast:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, gap)
    end
end

function ns.PlatesActive() return db ~= nil and db.enabled == true end

-- appele par le module Ressources a chaque changement de points ou de reglage
function ns.PlatesComboUpdate()
    if not db then return end
    for _, f in pairs(active) do updateCombo(f) end
end

local function updateTarget(f)
    local ok, isTarget = pcall(UnitIsUnit, f.unit, "target")
    local on = (ok and not issecret(isTarget) and isTarget) and true or false
    f.isTarget = on
    local mark = on and db.targetBorder
    f.arrowL:SetShown(mark)
    f.arrowR:SetShown(mark)
    -- la cible devant, les autres un peu effacees quand on a une cible
    local okE, hasTarget = pcall(UnitExists, "target")
    hasTarget = okE and not issecret(hasTarget) and hasTarget
    f:SetAlpha((on or not hasTarget or not db.fadeOthers) and 1 or db.otherAlpha)
    -- echelle sur notre cadre seulement (centre sur la plaque : reste en place)
    f:SetScale(on and db.targetScale / 100 or 1)
    if f.plate then
        local okL, lvl = pcall(f.plate.GetFrameLevel, f.plate)
        if okL and type(lvl) == "number" then f:SetFrameLevel(lvl + (on and 15 or 5)) end
    end
    local C = ns.COLORS
    if mark then
        f.border:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    else
        ns.UI.ResetBorder(f.hp)
    end
    updateCombo(f)
end

local function updateDebuffs(f)
    if f.native then
        for _, b in ipairs(f.debuffs) do b:Hide() end
        -- conteneur du client : affiche / cache seulement si ca change, hors combat
        local want = db.debuffs and true or false
        if f.nativeShown ~= want and not InCombatLockdown() then
            f.nativeShown = want
            pcall(f.native.frame.SetShown, f.native.frame, want)
        end
        return
    end
    if not db.debuffs then
        for _, b in ipairs(f.debuffs) do b:Hide() end
        return
    end
    local max = math.min(MAX_DEBUFFS, db.debuffMax)
    -- par identifiants (lisibles meme en combat), "a moi" demande au client
    local n = 0
    for _, e in ipairs(ns.UnitAuraList(f.unit, "HARMFUL", db.debuffMine, max)) do
        n = n + 1
        local b, a, id = f.debuffs[n], e.aura, e.id
        if not pcall(function() b.icon:SetTexture(a.icon) end) then b.icon:SetTexture(nil) end
        local swept = false
        if C_UnitAuras.GetAuraDuration and b.cd.SetCooldownFromDurationObject and id then
            local okD, d = pcall(C_UnitAuras.GetAuraDuration, f.unit, id)
            swept = okD and d and pcall(b.cd.SetCooldownFromDurationObject, b.cd, d) or false
        end
        if not swept and not pcall(function()
            if a.duration and a.duration > 0 then b.cd:SetCooldown(a.expirationTime - a.duration, a.duration) else b.cd:Clear() end
        end) then b.cd:Clear() end
        if not pcall(b.count.SetText, b.count, ns.AuraCountText(f.unit, id, a)) then b.count:SetText("") end
        b:Show()
    end
    for i = n + 1, MAX_DEBUFFS do f.debuffs[i]:Hide() end
end

-- sort en cours : objet de duree du client (accepte les valeurs secretes)
-- releve du dernier sort vu (/reload puis SavedVariables) : quel chemin a servi
local function castNote(path)
    if db then db.castDiag = { path = path, at = date and date("%H:%M:%S") or "" } end
end

-- plaques dont la barre de sort avance par OnUpdate (debut et fin lisibles)
local fallback = {}

local function updateCast(f)
    fallback[f] = nil
    if not db.cast or (db.castTargetOnly and not f.isTarget) then f.cast:Hide() return end
    local u = f.unit
    local channel = false
    local ok, name, _, tex, startMS, endMS, _, _, notInt = pcall(UnitCastingInfo, u)
    if not ok or isNil(name) then
        channel = true
        ok, name, _, tex, startMS, endMS, _, notInt = pcall(UnitChannelInfo, u)
    end
    f.castStart, f.castEnd = nil, nil
    if not ok or isNil(name) then f.cast:Hide() return end
    -- 1) objet de duree du client (accepte les valeurs secretes)
    local durFn = channel and UnitChannelDuration or UnitCastingDuration
    local e = Enum and Enum.StatusBarTimerDirection
    local dir = e and (channel and e.RemainingTime or e.ElapsedTime)
    local timed = false
    if durFn and f.cast.SetTimerDuration then
        local okD, d = pcall(durFn, u)
        timed = okD and not isNil(d) and pcall(f.cast.SetTimerDuration, f.cast, d, nil, dir) or false
    end
    if timed then
        castNote("timer")
    elseif type(startMS) == "number" and type(endMS) == "number" and not issecret(startMS) and not issecret(endMS) then
        -- 2) repli : debut et fin lisibles, barre avancee par OnUpdate
        f.castStart, f.castEnd = startMS / 1000, endMS / 1000
        fallback[f] = true
        f.cast:SetMinMaxValues(0, 1)
        castNote("startend")
    else
        castNote(durFn and "noduration" or "nodurationapi")
        f.cast:Hide()
        return
    end
    f.castNotInt, f.castChannel = notInt, channel
    paintLock(f.cast, f.castShield, notInt, channel and CHANNEL_COLOR or CAST_COLOR, db.castLock)
    applyReady(f.castReady, notInt, db.castReady and readyStates() or nil)
    if not pcall(f.castIcon.SetTexture, f.castIcon, tex) then f.castIcon:SetTexture(nil) end
    if not pcall(f.castText.SetText, f.castText, name) then f.castText:SetText("") end
    f.cast:Show()
end

local function updateAll(f)
    updateTarget(f)   -- en premier : la menace et la barre de sort en dependent
    updateName(f)
    updateHealth(f)
    updateDebuffs(f)
    updateCast(f)
end

---------------------------------------------------------------------------
-- Plaques du moteur
---------------------------------------------------------------------------

local function blizzUnitFrame(plate)
    local ok, uf = pcall(function() return plate.UnitFrame end)
    if ok and type(uf) == "table" and uf.SetAlpha then return uf end
end

local function attach(unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
    if not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
    -- objet du monde (herbe, filon : plaque du ciblage doux, module Eclats) :
    -- la plaque du jeu garde son nom et son icone, pas de barre de vie
    if UnitIsGameObject then
        local okG, isObj = pcall(UnitIsGameObject, unit)
        if okG and isObj == true then return end
    end
    local f = table.remove(pool) or makePlate()
    f.unit, f.plate = unit, plate
    if f.native then f.native:SetUnit(unit) end
    f:SetParent(plate)
    f:ClearAllPoints()
    f:SetPoint("CENTER", plate, "CENTER", 0, 0)
    f:SetFrameLevel(plate:GetFrameLevel() + 5)
    layout(f)
    local uf = blizzUnitFrame(plate)
    if uf then uf:SetAlpha(0) end
    active[unit] = f
    updateAll(f)
    f:Show()
end

local function detach(unit)
    local f = active[unit]
    if not f then return end
    active[unit] = nil
    f:Hide()
    f:SetScale(1)
    f:SetParent(UIParent)
    f.unit, f.plate, f.isTarget = nil, nil, nil
    f.isTarget = false
    f.castStart = nil
    fallback[f] = nil
    updateCombo(f)
    if f.native then f.native:SetUnit("none") end
    table.insert(pool, f)
end

local function restoreAll()
    for unit in pairs(active) do
        local f = active[unit]
        local uf = f.plate and blizzUnitFrame(f.plate)
        if uf then uf:SetAlpha(1) end
        detach(unit)
    end
end

local function scanAll()
    layoutVer = layoutVer + 1
    restoreAll()
    if not db.enabled or not C_NamePlate then return end
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local ok, unit = pcall(function() return plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit) end)
        if ok and unit then attach(unit) end
    end
end

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
local UNIT_EVENTS = {
    UNIT_HEALTH = updateHealth, UNIT_MAXHEALTH = updateHealth, UNIT_FACTION = updateHealth,
    UNIT_NAME_UPDATE = updateName, UNIT_LEVEL = updateName,
    -- conteneur natif : le client le tient a jour (affiche ou cache a l accroche)
    UNIT_AURA = function(f) if not f.native then updateDebuffs(f) end end,
    UNIT_SPELLCAST_START = updateCast, UNIT_SPELLCAST_STOP = updateCast, UNIT_SPELLCAST_FAILED = updateCast,
    UNIT_SPELLCAST_INTERRUPTED = updateCast, UNIT_SPELLCAST_DELAYED = updateCast,
    UNIT_SPELLCAST_CHANNEL_START = updateCast, UNIT_SPELLCAST_CHANNEL_STOP = updateCast,
    UNIT_SPELLCAST_CHANNEL_UPDATE = updateCast,
}
-- menace : l unite de l evenement peut etre "target" : on recolore tout
local THREAT_EVENTS = { UNIT_THREAT_SITUATION_UPDATE = true, UNIT_THREAT_LIST_UPDATE = true }

local DEFAULTS = {
    enabled = true, cast = true, debuffs = true, percent = true,
    width = 120, height = 10, otherAlpha = 0.6,
    -- ajouts du 05/10 (vie, nom, sort, debuffs, cible)
    colorMode = "class", tapped = true, threat = false,
    showName = true, showLevel = true, nameSize = 10, textInside = false,
    castHeight = 7, castTextSize = 8, castIcon = true, castTargetOnly = false,
    castLock = true, castReady = true,   -- non interruptible, interruption prete
    debuffSize = 18, debuffMax = 5, debuffMine = true, debuffTimer = true,
    targetBorder = true, targetScale = 115, fadeOthers = true,
}

ev:SetScript("OnEvent", function(_, event, unit)
    if ns.ModuleOff("plaques", ev) then return end
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        root.plates = root.plates or {}
        db = root.plates
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = v end
        end
        scanInterrupts()
        return
    end
    if not db or not db.enabled then return end
    if event == "PLAYER_ENTERING_WORLD" then
        scanAll()
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        attach(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        detach(unit)
    elseif event == "PLAYER_TARGET_CHANGED" then
        for _, f in pairs(active) do
            updateTarget(f)
            updateColor(f)
            updateCast(f)
        end
    elseif event == "SPELLS_CHANGED" then
        scanInterrupts()
    elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        -- l etat change en cours de sort : le nom de l evenement suffit
        local f = unit and active[unit]
        if f and f.cast:IsShown() then
            f.castNotInt = event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE"
            paintLock(f.cast, f.castShield, f.castNotInt, f.castChannel and CHANNEL_COLOR or CAST_COLOR, db.castLock)
            applyReady(f.castReady, f.castNotInt, db.castReady and readyStates() or nil)
        end
    elseif THREAT_EVENTS[event] then
        if db.threat then
            for _, f in pairs(active) do updateColor(f) end
        end
    elseif unit and active[unit] and UNIT_EVENTS[event] then
        UNIT_EVENTS[event](active[unit])
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_TARGET_CHANGED",
                     "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "UNIT_SPELLCAST_INTERRUPTIBLE",
                     "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" }) do
    pcall(ev.RegisterEvent, ev, e)
end
for e in pairs(UNIT_EVENTS) do pcall(ev.RegisterEvent, ev, e) end
for e in pairs(THREAT_EVENTS) do pcall(ev.RegisterEvent, ev, e) end

-- le cadre de Blizzard peut reprendre son opacite : on le recoupe
-- et la recharge de l interruption est relue 10 fois par seconde (une
-- lecture pour toutes les plaques qui montrent un sort)
ev:SetScript("OnUpdate", function()
    if not next(fallback) or not db or not db.enabled then return end
    -- barres de sort en repli (debut / fin lisibles) : avancees a chaque image
    local now = GetTime()
    for f in pairs(fallback) do
        if not f.castStart then
            fallback[f] = nil
        elseif f.cast:IsShown() then
            local total = f.castEnd - f.castStart
            local p = total > 0 and (now - f.castStart) / total or 1
            if f.castChannel then p = 1 - p end
            f.cast:SetValue(math.max(0, math.min(1, p)))
            if now > f.castEnd + 0.3 then
                f.castStart = nil
                fallback[f] = nil
                f.cast:Hide()
            end
        end
    end
end)
ns.Every(0.1, function()
    if not db or not db.enabled or not next(active) then return end
    local states
    for _, f in pairs(active) do
        if f.cast:IsShown() then
            if db.castReady then states = states or readyStates() end
            applyReady(f.castReady, f.castNotInt, states)
        end
    end
end, "Plaques : interruption prete", "plaques")
ns.Every(0.2, function()
    if not db or not db.enabled then return end
    for _, f in pairs(active) do
        local uf = f.plate and blizzUnitFrame(f.plate)
        if uf and uf:GetAlpha() > 0 then uf:SetAlpha(0) end
    end
end, "Plaques : opacite du jeu", "plaques")

-- police ou theme changes : prochaines accroches refaites
ns.Listen(function() layoutVer = layoutVer + 1 end)

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------

local win

local function rebuild()
    -- la taille change : on refait les cadres
    restoreAll()
    for i = #pool, 1, -1 do pool[i] = nil end
    scanAll()
end

local function buildWindow()
    win = ns.UI.Window("CorpUIPlatesOptions", ns.TITLE .. " - " .. L.MOD_PLATES, nil, 440, 600)
    -- chaque reglage applique lui-meme son effet (les cases relisent les
    -- plaques, la taille les refait) : pas d onChange commun
    local form = ns.UI.Form(win, -34)
    local function chk(text, key)
        return form:Check(text, function() return db[key] end, function(v)
            db[key] = v
            scanAll()
        end)
    end
    local function num(fmt, key, lo, hi, step, again)
        return form:Number(fmt, function() return db[key] end, function(v)
            db[key] = v
            if again then rebuild() else scanAll() end
        end, lo, hi, step)
    end
    chk(L.PLATES_OPT_ENABLE, "enabled")

    -- vie
    form:Header(L.PLATES_H_HEALTH)
    form:Columns(2)
    form:Cycle(L.PLATES_COLOR, { "class", "reaction", "theme" }, {
        class = L.PLATES_COLOR_CLASS, reaction = L.PLATES_COLOR_REACTION, theme = L.PLATES_COLOR_THEME,
    }, function() return db.colorMode end, function(v) db.colorMode = v scanAll() end)
    form:Cell(44)
    num(L.PLATES_WIDTH, "width", 60, 240, 10, true)
    num(L.PLATES_HEIGHT, "height", 4, 24, 1, true)
    chk(L.PLATES_OPT_PERCENT, "percent")
    chk(L.PLATES_OPT_TAPPED, "tapped")
    local threatBox = chk(L.PLATES_OPT_THREAT, "threat")
    form:EndColumns()
    -- ce que le client laisse lire de la menace (relu a chaque affichage)
    local threatText = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    threatText:SetPoint("TOPLEFT", win, "TOPLEFT", 8, form.y - 2)
    threatText:SetPoint("TOPRIGHT", win, "TOPLEFT", 428, form.y - 2)
    threatText:SetHeight(26)
    threatText:SetJustifyH("LEFT")
    threatText:SetJustifyV("TOP")
    form.y = form.y - 30
    table.insert(form.refreshers, function()
        -- sondage : la cible et les plaques visibles
        readThreat("target", "target")
        for u in pairs(active) do readThreat(u, "plate") break end
        local st = threatState()
        threatText:SetText(L["PLATES_THREAT_" .. st:upper()])
        threatBox:SetAlpha(st == "none" and 0.45 or 1)
    end)

    -- nom
    form:Header(L.PLATES_H_NAME)
    form:Columns(2)
    chk(L.PLATES_OPT_NAME, "showName")
    chk(L.PLATES_OPT_INSIDE, "textInside")
    chk(L.PLATES_OPT_LEVEL, "showLevel")
    num(L.PLATES_TEXT_SIZE, "nameSize", 6, 18, 1)
    form:EndColumns()

    -- barre de sort
    form:Header(L.PLATES_H_CAST)
    form:Columns(2)
    chk(L.PLATES_OPT_CAST, "cast")
    chk(L.PLATES_OPT_CAST_TARGET, "castTargetOnly")
    chk(L.PLATES_OPT_CAST_ICON, "castIcon")
    chk(L.PLATES_OPT_CAST_LOCK, "castLock")
    chk(L.PLATES_OPT_CAST_READY, "castReady")
    form:Cell(26)
    num(L.PLATES_HEIGHT, "castHeight", 3, 20, 1)
    num(L.PLATES_TEXT_SIZE, "castTextSize", 6, 16, 1)
    form:EndColumns()

    -- debuffs
    form:Header(L.PLATES_H_DEBUFFS)
    form:Columns(2)
    chk(L.PLATES_OPT_DEBUFFS, "debuffs")
    chk(L.PLATES_OPT_DEBUFF_MINE, "debuffMine")
    chk(L.PLATES_OPT_DEBUFF_TIMER, "debuffTimer")
    form:Cell(26)
    num(L.PLATES_DEBUFF_SIZE, "debuffSize", 10, 36, 1)
    num(L.PLATES_DEBUFF_MAX, "debuffMax", 1, MAX_DEBUFFS, 1)
    form:EndColumns()

    -- cible
    form:Header(L.PLATES_H_TARGET)
    form:Columns(2)
    chk(L.PLATES_OPT_TARGET_BORDER, "targetBorder")
    chk(L.PLATES_OPT_FADE, "fadeOthers")
    num(L.PLATES_TARGET_SCALE, "targetScale", 100, 150, 5)
    form:Number(L.PLATES_OTHER_ALPHA, function() return math.floor(db.otherAlpha * 100 + 0.5) end, function(v)
        db.otherAlpha = v / 100
        scanAll()
    end, 10, 100, 5)
    form:EndColumns()
    -- points de combo : position "plaque" du module Ressources (meme reglage
    -- que la liste "Points de combo" du cadre Joueur)
    form:Check(L.PLATES_OPT_COMBO, function()
        local r = ns.root and ns.root.resources
        return r and r.comboPos == "plate"
    end, function(v)
        local r = ns.root and ns.root.resources
        if not r then return end
        r.comboPos = v and "plate" or "target_above"
        ns.Changed()
    end)

    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", win, "TOPLEFT", 8, form.y - 6)
    hint:SetWidth(420)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.PLATES_HINT)
    win:SetHeight(math.floor(90 - form.y))
    win:HookScript("OnShow", function() form:Refresh() end)
end

local function toggle()
    if not win then buildWindow() end
    ns.ShowPanel(win)
end

ns.RegisterModule({
    command = "plaques",
    alias = "nameplates",
    panelName = "CorpUIPlatesOptions",
    icon = "Interface\\Icons\\Ability_DualWield",
    title = function() return L.MOD_PLATES end,
    desc = function() return L.PLATES_DESC end,
    Slash = function() toggle() end,
    Open = toggle,
})
