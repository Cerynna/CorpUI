--[[--------------------------------------------------------------------------
    CorpUI - module Menus (postures, micro-menu, sacs)
    Remplace le bas d ecran de Blizzard :
      - barre de postures a nous : formes de druide, postures de guerrier,
        camouflage, auras de paladin (l API des formes couvre tout ca).
        Boutons securises type "spell" (ID du sort de la forme) ; leur
        nombre change hors combat seulement. Raccourcis SHAPESHIFTBUTTONn
        rediriges vers nos boutons. Visibilite selon conditions (reglee
        dans le panneau des barres) : pilote d etat, comme les barres.
      - micro-menu et barre des sacs : nos propres boutons, icones dessinees
        pour CorpUI. Ceux du micro-menu cliquent le bouton de Blizzard
        correspondant par l action securisee "click" (pas d appel de
        fenetres de Blizzard depuis le code de l addon : sur ce client, une
        execution marquee par un addon casse sur les valeurs secretes).
    Les cadres de Blizzard qu on remplace vont au parent cache. La barre
    principale de Blizzard (MainMenuBar) n est cachee que si nos barres
    d action sont activees.
    Pas de panneau a soi : les reglages sont une section du panneau des
    barres d action (ns.MenusOptions), ou sont aussi les cases d affichage
    et l apparence des trois barres (ns.ExtraButtonBars).
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local issecret = issecretvalue or function() return false end

local STANCE_SIZE, GAP = 30, 4
-- reglages de la barre de formes : les memes que les barres d action
-- micro-menu et sacs : memes reglages que les barres d action
local MICRO_DEFAULTS = {
    buttons = 16, perRow = 16, size = 26, spacing = 3,
    backdrop = false, padding = 4, bgAlpha = 75, alpha = 1, mouseover = false,
    vis = "always", visCustom = "",
}
local BAG_DEFAULTS = {
    buttons = 6, perRow = 6, size = 30, spacing = 3,
    backdrop = false, padding = 4, bgAlpha = 75, alpha = 1, mouseover = false,
    vis = "always", visCustom = "",
}
local STANCE_DEFAULTS = {
    buttons = 10, perRow = 10, size = STANCE_SIZE, spacing = GAP,
    backdrop = false, padding = 4, bgAlpha = 75, alpha = 1, mouseover = false, hotkey = true,
    vis = "always", visCustom = "",
}
-- gestionnaire de recharges de Blizzard (rangees d icones au-dessus des barres)
local BLIZZ_CDM = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
local BLIZZ_BASE = { "MicroMenuContainer", "MicroMenu", "BagsBar", "MicroButtonAndBagsBar" }

local db
local stanceBar, microBar, bagBar
local stanceButtons = {}
local owner = CreateFrame("Frame")
local pending = false

---------------------------------------------------------------------------
-- Barre de postures
---------------------------------------------------------------------------

local function formInfo(i)
    local ok, icon, active, castable, spellID = pcall(GetShapeshiftFormInfo, i)
    if not ok then return nil end
    return icon, active, castable, spellID
end

local function updateStances()
    for i, b in ipairs(stanceButtons) do
        if b:IsShown() then
            local icon, active, castable = formInfo(i)
            b.icon:SetTexture(icon)
            b.active:SetShown(active and not issecret(active) and active or false)
            b.icon:SetVertexColor(((castable == false) and 0.4) or 1, ((castable == false) and 0.4) or 1, ((castable == false) and 0.4) or 1)
            local okC, start, duration = pcall(GetShapeshiftFormCooldown, i)
            if okC and start then pcall(b.cd.SetCooldown, b.cd, start, duration) end
            b.hotkey:SetText(ns.ShortKey and ns.ShortKey(GetBindingKey("SHAPESHIFTBUTTON" .. i)) or "")
        end
    end
end

local function makeStanceButton(i)
    local b = CreateFrame("Button", "CorpUIStanceButton" .. i, stanceBar, "SecureActionButtonTemplate")
    b:SetSize(STANCE_SIZE, STANCE_SIZE)     -- taille et place : layoutStances
    b:RegisterForClicks("AnyUp", "AnyDown")
    b.bindLabel = L.MENUS_STANCE .. " - " .. i
    if ns.RegisterBindable then ns.RegisterBindable(b, "SHAPESHIFTBUTTON" .. i) end
    b:SetAttribute("type", "spell")
    ns.UI.Skin(b, 0.6)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints()
    b.active = b:CreateTexture(nil, "OVERLAY")
    b.active:SetAllPoints()
    b.active:SetColorTexture(1, 0.85, 0.2, 0.3)
    b.active:Hide()
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.2)
    b.hotkey = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    b.hotkey:SetPoint("TOPRIGHT", -1, -2)
    b:SetScript("OnEnter", function(self)
        if ns.QuickBindHover and ns.QuickBindHover(self) then return end
        local t = ns.Tooltip(self, "ANCHOR_TOP")
        if not pcall(t.SetShapeshift, t, i) then t:Hide() return end
        t:Show()
    end)
    b:SetScript("OnLeave", ns.HideTooltip)
    stanceButtons[i] = b
    return b
end

-- Affichage de la barre (hors combat) : module et case actives, et au moins
-- une forme (pas une condition de macro : decide ici). Puis la condition
-- choisie dans le panneau des barres (pilote d etat "visibility", qui suit
-- le combat). Poignees de deplacement affichees : barre visible pour la placer.
local stanceCount = 0
local function applyStanceVisibility()
    if InCombatLockdown() then pending = true return end
    local on = db.enabled and db.stance and stanceCount > 0
    local cond = on and not ns.moversShown and ns.BarVisibility and ns.BarVisibility(db.stanceStyle)
    if cond then
        RegisterStateDriver(stanceBar, "visibility", cond)
    else
        UnregisterStateDriver(stanceBar, "visibility")
        stanceBar:SetShown(on and true or false)
    end
end

-- nombre de formes et sorts : hors combat (boutons securises)
local function layoutStances()
    if InCombatLockdown() then pending = true return end
    local n = 0
    local okN, num = pcall(GetNumShapeshiftForms)
    num = (okN and num and not issecret(num)) and num or 0
    for i = 1, num do
        local _, _, _, spellID = formInfo(i)
        local b = stanceButtons[i] or makeStanceButton(i)
        b:SetAttribute("spell", spellID)
        b:Show()
        n = i
    end
    for i = num + 1, #stanceButtons do stanceButtons[i]:Hide() end
    -- disposition commune aux barres de boutons (taille, lignes, fond...)
    local c = db.stanceStyle
    local shown = math.min(n, c.buttons)
    ns.LayoutButtonBar(stanceBar, stanceButtons, shown, c, db.stancePos)
    local font = math.max(8, math.floor(c.size * 0.3 + 0.5))
    for i, b in ipairs(stanceButtons) do
        if i > shown then b:Hide() end
        b.hotkey:SetShown(c.hotkey)
        local f, _, flags = b.hotkey:GetFont()
        if f then b.hotkey:SetFont(f, font, flags) end
    end
    stanceCount = n
    applyStanceVisibility()
    updateStances()
end

---------------------------------------------------------------------------
-- Micro-menu et sacs : nos propres boutons (icones dessinees pour CorpUI)
--   micro-menu : boutons securises "click" qui cliquent le bouton de
--   Blizzard correspondant (reste range, cache) : son code s execute comme
--   d habitude, sans marquer d execution depuis l addon.
--   sacs : clic = sacs CorpUI ; glisser-deposer = changer de sac.
---------------------------------------------------------------------------

local MICRO_SIZE, BAG_SIZE = 26, 30
local MICRO = {
    { "CharacterMicroButton", "character" }, { "ProfessionMicroButton", "professions" },
    { "PlayerSpellsMicroButton", "spellbook" }, { "SpellbookMicroButton", "spellbook" },
    { "TalentMicroButton", "talents" }, { "AchievementMicroButton", "achievements" },
    { "QuestLogMicroButton", "questlog" }, { "GuildMicroButton", "guild" },
    { "LFDMicroButton", "groupfinder" }, { "CollectionsMicroButton", "collections" },
    { "EJMicroButton", "adventure" }, { "HousingMicroButton", "housing" },
    { "LegacyMicroButton", "legacy" }, { "StoreMicroButton", "shop" },
    { "HelpMicroButton", "help" }, { "MainMenuMicroButton", "gamemenu" },
}
local microButtons = {}
local bagButtons = {}

local function squareButton(name, parent, size, template)
    local b = CreateFrame("Button", name, parent, template)
    b:SetSize(size, size)
    ns.UI.Skin(b, 0.95)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b.icon)
    hl:SetColorTexture(1, 1, 1, 0.15)
    return b
