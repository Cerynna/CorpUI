--[[--------------------------------------------------------------------------
    CorpUI - module Dez (desenchantement)

    Seulement sur un personnage qui connait Desenchanter (sort 13262) :
    une icone montre le prochain objet des sacs a desenchanter (armes et
    armures vertes, bleues, violettes ; ni chemise ni tabard).
      - clic gauche : desenchante cet objet. Bouton securise du jeu
        (SecureActionButtonTemplate : type "spell", sort 13262, puis la
        case du sac visee par target-bag / target-slot) : un clic = un
        desenchantement, comme un bouton de barre d action ;
      - clic droit : l objet est ignore (liste dans /corp dez, a oublier) ;
      - refus du jeu juste apres le clic (competence trop basse, objet qui
        ne se desenchante pas) : l objet est saute jusqu a la deconnexion.
    Attributs, affichage et position changes hors combat seulement (cadre
    securise) ; en combat l icone reste telle quelle, a demi transparente.
    Infobulle : celle de l objet, la valeur de desenchantement estimee
    (module Encheres) et les deux clics.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L
local C = ns.COLORS

local issecret = issecretvalue or function() return false end

local DISENCHANT = 13262
local ERR_WINDOW = 1.5        -- refus du jeu attribue au clic pendant 1,5 s

local db                      -- CorpUIDB.dez
local btn
local current                 -- { bag, slot, id, link, quality }
local remaining = 0
local skipped = {}            -- "id" -> vrai : refuse par le jeu (session)
local lastClick               -- { id, t }
local dirty = true

local function num(v)
    if not issecret(v) and type(v) == "number" then return v end
end

local function call(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, a = pcall(fn, ...)
    if ok then return a end
end

-- le personnage sait-il desenchanter ?
local function isEnchanter()
    for _, fn in ipairs({ IsPlayerSpell, IsSpellKnown }) do
        local v = call(fn, DISENCHANT)
        if v == true then return true end
    end
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        if call(C_SpellBook.IsSpellKnown, DISENCHANT) == true then return true end
    end
    return false
end
ns.DezIsEnchanter = isEnchanter

---------------------------------------------------------------------------
-- Choix de l objet
---------------------------------------------------------------------------

-- objet desenchantable : on reprend la table du module Encheres (qualite,
-- classe, emplacement) ; sans elle, armes / armures vertes a violettes
local function disenchantable(link, info)
    if ns.AH and ns.AH.DEParts then return ns.AH.DEParts(link) ~= nil end
    local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local ok, name, _, quality, _, _, _, _, _, loc, _, _, classID = pcall(fn, link)
    if not ok or not name then return false end
    quality, classID = num(quality), num(classID)
    return (classID == 2 or classID == 4) and quality and quality >= 2 and quality <= 4
        and loc ~= "INVTYPE_BODY" and loc ~= "INVTYPE_TABARD"
end

local function pick()
    local first, n = nil, 0
    if not (C_Container and C_Container.GetContainerItemInfo) then return nil, 0 end
    for _, bag in ipairs(ns.PlayerBags()) do
        for slot = 1, ns.BagSlots(bag) do
            local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
            if ok and type(info) == "table" then
                local id, link = num(info.itemID), info.hyperlink
                if id and type(link) == "string" and not issecret(link) and info.isLocked ~= true
                   and not db.ignore[id] and not skipped[id]
                   and (db.bound or info.isBound ~= true) and disenchantable(link, info) then
                    n = n + 1
                    if not first then first = { bag = bag, slot = slot, id = id, link = link, quality = num(info.quality) or 2,
                                                icon = info.iconFileID } end
                end
            end
        end
    end
    return first, n
end

---------------------------------------------------------------------------
-- Icone (bouton securise)
---------------------------------------------------------------------------

local function qualityColor(q)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c and num(c.r) then return c.r, c.g, c.b end
    return 0.12, 1, 0
end

local function showTip(self)
    if not current then return end
    local t = ns.Tooltip(self, "ANCHOR_TOP")
    if not pcall(t.SetBagItem, t, current.bag, current.slot) then t:AddLine(current.link) end
    if ns.AH and ns.AH.DEValue then
        local v = ns.AH.DEValue(current.link)
        if v and v > 0 and ns.AHMoney then t:AddLine(string.format(L.DEZ_VALUE, ns.AHMoney(v)), 1, 0.82, 0.25) end
    end
    t:AddLine(L.DEZ_TIP_LEFT, 0.42, 0.88, 0.46)
    t:AddLine(L.DEZ_TIP_RIGHT, 1, 0.5, 0.3)
    if remaining > 1 then t:AddLine(string.format(L.DEZ_LEFT, remaining), 0.7, 0.7, 0.7) end
    t:Show()
end

local anchor

local function build()
    db.pos = db.pos or { point = "CENTER", x = 0, y = -160 }
    -- position portee par un cadre ordinaire (deplace avec /corp movers,
    -- hors combat) ; le bouton securise s y accroche
    anchor = CreateFrame("Frame", "CorpUIDezAnchor", UIParent)
    anchor:SetSize(db.size, db.size)
    ns.ApplyPos(anchor, db.pos)
    anchor.mover = ns.UI.Mover(anchor, db.pos, L.DEZ_MOVER)
    btn = CreateFrame("Button", "CorpUIDez", UIParent, "SecureActionButtonTemplate")
    btn:SetSize(db.size, db.size)
    btn:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn:SetAttribute("type1", "spell")
    btn:SetAttribute("spell1", DISENCHANT)
    ns.UI.Skin(btn, 0.6, true)
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("TOPLEFT", 2, -2)
    btn.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(btn.icon)
    hl:SetColorTexture(1, 1, 1, 0.18)
    btn.count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    btn.count:SetPoint("BOTTOMRIGHT", -2, 2)
    -- petite marque de desenchantement (baguette) dans le coin
    btn.badge = btn:CreateTexture(nil, "OVERLAY")
    btn.badge:SetSize(14, 14)
    btn.badge:SetPoint("TOPLEFT", -4, 4)
    btn.badge:SetTexture("Interface\\Icons\\INV_Enchant_Disenchant")
    btn.badge:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn:SetScript("OnEnter", showTip)
    btn:SetScript("OnLeave", function() ns.HideTooltip() end)
    -- clic gauche : action securisee ; on note l objet pour attribuer un refus
    btn:SetScript("PreClick", function(_, button, down)
        if button == "LeftButton" and current then lastClick = { id = current.id, t = GetTime() } end
    end)
    -- clic droit (au relachement) : ignorer l objet
    btn:SetScript("PostClick", function(_, button, down)
        if button ~= "RightButton" or down or not current then return end
        db.ignore[current.id] = true
        ns.Say(string.format(L.DEZ_IGNORED, current.link))
        ns.HideTooltip()
        dirty = true
    end)
    btn:Hide()
end

-- objet affiche, attributs, visibilite : hors combat seulement
local function refresh()
    if not db or InCombatLockdown() then return end
    dirty = false
    local want = db.enabled and isEnchanter()
    local it, n
    if want then it, n = pick() end
    current, remaining = it, n or 0
    if not btn then
        if not want then return end
        build()
    end
    anchor:SetSize(db.size, db.size)
    if want and it then
        btn:SetAttribute("target-bag1", it.bag)
        btn:SetAttribute("target-slot1", it.slot)
        btn.icon:SetTexture(it.icon or (ns.ItemIcon and ns.ItemIcon(it.id)))
        local r, g, b = qualityColor(it.quality)
        if btn.cuiBorder then btn.cuiBorder:SetColorTexture(r, g, b, 1) end
        btn.count:SetText((db.count and remaining > 1) and remaining or "")
        btn:SetSize(db.size, db.size)
        btn:SetAlpha(1)
        btn:Show()
    else
        btn:SetAttribute("target-bag1", nil)
        btn:SetAttribute("target-slot1", nil)
        btn:Hide()
    end
end
ns.DezRefresh = function() dirty = true end

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

-- refus du jeu juste apres un clic : objet saute pour la session
local REFUSALS = { "SPELL_FAILED_LOW_CASTLEVEL", "SPELL_FAILED_CANT_BE_DISENCHANTED", "SPELL_FAILED_CANT_BE_DISENCHANTED_SKILL",
                   "ERR_CANT_BE_DISENCHANTED", "SPELL_FAILED_BAD_TARGETS" }
local function isRefusal(msg)
    if type(msg) ~= "string" or issecret(msg) then return false end
    for _, key in ipairs(REFUSALS) do
        local s = _G[key]
        if type(s) == "string" and not issecret(s) and s ~= "" and msg == s then return true end
    end
    return false
end

local ev = CreateFrame("Frame")
local acc = 0
ev:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.25 then return end
    acc = 0
    if dirty and db then refresh() end
    if btn and btn:IsShown() then btn:SetAlpha(InCombatLockdown() and 0.4 or 1) end
end)
ev:SetScript("OnEvent", function(_, event, a, b)
    if ns.ModuleOff("dez", ev) then return end
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        if type(root.dez) ~= "table" then root.dez = {} end
        db = root.dez
        if db.enabled == nil then db.enabled = true end
        if db.bound == nil then db.bound = true end
        if db.count == nil then db.count = true end
        if type(db.size) ~= "number" then db.size = 40 end
        if type(db.ignore) ~= "table" then db.ignore = {} end
        dirty = true
    elseif event == "UI_ERROR_MESSAGE" then
        if lastClick and GetTime() - lastClick.t <= ERR_WINDOW and isRefusal(b) then
            skipped[lastClick.id] = true
            if current and current.id == lastClick.id then ns.Say(string.format(L.DEZ_SKIPPED, current.link, b)) end
            lastClick = nil
            dirty = true
        end
    else
        -- sacs, sorts, combat termine : objet suivant
        dirty = true
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB",
                     "SKILL_LINES_CHANGED", "PLAYER_REGEN_ENABLED", "UI_ERROR_MESSAGE", "GET_ITEM_INFO_RECEIVED" }) do
    pcall(ev.RegisterEvent, ev, e)
end

---------------------------------------------------------------------------
-- Reglages (/corp dez)
---------------------------------------------------------------------------

local panel

local function buildPanel()
    panel = ns.UI.Window("CorpUIDezOptions", ns.TITLE .. " - " .. L.MOD_DEZ, nil, 440, 260)
    local form = ns.UI.Form(panel, -34, function() dirty = true end)
    local status = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    status:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, form.y)
    status:SetWidth(424)
    status:SetJustifyH("LEFT")
    form.y = form.y - 20
    form:Check(L.DEZ_OPT_ENABLE, function() return db.enabled end, function(v) db.enabled = v end)
    form:Columns(2)
    form:Check(L.DEZ_OPT_BOUND, function() return db.bound end, function(v) db.bound = v end)
    form:Check(L.DEZ_OPT_COUNT, function() return db.count end, function(v) db.count = v end)
    form:EndColumns()
    form:Number(L.DEZ_OPT_SIZE, function() return db.size end, function(v) db.size = v end, 24, 80, 2)
    local forget = ns.UI.Button(panel, "", 220, function(self)
        wipe(db.ignore)
        dirty = true
        form:Refresh()
    end)
    forget:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, form.y - 4)
    form.y = form.y - 34
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, form.y)
    hint:SetWidth(424)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.DEZ_HINT)
    panel:SetHeight(-(form.y - 40) + 20)
    table.insert(form.refreshers, function()
        local n = 0
        for _ in pairs(db.ignore) do n = n + 1 end
        forget:SetText(string.format(L.DEZ_FORGET, n))
        forget:SetEnabled(n > 0)
        status:SetText(isEnchanter() and "" or L.DEZ_NOT_ENCH)
    end)
    panel:HookScript("OnShow", function() form:Refresh() end)
end

local function toggle()
    if not db then return end
    if not panel then buildPanel() end
    ns.ShowPanel(panel)
end

ns.RegisterModule({
    command = "dez",
    alias = "disenchant",
    panelName = "CorpUIDezOptions",
    icon = "Interface\\Icons\\INV_Enchant_Disenchant",
    title = function() return L.MOD_DEZ end,
    desc = function() return L.DEZ_DESC end,
    Slash = function() toggle() end,
    Open = toggle,
})

-- banc d essai
ns._dez = { refresh = refresh, pick = pick, current = function() return current end, skipped = skipped,
            button = function() return btn end }
