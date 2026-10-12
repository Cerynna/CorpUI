--[[--------------------------------------------------------------------------
    CorpUI - module Chasseur : distance a la cible

    La zone morte du chasseur : entre 5 et 8 metres, ni coup de melee (5 m
    au plus) ni tir (8 m au moins). Deux styles (reglage) :
      - regle a zones (defaut, 10/10) : 0-5 / 5-8 (rouge) / 8-35 / au-dela,
        un curseur qui glisse a la place estimee (le jeu ne donne pas la
        distance d un monstre : tranches de melee, tir, 10, 11 et 28 m) ;
      - pastille : le nom de la zone, a sa couleur.
    Couleurs :
      Melee (0 a 5 m) orange, Zone morte (5 a 8 m) rouge et qui pulse,
      A portee (8 a 35 m) vert, Trop loin (plus de 35 m) gris ;
    un son (au choix, liste partagee avec l alerte de dissipation) a
    l entree dans la zone morte.

    Donnees du client (branche forever, documentation des API) :
      C_SwingTimer.IsTargetWithinSwingRange(0 : main droite / 2 : distance)
        -> vrai, faux, ou nil (pas de cible attaquable, pas d arme) ;
      CheckInteractDistance("target", 3) -> moins de ~10 m (duel).
    Aucune n est secrete ni restreinte. La mesure de portee de l attaque
    automatique n est faite que si elle est activee (EnableRangeCheck :
    10/10, sinon IsTargetWithinSwingRange repond nil). Le minuteur de
    Blizzard l active quand il s affiche ; CorpUI le cache : on l active
    nous-memes (connexion, changement de cible, et si le jeu ne repond plus),
    sans jamais la couper (reglage partage avec Blizzard). Melee prioritaire, puis tir ; ni
    l un ni l autre et proche = zone morte, sinon trop loin. Pas de distance
    au metre pres : une zone.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L
local C = ns.COLORS

local issecret = issecretvalue or function() return false end

local DEFAULTS = { show = "always", problems = false, scale = 100, sound = true, soundKey = "f_alarme", style = "ruler" }
local ZONES = {
    melee = { text = "HUNTER_Z_MELEE", range = "HUNTER_R_MELEE", rgb = { 0.94, 0.62, 0.15 } },
    dead = { text = "HUNTER_Z_DEAD", range = "HUNTER_R_DEAD", rgb = { 0.95, 0.3, 0.3 } },
    ranged = { text = "HUNTER_Z_RANGED", range = "HUNTER_R_RANGED", rgb = { 0.45, 0.8, 0.3 } },
    far = { text = "HUNTER_Z_FAR", range = "HUNTER_R_FAR", rgb = { 0.6, 0.6, 0.62 } },
    -- trop pres pour tirer, sans savoir si la melee porte (0 a 8 m)
    close = { text = "HUNTER_Z_CLOSE", range = "HUNTER_R_CLOSE", rgb = { 0.95, 0.45, 0.25 } },
}
local SOUND_GAP = 2         -- secondes au moins entre deux sons

local db
local hunter = false
local pill               -- cadre porteur (pastille, ou regle dans pill.ruler)
local current, lastSound = nil, 0

---------------------------------------------------------------------------
-- Zone
---------------------------------------------------------------------------

-- vrai / faux lisible, sinon nil
local function bool(ok, v)
    if not ok or issecret(v) or v == nil then return nil end
    return v and true or false
end

-- active la mesure de portee (main droite, distance) ; reactivee au plus
-- toutes les 2 s si le jeu ne repond plus (Blizzard a pu la couper)
local armedAt = -10
local function armRange(force)
    local ST = C_SwingTimer
    if not (hunter and ST and ST.EnableRangeCheck) then return end
    if not force and GetTime() - armedAt < 2 then return end
    armedAt = GetTime()
    pcall(ST.EnableRangeCheck, 0, true)
    pcall(ST.EnableRangeCheck, 2, true)
end

-- Deuxieme source (10/10 : en jeu, la portee de l attaque automatique
-- restait muette meme activee) : la portee des sorts du chasseur,
-- C_Spell.IsSpellInRange (vrai / faux / nil), par leur nom localise (le
-- rang le plus haut connu). Melee : Attaque (attaque automatique de
-- melee), Coupure d ailes ; PAS Attaque du raptor (diag en jeu : vrai a
-- plus de 11 m, attaque "au prochain coup" sans vraie portee). Tir : Tir
-- automatique (faux aussi sous sa portee minimale de 8 m).
local MELEE_SPELLS = { 6603, 2974 }
local RANGED_SPELLS = { 75 }

local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, id)
        if ok and type(n) == "string" and not issecret(n) then return n end
    end
end

local function spellRange(list)
    if not (C_Spell and C_Spell.IsSpellInRange) then return nil end
    for _, id in ipairs(list) do
        for _, key in ipairs({ spellName(id) or id, id }) do
            local ok, v = pcall(C_Spell.IsSpellInRange, key, "target")
            if ok and not issecret(v) and v ~= nil then return v and true or false end
        end
    end
    return nil
end

local function swingRange(t)
    local ST = C_SwingTimer
    if not (ST and ST.IsTargetWithinSwingRange) then return nil end
    return bool(pcall(ST.IsTargetWithinSwingRange, t))
end

local function targetOk()
    if not UnitExists("target") then return false end
    local okA, can = pcall(UnitCanAttack, "player", "target")
    if not bool(okA, can) then return false end
    local okD, dead = pcall(UnitIsDeadOrGhost, "target")
    return bool(okD, dead) ~= true
end

-- distance exacte, si le client la donne pour cette cible (d ordinaire
-- seulement soi et son groupe : jamais un monstre) ; nil sinon
local function exactYards()
    if not UnitDistanceSquared then return nil end
    local ok, d2, checked = pcall(UnitDistanceSquared, "target")
    if not ok or issecret(d2) or issecret(checked) or not checked or type(d2) ~= "number" or d2 < 0 then return nil end
    return math.sqrt(d2)
end

-- mesure du jeu (CheckInteractDistance) : 3 = 10 m, 2 = 11 m, 1 et 4 = 28 m ;
-- marchent aussi sur un PNJ (diag en jeu du 10/10)
local function within(i)
    if not CheckInteractDistance then return nil end
    return bool(pcall(CheckInteractDistance, "target", i))
end

local function zone()
    if not targetOk() then return nil end
    -- tir d abord (8 a 35 m)
    local ranged = swingRange(2)
    if ranged == nil then
        -- pas de mesure de l attaque automatique : on la (re)active
        armRange()
        ranged = spellRange(RANGED_SPELLS)
    end
    if ranged then
        -- place sur la regle : tranches du jeu (10, 11, 28 m)
        if within(3) then return "ranged", 9 end
        if within(2) then return "ranged", 10.5 end
        if within(4) or within(1) then return "ranged", 19.5 end
        return "ranged", 31.5
    end
    local melee = swingRange(0)
    if melee == nil then melee = spellRange(MELEE_SPELLS) end
    if melee then return "melee", 2.5 end
    if ranged == nil then return nil end           -- ni arme a distance ni sort connu
    -- ni tir ni melee : sous les 8 m ou au-dela de 35 m. A moins de 28 m
    -- sans pouvoir tirer, on est forcement sous les 8 m.
    local near, mid = within(3) or within(2), within(4) or within(1)
    if near or mid then
        if melee == false then return "dead", 6.5 end
        return "close", 4                          -- melee inconnue : 0 a 8 m
    end
    if near == nil and mid == nil then
        -- mesures du jeu muettes : la zone d avant (pas de saut a plus de 35 m)
        if current == "melee" or current == "dead" then return "dead", 6.5 end
        if current == "close" then return "close", 4 end
    end
    return "far", 38
end

---------------------------------------------------------------------------
-- Pastille
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Regle a zones
---------------------------------------------------------------------------

local RULER_W, BAR_H = 220, 10
-- largeur de chaque tranche sur la regle (pas a l echelle : la zone morte
-- aussi large que la melee, pour la voir)
local SEGS = {
    { key = "melee", from = 0, to = 5, w = 0.22 },
    { key = "dead", from = 5, to = 8, w = 0.22 },
    { key = "ranged", from = 8, to = 35, w = 0.42 },
    { key = "far", from = 35, to = 40, w = 0.14 },
}

-- metres -> position sur la regle (0 a 1)
local function frac(yd)
    local acc = 0
    for _, sg in ipairs(SEGS) do
        if yd <= sg.to then return acc + math.max(0, yd - sg.from) / (sg.to - sg.from) * sg.w end
        acc = acc + sg.w
    end
    return 1
end

local function buildRuler()
    local r = CreateFrame("Frame", nil, pill)
    r:SetAllPoints()
    r.zone = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ns.UI.HeadFont(r.zone, 12)
    r.zone:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
    r.range = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.range:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, -1)
    r.bar = CreateFrame("Frame", nil, r)
    r.bar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -17)
    r.bar:SetSize(RULER_W, BAR_H)
    ns.UI.Skin(r.bar, 0.9)
    r.segs = {}
    local x = 0
    for _, sg in ipairs(SEGS) do
        local t = r.bar:CreateTexture(nil, "ARTWORK")
        t:SetPoint("TOPLEFT", r.bar, "TOPLEFT", math.floor(x * RULER_W + 0.5), 0)
        t:SetSize(math.floor(sg.w * RULER_W + 0.5), BAR_H)
        ns.NoSnap(t)
        local c = ZONES[sg.key].rgb
        t:SetColorTexture(c[1], c[2], c[3], 1)
        r.segs[sg.key] = t
        -- graduation au debut de chaque tranche (sauf la derniere : "35")
        local lab = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        lab:SetPoint("TOP", r.bar, "BOTTOMLEFT", math.floor(x * RULER_W + 0.5), -2)
        lab:SetText(tostring(sg.from))
        x = x + sg.w
    end
    local last = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    last:SetPoint("TOPRIGHT", r.bar, "BOTTOMRIGHT", 0, -2)
    last:SetText(L.HUNTER_UNIT)
    -- curseur : trait blanc liseré de noir, qui depasse de la barre
    r.marker = CreateFrame("Frame", nil, r)
    r.marker:SetSize(4, BAR_H + 8)
    r.marker:SetFrameLevel(r.bar:GetFrameLevel() + 3)
    local edge = r.marker:CreateTexture(nil, "OVERLAY")
    edge:SetAllPoints()
    edge:SetColorTexture(0, 0, 0, 1)
    local core = r.marker:CreateTexture(nil, "OVERLAY", nil, 1)
    core:SetPoint("TOPLEFT", 1, -1)
    core:SetPoint("BOTTOMRIGHT", -1, 1)
    core:SetColorTexture(1, 1, 1, 1)
    r.pos, r.target = 0, 0
    r:SetScript("OnUpdate", function(self, dt)
        -- glissement du curseur vers la place estimee
        local d = self.target - self.pos
        if math.abs(d) > 0.3 then self.pos = self.pos + d * math.min(1, dt * 10) else self.pos = self.target end
        self.marker:ClearAllPoints()
        self.marker:SetPoint("CENTER", self.bar, "LEFT", self.pos, 0)
        -- zone morte : sa tranche clignote
        if self.pulse then
            self.segs.dead:SetAlpha(0.55 + 0.45 * math.abs(math.sin(GetTime() * 5)))
        end
    end)
    return r
