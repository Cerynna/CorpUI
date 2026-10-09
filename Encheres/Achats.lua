--[[--------------------------------------------------------------------------
    CorpUI - module Encheres : onglet Achats du volet (listes d achats)

    Listes d objets a acheter, chacune avec un prix maximum par objet (un
    montant, ou un pourcentage de la valeur marche). Une liste speciale,
    "Courses des metiers", reprend les manques de la file des metiers
    (module Metiers) avec leur quantite.
      - ligne verte : le prix le plus bas connu est sous ton max ;
      - clic : l objet est cherche dans l HV (son nom dans la barre de
        recherche de Blizzard) ; tu cliques sa ligne chez Blizzard pour
        voir les annonces ;
      - a l arrivee des annonces de l objet : combien sont sous ton max et
        ce qu elles coutent (pied de l onglet) ;
      - ajout : glisser un objet sur le champ, ou taper son nom (objets
        deja vus), ou "Objet affiche" (celui que montre Blizzard) ;
        clic droit sur une ligne : la retirer.
    Aucun achat : ce client l interdit aux addons, le clic Acheter reste
    celui de Blizzard.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L
local C = ns.COLORS
local AH = ns.AH

local num, call, field = AH.num, AH.call, AH.field

local PAD = 8
local ROW_H = 34
local CRAFT = "craft"         -- cle de la liste des courses des metiers

---------------------------------------------------------------------------
-- Donnees : db.shop = { lists = { { name, items = { { id, max, pct } } } }, sel }
---------------------------------------------------------------------------

local function shopDB()
    local db = AH.DB()
    if not db then return nil end
    if type(db.shop) ~= "table" then db.shop = {} end
    local s = db.shop
    if type(s.lists) ~= "table" then s.lists = {} end
    if #s.lists == 0 then s.lists[1] = { name = L.BUY_LIST_DEFAULT, items = {} } end
    for _, l in ipairs(s.lists) do
        if type(l.items) ~= "table" then l.items = {} end
        if type(l.name) ~= "string" then l.name = L.BUY_LIST_DEFAULT end
    end
    if s.sel ~= CRAFT and (type(s.sel) ~= "number" or not s.lists[s.sel]) then s.sel = 1 end
    return s
end
AH.ShopDB = shopDB

local function craftOn()
    return ns.Craft and type(ns.Craft.ShoppingList) == "function" and ns.Craft.DB and ns.Craft.DB() ~= nil
end

-- objets de la liste choisie : { id, max, pct, qty, craft }
local function currentItems()
    local s = shopDB()
    if not s then return {} end
    if s.sel == CRAFT then
        local out = {}
        if craftOn() then
            local ok, list = pcall(ns.Craft.ShoppingList)
            for _, it in ipairs(ok and list or {}) do
                if it.state == "buy" and (it.missing or 0) > 0 then out[#out + 1] = { id = it.id, qty = it.missing, craft = true } end
            end
        end
        return out
    end
    return s.lists[s.sel].items
end

-- prix max d une ligne (cuivre) : montant, ou pourcentage de la valeur marche
local function maxOf(it)
    if num(it.max) then return it.max end
    if num(it.pct) then
        local m = ns.AHSource and ns.AHSource(it.id, "market")
        if m then return m * it.pct / 100 end
    end
end
AH.ShopMaxOf = maxOf

local function addItem(id)
    local s = shopDB()
    if not (s and id) then return false end
    if s.sel == CRAFT then ns.Say(L.BUY_CRAFT_RO) return false end
    local items = s.lists[s.sel].items
    for _, it in ipairs(items) do
        if it.id == id then return false end
    end
    items[#items + 1] = { id = id }
    return true
end
AH.ShopAdd = addItem

local function removeItem(id)
    local s = shopDB()
    if not s or s.sel == CRAFT then return end
    local items = s.lists[s.sel].items
    for i, it in ipairs(items) do
        if it.id == id then table.remove(items, i) return end
    end
end

-- objet d apres un texte : lien, numero, ou nom deja vu (cache des noms du
-- module Persos, base de prix et objets des listes)
local function resolve(text)
    text = AH.str(text)
    if not text then return nil end
    local id = tonumber(text:match("item:(%d+)") or text:match("^%s*(%d+)%s*$"))
    if id then return id end
    local name = strtrim(text):gsub("^%[", ""):gsub("%]$", "")
    if name == "" then return nil end
    local info = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if info then
        local okI, iid = pcall(info, name)
        if okI and num(iid) then return iid end
    end
    local low = name:lower()
    local root = ns.InitRoot and ns.InitRoot()
    local names = root and root.itemNames
    if type(names) == "table" then
        for iid, n in pairs(names) do
            if type(n) == "string" and n:lower() == low then return tonumber(iid) end
        end
    end
    return nil
end
AH.ShopResolve = resolve

-- objet que montre la fenetre d achat de Blizzard (fiche ouverte), ou nil
local function shownItem()
    local ahf = ns.AHFrame and ns.AHFrame()
    if not ahf then return nil end
    local cb = field(ahf, "CommoditiesBuyFrame")
    if AH.visible(cb) then
        local id = num(field(field(cb, "ItemList"), "itemID"))
        if id then return id end
    end
    local ib = field(ahf, "ItemBuyFrame")
    if AH.visible(ib) then
        local key = field(ib, "itemKey")
        return type(key) == "table" and num(key.itemID) or nil
    end
end

---------------------------------------------------------------------------
-- Annonces arrivees pour un objet de la liste : combien sous le max
---------------------------------------------------------------------------

local live = {}     -- itemID -> { n, cost, need, needCost, at }
local lastPaint = 0

-- redessin tout de suite (apres un changement)
local function repaint()
    lastPaint = 0
    AH.Refresh("buy")
end

local function readLive(kind, id, key)
    local it
    for _, x in ipairs(currentItems()) do
        if x.id == id then it = x break end
    end
    if not it then return end
    local cap = maxOf(it)
    local ah = AH.api()
    local rows = {}
    if kind == "commodity" then
        local n = num(call(ah.GetNumCommoditySearchResults, id)) or 0
        for i = 1, n do
            local r = call(ah.GetCommoditySearchResultInfo, id, i)
            if type(r) == "table" then
                local u, q, own = num(r.unitPrice), num(r.quantity) or 0, num(r.numOwnerItems) or 0
                if u and q - own > 0 then rows[#rows + 1] = { u, q - own } end
            end
        end
    else
        local n = num(call(ah.GetNumItemSearchResults, key)) or 0
        for i = 1, n do
            local r = call(ah.GetItemSearchResultInfo, key, i)
            if type(r) == "table" and r.containsOwnerItem ~= true then
                local u = num(r.buyoutAmount)
                if u then rows[#rows + 1] = { u, num(r.quantity) or 1 } end
            end
        end
    end
    table.sort(rows, function(a, b) return a[1] < b[1] end)
    local out = { n = 0, cost = 0, at = GetTime(), cap = cap, need = it.qty, needCost = 0, needGot = 0, kind = kind, key = key }
    for _, r in ipairs(rows) do
        if cap and r[1] <= cap + 0.005 then
            out.n, out.cost = out.n + r[2], out.cost + r[1] * r[2]
        end
        if it.qty and out.needGot < it.qty then
            local take = math.min(r[2], it.qty - out.needGot)
            out.needGot, out.needCost = out.needGot + take, out.needCost + take * r[1]
        end
    end
    out.total = #rows
    live[id] = out
    repaint()
end

if ns.AHResultsListen then
    ns.AHResultsListen(function(kind, id, key)
        if kind ~= "browse" and id then readLive(kind, id, key) end
    end)
end

---------------------------------------------------------------------------
-- Onglet
---------------------------------------------------------------------------

local ui = {}

local function plainMoney(c)
    local t = AH.Money(c)
    t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return t
end

local function maxText(it)
    if num(it.pct) then return it.pct .. "%" end
    if num(it.max) then return plainMoney(it.max) end
    return ""
end

local function makeRow(list, i)
    local row = AH.ItemRow(list, ROW_H)
    row.max = ns.UI.EditBox(row, 70, 16)
    row.max:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -2, 2)
    row.max:SetJustifyH("RIGHT")
    local function commit(self)
        local it = row.it
        if not it or it.craft then return end
        local c, pct = AH.ParseMoney(self:GetText())
        if pct then it.pct, it.max = pct, nil
        elseif c then it.max, it.pct = c, nil
        elseif strtrim(self:GetText() or "") == "" then it.max, it.pct = nil, nil end
        -- annonces deja arrivees : recomptees avec le nouveau max
        local lv = live[it.id]
        if lv then readLive(lv.kind, it.id, lv.key) end
        repaint()
    end
    row.max:SetScript("OnEnterPressed", function(self) commit(self) self:ClearFocus() end)
    row.max:HookScript("OnEditFocusLost", commit)
    row.max:HookScript("OnEnter", function(self)
        local t = ns.Tooltip(self, "ANCHOR_TOP")
        t:AddLine(L.BUY_MAX)
        t:AddLine(L.BUY_MAX_TIP, 1, 1, 1, true)
        t:Show()
    end)
    row.max:HookScript("OnLeave", function() ns.HideTooltip() end)
    row.sub:ClearAllPoints()
    row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 7, -1)
    row.sub:SetPoint("RIGHT", row.max, "LEFT", -4, 0)
    row:SetScript("OnClick", function(self, button)
        local it = self.it
        if not it then return end
        if button == "RightButton" then
            if not it.craft then
                removeItem(it.id)
                repaint()
            end
        else
            AH.Search(it.id)
        end
    end)
    row:SetScript("OnEnter", function(self)
        local it = self.it
        if not it then return end
        local extra = { { L.BUY_TIP_CLICK, 0.7, 0.7, 0.7 } }
        if not it.craft then extra[#extra + 1] = { L.BUY_TIP_REMOVE, 0.7, 0.7, 0.7 } end
        AH.ItemTip(self, it.id, extra)
    end)
    return row
end

local function fillRow(row, it, i)
    row.it = it
    row.stripe:SetShown(i % 2 == 0)
    row.icon:SetTexture(ns.ItemIcon(it.id))
    row.name:SetText(AH.QualityHex(it.id) .. AH.ItemLabel(it.id) .. "|r" .. (it.qty and ("|cffffffff x" .. it.qty .. "|r") or ""))
    local v = ns.AHValues and ns.AHValues(it.id)
    local cap = maxOf(it)
    if v then
        local col = "|cffffffff"
        if cap then col = (v.min <= cap + 0.005) and "|cff6be070" or "|cffff6060" end
        row.right:SetText(col .. AH.Money(v.min) .. "|r")
    else
        row.right:SetText("|cff9d9d9d?|r")
    end
    local lv = live[it.id]
    local sub
    if lv and lv.cap then
        sub = string.format(L.BUY_UNDER_MAX, lv.n)
    elseif lv and lv.need then
        sub = string.format(L.BUY_NEED_COST, AH.Money(lv.needCost), lv.needGot)
    elseif v then
        sub = string.format(L.BUY_SEEN, ns.FormatAgo(v.seen))
    else
        sub = L.BUY_UNKNOWN
    end
    row.sub:SetText(sub)
    if it.craft then
        row.max:Hide()
    else
        row.max:Show()
        if not row.max:HasFocus() then row.max:SetText(maxText(it)) end
    end
end

local function listOptions()
    local s = shopDB()
    local out = {}
    for i, l in ipairs(s and s.lists or {}) do out[#out + 1] = { value = i, text = l.name .. " (" .. #l.items .. ")" } end
    if craftOn() then out[#out + 1] = { value = CRAFT, text = L.BUY_LIST_CRAFT } end
    return out
end

local function addFromBox()
    local id = resolve(ui.add:GetText())
    if not id then ns.Say(L.BUY_NOT_FOUND) return end
    addItem(id)
    ui.add:SetText("")
    ui.add:ClearFocus()
    repaint()
end

local function dropCursor()
    local kind, id = call(GetCursorInfo)
    if kind == "item" and num(id) then
        addItem(id)
        call(ClearCursor)
        repaint()
        return true
    end
end

local function build(page)
    ui.page = page
    ui.sel = ns.UI.Select(page, 160, listOptions, function() local s = shopDB() return s and s.sel end, function(v)
        local s = shopDB()
        if s then s.sel = v end
        repaint()
    end)
    ui.sel:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, -6)
    ui.new = ns.UI.Button(page, L.BUY_NEW, 60, function()
        local s = shopDB()
        if not s then return end
        s.lists[#s.lists + 1] = { name = string.format(L.BUY_LIST_N, #s.lists + 1), items = {} }
        s.sel = #s.lists
        repaint()
    end)
    ui.new:SetPoint("LEFT", ui.sel, "RIGHT", 4, 0)
    ui.del = ns.UI.Button(page, L.BUY_DELETE, 60, function(self)
        local s = shopDB()
        if not s or s.sel == CRAFT then return end
        if not self.armed then
            self.armed = true
            self:SetText(L.AH_SURE)
            C_Timer.After(3, function() if self.armed then self.armed = nil self:SetText(L.BUY_DELETE) end end)
            return
        end
        self.armed = nil
        self:SetText(L.BUY_DELETE)
        table.remove(s.lists, s.sel)
        s.sel = 1
        shopDB()
        repaint()
    end)
    ui.del:SetPoint("LEFT", ui.new, "RIGHT", 4, 0)
    -- nom de la liste (modifiable)
    ui.name = ns.UI.EditBox(page, 150, 18)
    ui.name:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, -32)
    local function rename(self)
        local s = shopDB()
        local t = strtrim(self:GetText() or "")
        if s and s.sel ~= CRAFT and t ~= "" then s.lists[s.sel].name = t end
        ui.sel:Refresh()
    end
    ui.name:SetScript("OnEnterPressed", function(self) rename(self) self:ClearFocus() end)
    ui.name:HookScript("OnEditFocusLost", rename)
    ui.nameLabel = AH.Text(page, "GameFontDisableSmall", "LEFT")
    ui.nameLabel:SetPoint("LEFT", ui.name, "RIGHT", 6, 0)
    ui.nameLabel:SetText(L.BUY_NAME)
    -- ajout : nom, lien, ou objet glisse
    ui.add = ns.UI.EditBox(page, 150, 18)
    ui.add:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, -56)
    ui.addHint = AH.Text(ui.add, "GameFontDisableSmall", "LEFT")
    ui.addHint:SetPoint("LEFT", 6, 0)
    ui.addHint:SetPoint("RIGHT", -6, 0)
    ui.addHint:SetText(L.BUY_ADD_HINT)
    ui.add:SetScript("OnEnterPressed", addFromBox)
    ui.add:HookScript("OnTextChanged", function(self) ui.addHint:SetShown((self:GetText() or "") == "" and not self:HasFocus()) end)
    ui.add:HookScript("OnEditFocusGained", function() ui.addHint:Hide() end)
    ui.add:HookScript("OnEditFocusLost", function(self) ui.addHint:SetShown((self:GetText() or "") == "") end)
    ui.add:SetScript("OnReceiveDrag", dropCursor)
    ui.add:HookScript("OnMouseDown", function() dropCursor() end)
    ui.addBtn = ns.UI.Button(page, L.BUY_ADD, 60, addFromBox)
    ui.addBtn:SetPoint("LEFT", ui.add, "RIGHT", 4, 0)
    ui.shown = ns.UI.Button(page, L.BUY_SHOWN, 60, function()
        local id = shownItem()
        if not id then ns.Say(L.BUY_NO_SHOWN) return end
        addItem(id)
        repaint()
    end)
    ui.shown:SetPoint("LEFT", ui.addBtn, "RIGHT", 4, 0)
    ui.shown:HookScript("OnEnter", function(self)
        local t = ns.Tooltip(self, "ANCHOR_TOP")
        t:AddLine(L.BUY_SHOWN)
        t:AddLine(L.BUY_SHOWN_TIP, 1, 1, 1, true)
        t:Show()
    end)
    ui.shown:HookScript("OnLeave", function() ns.HideTooltip() end)
    ui.list = AH.List(page, ROW_H, makeRow, fillRow)
    ui.list:SetPoint("TOPLEFT", page, "TOPLEFT", PAD - 2, -82)
    ui.list:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -PAD + 2, 60)
    ui.empty = AH.Text(page, "GameFontDisableSmall", "LEFT")
    ui.empty:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, -90)
    ui.empty:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
    ui.empty:SetHeight(40)
    ui.empty:SetWordWrap(true)
    ui.empty:SetJustifyV("TOP")
    ui.foot = AH.Text(page, "GameFontHighlightSmall", "LEFT")
    ui.foot:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", PAD, 36)
    ui.foot:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
    ui.hint = AH.Text(page, "GameFontDisableSmall", "LEFT")
    ui.hint:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", PAD, 6)
    ui.hint:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
    ui.hint:SetHeight(28)
    ui.hint:SetWordWrap(true)
    ui.hint:SetJustifyV("BOTTOM")
    ui.hint:SetText(L.BUY_HINT)
end

local function refresh(page, force)
    if not ui.page then return end
    local now = GetTime()
    if not force and now - lastPaint < 1 then return end
    lastPaint = now
    local s = shopDB()
    if not s then return end
    ui.sel:Refresh()
    local craft = s.sel == CRAFT
    if not ui.name:HasFocus() then ui.name:SetText(craft and L.BUY_LIST_CRAFT or s.lists[s.sel].name) end
    ui.name:SetEnabled(not craft)
    ui.del:SetEnabled(not craft and #s.lists > 1)
    ui.add:SetEnabled(not craft)
    ui.addBtn:SetEnabled(not craft)
    ui.shown:SetEnabled(not craft)
    local items = currentItems()
    ui.list:SetData(items)
    ui.empty:SetText(craft and L.BUY_CRAFT_EMPTY or L.BUY_EMPTY)
    ui.empty:SetShown(#items == 0)
    -- pied : l objet dont les annonces viennent d arriver
    local best, bestAt
    for _, it in ipairs(items) do
        local lv = live[it.id]
        if lv and (not bestAt or lv.at > bestAt) then best, bestAt = it, lv.at end
    end
    if best then
        local lv = live[best.id]
        local name = AH.ItemLabel(best.id)
        if lv.cap then
            if lv.n > 0 then
                ui.foot:SetText(string.format(L.BUY_FOOT, name, lv.n, AH.Money(lv.cost), AH.Money(lv.cost / lv.n)))
            else
                ui.foot:SetText(string.format(L.BUY_FOOT_NONE, name, AH.Money(lv.cap)))
            end
        elseif lv.need then
            ui.foot:SetText(string.format(L.BUY_FOOT_NEED, name, lv.needGot, AH.Money(lv.needCost)))
        else
            ui.foot:SetText("")
        end
    else
        ui.foot:SetText("")
    end
end

AH.AddTab({ key = "buy", order = 3, label = function() return L.AHP_TAB_BUY end, build = build,
            refresh = refresh, show = function(p) refresh(p, true) end })

-- banc d essai
AH._buy = { live = live, read = readLive, items = currentItems }