end

local function setBorder(b, c)
    if b.cuiBorder then b.cuiBorder:SetColorTexture(c[1], c[2], c[3], 1) end
end

local function buildMicro()
    for i, m in ipairs(MICRO) do
        local blizz = _G[m[1]]
        if type(blizz) == "table" and blizz.Click then
            local b = squareButton("CorpUIMicro" .. i, microBar, MICRO_SIZE, "SecureActionButtonTemplate")
            b.icon:SetTexture(ns.MEDIA .. "menu_" .. m[2])
            b:RegisterForClicks("AnyUp", "AnyDown")
            b:SetAttribute("type", "click")
            b:SetAttribute("clickbutton", blizz)
            b.blizz = blizz
            if m[1] == "MainMenuMicroButton" then
                -- menu du jeu : le bouton de Blizzard n agit que si la souris
                -- est dessus, et l ouvrir depuis l addon marquerait ses
                -- boutons (Deconnexion, Quitter : bloques). Son vrai bouton,
                -- invisible, est pose sur le notre (adoptGameMenu) : le clic
                -- arrive chez Blizzard, comme d habitude.
                b:SetAttribute("type", nil)
                b.gameMenu = true
            end
            -- notification de Blizzard (nouveau talent...) : point d or
            b.dot = b:CreateTexture(nil, "OVERLAY")
            b.dot:SetSize(6, 6)
            b.dot:SetPoint("TOPRIGHT", -2, -2)
            b.dot:SetColorTexture(ns.COLORS.gold[1], ns.COLORS.gold[2], ns.COLORS.gold[3], 1)
            b.dot:Hide()
            b:SetScript("OnEnter", function(self)
                local t = ns.Tooltip(self, "ANCHOR_TOP")
                local text = self.blizz.tooltipText
                if type(text) ~= "string" or text == "" then text = self.blizz.newbieText end
                t:AddLine(type(text) == "string" and text or m[1])
                t:Show()
            end)
            b:SetScript("OnLeave", ns.HideTooltip)
            table.insert(microButtons, b)
        end
    end
