--[[--------------------------------------------------------------------------
    CorpUI - module Groupe
    Cadres de groupe (party1-4) et de raid (raid1-40), a nous.

    Chaque cadre est un bouton securise lie a une unite fixe :
      clic gauche = cibler, clic droit = menu de l unite
      RegisterUnitWatch l affiche/le masque selon que l unite existe,
      meme en combat ; un pilote d etat montre le groupe hors raid et le
      raid en raid.
    Le raid est range par groupe (une colonne par groupe) hors combat ; un
    changement de groupe en combat est applique a la sortie du combat.
    Hors de portee : le cadre s estompe (SetAlphaFromBoolean accepte le
    booleen secret de portee).
    Apercu : affiche les cadres avec le joueur, pour les placer seul.
    Pour les soigneurs (reglages communs groupe + raid, db.heal) :
      surbrillance des debuffs que l on peut dissiper (filtre "HARMFUL|RAID"),
      petites icones de debuffs, soins entrants (barre qui prend la valeur
      telle quelle, meme secrete), liseré d aggro, icones de role, de chef et
      marqueur de raid. Une valeur secrete qu on ne peut pas afficher sans la
      lire (menace, marqueur, role) n affiche simplement rien.
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local UF = ns.UF
local issecret = issecretvalue or function() return false end

local PARTY_W, PARTY_H = 200, 40
local RAID_W, RAID_H, RAID_GAP = 82, 34, 3

local db
local party, raid
local buttons = {}      -- unite -> bouton
local layoutPending = false
local hs                -- reglages "pour les soigneurs" (db.heal)
local iconSpec, nativeStyle   -- conteneurs d auras du client (plus bas)
local ICON_MAX = 6      -- icones de debuffs creees par cadre (au plus)

-- reglage d un bouton : celui du groupe ou celui du raid
local function styleOf(b) return b.big and db.partyStyle or db.raidStyle end

---------------------------------------------------------------------------
-- Pour les soigneurs : debuffs, soins entrants, aggro, icones
---------------------------------------------------------------------------

-- couleurs des types de dissipation (et "sans type" : rouge sombre)
local DISPEL_COLORS = {
    Magic = { 0.2, 0.6, 1 }, Curse = { 0.6, 0, 1 }, Disease = { 0.6, 0.4, 0 }, Poison = { 0, 0.6, 0 },
}
local NO_TYPE = { 0.8, 0, 0 }
-- numero du type dans les donnees du jeu (abscisse de la courbe de couleur)
local DISPEL_IDS = { Magic = 1, Curse = 2, Disease = 3, Poison = 4 }

-- Courbe de couleur par type : C_UnitAuras.GetAuraDispelTypeColor l evalue
-- cote client, ce qui marche meme quand le type du debuff est secret (la
-- couleur rendue l est aussi, et SetVertexColor l accepte telle quelle).
local dispelCurve
local function getCurve()
    if dispelCurve ~= nil then return dispelCurve or nil end
    dispelCurve = false
    if C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor then
        local ok, cv = pcall(C_CurveUtil.CreateColorCurve)
        if ok and cv then
            if Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then
                pcall(cv.SetType, cv, Enum.LuaCurveType.Step)
            end
            pcall(cv.AddPoint, cv, 0, CreateColor(NO_TYPE[1], NO_TYPE[2], NO_TYPE[3], 1))
            for name, id in pairs(DISPEL_IDS) do
                local k = DISPEL_COLORS[name]
                pcall(cv.AddPoint, cv, id, CreateColor(k[1], k[2], k[3], 1))
            end
            pcall(cv.AddPoint, cv, 5, CreateColor(NO_TYPE[1], NO_TYPE[2], NO_TYPE[3], 1))
            dispelCurve = cv
        end
    end
    return dispelCurve or nil
end

-- premier debuff a dissiper : ceux de MA classe (filtre "RAID" du jeu), ou
-- tous les dissipables ("DISPELLABLE", repli sur "RAID" si refuse).
-- Par identifiants (ns.UnitAuraList) : lisible meme en combat, ou les
-- donnees des auras sont secretes. Renvoie une entree { id, aura } ou nil.
local badFilter = {}
local function dispelFilter()
    local filter = hs.dispelAll and "HARMFUL|DISPELLABLE" or "HARMFUL|RAID"
    if badFilter[filter] then filter = "HARMFUL|RAID" end
    return filter
end
local function findDispel(unit)
    local filter = dispelFilter()
    local list, accepted = ns.UnitAuraList(unit, filter, false, 1)
    if not accepted and filter ~= "HARMFUL|RAID" then
        badFilter[filter] = true
        list = ns.UnitAuraList(unit, "HARMFUL|RAID", false, 1)
    end
    return list[1]
end

-- couleur du type d un debuff : true, r, g, b, a (valeurs peut-etre secretes)
local function auraColor(unit, e)
    -- type lisible : notre couleur ; secret (ou aura illisible) : courbe du client
    local okD, d = pcall(function() return e.aura.dispelName end)
    if okD and not issecret(d) then
        local k = (type(d) == "string" and DISPEL_COLORS[d]) or NO_TYPE
        return true, k[1], k[2], k[3], 1
    end
    local cv = getCurve()
    if not cv or not (C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor) then return false end
    if not e.id then return false end
    local ok, col = pcall(C_UnitAuras.GetAuraDispelTypeColor, unit, e.id, cv)
    if not ok or type(col) ~= "table" or not col.GetRGBA then return false end
    local ok2, r, g, b, al = pcall(col.GetRGBA, col)
    if not ok2 then return false end
    return true, r, g, b, al
end

-- liseré de 4 textures blanches, a teinter : interieur ou exterieur au cadre
local function makeEdge(parent, outside, size, sub)
    local e = {}
    local o = outside and size or 0
    for i = 1, 4 do
        e[i] = parent:CreateTexture(nil, "OVERLAY", nil, sub)
        e[i]:SetColorTexture(1, 1, 1, 1)
        e[i]:Hide()
    end
    e[1]:SetPoint("TOPLEFT", -o, o)
    e[1]:SetPoint("TOPRIGHT", o, o)
    e[1]:SetHeight(size)
    e[2]:SetPoint("BOTTOMLEFT", -o, -o)
    e[2]:SetPoint("BOTTOMRIGHT", o, -o)
    e[2]:SetHeight(size)
    e[3]:SetPoint("TOPLEFT", -o, o)
    e[3]:SetPoint("BOTTOMLEFT", -o, -o)
    e[3]:SetWidth(size)
    e[4]:SetPoint("TOPRIGHT", o, o)
    e[4]:SetPoint("BOTTOMRIGHT", o, -o)
    e[4]:SetWidth(size)
    function e.Show(v) for i = 1, 4 do e[i]:SetShown(v) end end
    -- couleur (secrete acceptee) ; false si refusee
    function e.Color(r, g, b, a)
        for i = 1, 4 do
            if not pcall(e[i].SetVertexColor, e[i], r, g, b, a) then return false end
        end
        return true
    end
    return e
end

-- Soins entrants. Le calculateur du client (CreateUnitHealPredictionCalculator)
-- borne le soin a la vie manquante ; sinon UnitGetIncomingHeals. La valeur
-- est souvent secrete : elle va telle quelle dans une barre (permis).
local function incomingHeals(unit) return UF.IncomingHeals(unit) end

local function updateHeal(b, unit)
    if not hs or not hs.heal or b.down or not b.healOk then b.heal:Hide() return end
    local v = incomingHeals(unit)
    local okM, max = pcall(UnitHealthMax, unit)
    -- nombre lisible ou secret ; nil (aucun soin) : rien
    if okM and (issecret(v) or type(v) == "number") and UF.SetBar(b.heal, v, max) then
        b.heal:Show()
    else
        b.heal:Hide()
    end
end

-- aggro : UnitThreatSituation(unit) seul ; 2 ou 3 = l unite a l aggro.
-- Secret : le jeu n offre rien pour l afficher sans le lire, on n affiche rien.
local function updateAggro(b, unit)
    local show = false
    if hs and hs.aggro and not b.down and UnitThreatSituation then
        local ok, st = pcall(UnitThreatSituation, unit)
        if ok and not issecret(st) and type(st) == "number" then show = st >= 2 end
    end
    b.aggro.Show(show)
end

-- debuffs : surbrillance du cadre et petites icones
local function setIcon(f, unit, e)
    if not pcall(function() f.tex:SetTexture(e.aura.icon) end) then f.tex:SetTexture(nil) end
    local ok, r, g, bl = auraColor(unit, e)
    if not ok or not pcall(f.border.SetVertexColor, f.border, r, g, bl, 1) then
        f.border:SetVertexColor(NO_TYPE[1], NO_TYPE[2], NO_TYPE[3], 1)
    end
    if not pcall(f.count.SetText, f.count, ns.AuraCountText(unit, e.id, e.aura)) then f.count:SetText("") end
end

-- conteneurs du client : reglages et unite (le contenu se met a jour seul)
local function updateNative(b, unit)
    if b.nUnit ~= unit then
        b.nUnit = unit
        if b.nIcons then b.nIcons:SetUnit(unit) end
        if b.nDispel then b.nDispel:SetUnit(unit) end
    end
    -- appele a chaque changement d aura (souvent en combat) : on ne touche
    -- aux conteneurs du client que si quelque chose change, et jamais en
    -- combat (ils peuvent y etre proteges)
    local on = not b.down
    local icons, disp = (hs and hs.icons and on) and true or false, (hs and hs.dispel and on) and true or false
    local filter, style, alpha = dispelFilter(), hs and hs.dispelStyle, hs and hs.tintAlpha
    local st = b.nSt
    if st and st.icons == icons and st.disp == disp and st.filter == filter and st.style == style
        and st.alpha == alpha and st.mine == b.dispelMine then return end
    if InCombatLockdown() then return end
    if not st then st = {} b.nSt = st end
    st.icons, st.disp, st.filter, st.style, st.alpha, st.mine = icons, disp, filter, style, alpha, b.dispelMine
    b.nState = true
    if b.nIcons then pcall(b.nIcons.frame.SetShown, b.nIcons.frame, (hs and hs.icons and on) and true or false) end
    if b.nDispel then
        pcall(b.nDispel.frame.SetShown, b.nDispel.frame, (hs and hs.dispel and on) and true or false)
        b.nDispel:SetFilter(dispelFilter())
    end
    nativeStyle(b)
end

local function updateAuras(b, unit)
    if b.nIcons or b.nDispel then
        -- elements de l ancien chemin : caches une fois (l apercu les remontre)
        if not b.legacyHidden then
            b.dispel.Show(false)
            b.tint:Hide()
            for i = 1, ICON_MAX do b.icons[i]:Hide() end
            b.legacyHidden = true
        end
        updateNative(b, unit)
        return
    end
    -- surbrillance : couleur du type du premier debuff a dissiper
    local edgeOn, tintOn = false, false
    b.legacyDispel = false
    if hs and hs.dispel and not b.down and b.dispelMine ~= false then
        local e = findDispel(unit)
        if e then
            b.legacyDispel = true
            local ok, r, g, bl = auraColor(unit, e)
            if ok then
                if hs.dispelStyle ~= "tint" then edgeOn = b.dispel.Color(r, g, bl, 1) end
                if hs.dispelStyle ~= "border" then
                    tintOn = pcall(b.tint.SetVertexColor, b.tint, r, g, bl, (hs.tintAlpha or 35) / 100)
                end
            end
        end
    end
    b.dispel.Show(edgeOn)
    b.tint:SetShown(tintOn)
    -- icones : debuffs (tous, ou seulement ceux a dissiper)
    local n = 0
    if hs and hs.icons and not b.down then
        local filter = hs.iconsDispel and dispelFilter() or "HARMFUL"
        local max = math.min(ICON_MAX, hs.iconMax)
        for _, e in ipairs(ns.UnitAuraList(unit, filter, false, 40)) do
            if n >= max then break end
            if not ns.AuraAllowed or ns.AuraAllowed(e.aura, "group") then
                n = n + 1
                setIcon(b.icons[n], unit, e)
                b.icons[n]:Show()
            end
        end
    end
    for i = n + 1, ICON_MAX do b.icons[i]:Hide() end
end

-- icones de role (bouclier, croix, epee) : atlas si le client l a
local ROLE_ATLAS = { TANK = "roleicon-tiny-tank", HEALER = "roleicon-tiny-healer", DAMAGER = "roleicon-tiny-dps" }
local ROLE_COORDS = { TANK = { 0, 19 / 64, 22 / 64, 41 / 64 }, HEALER = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 },
                      DAMAGER = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 } }

