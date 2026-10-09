--[[--------------------------------------------------------------------------
    CorpUI - module Sacs
    Un seul sac pour tous les sacs (0 a 4).
      clic droit       : utiliser l objet (vendre chez un marchand) ; bouton
                         securise type "item", marche aussi en combat
      clic gauche      : prendre / poser (hors combat)
      Maj + clic       : lien dans le chat
      glisser-deposer  : ranger
    Recherche (les objets qui ne correspondent pas s estompent), tri, or,
    places libres. Options : taille et espacement des cases, lisere de
    qualite, objets de quete, nouveaux objets surlignes, niveau d objet,
    regroupement par type (affichage seulement : chaque bouton reste lie a
    son sac et a sa place reels ; la disposition ne change que hors combat).

    Ouverture : les touches des sacs (B, Maj+B...) cliquent un bouton
    securise qui ouvre/ferme notre sac, meme en combat. Ouvert
    automatiquement chez un marchand, a la banque, au courrier.
    Les sacs de Blizzard sont ranges dans un parent cache (option).
    Les boutons d objets, les titres de blocs et l habillage de la fenetre
    sont partages avec la fenetre de banque (ns.BagsShared, Banque.lua).
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local issecret = issecretvalue or function() return false end

-- taille et espacement des cases : reglages (db.size, db.spacing)
local PAD, HEAD, FOOT = 10, 52, 30
local MIN_WIDTH = 250     -- place pour la recherche, Trier et la croix
local QUEST_COLOR = { 1, 0.85, 0.1 }
local NEW_COLOR = { 1, 0.82, 0.25 }
local BAG_BINDINGS = { "OPENALLBAGS", "TOGGLEBACKPACK", "TOGGLEBAG1", "TOGGLEBAG2", "TOGGLEBAG3", "TOGGLEBAG4" }
local BLIZZ = { "ContainerFrameCombinedBags" }
for i = 1, 13 do table.insert(BLIZZ, "ContainerFrame" .. i) end

local db
local frame, toggleBtn, search, freeText, moneyText
local buttons = {}     -- "bag:slot" -> bouton
local layoutPending = false
-- PNJ ou fenetre ouverts (marchand, banque, poste, hotel des ventes,
-- echange) : le clic droit doit vendre / deposer / joindre, pas utiliser
local contexts = {}
local contextPending = false
local function atNPC() return next(contexts) ~= nil end
local owner = CreateFrame("Frame")

---------------------------------------------------------------------------
-- Objets
---------------------------------------------------------------------------

local function containerInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
        return ok and info or nil
    end
end

-- nombre lisible (ni secret ni autre chose qu un nombre), sinon nil
local function num(v)
    if v == nil or issecret(v) or type(v) ~= "number" then return nil end
    return v
end

-- couleur de qualite ; minQ : qualite minimale (2 = vert, 0 = tout)
local function qualityColor(q, minQ)
    q = num(q)
    if not q or q < (minQ or 2) then return nil end
    local fn = C_Item and C_Item.GetItemQualityColor
    if fn then
        local ok, r, g, b = pcall(fn, q)
        if ok and num(r) and num(g) and num(b) then return r, g, b end
    end
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
end

-- classe d objet (classID) et emplacement d equipement, sans attendre le cache
local function itemClass(itemID)
    itemID = num(itemID)
    local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not itemID or not fn then return nil end
    local ok, _, _, _, equipLoc, _, classID = pcall(fn, itemID)
    if not ok then return nil end
    if issecret(equipLoc) or type(equipLoc) ~= "string" then equipLoc = nil end
    return num(classID), equipLoc
end

-- objet de quete ? (et "commence une quete" pas encore prise)
local function questState(bag, slot)
    local fn = C_Container and C_Container.GetContainerItemQuestInfo
    if not fn then return false, false end
    local ok, q = pcall(fn, bag, slot)
    if not ok or type(q) ~= "table" then return false, false end
    local isQuest, questID, active = q.isQuestItem, q.questID, q.isActive
    if issecret(isQuest) or issecret(questID) or issecret(active) then return false, false end
    return isQuest and true or false, (questID and not active) and true or false
end

local function isNewItem(bag, slot)
    if not (C_NewItems and C_NewItems.IsNewItem) then return false end
    local ok, v = pcall(C_NewItems.IsNewItem, bag, slot)
    return ok and not issecret(v) and v and true or false
end

local function clearNew(b)
    if b.isNew and C_NewItems and C_NewItems.RemoveNewItem then
        pcall(C_NewItems.RemoveNewItem, b.bag, b.slot)
    end
    b.isNew = false
    b.glow:Hide()
end

-- niveau d objet de l equipement (armes, armures), sinon nil
local NO_ILVL = { [""] = true, INVTYPE_BAG = true, INVTYPE_QUIVER = true, INVTYPE_BODY = true,
                  INVTYPE_TABARD = true, INVTYPE_AMMO = true, INVTYPE_NON_EQUIP_IGNORE = true }
local function itemLevel(link, classID, equipLoc)
    if not link or issecret(link) or (classID ~= 2 and classID ~= 4) then return nil end
    if not equipLoc or NO_ILVL[equipLoc] then return nil end
    local fn = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
    if not fn then return nil end
    local ok, lvl = pcall(fn, link)
    lvl = ok and num(lvl)
    if lvl and lvl > 1 then return math.floor(lvl + 0.5) end
end

-- categorie d affichage (regroupement par type)
local GROUP_ORDER = { "equip", "consum", "trade", "quest", "misc", "empty" }
local GROUP_LABEL = { equip = "BAGS_GROUP_EQUIP", consum = "BAGS_GROUP_CONSUM", trade = "BAGS_GROUP_TRADE",
                      quest = "BAGS_GROUP_QUEST", misc = "BAGS_GROUP_MISC", empty = "BAGS_GROUP_EMPTY" }
-- classID : 0 consommable, 2 arme, 3 gemme, 4 armure, 5 composant,
-- 7 artisanat, 8 amelioration, 9 recette, 12 quete
local CLASS_GROUP = { [0] = "consum", [8] = "consum", [2] = "equip", [4] = "equip",
                      [3] = "trade", [5] = "trade", [7] = "trade", [9] = "trade", [12] = "quest" }
local function category(bag, slot)
    local info = containerInfo(bag, slot)
    if not info then return "empty" end
    if questState(bag, slot) then return "quest" end
    local classID, equipLoc = itemClass(info.itemID)
    local g = classID and CLASS_GROUP[classID]
    -- armure "divers" non equipable (ex. objet a tenir) : divers
    if g == "equip" and (not equipLoc or NO_ILVL[equipLoc]) then g = "misc" end
    return g or "misc"
end

local newCount = 0

-- texte de la recherche (partage par les sacs et la banque), en minuscules
local function currentQuery()
    return search and strlower(strtrim(search:GetText() or "")) or ""
end

-- met a jour un bouton (sacs ou banque). query : recherche en minuscules ;
-- noNew : pas de lueur "nouvel objet" (banque). Renvoie vrai si l objet
-- est nouveau.
local function updateButton(b, query, noNew)
    local info = containerInfo(b.bag, b.slot)
    if not info then
        b.icon:SetTexture(nil)
        b.count:SetText("")
        b.border:Hide()
        b.cd:Clear()
        b.ilvl:SetText("")
        b.questMark:Hide()
        b.isNew = false
        b.glow:Hide()
        b.link = nil
        return false
    end
    b.icon:SetTexture(info.iconFileID)
    b.icon:SetDesaturated(info.isLocked and true or false)
    local stack = num(info.stackCount) or 1
    b.count:SetText(stack > 1 and stack or "")
    b.link = info.hyperlink
    -- lisere : quete (option), sinon qualite (option)
    local isQuest, starts = false, false
    if db.questBorder then isQuest, starts = questState(b.bag, b.slot) end
    local r, g, bl
    if isQuest then
        r, g, bl = QUEST_COLOR[1], QUEST_COLOR[2], QUEST_COLOR[3]
    elseif db.qualityBorder then
        r, g, bl = qualityColor(info.quality, db.qualityLow and 0 or 2)
    end
    if r then
        b.border:SetColorTexture(r, g, bl, 1)
        b.border:Show()
    else
        b.border:Hide()
    end
    b.questMark:SetShown(starts)
    -- niveau d objet
    local lvl
    if db.itemLevel then
        local classID, equipLoc = itemClass(info.itemID)
        lvl = itemLevel(info.hyperlink, classID, equipLoc)
    end
    if lvl then
        local qr, qg, qb = qualityColor(info.quality, 0)
        b.ilvl:SetTextColor(qr or 1, qg or 1, qb or 1)
        b.ilvl:SetText(lvl)
    else
        b.ilvl:SetText("")
    end
    -- nouvel objet : lueur jusqu au survol ou a la fermeture des sacs
    b.isNew = (not noNew) and db.newGlow and isNewItem(b.bag, b.slot) or false
    b.glow:SetShown(b.isNew)
    if C_Container.GetContainerItemCooldown then
        local ok, start, duration = pcall(C_Container.GetContainerItemCooldown, b.bag, b.slot)
        if ok and start then pcall(b.cd.SetCooldown, b.cd, start, duration) end
    end
    -- recherche : estomper ce qui ne correspond pas
    query = query or ""
    local name = (not issecret(info.hyperlink) and type(info.hyperlink) == "string") and ns.LinkName(info.hyperlink) or ""
    if issecret(name) or type(name) ~= "string" then name = "" end
    b.icon:SetAlpha((query == "" or strlower(name):find(query, 1, true)) and 1 or 0.2)
    return b.isNew
end

local function updateAll()
    if not frame or not frame:IsShown() then return end
    local free, total = 0, 0
    newCount = 0
    local query = currentQuery()
    for _, b in pairs(buttons) do
        if b:IsShown() then
            if updateButton(b, query) then newCount = newCount + 1 end
            total = total + 1
            if not b.link then free = free + 1 end
        end
    end
    freeText:SetText(string.format(L.BAGS_FREE, free, total))
    moneyText:SetText(ns.FormatMoney(GetMoney()))
end

---------------------------------------------------------------------------
-- Boutons
---------------------------------------------------------------------------

-- banque ouverte : type de banque a donner au jeu pour deposer (comme les
-- sacs de Blizzard : UseContainerItem(sac, place, nil, typeDeBanque))
local function bankDepositType()
    if not contexts.bank then return nil end
    return Enum and Enum.BankType and Enum.BankType.Character
end

-- clic droit "a la main" : vendre, deposer, joindre, ou (banque) ranger
-- dans les sacs. Hors combat seulement.
local function useItem(self)
    if InCombatLockdown() or not (C_Container and C_Container.UseContainerItem) then return end
    local bt = (not self.isBank) and bankDepositType() or nil
    if bt ~= nil then
        pcall(C_Container.UseContainerItem, self.bag, self.slot, nil, bt, false)
    else
        pcall(C_Container.UseContainerItem, self.bag, self.slot)
    end
end

-- Hotel des ventes : le clic droit du jeu (mettre l objet en vente) appelle
-- AuctionHouseFrame:SetPostItem. Appele par l addon, il marquerait la vente
-- (bouton "Creer une vente" bloque ensuite), et UseContainerItem y est
-- refuse aux addons. Le bouton du sac de Blizzard (cache, mais ses sacs
-- sont ouverts par le jeu a l HV) est donc clique par l action securisee
-- "click" : son propre code met l objet en vente, sans trace de l addon.
local function blizzardItemButton(bag, slot)
    local find = ContainerFrameUtil_GetItemButtonAndContainer
    if type(find) ~= "function" then return nil end
    local ok, b = pcall(find, bag, slot)
    if ok and type(b) == "table" and b.Click then return b end
end

-- Bouton d objet commun aux sacs et a la banque.
--   secure : bouton d action securise (sacs : clic droit "utiliser" en
--            combat, sort qui attend une cible). Sinon bouton simple
--            (banque : aucune contrainte de combat sur la fenetre).
--   name   : nom global du bouton
local function createItemButton(parent, bag, slot, secure, name, size)
    local b = CreateFrame("Button", name, parent, secure and "SecureActionButtonTemplate" or nil)
    b:SetSize(size, size)
    b.bag, b.slot, b.secure = bag, slot, secure and true or false
    b:RegisterForDrag("LeftButton")
    if secure then
        b:RegisterForClicks("AnyUp", "AnyDown")
        -- clic droit securise "utiliser" (marche en combat), sauf chez un PNJ
        b:SetAttribute("type2", atNPC() and "" or "item")
        b:SetAttribute("item", bag .. " " .. slot)
    else
        b:RegisterForClicks("AnyUp")
    end

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.12, 0.12, 0.14, 0.9)
    b.border = b:CreateTexture(nil, "BORDER")
    b.border:SetPoint("TOPLEFT", -1, 1)
    b.border:SetPoint("BOTTOMRIGHT", 1, -1)
    b.border:Hide()
    local inner = b:CreateTexture(nil, "BORDER", nil, 1)
    inner:SetAllPoints()
    inner:SetColorTexture(0.12, 0.12, 0.14, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b.icon)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    -- niveau d objet (equipement : jamais empile, le coin du nombre est libre)
    b.ilvl = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.ilvl:SetPoint("BOTTOMRIGHT", -2, 2)
    -- "!" : objet qui commence une quete
    b.questMark = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.questMark:SetPoint("TOPLEFT", 3, -2)
    b.questMark:SetText("!")
    b.questMark:SetTextColor(QUEST_COLOR[1], QUEST_COLOR[2], QUEST_COLOR[3])
    b.questMark:Hide()
    -- lueur douce des nouveaux objets (montee depuis le bas de la case)
    b.glow = b:CreateTexture(nil, "OVERLAY", nil, 1)
    b.glow:SetPoint("TOPLEFT", 1, -1)
    b.glow:SetPoint("BOTTOMRIGHT", -1, 1)
    ns.UI.Gradient(b.glow, "VERTICAL", NEW_COLOR[1], NEW_COLOR[2], NEW_COLOR[3], 0.55, NEW_COLOR[1], NEW_COLOR[2], NEW_COLOR[3], 0.05)
    pcall(b.glow.SetBlendMode, b.glow, "ADD")
    b.glow:Hide()
    b.isNew = false
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.2)

    -- sort qui attend une cible (desenchanter, enchantement, pierre a
    -- aiguiser...) : le clic gauche devient l action securisee "utiliser
    -- l objet", qui applique le sort a l objet comme dans les sacs du jeu.
    -- Sinon pas d action securisee au clic gauche (prendre/poser ci-dessous).
    -- (un clic = appui puis relachement : l etat est lu a l appui et garde
    -- jusqu au relachement, ou le sort est deja parti)
    -- Pas le type "item" : pour un objet equipable, l action securisee du jeu
    -- l equipe sans regarder le sort en attente. La macro "/use sac place"
    -- utilise l emplacement, comme les sacs du jeu (le sort s applique).
    -- (bouton simple de la banque : le clic gauche prend l objet, ce qui
    -- applique aussi un sort en attente, comme la banque de Blizzard)
    if secure then
        b:SetScript("PreClick", function(self, button, down)
            if InCombatLockdown() then return end
            -- clic droit : a l HV par le bouton du jeu ; ailleurs comme avant
            -- (utiliser hors PNJ, sinon l addon s en charge a la fin du clic)
            if button == "RightButton" then
                local target = contexts.auction and blizzardItemButton(self.bag, self.slot) or nil
                self.viaBlizzard = target ~= nil
                if target then
                    self:SetAttribute("type2", "click")
                    self:SetAttribute("clickbutton2", target)
                else
                    self:SetAttribute("type2", atNPC() and "" or "item")
                    self:SetAttribute("clickbutton2", nil)
                end
                return
            end
            if button ~= "LeftButton" then return end
            if down or self.targeting == nil then
                local t = (SpellCanTargetItem and SpellCanTargetItem())
                    or (SpellCanTargetItemID and SpellCanTargetItemID())
                    or (SpellIsTargeting and SpellIsTargeting())
                self.targeting = t and true or false
            end
            if self.targeting then
                self:SetAttribute("type1", "macro")
                self:SetAttribute("macrotext1", "/use " .. self.bag .. " " .. self.slot)
            else
                self:SetAttribute("type1", nil)
            end
        end)
    end

    -- clic gauche (insecure, hors combat) : prendre/poser, lien
    b:HookScript("OnClick", function(self, button, down)
        -- le sort a deja ete applique a l objet par l action securisee
        if button == "LeftButton" and self.targeting then
            if not down then self.targeting = nil end
            return
        end
        if button == "LeftButton" and not down then self.targeting = nil end
        -- clic droit : sacs chez un PNJ (sinon l action securisee s en
        -- charge) ; banque : toujours (ranger dans les sacs)
        if button == "RightButton" then
            if down or self.viaBlizzard then return end
            if contexts.auction and self.secure then
                -- bouton du jeu introuvable : l objet passe au curseur, a
                -- poser dans la case de vente (UseContainerItem est refuse)
                if not InCombatLockdown() then pcall(C_Container.PickupContainerItem, self.bag, self.slot) end
                return
            end
            if not self.secure or atNPC() then useItem(self) end
            return
        end
        if button ~= "LeftButton" or down then return end
        if IsShiftKeyDown() and self.link then
            if ChatEdit_InsertLink then pcall(ChatEdit_InsertLink, self.link) end
            return
        end
        if InCombatLockdown() then return end
        pcall(C_Container.PickupContainerItem, self.bag, self.slot)
    end)
    b:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        pcall(C_Container.PickupContainerItem, self.bag, self.slot)
    end)
    b:SetScript("OnReceiveDrag", function(self)
        if InCombatLockdown() then return end
        pcall(C_Container.PickupContainerItem, self.bag, self.slot)
    end)
    b:SetScript("OnEnter", function(self)
        if self.isNew then clearNew(self) end
        local t = ns.Tooltip(self, self.tipAnchor or "ANCHOR_LEFT")
        if not pcall(t.SetBagItem, t, self.bag, self.slot) or not self.link then t:Hide() return end
        t:Show()
    end)
    b:SetScript("OnLeave", ns.HideTooltip)
    return b