end

-- emplacements des sacs : 0 = sac a dos, 1 a 4, puis le sac de composants
local function invSlot(bag)
    if bag == 0 then return nil end
    if C_Container and C_Container.ContainerIDToInventoryID then
        local ok, id = pcall(C_Container.ContainerIDToInventoryID, bag)
        if ok then return id end
    end
end

local function bagFree(bag)
    local fn = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
    local ok, n = pcall(fn, bag)
    return ok and n or 0
end

local function freeSlots()
    local free = 0
    for _, bag in ipairs(ns.PlayerBags()) do free = free + bagFree(bag) end
    return free
end

local REAGENT_BAG = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or 5

local function buildBags()
    local toggle = _G.CorpUIBagsToggle
    for _, bag in ipairs(ns.PlayerBags()) do
        local b = squareButton("CorpUIBagSlot" .. bag, bagBar, BAG_SIZE, "SecureActionButtonTemplate")
        b.bag, b.inv = bag, invSlot(bag)
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:RegisterForDrag("LeftButton")
        -- clic : ouvre / ferme les sacs CorpUI (sinon le sac de Blizzard)
        local target = toggle or (bag == 0 and _G.MainMenuBarBackpackButton) or nil
        if target then
            b:SetAttribute("type", "click")
            b:SetAttribute("clickbutton", target)
        end
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.icon:SetTexCoord(0, 1, 0, 1)
        if bag == 0 then b.icon:SetTexture(ns.MEDIA .. "menu_backpack") end
        -- places libres : total sur le sac a dos, celles du sac sur les autres
        b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        b.count:SetPoint("BOTTOMRIGHT", -2, 2)
        -- changer de sac : prendre / poser (hors combat)
        b:SetScript("OnDragStart", function(self)
            if InCombatLockdown() or not self.inv then return end
            pcall(PickupBagFromSlot, self.inv)
        end)
        b:SetScript("OnReceiveDrag", function(self)
            if InCombatLockdown() then return end
            if self.bag == 0 then pcall(PutItemInBackpack) else pcall(PutItemInBag, self.inv) end
        end)
        b:SetScript("OnEnter", function(self)
            local t = ns.Tooltip(self, "ANCHOR_TOP")
            if self.inv and pcall(t.SetInventoryItem, t, "player", self.inv) and t:NumLines() > 0 then
                t:Show()
                return
            end
            t:AddLine(self.bag == 0 and BACKPACK_TOOLTIP or (BAGSLOT or L.MENUS_BAGS))
            if self.bag == 0 then t:AddLine(string.format(L.MENUS_FREE, freeSlots()), 1, 1, 1) end
            t:Show()
        end)
        b:SetScript("OnLeave", ns.HideTooltip)
        table.insert(bagButtons, b)
    end
