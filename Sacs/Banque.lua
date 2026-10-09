--[[--------------------------------------------------------------------------
    CorpUI - module Sacs : fenetre de banque

    Banque de ce client (variante Camelot du code de Blizzard, branche
    forever) : banque moderne a "onglets" (C_Bank), ou chaque onglet est un
    conteneur : Enum.BagIndex.CharacterBankTab_1 (6, la banque de base,
    28 places, offerte au premier passage) puis CharacterBankTab_2.. (7..14)
    = les sacs de banque. Les sacs eux-memes sont des objets ranges dans le
    conteneur Enum.BagIndex.Characterbanktab (-2), place n = onglet n.
    (Ici -1 est le trousseau de cles, pas la banque.)

    Fenetre a nous, memes boutons que les sacs (ns.BagsShared) mais NON
    securises : aucune contrainte de combat sur la fenetre.
      clic droit        : ranger l objet dans les sacs (UseContainerItem)
      clic gauche       : prendre / poser ; Maj + clic : lien
      rangee des sacs   : clic = afficher / masquer ce sac dans la vue,
                          glisser = prendre le sac, deposer = poser un sac
      Acheter           : bouton du modele de Blizzard pour les addons
                          (BankPanelPurchaseButtonScriptTemplate) : la
                          confirmation et l achat sont faits par Blizzard
      Trier             : C_Container.SortBank (type de banque du perso)
    La fenetre de Blizzard reste OUVERTE (elle tient la session de banque
    et ses evenements) mais invisible : transparence 0 et echelle minuscule
    (rien d ecrit dans ses tables, aucun crochet). Sa fermeture (Echap,
    eloignement) donne BANKFRAME_CLOSED, qui ferme la notre ; notre croix
    appelle C_Bank.CloseBankFrame.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local issecret = issecretvalue or function() return false end
local S          -- ns.BagsShared (Sacs.lua)

local HEAD = 24        -- bandeau
local TOP = 54         -- sous la recherche
local FOOT = 30
local BAGSLOT = 30     -- emplacements de sacs
local TINY = 0.001     -- echelle de la fenetre de Blizzard cachee

local db
local frame, search, freeText, moneyText, costText, buyBtn
local buttons = {}     -- "sac:place" -> bouton
local bagSlots = {}    -- emplacements de sacs de banque (onglets 2..max)
local sections = {}
local bankOpen = false
local blizzWanted = false   -- "Blizzard" : fenetre du jeu jusqu a la fermeture
local hoverTab              -- conteneur survole dans la rangee des sacs
local pending = false
local confirmAt             -- achat : premier clic

local function charType() return Enum and Enum.BankType and Enum.BankType.Character end

local function bagHolder()
    return (Enum and Enum.BagIndex and Enum.BagIndex.Characterbanktab) or -2
end

-- appel protege a C_Bank (nil si absent ou en erreur)
local function bank(fn, ...)
    local f = C_Bank and C_Bank[fn]
    if not f then return nil end
    local ok, a, b = pcall(f, ...)
    if ok then return a, b end
end

local function enabled() return db and db.bankEnabled end

local function gstr(name, fallback)
    local v = _G[name]
    if type(v) == "string" and v ~= "" and not issecret(v) then return v end
    return fallback
end

---------------------------------------------------------------------------
-- Onglets (conteneurs) de la banque du personnage
---------------------------------------------------------------------------

-- { { id = conteneur, index = n, name = } } dans l ordre des onglets
local function purchasedTabs()
    local list = {}
    local bt = charType()
    if C_Bank and bt ~= nil then
        local data = bank("FetchPurchasedBankTabData", bt)
        if type(data) == "table" then
            for i, t in ipairs(data) do
                local id = S.Num(t.ID)
                if id then
                    local name = t.name
                    if issecret(name) or type(name) ~= "string" then name = nil end
                    list[#list + 1] = { id = id, index = i, name = name }
                end
            end
            return list
        end
        local ids = bank("FetchPurchasedBankTabIDs", bt)
        if type(ids) == "table" then
            for i, id in ipairs(ids) do
                id = S.Num(id)
                if id then list[#list + 1] = { id = id, index = i } end
            end
            return list
        end
    end
    -- ancienne banque (sans C_Bank) : conteneur -1 puis les sacs de banque
    if not C_Bank then
        list[1] = { id = BANK_CONTAINER or -1, index = 1 }
        local first = ns.FirstBankBag()
        for i = 1, (NUM_BANKBAGSLOTS or 0) do
            list[#list + 1] = { id = first + i - 1, index = i + 1 }
        end
    end
    return list
end

local function maxTabs(nBought)
    local m = S.Num(bank("FetchMaxNumBankTabs", charType()))
    return math.max(m or 0, nBought)
end

-- la banque range des sacs dans ses onglets (sinon : onglets simples)
local function usesBags()
    if not C_Bank then return true end
    local v = bank("ShouldUsePlayerBagsInBank")
    if v == nil or issecret(v) then return true end
    return v and true or false
end

local function tabName(tab)
    if tab.index == 1 then return gstr("BANK", L.BANK_TITLE) end
    local fn = C_Container and C_Container.GetBagName
    if fn then
        local ok, n = pcall(fn, tab.id)
        if ok and type(n) == "string" and not issecret(n) and n ~= "" then return n end
    end
    return tab.name or gstr("BANK_BAG", L.BANK_BAGSLOTS)
end

-- prochain emplacement achetable : cout, peut payer (nil si aucun)
local function nextPurchase()
    local bt = charType()
    if bt == nil or not C_Bank then return nil end
    if bank("HasMaxBankTabs", bt) then return nil end
    local data = bank("FetchNextPurchasableBankTabData", bt)
    if type(data) ~= "table" then return nil end
    local cost = S.Num(data.tabCost)
    if not cost then return nil end
    local afford = data.canAfford
    if issecret(afford) then afford = nil end
    if afford == nil then afford = GetMoney() >= cost end
    return cost, afford and true or false
end

---------------------------------------------------------------------------
-- Fenetre de Blizzard : invisible mais ouverte
---------------------------------------------------------------------------

local saved
local function blizzBank(hide)
    local f = BankFrame
    if type(f) ~= "table" or not f.SetScale or not f.SetAlpha then return end
    if hide then
        local okP, prot = pcall(f.IsProtected, f)
        if okP and prot and InCombatLockdown() then return end
        if not saved then
            local okS, sc = pcall(f.GetScale, f)
            local okA, al = pcall(f.GetAlpha, f)
            saved = { scale = (okS and S.Num(sc)) or 1, alpha = (okA and S.Num(al)) or 1 }
            if saved.scale <= TINY then saved.scale = 1 end
        end
        pcall(f.SetAlpha, f, 0)
        pcall(f.SetScale, f, TINY)
    elseif saved then
        local okP, prot = pcall(f.IsProtected, f)
        if okP and prot and InCombatLockdown() then return end
        pcall(f.SetScale, f, saved.scale)
        pcall(f.SetAlpha, f, saved.alpha)
        saved = nil
    end
end

local function closeBank()
    if frame then frame:Hide() end
    local fn = (C_Bank and C_Bank.CloseBankFrame) or CloseBankFrame
    if fn then pcall(fn) end
end

---------------------------------------------------------------------------
-- Mise a jour
---------------------------------------------------------------------------

local function refreshBagSlot(s)
    local holder = bagHolder()
    local info = s.purchased and S.ContainerInfo(holder, s.index) or nil
    s.hasBag = info and true or false
    s.icon:SetTexture(info and info.iconFileID or nil)
    local hidden = db.bankHidden[s.index]
    s.icon:SetDesaturated(hidden and true or false)
    s.icon:SetAlpha(hidden and 0.4 or 1)
    s.lock:SetShown(not s.purchased)
    s.dim:SetShown(not s.purchased)
    s.next:SetShown(s.isNext and true or false)
end

local function refreshCost()
    local cost, afford = nextPurchase()
    if not cost then
        costText:Hide()
        buyBtn:Hide()
        return
    end
    local money = ns.FormatMoney(cost)
    if not afford then money = "|cffff4040" .. money:gsub("|r", "|r|cffff4040") .. "|r" end
    costText:SetText(gstr("COSTS_LABEL", L.BANK_COST) .. " " .. money)
    costText:Show()
    buyBtn:Show()
    buyBtn:SetEnabled(afford)
    if not confirmAt then buyBtn:SetText(gstr("BANKSLOTPURCHASE", L.BANK_BUY)) end
end

local function updateAll()
    if not frame or not frame:IsShown() then return end
    local q = strlower(strtrim(search:GetText() or ""))
    local free, total = 0, 0
    for _, b in pairs(buttons) do
        if b:IsShown() then
            S.UpdateButton(b, q, true)
            total = total + 1
            if not b.link then free = free + 1 end
            -- survol d un sac : ses objets ressortent
            if hoverTab and b.bag ~= hoverTab then b.icon:SetAlpha(0.2) end
        end
    end
    freeText:SetText(string.format(L.BAGS_FREE, free, total))
    moneyText:SetText(ns.FormatMoney(GetMoney()))
    for _, s in ipairs(bagSlots) do
        if s:IsShown() then refreshBagSlot(s) end
    end
    refreshCost()
end

---------------------------------------------------------------------------
-- Emplacements de sacs de banque
---------------------------------------------------------------------------

local function bagSlotAt(i)
    local s = bagSlots[i]
    if s then return s end
    local C = ns.COLORS
    s = CreateFrame("Button", nil, frame)
    s:SetSize(BAGSLOT, BAGSLOT)
    s:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    s:RegisterForDrag("LeftButton")
    local edge = s:CreateTexture(nil, "BACKGROUND")
    edge:SetPoint("TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", 1, -1)
    edge:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
    local bg = s:CreateTexture(nil, "BORDER")
    bg:SetAllPoints()
    bg:SetColorTexture(0.12, 0.12, 0.14, 1)
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetPoint("TOPLEFT", 1, -1)
    s.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    s.dim = s:CreateTexture(nil, "OVERLAY")
    s.dim:SetAllPoints()
    s.dim:SetColorTexture(0, 0, 0, 0.55)
    s.lock = s:CreateTexture(nil, "OVERLAY", nil, 1)
    s.lock:SetPoint("CENTER")
    s.lock:SetSize(BAGSLOT - 10, BAGSLOT - 10)
    if not pcall(s.lock.SetAtlas, s.lock, "bankslot-icon-lock") then
        s.lock:SetTexture("Interface\\PetBattles\\PetBattle-LockIcon")
    end
    -- le prochain emplacement achetable : liseré d or
    s.next = s:CreateTexture(nil, "BACKGROUND", nil, 1)
    s.next:SetPoint("TOPLEFT", -1, 1)
    s.next:SetPoint("BOTTOMRIGHT", 1, -1)
    s.next:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.9)
    s.next:Hide()
    local hl = s:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.2)

    s:SetScript("OnClick", function(self)
        if not self.purchased then return end
        -- un objet (sac) sur le curseur : le poser ici
        if CursorHasItem and CursorHasItem() then
            if not InCombatLockdown() then pcall(C_Container.PickupContainerItem, bagHolder(), self.index) end
            return
        end
        db.bankHidden[self.index] = (not db.bankHidden[self.index]) or nil
        ns.BankLayout()
    end)
    s:SetScript("OnDragStart", function(self)
        if not self.purchased or InCombatLockdown() then return end
        pcall(C_Container.PickupContainerItem, bagHolder(), self.index)
    end)
    s:SetScript("OnReceiveDrag", function(self)
        if not self.purchased or InCombatLockdown() then return end
        pcall(C_Container.PickupContainerItem, bagHolder(), self.index)
    end)
    s:SetScript("OnEnter", function(self)
        local t = ns.Tooltip(self, "ANCHOR_RIGHT")
        if self.purchased then
            if not (self.hasBag and pcall(t.SetBagItem, t, bagHolder(), self.index)) then
                t:SetText(L.BANK_BAG_EMPTY)
            end
            t:AddLine(L.BANK_BAG_HINT, 0.7, 0.7, 0.7, true)
            hoverTab = self.tabID
            updateAll()
        else
            t:SetText(gstr("BANK_BAG_PURCHASE", L.BANK_BAG_LOCKED))
            local cost = nextPurchase()
            if self.isNext and cost then
                t:AddLine(gstr("COSTS_LABEL", L.BANK_COST) .. " " .. ns.FormatMoney(cost), 1, 1, 1)
            end
        end
        t:Show()
    end)
    s:SetScript("OnLeave", function()
        ns.HideTooltip()
        if hoverTab then
            hoverTab = nil
            updateAll()
        end
    end)
    bagSlots[i] = s
    return s
end

---------------------------------------------------------------------------
-- Disposition (boutons non securises : possible en combat)
---------------------------------------------------------------------------

local function layout()
    if not frame or not frame:IsShown() then return end
    local PAD = S.PAD
    local size = db.bankSameSize and db.size or db.bankSize
    local gap, cols = db.spacing, db.bankColumns
    local step = size + gap
    local tabs = purchasedTabs()
    local nTabs = maxTabs(#tabs)
    local used = {}
    local y = TOP
    local nsec = 0
    local function header(text)
        nsec = nsec + 1
        local s = S.Section(frame, sections, nsec)
        s.title:SetText(text)
        s.title:ClearAllPoints()
        s.title:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(y + 4))
        s.title:Show()
        s.line:Show()
        y = y + S.SECTION
    end

    -- rangee des emplacements de sacs (onglets 2..max)
    local nBag = 0
    local rowW = 0
    local tabByIndex = {}
    for _, t in ipairs(tabs) do tabByIndex[t.index] = t end
    if usesBags() and nTabs > 1 and db.bankShowSlots ~= false then
        header(gstr("BAGSLOTTEXT", L.BANK_BAGSLOTS))
        for i = 2, nTabs do
            nBag = nBag + 1
            local s = bagSlotAt(nBag)
            s.index = i
            s.purchased = tabByIndex[i] ~= nil
            s.isNext = (i == #tabs + 1)
            s.tabID = tabByIndex[i] and tabByIndex[i].id
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 1 + (nBag - 1) * (BAGSLOT + 5), -(y + 1))
            s:Show()
        end
        rowW = nBag * (BAGSLOT + 5)
        -- cout et achat, sur la meme ligne, a droite
        buyBtn:ClearAllPoints()
        buyBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(y + 4))
        y = y + BAGSLOT + 8
    else
        -- pas de rangee de sacs : l achat a sa propre ligne
        buyBtn:ClearAllPoints()
        buyBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(y + 2))
        if nextPurchase() then y = y + 28 else y = y + 6 end
    end
    for i = nBag + 1, #bagSlots do bagSlots[i]:Hide() end

    -- contenu : une seule grille continue, tous les onglets affiches a la
    -- suite (un seul titre)
    local shown = {}
    for _, t in ipairs(tabs) do
        if not db.bankHidden[t.index] and ns.BagSlots(t.id) > 0 then shown[#shown + 1] = t end
    end
    if #shown > 0 and nBag > 0 then header(gstr("BANK", L.BANK_TITLE or "Bank")) end
    local n = 0
    for _, t in ipairs(shown) do
        for slot = 1, ns.BagSlots(t.id) do
            local key = t.id .. ":" .. slot
            local b = buttons[key]
            if not b then
                b = S.CreateItemButton(frame, t.id, slot, false, "CorpUIBank" .. t.id .. "Slot" .. slot, size)
                b.isBank = true
                b.tipAnchor = "ANCHOR_RIGHT"
                buttons[key] = b
            end
            used[key] = true
            local col, row = n % cols, math.floor(n / cols)
            b:SetSize(size, size)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + col * step, -(y + row * step))
            b:Show()
            n = n + 1
        end
    end
    y = y + math.max(1, math.ceil(n / cols)) * step

    for i = nsec + 1, #sections do
        sections[i].title:Hide()
        sections[i].line:Hide()
    end
    for key, b in pairs(buttons) do
        if not used[key] then b:Hide() end
    end
    local w = math.max(S.MIN_WIDTH, PAD * 2 + cols * size + (cols - 1) * gap, PAD * 2 + rowW + 230)
    frame:SetSize(w, y - gap + FOOT)
    updateAll()
end

local function schedule()
    if pending then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        layout()
    end)
