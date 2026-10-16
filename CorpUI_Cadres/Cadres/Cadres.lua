--[[--------------------------------------------------------------------------
    CorpUI - module Cadres (essai)
    Nos propres cadres joueur, cible, cible de la cible, familier et
    focalisation, a la place de ceux de Blizzard.

    C est aussi un TEST : en combat, ce client rend certaines valeurs
    "secretes" (illisibles par un addon). Les barres de vie de Blizzard
    les affichent quand meme ; reste a savoir si les notres le peuvent.
    Chaque mise a jour note ce qui s est passe dans CorpUIDB.frames.diag
    (hors combat et en combat, par unite) :
      health  : la vie etait-elle secrete ?
      bar     : la barre a-t-elle accepte la valeur ?
      text    : "full" (calculs possibles), "format" (nombres bruts
                seulement), "none" (rien d affichable)
    /corp cadres diag les affiche ; ils survivent a un /reload.

    Securite :
      - boutons SecureUnitButtonTemplate : clic gauche = cibler,
        clic droit = menu de l unite ; la cible s affiche/se masque seule
        (RegisterUnitWatch), meme en combat
      - les cadres de Blizzard ne sont touches que si l option
        experimentale est cochee (transparence + souris coupee, hors combat)
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L

local issecret = issecretvalue or function() return false end

local W, H_HP, H_PW, H_TOP = 230, 22, 10, 18
-- cadres compacts (familier, cible de la cible, focalisation)
local WS, HS_HP, HS_PW, HS_TOP = 120, 14, 4, 14

-- unite, nom du cadre, reglages, position par defaut, libelle
-- watch : affiche/masque par le code securise selon que l unite existe
local UNITS = {
    { unit = "player", name = "Player", show = "showPlayer", pos = "playerPos", label = "FRAMES_PLAYER",
      def = { point = "CENTER", x = -260, y = -180 } },
    { unit = "target", name = "Target", show = "showTarget", pos = "targetPos", label = "FRAMES_TARGET",
      def = { point = "CENTER", x = 260, y = -180 }, watch = true },
    { unit = "targettarget", name = "TargetTarget", show = "showToT", pos = "totPos", label = "FRAMES_TOT",
      def = { point = "CENTER", x = 455, y = -180 }, watch = true, small = true },
    { unit = "pet", name = "Pet", show = "showPet", pos = "petPos", label = "FRAMES_PET",
      def = { point = "CENTER", x = -455, y = -180 }, watch = true, small = true },
    { unit = "focus", name = "Focus", show = "showFocus", pos = "focusPos", label = "FRAMES_FOCUS",
      def = { point = "CENTER", x = -260, y = -90 }, watch = true, small = true },
}
-- boss et adversaires d arene : cinq cadres empiles sous le premier, qui
-- porte seul la poignee (une position pour les cinq)
for _, g in ipairs({
    { key = "boss", name = "Boss", label = "FRAMES_BOSS", def = { point = "RIGHT", x = -300, y = 140 } },
    { key = "arena", name = "Arena", label = "FRAMES_ARENA", def = { point = "RIGHT", x = -500, y = 140 } },
}) do
    for i = 1, 5 do
        table.insert(UNITS, { unit = g.key .. i, name = g.name .. i, show = "show" .. g.name, pos = g.key .. "Pos",
            label = g.label, def = g.def, watch = true, small = true, wide = true, index = i,
            below = i > 1 and (g.key .. (i - 1)) or nil, group = g.key })
    end
end
local WB, HB_HP = 180, 18      -- cadres de boss / arene : compacts mais larges

-- Apparence reglable par cadre (boss et arene : un reglage pour les cinq)
local STYLE_ORDER = { "player", "target", "targettarget", "pet", "focus", "boss", "arena" }
local STYLE_LABEL = { player = "FRAMES_PLAYER", target = "FRAMES_TARGET", targettarget = "FRAMES_TOT",
    pet = "FRAMES_PET", focus = "FRAMES_FOCUS", boss = "FRAMES_BOSS", arena = "FRAMES_ARENA" }
-- portrait : aucun, plat, 3D ; a gauche ou a droite du cadre
local PORTRAITS = { "none", "2d", "3d" }
local SIDES = { "left", "right" }

-- Textes libres (facon tags ElvUI) : chaque emplacement du cadre affiche
-- l etiquette choisie (db.style[cle].texts[emplacement])
--   nameL / nameR : bandeau du haut, a gauche / a droite
--   hpL / hpC / hpR : barre de vie, gauche / centre / droite
--   pwC : centre de la barre de puissance
local SLOTS = { "nameL", "nameR", "hpL", "hpR", "hpC", "pwC" }
local SLOT_LABEL = { nameL = "FRAMES_SLOT_NAMEL", nameR = "FRAMES_SLOT_NAMER", hpL = "FRAMES_SLOT_HPL",
    hpR = "FRAMES_SLOT_HPR", hpC = "FRAMES_SLOT_HPC", pwC = "FRAMES_SLOT_PWC" }
-- ordre de mise a jour : "Mort" / "Fantome" va dans le premier texte de vie
local SLOT_PRIORITY = { "hpC", "hpL", "hpR", "pwC", "nameR", "nameL" }
local TAGS = { "none", "name", "nameshort", "level", "levelclass", "class", "group",
    "hp:cur", "hp:pct", "hp:curmax", "hp:curmaxpct", "hp:curpct", "hp:deficit",
    "pw:cur", "pw:pct", "pw:curmax" }
local TAG_LABEL = { none = "FRAMES_TXT_NONE", name = "FRAMES_TAG_NAME", nameshort = "FRAMES_TAG_NAMESHORT",
    level = "FRAMES_TAG_LEVEL", levelclass = "FRAMES_TAG_LEVELCLASS", class = "FRAMES_TAG_CLASS",
    group = "FRAMES_TAG_GROUP", ["hp:cur"] = "FRAMES_TAG_HP_CUR", ["hp:pct"] = "FRAMES_TAG_HP_PCT",
    ["hp:curmax"] = "FRAMES_TAG_HP_CURMAX", ["hp:curmaxpct"] = "FRAMES_TAG_HP_CURMAXPCT",
    ["hp:curpct"] = "FRAMES_TAG_HP_CURPCT", ["hp:deficit"] = "FRAMES_TAG_HP_DEFICIT",
    ["pw:cur"] = "FRAMES_TAG_PW_CUR", ["pw:pct"] = "FRAMES_TAG_PW_PCT", ["pw:curmax"] = "FRAMES_TAG_PW_CURMAX" }
-- famille d une etiquette : quel evenement la remet a jour
local function tagKind(tag)
    if not tag or tag == "none" then return "none" end
    local p = tag:sub(1, 3)
    if p == "hp:" then return "health" end
    if p == "pw:" then return "power" end
    return "info"
end
-- ancien "texte de vie" -> etiquette du centre de la barre de vie
local OLD_HP_TEXT = { both = "hp:curmaxpct", value = "hp:curmax", pct = "hp:pct", cur = "hp:cur", none = "none" }
-- couleur du nom : auto (ancien rendu : classe des joueurs, or sinon),
-- classe / reaction, reaction seule, blanc
local NAME_COLORS = { "auto", "class", "reaction", "white" }

local function styleDefaults(key)
    -- la cible (et sa cible) ont le portrait a droite, les autres a gauche
    local side = (key == "target" or key == "targettarget") and "right" or "left"
    -- icone de raid (16/10) : affichee, au milieu du bord du haut
    if key == "player" or key == "target" then
        return { width = W, top = H_TOP, hp = H_HP, power = H_PW, nameSize = 13, valueSize = 12,
                 hpText = "both", powerText = true, color = "class", portrait = "none", portraitSide = side,
                 nameColor = "auto", nameLen = 12,
                 mark = true, markSize = 22, markPos = "top", markX = 0, markY = 0, markAlpha = 100 }
    end
    local wide = key == "boss" or key == "arena"
    return { width = wide and WB or WS, top = HS_TOP, hp = wide and HB_HP or HS_HP, power = HS_PW,
             nameSize = 11, valueSize = 10, hpText = "pct", powerText = false, color = "class",
             portrait = "none", portraitSide = side, nameColor = "auto", nameLen = 10,
             mark = true, markSize = 16, markPos = "top", markX = 0, markY = 0, markAlpha = 100 }
end

-- textes par defaut d un cadre, tires des anciens reglages (meme rendu qu avant)
local function textDefaults(s)
    return { nameL = "name", nameR = "levelclass", hpL = "none", hpR = "none",
             hpC = OLD_HP_TEXT[s.hpText] or "hp:pct", pwC = s.powerText and "pw:curmax" or "none" }
end

local db
local frames = {}

local function style(f)
    local s = db.style[f.styleKey]
    -- reglages importes sans textes (profil ancien) : ceux d avant
    if not s.texts then s.texts = textDefaults(s) end
    return s
end

---------------------------------------------------------------------------
-- Diagnostic
---------------------------------------------------------------------------

local function note(unit, field, value)
    if not db then return end
    local key = unit .. (InCombatLockdown() and "_combat" or "")
    local d = db.diag[key]
    if not d then
        d = {}
        db.diag[key] = d
    end
    -- on ne garde que la premiere valeur securisee : une mise a jour
    -- "secrete" ne doit pas etre ecrasee par une lisible juste apres
    if d[field] == nil or value == true or value == "none" then d[field] = value end
    d.t = time()
end

---------------------------------------------------------------------------
-- Valeurs
---------------------------------------------------------------------------

local function short(n)
    if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
    if n >= 1e4 then return string.format("%.0fk", n / 1e3) end
    return tostring(n)
end

-- Barre : on passe la valeur telle quelle (le client accepte peut-etre
-- les valeurs secretes dans une barre)
local function setBar(bar, cur, max)
    local ok1 = pcall(bar.SetMinMaxValues, bar, 0, max)
    local ok2 = pcall(bar.SetValue, bar, cur)
    return ok1 and ok2
end

-- Pourcentage calcule par le client lui-meme (accepte les valeurs secretes).
-- Renvoie ok, p : p peut etre secret, on ne le teste jamais.
local function apiPercent(unit, kind, curve)
    local scale = curve or (CurveConstants and CurveConstants.ScaleTo100)
    if not scale then return false end
    local fn = kind == "power" and UnitPowerPercent or UnitHealthPercent
    if not fn then return false end
    if kind == "power" then return pcall(fn, unit, nil, true, scale) end
    return pcall(fn, unit, true, scale)
end

-- Texte, du plus riche au plus simple. Renvoie le mode obtenu :
--   full   : "1234 / 2000  62%" calcule par nous (valeurs lisibles)
--   api    : nombres abreges et % par les fonctions de Blizzard prevues pour
--            les valeurs secretes (AbbreviateNumbers, UnitHealthPercent)
--   format : nombres bruts seulement
--   none   : rien d affichable
local function setValueText(fs, cur, max, withPct, unit, kind)
    local ok, txt = pcall(function()
        if max <= 0 then return "" end
        local s = short(cur) .. " / " .. short(max)
        if withPct then s = s .. "  " .. math.floor(cur / max * 100 + 0.5) .. "%" end
        return s
    end)
    if ok then
        fs:SetText(txt)
        return "full"
    end
    if AbbreviateNumbers then
        local okA, a = pcall(AbbreviateNumbers, cur)
        local okB, b = pcall(AbbreviateNumbers, max)
        if okA and okB then
            local okP, pct = false, nil
            if withPct then okP, pct = apiPercent(unit, kind) end
            local shown
            if okP then
                shown = pcall(fs.SetFormattedText, fs, "%s / %s  %d%%", a, b, pct)
            else
                shown = pcall(fs.SetFormattedText, fs, "%s / %s", a, b)
            end
            if shown then return "api" end
        end
    end
    if pcall(fs.SetFormattedText, fs, "%d / %d", cur, max) then return "format" end
    fs:SetText("")
    return "none"
end

local function unitFlag(fn, unit)
    if not fn then return false end
    local ok, v = pcall(fn, unit)
    if not ok or issecret(v) then return false end
    return v and true or false
end

---------------------------------------------------------------------------
-- Couleurs
---------------------------------------------------------------------------

local POWER_FALLBACK = {
    MANA = { 0, 0.44, 0.87 }, RAGE = { 0.78, 0.15, 0.15 }, ENERGY = { 1, 0.85, 0.1 },
    FOCUS = { 1, 0.5, 0.25 },
}

local function powerColor(unit)
    local ok, _, token = pcall(UnitPowerType, unit)
    token = ok and not issecret(token) and token or "MANA"
    local c = PowerBarColor and PowerBarColor[token]
    if c and c.r then return c.r, c.g, c.b end
    local f = POWER_FALLBACK[token] or POWER_FALLBACK.MANA
    return f[1], f[2], f[3]
end

local function reactionColor(unit)
    if unitFlag(UnitIsTapDenied, unit) then return 0.5, 0.5, 0.5 end
    local ok, r = pcall(UnitReaction, unit, "player")
    if ok and not issecret(r) and r then
        if r <= 3 then return 0.8, 0.15, 0.15 end
        if r == 4 then return 0.9, 0.8, 0.1 end
        return 0.2, 0.75, 0.25
    end
    return 0.2, 0.75, 0.25
end

local function healthColor(unit)
    if unitFlag(UnitIsPlayer, unit) then
        local ok, _, class = pcall(UnitClass, unit)
        if ok and not issecret(class) and class then return ns.ClassColor(class) end
    end
    return reactionColor(unit)
end

-- couleur du nom selon le reglage du cadre
local function nameColor(f, unit)
    local mode = style(f).nameColor or "auto"
    if mode == "white" then return 1, 1, 1 end
    if mode == "reaction" then return reactionColor(unit) end
    if mode == "class" then return healthColor(unit) end
    -- auto (ancien rendu) : classe des joueurs, or pour le reste
    if unitFlag(UnitIsPlayer, unit) then return healthColor(unit) end
    return 1, 0.82, 0
end

---------------------------------------------------------------------------
-- Etiquettes de texte (tags)
---------------------------------------------------------------------------

-- coupe une chaine UTF-8 lisible a n caracteres
local function utf8sub(s, n)
    local count, i = 0, 1
    while i <= #s do
        count = count + 1
        if count > n then return s:sub(1, i - 1) end
        local c = s:byte(i)
        i = i + (c >= 240 and 4 or c >= 224 and 3 or c >= 192 and 2 or 1)
    end
    return s
end

local function clear(fs)
    fs:SetText("")
end

-- courbe "vie pleine ?" : 1 tant que la vie n est pas pleine, 0 a 100 %
-- (sert d alpha au deficit quand les valeurs sont secretes)
local fullCurve
local function getFullCurve()
    if fullCurve == nil then
        fullCurve = false
        local ok, c = pcall(function()
            local c = C_CurveUtil.CreateCurve()
            c:SetType(Enum.LuaCurveType.Step)
            c:AddPoint(0, 1)
            c:AddPoint(0.999, 1)
            c:AddPoint(1, 0)
            return c
        end)
        if ok and c then fullCurve = c end
    end
    return fullCurve or nil
end

-- Valeur (vie ou puissance) selon l etiquette ; cur et max peuvent etre
-- secrets. Renvoie le mode du diagnostic pour "valeur / max".
-- deux nombres lisibles (pas secrets) : calcul direct, sans pcall
local function readableNums(a, b)
    return type(a) == "number" and type(b) == "number" and not issecret(a) and not issecret(b)
end

local function renderValue(fs, what, unit, kind, cur, max)
    if what == "curmax" or what == "curmaxpct" then
        return setValueText(fs, cur, max, what == "curmaxpct", unit, kind)
    elseif what == "cur" then
        -- valeur seule, abregee par le client (accepte les valeurs secretes)
        local okA, a = pcall(AbbreviateNumbers or tostring, cur)
        if not okA or not pcall(fs.SetFormattedText, fs, "%s", a) then
            if not pcall(fs.SetFormattedText, fs, "%d", cur) then clear(fs) end
        end
    elseif what == "pct" then
        local okP, p = apiPercent(unit, kind)
        if okP and pcall(fs.SetFormattedText, fs, "%d%%", p) then return end
        if readableNums(cur, max) then
            fs:SetText(max <= 0 and "" or (math.floor(cur / max * 100 + 0.5) .. "%"))
        else
            clear(fs)
        end
    elseif what == "curpct" then
        if readableNums(cur, max) then
            fs:SetText(max <= 0 and "" or (short(cur) .. "  " .. math.floor(cur / max * 100 + 0.5) .. "%"))
            return
        end
        local okA, a = pcall(AbbreviateNumbers or tostring, cur)
        local okP, p = apiPercent(unit, kind)
        if okA and okP and pcall(fs.SetFormattedText, fs, "%s  %d%%", a, p) then return end
        if okA and pcall(fs.SetFormattedText, fs, "%s", a) then return end
        clear(fs)
    elseif what == "deficit" then
        if readableNums(cur, max) then
            local d = max - cur
            fs:SetText(d <= 0 and "" or ("-" .. short(d)))
            return
        end
        -- valeurs secretes : le manque vient du client (UnitHealthMissing) et
        -- "vie pleine" se traduit en alpha 0 par une courbe ; sinon rien
        local curve = getFullCurve()
        if kind ~= "health" or not UnitHealthMissing or not curve then clear(fs) return end
        local okF, alpha = apiPercent(unit, "health", curve)
        local okM, miss = pcall(UnitHealthMissing, unit)
        local okA, a = false, nil
        if okM then okA, a = pcall(AbbreviateNumbers or tostring, miss) end
        if okF and okA and pcall(fs.SetAlpha, fs, alpha) and pcall(fs.SetFormattedText, fs, "-%s", a) then return end
        fs:SetAlpha(1)
        clear(fs)
    else
        clear(fs)
    end
end

-- Etiquettes d information (nom, niveau, classe, groupe)
-- Rang de la creature : mot, couleur du mot, couleur du liseré
-- (elite et boss en or, rare en argent)
local RANK_GOLD, RANK_SILVER, RANK_BOSS = { 1, 0.78, 0.2 }, { 0.78, 0.84, 0.95 }, { 1, 0.35, 0.25 }

local function rankOf(unit)
    if unitFlag(UnitIsPlayer, unit) then return nil end
    local okc, class = pcall(UnitClassification, unit)
    if not okc or issecret(class) then return nil end
    if class == "worldboss" then return L.FRAMES_RANK_BOSS, RANK_BOSS, RANK_GOLD end
    if class == "elite" then return L.FRAMES_RANK_ELITE, RANK_GOLD, RANK_GOLD end
    if class == "rareelite" then return L.FRAMES_RANK_RAREELITE, RANK_SILVER, RANK_GOLD end
    if class == "rare" then return L.FRAMES_RANK_RARE, RANK_SILVER, RANK_SILVER end
end

-- liseré et lueur du bandeau selon le rang (le joueur garde son liseré :
-- rouge en combat)
local function updateRank(f)
    if f.unit == "player" or not f.rankGlow then return end
    local edge
    if UnitExists(f.unit) then edge = select(3, rankOf(f.unit)) end
    if edge then
        f.border:SetColorTexture(edge[1], edge[2], edge[3], 1)
        ns.UI.Gradient(f.rankGlow, "HORIZONTAL", edge[1], edge[2], edge[3], 0, edge[1], edge[2], edge[3], 0.28)
        f.rankGlow:Show()
    else
        ns.UI.ResetBorder(f)
        f.rankGlow:Hide()
    end
end

-- Repos du joueur : pastille "Zz" a gauche du cadre (ou de son portrait)
local function updateRest(f)
    local r = f.rest
    if not r then return end
    -- pastille coupee (reglage commun ; la disposition Moderne la coupe)
    local resting = db.restIcon ~= false and IsResting and IsResting() and true or false
    r:SetShown(resting)
    if not resting then
        if r.pulse then r.pulse:Stop() end
        return
    end
    local p = f.portrait
    r:ClearAllPoints()
    if p and p:IsShown() and style(f).portraitSide ~= "right" then
        r:SetPoint("TOPRIGHT", p, "TOPLEFT", -3, 0)
    else
        r:SetPoint("TOPRIGHT", f, "TOPLEFT", -3, 0)
    end
    if r.pulse and not r.pulse:IsPlaying() then r.pulse:Play() end
end

-- Humeur du familier de chasseur (nourriture) : icones du jeu, liseré de
-- couleur. Donnees du client (branche forever, PetHappiness.lua) :
-- C_PetInfo.GetPetHappiness() -> humeur (1 mecontent, 2 satisfait,
-- 3 content), % de degats, loyaute ; C_PetInfo.GetPetFoodTypes() -> regime.
-- Le cadre du familier de Blizzard sur ce client ne l affiche pas.
local MOOD_ATLAS = { "UI-PetMad", "UI-PetNeutral", "UI-PetHappiness" }
local MOOD_RGB = { { 0.9, 0.2, 0.2 }, { 1, 0.82, 0.2 }, { 0.3, 0.85, 0.35 } }

local function petMood()
    if not (C_PetInfo and C_PetInfo.GetPetHappiness) then return nil end
    local okH, _, hunter = pcall(HasPetUI)
    if not okH or issecret(hunter) or not hunter then return nil end
    local ok, h, dmg, loyalty = pcall(C_PetInfo.GetPetHappiness)
    if not ok or issecret(h) or type(h) ~= "number" or not MOOD_ATLAS[h] then return nil end
    return h, not issecret(dmg) and dmg or nil, not issecret(loyalty) and loyalty or nil
end

local function updateMood(f)
    local m = f.mood
    if not m then return end
    local level
    if db.petMood ~= false then
        if UnitExists("pet") then
            level = petMood()
        elseif ns.PreviewOn("units") then
            level = 3
        end
    end
    m:SetShown(level ~= nil)
    if not level then return end
    pcall(m.tex.SetAtlas, m.tex, MOOD_ATLAS[level])
    local c = MOOD_RGB[level]
    m.cuiBorder:SetColorTexture(c[1], c[2], c[3], 1)
end

local function moodTooltip(self)
    local level, dmg, loyalty = petMood()
    if not level then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(_G["PET_HAPPINESS" .. level] or "?", MOOD_RGB[level][1], MOOD_RGB[level][2], MOOD_RGB[level][3])
    if type(dmg) == "number" and PET_DAMAGE_PERCENTAGE then
        GameTooltip:AddLine(string.format(PET_DAMAGE_PERCENTAGE, dmg), 1, 1, 1)
    end
    if type(loyalty) == "number" and loyalty ~= 0 then
        local t = loyalty < 0 and LOSING_LOYALTY or GAINING_LOYALTY
        if t then GameTooltip:AddLine(t, 1, 1, 1) end
    end
    if C_PetInfo.GetPetFoodTypes and PET_DIET_TEMPLATE then
        local res = { pcall(C_PetInfo.GetPetFoodTypes) }
        local list = {}
        if res[1] then
            local first = res[2]
            if type(first) == "table" then
                for _, v in ipairs(first) do if type(v) == "string" then table.insert(list, v) end end
            else
                for i = 2, #res do if type(res[i]) == "string" then table.insert(list, res[i]) end end
            end
        end
        local diet = #list > 0 and table.concat(list, PET_FOOD_DELIMIT or ", ") or (NONE or "-")
        GameTooltip:AddLine(string.format(PET_DIET_TEMPLATE, diet), 1, 1, 1, true)
    end
    GameTooltip:Show()
end

local function renderInfo(fs, tag, f, unit)
    if tag == "name" or tag == "nameshort" then
        local ok, name = pcall(UnitName, unit)
        if not ok then clear(fs) return end
        -- nom secret : affiche tel quel (pas de decoupe possible)
        if issecret(name) then
            if not pcall(fs.SetText, fs, name) then clear(fs) end
            return
        end
        name = name or ""
        if tag == "nameshort" then name = utf8sub(name, style(f).nameLen or 10) end
        fs:SetText(name)
    elseif tag == "level" or tag == "levelclass" then
        local okL, level = pcall(UnitLevel, unit)
        if not okL then clear(fs) return end
        -- rang (elite, rare...) : mot colore apres le niveau
        local suffix = ""
        if tag == "levelclass" then
            local word, c = rankOf(unit)
            if word then
                suffix = string.format(" |cff%02x%02x%02x%s|r", math.floor(c[1] * 255 + 0.5),
                    math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5), word)
            end
        end
        if issecret(level) then
            if not pcall(fs.SetFormattedText, fs, "%d%s", level, suffix) then clear(fs) end
            return
        end
        local lv = ((type(level) == "number" and level > 0) and tostring(level) or "??") .. suffix
        fs:SetText(lv)
    elseif tag == "class" then
        -- classe des joueurs seulement (nom localise, peut etre secret)
        if not unitFlag(UnitIsPlayer, unit) then clear(fs) return end
        local ok, cname = pcall(UnitClass, unit)
        if not ok or not pcall(fs.SetText, fs, cname) then clear(fs) end
    elseif tag == "group" then
        -- groupe du raid : on cherche l unite parmi raid1..raid40
        local sub
        if unitFlag(IsInRaid) then
            local okN, n = pcall(GetNumGroupMembers)
            if okN and not issecret(n) and type(n) == "number" then
                for i = 1, n do
                    if unitFlag(function() return UnitIsUnit("raid" .. i, unit) end) then
                        local okR, _, _, g = pcall(GetRaidRosterInfo, i)
                        if okR and not issecret(g) and type(g) == "number" then sub = g end
                        break
                    end
                end
            end
        end
        if sub then fs:SetFormattedText(L.FRAMES_GROUP_FMT, sub) else clear(fs) end
    else
        clear(fs)
    end
end

---------------------------------------------------------------------------
-- Mise a jour
---------------------------------------------------------------------------

local function updateHealth(f)
    local unit = f.unit
    local okC, cur = pcall(UnitHealth, unit)
    local okM, max = pcall(UnitHealthMax, unit)
    if not okC or not okM then return end
    note(unit, "health", issecret(cur) or issecret(max))
    note(unit, "bar", setBar(f.hp, cur, max))
    ns.UF.UpdateHeal(f.heal, unit, db.healPrediction)
    local status
    if unitFlag(UnitIsGhost, unit) then
        status = L.FRAMES_GHOST
    elseif unitFlag(UnitIsDead, unit) then
        status = L.FRAMES_DEAD
    elseif unitFlag(UnitIsPlayer, unit) and not unitFlag(UnitIsConnected, unit) then
        status = L.FRAMES_OFFLINE
    end
    -- textes de vie : l etat (mort, fantome, deconnecte) prend le premier,
    -- les suivants sont vides
    local texts = style(f).texts
    for _, key in ipairs(SLOT_PRIORITY) do
        local tag = texts[key]
        if tagKind(tag) == "health" then
            local fs = f.texts[key]
            fs:SetAlpha(1)
            if status then
                fs:SetText(status)
                status = ""
            else
                local mode = renderValue(fs, tag:sub(4), unit, "health", cur, max)
                if mode then note(unit, "text", mode) end
            end
        end
    end
    if style(f).color == "theme" then
        local a = ns.COLORS.violet
        f.hp:SetStatusBarColor(a[1], a[2], a[3])
    else
        f.hp:SetStatusBarColor(healthColor(unit))
    end
end

local function updatePower(f)
    local unit = f.unit
    local okC, cur = pcall(UnitPower, unit)
    local okM, max = pcall(UnitPowerMax, unit)
    if not okC or not okM then return end
    note(unit, "power", issecret(cur) or issecret(max))
    setBar(f.pw, cur, max)
    local texts = style(f).texts
    for _, key in ipairs(SLOT_PRIORITY) do
        local tag = texts[key]
        if tagKind(tag) == "power" then
            local fs = f.texts[key]
            fs:SetAlpha(1)
            renderValue(fs, tag:sub(4), unit, "power", cur, max)
        end
    end
    f.pw:SetStatusBarColor(powerColor(unit))
end

-- nom, niveau, classe, groupe, emplacements vides ; couleur de chaque texte
local function updateInfo(f)
    local unit = f.unit
    local texts = style(f).texts
    local nr, ng, nb
    for _, key in ipairs(SLOT_PRIORITY) do
        local tag = texts[key]
        local fs = f.texts[key]
        local kind = tagKind(tag)
        if kind == "info" then
            fs:SetAlpha(1)
            renderInfo(fs, tag, f, unit)
        elseif kind == "none" then
            fs:SetAlpha(1)
            fs:SetText("")
        end
        if tag == "name" or tag == "nameshort" then
            if not nr then nr, ng, nb = nameColor(f, unit) end
            fs:SetTextColor(nr, ng, nb)
        else
            fs:SetTextColor(1, 1, 1)
        end
    end
end

-- Portrait : aucun, plat (texture du jeu) ou 3D (modele de l unite),
-- reglage du cadre (db.style[cle].portrait)
local function updatePortrait(f)
    local p = f.portrait
    if not p then return end
    local mode = style(f).portrait or "none"
    p:SetShown(mode ~= "none")
    if mode == "none" then return end
    if not UnitExists(f.unit) then
        -- apercu (interface deverrouillee) : un point d interrogation
        p.model:Hide()
        p.tex:Show()
        p.tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        return
    end
    if mode == "3d" then
        p.tex:Hide()
        p.model:Show()
        local ok = pcall(function()
            p.model:ClearModel()
            p.model:SetUnit(f.unit)
            p.model:SetPortraitZoom(1)
            p.model:SetCamDistanceScale(1)
            p.model:SetPosition(0, 0, 0)
        end)
        -- unite hors de portee du modele : on retombe sur le portrait plat
        if ok then return end
        p.model:Hide()
    else
        p.model:Hide()
    end
    p.tex:Show()
    if not pcall(SetPortraitTexture, p.tex, f.unit) then p.tex:SetTexture(nil) end
end

---------------------------------------------------------------------------
-- Apercu pendant le reglage (ns.PreviewOn("units")) : un cadre sans unite
-- montre des donnees fictives, rendues avec ses vrais reglages (tailles,
-- textes libres, couleurs, portrait, rang).
---------------------------------------------------------------------------

local PV_POWER = { MANA = { 0, 0.44, 0.87 }, RAGE = { 0.78, 0.15, 0.15 }, ENERGY = { 1, 0.85, 0.1 },
                   FOCUS = { 1, 0.5, 0.25 } }
local PV_ARENA = { "WARRIOR", "PRIEST", "ROGUE", "MAGE", "PALADIN" }

local function fakeData(f)
    local key, i = f.styleKey, f.index or 1
    if key == "target" then
        return { name = L.CF_PV_TARGET, level = 62, rank = "elite", hp = 37728, max = 52400, pw = 4400, pwMax = 8000,
                 power = "MANA", hostile = true, icon = "Interface\\Icons\\INV_Misc_Head_Dragon_Black" }
    elseif key == "targettarget" then
        local okN, n = pcall(UnitName, "player")
        local _, class = UnitClass("player")
        return { name = (okN and not issecret(n) and n) or "?", level = 60, class = class, hp = 3520, max = 4000,
                 pw = 2900, pwMax = 4800, power = "MANA", icon = "Interface\\Icons\\INV_Misc_QuestionMark" }
    elseif key == "pet" then
        return { name = L.CF_PV_PET, level = 60, hp = 3200, max = 3200, pw = 80, pwMax = 100, power = "FOCUS",
                 icon = "Interface\\Icons\\Ability_Hunter_Pet_Wolf" }
    elseif key == "focus" then
        return { name = L.CF_PV_FOCUS, level = 60, class = "MAGE", hp = 1845, max = 4100, pw = 1800, pwMax = 6000,
                 power = "MANA", hostile = true, icon = "Interface\\Icons\\Spell_Frost_FrostBolt02" }
    elseif key == "boss" then
        return { name = f.preview or L.FRAMES_BOSS, level = -1, rank = "worldboss", hp = 1000 - (i - 1) * 180,
                 max = 1000, pw = 100, pwMax = 100, power = "RAGE", hostile = true,
                 icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01" }
    elseif key == "arena" then
        local class = PV_ARENA[i] or "WARRIOR"
        return { name = f.preview or L.FRAMES_ARENA, level = 60, class = class, hp = 4200 - i * 500, max = 4200,
                 pw = 60, pwMax = 100, power = class == "WARRIOR" and "RAGE" or class == "ROGUE" and "ENERGY" or "MANA",
                 hostile = true, icon = "Interface\\Icons\\INV_Misc_QuestionMark" }
    end
end

local PV_RANK = { elite = { "FRAMES_RANK_ELITE", RANK_GOLD, RANK_GOLD }, worldboss = { "FRAMES_RANK_BOSS", RANK_BOSS, RANK_GOLD } }

local function fakeValue(what, cur, max)
    local pct = max > 0 and math.floor(cur / max * 100 + 0.5) or 0
    if what == "cur" then return short(cur) end
    if what == "pct" then return pct .. "%" end
    if what == "curmax" then return short(cur) .. " / " .. short(max) end
    if what == "curmaxpct" then return short(cur) .. " / " .. short(max) .. "  " .. pct .. "%" end
    if what == "curpct" then return short(cur) .. "  " .. pct .. "%" end
    if what == "deficit" then return cur < max and ("-" .. short(max - cur)) or "" end
    return ""
end

local function fakeUpdate(f)
    local d = fakeData(f)
    if not d then return false end
    local s = style(f)
    local rank = d.rank and PV_RANK[d.rank]
    -- couleurs : classe (joueurs) ou reaction (hostile / amical), comme le vrai
    local cr, cg, cb
    if d.class then cr, cg, cb = ns.ClassColor(d.class)
    elseif d.hostile then cr, cg, cb = 0.8, 0.15, 0.15
    else cr, cg, cb = 0.2, 0.75, 0.25 end
    setBar(f.hp, d.hp, d.max)
    if s.color == "theme" then
        local a = ns.COLORS.violet
        f.hp:SetStatusBarColor(a[1], a[2], a[3])
    else
        f.hp:SetStatusBarColor(cr, cg, cb)
    end
    setBar(f.pw, d.pw, d.pwMax)
    local pc = PV_POWER[d.power] or PV_POWER.MANA
    f.pw:SetStatusBarColor(pc[1], pc[2], pc[3])
    if f.heal then f.heal:Hide() end
    local mode = s.nameColor or "auto"
    local nr, ng, nb
    if mode == "white" then nr, ng, nb = 1, 1, 1
    elseif mode == "reaction" then
        if d.hostile then nr, ng, nb = 0.8, 0.15, 0.15 else nr, ng, nb = 0.2, 0.75, 0.25 end
    elseif mode == "class" or d.class then nr, ng, nb = cr, cg, cb
    else nr, ng, nb = 1, 0.82, 0 end
    for _, key in ipairs(SLOTS) do
        local tag = s.texts[key]
        local fs = f.texts[key]
        fs:SetAlpha(1)
        fs:SetTextColor(1, 1, 1)
        local txt = ""
        if tag == "name" then
            txt = d.name
            fs:SetTextColor(nr, ng, nb)
        elseif tag == "nameshort" then
            txt = utf8sub(d.name, s.nameLen or 10)
            fs:SetTextColor(nr, ng, nb)
        elseif tag == "level" or tag == "levelclass" then
            txt = d.level > 0 and tostring(d.level) or "??"
            if tag == "levelclass" and rank then
                local c = rank[2]
                txt = txt .. string.format(" |cff%02x%02x%02x%s|r", math.floor(c[1] * 255 + 0.5),
                    math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5), L[rank[1]])
            end
        elseif tag == "class" then
            txt = d.class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[d.class] or ""
        elseif tag == "group" then
            txt = string.format(L.FRAMES_GROUP_FMT, 1)
        elseif tagKind(tag) == "health" then
            txt = fakeValue(tag:sub(4), d.hp, d.max)
        elseif tagKind(tag) == "power" then
            txt = fakeValue(tag:sub(4), d.pw, d.pwMax)
        end
        fs:SetText(txt)
    end
    -- rang : liseré et lueur du bandeau
    if f.rankGlow then
        local edge = rank and rank[3]
        if edge then
            f.border:SetColorTexture(edge[1], edge[2], edge[3], 1)
            ns.UI.Gradient(f.rankGlow, "HORIZONTAL", edge[1], edge[2], edge[3], 0, edge[1], edge[2], edge[3], 0.28)
            f.rankGlow:Show()
        else
            ns.UI.ResetBorder(f)
            f.rankGlow:Hide()
        end
    end
    local p = f.portrait
    if p then
        local pmode = s.portrait or "none"
        p:SetShown(pmode ~= "none")
        p.model:Hide()
        p.tex:Show()
        p.tex:SetTexture(d.icon)
    end
    return true
end

-- Icone de raid (16/10) : celle de l unite (numero secret, pose par
-- ns.RaidMark), un crane dans l apercu ; position, taille, decalage et
-- opacite reglables par cadre
local function updateMark(f, fake)
    local m = f.mark
    if not m then return end
    local s = style(f)
    local shown = false
    if s.mark then
        if fake then
            shown = ns.RaidMark(m, nil, f.unit == "player" and 1 or 8)
        elseif UnitExists(f.unit) then
            shown = ns.RaidMark(m, f.unit)
        end
    end
    m:SetShown(shown)
end

local function layoutMark(f)
    if not f.mark then return end
    local s = style(f)
    ns.UI.PlaceRaidMark(f.mark, f, s.markPos, s.markSize, s.markX, s.markY, s.markAlpha)
end

local function updateAll(f)
    updateMood(f)
    if not UnitExists(f.unit) and ns.PreviewOn("units") and fakeUpdate(f) then
        updateMark(f, true)
        return
    end
    updateMark(f)
    if not UnitExists(f.unit) then
        -- apercu pour les placer (interface deverrouillee) : leur nom
        -- (dans le texte du nom, sinon a gauche du bandeau)
        if f.preview then
            local texts = style(f).texts
            local slot = "nameL"
            for _, key in ipairs(SLOTS) do
                if texts[key] == "name" or texts[key] == "nameshort" then slot = key break end
            end
            for _, key in ipairs(SLOTS) do
                local fs = f.texts[key]
                fs:SetAlpha(1)
                fs:SetText(key == slot and f.preview or "")
                if key == slot then fs:SetTextColor(1, 0.82, 0) end
            end
        end
        updatePortrait(f)
        updateRank(f)
        updateRest(f)
        return
    end
    updatePortrait(f)
    updateRank(f)
    updateRest(f)
    updateInfo(f)
    updateHealth(f)
    updatePower(f)
end

local function updateCombat()
    local inCombat = unitFlag(UnitAffectingCombat, "player")
    local f = frames.player
    if not f then return end
    -- en combat : liseré rouge, sinon celui du theme
    if inCombat then f.border:SetColorTexture(0.85, 0.12, 0.12, 1) else ns.UI.ResetBorder(f) end
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

local function makeBar(parent, h)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetHeight(h)
    bar:SetStatusBarTexture(ns.BAR_TEXTURE)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.55)
    return bar
