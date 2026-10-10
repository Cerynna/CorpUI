--[[--------------------------------------------------------------------------
    CorpUI - module Incantations (barres de sort du joueur, de la cible et
    de la focalisation)
    Cadres ordinaires (non securises) : ils s affichent et se masquent
    librement, meme en combat.

    Progression : objet de duree du client (UnitCastingDuration /
    UnitChannelDuration + StatusBar:SetTimerDuration), qui anime la barre
    tout seul et accepte les valeurs secretes. Repli : debut et fin lisibles
    (UnitCastingInfo) et calcul a chaque image.
    Reglages par barre (db.conf[unite]) : accrochee sous son cadre d unite
    (elle le suit, sur toute sa largeur) ou libre avec sa poignee et sa
    largeur ; hauteur, icone, taille du texte, temps restant.
    "Deverrouiller l interface" (onglet General) affiche des barres
    d exemple pour placer les barres libres.
    Sort non interruptible : gris acier + bouclier ; cible et focalisation :
    liseré vert quand l interruption du joueur est prete (db.lockColor,
    db.interruptReady).
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local issecret = issecretvalue or function() return false end

local W, H = 230, 20
local COLORS = {
    cast        = { 1, 0.7, 0.1 },
    channel     = { 0.3, 0.85, 0.3 },
    interrupted = { 0.85, 0.15, 0.15 },
}

local db
local bars = {}

-- unite, cadre d unite de CorpUI (Cadres.lua), position libre, libelle
local UNITS = {
    { unit = "player", frame = "CorpUIPlayerFrame", pos = "playerPos", label = "CAST_PLAYER",
      def = { point = "CENTER", x = -260, y = -240 } },
    { unit = "target", frame = "CorpUITargetFrame", pos = "targetPos", label = "CAST_TARGET",
      def = { point = "CENTER", x = 260, y = -300 } },
    { unit = "focus", frame = "CorpUIFocusFrame", pos = "focusPos", label = "CAST_FOCUS",
      def = { point = "CENTER", x = -260, y = -130 } },
}
local UNIT_FRAMES = {}
for _, u in ipairs(UNITS) do UNIT_FRAMES[u.unit] = u.frame end

local function conf(unit) return db.conf[unit] end

-- "rien" sans risque : une valeur secrete existe, mais la comparer peut lever
local function isNil(v)
    local ok, r = pcall(function() return v == nil end)
    return ok and r
end

---------------------------------------------------------------------------
-- Sort non interruptible et interruption prete
-- notInterruptible peut etre secret : jamais teste, il passe tel quel a
-- SetVertexColorFromBoolean (couleur de la barre) et SetAlphaFromBoolean
-- (bouclier, liseré vert). Lisible : simple test.
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
local RINGS = 2                -- liserés par barre : un par interruption connue
local known = {}               -- interruptions apprises par le joueur

local function scanInterrupts()
    for i = #known, 1, -1 do known[i] = nil end
    local ok, _, class = pcall(UnitClass, "player")
    if not ok or issecret(class) or not INTERRUPTS[class] then return end
    for _, id in ipairs(INTERRUPTS[class]) do
        local okK, k = pcall(IsPlayerSpell or IsSpellKnown, id)
        if okK and not issecret(k) and k and #known < RINGS then table.insert(known, id) end
    end
end

-- etat "prete" de chaque interruption connue (booleen, secret possible) :
-- objet de duree de la recharge sans le temps global, IsZero = prete
local function readyStates()
    local out = {}
    for i, id in ipairs(known) do
        local v = false
        local okD, d = false, nil
        if C_Spell and C_Spell.GetSpellCooldownDuration then okD, d = pcall(C_Spell.GetSpellCooldownDuration, id, true) end
        if okD and isNil(d) then
            v = true                                -- connue et sans recharge
        elseif okD then
            local okZ, z = pcall(d.IsZero, d)
            if okZ then v = z end
        elseif C_Spell and C_Spell.GetSpellCooldown then
            -- repli : recharge lisible (hors combat surtout)
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

-- alpha selon un booleen, secret ou non ; echec avec un secret : masque
local function alphaFrom(r, v, a1, a0)
    if issecret(v) then
        if not (r.SetAlphaFromBoolean and pcall(r.SetAlphaFromBoolean, r, v, a1, a0)) then r:SetAlpha(0) end
    else
        r:SetAlpha(v and a1 or a0)
    end
end

local STEEL = { 0.45, 0.5, 0.58 }    -- gris acier, comme ElvUI
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

-- liseré vert de 2 px autour de target (sur son liseré de 1 px)
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

-- cadre "interruptible" (alpha 0 si non interruptible) et ses liserés, un
-- par interruption (alpha 1 si prete) : les alphas se multiplient, les
-- liserés se superposent (l une OU l autre prete)
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
-- Barre
---------------------------------------------------------------------------

local function timerDirection(channel)
    local e = Enum and Enum.StatusBarTimerDirection
    if not e then return nil end
    return channel and e.RemainingTime or e.ElapsedTime
end

local function setColor(bar, key)
    paintLock(bar.sb, bar.shield, nil, COLORS[key], false)
end

-- couleur du sort en cours (interruptible ou non)
local function paint(bar)
    paintLock(bar.sb, bar.shield, bar.notInt, COLORS[bar.channel and "channel" or "cast"], db.lockColor)
end

-- liseré vert : cible et focalisation, sort interruptible, interruption prete
local function updateReady(bar)
    local on = bar.casting and bar.unit ~= "player" and db.interruptReady
    applyReady(bar.ready, bar.notInt, on and readyStates() or nil)
end

local function stop(bar, interrupted)
    bar.casting = nil
    bar.notInt = nil
    bar.ready:SetAlpha(0)
    if interrupted then
        setColor(bar, "interrupted")
        bar.text:SetText(L.CAST_INTERRUPTED)
        bar.time:SetText("")
        bar.hideAt = GetTime() + 0.6
    elseif not ns.moversShown then
        bar:Hide()
    end
end

local function start(bar, channel)
    local unit = bar.unit
    local name, _, tex, startMS, endMS, notInterruptible
    if channel then
        local ok, n, _, t, s, e, _, ni = pcall(UnitChannelInfo, unit)
        if ok then name, tex, startMS, endMS, notInterruptible = n, t, s, e, ni end
    else
        local ok, n, _, t, s, e, _, _, ni = pcall(UnitCastingInfo, unit)
        if ok then name, tex, startMS, endMS, notInterruptible = n, t, s, e, ni end
    end
    if isNil(name) then return stop(bar) end
    bar.casting = true
    bar.channel = channel
    bar.hideAt = nil
    bar.icon:SetTexture(tex)
    pcall(bar.text.SetText, bar.text, name)
    bar.notInt = notInterruptible
    paint(bar)
    bar.readyT = 0
    updateReady(bar)

    -- 1) objet de duree du client
    bar.duration, bar.startT, bar.endT = nil, nil, nil
    local durFn = channel and UnitChannelDuration or UnitCastingDuration
    if durFn and bar.sb.SetTimerDuration then
        local ok, d = pcall(durFn, unit)
        if ok and d and pcall(bar.sb.SetTimerDuration, bar.sb, d, nil, timerDirection(channel)) then
            bar.duration = d
        end
    end
    -- 2) repli : debut et fin lisibles
    if not bar.duration and startMS and endMS and not issecret(startMS) and not issecret(endMS) then
        bar.startT, bar.endT = startMS / 1000, endMS / 1000
        bar.sb:SetMinMaxValues(0, 1)
    end
    bar:Show()
