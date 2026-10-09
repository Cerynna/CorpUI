--[[--------------------------------------------------------------------------
    CorpUI - module Raid (barre facon MRT)
    Une barre deplacable avec :
      - 8 marqueurs de cible + retirer le marqueur ;
      - 8 marqueurs au sol + tout effacer ;
      - appel, verification des roles, decompte de pull, et en option
        convertir en raid / tout le monde assistant.

    Sur ce client, SetRaidTarget, RemoveRaidTargets, PlaceRaidMarker,
    ClearRaidMarker et C_PartyInfo.DoReadyCheck / DoCountdown / ConvertToRaid /
    SetEveryoneIsAssistant sont marquees HasRestrictions : un addon ne peut
    pas les appeler. Chaque bouton est donc un SecureActionButton dont
    l action est executee par le code securise de Blizzard au clic materiel
    (SECURE_ACTIONS de SecureTemplates.lua, branche forever) :
      - type "raidtarget" : marker (1-8), action (set / clear / clear-all),
        unit (target au clic gauche, focus au clic droit, none pour tout
        retirer) ;
      - type "worldmarker" : marker (index du marqueur au sol), action
        (set au clic gauche : le jeu demande ensuite un clic au sol ; clear
        au clic droit). Sans marker, clear = ClearRaidMarker(nil) = tous ;
      - type "macro" : macrotext "/readycheck", "/countdown N" et
        "/countdown 0" (annule). Commandes de Blizzard (SlashCommands.lua),
        ecrites avec leur nom du client (SLASH_READYCHECK1, SLASH_COUNTDOWN1) ;
      - type "click" : le code securise clique le bouton de Blizzard qui fait
        l action (RaidFrameConvertToRaidButton ; case "tout le monde
        assistant" du gestionnaire de raid). Absent : bouton grise.
    La verification des roles (InitiateRolePoll) n est pas restreinte :
    bouton ordinaire, appel direct.

    Attributs, taille, position et visibilite : hors combat seulement (en
    combat tout est differe a PLAYER_REGEN_ENABLED). L etat affiche
    (boutons grises sans les droits de chef ou d assistant, marqueurs au sol
    poses, decompte) est lu hors du code securise, valeurs secretes ecartees.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local issecret = issecretvalue or function() return false end

local ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
-- marqueur de cible (etoile ... crane) -> marqueur au sol de meme forme
-- (meme correspondance que WORLD_RAID_MARKER_ORDER du gestionnaire de raid)
local RT_TO_WM = { 5, 6, 3, 2, 7, 1, 4, 8 }
-- couleur de chaque marqueur au sol (par index de marqueur au sol)
local WM_COLORS = {
    { 0.25, 0.55, 1.00 },   -- 1 carre bleu
    { 0.25, 0.90, 0.30 },   -- 2 triangle vert
    { 0.80, 0.35, 1.00 },   -- 3 losange violet
    { 1.00, 0.25, 0.25 },   -- 4 croix rouge
    { 1.00, 0.90, 0.20 },   -- 5 etoile jaune
    { 1.00, 0.55, 0.10 },   -- 6 cercle orange
    { 0.75, 0.80, 0.90 },   -- 7 lune argent
    { 1.00, 1.00, 1.00 },   -- 8 crane blanc
}

local DEFAULTS = {
    enabled = true, orient = "h", stacked = false, size = 24, spacing = 2, backdrop = true,
    vis = "group", marks = true, ground = true, tools = true, extras = true,
    pull = 10, bigTimer = false,
}
local VIS_DRIVERS = { group = "[group] show; hide", raid = "[group:raid] show; hide" }

local db
local bar
local marks, grounds = {}, {}
local allButtons, shownButtons = {}, {}
local readyB, roleB, pullB, convertB, assistB
local pending, needBuild = false, false
local lastDriver
local cd = {}            -- decompte de pull en cours (endTime, shown)

---------------------------------------------------------------------------
-- Lectures (hors code securise, valeurs secretes ecartees)
---------------------------------------------------------------------------

local function flag(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn, ...)
    if not ok or issecret(v) then return false end
    return v and true or false
end

-- droits dans le groupe : ce qui grise les boutons (affichage seulement)
local function readState()
    local s = {}
    s.group = flag(IsInGroup)
    s.raid = s.group and flag(IsInRaid)
    s.leader = s.group and flag(UnitIsGroupLeader, "player")
    s.assist = s.raid and flag(UnitIsGroupAssistant, "player")
    s.everyone = s.raid and flag(IsEveryoneAssistant)
    s.lead = s.leader or s.assist or s.everyone
    -- marqueurs : libres hors raid (seul ou en groupe), chef / assistant en raid
    s.mark = not s.raid or s.lead
    s.lfg = flag(HasLFGRestrictions)
    s.bg = flag(UnitInBattleground, "player")
    -- conversion en raid permise (lecture non restreinte, comme RaidFrame_Update)
    local allow = C_PartyInfo and C_PartyInfo.AllowedToDoPartyConversion
    s.convert = type(allow) ~= "function" or flag(allow, true)
    return s
end

-- bouton de Blizzard a cliquer depuis le code securise (type "click")
local function blizzButton(f)
    if type(f) == "table" and type(f.Click) == "function" then return f end
end

local function convertDelegate()
    return blizzButton(_G.RaidFrameConvertToRaidButton)
end

local function assistDelegate()
    local f = blizzButton(_G.CompactRaidFrameManagerDisplayFrameEveryoneIsAssistButton)
    if f then return f end
    local m = _G.CompactRaidFrameManager
    local d = type(m) == "table" and m.displayFrame
    return blizzButton(type(d) == "table" and d.everyoneIsAssistButton or nil)
end

-- nom de commande du client (localise), sinon le nom anglais
local function slashText(key, fallback)
    local v = _G["SLASH_" .. key .. "1"]
    if not issecret(v) and type(v) == "string" and v:sub(1, 1) == "/" then return v end
    return fallback
end

local function hex(c)
    return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
        math.floor(c[3] * 255 + 0.5))
end

local function iconLine(i)
    return "|T" .. ICON .. i .. ":0|t " .. hex(WM_COLORS[RT_TO_WM[i]]) .. L["RAID_ICON_" .. i] .. "|r"
end

---------------------------------------------------------------------------
-- Boutons
---------------------------------------------------------------------------

local function setFontSize(fs, size)
    local f, _, flags = fs:GetFont()
    if f then fs:SetFont(f, size, flags) end
end

-- bouton carre au style des barres : fond sombre, liseré, icone, or au survol.
-- secure : SecureActionButton (attributs poses hors combat, une fois pour
-- toutes dans b.attrs) ; sinon bouton ordinaire.
local function makeButton(name, secure, attrs)
    local b = CreateFrame("Button", name, bar, secure and "SecureActionButtonTemplate" or nil)
    if secure then
        -- comme les barres d action : l action part a l appui ou au
        -- relachement selon l option du jeu (ActionButtonUseKeyDown)
        b:RegisterForClicks("AnyUp", "AnyDown")
        for k, v in pairs(attrs or {}) do b:SetAttribute(k, v) end
    else
        b:RegisterForClicks("LeftButtonUp")
    end
    b:SetSize(DEFAULTS.size, DEFAULTS.size)
    ns.UI.Skin(b, 0.6)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.04, 0.96, 0.04, 0.96)
    -- etat "actif" (decompte en cours, tout le monde assistant)
    b.on = b:CreateTexture(nil, "OVERLAY")
    b.on:SetPoint("TOPLEFT", 1, -1)
    b.on:SetPoint("BOTTOMRIGHT", -1, 1)
    local g = ns.COLORS.gold
    b.on:SetColorTexture(g[1], g[2], g[3], 0.22)
    b.on:Hide()
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 1, -1)
    hl:SetPoint("BOTTOMRIGHT", -1, 1)
    hl:SetColorTexture(1, 1, 1, 0.15)
    b:SetScript("OnEnter", function(self)
        if ns.QuickBindHover and ns.QuickBindHover(self) then return end
        local c = ns.COLORS.gold
        if self.cuiBorder then self.cuiBorder:SetColorTexture(c[1], c[2], c[3], 1) end
        local t = ns.Tooltip(self, "ANCHOR_TOP")
        if self.tip then self.tip(t) end
        if not self.ok and self.why then t:AddLine(self.why, 1, 0.35, 0.35, true) end
        t:Show()
    end)
    b:SetScript("OnLeave", function(self)
        ns.UI.ResetBorder(self)
        ns.HideTooltip()
    end)
    b.ok = true
    -- raccourcis rapides (/corp kb) : un raccourci peut viser le bouton
    if ns.RegisterBindable then ns.RegisterBindable(b, "CLICK " .. name .. ":LeftButton") end
    table.insert(allButtons, b)
    return b
