--[[--------------------------------------------------------------------------
    CorpUI - module Chasseur : distance a la cible

    La zone morte du chasseur : entre 5 et 8 metres, ni coup de melee (5 m
    au plus) ni tir (8 m au moins). Une pastille sous le personnage dit ou
    l on est, a sa couleur :
      Melee (0 a 5 m) orange, Zone morte (5 a 8 m) rouge et qui pulse,
      A portee (8 a 35 m) vert, Trop loin (plus de 35 m) gris ;
    un son (au choix, liste partagee avec l alerte de dissipation) a
    l entree dans la zone morte.

    Donnees du client (branche forever, documentation des API) :
      C_SwingTimer.IsTargetWithinSwingRange(0 : main droite / 2 : distance)
        -> vrai, faux, ou nil (pas de cible attaquable, pas d arme) ;
      CheckInteractDistance("target", 3) -> moins de ~10 m (duel).
    Aucune n est secrete ni restreinte. Melee prioritaire, puis tir ; ni
    l un ni l autre et proche = zone morte, sinon trop loin. Pas de distance
    au metre pres : une zone.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L
local C = ns.COLORS

local issecret = issecretvalue or function() return false end

local DEFAULTS = { show = "always", problems = false, scale = 100, sound = true, soundKey = "f_alarme" }
local ZONES = {
    melee = { text = "HUNTER_Z_MELEE", range = "HUNTER_R_MELEE", rgb = { 0.94, 0.62, 0.15 } },
    dead = { text = "HUNTER_Z_DEAD", range = "HUNTER_R_DEAD", rgb = { 0.95, 0.3, 0.3 } },
    ranged = { text = "HUNTER_Z_RANGED", range = "HUNTER_R_RANGED", rgb = { 0.45, 0.8, 0.3 } },
    far = { text = "HUNTER_Z_FAR", range = "HUNTER_R_FAR", rgb = { 0.6, 0.6, 0.62 } },
}
local SOUND_GAP = 2         -- secondes au moins entre deux sons

local db
local hunter = false
local pill
local current, lastSound = nil, 0

---------------------------------------------------------------------------
-- Zone
---------------------------------------------------------------------------

-- vrai / faux lisible, sinon nil
local function bool(ok, v)
    if not ok or issecret(v) or v == nil then return nil end
    return v and true or false
end

local function targetOk()
    if not UnitExists("target") then return false end
    local okA, can = pcall(UnitCanAttack, "player", "target")
    if not bool(okA, can) then return false end
    local okD, dead = pcall(UnitIsDeadOrGhost, "target")
    return bool(okD, dead) ~= true
end

local function zone()
    if not targetOk() then return nil end
    local ST = C_SwingTimer
    if not (ST and ST.IsTargetWithinSwingRange) then return nil end
    if bool(pcall(ST.IsTargetWithinSwingRange, 0)) then return "melee" end
    local ranged = bool(pcall(ST.IsTargetWithinSwingRange, 2))
    if ranged then return "ranged" end
    if ranged == nil then return nil end          -- pas d arme a distance
    local close = CheckInteractDistance and bool(pcall(CheckInteractDistance, "target", 3))
    if close then return "dead" end
    if close == false then return "far" end
    return nil
end

---------------------------------------------------------------------------
-- Pastille
---------------------------------------------------------------------------

local function paint(z, preview)
    local d = ZONES[z]
    if not d then pill:Hide() return end
    local c = d.rgb
    pill.cuiBorder:SetColorTexture(c[1], c[2], c[3], 1)
    pill.cuiBg:SetColorTexture(c[1] * 0.18, c[2] * 0.18, c[3] * 0.18, 0.92)
    pill.text:SetText(L[d.text])
    pill.text:SetTextColor(math.min(1, c[1] + 0.15), math.min(1, c[2] + 0.15), math.min(1, c[3] + 0.15))
    pill.range:SetText(L[d.range])
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
        if hunter then paint("dead", true) else pill:Hide() end
        return
    end
    local z = wanted() and zone() or nil
    if z == "ranged" and db.problems then z = nil end
    -- son a l entree dans la zone morte
    if z == "dead" and current ~= "dead" and db.sound and GetTime() - lastSound >= SOUND_GAP then
        lastSound = GetTime()
        if ns.PlaySoundKey then ns.PlaySoundKey(db.soundKey) end
    end
    current = z
    if z then paint(z) else
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
    pill.mover = ns.UI.Mover(pill, db.pos, L.HUNTER_MOVER)
    pill:Hide()
    -- distance : relue 10 fois par seconde
    local acc = 0
    pill.watch = CreateFrame("Frame")
    pill.watch:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.1 then return end
        acc = 0
        update()
    end)
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
        apply()
        return
    end
    if not db then return end
    if event == "PLAYER_TARGET_CHANGED" then
        current = nil          -- nouvelle cible : pas de son pour une zone deja la
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
    Slash = function() toggle() end,
    Open = toggle,
})
