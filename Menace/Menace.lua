--[[--------------------------------------------------------------------------
    CorpUI - menace (lecture et alerte)
    La menace s affiche dans le compteur : mode "Menace" d une fenetre
    (Compteur.lua), une ligne par membre du groupe (familiers compris) sur
    la liste de menace de ta cible, la plus haute en haut, le tank marque
    d un bouclier. Ici : la lecture (ns.Threat), l apercu du
    deverrouillage, l alerte au centre de l ecran (et son) quand tu
    approches de prendre l aggro, et la section "Menace" du panneau du
    compteur (ns.ThreatOptions).

    Ce que le client laisse lire : UnitDetailedThreatSituation(unite,
    "target") (tank ?, etat 0-3, % de la menace qu il faut pour prendre
    l aggro, valeur). Contre un boss, les valeurs sont secretes : elles vont
    telles quelles aux barres et aux textes (permis), sans tri ni calcul ;
    l alerte lit alors UnitThreatSituation("player", "target"), dont l etat
    reste lisible (1 = plus de menace que le tank sans l avoir prise).
    Alerte : relevee 5 fois par seconde en combat, contre une cible ennemie.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local issecret = issecretvalue or function() return false end

local DEFAULTS = { warn = true, warnPct = 80, warnSound = true, raw = false }
local TANK_ICON = "Interface\\GroupFrame\\UI-Group-MainTankIcon"

local db
local warnFrame
local elapsed = 0
local warned = false

local function readable(v) return not issecret(v) and v ~= nil end
-- valeur par defaut sans tester une valeur secrete (test et comparaison interdits)
local function orDefault(v, d)
    if issecret(v) then return v end
    if v == nil then return d end
    return v
end

local function inCombat()
    if InCombatLockdown() then return true end
    local ok, v = pcall(UnitAffectingCombat, "player")
    return ok and readable(v) and v or false
end

---------------------------------------------------------------------------
-- Lecture
---------------------------------------------------------------------------

local function unitList()
    local list = {}
    local function add(u)
        local ok, e = pcall(UnitExists, u)
        if ok and readable(e) and e then table.insert(list, u) end
    end
    if IsInRaid() then
        for i = 1, (GetNumGroupMembers() or 0) do
            add("raid" .. i)
            add("raidpet" .. i)
        end
    else
        add("player")
        add("pet")
        for i = 1, 4 do
            add("party" .. i)
            add("partypet" .. i)
        end
    end
    return list
end

-- cible avec une liste de menace (ennemi attaquable)
local function hostileTarget()
    local ok, e = pcall(UnitExists, "target")
    if not (ok and readable(e) and e) then return false end
    local okA, can = pcall(UnitCanAttack, "player", "target")
    return okA and readable(can) and can or false
end

local function isMe(unit)
    local ok, v = pcall(UnitIsUnit, unit, "player")
    return ok and readable(v) and v or false
end

-- lignes : { unit, name, class, tanking, status, scaled, value, me, secret }
local function collect()
    local out, secret = {}, false
    if not hostileTarget() then return out, false end
    for _, u in ipairs(unitList()) do
        local ok, tanking, status, scaled, _, value = pcall(UnitDetailedThreatSituation, u, "target")
        -- rien (pas sur la liste) : status nil ; secret : sur la liste
        if ok and (issecret(status) or status ~= nil) then
            local s = issecret(tanking) or issecret(status) or issecret(scaled)
            if s then secret = true end
            local okN, name = pcall(UnitName, u)
            local okC, _, class = pcall(UnitClass, u)
            table.insert(out, {
                unit = u, name = okN and orDefault(name, "?") or "?", class = okC and readable(class) and class or nil,
                tanking = tanking, status = status, scaled = scaled, value = value, me = isMe(u), secret = s,
            })
        end
    end
    -- tri : seulement si tout est lisible (comparer un secret est interdit)
    if not secret then
        table.sort(out, function(a, b)
            local x, y = tonumber(a.scaled) or 0, tonumber(b.scaled) or 0
            if x ~= y then return x > y end
            return (a.tanking and 1 or 0) > (b.tanking and 1 or 0)
        end)
    end
    return out, secret
end

-- apercu du deverrouillage : lignes fictives
local function fakeRows()
    local _, myClass = UnitClass("player")
    return {
        { name = L.THREAT_FAKE_TANK, class = "WARRIOR", scaled = 100, tanking = true, status = 3, value = 18400 },
        { name = orDefault(UnitName("player"), "?"), class = myClass, scaled = 86, status = 0, value = 15800, me = true },
        { name = L.THREAT_FAKE_DPS, class = "MAGE", scaled = 64, status = 0, value = 11800 },
        { name = L.THREAT_FAKE_HEAL, class = "PRIEST", scaled = 31, status = 0, value = 5700 },
    }
end

local function targetName()
    local ok, n = pcall(UnitName, "target")
    if ok then return orDefault(n, "") end
    return ""
end

ns.Threat = {
    Collect = collect,
    Fake = fakeRows,
    TargetName = targetName,
    HostileTarget = hostileTarget,
    TANK_ICON = TANK_ICON,
    -- valeur brute affichee a cote du % (reglage)
    ShowRaw = function() return db and db.raw or false end,
}

---------------------------------------------------------------------------
-- Alerte (avant de prendre l aggro)
---------------------------------------------------------------------------

local function role()
    local ok, r = pcall(UnitGroupRolesAssigned, "player")
    return ok and readable(r) and r or nil
end

local function hideWarn()
    if warnFrame and warnFrame:IsShown() then warnFrame:Hide() end
end

local function checkWarn()
    if not db.warn or ns.moversShown or role() == "TANK" or not inCombat() or not hostileTarget() then
        hideWarn()
        warned = false
        return
    end
    local me
    for _, e in ipairs((collect())) do if e.me then me = e end end
    local pct, tanking
    if me and readable(me.scaled) then pct = me.scaled end
    if me and readable(me.tanking) then tanking = me.tanking end
    -- etat lisible meme contre un boss
    local okS, status = pcall(UnitThreatSituation, "player", "target")
    status = okS and readable(status) and status or nil
    local danger = not tanking and ((pct and pct >= db.warnPct) or status == 1)
    if danger then
        local text = pct and string.format(L.THREAT_WARN_PCT, pct) or L.THREAT_WARN_HIGH
        warnFrame.text:SetText(text)
        local hot = (pct and pct >= 100) or status == 1
        if hot then warnFrame.text:SetTextColor(1, 0.25, 0.2) else warnFrame.text:SetTextColor(1, 0.7, 0.15) end
        warnFrame:Show()
        if not warned and db.warnSound and PlaySound then
            pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master")
        end
        warned = true
    else
        hideWarn()
        -- reamorcee nettement sous le seuil (pas de son en boucle)
        if not pct or pct < db.warnPct - 10 then warned = false end
    end
end

local function build()
    -- grand texte en haut du centre de l ecran
    warnFrame = CreateFrame("Frame", "CorpUIThreatWarning", UIParent)
    warnFrame:SetSize(400, 40)
    warnFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    warnFrame:SetFrameStrata("HIGH")
    warnFrame.text = warnFrame:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(warnFrame.text, 22)
    warnFrame.text:SetPoint("CENTER")
    warnFrame.text:SetShadowOffset(1, -1)
    warnFrame:Hide()
end

---------------------------------------------------------------------------
-- Section "Menace" du panneau du compteur
---------------------------------------------------------------------------

function ns.ThreatOptions(form, parent)
    if not db then return end
    local function chk(text, key)
        form:Check(text, function() return db[key] end, function(v) db[key] = v end)
    end
    form:Gap(4)
    form:Header(L.MOD_THREAT)
    form:Columns(2)
    chk(L.THREAT_OPT_WARN, "warn")
    chk(L.THREAT_OPT_SOUND, "warnSound")
    form:Number(L.THREAT_WARN_AT, function() return db.warnPct end, function(v) db.warnPct = math.floor(v + 0.5) end, 50, 100, 5)
    chk(L.THREAT_OPT_RAW, "raw")
    form:EndColumns()
    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, form.y - 2)
    hint:SetWidth(420)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.THREAT_HINT)
    form:Gap(math.ceil(hint:GetStringHeight() or 40) + 6)
end

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function()
    local root = ns.InitRoot()
    if type(root.threat) ~= "table" then root.threat = {} end
    db = root.threat
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    build()
end)
pcall(ev.RegisterEvent, ev, "PLAYER_LOGIN")

-- alerte : 5 fois par seconde
ev:SetScript("OnUpdate", function(_, dt)
    if not db or not warnFrame then return end
    elapsed = elapsed + dt
    if elapsed < 0.2 then return end
    elapsed = 0
    local ok, err = pcall(checkWarn)
    if not ok then
        hideWarn()
        geterrorhandler()(err)
    end
end)
