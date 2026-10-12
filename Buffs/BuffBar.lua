--[[--------------------------------------------------------------------------
    CorpUI - module Buffs : barre de buffs (boutons securises)

    Boutons, de haut en bas :
      aura     (paladin) clic : lancer l aura assignee, molette : en changer
      fureur   (paladin) clic : Fureur vertueuse
      auto     clic gauche : prochain buff de groupe necessaire
               clic droit  : prochain buff individuel necessaire
      entrees  une par cible assignee qui a besoin d un buff :
               - classe (paladin) : supreme sur la classe
               - groupe (pretre, mage, druide) : priere/illumination/don
               - joueur : buff individuel (Epines, Amplification...)
               clic gauche : version de groupe, clic droit : version simple
               survol : liste des membres (popout), sauf pour un joueur
      membres  clic gauche : version simple, clic droit : version de groupe
               molette : choisir son buff individuel
      morts    (pretre, paladin) clic : resurrection, annoncee au groupe

    Une entree dont tout le monde a son buff (et assez de temps) est
    masquee ; Auto aussi quand plus personne n a besoin de rien. Ces
    changements ne se font que hors combat.

    Contraintes du code securise :
      - hors combat, les attributs sont recalcules en continu et juste
        avant chaque clic (PreClick) : cible a portee et qui en a besoin
      - en combat, on ne peut ni changer les attributs ni afficher/masquer
        les boutons : les derniers reglages restent, seuls textes, icones
        et couleurs se mettent a jour. Le popout s ouvre en combat grace a
        un snippet securise (SecureHandlerEnterLeaveTemplate).
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local BTN_W, BTN_H = 118, 30
local PB_W, PB_H   = 132, 22
local GAP          = 2
local HANDLE_H     = 14
local MAX_DEAD     = 10

local issecret = issecretvalue or function() return false end

local bar, handle
local auraBtn, rfBtn, autoBtn
local entryBtns = {}      -- id d entree -> bouton
local deadBtns = {}       -- boutons de resurrection
local entries = {}        -- entrees affichees, dans l ordre
local layoutPending = true
local lastSig

---------------------------------------------------------------------------
-- Aides
---------------------------------------------------------------------------

local function setAttr(b, k, v)
    if b:GetAttribute(k) ~= v then b:SetAttribute(k, v) end
end

local function myInfo()
    return ns.casters[ns.me]
end

local function isPaladin()
    return ns.PlayerClass() == "PALADIN"
end

-- Nom du sort simple, et de la version de groupe si on peut la lancer
-- (connue et composants en sac)
local function singleSpell(key)
    local p = myInfo()
    if not p or not p.skills[key] then return nil end
    return ns.BuffName(key, false)
end

local function groupSpell(key)
    local p = myInfo()
    local s = p and p.skills[key]
    if s and s.group and (s.reagents or 0) > 0 then return ns.BuffName(key, true) end
    return nil
end

local function bestSpell(key)
    local g = groupSpell(key)
    if g then return g, true end
    return singleSpell(key), false
end

local function playerHasBuff(name)
    if not name or not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then return nil end
    local found
    local ok = pcall(function()
        for i = 1, 40 do
            local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not aura then break end
            if issecret(aura.name) then error("secret") end
            if aura.name == name then found = true return end
        end
        found = false
    end)
    if ok then return found end
    return nil
end

local function alive(m)
    return not ns.IsDead(m.unit) and ns.IsConnected(m.unit)
end

local function warnFor(e)
    return e.kind == "i" and ns.WARN_SINGLE or ns.WARN_GROUP
end

-- Le membre a-t-il besoin de ce buff (absent ou bientot fini) ?
local function needs(m, key, warn)
    if not alive(m) then return false end
    local left = ns.Remaining(m, key)
    return not left or left < warn
end

local function entryNeeds(e)
    local warn = warnFor(e)
    for _, m in ipairs(e.members) do
        if needs(m, e.key, warn) then return true end
    end
    return false
end

local function entryStatus(e)
    local missing, dead, minLeft, total = 0, 0, nil, 0
    for _, m in ipairs(e.members) do
        total = total + 1
        if not alive(m) then
            dead = dead + 1
        else
            local left = ns.Remaining(m, e.key)
            if not left then
                missing = missing + 1
            elseif not minLeft or left < minLeft then
                minLeft = left
            end
        end
    end
    return missing, minLeft, total, dead
end

local function colorFor(missing, minLeft, warn, total)
    if total == 0 then return 0.25, 0.25, 0.25 end
    if missing > 0 then return 0.9, 0.22, 0.22 end
    if minLeft and minLeft < warn then return 1, 0.7, 0.15 end
    return 0.3, 0.8, 0.4
end

-- Meilleure cible : vivante, connectee, a portee, et qui en a le plus besoin
local function pickTarget(members, key, spell)
    local best, bestScore
    for _, m in ipairs(members) do
        if alive(m) and UnitExists(m.unit) then
            local range = ns.InRange(m.unit, spell)
            local left = ns.Remaining(m, key)
            local score = (range == true and 10000) or (range == nil and 5000) or 0
            score = score + (left and (1000 - math.min(left, 999)) or 2000)
            if not bestScore or score > bestScore then best, bestScore = m, score end
        end
    end
    return best, bestScore and bestScore >= 5000
end

local function isFeigning(unit)
    if not UnitIsFeignDeath then return false end
    local ok, v = pcall(UnitIsFeignDeath, unit)
    return ok and not issecret(v) and v or false
end

local function incomingRez(unit)
    if not UnitHasIncomingResurrection then return false end
    local ok, v = pcall(UnitHasIncomingResurrection, unit)
    return ok and not issecret(v) and v or false
end

local function rezSpellName()
    local prov = ns.MyProvider()
    return prov and prov.rez and ns.SpellName(prov.rez)
end

-- Joueurs morts a relever, soigneurs d abord
local function deadList()
    local list = {}
    local p = myInfo()
    if not ns.db.showDead or not (p and p.rez) then return list end
    for _, m in ipairs(ns.roster) do
        if not UnitIsUnit(m.unit, "player") and ns.IsConnected(m.unit)
            and ns.IsDead(m.unit) and not isFeigning(m.unit) then
            table.insert(list, m)
        end
    end
    table.sort(list, function(a, b)
        local pa, pb = ns.REZ_PRIORITY[a.class] or 9, ns.REZ_PRIORITY[b.class] or 9
        if pa ~= pb then return pa < pb end
        return a.name < b.name
    end)
    while #list > MAX_DEAD do table.remove(list) end
    return list
end

---------------------------------------------------------------------------
-- Entrees : ce que j ai a buffer
---------------------------------------------------------------------------

-- Toutes les entrees qui me sont assignees (avant masquage)
local function buildEntries()
    local list = {}
    local prov = ns.MyProvider()
    local p = myInfo()
    if not prov or not p then return list end

    if prov.mode == "class" then
        local a = ns.db.assign[ns.me] or {}
        for _, class in ipairs(ns.CLASSES) do
            local key = a[class]
            local all = ns.byClass[class]
            if key and all and #all > 0 then
                -- ceux qui ont une benediction individuelle sortent de la classe
                local members = {}
                for _, m in ipairs(all) do
                    local mine = ns.MyBuffsFor(m)[1]
                    if mine and mine.via == "class" then table.insert(members, m) end
                end
                table.insert(list, { id = "c:" .. class, kind = "c", key = key, class = class,
                                     members = members, popout = all })
            end
        end
    else
        local groups = ns.db.groups[ns.me] or {}
        for _, b in ipairs(prov.buffs) do
            local set = groups[b.key]
            for g = 1, ns.MAX_GROUPS do
                if set and set[g] and ns.byGroup[g] then
                    local members = {}
                    for _, m in ipairs(ns.byGroup[g]) do
                        if not (b.manaOnly and ns.NO_MANA[m.class]) then table.insert(members, m) end
                    end
                    if #members > 0 then
                        table.insert(list, { id = "g:" .. b.key .. ":" .. g, kind = "g", key = b.key,
                                             group = g, members = members, popout = members })
                    end
                end
            end
        end
    end

    -- buffs individuels
    local names = {}
    for name in pairs(ns.db.indiv[ns.me] or {}) do table.insert(names, name) end
    table.sort(names)
    for _, name in ipairs(names) do
        local key = ns.db.indiv[ns.me][name]
        local m = ns.MemberByName(name)
        if m and p.skills[key] then
            local covered = false
            for _, e in ipairs(ns.MyBuffsFor(m)) do
                if e.key == key and not e.indiv then covered = true end
            end
            if not covered then
                table.insert(list, { id = "i:" .. name, kind = "i", key = key, members = { m } })
            end
        end
    end
    return list
end

---------------------------------------------------------------------------
-- Choix de l auto-bouton
---------------------------------------------------------------------------

local function nextGroupCast()
    for _, e in ipairs(buildEntries()) do
        if e.kind ~= "i" and entryNeeds(e) then
            local spell = bestSpell(e.key)
            local target, reachable = pickTarget(e.members, e.key, spell)
            if spell and target and reachable then return spell, target.unit end
        end
    end
end

local function nextSingleCast()
    local candidates = {}
    for _, m in ipairs(ns.roster) do
        for _, mine in ipairs(ns.MyBuffsFor(m)) do
            local warn = mine.indiv and ns.WARN_SINGLE or ns.WARN_GROUP
            if needs(m, mine.key, warn) then
                table.insert(candidates, { m = m, key = mine.key, indiv = mine.indiv and true or false,
                                           left = ns.Remaining(m, mine.key) })
            end
        end
    end
    -- individuels d abord, puis les plus urgents
    table.sort(candidates, function(x, y)
        if x.indiv ~= y.indiv then return x.indiv end
        return (x.left or -1) < (y.left or -1)
    end)
    for _, c in ipairs(candidates) do
        local spell = singleSpell(c.key)
        if spell and ns.InRange(c.m.unit, spell) ~= false then return spell, c.m.unit end
    end
end

---------------------------------------------------------------------------
-- Creation des boutons
---------------------------------------------------------------------------

-- Habillage CorpUI : fond obsidienne et liseré du theme ; l etat (manque,
-- bientot fini, ok) se lit sur une bande a gauche et une teinte en degrade
local function decorate(b, w, h)
    local C = ns.COLORS
    b:SetSize(w, h)
    b.edge = b:CreateTexture(nil, "BACKGROUND", nil, -2)
    b.edge:SetPoint("TOPLEFT", -1, 1)
    ns.NoSnap(b.edge)
    b.edge:SetPoint("BOTTOMRIGHT", 1, -1)
    b.edge:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
    b.bg = b:CreateTexture(nil, "BACKGROUND", nil, -1)
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.92)
    b.tint = b:CreateTexture(nil, "BACKGROUND")
    b.tint:SetAllPoints()
    b.tint:SetColorTexture(1, 1, 1, 1)
    b.accent = b:CreateTexture(nil, "BORDER")
    b.accent:SetPoint("TOPLEFT")
    b.accent:SetPoint("BOTTOMLEFT")
    b.accent:SetWidth(2)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    ns.UI.Gradient(hl, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.25, C.violet[1], C.violet[2], C.violet[3], 0.05)
    b:RegisterForClicks("AnyUp", "AnyDown")
end

-- couleur d etat : vive sur la bande, en degrade discret sur le fond ;
-- une couleur terne (aucun etat) laisse le bouton neutre
local function paint(b, r, g, bl)
    local m = math.max(r, g, bl)
    if m < 0.3 then
        b.accent:SetColorTexture(0, 0, 0, 0)
        b.tint:SetColorTexture(0, 0, 0, 0)
        return
    end
    r, g, bl = r / m * 0.95, g / m * 0.95, bl / m * 0.95
    b.accent:SetColorTexture(r, g, bl, 1)
    ns.UI.Gradient(b.tint, "HORIZONTAL", r, g, bl, 0.28, r, g, bl, 0)
end

local function addIcon(b, size, x)
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetSize(size, size)
    t:SetPoint("LEFT", x, 0)
    t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return t
end

local function addText(b, template, point, x, y)
    local fs = b:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    fs:SetPoint(point, x or 0, y or 0)
    return fs
end

local function tipAnchor(self)
    local t = ns.Tooltip(self)
    t:SetOwner(self, ns.db.bar.vertical and "ANCHOR_LEFT" or "ANCHOR_BOTTOM")
    return t
end

local function createSimpleButton()
    local b = CreateFrame("Button", nil, bar, "SecureActionButtonTemplate")
    decorate(b, BTN_W, BTN_H)
    b.icon = addIcon(b, BTN_H - 6, 3)
    b.text = addText(b, "GameFontHighlightSmall", "LEFT", BTN_H + 2, 0)
    b.text:SetWidth(BTN_W - BTN_H - 6)
    b.text:SetJustifyH("LEFT")
    b:SetScript("OnLeave", ns.HideTooltip)
    return b
end

local function createAuraButton()
    auraBtn = createSimpleButton()
    auraBtn:SetAttribute("type", "spell")
    auraBtn:EnableMouseWheel(true)
    auraBtn:SetScript("OnMouseWheel", function(_, delta)
        if InCombatLockdown() then return end
        ns.SetAura(ns.me, ns.CycleAura(ns.me, ns.db.aura[ns.me], delta > 0 and -1 or 1))
    end)
    auraBtn:SetScript("OnEnter", function(self)
        local t = tipAnchor(self)
        local akey = ns.db.aura[ns.me]
        t:AddLine(akey and ns.AuraName(akey) or L.NO_AURA_ASSIGNED)
        t:AddLine(L.TIP_CAST_AURA, 1, 1, 1)
        t:AddLine(L.TIP_WHEEL_AURA, 1, 1, 1)
        t:Show()
    end)
end

local function createRFButton()
    rfBtn = createSimpleButton()
    rfBtn:SetAttribute("type", "spell")
    rfBtn.icon:SetTexture(ns.SpellIcon(ns.RIGHTEOUS_FURY))
    rfBtn:SetScript("OnEnter", function(self)
        local t = tipAnchor(self)
        t:AddLine(ns.SpellName(ns.RIGHTEOUS_FURY) or "Righteous Fury")
        t:AddLine(L.TIP_CAST, 1, 1, 1)
        t:Show()
    end)
end

local function createAutoButton()
    autoBtn = createSimpleButton()
    autoBtn:SetScript("PreClick", function(self, button, down)
        if InCombatLockdown() then return end
        local spell, unit
        if button == "RightButton" then spell, unit = nextSingleCast() else spell, unit = nextGroupCast() end
        if spell then
            self:SetAttribute("type", "spell")
            self:SetAttribute("spell", spell)
            self:SetAttribute("unit", unit)
        else
            self:SetAttribute("type", nil)
            if not down then ns.Say(L.NOBODY_NEEDS) end
        end
    end)
    autoBtn:SetScript("OnEnter", function(self)
        local t = tipAnchor(self)
        t:AddLine(L.AUTO_TITLE)
        t:AddLine(L.AUTO_LEFT, 1, 1, 1)
        t:AddLine(L.AUTO_RIGHT, 1, 1, 1)
        t:AddLine(L.AUTO_NOTE, 0.6, 0.6, 0.6)
        t:Show()
    end)
end

-- Snippets securises du popout (s executent aussi en combat)
local SHOW_POPOUT = [[
    local p = self:GetFrameRef("popout")
    if p then p:Show() end
]]
local HIDE_FROM_OWNER = [[
    local p = self:GetFrameRef("popout")
    if p and not p:IsUnderMouse(true) then p:Hide() end
]]
local HIDE_FROM_POPOUT = [[
    local o = self:GetFrameRef("owner")
    if not self:IsUnderMouse(true) and not (o and o:IsUnderMouse(true)) then self:Hide() end
]]
local HIDE_FROM_MEMBER = [[
    local p = self:GetFrameRef("popout")
    local o = self:GetFrameRef("owner")
    if p and not p:IsUnderMouse(true) and not (o and o:IsUnderMouse(true)) then p:Hide() end
]]

-- Buff que ce membre recoit de moi dans le contexte d une entree : sa
-- benediction individuelle chez un paladin, sinon le buff de l entree
local function memberKey(mb)
    local m, e = mb.member, mb.entry
    if not m or not e then return nil end
    if e.kind == "c" then
        local mine = ns.MyBuffsFor(m)[1]
        return mine and mine.key, mine and mine.indiv
    end
    return e.key, false
end

local function memberTooltip(self)
    local m = self.member
    if not m then return end
    local key, indiv = memberKey(self)
    local t = tipAnchor(self)
    t:AddLine(ns.ClassHex(m.class) .. m.name .. "|r")
    if key then
        t:AddLine(string.format(indiv and L.INDIV or L.CLASS_BLESSING, ns.BuffName(key) or key), 1, 1, 1)
        local left = ns.Remaining(m, key)
        t:AddLine(left and string.format(L.TIME_LEFT, left == math.huge and L.UNLIMITED or ns.FormatTime(left)) or L.ABSENT,
            left and 0.5 or 1, left and 1 or 0.3, left and 0.5 or 0.3)
        t:AddLine(" ")
        t:AddLine(string.format(L.M_LEFT_SPELL, singleSpell(key) or "-"), 0.5, 0.8, 1)
        local g = self.entry and groupSpell(self.entry.key)
        if g then t:AddLine(string.format(L.M_RIGHT_SPELL, g), 0.5, 0.8, 1) end
    end
    t:AddLine(L.M_WHEEL, 0.5, 0.8, 1)
    t:Show()
end

local function createMemberButton(eb, i)
    local pop = eb.popout
    local b = CreateFrame("Button", nil, pop, "SecureActionButtonTemplate, SecureHandlerEnterLeaveTemplate")
    decorate(b, PB_W, PB_H)
    b:SetPoint("TOPLEFT", pop, "TOPLEFT", 2, -2 - (i - 1) * PB_H)
    b.icon = addIcon(b, PB_H - 4, 2)
    b.name = addText(b, "GameFontHighlightSmall", "LEFT", PB_H + 1, 0)
    b.name:SetWidth(PB_W - PB_H - 40)
    b.name:SetJustifyH("LEFT")
    b.time = addText(b, "GameFontHighlightSmall", "RIGHT", -3, 0)
    SecureHandlerSetFrameRef(b, "popout", pop)
    SecureHandlerSetFrameRef(b, "owner", eb)
    b:SetAttribute("_onleave", HIDE_FROM_MEMBER)
    b:HookScript("OnEnter", memberTooltip)
    b:HookScript("OnLeave", ns.HideTooltip)
    b:EnableMouseWheel(true)
    b:SetScript("OnMouseWheel", function(self, delta)
        if InCombatLockdown() or not self.member then return end
        ns.CycleIndividual(self.member.name, delta > 0 and -1 or 1)
    end)
    eb.members[i] = b
    return b
end

local function createDeadButton(i)
    local b = CreateFrame("Button", nil, bar, "SecureActionButtonTemplate")
    decorate(b, BTN_W, BTN_H - 6)
    b.icon = addIcon(b, BTN_H - 10, 3)
    b.name = addText(b, "GameFontHighlightSmall", "LEFT", BTN_H - 4, 0)
    b.name:SetWidth(BTN_W - BTN_H - 36)
    b.name:SetJustifyH("LEFT")
    b.status = addText(b, "GameFontHighlightSmall", "RIGHT", -3, 0)
    b:SetAttribute("type", "spell")
    b:SetScript("OnEnter", function(self)
        local m = self.member
        if not m then return end
        local t = tipAnchor(self)
        t:AddLine(string.format(L.IS_DEAD, ns.ClassHex(m.class) .. m.name .. "|r"))
        local by = ns.RezzedBy(m.name)
        if by then t:AddLine(string.format(L.REZ_BY, by), 1, 0.82, 0) end
        t:AddLine(string.format(L.CLICK_SPELL, rezSpellName() or "?"), 0.5, 0.8, 1)
        t:Show()
    end)
    b:SetScript("OnLeave", ns.HideTooltip)
    deadBtns[i] = b
    return b
end

local function entryTooltip(self)
    local e = self.entry
    if not e then return end
    local t = tipAnchor(self)
    if e.kind == "c" then
        t:AddLine(ns.ClassHex(e.class) .. ns.ClassName(e.class) .. "|r")
    elseif e.kind == "g" then
        t:AddLine(string.format(L.GROUP_LONG, e.group))
    else
        local m = e.members[1]
        t:AddLine(ns.ClassHex(m.class) .. m.name .. "|r")
    end
    local missing, _, total, dead = entryStatus(e)
    t:AddLine(ns.BuffName(e.key, e.kind ~= "i") or e.key, 1, 1, 1)
    if e.kind ~= "i" then
        t:AddLine(string.format(L.CLASS_STATS, total, missing, dead), 0.8, 0.8, 0.8)
    end
    t:AddLine(" ")
    if e.kind == "i" then
        t:AddLine(string.format(L.TIP_LEFT_SPELL, singleSpell(e.key) or "-"), 0.5, 0.8, 1)
    else
        t:AddLine(string.format(L.TIP_LEFT_SPELL, (bestSpell(e.key)) or "-"), 0.5, 0.8, 1)
        t:AddLine(string.format(L.TIP_RIGHT_MEMBER, singleSpell(e.key) or "-"), 0.5, 0.8, 1)
    end
    local p = myInfo()
    local s = p and p.skills[e.key]
    if s and ns.BUFF_BY_KEY[e.key].group then
        t:AddLine(string.format(L.REAGENTS, s.reagents or 0), 0.8, 0.8, 0.8)
    end
    t:Show()
end

-- Une entree : classe (icone de classe), groupe (G3) ou joueur (nom)
local function createEntryButton(id, kind)
    local template = kind == "i" and "SecureActionButtonTemplate"
        or "SecureActionButtonTemplate, SecureHandlerEnterLeaveTemplate"
    local b = CreateFrame("Button", nil, bar, template)
    decorate(b, BTN_W, BTN_H)
    b.kind = kind
    b.classIcon = addIcon(b, BTN_H - 8, 3)
    b.groupText = addText(b, "GameFontNormal", "LEFT", 4, 0)
    b.buffIcon = addIcon(b, BTN_H - 8, BTN_H - 2)
    b.label = addText(b, "GameFontHighlightSmall", "LEFT", 2 * BTN_H - 8, 0)
    b.label:SetWidth(BTN_W - 2 * BTN_H - 30)
    b.label:SetJustifyH("LEFT")
    b.time = addText(b, "GameFontHighlightSmall", "TOPRIGHT", -4, -3)
    b.count = addText(b, "GameFontHighlightSmall", "BOTTOMRIGHT", -4, 3)
    b.members = {}

    if kind ~= "i" then
        local pop = CreateFrame("Frame", nil, bar, "SecureHandlerEnterLeaveTemplate")
        pop:SetFrameStrata("DIALOG")
        pop:EnableMouse(true)
        pop:SetClampedToScreen(true)
        pop.bg = pop:CreateTexture(nil, "BACKGROUND")
        pop.bg:SetPoint("TOPLEFT", -1, 1)
        ns.NoSnap(pop.bg)
        pop.bg:SetPoint("BOTTOMRIGHT", 1, -1)
        pop.bg:SetColorTexture(ns.COLORS.border[1], ns.COLORS.border[2], ns.COLORS.border[3], 0.95)
        pop:Hide()
        b.popout = pop

        SecureHandlerSetFrameRef(b, "popout", pop)
        SecureHandlerSetFrameRef(pop, "owner", b)
        b:SetAttribute("_onenter", SHOW_POPOUT)
        b:SetAttribute("_onleave", HIDE_FROM_OWNER)
        pop:SetAttribute("_onleave", HIDE_FROM_POPOUT)

        -- filet hors combat : refermer si la souris est partie ailleurs
        local away = 0
        pop:SetScript("OnUpdate", function(self, dt)
            if InCombatLockdown() then return end
            if self:IsMouseOver() or b:IsMouseOver() then
                away = 0
            else
                away = away + dt
                if away > 0.3 then self:Hide() end
            end
        end)
        pop:SetScript("OnShow", function() away = 0 end)
        b:HookScript("OnEnter", entryTooltip)
        b:HookScript("OnLeave", ns.HideTooltip)
    else
        b:SetScript("OnEnter", entryTooltip)
        b:SetScript("OnLeave", ns.HideTooltip)
        b:EnableMouseWheel(true)
        b:SetScript("OnMouseWheel", function(self, delta)
            if InCombatLockdown() or not self.entry then return end
            ns.CycleIndividual(self.entry.members[1].name, delta > 0 and -1 or 1)
        end)
    end

    b:SetScript("PreClick", function(self)
        if InCombatLockdown() then return end
        ns.UpdateEntrySecure(self)
    end)
    entryBtns[id] = b
    return b
end

---------------------------------------------------------------------------
-- Attributs securises (hors combat uniquement)
---------------------------------------------------------------------------

function ns.UpdateEntrySecure(b)
    local e = b.entry
    if not e then
        setAttr(b, "type1", nil)
        setAttr(b, "type2", nil)
        return
    end
    local single = singleSpell(e.key)
    local left = e.kind == "i" and single or bestSpell(e.key)
    local t1 = pickTarget(e.members, e.key, left)
    local t2 = pickTarget(e.members, e.key, single)
    setAttr(b, "type1", left and t1 and "spell" or nil)
    setAttr(b, "spell1", left)
    setAttr(b, "unit1", t1 and t1.unit)
    setAttr(b, "type2", single and t2 and "spell" or nil)
    setAttr(b, "spell2", single)
    setAttr(b, "unit2", t2 and t2.unit)
end

local function updateMemberSecure(mb)
    local m, e = mb.member, mb.entry
    local key = memberKey(mb)
    local single = key and singleSpell(key)
    local group = e and groupSpell(e.key)
    setAttr(mb, "type1", single and "spell" or nil)
    setAttr(mb, "spell1", single)
    setAttr(mb, "unit1", m and m.unit)
    setAttr(mb, "type2", group and "spell" or nil)
    setAttr(mb, "spell2", group)
    setAttr(mb, "unit2", m and m.unit)
end

local function updateSecure()
    if InCombatLockdown() or not bar then return end
    if isPaladin() then
        local akey = ns.db.aura[ns.me]
        setAttr(auraBtn, "spell", akey and ns.AuraName(akey))
        setAttr(rfBtn, "spell", ns.SpellName(ns.RIGHTEOUS_FURY))
    end
    local rezName = rezSpellName()
    for _, b in ipairs(deadBtns) do
        if b:IsShown() and b.member then
            setAttr(b, "spell", rezName)
            setAttr(b, "unit", b.member.unit)
        end
    end
    for _, e in ipairs(entries) do
        local b = entryBtns[e.id]
        if b and b:IsShown() then
            ns.UpdateEntrySecure(b)
            for _, mb in ipairs(b.members) do
                if mb:IsShown() then updateMemberSecure(mb) end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Disposition (hors combat uniquement)
---------------------------------------------------------------------------

local function wantsBar()
    return ns.db.bar.shown and ns.MyProvider() ~= nil and myInfo() ~= nil
end

-- force : refaire la disposition meme si rien n a change en apparence
local function layout(force)
    if InCombatLockdown() then layoutPending = true return end
    layoutPending = false
    if not wantsBar() then
        bar:Hide()
        lastSig = nil
        return
    end

    local vertical = ns.db.bar.vertical
    local p = myInfo()
    local pal = isPaladin()

    -- ce qu il faut afficher
    local showAura = pal and ns.db.showAura and next(p.auras) ~= nil or false
    local showRF = pal and ns.db.showRF and p.rf and true or false
    local wanted = {}
    local anyNeed = false
    for _, e in ipairs(buildEntries()) do
        local need = entryNeeds(e)
        anyNeed = anyNeed or need
        if not ns.db.hideBuffed or need then table.insert(wanted, e) end
    end
    -- pas de buff a donner (chaman) : pas de bouton Auto
    local showAuto = #ns.MyProvider().buffs > 0 and (not ns.db.hideBuffed or anyNeed)
    local dead = deadList()

    -- rien n a change : on garde la disposition, on rafraichit les donnees
    local parts = { tostring(vertical), tostring(showAura), tostring(showRF), tostring(showAuto), tostring(ns.db.bar.scale) }
    for _, e in ipairs(wanted) do
        local ids = {}
        for _, m in ipairs(e.popout or e.members) do table.insert(ids, m.unit) end
        table.insert(parts, e.id .. "=" .. table.concat(ids, ","))
    end
    for _, m in ipairs(dead) do table.insert(parts, "d" .. m.unit .. m.name) end
    local sig = table.concat(parts, "|")
    if not force and sig == lastSig then
        -- memes boutons : rattacher les entrees fraiches (membres a jour)
        entries = wanted
        for _, e in ipairs(entries) do
            local b = entryBtns[e.id]
            if b then
                b.entry = e
                for i, m in ipairs(e.popout or {}) do
                    if b.members[i] then b.members[i].member, b.members[i].entry = m, e end
                end
            end
        end
        updateSecure()
        return
    end
    lastSig = sig
    entries = wanted

    local shown = {}
    auraBtn:SetShown(showAura)
    if showAura then table.insert(shown, auraBtn) end
    rfBtn:SetShown(showRF)
    if showRF then table.insert(shown, rfBtn) end
    autoBtn:SetShown(showAuto)
    if showAuto then table.insert(shown, autoBtn) end

    local used = {}
    for _, e in ipairs(entries) do
        local b = entryBtns[e.id] or createEntryButton(e.id, e.kind)
        used[e.id] = true
        b.entry = e
        b:Show()
        table.insert(shown, b)
        if b.popout then
            local list = e.popout
            for i, m in ipairs(list) do
                local mb = b.members[i] or createMemberButton(b, i)
                mb.member, mb.entry = m, e
                mb:Show()
            end
            for i = #list + 1, #b.members do b.members[i]:Hide() end
            b.popout:SetSize(PB_W + 4, #list * PB_H + 4)
            b.popout:ClearAllPoints()
            if vertical then
                b.popout:SetPoint("TOPLEFT", b, "TOPRIGHT", 0, 0)
            else
                b.popout:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, 0)
            end
        end
    end
    for id, b in pairs(entryBtns) do
        if not used[id] then
            b:Hide()
            b.entry = nil
            if b.popout then b.popout:Hide() end
        end
    end

    for i, m in ipairs(dead) do
        local b = deadBtns[i] or createDeadButton(i)
        b.member = m
        b:Show()
        table.insert(shown, b)
    end
    for i = #dead + 1, #deadBtns do
        deadBtns[i]:Hide()
        deadBtns[i].member = nil
    end

    -- rien a afficher : pas de poignee seule qui flotte a l ecran
    if #shown == 0 then
        bar:Hide()
        return
    end

    handle:ClearAllPoints()
    handle:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    local prev
    for i, b in ipairs(shown) do
        b:ClearAllPoints()
        if i == 1 then
            b:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, -HANDLE_H)
        elseif vertical then
            b:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -GAP)
        else
            b:SetPoint("TOPLEFT", prev, "TOPRIGHT", GAP, 0)
        end
        prev = b
    end
    -- figer le coin haut-gauche avant de changer taille et echelle
    bar:Show()
    ns.PinTop(bar, ns.db.bar)
    local newScale = ns.db.bar.scale or 1
    local oldScale = bar:GetScale()
    if math.abs(oldScale - newScale) > 0.001 then
        -- les decalages sont exprimes a l echelle du cadre : les convertir
        local s = ns.db.bar
        s.x, s.y = s.x * oldScale / newScale, s.y * oldScale / newScale
        bar:SetScale(newScale)
        ns.ApplyPos(bar, s)
    end

    local n = #shown
    if vertical then
        local h = HANDLE_H
        for _, b in ipairs(shown) do h = h + b:GetHeight() + GAP end
        bar:SetSize(BTN_W, h)
    else
        bar:SetSize(math.max(n, 1) * BTN_W + math.max(n - 1, 0) * GAP, HANDLE_H + BTN_H)
    end
    handle:SetSize(bar:GetWidth(), HANDLE_H)
    updateSecure()