end

-- poignee commune (grille, aimantation, reglage au pixel : Movers.lua)
local function makeMover(f, store, label)
    f.mover = ns.UI.Mover(f, store, label)
end

local function build(u, store)
    local unit, small = u.unit, u.small
    local f = CreateFrame("Button", "CorpUI" .. u.name .. "Frame", UIParent, "SecureActionButtonTemplate")
    f.unit, f.small = unit, small
    f.styleKey = u.group or unit
    -- tailles de depart ; les vraies viennent du reglage du cadre (layoutFrame)
    local hTop, hHp, hPw = H_TOP, H_HP, H_PW
    f:SetSize(W, hTop + hHp + hPw + 6)
    f:SetScale(db.scale or 1)
    if u.below then
        -- boss 2 a 5 : sous le precedent
        f:SetPoint("TOP", frames[u.below], "BOTTOM", 0, -8)
    else
        ns.ApplyPos(f, store)
    end
    if u.group then f.preview = L[u.label] .. " " .. u.index end
    f.index = u.index
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:SetAttribute("unit", unit)
    f:SetAttribute("type1", "target")
    f:SetAttribute("type2", "togglemenu")
    ns.UF.HoverTooltip(f)
    -- modele d action (et non "unite") : le modele "unite" passe chaque clic par
    -- les raccourcis de clic de Blizzard, qui ignorent ou bloquent nos reglages
    -- (Maj+clic "cibler" abandonne). Appui ET relachement : il agit a l appui
    -- si l option du jeu "action a l appui" est active.
    f:RegisterForClicks("AnyUp", "AnyDown")
    ns.RegisterUnitButton(f)

    f.border = ns.UI.Skin(f, 0.92, true)
    -- elite / rare : lueur du bandeau (liseré recolore par updateRank)
    if unit ~= "player" then
        f.rankGlow = f:CreateTexture(nil, "BACKGROUND", nil, -5)
        f.rankGlow:SetPoint("TOPLEFT", 0, 0)
        f.rankGlow:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, -H_TOP)
        f.rankGlow:SetColorTexture(1, 1, 1, 1)
        f.rankGlow:Hide()
    else
        -- repos : pastille "Zz" qui respire doucement
        local r = CreateFrame("Frame", nil, f)
        r:SetSize(24, 16)
        r:SetFrameLevel(f:GetFrameLevel() + 6)
        ns.UI.Skin(r, 0.92)
        r.cuiBorder:SetColorTexture(ns.COLORS.violet[1], ns.COLORS.violet[2], ns.COLORS.violet[3], 1)
        r.text = r:CreateFontString(nil, "OVERLAY")
        ns.UI.HeadFont(r.text, 10)
        r.text:SetPoint("CENTER", 0, 0)
        r.text:SetText("Zz")
        r.text:SetTextColor(ns.COLORS.gold[1], ns.COLORS.gold[2], ns.COLORS.gold[3])
        r:EnableMouse(true)
        r:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L.FRAMES_RESTING)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        pcall(function()
            local g = r:CreateAnimationGroup()
            g:SetLooping("BOUNCE")
            local a = g:CreateAnimation("Alpha")
            a:SetFromAlpha(1)
            a:SetToAlpha(0.45)
            a:SetDuration(1.4)
            r.pulse = g
        end)
        r:Hide()
        f.rest = r
    end
    -- familier de chasseur : humeur (nourriture), a droite du cadre
    if unit == "pet" then
        local m = CreateFrame("Frame", nil, f)
        m:SetSize(20, 20)
        m:SetPoint("LEFT", f, "RIGHT", 4, 0)
        m:SetFrameLevel(f:GetFrameLevel() + 6)
        ns.UI.Skin(m, 0.92)
        m.tex = m:CreateTexture(nil, "ARTWORK")
        m.tex:SetPoint("TOPLEFT", 1, -1)
        m.tex:SetPoint("BOTTOMRIGHT", -1, 1)
        m:EnableMouse(true)
        m:SetScript("OnEnter", moodTooltip)
        m:SetScript("OnLeave", function() GameTooltip:Hide() end)
        m:Hide()
        f.mood = m
    end

    -- textes libres (emplacements, voir SLOTS) ; ancres et polices : layoutFrame
    f.texts = {}
    f.texts.nameL = f:CreateFontString(nil, "OVERLAY", small and "GameFontNormalSmall" or "GameFontNormal")
    f.texts.nameL:SetPoint("TOPLEFT", 4, small and -2 or -3)
    f.texts.nameL:SetPoint("RIGHT", small and -24 or -34, 0)
    f.texts.nameR = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.texts.nameR:SetPoint("TOPRIGHT", -4, small and -3 or -4)

    f.hp = makeBar(f, hHp)
    f.hp:SetPoint("TOPLEFT", 2, -hTop)
    f.hp:SetPoint("TOPRIGHT", -2, -hTop)
    -- soins entrants (sous les textes)
    f.heal = ns.UF.HealBar(f.hp)
    f.hpTop = CreateFrame("Frame", nil, f.hp)
    f.hpTop:SetAllPoints(f.hp)
    f.hpTop:SetFrameLevel(f.hp:GetFrameLevel() + 3)
    for _, key in ipairs({ "hpL", "hpC", "hpR" }) do
        local fs = f.hpTop:CreateFontString(nil, "OVERLAY", small and "GameFontHighlightSmall" or "GameFontHighlight")
        fs:SetPoint("CENTER")
        f.texts[key] = fs
    end

    f.pw = makeBar(f, hPw)
    f.pw:SetPoint("TOPLEFT", f.hp, "BOTTOMLEFT", 0, -2)
    f.pw:SetPoint("TOPRIGHT", f.hp, "BOTTOMRIGHT", 0, -2)
    f.texts.pwC = f.pw:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.texts.pwC:SetPoint("CENTER")
    f.texts.pwC:Hide()
    for _, fs in pairs(f.texts) do fs:SetWordWrap(false) end
    -- anciens noms (nom, niveau, texte de vie, texte du mana)
    f.name, f.level, f.hpText, f.pwText = f.texts.nameL, f.texts.nameR, f.texts.hpC, f.texts.pwC

    -- portrait : carre de la hauteur du cadre, a l exterieur ; cote et
    -- taille poses par layoutFrame (reglage du cadre). Cadre simple (non
    -- securise) enfant du bouton : rien de securise ne s y accroche.
    do
        local h = hTop + hHp + hPw + 6
        local p = CreateFrame("Frame", nil, f)
        p:SetSize(h, h)
        p:SetPoint("TOPRIGHT", f, "TOPLEFT", -3, 0)
        ns.UI.Skin(p, 0.92, true)
        p.tex = p:CreateTexture(nil, "ARTWORK")
        p.tex:SetPoint("TOPLEFT", 1, -1)
        p.tex:SetPoint("BOTTOMRIGHT", -1, 1)
        p.tex:SetTexCoord(0.12, 0.88, 0.12, 0.88)
        p.model = CreateFrame("PlayerModel", nil, p)
        p.model:SetPoint("TOPLEFT", 1, -1)
        p.model:SetPoint("BOTTOMRIGHT", -1, 1)
        p:Hide()
        f.portrait = p
    end

    -- icone de raid : au-dessus des barres et des textes
    f.markHost = CreateFrame("Frame", nil, f)
    f.markHost:SetAllPoints(f)
    f.markHost:SetFrameLevel(f:GetFrameLevel() + 12)
    f.mark = f.markHost:CreateTexture(nil, "OVERLAY", nil, 7)
    f.mark:Hide()

    if not u.below then makeMover(f, store, L[u.label]) end

    -- evenements de cette unite seulement
    local ev = CreateFrame("Frame")
    ev:SetScript("OnEvent", function(_, event)
        if ns.ModuleOff("cadres", ev) then return end
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_CONNECTION" then
            updateHealth(f)
        elseif event == "UNIT_HEAL_PREDICTION" then
            ns.UF.UpdateHeal(f.heal, f.unit, db.healPrediction)
        elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
            updatePower(f)
        elseif event == "UNIT_PORTRAIT_UPDATE" or event == "UNIT_MODEL_CHANGED" then
            updatePortrait(f)
        else
            updateInfo(f)
        end
    end)
    for _, e in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER",
                         "UNIT_DISPLAYPOWER", "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION",
                         "UNIT_CONNECTION", "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_HEAL_PREDICTION" }) do
        pcall(ev.RegisterUnitEvent, ev, e, unit)
    end
    f:SetScript("OnShow", function(self)
        if not u.below then ns.PinTop(self, store) end
        updateAll(self)
    end)
    frames[unit] = f
    return f