end

local function onUpdate(bar, elapsed)
    if bar.hideAt then
        if GetTime() >= bar.hideAt then
            bar.hideAt = nil
            if not ns.moversShown then bar:Hide() end
        end
        return
    end
    if not bar.casting then return end
    -- recharge de l interruption relue 10 fois par seconde
    if bar.unit ~= "player" and db.interruptReady then
        bar.readyT = (bar.readyT or 0) + (elapsed or 0)
        if bar.readyT >= 0.1 then
            bar.readyT = 0
            updateReady(bar)
        end
    end
    if bar.startT then
        local now = GetTime()
        local total = bar.endT - bar.startT
        local p = total > 0 and (now - bar.startT) / total or 1
        if bar.channel then p = 1 - p end
        bar.sb:SetValue(math.max(0, math.min(1, p)))
        if bar.showTime then bar.time:SetText(string.format("%.1f", math.max(0, bar.endT - now))) end
    elseif not bar.showTime then
        return
    elseif bar.duration and bar.duration.GetRemainingDuration then
        local ok, rem = pcall(bar.duration.GetRemainingDuration, bar.duration)
        if not (ok and pcall(bar.time.SetFormattedText, bar.time, "%.1f", rem)) then bar.time:SetText("") end
    else
        bar.time:SetText("")
    end