local function setRole(t, role)
    local atlas = ROLE_ATLAS[role]
    local okA, info = false, nil
    if C_Texture and C_Texture.GetAtlasInfo then okA, info = pcall(C_Texture.GetAtlasInfo, atlas) end
    if okA and info and t.SetAtlas and pcall(t.SetAtlas, t, atlas) then return end
    t:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
    t:SetTexCoord(unpack(ROLE_COORDS[role]))
end

local function updateIcons(b, unit, fake)
    local sz = b.big and 14 or 11
    local x = 3
    -- role puis chef, en haut a gauche, a cheval sur le bord
    local function place(t, on)
        t:SetShown(on and true or false)
        if on then
            t:ClearAllPoints()
            t:SetSize(sz, sz)
            t:SetPoint("CENTER", b, "TOPLEFT", x + sz / 2, 0)
            x = x + sz + 1
        end
    end
    local role
    if fake then
        role = hs and hs.role and fake.role or nil
    elseif hs and hs.role and UnitGroupRolesAssigned then
        local ok, r = pcall(UnitGroupRolesAssigned, unit)
        if ok and not issecret(r) and type(r) == "string" and ROLE_COORDS[r] then role = r end
    end
    if role then setRole(b.roleIcon, role) end
    place(b.roleIcon, role)
    local lead, assist
    if fake then
        lead = hs and hs.leader and fake.lead
        assist = hs and hs.leader and not lead and not b.big and fake.assist
    else
        lead = hs and hs.leader and UF.Flag(UnitIsGroupLeader, unit)
        assist = hs and hs.leader and not lead and IsInRaid() and UF.Flag(UnitIsGroupAssistant, unit)
    end
    if lead then
        b.leadIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
    elseif assist then
        b.leadIcon:SetTexture("Interface\\GroupFrame\\UI-Group-AssistantIcon")
    end
    place(b.leadIcon, lead or assist)
    -- marqueur de raid : numero secret sur ce client, pose par
    -- ns.RaidMark (SetSpriteSheetCell) ; position, taille, decalage et
    -- opacite reglables (16/10)
    local shown = false
    if hs and hs.marker then
        if fake then
            shown = fake.mark and ns.RaidMark(b.markIcon, nil, fake.mark) or false
        else
            shown = ns.RaidMark(b.markIcon, unit)
        end
    end
    if shown then
        ns.UI.PlaceRaidMark(b.markIcon, b, hs.markPos, hs.markSize, hs.markX, hs.markY, hs.markAlpha)
    end
    b.markIcon:SetShown(shown)
