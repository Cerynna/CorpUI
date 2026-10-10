--[[--------------------------------------------------------------------------
    CorpUI - module Butin
    1. Fenetre de butin a nous (remplace LootFrame) : liste des objets,
       clic = ramasser (LootSlot), Maj+clic = lien, infobulle, "tout
       ramasser", au curseur ou a une position fixe (poignee commune).
    2. Jets de groupe a nous (remplacent GroupLootFrame1..4 et leur
       conteneur GroupLootContainer) : icone, nom, temps restant, boutons
       Besoin / Cupidite (ou Transmo) / Desenchanter (si permis) / Passer
       -> RollOnLoot(rollID, 1 / 2 / 4 / 3 / 0).

    Ce que fait Blizzard sur ce client (branche forever, lu le 05/10) :
      - LootFrame (Blizzard_UIPanels_Game/Mainline/LootFrame.lua) ecoute
        LOOT_OPENED / LOOT_CLOSED, puis LOOT_SLOT_CLEARED / CHANGED une fois
        affiche ; son OnHide appelle CloseLoot(). Echap le ferme
        (RegisterGameMenuEscHandler). On le laisse vivre dans le parent
        cache : il garde la gestion d Echap et des confirmations, et ferme
        la session de butin, ce qui nous renvoie LOOT_CLOSED.
      - START_LOOT_ROLL est route par Blizzard_Game vers
        GroupLootContainer_AddRoll (4 cadres GroupLootFrameN, ancres au
        conteneur mais enfants d UIParent : il faut les ranger un par un).
        Le cadre de Blizzard ne disparait qu a CANCEL_LOOT_ROLL (le clic
        appelle seulement RollOnLoot) : on fait pareil.
      - GetLootRollItemInfo(rollID) -> texture, name, count, quality,
        bindOnPickUp, canNeed, canGreed, canDisenchant, reasonNeed,
        reasonGreed, reasonDisenchant, deSkillRequired, canTransmog.
        Pas de bouton Desenchanter chez Blizzard ici : le notre n apparait
        que si canDisenchant est vrai.
      - Les confirmations (objet lie quand ramasse, CONFIRM_LOOT_ROLL)
        restent les fenetres de Blizzard.
    Aucun crochet, aucune globale de Blizzard ecrite.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L
local C = ns.COLORS

local issecret = issecretvalue or function() return false end

local DEFAULTS = {
    enabled = true,          -- fenetre de butin CorpUI
    rolls = true,            -- jets de groupe CorpUI
    hideBlizzard = true,
    iconSize = 30,
    rollIconSize = 36,
    rollWidth = 300,
    scale = 100,             -- en %
    position = "cursor",     -- "cursor" ou "fixed"
}

local LOOT_W = 240
local HEADER_H = 22
local FOOTER_H = 28

local LOOT_BLIZZ = { "LootFrame" }
local ROLL_BLIZZ = { "GroupLootContainer", "GroupLootFrame1", "GroupLootFrame2", "GroupLootFrame3", "GroupLootFrame4" }

local db
local pendingHide = false

---------------------------------------------------------------------------
-- Lectures prudentes
---------------------------------------------------------------------------

-- (issecret d abord : comparer une valeur secrete, meme a nil, est interdit)
local function readable(v)
    if issecret(v) then return false end
    return v ~= nil
end

local function num(v)
    if readable(v) and type(v) == "number" then return v end
end

-- vrai / faux lisible ; secret ou absent -> def
local function flag(v, def)
    if issecret(v) then return def end
    if v == nil then return def end
    return v and true or false
end

local function present(v)
    return issecret(v) or v ~= nil
end

local function call(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

-- couleur de qualite (ColorManager du client moderne, sinon les anciennes)
local function qualityColor(q)
    q = num(q)
    if not q then return 1, 1, 1 end
    if ColorManager and ColorManager.GetColorDataForItemQuality then
        local ok, cd = pcall(ColorManager.GetColorDataForItemQuality, q)
        if ok and type(cd) == "table" then
            local col = cd.color
            if type(col) == "table" and col.GetRGB then
                local ok2, r, g, b = pcall(col.GetRGB, col)
                if ok2 and num(r) then return r, g, b end
            end
            if num(cd.r) then return cd.r, cd.g, cd.b end
        end
    end
    local fn = (C_Item and C_Item.GetItemQualityColor) or GetItemQualityColor
    if fn then
        local ok, r, g, b = pcall(fn, q)
        if ok and num(r) and num(g) and num(b) then return r, g, b end
    end
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function setFont(fs, size)
    local font = (ns.FontFile and ns.FontFile("regular")) or STANDARD_TEXT_FONT
    pcall(fs.SetFont, fs, font, size, "OUTLINE")
end

-- texte du jeu s il existe, sinon le notre
local function gameText(global, fallback)
    local v = _G[global]
    if type(v) == "string" and v ~= "" then return v end
    return fallback
end

local function showTooltip(owner, method, ...)
    local t = GameTooltip
    t:SetOwner(owner, "ANCHOR_RIGHT")
    if t[method] and pcall(t[method], t, ...) then t:Show() else t:Hide() end
end

-- lien d objet : Maj = chat, Ctrl = cabine d essayage (fonction du jeu)
local function modifiedLink(link)
    if not present(link) then return end
    if HandleModifiedItemClick and pcall(HandleModifiedItemClick, link) then return end
    if IsShiftKeyDown() and ChatEdit_InsertLink then pcall(ChatEdit_InsertLink, link) end
end

---------------------------------------------------------------------------
-- Fenetre de butin
---------------------------------------------------------------------------

local lootFrame, lootHolder
local lootRows = {}
local cleared = {}
local lootPreview         -- liste factice (apercu), sinon nil

local function previewItems()
    return {
        { tex = "Interface\\Icons\\INV_Misc_Coin_01", name = "12 " .. (ns.L.MONEY_S or "s"), qty = 1, quality = 1, coin = true },
        { tex = "Interface\\Icons\\INV_Sword_04", name = L.LT_PREVIEW_ITEM, qty = 1, quality = 3 },
        { tex = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01", name = L.LT_PREVIEW_ITEM, qty = 4, quality = 1 },
        { tex = "Interface\\Icons\\INV_Misc_Gem_Pearl_04", name = L.LT_PREVIEW_ITEM, qty = 1, quality = 4, quest = true },
    }
end

-- infos d un emplacement (ou nil s il est vide)
local function slotData(i)
    if lootPreview then return lootPreview[i] end
    if cleared[i] then return nil end
    local ok, tex, name, qty, currencyID, quality, locked, isQuestItem, questID, isActive, isCoin = pcall(GetLootSlotInfo, i)
    if not ok or not present(tex) then return nil end
    if readable(currencyID) and currencyID and CurrencyContainerUtil and CurrencyContainerUtil.GetCurrencyContainerInfo then
        local ok2, n2, t2, q2, qual2 = pcall(CurrencyContainerUtil.GetCurrencyContainerInfo, currencyID, qty, name, tex, quality)
        if ok2 then name, tex, qty, quality = n2, t2, q2, qual2 end
    end
    -- l argent arrive sur plusieurs lignes
    if readable(name) and type(name) == "string" then name = name:gsub("\n", " ") end
    local d = { tex = tex, name = name, qty = qty, quality = quality }
    d.locked = flag(locked, false)
    d.quest = flag(isQuestItem, false) or readable(questID) and questID ~= 0
    d.questStart = readable(questID) and questID ~= 0 and not flag(isActive, true)
    d.coin = flag(isCoin, false)
    return d
end

local function lootCount()
    if lootPreview then return #lootPreview end
    local ok, n = pcall(GetNumLootItems)
    return ok and num(n) or 0
end

local function slotType(i)
    local ok, t = call(GetLootSlotType, i)
    if ok then return num(t) end
end

local function onSlotEnter(self)
    if lootPreview or not self.slot then return end
    local t = slotType(self.slot)
    local LT = Enum and Enum.LootSlotType or {}
    if t ~= nil and t == LT.Currency then
        showTooltip(self, "SetLootCurrency", self.slot)
    elseif t == nil or t == LT.Item then
        showTooltip(self, "SetLootItem", self.slot)
    end
end

local function onSlotClick(self)
    if lootPreview or not self.slot then return end
    if IsModifiedClick and IsModifiedClick() then
        local ok, link = call(GetLootSlotLink, self.slot)
        if ok then modifiedLink(link) end
        return
    end
    pcall(LootSlot, self.slot)
end

local function makeSlot(parent)
    local b = CreateFrame("Button", nil, parent)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.border = b:CreateTexture(nil, "BORDER")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.border:SetPoint("TOPLEFT", b.icon, "TOPLEFT", -1, 1)
    b.border:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", 1, -1)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", -1, 1)
    b.quest = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.quest:SetPoint("TOPLEFT", b.icon, "TOPLEFT", 2, -1)
    b.quest:SetText("!")
    b.quest:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.name:SetJustifyH("LEFT")
    b.name:SetWordWrap(false)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    ns.UI.Gradient(hl, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.3, C.violet[1], C.violet[2], C.violet[3], 0.02)
    b:SetScript("OnEnter", onSlotEnter)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", onSlotClick)
    return b
end

local function styleSlot(b)
    local s = db.iconSize
    b:SetHeight(s + 4)
    b.icon:ClearAllPoints()
    b.icon:SetPoint("LEFT", 2, 0)
    b.icon:SetSize(s, s)
    b.name:ClearAllPoints()
    b.name:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
    b.name:SetPoint("RIGHT", -4, 0)
    setFont(b.name, math.max(10, math.min(14, math.floor(s / 2.4))))
end

local function fillSlot(b, d)
    if not pcall(b.icon.SetTexture, b.icon, d.tex) then b.icon:SetTexture(nil) end
    if d.locked then b.icon:SetVertexColor(0.9, 0.2, 0.2) else b.icon:SetVertexColor(1, 1, 1) end
    local r, g, bl = qualityColor(d.quality)
    if d.coin then r, g, bl = C.gold[1], C.gold[2], C.gold[3] end
    if not pcall(b.name.SetText, b.name, d.name) then b.name:SetText("?") end
    b.name:SetTextColor(r, g, bl)
    if d.quest then
        b.border:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    else
        b.border:SetColorTexture(r * 0.8, g * 0.8, bl * 0.8, 1)
    end
    b.quest:SetShown(d.questStart and true or false)
    local q = num(d.qty)
    if q and q > 1 then
        b.count:SetText(q)
    elseif issecret(d.qty) then
        -- quantite illisible : on la donne telle quelle
        if not pcall(b.count.SetFormattedText, b.count, "%s", d.qty) then b.count:SetText("") end
    else
        b.count:SetText("")
    end
end

local function refreshLoot()
    if not lootFrame then return end
    local n = lootCount()
    local shown = 0
    local h = db.iconSize + 4
    for i = 1, n do
        local d = slotData(i)
        if d then
            shown = shown + 1
            local b = lootRows[shown]
            if not b then
                b = makeSlot(lootFrame)
                lootRows[shown] = b
            end
            styleSlot(b)
            b.slot = i
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", lootFrame, "TOPLEFT", 4, -HEADER_H - 2 - (shown - 1) * (h + 2))
            b:SetPoint("RIGHT", lootFrame, "RIGHT", -4, 0)
            fillSlot(b, d)
            b:Show()
            -- infobulle a jour si la souris est dessus
            if GameTooltip:IsOwned(b) then onSlotEnter(b) end
        end
    end
    for i = shown + 1, #lootRows do
        lootRows[i].slot = nil
        lootRows[i]:Hide()
    end
    lootFrame:SetHeight(HEADER_H + 4 + shown * (h + 2) + FOOTER_H)
    lootFrame.lootAll:SetEnabled(shown > 0)
end

local function placeLoot()
    local f = lootFrame
    f:SetScale(db.scale / 100)
    f:ClearAllPoints()
    if db.position == "fixed" then
        f:SetPoint("TOPLEFT", lootHolder, "TOPLEFT")
    else
        -- premiere ligne sous le curseur (le cadre reste dans l ecran)
        local x, y = GetCursorPosition()
        local s = f:GetEffectiveScale()
        x = (num(x) or 0) / s - 20
        y = (num(y) or 0) / s + HEADER_H + (db.iconSize + 4) / 2 + 2
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    end
end

local function lootAll()
    if lootPreview then return end
    -- a l envers : ramasser ne decale pas les emplacements restants
    for i = lootCount(), 1, -1 do
        if slotData(i) then pcall(LootSlot, i) end
    end
end

local function closeLoot()
    if lootPreview then
        lootPreview = nil
        lootFrame:Hide()
        return
    end
    pcall(CloseLoot)
    lootFrame:Hide()
end

local function buildLoot()
    lootHolder = CreateFrame("Frame", "CorpUILootAnchor", UIParent)
    lootHolder:SetSize(LOOT_W, HEADER_H + FOOTER_H + 3 * 34)
    ns.ApplyPos(lootHolder, db.pos)
    lootHolder.mover = ns.UI.Mover(lootHolder, db.pos, L.LT_H_WINDOW)

    local f = CreateFrame("Frame", "CorpUILootFrame", UIParent, "BackdropTemplate")
    lootFrame = f
    f:SetSize(LOOT_W, 120)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    ns.UI.SetBackdrop(f, 0.95)
    ns.UI.Shadow(f, 4)

    local head = f:CreateTexture(nil, "ARTWORK")
    head:SetPoint("TOPLEFT", 1, -1)
    head:SetPoint("TOPRIGHT", -1, -1)
    head:SetHeight(HEADER_H)
    ns.UI.Gradient(head, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.35, C.violet[1], C.violet[2], C.violet[3], 0.05)
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", 1, -HEADER_H - 1)
    line:SetPoint("TOPRIGHT", -1, -HEADER_H - 1)
    line:SetHeight(1)
    ns.NoSnap(line)
    ns.UI.Gradient(line, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.7, C.gold[1], C.gold[2], C.gold[3], 0)

    f.title = f:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(f.title, 12)
    f.title:SetPoint("TOPLEFT", 8, -5)
    f.title:SetPoint("RIGHT", -26, 0)
    f.title:SetHeight(14)
    f.title:SetJustifyH("LEFT")
    f.title:SetWordWrap(false)
    f.title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    f.title:SetText(gameText("LOOT", L.MOD_LOOT))

    local close = ns.UI.Button(f, "x", 18, closeLoot)
    close:SetSize(18, 18)
    close:SetPoint("TOPRIGHT", -3, -2)

    f.lootAll = ns.UI.Button(f, L.LT_LOOT_ALL, 120, lootAll)
    f.lootAll:SetPoint("BOTTOMLEFT", 4, 4)
    f.lootAll:SetPoint("BOTTOMRIGHT", -4, 4)

    f:SetScript("OnHide", function()
        GameTooltip:Hide()
        lootPreview = nil
    end)
    f:Hide()
end

local function openLoot(preview)
    if not db or not lootFrame then return end
    if not preview and not db.enabled then return end
    wipe(cleared)
    lootPreview = preview
    placeLoot()
    refreshLoot()
    lootFrame:Show()
    lootFrame:Raise()
end

---------------------------------------------------------------------------
-- Jets de groupe
---------------------------------------------------------------------------

local rollHolder
local active = {}       -- cadres affiches, dans l ordre
local pool = {}

-- types de jet : valeur pour RollOnLoot, atlas du client, image classique
local ROLLS = {
    { key = "need", type = 1, atlas = "lootroll-toast-icon-need-up", file = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",
      label = function() return gameText("NEED", L.LT_NEED) end },
    { key = "greed", type = 2, atlas = "lootroll-toast-icon-greed-up", file = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
      label = function() return gameText("GREED", L.LT_GREED) end },
    { key = "transmog", type = 4, atlas = "lootroll-toast-icon-transmog-up", file = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
      label = function() return gameText("TRANSMOGRIFICATION", L.LT_TRANSMOG) end },
    { key = "de", type = 3, atlas = "lootroll-toast-icon-disenchant-up", file = "Interface\\Buttons\\UI-GroupLoot-DE-Up",
      label = function() return gameText("ROLL_DISENCHANT", L.LT_DE) end },
    { key = "pass", type = 0, atlas = "lootroll-toast-icon-pass-up", file = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
      label = function() return gameText("PASS", L.LT_PASS) end },
}

local function setIcon(tex, atlas, file)
    local ok, res = pcall(tex.SetAtlas, tex, atlas)
    if not ok or res == false then tex:SetTexture(file) end
end

local layoutRolls

local function releaseRoll(r)
    for i, o in ipairs(active) do
        if o == r then table.remove(active, i) break end
    end
    r.rollID, r.preview, r.token = nil, nil, nil
    r:Hide()
    if GameTooltip:IsOwned(r.iconBtn) then GameTooltip:Hide() end
    table.insert(pool, r)
    layoutRolls()
end

local function findRoll(rollID)
    if not readable(rollID) then return nil end
    for _, r in ipairs(active) do
        if r.rollID == rollID then return r end
    end
end

local function onRollButton(self)
    local r = self.owner
    if r.preview then releaseRoll(r) return end
    if not r.rollID then return end
    -- le cadre disparait a CANCEL_LOOT_ROLL (comme chez Blizzard), ce qui
    -- laisse la confirmation des objets lies faire son travail
    pcall(RollOnLoot, r.rollID, self.def.type)
end

local function onRollButtonEnter(self)
    local t = GameTooltip
    t:SetOwner(self, "ANCHOR_RIGHT")
    t:AddLine(self.def.label(), 1, 1, 1)
    if not self:IsEnabled() and type(self.reason) == "string" then
        t:AddLine(self.reason, 1, 0.25, 0.25, true)
    end
    t:Show()
end

local function makeRoll()
    local r = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    r:SetFrameStrata("DIALOG")
    r:SetClampedToScreen(true)
    r:EnableMouse(true)
    ns.UI.SetBackdrop(r, 0.95)
    ns.UI.Shadow(r, 3)

    local ib = CreateFrame("Button", nil, r)
    r.iconBtn = ib
    ib.border = ib:CreateTexture(nil, "BORDER")
    ib.border:SetPoint("TOPLEFT", -1, 1)
    ns.NoSnap(ib.border)
    ib.border:SetPoint("BOTTOMRIGHT", 1, -1)
    ib.icon = ib:CreateTexture(nil, "ARTWORK")
    ib.icon:SetAllPoints()
    ib.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ib.count = ib:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    ib.count:SetPoint("BOTTOMRIGHT", -1, 1)
    ib:SetScript("OnEnter", function(self)
        if r.preview or not r.rollID then return end
        showTooltip(self, "SetLootRollItem", r.rollID)
    end)
    ib:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ib:SetScript("OnClick", function()
        if r.preview or not r.rollID then return end
        if IsModifiedClick and IsModifiedClick() then
            local ok, link = call(GetLootRollItemLink, r.rollID)
            if ok then modifiedLink(link) end
        end
    end)

    r.buttons = {}
    for _, def in ipairs(ROLLS) do
        local b = CreateFrame("Button", nil, r)
        b.def, b.owner = def, r
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints()
        setIcon(b.tex, def.atlas, def.file)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.15)
        b:SetMotionScriptsWhileDisabled(true)
        b:SetScript("OnClick", onRollButton)
        b:SetScript("OnEnter", onRollButtonEnter)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r.buttons[def.key] = b
    end

    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)

    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetStatusBarTexture(ns.BAR_TEXTURE)
    r.bar:SetStatusBarColor(C.violet[1], C.violet[2], C.violet[3], 1)
    r.bar:SetMinMaxValues(0, 1)
    local bbg = r.bar:CreateTexture(nil, "BACKGROUND")
    bbg:SetAllPoints()
    bbg:SetColorTexture(0, 0, 0, 0.5)
    r.time = r.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.time:SetPoint("RIGHT", -2, 0)

    r.result = r:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(r.result, 16)
    r.result:SetPoint("RIGHT", -10, 0)
    r.result:Hide()
    return r
end

local function styleRoll(r)
    local s = db.rollIconSize
    local bs = math.max(16, math.floor(s * 0.62))
    r:SetSize(db.rollWidth, s + 8)
    r:SetScale(db.scale / 100)
    r.iconBtn:ClearAllPoints()
    r.iconBtn:SetPoint("LEFT", 4, 0)
    r.iconBtn:SetSize(s, s)
    for _, b in pairs(r.buttons) do b:SetSize(bs, bs) end
    setFont(r.name, math.max(10, math.min(14, math.floor(s / 2.8))))
end

-- boutons visibles, de droite a gauche : Passer, Desenchanter, Cupidite
-- (ou Transmo), Besoin
local function layoutButtons(r)
    local last
    for i = #ROLLS, 1, -1 do
        local b = r.buttons[ROLLS[i].key]
        b:ClearAllPoints()
        if b:IsShown() then
            if last then b:SetPoint("RIGHT", last, "LEFT", -3, 0) else b:SetPoint("RIGHT", r, "RIGHT", -6, 0) end
            last = b
        end
    end
    r.name:ClearAllPoints()
    r.name:SetPoint("TOPLEFT", r.iconBtn, "TOPRIGHT", 6, -1)
    r.name:SetPoint("RIGHT", last or r, last and "LEFT" or "RIGHT", -6, 0)
    r.name:SetHeight(14)
    r.bar:ClearAllPoints()
    r.bar:SetPoint("BOTTOMLEFT", r.iconBtn, "BOTTOMRIGHT", 6, 1)
    r.bar:SetPoint("RIGHT", last or r, last and "LEFT" or "RIGHT", -6, 0)
    r.bar:SetHeight(math.max(6, math.floor(db.rollIconSize / 4)))
end

local function setButton(b, show, can, reason)
    b:SetShown(show)
    if not show then return end
    b:SetEnabled(can)
    pcall(b.tex.SetDesaturated, b.tex, not can)
    b.tex:SetAlpha(can and 1 or 0.5)
    b.reason = nil
    if not can and num(reason) then
        local text = _G["LOOT_ROLL_INELIGIBLE_REASON" .. reason]
        if type(text) == "string" then b.reason = text end
    end
end

-- infos du jet (vrai si l objet est connu)
local function fillRoll(r)
    local tex, name, count, quality, canNeed, canGreed, canDE, rNeed, rGreed, rDE, canTransmog
    if r.preview then
        tex, name, count, quality = "Interface\\Icons\\INV_Sword_04", L.LT_PREVIEW_ITEM, 1, 3
        canNeed, canGreed, canDE, canTransmog = true, true, false, false
    else
        local ok, a1, a2, a3, a4, _, a6, a7, a8, a9, a10, a11, _, a13 = pcall(GetLootRollItemInfo, r.rollID)
        if not ok or not present(a2) then return false end
        tex, name, count, quality = a1, a2, a3, a4
        canNeed, canGreed, canDE = flag(a6, true), flag(a7, true), flag(a8, false)
        rNeed, rGreed, rDE = a9, a10, a11
        canTransmog = flag(a13, false)
    end
    local ib = r.iconBtn
    if not pcall(ib.icon.SetTexture, ib.icon, tex) then ib.icon:SetTexture(nil) end
    local cr, cg, cb = qualityColor(quality)
    ib.border:SetColorTexture(cr, cg, cb, 1)
    if not pcall(r.name.SetText, r.name, name) then r.name:SetText("?") end
    r.name:SetTextColor(cr, cg, cb)
    local c = num(count)
    ib.count:SetText(c and c > 1 and c or "")
    setButton(r.buttons.need, true, canNeed, rNeed)
    setButton(r.buttons.greed, not canTransmog, canGreed, rGreed)
    setButton(r.buttons.transmog, canTransmog, true)
    setButton(r.buttons.de, canDE, true, rDE)
    setButton(r.buttons.pass, true, true)
    r.result:Hide()
    layoutButtons(r)
    return true
end

layoutRolls = function()
    if not rollHolder then return end
    local y = 0
    for _, r in ipairs(active) do
        r:ClearAllPoints()
        -- (decalage divise par l echelle du jet : il compte dans son repere)
        r:SetPoint("TOP", rollHolder, "TOP", 0, -y / (db.scale / 100))
        y = y + (db.rollIconSize + 8 + 4) * db.scale / 100
    end
end

local function addRoll(rollID, rollTime, preview)
    if not db or not rollHolder then return end
    if not preview then
        if not db.rolls or not readable(rollID) or findRoll(rollID) then return end
    end
    local r = table.remove(pool) or makeRoll()
    r.rollID, r.preview = rollID, preview
    styleRoll(r)
    if not fillRoll(r) then
        r.rollID, r.preview = nil, nil
        table.insert(pool, r)
        return
    end
    local total = num(rollTime)
    if (not total or total <= 0) and not preview and C_Loot and C_Loot.GetLootRollDuration then
        local ok, d = pcall(C_Loot.GetLootRollDuration, rollID)
        if ok then total = num(d) end
    end
    if not total or total <= 0 then total = 60000 end
    r.total = total
    r.started = GetTime()
    r.bar:SetMinMaxValues(0, total)
    r.bar:SetValue(total)
    r:Show()
    table.insert(active, r)
    layoutRolls()
end

local function clearRolls()
    for i = #active, 1, -1 do releaseRoll(active[i]) end
end

-- jets deja en cours (connexion, rechargement, activation)
local function rehydrate()
    if not db or not db.rolls then return end
    local ok, list = call(GetActiveLootRollIDs)
    if not ok or type(list) ~= "table" then return end
    for _, id in ipairs(list) do addRoll(id) end
end

-- resultat d un jet Besoin (le jeu le montre 5 s avant de retirer le cadre)
local function showNeedResult(rollID, roll, isWinning)
    local r = findRoll(rollID)
    if not r then return end
    for _, b in pairs(r.buttons) do b:Hide() end
    local win = flag(isWinning, false)
    if not pcall(r.result.SetFormattedText, r.result, "%s", roll) then r.result:SetText("") end
    if win then r.result:SetTextColor(0.25, 1, 0.25) else r.result:SetTextColor(1, 0.25, 0.25) end
    r.result:Show()
    local token = {}
    r.token = token
    C_Timer.After(5, function() if r.token == token then releaseRoll(r) end end)
end

local function updateRolls()
    for i = #active, 1, -1 do
        local r = active[i]
        local left
        if r.preview then
            left = r.total - (GetTime() - r.started) * 1000
            if left <= 0 then releaseRoll(r) end
        else
            local ok, v = call(GetLootRollTimeLeft, r.rollID)
            if ok then left = v end
        end
        if r:IsShown() then
            local l = num(left)
            if l then
                l = math.max(0, math.min(l, r.total))
                r.bar:SetValue(l)
                r.time:SetText(string.format("%d", math.ceil(l / 1000)))
                local p = l / r.total
                r.bar:SetStatusBarColor(C.violet[1] * p + 1 * (1 - p), C.violet[2] * p + 0.3 * (1 - p), C.violet[3] * p + 0.2 * (1 - p), 1)
            elseif left ~= nil and not pcall(r.bar.SetValue, r.bar, left) then
                r.bar:SetValue(0)
            end
            -- filet de securite si CANCEL_LOOT_ROLL n arrive pas
            if not r.preview and GetTime() - r.started > r.total / 1000 + 10 then releaseRoll(r) end
        end
    end
end

local function buildRolls()
    rollHolder = CreateFrame("Frame", "CorpUILootRollAnchor", UIParent)
    rollHolder:SetSize(db.rollWidth, db.rollIconSize + 8)
    ns.ApplyPos(rollHolder, db.rollPos)
    rollHolder.mover = ns.UI.Mover(rollHolder, db.rollPos, L.LT_H_ROLLS)
    local since = 0
    rollHolder:SetScript("OnUpdate", function(_, dt)
        since = since + dt
        if since < 0.1 then return end
        since = 0
        if #active > 0 then updateRolls() end
    end)
end

---------------------------------------------------------------------------
-- Application des reglages
---------------------------------------------------------------------------

local function hideBlizzard()
    if not db then return end
    local a = ns.HideBlizzard(LOOT_BLIZZ, db.enabled and db.hideBlizzard)
    local b = ns.HideBlizzard(ROLL_BLIZZ, db.rolls and db.hideBlizzard)
    pendingHide = not (a and b)
end

local function updateMovers()
    if not db or not lootHolder then return end
    local s = db.scale / 100
    lootHolder:SetSize(LOOT_W * s, (HEADER_H + FOOTER_H + 3 * (db.iconSize + 6)) * s)
    rollHolder:SetSize(db.rollWidth * s, (db.rollIconSize + 8) * s)
    lootHolder.mover:SetShown(ns.moversShown and db.enabled and db.position == "fixed")
    rollHolder.mover:SetShown(ns.moversShown and db.rolls)
end

local function apply()
    if not db then return end
    hideBlizzard()
    updateMovers()
    if not db.enabled and lootFrame:IsShown() and not lootPreview then lootFrame:Hide() end
    if lootFrame:IsShown() then
        placeLoot()
        refreshLoot()
    end
    if db.rolls then
        for _, r in ipairs(active) do styleRoll(r) fillRoll(r) end
        layoutRolls()
        rehydrate()
    else
        clearRolls()
    end
end

local function preview()
    if not db then return end
    openLoot(previewItems())
    addRoll(nil, 20000, true)
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------

local win

local function buildOptions()
    win = ns.UI.Window("CorpUILootOptions", ns.TITLE .. " - " .. L.MOD_LOOT, nil, 440, 300)
    local form = ns.UI.Form(win, -34, function() apply() end)
    local function check(key, text)
        form:Check(text, function() return db[key] end, function(v) db[key] = v end)
    end
    check("enabled", L.LT_OPT_ENABLE)
    check("rolls", L.LT_OPT_ROLLS)
    check("hideBlizzard", L.LT_OPT_BLIZZ)
    form:Header(L.LT_H_WINDOW)
    form:Columns(2)
    form:Number(L.LT_ICON_SIZE, function() return db.iconSize end, function(v) db.iconSize = v end, 16, 48)
    form:Number(L.LT_SCALE, function() return db.scale end, function(v) db.scale = v end, 50, 200, 5)
    form:Cycle(L.LT_POSITION, { "cursor", "fixed" }, { cursor = L.LT_POS_CURSOR, fixed = L.LT_POS_FIXED },
        function() return db.position end, function(v) db.position = v end)
    form:EndColumns()
    form:Header(L.LT_H_ROLLS)
    form:Columns(2)
    form:Number(L.LT_ROLL_ICON, function() return db.rollIconSize end, function(v) db.rollIconSize = v end, 20, 64)
    form:Number(L.LT_ROLL_WIDTH, function() return db.rollWidth end, function(v) db.rollWidth = v end, 200, 500, 10)
    form:EndColumns()
    form:Gap(4)
    local prev = ns.UI.Button(win, L.LT_PREVIEW, 150, preview)
    prev:SetPoint("TOPLEFT", win, "TOPLEFT", 8, form.y)
    form:Gap(30)
    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", win, "TOPLEFT", 8, form.y - 4)
    hint:SetWidth(420)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.LT_HINT)
    win:SetHeight(math.floor(80 - form.y))
    win:HookScript("OnShow", function() form:Refresh() end)