end

-- cadre d unite auquel la barre est accrochee (nil : barre libre)
local function host(f)
    if not conf(f.unit).attach then return nil end
    return _G[UNIT_FRAMES[f.unit]]
end

-- Tailles, icone et textes selon le reglage de la barre
local function layout(f)
    local c = conf(f.unit)
    local h = c.height
    f.icon:SetSize(h, h)
    f.icon:SetShown(c.icon)
    -- bouclier : sur l icone, sinon a gauche de la barre
    f.shield:ClearAllPoints()
    f.shield:SetSize(math.floor(h * 0.8 + 0.5), h)
    if c.icon then f.shield:SetPoint("CENTER", f.icon, "CENTER")
    else f.shield:SetPoint("RIGHT", f, "LEFT", -2, 0) end
    f.sb:ClearAllPoints()
    f.sb:SetPoint("TOPLEFT", c.icon and (h + 1) or 0, 0)
    f.sb:SetPoint("BOTTOMRIGHT")
    local font = (ns.FontFile and ns.FontFile("regular")) or STANDARD_TEXT_FONT
    pcall(f.text.SetFont, f.text, font, c.textSize, "")
    pcall(f.time.SetFont, f.time, font, c.textSize, "")
    f.showTime = c.showTime
    f.time:SetShown(c.showTime)
    if not c.showTime then f.time:SetText("") end
    -- place laissee au temps a droite du nom du sort
    f.text:ClearAllPoints()
    f.text:SetPoint("LEFT", 4, 0)
    f.text:SetPoint("RIGHT", c.showTime and -(c.textSize * 3 + 6) or -4, 0)
end

local function place(f)
    layout(f)
    f:ClearAllPoints()
    local c = conf(f.unit)
    local uf = host(f)
    if uf then
        -- sous le cadre, sur toute sa largeur ; le portrait reste a cote
        f:SetPoint("TOPLEFT", uf, "BOTTOMLEFT", 0, -4)
        f:SetPoint("TOPRIGHT", uf, "BOTTOMRIGHT", 0, -4)
        f:SetHeight(c.height)
    else
        f:SetSize(c.width, c.height)
        ns.ApplyPos(f, f.store)
    end
    -- accrochee : pas de poignee a elle, elle suit le cadre
    if f.mover then f.mover:SetShown(ns.moversShown and not uf) end
end
ns.CastBarAttached = function(unit)
    return db and bars[unit] ~= nil and db.conf[unit] and db.conf[unit].attach and db.show[unit] or false
end