end

-- Tailles et polices d un cadre selon son reglage (hors combat)
local function layoutFrame(f)
    local s = style(f)
    local pw = s.power
    local h = s.top + s.hp + (pw > 0 and (pw + 2) or 0) + 4
    f:SetSize(s.width, h)
    f.hp:ClearAllPoints()
    f.hp:SetPoint("TOPLEFT", 2, -s.top)
    f.hp:SetPoint("TOPRIGHT", -2, -s.top)
    f.hp:SetHeight(s.hp)
    f.pw:SetHeight(math.max(1, pw))
    f.pw:SetShown(pw > 0)
    local bold = (ns.FontFile and ns.FontFile("bold")) or STANDARD_TEXT_FONT
    local regular = (ns.FontFile and ns.FontFile("regular")) or STANDARD_TEXT_FONT
    -- police de chaque emplacement (et non de l etiquette) : comme avant,
    -- gras pour la gauche du bandeau, contour pour les barres
    local t = f.texts
    pcall(t.nameL.SetFont, t.nameL, bold, s.nameSize, "")
    pcall(t.nameR.SetFont, t.nameR, regular, math.max(8, s.nameSize - 2), "")
    for _, key in ipairs({ "hpL", "hpC", "hpR" }) do
        pcall(t[key].SetFont, t[key], regular, s.valueSize, "OUTLINE")
    end
    pcall(t.pwC.SetFont, t.pwC, regular, math.max(7, s.valueSize - 2), "OUTLINE")
    t.pwC:SetShown(s.texts.pwC ~= "none" and pw >= 6)
    -- bandeau du haut : gauche et droite centres en hauteur ; la gauche
    -- prend toute la largeur si la droite est vide
    local y = -math.max(1, math.floor((s.top - s.nameSize) / 2))
    t.nameL:ClearAllPoints()
    t.nameL:SetPoint("TOPLEFT", 4, y)
    t.nameR:ClearAllPoints()
    t.nameR:SetPoint("TOPRIGHT", -4, y - 1)
    t.nameR:SetJustifyH("RIGHT")
    -- la gauche s arrete ou commence la droite ("62 Élite" est plus long)
    if s.texts.nameR == "none" then
        t.nameL:SetPoint("RIGHT", -4, 0)
    else
        t.nameL:SetPoint("RIGHT", t.nameR, "LEFT", -4, 0)
    end
    t.nameL:SetJustifyH("LEFT")
    if f.rankGlow then
        f.rankGlow:ClearAllPoints()
        f.rankGlow:SetPoint("TOPLEFT", 0, 0)
        f.rankGlow:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, -s.top)
    end
    -- barre de vie : gauche, centre, droite
    t.hpL:ClearAllPoints()
    t.hpL:SetPoint("LEFT", f.hpTop, "LEFT", 4, 0)
    t.hpL:SetJustifyH("LEFT")
    t.hpC:ClearAllPoints()
    t.hpC:SetPoint("CENTER", f.hpTop, "CENTER")
    t.hpR:ClearAllPoints()
    t.hpR:SetPoint("RIGHT", f.hpTop, "RIGHT", -4, 0)
    t.hpR:SetJustifyH("RIGHT")
    if f.portrait then
        local p = f.portrait
        p:SetSize(h, h)
        p:ClearAllPoints()
        if s.portraitSide == "right" then
            p:SetPoint("TOPLEFT", f, "TOPRIGHT", 3, 0)
        else
            p:SetPoint("TOPRIGHT", f, "TOPLEFT", -3, 0)
        end
    end
    layoutMark(f)
    updateAll(f)