end

---------------------------------------------------------------------------
-- Rendu (textes, icones, couleurs : autorise en combat)
---------------------------------------------------------------------------

local function renderMember(mb)
    local m = mb.member
    if not m then return end
    local key, indiv = memberKey(mb)
    mb.icon:SetTexture(key and ns.BuffIcon(key, not indiv) or nil)
    local name = m.name
    if ns.db.indiv[ns.me] and ns.db.indiv[ns.me][m.name] then name = name .. " |cffffd100*|r" end
    mb.name:SetText(ns.ClassHex(m.class) .. name .. "|r")
    local r, g, bl
    if not alive(m) then
        mb.time:SetText("|cff888888" .. L.DEAD .. "|r")
        r, g, bl = 0.2, 0.2, 0.2
    elseif not key then
        mb.time:SetText("")
        r, g, bl = 0.15, 0.15, 0.15
    else
        local left = ns.Remaining(m, key)
        if not left then
            mb.time:SetText("|cffff5050--|r")
            r, g, bl = 0.6, 0.08, 0.08
        else
            mb.time:SetText(left == math.huge and "" or ns.FormatTime(left))
            local warn = indiv and ns.WARN_SINGLE or ns.WARN_GROUP
            if left < warn then r, g, bl = 0.75, 0.5, 0.05 else r, g, bl = 0.1, 0.45, 0.12 end
        end
        if ns.InRange(m.unit, singleSpell(key)) == false then
            mb.name:SetText("|cff888888" .. name .. "|r")
        end
    end
    paint(mb, r, g, bl)