end

local function makeButton(bag, slot)
    local b = createItemButton(frame, bag, slot, true, "CorpUIBag" .. bag .. "Slot" .. slot, db.size)
    buttons[bag .. ":" .. slot] = b
    return b
end

---------------------------------------------------------------------------
-- Disposition (hors combat : boutons securises)
---------------------------------------------------------------------------

local SECTION = 22        -- hauteur d un titre de bloc
-- titres de blocs (composants, types d objets) : simples textes ancres au
-- sac, jamais aux boutons securises
local sections = {}

-- titre de bloc n i d une fenetre (cree a la demande dans list)
local function sectionOf(parent, list, i)
    local s = list[i]
    if s then return s end
    local C = ns.COLORS
    s = {}
    s.title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    s.title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    s.line = parent:CreateTexture(nil, "ARTWORK")
    s.line:SetHeight(1)
    s.line:SetPoint("LEFT", s.title, "RIGHT", 6, 0)
    s.line:SetPoint("RIGHT", parent, "RIGHT", -PAD, 0)
    ns.UI.Gradient(s.line, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.7, C.gold[1], C.gold[2], C.gold[3], 0)
    list[i] = s
    return s
end

local function sectionAt(i) return sectionOf(frame, sections, i) end

-- Charte des fenetres CorpUI : ombre, bandeau degrade de l accent avec un
-- filet d or, logo et titre en or (police des titres). Textures seulement :
-- rien de securise ne s y ancre.
local function dressWindow(f, titleText, headH)
    local C = ns.COLORS
    ns.UI.SetBackdrop(f, 0.95)
    ns.UI.Shadow(f, 4)
    local head = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    head:SetPoint("TOPLEFT", 1, -1)
    head:SetPoint("TOPRIGHT", -1, -1)
    head:SetHeight(headH)
    ns.UI.Gradient(head, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.35, C.violet[1], C.violet[2], C.violet[3], 0.05)
    local line = f:CreateTexture(nil, "BORDER")
    line:SetPoint("TOPLEFT", head, "BOTTOMLEFT")
    line:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT")
    line:SetHeight(1)
    ns.UI.Gradient(line, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.7, C.gold[1], C.gold[2], C.gold[3], 0)
    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetSize(18, 18)
    logo:SetPoint("TOPLEFT", 6, -(headH - 18) / 2 - 1)
    logo:SetTexture(ns.LOGO)
    local title = f:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(title, 12)
    title:SetPoint("LEFT", logo, "RIGHT", 5, 0)
    title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    title:SetText(titleText)
    return title