end

local function buildMarks()
    for i = 1, 8 do
        local b = makeButton("CorpUIRaidMark" .. i, true, {
            type = "raidtarget", action = "set", marker = i,
            ["*unit1"] = "target", ["*unit2"] = "focus",
        })
        b.icon:SetTexture(ICON .. i)
        b.icon:SetTexCoord(0, 1, 0, 1)
        b.icon:ClearAllPoints()
        b.icon:SetPoint("TOPLEFT", 2, -2)
        b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        b.need = "mark"
        b.bindLabel = L.MOD_RAID .. " - " .. L["RAID_ICON_" .. i]
        b.tip = function(t)
            t:AddLine(iconLine(i))
            t:AddLine(L.RAID_TIP_TARGET, 1, 1, 1)
            t:AddLine(L.RAID_TIP_FOCUS, 1, 1, 1)
        end
        marks[i] = b
    end
    -- retirer : cible (gauche), focalisation (droit), tous (Maj)
    local c = makeButton("CorpUIRaidMarkClear", true, {
        type = "raidtarget", action = "clear",
        ["*unit1"] = "target", ["*unit2"] = "focus",
        ["shift-action1"] = "clear-all", ["shift-unit1"] = "none",
        ["shift-action2"] = "clear-all", ["shift-unit2"] = "none",
    })
    c.icon:SetTexture(ns.MEDIA .. "raid_clear")
    c.need = "mark"
    c.bindLabel = L.MOD_RAID .. " - " .. L.RAID_CLEAR
    c.tip = function(t)
        t:AddLine(L.RAID_CLEAR)
        t:AddLine(L.RAID_TIP_CLEAR, 1, 1, 1, true)
        t:AddLine(L.RAID_TIP_CLEAR_ALL, 1, 1, 1, true)
    end
    marks[9] = c