end

---------------------------------------------------------------------------
-- Affichage, verrou, cadres de Blizzard (hors combat uniquement)
---------------------------------------------------------------------------

local function blizzard(hide)
    ns.HideBlizzard({ "PlayerFrame", "TargetFrame", "PetFrame", "FocusFrame", "BossTargetFrameContainer",
        "Boss1TargetFrame", "Boss2TargetFrame", "Boss3TargetFrame", "Boss4TargetFrame", "Boss5TargetFrame",
        "ArenaEnemyFramesContainer", "ArenaEnemyFrames" }, hide)
end

local appliedPreview = false

local function apply()
    if InCombatLockdown() then
        ns.Say(L.COMBAT_BLOCKED)
        return
    end
    -- un seul verrou : "Deverrouiller l interface" (onglet General) ; apercu
    -- pendant le reglage (page des cadres ouverte) : cadres montres sans unite
    local unlocked = ns.moversShown
    local previewing = ns.PreviewOn("units")
    appliedPreview = previewing
    for _, u in ipairs(UNITS) do
        local f = frames[u.unit]
        local show = db[u.show]
        local wasShown = f:IsShown()
        f:SetScale(db.scale)
        layoutFrame(f)
        if not u.watch then
            f:SetShown(show)
        elseif show and (unlocked or previewing) then
            -- deverrouille ou apercu : visible meme sans unite
            UnregisterUnitWatch(f)
            f:Show()
        elseif show then
            -- suit l existence de l unite, gere par le code securise
            RegisterUnitWatch(f)
        else
            UnregisterUnitWatch(f)
            f:Hide()
        end
        if f.mover then f.mover:SetShown(unlocked and show) end
        -- un cadre qui vient de s afficher a deja ete relu par son OnShow
        if u.watch and (wasShown or not f:IsShown()) then updateAll(f) end
    end
    if db.hideBlizzard or db.blizzardHidden then
        blizzard(db.hideBlizzard)
        db.blizzardHidden = db.hideBlizzard
    end