end
ns.BankLayout = layout

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

local function build()
    frame = CreateFrame("Frame", "CorpUIBank", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("HIGH")
    frame:SetSize(400, 300)
    ns.ApplyPos(frame, db.bankPos)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        ns.PinTop(self, db.bankPos, true)
    end)
    frame:Hide()
    S.DressWindow(frame, gstr("BANK", L.BANK_TITLE), HEAD)

    -- meme recherche que les sacs : ce qu on tape ici part dans leur champ
    search = ns.UI.SearchBox(frame, 140, function(text, userInput)
        if userInput then S.SetQuery(text) end
        updateAll()
    end)
    search:SetPoint("TOPLEFT", 14, -30)

    local sort = ns.UI.Button(frame, L.BAGS_SORT, 60, function()
        local bt = charType()
        if C_Container and C_Container.SortBank and bt ~= nil then
            pcall(C_Container.SortBank, bt)
        elseif C_Container and C_Container.SortBankBags then
            pcall(C_Container.SortBankBags)
        end
    end)
    sort:SetHeight(20)
    sort:SetPoint("LEFT", search, "RIGHT", 8, 0)

    -- afficher / cacher la rangee des emplacements de sacs
    local slotsBtn = ns.UI.Button(frame, "", 22, function()
        db.bankShowSlots = db.bankShowSlots == false
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
    sort:HookScript("OnEnter", function(self)
        local t = ns.Tooltip(self, "ANCHOR_RIGHT")
        t:SetText(gstr("BAG_CLEANUP_BANK", L.BAGS_SORT))
        t:Show()
    end)
    sort:HookScript("OnLeave", ns.HideTooltip)

    local close = ns.UI.Button(frame, "x", 18, closeBank)
    close:SetSize(18, 18)
    close:SetPoint("TOPRIGHT", -3, -3)

    -- achat d un emplacement : C_Bank.PurchaseBankTab est reserve a
    -- l interface de Blizzard (« CorpUI a ete bloque »). Le modele prevu
    -- pour les addons ouvre la confirmation de Blizzard, qui achete elle-meme.
    local okT = pcall(function()
        buyBtn = ns.UI.Button(frame, gstr("BANKSLOTPURCHASE", L.BANK_BUY), 70, nil, "BankPanelPurchaseButtonScriptTemplate")
    end)
    if not okT or not buyBtn then
        buyBtn = ns.UI.Button(frame, gstr("BANKSLOTPURCHASE", L.BANK_BUY), 70)
        buyBtn:Disable()
    end
    local bt = charType()
    if bt ~= nil then buyBtn:SetAttribute("overrideBankType", bt) end
    buyBtn:SetHeight(20)
    buyBtn:Hide()
    costText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    costText:SetPoint("RIGHT", buyBtn, "LEFT", -6, 0)
    costText:Hide()

    freeText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    freeText:SetPoint("BOTTOMLEFT", 12, 10)
    moneyText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    moneyText:SetPoint("BOTTOMRIGHT", -12, 10)

    frame:SetScript("OnShow", function()
        local q = S.BagsQueryText and S.BagsQueryText()
        if q and search:GetText() ~= q then search:SetText(q) end
        layout()
    end)
    frame:SetScript("OnHide", function()
        hoverTab, confirmAt = nil, nil
    end)
end

-- les sacs ont change de recherche : on suit
function ns.BankSearchChanged(text)
    if not search then return end
    if search:GetText() ~= text then search:SetText(text) end
    updateAll()
end

---------------------------------------------------------------------------
-- Ouverture / fermeture
---------------------------------------------------------------------------

local function showBank()
    if not enabled() or not bankOpen or blizzWanted then return end
    if not frame then build() end
    blizzBank(true)
    frame:Show()
    layout()
end

-- reglage change : appliquer tout de suite
local function apply()
    if enabled() then
        if bankOpen then showBank() end
    else
        if frame then frame:Hide() end
        blizzBank(false)
    end
end

---------------------------------------------------------------------------
-- Options (dans le panneau du module Sacs)
---------------------------------------------------------------------------

function ns.BankOptions(form)
    if not db then return end
    form:Header(gstr("BANK", L.BANK_TITLE))
    form:Check(L.BANK_OPT_ENABLE, function() return db.bankEnabled end, function(v)
        db.bankEnabled = v and true or false
        apply()
    end)
    form:Check(L.BANK_OPT_SAME_SIZE, function() return db.bankSameSize end, function(v)
        db.bankSameSize = v and true or false
        schedule()
    end)
    form:Columns(2)
    form:Number(L.BANK_COLUMNS, function() return db.bankColumns end, function(v)
        db.bankColumns = math.max(6, math.min(24, math.floor(v + 0.5)))
        schedule()
    end, 6, 24, 1)
    form:Number(L.BANK_SIZE, function() return db.bankSize end, function(v)
        db.bankSize = math.max(24, math.min(52, math.floor(v + 0.5)))
        schedule()
    end, 24, 52, 1)
    form:EndColumns()
    form:Gap(4)
end

---------------------------------------------------------------------------

local REFRESH = { BAG_UPDATE_DELAYED = true, PLAYERBANKSLOTS_CHANGED = true, BANK_TABS_CHANGED = true,
                  BAG_CONTAINER_UPDATE = true, BAG_UPDATE = true }
local LIGHT = { ITEM_LOCK_CHANGED = true, BAG_UPDATE_COOLDOWN = true, PLAYER_MONEY = true }

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        S = ns.BagsShared
        local root = ns.InitRoot()
        root.bags = root.bags or {}
        db = root.bags
        if db.bankEnabled == nil then db.bankEnabled = true end
        if db.bankSameSize == nil then db.bankSameSize = true end
        db.bankColumns = db.bankColumns or 14
        db.bankSize = db.bankSize or 36
        if type(db.bankHidden) ~= "table" then db.bankHidden = {} end
        db.bankPos = db.bankPos or { point = "TOPLEFT", x = 20, y = -110 }
        return
    end
    if not db or not S then return end
    if event == "BANKFRAME_OPENED" then
        bankOpen, blizzWanted = true, false
        if not enabled() then blizzBank(false) return end
        showBank()
        -- la fenetre de Blizzard s affiche juste apres et achete l onglet
        -- de base (gratuit) : on repasse une fois
        C_Timer.After(0.2, function()
            if bankOpen and enabled() and not blizzWanted then
                blizzBank(true)
                schedule()
            end
        end)
    elseif event == "BANKFRAME_CLOSED" then
        bankOpen, blizzWanted = false, false
        if frame then frame:Hide() end
        -- la fenetre de Blizzard reste reduite tant que la banque CorpUI
        -- est active (elle est fermee a cet instant)
        if enabled() then blizzBank(true) end
    elseif REFRESH[event] then
        if frame and frame:IsShown() then schedule() end
    elseif LIGHT[event] then
        updateAll()
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "BAG_UPDATE_DELAYED", "BAG_UPDATE",
                     "PLAYERBANKSLOTS_CHANGED", "BANK_TABS_CHANGED", "BAG_CONTAINER_UPDATE", "ITEM_LOCK_CHANGED",
                     "BAG_UPDATE_COOLDOWN", "PLAYER_MONEY" }) do
    pcall(ev.RegisterEvent, ev, e)
end

-- filet : notre fenetre ne reste jamais ouverte hors de la banque
local since = 0
ev:SetScript("OnUpdate", function(_, dt)
    since = since + dt
    if since < 0.5 then return end
    since = 0
    if frame and frame:IsShown() and not bankOpen then frame:Hide() end
end)
