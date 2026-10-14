--[[--------------------------------------------------------------------------
    CorpUI - totems actifs du chaman (avec le module Cadres)
    Le cadre des totems de Blizzard (TotemFrame) est accroche a leur cadre
    joueur, masque par CorpUI : ici, quatre cases dans l ordre Terre, Feu,
    Eau, Air, sous le cadre joueur de CorpUI (et sous sa barre de sort
    quand elle y est accrochee), ou libres et deplacables :
      - icone du totem pose, temps restant, lisere a la couleur de
        l element (attenue quand la case est vide) ;
      - clic droit : detruire le totem. Bouton SECURISE (type "destroytotem",
        attribut "totem-slot", gere par le jeu) : aucune fonction appelee par
        l addon ;
      - infobulle du totem au survol.
    Chaman seulement. Les cases sont des cadres securises : montrees,
    cachees et placees hors combat ; en combat, seuls leur contenu et leur
    opacite changent (case vide masquee par l opacite si l option le dit).

    Valeurs secretes : GetTotemInfo est lu sous pcall ; l icone et le
    recharge (Cooldown) recoivent les valeurs telles quelles, le temps
    restant n est calcule que si elles sont lisibles (sinon chiffres du
    recharge du client).
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local C = ns.COLORS

local issecret = issecretvalue or function() return false end

local DEFAULTS = { enabled = true, attach = true, size = 26, spacing = 3, showEmpty = true, time = true }
-- emplacements du jeu (Constants.lua : feu 1, terre 2, eau 3, air 4), dans
-- l ordre de Blizzard (SHAMAN_TOTEM_PRIORITIES) : Terre, Feu, Eau, Air
local ORDER = {
    { slot = EARTH_TOTEM_SLOT or 2, color = { 0.66, 0.47, 0.26 } },
    { slot = FIRE_TOTEM_SLOT or 1, color = { 1.00, 0.45, 0.15 } },
    { slot = WATER_TOTEM_SLOT or 3, color = { 0.25, 0.60, 1.00 } },
    { slot = AIR_TOTEM_SLOT or 4, color = { 0.72, 0.78, 1.00 } },
}
local GAP = 4   -- sous le cadre joueur (ou sous sa barre de sort)

local db
local bar
local buttons = {}
local pending       -- placement a refaire en sortie de combat
local isShaman = false

---------------------------------------------------------------------------
-- Lecture d un emplacement
---------------------------------------------------------------------------

-- actif, icone, debut, duree (debut / duree eventuellement secrets)
local function totem(slot)
    if not GetTotemInfo then return false end
    local ok, have, _, start, dur, icon = pcall(GetTotemInfo, slot)
    if not ok then return false end
    -- haveTotem : l element est disponible ; pose seulement avec une duree
    -- (comme le cadre des totems de Blizzard)
    local okA, active = pcall(function() return (have and dur and dur > 0) and true or false end)
    if not okA then active = type(icon) ~= "nil" end
    return active, icon, start, dur
end

local function fmt(sec)
    if sec >= 60 then return string.format("%d:%02d", math.floor(sec / 60), math.floor(sec % 60)) end
    return tostring(math.floor(sec + 0.5))
end

---------------------------------------------------------------------------
-- Une case
---------------------------------------------------------------------------

local function paint(b, active)
    local c = b.color
    -- case vide : lisere de l element bien visible (on reconnait la case),
    -- fond plus sombre ; active : lisere plein
    local a = active and 1 or 0.75
    for _, e in ipairs(b.edges) do e:SetColorTexture(c[1], c[2], c[3], a) end
    b.fill:SetColorTexture(c[1] * 0.12, c[2] * 0.12, c[3] * 0.12, active and 0.55 or 0.7)
end

local function update(b)
    if not db then return end
    local active, icon, start, dur = totem(b.slot)
    b.active = active
    if active then
        if not pcall(b.icon.SetTexture, b.icon, icon) then b.icon:SetTexture(nil) end
        b.icon:Show()
        pcall(b.cd.SetCooldown, b.cd, start, dur)
        -- temps restant calcule si lisible, sinon chiffres du recharge
        local okR = not issecret(start) and not issecret(dur) and type(start) == "number" and type(dur) == "number"
        b.readable = okR and dur > 0
        b.start, b.dur = start, dur
        pcall(b.cd.SetHideCountdownNumbers, b.cd, b.readable or not db.time)
    else
        b.icon:Hide()
        b.cd:Clear()
        b.readable, b.start, b.dur = false, nil, nil
        b.time:SetText("")
    end
    paint(b, active)
    -- case vide : masquee par l opacite (permis en combat)
    local show = active or db.showEmpty or ns.moversShown
    b:SetAlpha(show and 1 or 0)
end

local function tickTime(b)
    if not (b.active and b.readable and db.time) then b.time:SetText("") return end
    local rem = b.start + b.dur - GetTime()
    if rem <= 0 then b.time:SetText("") return end
    b.time:SetText(fmt(rem))
end

local function makeButton(i, spec)
    local b = CreateFrame("Button", "CorpUITotemButton" .. i, bar, "SecureActionButtonTemplate")
    b.slot, b.color = spec.slot, spec.color
    b:RegisterForClicks("RightButtonUp", "RightButtonDown")
    -- clic droit : le jeu detruit le totem de cet emplacement
    b:SetAttribute("type2", "destroytotem")
    b:SetAttribute("totem-slot", spec.slot)
    b.fill = b:CreateTexture(nil, "BACKGROUND")
    b.fill:SetAllPoints()
    b.fill:SetColorTexture(0, 0, 0, 0.55)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.edges = {}
    for k, pts in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local e = b:CreateTexture(nil, "OVERLAY", nil, 7)
        e:SetPoint(pts[1], b, pts[1], 0, 0)
        e:SetPoint(pts[2], b, pts[2], 0, 0)
        if k <= 2 then e:SetHeight(1) else e:SetWidth(1) end
        ns.NoSnap(e)
        b.edges[k] = e
    end
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b.icon)
    pcall(b.cd.SetDrawEdge, b.cd, false)
    pcall(b.cd.SetReverse, b.cd, true)
    -- police des la creation (SetText avant la disposition : "Font not set")
    b.time = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.time:SetShadowOffset(0, 0)
    b.time:SetPoint("TOP", b, "BOTTOM", 0, -1)
    b:SetScript("OnEnter", function(self)
        if not self.active then return end
        local t = ns.Tooltip(self, "ANCHOR_TOP")
        if pcall(t.SetTotem, t, self.slot) then t:Show() end
    end)
    b:SetScript("OnLeave", ns.HideTooltip)
    return b
end

---------------------------------------------------------------------------
-- Construction et placement
---------------------------------------------------------------------------

local function build()
    bar = CreateFrame("Frame", "CorpUITotemBar", UIParent)
    bar:SetFrameStrata("LOW")
    for i, spec in ipairs(ORDER) do buttons[i] = makeButton(i, spec) end
    bar.mover = ns.UI.Mover(bar, db.pos, L.TOTEM_MOVER)
    -- deplace a la main : barre libre
    bar.mover.onMoved = function() db.attach = false end
    local acc = 0
    bar:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.2 then return end
        acc = 0
        for _, b in ipairs(buttons) do tickTime(b) end
    end)