end

---------------------------------------------------------------------------
-- Diagnostic lisible
---------------------------------------------------------------------------

local function yesno(v, yes, no)
    if v == nil then return "|cff888888?|r" end
    return v and yes or no
end

local function printDiag()
    ns.Say(L.FRAMES_DIAG_TITLE)
    local any = false
    for _, key in ipairs({ "player", "player_combat", "target", "target_combat" }) do
        local d = db.diag[key]
        if d then
            any = true
            local unit, combat = key:match("^(%a+)(_?%a*)$")
            local label = (unit == "player" and L.FRAMES_PLAYER or L.FRAMES_TARGET) ..
                (combat ~= "" and (" (" .. L.FRAMES_IN_COMBAT .. ")") or "")
            local textMode = d.text == "full" and ("|cff00ff00" .. L.FRAMES_TEXT_FULL .. "|r")
                or d.text == "api" and ("|cff00ff00" .. L.FRAMES_TEXT_API .. "|r")
                or d.text == "format" and ("|cffffd100" .. L.FRAMES_TEXT_FORMAT .. "|r")
                or d.text == "none" and ("|cffff4040" .. L.FRAMES_TEXT_NONE .. "|r") or "?"
            ns.Chat(string.format("  %s : " .. L.FRAMES_DIAG_LINE, label,
                yesno(d.health, "|cffffd100" .. L.FRAMES_SECRET .. "|r", "|cff00ff00" .. L.FRAMES_READABLE .. "|r"),
                yesno(d.bar, "|cff00ff00OK|r", "|cffff4040" .. L.FRAMES_FAIL .. "|r"),
                textMode))
        end
    end
    if not any then ns.Chat("  " .. L.FRAMES_NO_DIAG) end