end

local function paintRuler(z, yd, preview)
    local r = pill.ruler
    local d = ZONES[z]
    local c = d.rgb
    r.zone:SetText(L[d.text])
    r.zone:SetTextColor(math.min(1, c[1] + 0.15), math.min(1, c[2] + 0.15), math.min(1, c[3] + 0.15))
    local exact = not preview and exactYards()
    r.range:SetText(exact and string.format("%.0f %s", exact, L.HUNTER_UNIT) or L[d.range])
    -- tranche(s) allumee(s) ; "trop pres" : melee et zone morte
    for key, t in pairs(r.segs) do
        local on = key == z or (z == "close" and (key == "melee" or key == "dead"))
        t:SetAlpha(on and 1 or 0.28)
    end
    r.pulse = (z == "dead") and not preview
    r.target = frac(exact or yd or 0) * RULER_W
end

local function paint(z, preview, yd)
    local d = ZONES[z]
    if not d then pill:Hide() return end
    local ruler = db.style ~= "pill"
    pill.ruler:SetShown(ruler)
    pill.cuiBg:SetShown(not ruler)
    pill.cuiBorder:SetShown(not ruler)
    pill.text:SetShown(not ruler)
    pill.range:SetShown(not ruler)
    if ruler then
        pill:SetSize(RULER_W, 42)
        if pill.pulse then pill.pulse:Stop() end
        pill:SetAlpha(1)
        paintRuler(z, yd, preview)
        pill:Show()
        return
    end
    pill:SetHeight(22)
    local c = d.rgb
    pill.cuiBorder:SetColorTexture(c[1], c[2], c[3], 1)
    pill.cuiBg:SetColorTexture(c[1] * 0.18, c[2] * 0.18, c[3] * 0.18, 0.92)
    pill.text:SetText(L[d.text])
    pill.text:SetTextColor(math.min(1, c[1] + 0.15), math.min(1, c[2] + 0.15), math.min(1, c[3] + 0.15))
    local y = not preview and exactYards()
    pill.range:SetText(y and string.format("%.0f %s", y, L.HUNTER_UNIT) or L[d.range])
    local w = math.floor(pill.text:GetStringWidth() + pill.range:GetStringWidth() + 26)
    pill:SetWidth(math.max(90, w))
    if pill.pulse then
        if z == "dead" and not preview then
            if not pill.pulse:IsPlaying() then pill.pulse:Play() end
        else
            pill.pulse:Stop()
            pill:SetAlpha(1)
        end
    end
    pill:Show()
