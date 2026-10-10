--[[--------------------------------------------------------------------------
    CorpUI - module Reactifs
    Pour chaque personnage, une quantite visee par composant de sort.
      - alerte dans le chat quand un composant passe sous le quart de la
        quantite visee (une fois par session et par composant)
      - achat automatique du complement chez un marchand qui le vend
    Les quantites se reglent dans le panneau Marchand, section Reactifs
    (/corp reactifs l ouvre) ; 0 = ignore. Le module n a plus de panneau :
    il fournit sa section (ns.ReagentsOptions), Marchand.lua l empile.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

-- itemID -> quantite visee par defaut, par classe
local DEFAULTS = {
    PALADIN = { { 21177, 100 } },                               -- Symbole des rois
    PRIEST  = { { 17029, 20 }, { 17028, 0 } },                  -- Bougie sacree, sainte
    MAGE    = { { 17020, 40 }, { 17031, 10 }, { 17032, 5 } },   -- Poudre arcanique, runes
    DRUID   = { { 17021, 20 }, { 17026, 20 },                   -- Baies, racine-epine
                { 17034, 0 }, { 17035, 0 }, { 17036, 0 }, { 17037, 0 }, { 17038, 0 } },  -- graines (Renaissance)
    ROGUE   = { { 5140, 20 }, { 5530, 20 } },                   -- Poudre eclipsante, aveuglante
    SHAMAN  = { { 17030, 5 } },                                 -- Ankh
    WARLOCK = { { 5565, 0 }, { 16583, 0 } },                    -- Pierre infernale, figurine
}

local ALERT_RATIO = 0.25

local db          -- CorpUIDB.reagents
local alerted = {}
local boughtAt = {}   -- id -> heure d achat : pas d alerte le temps que les objets arrivent

local function myClass()
    local _, c = UnitClass("player")
    return c
end

-- Quantites visees du personnage, creees depuis les defauts de sa classe
local function targets()
    local key = ns.CharKey()
    if not db.targets[key] then
        local t = {}
        for _, d in ipairs(DEFAULTS[myClass()] or {}) do t[d[1]] = d[2] end
        db.targets[key] = t
    end
    return db.targets[key]
end

local function itemList()
    local list = {}
    for _, d in ipairs(DEFAULTS[myClass()] or {}) do table.insert(list, d[1]) end
    return list
end

-- Nom de l objet ; s il n est pas encore en cache, on le demande au client
-- (GET_ITEM_INFO_RECEIVED rafraichit ensuite le panneau)
local function itemLabel(id)
    local name = ns.ItemName(id)
    if name then return name end
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return "item:" .. id
end

---------------------------------------------------------------------------
-- Alertes
---------------------------------------------------------------------------

local function checkLow()
    if not db.alert then return end
    local t = targets()
    for _, id in ipairs(itemList()) do
        local want = t[id] or 0
        local recent = boughtAt[id] and (GetTime() - boughtAt[id]) < 5
        if want > 0 and not recent then
            local have = ns.ItemCount(id)
            if have < want * ALERT_RATIO then
                if not alerted[id] then
                    alerted[id] = true
                    ns.Say(string.format(L.REAG_LOW, itemLabel(id), have, want))
                end
            elseif have >= want then
                alerted[id] = nil
            end
        end
    end
end

---------------------------------------------------------------------------
-- Achat chez le marchand
---------------------------------------------------------------------------

-- achat commun (Core.lua : ns.MerchantBuy), meme logique pour Metiers
local function buyMissing()
    if not db.autoBuy then return end
    local t = targets()
    local got, spent = ns.MerchantBuy(function(id)
        local want = t[id]
        if want and want > 0 then return want - ns.ItemCount(id) end
    end)
    local bought = {}
    for _, g in ipairs(got) do
        table.insert(bought, g.n .. " " .. itemLabel(g.id))
        alerted[g.id] = nil
        boughtAt[g.id] = GetTime()
    end
    if #bought > 0 then
        ns.Say(string.format(L.REAG_BOUGHT, table.concat(bought, ", "), ns.FormatMoney(spent)))
    end
end

---------------------------------------------------------------------------
-- Section du panneau Marchand
---------------------------------------------------------------------------

local win, rows = nil, {}   -- win : le panneau qui porte la section (Marchand)
local empty                 -- "ta classe n utilise pas de composants"
local ROW_H = 26
local rowTop = -104     -- la liste vient sous les options et l aide (recalcule a la construction)

local function refresh()
    if not win or not win:IsShown() then return end
    local t = targets()
    local list = itemList()
    for i, id in ipairs(list) do
        local row = rows[i]
        if not row then
            row = CreateFrame("Frame", nil, win)
            row:SetSize(300, ROW_H)
            row:SetPoint("TOPLEFT", 8, rowTop - (i - 1) * ROW_H)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(ROW_H - 4, ROW_H - 4)
            row.icon:SetPoint("LEFT")
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.name:SetPoint("LEFT", ROW_H + 2, 0)
            row.name:SetWidth(170)
            row.name:SetJustifyH("LEFT")
            row.have = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.have:SetPoint("LEFT", ROW_H + 176, 0)
            row.box = ns.UI.EditBox(row, 40, 20)
            row.box:SetJustifyH("CENTER")
            row.box:SetSize(40, 20)
            row.box:SetPoint("RIGHT", -4, 0)
            row.box:SetAutoFocus(false)
            row.box:SetNumeric(true)
            row.box:SetMaxLetters(4)
            row.box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
            row.box:SetScript("OnEditFocusLost", function(self)
                targets()[self.id] = tonumber(self:GetText()) or 0
                alerted[self.id] = nil
                refresh()
            end)
            rows[i] = row
        end
        row.icon:SetTexture(ns.ItemIcon(id))
        row.name:SetText(itemLabel(id))
        local have, want = ns.ItemCount(id), t[id] or 0
        local color = (want > 0 and have < want * ALERT_RATIO) and "|cffff6060" or
                      (want > 0 and have < want) and "|cffffd100" or "|cff80ff80"
        row.have:SetText(color .. have .. "|r /")
        row.box.id = id
        if not row.box:HasFocus() then row.box:SetText(tostring(want)) end
        row:Show()
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    empty:SetShown(#list == 0)
end

-- Section "Reactifs" construite dans le panneau parent (Marchand.lua), a
-- partir de la hauteur y : intertitre, deux cases, aide, puis la liste des
-- composants de la classe. Renvoie le y sous la section et la fonction a
-- appeler a l affichage du panneau (cases relues, liste remplie).
-- La classe ne change pas en cours de session : la hauteur de la liste est
-- connue des la construction.
function ns.ReagentsOptions(parent, y)
    win = parent
    local form = ns.UI.Form(parent, y)
    form:Header(L.MOD_REAG)
    form:Check(L.REAG_OPT_BUY, function() return db.autoBuy end, function(v) db.autoBuy = v end)
    form:Check(L.REAG_OPT_ALERT, function() return db.alert end, function(v) db.alert = v end)
    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, form.y - 6)
    hint:SetWidth(420)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.REAG_HINT)
    -- la liste (maison) vient sous l aide, qui tient sur une ligne
    rowTop = form.y - 26
    empty = parent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, rowTop - 4)
    empty:SetText(L.REAG_NONE)
    local function onShow()
        form:Refresh()
        refresh()
    end
    return rowTop - math.max(1, #itemList()) * ROW_H, onShow
end

---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if ns.ModuleOff("marchand", ev) then return end
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        root.reagents = root.reagents or {}
        db = root.reagents
        db.targets = db.targets or {}
        if db.autoBuy == nil then db.autoBuy = true end
        if db.alert == nil then db.alert = true end
        -- les noms d objets arrivent parfois apres le login
        C_Timer.After(5, checkLow)
    elseif not db then
        return
    elseif event == "BAG_UPDATE_DELAYED" then
        checkLow()
        refresh()
    elseif event == "MERCHANT_SHOW" then
        -- la liste du marchand peut arriver juste apres l ouverture
        C_Timer.After(0.3, function()
            local ok, err = pcall(buyMissing)
            if not ok then ns.Say("|cffff4040" .. tostring(err) .. "|r") end
        end)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        refresh()
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "MERCHANT_SHOW", "GET_ITEM_INFO_RECEIVED" }) do
    pcall(ev.RegisterEvent, ev, e)
end

-- pas de panneau a lui : /corp reactifs ouvre le panneau Marchand
ns.RegisterModule({
    command = "reactifs",
    title = function() return L.MOD_REAG end,
    desc = function() return L.REAG_DESC end,
    Slash = function() if ns.OpenShopOptions then ns.OpenShopOptions() end end,
})