end

local function renderEntry(b, e)
    local missing, minLeft, total, dead = entryStatus(e)
    local isGroupCast = e.kind ~= "i" and select(2, bestSpell(e.key))
    b.buffIcon:SetTexture(ns.BuffIcon(e.key, isGroupCast))
    b.classIcon:SetShown(e.kind == "c")
    b.groupText:SetShown(e.kind == "g")
    b.label:SetShown(e.kind == "i")
    if e.kind == "c" then
        ns.SetClassIcon(b.classIcon, e.class)
    elseif e.kind == "g" then
        b.groupText:SetText(string.format(L.GROUP_SHORT, e.group))
    else
        local m = e.members[1]
        b.label:SetText(ns.ClassHex(m.class) .. m.name .. "|r")
    end
    b.time:SetText(minLeft and minLeft ~= math.huge and ns.FormatTime(minLeft) or "")
    if e.kind == "i" then
        b.count:SetText(missing > 0 and ("|cffff6060" .. L.ABSENT .. "|r") or "")
    elseif missing > 0 then
        b.count:SetText("|cffff6060" .. string.format(L.MISSING_N, missing) .. "|r")
    elseif dead > 0 then
        b.count:SetText("|cff888888" .. string.format(L.DEAD_N, dead) .. "|r")
    else
        b.count:SetText(total > 0 and ("|cff80ff80" .. total .. "/" .. total .. "|r") or "")
    end
    paint(b, colorFor(missing, minLeft, warnFor(e), total - dead))
    for _, mb in ipairs(b.members) do
        if mb:IsShown() then renderMember(mb) end
    end
    return missing
