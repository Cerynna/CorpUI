--[[--------------------------------------------------------------------------
    CorpUI - minuteur de coups blancs (sous le cadre joueur)
    Une barre par arme : main droite, main gauche (deux armes), distance
    (arc, fusil, baguette). Source : l evenement du client PLAYER_SWING
    (duree du coup, type d arme), celui qu utilise le minuteur de Blizzard
    (Blizzard_SwingTimer) ; aucun journal de combat.
      - la barre se remplit jusqu au prochain coup, temps restant a droite ;
      - attaque "au prochain coup" en attente (Frappe heroique,
        Enchainement, Attaque du raptor, Mutiler) : barre de la main droite
        en or ;
      - cible hors de portee de l arme : barre estompee (lecture
        C_SwingTimer.IsTargetWithinSwingRange 5 fois par seconde, sans
        toucher au reglage de portee partage avec Blizzard).
    Affichage : "auto" (une barre n apparait qu en frappant, en combat :
    rien pour un lanceur de sorts), "combat" (armes equipees, en combat) ou
    "toujours". Accrochee sous le cadre joueur, sa barre de sort et les
    totems (largeur du cadre), ou libre (poignee). Apercu complet au
    deverrouillage. Le minuteur de Blizzard est cache (option).
    Rien de protege : tout se fait aussi en combat.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L
local C = ns.COLORS

local issecret = issecretvalue or function() return false end

local ST = Enum and Enum.PlayerSwingType or {}
local KINDS = {
    { key = "main", type = ST.MainHand or 0, label = "SWING_MH" },
    { key = "off", type = ST.OffHand or 1, label = "SWING_OH" },
    { key = "ranged", type = ST.Ranged or 2, label = "SWING_RANGED" },
}
local DEFAULTS = {
    enabled = true, attach = true, width = 180, height = 8, off = true, ranged = true, time = true,
    vis = "auto", hideBlizzard = true, queue = true, range = true,
}
local VIS_VALUES = { "auto", "combat", "always" }
local BLIZZ = { "SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame" }
local GAP = 4          -- sous le cadre joueur, sa barre de sort, les totems
local SPACE = 2        -- entre deux barres
local LINGER = 3       -- "auto" : la barre reste 3 s apres le coup attendu
-- attaques au prochain coup (tous les rangs) : Frappe heroique,
-- Enchainement, Attaque du raptor, Mutiler
local NEXT_SWING = {
    78, 284, 285, 1608, 11564, 11565, 11566, 11567, 25286,
    845, 7369, 11608, 11609, 20569,
    2973, 14260, 14261, 14262, 14263, 14264, 14265, 14266,
    6807, 6808, 6809, 8972, 9745, 9880, 9881,
}

local db
local box               -- conteneur (poignee)
local bars = {}         -- cle -> barre
local known = {}        -- attaques au prochain coup connues
local pending = false

local function readable(v) return v ~= nil and not issecret(v) end

-- vitesses d attaque : main droite, main gauche, distance (0 / nil : pas d arme)
local function speeds()
    local ok, mh, oh, rg = pcall(UnitAttackSpeed, "player")
    if not ok then return nil, nil, nil end
    local function n(v) return readable(v) and type(v) == "number" and v > 0 and v or nil end
    return n(mh), n(oh), n(rg)
end

local function inCombat()
    local ok, v = pcall(UnitAffectingCombat, "player")
    return (ok and readable(v) and v) or InCombatLockdown() or false
end

local function scanKnown()
    known = {}
    for _, id in ipairs(NEXT_SWING) do
        local ok, v = pcall(IsPlayerSpell, id)
        if ok and readable(v) and v then table.insert(known, id) end
    end
end

local function queued()
    if not C_Spell or not C_Spell.IsCurrentSpell then return false end
    for _, id in ipairs(known) do
        local ok, v = pcall(C_Spell.IsCurrentSpell, id)
        if ok and readable(v) and v then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Barres
---------------------------------------------------------------------------

local function colorOf(kind)
    if kind.key == "ranged" then return { 0.45, 0.78, 0.35 } end
    local c = C.violet
    if kind.key == "off" then return { c[1] * 0.6 + 0.4, c[2] * 0.6 + 0.4, c[3] * 0.6 + 0.4 } end
    return c
end

local function makeBar(kind)
    local b = CreateFrame("Frame", nil, box)
    b.kind = kind
    ns.UI.Skin(b, 0.8)
    b.sb = CreateFrame("StatusBar", nil, b)
    b.sb:SetAllPoints()
    b.sb:SetStatusBarTexture(ns.BAR_TEXTURE)
    b.sb:SetMinMaxValues(0, 1)
    b.sb:SetValue(0)
    -- police des la creation (10/10) : une barre jamais disposee (main
    -- gauche, distance) etait remise a zero sans police -> "Font not set"
    b.label = b.sb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetShadowOffset(0, 0)
    b.label:SetPoint("LEFT", 3, 0)
    b.time = b.sb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.time:SetShadowOffset(0, 0)
    b.time:SetPoint("RIGHT", -3, 0)
    b:Hide()
    bars[kind.key] = b
    return b
end

local function paint(b)
    local c = colorOf(b.kind)
    if b.kind.key == "main" and b.queued then c = C.gold end
    b.sb:SetStatusBarColor(c[1], c[2], c[3])
end

local function clear(b)
    b.endT, b.dur = nil, nil
    b.sb:SetValue(0)
    b.time:SetText("")
end

-- barres a montrer, dans l ordre
local function wanted()
    local list = {}
    if not db then return list end
    if ns.moversShown then
        for _, k in ipairs(KINDS) do table.insert(list, bars[k.key]) end
        return list
    end
    if not db.enabled then return list end
    local mh, oh, rg = speeds()
    local has = { main = mh ~= nil, off = oh ~= nil and db.off, ranged = rg ~= nil and db.ranged }
    local fight = inCombat()
    local now = GetTime()
    for _, k in ipairs(KINDS) do
        local b = bars[k.key]
        local on = false
        if has[k.key] then
            if db.vis == "always" then on = true
            elseif db.vis == "combat" then on = fight
            else on = fight and b.lastEnd ~= nil and now <= b.lastEnd + LINGER end
        end
        if on then table.insert(list, b) end
    end
    return list
end

-- cadre joueur et ce qui est deja accroche dessous
local function anchorFrame()
    local pf = _G.CorpUIPlayerFrame
    if type(pf) ~= "table" or not pf.GetBottom then return nil, 0 end
    local dy = GAP
    local cb = _G.CorpUICastBarplayer
    if cb and ns.CastBarAttached and ns.CastBarAttached("player") then
        dy = dy + (cb:GetHeight() or 0) + GAP
    end
    if ns.TotemBarBlock then dy = dy + ns.TotemBarBlock() end
    return pf, dy
end

local shownSig
local function layout(force)
    if not box then return end
    local list = wanted()
    local pf, dy = anchorFrame()
    local attached = db.attach and pf
    local w = attached and math.floor((pf:GetWidth() or db.width) + 0.5) or db.width
    local sig = #list .. ":" .. w .. ":" .. tostring(attached and dy) .. ":" .. db.height
    for _, b in ipairs(list) do sig = sig .. b.kind.key end
    if sig == shownSig and not force then return end
    shownSig = sig
    local h = db.height
    local font = (ns.FontFile and ns.FontFile("regular")) or STANDARD_TEXT_FONT
    local size = math.max(7, math.min(12, h + 1))
    for _, k in ipairs(KINDS) do bars[k.key]:Hide() end
    for i, b in ipairs(list) do
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -(i - 1) * (h + SPACE))
        b:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, -(i - 1) * (h + SPACE))
        b:SetHeight(h)
        pcall(b.label.SetFont, b.label, font, size, "OUTLINE")
        pcall(b.time.SetFont, b.time, font, size, "OUTLINE")
        -- etiquette et temps seulement si la barre est assez haute
        b.label:SetShown(h >= 8)
        b.time:SetShown(db.time and h >= 8)
        b.label:SetText(L[b.kind.label])
        paint(b)
        b:Show()
    end
    box:SetSize(w, math.max(1, #list * h + math.max(0, #list - 1) * SPACE))
    box:ClearAllPoints()
    if attached then
        box:SetPoint("TOPLEFT", pf, "BOTTOMLEFT", 0, -dy)
    else
        ns.ApplyPos(box, db.pos)
    end
    if box.mover then box.mover:SetShown((ns.moversShown and not attached) and true or false) end
    box:SetShown(#list > 0)
    -- apercu du deverrouillage : barres a moitie pleines
    if ns.moversShown then
        for i, b in ipairs(list) do
            if not b.endT then
                b.sb:SetValue(0.3 + 0.2 * i)
                if db.time then b.time:SetText(string.format("%.1f", 1.6 - 0.4 * i)) end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Coups
---------------------------------------------------------------------------

local function onSwing(duration, swingType)
    if not db or not db.enabled then return end
    if not readable(duration) or not readable(swingType) or type(duration) ~= "number" or duration <= 0 then return end
    for _, k in ipairs(KINDS) do
        if k.type == swingType then
            local b = bars[k.key]
            b.dur = duration
            b.endT = GetTime() + duration
            b.lastEnd = b.endT
        end
    end
    layout()
end

local acc, rangeAcc = 0, 0
local function tick(_, dt)
    if not db or not box then return end
    acc = acc + dt
    rangeAcc = rangeAcc + dt
    local now = GetTime()
    for _, k in ipairs(KINDS) do
        local b = bars[k.key]
        if b.endT then
            local rem = b.endT - now
            if rem <= 0 then
                clear(b)
            elseif b:IsShown() then
                b.sb:SetValue(1 - rem / b.dur)
                if db.time then b.time:SetFormattedText("%.1f", rem) end
            end
        end
    end
    if rangeAcc >= 0.2 then
        rangeAcc = 0
        -- attaque au prochain coup en attente : barre de la main droite en or
        local q = db.queue and #known > 0 and queued() or false
        local mb = bars.main
        if q ~= mb.queued then
            mb.queued = q
            paint(mb)
        end
        -- portee de l arme (cible actuelle) : barre estompee hors de portee
        for _, k in ipairs(KINDS) do
            local b = bars[k.key]
            local a = 1
            if db.range and not ns.moversShown and C_SwingTimer and C_SwingTimer.IsTargetWithinSwingRange then
                local ok, v = pcall(C_SwingTimer.IsTargetWithinSwingRange, k.type)
                -- nil : pas de mesure, ce n est pas "hors de portee"
                if ok and readable(v) and v == false then a = 0.4 end
            end
            if b:GetAlpha() ~= a then b:SetAlpha(a) end
        end
    end
    -- barres apparues / disparues ("auto"), cadre joueur deplace : 2 fois par seconde
    if acc >= 0.5 then
        acc = 0
        layout()
    end
end

---------------------------------------------------------------------------
-- Application
---------------------------------------------------------------------------

local function apply()
    if not db or not box then return end
    shownSig = nil
    layout(true)
    -- minuteur de Blizzard : rangé tant que le notre est actif (hors combat)
    local hide = db.enabled and db.hideBlizzard and true or false
    if hide or db.blizzHidden then
        if InCombatLockdown() then pending = true return end
        if ns.HideBlizzard(BLIZZ, hide) then db.blizzHidden = hide or nil end
    end
end
ns.SwingApply = apply

local function build()
    box = CreateFrame("Frame", "CorpUISwingTimer", UIParent)
    box:SetFrameStrata("LOW")
    box:SetSize(db.width, db.height)
    for _, k in ipairs(KINDS) do makeBar(k) end
    box.mover = ns.UI.Mover(box, db.pos, L.SWING_MOVER)
    -- deplace a la main : minuteur libre
    box.mover.onMoved = function() db.attach = false end
    box:Hide()
    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", tick)
end

-- poignees affichees : apercu complet (les trois barres)
local lastMovers = false
ns.Listen(function()
    if not db or (ns.moversShown and true or false) == lastMovers then return end
    lastMovers = ns.moversShown and true or false
    for _, k in ipairs(KINDS) do
        if not lastMovers then clear(bars[k.key]) end
    end
    apply()
end)

---------------------------------------------------------------------------
-- Options (section "Joueur" de l editeur des cadres)
---------------------------------------------------------------------------

ns.FramesOpt = ns.FramesOpt or {}
function ns.FramesOpt.Swing(parent, y)
    local form = ns.UI.Form(parent, y, function() apply() end)
    form:Header(L.SWING_HEADER)
    local function chk(text, key)
        form:Check(text, function() return db and db[key] end, function(v) if db then db[key] = v end end)
    end
    chk(L.SWING_OPT_ENABLE, "enabled")
    form:Columns(2)
    form:Check(L.SWING_OPT_ATTACH, function() return db and db.attach end, function(v)
        if not db then return end
        -- detache : il reste ou il est (position absolue)
        if not v and box and box:GetLeft() then ns.PinTop(box, db.pos, true) end
        db.attach = v
    end)
    chk(L.SWING_OPT_OFF, "off")
    chk(L.SWING_OPT_RANGED, "ranged")
    chk(L.SWING_OPT_TIME, "time")
    chk(L.SWING_OPT_QUEUE, "queue")
    chk(L.SWING_OPT_RANGE, "range")
    chk(L.SWING_OPT_BLIZZ, "hideBlizzard")
    form:Cycle(L.SWING_VIS, VIS_VALUES, { auto = L.SWING_VIS_AUTO, combat = L.SWING_VIS_COMBAT, always = L.SWING_VIS_ALWAYS },
        function() return db and db.vis or "auto" end, function(v) if db then db.vis = v end end)
    form:Number(L.SWING_WIDTH, function() return db and db.width or 180 end, function(v)
        if db then db.width = math.max(60, math.min(500, math.floor(v + 0.5))) end
    end, 60, 500, 5)
    form:Number(L.SWING_HEIGHT, function() return db and db.height or 8 end, function(v)
        if db then db.height = math.max(4, math.min(30, math.floor(v + 0.5))) end
    end, 4, 30, 1)
    form:EndColumns()
    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, form.y - 6)
    hint:SetWidth(420)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.SWING_HINT)
    parent:HookScript("OnShow", function() form:Refresh() end)
    form:Refresh()
    return form.y - 40
end

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, a1, a2)
    if ns.ModuleOff("cadres", ev) then return end
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        if type(root.frames) ~= "table" then root.frames = {} end
        if type(root.frames.swing) ~= "table" then root.frames.swing = {} end
        db = root.frames.swing
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = v end
        end
        if type(db.pos) ~= "table" then db.pos = { point = "CENTER", x = -175, y = -250 } end
        scanKnown()
        build()
        apply()
    elseif not db then
        return
    elseif event == "PLAYER_SWING" then
        onSwing(a1, a2)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending then pending = false apply() end
        layout()
    elseif event == "SPELLS_CHANGED" then
        scanKnown()
    elseif event == "PLAYER_TARGET_CHANGED" then
        if not ns.moversShown then
            for _, k in ipairs(KINDS) do bars[k.key]:SetAlpha(1) end
        end
    else
        -- arme changee, vitesse, entree dans le monde, combat
        shownSig = nil
        layout()
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_SWING", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
                     "PLAYER_ENTERING_WORLD", "WEAPON_SLOT_CHANGED", "PLAYER_EQUIPMENT_CHANGED",
                     "SPELLS_CHANGED", "PLAYER_TARGET_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
pcall(ev.RegisterUnitEvent, ev, "UNIT_ATTACK_SPEED", "player")