end

-- icones CorpUI : besace pour un sac, bourse a la feuille pour le sac de
-- composants, contour en pointilles pour un emplacement vide
local function updateBags()
    for _, b in ipairs(bagButtons) do
        if b.bag == 0 then
            b.count:SetText(freeSlots())
        else
            local equipped = b.inv and GetInventoryItemTexture("player", b.inv)
            if equipped then
                b.icon:SetTexture(ns.MEDIA .. (b.bag == REAGENT_BAG and "menu_reagentbag" or "menu_bag"))
                b.icon:SetAlpha(1)
                b.count:SetText(bagFree(b.bag))
            else
                b.icon:SetTexture(ns.MEDIA .. "menu_bagempty")
                b.icon:SetAlpha(0.6)
                b.count:SetText("")
            end
        end
    end
end

-- disposition : seulement les boutons utiles (hors combat : boutons securises)
-- affichage d une barre a nous : case, puis condition (pilote d etat)
local function applyBarVisibility(bar, on, c)
    if InCombatLockdown() then pending = true return end
    local cond = on and not ns.moversShown and ns.BarVisibility and ns.BarVisibility(c)
    if cond then
        RegisterStateDriver(bar, "visibility", cond)
    else
        UnregisterStateDriver(bar, "visibility")
        bar:SetShown(on and true or false)
    end
end

-- bouton du menu du jeu de Blizzard, transparent, sur notre engrenage
local function adoptGameMenu(b)
    local blizz = b.blizz
    if InCombatLockdown() or not blizz then return end
    if blizz:GetParent() ~= b then blizz:SetParent(b) end
    blizz:ClearAllPoints()
    blizz:SetAllPoints(b)
    blizz:SetAlpha(0)
    blizz:SetFrameLevel(b:GetFrameLevel() + 5)
    blizz:Show()
end

local function layoutMicro()
    local c = db.microStyle
    local list = {}
    for _, b in ipairs(microButtons) do
        -- seulement les boutons que Blizzard range dans son micro-menu et
        -- montre (certains existent sur ce client sans y etre : maison...)
        local inMenu = MicroMenu and (b.blizz:GetParent() == MicroMenu or b.gameMenu)
        local show = db.enabled and db.micro and inMenu and b.blizz:IsShown() and #list < c.buttons
        b:SetShown(show and true or false)
        if show then table.insert(list, b) end
        if b.gameMenu and show then adoptGameMenu(b) end
    end
    if #list > 0 then ns.LayoutButtonBar(microBar, list, #list, c, db.microPos) end