end

local function render()
    if not bar or not bar:IsShown() then return end
    local p = myInfo()
    if not p then return end

    if isPaladin() then
        local akey = ns.db.aura[ns.me]
        local auraName = akey and ns.AuraName(akey)
        auraBtn.icon:SetTexture(akey and ns.AuraIcon(akey) or "Interface\\Icons\\INV_Misc_QuestionMark")
        local auraOn = auraName and playerHasBuff(auraName)
        auraBtn.text:SetText(auraName or ("|cff888888" .. L.NO_AURA .. "|r"))
        paint(auraBtn, auraOn and 0.1 or (auraName and 0.6 or 0.15), auraOn and 0.45 or 0.1, auraOn and 0.12 or 0.1)

        local rfName = ns.SpellName(ns.RIGHTEOUS_FURY)
        local rfOn = playerHasBuff(rfName)
        rfBtn.text:SetText(rfName or "Righteous Fury")
        paint(rfBtn, rfOn and 0.1 or 0.15, rfOn and 0.45 or 0.15, rfOn and 0.12 or 0.15)
    end

    local totalMissing = 0
    for _, e in ipairs(entries) do
        local b = entryBtns[e.id]
        if b and b:IsShown() then totalMissing = totalMissing + renderEntry(b, e) end
    end

    local rezName = rezSpellName()
    for _, b in ipairs(deadBtns) do
        local m = b.member
        if b:IsShown() and m then
            b.icon:SetTexture(ns.SpellIcon(ns.MyProvider().rez))
            b.name:SetText(ns.ClassHex(m.class) .. m.name .. "|r")
            local by = ns.RezzedBy(m.name)
            local r, g, bl = 0.45, 0.05, 0.05
            if not ns.IsDead(m.unit) then
                b.status:SetText("|cff80ff80" .. L.RAISED .. "|r")
                r, g, bl = 0.1, 0.4, 0.12
            elseif incomingRez(m.unit) or by then
                b.status:SetText("|cffffd100" .. (by and string.format(L.REZ_SHORT, by) or L.REZ_PENDING) .. "|r")
                r, g, bl = 0.5, 0.4, 0.05
            elseif UnitIsGhost and UnitIsGhost(m.unit) then
                b.status:SetText("|cff999999" .. L.GHOST .. "|r")
            elseif ns.InRange(m.unit, rezName) == false then
                b.status:SetText("|cff999999" .. L.FAR .. "|r")
                r, g, bl = 0.25, 0.08, 0.08
            else
                b.status:SetText("|cffff8080" .. L.DEAD .. "|r")
            end
            paint(b, r, g, bl)
        end
    end

    -- composants du premier buff de groupe connu
    local reag
    for _, b in ipairs(ns.MyProvider().buffs) do
        local s = p.skills[b.key]
        if b.group and s then reag = s.reagents break end
    end
    local firstGroup
    for _, b in ipairs(ns.MyProvider().buffs) do
        if b.group then firstGroup = b break end
    end
    autoBtn.icon:SetTexture(firstGroup and ns.SpellIcon(firstGroup.group) or ns.SpellIcon(21562))
    autoBtn.text:SetText(string.format("%s  %s%s", L.AUTO_TEXT,
        totalMissing > 0 and ("|cffff6060" .. string.format(L.MISSING_N, totalMissing) .. "|r  ") or "",
        reag and ("|cffffd100x" .. reag .. "|r") or ""))
    paint(autoBtn, totalMissing > 0 and 0.6 or 0.1, totalMissing > 0 and 0.08 or 0.4, totalMissing > 0 and 0.08 or 0.12)
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