end

local function wanted()
    if not hunter then return false end
    if db.show == "combat" and not InCombatLockdown() then return false end
    return true
end

local function update()
    if not pill then return end
    if ns.moversShown then
        -- apercu pour la placer (chasseurs seulement)
        if hunter then paint("dead", true, 6.5) else pill:Hide() end
        return
    end
    local z, yd
    if wanted() then z, yd = zone() end
    if z == "ranged" and db.problems then z = nil end
    -- son a l entree dans la zone morte
    if z == "dead" and current ~= "dead" and db.sound and GetTime() - lastSound >= SOUND_GAP then
        lastSound = GetTime()
        if ns.PlaySoundKey then ns.PlaySoundKey(db.soundKey) end
    end
    current = z
    if z then paint(z, false, yd) else
        if pill.pulse then pill.pulse:Stop() end
        pill:Hide()
    end
end

local function build()
    pill = CreateFrame("Frame", "CorpUIHunterRange", UIParent)
    pill:SetFrameStrata("MEDIUM")
    pill:SetSize(120, 22)
    ns.ApplyPos(pill, db.pos)
    ns.UI.Skin(pill, 0.92)
    pill.text = pill:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ns.UI.HeadFont(pill.text, 13)
    pill.text:SetPoint("LEFT", pill, "LEFT", 10, 0)
    pill.range = pill:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    pill.range:SetPoint("LEFT", pill.text, "RIGHT", 6, -1)
    pcall(function()
        local g = pill:CreateAnimationGroup()
        g:SetLooping("BOUNCE")
        local a = g:CreateAnimation("Alpha")
        a:SetFromAlpha(1)
        a:SetToAlpha(0.45)
        a:SetDuration(0.45)
        pill.pulse = g
    end)
    pill.ruler = buildRuler()
    pill.ruler:Hide()
    pill.mover = ns.UI.Mover(pill, db.pos, L.HUNTER_MOVER)
    pill:Hide()
    -- distance : relue 10 fois par seconde (chasseurs seulement)
    pill.watch = ns.Every(0.1, function()
        if hunter or pill:IsShown() then update() end
    end, "Chasseur : distance", "chasseur")