end

local function layoutBags()
    local c = db.bagStyle
    -- sac a dos en dernier (a droite d une rangee) ; option compacte : lui
    -- seul (la fenetre des sacs montre deja tous les sacs)
    local list = {}
    for i = 1, #bagButtons do
        local b = bagButtons[i]
        local show = db.enabled and db.bags and not (db.bagsCompact and b.bag ~= 0)
        b:SetShown(show and true or false)
        if show then table.insert(list, 1, b) end
    end
    while #list > c.buttons do table.remove(list, 1):Hide() end
    if #list > 0 then ns.LayoutButtonBar(bagBar, list, #list, c, db.bagPos) end
    updateBags()
end

-- etat des boutons du micro-menu : desactive, fenetre ouverte, notification
local function refreshMicro()
    local C = ns.COLORS
    for _, b in ipairs(microButtons) do
        if b:IsVisible() then
            local blizz = b.blizz
            local enabled = blizz:IsEnabled()
            b.icon:SetDesaturated(not enabled)
            b.icon:SetAlpha(enabled and 1 or 0.45)
            local open = blizz.GetButtonState and blizz:GetButtonState() == "PUSHED"
            if b:IsMouseOver() or open then setBorder(b, C.gold) else setBorder(b, C.border) end
            local note = blizz.NotificationOverlay
            b.dot:SetShown(note and note.IsShown and note:IsShown() or false)
        end
    end
end

---------------------------------------------------------------------------
-- Construction et application
---------------------------------------------------------------------------

local function build()
    db.stancePos = db.stancePos or { point = "BOTTOM", x = -150, y = 284 }
    db.microPos = db.microPos or { point = "BOTTOMRIGHT", x = -8, y = 6 }
    db.bagPos = db.bagPos or { point = "BOTTOMRIGHT", x = -8, y = 50 }

    stanceBar = CreateFrame("Frame", "CorpUIStanceBar", UIParent)
    stanceBar:SetSize(1, 1)
    ns.ApplyPos(stanceBar, db.stancePos)
    -- fond facultatif, comme les barres d action
    stanceBar.backBorder, stanceBar.back = ns.UI.Skin(stanceBar, 0.75, false)
    stanceBar.back:Hide()
    stanceBar.backBorder:Hide()
    ns.UI.Mover(stanceBar, db.stancePos, L.MENUS_STANCE)
    table.insert(ns.ButtonBars, { frame = stanceBar, conf = function() return db.stanceStyle end })

    microBar = CreateFrame("Frame", "CorpUIMicroBar", UIParent)
    microBar:SetSize(200, 30)
    ns.ApplyPos(microBar, db.microPos)
    microBar.backBorder, microBar.back = ns.UI.Skin(microBar, 0.75, false)
    microBar.back:Hide()
    microBar.backBorder:Hide()
    ns.UI.Mover(microBar, db.microPos, L.MENUS_MICRO)
    table.insert(ns.ButtonBars, { frame = microBar, conf = function() return db.microStyle end })

    bagBar = CreateFrame("Frame", "CorpUIBagBar", UIParent)
    bagBar:SetSize(200, 30)
    ns.ApplyPos(bagBar, db.bagPos)
    bagBar.backBorder, bagBar.back = ns.UI.Skin(bagBar, 0.75, false)
    bagBar.back:Hide()
    bagBar.backBorder:Hide()
    ns.UI.Mover(bagBar, db.bagPos, L.MENUS_BAGS)
    table.insert(ns.ButtonBars, { frame = bagBar, conf = function() return db.bagStyle end })

    buildMicro()
    buildBags()
end