end

-- tout ce qui sert aux soigneurs, d un coup
local function updateHealer(b, unit)
    updateHeal(b, unit)
    updateAuras(b, unit)
    updateAggro(b, unit)
    updateIcons(b, unit)
end

-- icones de debuffs : en bas a gauche de la barre de vie (hors combat)
local function layoutIcons(b)
    if not hs then return end
    if b.nIcons then b.nIcons:Apply(iconSpec(b)) end
    local s = styleOf(b)
    local sz = math.max(6, math.min(hs.iconSize, s.hp - 2))
    for i = 1, ICON_MAX do
        local f = b.icons[i]
        f:ClearAllPoints()
        f:SetSize(sz, sz)
        f:SetPoint("BOTTOMLEFT", b.hp, "BOTTOMLEFT", 1 + (i - 1) * (sz + 1), 1)
        local reg = (ns.FontFile and ns.FontFile("regular")) or STANDARD_TEXT_FONT
        pcall(f.count.SetFont, f.count, reg, math.max(7, math.floor(sz * 0.6)), "OUTLINE")
    end
end

---------------------------------------------------------------------------
-- Boutons
---------------------------------------------------------------------------

-- deconnecte : lu seulement s il n est pas secret (secret : connecte)
local function offline(unit)
    local ok, v = pcall(UnitIsConnected, unit)
    if not ok or issecret(v) then return false end
    return not v
end

-- vie : etat (mort, fantome, deconnecte), couleur, barre, texte
local function updateHealth(b, unit)
    local s = styleOf(b)
    local ghost = UF.Flag(UnitIsGhost, unit)
    local dead = not ghost and UF.Flag(UnitIsDead, unit)
    local off = not ghost and not dead and offline(unit)
    -- mort, fantome ou deconnecte : barre grise, rien pour les soigneurs
    b.down = ghost or dead or off
    if b.down then
        b.hp:SetStatusBarColor(0.45, 0.45, 0.45)
    elseif s.color == "theme" then
        local a = ns.COLORS.violet
        b.hp:SetStatusBarColor(a[1], a[2], a[3])
    else
        b.hp:SetStatusBarColor(UF.HealthColor(unit))
    end
    if off then b.name:SetTextColor(0.6, 0.6, 0.6) else b.name:SetTextColor(1, 1, 1) end
    local okC, cur = pcall(UnitHealth, unit)
    local okM, max = pcall(UnitHealthMax, unit)
    if okC and okM then UF.SetBar(b.hp, cur, max) end
    if ghost then
        b.hpText:SetText(L.FRAMES_GHOST)
    elseif dead then
        b.hpText:SetText(L.FRAMES_DEAD)
    elseif off then
        b.hpText:SetText(L.FRAMES_OFFLINE)
    elseif okC and okM then
        UF.SetText(b.hpText, unit, "health", cur, max, s.hpText)
    end
end

-- puissance : barre, texte, couleur
local function updatePower(b, unit)
    local okP, p = pcall(UnitPower, unit)
    local okX, px = pcall(UnitPowerMax, unit)
    if okP and okX then
        UF.SetBar(b.pw, p, px)
        if b.pwText:IsShown() then UF.SetText(b.pwText, unit, "power", p, px, "value") end
    end
    b.pw:SetStatusBarColor(UF.PowerColor(unit))
end

-- vie, mana, textes : le coeur du cadre (nom et niveau compris)
local function updateCore(b, unit)
    local okN, name = pcall(UnitName, unit)
    if okN then
        if issecret(name) then pcall(b.name.SetText, b.name, name) else b.name:SetText(name or "") end
    end
    updateHealth(b, unit)
    updatePower(b, unit)
    local okL, lv = pcall(UnitLevel, unit)
    b.level:SetText(okL and not issecret(lv) and type(lv) == "number" and lv > 0 and lv or "")
end

---------------------------------------------------------------------------
-- Apercu (page des cadres ouverte, ou interface deverrouillee) : chaque
-- cadre montre un membre fictif (b.fakeIndex), rendu avec les vrais
-- reglages : classes, vies, mort / deconnecte, soins entrants, aggro,
-- icones, debuffs et surbrillance de dissipation de chaque type.
---------------------------------------------------------------------------

local PV_CLASSES = { "WARRIOR", "PRIEST", "MAGE", "ROGUE", "DRUID", "PALADIN", "HUNTER", "WARLOCK", "SHAMAN" }
local PV_NAMES = { "Brakka", "Lunelle", "Sylvae", "Ombrelame", "Feuillage", "Thorgrim", "Kaelis", "Morvane",
    "Tonnerre", "Gorlak", "Elyndra", "Pyros", "Silene", "Ronce", "Aldric", "Fennir", "Nyx", "Brume", "Hildra",
    "Oskar", "Velka", "Tamsin", "Draven", "Isolde", "Grimm" }
local PV_HP = { 1, 0.62, 0.85, 0.34, 1, 0.91, 0.15, 0.77, 1, 0.48 }
local PV_DISPEL = { [2] = "Magic", [3] = "Curse", [5] = "Poison", [7] = "Disease", [11] = "Magic", [14] = "Curse",
    [18] = "Poison", [22] = "Disease" }
local PV_ICON = { Magic = "Interface\\Icons\\Spell_Frost_FrostNova", Curse = "Interface\\Icons\\Spell_Shadow_CurseOfSargeras",
    Disease = "Interface\\Icons\\Spell_Shadow_CreepingPlague", Poison = "Interface\\Icons\\Spell_Nature_CorrosiveBreath",
    none = "Interface\\Icons\\Ability_Gouge" }
local PV_HEALERS = { PRIEST = true, DRUID = true, PALADIN = true, SHAMAN = true }
local PV_POWER = { WARRIOR = { 0.78, 0.15, 0.15 }, ROGUE = { 1, 0.85, 0.1 } }