end

---------------------------------------------------------------------------
-- Fenetre d options
---------------------------------------------------------------------------

-- Sections de l editeur des cadres (Cadres/Editeur.lua) : chaque fonction
-- construit ses reglages dans parent a partir de y et renvoie le y suivant.
ns.FramesOpt = ns.FramesOpt or {}

-- cadre (cle de style) -> case "afficher" de la sauvegarde
local SHOW_KEY = { player = "showPlayer", target = "showTarget", targettarget = "showToT", pet = "showPet",
                   focus = "showFocus", boss = "showBoss", arena = "showArena" }

-- reglages communs a tous les cadres d unite
function ns.FramesOpt.Common(parent, y)
    local form = ns.UI.Form(parent, y, function() apply() end)
    form:Header(L.FRAMES_COMMON_HEAD)
    form:Check(L.FRAMES_OPT_BLIZZ, function() return db.hideBlizzard end, function(v) db.hideBlizzard = v end)
    form:Check(L.FRAMES_OPT_HEAL, function() return db.healPrediction end, function(v) db.healPrediction = v end)
    form:Check(L.FRAMES_OPT_REST, function() return db.restIcon end, function(v) db.restIcon = v end)
    form:Columns(2)
    form:Number(L.FRAMES_SCALE, function() return db.scale end, function(v)
        db.scale = math.max(0.6, math.min(1.6, math.floor(v * 10 + 0.5) / 10))
    end, 0.6, 1.6, 0.1)
    form:EndColumns()
    -- diagnostic : /corp cadres diag (outil, hors du menu)
    parent:HookScript("OnShow", function() form:Refresh() end)
    return form.y
