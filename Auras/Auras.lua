--[[--------------------------------------------------------------------------
    CorpUI - module Auras
    - Buffs du joueur (en haut a droite) : clic droit = annuler le buff.
      Les emplacements sont des boutons securises FIXES (cancelaura sur
      l index i) : ils n ont jamais besoin d etre affiches/masques en
      combat, seuls leur icone et leur texte changent. L emplacement i
      montre toujours l aura n° i, donc le clic annule la bonne.
    - Debuffs du joueur (en dessous), bordure couleur du type de magie.
    - Auras de la cible, au-dessus (ou au-dessous) de notre cadre cible :
      debuffs puis buffs.
    Les cadres BuffFrame / DebuffFrame de Blizzard vont au parent cache.
    - Enchantements d arme temporaires (13/10 : pierre a aiguiser, poison,
      armes du chaman ; la fenetre des buffs de Blizzard les montrait) :
      deux emplacements a droite des buffs (main droite, main gauche),
      icone de l arme, temps restant, charges ; clic droit : annuler
      (action securisee "cancelaura" sur l emplacement). Boutons securises
      toujours affiches : sans enchantement, transparents.

    Disposition par groupe (db.layout.buffs / debuffs / target) : taille,
    nombre par ligne, nombre maximum, espacement, sens (haut / bas), temps
    restant (aucun, texte sous l icone, decompte natif du Cooldown).
    Appliquee hors combat seulement (les buffs sont des boutons securises).

    Valeurs secretes : icone et nombre passent tels quels ; la duree passe
    par l objet de duree du client (C_UnitAuras.GetAuraDuration) pour le
    balayage, le texte de temps restant est tente puis abandonne ; le
    decompte natif du Cooldown n a besoin d aucune lecture de notre part.
    Filtre "mes debuffs" : demande au client (filtre "HARMFUL|PLAYER"),
    sans lire la source de l aura (qui peut etre secrete).
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local issecret = issecretvalue or function() return false end

local MAX_BUFFS, MAX_DEBUFFS, MAX_TARGET = 32, 40, 40
local TIME_H = 10        -- place du texte de temps sous une icone
local BLIZZ = { "BuffFrame", "DebuffFrame" }

-- groupes reglables (liste du panneau) et valeurs de depart (celles d avant)
local GROUPS = { "buffs", "debuffs", "target" }
local GROUP_LABEL = { buffs = "AURAS_BUFFS", debuffs = "AURAS_DEBUFFS", target = "AURAS_TARGET" }
local DEFAULTS = {
    buffs   = { size = 30, perRow = 12, max = 32, spacing = 4, grow = "down", time = "below", center = false },
    debuffs = { size = 30, perRow = 12, max = 16, spacing = 4, grow = "down", time = "below", center = false },
    target  = { size = 22, perRow = 10, max = 16, spacing = 3, grow = "up", time = "none" },
}
local TIMES = { "none", "below", "native" }
local GROWS = { "up", "down" }
local FILTERS = { "all", "debuffs", "mine" }

local db
local buffs, debuffs, target = {}, {}, {}
local buffHeader, debuffHeader, targetHeader

---------------------------------------------------------------------------
-- Une icone d aura
---------------------------------------------------------------------------

local function decorate(b, size)
    b:SetSize(size, size)
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetPoint("TOPLEFT", -1, 1)
    ns.NoSnap(b.border)
    b.border:SetPoint("BOTTOMRIGHT", 1, -1)
    b.border:SetColorTexture(ns.COLORS.border[1], ns.COLORS.border[2], ns.COLORS.border[3], 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints()
    b.cd:SetReverse(true)
    if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(true) end
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", 2, -2)
    b.time = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.time:SetPoint("TOP", b, "BOTTOM", 0, -1)
end

-- enchantement d arme : present, secondes restantes, charges ; nil si
-- illisible (valeur secrete : on garde l affichage d avant)
local function enchantInfo(off)
    local function n(v) return type(v) == "number" and not issecret(v) and v or nil end
    if C_Item and C_Item.GetWeaponEnchantInfo then
        local slots = Enum and Enum.WeaponSlot
        local slot
        if off then slot = slots and slots.OffHand or 1 else slot = slots and slots.MainHand or 0 end
        local ok, list = pcall(C_Item.GetWeaponEnchantInfo, slot)
        if ok and type(list) == "table" then
            local secret = false
            for _, e in pairs(list) do
                if type(e) == "table" then
                    if issecret(e.hasEnchant) then
                        secret = true
                    elseif e.hasEnchant then
                        local ms = n(e.timeLeft)
                        return true, ms and ms > 0 and ms / 1000 or nil, n(e.charges) or 0
                    end
                end
            end
            if secret then return nil end
            return false
        end
    end
    if GetWeaponEnchantInfo then
        local ok, hasMH, mhExp, mhCh, _, hasOH, ohExp, ohCh = pcall(GetWeaponEnchantInfo)
        if not ok or issecret(hasMH) or issecret(hasOH) then return nil end
        local has, ms, ch = hasMH, n(mhExp), n(mhCh)
        if off then has, ms, ch = hasOH, n(ohExp), n(ohCh) end
        return has and true or false, ms and ms > 0 and ms / 1000 or nil, ch or 0
    end
    return nil
end

local function formatLeft(sec)
    if sec >= 3600 then return string.format("%dh", math.floor(sec / 3600)) end
    if sec >= 60 then return string.format("%dm", math.floor(sec / 60)) end
    return string.format("%d", math.floor(sec))
end

-- id : identifiant de l aura (ns.UnitAuraList), lu dans l aura sinon ;
-- les champs de l aura peuvent etre secrets (en combat) : tout sous pcall
local function setAura(b, unit, aura, showTime, id)
    b.unit, b.auraIndex = unit, nil
    if not issecret(aura) and not aura then
        b.icon:SetTexture(nil)
        b.count:SetText("")
        b.time:SetText("")
        b.cd:Clear()
        b.border:SetColorTexture(0, 0, 0, 0)
        b.data = nil
        return false
    end
    b.data = aura
    if not id then
        local okI, v = pcall(function() return aura.auraInstanceID end)
        id = okI and v or nil
    end
    b.auraID = id
    b.border:SetColorTexture(ns.COLORS.border[1], ns.COLORS.border[2], ns.COLORS.border[3], 1)
    if not pcall(function() b.icon:SetTexture(aura.icon) end) then b.icon:SetTexture(nil) end
    if not pcall(b.count.SetText, b.count, ns.AuraCountText(unit, id, aura)) then b.count:SetText("") end
    -- balayage : objet de duree, sinon debut + duree lisibles
    local swept = false
    if C_UnitAuras.GetAuraDuration and b.cd.SetCooldownFromDurationObject and id then
        local ok, d = pcall(C_UnitAuras.GetAuraDuration, unit, id)
        swept = ok and d and pcall(b.cd.SetCooldownFromDurationObject, b.cd, d) or false
    end
    if not swept then
        if not pcall(function()
            if aura.duration and aura.duration > 0 then
                b.cd:SetCooldown(aura.expirationTime - aura.duration, aura.duration)
            else
                b.cd:Clear()
            end
        end) then b.cd:Clear() end
    end
    local okE, exp = pcall(function() return aura.expirationTime end)
    b.expires = okE and exp or nil
    if showTime then
        local ok, left = pcall(function()
            if aura.expirationTime and aura.expirationTime > 0 then return aura.expirationTime - GetTime() end
        end)
        b.time:SetText(ok and left and left > 0 and formatLeft(left) or "")
    else
        b.time:SetText("")
    end
    return true
end

---------------------------------------------------------------------------
-- Filtres : liste noire (jamais affichee) et liste blanche (seules
-- affichees, pour les groupes reglés sur "liste blanche"). Une entree est
-- un nom de sort (sans majuscules) ou un numero de sort. Une aura dont le
-- nom et le numero sont secrets ne peut pas etre filtree : elle s affiche.
---------------------------------------------------------------------------

local FILTER_MODES = { "off", "black", "white" }

-- nom (minuscules) et numero lisibles d une aura
local function auraKeys(a)
    local name, id
    local ok, n = pcall(function() return a.name end)
    if ok and type(n) == "string" and not issecret(n) then name = n:lower() end
    local ok2, s = pcall(function() return a.spellId end)
    if ok2 and type(s) == "number" and not issecret(s) then id = tostring(s) end
    return name, id
end

local function listed(list, name, id)
    return (name and list[name]) or (id and list[id]) or false
end

-- group : "debuffs", "target" ou "group" (icones des cadres de groupe)
function ns.AuraAllowed(a, group)
    if not db or not db.filter or not a then return true end
    local f = db.filter
    local mode = f.mode[group] or "off"
    if mode == "off" then return true end
    local name, id = auraKeys(a)
    if not name and not id then return true end
    if listed(f.black, name, id) then return false end
    if mode == "white" then return listed(f.white, name, id) and true or false end
    return true
end

local function filterAdd(listName, text)
    text = strtrim(text or "")
    if text == "" then return false end
    db.filter[listName][text:lower()] = true
    return true
end

-- Alt + clic sur une icone : l aura passe en liste noire
local function blockFromIcon(b, group)
    if not (IsAltKeyDown() and b.data) then return end
    local name, id = auraKeys(b.data)
    local key = name or id
    if not key then ns.Say(L.AURAS_FILTER_SECRET) return end
    db.filter.black[key] = true
    if db.filter.mode[group] == "off" then db.filter.mode[group] = "black" end
    ns.Say(string.format(L.AURAS_FILTER_ADDED, key))
    if ns.AurasRefresh then ns.AurasRefresh() end
end

local function debuffColor(aura)
    local ok, t = pcall(function() return aura.dispelName end)
    if not ok or issecret(t) then t = nil end
    local c = t and DebuffTypeColor and DebuffTypeColor[t]
    if c then return c.r, c.g, c.b end
    return 0.8, 0, 0
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

local function header(name, store, w, h, label)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(w, h)
    ns.ApplyPos(f, store)
    ns.UI.Mover(f, store, label)
    return f
end

local ENCHANT_SLOTS = { 16, 17 }     -- main droite, main gauche
local enchants = {}

local function buildEnchants()
    for k, slot in ipairs(ENCHANT_SLOTS) do
        local b = CreateFrame("Button", "CorpUIWeaponEnchant" .. k, buffHeader, "SecureActionButtonTemplate")
        decorate(b, DEFAULTS.buffs.size)
        b:RegisterForClicks("RightButtonUp", "RightButtonDown")
        b:SetAttribute("type2", "cancelaura")
        b:SetAttribute("target-slot", slot)
        b.slot, b.off = slot, k == 2
        b.border:SetColorTexture(0.64, 0.21, 0.93, 1)
        b:SetScript("OnEnter", function(self)
            if not self.has then return end
            local t = ns.Tooltip(self, "ANCHOR_BOTTOMLEFT")
            if not pcall(t.SetInventoryItem, t, "player", self.slot) then t:Hide() return end
            t:AddLine(L.AURAS_CANCEL, 0.5, 0.8, 1)
            t:Show()
        end)
        b:SetScript("OnLeave", ns.HideTooltip)
        b:SetAlpha(0)
        enchants[k] = b
    end
end

-- a droite des buffs (ils partent du bord droit vers la gauche) ; hors combat
local function layoutEnchants()
    local c = db.layout.buffs
    local timeH = c.time == "below" and TIME_H or 0
    for k, b in ipairs(enchants) do
        local x = c.spacing + (k - 1) * (c.size + c.spacing)
        b:SetSize(c.size, c.size)
        b:ClearAllPoints()
        if c.grow == "up" then
            b:SetPoint("BOTTOMLEFT", buffHeader, "BOTTOMRIGHT", x, timeH)
        else
            b:SetPoint("TOPLEFT", buffHeader, "TOPRIGHT", x, 0)
        end
        b.time:SetShown(c.time ~= "none")
        b:Show()
    end
end

-- etat des enchantements : transparence, icone, temps (permis en combat)
local function updateEnchants()
    for _, b in ipairs(enchants) do
        local has, left, charges = enchantInfo(b.off)
        if has ~= nil then
            if not db.weaponEnchants then has = false end
            b.has = has
            if has then
                local ok, tex = pcall(GetInventoryItemTexture, "player", b.slot)
                b.icon:SetTexture(ok and not issecret(tex) and tex or "Interface\\Icons\\INV_Misc_QuestionMark")
                b.time:SetText(left and formatLeft(left) or "")
                b.count:SetText((charges or 0) > 1 and charges or "")
                b:SetAlpha(1)
            else
                b.icon:SetTexture(nil)
                b.time:SetText("")
                b.count:SetText("")
                b:SetAlpha(0)
            end
        end
    end
end
ns._enchants = { list = enchants, update = function() updateEnchants() end }

local function buildPlayer()
    db.buffPos = db.buffPos or { point = "TOPRIGHT", x = -230, y = -14 }
    db.debuffPos = db.debuffPos or { point = "TOPRIGHT", x = -230, y = -120 }
    -- taille reelle posee par layoutGroup
    buffHeader = header("CorpUIBuffs", db.buffPos, 12 * 34, 3 * 44, L.AURAS_BUFFS)
    debuffHeader = header("CorpUIDebuffs", db.debuffPos, 12 * 34, 2 * 44, L.AURAS_DEBUFFS)

    for i = 1, MAX_BUFFS do
        local b = CreateFrame("Button", "CorpUIBuff" .. i, buffHeader, "SecureActionButtonTemplate")
        decorate(b, DEFAULTS.buffs.size)
        b:RegisterForClicks("RightButtonUp", "RightButtonDown")
        b:SetAttribute("type2", "cancelaura")
        b:SetAttribute("unit", "player")
        b:SetAttribute("index", i)
        b:SetAttribute("filter", "HELPFUL")
        b:SetScript("OnEnter", function(self)
            if not self.data then return end
            local t = ns.Tooltip(self, "ANCHOR_BOTTOMLEFT")
            if not pcall(t.SetUnitBuffByAuraInstanceID, t, "player", self.data.auraInstanceID)
                and not pcall(t.SetUnitAura, t, "player", i, "HELPFUL") then t:Hide() return end
            t:AddLine(L.AURAS_CANCEL, 0.5, 0.8, 1)
            t:Show()
        end)
        b:SetScript("OnLeave", ns.HideTooltip)
        buffs[i] = b
    end
    buildEnchants()
    for i = 1, MAX_DEBUFFS do
        local b = CreateFrame("Frame", nil, debuffHeader)
        decorate(b, DEFAULTS.debuffs.size)
        b:EnableMouse(true)
        b:SetScript("OnEnter", function(self)
            if not self.data then return end
            local t = ns.Tooltip(self, "ANCHOR_BOTTOMLEFT")
            if not pcall(t.SetUnitDebuffByAuraInstanceID, t, "player", self.data.auraInstanceID)
                and not pcall(t.SetUnitAura, t, "player", self.idx or i, "HARMFUL") then t:Hide() return end
            t:Show()
        end)
        b:SetScript("OnLeave", ns.HideTooltip)
        b:SetScript("OnMouseUp", function(self) blockFromIcon(self, "debuffs") end)
        b:Hide()
        debuffs[i] = b
    end
end

-- auras de la cible par le conteneur du client (lisibles en combat) ;
-- nos boutons ne servent plus que si le client ne l a pas
local native
-- idem pour les buffs et debuffs du joueur : en combat, ce client refuse
-- toute lecture d aura a un addon, nos boutons se vidaient
local nativeBuffs, nativeDebuffs

-- numeros de sorts d une liste de filtre (le conteneur ne filtre que par numero)
local function spellIDs(list)
    local out, any = {}, false
    for k in pairs(list or {}) do
        local id = tonumber(k)
        if id then out[id] = true any = true end
    end
    return out, any
end

-- filtres par numero pour un conteneur du client (group : "target", "group"...)
function ns.AurasSpellFilter(group, base)
    local t = base or {}
    local f = db and db.filter
    if not f then return t end
    local mode = f.mode[group] or "off"
    if mode == "black" or mode == "white" then
        local ex, anyEx = spellIDs(f.black)
        if anyEx then t.excludeSpellIDs = ex end
    end
    if mode == "white" then t.includeSpellIDs = spellIDs(f.white) end
    return t
end

local function targetSpec()
    local c = db.layout.target
    local f = db.filter
    local mode = f and f.mode.target or "off"
    local function cand(extra)
        local t = extra or {}
        if mode == "black" or mode == "white" then
            local ex, anyEx = spellIDs(f.black)
            if anyEx then t.excludeSpellIDs = ex end
        end
        if mode == "white" then t.includeSpellIDs = spellIDs(f.white) end
        return t
    end
    local filter = db.targetFilter
    return {
        width = c.size, height = c.size, spacing = c.spacing, perRow = c.perRow, max = c.max,
        grow = c.grow, fromRight = false, time = c.time,
        groups = {
            { key = "mine", filter = "HARMFUL", candidate = cand({ isFromPlayerOrPlayerPet = true }) },
            { key = "others", filter = "HARMFUL", candidate = cand({ isFromPlayerOrPlayerPet = false }),
              desaturate = db.desaturateOthers, enabled = filter ~= "mine" },
            { key = "buffs", filter = "HELPFUL", candidate = cand(), enabled = filter == "all" },
        },
    }
end

-- buffs / debuffs du joueur, depuis le coin droit de leur poignee
local function playerSpec(key)
    local c = db.layout[key]
    local spec = {
        width = c.size, height = c.size, spacing = c.spacing, perRow = c.perRow, max = c.max,
        grow = c.grow, fromRight = not c.center, center = c.center or nil, time = c.time,
        tooltipAnchor = "ANCHOR_BOTTOMLEFT",
    }
    if key == "buffs" then
        spec.cancel = "RightButtonUp"
        spec.groups = { { key = "buffs", filter = "HELPFUL", candidate = {} } }
    else
        spec.groups = { { key = "debuffs", filter = "HARMFUL", candidate = ns.AurasSpellFilter("debuffs") } }
    end
    return spec
end

local function buildNativePlayer()
    if not ns.NativeAuras then return end
    nativeBuffs = ns.NativeAuras(buffHeader, "player", playerSpec("buffs"))
    nativeDebuffs = ns.NativeAuras(debuffHeader, "player", playerSpec("debuffs"))
end

local function buildTarget()
    targetHeader = CreateFrame("Frame", "CorpUITargetAuras", UIParent)
    targetHeader:SetSize(10 * 25, 2 * 25)
    for i = 1, MAX_TARGET do
        local b = CreateFrame("Frame", nil, targetHeader)
        decorate(b, DEFAULTS.target.size)
        b:EnableMouse(true)
        b:SetScript("OnEnter", function(self)
            if not self.data then return end
            local t = ns.Tooltip(self, "ANCHOR_BOTTOMRIGHT")
            local fn = self.harmful and t.SetUnitDebuffByAuraInstanceID or t.SetUnitBuffByAuraInstanceID
            if not (fn and pcall(fn, t, "target", self.auraID)) then t:Hide() return end
            t:Show()
        end)
        b:SetScript("OnLeave", ns.HideTooltip)
        b:SetScript("OnMouseUp", function(self) blockFromIcon(self, "target") end)
        b:Hide()
        target[i] = b
    end
    native = ns.NativeAuras and ns.NativeAuras(targetHeader, "target", targetSpec())
end

-- Disposition d un groupe selon son reglage. Hors combat seulement : les
-- buffs sont des boutons securises (taille, place, affichage).
local GROUP_ICONS = { buffs = function() return buffs, buffHeader, true end,
                      debuffs = function() return debuffs, debuffHeader, true end,
                      target = function() return target, targetHeader, false end }

local function layoutGroup(key)
    local c = db.layout[key]
    if key == "buffs" and #enchants > 0 then layoutEnchants() end
    local list, h, fromRight = GROUP_ICONS[key]()
    local n = math.max(1, math.min(c.max, #list))
    local timeH = c.time == "below" and TIME_H or 0
    local stepX = c.size + c.spacing
    local stepY = c.size + c.spacing + timeH
    local per = math.max(1, c.perRow)
    h:SetSize(per * stepX, math.ceil(n / per) * stepY)
    local font = (ns.FontFile and ns.FontFile("regular")) or STANDARD_TEXT_FONT
    for i, b in ipairs(list) do
        local col, row = (i - 1) % per, math.floor((i - 1) / per)
        local x = fromRight and -col * stepX or col * stepX
        b:SetSize(c.size, c.size)
        b:ClearAllPoints()
        if c.grow == "up" then
            -- premiere ligne en bas (pres du cadre cible), les suivantes au-dessus
            b:SetPoint(fromRight and "BOTTOMRIGHT" or "BOTTOMLEFT", x, timeH + row * stepY)
        else
            b:SetPoint(fromRight and "TOPRIGHT" or "TOPLEFT", x, -row * stepY)
        end
        b.inRange = i <= n
        b.time:SetShown(c.time == "below")
        if c.time ~= "below" then b.time:SetText("") end
        if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(c.time ~= "native") end
        -- chiffres du decompte natif a l echelle de l icone
        if c.time == "native" and b.cd.GetCountdownFontString then
            local ok, fs = pcall(b.cd.GetCountdownFontString, b.cd)
            if ok and fs then pcall(fs.SetFont, fs, font, math.max(8, math.floor(c.size * 0.45)), "OUTLINE") end
        end
    end
    if key == "target" and native then
        for _, b in ipairs(list) do b.inRange = false b:Hide() end
        native:Apply(targetSpec())
    end
    -- joueur par le conteneur du client : nos boutons restent caches
    local na = (key == "buffs" and nativeBuffs) or (key == "debuffs" and nativeDebuffs)
    if na then
        if not InCombatLockdown() then
            for _, b in ipairs(list) do b.inRange = false b:Hide() end
        end
        na:Apply(playerSpec(key))
        return
    end
    -- buffs : emplacements fixes, affiches jusqu au maximum
    if key == "buffs" and not InCombatLockdown() then
        for _, b in ipairs(list) do b:SetShown(b.inRange) end
    end
end

-- Au-dessus de notre cadre cible s il existe (vers le haut), ou en
-- dessous (vers le bas : sous la barre de sort accrochee, s il y en a une) ;
-- sinon a une place par defaut
local function placeTarget()
    targetHeader:ClearAllPoints()
    local tf = _G.CorpUITargetFrame
    local down = db.layout.target.grow == "down"
    if tf and down then
        local cb = ns.CastBarAttached and ns.CastBarAttached("target") and _G.CorpUICastBartarget
        local combo = ns.ComboOn and ns.ComboOn("target", "below")
        targetHeader:SetPoint("TOPLEFT", combo or cb or tf, "BOTTOMLEFT", 0, -4)
    elseif tf then
        local combo = ns.ComboOn and ns.ComboOn("target", "above")
        targetHeader:SetPoint("BOTTOMLEFT", combo or tf, "TOPLEFT", 0, 4)
    else
        targetHeader:SetPoint("CENTER", UIParent, "CENTER", 260, -260)
    end
end

---------------------------------------------------------------------------
-- Mise a jour
---------------------------------------------------------------------------

local function getAura(unit, i, filter)
    local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
    return ok and a or nil
end

local function updatePlayer()
    if not db.player then return end
    if nativeBuffs and nativeDebuffs then return end   -- le client s en charge
    local below = db.layout.buffs.time == "below"
    for i, b in ipairs(buffs) do
        setAura(b, "player", b.inRange and getAura("player", i, "HELPFUL") or nil, below)
    end
    below = db.layout.debuffs.time == "below"
    local j = 0
    for i = 1, 40 do
        local a = getAura("player", i, "HARMFUL")
        if not a then break end
        if ns.AuraAllowed(a, "debuffs") then
            local b = debuffs[j + 1]
            if not (b and b.inRange) then break end
            j = j + 1
            if setAura(b, "player", a, below) then
                b.idx = i
                b.border:SetColorTexture(debuffColor(a))
                b:Show()
            else
                b:Hide()
            end
        end
    end
    for k = j + 1, #debuffs do
        setAura(debuffs[k], "player", nil, below)
        debuffs[k]:Hide()
    end
end

local function fromPlayer(a)
    local ok, mine = pcall(function() return a.isFromPlayerOrPlayerPet or a.sourceUnit == "player" end)
    return ok and mine and not issecret(mine) and mine or false
end

---------------------------------------------------------------------------
-- Apercu (page des cadres ouverte, sans cible) : auras fictives sur nos
-- icones de cible, avec les vrais reglages (taille, lignes, sens, temps,
-- filtre, debuffs des autres grises). Le conteneur du client, lui, n a
-- rien a montrer sans cible.
---------------------------------------------------------------------------

local PV_TARGET = {
    { icon = "Interface\\Icons\\Spell_Nature_FaerieFire", harmful = true, mine = true, type = "Magic", left = 34, total = 40 },
    { icon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain", harmful = true, mine = true, type = "Magic", left = 14, total = 18 },
    { icon = "Interface\\Icons\\Ability_Warrior_Sunder", harmful = true, count = 5, left = 27, total = 30 },
    { icon = "Interface\\Icons\\Spell_Shadow_CurseOfSargeras", harmful = true, type = "Curse", left = 9, total = 24 },
    { icon = "Interface\\Icons\\Ability_Warrior_WarCry", harmful = true, left = 21, total = 30 },
    { icon = "Interface\\Icons\\Spell_Holy_PowerWordShield", left = 22, total = 30 },
    { icon = "Interface\\Icons\\Spell_Nature_Regeneration", left = 1700, total = 1800 },
    { icon = "Interface\\Icons\\Spell_Holy_WordFortitude", left = 1500, total = 1800 },
    { icon = "Interface\\Icons\\Spell_Nature_Rejuvenation", left = 8, total = 12 },
}
local previewTarget = false

-- vrai : l apercu occupe les icones de cible
local function fakeTarget()
    local on = db.target and ns.PreviewOn and ns.PreviewOn("units") and not UnitExists("target")
    if not on then
        if previewTarget then
            previewTarget = false
            for _, b in ipairs(target) do
                b.cd:Clear()
                b:Hide()
            end
        end
        return false
    end
    previewTarget = true
    local c = db.layout.target
    local filter = db.targetFilter
    local list = {}
    for _, a in ipairs(PV_TARGET) do
        if a.harmful then
            if filter ~= "mine" or a.mine then list[#list + 1] = a end
        elseif filter == "all" then
            list[#list + 1] = a
        end
    end
    local n = math.min(c.max, #target)
    local now = GetTime()
    for i, b in ipairs(target) do
        local a = i <= n and list[i]
        if a then
            b.data, b.expires, b.auraID = nil, nil, nil
            b.icon:SetTexture(a.icon)
            b.count:SetText(a.count and tostring(a.count) or "")
            b.time:SetText(c.time == "below" and formatLeft(a.left) or "")
            if not pcall(b.cd.SetCooldown, b.cd, now - (a.total - a.left), a.total) then b.cd:Clear() end
            if a.harmful then
                local col = a.type and DebuffTypeColor and DebuffTypeColor[a.type]
                if col then b.border:SetColorTexture(col.r, col.g, col.b, 1) else b.border:SetColorTexture(0.8, 0, 0, 1) end
                b.icon:SetDesaturated((not a.mine and db.desaturateOthers) and true or false)
            else
                b.border:SetColorTexture(ns.COLORS.border[1], ns.COLORS.border[2], ns.COLORS.border[3], 1)
                b.icon:SetDesaturated(false)
            end
            b.harmful = a.harmful and true or false
            b:Show()
        else
            b:Hide()
        end
    end
    return true
end

local function updateTarget()
    if not db.target then return end
    if fakeTarget() then return end
    if native then
        native:Refresh()
        return
    end
    local c = db.layout.target
    local list = {}
    if UnitExists("target") then
        -- par identifiants (lisibles meme en combat) ; "mes debuffs" : le
        -- client dit lui-meme lesquels sont a moi
        local mineOnly = db.targetFilter == "mine"
        for _, e in ipairs(ns.UnitAuraList("target", "HARMFUL", mineOnly, 40, true)) do
            if ns.AuraAllowed(e.aura, "target") then
                table.insert(list, { a = e.aura, id = e.id, harmful = true, mine = e.mine })
            end
        end
        if db.targetFilter ~= "debuffs" and not mineOnly then
            for _, e in ipairs(ns.UnitAuraList("target", "HELPFUL", false, 40)) do
                if ns.AuraAllowed(e.aura, "target") then
                    table.insert(list, { a = e.aura, id = e.id, harmful = false })
                end
            end
        end
    end
    local below = c.time == "below"
    for i, b in ipairs(target) do
        local e = b.inRange and list[i]
        if e and setAura(b, "target", e.a, below, e.id) then
            b.harmful = e.harmful
            if e.harmful then
                local mine = e.mine
                if mine == nil then mine = fromPlayer(e.a) end
                b.border:SetColorTexture(debuffColor(e.a))
                b.icon:SetDesaturated(not mine and db.desaturateOthers)
            else
                b.border:SetColorTexture(ns.COLORS.border[1], ns.COLORS.border[2], ns.COLORS.border[3], 1)
                b.icon:SetDesaturated(false)
            end
            b:Show()
        else
            b:Hide()
        end
    end
end

-- texte de temps restant (sous l icone) : une fois par seconde
local function tickIcon(b)
    if not (b.data and b.expires) then return end
    local ok, left = pcall(function()
        if b.expires > 0 then return b.expires - GetTime() end
    end)
    b.time:SetText(ok and left and left > 0 and formatLeft(left) or "")
end

local function tickTimes()
    updateEnchants()
    if db.layout.buffs.time == "below" then
        for _, b in ipairs(buffs) do tickIcon(b) end
    end
    if db.layout.debuffs.time == "below" then
        for _, b in ipairs(debuffs) do if b:IsShown() then tickIcon(b) end end
    end
    if db.layout.target.time == "below" then
        for _, b in ipairs(target) do if b:IsShown() then tickIcon(b) end end
    end
end

local function layoutAll()
    for _, key in ipairs(GROUPS) do layoutGroup(key) end
end

local function apply()
    if InCombatLockdown() then return end
    layoutAll()
    buffHeader:SetShown(db.player)
    debuffHeader:SetShown(db.player)
    targetHeader:SetShown(db.target)
    placeTarget()
    if db.hideBlizzard or db.blizzardHidden then
        ns.HideBlizzard(BLIZZ, db.player and db.hideBlizzard)
        db.blizzardHidden = db.player and db.hideBlizzard
    end
    updatePlayer()
    updateTarget()
end

---------------------------------------------------------------------------
-- Fenetre d options
---------------------------------------------------------------------------

-- Sections de l editeur des cadres (Cadres/Editeur.lua) : auras du joueur
-- (cadre Joueur), de la cible (cadre Cible), filtre des icones de groupe
-- (cadres Groupe / Raid) et listes de filtres (reglages communs).
-- En combat rien ne change (le reglage est relu et revient a sa valeur).
ns.FramesOpt = ns.FramesOpt or {}

local function guard()
    if InCombatLockdown() then ns.Say(L.COMBAT_BLOCKED) return false end
    return true
end

local function auraForm(parent, y)
    local form = ns.UI.Form(parent, y, function()
        if not InCombatLockdown() then apply() end
    end)
    parent:HookScript("OnShow", function() form:Refresh() end)
    return form
end

-- disposition d un groupe d icones (buffs, debuffs, cible)
local function layoutControls(form, key)
    local function cur() return db.layout[key] end
    form:Columns(2)
    local function num(fmt, k, lo, hi)
        form:Number(fmt, function() return cur()[k] end, function(v)
            if guard() then cur()[k] = v end
        end, lo, hi, 1)
    end
    num(L.AURAS_SIZE, "size", 12, 64)
    num(L.AURAS_PERROW, "perRow", 1, 20)
    num(L.AURAS_MAX, "max", 1, 40)
    num(L.AURAS_SPACING, "spacing", 0, 20)
    form:Cycle(L.AURAS_GROW, GROWS, { up = L.AURAS_GROW_UP, down = L.AURAS_GROW_DOWN },
        function() return cur().grow end, function(v) if guard() then cur().grow = v end end)
    form:Cycle(L.AURAS_TIME, TIMES,
        { none = L.AURAS_TIME_NONE, below = L.AURAS_TIME_BELOW, native = L.AURAS_TIME_NATIVE },
        function() return cur().time end, function(v) if guard() then cur().time = v end end)
    -- buffs et debuffs du joueur : ligne centree sur la poignee (style Moderne)
    if key ~= "target" then
        form:Check(L.AURAS_CENTER, function() return cur().center end, function(v)
            if guard() then cur().center = v end
        end)
    end
    form:EndColumns()
end

local MODE_NAMES
local function filterMode(form, g)
    MODE_NAMES = MODE_NAMES or { off = L.AURAS_FMODE_OFF, black = L.AURAS_FMODE_BLACK, white = L.AURAS_FMODE_WHITE }
    form:Columns(2)
    form:Cycle(L.AURAS_FILTER_MODE, FILTER_MODES, MODE_NAMES,
        function() return db and db.filter and db.filter.mode[g] or "off" end, function(v) db.filter.mode[g] = v end)
    form:EndColumns()
end

local function check(form, key, text)
    form:Check(text, function() return db[key] end, function(v)
        if guard() then db[key] = v end
    end)
end

function ns.FramesOpt.PlayerAuras(parent, y)
    local form = auraForm(parent, y)
    form:Header(L.AURAS_BUFFS)
    check(form, "player", L.AURAS_OPT_PLAYER)
    check(form, "hideBlizzard", L.AURAS_OPT_BLIZZ)
    check(form, "weaponEnchants", L.AURAS_OPT_ENCHANTS)
    layoutControls(form, "buffs")
    form:Header(L.AURAS_DEBUFFS)
    layoutControls(form, "debuffs")
    filterMode(form, "debuffs")
    return form.y
end

function ns.FramesOpt.TargetAuras(parent, y)
    local form = auraForm(parent, y)
    form:Header(L.AURAS_TARGET)
    check(form, "target", L.AURAS_OPT_TARGET)
    check(form, "desaturateOthers", L.AURAS_OPT_OTHERS)
    form:Columns(2)
    form:Cycle(L.AURAS_FILTER, FILTERS,
        { all = L.AURAS_FILTER_ALL, debuffs = L.AURAS_FILTER_DEBUFFS, mine = L.AURAS_FILTER_MINE },
        function() return db.targetFilter end, function(v) if guard() then db.targetFilter = v end end)
    form:EndColumns()
    layoutControls(form, "target")
    filterMode(form, "target")
    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, form.y - 2)
    hint:SetWidth(420)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.AURAS_LAYOUT_HINT)
    form:Gap(30)
    return form.y
end

-- filtre des icones de debuffs des cadres de groupe / raid
function ns.FramesOpt.GroupAuraFilter(parent, y)
    local form = auraForm(parent, y)
    filterMode(form, "group")
    return form.y
end

-- listes noire et blanche (communes aux trois filtres)
function ns.FramesOpt.AuraLists(parent, y)
    local form = auraForm(parent, y)
    form:Header(L.AURAS_FILTERS)
    local which = "black"
    local listSel = form:Select(nil, function()
        return { { value = "black", text = L.AURAS_LIST_BLACK }, { value = "white", text = L.AURAS_LIST_WHITE } }
    end, function() return which end, function(v) which = v end, 190)
    local edit = CreateFrame("EditBox", nil, parent)
    edit:SetSize(140, 22)
    edit:SetPoint("LEFT", listSel, "RIGHT", 8, 0)
    edit:SetAutoFocus(false)
    edit:SetFontObject("GameFontHighlightSmall")
    edit:SetTextInsets(6, 6, 0, 0)
    edit:SetMaxLetters(60)
    ns.UI.Skin(edit, 0.8)
    local ph = edit:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ph:SetPoint("LEFT", 6, 0)
    ph:SetText(L.AURAS_FILTER_INPUT)
    local function syncPh() ph:SetShown((edit:GetText() or "") == "" and not edit:HasFocus()) end
    edit:SetScript("OnEditFocusGained", syncPh)
    edit:SetScript("OnEditFocusLost", syncPh)
    edit:SetScript("OnTextChanged", syncPh)
    local function addTyped()
        if filterAdd(which, edit:GetText()) then
            edit:SetText("")
            form.Changed()
            ns.AurasRefresh()
        end
        edit:ClearFocus()
    end
    edit:SetScript("OnEnterPressed", addTyped)
    edit:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
    local add = ns.UI.Button(parent, L.AURAS_FILTER_ADD, 70, addTyped)
    add:SetPoint("LEFT", edit, "RIGHT", 6, 0)
    -- contenu de la liste choisie : deux colonnes, x pour retirer ; la
    -- section garde la place de 6 lignes (12 entrees), au-dela la liste deborde
    local listFrame = CreateFrame("Frame", nil, parent)
    listFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, form.y - 2)
    listFrame:SetSize(420, 18)
    local rows = {}
    local ROW = 18
    local function shownName(key)
        local id = tonumber(key)
        if id and C_Spell and C_Spell.GetSpellName then
            local ok, n = pcall(C_Spell.GetSpellName, id)
            if ok and type(n) == "string" and not issecret(n) then return key .. "  |cff999999" .. n .. "|r" end
        end
        return key
    end
    local function refreshList()
        if not (db and db.filter) then return end
        local keys = {}
        for k in pairs(db.filter[which]) do table.insert(keys, k) end
        table.sort(keys)
        for i, key in ipairs(keys) do
            local r = rows[i]
            if not r then
                r = CreateFrame("Button", nil, listFrame)
                r:SetSize(204, ROW)
                local hl = r:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0.06)
                r.x = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                r.x:SetPoint("LEFT", 2, 0)
                r.x:SetText("×")
                r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                r.text:SetPoint("LEFT", 14, 0)
                r.text:SetPoint("RIGHT", -2, 0)
                r.text:SetJustifyH("LEFT")
                r.text:SetWordWrap(false)
                r:SetScript("OnClick", function(self)
                    db.filter[which][self.key] = nil
                    form.Changed()
                    ns.AurasRefresh()
                end)
                rows[i] = r
            end
            r.key = key
            r.text:SetText(shownName(key))
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", ((i - 1) % 2) * 210, -math.floor((i - 1) / 2) * ROW)
            r:Show()
        end
        for i = #keys + 1, #rows do rows[i]:Hide() end
        if #keys == 0 then
            listFrame.empty = listFrame.empty or listFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            listFrame.empty:SetPoint("TOPLEFT", 2, -3)
            listFrame.empty:SetText(L.AURAS_FILTER_EMPTY)
        end
        if listFrame.empty then listFrame.empty:SetShown(#keys == 0) end
        listFrame:SetHeight(math.max(1, math.ceil(#keys / 2)) * ROW)
        if parent.Relayout then parent:Relayout() end
    end
    table.insert(form.refreshers, refreshList)
    refreshList()
    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", listFrame, "BOTTOMLEFT", 0, -6)
    hint:SetWidth(420)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.AURAS_FILTER_HINT)
    -- place reservee : 6 lignes de liste + l aide
    return form.y - 6 * ROW - 50
end

---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, unit)
    if ns.ModuleOff("auras", ev) then return end
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        root.auras = root.auras or {}
        db = root.auras
        for k, v in pairs({ player = true, hideBlizzard = true, target = true, desaturateOthers = true,
                            targetFilter = "all", weaponEnchants = true }) do
            if db[k] == nil then db[k] = v end
        end
        db.layout = db.layout or {}
        for _, key in ipairs(GROUPS) do
            local c = db.layout[key] or {}
            db.layout[key] = c
            for k, v in pairs(DEFAULTS[key]) do
                if c[k] == nil then c[k] = v end
            end
        end
        db.auraProbe = nil
        db.filter = db.filter or {}
        db.filter.black = db.filter.black or {}
        db.filter.white = db.filter.white or {}
        db.filter.mode = db.filter.mode or {}
        for k, v in pairs({ debuffs = "black", target = "black", group = "black" }) do
            if db.filter.mode[k] == nil then db.filter.mode[k] = v end
        end
        buildPlayer()
        buildNativePlayer()
        buildTarget()
        -- premiere disposition meme en combat (/reload) : comme avant, les
        -- boutons sont places a leur creation
        layoutAll()
        apply()
    elseif not db then
        return
    elseif event == "UNIT_AURA" then
        if unit == "player" then updatePlayer() elseif unit == "target" then updateTarget() end
    elseif event == "UNIT_INVENTORY_CHANGED" or event == "PLAYER_EQUIPMENT_CHANGED" then
        updateEnchants()
    elseif event == "PLAYER_TARGET_CHANGED" then
        updateTarget()
    elseif event == "PLAYER_ENTERING_WORLD" then
        apply()
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "UNIT_AURA", "PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD",
                     "UNIT_INVENTORY_CHANGED", "PLAYER_EQUIPMENT_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)
end

-- /corp auras diag : ce que le client rend pour les debuffs de la cible
function ns.AurasDiag()
    local function show(v)
        if issecret(v) then return "S" end
        return tostring(v)
    end
    ns.Say(string.format("auras diag : cible %s, filtre %s, combat %s, cadre %s",
        tostring(UnitExists("target")), tostring(db and db.targetFilter), tostring(InCombatLockdown()),
        tostring(targetHeader and targetHeader:IsVisible())))
    for _, filter in ipairs({ "HARMFUL", "HARMFUL|PLAYER", "PLAYER|HARMFUL", "HELPFUL" }) do
        local n, first, err = 0, nil, nil
        for i = 1, 40 do
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "target", i, filter)
            if not ok then err = tostring(a):sub(1, 60) break end
            if type(a) ~= "table" then break end
            n = n + 1
            first = first or a
        end
        local line = filter .. " : " .. n .. (err and (" ERR " .. err) or "")
        if first then
            local ok, s = pcall(function()
                local okA, allowed = pcall(ns.AuraAllowed, first, "target")
                return string.format(" | nom %s id %s icone %s moi %s src %s inst %s ok %s", show(first.name), show(first.spellId),
                    show(first.icon), show(first.isFromPlayerOrPlayerPet), show(first.sourceUnit), show(first.auraInstanceID),
                    tostring(okA and allowed))
            end)
            line = line .. (ok and s or " | ?")
        end
        ns.Say(line)
    end
    local all = ns.UnitAuraList("target", "HARMFUL", false, 40)
    local mine = ns.UnitAuraList("target", "HARMFUL", true, 40)
    ns.Say(string.format("par identifiants : %d debuffs, %d a moi (API %s)", #all, #mine,
        tostring(C_UnitAuras.GetUnitAuraInstanceIDs ~= nil)))
    local shown = 0
    for _, b in ipairs(target) do if b:IsShown() then shown = shown + 1 end end
    ns.Say("icones affichees : " .. shown .. ", IsAuraFilteredOut : " .. tostring(C_UnitAuras.IsAuraFilteredOutByInstanceID ~= nil))
end

function ns.AurasRefresh()
    if not db then return end
    if native and not InCombatLockdown() then native:Apply(targetSpec()) end
    if not InCombatLockdown() then
        if nativeBuffs then nativeBuffs:Apply(playerSpec("buffs")) end
        if nativeDebuffs then nativeDebuffs:Apply(playerSpec("debuffs")) end
    end
    updatePlayer()
    updateTarget()
    if ns.GroupRefreshAuras then ns.GroupRefreshAuras() end
end

local elapsed = 0
ev:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 1 or not db then return end
    elapsed = 0
    tickTimes()
end)

-- reglages : editeur des cadres (Cadres/Editeur.lua), cadres Joueur et Cible
ns.RegisterModule({
    command = "auras",
    title = function() return L.MOD_AURAS end,
    desc = function() return L.AURAS_DESC end,
    Slash = function(input)
        if strlower(strtrim(input or "")) == "diag" then ns.AurasDiag() return end
        if ns.OpenFrames then ns.OpenFrames("player") end
    end,
})

-- le cadre cible ou la barre de sort peut changer (deverrouillage...) : on se replace
ns.AurasPlaceTarget = function() if targetHeader and not InCombatLockdown() then placeTarget() end end
ns.Listen(function()
    if not targetHeader then return end
    if not InCombatLockdown() then placeTarget() end
    -- apercu ouvert / ferme, reglages changes : auras fictives a jour
    if db and (previewTarget or (ns.PreviewOn and ns.PreviewOn("units"))) then updateTarget() end
end)