local function fakeOf(n)
    local class = PV_CLASSES[(n - 1) % #PV_CLASSES + 1]
    local d = { name = PV_NAMES[n] or ("#" .. n), class = class, max = 4000 + (n * 137) % 2000 }
    d.hp = PV_HP[(n - 1) % #PV_HP + 1]
    d.dead, d.offline = n == 9, n == 17
    d.role = n % 5 == 1 and "TANK" or (PV_HEALERS[class] and "HEALER") or "DAMAGER"
    d.lead, d.assist = n == 1, n == 2
    d.mark = (n == 1 and 8) or (n == 6 and 7) or nil
    d.aggro = n == 1
    d.heal = (n == 4 and 0.3) or (n == 7 and 0.2) or nil
    d.dispel = PV_DISPEL[n]
    d.debuffs = {}
    if d.dispel then d.debuffs[#d.debuffs + 1] = { type = d.dispel, icon = PV_ICON[d.dispel], count = n == 5 and 3 or nil } end
    if n % 4 == 0 then d.debuffs[#d.debuffs + 1] = { icon = PV_ICON.none } end
    if n == 3 then d.debuffs[#d.debuffs + 1] = { type = "Magic", icon = PV_ICON.Magic } end
    d.pw = class == "WARRIOR" and 35 or class == "ROGUE" and 80 or 70
    d.pwMax = 100
    return d
end

local function fakeHpText(mode, cur, max)
    local pct = max > 0 and math.floor(cur / max * 100 + 0.5) or 0
    local function ab(v)
        local ok, a = pcall(AbbreviateNumbers or tostring, v)
        return ok and a or tostring(v)
    end
    if mode == "none" then return "" end
    if mode == "cur" then return ab(cur) end
    if mode == "pct" then return pct .. "%" end
    if mode == "both" then return ab(cur) .. " / " .. ab(max) .. "  " .. pct .. "%" end
    return ab(cur) .. " / " .. ab(max)
end

local function fakeAuras(b, d)
    -- conteneurs du client caches pendant l apercu (hors combat) ; remis par
    -- updateNative (nState oublie) a la fin de l apercu
    if not InCombatLockdown() then
        if b.nIcons then pcall(b.nIcons.frame.SetShown, b.nIcons.frame, false) end
        if b.nDispel then pcall(b.nDispel.frame.SetShown, b.nDispel.frame, false) end
        b.nState, b.nSt = nil, nil
    end
    local edgeOn, tintOn = false, false
    if hs and hs.dispel and not b.down and d.dispel then
        local k = DISPEL_COLORS[d.dispel]
        if hs.dispelStyle ~= "tint" then edgeOn = b.dispel.Color(k[1], k[2], k[3], 1) end
        if hs.dispelStyle ~= "border" then
            b.tint:SetVertexColor(k[1], k[2], k[3], (hs.tintAlpha or 35) / 100)
            tintOn = true
        end
    end
    b.dispel.Show(edgeOn)
    b.tint:SetShown(tintOn)
    local n = 0
    if hs and hs.icons and not b.down then
        local max = math.min(ICON_MAX, hs.iconMax)
        for _, a in ipairs(d.debuffs) do
            if n >= max then break end
            if not hs.iconsDispel or a.type then
                n = n + 1
                local f = b.icons[n]
                f.tex:SetTexture(a.icon)
                local k = (a.type and DISPEL_COLORS[a.type]) or NO_TYPE
                f.border:SetVertexColor(k[1], k[2], k[3], 1)
                f.count:SetText(a.count and tostring(a.count) or "")
                f:Show()
            end
        end
    end
    for i = n + 1, ICON_MAX do b.icons[i]:Hide() end
end

local function fakeButton(b)
    b.legacyHidden = nil
    local d = fakeOf(b.fakeIndex)
    local s = styleOf(b)
    b.down = d.dead or d.offline
    b.name:SetText(d.name)
    if d.offline then b.name:SetTextColor(0.6, 0.6, 0.6) else b.name:SetTextColor(1, 1, 1) end
    local cur = d.dead and 0 or math.floor(d.max * d.hp)
    UF.SetBar(b.hp, cur, d.max)
    local cr, cg, cb = ns.ClassColor(d.class)
    if b.down then
        b.hp:SetStatusBarColor(0.45, 0.45, 0.45)
    elseif s.color == "theme" then
        local a = ns.COLORS.violet
        b.hp:SetStatusBarColor(a[1], a[2], a[3])
    else
        b.hp:SetStatusBarColor(cr, cg, cb)
    end
    if d.dead then
        b.hpText:SetText(L.FRAMES_DEAD)
    elseif d.offline then
        b.hpText:SetText(L.FRAMES_OFFLINE)
    else
        b.hpText:SetText(fakeHpText(s.hpText, cur, d.max))
    end
    UF.SetBar(b.pw, d.pw, d.pwMax)
    local pc = PV_POWER[d.class] or { 0, 0.44, 0.87 }
    b.pw:SetStatusBarColor(pc[1], pc[2], pc[3])
    if b.pwText:IsShown() then b.pwText:SetText(d.pw .. " / " .. d.pwMax) end
    b.level:SetText("60")
    if hs and hs.heal and not b.down and b.healOk and d.heal then
        b.heal:SetMinMaxValues(0, d.max)
        b.heal:SetValue(math.floor(d.max * d.heal))
        b.heal:Show()
    else
        b.heal:Hide()
    end
    b.aggro.Show((hs and hs.aggro and d.aggro and not b.down) and true or false)
    updateIcons(b, nil, d)
    fakeAuras(b, d)
end

local function update(b)
    if b.fakeIndex then fakeButton(b) return end
    local unit = b:GetAttribute("unit")
    if not unit or not UnitExists(unit) then return end
    updateCore(b, unit)
    updateHealer(b, unit)
end

-- icones de debuffs par le conteneur du client
iconSpec = function(b)
    local s = b and styleOf(b)
    local sz = 14
    if hs and s then sz = math.max(6, math.min(hs.iconSize, s.hp - 2)) end
    local filter = (hs and hs.iconsDispel) and dispelFilter() or "HARMFUL"
    local max = hs and math.min(ICON_MAX, hs.iconMax) or 3
    local cand = {}
    if ns.AurasSpellFilter then cand = ns.AurasSpellFilter("group") end
    return {
        width = sz, height = sz, spacing = 1, perRow = max, max = max, grow = "up", fromRight = false,
        time = "none", countSize = math.max(7, math.floor(sz * 0.6)), noMouse = true,
        anchor = { b and b.hp, "BOTTOMLEFT", 1, 1 },
        groups = { { key = "icons", filter = filter, candidate = cand } },
    }
end

-- surbrillance de dissipation : liseré (4 bords) et teinte, teints par le
-- client selon le type du premier debuff a dissiper
local function buildDispelSlot(b, btn)
    local map = ns.DispelColorMap and ns.DispelColorMap()
    local style = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
    local function reg(t)
        if style then
            pcall(btn.AddDispelTypeTexture, btn, t, { style = style.PreserveAsset, showWhenHarmful = true,
                customDispelColorMap = map })
        end
    end
    local e = {}
    for i = 1, 4 do
        e[i] = btn:CreateTexture(nil, "OVERLAY", nil, 6)
        e[i]:SetColorTexture(1, 1, 1, 1)
    end
    e[1]:SetPoint("TOPLEFT", b, "TOPLEFT")
    e[1]:SetPoint("TOPRIGHT", b, "TOPRIGHT")
    e[1]:SetHeight(2)
    e[2]:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT")
    e[2]:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT")
    e[2]:SetHeight(2)
    e[3]:SetPoint("TOPLEFT", b, "TOPLEFT")
    e[3]:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT")
    e[3]:SetWidth(2)
    e[4]:SetPoint("TOPRIGHT", b, "TOPRIGHT")
    e[4]:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT")
    e[4]:SetWidth(2)
    local tint = btn:CreateTexture(nil, "ARTWORK")
    tint:SetAllPoints(b.hp)
    tint:SetColorTexture(1, 1, 1, 1)
    for i = 1, 4 do reg(e[i]) end
    reg(tint)
    b.nEdges, b.nTint = e, tint
    -- son a l apparition : Groupe regarde si cette case devient visible
    b.nDispelBtn = btn
    nativeStyle(b)
end

-- style choisi (liseré / teinte / les deux) : par la transparence, que le
-- client ne touche pas (il montre et cache lui-meme les textures)
-- Le bouton du client (et nos textures posees dessus) peut etre interdit
-- aux addons (11/10 : "Attempt to access forbidden object" sur raid9, au
-- passage du pilote d etat) : on n y touche pas ; la transparence voulue
-- est reprise au passage suivant.
local function setAlphaSafe(t, a)
    local okF, forbidden = pcall(t.IsForbidden, t)
    if not okF or forbidden then return end
    pcall(t.SetAlpha, t, a)
end

nativeStyle = function(b)
    if not (hs and b.nEdges) then return end
    local okF, forbidden = pcall(b.nDispelBtn.IsForbidden, b.nDispelBtn)
    if not okF or forbidden then return end
    -- repartition en raid (Dissipation) : rien sur les groupes des autres
    local mine = b.dispelMine ~= false
    local edge = (mine and hs.dispelStyle ~= "tint") and 1 or 0
    for i = 1, 4 do setAlphaSafe(b.nEdges[i], edge) end
    setAlphaSafe(b.nTint, (mine and hs.dispelStyle ~= "border") and ((hs.tintAlpha or 35) / 100) or 0)
end

-- mes groupes (repartition du module Dissipation), hors combat
local function refreshMine()
    for _, b in pairs(buttons) do
        local mine = true
        if ns.Dispel and ns.Dispel.IsMine and not b.fakeIndex then mine = ns.Dispel.IsMine(b.realUnit) end
        b.dispelMine = mine
    end
end

-- Son d alerte : la case "debuff a dissiper" d un cadre vient d apparaitre
-- (visibilite de notre cadre, aucune aura lue : marche en combat)
local function dispelShown(b)
    if b.nDispelBtn then
        local ok, v = pcall(b.nDispelBtn.IsVisible, b.nDispelBtn)
        if ok and not issecret(v) then return v and true or false end
        return false
    end
    return b.legacyDispel and true or false
end

local function checkAlerts()
    if not (hs and hs.dispel and ns.Dispel and ns.Dispel.Alert) then return end
    for _, b in pairs(buttons) do
        local on = false
        if not b.fakeIndex and not b.down and b.dispelMine ~= false and b:IsVisible() then on = dispelShown(b) end
        if on and not b.alerted then ns.Dispel.Alert(b:GetAttribute("unit")) end
        b.alerted = on
    end
end

local dispelPending = false
-- reglages de dissipation ou repartition changes (module Dissipation)
function ns.GroupDispelRefresh()
    if InCombatLockdown() then
        dispelPending = true
    else
        dispelPending = false
        refreshMine()
        for _, b in pairs(buttons) do b.nState, b.nSt = nil, nil end
    end
    for _, b in pairs(buttons) do
        if b:IsVisible() then update(b) end
    end
end

local function makeButton(parent, unit, big)
    local b = CreateFrame("Button", "CorpUI" .. unit .. "Frame", parent, "SecureActionButtonTemplate")
    b:SetSize(100, 30)
    b:SetAttribute("unit", unit)
    b:SetAttribute("type1", "target")
    b:SetAttribute("type2", "togglemenu")
    -- modele d action (et non "unite") : le modele "unite" passe chaque clic par
    -- les raccourcis de clic de Blizzard, qui ignorent ou bloquent nos reglages
    -- (Maj+clic "cibler" abandonne). Appui ET relachement : il agit a l appui
    -- si l option du jeu "action a l appui" est active.
    b:RegisterForClicks("AnyUp", "AnyDown")
    ns.RegisterUnitButton(b)
    UF.HoverTooltip(b)
    b.realUnit = unit
    b.big = big
    ns.UI.Skin(b, 0.9, big)
    -- tailles et positions : sizeButton (meme modele que les cadres d unite)
    b.hp = UF.Bar(b, 10)
    b.pw = UF.Bar(b, 3)
    local lv = b.hp:GetFrameLevel() or 1
    -- soins entrants : barre accrochee au bout du remplissage de la vie, dans
    -- un cadre qui la coupe au bord de la barre de vie
    b.healClip = CreateFrame("Frame", nil, b.hp)
    b.healClip:SetAllPoints(b.hp)
    b.healClip:SetFrameLevel(lv + 1)
    if b.healClip.SetClipsChildren then b.healClip:SetClipsChildren(true) end
    b.heal = CreateFrame("StatusBar", nil, b.healClip)
    b.heal:SetStatusBarTexture(ns.BAR_TEXTURE)
    b.heal:SetStatusBarColor(0.1, 0.9, 0.4, 0.55)
    b.heal:SetMinMaxValues(0, 1)
    b.heal:SetValue(0)
    b.heal:Hide()
    local fill = b.hp.GetStatusBarTexture and b.hp:GetStatusBarTexture()
    if fill then
        b.heal:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
        b.heal:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", 0, 0)
        b.healOk = true
    end
    -- textes au-dessus des soins entrants ; teinte de dissipation dessous
    b.txt = CreateFrame("Frame", nil, b.hp)
    b.txt:SetAllPoints(b.hp)
    b.txt:SetFrameLevel(lv + 3)
    b.tint = b.txt:CreateTexture(nil, "BACKGROUND")
    b.tint:SetAllPoints(b.hp)
    b.tint:SetColorTexture(1, 1, 1, 1)
    b.tint:Hide()
    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.name:SetWordWrap(false)
    b.name:SetJustifyH("LEFT")
    b.level = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.hpText = b.txt:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.pwText = b.pw:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.pwText:SetPoint("CENTER")
    b.pwText:Hide()
    -- calque du dessus : liserés, icones (enfants du bouton, jamais l inverse)
    b.ov = CreateFrame("Frame", nil, b)
    b.ov:SetAllPoints(b)
    b.ov:SetFrameLevel(lv + 5)
    b.dispel = makeEdge(b.ov, false, 2, 6)
    b.aggro = makeEdge(b.ov, true, 2, 7)
    b.aggro.Color(1, 0.1, 0.1, 1)
    b.roleIcon = b.ov:CreateTexture(nil, "OVERLAY")
    b.roleIcon:Hide()
    b.leadIcon = b.ov:CreateTexture(nil, "OVERLAY")
    b.leadIcon:Hide()
    b.markIcon = b.ov:CreateTexture(nil, "OVERLAY")
    b.markIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    b.markIcon:SetPoint("CENTER", b, "TOP", 0, 0)
    b.markIcon:Hide()
    -- icones de debuffs, creees d avance (rien a creer en combat)
    b.icons = {}
    for i = 1, ICON_MAX do
        local f = CreateFrame("Frame", nil, b.ov)
        f:SetSize(14, 14)
        f.border = f:CreateTexture(nil, "BACKGROUND")
        f.border:SetAllPoints()
        f.border:SetColorTexture(1, 1, 1, 1)
        f.tex = f:CreateTexture(nil, "ARTWORK")
        f.tex:SetPoint("TOPLEFT", 1, -1)
        f.tex:SetPoint("BOTTOMRIGHT", -1, 1)
        f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f.count = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.count:SetPoint("BOTTOMRIGHT", 1, -1)
        f:Hide()
        b.icons[i] = f
    end
    -- en combat, seul le client peut lire les auras : conteneurs a lui
    -- (icones + surbrillance de dissipation), habilles par nous
    if ns.NativeAuras then
        b.nIcons = ns.NativeAuras(b.ov, unit, iconSpec(b))
        b.nDispel = ns.NativeAuraSlot(b.ov, unit, "HARMFUL|RAID", function(btn) buildDispelSlot(b, btn) end)
        b.nUnit = unit
    end
    b:SetScript("OnShow", update)
    buttons[unit] = b
    return b
end

---------------------------------------------------------------------------
-- Disposition (hors combat)
---------------------------------------------------------------------------

-- hauteur d un cadre : bandeau du nom + vie + mana (+ liseré interieur)
local function frameHeight(s)
    return s.top + s.hp + (s.power > 0 and (s.power + 1) or 0) + 2
end

-- tailles, textes et polices d un bouton selon son reglage. Bandeau du nom
-- de moins de 8 px : le nom passe dans la barre de vie (style raid).
local function sizeButton(b, s)
    b:SetSize(s.width, frameHeight(s))
    b.hp:ClearAllPoints()
    b.hp:SetPoint("TOPLEFT", 1, -(s.top + 1))
    b.hp:SetPoint("TOPRIGHT", -1, -(s.top + 1))
    b.hp:SetHeight(s.hp)
    b.pw:ClearAllPoints()
    b.pw:SetPoint("TOPLEFT", b.hp, "BOTTOMLEFT", 0, -1)
    b.pw:SetPoint("TOPRIGHT", b.hp, "BOTTOMRIGHT", 0, -1)
    b.pw:SetHeight(math.max(1, s.power))
    b.pw:SetShown(s.power > 0)
    b.heal:SetWidth(math.max(1, s.width - 2))
    layoutIcons(b)
    local strip = s.top >= 8
    b.name:SetParent(strip and b or b.txt)
    b.name:SetDrawLayer("OVERLAY", 7)
    b.name:ClearAllPoints()
    b.hpText:ClearAllPoints()
    if strip then
        local y = -math.max(1, math.floor((s.top - s.nameSize) / 2))
        b.name:SetPoint("TOPLEFT", 4, y)
        b.name:SetPoint("RIGHT", -30, 0)
        b.level:ClearAllPoints()
        b.level:SetPoint("TOPRIGHT", -4, y - 1)
        b.level:Show()
        b.hpText:SetPoint("CENTER")
    else
        b.name:SetPoint("TOPLEFT", 3, -2)
        b.name:SetPoint("RIGHT", -3, 0)
        b.level:Hide()
        b.hpText:SetPoint("BOTTOMRIGHT", -3, 2)
    end
    local bold = (ns.FontFile and ns.FontFile("bold")) or STANDARD_TEXT_FONT
    local reg = (ns.FontFile and ns.FontFile("regular")) or STANDARD_TEXT_FONT
    pcall(b.name.SetFont, b.name, bold, s.nameSize, strip and "" or "OUTLINE")
    pcall(b.level.SetFont, b.level, reg, math.max(8, s.nameSize - 2), "")
    pcall(b.hpText.SetFont, b.hpText, reg, s.valueSize, "OUTLINE")
    pcall(b.pwText.SetFont, b.pwText, reg, math.max(7, s.valueSize - 2), "OUTLINE")
    b.pwText:SetShown(s.powerText and s.power >= 6)
    if b:IsVisible() then update(b) end
end

-- groupe : quatre cadres en colonne ou en ligne
local function layoutParty()
    if InCombatLockdown() then layoutPending = true return end
    local s = db.partyStyle
    local h = frameHeight(s)
    local across = s.orient == "horizontal"
    for i = 1, 4 do
        local b = buttons["party" .. i]
        sizeButton(b, s)
        b:ClearAllPoints()
        if across then
            b:SetPoint("TOPLEFT", party, "TOPLEFT", (i - 1) * (s.width + s.spacing), 0)
        else
            b:SetPoint("TOPLEFT", party, "TOPLEFT", 0, -(i - 1) * (h + s.spacing))
        end
    end
    if across then
        party:SetSize(4 * s.width + 3 * s.spacing, h)
    else
        party:SetSize(s.width, 4 * h + 3 * s.spacing)
    end
end

-- rosterOnly (changement de groupe) : tailles et polices ne dependent pas
-- du groupe, seules les places suivent les sous-groupes, et seulement s ils
-- ont change
local lastGroup = {}
local function layoutRaid(rosterOnly)
    if InCombatLockdown() then layoutPending = true return end
    if rosterOnly and layoutPending then rosterOnly = false end
    layoutPending = false
    local s = db.raidStyle
    -- groupes en colonnes (un groupe = une colonne) ou en lignes
    local rows = s.groups == "rows"
    local stepX, stepY = s.width + s.spacing, frameHeight(s) + s.spacing
    if rows then
        raid:SetSize(5 * stepX - s.spacing, 8 * stepY - s.spacing)
    else
        raid:SetSize(8 * stepX - s.spacing, 5 * stepY - s.spacing)
    end
    local count = {}
    local same = rosterOnly
    local groups = {}
    for i = 1, 40 do
        local g = 1
        if IsInRaid() and not ns.PreviewOn("raid") and not ns.moversShown then
            local _, _, subgroup = GetRaidRosterInfo(i)
            g = (subgroup and not issecret(subgroup)) and subgroup or math.ceil(i / 5)
        else
            g = math.ceil(i / 5)
        end
        groups[i] = g
        if lastGroup[i] ~= g then same = false end
    end
    if same then refreshMine() return end
    for i = 1, 40 do
        local b = buttons["raid" .. i]
        local g = groups[i]
        lastGroup[i] = g
        -- (hors raid : apercu, deverrouillage, rangement par paquets de 5)
        count[g] = (count[g] or 0) + 1
        if not rosterOnly then sizeButton(b, s) end
        b:ClearAllPoints()
        if rows then
            b:SetPoint("TOPLEFT", raid, "TOPLEFT", (count[g] - 1) * stepX, -(g - 1) * stepY)
        else
            b:SetPoint("TOPLEFT", raid, "TOPLEFT", (g - 1) * stepX, -(count[g] - 1) * stepY)
        end
    end
    refreshMine()
end

local function watch(b, on)
    if on then RegisterUnitWatch(b) else UnregisterUnitWatch(b) end
end

-- Pilote de visibilite ou apercu
local previewing = false     -- apercu : tous les cadres montrent "player"

local function applyVisibility()
    if InCombatLockdown() then layoutPending = true return end
    local partyOn, raidOn = db.showParty, db.showRaid
    UnregisterStateDriver(party, "visibility")
    UnregisterStateDriver(raid, "visibility")
    -- deverrouiller l interface montre les deux, pour pouvoir les placer
    local showParty = ns.PreviewOn("party") or ns.moversShown
    local showRaid = ns.PreviewOn("raid") or ns.moversShown
    previewing = (showParty or showRaid) and true or false
    if showParty or showRaid then
        party:SetShown(partyOn and showParty)
        raid:SetShown(raidOn and showRaid)
        for unit, b in pairs(buttons) do
            watch(b, false)
            b:SetAttribute("unit", "player")
            local n = tonumber(unit:match("%d+")) or 1
            b:SetShown(not unit:find("^raid") or n <= 25)
            -- membre fictif (le groupe : 2 a 5, le joueur etant hors des cadres)
            b.fakeIndex = b.big and (n + 1) or n
            update(b)
        end
    else
        for unit, b in pairs(buttons) do
            b.fakeIndex = nil
            b:SetAttribute("unit", b.realUnit)
            watch(b, true)
        end
        if partyOn then
            RegisterStateDriver(party, "visibility", "[group:raid] hide; [group:party] show; hide")
        else
            party:Hide()
        end
        if raidOn then
            RegisterStateDriver(raid, "visibility", "[group:raid] show; hide")
        else
            raid:Hide()
        end
    end
    layoutParty()
    layoutRaid()
    if db.hideBlizzard or db.blizzardHidden then
        ns.HideBlizzard({ "PartyFrame", "CompactPartyFrame", "CompactRaidFrameContainer", "CompactRaidFrameManager" },
            db.hideBlizzard)
        db.blizzardHidden = db.hideBlizzard
    end
end

local function build()
    db.partyPos = db.partyPos or { point = "TOPLEFT", x = 30, y = -220 }
    db.raidPos = db.raidPos or { point = "TOPLEFT", x = 30, y = -440 }
    -- premiere version : raid et groupe au meme endroit, impossibles a separer
    -- une fois deverrouilles ; on decale le raid s il n a jamais ete deplace
    if db.raidPos.point == "TOPLEFT" and db.raidPos.y == -220 and not db.raidPos.rel then db.raidPos.y = -440 end

    party = CreateFrame("Frame", "CorpUIParty", UIParent, "SecureHandlerStateTemplate")
    party:SetSize(PARTY_W, 4 * (PARTY_H + 6))
    ns.ApplyPos(party, db.partyPos)
    for i = 1, 4 do makeButton(party, "party" .. i, true) end
    ns.UI.Mover(party, db.partyPos, L.MOD_GROUP .. " - " .. L.GROUP_PARTY)

    raid = CreateFrame("Frame", "CorpUIRaid", UIParent, "SecureHandlerStateTemplate")
    raid:SetSize(8 * (RAID_W + RAID_GAP), 5 * (RAID_H + RAID_GAP))
    ns.ApplyPos(raid, db.raidPos)
    for i = 1, 40 do makeButton(raid, "raid" .. i, false) end
    ns.UI.Mover(raid, db.raidPos, L.MOD_GROUP .. " - " .. L.GROUP_RAID)

    applyVisibility()
end

---------------------------------------------------------------------------
-- Fenetre d options
---------------------------------------------------------------------------

-- Sections de l editeur des cadres (Cadres/Editeur.lua) : groupe ou raid,
-- puis les reglages pour les soigneurs (communs aux deux)
ns.FramesOpt = ns.FramesOpt or {}

local HP_TEXTS = { "both", "value", "pct", "cur", "none" }

function ns.FramesOpt.Group(parent, y, which)
    local raidMode = which == "raid"
    local function t() return raidMode and db.raidStyle or db.partyStyle end
    -- afficher / masquer et disposition : refuses en combat (cadres securises)
    local form = ns.UI.Form(parent, y, function()
        if InCombatLockdown() then ns.Say(L.COMBAT_BLOCKED) return end
        applyVisibility()
    end)
    form:Check(raidMode and L.GROUP_OPT_RAID or L.GROUP_OPT_PARTY,
        function() return db[raidMode and "showRaid" or "showParty"] end,
        function(v) db[raidMode and "showRaid" or "showParty"] = v end)
    form:Check(L.GROUP_OPT_BLIZZ, function() return db.hideBlizzard end, function(v) db.hideBlizzard = v end)
    form:Header(raidMode and L.GROUP_RAID_HEAD or L.GROUP_PARTY_HEAD)
    form:Columns(2)
    if raidMode then
        form:Cycle(L.GROUP_GROUPS, { "columns", "rows" }, { columns = L.GROUP_COLUMNS, rows = L.GROUP_ROWS },
            function() return t().groups end, function(v) t().groups = v end)
    else
        form:Cycle(L.GROUP_ORIENT, { "vertical", "horizontal" }, { vertical = L.GROUP_VERTICAL, horizontal = L.GROUP_HORIZONTAL },
            function() return t().orient end, function(v) t().orient = v end)
    end
    local function num(fmt, key, lo, hi, step)
        form:Number(fmt, function() return t()[key] end, function(v) t()[key] = v end, lo, hi, step)
    end
    num(L.FRAMES_WIDTH, "width", 40, 400, 2)
    num(L.FRAMES_TOP, "top", 0, 40)
    num(L.FRAMES_HP_H, "hp", 6, 80)
    num(L.FRAMES_PW_H, "power", 0, 30)
    num(L.BARS_SPACING, "spacing", 0, 40)
    num(L.FRAMES_NAME_SIZE, "nameSize", 7, 24)
    num(L.FRAMES_VALUE_SIZE, "valueSize", 7, 24)
    form:Cycle(L.FRAMES_HP_TEXT, HP_TEXTS, { both = L.FRAMES_TXT_BOTH, value = L.FRAMES_TXT_VALUE, pct = L.FRAMES_TXT_PCT,
        cur = L.FRAMES_TXT_CUR, none = L.FRAMES_TXT_NONE }, function() return t().hpText end, function(v) t().hpText = v end)
    form:Cycle(L.FRAMES_HP_COLOR, { "class", "theme" }, { class = L.FRAMES_COLOR_CLASS, theme = L.FRAMES_COLOR_THEME },
        function() return t().color end, function(v) t().color = v end)
    form:Check(L.FRAMES_PW_TEXT, function() return t().powerText end, function(v) t().powerText = v end)
    form:EndColumns()
    local tip = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tip:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, form.y - 4)
    tip:SetWidth(420)
    tip:SetJustifyH("LEFT")
    tip:SetText(L.GROUP_STYLE_HINT)
    form:Gap(30)
    parent:HookScript("OnShow", function() form:Refresh() end)
    return form.y
end

-- pour les soigneurs : reglages communs au groupe et au raid. Rien de
-- protege ici : applique tout de suite, meme en combat (sauf la taille
-- des icones, reprise a la sortie du combat).
function ns.FramesOpt.Healers(parent, y)
    local heal = ns.UI.Form(parent, y, function()
        if InCombatLockdown() then
            layoutPending = true
        else
            for _, b in pairs(buttons) do layoutIcons(b) end
        end
        for _, b in pairs(buttons) do if b:IsVisible() then update(b) end end
    end)
    local function hcheck(text, key)
        heal:Check(text, function() return hs[key] end, function(v) hs[key] = v end)
    end
    heal:Header(L.GROUP_HEAL_HEAD)
    heal:Columns(2)
    hcheck(L.GROUP_HEAL_PRED, "heal")
    hcheck(L.GROUP_HEAL_AGGRO, "aggro")
    hcheck(L.GROUP_HEAL_ROLE, "role")
    hcheck(L.GROUP_HEAL_LEADER, "leader")
    hcheck(L.GROUP_HEAL_MARKER, "marker")
    heal:Number(L.GROUP_RANGE_ALPHA, function() return hs.rangeAlpha or 45 end, function(v) hs.rangeAlpha = v end, 0, 100, 5)
    heal:EndColumns()
    -- marqueur de raid : place, taille, decalage, opacite (16/10)
    heal:Header(L.FRAMES_MARK_HEAD)
    heal:Columns(2)
    local posNames = {}
    for _, p in ipairs(ns.RAID_MARK_POS) do posNames[p] = L["MARK_POS_" .. p:upper()] end
    heal:Cycle(L.FRAMES_MARK_POS, ns.RAID_MARK_POS, posNames,
        function() return hs.markPos or "top" end, function(v) hs.markPos = v end)
    heal:Number(L.FRAMES_MARK_SIZE, function() return hs.markSize end, function(v) hs.markSize = v end, 8, 40)
    heal:Number(L.FRAMES_MARK_X, function() return hs.markX end, function(v) hs.markX = v end, -60, 60)
    heal:Number(L.FRAMES_MARK_Y, function() return hs.markY end, function(v) hs.markY = v end, -60, 60)
    heal:Number(L.FRAMES_MARK_ALPHA, function() return hs.markAlpha end, function(v) hs.markAlpha = v end, 10, 100, 5)
    heal:EndColumns()
    heal:Header(L.GROUP_ICONS_HEAD)
    heal:Columns(2)
    hcheck(L.GROUP_HEAL_ICONS, "icons")
    hcheck(L.GROUP_HEAL_ICONS_DISPEL, "iconsDispel")
    heal:Number(L.GROUP_HEAL_ICON_MAX, function() return hs.iconMax end, function(v) hs.iconMax = v end, 1, ICON_MAX)
    heal:Number(L.GROUP_HEAL_ICON_SIZE, function() return hs.iconSize end, function(v) hs.iconSize = v end, 8, 30)
    heal:EndColumns()
    local note = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, heal.y - 4)
    note:SetWidth(420)
    note:SetJustifyH("LEFT")
    note:SetText(L.GROUP_HEAL_HINT .. " " .. L.GROUP_DISPEL_MOVED)
    heal:Gap(44)
    parent:HookScript("OnShow", function() heal:Refresh() end)
    return heal.y
end

-- les filtres d auras ont change
function ns.GroupRefreshAuras()
    for _, b in pairs(buttons) do
        if b.nIcons and not InCombatLockdown() then b.nIcons:Apply(iconSpec(b)) end
        if b:IsVisible() then updateAuras(b, b:GetAttribute("unit")) end
    end
end


---------------------------------------------------------------------------

local rosterQueued = false
local function rosterFlush()
    rosterQueued = false
    if not db then return end
    layoutRaid(true)
    for _, b in pairs(buttons) do if b:IsVisible() then update(b) end end
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, unit)
    if ns.ModuleOff("groupe", ev) then return end
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        root.group = root.group or {}
        db = root.group
        if db.showParty == nil then db.showParty = true end
        if db.showRaid == nil then db.showRaid = true end
        -- disposition et tailles (reglables)
        db.partyStyle = db.partyStyle or {}
        db.raidStyle = db.raidStyle or {}
        -- (defauts = rendu d origine ; "height" des premiers reglages abandonnee)
        for k, v in pairs({ orient = "vertical", width = PARTY_W, spacing = 6, top = 16, hp = 16, power = 5,
                            nameSize = 13, valueSize = 10, hpText = "value", color = "class", powerText = false }) do
            if db.partyStyle[k] == nil then db.partyStyle[k] = v end
        end
        for k, v in pairs({ groups = "columns", width = RAID_W, spacing = RAID_GAP, top = 0, hp = 29, power = 3,
                            nameSize = 10, valueSize = 9, hpText = "pct", color = "class", powerText = false }) do
            if db.raidStyle[k] == nil then db.raidStyle[k] = v end
        end
        db.partyStyle.height, db.raidStyle.height = nil, nil
        -- pour les soigneurs (nouvelles cles seulement)
        db.heal = db.heal or {}
        hs = db.heal
        for k, v in pairs({ dispel = true, dispelAll = false, dispelStyle = "both", icons = true, iconsDispel = false,
                            iconMax = 3, iconSize = 14, heal = true, aggro = true, role = true, leader = true,
                            marker = true, tintAlpha = 35,
                            markPos = "top", markSize = 16, markX = 0, markY = 0, markAlpha = 100 }) do
            if hs[k] == nil then hs[k] = v end
        end
        -- demande du 06/10 : le cadre entier prend la couleur du debuff
        if not hs.dispelStyle2 then
            hs.dispelStyle2 = true
            if hs.dispelStyle == "border" then hs.dispelStyle = "both" end
        end
        -- l interface de Blizzard qu on remplace est masquee par defaut (une fois)
        if not db.blizzDefault2 then
            db.hideBlizzard = true
            db.blizzDefault2 = true
        end
        build()
    elseif not db then
        return
    elseif event == "GROUP_ROSTER_UPDATE" then
        -- rafale (invitations, connexions, deplacements) : un passage
        if not rosterQueued then
            rosterQueued = true
            C_Timer.After(0.2, rosterFlush)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if layoutPending then applyVisibility() end
        if dispelPending then ns.GroupDispelRefresh() end
    elseif event == "RAID_TARGET_UPDATE" or event == "PARTY_LEADER_CHANGED" or event == "PLAYER_ROLES_ASSIGNED" then
        -- marqueurs, chef, roles : sans unite, tous les cadres
        for _, b in pairs(buttons) do
            local u = b:GetAttribute("unit")
            if b:IsVisible() and u and UnitExists(u) and not b.fakeIndex then updateIcons(b, u) end
        end
    elseif unit then
        -- un evenement d unite : le cadre de cette unite (les cadres sont
        -- ranges par unite), seulement la partie concernee pour les
        -- evenements frequents. Apercu : tous montrent "player".
        if issecret(unit) or type(unit) ~= "string" then return end
        if previewing then
            if unit ~= "player" then return end
            for _, b in pairs(buttons) do
                if b.fakeIndex and b:IsVisible() then fakeButton(b) end
            end
            return
        end
        local b = buttons[unit]
        if b and b:IsVisible() then
            if event == "UNIT_AURA" then
                updateAuras(b, unit)
            elseif event == "UNIT_HEAL_PREDICTION" then
                updateHeal(b, unit)
            elseif event == "UNIT_THREAT_SITUATION_UPDATE" then
                updateAggro(b, unit)
            elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
                updatePower(b, unit)
            elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_FLAGS" then
                -- mort / resurrection : surbrillance et aggro suivent
                local was = b.down
                updateHealth(b, unit)
                if was ~= b.down then updateHealer(b, unit) elseif event ~= "UNIT_FLAGS" then updateHeal(b, unit) end
            else
                update(b)
            end
        end
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED", "UNIT_HEALTH",
                     "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_NAME_UPDATE",
                     "UNIT_CONNECTION", "UNIT_LEVEL", "UNIT_DISPLAYPOWER", "UNIT_FLAGS", "UNIT_AURA",
                     "UNIT_HEAL_PREDICTION", "UNIT_THREAT_SITUATION_UPDATE", "RAID_TARGET_UPDATE",
                     "PARTY_LEADER_CHANGED", "PLAYER_ROLES_ASSIGNED" }) do
    pcall(ev.RegisterEvent, ev, e)