end

local function buildGround()
    for i = 1, 8 do
        local wm = RT_TO_WM[i]
        local col = WM_COLORS[wm]
        local b = makeButton("CorpUIRaidGround" .. i, true, {
            type = "worldmarker", marker = wm,
            ["*action1"] = "set", ["*action2"] = "clear",
        })
        -- lueur de la couleur du marqueur, montant du bas : "au sol"
        b.glow = b:CreateTexture(nil, "ARTWORK", nil, -1)
        b.glow:SetPoint("BOTTOMLEFT", 1, 1)
        b.glow:SetPoint("BOTTOMRIGHT", -1, 1)
        b.glow:SetPoint("TOP", b, "CENTER", 0, 2)
        ns.UI.Gradient(b.glow, "VERTICAL", col[1], col[2], col[3], 0.9, col[1], col[2], col[3], 0)
        b.glow:SetAlpha(0.45)
        b.icon:SetTexture(ICON .. i)
        b.icon:SetTexCoord(0, 1, 0, 1)
        b.icon:ClearAllPoints()
        b.icon:SetPoint("TOPLEFT", 4, -2)
        b.icon:SetPoint("BOTTOMRIGHT", -4, 6)
        -- pastille d or : marqueur pose
        b.dot = b:CreateTexture(nil, "OVERLAY", nil, 1)
        b.dot:SetSize(4, 4)
        b.dot:SetPoint("TOPRIGHT", -2, -2)
        local g = ns.COLORS.gold
        b.dot:SetColorTexture(g[1], g[2], g[3], 1)
        b.dot:Hide()
        b.wm = wm
        b.need = "mark"
        b.bindLabel = L.MOD_RAID .. " - " .. string.format(L.RAID_GROUND, L["RAID_ICON_" .. i])
        b.tip = function(t)
            t:AddLine(string.format(L.RAID_GROUND, iconLine(i)))
            if b.active then t:AddLine(L.RAID_GROUND_ON, 1, 0.82, 0) end
            t:AddLine(L.RAID_TIP_PLACE, 1, 1, 1, true)
            t:AddLine(L.RAID_TIP_REMOVE, 1, 1, 1)
        end
        grounds[i] = b
    end
    -- tout effacer : ClearRaidMarker sans index
    local c = makeButton("CorpUIRaidGroundClear", true, { type = "worldmarker", action = "clear" })
    c.icon:SetTexture(ns.MEDIA .. "raid_clearground")
    c.need = "mark"
    c.bindLabel = L.MOD_RAID .. " - " .. L.RAID_GROUND_CLEAR
    c.tip = function(t) t:AddLine(L.RAID_GROUND_CLEAR) end
    grounds[9] = c