end

-- cadre joueur de CorpUI, et sa barre de sort quand elle y est accrochee
local function anchorFrame()
    local pf = _G.CorpUIPlayerFrame
    if type(pf) ~= "table" or not pf.GetBottom then return nil, 0 end
    local dy = GAP
    local cb = _G.CorpUICastBarplayer
    if cb and ns.CastBarAttached and ns.CastBarAttached("player") then
        dy = GAP + (cb:GetHeight() or 0) + GAP
    end
    return pf, dy
end

local function apply()
    if not bar then return end
    if InCombatLockdown() then pending = true return end
    pending = false
    local size, gap = db.size, db.spacing
    bar:SetSize(size * #buttons + gap * (#buttons - 1), size)
    local font = (ns.FontFile and ns.FontFile("regular")) or STANDARD_TEXT_FONT
    for i, b in ipairs(buttons) do
        b:SetSize(size, size)
        b:ClearAllPoints()
        b:SetPoint("LEFT", bar, "LEFT", (i - 1) * (size + gap), 0)
        pcall(b.time.SetFont, b.time, font, math.max(8, math.floor(size * 0.4)), "OUTLINE")
    end
    bar:ClearAllPoints()
    local pf, dy = anchorFrame()
    if db.attach and pf then
        bar:SetPoint("TOPLEFT", pf, "BOTTOMLEFT", 0, -dy)
    else
        ns.ApplyPos(bar, db.pos)
    end
    -- accrochee : pas de poignee, elle suit le cadre joueur
    if bar.mover then bar.mover:SetShown((ns.moversShown and not (db.attach and pf)) and true or false) end
    bar:SetShown(isShaman and (db.enabled or ns.moversShown) and true or false)
    for _, b in ipairs(buttons) do update(b) end
end
ns.TotemsApply = apply

-- place prise sous le cadre joueur (minuteur de coups blancs : en dessous)
function ns.TotemBarBlock()
    if not bar or not db or not db.attach or not bar:IsShown() then return 0 end
    return (bar:GetHeight() or 0) + GAP
end

-- poignees affichees : la barre se montre (cases vides comprises)
local lastMovers = false
ns.Listen(function()
    if not db or (ns.moversShown and true or false) == lastMovers then return end
    lastMovers = ns.moversShown and true or false
    apply()
end)

---------------------------------------------------------------------------
-- Options (section "Joueur" de l editeur des cadres)
---------------------------------------------------------------------------

function ns.FramesOpt.Totems(parent, y)
    local form = ns.UI.Form(parent, y, function() apply() end)
    form:Header(L.TOTEM_HEADER)
    form:Check(L.TOTEM_OPT_ENABLE, function() return db and db.enabled end, function(v) if db then db.enabled = v end end)
    form:Columns(2)
    form:Check(L.TOTEM_OPT_ATTACH, function() return db and db.attach end, function(v)
        if not db then return end
        -- detachee : elle reste ou elle est (position absolue)
        if not v and bar and bar:GetLeft() then ns.PinTop(bar, db.pos, true) end
        db.attach = v
    end)
    form:Check(L.TOTEM_OPT_EMPTY, function() return db and db.showEmpty end, function(v) if db then db.showEmpty = v end end)
    form:Check(L.TOTEM_OPT_TIME, function() return db and db.time end, function(v) if db then db.time = v end end)
    form:Number(L.TOTEM_SIZE, function() return db and db.size or 26 end, function(v)
        if db then db.size = math.max(16, math.min(48, math.floor(v + 0.5))) end
    end, 16, 48, 1)
    form:EndColumns()
    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, form.y - 6)
    hint:SetWidth(420)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.TOTEM_HINT)
    parent:HookScript("OnShow", function() form:Refresh() end)
    form:Refresh()
    return form.y - 40
end

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, arg)
    if ns.ModuleOff("cadres", ev) then return end
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        if type(root.frames) ~= "table" then root.frames = {} end
        if type(root.frames.totems) ~= "table" then root.frames.totems = {} end
        db = root.frames.totems
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = v end
        end
        if type(db.pos) ~= "table" then db.pos = { point = "CENTER", x = -175, y = -230 } end
        local _, class = UnitClass("player")
        isShaman = class == "SHAMAN"
        build()
        apply()
    elseif not db then
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending then apply() end
    elseif event == "PLAYER_TOTEM_UPDATE" then
        for _, b in ipairs(buttons) do
            local ok, same = pcall(function() return arg == nil or b.slot == arg end)
            if not ok or same then update(b) end
        end
    else
        -- entree dans le monde : le cadre joueur et sa barre de sort sont
        -- places, la barre suit
        apply()
    end
end)
pcall(ev.RegisterEvent, ev, "PLAYER_LOGIN")
pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")
pcall(ev.RegisterEvent, ev, "PLAYER_ENTERING_WORLD")
pcall(ev.RegisterEvent, ev, "PLAYER_TOTEM_UPDATE")