end

-- alertes (5 fois par seconde) et portee (2 fois) : planificateur commun,
-- rien hors groupe (sauf apercu)
local function grouped()
    return previewing or IsInGroup() or IsInRaid()
end
local alertsIdle = false
ns.Every(0.2, function()
    if not db then return end
    if not grouped() then
        -- hors groupe : alertes oubliees une fois (pas de rappel au retour)
        if not alertsIdle then
            alertsIdle = true
            for _, b in pairs(buttons) do b.alerted = false end
        end
        return
    end
    alertsIdle = false
    checkAlerts()
end, "Groupe : alertes", "groupe")
ns.Every(0.5, function()
    if not db or not grouped() then return end
    for _, b in pairs(buttons) do
        if b:IsVisible() then UF.Range(b, b:GetAttribute("unit"), (hs and hs.rangeAlpha or 45) / 100) end
    end
end, "Groupe : portee", "groupe")

-- reglages : editeur des cadres (Cadres/Editeur.lua), cadre "Groupe"
ns.RegisterModule({
    command = "groupe",
    title = function() return L.MOD_GROUP end,
    desc = function() return L.GROUP_DESC end,
    Slash = function() if ns.OpenFrames then ns.OpenFrames("party") end end,
})

-- Deverrouillage / verrouillage de l interface : afficher ou retirer l apercu
local lastMovers, lastPreview = false, "falsefalse"
ns.Listen(function()
    if not db or not party then return end
    local pv = tostring(ns.PreviewOn("party")) .. tostring(ns.PreviewOn("raid"))
    if ns.moversShown == lastMovers and pv == lastPreview then return end
    if InCombatLockdown() then
        layoutPending = true
        return
    end
    lastMovers, lastPreview = ns.moversShown, pv
    applyVisibility()
end)