local function makeBar(unit, store, label)
    local f = CreateFrame("Frame", "CorpUICastBar" .. unit, UIParent)
    f.unit, f.store = unit, store
    f:SetSize(W, H)
    ns.UI.Skin(f, 0.85, true)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(H, H)
    f.icon:SetPoint("LEFT")
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.sb = ns.UF.Bar(f, H)
    f.sb:SetPoint("TOPLEFT", H + 1, 0)
    f.sb:SetPoint("BOTTOMRIGHT")
    f.text = f.sb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.text:SetPoint("LEFT", 4, 0)
    f.text:SetPoint("RIGHT", -36, 0)
    f.text:SetJustifyH("LEFT")
    f.text:SetWordWrap(false)
    f.time = f.sb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.time:SetPoint("RIGHT", -4, 0)
    -- sort non interruptible : bouclier (alpha selon notInterruptible)
    f.shield = f.sb:CreateTexture(nil, "OVERLAY", nil, 2)
    if not pcall(f.shield.SetAtlas, f.shield, "nameplates-InterruptShield") then
        f.shield:SetTexture("Interface\\Icons\\INV_Shield_06")
    end
    f.shield:SetAlpha(0)
    -- interruption prete : liseré vert autour de toute la barre
    f.ready = makeReady(f, f)
    f:SetScript("OnUpdate", onUpdate)
    f:Hide()
    f.mover = ns.UI.Mover(f, store, label)
    place(f)

    local ev = CreateFrame("Frame")
    ev:SetScript("OnEvent", function(_, event)
        if ns.ModuleOff("incantations", ev) then return end
        if not db or not db.show[unit] then return end
        if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" then
            start(f, false)
        elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
            start(f, true)
        elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
            stop(f, true)
        elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
            -- l etat change en cours de sort : le nom de l evenement suffit
            if f.casting then
                f.notInt = event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE"
                paint(f)
                updateReady(f)
            end
        elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED"
            or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            if not f.hideAt then stop(f) end
        end
    end)
    for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_STOP",
                         "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
                         "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
                         "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_INTERRUPTIBLE",
                         "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" }) do
        pcall(ev.RegisterUnitEvent, ev, e, unit)
    end
    bars[unit] = f
    return f
end

-- La cible (ou la focalisation) change : reprendre son incantation en
-- cours, s il y en a une
local function refreshUnit(unit)
    local f = bars[unit]
    if not f or not db.show[unit] then return end
    local okC, cast = pcall(UnitCastingInfo, unit)
    local okH, chan = pcall(UnitChannelInfo, unit)
    if okC and not isNil(cast) then start(f, false)
    elseif okH and not isNil(chan) then start(f, true)
    else stop(f) end
end

-- Apercu pendant le deverrouillage de l interface ; barre desactivee : masquee
local function preview()
    for unit, f in pairs(bars) do
        place(f)
        if not db.show[unit] then
            f.casting, f.hideAt = nil, nil
            f:Hide()
        elseif ns.moversShown then
            f.casting = nil
            f.hideAt = nil
            setColor(f, "cast")
            f.ready:SetAlpha(0)
            ns.UF.SetBar(f.sb, 0.6, 1)
            f.icon:SetTexture("Interface\\Icons\\Spell_Nature_Lightning")
            f.text:SetText("")       -- l etiquette de la poignee suffit
            f.time:SetText("")
            f:Show()
        elseif not f.casting and not f.hideAt then
            f:Hide()
        end
    end
end

local function applyBlizzard()
    if db.hideBlizzard or db.blizzardHidden then
        ns.HideBlizzard({ "PlayerCastingBarFrame", "CastingBarFrame", "TargetFrameSpellBar" }, db.hideBlizzard)
        db.blizzardHidden = db.hideBlizzard
    end
end

---------------------------------------------------------------------------
-- Fenetre d options
---------------------------------------------------------------------------

-- Sections de l editeur des cadres (Cadres/Editeur.lua) : reglages communs
-- des barres de sort, puis la barre de chaque cadre (joueur, cible, focalisation).
-- Apres chaque reglage : disposition et apercu des barres, barres de
-- Blizzard, et les auras de la cible se replacent (barre accrochee).
ns.FramesOpt = ns.FramesOpt or {}

local function castForm(parent, y)
    local form = ns.UI.Form(parent, y, function()
        preview()
        applyBlizzard()
        ns.Changed()
    end)
    parent:HookScript("OnShow", function() form:Refresh() end)
    return form
end