end

local function apply()
    if not pill then return end
    pill:SetScale((db.scale or 100) / 100)
    if pill.mover then pill.mover:SetShown(ns.moversShown and hunter) end
    update()
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------

local win

local function buildOptions()
    win = ns.UI.Window("CorpUIHunterOptions", ns.TITLE .. " - " .. L.MOD_HUNTER, nil, 440, 300)
    local form = ns.UI.Form(win, -34, function() apply() end)
    local note = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    note:SetPoint("TOPLEFT", win, "TOPLEFT", 8, -34)
    note:SetWidth(420)
    note:SetJustifyH("LEFT")
    form:Gap(hunter and 0 or 18)
    form:Header(L.HUNTER_H_RANGE)
    form:Columns(2)
    form:Cycle(L.HUNTER_OPT_SHOW, { "always", "combat" }, { always = L.HUNTER_SHOW_ALWAYS, combat = L.HUNTER_SHOW_COMBAT },
        function() return db.show end, function(v) db.show = v end)
    form:Number(L.HUNTER_OPT_SCALE, function() return db.scale end, function(v) db.scale = v end, 50, 200, 5)
    form:Cycle(L.HUNTER_OPT_STYLE, { "ruler", "pill" }, { ruler = L.HUNTER_STYLE_RULER, pill = L.HUNTER_STYLE_PILL },
        function() return db.style end, function(v) db.style = v end)
    form:EndColumns()
    form:Switch(L.HUNTER_OPT_PROBLEMS, function() return db.problems end, function(v) db.problems = v end)
    form:Switch(L.HUNTER_OPT_SOUND, function() return db.sound end, function(v) db.sound = v end)
    if ns.SoundChoices then
        local sel = form:Select(L.HUNTER_OPT_SOUNDSEL, ns.SoundChoices, function() return db.soundKey end, function(v)
            db.soundKey = v
            if ns.PlaySoundKey then ns.PlaySoundKey(v) end
        end, 200)
        local test = ns.UI.Button(win, L.HUNTER_TEST, 100, function()
            if ns.PlaySoundKey then ns.PlaySoundKey(db.soundKey) end
        end)
        test:SetPoint("LEFT", sel, "RIGHT", 8, 0)
    end
    form:Gap(6)
    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", win, "TOPLEFT", 8, form.y)
    hint:SetWidth(420)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.HUNTER_HINT)
    win:SetHeight(math.floor(70 - form.y))
    win:HookScript("OnShow", function()
        note:SetText(hunter and "" or L.HUNTER_NOT)
        form:Refresh()
    end)