end

-- afficher ce cadre (boss et arene : les cinq)
function ns.FramesOpt.Show(parent, y, key)
    local form = ns.UI.Form(parent, y, function() apply() end)
    form:Check(L.FRAMES_OPT_SHOW, function() return db[SHOW_KEY[key]] end, function(v) db[SHOW_KEY[key]] = v end)
    if key == "pet" then
        form:Check(L.FRAMES_OPT_PETMOOD, function() return db.petMood end, function(v) db.petMood = v end)
    end
    parent:HookScript("OnShow", function() form:Refresh() end)
    return form.y
end

-- apparence et textes d un cadre (boss et arene : un reglage pour les cinq)
function ns.FramesOpt.Style(parent, y, key)
    local function cur() return db.style[key] end
    local form = ns.UI.Form(parent, y, function() apply() end)
    form:Header(L.FRAMES_STYLE)
    form:Columns(2)
    local function num(fmt, k, lo, hi, step)
        form:Number(fmt, function() return cur()[k] end, function(v) cur()[k] = v end, lo, hi, step)
    end
    num(L.FRAMES_WIDTH, "width", 60, 400, 5)
    num(L.FRAMES_TOP, "top", 8, 40)
    num(L.FRAMES_HP_H, "hp", 6, 60)
    num(L.FRAMES_PW_H, "power", 0, 30)
    num(L.FRAMES_NAME_SIZE, "nameSize", 8, 24)
    num(L.FRAMES_VALUE_SIZE, "valueSize", 7, 24)
    form:Cycle(L.FRAMES_HP_COLOR, { "class", "theme" }, { class = L.FRAMES_COLOR_CLASS, theme = L.FRAMES_COLOR_THEME },
        function() return cur().color end, function(v) cur().color = v end)
    form:Cycle(L.FRAMES_NAME_COLOR, NAME_COLORS, { auto = L.FRAMES_NCOLOR_AUTO, class = L.FRAMES_COLOR_CLASS,
        reaction = L.FRAMES_NCOLOR_REACTION, white = L.FRAMES_NCOLOR_WHITE },
        function() return cur().nameColor or "auto" end, function(v) cur().nameColor = v end)
    form:Cycle(L.FRAMES_PORTRAIT, PORTRAITS,
        { none = L.FRAMES_PORTRAIT_NONE, ["2d"] = L.FRAMES_PORTRAIT_2D, ["3d"] = L.FRAMES_PORTRAIT_3D },
        function() return cur().portrait or "none" end, function(v) cur().portrait = v end)
    form:Cycle(L.FRAMES_PORTRAIT_SIDE, SIDES, { left = L.FRAMES_SIDE_LEFT, right = L.FRAMES_SIDE_RIGHT },
        function() return cur().portraitSide or "left" end, function(v) cur().portraitSide = v end)
    form:EndColumns()
    -- recopier les polices et les couleurs de ce cadre sur tous (pas les tailles)
    local copy = ns.UI.Button(parent, L.FRAMES_STYLE_COPY, 200, function()
        local c = cur()
        for _, k in ipairs(STYLE_ORDER) do
            local o = db.style[k]
            o.nameSize, o.valueSize, o.color, o.nameColor = c.nameSize, c.valueSize, c.color, c.nameColor
        end
        apply()
        form:Refresh()
    end)
    copy:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, form.y)
    form:Gap(28)
    -- textes libres : une etiquette par emplacement
    form:Header(L.FRAMES_TEXTS)
    form:Columns(2)
    local tagNames = {}
    for _, tag in ipairs(TAGS) do tagNames[tag] = L[TAG_LABEL[tag]] end
    for _, slot in ipairs(SLOTS) do
        form:Cycle(L[SLOT_LABEL[slot]], TAGS, tagNames,
            function() return (cur().texts or {})[slot] or "none" end, function(v)
                local st = cur()
                st.texts = st.texts or textDefaults(st)
                st.texts[slot] = v
            end)
    end
    num(L.FRAMES_NAME_LEN, "nameLen", 3, 30)
    form:EndColumns()
    -- icone de raid (16/10) : un crane dans l apercu de la page
    form:Header(L.FRAMES_MARK_HEAD)
    form:Check(L.FRAMES_MARK_SHOW, function() return cur().mark end, function(v) cur().mark = v end)
    form:Columns(2)
    local posNames = {}
    for _, p in ipairs(ns.RAID_MARK_POS) do posNames[p] = L["MARK_POS_" .. p:upper()] end
    form:Cycle(L.FRAMES_MARK_POS, ns.RAID_MARK_POS, posNames,
        function() return cur().markPos or "top" end, function(v) cur().markPos = v end)
    num(L.FRAMES_MARK_SIZE, "markSize", 8, 48)
    num(L.FRAMES_MARK_X, "markX", -100, 100)
    num(L.FRAMES_MARK_Y, "markY", -100, 100)
    num(L.FRAMES_MARK_ALPHA, "markAlpha", 10, 100, 5)
    form:EndColumns()
    parent:HookScript("OnShow", function() form:Refresh() end)
    return form.y