function ns.FramesOpt.CastCommon(parent, y)
    local form = castForm(parent, y)
    form:Header(L.MOD_CAST)
    form:Check(L.CAST_OPT_BLIZZ, function() return db.hideBlizzard end, function(v) db.hideBlizzard = v end)
    form:Check(L.CAST_OPT_LOCK, function() return db.lockColor end, function(v) db.lockColor = v end)
    form:Check(L.CAST_OPT_READY, function() return db.interruptReady end, function(v) db.interruptReady = v end)
    return form.y
end

function ns.FramesOpt.Cast(parent, y, unit)
    local function cur() return conf(unit) end
    local form = castForm(parent, y)
    form:Header(L.CAST_BAR_HEAD)
    form:Columns(2)
    form:Check(L.CAST_OPT_SHOW, function() return db.show[unit] end, function(v) db.show[unit] = v end)
    form:Check(L.CAST_OPT_ATTACH1, function() return cur().attach end, function(v) cur().attach = v end)
    local function num(fmt, key, lo, hi, step)
        form:Number(fmt, function() return cur()[key] end, function(v) cur()[key] = v end, lo, hi, step)
    end
    num(L.CAST_WIDTH, "width", 80, 500, 5)
    num(L.CAST_HEIGHT, "height", 8, 40)
    num(L.CAST_TEXT_SIZE, "textSize", 7, 20)
    form:Cell(44)
    form:Check(L.CAST_OPT_ICON, function() return cur().icon end, function(v) cur().icon = v end)
    form:Check(L.CAST_OPT_TIME, function() return cur().showTime end, function(v) cur().showTime = v end)
    form:EndColumns()
    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, form.y - 2)
    hint:SetWidth(420)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.CAST_WIDTH_HINT)
    form:Gap(30)
    return form.y
end

---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if ns.ModuleOff("incantations", ev) then return end
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        root.cast = root.cast or {}
        db = root.cast
        db.show = db.show or { player = true, target = true }
        if db.show.focus == nil then db.show.focus = true end
        if db.attach == nil then db.attach = true end     -- sous les cadres d unite par defaut
        -- ajouts du 05/10 : gris + bouclier si non interruptible, liseré vert si interruption prete
        if db.lockColor == nil then db.lockColor = true end
        if db.interruptReady == nil then db.interruptReady = true end
        scanInterrupts()
        -- l interface de Blizzard qu on remplace est masquee par defaut (une fois)
        if not db.blizzDefault2 then
            db.hideBlizzard = true
            db.blizzDefault2 = true
        end
        -- reglages par barre ; "accrochee" reprend l ancien reglage commun
        db.conf = db.conf or {}
        for _, u in ipairs(UNITS) do
            local c = db.conf[u.unit] or {}
            db.conf[u.unit] = c
            for k, v in pairs({ attach = db.attach, width = W, height = H, icon = true, textSize = 10, showTime = true }) do
                if c[k] == nil then c[k] = v end
            end
            db[u.pos] = db[u.pos] or { point = u.def.point, x = u.def.x, y = u.def.y }
        end
        -- laisser la place aux auras de la cible sous son cadre
        if db.targetPos.point == "CENTER" and db.targetPos.y == -240 and not db.targetPos.rel then db.targetPos.y = -300 end
        for _, u in ipairs(UNITS) do makeBar(u.unit, db[u.pos], L[u.label]) end
        preview()
        applyBlizzard()
    elseif not db then
        return
    elseif event == "PLAYER_TARGET_CHANGED" then
        refreshUnit("target")
    elseif event == "PLAYER_FOCUS_CHANGED" then
        refreshUnit("focus")
    elseif event == "SPELLS_CHANGED" then
        scanInterrupts()
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "SPELLS_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)
end

ns.Listen(function() if db then preview() end end)

-- reglages : editeur des cadres (Cadres/Editeur.lua), cadres Joueur / Cible / Focalisation
ns.RegisterModule({
    command = "incantations",
    title = function() return L.MOD_CAST end,
    desc = function() return L.CAST_DESC end,
    Slash = function() if ns.OpenFrames then ns.OpenFrames("player") end end,
})