end

local function toggle()
    if not db then return end
    if not win then buildOptions() end
    ns.ShowPanel(win)
end

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if ns.ModuleOff("chasseur", ev) then return end
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        if type(root.hunter) ~= "table" then root.hunter = {} end
        db = root.hunter
        for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
        if type(db.pos) ~= "table" then db.pos = { point = "CENTER", x = 0, y = -70 } end
        local _, class = UnitClass("player")
        hunter = class == "HUNTER"
        build()
        armRange(true)
        apply()
        return
    end
    if not db then return end
    if event == "PLAYER_TARGET_CHANGED" then
        current = nil          -- nouvelle cible : pas de son pour une zone deja la
        armRange(true)
        update()
    else
        update()
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
    pcall(ev.RegisterEvent, ev, e)
end

ns.Listen(function() if db and pill then apply() end end)

ns.RegisterModule({
    command = "chasseur",
    alias = "hunter",
    panelName = "CorpUIHunterOptions",
    icon = "Interface\\Icons\\Ability_Hunter_SniperShot",
    title = function() return L.MOD_HUNTER end,
    desc = function() return L.HUNTER_DESC end,
    Slash = function(input)
        if strlower(strtrim(input or "")) == "diag" then
            -- ce que le jeu repond, valeur par valeur (cible ennemie vivante)
            local function show(ok, v)
                if not ok then return "erreur" end
                if issecret(v) then return "secret" end
                return tostring(v)
            end
            local ST = C_SwingTimer
            ns.Say(string.format("chasseur diag : chasseur %s, module %s, affichage %s, combat %s",
                tostring(hunter), db and "pret" or "non charge", db and db.show or "?", tostring(InCombatLockdown())))
            ns.Say(string.format("  cible %s, attaquable %s, morte %s",
                tostring(UnitExists("target")), show(pcall(UnitCanAttack, "player", "target")),
                show(pcall(UnitIsDeadOrGhost, "target"))))
            local okD, d2, checked = pcall(UnitDistanceSquared or function() end, "target")
            local okP, px = pcall(UnitPosition or function() end, "target")
            ns.Say(string.format("  distance exacte : %s (mesuree %s), position %s",
                show(okD, d2), show(okD, checked), show(okP, px)))
            local cid = {}
            for i = 1, 4 do cid[i] = CheckInteractDistance and show(pcall(CheckInteractDistance, "target", i)) or "absent" end
            ns.Say(string.format("  distances du jeu : 28 m (1) %s, 11 m (2) %s, 10 m (3) %s, 28 m (4) %s", cid[1], cid[2], cid[3], cid[4]))
            ns.Say(string.format("  melee (0) %s, tir (2) %s, moins de 10 m %s",
                ST and ST.IsTargetWithinSwingRange and show(pcall(ST.IsTargetWithinSwingRange, 0)) or "absent",
                ST and ST.IsTargetWithinSwingRange and show(pcall(ST.IsTargetWithinSwingRange, 2)) or "absent",
                CheckInteractDistance and show(pcall(CheckInteractDistance, "target", 3)) or "absent"))
            local sp = C_Spell and C_Spell.IsSpellInRange
            local parts = {}
            for _, id in ipairs({ 6603, 2974, 2973, 75 }) do
                local n = spellName(id)
                parts[#parts + 1] = tostring(n or id) .. " " .. (sp and show(pcall(sp, n or id, "target")) or "absent")
            end
            ns.Say("  sorts : " .. table.concat(parts, ", "))
            ns.Say(string.format("  zone %s, pastille %s", tostring(zone()), pill and tostring(pill:IsShown()) or "absente"))
            return
        end
        toggle()
    end,
    Open = toggle,
})