end

ns.FramesDiag = function() if db then printDiag() end end

---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if ns.ModuleOff("cadres", ev) then return end
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        root.frames = root.frames or {}
        db = root.frames
        db.diag = {}        -- releves de cette session seulement
        for _, u in ipairs(UNITS) do
            if db[u.show] == nil then db[u.show] = true end
        end
        -- l interface de Blizzard qu on remplace est masquee par defaut (une fois)
        if not db.blizzDefault2 then
            db.hideBlizzard = true
            db.blizzDefault2 = true
        end
        db.scale = db.scale or 1
        if db.healPrediction == nil then db.healPrediction = true end
        if db.restIcon == nil then db.restIcon = true end
        if db.petMood == nil then db.petMood = true end
        -- apparence par cadre : valeurs par defaut pour les reglages manquants
        db.style = db.style or {}
        for _, key in ipairs(STYLE_ORDER) do
            local s = db.style[key] or {}
            db.style[key] = s
            -- portrait : ancien reglage global (joueur et cible), repris une fois
            if s.portrait == nil and (key == "player" or key == "target") and db.portrait then
                s.portrait = db.portrait
            end
            for k, v in pairs(styleDefaults(key)) do
                if s[k] == nil then s[k] = v end
            end
            -- textes libres : repris une fois des anciens reglages (texte de
            -- vie, texte du mana), puis emplacements manquants completes
            s.texts = s.texts or {}
            for slot, tag in pairs(textDefaults(s)) do
                if s.texts[slot] == nil or not TAG_LABEL[s.texts[slot]] then s.texts[slot] = tag end
            end
        end
        for _, u in ipairs(UNITS) do
            db[u.pos] = db[u.pos] or { point = u.def.point, x = u.def.x, y = u.def.y }
            build(u, db[u.pos])
        end
        apply()
        updateCombat()
    elseif not db then
        return
    elseif event == "PLAYER_TARGET_CHANGED" then
        if frames.target then updateAll(frames.target) end
        if frames.targettarget then updateAll(frames.targettarget) end
    elseif event == "UNIT_TARGET" then
        if frames.targettarget then updateAll(frames.targettarget) end
    elseif event == "UNIT_PET" then
        if frames.pet then updateAll(frames.pet) end
    elseif event == "PLAYER_FOCUS_CHANGED" then
        if frames.focus then updateAll(frames.focus) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        for _, f in pairs(frames) do updateAll(f) end
    elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" or event == "UNIT_TARGETABLE_CHANGED"
        or event == "ARENA_OPPONENT_UPDATE" then
        -- boss / adversaires : l unite derriere boss1... a pu changer
        for _, f in pairs(frames) do if f.preview then updateAll(f) end end
    elseif event == "RAID_TARGET_UPDATE" then
        for _, f in pairs(frames) do
            if UnitExists(f.unit) then updateMark(f) end
        end
    elseif event == "PLAYER_UPDATE_RESTING" then
        if frames.player then updateRest(frames.player) end
    elseif event == "UNIT_HAPPINESS" or event == "PET_UI_UPDATE" then
        if frames.pet then updateMood(frames.pet) end
    elseif event == "GROUP_ROSTER_UPDATE" then
        -- etiquette "groupe en raid"
        for _, f in pairs(frames) do if UnitExists(f.unit) then updateInfo(f) end end
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        -- page des cadres ouverte / fermee pendant le combat : apercu a revoir
        if event == "PLAYER_REGEN_ENABLED" and appliedPreview ~= ns.PreviewOn("units") then apply() end
        updateCombat()
        -- une mise a jour par phase pour que le diagnostic voie les deux
        for _, f in pairs(frames) do updateAll(f) end
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD",
                     "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_PET", "PLAYER_FOCUS_CHANGED",
                     "INSTANCE_ENCOUNTER_ENGAGE_UNIT", "UNIT_TARGETABLE_CHANGED", "ARENA_OPPONENT_UPDATE",
                     "GROUP_ROSTER_UPDATE", "PLAYER_UPDATE_RESTING", "UNIT_HAPPINESS", "PET_UI_UPDATE",
                     "RAID_TARGET_UPDATE" }) do
    pcall(ev.RegisterEvent, ev, e)
end
pcall(ev.RegisterUnitEvent, ev, "UNIT_TARGET", "target")

-- la cible de la cible n a pas d evenement fiable : relue 4 fois par seconde,
-- seulement affichee ; la meme unite : vie, puissance et textes seulement
ns.Every(0.25, function()
    local f = frames.targettarget
    if not (f and f:IsVisible()) then return end
    local ok, g = pcall(UnitGUID, "targettarget")
    if ok and g and not issecret(g) and g == f.totGUID then
        updateInfo(f)
        updateHealth(f)
        updatePower(f)
        updateMark(f)
        return
    end
    f.totGUID = (ok and g and not issecret(g)) and g or nil
    updateAll(f)
end, "Cadres : cible de la cible", "cadres")

-- module "cadres" : editeur de tous les cadres (Cadres/Editeur.lua)

-- L interrupteur general "Deverrouiller l interface" montre aussi nos poignees
ns.Listen(function()
    if not db or not frames.player or InCombatLockdown() then return end
    apply()
end)