local function createBar()
    bar = CreateFrame("Frame", "CorpUIBuffBar", UIParent)
    bar:SetSize(BTN_W, 100)
    bar:SetScale(ns.db.bar.scale or 1)
    ns.ApplyPos(bar, ns.db.bar)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar:Hide()

    handle = CreateFrame("Button", nil, bar)
    handle:SetHeight(HANDLE_H)
    local C = ns.COLORS
    handle.bg = handle:CreateTexture(nil, "BACKGROUND")
    handle.bg:SetAllPoints()
    handle.bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.92)
    handle.glow = handle:CreateTexture(nil, "BORDER")
    handle.glow:SetAllPoints()
    ns.UI.Gradient(handle.glow, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.45, C.violet[1], C.violet[2], C.violet[3], 0.05)
    handle.line = handle:CreateTexture(nil, "ARTWORK")
    handle.line:SetPoint("BOTTOMLEFT")
    handle.line:SetPoint("BOTTOMRIGHT")
    handle.line:SetHeight(1)
    ns.NoSnap(handle.line)
    ns.UI.Gradient(handle.line, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.8, C.gold[1], C.gold[2], C.gold[3], 0)
    handle.text = handle:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(handle.text, 10)
    handle.text:SetPoint("LEFT", 5, 0)
    handle.text:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    handle.text:SetText(L.MOD_BUFFS or "Buffs")
    handle:RegisterForDrag("LeftButton")
    handle:RegisterForClicks("RightButtonUp")
    handle:SetScript("OnDragStart", function()
        if ns.db.bar.locked or InCombatLockdown() then return end
        bar:StartMoving()
    end)
    handle:SetScript("OnDragStop", function()
        bar:StopMovingOrSizing()
        ns.PinTop(bar, ns.db.bar, true)
    end)
    handle:SetScript("OnClick", function() ns.ToggleWindow() end)
    handle:SetScript("OnEnter", function(self)
        local t = tipAnchor(self)
        t:AddLine(ns.TITLE)
        t:AddLine(ns.db.bar.locked and L.HANDLE_LOCKED or L.HANDLE_DRAG, 1, 1, 1)
        t:AddLine(L.HANDLE_RIGHT, 1, 1, 1)
        t:Show()
    end)
    handle:SetScript("OnLeave", ns.HideTooltip)

    createAuraButton()
    createRFButton()
    createAutoButton()
end

function ns.ResetBar()
    if not bar or InCombatLockdown() then return end
    ns.ApplyPos(bar, ns.db.bar)
    if bar:IsShown() then ns.PinTop(bar, ns.db.bar) end
end

table.insert(ns.inits, function()
    if not ns.ModuleOff("buffs") then createBar() end
end)

ns.Listen(function()
    if not bar then return end
    layout(true)
    render()
end, "buffs")

function ns.Tick()
    if not bar then return end
    -- chaque tick hors combat : une entree qui vient d etre buffee
    -- disparait, un mort apparait (layout ne replace que si ca change)
    if not InCombatLockdown() then layout(layoutPending) end
    render()
end