end

local function buildTools()
    readyB = makeButton("CorpUIRaidReady", true, { ["*type1"] = "macro" })
    readyB.icon:SetTexture(ns.MEDIA .. "raid_ready")
    readyB.need = "lead"
    readyB.bindLabel = L.MOD_RAID .. " - " .. L.RAID_READY
    readyB.tip = function(t) t:AddLine(L.RAID_READY) end

    -- InitiateRolePoll n est pas restreinte : appel direct
    roleB = makeButton("CorpUIRaidRole", false)
    roleB.icon:SetTexture(ns.MEDIA .. "raid_role")
    roleB.need = "role"
    roleB.bindLabel = L.MOD_RAID .. " - " .. L.RAID_ROLE
    roleB.tip = function(t) t:AddLine(L.RAID_ROLE) end
    roleB:SetScript("OnClick", function()
        if InitiateRolePoll then pcall(InitiateRolePoll) end
    end)

    pullB = makeButton("CorpUIRaidPull", true, { ["*type1"] = "macro", ["*type2"] = "macro" })
    pullB.icon:SetTexture(ns.MEDIA .. "raid_pull")
    pullB.need = "lead"
    pullB.bindLabel = L.MOD_RAID .. " - " .. string.format(L.RAID_PULL, db.pull)
    pullB.tip = function(t)
        t:AddLine(string.format(L.RAID_PULL, db.pull))
        t:AddLine(L.RAID_TIP_PULL, 1, 1, 1)
        t:AddLine(L.RAID_TIP_PULL_CANCEL, 1, 1, 1)
    end
    -- secondes restantes au centre ; au repos, la duree dans le coin
    pullB.count = pullB:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(pullB.count, 12)
    pullB.count:SetPoint("TOPLEFT", 0, 0)
    pullB.count:SetPoint("BOTTOMRIGHT", 0, 0)
    pullB.count:SetTextColor(1, 1, 1)
    pullB.idle = pullB:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    pullB.idle:SetPoint("BOTTOMRIGHT", -1, 1)

    convertB = makeButton("CorpUIRaidConvert", true, { ["*type1"] = "click" })
    convertB.icon:SetTexture(ns.MEDIA .. "raid_convert")
    convertB.need = "convert"
    convertB.bindLabel = L.MOD_RAID .. " - " .. L.RAID_CONVERT
    convertB.tip = function(t) t:AddLine(L.RAID_CONVERT) end

    assistB = makeButton("CorpUIRaidAssist", true, { ["*type1"] = "click" })
    assistB.icon:SetTexture(ns.MEDIA .. "raid_assist")
    assistB.need = "assist"
    assistB.bindLabel = L.MOD_RAID .. " - " .. L.RAID_ASSIST
    assistB.tip = function(t)
        t:AddLine(L.RAID_ASSIST)
        t:AddLine(flag(IsEveryoneAssistant) and L.RAID_STATE_ON or L.RAID_STATE_OFF, 1, 0.82, 0)
    end
end

---------------------------------------------------------------------------
-- Etat affiche (autorise en combat : textures et textes seulement)
---------------------------------------------------------------------------

local function allowed(b, s)
    local need = b.need
    if need == "mark" then
        return s.mark, L.RAID_NEED_LEAD
    elseif need == "lead" or need == "role" then
        if not s.group then return false, L.RAID_NEED_GROUP end
        if need == "role" then return s.lead and not s.lfg and not s.bg, L.RAID_NEED_LEAD end
        return s.lead, L.RAID_NEED_LEAD
    elseif need == "convert" then
        if not b:GetAttribute("clickbutton") then return false, L.RAID_UNAVAILABLE end
        return s.group and not s.raid and s.leader and s.convert, L.RAID_NEED_PARTY
    elseif need == "assist" then
        if not b:GetAttribute("clickbutton") then return false, L.RAID_UNAVAILABLE end
        return s.raid and s.leader, L.RAID_NEED_RAIDLEAD
    end
    return true
end

