--[[--------------------------------------------------------------------------
    CorpUI - module Rappels
    Petite barre d icones : une par buff personnel absent ou bientot fini
    (armure du mage, Feu interieur, aspect du chasseur, poisons...).
      clic    : lancer le sort (boutons securises)
      molette : choisir le sort quand il y en a plusieurs (hors combat)
    Les poisons du voleur ne peuvent qu etre signales : les appliquer
    demande d utiliser un objet puis de cliquer l arme.

    Comme pour la barre de buffs : afficher/masquer/changer un sort ne se
    fait que hors combat ; en combat, seuls les minuteurs bougent.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local issecret = issecretvalue or function() return false end

-- spells : par ordre de preference ; also : autres buffs qui comptent aussi
-- (version de groupe) ; weapon : enchantement d arme a verifier
local DEFS = {
    MAGE    = { { key = "armor",     spells = { 6117, 7302, 168 } } },          -- Armure de mage, de glace, de givre
    PRIEST  = { { key = "innerfire", spells = { 588 } } },
    WARLOCK = { { key = "armor",     spells = { 706, 687 } } },                 -- Armure demoniaque, Peau de demon
    HUNTER  = { { key = "aspect",    spells = { 13165, 13163, 5118, 13159, 20043, 13161 } } },
    WARRIOR = { { key = "shout",     spells = { 6673 }, warn = 15, groupOnly = true } },
    SHAMAN  = { { key = "shield",    spells = { 324 } },
                { key = "weapon",    weapon = "main", spells = { 8232, 8024, 8033, 8017 } } },
    -- Marque du fauve (le Don du fauve d un autre druide compte aussi), Epines
    DRUID   = { { key = "mark",      spells = { 1126 }, also = { 21849 } },
                { key = "thorns",    spells = { 467 } } },
    ROGUE   = { { key = "poisonMH",  weapon = "main", poison = true },
                { key = "poisonOH",  weapon = "off",  poison = true } },
}
local WARN = 60
local POISON_ICON = "Interface\\Icons\\Ability_Poisons"
local HANDLE_H = 14
local GAP = 3
local db
local function btnSize() return (db and db.size) or 36 end
local bar, handle
local buttons = {}
-- signature de la disposition affichee ; nil = a refaire (jamais egal a la
-- signature d une liste vide, sinon la barre resterait affichee)
local shownKeys

local function defs()
    local _, c = UnitClass("player")
    return DEFS[c] or {}
end

local function known(id)
    return ns.KnownSpell and ns.KnownSpell(id) and true or false
end

local function knownSpells(def)
    local list = {}
    for _, id in ipairs(def.spells or {}) do
        if known(id) then table.insert(list, id) end
    end
    return list
end

-- Sort retenu pour ce rappel : le choix du joueur s il est encore connu
local function chosenSpell(def)
    local list = knownSpells(def)
    if #list == 0 then return nil end
    local choice = db.choice[ns.CharKey()] and db.choice[ns.CharKey()][def.key]
    for _, id in ipairs(list) do
        if id == choice then return id end
    end
    return list[1]
end

local function cycleSpell(def, step)
    local list = knownSpells(def)
    if #list < 2 then return end
    local cur = chosenSpell(def)
    local idx = 1
    for i, id in ipairs(list) do if id == cur then idx = i end end
    idx = (idx - 1 + step) % #list + 1
    db.choice[ns.CharKey()] = db.choice[ns.CharKey()] or {}
    db.choice[ns.CharKey()][def.key] = list[idx]
end

-- Buff present sur le joueur parmi ces sorts ? -> present, secondes restantes
-- (nil si illisible : en combat, on garde l etat precedent)
local function buffState(def)
    local wanted = {}
    for _, list in ipairs({ def.spells, def.also or {} }) do
        for _, id in ipairs(list) do
            local n = ns.SpellName(id)
            if n then wanted[n] = true end
        end
    end
    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then return nil end
    local found, left = false, nil
    local ok = pcall(function()
        for i = 1, 40 do
            local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not a then break end
            if issecret(a.name) then error("secret") end
            if wanted[a.name] then
                found = true
                local exp = a.expirationTime
                if exp and not issecret(exp) and exp > 0 then left = exp - GetTime() end
                return
            end
        end
    end)
    if not ok then return nil end
    return found, left
end

local function hasOffhandWeapon()
    local id = GetInventoryItemID and GetInventoryItemID("player", 17)
    if not id then return false end
    local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not fn then return true end
    local ok, _, _, _, equipLoc = pcall(fn, id)
    return not ok or equipLoc ~= "INVTYPE_SHIELD" and equipLoc ~= "INVTYPE_HOLDABLE"
end

local function seconds(ms)
    if type(ms) == "number" and not issecret(ms) and ms > 0 then return ms / 1000 end
    return nil
end

-- Enchantement temporaire d une arme (pierre a aiguiser, poison, arme
-- Croque-roc du chaman...) -> present, secondes restantes ; nil : illisible.
-- Ce client : C_Item.GetWeaponEnchantInfo(emplacement) renvoie une liste
-- { hasEnchant, timeLeft (ms)... }, comme pour le cadre des buffs de
-- Blizzard ; l ancienne fonction globale n existe qu avec les fonctions
-- depreciees (secours).
local function weaponEnchant(off)
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
                        return true, seconds(e.timeLeft)
                    end
                end
            end
            if secret then return nil end
            return false
        end
    end
    if GetWeaponEnchantInfo then
        local ok, hasMH, mhExp, _, _, hasOH, ohExp = pcall(GetWeaponEnchantInfo)
        if not ok or issecret(hasMH) or issecret(hasOH) then return nil end
        if off then return hasOH and true or false, seconds(ohExp) end
        return hasMH and true or false, seconds(mhExp)
    end
    return nil
end

local function weaponState(def)
    if def.weapon == "off" and not hasOffhandWeapon() then return true, nil, true end
    return weaponEnchant(def.weapon == "off")
end

-- Ce rappel est-il a afficher ? -> besoin, secondes restantes
local function needs(def)
    if def.groupOnly and not IsInGroup() then return false end
    if not def.poison and not chosenSpell(def) then return false end   -- sort pas encore appris
    local present, left
    if def.weapon then present, left = weaponState(def) else present, left = buffState(def) end
    if present == nil then return nil end
    if not present then return true end
    return left ~= nil and left < (def.warn or WARN), left
end

---------------------------------------------------------------------------
-- Barre
---------------------------------------------------------------------------

local function tooltip(self)
    local def = self.def
    if not def then return end
    local t = ns.Tooltip(self, "ANCHOR_BOTTOM")
    if def.poison then
        t:AddLine(def.weapon == "main" and L.REMIND_POISON_MH or L.REMIND_POISON_OH)
        t:AddLine(L.REMIND_POISON_TIP, 1, 1, 1)
    else
        local id = chosenSpell(def)
        t:AddLine(id and ns.SpellName(id) or "?")
        t:AddLine(L.TIP_CAST, 1, 1, 1)
        if #knownSpells(def) > 1 then t:AddLine(L.REMIND_WHEEL, 0.5, 0.8, 1) end
    end
    t:Show()
end

local function button(i)
    if buttons[i] then return buttons[i] end
    local C = ns.COLORS
    local b = CreateFrame("Button", nil, bar, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b.edge = b:CreateTexture(nil, "BACKGROUND")
    b.edge:SetAllPoints()
    b.edge:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
    b.inner = b:CreateTexture(nil, "BORDER")
    b.inner:SetPoint("TOPLEFT", 1, -1)
    b.inner:SetPoint("BOTTOMRIGHT", -1, 1)
    b.inner:SetColorTexture(0, 0, 0, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b.icon)
    ns.UI.Gradient(hl, "VERTICAL", C.violet[1], C.violet[2], C.violet[3], 0.1, C.violet[1], C.violet[2], C.violet[3], 0.45)
    b.time = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.time:SetPoint("BOTTOM", 0, 3)
    b:SetScript("OnEnter", tooltip)
    b:SetScript("OnLeave", ns.HideTooltip)
    b:EnableMouseWheel(true)
    b:SetScript("OnMouseWheel", function(self, delta)
        if InCombatLockdown() or not self.def or self.def.poison then return end
        cycleSpell(self.def, delta > 0 and -1 or 1)
        shownKeys = nil      -- forcer la mise a jour des attributs
    end)
    buttons[i] = b
    return b
end

local function hiddenByContext()
    if not db.enabled then return true end
    if db.hideResting and IsResting and IsResting() then return true end
    if UnitIsDeadOrGhost("player") then return true end
    if UnitOnTaxi and UnitOnTaxi("player") then return true end
    if IsMounted and IsMounted() then return true end
    return false
end

local function update()
    if not db or not bar then return end
    local list = {}
    if not hiddenByContext() then
        for _, def in ipairs(defs()) do
            local need, left = needs(def)
            if need then table.insert(list, { def = def, left = left }) end
        end
    end

    -- disposition : seulement hors combat
    if not InCombatLockdown() then
        local keys = {}
        for _, e in ipairs(list) do
            table.insert(keys, e.def.key .. ":" .. tostring(not e.def.poison and chosenSpell(e.def)))
        end
        local sig = table.concat(keys, ",")
        if sig ~= shownKeys then
            shownKeys = sig
            local size = btnSize()
            for i, e in ipairs(list) do
                local b = button(i)
                b:SetSize(size, size)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", (i - 1) * (size + GAP), -HANDLE_H - 1)
                b.def = e.def
                if e.def.poison then
                    b:SetAttribute("type", nil)
                    b.icon:SetTexture(POISON_ICON)
                else
                    local id = chosenSpell(e.def)
                    b:SetAttribute("type", "spell")
                    b:SetAttribute("spell", ns.SpellName(id))
                    b:SetAttribute("unit", "player")
                    b.icon:SetTexture(ns.SpellIcon(id))
                end
                b:Show()
            end
            for i = #list + 1, #buttons do
                buttons[i]:Hide()
                buttons[i].def = nil
            end
            bar:SetSize(math.max(1, #list) * (size + GAP) - GAP, size + HANDLE_H + 1)
            handle:SetWidth(bar:GetWidth())
            bar:SetShown(#list > 0)
        end
    end

    -- minuteurs : toujours
    for _, b in ipairs(buttons) do
        if b:IsShown() and b.def then
            local _, left = needs(b.def)
            b.time:SetText(left and ns.FormatTime(left) or "")
            b.icon:SetDesaturated(left == nil)
            if left == nil then
                b.edge:SetColorTexture(0.9, 0.22, 0.22, 1)
            else
                b.edge:SetColorTexture(1, 0.7, 0.15, 1)
            end
        end
    end
end

local function buildBar()
    db.pos = db.pos or { point = "TOP", x = 0, y = -120 }
    bar = CreateFrame("Frame", "CorpUIReminders", UIParent)
    bar:SetSize(btnSize(), btnSize() + HANDLE_H + 1)
    ns.ApplyPos(bar, db.pos)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar:Hide()
    handle = CreateFrame("Button", nil, bar)
    handle:SetHeight(HANDLE_H)
    handle:SetPoint("TOPLEFT")
    handle:SetWidth(btnSize())
    local C = ns.COLORS
    local bg = handle:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.92)
    local glow = handle:CreateTexture(nil, "BORDER")
    glow:SetAllPoints()
    ns.UI.Gradient(glow, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.45, C.violet[1], C.violet[2], C.violet[3], 0.05)
    local line = handle:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    ns.NoSnap(line)
    ns.UI.Gradient(line, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.8, C.gold[1], C.gold[2], C.gold[3], 0)
    handle.text = handle:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(handle.text, 9)
    handle.text:SetPoint("LEFT", 4, 0)
    handle.text:SetPoint("RIGHT", -2, 0)
    handle.text:SetJustifyH("LEFT")
    handle.text:SetWordWrap(false)
    handle.text:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    handle.text:SetText(L.MOD_REMIND)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function()
        if db.locked or InCombatLockdown() then return end
        bar:StartMoving()
    end)
    handle:SetScript("OnDragStop", function()
        bar:StopMovingOrSizing()
        ns.PinTop(bar, db.pos, true)
    end)
    handle:SetScript("OnEnter", function(self)
        local t = ns.Tooltip(self, "ANCHOR_BOTTOM")
        t:AddLine(L.MOD_REMIND)
        t:AddLine(db.locked and L.CHK_LOCK or L.HANDLE_DRAG, 1, 1, 1)
        t:Show()
    end)
    handle:SetScript("OnLeave", ns.HideTooltip)
    bar:SetScript("OnShow", function(self) ns.PinTop(self, db.pos) end)
end

---------------------------------------------------------------------------
-- Fenetre d options
---------------------------------------------------------------------------

local win

local function buildWindow()
    ns.root.remindWin = ns.root.remindWin or { point = "CENTER", x = 0, y = 60 }
    win = ns.UI.Window("CorpUIRemindersOptions", ns.TITLE .. " - " .. L.MOD_REMIND, ns.root.remindWin, 440, 120)
    local form = ns.UI.Form(win, -34)
    form:Check(L.REMIND_OPT_SHOW, function() return db.enabled end, function(v) db.enabled = v shownKeys = nil end)
    form:Check(L.REMIND_OPT_REST, function() return db.hideResting end, function(v) db.hideResting = v shownKeys = nil end)
    form:Check(L.CHK_LOCK, function() return db.locked end, function(v) db.locked = v end)
    form:Columns(2)
    form:Number(L.REMIND_SIZE, function() return btnSize() end, function(v) db.size = v shownKeys = nil end, 20, 64)
    form:EndColumns()
    win:HookScript("OnShow", function() form:Refresh() end)
end

local function toggle()
    if not win then buildWindow() end
    ns.ShowPanel(win)
end

---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, unit)
    if ns.ModuleOff("rappels", ev) then return end
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        root.reminders = root.reminders or {}
        db = root.reminders
        db.choice = db.choice or {}
        if db.enabled == nil then db.enabled = true end
        if db.hideResting == nil then db.hideResting = true end
        buildBar()
    end
end)
pcall(ev.RegisterEvent, ev, "PLAYER_LOGIN")

-- verification toutes les secondes : simple et sans risque d evenement manquant
local elapsed = 0
ev:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 1 then return end
    elapsed = 0
    local ok, err = pcall(update)
    if not ok then geterrorhandler()(err) end
end)

ns.RegisterModule({
    command = "rappels",
    panelName = "CorpUIRemindersOptions",
    icon = "Interface\\Icons\\Spell_Frost_FrostArmor02",
    title = function() return L.MOD_REMIND end,
    desc = function() return L.REMIND_DESC end,
    Slash = function() toggle() end,
    Open = toggle,
})