end

---------------------------------------------------------------------------
-- Emplacements des sacs (rangee facultative en haut) : voir et changer
-- ses sacs. Boutons simples (pas securises) : prendre / poser un sac,
-- clic avec un sac en main pour le poser.
---------------------------------------------------------------------------
local BAGSLOT = 30
local bagSlotBtns = {}

local function invSlotOf(bag)
    if C_Container and C_Container.ContainerIDToInventoryID then
        local ok, id = pcall(C_Container.ContainerIDToInventoryID, bag)
        if ok and type(id) == "number" then return id end
    end
end

local function bagSlotAt(i)
    local s = bagSlotBtns[i]
    if s then return s end
    s = CreateFrame("Button", nil, frame)
    s:SetSize(BAGSLOT, BAGSLOT)
    ns.UI.Skin(s, 0.9)
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetPoint("TOPLEFT", 1, -1)
    s.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    local hl = s:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(s.icon)
    hl:SetColorTexture(1, 1, 1, 0.15)
    s.count = s:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    s.count:SetPoint("BOTTOMRIGHT", -1, 1)
    s:RegisterForDrag("LeftButton")
    s:RegisterForClicks("LeftButtonUp")
    s:SetScript("OnDragStart", function(self)
        if InCombatLockdown() or not self.inv then return end
        pcall(PickupBagFromSlot, self.inv)
    end)
    local function put(self)
        if InCombatLockdown() or not self.inv then return end
        pcall(PutItemInBag, self.inv)
    end
    s:SetScript("OnReceiveDrag", put)
    s:SetScript("OnClick", function(self)
        if InCombatLockdown() or not self.inv then return end
        if CursorHasItem and CursorHasItem() then put(self) else pcall(PickupBagFromSlot, self.inv) end
    end)
    s:SetScript("OnEnter", function(self)
        if self.cuiBorder then self.cuiBorder:SetColorTexture(ns.COLORS.gold[1], ns.COLORS.gold[2], ns.COLORS.gold[3], 1) end
        local t = ns.Tooltip(self, "ANCHOR_TOP")
        if self.inv and pcall(t.SetInventoryItem, t, "player", self.inv) and t:NumLines() > 0 then
            t:Show()
            return
        end
        t:AddLine(BAGSLOT_TOOLTIP or BAGSLOTTEXT or L.BAGS_SLOTS_TITLE)
        t:Show()
    end)
    s:SetScript("OnLeave", function(self)
        ns.UI.ResetBorder(self)
        ns.HideTooltip()
    end)
    bagSlotBtns[i] = s
    return s