local function refreshState()
    if not bar then return end
    local s = readState()
    for _, b in ipairs(allButtons) do
        local ok, why = allowed(b, s)
        b.ok, b.why = ok and true or false, why
        b.icon:SetDesaturated(not b.ok)
        b.icon:SetAlpha(b.ok and 1 or 0.4)
    end
    assistB.on:SetShown(s.everyone)
    -- decompte en cours : chronometre estompe sous les chiffres
    if cd.endTime then pullB.icon:SetAlpha(0.25) end
end

-- marqueurs au sol poses : pastille d or, lueur pleine
local function refreshGround()
    for i = 1, 8 do
        local b = grounds[i]
        if b and b:IsVisible() then
            local active = flag(IsRaidMarkerActive, b.wm)
            b.active = active
            b.dot:SetShown(active)
            b.glow:SetAlpha(active and 1 or 0.45)
        end
    end
end

---------------------------------------------------------------------------
-- Decompte de pull : le jeu l annonce (START_PLAYER_COUNTDOWN) ; on montre
-- les secondes sur le bouton et, en option, en grand a l ecran
---------------------------------------------------------------------------

local cdFrame = CreateFrame("Frame")
local big

local function bigFrame()
    if big then return big end
    big = CreateFrame("Frame", "CorpUIRaidBigTimer", UIParent)
    big:SetSize(320, 90)
    big:SetPoint("CENTER", UIParent, "CENTER", 0, 210)
    big:SetFrameStrata("HIGH")
    big.text = big:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(big.text, 64)
    big.text:SetAllPoints()
    local g = ns.COLORS.gold
    big.text:SetTextColor(g[1], g[2], g[3])
    big:Hide()
    return big
end

local function showCount(n)
    if pullB then
        pullB.count:SetText(n and tostring(n) or "")
        pullB.idle:SetShown(not n)
        pullB.on:SetShown(n and true or false)
        pullB.icon:SetAlpha(n and 0.25 or (pullB.ok and 1 or 0.4))
    end
    if n and db and db.bigTimer then
        local f = bigFrame()
        f.text:SetText(tostring(n))
        f:Show()
    elseif big then
        big:Hide()
    end
end

local function stopCountdown()
    cd.endTime, cd.shown = nil, nil
    cdFrame:SetScript("OnUpdate", nil)
    showCount(nil)
end

local function tick()
    if not cd.endTime then return end
    local left = cd.endTime - GetTime()
    if left <= 0 then
        stopCountdown()
        if db and db.bigTimer then
            local f = bigFrame()
            f.text:SetText(L.RAID_PULL_GO)
            f:Show()
            C_Timer.After(1.5, function() if not cd.endTime and big then big:Hide() end end)
        end
        return
    end
    local n = math.ceil(left)
    if n ~= cd.shown then
        cd.shown = n
        showCount(n)
    end
end

local function startCountdown(seconds)
    -- valeur secrete (verrou des messages en combat) : le jeu affiche le sien
    if issecret(seconds) or type(seconds) ~= "number" then return end
    if seconds <= 0 then stopCountdown() return end
    cd.endTime, cd.shown = GetTime() + seconds, nil
    cdFrame:SetScript("OnUpdate", tick)
    tick()
end

---------------------------------------------------------------------------
-- Disposition, attributs, visibilite : hors combat seulement
---------------------------------------------------------------------------