local function applyBindings()
    ClearOverrideBindings(owner)
    if not (db.enabled and db.stance) then return end
    for i = 1, 10 do
        for _, key in ipairs({ GetBindingKey("SHAPESHIFTBUTTON" .. i) }) do
            SetOverrideBindingClick(owner, false, key, "CorpUIStanceButton" .. i, "LeftButton")
        end
    end
end

local function apply()
    if InCombatLockdown() then pending = true return end
    pending = false
    local on = db.enabled
    -- barres a nous
    layoutMicro()
    layoutBags()
    applyBarVisibility(microBar, on and db.micro, db.microStyle)
    applyBarVisibility(bagBar, on and db.bags, db.bagStyle)
    layoutStances()
    applyBindings()
    -- interface de Blizzard remplacee
    local hide = on and db.hideBlizzard
    ns.HideBlizzard(BLIZZ_CDM, on and db.hideCooldowns)
    ns.HideBlizzard(BLIZZ_BASE, hide)
    ns.HideBlizzard({ "StanceBar" }, hide and db.stance)
    local barsOn = ns.root.bars and ns.root.bars.enabled
    ns.HideBlizzard({ "MainMenuBar", "MainActionBar" }, hide and barsOn)
end

---------------------------------------------------------------------------
-- Reglages : une section du panneau des barres d action, juste apres sa
-- grille "Barres affichees" (qui porte les cases postures, micro-menu et
-- sacs). Ici : le remplacement lui-meme et l interface de Blizzard.
-- parent : la fenetre du panneau des barres ; y : hauteur de depart.
-- Renvoie la hauteur suivante.
---------------------------------------------------------------------------

function ns.MenusOptions(parent, y)
    -- en combat : rien ne change (la case est relue et revient a sa valeur)
    local form = ns.UI.Form(parent, y, function()
        if db and not InCombatLockdown() then apply() end
    end)
    local function check(key, text)
        form:Check(text, function() return db and db[key] end, function(v)
            if InCombatLockdown() then ns.Say(L.COMBAT_BLOCKED) return end
            if db then db[key] = v end
        end)
    end
    form:Header(L.MENUS_SECTION)
    check("enabled", L.MENUS_OPT_ENABLE)
    check("bagsCompact", L.MENUS_BAGS_COMPACT)
    -- interface de Blizzard
    check("hideBlizzard", L.MENUS_OPT_BLIZZ)
    check("hideCooldowns", L.MENUS_OPT_CDM)
    form:Refresh()
    parent:HookScript("OnShow", function() form:Refresh() end)
    return form.y
end

---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if ns.ModuleOff("barres", ev) then return end
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        root.menus = root.menus or {}
        db = root.menus
        for k, v in pairs({ enabled = true, stance = true, micro = true, bags = true, hideBlizzard = true, hideCooldowns = true }) do
            if db[k] == nil then db[k] = v end
        end
        for key, defaults in pairs({ stanceStyle = STANCE_DEFAULTS, microStyle = MICRO_DEFAULTS, bagStyle = BAG_DEFAULTS }) do
            db[key] = db[key] or {}
            for k, v in pairs(defaults) do
                if db[key][k] == nil then db[key][k] = v end
            end
        end
        build()
        apply()
    elseif not db then
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending then apply() end
    elseif event == "UPDATE_SHAPESHIFT_FORMS" or event == "SPELLS_CHANGED" then
        layoutStances()
    elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYER_EQUIPMENT_CHANGED" then
        updateBags()
    elseif event == "UPDATE_BINDINGS" then
        if not InCombatLockdown() then applyBindings() end
        updateStances()
    else
        updateStances()
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_ENABLED", "UPDATE_SHAPESHIFT_FORMS", "UPDATE_SHAPESHIFT_FORM",
                     "UPDATE_SHAPESHIFT_USABLE", "UPDATE_SHAPESHIFT_COOLDOWN", "SPELLS_CHANGED",
                     "UPDATE_BINDINGS", "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)
end