end

local function refreshBagSlots()
    for _, s in ipairs(bagSlotBtns) do
        if s:IsShown() and s.inv then
            local okT, tex = pcall(GetInventoryItemTexture, "player", s.inv)
            if okT and tex then
                s.icon:SetTexture(tex)
                s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                s.icon:SetAlpha(1)
            else
                s.icon:SetTexture(ns.MEDIA .. "menu_bagempty")
                s.icon:SetTexCoord(0, 1, 0, 1)
                s.icon:SetAlpha(0.5)
            end
            local n = ns.BagSlots(s.bag)
            s.count:SetText(n > 0 and n or "")
        end
    end
end
ns.RefreshBagSlots = refreshBagSlots

local function layout()
    -- en combat : on ne bouge rien (boutons securises), mais icones,
    -- nombres et liseres se mettent a jour
    if InCombatLockdown() then layoutPending = true updateAll() return end
    layoutPending = false
    local cols, size, gap = db.columns, db.size, db.spacing
    local step = size + gap
    local used = {}
    local reagentBag = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or ((NUM_BAG_SLOTS or 4) + 1)
    local y = HEAD            -- haut de la ligne en cours
    local n = 0               -- emplacements places dans le bloc en cours
    local nsec = 0            -- titres de blocs utilises
    local function place(bag, slot)
        local key = bag .. ":" .. slot
        local btn = buttons[key] or makeButton(bag, slot)
        used[key] = true
        local col, row = n % cols, math.floor(n / cols)
        btn:SetSize(size, size)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", PAD + col * step, -(y + row * step))
        btn:Show()
        n = n + 1
    end
    local function rowsOf(count) return math.max(0, math.ceil(count / cols)) end
    local function header(text)
        nsec = nsec + 1
        local s = sectionAt(nsec)
        s.title:SetText(text)
        s.title:ClearAllPoints()
        s.title:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(y + 4))
        s.title:Show()
        s.line:Show()
        y = y + SECTION
    end

    -- emplacements des sacs (facultatif) : sacs 1 a 4 et sac de composants
    local nSlot = 0
    if db.showBagSlots then
        header(BAGSLOTTEXT or L.BAGS_SLOTS_TITLE)
        for _, bag in ipairs(ns.PlayerBags()) do
            local inv = bag ~= 0 and invSlotOf(bag)
            if inv then
                nSlot = nSlot + 1
                local s = bagSlotAt(nSlot)
                s.bag, s.inv = bag, inv
                s:ClearAllPoints()
                s:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + (nSlot - 1) * (BAGSLOT + 4), -(y + 1))
                s:Show()
            end
        end
        y = y + BAGSLOT + 8
    end
    for i = nSlot + 1, #bagSlotBtns do bagSlotBtns[i]:Hide() end
    refreshBagSlots()
    -- sans la rangee (ni titre de bloc) : un peu d air sous la recherche
    if not db.showBagSlots and not db.groupByType then y = y + 6 end

    -- sacs normaux (0 a 4)
    local bags, slots = {}, {}
    for _, bag in ipairs(ns.PlayerBags()) do
        if bag ~= reagentBag then
            for slot = 1, ns.BagSlots(bag) do
                bags[#bags + 1], slots[#slots + 1] = bag, slot
            end
        end
    end
    if db.groupByType then
        -- un bloc par type, dans l ordre des sacs a l interieur de chaque bloc
        local groups = {}
        for _, g in ipairs(GROUP_ORDER) do groups[g] = {} end
        for i = 1, #bags do
            local list = groups[category(bags[i], slots[i])]
            list[#list + 1] = i
        end
        local any = false
        for _, g in ipairs(GROUP_ORDER) do
            local list = groups[g]
            if #list > 0 then
                any = true
                header(L[GROUP_LABEL[g]])
                n = 0
                for _, i in ipairs(list) do place(bags[i], slots[i]) end
                y = y + rowsOf(n) * step
            end
        end
        if not any then y = y + step end
    else
        for i = 1, #bags do place(bags[i], slots[i]) end
        y = y + math.max(1, rowsOf(n)) * step
    end

    -- sac de composants : son propre bloc, sous un titre
    local reagentSlots = ns.BagSlots(reagentBag)
    if reagentSlots > 0 then
        header(L.BAGS_REAGENTS)
        n = 0
        for slot = 1, reagentSlots do place(reagentBag, slot) end
        y = y + rowsOf(n) * step
    end

    for i = nsec + 1, #sections do
        sections[i].title:Hide()
        sections[i].line:Hide()
    end
    for key, btn in pairs(buttons) do
        if not used[key] then btn:Hide() end
    end
    frame:SetSize(math.max(MIN_WIDTH, PAD * 2 + cols * size + (cols - 1) * gap), y - gap + FOOT)
    updateAll()
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

local function build()
    db.pos = db.pos or { point = "BOTTOMRIGHT", x = -80, y = 120 }
    frame = CreateFrame("Frame", "CorpUIBags", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("HIGH")
    frame:SetSize(300, 300)
    ns.ApplyPos(frame, db.pos)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        ns.PinTop(self, db.pos, true)
    end)
    frame:Hide()

    dressWindow(frame, L.MOD_BAGS, 24)

    -- la banque suit la meme recherche (Banque.lua)
    search = ns.UI.SearchBox(frame, 140, function(text)
        updateAll()
        if ns.BankSearchChanged then ns.BankSearchChanged(text) end
    end)
    search:SetPoint("TOPLEFT", 14, -30)

    local sort = ns.UI.Button(frame, L.BAGS_SORT, 60, function()
        if C_Container and C_Container.SortBags then pcall(C_Container.SortBags) end
    end)
    sort:SetHeight(20)
    sort:SetPoint("LEFT", search, "RIGHT", 8, 0)

    -- afficher / cacher la rangee des emplacements de sacs
    local slotsBtn = ns.UI.Button(frame, "", 22, function()
        if InCombatLockdown() then ns.Say(L.COMBAT_BLOCKED) return end
        db.showBagSlots = not db.showBagSlots
        layout()
    end)
    slotsBtn:SetSize(22, 20)
    slotsBtn:SetPoint("LEFT", sort, "RIGHT", 4, 0)
    local sIcon = slotsBtn:CreateTexture(nil, "ARTWORK")
    sIcon:SetPoint("TOPLEFT", 2, -1)
    sIcon:SetPoint("BOTTOMRIGHT", -2, 1)
    sIcon:SetTexture(ns.MEDIA .. "menu_bag")
    slotsBtn:HookScript("OnEnter", function(self)
        local t = ns.Tooltip(self, "ANCHOR_RIGHT")
        t:SetText(L.BAGS_SLOTS_TOGGLE)
        t:Show()
    end)
    slotsBtn:HookScript("OnLeave", ns.HideTooltip)

    -- croix securisee : fermer marche aussi en combat
    -- (bouton plat de la charte, ancre au sac lui-meme)
    local close = ns.UI.Button(frame, "x", 18, nil, "SecureHandlerClickTemplate")
    close:SetSize(18, 18)
    close:SetPoint("TOPRIGHT", -3, -3)
    SecureHandlerSetFrameRef(close, "bags", frame)
    close:SetAttribute("_onclick", [[ self:GetFrameRef("bags"):Hide() ]])

    freeText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    freeText:SetPoint("BOTTOMLEFT", 12, 10)
    moneyText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    moneyText:SetPoint("BOTTOMRIGHT", -12, 10)

    frame:SetScript("OnShow", function() layout() end)

    -- bouton d ouverture/fermeture, clique par les touches des sacs
    -- Il doit rester AFFICHE : un raccourci ne clique pas un bouton cache.
    -- On le met hors de l ecran, en 1x1.
    toggleBtn = CreateFrame("Button", "CorpUIBagsToggle", UIParent, "SecureHandlerClickTemplate")
    toggleBtn:SetSize(1, 1)
    toggleBtn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -50, 50)
    toggleBtn:RegisterForClicks("AnyUp", "AnyDown")
    SecureHandlerSetFrameRef(toggleBtn, "bags", frame)
    -- Une touche envoie l appui puis le relachement, ou seulement l un des
    -- deux selon le reglage "action a l appui" : on agit une fois par frappe.
    toggleBtn:SetAttribute("_onclick", [[
        if down then
            self:SetAttribute("sawdown", 1)
        elseif self:GetAttribute("sawdown") then
            self:SetAttribute("sawdown", nil)
            return
        end
        local f = self:GetFrameRef("bags")
        if f:IsShown() then f:Hide() else f:Show() end
    ]])

    -- fermeture : les nouveaux objets ne le sont plus (comme les sacs du jeu)
    frame:SetScript("OnHide", function()
        for _, b in pairs(buttons) do
            if b.isNew then clearNew(b) end
        end
        newCount = 0
    end)

    -- pulsation douce des lueurs (cadre non securise, toujours affiche :
    -- il ne tourne que quand le sac est ouvert)
    local pulse = CreateFrame("Frame", nil, frame)
    local t = 0
    pulse:SetScript("OnUpdate", function(_, dt)
        if newCount == 0 then return end
        t = (t + dt) % 6.2832
        local a = 0.6 + 0.4 * math.sin(t * 2)
        for _, b in pairs(buttons) do
            if b.isNew then b.glow:SetAlpha(a) end
        end
    end)
end

---------------------------------------------------------------------------
-- Activation : touches, sacs de Blizzard (hors combat)
---------------------------------------------------------------------------

local function applyBindings()
    ClearOverrideBindings(owner)
    if not db.enabled then return end
    for _, action in ipairs(BAG_BINDINGS) do
        for _, key in ipairs({ GetBindingKey(action) }) do
            SetOverrideBindingClick(owner, false, key, "CorpUIBagsToggle", "LeftButton")
        end
    end
end

local function apply()
    if InCombatLockdown() then layoutPending = true return end
    applyBindings()
    if db.hideBlizzard or db.blizzardHidden then
        ns.HideBlizzard(BLIZZ, db.enabled and db.hideBlizzard)
        db.blizzardHidden = db.enabled and db.hideBlizzard
    end
    if not db.enabled then frame:Hide() end
end

-- bascule le clic droit de tous les boutons (hors combat : attributs securises)
local function applyContext()
    if InCombatLockdown() then contextPending = true return end
    contextPending = false
    local use = atNPC() and "" or "item"
    for _, b in pairs(buttons) do b:SetAttribute("type2", use) end
end

local CONTEXT_EVENTS = {
    MERCHANT_SHOW = { "merchant", true }, MERCHANT_CLOSED = { "merchant", false },
    BANKFRAME_OPENED = { "bank", true }, BANKFRAME_CLOSED = { "bank", false },
    MAIL_SHOW = { "mail", true }, MAIL_CLOSED = { "mail", false },
    AUCTION_HOUSE_SHOW = { "auction", true }, AUCTION_HOUSE_CLOSED = { "auction", false },
    TRADE_SHOW = { "trade", true }, TRADE_CLOSED = { "trade", false },
}

local function open(show)
    if not db.enabled or InCombatLockdown() then return end
    frame:SetShown(show)
end

---------------------------------------------------------------------------
-- Fenetre d options
---------------------------------------------------------------------------

local win

local function buildWindow()
    win = ns.UI.Window("CorpUIBagsOptions", ns.TITLE .. " - " .. L.MOD_BAGS, nil, 440, 170)
    -- chaque reglage applique lui-meme son effet : pas d onChange commun
    local form = ns.UI.Form(win, -34)
    form:Check(L.BAGS_OPT_ENABLE, function() return db.enabled end, function(v) db.enabled = v apply() end)
    form:Check(L.BAGS_OPT_BLIZZ, function() return db.hideBlizzard end, function(v) db.hideBlizzard = v apply() end)
    form:Gap(4)
    form:Columns(2)
    -- disposition (boutons securises) : refusee en combat, le curseur
    -- revient a la valeur enregistree
    local function number(key, lo, hi)
        return function(v)
            if InCombatLockdown() then ns.Say(L.COMBAT_BLOCKED) return end
            db[key] = math.max(lo, math.min(hi, math.floor(v + 0.5)))
            if frame:IsShown() then layout() end
        end
    end
    form:Number(L.BAGS_COLUMNS, function() return db.columns end, number("columns", 6, 20), 6, 20, 1)
    form:Number(L.BAGS_SIZE, function() return db.size end, number("size", 24, 52), 24, 52, 1)
    form:Number(L.BAGS_SPACING, function() return db.spacing end, number("spacing", 0, 12), 0, 12, 1)
    form:EndColumns()
    form:Gap(4)
    -- affichage seul : rafraichi tout de suite, meme en combat
    local function display(key)
        return function(v)
            db[key] = v
            updateAll()
        end
    end
    form:Columns(2)
    form:Check(L.BAGS_OPT_QUALITY, function() return db.qualityBorder end, display("qualityBorder"))
    form:Check(L.BAGS_OPT_QUALITY_LOW, function() return db.qualityLow end, display("qualityLow"))
    form:Check(L.BAGS_OPT_QUEST, function() return db.questBorder end, display("questBorder"))
    form:Check(L.BAGS_OPT_NEW, function() return db.newGlow end, display("newGlow"))
    form:Check(L.BAGS_OPT_ILVL, function() return db.itemLevel end, display("itemLevel"))
    -- regroupement : change la disposition, donc hors combat (sinon applique
    -- a la sortie du combat)
    form:Check(L.BAGS_OPT_GROUP, function() return db.groupByType end, function(v)
        db.groupByType = v
        if frame:IsShown() then layout() end
    end)
    form:EndColumns()
    -- reglage du jeu (partage avec ses sacs) : trier du dernier sac au premier
    if C_Container and C_Container.GetSortBagsRightToLeft and C_Container.SetSortBagsRightToLeft then
        form:Check(L.BAGS_OPT_SORT_RTL, function()
            local ok, v = pcall(C_Container.GetSortBagsRightToLeft)
            return ok and not issecret(v) and v
        end, function(v)
            pcall(C_Container.SetSortBagsRightToLeft, v and true or false)
        end)
    end
    -- reglages de la fenetre de banque (Banque.lua)
    if ns.BankOptions then ns.BankOptions(form) end
    local openBtn = ns.UI.Button(win, L.BAGS_OPEN, 120, function() open(true) end)
    openBtn:SetPoint("TOPLEFT", win, "TOPLEFT", 8, form.y - 6)
    win:SetHeight(math.floor(40 - form.y))
    win:HookScript("OnShow", function() form:Refresh() end)
end

local function toggle()
    if not win then buildWindow() end
    ns.ShowPanel(win)
end

---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        root.bags = root.bags or {}
        db = root.bags
        if db.enabled == nil then db.enabled = true end
        if db.hideBlizzard == nil then db.hideBlizzard = true end
        if db.showBagSlots == nil then db.showBagSlots = true end
        db.columns = db.columns or 10
        -- nouvelles cles : valeurs par defaut seulement
        db.size = db.size or 36
        db.spacing = db.spacing or 4
        for key, v in pairs({ qualityBorder = true, qualityLow = false, questBorder = true, newGlow = true,
                              itemLevel = true, groupByType = false }) do
            if db[key] == nil then db[key] = v end
        end
        build()
        apply()
    elseif not db then
        return
    elseif event == "BAG_UPDATE_DELAYED" or event == "ITEM_LOCK_CHANGED" or event == "BAG_UPDATE_COOLDOWN"
        or event == "PLAYER_MONEY" then
        if event == "BAG_UPDATE_DELAYED" then layout() else updateAll() end
    elseif event == "UPDATE_BINDINGS" then
        if not InCombatLockdown() then applyBindings() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if layoutPending then apply() layout() end
        if contextPending then applyContext() end
    elseif CONTEXT_EVENTS[event] then
        local c = CONTEXT_EVENTS[event]
        contexts[c[1]] = c[2] or nil
        applyContext()
        open(atNPC())
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN",
                     "PLAYER_MONEY", "UPDATE_BINDINGS", "PLAYER_REGEN_ENABLED", "MERCHANT_SHOW",
                     "MERCHANT_CLOSED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "MAIL_SHOW", "MAIL_CLOSED",
                     "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "TRADE_SHOW", "TRADE_CLOSED" }) do
    pcall(ev.RegisterEvent, ev, e)
end

-- Filet : quand le jeu ouvre ou ferme ses sacs (bouton du sac a dos,
-- marchand...), meme ranges dans le parent cache, on suit. Hors combat
-- seulement (notre sac contient des boutons securises).
local lastBlizz = false
local function blizzOpen()
    for _, name in ipairs(BLIZZ) do
        local f = _G[name]
        if f and f:IsShown() then return true end
    end
    return false
end
local since = 0
ev:SetScript("OnUpdate", function(_, dt)
    since = since + dt
    if since < 0.15 or not db or not db.enabled or not frame then return end
    since = 0
    local open = blizzOpen()
    if open ~= lastBlizz and not InCombatLockdown() then
        lastBlizz = open
        frame:SetShown(open)
    end
end)

-- Partage avec la fenetre de banque (Sacs/Banque.lua)
ns.BagsShared = {
    PAD = PAD, SECTION = SECTION, MIN_WIDTH = MIN_WIDTH,
    DB = function() return db end,
    CreateItemButton = createItemButton,
    UpdateButton = updateButton,
    Section = sectionOf,
    DressWindow = dressWindow,
    ContainerInfo = containerInfo,
    Num = num,
    Query = currentQuery,
    BagsQueryText = function() return search and search:GetText() or nil end,
    -- recherche tapee dans la banque : meme champ que les sacs
    SetQuery = function(text)
        if search and search:GetText() ~= text then search:SetText(text or "") end
    end,
    -- sacs ouverts a cote de la banque
    OpenBags = function() open(true) end,
    BagsFrame = function() return frame end,
}

ns.RegisterModule({
    command = "sacs",
    panelName = "CorpUIBagsOptions",
    icon = "Interface\\Icons\\INV_Misc_Bag_08",
    title = function() return L.MOD_BAGS end,
    desc = function() return L.BAGS_DESC end,
    Slash = function(input)
        if strlower(strtrim(input or "")) == "ouvrir" or strlower(strtrim(input or "")) == "open" then
            open(not frame:IsShown())
        else
            toggle()
        end
    end,
    Open = toggle,
})