local function sections()
    local list = {}
    if db.marks then table.insert(list, marks) end
    if db.ground then table.insert(list, grounds) end
    local t = {}
    if db.tools then t[#t + 1] = readyB; t[#t + 1] = roleB; t[#t + 1] = pullB end
    if db.extras then t[#t + 1] = convertB; t[#t + 1] = assistB end
    if #t > 0 then table.insert(list, t) end
    return list
end

local function layout()
    if InCombatLockdown() then pending = true return end
    local s, gap = db.size, db.spacing
    local sep = math.max(gap, math.floor(s / 3 + 0.5))   -- entre deux groupes
    local pad = db.backdrop and 3 or 0
    local vertical = db.orient == "v"
    for _, b in ipairs(allButtons) do
        b:Hide()
        b:ClearAllPoints()
    end
    shownButtons = {}
    local along, cross, maxAlong = 0, 0, 0
    for si, sec in ipairs(sections()) do
        if si > 1 then
            if db.stacked then
                along, cross = 0, cross + s + gap
            else
                along = along + sep - gap
            end
        end
        for _, b in ipairs(sec) do
            local x, y = along, cross
            if vertical then x, y = cross, along end
            b:SetSize(s, s)
            b:SetPoint("TOPLEFT", bar, "TOPLEFT", pad + x, -(pad + y))
            b:Show()
            table.insert(shownButtons, b)
            along = along + s + gap
            maxAlong = math.max(maxAlong, along - gap)
        end
    end
    local w, h = maxAlong, cross + s
    if vertical then w, h = h, w end
    bar:SetSize(math.max(1, w + 2 * pad), math.max(1, h + 2 * pad))
    bar.back:SetShown(db.backdrop)
    bar.backBorder:SetShown(db.backdrop)
    -- textes du bouton de pull a la taille des boutons
    ns.UI.HeadFont(pullB.count, math.max(10, math.floor(s * 0.55 + 0.5)))
    setFontSize(pullB.idle, math.max(7, math.floor(s * 0.36 + 0.5)))
end

local function applyAttributes()
    if InCombatLockdown() then pending = true return end
    readyB:SetAttribute("macrotext", slashText("READYCHECK", "/readycheck"))
    local cmd = slashText("COUNTDOWN", "/countdown")
    pullB:SetAttribute("*macrotext1", cmd .. " " .. math.floor(db.pull))
    pullB:SetAttribute("*macrotext2", cmd .. " 0")
    pullB.idle:SetText(tostring(math.floor(db.pull)))
    convertB:SetAttribute("clickbutton", convertDelegate())
    assistB:SetAttribute("clickbutton", assistDelegate())
end

local function applyVisibility()
    if not bar then return end
    if InCombatLockdown() then pending = true return end
    local on = db.enabled and #shownButtons > 0
    local cond
    -- poignees de deplacement affichees : barre visible pour la placer
    if on and not ns.moversShown then
        if db.vis == "lead" then
            local s = readState()
            cond = (s.group and s.lead) and VIS_DRIVERS.group or "hide"
        else
            cond = VIS_DRIVERS[db.vis]
        end
    end
    if cond then
        if cond ~= lastDriver then
            RegisterStateDriver(bar, "visibility", cond)
            lastDriver = cond
        end
    else
        if lastDriver then
            UnregisterStateDriver(bar, "visibility")
            lastDriver = nil
        end
        bar:SetShown(on and true or false)
    end
end

local function apply()
    if not bar then return end
    if InCombatLockdown() then pending = true return end
    pending = false
    applyAttributes()
    layout()
    applyVisibility()
    refreshState()
end

local function build()
    if InCombatLockdown() then needBuild = true return end
    needBuild = false
    db.pos = db.pos or { point = "TOP", x = 0, y = -40 }
    bar = CreateFrame("Frame", "CorpUIRaidBar", UIParent)
    bar:SetSize(1, 1)
    ns.ApplyPos(bar, db.pos)
    bar.backBorder, bar.back = ns.UI.Skin(bar, 0.75, false)
    ns.UI.Mover(bar, db.pos, L.MOD_RAID)
    buildMarks()
    buildGround()
    buildTools()
    -- etat des marqueurs au sol et des droits, deux fois par seconde
    local since = 0
    bar:SetScript("OnUpdate", function(_, dt)
        since = since + dt
        if since < 0.5 then return end
        since = 0
        refreshGround()
        refreshState()
    end)
    apply()
end

---------------------------------------------------------------------------
-- Panneau d options
---------------------------------------------------------------------------

local win
local warned = false     -- message "apres le combat" deja donne pour ce combat

local function changed()
    if not bar then return end
    if InCombatLockdown() then
        pending = true
        if not warned then
            warned = true
            ns.Say(L.RAID_AFTER_COMBAT)
        end
        return
    end
    apply()
end

local function buildWindow()
    win = ns.UI.Window("CorpUIRaidOptions", ns.TITLE .. " - " .. L.MOD_RAID, nil, 440, 400)
    local form = ns.UI.Form(win, -34, changed)
    local function check(key, text)
        form:Check(text, function() return db[key] end, function(v) db[key] = v end)
    end
    check("enabled", L.RAID_OPT_ENABLE)
    form:Columns(2)
    form:Cycle(L.RAID_OPT_LAYOUT, { "h", "v" }, { h = L.RAID_LAYOUT_H, v = L.RAID_LAYOUT_V },
        function() return db.orient end, function(v) db.orient = v end)
    form:Cycle(L.RAID_OPT_VIS, { "always", "group", "raid", "lead" },
        { always = L.RAID_VIS_ALWAYS, group = L.RAID_VIS_GROUP, raid = L.RAID_VIS_RAID, lead = L.RAID_VIS_LEAD },
        function() return db.vis end, function(v) db.vis = v end)
    form:Number(L.RAID_OPT_SIZE, function() return db.size end, function(v) db.size = v end, 16, 48, 1)
    form:Number(L.RAID_OPT_SPACING, function() return db.spacing end, function(v) db.spacing = v end, 0, 12, 1)
    form:EndColumns()
    form:Columns(2)
    check("stacked", L.RAID_OPT_STACKED)
    check("backdrop", L.RAID_OPT_BACKDROP)
    form:EndColumns()
    form:Gap(4)
    form:Header(L.RAID_OPT_BUTTONS)
    form:Columns(2)
    check("marks", L.RAID_OPT_MARKS)
    check("ground", L.RAID_OPT_GROUND)
    check("tools", L.RAID_OPT_TOOLS)
    check("extras", L.RAID_OPT_EXTRAS)
    form:Number(L.RAID_OPT_PULL, function() return db.pull end, function(v) db.pull = v end, 3, 60, 1)
    form:EndColumns()
    check("bigTimer", L.RAID_OPT_BIG)
    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", win, "TOPLEFT", 8, form.y - 6)
    hint:SetPoint("TOPRIGHT", win, "TOPRIGHT", -8, form.y - 6)
    hint:SetHeight(48)
    hint:SetJustifyH("LEFT")
    hint:SetJustifyV("TOP")
    hint:SetText(L.RAID_HINT)
    win:HookScript("OnShow", function() form:Refresh() end)
end

local function toggle()
    if not win then buildWindow() end
    ns.ShowPanel(win)
end

-- /corp raid diag : ce que la barre a trouve sur ce client (chat + sauvegarde)
local function diag()
    local s = readState()
    local out = {
        "commands: " .. slashText("READYCHECK", "?") .. " " .. slashText("COUNTDOWN", "?"),
        string.format("group=%s raid=%s leader=%s assist=%s everyone=%s", tostring(s.group), tostring(s.raid),
            tostring(s.leader), tostring(s.assist), tostring(s.everyone)),
        "convert button: " .. (convertDelegate() and "ok" or "-") .. "  everyone-assist button: "
            .. (assistDelegate() and "ok" or "-"),
        "combat=" .. tostring(InCombatLockdown() and true or false) .. " bar=" .. tostring(bar and bar:IsShown() or false)
            .. " driver=" .. tostring(lastDriver),
    }
    if db then db.diag = out end
    ns.Say("raid diag")
    for _, line in ipairs(out) do ns.Chat("  " .. line) end
end

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        root.raid = root.raid or {}
        db = root.raid
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = v end
        end
        build()
    elseif not db then
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        warned = false
        if needBuild then build() elseif pending then apply() end
    elseif event == "START_PLAYER_COUNTDOWN" then
        -- (initiatedBy, timeRemaining, totalTime, ...)
        startCountdown(a2)
    elseif event == "CANCEL_PLAYER_COUNTDOWN" then
        stopCountdown()
    elseif not bar then
        return
    elseif event == "ADDON_LOADED" then
        -- boutons de Blizzard charges plus tard (gestionnaire de raid...)
        if not InCombatLockdown() then applyAttributes() end
        refreshState()
    else
        -- groupe, chef, assistants : visibilite "chef ou assistant" (hors
        -- combat, sinon differee) et boutons grises
        if db.vis == "lead" then applyVisibility() end
        refreshState()
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED",
                     "PLAYER_ENTERING_WORLD", "ADDON_LOADED", "START_PLAYER_COUNTDOWN", "CANCEL_PLAYER_COUNTDOWN" }) do
    pcall(ev.RegisterEvent, ev, e)
end

-- poignees de deplacement affichees / masquees : visibilite a revoir
local lastMovers = false
ns.Listen(function()
    if not bar or (ns.moversShown and true or false) == lastMovers then return end
    lastMovers = ns.moversShown and true or false
    applyVisibility()
end)

ns.RegisterModule({
    command = "raid",
    panelName = "CorpUIRaidOptions",
    icon = ICON .. "8",
    title = function() return L.MOD_RAID end,
    desc = function() return L.RAID_DESC end,
    Slash = function(input)
        if strlower(strtrim(input or "")) == "diag" then diag() return end
        toggle()
    end,
    Open = toggle,
})