end

local function toggle()
    if not win then buildOptions() end
    ns.ShowPanel(win)
end

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, ...)
    if ns.ModuleOff("butin", ev) then return end
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        root.loot = root.loot or {}
        db = root.loot
        for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
        if type(db.pos) ~= "table" then db.pos = { point = "LEFT", x = 260, y = 120 } end
        if type(db.rollPos) ~= "table" then db.rollPos = { point = "TOP", x = 0, y = -200 } end
        if db.position ~= "fixed" then db.position = "cursor" end
        buildLoot()
        buildRolls()
        apply()
        return
    end
    if not db then return end
    if event == "LOOT_OPENED" then
        openLoot(nil)
    elseif event == "LOOT_SLOT_CLEARED" then
        local slot = ...
        if num(slot) and not lootPreview then
            cleared[slot] = true
            if lootFrame:IsShown() then refreshLoot() end
        end
    elseif event == "LOOT_SLOT_CHANGED" then
        if lootFrame:IsShown() and not lootPreview then refreshLoot() end
    elseif event == "LOOT_CLOSED" then
        if not lootPreview then lootFrame:Hide() end
    elseif event == "START_LOOT_ROLL" then
        local rollID, rollTime = ...
        addRoll(rollID, rollTime)
    elseif event == "CANCEL_LOOT_ROLL" then
        local r = findRoll((...))
        -- un jet Besoin garde son resultat affiche quelques secondes
        if r and not r.token then releaseRoll(r) end
    elseif event == "CANCEL_ALL_LOOT_ROLLS" then
        clearRolls()
    elseif event == "MAIN_SPEC_NEED_ROLL" then
        showNeedResult(...)
    elseif event == "PLAYER_ENTERING_WORLD" then
        rehydrate()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingHide then hideBlizzard() end
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_SLOT_CHANGED", "LOOT_CLOSED",
                     "START_LOOT_ROLL", "CANCEL_LOOT_ROLL", "CANCEL_ALL_LOOT_ROLLS", "MAIN_SPEC_NEED_ROLL",
                     "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }) do
    pcall(ev.RegisterEvent, ev, e)
end

ns.Listen(function() if db and lootHolder then updateMovers() end end)

ns.RegisterModule({
    command = "butin",
    panelName = "CorpUILootOptions",
    icon = "Interface\\Icons\\INV_Misc_Bag_10",
    title = function() return L.MOD_LOOT end,
    desc = function() return L.LT_DESC end,
    Slash = function(input)
        local cmd = strlower(strtrim(input or ""))
        if cmd == "test" or cmd == "apercu" then preview() return end
        toggle()
    end,
    Open = toggle,
})