-- etat du micro-menu cinq fois par seconde ; disposition toutes les 2 s
-- (Blizzard montre / cache certains boutons), hors combat
local since, layoutTick = 0, 0
ev:SetScript("OnUpdate", function(_, dt)
    since = since + dt
    if since < 0.2 or not db or not db.enabled then return end
    since = 0
    refreshMicro()
    layoutTick = layoutTick + 1
    if layoutTick >= 10 and not InCombatLockdown() then
        layoutTick = 0
        layoutMicro()
    end
end)

-- poignees de deplacement affichees / masquees : visibilite de la barre de
-- formes a revoir (son pilote d etat est suspendu pendant le placement)
local lastMovers = false
ns.Listen(function()
    if not db or not stanceBar or (ns.moversShown and true or false) == lastMovers then return end
    lastMovers = ns.moversShown and true or false
    applyStanceVisibility()
    applyBarVisibility(microBar, db.enabled and db.micro, db.microStyle)
    applyBarVisibility(bagBar, db.enabled and db.bags, db.bagStyle)
end)

-- Formes, micro-menu et sacs se reglent dans le panneau des barres d action
ns.ExtraButtonBars = {
    { label = function() return L.MENUS_STANCE end, conf = function() return db and db.stanceStyle end,
      shown = function() return db and db.stance end, setShown = function(v) db.stance = v end },
    { label = function() return L.MENUS_MICRO end, conf = function() return db and db.microStyle end,
      shown = function() return db and db.micro end, setShown = function(v) db.micro = v end },
    { label = function() return L.MENUS_BAGS end, conf = function() return db and db.bagStyle end,
      shown = function() return db and db.bags end, setShown = function(v) db.bags = v end },
}
function ns.MenusApply() if db then apply() end end
ns.StanceBar = ns.ExtraButtonBars[1]
ns.StanceBar.apply = ns.MenusApply

-- Pas de panneau (donc pas d onglet) : /corp menus ouvre celui des barres
-- d action, qui contient la section de ce module (ns.MenusOptions)
ns.RegisterModule({
    command = "menus",
    title = function() return L.MOD_MENUS end,
    desc = function() return L.MENUS_DESC end,
    Slash = function(input)
        if input and input:find("diag") then
            -- cadres visibles collés au bas de l ecran : ce qu il reste de Blizzard
            local out = {}
            local function scan(parent, depth)
                local okK, kids = pcall(function() return { parent:GetChildren() } end)
                for _, c in ipairs(okK and kids or {}) do pcall(function()
                    local okB, bottom = pcall(c.GetBottom, c)
                    local okW, w = pcall(c.GetWidth, c)
                    local okV, vis = pcall(c.IsVisible, c)
                    if okV and vis == true and okB and bottom and not issecret(bottom) and bottom < 120
                        and okW and w and not issecret(w) and w > 150 then
                        local okN, n = pcall(c.GetDebugName, c)
                        table.insert(out, (okN and tostring(n) or "?") .. " w" .. math.floor(w) .. " b" .. math.floor(bottom))
                        if depth < 2 then scan(c, depth + 1) end
                    end
                end) end
            end
            local okS, err = pcall(scan, UIParent, 0)
            -- et tous les cadres du jeu, quel que soit leur parent
            pcall(function()
                local f = EnumerateFrames()
                while f do
                    pcall(function()
                        local b, w = f:GetBottom(), f:GetWidth()
                        if f:IsVisible() and b and w and not issecret(b) and not issecret(w) and b < 60 and w > 200 and w < 600 then
                            table.insert(out, "* " .. tostring(f:GetDebugName()) .. " w" .. math.floor(w) .. " b" .. math.floor(b))
                        end
                    end)
                    f = EnumerateFrames(f)
                end
            end)
            if not okS then table.insert(out, "ERR " .. tostring(err)) end
            db.diag = out
            ns.Chat("CorpUI diag : " .. #out)
            for _, line in ipairs(out) do ns.Chat(line) end
            return
        end
        if ns.OpenBars then ns.OpenBars() end
    end,
})
